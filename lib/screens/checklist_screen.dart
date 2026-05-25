import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
import '../services/smb_service.dart';
import 'pdf_view_screen.dart';
import 'dart:io';
import 'dart:convert';
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
  bool _isLoading = false;
  bool _isSorted = false;
  bool _isSyncing = false;

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
  final Set<int> _selectedIndices = {}; 

  final ScrollController _scrollController = ScrollController();
  int? _highlightedRealIndex;
  final double _subheadingHeight = 40.0;
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
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) _loadExcelData(_excelPath);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
    await prefs.setStringList('processList', _processList);
    await prefs.setString('processColors', jsonEncode(_processColors));
  }

  Future<void> _loadExcelData(String path) async {
    setState(() => _isLoading = true);
    try {
      final items = await _excelService.loadExcel(path);
      setState(() {
        _originalItems = items;
        _displayItems = List.from(items);
        _currentFileName = p.basename(path);
        _excelPath = path;
        _isSorted = false;
        _currentSortCol = "";
        _searchController.clear();
        _searchQuery = "";
        _showUnfinishedOnly = false;
        _selectedSections.clear();
        _isEditMode = false;
        _isReorderMode = false;
        _selectedIndices.clear();
        _noFilterMode = 0;
        _temporaryVisibleItem = null;
        _remarksFilterQuery = "";
        _remarksExcludeQuery = "";
        _remarksIncludeLogic = "AND";
        _remarksExcludeLogic = "OR";
        _columnFilters.forEach((key, value) => value.clear());
      });
      _saveSettings();
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
    else if (col == 'process') { options = validOptions.toList(); options.sort(); titleText = "공정 설정"; }
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
            const Text("포함 필터", style: TextStyle(fontWeight: FontWeight.bold)), TextField(controller: includeController),
            Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)), const Text("OR")]),
            const SizedBox(height: 10), const Text("제외 필터", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)), TextField(controller: excludeController),
            Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)), const Text("OR")]),
          ] else ...[
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => setModalState(() => localFilters.addAll(options.where((o) => col == 'process' || col == 'quantity' || validOptions.contains(o)))), child: const Text("전체 선택", style: TextStyle(fontSize: 12)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => setModalState(() => localFilters.clear()), child: const Text("전체 해제", style: TextStyle(fontSize: 12))))]),
            const SizedBox(height: 10), if (col == 'quantity') ...[const Text("수량 직접 입력", style: TextStyle(fontWeight: FontWeight.bold)), TextField(controller: quantityController, keyboardType: TextInputType.number), const SizedBox(height: 15)],
            const Text("항목 선택", style: TextStyle(fontWeight: FontWeight.bold)), _buildFilterGrid(options, localFilters, col, setModalState, validOptions: (col == 'complete' || col == 'complement') ? validOptions : null),
          ],
        ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () { setState(() { _isSorted = localIsSorted; if (localIsSorted) { _currentSortCol = col; _isAscending = localIsAscending; } else if (_currentSortCol == col) _currentSortCol = ""; if (_columnFilters.containsKey(col)) _columnFilters[col] = localFilters; if (col == 'remarks') { _remarksFilterQuery = includeController.text; _remarksExcludeQuery = excludeController.text; _remarksIncludeLogic = localIncludeLogic; _remarksExcludeLogic = localExcludeLogic; } if (col == 'quantity') _quantitySearchQuery = quantityController.text; }); _applyFilterAndSort(); Navigator.pop(ctx); }, child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold)))],
    )));
  }

  Widget _buildFilterGrid(List<String> options, Set<String> localFilters, String col, StateSetter setModalState, {Set<String>? validOptions}) {
    return LayoutBuilder(builder: (context, constraints) {
      double itemWidth = col == 'complete' ? constraints.maxWidth / 2 : constraints.maxWidth / 3;
      return Wrap(children: options.map((opt) {
        bool isValid = validOptions == null || validOptions.contains(opt);
        bool isSel = localFilters.contains(opt);
        return SizedBox(width: itemWidth, child: InkWell(
          onTap: !isValid ? null : () => setModalState(() { if (col == 'complete') { if (isSel) localFilters.clear(); else { localFilters.clear(); localFilters.add(opt); } } else { if (isSel) localFilters.remove(opt); else localFilters.add(opt); } }),
          child: Opacity(opacity: isValid ? 1.0 : 0.3, child: Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: isSel, onChanged: !isValid ? null : (v) => setModalState(() { if (col == 'complete') { if (isSel && !v!) localFilters.clear(); else { localFilters.clear(); if (v!) localFilters.add(opt); } } else { if (v!) localFilters.add(opt); else localFilters.remove(opt); } }), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(opt, style: const TextStyle(fontSize: 12))))])),
        ));
      }).toList());
    });
  }

  Future<void> _pickSource(String mode) async { _forgetFocus(); showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.phone_android), title: const Text("내 휴대폰"), onTap: () { Navigator.pop(ctx); _openCustomPicker(mode); }), ListTile(leading: const Icon(Icons.computer), title: const Text("PC 공유폴더 (SMB)"), onTap: () { Navigator.pop(ctx); _openSmbShares(mode); }), const SizedBox(height: 10)]))); }

  void _openSettings() async {
    _forgetFocus(); final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp')); final userController = TextEditingController(text: prefs.getString('smbUser')); final passController = TextEditingController(text: prefs.getString('smbPass'));
    final newProcessController = TextEditingController(); bool obscurePass = true; 
    final List<Color> palette = [Colors.blueGrey, Colors.blue, Colors.indigo, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink, Colors.purple, Colors.deepPurple];
    showDialog(context: context, builder: (ctx) => DefaultTabController(length: 2, child: StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const TabBar(labelColor: Colors.blue, unselectedLabelColor: Colors.grey, tabs: [Tab(icon: Icon(Icons.dns), text: "연결 설정"), Tab(icon: Icon(Icons.settings_suggest), text: "공정 관리")]),
      content: SizedBox(width: double.maxFinite, height: 450, child: TabBarView(children: [
        SingleChildScrollView(child: Column(children: [const SizedBox(height: 20), TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소", border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: userController, decoration: const InputDecoration(labelText: "ID", border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: passController, obscureText: obscurePass, decoration: InputDecoration(labelText: "PW", border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obscurePass ? Icons.visibility : Icons.visibility_off), onPressed: () => setDialogState(() => obscurePass = !obscurePass)))), const SizedBox(height: 20), ElevatedButton.icon(onPressed: () async { String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text); if (err == null) { List<String> shares = await _smbService.listShares(); _showError("성공", "✅ 접속 성공!\n\n[공유 목록]\n${shares.join('\n')}"); } else _showError("오류", "접속 실패: $err"); }, icon: const Icon(Icons.check_circle_outline), label: const Text("접속 테스트"))])),
        Column(children: [
          Expanded(child: ReorderableListView(onReorder: (o, n) { setDialogState(() { if (n > o) n -= 1; final String item = _processList.removeAt(o); _processList.insert(n, item); }); }, children: [
              for (int i = 0; i < _processList.length; i++) 
                ListTile(key: ValueKey(_processList[i] + i.toString()), dense: true, visualDensity: VisualDensity.compact, contentPadding: const EdgeInsets.symmetric(horizontal: 4), leading: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20), onPressed: () { showDialog(context: context, builder: (confirmCtx) => AlertDialog(title: const Text("공정 삭제"), content: Text("'${_processList[i]}' 공정을 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text("취소")), TextButton(onPressed: () { setDialogState(() { _processList.removeAt(i); }); Navigator.pop(confirmCtx); }, child: const Text("삭제", style: TextStyle(color: Colors.red)))])); }),
                      (() {
                        Color dotColor;
                        if (_processColors[_processList[i]] != null) dotColor = Color(_processColors[_processList[i]]!);
                        else { String p = _processList[i]; if (p == "완료") dotColor = Colors.purple; else if (p == "보류") dotColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) dotColor = Colors.orange; else dotColor = Colors.blueGrey; }
                        return GestureDetector(onTap: () { showDialog(context: context, builder: (pCtx) => AlertDialog(title: Text("${_processList[i]} 색상 선택"), content: Wrap(spacing: 8, runSpacing: 8, children: palette.map((c) => GestureDetector(onTap: () { setDialogState(() => _processColors[_processList[i]] = c.value); Navigator.pop(pCtx); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))).toList()))); }, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)));
                      })(),
                    ]), title: Text(_processList[i], style: const TextStyle(fontSize: 13)), trailing: const Icon(Icons.drag_handle, size: 20))
            ])),
          const Divider(), Row(children: [Expanded(child: TextField(controller: newProcessController, decoration: const InputDecoration(hintText: "공정명 추가", isDense: true))), IconButton(icon: const Icon(Icons.add_box, color: Colors.green, size: 30), onPressed: () { if (newProcessController.text.isNotEmpty) setDialogState(() { _processList.add(newProcessController.text); newProcessController.clear(); }); }), IconButton(icon: const Icon(Icons.color_lens_outlined, color: Colors.orange, size: 30), onPressed: () { setDialogState(() => _processColors.clear()); })]),
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
      return AlertDialog(title: Text(p.basename(initialPath)), content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); }), Expanded(child: ListView.builder(itemCount: entities.length, itemBuilder: (c, i) { final e = entities[i]; final isDir = e is Directory; return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue), title: Text(p.basename(e.path)), onTap: () { if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); } else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); } }); }))])), actions: [if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))]);
    }));
  }

  void _handleClose() { _forgetFocus(); if (_originalItems.isEmpty) return; showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("리스트 닫기"), content: const Text("현재 리스트를 닫으시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { setState(() { _originalItems = []; _displayItems = []; _currentFileName = "파일을 선택하세요"; _excelPath = ""; _isSorted = false; _currentSortCol = ""; _searchController.clear(); _searchQuery = ""; _showUnfinishedOnly = false; _selectedSections.clear(); }); _saveSettings(); Navigator.pop(ctx); _showSnackBar("리스트가 닫혔습니다."); }, child: const Text("예", style: TextStyle(color: Colors.red)))])); }

  void _handleRefresh() { _forgetFocus(); if (_excelPath.isEmpty) return; if (File(_excelPath).existsSync()) { _loadExcelData(_excelPath); _showSnackBar("🔄 리스트를 새로고침했습니다."); } }

  void _showComplementDialog(ItemModel item) { _forgetFocus(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("보완 선택"), content: Column(mainAxisSize: MainAxisSize.min, children: [_dialogBtn("부족", Colors.orange, () { item.complement = "부족"; item.complete = false; }), _dialogBtn("재작업", Colors.red, () { item.complement = "재작업"; item.complete = false; }), const Divider(), _dialogBtn("지우기", Colors.grey, () { item.complement = ""; }), _dialogBtn("선택취소", Colors.blueGrey, () {}),]))); }

  void _showProcessDialog(ItemModel item) {
    _forgetFocus(); List<String> sortedDisplayList = List.from(_processList); bool hasFinished = sortedDisplayList.remove("완료"); if (hasFinished) sortedDisplayList.add("완료");
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("공정 선택"), content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 2.5, mainAxisSpacing: 8, crossAxisSpacing: 8, children: sortedDisplayList.map((p) { int? colorVal = _processColors[p]; Color btnColor; if (colorVal != null) { btnColor = Color(colorVal); } else { if (p == "완료") btnColor = Colors.purple; else if (p == "보류") btnColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) btnColor = Colors.orange; else btnColor = Colors.blueGrey[700]!; } return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white), onPressed: () { setState(() { item.process = p; }); if (_autoSave) _manualSave(silent: true); Navigator.pop(context); }, child: Text(p)); }).toList()),
                const Divider(), _dialogBtn("지우기", Colors.grey, () { item.process = ""; }), _dialogBtn("선택취소", Colors.blueGrey, () {}),
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

  Widget _buildSummaryWidget(bool isDark) { if (_originalItems.isEmpty) return const SizedBox.shrink(); final dataItems = _originalItems.where((i) => !i.isSubheading); int total = dataItems.length; int completed = dataItems.where((i) => i.complete).length; final fItems = _displayItems.where((i) => !i.isSubheading && i.realIndex != -1); int fTotal = fItems.length; int fComp = fItems.where((i) => i.complete).length; bool isFiltered = total != fTotal || _showUnfinishedOnly; return InkWell(onTap: () { setState(() => _showUnfinishedOnly = !_showUnfinishedOnly); _applyFilterAndSort(); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text("[전체 $total / 완료 $completed / ${(total>0?(completed/total*100):0).toStringAsFixed(1)}%]", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey[800])), if (isFiltered) Text("[필터 $fTotal / 완료 $fComp / ${(fTotal>0?(fComp/fTotal*100):0).toStringAsFixed(1)}%]", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent))]))); }
  Widget _topBtn(String label, VoidCallback? onTap, {Color? bgColor}) { return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bgColor ?? Colors.blueGrey[700], foregroundColor: Colors.white, minimumSize: const Size(0, 45), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: FittedBox(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))); }

  Future<void> _handleItemClick(ItemModel item) async {
    _forgetFocus(); if (_autoSave) _manualSave(silent: true); if (_pdfFolderPath.startsWith("smb://")) { setState(() => _isLoading = true); try { String shareWithRest = _pdfFolderPath.replaceFirst("smb://", ""); int firstSlash = shareWithRest.indexOf("/"); String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest; String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : ""; String remoteFilePath = folderPath.isEmpty ? "${item.itemCode}.pdf" : "$folderPath/${item.itemCode}.pdf"; await _smbService.downloadFile(share, remoteFilePath, "$_baseDownloadPath/CheckSheet/${item.itemCode}.pdf"); } catch (_) {} finally { setState(() => _isLoading = false); } }
    if (!mounted) return; final String? lastItemCode = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(allItems: _originalItems.where((i) => !i.isSubheading).toList(), filteredItems: _displayItems.where((i) => !i.isSubheading && i.realIndex != -1).toList(), initialIndex: _originalItems.where((i) => !i.isSubheading).toList().indexOf(item), pdfFolderPath: _pdfFolderPath, smbService: _smbService, processList: _processList, processColors: _processColors, onStatusUpdate: (it, type) { if (type == 'complete') { setState(() { it.complete = !it.complete; if (it.complete) it.complement = ""; }); } else setState(() {}); if (_autoSave) _manualSave(silent: true); })));
    if (lastItemCode != null) { bool isDisplayed = _displayItems.any((i) => !i.isSubheading && i.itemCode == lastItemCode); if (!isDisplayed) { final targetItem = _originalItems.firstWhere((i) => !i.isSubheading && i.itemCode == lastItemCode); setState(() { _temporaryVisibleItem = targetItem; }); _applyFilterAndSort(); } WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(lastItemCode)); }
  }

  void _showResetConfirm() { _forgetFocus(); if (_originalItems.isEmpty) return; showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋"), content: const Text("모든 체크와 비고를 지우시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { setState(() { for (var i in _originalItems) { i.complete = false; i.complement = ""; i.process = ""; i.remarks = ""; } }); if (_autoSave) _manualSave(silent: true); Navigator.pop(ctx); }, child: const Text("예", style: TextStyle(color: Colors.red)))])); }

  void _reorderSubheading(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1; if (oldIndex == newIndex) return; List<ItemModel> subheads = _originalItems.where((i) => i.isSubheading).toList(); if (oldIndex < 0 || oldIndex >= subheads.length) return; final targetSub = subheads[oldIndex]; int startIdx = _originalItems.indexOf(targetSub); int endIdx = startIdx + 1; while (endIdx < _originalItems.length && !_originalItems[endIdx].isSubheading) { endIdx++; } List<ItemModel> itemsToMove = _originalItems.sublist(startIdx, endIdx);
    setState(() { _originalItems.removeRange(startIdx, endIdx); List<ItemModel> remainingSubheads = _originalItems.where((i) => i.isSubheading).toList(); int insertIdx; if (newIndex >= remainingSubheads.length) { insertIdx = _originalItems.length; } else { insertIdx = _originalItems.indexOf(remainingSubheads[newIndex]); } _originalItems.insertAll(insertIdx, itemsToMove); });
    if (_autoSave) _manualSave(silent: true); _applyFilterAndSort();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: _isReorderMode ? const Text("순서 변경 모드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent)) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)]), 
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900], foregroundColor: Colors.white, 
        actions: _isReorderMode ? [
          TextButton(onPressed: () { setState(() { _originalItems = List.from(_preReorderItems); _isReorderMode = false; }); _applyFilterAndSort(); }, child: const Text("취소", style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () => setState(() => _isReorderMode = false), child: const Text("완료", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
        ] : _isEditMode ? [
          TextButton(onPressed: () { setState(() { _isSubheadingViewMode = !_isSubheadingViewMode; }); _applyFilterAndSort(); }, child: Text(_isSubheadingViewMode ? "전체보기" : "부분제목만", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _deleteSelectedRows, icon: const Icon(Icons.delete_forever, color: Colors.redAccent), label: Text("확인(${_selectedIndices.length})", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: () => setState(() { _isEditMode = false; _selectedIndices.clear(); }), child: const Text("취소", style: TextStyle(color: Colors.white))),
        ] : [
          if (_isSorted || _selectedSections.isNotEmpty || _showUnfinishedOnly || _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty || _quantitySearchQuery.isNotEmpty || _isSubheadingViewMode || _noFilterMode != 0 || _searchQuery.isNotEmpty || _columnFilters.values.any((s) => s.isNotEmpty)) 
            TextButton(onPressed: _resetSort, child: const Text("필터리셋", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _handleRefresh, child: const Text("새로고침", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _handleClose, child: const Text("닫기", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red)),
        ]
      ),
      body: SafeArea(child: Listener(onPointerDown: (_) { _clearHighlight(); _forgetFocus(); if (_temporaryVisibleItem != null) { setState(() { _temporaryVisibleItem = null; }); _applyFilterAndSort(); } }, behavior: HitTestBehavior.translucent, child: Column(children: [
        if (!_isEditMode && !_isReorderMode) Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [
          _topBtn("설정", _openSettings), const SizedBox(width: 4), _topBtn("엑셀선택", () => _pickSource('file')), const SizedBox(width: 4), _topBtn("PDF폴더", () => _pickSource('dir')), const SizedBox(width: 4),
          _topBtn("부분제목", () { setState(() { _isSubheadingViewMode = !_isSubheadingViewMode; }); _applyFilterAndSort(); }, bgColor: _isSubheadingViewMode ? Colors.blue : Colors.indigo[800]), const SizedBox(width: 4),
          _topBtn("행삭제", () => setState(() => _isEditMode = true), bgColor: Colors.orange[800]), const SizedBox(width: 4),
          if (_pdfFolderPath.startsWith("smb://")) ...[_topBtn("PDF동기화", _isSyncing ? null : _syncAllPdfs, bgColor: Colors.deepOrange[900]), const SizedBox(width: 4)],
          _topBtn("리셋", _showResetConfirm, bgColor: Colors.red[700]), const SizedBox(width: 4), _topBtn("저장", () { _forgetFocus(); _manualSave(); }, bgColor: Colors.green[700]),
        ])),
        if (!_isReorderMode) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [
          Expanded(flex: 4, child: TextField(controller: _searchController, focusNode: _searchFocusNode, decoration: InputDecoration(hintText: "품목코드 검색", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: EdgeInsets.zero, prefixIcon: const Icon(Icons.search), suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchQuery = ""; _applyFilterAndSort(); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollController.jumpTo(_preSearchScrollOffset)); }); }) : null), onChanged: (v) { if (_searchQuery.isEmpty && v.isNotEmpty) _preSearchScrollOffset = _scrollController.offset; setState(() => _searchQuery = v); _applyFilterAndSort(); if (v.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollController.jumpTo(_preSearchScrollOffset)); })),
          Expanded(flex: 6, child: _buildSummaryWidget(isDark)),
        ])),
        if (!_isReorderMode) _buildHeader(isDark),
        Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _isReorderMode ? ReorderableListView(onReorder: _reorderSubheading, children: _originalItems.where((i) => i.isSubheading).map((item) => ListTile(key: ValueKey("reorder-${item.itemCode}"), title: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: const Icon(Icons.drag_handle), tileColor: isDark ? Colors.white10 : Colors.grey[200])).toList()) : ListView.builder(controller: _scrollController, itemCount: _displayItems.length, itemBuilder: (ctx, idx) {
          final item = _displayItems[idx];
          if (item.isSubheading) {
            bool isSectionSel = _selectedSections.contains(item.itemCode);
            return GestureDetector(
              onTap: () {
                if (_isEditMode) { _toggleSectionSelection(item.itemCode); } 
                else if (_isSubheadingViewMode) { if (item.realIndex != -1) { setState(() { _selectedSections = {item.itemCode}; _isSubheadingViewMode = false; }); _applyFilterAndSort(); } else setState(() => _isSubheadingViewMode = false); } 
                else { setState(() { if (_selectedSections.contains(item.itemCode)) _selectedSections.remove(item.itemCode); else _selectedSections.add(item.itemCode); }); _applyFilterAndSort(); }
              }, 
              child: Container(
                height: _subheadingHeight, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.centerLeft, 
                color: _selectedSections.contains(item.itemCode) ? Colors.blueGrey : (isDark ? Colors.white10 : Colors.grey[300]), 
                child: Row(children: [
                  // ❗ 핵심: 오직 '부분제목 모드'이면서 '편집모드가 아닐 때'만 체크박스 노출
                  if (_isSubheadingViewMode && !_isEditMode) Checkbox(value: isSectionSel, onChanged: (v) { setState(() { if (v!) _selectedSections.add(item.itemCode); else _selectedSections.remove(item.itemCode); }); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                  Expanded(child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))), 
                  if (_isEditMode) Icon(_isSectionSelected(item.itemCode) ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20),
                  // ❗ 핵심: 오직 '부분제목 모드'이면서 '편집모드가 아닐 때'만 순서변경 아이콘 노출
                  if (_isSubheadingViewMode && !_isEditMode) IconButton(icon: const Icon(Icons.reorder, size: 20, color: Colors.blue), onPressed: () => setState(() { _preReorderItems = List.from(_originalItems); _isReorderMode = true; }), tooltip: "순서 변경"),
                ])
              )
            );
          }
          return _buildDataRow(item, isDark);
        })),
        if (_isSubheadingViewMode && _selectedSections.isNotEmpty) Container(color: isDark ? Colors.blueGrey[900] : Colors.blueGrey[100], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [
            Text("선택됨: ${_selectedSections.length}개", style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(),
            TextButton(onPressed: () { setState(() { _selectedSections.clear(); _isSubheadingViewMode = false; }); _applyFilterAndSort(); }, child: const Text("모두보기", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
            TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("모두 해제")),
            TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("취소", style: TextStyle(color: Colors.red))), const SizedBox(width: 8),
            ElevatedButton(onPressed: () { setState(() => _isSubheadingViewMode = false); _applyFilterAndSort(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), child: const Text("선택 항목 보기")),
          ])),
        if (_isSyncing) const LinearProgressIndicator(minHeight: 2, color: Colors.orange),
        Offstage(child: TextField(focusNode: _dummyFocusNode, readOnly: true)),
      ]))),
    );
  }

  Widget _buildHeader(bool isDark) { return Container(color: isDark ? Colors.grey[900] : Colors.grey[800], height: 40, child: Row(children: [if (_isEditMode) const SizedBox(width: 35), _headerBtn("No", "no", 35), Expanded(flex: 5, child: _headerBtn("품목코드", "itemCode", null)), _headerBtn("수량", "quantity", 40), _headerBtn("완료", "complete", 50), _headerBtn("보완", "complement", 50), _headerBtn("공정", "process", 50), Expanded(flex: 3, child: _headerBtn("비고", "remarks", null))])); }
  Widget _headerBtn(String label, String? colKey, double? width) { bool isTarget = colKey != null && _currentSortCol == colKey; bool isNoFilt = colKey == 'no' && _noFilterMode != 0; String dLabel = (colKey == 'no' && _noFilterMode == 2) ? "-No" : label; bool isFiltActive = false; if (colKey != null && ['complete', 'complement', 'process', 'quantity'].contains(colKey)) isFiltActive = _columnFilters[colKey]!.isNotEmpty || (colKey == 'quantity' && _quantitySearchQuery.isNotEmpty); else if (colKey == 'remarks') isFiltActive = _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty; return InkWell(onTap: colKey == null ? null : () => _sortBy(colKey), child: Container(width: width, alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: Text(dLabel, style: TextStyle(color: (isNoFilt || isFiltActive) ? Colors.yellow : Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)), if (isTarget) Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18)]))); }
  Widget _buildDataRow(ItemModel item, bool isDark) { bool isSel = _selectedIndices.contains(item.realIndex); bool isHigh = item.realIndex == _highlightedRealIndex; return GestureDetector(onTap: _isEditMode ? () { setState(() { if (isSel) _selectedIndices.remove(item.realIndex); else _selectedIndices.add(item.realIndex); }); } : null, behavior: HitTestBehavior.opaque, child: Container(decoration: BoxDecoration(color: isSel ? Colors.blue.withOpacity(0.1) : (item.complete ? (isDark ? Colors.green.withOpacity(0.1) : Colors.green[50]) : null), border: isHigh ? Border.all(color: Colors.blue, width: 2) : Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))), height: 45, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (_isEditMode) Container(width: 35, alignment: Alignment.center, child: Icon(isSel ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20)), SizedBox(width: 35, child: Center(child: Text(item.displayNo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))), Expanded(flex: 5, child: InkWell(onTap: () => _handleItemClick(item), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(item.itemCode, style: TextStyle(fontSize: 13, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold)))))), SizedBox(width: 40, child: Center(child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))), _cellCheck(item.complete, isDark, () { setState(() { item.complete = !item.complete; if (item.complete) item.complement = ""; }); if (_autoSave) _manualSave(silent: true); }), _cellComplement(item.complement, isDark, () => _showComplementDialog(item)), _cellProcess(item.process, isDark, () => _showProcessDialog(item)), Expanded(flex: 3, child: _RemarksCell(item: item, onSave: () { if (_autoSave) _manualSave(silent: true); }, onForgetFocus: _forgetFocus))]))); }
  Widget _cellCheck(bool val, bool isDark, VoidCallback onTap) { return InkWell(onTap: onTap, child: Container(width: 50, alignment: Alignment.center, color: val ? Colors.green.withOpacity(0.3) : null, child: val ? const Icon(Icons.check, size: 20, color: Colors.green) : null)); }
  Widget _cellComplement(String txt, bool isDark, VoidCallback onTap) { if (txt.isEmpty) return InkWell(onTap: onTap, child: const SizedBox(width: 50)); Color baseColor = (txt == "부족") ? Colors.orange : Colors.red; return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: BoxDecoration(color: baseColor.withOpacity(0.15), border: Border(left: BorderSide(color: baseColor, width: 4))), alignment: Alignment.center, child: FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))))); }
  Widget _cellProcess(String txt, bool isDark, VoidCallback onTap) { int? colorVal = txt.isNotEmpty ? _processColors[txt] : null; Color baseColor; if (colorVal != null) { baseColor = Color(colorVal); } else { if (txt == "완료") baseColor = Colors.purple; else if (txt == "보류") baseColor = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(txt)) baseColor = Colors.orange; else baseColor = Colors.blueGrey; } return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: txt.isEmpty ? const BoxDecoration(color: Colors.transparent) : BoxDecoration(color: baseColor.withOpacity(0.15), border: Border(left: BorderSide(color: baseColor, width: 4))), alignment: Alignment.center, child: txt.isNotEmpty ? FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87))) : null)); }
  void _showError(String t, String m) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(t), content: Text(m), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))])); }
  void _showSnackBar(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(m)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating)); }
  Future<void> _manualSave({bool silent = false}) async { if (_excelPath.isNotEmpty) { bool ok = await _excelService.saveExcel(_excelPath, _originalItems); if (ok && !silent) _showSnackBar("저장 완료"); } }
  int _compareDisplayNo(String a, String b) { List<String> pa = a.split('-'); List<String> pb = b.split('-'); int ma = int.tryParse(pa[0]) ?? 0; int mb = int.tryParse(pb[0]) ?? 0; if (ma != mb) return ma.compareTo(mb); int sa = (pa.length > 1) ? (int.tryParse(pa[1]) ?? 0) : 0; int sb = (pb.length > 1) ? (int.tryParse(pb[1]) ?? 0) : 0; return sa.compareTo(sb); }
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
