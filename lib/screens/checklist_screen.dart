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
  bool _isLoading = false;
  bool _isSorted = false;
  bool _isSyncing = false;
  double _scannerZoom = 0.0; 

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
  bool _isSelectionFiltered = false; 
  final Set<int> _selectedIndices = {}; 
  bool _isSelecting = false; 
  bool _isScrollingArea = false; 
  Timer? _scrollTimer; 
  final ScrollController _scrollController = ScrollController();
  int? _highlightedRealIndex;
  String? _trackedItemCode; 
  final double _subheadingHeight = 80.0; 
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
      if (_scrollController.hasClients) { _scrollController.jumpTo(targetOffset); }
      if (mounted) { setState(() { _highlightedRealIndex = foundRealIndex; }); }
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
    await prefs.setDouble('scannerZoom', _scannerZoom);
    await prefs.setStringList('processList', _processList);
    await prefs.setString('processColors', jsonEncode(_processColors));
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
          _isSorted = false; _currentSortCol = ""; _searchController.clear(); _searchQuery = ""; _showUnfinishedOnly = false; _selectedSections.clear(); _noFilterMode = 0; _remarksFilterQuery = ""; _remarksExcludeQuery = ""; _remarksIncludeLogic = "AND"; _remarksExcludeLogic = "OR"; _quantitySearchQuery = ""; _isSubheadingViewMode = false; _columnFilters.forEach((key, value) => value.clear());
        }
        _isEditMode = false; _isReorderMode = false; _selectedIndices.clear(); _temporaryVisibleItem = null;
      });
      if (keepFilters) _applyFilterAndSort(); else _saveSettings();
      _saveLastDir(path);
    } catch (e) { _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다."); } finally { setState(() => _isLoading = false); }
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
      if (results.isEmpty) results.add(ItemModel(realIndex: -1, no: "", displayNo: "", itemCode: "부분제목 없음", quantity: "", isSubheading: true));
      setState(() { _displayItems = results; });
      _saveSettings();
      return;
    }
    String? currentHeader; Map<String, List<ItemModel>> sectionMap = {}; List<String> headerOrder = [];
    for (var item in _originalItems) {
      if (item.isSubheading) { currentHeader = item.itemCode; sectionMap[currentHeader] = []; headerOrder.add(currentHeader); }
      else {
        if (currentHeader != null) sectionMap[currentHeader]!.add(item);
        else { if (!sectionMap.containsKey("ROOT")) { sectionMap["ROOT"] = []; headerOrder.insert(0, "ROOT"); } sectionMap["ROOT"]!.add(item); }
      }
    }
    for (var header in headerOrder) {
      if (_selectedSections.isNotEmpty && !_selectedSections.contains(header)) continue;
      List<ItemModel> sectionItems = List.from(sectionMap[header]!);
      if (_searchQuery.isNotEmpty) { final q = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty); sectionItems = sectionItems.where((it) { final t = it.itemCode.toLowerCase(); return q.every((p) => t.contains(p)); }).toList(); }
      _columnFilters.forEach((col, sel) {
        if (sel.isNotEmpty || (col == 'quantity' && _quantitySearchQuery.isNotEmpty)) {
          sectionItems = sectionItems.where((it) {
            String v = ""; if (col == 'complete') v = it.complete ? "완료" : "미완료"; else if (col == 'complement') v = it.complement.isEmpty ? "(빈칸)" : it.complement; else if (col == 'process') v = it.process.isEmpty ? "(빈칸)" : it.process; else if (col == 'quantity') v = it.quantity;
            bool s = sel.contains(v); if (col == 'quantity' && _quantitySearchQuery.isNotEmpty) { final q = _quantitySearchQuery.split(' ').where((p) => p.isNotEmpty); s = s || q.any((p) => v == p); } return s;
          }).toList();
        }
      });
      if (_remarksFilterQuery.isNotEmpty) { final q = _remarksFilterQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty); sectionItems = sectionItems.where((it) { final t = it.remarks.toLowerCase(); return _remarksIncludeLogic == "AND" ? q.every((p) => t.contains(p)) : q.any((p) => t.contains(p)); }).toList(); }
      if (_remarksExcludeQuery.isNotEmpty) { final q = _remarksExcludeQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty); sectionItems = sectionItems.where((it) { final t = it.remarks.toLowerCase(); bool e = _remarksExcludeLogic == "AND" ? q.every((p) => t.contains(p)) : q.any((p) => t.contains(p)); return !e; }).toList(); }
      if (_showUnfinishedOnly) sectionItems = sectionItems.where((it) => !it.complete).toList();
      if (_isSelectionFiltered) sectionItems = sectionItems.where((it) => _selectedIndices.contains(it.realIndex)).toList();
      if (_noFilterMode == 1) sectionItems = sectionItems.where((it) => it.no.isNotEmpty).toList();
      else if (_noFilterMode == 2) sectionItems = sectionItems.where((it) { if (it.displayNo.contains('-')) return true; if (it.no.isNotEmpty) return !_originalItems.any((o) => !o.isSubheading && o.displayNo.startsWith("${it.no}-")); return false; }).toList();
      if (_temporaryVisibleItem != null && !_temporaryVisibleItem!.isSubheading) {
        String tH = "ROOT"; String? temp; for (var i in _originalItems) { if (i.isSubheading) temp = i.itemCode; if (i == _temporaryVisibleItem) { tH = temp ?? "ROOT"; break; } }
        if (header == tH) { if (!sectionItems.any((it) => it.realIndex == _temporaryVisibleItem!.realIndex)) { sectionItems.add(_temporaryVisibleItem!); sectionItems.sort((a, b) => a.realIndex.compareTo(b.realIndex)); } }
      }
      if (sectionItems.isNotEmpty) { if (header != "ROOT") results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header)); results.addAll(sectionItems); }
      else if (_selectedSections.contains(header)) results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header));
    }
    if (_isSorted && _currentSortCol.isNotEmpty) {
      results = results.where((i) => !i.isSubheading).toList();
      results.sort((a, b) { int cmp = 0; switch (_currentSortCol) { case 'no': cmp = _compareDisplayNo(a.displayNo, b.displayNo); break; case 'itemCode': cmp = a.itemCode.compareTo(b.itemCode); break; case 'quantity': cmp = (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0); break; case 'complete': cmp = (a.complete ? 1 : 0).compareTo(b.complete ? 1 : 0); break; case 'complement': cmp = a.complement.compareTo(b.complement); break; case 'process': cmp = a.process.compareTo(b.process); break; case 'remarks': cmp = a.remarks.compareTo(b.remarks); break; } return _isAscending ? cmp : -cmp; });
    }
    setState(() { _displayItems = results; });
    if (_trackedItemCode != null) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _trackedItemCode != null) { if (_displayItems.any((i) => !i.isSubheading && i.itemCode == _trackedItemCode)) _scrollToItem(_trackedItemCode!); } }); }
    _saveSettings();
  }

  void _resetSort() {
    _forgetFocus(); setState(() {
      _isSorted = false; _currentSortCol = ""; _remarksFilterQuery = ""; _remarksExcludeQuery = ""; _quantitySearchQuery = ""; _remarksIncludeLogic = "AND"; _remarksExcludeLogic = "OR"; _noFilterMode = 0; _temporaryVisibleItem = null; _columnFilters.forEach((k, v) => v.clear()); _showUnfinishedOnly = false; _selectedSections.clear(); _isSubheadingViewMode = false; _isReorderMode = false; _searchQuery = ""; _searchController.clear(); _isSelectionFiltered = false; _selectedIndices.clear();
    });
    _applyFilterAndSort();
  }

  void _sortBy(String col) {
    _forgetFocus(); if (col == 'itemCode') { setState(() { if (_currentSortCol == col) { if (_isAscending) _isAscending = false; else { _isSorted = false; _currentSortCol = ""; } } else { _currentSortCol = col; _isAscending = true; _isSorted = true; } }); _applyFilterAndSort(); return; }
    if (col == 'no') { setState(() => _noFilterMode = (_noFilterMode + 1) % 3); _applyFilterAndSort(); return; }
    _showFilterDialog(col);
  }

  Set<String> _getValidOptionsForColumn(String col) {
    Set<String> validSet = {};
    for (var item in _originalItems) {
      if (item.isSubheading) continue;
      if (_selectedSections.isNotEmpty) { String? t; for(var i in _originalItems) { if(i.isSubheading) t = i.itemCode; if(i == item) break; } if (!_selectedSections.contains(t)) continue; }
      if (_searchQuery.isNotEmpty) { final q = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty); if (!q.every((p) => item.itemCode.toLowerCase().contains(p))) continue; }
      if (_showUnfinishedOnly && item.complete) continue;
      if (_noFilterMode == 1 && item.no.isEmpty) continue;
      if (_noFilterMode == 2) { if (!item.displayNo.contains('-')) { if (item.no.isNotEmpty) { if (_originalItems.any((o) => !o.isSubheading && o.displayNo.startsWith("${item.no}-"))) continue; } else continue; } }
      bool pass = true; _columnFilters.forEach((c, sel) {
        if (c == col) return; if (sel.isNotEmpty || (c == 'quantity' && _quantitySearchQuery.isNotEmpty)) {
          String v = ""; if (c == 'complete') v = item.complete ? "완료" : "미완료"; else if (c == 'complement') v = item.complement.isEmpty ? "(빈칸)" : item.complement; else if (c == 'process') v = item.process.isEmpty ? "(빈칸)" : item.process; else if (c == 'quantity') v = item.quantity;
          bool s = sel.contains(v); if (c == 'quantity' && _quantitySearchQuery.isNotEmpty) { final q = _quantitySearchQuery.split(' ').where((p) => p.isNotEmpty); s = s || q.any((p) => v == p); } if (!s) pass = false;
        }
      });
      if (!pass) continue;
      String val = ""; if (col == 'complete') val = item.complete ? "완료" : "미완료"; else if (col == 'complement') val = item.complement.isEmpty ? "(빈칸)" : item.complement; else if (col == 'process') val = item.process.isEmpty ? "(빈칸)" : item.process; else if (col == 'quantity') val = item.quantity;
      validSet.add(val);
    }
    return validSet;
  }

  void _showFilterDialog(String col) {
    List<String> options = []; String title = ""; Set<String> validOptions = _getValidOptionsForColumn(col);
    if (col == 'complete') { options = ["완료", "미완료"]; title = "완료 설정"; }
    else if (col == 'complement') { options = ["부족", "재작업", "(빈칸)"]; title = "보완 설정"; }
    else if (col == 'process') { List<String> f = []; if (validOptions.contains("(빈칸)")) f.add("(빈칸)"); List<String> b = List.from(_processList); b.remove("완료"); for (var p in b) { if (validOptions.contains(p)) f.add(p); } List<String> e = validOptions.where((o) => o != "(빈칸)" && o != "완료" && !_processList.contains(o)).toList(); e.sort(); f.addAll(e); if (validOptions.contains("완료")) f.add("완료"); options = f; title = "공정 설정"; }
    else if (col == 'quantity') { options = validOptions.toList(); options.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0)); title = "수량 설정"; }
    else if (col == 'remarks') { title = "비고 설정"; }
    bool srt = _isSorted && _currentSortCol == col; bool asc = _isAscending; Set<String> filt = Set.from(_columnFilters[col] ?? {});
    final incC = TextEditingController(text: _remarksFilterQuery); final excC = TextEditingController(text: _remarksExcludeQuery); final qtyC = TextEditingController(text: _quantitySearchQuery);
    String incL = _remarksIncludeLogic; String excL = _remarksExcludeLogic;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (context, setModal) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("정렬", style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<bool?>(title: const Text("오름차순"), value: true, groupValue: srt ? asc : null, onChanged: (v) => setModal(() { srt = true; asc = true; }), contentPadding: EdgeInsets.zero, dense: true),
        RadioListTile<bool?>(title: const Text("내림차순"), value: false, groupValue: srt ? asc : null, onChanged: (v) => setModal(() { srt = true; asc = false; }), contentPadding: EdgeInsets.zero, dense: true),
        RadioListTile<bool?>(title: const Text("정렬 안함"), value: null, groupValue: srt ? asc : null, onChanged: (v) => setModal(() { srt = false; }), contentPadding: EdgeInsets.zero, dense: true),
        if (col != 'itemCode') ...[
          const Divider(), if (col == 'remarks') ...[
            const Text("포함 필터", style: TextStyle(fontWeight: FontWeight.bold)), TextField(controller: incC), Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: incL, onChanged: (v) => setModal(() => incL = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: incL, onChanged: (v) => setModal(() => incL = v!)), const Text("OR")]),
            const SizedBox(height: 10), const Text("제외 필터", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)), TextField(controller: excC), Row(children: [const Text("로직: "), Radio<String>(value: "AND", groupValue: excL, onChanged: (v) => setModal(() => excL = v!)), const Text("AND"), Radio<String>(value: "OR", groupValue: excL, onChanged: (v) => setModal(() => excL = v!)), const Text("OR")]),
          ] else ...[
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => setModal(() => filt.addAll(options.where((o) => col == 'process' || col == 'quantity' || validOptions.contains(o)))), child: const Text("전체 선택", style: TextStyle(fontSize: 12)))), const SizedBox(width: 8), Expanded(child: OutlinedButton(onPressed: () => setModal(() => filt.clear()), child: const Text("전체 해제", style: TextStyle(fontSize: 12))))]),
            const SizedBox(height: 10), if (col == 'quantity') ...[const Text("수량 직접 입력", style: TextStyle(fontWeight: FontWeight.bold)), TextField(controller: qtyC, keyboardType: TextInputType.number), const SizedBox(height: 15)],
            const Text("항목 선택", style: TextStyle(fontWeight: FontWeight.bold)), _buildFilterGrid(options, filt, col, setModal, validOptions: (col == 'complete' || col == 'complement') ? validOptions : null),
          ],
        ],
        if (['complete', 'process', 'complement'].contains(col)) ...[ const Divider(height: 30), SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); _resetFilteredItemsColumn(col); }, icon: const Icon(Icons.restart_alt, size: 18), label: const Text("현재 리스트 항목 리셋", style: TextStyle(fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red[800], side: BorderSide(color: Colors.red[200]!)))) ],
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () { setState(() { _isSorted = srt; if (srt) { _currentSortCol = col; _isAscending = asc; } else if (_currentSortCol == col) _currentSortCol = ""; if (_columnFilters.containsKey(col)) _columnFilters[col] = filt; if (col == 'remarks') { _remarksFilterQuery = incC.text; _remarksExcludeQuery = excC.text; _remarksIncludeLogic = incL; _remarksExcludeLogic = excL; } if (col == 'quantity') _quantitySearchQuery = qtyC.text; }); _applyFilterAndSort(); Navigator.pop(ctx); }, child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold)))],
    )));
  }

  Widget _buildFilterGrid(List<String> options, Set<String> filt, String col, StateSetter setModal, {Set<String>? validOptions}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (ctx, constraints) {
      double w = col == 'complete' ? constraints.maxWidth / 2 : constraints.maxWidth / 3;
      return Wrap(children: options.map((o) {
        bool valid = validOptions == null || validOptions.contains(o); bool sel = filt.contains(o);
        return SizedBox(width: w, child: InkWell(onTap: !valid ? null : () => setModal(() { if (col == 'complete') { if (sel) filt.clear(); else { filt.clear(); filt.add(o); } } else { if (sel) filt.remove(o); else filt.add(o); } }), child: Opacity(opacity: valid ? 1.0 : 0.3, child: Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: sel, onChanged: !valid ? null : (v) => setModal(() { if (col == 'complete') { if (sel && !v!) filt.clear(); else { filt.clear(); if (v!) filt.add(o); } } else { if (v!) filt.add(o); else filt.remove(o); } }), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), if (col == 'process' && o != "(빈칸)") Container(width: 4, height: 16, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: (() { int? c = _processColors[o]; if (c != null) return Color(c); if (o == "완료") return Colors.purple; if (o == "보류") return Colors.red; if (["용접", "도장", "도금", "인쇄"].contains(o)) return Colors.orange; return Colors.blueGrey; })(), borderRadius: BorderRadius.circular(2))), Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(o, style: TextStyle(fontSize: 12, fontWeight: col == 'process' ? FontWeight.bold : FontWeight.normal, color: isDark ? Colors.white : Colors.black87))))]))));
      }).toList());
    });
  }

  Future<void> _pickSource(String mode) async {
    _forgetFocus(); showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.phone_android), title: const Text("내 휴대폰"), onTap: () { Navigator.pop(ctx); _openCustomPicker(mode); }), ListTile(leading: const Icon(Icons.computer), title: const Text("PC 공유폴더 (SMB)"), onTap: () { Navigator.pop(ctx); _openSmbShares(mode); }), const SizedBox(height: 10)])));
  }

  void _createNewFile(String currentPath) {
    final now = DateTime.now(); final date = "${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}"; String name = "체크시트_$date"; int c = 1; while (File("$currentPath/$name.xlsx").existsSync()) { name = "체크시트_$date($c)"; c++; }
    final ctrl = TextEditingController(text: name); ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("새 엑셀 파일 생성"), content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "파일명 입력", suffixText: ".xlsx"), autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () async { String n = ctrl.text.trim(); if (n.isEmpty) return; if (!n.endsWith(".xlsx")) n += ".xlsx"; String p = "$currentPath/$n"; if (File(p).existsSync() && n != "$name.xlsx") { _showError("생성 실패", "이미 동일한 이름의 파일이 존재합니다."); return; } bool ok = await _excelService.createEmptyExcel(p); if (ok) { Navigator.pop(ctx); if (mounted) Navigator.pop(context); _loadExcelData(p); _showSnackBar("새 파일이 생성되었습니다."); } else _showError("오류", "파일 생성에 실패했습니다."); }, child: const Text("생성", style: TextStyle(fontWeight: FontWeight.bold)))]));
  }

  void _openSettings() async {
    _forgetFocus(); final prefs = await SharedPreferences.getInstance();
    final ipC = TextEditingController(text: prefs.getString('smbIp')); final userC = TextEditingController(text: prefs.getString('smbUser')); final passC = TextEditingController(text: prefs.getString('smbPass'));
    final newC = TextEditingController(); bool obs = true; final palette = [Colors.blueGrey, Colors.blue, Colors.indigo, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink, Colors.purple, Colors.deepPurple];
    showDialog(context: context, builder: (ctx) => DefaultTabController(length: 2, child: StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: const TabBar(labelColor: Colors.blue, unselectedLabelColor: Colors.grey, tabs: [Tab(icon: Icon(Icons.dns), text: "연결 설정"), Tab(icon: Icon(Icons.settings_suggest), text: "공정 관리")]),
      content: SizedBox(width: double.maxFinite, height: 450, child: TabBarView(children: [
        SingleChildScrollView(child: Column(children: [
          const SizedBox(height: 20), TextField(controller: ipC, decoration: const InputDecoration(labelText: "IP 주소", border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: userC, decoration: const InputDecoration(labelText: "ID", border: OutlineInputBorder())), const SizedBox(height: 10), TextField(controller: passC, obscureText: obs, decoration: InputDecoration(labelText: "PW", border: const OutlineInputBorder(), suffixIcon: IconButton(icon: Icon(obs ? Icons.visibility : Icons.visibility_off), onPressed: () => setD(() => obs = !obs)))), const SizedBox(height: 20), const Align(alignment: Alignment.centerLeft, child: Text("스캐너 기본 배율 (줌)", style: TextStyle(fontWeight: FontWeight.bold))), const SizedBox(height: 5),
          Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blueGrey.withOpacity(0.2))), child: Column(children: [Row(children: [const Icon(Icons.zoom_in, size: 20, color: Colors.blue), const SizedBox(width: 10), Expanded(child: Slider(value: _scannerZoom, min: 0.0, max: 1.0, onChanged: (v) => setD(() => _scannerZoom = v))), Text(_scannerZoom.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))]), const SizedBox(height: 5), Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_zoomQuickBtnDialog("0.0", 0.0, setD), _zoomQuickBtnDialog("0.1", 0.1, setD), _zoomQuickBtnDialog("0.2", 0.2, setD), _zoomQuickBtnDialog("0.3", 0.3, setD), _zoomQuickBtnDialog("0.4", 0.4, setD), _zoomQuickBtnDialog("0.5", 0.5, setD)]), const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_zoomQuickBtnDialog("0.6", 0.6, setD), _zoomQuickBtnDialog("0.7", 0.7, setD), _zoomQuickBtnDialog("0.8", 0.8, setD), _zoomQuickBtnDialog("0.9", 0.9, setD), _zoomQuickBtnDialog("1.0", 1.0, setD), const SizedBox(width: 40)])])])) , const SizedBox(height: 20), ElevatedButton.icon(onPressed: () async { String? err = await _smbService.testConnection(ipC.text, userC.text, passC.text); if (err == null) { List<String> sh = await _smbService.listShares(); _showError("성공", "✅ 접속 성공!\n\n[공유 목록]\n${sh.join('\n')}"); } else _showError("오류", "접속 실패: $err"); }, icon: const Icon(Icons.check_circle_outline), label: const Text("접속 테스트"))
        ])),
        Column(children: [
          Expanded(child: ReorderableListView(onReorder: (o, n) { setD(() { if (n > o) n -= 1; if (_processList[o] == "완료" || n >= _processList.length) return; final String item = _processList.removeAt(o); _processList.insert(n, item); }); }, buildDefaultDragHandles: false, children: [ for (int i = 0; i < _processList.length; i++) ListTile(key: ValueKey(_processList[i] + i.toString()), dense: true, visualDensity: VisualDensity.compact, contentPadding: const EdgeInsets.symmetric(horizontal: 4), leading: Row(mainAxisSize: MainAxisSize.min, children: [ IconButton(icon: Icon(Icons.remove_circle_outline, color: _processList[i] == "완료" ? Colors.grey : Colors.red, size: 20), onPressed: _processList[i] == "완료" ? null : () { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("공정 삭제"), content: Text("'${_processList[i]}' 공정을 삭제하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () { setD(() => _processList.removeAt(i)); Navigator.pop(ctx); }, child: const Text("삭제", style: TextStyle(color: Colors.red)))])); }), (() { Color c; if (_processColors[_processList[i]] != null) c = Color(_processColors[_processList[i]]!); else { String p = _processList[i]; if (p == "완료") c = Colors.purple; else if (p == "보류") c = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) c = Colors.orange; else c = Colors.blueGrey; } return GestureDetector(onTap: () { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("${_processList[i]} 색상 선택"), content: Wrap(spacing: 8, runSpacing: 8, children: palette.map((color) => GestureDetector(onTap: () { setD(() => _processColors[_processList[i]] = color.value); Navigator.pop(ctx); }, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2))))).toList()))); }, child: Container(width: 20, height: 20, decoration: BoxDecoration(color: c, shape: BoxShape.circle))); })(), ]), title: Text(_processList[i], style: TextStyle(fontSize: 13, color: _processList[i] == "완료" ? Colors.purple : null, fontWeight: _processList[i] == "완료" ? FontWeight.bold : null)), trailing: _processList[i] == "완료" ? const SizedBox(width: 24) : ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, size: 20))) ])),
          const Divider(), Row(children: [Expanded(child: TextField(controller: newC, decoration: const InputDecoration(hintText: "공정명 추가", isDense: true))), IconButton(icon: const Icon(Icons.add_box, color: Colors.green, size: 30), onPressed: () { if (newC.text.isNotEmpty) { setD(() { int idx = _processList.indexOf("완료"); if (idx != -1) _processList.insert(idx, newC.text); else _processList.add(newC.text); newC.clear(); }); } }), IconButton(icon: const Icon(Icons.color_lens_outlined, color: Colors.orange, size: 30), onPressed: () { setD(() => _processColors.clear()); })])
        ])
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () async { await prefs.setString('smbIp', ipC.text); await prefs.setString('smbUser', userC.text); await prefs.setString('smbPass', passC.text); await prefs.setStringList('processList', _processList); await prefs.setString('processColors', jsonEncode(_processColors)); _smbService.setConfig(ipC.text, userC.text, passC.text); setState(() {}); Navigator.pop(ctx); }, child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold)))]
    ))));
  }

  void _openSmbShares(String mode) async {
    _forgetFocus(); setState(() => _isLoading = true);
    try { List<String> sh = await _smbService.listShares(); setState(() => _isLoading = false); if (!mounted) return; if (sh.isNotEmpty && sh[0].startsWith("ERROR:")) { _showError("탐색 실패", sh[0].replaceFirst("ERROR:", "").trim()); return; } showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("공유폴더 선택"), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: sh.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.folder_shared), title: Text(sh[i]), onTap: () { Navigator.pop(ctx); _showSmbFiles(sh[i], "", mode); })))) ); } catch (e) { setState(() => _isLoading = false); _showError("치명적 오류", "$e"); }
  }

  void _showSmbFiles(String share, String path, String mode) async {
    setState(() => _isLoading = true); List<Map<String, dynamic>> files = await _smbService.listFiles(share, path); setState(() => _isLoading = false); if (!mounted) return; List<Map<String, dynamic>> filt = files.where((f) { if (f['isDirectory'] as bool) return true; String n = (f['name'] as String).toLowerCase(); return mode == 'file' ? (n.endsWith('.xlsx') || n.endsWith('.xls')) : n.endsWith('.pdf'); }).toList();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("$share/$path"), content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [if (path != "") ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showSmbFiles(share, p.dirname(path) == "." ? "" : p.dirname(path), mode); }), Expanded(child: ListView.builder(itemCount: filt.length, itemBuilder: (c, i) { final f = filt[i]; bool isDir = f['isDirectory'] as bool; String n = f['name'] as String; return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description), title: Text(n), onTap: () { if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, "${path == "" ? "" : "$path/"}$n"); } else if (mode == 'file') { Navigator.pop(ctx); _downloadAndLoad(share, "${path == "" ? "" : "$path/"}$n"); } }); }))])), actions: [if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = "smb://$share/$path"); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소"))]));
  }

  Future<void> _downloadAndLoad(String share, String remotePath) async { setState(() => _isLoading = true); String local = "$_baseDownloadPath/CheckSheet/${p.basename(remotePath)}"; File? f = await _smbService.downloadFile(share, remotePath, local); setState(() => _isLoading = false); if (f != null) _loadExcelData(f.path); else _showError("오류", "다운로드 실패"); }

  Future<void> _syncAllPdfs() async {
    _forgetFocus(); if (_originalItems.isEmpty) return; List<ItemModel> targets = _originalItems.where((i) => !i.isSubheading).toList(); setState(() => _isSyncing = true);
    try { String sWR = _pdfFolderPath.replaceFirst("smb://", ""); if (sWR.endsWith("/")) sWR = sWR.substring(0, sWR.length - 1); int firstS = sWR.indexOf("/"); String share = firstS != -1 ? sWR.substring(0, firstS) : sWR; String fP = firstS != -1 ? sWR.substring(firstS + 1) : ""; const int bSize = 5; for (int i = 0; i < targets.length; i += bSize) { final chunk = targets.skip(i).take(bSize); await Future.wait(chunk.map((it) { String c = it.itemCode.trim(); String r = fP.isEmpty ? "$c.pdf" : "$fP/$c.pdf"; String l = "$_baseDownloadPath/CheckSheet/$c.pdf"; return _smbService.downloadFile(share, r, l); })); } _showSnackBar("✅ ${targets.length}개 동기화 완료!"); } catch (e) { debugPrint("Sync Error: $e"); } finally { setState(() => _isSyncing = false); }
  }

  Future<void> _openCustomPicker(String mode) async { _forgetFocus(); final prefs = await SharedPreferences.getInstance(); String start = prefs.getString('lastDir') ?? "$_baseDownloadPath/CheckSheet"; if (!Directory(start).existsSync()) start = _baseDownloadPath; _showFileBrowser(mode, start); }

  void _showFileBrowser(String mode, String initialPath) {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setM) { final dir = Directory(initialPath); List<FileSystemEntity> entities = []; try { entities = dir.listSync().where((e) { if (e is Directory) return true; return mode == 'file' ? (e.path.endsWith('.xlsx') || e.path.endsWith('.xls')) : e.path.endsWith('.pdf'); }).toList(); entities.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase())); } catch (_) {}
      return AlertDialog(title: Text(p.basename(initialPath)), content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [ ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); }), Expanded(child: ListView.builder(itemCount: entities.length, itemBuilder: (c, i) { final e = entities[i]; final isDir = e is Directory; return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue), title: Text(p.basename(e.path)), onTap: () { if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); } else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); } }); })) ])), actions: [ if (mode == 'file') TextButton(onPressed: () => _createNewFile(initialPath), child: const Text("새 파일 만들기", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold))), if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")) ]);
    }));
  }

  void _handleClose() { _forgetFocus(); if (_originalItems.isEmpty) return; showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("리스트 닫기"), content: const Text("현재 리스트를 닫으시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { setState(() { _originalItems = []; _displayItems = []; _currentFileName = "파일을 선택하세요"; _excelPath = ""; _isSorted = false; _currentSortCol = ""; _searchController.clear(); _searchQuery = ""; _showUnfinishedOnly = false; _selectedSections.clear(); }); _saveSettings(); Navigator.pop(ctx); _showSnackBar("리스트가 닫혔습니다."); }, child: const Text("예", style: TextStyle(color: Colors.red)))])); }
  void _handleRefresh() { _forgetFocus(); if (_excelPath.isEmpty) return; if (File(_excelPath).existsSync()) { _loadExcelData(_excelPath, keepFilters: true); _showSnackBar("🔄 리스트를 새로고침했습니다."); } }

  void _showCompleteTimeDialog(ItemModel item) {
    _forgetFocus(); String record = item.completeTime.isEmpty ? "기록 없음" : item.completeTime;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))), const SizedBox(height: 8), const Text("완료 입력 시간", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]), content: Text("입력시간 : $record", style: const TextStyle(fontSize: 16)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
  }

  void _resetFilteredItemsColumn(String col) {
    final filtered = _displayItems.where((i) => !i.isSubheading && i.realIndex != -1).toList(); if (filtered.isEmpty) return;
    String name = (col == 'complete') ? "완료" : (col == 'process' ? "공정" : "보완");
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text("리스트 항목 $name 리셋"), content: Text("현재 화면에 보이는 ${filtered.length}개 항목의 [$name] 항목을 리셋하시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () { setState(() { for (var it in filtered) { if (col == 'complete') { it.complete = false; it.completeTime = ""; it.complement = ""; it.complementTime = ""; } else if (col == 'process') { it.process = ""; it.processTime = ""; } else if (col == 'complement') { it.complement = ""; it.complementTime = ""; } } }); if (_autoSave) _manualSave(silent: true); Navigator.pop(ctx); _showSnackBar("$name 리셋 완료"); }, child: const Text("리셋 실행", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))]));
  }

  void _showComplementDialog(ItemModel item) {
    _forgetFocus(); String last = item.complementTime.isNotEmpty ? "입력시간 : ${item.complementTime}" : "입력시간 : 없음";
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))), const SizedBox(height: 8), Row(children: [const Text("보완 선택", style: TextStyle(fontWeight: FontWeight.bold)), if (item.complement.isNotEmpty) ...[const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: (item.complement == "부족") ? Colors.orange : Colors.red, borderRadius: BorderRadius.circular(4)), child: Text(item.complement, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))]]), const SizedBox(height: 4), Text(last, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.blueGrey))]), content: Column(mainAxisSize: MainAxisSize.min, children: [_dialogBtn("부족", Colors.orange, () { item.complement = "부족"; item.complete = false; item.complementTime = DateTime.now().toString().substring(0, 16); }), _dialogBtn("재작업", Colors.red, () { item.complement = "재작업"; item.complete = false; item.complementTime = DateTime.now().toString().substring(0, 16); }), const Divider(), _dialogBtn("지우기", Colors.grey, () { item.complement = ""; item.complementTime = ""; }), _dialogBtn("선택취소", Colors.blueGrey, () {})])));
  }

  void _showProcessDialog(ItemModel item) {
    _forgetFocus(); String last = item.processTime.isNotEmpty ? "입력시간 : ${item.processTime}" : "입력시간 : 없음";
    List<String> sorted = List.from(_processList); bool hasF = sorted.remove("완료"); if (hasF) sorted.add("완료");
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))), const SizedBox(height: 8), Row(children: [const Text("공정 선택", style: TextStyle(fontWeight: FontWeight.bold)), if (item.process.isNotEmpty) ...[const SizedBox(width: 10), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: (() { int? c = _processColors[item.process]; if (c != null) return Color(c); if (item.process == "완료") return Colors.purple; if (item.process == "보류") return Colors.red; return Colors.blueGrey; })(), borderRadius: BorderRadius.circular(4)), child: Text(item.process, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))]]), const SizedBox(height: 4), Text(last, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.blueGrey))]), content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 3, childAspectRatio: 2.0, mainAxisSpacing: 8, crossAxisSpacing: 8, children: sorted.map((p) { int? c = _processColors[p]; Color btnC; if (c != null) btnC = Color(c); else { if (p == "완료") btnC = Colors.purple; else if (p == "보류") btnC = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(p)) btnC = Colors.orange; else btnC = Colors.blueGrey[700]!; } return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: btnC, foregroundColor: Colors.white), onPressed: () { setState(() { item.process = p; item.processTime = DateTime.now().toString().substring(0, 16); }); if (_autoSave) _manualSave(silent: true); Navigator.pop(context); }, child: Text(p)); }).toList()), const Divider(), _dialogBtn("지우기", Colors.grey, () { item.process = ""; item.processTime = ""; }), _dialogBtn("선택취소", Colors.blueGrey, () {})])))));
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) { return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), onPressed: () { setState(onSelected); if (_autoSave) _manualSave(silent: true); Navigator.pop(context); }, child: Text(label))); }

  void _deleteSelectedRows() {
    if (_selectedIndices.isEmpty) return; final Set<int> finalD = Set.from(_selectedIndices);
    for (int sIdx in _selectedIndices) { try { final target = _originalItems.firstWhere((i) => i.realIndex == sIdx); if (target.isSubheading) { bool found = false; for (var it in _originalItems) { if (it.isSubheading) { if (it.realIndex == target.realIndex) found = true; else if (found) break; } else if (found) finalD.add(it.realIndex); } } } catch (_) {} }
    bool isSmb = _pdfFolderPath.startsWith("smb://"); bool delPdf = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => AlertDialog(title: const Text("행 삭제"), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text("선택한 섹션 및 하위 항목 포함 총 ${finalD.length}개를 삭제하시겠습니까?"), if (!isSmb) ...[const SizedBox(height: 15), Row(children: [Checkbox(value: delPdf, onChanged: (v) => setM(() => delPdf = v!)), const Expanded(child: Text("관련 로컬 PDF 파일도 함께 삭제", style: TextStyle(fontSize: 13, color: Colors.redAccent)))])]]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: () async { final List<String> pdfs = []; if (delPdf) { for (int dIdx in finalD) { try { final it = _originalItems.firstWhere((i) => i.realIndex == dIdx); if (!it.isSubheading && it.itemCode.isNotEmpty) pdfs.add(it.itemCode.trim()); } catch (_) {} } } int delCount = 0; if (delPdf && pdfs.isNotEmpty) { for (String code in pdfs) { final f = File("$_baseDownloadPath/CheckSheet/$code.pdf"); if (await f.exists()) { try { await f.delete(); delCount++; } catch (_) {} } } } setState(() { _originalItems.removeWhere((it) => finalD.contains(it.realIndex)); _isEditMode = false; _selectedIndices.clear(); }); _applyFilterAndSort(); Navigator.pop(ctx); String msg = "${finalD.length}개 항목 삭제됨"; if (delCount > 0) msg += " (PDF $delCount개 삭제)"; _showSnackBar(msg); if (_autoSave) _manualSave(silent: true); }, child: const Text("삭제", style: TextStyle(color: Colors.red)))])));
  }

  void _toggleSectionSelection(String headerTitle) { String? current; List<int> indices = []; for (var it in _originalItems) { if (it.isSubheading) { current = it.itemCode; if (current == headerTitle) indices.add(it.realIndex); } else if (current == headerTitle) indices.add(it.realIndex); } setState(() { bool all = indices.every((idx) => _selectedIndices.contains(idx)); if (all) { for (var idx in indices) _selectedIndices.remove(idx); } else _selectedIndices.addAll(indices); }); }
  bool _isSectionSelected(String header) { String? current; List<int> indices = []; for (var i in _originalItems) { if (i.isSubheading) current = i.itemCode; else if (current == header) indices.add(i.realIndex); } return indices.isNotEmpty && indices.every((idx) => _selectedIndices.contains(idx)); }

  Widget _buildSummaryWidget(bool isDark) {
    if (_originalItems.isEmpty) return const SizedBox.shrink();
    final dItems = _originalItems.where((i) => !i.isSubheading); int total = dItems.length; int comp = dItems.where((i) => i.complete).length;
    final fItems = _displayItems.where((i) => !i.isSubheading && i.realIndex != -1); int fTotal = fItems.length; int fComp = fItems.where((i) => i.complete).length;
    bool isF = total != fTotal || _showUnfinishedOnly || _columnFilters.values.any((s) => s.isNotEmpty) || _searchQuery.isNotEmpty;
    String totalS = "전체 $total / 완료 $comp / ${(total > 0 ? (comp / total * 100) : 0).toStringAsFixed(1)}%";
    String filterS = isF ? "필터 $fTotal / 완료 $fComp / ${(fTotal > 0 ? (fComp / fTotal * 100) : 0).toStringAsFixed(1)}%" : "";
    return InkWell(onTap: () { setState(() => _showUnfinishedOnly = !_showUnfinishedOnly); _applyFilterAndSort(); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [FittedBox(fit: BoxFit.scaleDown, child: Text("[$totalS]", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.blueGrey[800]))), if (isF) FittedBox(fit: BoxFit.scaleDown, child: Text("[$filterS]", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orangeAccent)))])));
  }
  Widget _topBtn(String label, VoidCallback? onTap, {Color? bgColor}) { return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(backgroundColor: bgColor ?? Colors.blueGrey[700], foregroundColor: Colors.white, minimumSize: const Size(0, 45), padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: FittedBox(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))))); }

  Future<void> _handleItemClick(ItemModel item) async {
    _forgetFocus(); if (_autoSave) _manualSave(silent: true); if (_pdfFolderPath.startsWith("smb://")) { setState(() => _isLoading = true); try { String sWR = _pdfFolderPath.replaceFirst("smb://", ""); int firstS = sWR.indexOf("/"); String share = firstS != -1 ? sWR.substring(0, firstS) : sWR; String fP = firstS != -1 ? sWR.substring(firstS + 1) : ""; String r = fP.isEmpty ? "${item.itemCode}.pdf" : "$fP/${item.itemCode}.pdf"; await _smbService.downloadFile(share, r, "$_baseDownloadPath/CheckSheet/${item.itemCode}.pdf"); } catch (_) {} finally { setState(() => _isLoading = false); } }
    if (!mounted) return; final String? lastCode = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(allItems: _originalItems.where((i) => !i.isSubheading).toList(), filteredItems: _displayItems.where((i) => !i.isSubheading && i.realIndex != -1).toList(), initialIndex: _originalItems.where((i) => !i.isSubheading).toList().indexOf(item), pdfFolderPath: _pdfFolderPath, smbService: _smbService, processList: _processList, processColors: _processColors, onStatusUpdate: (it, type) { if (type == 'complete') { setState(() { it.complete = !it.complete; if (it.complete) { it.completeTime = DateTime.now().toString().substring(0, 16); it.complement = ""; it.complementTime = ""; } else { it.completeTime = ""; } }); } else setState(() {}); if (_autoSave) _manualSave(silent: true); })));
    if (lastCode != null) { setState(() { _trackedItemCode = lastCode; }); if (!_displayItems.any((i) => !i.isSubheading && i.itemCode == lastCode)) { final target = _originalItems.firstWhere((i) => !i.isSubheading && i.itemCode == lastCode); setState(() { _temporaryVisibleItem = target; }); _applyFilterAndSort(); } WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(lastCode)); }
  }

  void _showResetConfirm() {
    _forgetFocus(); if (_originalItems.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋 범위 선택"), content: const Text("리셋할 범위를 선택해주세요."), actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), onPressed: () { Navigator.pop(ctx); _showResetOptions(isAll: true); }, child: const Text("전체 리셋")), const SizedBox(height: 8), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo[800], foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)), onPressed: () { Navigator.pop(ctx); _showSectionSelector(); }, child: const Text("부분제목별 리셋")), const Divider(height: 24), TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소", style: TextStyle(color: Colors.grey, fontSize: 16)))]))]));
  }

  void _showSectionSelector() {
    final subheads = _originalItems.where((i) => i.isSubheading).toList(); if (subheads.isEmpty) { _showSnackBar("리셋할 부분제목이 없습니다."); return; }
    final ScrollController sC = ScrollController();
    showDialog(context: context, builder: (ctx) { final bool dark = Theme.of(context).brightness == Brightness.dark; return AlertDialog(title: Row(children: [const Text("리셋할 부분제목 선택", style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text("${subheads.length}개", style: TextStyle(fontSize: 12, color: dark ? Colors.blue[200] : Colors.blue[700]))]), content: SizedBox(width: double.maxFinite, height: 450, child: Theme(data: Theme.of(ctx).copyWith(scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(dark ? Colors.blue[300]!.withOpacity(0.5) : Colors.blue[700]!.withOpacity(0.4)), thickness: WidgetStateProperty.all(6), radius: const Radius.circular(10))), child: Scrollbar(controller: sC, thumbVisibility: true, child: ListView.separated(controller: sC, shrinkWrap: true, itemCount: subheads.length, separatorBuilder: (c, i) => const Divider(height: 1), itemBuilder: (c, i) { final item = subheads[i]; int total = 0; int comp = 0; int startIdx = _originalItems.indexOf(item); if (startIdx != -1) { for (int j = startIdx + 1; j < _originalItems.length; j++) { if (_originalItems[j].isSubheading) break; total++; if (_originalItems[j].complete) comp++; } } double p = total > 0 ? (comp / total * 100) : 0; bool allD = total > 0 && total == comp; String rT = item.itemCode; List<String> parts = rT.split('_'); String l1 = parts.length > 3 ? parts.sublist(0, 3).join('_') : rT; String l2 = parts.length > 3 ? parts.sublist(3).join('_') : ""; return InkWell(onTap: () { Navigator.pop(ctx); _showResetOptions(isAll: false, subheadingItem: item); }, child: Container(height: 80, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: allD ? (dark ? Colors.green.withOpacity(0.1) : Colors.green[50]) : null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("[${(i + 1).toString().padLeft(2, '0')}]", style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.blue[300] : Colors.blue[800], fontSize: 13)), const SizedBox(width: 8), Expanded(child: SizedBox(height: 20, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(l1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))))]), Padding(padding: const EdgeInsets.only(left: 38), child: SizedBox(height: 20, width: double.infinity, child: l2.isNotEmpty ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(l2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))) : const SizedBox.shrink())), Padding(padding: const EdgeInsets.only(left: 38), child: Row(children: [Icon(Icons.list_alt, size: 14, color: dark ? Colors.grey[400] : Colors.grey[600]), const SizedBox(width: 4), Text("항목: $total개", style: TextStyle(fontSize: 12, color: dark ? Colors.grey[400] : Colors.grey[700])), const SizedBox(width: 12), Icon(Icons.check_circle_outline, size: 14, color: allD ? Colors.green : (dark ? Colors.grey[400] : Colors.grey[600])), const SizedBox(width: 4), Text("완료: $comp개 (${p.toStringAsFixed(1)}%)", style: TextStyle(fontSize: 12, color: allD ? Colors.green : (dark ? Colors.grey[400] : Colors.grey[700]), fontWeight: allD ? FontWeight.bold : FontWeight.normal)), if (allD) ...[const SizedBox(width: 8), const Text("🏆", style: TextStyle(fontSize: 12))]]))]))); } )))), actions: [TextButton(onPressed: () { sC.dispose(); Navigator.pop(ctx); }, child: const Text("취소", style: TextStyle(fontSize: 16)))]); }).then((_) => sC.dispose());
  }

  void _showResetOptions({required bool isAll, ItemModel? subheadingItem}) {
    bool rStatus = true; bool rRemarks = false; String t = isAll ? "전체" : "'${subheadingItem?.itemCode}' 섹션";
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setM) => AlertDialog(title: Text("$t 리셋 설정"), content: Column(mainAxisSize: MainAxisSize.min, children: [CheckboxListTile(title: const Text("체크상태 초기화"), subtitle: const Text("(완료, 보완, 공정 상태 삭제)"), value: rStatus, onChanged: (v) => setM(() => rStatus = v!)), CheckboxListTile(title: const Text("비고란 초기화"), subtitle: const Text("(입력된 메모 일괄 삭제)"), value: rRemarks, onChanged: (v) => setM(() => rRemarks = v!))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")), TextButton(onPressed: (!rStatus && !rRemarks) ? null : () { _executeReset(isAll: isAll, subheadingItem: subheadingItem, status: rStatus, remarks: rRemarks); Navigator.pop(ctx); }, child: const Text("리셋 실행", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)))])));
  }

  void _executeReset({required bool isAll, ItemModel? subheadingItem, required bool status, required bool remarks}) {
    setState(() { if (isAll) { for (var i in _originalItems) { if (i.isSubheading) continue; if (status) { i.complete = false; i.completeTime = ""; i.complement = ""; i.complementTime = ""; i.process = ""; i.processTime = ""; } if (remarks) i.remarks = ""; } } else if (subheadingItem != null) { int sIdx = _originalItems.indexOf(subheadingItem); if (sIdx != -1) { for (int i = sIdx + 1; i < _originalItems.length; i++) { if (_originalItems[i].isSubheading) break; if (status) { _originalItems[i].complete = false; _originalItems[i].completeTime = ""; _originalItems[i].complement = ""; _originalItems[i].complementTime = ""; _originalItems[i].process = ""; _originalItems[i].processTime = ""; } if (remarks) _originalItems[i].remarks = ""; } } } });
    _applyFilterAndSort(); if (_autoSave) _manualSave(silent: true); _showSnackBar("리셋이 완료되었습니다.");
  }

  void _reorderSubheading(int oldIdx, int newIdx) {
    if (newIdx > oldIdx) newIdx -= 1; if (oldIdx == newIdx) return; List<ItemModel> sub = _originalItems.where((i) => i.isSubheading).toList(); if (oldIdx < 0 || oldIdx >= sub.length) return; final target = sub[oldIdx]; int sIdx = _originalItems.indexOf(target); int eIdx = sIdx + 1; while (eIdx < _originalItems.length && !_originalItems[eIdx].isSubheading) eIdx++; List<ItemModel> toMove = _originalItems.sublist(sIdx, eIdx);
    setState(() { _originalItems.removeRange(sIdx, eIdx); List<ItemModel> rem = _originalItems.where((i) => i.isSubheading).toList(); int insIdx = (newIdx >= rem.length) ? _originalItems.length : _originalItems.indexOf(rem[newIdx]); _originalItems.insertAll(insIdx, toMove); });
    if (_autoSave) _manualSave(silent: true); _applyFilterAndSort();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark; final double sW = MediaQuery.of(context).size.width;
    final double flexU = (sW - 260) / 8; final double cStart = 70.0; final double cEnd = 70.0 + (flexU * 5);
    return Scaffold(
      appBar: AppBar(
        title: _isReorderMode ? const Text("순서 변경 모드", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent)) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)]), 
        backgroundColor: dark ? Colors.black : Colors.blueGrey[900], foregroundColor: Colors.white, 
        actions: _isReorderMode ? [
          TextButton(onPressed: () { setState(() { _originalItems = List.from(_preReorderItems); _isReorderMode = false; }); _applyFilterAndSort(); }, child: const Text("취소", style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () => setState(() => _isReorderMode = false), child: const Text("완료", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
        ] : _isEditMode ? [
          TextButton(onPressed: () { if (_selectedIndices.isEmpty) { _showSnackBar("선택된 항목이 없습니다."); return; } setState(() { _isSelectionFiltered = true; _isEditMode = false; }); _applyFilterAndSort(); }, child: const Text("선택필터", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _deleteSelectedRows, icon: const Icon(Icons.delete_forever, color: Colors.redAccent), label: Text("삭제(${_selectedIndices.length})", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
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
        if (!_isEditMode && !_isReorderMode) Padding(padding: const EdgeInsets.all(8.0), child: Row(children: [ _topBtn("설정", _openSettings), const SizedBox(width: 4), _topBtn("엑셀선택", () => _pickSource('file')), const SizedBox(width: 4), _topBtn("PDF폴더", () => _pickSource('dir')), const SizedBox(width: 4), _topBtn("부분제목", () { setState(() { if (_isSubheadingViewMode) _selectedSections.clear(); _isSubheadingViewMode = !_isSubheadingViewMode; }); _applyFilterAndSort(); }, bgColor: _isSubheadingViewMode ? Colors.blue : Colors.indigo[800]), const SizedBox(width: 4), _topBtn("선택모드", () => setState(() => _isEditMode = true), bgColor: Colors.orange[800]), const SizedBox(width: 4), if (_pdfFolderPath.startsWith("smb://")) ...[_topBtn("PDF동기화", _isSyncing ? null : _syncAllPdfs, bgColor: Colors.deepOrange[900]), const SizedBox(width: 4)], _topBtn("리셋", _showResetConfirm, bgColor: Colors.red[700]), const SizedBox(width: 4), _topBtn("저장", () { _forgetFocus(); _manualSave(); }, bgColor: Colors.green[700]), ])),
        if (!_isReorderMode) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(children: [
          Expanded(flex: 3, child: TextField(controller: _searchController, focusNode: _searchFocusNode, decoration: InputDecoration(hintText: "품목코드 검색", border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10), prefixIcon: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty) ? null : const Icon(Icons.search), suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_searchController.text.isNotEmpty) IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchQuery = ""; _applyFilterAndSort(); if (_scrollController.hasClients) _scrollController.jumpTo(_preSearchScrollOffset); }); }),
            IconButton(icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.blue), onPressed: () async {
              _forgetFocus(); final prefs = await SharedPreferences.getInstance(); _scannerZoom = prefs.getDouble('scannerZoom') ?? 0.0;
              if (!mounted) return; final String? res = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => QrScannerDialog(initialZoom: _scannerZoom)));
              if (res != null && res.isNotEmpty) {
                String? c; if (res.startsWith("CODE:")) { final p = res.split('|'); c = p[0].replaceFirst("CODE:", ""); if (p.length > 1 && p[1].startsWith("ZOOM:")) { final double? z = double.tryParse(p[1].replaceFirst("ZOOM:", "")); if (z != null) setState(() => _scannerZoom = z); } } else if (res.startsWith("ZOOM:")) { final double? z = double.tryParse(res.replaceFirst("ZOOM:", "")); if (z != null) { setState(() => _scannerZoom = z); _saveSettings(); } return; } else c = res;
                if (c == null || c.isEmpty) return; String cln = c.replaceAll('<NUL>', '').replaceAll('<NULL>', '').trim().replaceAll(RegExp(r'[\x00-\x1F]'), ''); if (cln.toUpperCase().endsWith('-S')) cln = cln.substring(0, cln.length - 2);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("스캔: $res → 정제: $cln"), duration: const Duration(seconds: 2)));
                if (_searchQuery.isEmpty) _preSearchScrollOffset = _scrollController.offset; setState(() { _searchController.text = cln; _searchQuery = cln; }); _applyFilterAndSort(); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToItem(cln));
              }
            }),
          ])), onChanged: (v) { if (_searchQuery.isEmpty && v.isNotEmpty) _preSearchScrollOffset = _scrollController.offset; setState(() => _searchQuery = v); _applyFilterAndSort(); if (v.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.jumpTo(_preSearchScrollOffset); }); })),
          Expanded(flex: 2, child: _buildSummaryWidget(dark)),
        ])),
        if (!_isReorderMode) _buildHeader(dark),
        Expanded(child: Listener(
          onPointerDown: _isEditMode ? (ev) { double x = ev.localPosition.dx; if (x >= cStart && x <= cEnd) { _isScrollingArea = true; _isSelecting = false; } else { _isScrollingArea = false; _isSelecting = true; _handleDragUpdate(ev.localPosition.dy); } } : (_) { _clearHighlight(); _forgetFocus(); setState(() => _trackedItemCode = null); if (_temporaryVisibleItem != null) { setState(() => _temporaryVisibleItem = null); _applyFilterAndSort(); } }, 
          onPointerMove: _isEditMode ? (ev) { if (_isScrollingArea) { if (_scrollController.hasClients) { double off = _scrollController.offset - ev.delta.dy; if (off < 0) off = 0; if (off > _scrollController.position.maxScrollExtent) off = _scrollController.position.maxScrollExtent; _scrollController.jumpTo(off); } } else if (_isSelecting) { _handleDragUpdate(ev.localPosition.dy); _handleAutoScroll(ev.localPosition.dy); } } : null,
          onPointerUp: _isEditMode ? (_) { setState(() { _isSelecting = false; _isScrollingArea = false; }); _scrollTimer?.cancel(); } : null,
          behavior: HitTestBehavior.opaque, 
          child: _isLoading ? const Center(child: CircularProgressIndicator()) : (_isReorderMode ? ReorderableListView(
            onReorder: _reorderSubheading, buildDefaultDragHandles: false, children: _originalItems.where((i) => i.isSubheading).toList().asMap().entries.map((en) {
              return ListTile(key: ValueKey("reorder-${en.value.itemCode}"), title: Text(en.value.itemCode, style: const TextStyle(fontWeight: FontWeight.bold)), trailing: ReorderableDragStartListener(index: en.key, child: const Icon(Icons.drag_handle)), tileColor: dark ? Colors.white10 : Colors.grey[200]);
            }).toList()) : ListView.builder(
            controller: _scrollController, padding: EdgeInsets.zero, physics: _isEditMode ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(), itemCount: _displayItems.length, itemBuilder: (ctx, idx) {
            final item = _displayItems[idx];
            if (item.isSubheading) {
              bool isSectionSel = _selectedSections.contains(item.itemCode); int total = 0; int comp = 0; int startIdx = _originalItems.indexOf(item); int seq = _originalItems.where((i) => i.isSubheading).toList().indexOf(item) + 1;
              if (startIdx != -1) { for (int j = startIdx + 1; j < _originalItems.length; j++) { if (_originalItems[j].isSubheading) break; total++; if (_originalItems[j].complete) comp++; } }
              double p = total > 0 ? (comp / total * 100) : 0; bool allD = total > 0 && total == comp;
              String rT = item.itemCode; List<String> parts = rT.split('_'); String l1 = parts.length > 3 ? parts.sublist(0, 3).join('_') : rT; String l2 = parts.length > 3 ? parts.sublist(3).join('_') : "";
              return GestureDetector(onTap: () { if (_isEditMode) _toggleSectionSelection(item.itemCode); else if (_isSubheadingViewMode) { if (item.realIndex != -1) { setState(() { _selectedSections = {item.itemCode}; _isSubheadingViewMode = false; }); _applyFilterAndSort(); } else setState(() => _isSubheadingViewMode = false); } else { setState(() { if (_selectedSections.contains(item.itemCode)) _selectedSections.remove(item.itemCode); else _selectedSections.add(item.itemCode); }); _applyFilterAndSort(); } }, child: Container(height: _subheadingHeight, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), alignment: Alignment.centerLeft, decoration: BoxDecoration(color: allD ? (dark ? Colors.green.withOpacity(0.15) : Colors.green[100]) : (_selectedSections.contains(item.itemCode) ? Colors.blueGrey : (dark ? Colors.white10 : Colors.grey[300])), border: Border(bottom: BorderSide(color: dark ? Colors.white24 : Colors.grey[400]!, width: 0.5))), child: Row(children: [if (_isSubheadingViewMode && !_isEditMode) Checkbox(value: isSectionSel, onChanged: (v) { setState(() { if (v!) _selectedSections.add(item.itemCode); else _selectedSections.remove(item.itemCode); }); }, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Text("[${seq.toString().padLeft(2, '0')}]", style: TextStyle(fontWeight: FontWeight.bold, color: dark ? Colors.blue[300] : Colors.blue[800], fontSize: 13)), const SizedBox(width: 6), Expanded(child: SizedBox(height: 20, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(l1, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)))))]), Padding(padding: const EdgeInsets.only(left: 36), child: SizedBox(height: 20, width: double.infinity, child: l2.isNotEmpty ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(l2, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))) : const SizedBox.shrink())), Padding(padding: const EdgeInsets.only(left: 36), child: Row(children: [Icon(Icons.list_alt, size: 12, color: dark ? Colors.grey[400] : Colors.grey[700]), const SizedBox(width: 3), Text("$total개", style: TextStyle(fontSize: 11, color: dark ? Colors.grey[400] : Colors.grey[700])), const SizedBox(width: 10), Icon(Icons.check_circle_outline, size: 12, color: allD ? Colors.green : (dark ? Colors.grey[400] : Colors.grey[600])), const SizedBox(width: 3), Text("완료 $comp개 (${p.toStringAsFixed(1)}%)", style: TextStyle(fontSize: 11, color: allD ? (dark ? Colors.green[300] : Colors.green[800]) : (dark ? Colors.grey[400] : Colors.grey[700]), fontWeight: allD ? FontWeight.bold : FontWeight.normal)), if (allD) ...[const SizedBox(width: 6), const Text("🏆", style: TextStyle(fontSize: 11))]]))])), if (_isEditMode) Icon(_isSectionSelected(item.itemCode) ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20), if (_isSubheadingViewMode && !_isEditMode) IconButton(icon: const Icon(Icons.reorder, size: 20, color: Colors.blue), onPressed: () => setState(() { _preReorderItems = List.from(_originalItems); _isReorderMode = true; }), tooltip: "순서 변경")])));
            }
            return _buildDataRow(item, dark);
          }))),
        )),
        if (_isSubheadingViewMode && _selectedSections.isNotEmpty) Container(color: dark ? Colors.blueGrey[900] : Colors.blueGrey[100], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: [Text("선택됨: ${_selectedSections.length}개", style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: () { setState(() { _selectedSections.clear(); _isSubheadingViewMode = false; }); _applyFilterAndSort(); }, child: const Text("모두보기", style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))), TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("모두 해제")), TextButton(onPressed: () => setState(() => _selectedSections.clear()), child: const Text("취소", style: TextStyle(color: Colors.red))), const SizedBox(width: 8), ElevatedButton(onPressed: () { setState(() => _isSubheadingViewMode = false); _applyFilterAndSort(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white), child: const Text("선택 항목 보기"))])),
        if (_isSyncing) const LinearProgressIndicator(minHeight: 2, color: Colors.orange),
        Offstage(child: TextField(focusNode: _dummyFocusNode, readOnly: true)),
      ])),
    );
  }

  void _handleDragUpdate(double localY) {
    if (!_scrollController.hasClients) return; double cur = _scrollController.offset; double tY = localY + cur; double acc = 0; int? tIdx;
    for (int i = 0; i < _displayItems.length; i++) { double h = _displayItems[i].isSubheading ? _subheadingHeight : _itemHeight; if (tY >= acc && tY <= acc + h) { tIdx = i; break; } acc += h; }
    if (tIdx != null) { final it = _displayItems[tIdx]; if (!it.isSubheading && it.realIndex != -1) { if (!_selectedIndices.contains(it.realIndex)) setState(() => _selectedIndices.add(it.realIndex)); } }
  }

  void _handleAutoScroll(double localY) {
    _scrollTimer?.cancel(); if (!_scrollController.hasClients) return; double vH = _scrollController.position.viewportDimension;
    if (localY < 50.0) { _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (t) { if (_scrollController.offset > 0) { _scrollController.jumpTo(_scrollController.offset - 10); _handleDragUpdate(localY); } else t.cancel(); }); } else if (localY > vH - 50.0) { _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (t) { if (_scrollController.offset < _scrollController.position.maxScrollExtent) { _scrollController.jumpTo(_scrollController.offset + 10); _handleDragUpdate(localY); } else t.cancel(); }); }
  }

  Widget _buildHeader(bool dark) { return Container(color: dark ? Colors.grey[900] : Colors.grey[800], height: 40, child: Row(children: [if (_isEditMode) const SizedBox(width: 35), _headerBtn("No", "no", 35), Expanded(flex: 5, child: _headerBtn("품목코드", "itemCode", null)), _headerBtn("수량", "quantity", 40), _headerBtn("완료", "complete", 50), _headerBtn("공정", "process", 50), _headerBtn("보완", "complement", 50), Expanded(flex: 3, child: _headerBtn("비고", "remarks", null))])); }
  Widget _headerBtn(String label, String? key, double? width) { bool isT = key != null && _currentSortCol == key; bool isN = key == 'no' && _noFilterMode != 0; String dL = (key == 'no' && _noFilterMode == 2) ? "-No" : label; bool isF = false; if (key != null && ['complete', 'complement', 'process', 'quantity'].contains(key)) isF = _columnFilters[key]!.isNotEmpty || (key == 'quantity' && _quantitySearchQuery.isNotEmpty); else if (key == 'remarks') isF = _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty; return InkWell(onTap: key == null ? null : () => _sortBy(key), child: Container(width: width, alignment: Alignment.center, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Flexible(child: Text(dL, style: TextStyle(color: (isN || isF) ? Colors.yellow : Colors.white, fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)), if (isT) Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18)]))); }
  
  Widget _buildDataRow(ItemModel item, bool dark) {
    bool isSel = _selectedIndices.contains(item.realIndex); bool isHigh = item.realIndex == _highlightedRealIndex;
    return Container(decoration: BoxDecoration(color: isSel ? Colors.blue.withOpacity(0.1) : (item.complete ? (dark ? Colors.green.withOpacity(0.1) : Colors.green[50]) : null), border: isHigh ? Border.all(color: Colors.blue, width: 2) : Border(bottom: BorderSide(color: dark ? Colors.white10 : Colors.grey[300]!))), height: 45, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_isEditMode) Container(width: 35, alignment: Alignment.center, child: Icon(isSel ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20)),
      SizedBox(width: 35, child: Center(child: Text(item.displayNo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))),
      Expanded(flex: 5, child: GestureDetector(onVerticalDragUpdate: _isEditMode ? (details) { if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.offset - details.delta.dy); } : null, onTap: _isEditMode ? () { setState(() { if (isSel) _selectedIndices.remove(item.realIndex); else _selectedIndices.add(item.realIndex); }); } : () => _handleItemClick(item), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft, color: Colors.transparent, child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(item.itemCode, style: TextStyle(fontSize: 13, color: dark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold)))))),
      _buildSelectableCell(SizedBox(width: 40, child: Center(child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)))), item),
      _buildSelectableCell(_cellCheck(item, dark, _isEditMode ? null : () { setState(() { item.complete = !item.complete; if (item.complete) { item.completeTime = DateTime.now().toString().substring(0, 16); item.complement = ""; item.complementTime = ""; } else item.completeTime = ""; }); if (_autoSave) _manualSave(silent: true); }), item),
      _buildSelectableCell(_cellProcess(item.process, dark, _isEditMode ? null : () => _showProcessDialog(item)), item),
      _buildSelectableCell(_cellComplement(item.complement, dark, _isEditMode ? null : () => _showComplementDialog(item)), item),
      Expanded(flex: 3, child: IgnorePointer(ignoring: _isEditMode, child: _RemarksCell(item: item, onSave: () { if (_autoSave) _manualSave(silent: true); }, onForgetFocus: _forgetFocus)))
    ]));
  }

  Widget _buildSelectableCell(Widget child, ItemModel item) { if (!_isEditMode) return child; return GestureDetector(onTap: () { setState(() { if (_selectedIndices.contains(item.realIndex)) _selectedIndices.remove(item.realIndex); else _selectedIndices.add(item.realIndex); }); }, child: child); }
  Widget _cellCheck(ItemModel item, bool dark, VoidCallback? onTap) { return InkWell(onTap: onTap, onLongPress: _isEditMode ? null : () => _showCompleteTimeDialog(item), child: Container(width: 50, alignment: Alignment.center, color: item.complete ? Colors.green.withOpacity(0.3) : null, child: item.complete ? const Icon(Icons.check, size: 20, color: Colors.green) : null)); }
  Widget _cellComplement(String txt, bool dark, VoidCallback? onTap) { if (txt.isEmpty) return InkWell(onTap: onTap, child: const SizedBox(width: 50)); Color base = (txt == "부족") ? Colors.orange : Colors.red; return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: BoxDecoration(color: base.withOpacity(0.15), border: Border(left: BorderSide(color: base, width: 4))), alignment: Alignment.center, child: FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87))))); }
  Widget _cellProcess(String txt, bool dark, VoidCallback? onTap) { int? cVal = txt.isNotEmpty ? _processColors[txt] : null; Color base; if (cVal != null) base = Color(cVal); else { if (txt == "완료") base = Colors.purple; else if (txt == "보류") base = Colors.red; else if (["용접", "도장", "도금", "인쇄"].contains(txt)) base = Colors.orange; else base = Colors.blueGrey; } return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 50, decoration: txt.isEmpty ? const BoxDecoration(color: Colors.transparent) : BoxDecoration(color: base.withOpacity(0.15), border: Border(left: BorderSide(color: base, width: 4))), alignment: Alignment.center, child: txt.isNotEmpty ? FittedBox(child: Text(txt, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dark ? Colors.white : Colors.black87))) : null)); }
  void _showError(String t, String m) { showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(t), content: Text(m), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))])); }
  void _showSnackBar(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(m)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating)); }
  Future<void> _manualSave({bool silent = false}) async { if (_excelPath.isNotEmpty) { bool ok = await _excelService.saveExcel(_excelPath, _originalItems); if (ok && !silent) _showSnackBar("저장 완료"); } }
  int _compareDisplayNo(String a, String b) { List<String> pa = a.split('-'); List<String> pb = b.split('-'); int ma = int.tryParse(pa[0]) ?? 0; int mb = int.tryParse(pb[0]) ?? 0; if (ma != mb) return ma.compareTo(mb); int sa = (pa.length > 1) ? (int.tryParse(pa[1]) ?? 0) : 0; int sb = (pb.length > 1) ? (int.tryParse(pb[1]) ?? 0) : 0; return sa.compareTo(sb); }
  Widget _zoomQuickBtnDialog(String label, double value, StateSetter setD) { bool isS = (_scannerZoom - value).abs() < 0.05; return GestureDetector(onTap: () => setD(() => _scannerZoom = value), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: isS ? Colors.blue : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isS ? Colors.blue : Colors.grey.withOpacity(0.3))), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isS ? Colors.white : Colors.black87)))); }
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
