import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
import '../services/smb_service.dart';
import 'pdf_view_screen.dart';
import '../widgets/qr_scanner_dialog.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path/path.dart' as p;

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final ExcelService _excelService = ExcelService();
  final SmbService _smbService = SmbService();
  
  List<ItemModel> _originalItems = []; 
  List<ItemModel> _displayItems = [];  
  
  String _excelPath = "";
  String _pdfFolderPath = "";
  String _currentFileName = "파일을 선택하세요";
  bool _autoSave = true;
  bool _confirmComplete = false; // ❗ 완료 체크 시 확인창 여부
  bool _isLoading = false;
  bool _isSorted = false;
  bool _isSyncing = false;
  double _scannerZoom = 0.0; // ❗ 스캐너 기본 줌 (0.0=1x, 1.0=3x)

  String _currentSortCol = ""; 
  bool _isAscending = true;   

  final Map<String, Set<String>> _columnFilters = {
    'complete': {},
    'complement': {},
    'process': {},
    'quantity': {},
  };
  String _remarksExcludeQuery = "";
  String _quantitySearchQuery = ""; 
  String _remarksIncludeLogic = "AND"; 
  String _remarksExcludeLogic = "OR";  

  final String _baseDownloadPath = "/storage/emulated/0/Download";
  final FocusNode _dummyFocusNode = FocusNode();

  List<String> _processList = ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅', '버핑', '용접', '도장', '도금', '인쇄', '보류', '사급', '완료'];
  Map<String, int> _processColors = {}; 

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  String _remarksFilterQuery = ""; 

  bool _showUnfinishedOnly = false; 
  Set<String> _selectedSections = {}; 
  bool _isSubheadingViewMode = false; 
  bool _isReorderMode = false; 
  List<ItemModel> _preReorderItems = []; 
  int _noFilterMode = 0; 
  ItemModel? _temporaryVisibleItem; 

  bool _isEditMode = false;
  bool _isSelectionFiltered = false; // ❗ 선택 필터 활성화 여부
  final Set<int> _selectedIndices = {}; 
  bool _isSelecting = false; // ❗ 드래그 선택 중인지 여부
  final GlobalKey _scrollKey = GlobalKey(); // ❗ 스크롤 영역 좌표 계산용
  Timer? _scrollTimer; // ❗ 자동 스크롤 타이머
  final ScrollController _scrollController = ScrollController();
  int? _highlightedRealIndex;
  String? _trackedItemCode; // ❗ 필터가 바뀌어도 기억을 유지할 품목코드
  final double _subheadingHeight = 80.0; // ❗ 60.0 -> 80.0 상향 (3단 고정 레이아웃 대응)
  final double _itemHeight = 45.0;
  double _preSearchScrollOffset = 0.0; 

  @override
  void initState() {
    super.initState();
    _initApp();
    _searchFocusNode.addListener(() => setState(() {})); 
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _dummyFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearHighlight() {
    if (_highlightedRealIndex != null) {
      setState(() => _highlightedRealIndex = null);
    }
  }

  void _scrollToItem(String itemCode) {
    int targetIndex = -1;
    double offset = 0.0;
    int? foundRealIndex;

    for (int i = 0; i < _displayItems.length; i++) {
      final item = _displayItems[i];
      if (!item.isSubheading && item.itemCode == itemCode) {
        targetIndex = i;
        foundRealIndex = item.realIndex;
        break;
      }
      offset += item.isSubheading ? _subheadingHeight : _itemHeight;
    }

    if (targetIndex != -1 && foundRealIndex != null) {
      setState(() => _highlightedRealIndex = null);

      final screenHeight = MediaQuery.of(context).size.height;
      final appBarHeight = kToolbarHeight + 50; 
      double targetOffset = offset - (screenHeight / 2) + (appBarHeight / 2) + (_itemHeight / 2);

      if (targetOffset < 0) targetOffset = 0;
      if (_scrollController.hasClients && targetOffset > _scrollController.position.maxScrollExtent) {
        targetOffset = _scrollController.position.maxScrollExtent;
      }

      if (_scrollController.hasClients) {
        _scrollController.jumpTo(targetOffset);
      }
      if (mounted) {
        setState(() {
          _highlightedRealIndex = foundRealIndex;
        });
      }
    }
  }

  Future<void> _initApp() async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
    await _loadSettings();
    await _ensureBaseDirectory();
  }

  Future<void> _ensureBaseDirectory() async {
    final baseDir = Directory("$_baseDownloadPath/CheckSheet");
    if (!baseDir.existsSync()) baseDir.createSync(recursive: true);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _excelPath = prefs.getString('excelPath') ?? "";
      _pdfFolderPath = prefs.getString('pdfFolderPath') ?? "";
      _autoSave = prefs.getBool('autoSave') ?? true;
      _confirmComplete = prefs.getBool('confirmComplete') ?? false;
      _scannerZoom = prefs.getDouble('scannerZoom') ?? 0.0;
      _smbService.setConfig(
        prefs.getString('smbIp') ?? "",
        prefs.getString('smbUser') ?? "",
        prefs.getString('smbPass') ?? "",
      );
      _processList = prefs.getStringList('processList') ?? ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅', '버핑', '용접', '도장', '도금', '인쇄', '보류', '사급', '완료'];
      
      String? colorsJson = prefs.getString('processColors');
      if (colorsJson != null) {
        try {
          Map<String, dynamic> decoded = jsonDecode(colorsJson);
          _processColors = decoded.map((key, value) => MapEntry(key, value as int));
        } catch (_) { _processColors = {}; }
      } else { _processColors = {}; }

      // ❗ 필터 상태 복구
      _searchQuery = prefs.getString('filter_searchQuery') ?? "";
      _searchController.text = _searchQuery;
      _currentSortCol = prefs.getString('filter_currentSortCol') ?? "";
      _isAscending = prefs.getBool('filter_isAscending') ?? true;
      _isSorted = prefs.getBool('filter_isSorted') ?? false;
      _showUnfinishedOnly = prefs.getBool('filter_showUnfinishedOnly') ?? false;
      _isSubheadingViewMode = prefs.getBool('filter_isSubheadingViewMode') ?? false;
      _noFilterMode = prefs.getInt('filter_noFilterMode') ?? 0;
      _remarksFilterQuery = prefs.getString('filter_remarksFilterQuery') ?? "";
      _remarksExcludeQuery = prefs.getString('filter_remarksExcludeQuery') ?? "";
      _remarksIncludeLogic = prefs.getString('filter_remarksIncludeLogic') ?? "AND";
      _remarksExcludeLogic = prefs.getString('filter_remarksExcludeLogic') ?? "OR";
      _quantitySearchQuery = prefs.getString('filter_quantitySearchQuery') ?? "";

      String? colFilterJson = prefs.getString('filter_columnFilters');
      if (colFilterJson != null) {
        try {
          Map<String, dynamic> decoded = jsonDecode(colFilterJson);
          decoded.forEach((key, value) {
            if (_columnFilters.containsKey(key)) {
              _columnFilters[key] = (value as List).map((e) => e.toString()).toSet();
            }
          });
        } catch (_) {}
      }

      List<String>? selSections = prefs.getStringList('filter_selectedSections');
      if (selSections != null) _selectedSections = selSections.toSet();
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) _loadExcelData(_excelPath, keepFilters: true);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
    await prefs.setBool('confirmComplete', _confirmComplete);
    await prefs.setDouble('scannerZoom', _scannerZoom);
    await prefs.setStringList('processList', _processList);
    await prefs.setString('processColors', jsonEncode(_processColors));

    // ❗ 필터 상태 저장
    await prefs.setString('filter_searchQuery', _searchQuery);
    await prefs.setString('filter_currentSortCol', _currentSortCol);
    await prefs.setBool('filter_isAscending', _isAscending);
    await prefs.setBool('filter_isSorted', _isSorted);
    await prefs.setBool('filter_showUnfinishedOnly', _showUnfinishedOnly);
    await prefs.setBool('filter_isSubheadingViewMode', _isSubheadingViewMode);
    await prefs.setInt('filter_noFilterMode', _noFilterMode);
    await prefs.setString('filter_remarksFilterQuery', _remarksFilterQuery);
    await prefs.setString('filter_remarksExcludeQuery', _remarksExcludeQuery);
    await prefs.setString('filter_remarksIncludeLogic', _remarksIncludeLogic);
    await prefs.setString('filter_remarksExcludeLogic', _remarksExcludeLogic);
    await prefs.setString('filter_quantitySearchQuery', _quantitySearchQuery);

    Map<String, List<String>> colFilterMap = _columnFilters.map((k, v) => MapEntry(k, v.toList()));
    await prefs.setString('filter_columnFilters', jsonEncode(colFilterMap));
    await prefs.setStringList('filter_selectedSections', _selectedSections.toList());
  }

  Future<void> _loadExcelData(String path, {bool keepFilters = false}) async {
    setState(() => _isLoading = true);
    try {
      final items = await _excelService.loadExcel(path);
      setState(() {
        _originalItems = items;
        _displayItems = List.from(items);
        _currentFileName = p.basename(path);
        _excelPath = path;

        if (!keepFilters) {
          _isSorted = false;
          _currentSortCol = "";
          _searchController.clear();
          _searchQuery = "";
          _showUnfinishedOnly = false;
          _selectedSections.clear();
          _noFilterMode = 0;
          _remarksFilterQuery = "";
          _remarksExcludeQuery = "";
          _remarksIncludeLogic = "AND";
          _remarksExcludeLogic = "OR";
          _quantitySearchQuery = "";
          _isSubheadingViewMode = false;
          _columnFilters.forEach((key, value) => value.clear());
        }
        
        _isEditMode = false;
        _isReorderMode = false;
        _selectedIndices.clear();
        _temporaryVisibleItem = null;
      });

      if (keepFilters) {
        _applyFilterAndSort();
      } else {
        _saveSettings(); // 초기화된 상태 저장
      }
      _saveLastDir(path);
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveLastDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastDir', p.dirname(path));
  }

  void _forgetFocus() {
    if (!mounted) return;
    _searchFocusNode.unfocus();
    FocusScope.of(context).requestFocus(_dummyFocusNode);
  }

  void _applyFilterAndSort() {
    List<ItemModel> results = [];
    
    if (_isSubheadingViewMode) {
      results = _originalItems.where((i) => i.isSubheading).toList();
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        results = results.where((i) => i.itemCode.toLowerCase().contains(query)).toList();
      }
      if (results.isEmpty) {
        results.add(ItemModel(realIndex: -1, no: "", displayNo: "", itemCode: "부분제목 없음", quantity: "", isSubheading: true));
      }
      setState(() { _displayItems = results; });
      _saveSettings(); // ❗ 상태 변경 저장
      return;
    }

    String? currentHeader;
    Map<String, List<ItemModel>> sectionMap = {};
    List<String> headerOrder = [];

    for (var item in _originalItems) {
      if (item.isSubheading) {
        currentHeader = item.itemCode;
        sectionMap[currentHeader] = [];
        headerOrder.add(currentHeader);
      } else {
        if (currentHeader != null) sectionMap[currentHeader]!.add(item);
        else {
          if (!sectionMap.containsKey("ROOT")) { sectionMap["ROOT"] = []; headerOrder.insert(0, "ROOT"); }
          sectionMap["ROOT"]!.add(item);
        }
      }
    }

    for (var header in headerOrder) {
      if (_selectedSections.isNotEmpty && !_selectedSections.contains(header)) continue;
      List<ItemModel> sectionItems = List.from(sectionMap[header]!);

      if (_searchQuery.isNotEmpty) {
        final queryParts = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.itemCode.toLowerCase();
          return queryParts.every((part) => targetStr.contains(part));
        }).toList();
      }

      _columnFilters.forEach((col, selectedValues) {
        if (selectedValues.isNotEmpty || (col == 'quantity' && _quantitySearchQuery.isNotEmpty)) {
          sectionItems = sectionItems.where((item) {
            String val = "";
            if (col == 'complete') val = item.complete ? "완료" : "미완료";
            else if (col == 'complement') val = item.complement.isEmpty ? "(빈칸)" : item.complement;
            else if (col == 'process') val = item.process.isEmpty ? "(빈칸)" : item.process;
            else if (col == 'quantity') val = item.quantity;
            bool isSelected = selectedValues.contains(val);
            if (col == 'quantity' && _quantitySearchQuery.isNotEmpty) {
              final queryParts = _quantitySearchQuery.split(' ').where((p) => p.isNotEmpty);
              bool isMatched = queryParts.any((p) => val == p);
              return isSelected || isMatched;
            }
            return isSelected;
          }).toList();
        }
      });

      if (_remarksFilterQuery.isNotEmpty) {
        final queryParts = _remarksFilterQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.remarks.toLowerCase();
          return _remarksIncludeLogic == "AND" ? queryParts.every((part) => targetStr.contains(part)) : queryParts.any((part) => targetStr.contains(part));
        }).toList();
      }

      if (_remarksExcludeQuery.isNotEmpty) {
        final excludeParts = _remarksExcludeQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.remarks.toLowerCase();
          bool shouldExclude = _remarksExcludeLogic == "AND" ? excludeParts.every((part) => targetStr.contains(part)) : excludeParts.any((part) => targetStr.contains(part));
          return !shouldExclude;
        }).toList();
      }

      if (_showUnfinishedOnly) {
        sectionItems = sectionItems.where((item) => !item.complete).toList();
      }

      if (_isSelectionFiltered) {
        sectionItems = sectionItems.where((item) => _selectedIndices.contains(item.realIndex)).toList();
      }

      if (_noFilterMode == 1) {
        sectionItems = sectionItems.where((item) => item.no.isNotEmpty).toList();
      } else if (_noFilterMode == 2) {
        sectionItems = sectionItems.where((item) {
          if (item.displayNo.contains('-')) return true;
          if (item.no.isNotEmpty) {
            bool hasSub = _originalItems.any((other) => !other.isSubheading && other.displayNo.startsWith("${item.no}-"));
            return !hasSub;
          }
          return false;
        }).toList();
      }

      if (_temporaryVisibleItem != null && !_temporaryVisibleItem!.isSubheading) {
        String targetHeader = "ROOT";
        String? tempCurrent;
        for (var i in _originalItems) {
          if (i.isSubheading) tempCurrent = i.itemCode;
          if (i == _temporaryVisibleItem) { targetHeader = tempCurrent ?? "ROOT"; break; }
        }
        if (header == targetHeader) {
          bool alreadyIn = sectionItems.any((it) => it.realIndex == _temporaryVisibleItem!.realIndex);
          if (!alreadyIn) {
            sectionItems.add(_temporaryVisibleItem!);
            sectionItems.sort((a, b) => a.realIndex.compareTo(b.realIndex));
          }
        }
      }

      if (sectionItems.isNotEmpty) {
        if (header != "ROOT") { results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header)); }
        results.addAll(sectionItems);
      } else if (_selectedSections.contains(header)) {
        results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header));
      }
    }

    if (_isSorted && _currentSortCol.isNotEmpty) {
      results = results.where((i) => !i.isSubheading).toList();
      results.sort((a, b) {
        int cmp = 0;
        switch (_currentSortCol) {
          case 'no': cmp = _compareDisplayNo(a.displayNo, b.displayNo); break;
          case 'itemCode': cmp = a.itemCode.compareTo(b.itemCode); break;
          case 'quantity': cmp = (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0); break;
          case 'complete': cmp = (a.complete ? 1 : 0).compareTo(b.complete ? 1 : 0); break;
          case 'complement': cmp = a.complement.compareTo(b.complement); break;
          case 'process': cmp = a.process.compareTo(b.process); break;
          case 'remarks': cmp = a.remarks.compareTo(b.remarks); break;
        }
        return _isAscending ? cmp : -cmp;
      });
    }

    setState(() { _displayItems = results; });

    // ❗ 필터 변경 후 추적 중인 항목이 리스트에 있다면 자동 포커스 복원
    if (_trackedItemCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _trackedItemCode != null) {
          final bool exists = _displayItems.any((i) => !i.isSubheading && i.itemCode == _trackedItemCode);
          if (exists) {
            _scrollToItem(_trackedItemCode!);
          }
        }
      });
    }
    _saveSettings(); // ❗ 상태 변경 저장
  }

  void _resetSort() {
    _forgetFocus();
    setState(() {
      _isSorted = false; _currentSortCol = ""; _remarksFilterQuery = ""; _remarksExcludeQuery = ""; _quantitySearchQuery = "";
      _remarksIncludeLogic = "AND"; _remarksExcludeLogic = "OR"; _noFilterMode = 0; _temporaryVisibleItem = null;
      _columnFilters.forEach((key, value) => value.clear());
      _showUnfinishedOnly = false; _selectedSections.clear(); _isSubheadingViewMode = false;
      _isReorderMode = false;
      _searchQuery = "";
      _searchController.clear();
      _isSelectionFiltered = false;
      _selectedIndices.clear();
    });
    _applyFilterAndSort();
  }

  void _sortBy(String col) {
    _forgetFocus();
    if (col == 'itemCode') {
      setState(() {
        if (_currentSortCol == col) {
          if (_isAscending) {
            _isAscending = false; 
          } else {
            _isSorted = false; 
            _currentSortCol = "";
          }
        } else {
          _currentSortCol = col; 
          _isAscending = true;
          _isSorted = true;
        }
      });
      _applyFilterAndSort();
      return;
    }
    if (col == 'no') {
      setState(() => _noFilterMode = (_noFilterMode + 1) % 3);
      _applyFilterAndSort();
      return;
    }
    _showFilterDialog(col);
  }

  Set<String> _getValidOptionsForColumn(String col) {
    Set<String> validSet = {};
    for (var item in _originalItems) {
      if (item.isSubheading) continue;
      if (_selectedSections.isNotEmpty) {
        String? targetHeader;
        for(var i in _originalItems) {
          if(i.isSubheading) targetHeader = i.itemCode;
          if(i == item) break;
        }
        if (!_selectedSections.contains(targetHeader)) continue;
      }
      if (_searchQuery.isNotEmpty) {
        final queryParts = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        final targetStr = item.itemCode.toLowerCase();
        if (!queryParts.every((part) => targetStr.contains(part))) continue;
      }
      if (_showUnfinishedOnly && item.complete) continue;
      if (_noFilterMode == 1 && item.no.isEmpty) continue;
      if (_noFilterMode == 2) {
        if (!item.displayNo.contains('-')) {
          if (item.no.isNotEmpty) {
            bool hasSub = _originalItems.any((other) => !other.isSubheading && other.displayNo.startsWith("${item.no}-"));
            if (hasSub) continue;
          } else continue;
        }
      }
      if (_remarksFilterQuery.isNotEmpty && col != 'remarks') {
        final queryParts = _remarksFilterQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        final targetStr = item.remarks.toLowerCase();
        bool match = _remarksIncludeLogic == "AND" ? queryParts.every((part) => targetStr.contains(part)) : queryParts.any((part) => targetStr.contains(part));
        if (!match) continue;
      }
      if (_remarksExcludeQuery.isNotEmpty && col != 'remarks') {
        final excludeParts = _remarksExcludeQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        final targetStr = item.remarks.toLowerCase();
        bool shouldExclude = _remarksExcludeLogic == "AND" ? excludeParts.every((part) => targetStr.contains(part)) : excludeParts.any((part) => targetStr.contains(part));
        if (shouldExclude) continue;
      }
      bool passOtherFilters = true;
      _columnFilters.forEach((c, selectedValues) {
        if (c == col) return; 
        if (selectedValues.isNotEmpty || (c == 'quantity' && _quantitySearchQuery.isNotEmpty)) {
          String val = "";
          if (c == 'complete') val = item.complete ? "완료" : "미완료";
          else if (c == 'complement') val = item.complement.isEmpty ? "(빈칸)" : item.complement;
          else if (c == 'process') val = item.process.isEmpty ? "(빈칸)" : item.process;
          else if (c == 'quantity') val = item.quantity;
          bool isSelected = selectedValues.contains(val);
          if (c == 'quantity' && _quantitySearchQuery.isNotEmpty) {
            final qParts = _quantitySearchQuery.split(' ').where((p) => p.isNotEmpty);
            bool qMatch = qParts.any((p) => val == p);
            isSelected = isSelected || qMatch;
          }
          if (!isSelected) passOtherFilters = false;
        }
      });
      if (!passOtherFilters) continue;
      String val = "";
      if (col == 'complete') val = item.complete ? "완료" : "미완료";
      else if (col == 'complement') val = item.complement.isEmpty ? "(빈칸)" : item.complement;
      else if (col == 'process') val = item.process.isEmpty ? "(빈칸)" : item.process;
      else if (col == 'quantity') val = item.quantity;
      validSet.add(val);
    }
    return validSet;
  }

  void _showFilterDialog(String col) {
    List<String> options = [];
    String titleText = "";
    Set<String> validOptions = _getValidOptionsForColumn(col);
    if (col == 'complete') { options = ["완료", "미완료"]; titleText = "완료 설정"; }
    else if (col == 'complement') { options = ["부족", "재작업", "(빈칸)"]; titleText = "보완 설정"; }
    else if (col == 'process') { 
      // ❗ 공정 필터 순서: (빈칸) -> 설정 > 공정관리 순서 -> 미등록 공정(알파벳순) -> 완료(항상 마지막)
      List<String> finalOrder = [];
      if (validOptions.contains("(빈칸)")) finalOrder.add("(빈칸)");
      
      List<String> baseOrder = List.from(_processList);
      baseOrder.remove("완료");
      
      for (var p in baseOrder) {
        if (validOptions.contains(p)) finalOrder.add(p);
      }
      
      // 설정에는 없지만 데이터에 존재하는 공정들 추가 (누락 방지)
      List<String> extraOptions = validOptions.where((opt) => 
        opt != "(빈칸)" && opt != "완료" && !_processList.contains(opt)
      ).toList();
      extraOptions.sort();
      finalOrder.addAll(extraOptions);
      
      if (validOptions.contains("완료")) finalOrder.add("완료");
      
      options = finalOrder;
      titleText = "공정 설정"; 
    }
    else if (col == 'quantity') { options = validOptions.toList(); options.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0)); titleText = "수량 설정"; }
    else if (col == 'remarks') { titleText = "비고 설정"; }
    
    bool localIsSorted = _isSorted && _currentSortCol == col;
    bool localIsAscending = _isAscending;
    Set<String> localFilters = Set.from(_columnFilters[col] ?? {});
    final includeController = TextEditingController(text: _remarksFilterQuery);
    final excludeController = TextEditingController(text: _remarksExcludeQuery);
    final quantityController = TextEditingController(text: _quantitySearchQuery);
    String localIncludeLogic = _remarksIncludeLogic;
    String localExcludeLogic = _remarksExcludeLogic;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setModalState) => AlertDialog(
      title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("정렬", style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<bool?>(title: const Text("오름차순"), value: true, groupValue: localIsSorted ? localIsAscending : null, onChanged: (val) => setModalState(() { localIsSorted = true; localIsAscending = true; }), contentPadding: EdgeInsets.zero, dense: true),
        RadioListTile<bool?>(title: const Text("내림차순"), value: false, groupValue: localIsSorted ? localIsAscending : null, onChanged: (val) => setModalState(() { localIsSorted = true; localIsAscending = false; }), contentPadding: EdgeInsets.zero, dense: true),
        RadioListTile<bool?>(title: const Text("정렬 안함"), value: null, groupValue: localIsSorted ? localIsAscending : null, onChanged: (val) => setModalState(() { localIsSorted = false; }), contentPadding: EdgeInsets.zero, dense: true),
        if (col != 'itemCode') ...[
          const Divider(),
          if (col == 'remarks') ...[
            const Text("포함 필터", style: TextStyle(fontWeight: FontWeight.bold)), 
            TextField(
              controller: includeController,
              decoration: InputDecoration(
                isDense: true,
                suffixIcon: includeController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setModalState(() => includeController.clear())) 
                  : null
              ),
              onChanged: (v) => setModalState(() {}),
            ),
            Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)), const Text("OR")]),
            const SizedBox(height: 10), const Text("제외 필터", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)), 
            TextField(
              controller: excludeController,
              decoration: InputDecoration(
                isDense: true,
                suffixIcon: excludeController.text.isNotEmpty 
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => setModalState(() => excludeController.clear())) 
                  : null
              ),
              onChanged: (v) => setModalState(() {}),
            ),
            Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)), const Text("OR")]),
          ] else ...[
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => setModalState(() => localFilters.addAll(options.where((o) => col == 'process' || col == 'quantity' || validOptions.contains(o)))), child: const Text("전체 선택", style: TextStyle(fontSize: 12)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => setModalState(() => localFilters.clear()), child: const Text("전체 해제", style: TextStyle(fontSize: 12))))]),
            const SizedBox(height: 10), if (col == 'quantity') ...[const Text("수량 직접 입력", style: TextStyle(fontWeight: FontWeight.bold)), TextField(controller: quantityController, keyboardType: TextInputType.number), const SizedBox(height: 15)],
            const Text("항목 선택", style: TextStyle(fontWeight: FontWeight.bold)), _buildFilterGrid(options, localFilters, col, setModalState, validOptions: (col == 'complete' || col == 'complement') ? validOptions : null),
          ],
        ],
        if (['complete', 'process', 'complement'].contains(col)) ...[
          const Divider(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _resetFilteredItemsColumn(col);
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text("현재 리스트 항목 리셋", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[800], side: BorderSide(color: Colors.red[200]!)),
            ),
          )
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () { setState(() { _isSorted = localIsSorted; if (localIsSorted) { _currentSortCol = col; _isAscending = localIsAscending; } else if (_currentSortCol == col) _currentSortCol = ""; if (_columnFilters.containsKey(col)) _columnFilters[col] = localFilters; if (col == 'remarks') { _remarksFilterQuery = includeController.text; _remarksExcludeQuery = excludeController.text; _remarksIncludeLogic = localIncludeLogic; _remarksExcludeLogic = localExcludeLogic; } if (col == 'quantity') _quantitySearchQuery = quantityController.text; }); _applyFilterAndSort(); Navigator.pop(ctx); }, child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold)))],
    )));
  }

  Widget _buildFilterGrid(List<String> options, Set<String> localFilters, String col, StateSetter setModalState, {Set<String>? validOptions}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, constraints) {
      double itemWidth = col == 'complete' ? constraints.maxWidth / 2 : constraints.maxWidth / 3;
      return Wrap(children: options.map((opt) {
        bool isValid = validOptions == null || validOptions.contains(opt);
        bool isSel = localFilters.contains(opt);
        return SizedBox(width: itemWidth, child: InkWell(
          onTap: !isValid ? null : () => setModalState(() { if (col == 'complete') { if (isSel) localFilters.clear(); else { localFilters.clear(); localFilters.add(opt); } } else { if (isSel) localFilters.remove(opt); else localFilters.add(opt); } }),
          child: Opacity(opacity: isValid ? 1.0 : 0.3, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: isSel, onChanged: !isValid ? null : (v) => setModalState(() { if (col == 'complete') { if (isSel && !v!) localFilters.clear(); else { localFilters.clear(); if (v!) localFilters.add(opt); } } else { if (v!) localFilters.add(opt); else localFilters.remove(opt); } }), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), 
            if (col == 'process' && opt != "(빈칸)") 
              Container(
                width: 4, 
                height: 16, 
                margin: const EdgeInsets.only(right: 4), 
                decoration: BoxDecoration(
                  color: (() {
                    int? colorVal = _processColors[opt];
                    if (colorVal != null) return Color(colorVal);
                    if (opt == "완료") return Colors.purple;
                    if (opt == "보류") return Colors.red;
                    if (["용접", "도장", "도금", "인쇄"].contains(opt)) return Colors.orange;
                    return Colors.blueGrey;
                  })(),
                  borderRadius: BorderRadius.circular(2)
                )
              ),
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(opt, style: TextStyle(
              fontSize: 12, 
              fontWeight: col == 'process' ? FontWeight.bold : FontWeight.normal,
              color: isDark ? Colors.white : Colors.black87,
            )))),
          ])),
        ));
      }).toList());
    });
  }

  Future<void> _pickSource(String mode) async {
    _forgetFocus();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.phone_android), title: const Text("내 휴대폰"), onTap: () { Navigator.pop(ctx); _openCustomPicker(mode); }),
            ListTile(leading: const Icon(Icons.computer), title: const Text("PC 공유폴더 (SMB)"), onTap: () { Navigator.pop(ctx); _openSmbShares(mode); }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _createNewFile(String currentPath) {
    // ❗ 기본 파일명 생성 (체크시트_YYYYMMDD)
    final now = DateTime.now();
    final dateStr = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}";
    String baseName = "체크시트_$dateStr";
    String finalName = baseName;
    
    // ❗ 중복 체크 및 자동 넘버링
    int counter = 1;
    while (File("$currentPath/$finalName.xlsx").existsSync()) {
      finalName = "$baseName($counter)";
      counter++;
    }

    final nameController = TextEditingController(text: finalName);
    // ❗ 텍스트 전체 선택 상태로 시작
    nameController.selection = TextSelection(baseOffset: 0, extentOffset: nameController.text.length);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("새 엑셀 파일 생성"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: "파일명 입력", suffixText: ".xlsx"),
          autofocus: true, // ❗ 키보드 자동 팝업
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () async {
              String name = nameController.text.trim();
              if (name.isEmpty) return;
              if (!name.endsWith(".xlsx")) name += ".xlsx";
              
              String newPath = "$currentPath/$name";
              if (File(newPath).existsSync() && name != "$finalName.xlsx") {
                _showError("생성 실패", "이미 동일한 이름의 파일이 존재합니다.");
                return;
              }
              
              bool ok = await _excelService.createEmptyExcel(newPath);
              if (ok) {
                Navigator.pop(ctx); // 생성창 닫기
                if (mounted) Navigator.pop(context); // 탐색기 닫기 (context 사용)
                _loadExcelData(newPath);
                _showSnackBar("새 파일이 생성되었습니다.");
              } else {
                _showError("오류", "파일 생성에 실패했습니다.");
              }
            },
            child: const Text("생성", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openSettings() async {
    _forgetFocus(); final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp')); final userController = TextEditingController(text: prefs.getString('smbUser')); final passController = TextEditingController(text: prefs.getString('smbPass'));
    final newProcessController = TextEditingController(); bool obscurePass = true; 
    final List<Color> palette = [Colors.blueGrey, Colors.blue, Colors.indigo, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink, Colors.purple, Colors.deepPurple];
    showDialog(context: context, builder: (ctx) => DefaultTabController(length: 2, child: StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const TabBar(labelColor: Colors.blue, unselectedLabelColor: Colors.grey, tabs: [Tab(icon: Icon(Icons.dns), text: "연결 설정"), Tab(icon: Icon(Icons.settings_suggest), text: "공정 관리")]),
      content: SizedBox(width: double.maxFinite, height: 450, child: TabBarView(children: [
        SingleChildScrollView(child: Column(children: [
          const SizedBox(height: 20), 
          TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소", border: OutlineInputBorder())), 
          const SizedBox(height: 10), 
          TextField(controller: userController, decoration: const InputDecoration(labelText: "ID", border: OutlineInputBorder())), 
          const SizedBox(height: 10), 
          TextField(controller: passController, obscureText: obscurePass, decoration: InputDecoration(labelText: "PW", border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscurePass ? Icons.visibility : Icons.visibility_off), onPressed: () => setDialogState(() => obscurePass = !obscurePass)))), 
          const SizedBox(height: 20),
          // ❗ 완료 체크 확인 여부 설정 추가
          CheckboxListTile(
            title: const Text("완료 체크 시 확인창 표시"),
            subtitle: const Text("체크 표시 전 한 번 더 물어봅니다."),
            value: _confirmComplete,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => setDialogState(() => _confirmComplete = v!),
          ),
          const SizedBox(height: 10),
          // ❗ 스캐너 줌 설정 UI 추가
          const Align(alignment: Alignment.centerLeft, child: Text("스캐너 기본 배율 (줌)", style: TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueGrey.withOpacity(0.2))),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.zoom_in, size: 20, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(child: Slider(
                  value: _scannerZoom, min: 0.0, max: 1.0, 
                  onChanged: (v) => setDialogState(() => _scannerZoom = v),
                )),
                Text(_scannerZoom.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ]),
              const SizedBox(height: 5),
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _zoomQuickBtnDialog("0.0", 0.0, setDialogState),
                      _zoomQuickBtnDialog("0.1", 0.1, setDialogState),
                      _zoomQuickBtnDialog("0.2", 0.2, setDialogState),
                      _zoomQuickBtnDialog("0.3", 0.3, setDialogState),
                      _zoomQuickBtnDialog("0.4", 0.4, setDialogState),
                      _zoomQuickBtnDialog("0.5", 0.5, setDialogState),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _zoomQuickBtnDialog("0.6", 0.6, setDialogState),
                      _zoomQuickBtnDialog("0.7", 0.7, setDialogState),
                      _zoomQuickBtnDialog("0.8", 0.8, setDialogState),
                      _zoomQuickBtnDialog("0.9", 0.9, setDialogState),
                      _zoomQuickBtnDialog("1.0", 1.0, setDialogState),
                      const SizedBox(width: 40),
                    ],
                  ),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(onPressed: () async { String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text); if (err == null) { List<String> shares = await _smbService.listShares(); _showError("성공", "✅ 접속 성공!\n\n[공유 목록]\n${shares.join('\n')}"); } else _showError("오류", "접속 실패: $err"); }, icon: const Icon(Icons.check_circle_outline), label: const Text("접속 테스트"))
        ])),
        Column(children: [
          Expanded(child: ReorderableListView(
            onReorder: (o, n) { 
              setDialogState(() { 
                if (n > o) n -= 1; 
                // ❗ '완료'는 위치 고정 (이동 및 완료 위로 삽입 제한)
                if (_processList[o] == "완료" || n >= _processList.length) return;
                final String item = _processList.removeAt(o); 
                _processList.insert(n, item); 
              }); 
            }, 
            buildDefaultDragHandles: false, // ❗ 드래그 핸들 커스텀 제어
            children: [
              for (int i = 0; i < _processList.length; i++) 
                ListTile(
                  key: ValueKey(_processList[i] + i.toString()), 
                  dense: true, visualDensity: VisualDensity.compact, 
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4), 
                  leading: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: Icon(Icons.remove_circle_outline, color: _processList[i] == "완료" ? Colors.grey : Colors.red, size: 20), 
                        onPressed: _processList[i] == "완료" ? null : () { 
                          showDialog(context: context, builder: (confirmCtx) => AlertDialog(title: const Text("공정 삭제"), content: Text("'${_processList[i]}' 공정을 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text("취소")), TextButton(onPressed: () { setDialogState(() { _processList.removeAt(i); }); Navigator.pop(confirmCtx); }, child: const Text("삭제", style: TextStyle(color: Colors.red)))])); 
                        }
                      ),
                      (() {
                        Color dotColor;
                        if (_processColors[_processList[i]] != null) dotColor = Color(_processColors[_processList[i]]!);
                        else { String p = _processList[i]; if (p == "완료") dotColor = Colors.purple; else if (p == "보류") dotColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) dotColor = Colors.orange; else dotColor = Colors.blueGrey; }
                        return GestureDetector(onTap: () { showDialog(context: context, builder: (pCtx) => AlertDialog(title: Text("${_processList[i]} 색상 선택"), content: Wrap(spacing: 8, runSpacing: 8, children: palette.map((c) => GestureDetector(onTap: () { setDialogState(() => _processColors[_processList[i]] = c.value); Navigator.pop(pCtx); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))).toList()))); }, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)));
                      })(),
                    ]), 
                  title: Text(_processList[i], style: TextStyle(fontSize: 13, color: _processList[i] == "완료" ? Colors.purple : null, fontWeight: _processList[i] == "완료" ? FontWeight.bold : null)), 
                  trailing: _processList[i] == "완료" ? const SizedBox(width: 24) : ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, size: 20)),
                )
            ])),
          const Divider(), 
          Row(children: [
            Expanded(child: TextField(controller: newProcessController, decoration: const InputDecoration(hintText: "공정명 추가", isDense: true))), 
            IconButton(icon: const Icon(Icons.add_box, color: Colors.green, size: 30), onPressed: () { 
              if (newProcessController.text.isNotEmpty) {
                setDialogState(() { 
                  // ❗ 신규 공정은 항상 '완료' 바로 위에 추가
                  int insertIdx = _processList.indexOf("완료");
                  if (insertIdx != -1) _processList.insert(insertIdx, newProcessController.text);
                  else _processList.add(newProcessController.text);
                  newProcessController.clear(); 
                });
              }
            }), 
            IconButton(icon: const Icon(Icons.color_lens_outlined, color: Colors.orange, size: 30), onPressed: () { setDialogState(() => _processColors.clear()); })
          ]),
        ]),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () async { await prefs.setString('smbIp', ipController.text); await prefs.setString('smbUser', userController.text); await prefs.setString('smbPass', passController.text); await prefs.setStringList('processList', _processList); await prefs.setString('processColors', jsonEncode(_processColors)); _smbService.setConfig(ipController.text, userController.text, passController.text); setState(() {}); Navigator.pop(ctx); }, child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)))],
    ))));
  }

  void _openSmbShares(String mode) async {
    _forgetFocus(); setState(() => _isLoading = true);
    try { List<String> shares = await _smbService.listShares(); setState(() => _isLoading = false); if (!mounted) return; if (shares.isNotEmpty && shares[0].startsWith("ERROR:")) { _showError("탐색 실패", shares[0].replaceFirst("ERROR:", "").trim()); return; } showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("공유폴더 선택"), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: shares.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.folder_shared), title: Text(shares[i]), onTap: () { Navigator.pop(ctx); _showSmbFiles(shares[i], "", mode); })))) ); } catch (e) { setState(() => _isLoading = false); _showError("치명적 오류", "$e"); }
  }

  void _showSmbFiles(String share, String path, String mode) async {
    setState(() => _isLoading = true); List<Map<String, dynamic>> files = await _smbService.listFiles(share, path); setState(() => _isLoading = false); if (!mounted) return; List<Map<String, dynamic>> filteredFiles = files.where((f) { if (f['isDirectory'] as bool) return true; String name = (f['name'] as String).toLowerCase(); return mode == 'file' ? (name.endsWith('.xlsx') || name.endsWith('.xls')) : name.endsWith('.pdf'); }).toList();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("$share/$path"), content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [if (path != "") ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showSmbFiles(share, p.dirname(path) == "." ? "" : p.dirname(path), mode); }), Expanded(child: ListView.builder(itemCount: filteredFiles.length, itemBuilder: (c, i) { final f = filteredFiles[i]; bool isDir = f['isDirectory'] as bool; String name = f['name'] as String; return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description), title: Text(name), onTap: () { if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, "${path == "" ? "" : "$path/"}$name"); } else if (mode == 'file') { Navigator.pop(ctx); _downloadAndLoad(share, "${path == "" ? "" : "$path/"}$name"); } }); }))])), actions: [if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = "smb://$share/$path"); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))]));
  }

  Future<void> _downloadAndLoad(String share, String remotePath) async { setState(() => _isLoading = true); String localPath = "$_baseDownloadPath/CheckSheet/${p.basename(remotePath)}"; File? file = await _smbService.downloadFile(share, remotePath, localPath); setState(() => _isLoading = false); if (file != null) _loadExcelData(file.path); else _showError("오류", "다운로드 실패"); }

  Future<void> _syncAllPdfs() async {
    _forgetFocus(); if (_originalItems.isEmpty) return; List<ItemModel> targets = _originalItems.where((i) => !i.isSubheading).toList(); setState(() => _isSyncing = true);
    try { String shareWithRest = _pdfFolderPath.replaceFirst("smb://", ""); if (shareWithRest.endsWith("/")) shareWithRest = shareWithRest.substring(0, shareWithRest.length - 1); int firstSlash = shareWithRest.indexOf("/"); String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest; String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : ""; const int batchSize = 5; for (int i = 0; i < targets.length; i += batchSize) { final chunk = targets.skip(i).take(batchSize); await Future.wait(chunk.map((item) { String cleanCode = item.itemCode.trim(); String remoteFilePath = folderPath.isEmpty ? "$cleanCode.pdf" : "$folderPath/$cleanCode.pdf"; String localFilePath = "$_baseDownloadPath/CheckSheet/$cleanCode.pdf"; return _smbService.downloadFile(share, remoteFilePath, localFilePath); })); } _showSnackBar("✅ ${targets.length}개 동기화 완료!"); } catch (e) { debugPrint("Sync Error: $e"); } finally { setState(() => _isSyncing = false); }
  }

  Future<void> _openCustomPicker(String mode) async { _forgetFocus(); final prefs = await SharedPreferences.getInstance(); String startPath = prefs.getString('lastDir') ?? "$_baseDownloadPath/CheckSheet"; if (!Directory(startPath).existsSync()) startPath = _baseDownloadPath; _showFileBrowser(mode, startPath); }

  void _showFileBrowser(String mode, String initialPath) {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setModalState) { final dir = Directory(initialPath); List<FileSystemEntity> entities = []; try { entities = dir.listSync().where((e) { if (e is Directory) return true; return mode == 'file' ? (e.path.endsWith('.xlsx') || e.path.endsWith('.xls')) : e.path.endsWith('.pdf'); }).toList(); entities.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())); } catch (_) {}
      return AlertDialog(
        title: Text(p.basename(initialPath)), 
        content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
          ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); }), 
          Expanded(child: ListView.builder(itemCount: entities.length, itemBuilder: (c, i) { final e = entities[i]; final isDir = e is Directory; return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue), title: Text(p.basename(e.path)), onTap: () { if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); } else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); } }); }))
        ])), 
        actions: [
          if (mode == 'file') TextButton(onPressed: () => _createNewFile(initialPath), child: const Text("새 파일 만들기", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))),
          if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")), 
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))
        ]
      );
    }));
  }

  void _handleClose() { _forgetFocus(); if (_originalItems.isEmpty) return; showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("리스트 닫기"), content: const Text("현재 리스트를 닫으시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { setState(() { _originalItems = []; _displayItems = []; _currentFileName = "파일을 선택하세요"; _excelPath = ""; _isSorted = false; _currentSortCol = ""; _searchController.clear(); _searchQuery = ""; _showUnfinishedOnly = false; _selectedSections.clear(); }); _saveSettings(); Navigator.pop(ctx); _showSnackBar("리스트가 닫혔습니다."); }, child: const Text("예", style: TextStyle(color: Colors.red)))])); }

  void _handleRefresh() { _forgetFocus(); if (_excelPath.isEmpty) return; if (File(_excelPath).existsSync()) { _loadExcelData(_excelPath, keepFilters: true); _showSnackBar("🔄 리스트를 새로고침했습니다."); } }

  void _showCompleteTimeDialog(ItemModel item) {
    _forgetFocus();
    String record = item.completeTime.isEmpty ? "기록 없음" : item.completeTime;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))),
            const SizedBox(height: 8),
            const Text("완료 입력 시간", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text("입력시간 : $record", style: const TextStyle(fontSize: 16)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
      ),
    );
  }

  void _resetFilteredItemsColumn(String col) {
    final filtered = _displayItems.where((i) => !i.isSubheading && i.realIndex != -1).toList();
    if (filtered.isEmpty) return;

    String colName = "";
    if (col == 'complete') colName = "완료";
    else if (col == 'process') colName = "공정";
    else if (col == 'complement') colName = "보완";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("리스트 항목 $colName 리셋"),
        content: Text("현재 화면에 보이는 ${filtered.length}개 항목의 [$colName] 항목을 리셋하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () {
              setState(() {
                for (var item in filtered) {
                  if (col == 'complete') {
                    item.complete = false;
                    item.completeTime = "";
                    item.complement = "";
                    item.complementTime = "";
                  } else if (col == 'process') {
                    item.process = "";
                    item.processTime = "";
                  } else if (col == 'complement') {
                    item.complement = "";
                    item.complementTime = "";
                  }
                }
              });
              if (_autoSave) _manualSave(silent: true);
              Navigator.pop(ctx);
              _showSnackBar("$colName 리셋 완료");
            },
            child: const Text("리셋 실행", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showComplementDialog(ItemModel item) {
    _forgetFocus();
    String lastRecord = "입력시간 : 없음";
    if (item.complementTime.isNotEmpty) {
      lastRecord = "입력시간 : ${item.complementTime}";
    }
    
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("보완 선택", style: TextStyle(fontWeight: FontWeight.bold)),
              if (item.complement.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: (item.complement == "부족") ? Colors.orange : Colors.red, borderRadius: BorderRadius.circular(4)),
                  child: Text(item.complement, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
          const SizedBox(height: 4),
          Text(lastRecord, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.blueGrey)),
        ],
      ),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogBtn("부족", Colors.orange, () { 
          item.complement = "부족"; 
          item.complete = false; 
          item.complementTime = DateTime.now().toString().substring(0, 16);
        }), 
        _dialogBtn("재작업", Colors.red, () { 
          item.complement = "재작업"; 
          item.complete = false; 
          item.complementTime = DateTime.now().toString().substring(0, 16);
        }), 
        const Divider(), 
        _dialogBtn("지우기", Colors.grey, () { 
          item.complement = ""; 
          item.complementTime = "";
        }), 
        _dialogBtn("선택취소", Colors.blueGrey, () {}),
      ]),
    ));
  }

  void _showProcessDialog(ItemModel item) {
    _forgetFocus();
    String lastRecord = "입력시간 : 없음";
    if (item.processTime.isNotEmpty) {
      lastRecord = "입력시간 : ${item.processTime}";
    }
    
    List<String> sortedDisplayList = List.from(_processList);
    bool hasFinished = sortedDisplayList.remove("완료");
    if (hasFinished) sortedDisplayList.add("완료");
    
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("공정 선택", style: TextStyle(fontWeight: FontWeight.bold)),
              if (item.process.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (() {
                      int? colorVal = _processColors[item.process];
                      if (colorVal != null) return Color(colorVal);
                      if (item.process == "완료") return Colors.purple;
                      if (item.process == "보류") return Colors.red;
                      return Colors.blueGrey;
                    })(),
                    borderRadius: BorderRadius.circular(4)
                  ),
                  child: Text(item.process, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ]
            ],
          ),
          const SizedBox(height: 4),
          Text(lastRecord, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.blueGrey)),
        ],
      ),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, childAspectRatio: 2.0, mainAxisSpacing: 8, crossAxisSpacing: 8, children: sortedDisplayList.map((p) { 
 int? colorVal = _processColors[p]; Color btnColor; if (colorVal != null) { btnColor = Color(colorVal); } else { if (p == "완료") btnColor = Colors.purple; else if (p == "보류") btnColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) btnColor = Colors.orange; else btnColor = Colors.blueGrey[700]!; } return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white), onPressed: () { 
   setState(() { 
     item.process = p; 
     item.processTime = DateTime.now().toString().substring(0, 16);
   }); 
   if (_autoSave) _manualSave(silent: true); Navigator.pop(context); 
 }, child: Text(p)); }).toList()),
                const Divider(), _dialogBtn("지우기", Colors.grey, () { 
                  item.process = ""; 
                  item.processTime = "";
                }), 
                _dialogBtn("선택취소", Colors.blueGrey, () {}),
              ])))));
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) { return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), onPressed: () { setState(onSelected); if (_autoSave) _manualSave(silent: true); Navigator.pop(context); }, child: Text(label))); }

  void _deleteSelectedRows() {
    if (_selectedIndices.isEmpty) return; final Set<int> finalDeleteIndices = Set.from(_selectedIndices);
    for (int selIdx in _selectedIndices) { try { final target = _originalItems.firstWhere((i) => i.realIndex == selIdx); if (target.isSubheading) { bool foundTarget = false; for (var item in _originalItems) { if (item.isSubheading) { if (item.realIndex == target.realIndex) foundTarget = true; else if (foundTarget) break; } else if (foundTarget) finalDeleteIndices.add(item.realIndex); } } } catch (_) {} }
    bool isSmbMode = _pdfFolderPath.startsWith("smb://"); bool shouldDeletePdf = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setModalState) => AlertDialog(title: const Text("행 삭제"), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text("선택한 섹션 및 하위 항목 포함 총 ${finalDeleteIndices.length}개를 삭제하시겠습니까?"), if (!isSmbMode) ...[const SizedBox(height: 15), Row(children: [Checkbox(value: shouldDeletePdf, onChanged: (v) => setModalState(() => shouldDeletePdf = v!)), const Expanded(child: Text("관련 로컬 PDF 파일도 함께 삭제", style: TextStyle(fontSize: 13, color: Colors.redAccent)))])]]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () async { final List<String> pdfsToDelete = []; if (shouldDeletePdf) { for (int delIdx in finalDeleteIndices) { try { final item = _originalItems.firstWhere((i) => i.realIndex == delIdx); if (!item.isSubheading && item.itemCode.isNotEmpty) pdfsToDelete.add(item.itemCode.trim()); } catch (_) {} } } int deletedFileCount = 0; if (shouldDeletePdf && pdfsToDelete.isNotEmpty) { for (String code in pdfsToDelete) { final file = File("$_baseDownloadPath/CheckSheet/$code.pdf"); if (await file.exists()) { try { await file.delete(); deletedFileCount++; } catch (_) {} } } } setState(() { _originalItems.removeWhere((item) => finalDeleteIndices.contains(item.realIndex)); _isEditMode = false; _selectedIndices.clear(); }); _applyFilterAndSort(); Navigator.pop(ctx); String msg = "${finalDeleteIndices.length}개 항목 삭제됨"; if (deletedFileCount > 0) msg += " (PDF $deletedFileCount개 삭제)"; _showSnackBar(msg); if (_autoSave) _manualSave(silent: true); }, child: const Text("삭제", style: TextStyle(color: Colors.red)))])));
  }

  void _toggleSectionSelection(String headerTitle) { String? currentHeader; List<int> sectionRealIndices = []; for (var item in _originalItems) { if (item.isSubheading) { currentHeader = item.itemCode; if (currentHeader == headerTitle) sectionRealIndices.add(item.realIndex); } else if (currentHeader == headerTitle) sectionRealIndices.add(item.realIndex); } setState(() { bool allSelected = sectionRealIndices.every((idx) => _selectedIndices.contains(idx)); if (allSelected) { for (var idx in sectionRealIndices) _selectedIndices.remove(idx); } else _selectedIndices.addAll(sectionRealIndices); }); }
  bool _isSectionSelected(String header) { String? current; List<int> indices = []; for (var i in _originalItems) { if (i.isSubheading) current = i.itemCode; else if (current == header) indices.add(i.realIndex); } return indices.isNotEmpty && indices.every((idx) => _selectedIndices.contains(idx)); }

  Widget _buildSummaryWidget(bool isDark) {
    if (_originalItems.isEmpty) return const SizedBox.shrink();
    final dataItems = _originalItems.where((i) => !i.isSubheading);
    int total = dataItems.length;
    int completed = dataItems.where((i) => i.complete).length;
    int shortage = dataItems.where((i) => i.complement == "부족").length;
    int rework = dataItems.where((i) => i.complement == "재작업").length;

    final fItems = _displayItems.where((i) => !i.isSubheading && i.realIndex != -1);
    int fTotal = fItems.length;
    int fComp = fItems.where((i) => i.complete).length;
    int fShortage = fItems.where((i) => i.complement == "부족").length;
    int fRework = fItems.where((i) => i.complement == "재작업").length;

    bool isFiltered = total != fTotal || _showUnfinishedOnly || _columnFilters.values.any((s) => s.isNotEmpty) || _searchQuery.isNotEmpty;

    String totalStr = "전체 $total / 완료 $completed";
    if (shortage > 0) totalStr += " / 부족 $shortage";
    if (rework > 0) totalStr += " / 재작업 $rework";
    totalStr += " / ${(total > 0 ? (completed / total * 100) : 0).toStringAsFixed(1)}%";

    String filterStr = "";
    if (isFiltered) {
      filterStr = "필터 $fTotal / 완료 $fComp";
      if (fShortage > 0) filterStr += " / 부족 $fShortage";
      if (fRework > 0) filterStr += " / 재작업 $fRework";
      filterStr += " / ${(fTotal > 0 ? (fComp / fTotal * 100) : 0).toStringAsFixed(1)}%";
    }

    return InkWell(
      onTap: () { setState(() => _showUnfinishedOnly = !_showUnfinishedOnly); _applyFilterAndSort(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text("[$totalStr]", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey[800]))),
            if (isFiltered) FittedBox(fit: BoxFit.scaleDown, child: Text("[$filterStr]", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent))),
          ],
        ),
      ),
    );
  }
  Widget _topBtn(String label, VoidCallback? onTap, {Color? bgColor}) { return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bgColor ?? Colors.blueGrey[700], foregroundColor: Colors.white, minimumSize: const Size(0, 45), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: FittedBox(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))); }

  Future<void> _handleItemClick(ItemModel item) async {
    _forgetFocus(); if (_autoSave) _manualSave(silent: true); if (_pdfFolderPath.startsWith("smb://")) { setState(() => _isLoading = true); try { String shareWithRest = _pdfFolderPath.replaceFirst("smb://", ""); int firstSlash = shareWithRest.indexOf("/"); String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest; String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : ""; String remoteFilePath = folderPath.isEmpty ? "${item.itemCode}.pdf" : "$folderPath/${item.itemCode}.pdf"; await _smbService.downloadFile(share, remoteFilePath, "$_baseDownloadPath/CheckSheet/${item.itemCode}.pdf"); } catch (_) {} finally { setState(() => _isLoading = false); } }
    if (!mounted) return; final String? lastItemCode = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(allItems: _originalItems.where((i) => !i.isSubheading).toList(), filteredItems: _displayItems.where((i) => !i.isSubheading && i.realIndex != -1).toList(), initialIndex: _originalItems.where((i) => !i.isSubheading).toList().indexOf(item), pdfFolderPath: _pdfFolderPath, smbService: _smbService, processList: _processList, processColors: _processColors, confirmComplete: _confirmComplete, onStatusUpdate: (it, type) { if (type == 'complete') { setState(() { it.complete = !it.complete; if (it.complete) { it.completeTime = DateTime.now().toString().substring(0, 16); it.complement = ""; it.complementTime = ""; } else { it.completeTime = ""; } }); } else setState(() {}); if (_autoSave) _manualSave(silent: true); })));
    if (lastItemCode != null) { 
      // ❗ 추적 메모리에 기록
      setState(() {
        _trackedItemCode = lastItemCode;
      });
      
      bool isDisplayed = _displayItems.any((i) => !i.isSubheading && i.itemCode == lastItemCode); 
      if (!isDisplayed) { 
        final targetItem = _originalItems.firstWhere((i) => !i.isSubheading && i.itemCode == lastItemCode); 
        setState(() { _temporaryVisibleItem = targetItem; }); 
        _applyFilterAndSort(); 
      } 
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(lastItemCode)); 
    }
  }

  void _showResetConfirm() {
    _forgetFocus();
    if (_originalItems.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 리셋 범위 선택"),
        content: const Text("리셋할 범위를 선택해주세요."),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showResetOptions(isAll: true);
                  },
                  child: const Text("전체 리셋"),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showSectionSelector();
                  },
                  child: const Text("부분제목별 리셋"),
                ),
                const Divider(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("취소", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showSectionSelector() {
    final subheads = _originalItems.where((i) => i.isSubheading).toList();
    if (subheads.isEmpty) {
      _showSnackBar("리셋할 부분제목이 없습니다.");
      return;
    }

    final ScrollController selectorScrollController = ScrollController();

    showDialog(
      context: context,
      builder: (ctx) {
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          title: Row(
            children: [
              const Text("리셋할 부분제목 선택", style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text("${subheads.length}개", style: TextStyle(fontSize: 12, color: isDark ? Colors.blue[200] : Colors.blue[700])),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 450,
            child: Theme(
              data: Theme.of(ctx).copyWith(
                scrollbarTheme: ScrollbarThemeData(
                  thumbColor: WidgetStateProperty.all(isDark ? Colors.blue[300]!.withOpacity(0.5) : Colors.blue[700]!.withOpacity(0.4)),
                  thickness: WidgetStateProperty.all(6),
                  radius: const Radius.circular(10),
                ),
              ),
              child: Scrollbar(
                controller: selectorScrollController,
                thumbVisibility: true, // ❗ 슬라이드가 필요한 경우 항상 노출
                child: ListView.separated(
                  controller: selectorScrollController,
                  shrinkWrap: true,
                  itemCount: subheads.length,
                  separatorBuilder: (c, i) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final item = subheads[i];
                    
                    // 해당 섹션의 하위 아이템 정보 계산
                    int totalItems = 0;
                    int completedItems = 0;
                    int startIdx = _originalItems.indexOf(item);
                    if (startIdx != -1) {
                      for (int j = startIdx + 1; j < _originalItems.length; j++) {
                        if (_originalItems[j].isSubheading) break;
                        totalItems++;
                        if (_originalItems[j].complete) completedItems++;
                      }
                    }
                    
                    double percent = totalItems > 0 ? (completedItems / totalItems * 100) : 0;
                    bool isAllDone = totalItems > 0 && totalItems == completedItems;

                    // ❗ 제목 3단 분리 로직 (3번째 언더바 기준) - 빌드 오류 수정분
                    String rawTitle = item.itemCode;
                    List<String> parts = rawTitle.split('_');
                    String line1 = "";
                    String line2 = "";
                    if (parts.length > 3) {
                      line1 = parts.sublist(0, 3).join('_');
                      line2 = parts.sublist(3).join('_');
                    } else {
                      line1 = rawTitle;
                      line2 = "";
                    }

                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _showResetOptions(isAll: false, subheadingItem: item);
                      },
                      child: Container(
                        height: 80, // 메인 UI와 동일하게 80px 고정
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: isAllDone ? (isDark ? Colors.green.withOpacity(0.1) : Colors.green[50]) : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1행: [순번] + 상위 정보 (Fit 적용)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "[${(i + 1).toString().padLeft(2, '0')}]",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.blue[300] : Colors.blue[800],
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    height: 20,
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        line1,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // 2행: 하위 상세 정보 (Fit 적용 및 들여쓰기)
                            Padding(
                              padding: const EdgeInsets.only(left: 38),
                              child: SizedBox(
                                height: 20,
                                width: double.infinity,
                                child: line2.isNotEmpty ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    line2,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 14,
                                    ),
                                  ),
                                ) : const SizedBox.shrink(),
                              ),
                            ),
                            // 3행: 통계 정보 (들여쓰기)
                            Padding(
                              padding: const EdgeInsets.only(left: 38),
                              child: Row(
                                children: [
                                  Icon(Icons.list_alt, size: 14, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text("항목: $totalItems개", style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                                  const SizedBox(width: 12),
                                  Icon(Icons.check_circle_outline, size: 14, color: isAllDone ? Colors.green : (isDark ? Colors.grey[400] : Colors.grey[600])),
                                  const SizedBox(width: 4),
                                  Text(
                                    "완료: $completedItems개 (${percent.toStringAsFixed(1)}%)",
                                    style: TextStyle(
                                      fontSize: 12, 
                                      color: isAllDone ? Colors.green : (isDark ? Colors.grey[400] : Colors.grey[700]),
                                      fontWeight: isAllDone ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  if (isAllDone) ...[
                                    const SizedBox(width: 8),
                                    const Text("🏆", style: TextStyle(fontSize: 12)),
                                  ]
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                selectorScrollController.dispose();
                Navigator.pop(ctx);
              }, 
              child: const Text("취소", style: TextStyle(fontSize: 16))
            )
          ],
        );
      },
    ).then((_) => selectorScrollController.dispose());
  }

  void _showResetOptions({required bool isAll, ItemModel? subheadingItem}) {
    bool resetStatus = true;
    bool resetRemarks = false;
    String targetName = isAll ? "전체" : "'${subheadingItem?.itemCode}' 섹션";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text("$targetName 리셋 설정"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text("체크상태 초기화"),
                subtitle: const Text("(완료, 보완, 공정 상태 삭제)"),
                value: resetStatus,
                onChanged: (v) => setModalState(() => resetStatus = v!),
              ),
              CheckboxListTile(
                title: const Text("비고란 초기화"),
                subtitle: const Text("(입력된 메모 일괄 삭제)"),
                value: resetRemarks,
                onChanged: (v) => setModalState(() => resetRemarks = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            TextButton(
              onPressed: (!resetStatus && !resetRemarks) ? null : () {
                _executeReset(isAll: isAll, subheadingItem: subheadingItem, status: resetStatus, remarks: resetRemarks);
                Navigator.pop(ctx);
              },
              child: const Text("리셋 실행", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _executeReset({required bool isAll, ItemModel? subheadingItem, required bool status, required bool remarks}) {
    setState(() {
      if (isAll) {
        for (var i in _originalItems) {
          if (i.isSubheading) continue;
          if (status) { 
            i.complete = false; 
            i.completeTime = "";
            i.complement = ""; 
            i.complementTime = "";
            i.process = ""; 
            i.processTime = "";
          }
          if (remarks) i.remarks = "";
        }
      } else if (subheadingItem != null) {
        int startIdx = _originalItems.indexOf(subheadingItem);
        if (startIdx != -1) {
          for (int i = startIdx + 1; i < _originalItems.length; i++) {
            if (_originalItems[i].isSubheading) break;
            if (status) { 
              _originalItems[i].complete = false; 
              _originalItems[i].completeTime = "";
              _originalItems[i].complement = ""; 
              _originalItems[i].complementTime = "";
              _originalItems[i].process = ""; 
              _originalItems[i].processTime = "";
            }
            if (remarks) _originalItems[i].remarks = "";
          }
        }
      }
    });
    _applyFilterAndSort();
    if (_autoSave) _manualSave(silent: true);
    _showSnackBar("리셋이 완료되었습니다.");
  }

  void _reorderSubheading(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1; if (oldIndex == newIndex) return; List<ItemModel> subheads = _originalItems.where((i) => i.isSubheading).toList(); if (oldIndex < 0 || oldIndex >= subheads.length) return; final targetSub = subheads[oldIndex]; int startIdx = _originalItems.indexOf(targetSub); int endIdx = startIdx + 1; while (endIdx < _originalItems.length && !_originalItems[endIdx].isSubheading) { endIdx++; } List<ItemModel> itemsToMove = _originalItems.sublist(startIdx, endIdx);
    setState(() { _originalItems.removeRange(startIdx, endIdx); List<ItemModel> remainingSubheads = _originalItems.where((i) => i.isSubheading).toList(); int insertIdx; if (newIndex >= remainingSubheads.length) { insertIdx = _originalItems.length; } else { insertIdx = _originalItems.indexOf(remainingSubheads[newIndex]); } _originalItems.insertAll(insertIdx, itemsToMove); });
    if (_autoSave) _manualSave(silent: true); _applyFilterAndSort();
  }

  void _selectAllVisible() {
    setState(() {
      for (var item in _displayItems) {
        if (!item.isSubheading && item.realIndex != -1) {
          _selectedIndices.add(item.realIndex);
        }
      }
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedIndices.clear();
    });
  }

  void _showBatchInputDialog() {
    if (_selectedIndices.isEmpty) {
      _showSnackBar("선택된 항목이 없습니다.");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("일괄 입력 항목 선택"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _batchTypeBtn("완료 일괄 변경", () => _showBatchValueSelection("complete")),
            _batchTypeBtn("공정 일괄 변경", () => _showBatchValueSelection("process")),
            _batchTypeBtn("보완 일괄 변경", () => _showBatchValueSelection("complement")),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))],
      ),
    );
  }

  Widget _batchTypeBtn(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.blueGrey[700],
          foregroundColor: Colors.white,
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }

  void _showBatchValueSelection(String type) {
    Navigator.pop(context); // 타입 선택창 닫기
    
    String title = "";
    List<Widget> options = [];

    if (type == "process") {
      title = "공정 일괄 선택";
      List<String> sortedList = List.from(_processList);
      bool hasFinished = sortedList.remove("완료");
      if (hasFinished) sortedList.add("완료");

      options = [
        Wrap(
          spacing: 8, runSpacing: 8,
          children: sortedList.map((p) {
            int? colorVal = _processColors[p];
            Color btnColor;
            if (colorVal != null) btnColor = Color(colorVal);
            else {
              if (p == "완료") btnColor = Colors.purple;
              else if (p == "보류") btnColor = Colors.red;
              else if (["용접", "도장", "도금", "인쇄"].contains(p)) btnColor = Colors.orange;
              else btnColor = Colors.blueGrey[700]!;
            }
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white),
              onPressed: () => _applyBatchInput(type, p),
              child: Text(p),
            );
          }).toList(),
        ),
        const Divider(),
        _batchValueBtn("지우기 (초기화)", Colors.grey, () => _applyBatchInput(type, "")),
      ];
    } else if (type == "complement") {
      title = "보완 일괄 선택";
      options = [
        _batchValueBtn("부족", Colors.orange, () => _applyBatchInput(type, "부족")),
        _batchValueBtn("재작업", Colors.red, () => _applyBatchInput(type, "재작업")),
        const Divider(),
        _batchValueBtn("지우기 (초기화)", Colors.grey, () => _applyBatchInput(type, "")),
      ];
    } else if (type == "complete") {
      title = "완료 여부 일괄 변경";
      options = [
        _batchValueBtn("완료 처리", Colors.green, () => _applyBatchInput(type, true)),
        _batchValueBtn("미완료 처리 (체크해제)", Colors.blueGrey, () => _applyBatchInput(type, false)),
      ];
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: options)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))],
      ),
    );
  }

  Widget _batchValueBtn(String label, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, 45),
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }

  void _applyBatchInput(String type, dynamic value) async {
    Navigator.pop(context); // 값 선택창 닫기

    final targets = _originalItems.where((i) => _selectedIndices.contains(i.realIndex) && !i.isSubheading).toList();
    if (targets.isEmpty) return;

    // 덮어쓰기 확인이 필요한지 체크
    bool hasData = targets.any((i) {
      if (type == "process") return i.process.isNotEmpty;
      if (type == "complement") return i.complement.isNotEmpty;
      if (type == "complete") return i.complete;
      return false;
    });

    if (hasData) {
      bool confirm = await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("데이터 덮어쓰기 확인"),
          content: const Text("선택한 항목 중 이미 데이터가 있는 항목이 있습니다.\n기존 데이터를 무시하고 덮어쓰시겠습니까?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("덮어쓰기", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
          ],
        ),
      ) ?? false;
      if (!confirm) return;
    }

    setState(() {
      String now = DateTime.now().toString().substring(0, 16);
      for (var item in targets) {
        if (type == "process") {
          item.process = value.toString();
          item.processTime = value.toString().isEmpty ? "" : now;
        } else if (type == "complement") {
          item.complement = value.toString();
          item.complementTime = value.toString().isEmpty ? "" : now;
          if (value.toString().isNotEmpty) {
            item.complete = false;
            item.completeTime = "";
          }
        } else if (type == "complete") {
          bool val = value as bool;
          item.complete = val;
          item.completeTime = val ? now : "";
          if (val) {
            item.complement = "";
            item.complementTime = "";
          }
        }
      }
    });

    if (_autoSave) _manualSave(silent: true);
    _showSnackBar("일괄 처리가 완료되었습니다.");
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: (_isReorderMode) 
          ? const Text("순서 변경 모드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent)) 
          : (_isEditMode)
            ? const SizedBox.shrink() // ❗ 선택모드 시 제목 숨김으로 공간 확보
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)]), 
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900], foregroundColor: Colors.white, 
        actions: _isReorderMode ? [
          TextButton(onPressed: () { setState(() { _originalItems = List.from(_preReorderItems); _isReorderMode = false; }); _applyFilterAndSort(); }, child: const Text("취소", style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () => setState(() => _isReorderMode = false), child: const Text("완료", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
        ] : _isEditMode ? [
          TextButton(onPressed: _selectAllVisible, child: const Text("전체선택", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _deselectAll, child: const Text("전체해제", style: TextStyle(color: Colors.white))),
          TextButton(onPressed: _showBatchInputDialog, child: const Text("일괄입력", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))),
          const VerticalDivider(color: Colors.white24, indent: 15, endIndent: 15),
          TextButton(onPressed: () {
            setState(() {
              if (_selectedIndices.isEmpty) {
                _showSnackBar("선택된 항목이 없습니다.");
                return;
              }
              _isSelectionFiltered = true;
              _isEditMode = false; // ❗ 모드 자동 종료
            });
            _applyFilterAndSort(); // ❗ 시스템 필터 로직을 통해 부분제목 포함하여 다시 그림
          }, child: const Text("선택필터", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _deleteSelectedRows, child: Text("삭제(${_selectedIndices.length})", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: () => setState(() { _isEditMode = false; _selectedIndices.clear(); _applyFilterAndSort(); }), child: const Text("취소", style: TextStyle(color: Colors.white))),
        ] : [
          if (_isSorted || _selectedSections.isNotEmpty || _showUnfinishedOnly || _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty || _quantitySearchQuery.isNotEmpty || _isSubheadingViewMode || _noFilterMode != 0 || _searchQuery.isNotEmpty || _columnFilters.values.any((s) => s.isNotEmpty) || _isSelectionFiltered) 
            TextButton(onPressed: _resetSort, child: const Text("필터리셋", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _handleRefresh, child: const Text("새로고침", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _handleClose, child: const Text("닫기", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red)),
        ]
      ),
      body: SafeArea(child: Column(children: [
        if (!_isEditMode && !_isReorderMode) Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [
          _topBtn("설정", _openSettings), const SizedBox(width: 4), _topBtn("엑셀선택", () => _pickSource('file')), const SizedBox(width: 4), _topBtn("PDF폴더", () => _pickSource('dir')), const SizedBox(width: 4),
          _topBtn("부분제목", () { 
            setState(() { 
              if (_isSubheadingViewMode) {
                _selectedSections.clear(); // ❗ 모드 해제 시 필터 초기화
              }
              _isSubheadingViewMode = !_isSubheadingViewMode; 
            }); 
            _applyFilterAndSort(); 
          }, bgColor: _isSubheadingViewMode ? Colors.blue : Colors.indigo[800]), const SizedBox(width: 4),
          _topBtn("선택모드", () => setState(() => _isEditMode = true), bgColor: Colors.orange[800]), const SizedBox(width: 4),
          if (_pdfFolderPath.startsWith("smb://")) ...[_topBtn("PDF동기화", _isSyncing ? null : _syncAllPdfs, bgColor: Colors.deepOrange[900]), const SizedBox(width: 4)],
          _topBtn("리셋", _showResetConfirm, bgColor: Colors.red[700]), const SizedBox(width: 4), _topBtn("저장", () { _forgetFocus(); _manualSave(); }, bgColor: Colors.green[700]),
        ])),
        if (!_isReorderMode) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [
          Expanded(flex: 3, child: TextField(controller: _searchController, focusNode: _searchFocusNode, decoration: InputDecoration(hintText: "품목코드 검색", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10), prefixIcon: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty) ? null : const Icon(Icons.search), suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_searchController.text.isNotEmpty) IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchQuery = ""; _applyFilterAndSort(); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollController.jumpTo(_preSearchScrollOffset)); }); }),
            IconButton(icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.blue), onPressed: () async {
              _forgetFocus();
              // ❗ 실행 전 항상 저장소에서 최신 줌 값 로드 (동기화 근본 해결)
              final prefs = await SharedPreferences.getInstance();
              _scannerZoom = prefs.getDouble('scannerZoom') ?? 0.0;
              
              if (!mounted) return;
              // ❗ Navigator.push를 사용하여 전체 화면으로 전환
              final String? result = await Navigator.push<String>(
                context, 
                MaterialPageRoute(builder: (_) => QrScannerDialog(initialZoom: _scannerZoom))
              );
              
              if (result != null && result.isNotEmpty) {
                String? code;
                
                // ❗ 새로운 반환 형식 대응 (CODE:xxx|ZOOM:0.x 또는 ZOOM:0.x)
                if (result.startsWith("CODE:")) {
                  final parts = result.split('|');
                  code = parts[0].replaceFirst("CODE:", "");
                  if (parts.length > 1 && parts[1].startsWith("ZOOM:")) {
                    final double? newZoom = double.tryParse(parts[1].replaceFirst("ZOOM:", ""));
                    if (newZoom != null) {
                      setState(() => _scannerZoom = newZoom);
                    }
                  }
                } else if (result.startsWith("ZOOM:")) {
                  final double? newZoom = double.tryParse(result.replaceFirst("ZOOM:", ""));
                  if (newZoom != null) {
                    setState(() => _scannerZoom = newZoom);
                    _saveSettings(); 
                  }
                  return;
                } else {
                  code = result;
                }

                if (code == null || code.isEmpty) return;

                // 데이터 정제 로직 강화 (<NUL>, <NULL> 제거 및 대소문자 무관 -S 처리)
                String cleaned = code.replaceAll('<NUL>', '').replaceAll('<NULL>', '').trim();
                // 제어 문자 및 보이지 않는 문자 제거 (ASCII 0-31)
                cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F]'), '');
                
                if (cleaned.toUpperCase().endsWith('-S')) {
                  cleaned = cleaned.substring(0, cleaned.length - 2);
                }
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("스캔: $result → 정제: $cleaned"), duration: const Duration(seconds: 2)));
                }

                if (_searchQuery.isEmpty) _preSearchScrollOffset = _scrollController.offset;
                setState(() {
                  _searchController.text = cleaned;
                  _searchQuery = cleaned;
                });
                _applyFilterAndSort();
                // ❗ 정제된 항목으로 즉시 이동 및 하이라이트
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(cleaned));
              }
            }),
          ])), onChanged: (v) { if (_searchQuery.isEmpty && v.isNotEmpty) _preSearchScrollOffset = _scrollController.offset; setState(() => _searchQuery = v); _applyFilterAndSort(); if (v.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollController.jumpTo(_preSearchScrollOffset)); })),
          Expanded(flex: 2, child: _buildSummaryWidget(isDark)),
        ])),
        if (!_isReorderMode) _buildHeader(isDark),
        Expanded(
          child: Listener(onPointerDown: (_) { 
            // ❗ 리스트 영역 터치 시에만 포커스 해제 (상단 버튼 영역 보호)
            _clearHighlight(); 
            _forgetFocus(); 
            setState(() {
              _trackedItemCode = null; 
            });
            if (_temporaryVisibleItem != null) { 
              setState(() { _temporaryVisibleItem = null; }); 
              _applyFilterAndSort(); 
            } 
          }, behavior: HitTestBehavior.translucent, child: Container(
            key: _scrollKey,
            child: _isLoading ? const Center(child: CircularProgressIndicator()) : _isReorderMode ? ReorderableListView(
            onReorder: _reorderSubheading, 
            buildDefaultDragHandles: false, // ❗ 기본 핸들 비활성화
            children: _originalItems.where((i) => i.isSubheading).toList().asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return ListTile(
                key: ValueKey("reorder-${item.itemCode}"), 
                title: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold)), 
                trailing: ReorderableDragStartListener(index: idx, child: const Icon(Icons.drag_handle)), // ❗ 즉시 드래그 핸들 적용
                tileColor: isDark ? Colors.white10 : Colors.grey[200]
              );
            }).toList()) : ListView.builder(
              controller: _scrollController, 
              physics: const AlwaysScrollableScrollPhysics(), // ❗ 부드러운 스크롤 보장
              itemCount: _displayItems.length, 
              itemBuilder: (ctx, idx) {
            final item = _displayItems[idx];
            if (item.isSubheading) {
              bool isSectionSel = _selectedSections.contains(item.itemCode);
              
              // 해당 섹션의 요약 정보 계산
              int totalItems = 0;
              int completedItems = 0;
              int startIdx = _originalItems.indexOf(item);
              int sectionSeq = _originalItems.where((i) => i.isSubheading).toList().indexOf(item) + 1;
              
              if (startIdx != -1) {
                for (int j = startIdx + 1; j < _originalItems.length; j++) {
                  if (_originalItems[j].isSubheading) break;
                  totalItems++;
                  if (_originalItems[j].complete) completedItems++;
                }
              }
              double percent = totalItems > 0 ? (completedItems / totalItems * 100) : 0;
              bool isAllDone = totalItems > 0 && totalItems == completedItems;

              // ❗ 제목 3단 분리 로직 (3번째 언더바 기준)
              String rawTitle = item.itemCode;
              List<String> parts = rawTitle.split('_');
              String line1 = "";
              String line2 = "";
              if (parts.length > 3) {
                line1 = parts.sublist(0, 3).join('_');
                line2 = parts.sublist(3).join('_');
              } else {
                line1 = rawTitle;
                line2 = "";
              }

              return GestureDetector(
                onTap: () {
                  if (_isEditMode) { _toggleSectionSelection(item.itemCode); } 
                  else if (_isSubheadingViewMode) { if (item.realIndex != -1) { setState(() { _selectedSections = {item.itemCode}; _isSubheadingViewMode = false; }); _applyFilterAndSort(); } else setState(() => _isSubheadingViewMode = false); } 
                  else { setState(() { if (_selectedSections.contains(item.itemCode)) _selectedSections.remove(item.itemCode); else _selectedSections.add(item.itemCode); }); _applyFilterAndSort(); }
                }, 
                child: Container(
                  height: _subheadingHeight, 
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                  alignment: Alignment.centerLeft, 
                  decoration: BoxDecoration(
                    color: isAllDone ? (isDark ? Colors.green.withOpacity(0.15) : Colors.green[100]) : (_selectedSections.contains(item.itemCode) ? Colors.blueGrey : (isDark ? Colors.white10 : Colors.grey[300])),
                    border: Border(bottom: BorderSide(color: isDark ? Colors.white24 : Colors.grey[400]!, width: 0.5)),
                  ),
                  child: Row(children: [
                    if (_isSubheadingViewMode && !_isEditMode) Checkbox(value: isSectionSel, onChanged: (v) { setState(() { if (v!) _selectedSections.add(item.itemCode); else _selectedSections.remove(item.itemCode); }); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 1행: [순번] + 상위 정보 (Fit 적용)
                          Row(
                            children: [
                              Text(
                                "[${sectionSeq.toString().padLeft(2, '0')}]",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.blue[300] : Colors.blue[800],
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: SizedBox(
                                  height: 20,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      line1,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // 2행: 하위 상세 정보 (모델명 등 - Fit 적용 및 들여쓰기)
                          Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: SizedBox(
                              height: 20,
                              width: double.infinity,
                              child: line2.isNotEmpty ? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  line2,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 14,
                                  ),
                                ),
                              ) : const SizedBox.shrink(),
                            ),
                          ),
                          // 3행: 통계 정보 (들여쓰기)
                          Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: Row(
                              children: [
                                Icon(Icons.list_alt, size: 12, color: isDark ? Colors.grey[400] : Colors.grey[700]),
                                const SizedBox(width: 3),
                                Text("$totalItems개", style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[700])),
                                const SizedBox(width: 10),
                                Icon(Icons.check_circle_outline, size: 12, color: isAllDone ? Colors.green : (isDark ? Colors.grey[400] : Colors.grey[600])),
                                const SizedBox(width: 3),
                                Text(
                                  "완료 $completedItems개 (${percent.toStringAsFixed(1)}%)",
                                  style: TextStyle(
                                    fontSize: 11, 
                                    color: isAllDone ? (isDark ? Colors.green[300] : Colors.green[800]) : (isDark ? Colors.grey[400] : Colors.grey[700]),
                                    fontWeight: isAllDone ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (isAllDone) ...[
                                  const SizedBox(width: 6),
                                  const Text("🏆", style: TextStyle(fontSize: 11)),
                                ]
                              ],
                            ),
                          ),
                        ],
                      ),
                    ), 
                    if (_isEditMode) Icon(_isSectionSelected(item.itemCode) ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20),
                    if (_isSubheadingViewMode && !_isEditMode) IconButton(icon: const Icon(Icons.reorder, size: 20, color: Colors.blue), onPressed: () => setState(() { _preReorderItems = List.from(_originalItems); _isReorderMode = true; }), tooltip: "순서 변경"),
                  ])
                )
              );
            }
            return _buildDataRow(item, isDark);
          })),
        )),
        if (_isSubheadingViewMode && _selectedSections.isNotEmpty) Container(color: isDark ? Colors.blueGrey[900] : Colors.blueGrey[100], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
            Text("선택됨: ${_selectedSections.length}개", style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(),
            TextButton(onPressed: () { setState(() { _selectedSections.clear(); _isSubheadingViewMode = false; }); _applyFilterAndSort(); }, child: const Text("모두보기", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("모두 해제")),
            TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("취소", style: TextStyle(color: Colors.red))), const SizedBox(width: 8),
            ElevatedButton(onPressed: () { setState(() => _isSubheadingViewMode = false); _applyFilterAndSort(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), child: const Text("선택 항목 보기")),
          ])),
        if (_isSyncing) const LinearProgressIndicator(minHeight: 2, color: Colors.orange),
        Offstage(child: TextField(focusNode: _dummyFocusNode, readOnly: true)),
      ])),
    );
  }

  void _handleDragUpdate(double globalY) {
    final RenderBox? renderBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localPosition = renderBox.globalToLocal(Offset(0, globalY));
    double localY = localPosition.dy;

    double currentOffset = _scrollController.offset;
    double targetY = localY + currentOffset;
    
    double accumulatedHeight = 0;
    int? targetIdx;
    
    for (int i = 0; i < _displayItems.length; i++) {
      double h = _displayItems[i].isSubheading ? _subheadingHeight : _itemHeight;
      if (targetY >= accumulatedHeight && targetY <= accumulatedHeight + h) {
        targetIdx = i;
        break;
      }
      accumulatedHeight += h;
    }
    
    if (targetIdx != null) {
      final item = _displayItems[targetIdx];
      if (!item.isSubheading && item.realIndex != -1) {
        if (!_selectedIndices.contains(item.realIndex)) {
          setState(() {
            _selectedIndices.add(item.realIndex);
          });
        }
      }
    }
  }

  void _handleAutoScroll(double globalY) {
    _scrollTimer?.cancel();
    final RenderBox? renderBox = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localPosition = renderBox.globalToLocal(Offset(0, globalY));
    double localY = localPosition.dy;

    const double threshold = 60.0;
    double viewHeight = renderBox.size.height;
    
    if (localY < threshold) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (_scrollController.offset > 0) {
          _scrollController.jumpTo(_scrollController.offset - 10);
          _handleDragUpdate(globalY);
        } else {
          timer.cancel();
        }
      });
    } else if (localY > viewHeight - threshold) {
      _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (_scrollController.offset < _scrollController.position.maxScrollExtent) {
          _scrollController.jumpTo(_scrollController.offset + 10);
          _handleDragUpdate(globalY);
        } else {
          timer.cancel();
        }
      });
    }
  }

  Widget _buildSelectionZone({required Widget child, required ItemModel item}) {
    if (!_isEditMode) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (details) {
        setState(() => _isSelecting = true);
        _handleDragUpdate(details.globalPosition.dy);
      },
      onVerticalDragUpdate: (details) {
        _handleDragUpdate(details.globalPosition.dy);
        _handleAutoScroll(details.globalPosition.dy);
      },
      onVerticalDragEnd: (_) {
        setState(() => _isSelecting = false);
        _scrollTimer?.cancel();
      },
      onTap: () {
        setState(() {
          if (_selectedIndices.contains(item.realIndex)) {
            _selectedIndices.remove(item.realIndex);
          } else {
            _selectedIndices.add(item.realIndex);
          }
        });
      },
      child: child,
    );
  }

  Widget _buildHeader(bool isDark) { return Container(color: isDark ? Colors.grey[900] : Colors.grey[800], height: 40, child: Row(children: [if (_isEditMode) const SizedBox(width: 35), _headerBtn("No", "no", 35), Expanded(flex: 5, child: _headerBtn("품목코드", "itemCode", null)), _headerBtn("수량", "quantity", 40), _headerBtn("완료", "complete", 50), _headerBtn("공정", "process", 50), _headerBtn("보완", "complement", 50), Expanded(flex: 3, child: _headerBtn("비고", "remarks", null))])); }
  Widget _headerBtn(String label, String? colKey, double? width) { bool isTarget = colKey != null && _currentSortCol == colKey; bool isNoFilt = colKey == 'no' && _noFilterMode != 0; String dLabel = (colKey == 'no' && _noFilterMode == 2) ? "-No" : label; bool isFiltActive = false; if (colKey != null && ['complete', 'complement', 'process', 'quantity'].contains(colKey)) isFiltActive = _columnFilters[colKey]!.isNotEmpty || (colKey == 'quantity' && _quantitySearchQuery.isNotEmpty); else if (colKey == 'remarks') isFiltActive = _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty; return InkWell(onTap: colKey == null ? null : () => _sortBy(colKey), child: Container(width: width, alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: Text(dLabel, style: TextStyle(color: (isNoFilt || isFiltActive) ? Colors.yellow : Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)), if (isTarget) Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18)]))); }
  Widget _buildDataRow(ItemModel item, bool isDark) {
    bool isSel = _selectedIndices.contains(item.realIndex);
    bool isHigh = item.realIndex == _highlightedRealIndex;
    
    return Container(
      decoration: BoxDecoration(
        color: isSel ? Colors.blue.withOpacity(0.1) : (item.complete ? (isDark ? Colors.green.withOpacity(0.1) : Colors.green[50]) : null),
        border: isHigh ? Border.all(color: Colors.blue, width: 2) : Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))
      ),
      height: 45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ❗ 1. 에디트 모드 체크박스 (헤더와 맞춤)
          if (_isEditMode) _buildSelectionZone(
            item: item,
            child: Container(width: 35, alignment: Alignment.center, child: Icon(isSel ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20))
          ),
          
          // ❗ 2. No 영역
          _buildSelectionZone(
            item: item,
            child: SizedBox(width: 35, child: Center(child: Text(item.displayNo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
          ),
          
          // ❗ 3. 품목코드 (스크롤 구역 - GestureDetector 없음)
          Expanded(
            flex: 5,
            child: GestureDetector(
              onTap: _isEditMode ? () {
                setState(() {
                  if (isSel) _selectedIndices.remove(item.realIndex);
                  else _selectedIndices.add(item.realIndex);
                });
              } : () => _handleItemClick(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                color: Colors.transparent, 
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.itemCode,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.blue[300] : Colors.blue[700],
                      fontWeight: FontWeight.bold
                    )
                  )
                )
              )
            )
          ),

          // ❗ 4. 수량
          _buildSelectionZone(
            item: item,
            child: SizedBox(width: 40, child: Center(child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
          ),

          // ❗ 5. 완료 체크
          _buildSelectionZone(
            item: item,
            child: _cellCheck(item, isDark, _isEditMode ? null : () async { 
              if (_confirmComplete) {
                bool isChecking = !item.complete;
                bool? confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(isChecking ? "완료 체크 확인" : "완료 체크 해제 확인"),
                    content: Text("[${item.itemCode}]\n항목을 ${isChecking ? '완료 처리' : '미완료 처리'}하시겠습니까?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                );
                if (confirm != true) return;
              }
              setState(() { 
                item.complete = !item.complete; 
                if (item.complete) { 
                  item.completeTime = DateTime.now().toString().substring(0, 16); 
                  item.complement = ""; 
                  item.complementTime = ""; 
                } else { 
                  item.completeTime = ""; 
                } 
              }); 
              if (_autoSave) _manualSave(silent: true); 
            }),
          ),

          // ❗ 6. 공정
          _buildSelectionZone(
            item: item,
            child: _cellProcess(item.process, isDark, _isEditMode ? null : () => _showProcessDialog(item)),
          ),

          // ❗ 7. 보완
          _buildSelectionZone(
            item: item,
            child: _cellComplement(item.complement, isDark, _isEditMode ? null : () => _showComplementDialog(item)),
          ),

          // ❗ 8. 비고 (flex: 3)
          Expanded(
            flex: 3,
            child: _buildSelectionZone(
              item: item,
              child: IgnorePointer(
                ignoring: _isEditMode,
                child: _RemarksCell(
                  item: item,
                  onSave: () { if (_autoSave) _manualSave(silent: true); },
                  onForgetFocus: _forgetFocus
                )
              )
            )
          ),
        ]
      )
    );
  }
  Widget _cellCheck(ItemModel item, bool isDark, VoidCallback? onTap) { return InkWell(onTap: onTap, onLongPress: _isEditMode ? null : () => _showCompleteTimeDialog(item), child: Container(width: 50, alignment: Alignment.center, color: item.complete ? Colors.green.withOpacity(0.3) : null, child: item.complete ? const Icon(Icons.check, size: 20, color: Colors.green) : null)); }
  Widget _cellComplement(String txt, bool isDark, VoidCallback? onTap) { if (txt.isEmpty) return InkWell(onTap: onTap, child: const SizedBox(width: 50)); Color baseColor = (txt == "부족") ? Colors.orange : Colors.red; return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: BoxDecoration(color: baseColor.withOpacity(0.15), border: Border(left: BorderSide(color: baseColor, width: 4))), alignment: Alignment.center, child: FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))))); }
  Widget _cellProcess(String txt, bool isDark, VoidCallback? onTap) { int? colorVal = txt.isNotEmpty ? _processColors[txt] : null; Color baseColor; if (colorVal != null) { baseColor = Color(colorVal); } else { if (txt == "완료") baseColor = Colors.purple; else if (txt == "보류") baseColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(txt)) baseColor = Colors.orange; else baseColor = Colors.blueGrey; } return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: txt.isEmpty ? const BoxDecoration(color: Colors.transparent) : BoxDecoration(color: baseColor.withOpacity(0.15), border: Border(left: BorderSide(color: baseColor, width: 4))), alignment: Alignment.center, child: txt.isNotEmpty ? FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))) : null)); }
  void _showError(String t, String m) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(t), content: Text(m), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))])); }
  void _showSnackBar(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(m)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating)); }
  Future<void> _manualSave({bool silent = false}) async { if (_excelPath.isNotEmpty) { bool ok = await _excelService.saveExcel(_excelPath, _originalItems); if (ok && !silent) _showSnackBar("저장 완료"); } }
  int _compareDisplayNo(String a, String b) { List<String> pa = a.split('-'); List<String> pb = b.split('-'); int ma = int.tryParse(pa[0]) ?? 0; int mb = int.tryParse(pb[0]) ?? 0; if (ma != mb) return ma.compareTo(mb); int sa = (pa.length > 1) ? (int.tryParse(pa[1]) ?? 0) : 0; int sb = (pb.length > 1) ? (int.tryParse(pb[1]) ?? 0) : 0; return sa.compareTo(sb); }

  // ❗ 설정 다이얼로그용 줌 퀵 버튼 헬퍼
  Widget _zoomQuickBtnDialog(String label, double value, StateSetter setDialogState) {
    bool isSelected = (_scannerZoom - value).abs() < 0.05;
    return GestureDetector(
      onTap: () => setDialogState(() => _scannerZoom = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _RemarksCell extends StatefulWidget {
  final ItemModel item; final VoidCallback onSave; final VoidCallback onForgetFocus;
  const _RemarksCell({required this.item, required this.onSave, required this.onForgetFocus});
  @override State<_RemarksCell> createState() => _RemarksCellState();
}
class _RemarksCellState extends State<_RemarksCell> {
  late TextEditingController _ctrl; late FocusNode _node;
  @override void initState() { super.initState(); _ctrl = TextEditingController(text: widget.item.remarks); _node = FocusNode(); _node.addListener(() { if (!_node.hasFocus) { widget.item.remarks = _ctrl.text; widget.onSave(); } }); }
  @override void didUpdateWidget(_RemarksCell old) { super.didUpdateWidget(old); if (!_node.hasFocus) _ctrl.text = widget.item.remarks; }
  @override void dispose() { _node.dispose(); _ctrl.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { return Stack(alignment: Alignment.centerRight, children: [TextField(focusNode: _node, controller: _ctrl, style: const TextStyle(fontSize: 12), decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4)), onSubmitted: (v) { widget.item.remarks = v; widget.onSave(); widget.onForgetFocus(); }), if (_ctrl.text.isNotEmpty) IconButton(icon: const Icon(Icons.cancel, size: 14), onPressed: () { setState(() => _ctrl.clear()); widget.item.remarks = ""; widget.onSave(); })]); }
}
