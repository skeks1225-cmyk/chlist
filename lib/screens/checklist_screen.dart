import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
import '../services/smb_service.dart';
import 'pdf_view_screen.dart';
import 'dart:io';
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

  // ❗ 필터 관련 상태 변수 추가
  final Map<String, Set<String>> _columnFilters = {
    'complete': {},
    'complement': {},
    'process': {},
    'quantity': {},
  };
  String _remarksExcludeQuery = "";
  String _quantitySearchQuery = ""; // ❗ 수량 직접 입력 검색어
  String _remarksIncludeLogic = "AND"; // ❗ 기본값 AND
  String _remarksExcludeLogic = "OR";  // ❗ 기본값 OR

  final String _baseDownloadPath = "/storage/emulated/0/Download";
  final FocusNode _dummyFocusNode = FocusNode();

  List<String> _processList = ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅', '용접', '도장', '도금', '인쇄'];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  String _remarksFilterQuery = ""; // 비고란 포함 필터 쿼리

  bool _showUnfinishedOnly = false; 
  String? _selectedSectionHeader; 
  bool _isSubheadingViewMode = false; // ❗ 부분제목만 보기 모드
  bool _showMainNumbersOnly = false; // ❗ 원본 번호가 있는 항목만 보기 모드

  // ❗ 행 삭제(편집) 모드 관련 변수
  bool _isEditMode = false;
  final Set<int> _selectedIndices = {}; // realIndex 저장
  final Set<int> _draggedIndices = {}; // 드래그 중 반전 중복 방지

  // ❗ 스크롤 및 포커싱 관련
  final ScrollController _scrollController = ScrollController();
  int? _highlightedRealIndex;
  final double _subheadingHeight = 40.0;
  final double _itemHeight = 45.0;
  double _preSearchScrollOffset = 0.0; // ❗ 검색 전 스크롤 위치 저장용

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

  // ❗ 특정 품목코드가 있는 위치로 스크롤 및 하이라이트
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
      // 누적 높이 계산
      offset += item.isSubheading ? _subheadingHeight : _itemHeight;
    }

    if (targetIndex != -1 && foundRealIndex != null) {
      // ❗ 이동 전 이전 하이라이트 제거
      setState(() => _highlightedRealIndex = null);

      // 화면 중앙 계산: (항목 위치) - (화면 높이 / 2) + (항목 높이 / 2)
      final screenHeight = MediaQuery.of(context).size.height;
      final appBarHeight = kToolbarHeight + 50; 
      double targetOffset = offset - (screenHeight / 2) + (appBarHeight / 2) + (_itemHeight / 2);

      // 범위 제한 (맨 위 또는 맨 아래)
      if (targetOffset < 0) targetOffset = 0;
      if (targetOffset > _scrollController.position.maxScrollExtent) {
        targetOffset = _scrollController.position.maxScrollExtent;
      }

      // ❗ 즉시 이동 및 하이라이트 표시
      _scrollController.jumpTo(targetOffset);
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
      _processList = prefs.getStringList('processList') ?? ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅', '용접', '도장', '도금', '인쇄'];
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) _loadExcelData(_excelPath);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
    await prefs.setStringList('processList', _processList);
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
        _selectedSectionHeader = null;
        _isEditMode = false;
        _selectedIndices.clear();
        // 필터 초기화
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
    
    // ❗ 부분제목만 보기 모드 처리
    if (_isSubheadingViewMode) {
      results = _originalItems.where((i) => i.isSubheading).toList();
      
      // 검색어가 있으면 부분제목 타이틀에서 검색
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        results = results.where((i) => i.itemCode.toLowerCase().contains(query)).toList();
      }

      if (results.isEmpty) {
        // 부분제목이 하나도 없는 경우 "부분제목 없음" 표시용 가상 아이템 추가
        results.add(ItemModel(
          realIndex: -1, 
          no: "", 
          displayNo: "", 
          itemCode: "부분제목 없음", 
          quantity: "", 
          isSubheading: true
        ));
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
          if (!sectionMap.containsKey("ROOT")) {
            sectionMap["ROOT"] = [];
            headerOrder.insert(0, "ROOT");
          }
          sectionMap["ROOT"]!.add(item);
        }
      }
    }

    for (var header in headerOrder) {
      if (_selectedSectionHeader != null && header != _selectedSectionHeader) continue;
      List<ItemModel> sectionItems = List.from(sectionMap[header]!);

      // 1. 품목코드 검색 필터
      if (_searchQuery.isNotEmpty) {
        final queryParts = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.itemCode.toLowerCase();
          return queryParts.every((part) => targetStr.contains(part));
        }).toList();
      }

      // 2. 컬럼별 체크박스 필터 (완료, 보완, 공정, 수량)
      _columnFilters.forEach((col, selectedValues) {
        if (selectedValues.isNotEmpty || (col == 'quantity' && _quantitySearchQuery.isNotEmpty)) {
          sectionItems = sectionItems.where((item) {
            String val = "";
            if (col == 'complete') val = item.complete ? "완료" : "미완료";
            else if (col == 'complement') val = item.complement.isEmpty ? "(빈칸)" : item.complement;
            else if (col == 'process') val = item.process.isEmpty ? "(빈칸)" : item.process;
            else if (col == 'quantity') val = item.quantity;

            // 체크박스 선택 확인
            bool isSelected = selectedValues.contains(val);
            
            // 수량의 경우 직접 입력 검색어도 확인 (정확한 일치)
            if (col == 'quantity' && _quantitySearchQuery.isNotEmpty) {
              final queryParts = _quantitySearchQuery.split(' ').where((p) => p.isNotEmpty);
              bool isMatched = queryParts.any((p) => val == p); // ❗ 정확한 일치 검색
              return isSelected || isMatched;
            }
            
            return isSelected;
          }).toList();
        }
      });

      // 3. 비고 포함 필터 (AND/OR)
      if (_remarksFilterQuery.isNotEmpty) {
        final queryParts = _remarksFilterQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.remarks.toLowerCase();
          if (_remarksIncludeLogic == "AND") {
            return queryParts.every((part) => targetStr.contains(part));
          } else {
            return queryParts.any((part) => targetStr.contains(part));
          }
        }).toList();
      }

      // 4. 비고 제외 필터 (AND/OR)
      if (_remarksExcludeQuery.isNotEmpty) {
        final excludeParts = _remarksExcludeQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.remarks.toLowerCase();
          bool shouldExclude = false;
          if (_remarksExcludeLogic == "AND") {
            shouldExclude = excludeParts.every((part) => targetStr.contains(part));
          } else {
            shouldExclude = excludeParts.any((part) => targetStr.contains(part));
          }
          return !shouldExclude;
        }).toList();
      }

      if (_showUnfinishedOnly) {
        sectionItems = sectionItems.where((item) => !item.complete).toList();
      }

      // ❗ 'No' 필터링 (원본 번호가 있는 항목만 보기)
      if (_showMainNumbersOnly) {
        sectionItems = sectionItems.where((item) => item.no.isNotEmpty).toList();
      }

      if (sectionItems.isNotEmpty) {
        if (header != "ROOT") {
          results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header));
        }
        results.addAll(sectionItems);
      } else if (_selectedSectionHeader != null && header == _selectedSectionHeader) {
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

    setState(() {
      _displayItems = results;
    });
  }

  void _resetSort() {
    _forgetFocus();
    setState(() {
      _isSorted = false;
      _currentSortCol = "";
      _remarksFilterQuery = "";
      _remarksExcludeQuery = "";
      _quantitySearchQuery = "";
      _remarksIncludeLogic = "AND";
      _remarksExcludeLogic = "OR";
      _showMainNumbersOnly = false;
      _columnFilters.forEach((key, value) => value.clear());
      _showUnfinishedOnly = false;
      _selectedSectionHeader = null;
      _isSubheadingViewMode = false;
    });
    _applyFilterAndSort();
  }

  void _sortBy(String col) {
    _forgetFocus();
    // ❗ 품목코드는 팝업 없이 즉시 정렬
    if (col == 'itemCode') {
      setState(() {
        if (_currentSortCol == col) _isAscending = !_isAscending;
        else { _currentSortCol = col; _isAscending = true; }
        _isSorted = true;
      });
      _applyFilterAndSort();
      return;
    }
    // ❗ 'No' 헤더는 필터링 토글로 동작 유지
    if (col == 'no') {
      setState(() => _showMainNumbersOnly = !_showMainNumbersOnly);
      _applyFilterAndSort();
      return;
    }

    _showFilterDialog(col);
  }

  void _showFilterDialog(String col) {
    List<String> options = [];
    if (col == 'complete') {
      options = ["완료", "미완료"];
    } else if (col == 'complement') {
      options = ["부족", "재작업", "(빈칸)"];
    } else if (col == 'process') {
      options = _originalItems.where((i) => !i.isSubheading && i.process.isNotEmpty).map((i) => i.process).toSet().toList();
      options.sort();
      options.add("(빈칸)");
    } else if (col == 'quantity') {
      options = _originalItems.where((i) => !i.isSubheading && i.quantity.isNotEmpty).map((i) => i.quantity).toSet().toList();
      options.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    }

    bool localIsSorted = _isSorted && _currentSortCol == col;
    bool localIsAscending = _isAscending;
    Set<String> localFilters = Set.from(_columnFilters[col] ?? {});
    
    final includeController = TextEditingController(text: _remarksFilterQuery);
    final excludeController = TextEditingController(text: _remarksExcludeQuery);
    final quantityController = TextEditingController(text: _quantitySearchQuery);
    String localIncludeLogic = _remarksIncludeLogic;
    String localExcludeLogic = _remarksExcludeLogic;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text("$col 설정", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("정렬", style: TextStyle(fontWeight: FontWeight.bold)),
                  RadioListTile<bool?>(
                    title: const Text("오름차순"), value: true, groupValue: localIsSorted ? localIsAscending : null,
                    onChanged: (val) => setModalState(() { localIsSorted = true; localIsAscending = true; }),
                    contentPadding: EdgeInsets.zero, dense: true,
                  ),
                  RadioListTile<bool?>(
                    title: const Text("내림차순"), value: false, groupValue: localIsSorted ? localIsAscending : null,
                    onChanged: (val) => setModalState(() { localIsSorted = true; localIsAscending = false; }),
                    contentPadding: EdgeInsets.zero, dense: true,
                  ),
                  RadioListTile<bool?>(
                    title: const Text("정렬 안함"), value: null, groupValue: localIsSorted ? localIsAscending : null,
                    onChanged: (val) => setModalState(() { localIsSorted = false; }),
                    contentPadding: EdgeInsets.zero, dense: true,
                  ),
                  if (col != 'itemCode') ...[
                    const Divider(),
                    if (col == 'remarks') ...[
                      const Text("포함 필터 (띄어쓰기 구분)", style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(controller: includeController, decoration: const InputDecoration(hintText: "포함할 단어")),
                      Row(
                        children: [
                          const Text("로직: "),
                          Radio<String>(value: "AND", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)),
                          const Text("AND"),
                          Radio<String>(value: "OR", groupValue: localIncludeLogic, onChanged: (v) => setModalState(() => localIncludeLogic = v!)),
                          const Text("OR"),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text("제외 필터 (띄어쓰기 구분)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                      TextField(controller: excludeController, decoration: const InputDecoration(hintText: "제외할 단어")),
                      Row(
                        children: [
                          const Text("로직: "),
                          Radio<String>(value: "AND", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)),
                          const Text("AND"),
                          Radio<String>(value: "OR", groupValue: localExcludeLogic, onChanged: (v) => setModalState(() => localExcludeLogic = v!)),
                          const Text("OR"),
                        ],
                      ),
                    ] else if (col == 'quantity') ...[
                      const Text("수량 직접 입력 (띄어쓰기 구분)", style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(controller: quantityController, decoration: const InputDecoration(hintText: "찾을 수량 입력 (예: 10 25)"), keyboardType: TextInputType.number),
                      const SizedBox(height: 15),
                      const Text("항목 선택", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        children: options.map((opt) {
                          bool isSel = localFilters.contains(opt);
                          return SizedBox(
                            width: (MediaQuery.of(context).size.width * 0.8) / 4, 
                            child: InkWell(
                              onTap: () => setModalState(() { if (isSel) localFilters.remove(opt); else localFilters.add(opt); }),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: isSel, 
                                    onChanged: (v) => setModalState(() { if (v!) localFilters.add(opt); else localFilters.remove(opt); }),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(opt, style: const TextStyle(fontSize: 12)))),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else if (options.isNotEmpty) ...[
                      const Text("필터", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        children: options.map((opt) {
                          bool isSel = localFilters.contains(opt);
                          double itemWidth;
                          if (col == 'complete') itemWidth = (MediaQuery.of(context).size.width * 0.8) / 2;
                          else if (col == 'complement') itemWidth = (MediaQuery.of(context).size.width * 0.8) / 3;
                          else if (col == 'process') itemWidth = (MediaQuery.of(context).size.width * 0.8) / 3;
                          else itemWidth = (MediaQuery.of(context).size.width * 0.8);

                          return SizedBox(
                            width: itemWidth,
                            child: InkWell(
                              onTap: () => setModalState(() {
                                if (col == 'complete') {
                                  if (isSel) localFilters.clear();
                                  else { localFilters.clear(); localFilters.add(opt); }
                                } else {
                                  if (isSel) localFilters.remove(opt); else localFilters.add(opt);
                                }
                              }),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: isSel, 
                                    onChanged: (v) => setModalState(() {
                                      if (col == 'complete') {
                                        localFilters.clear();
                                        if (v!) localFilters.add(opt);
                                      } else {
                                        if (v!) localFilters.add(opt); else localFilters.remove(opt);
                                      }
                                    }),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(opt, style: const TextStyle(fontSize: 12)))),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            TextButton(onPressed: () {
              setModalState(() {
                localIsSorted = false;
                localFilters.clear();
                includeController.clear();
                excludeController.clear();
                quantityController.clear();
                localIncludeLogic = "AND";
                localExcludeLogic = "OR";
              });
              setState(() {
                _isSorted = false;
                if (_columnFilters.containsKey(col)) _columnFilters[col]!.clear();
                if (col == 'remarks') { _remarksFilterQuery = ""; _remarksExcludeQuery = ""; }
                if (col == 'quantity') _quantitySearchQuery = "";
              });
              _applyFilterAndSort();
              Navigator.pop(ctx);
            }, child: const Text("초기화")),
            TextButton(onPressed: () {
              setState(() {
                _isSorted = localIsSorted;
                if (localIsSorted) { _currentSortCol = col; _isAscending = localIsAscending; }
                else if (_currentSortCol == col) { _currentSortCol = ""; }
                
                if (_columnFilters.containsKey(col)) {
                  _columnFilters[col] = localFilters;
                }
                if (col == 'remarks') {
                  _remarksFilterQuery = includeController.text;
                  _remarksExcludeQuery = excludeController.text;
                  _remarksIncludeLogic = localIncludeLogic;
                  _remarksExcludeLogic = localExcludeLogic;
                }
                if (col == 'quantity') {
                  _quantitySearchQuery = quantityController.text;
                }
              });
              _applyFilterAndSort();
              Navigator.pop(ctx);
            }, child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                Expanded(child: Text(opt, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            TextButton(onPressed: () {
              setModalState(() {
                localIsSorted = false;
                localFilters.clear();
                includeController.clear();
                excludeController.clear();
                quantityController.clear();
                localIncludeLogic = "AND";
                localExcludeLogic = "OR";
              });
              setState(() {
                _isSorted = false;
                if (_columnFilters.containsKey(col)) _columnFilters[col]!.clear();
                if (col == 'remarks') { _remarksFilterQuery = ""; _remarksExcludeQuery = ""; }
                if (col == 'quantity') _quantitySearchQuery = "";
              });
              _applyFilterAndSort();
              Navigator.pop(ctx);
            }, child: const Text("초기화")),
            TextButton(onPressed: () {
              setState(() {
                _isSorted = localIsSorted;
                if (localIsSorted) { _currentSortCol = col; _isAscending = localIsAscending; }
                else if (_currentSortCol == col) { _currentSortCol = ""; }
                
                if (_columnFilters.containsKey(col)) {
                  _columnFilters[col] = localFilters;
                }
                if (col == 'remarks') {
                  _remarksFilterQuery = includeController.text;
                  _remarksExcludeQuery = excludeController.text;
                  _remarksIncludeLogic = localIncludeLogic;
                  _remarksExcludeLogic = localExcludeLogic;
                }
                if (col == 'quantity') {
                  _quantitySearchQuery = quantityController.text;
                }
              });
              _applyFilterAndSort();
              Navigator.pop(ctx);
            }, child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
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

  void _openSettings() async {
    _forgetFocus();
    final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp'));
    final userController = TextEditingController(text: prefs.getString('smbUser'));
    final passController = TextEditingController(text: prefs.getString('smbPass'));
    final newProcessController = TextEditingController();
    bool obscurePass = true; 

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const TabBar(
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              tabs: [Tab(icon: Icon(Icons.dns), text: "연결 설정"), Tab(icon: Icon(Icons.settings_suggest), text: "공정 관리")],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: TabBarView(
                children: [
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소", border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: userController, decoration: const InputDecoration(labelText: "ID", border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(
                          controller: passController, 
                          obscureText: obscurePass,
                          decoration: InputDecoration(
                            labelText: "PW", 
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscurePass ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () async {
                            String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                            if (err == null) {
                              List<String> shares = await _smbService.listShares();
                              String shareMsg = shares.isNotEmpty 
                                  ? "\n\n[공유 목록]\n${shares.join('\n')}" 
                                  : "\n\n공유 폴더를 찾을 수 없습니다.";
                              _showError("성공", "✅ 접속 성공!$shareMsg");
                            } else {
                              _showError("오류", "접속 실패: $err");
                            }
                          },
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text("접속 테스트"),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 10),
                      Expanded(
                        child: ReorderableListView(
                          onReorder: (oldIndex, newIndex) {
                            setDialogState(() {
                              if (newIndex > oldIndex) newIndex -= 1;
                              final String item = _processList.removeAt(oldIndex);
                              _processList.insert(newIndex, item);
                            });
                          },
                          children: [
                            for (int i = 0; i < _processList.length; i++)
                              ListTile(
                                key: ValueKey(_processList[i] + i.toString()),
                                title: Text(_processList[i]),
                                trailing: const Icon(Icons.drag_handle),
                                leading: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: () => setDialogState(() => _processList.removeAt(i)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: newProcessController, decoration: const InputDecoration(hintText: "공정명 추가"))),
                          IconButton(
                            icon: const Icon(Icons.add_box, color: Colors.green, size: 35),
                            onPressed: () {
                              if (newProcessController.text.isNotEmpty) {
                                setDialogState(() {
                                  _processList.add(newProcessController.text);
                                  newProcessController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
              TextButton(onPressed: () async {
                await prefs.setString('smbIp', ipController.text);
                await prefs.setString('smbUser', userController.text);
                await prefs.setString('smbPass', passController.text);
                await prefs.setStringList('processList', _processList);
                _smbService.setConfig(ipController.text, userController.text, passController.text);
                setState(() {}); 
                Navigator.pop(ctx);
              }, child: const Text("저장", style: TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }

  void _openSmbShares(String mode) async {
    _forgetFocus();
    setState(() => _isLoading = true);
    try {
      List<String> shares = await _smbService.listShares();
      setState(() => _isLoading = false);
      if (!mounted) return;
      if (shares.isNotEmpty && shares[0].startsWith("ERROR:")) { _showError("탐색 실패", shares[0].replaceFirst("ERROR:", "").trim()); return; }
      if (shares.isEmpty) { _showError("오류", "공유폴더를 찾을 수 없습니다."); return; }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("공유폴더 선택"),
          content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: shares.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.folder_shared), title: Text(shares[i]), onTap: () { Navigator.pop(ctx); _showSmbFiles(shares[i], "", mode); }))),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("치명적 오류", "응답이 없습니다: $e");
    }
  }

  void _showSmbFiles(String share, String path, String mode) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> files = await _smbService.listFiles(share, path);
    setState(() => _isLoading = false);
    if (!mounted) return;

    List<Map<String, dynamic>> filteredFiles = files.where((f) {
      bool isDir = f['isDirectory'] as bool;
      if (isDir) return true;
      String name = (f['name'] as String).toLowerCase();
      if (mode == 'file') return name.endsWith('.xlsx') || name.endsWith('.xls');
      if (mode == 'dir') return name.endsWith('.pdf');
      return true;
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$share/$path"),
        content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
          if (path != "") ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showSmbFiles(share, p.dirname(path) == "." ? "" : p.dirname(path), mode); }),
          Expanded(child: ListView.builder(itemCount: filteredFiles.length, itemBuilder: (c, i) {
            final f = filteredFiles[i];
            bool isDir = f['isDirectory'] as bool;
            String name = f['name'] as String;
            return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description), title: Text(name), onTap: () {
              if (isDir) { Navigator.pop(ctx); _showSmbFiles(share, "${path == "" ? "" : "$path/"}$name", mode); }
              else if (mode == 'file') { Navigator.pop(ctx); _downloadAndLoad(share, "${path == "" ? "" : "$path/"}$name"); }
            });
          })),
        ])),
        actions: [
          if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = "smb://$share/$path"); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
        ],
      ),
    );
  }

  Future<void> _downloadAndLoad(String share, String remotePath) async {
    setState(() => _isLoading = true);
    String localPath = "$_baseDownloadPath/CheckSheet/${p.basename(remotePath)}";
    File? file = await _smbService.downloadFile(share, remotePath, localPath);
    setState(() => _isLoading = false);
    if (file != null) _loadExcelData(file.path);
    else _showError("오류", "파일 다운로드 실패");
  }

  Future<void> _syncAllPdfs() async {
    _forgetFocus();
    if (_originalItems.isEmpty) return;
    List<ItemModel> targets = _originalItems.where((i) => !i.isSubheading).toList();
    setState(() => _isSyncing = true);
    try {
      String shareWithRest = _pdfFolderPath.replaceFirst("smb://", "");
      if (shareWithRest.endsWith("/")) shareWithRest = shareWithRest.substring(0, shareWithRest.length - 1);
      int firstSlash = shareWithRest.indexOf("/");
      String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest;
      String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : "";
      const int batchSize = 5;
      for (int i = 0; i < targets.length; i += batchSize) {
        final chunk = targets.skip(i).take(batchSize);
        await Future.wait(chunk.map((item) {
          String cleanCode = item.itemCode.trim();
          String remoteFilePath = folderPath.isEmpty ? "$cleanCode.pdf" : "$folderPath/$cleanCode.pdf";
          String localFilePath = "$_baseDownloadPath/CheckSheet/$cleanCode.pdf";
          return _smbService.downloadFile(share, remoteFilePath, localFilePath);
        }));
      }
      _showSnackBar("✅ ${targets.length}개 품목 동기화 완료!");
    } catch (e) { debugPrint("Sync Error: $e"); }
    finally { setState(() => _isSyncing = false); }
  }

  Future<void> _openCustomPicker(String mode) async {
    _forgetFocus();
    final prefs = await SharedPreferences.getInstance();
    String startPath = prefs.getString('lastDir') ?? "$_baseDownloadPath/CheckSheet";
    if (!Directory(startPath).existsSync()) startPath = _baseDownloadPath;
    if (!mounted) return;
    _showFileBrowser(mode, startPath);
  }

  void _showFileBrowser(String mode, String initialPath) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final dir = Directory(initialPath);
          List<FileSystemEntity> entities = [];
          try {
            entities = dir.listSync().where((e) {
              if (e is Directory) return true;
              if (mode == 'file') return e.path.endsWith('.xlsx') || e.path.endsWith('.xls');
              return e.path.endsWith('.pdf');
            }).toList();
            entities.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
          } catch (_) {}
          return AlertDialog(
            title: Text(p.basename(initialPath)),
            content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
              ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); }),
              Expanded(child: ListView.builder(itemCount: entities.length, itemBuilder: (c, i) {
                final e = entities[i];
                final isDir = e is Directory;
                return ListTile(leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue), title: Text(p.basename(e.path)), onTap: () {
                  if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); }
                  else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); }
                });
              })),
            ])),
            actions: [
              if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ],
          );
        },
      ),
    );
  }

  void _handleClose() {
    _forgetFocus();
    if (_originalItems.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("리스트 닫기"),
        content: const Text("현재 리스트를 닫으시겠습니까?\n저장되지 않은 변경사항은 사라질 수 있습니다."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")),
          TextButton(
            onPressed: () {
              setState(() {
                _originalItems = []; _displayItems = [];
                _currentFileName = "파일을 선택하세요"; _excelPath = "";
                _isSorted = false; _currentSortCol = "";
                _searchController.clear(); _searchQuery = "";
                _showUnfinishedOnly = false; _selectedSectionHeader = null;
              });
              _saveSettings();
              Navigator.pop(ctx);
              _showSnackBar("리스트가 닫혔습니다.");
            },
            child: const Text("예", style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }

  void _handleRefresh() {
    _forgetFocus();
    if (_excelPath.isEmpty) { _showSnackBar("열려 있는 파일이 없습니다."); return; }
    if (File(_excelPath).existsSync()) {
      _loadExcelData(_excelPath);
      _showSnackBar("🔄 리스트를 다시 읽어왔습니다.");
    } else { _showError("새로고침 실패", "파일을 찾을 수 없습니다."); }
  }

  void _showComplementDialog(ItemModel item) {
    _forgetFocus();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("보완 선택", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogBtn("부족", Colors.orange, () { item.complement = "부족"; item.complete = false; }),
            _dialogBtn("재작업", Colors.red, () { item.complement = "재작업"; item.complete = false; }),
            const Divider(),
            _dialogBtn("지우기", Colors.grey, () { item.complement = ""; }),
            _dialogBtn("선택취소", Colors.blueGrey, () {}),
          ],
        ),
      ),
    );
  }

  void _showProcessDialog(ItemModel item) {
    _forgetFocus();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("공정 선택", style: TextStyle(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: 2.5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: _processList.map((p) => ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      setState(() { item.process = p; });
                      if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
                      Navigator.pop(context);
                    },
                    child: Text(p),
                  )).toList(),
                ),
                const Divider(),
                _dialogBtn("지우기", Colors.grey, () { item.process = ""; }),
                _dialogBtn("선택취소", Colors.blueGrey, () {}),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          setState(onSelected);
          if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
          Navigator.pop(context);
        },
        child: Text(label),
      ),
    );
  }

  void _deleteSelectedRows() {
    if (_selectedIndices.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("행 삭제 확인"),
        content: Text("선택한 ${_selectedIndices.length}개의 행을 리스트에서 완전히 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(onPressed: () {
            setState(() {
              _originalItems.removeWhere((item) => _selectedIndices.contains(item.realIndex));
              _isEditMode = false; _selectedIndices.clear();
            });
            _applyFilterAndSort();
            Navigator.pop(ctx);
            if (_autoSave && _excelPath.isNotEmpty) {
              _manualSave(silent: true);
              _showSnackBar("🗑️ 삭제 및 자동 저장되었습니다.");
            } else {
              _showSnackBar("삭제되었습니다. 엑셀 반영을 위해 [저장]을 눌러주세요.");
            }
          }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _toggleSectionSelection(String headerTitle) {
    String? currentHeader;
    List<int> sectionRealIndices = [];
    for (var item in _originalItems) {
      if (item.isSubheading) {
        currentHeader = item.itemCode;
        if (currentHeader == headerTitle) sectionRealIndices.add(item.realIndex);
      } else if (currentHeader == headerTitle) {
        sectionRealIndices.add(item.realIndex);
      }
    }
    setState(() {
      bool allSelected = sectionRealIndices.every((idx) => _selectedIndices.contains(idx));
      if (allSelected) {
        for (var idx in sectionRealIndices) _selectedIndices.remove(idx);
      } else {
        _selectedIndices.addAll(sectionRealIndices);
      }
    });
  }

  bool _isSectionSelected(String header) {
    String? current; List<int> indices = [];
    for (var i in _originalItems) {
      if (i.isSubheading) current = i.itemCode;
      else if (current == header) indices.add(i.realIndex);
    }
    return indices.isNotEmpty && indices.every((idx) => _selectedIndices.contains(idx));
  }

  Widget _buildSummaryWidget(bool isDark) {
    if (_originalItems.isEmpty) return const SizedBox.shrink();
    final dataItems = _originalItems.where((i) => !i.isSubheading);
    int total = dataItems.length;
    int completed = dataItems.where((i) => i.complete).length;
    int incomplete = total - completed;
    int shortages = dataItems.where((i) => i.complement == "부족").length;
    int reworks = dataItems.where((i) => i.complement == "재작업").length;
    double percent = total > 0 ? (completed / total) * 100 : 0;
    List<String> parts = ["전체 $total", "완료 $completed", "미완 $incomplete"];
    if (shortages > 0) parts.add("부족 $shortages");
    if (reworks > 0) parts.add("재작업 $reworks");
    parts.add("${percent.toStringAsFixed(1)}%");

    return InkWell(
      onTap: () { setState(() => _showUnfinishedOnly = !_showUnfinishedOnly); _applyFilterAndSort(); },
      child: Container(
        alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              if (_showUnfinishedOnly) const Icon(Icons.filter_list, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                "[${parts.join(' / ')}]",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _showUnfinishedOnly ? Colors.orangeAccent : (isDark ? Colors.white70 : Colors.blueGrey[800])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBtn(String label, VoidCallback? onTap, {Color? bgColor}) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap, 
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor ?? Colors.blueGrey[700],
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ), 
        child: FittedBox(
          fit: BoxFit.scaleDown, 
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))
        )
      )
    );
  }

  Future<void> _handleItemClick(ItemModel item) async {
    _forgetFocus();
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
    if (_pdfFolderPath.startsWith("smb://")) {
      setState(() => _isLoading = true);
      try {
        String shareWithRest = _pdfFolderPath.replaceFirst("smb://", "");
        if (shareWithRest.endsWith("/")) shareWithRest = shareWithRest.substring(0, shareWithRest.length - 1);
        int firstSlash = shareWithRest.indexOf("/");
        String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest;
        String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : "";
        String remoteFilePath = folderPath.isEmpty ? "${item.itemCode}.pdf" : "$folderPath/${item.itemCode}.pdf";
        String localFilePath = "$_baseDownloadPath/CheckSheet/${item.itemCode}.pdf";
        await _smbService.downloadFile(share, remoteFilePath, localFilePath);
      } catch (e) { debugPrint("SMB Error: $e"); }
      finally { setState(() => _isLoading = false); }
    }
    if (!mounted) return;
    
    // ❗ 뷰어로부터 마지막으로 보고 있던 품목코드를 받아옴
    final String? lastItemCode = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(
      items: _displayItems.where((i) => !i.isSubheading).toList(),
      initialIndex: _displayItems.where((i) => !i.isSubheading).toList().indexOf(item),
      pdfFolderPath: _pdfFolderPath, smbService: _smbService,
      processList: _processList, // ❗ 공정 목록 전달
      onStatusUpdate: (it, type) {
        if (type == 'complete') { setState(() { it.complete = !it.complete; if (it.complete) it.complement = ""; }); }
        else { setState(() {}); }
        if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
      },
    )));

    if (lastItemCode != null) {
      _scrollToItem(lastItemCode);
    }
  }

  void _showResetConfirm() {
    _forgetFocus();
    if (_originalItems.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋"), content: const Text("모든 체크와 비고를 지우시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { _resetAllData(); Navigator.pop(ctx); }, child: const Text("예", style: TextStyle(color: Colors.red)))]));
  }

  void _resetAllData() {
    setState(() { 
      for (var item in _originalItems) { item.complete = false; item.complement = ""; item.process = ""; item.remarks = ""; } 
      _displayItems = List.from(_originalItems); _isSorted = false; _currentSortCol = ""; 
      _selectedSectionHeader = null; _showUnfinishedOnly = false;
    });
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSmbPdf = _pdfFolderPath.startsWith("smb://");

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)]),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: _isEditMode ? [
          TextButton.icon(onPressed: _deleteSelectedRows, icon: const Icon(Icons.delete_forever, color: Colors.redAccent), label: Text("확인(${_selectedIndices.length})", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: () => setState(() { _isEditMode = false; _selectedIndices.clear(); }), child: const Text("취소", style: TextStyle(color: Colors.white))),
        ] : [
          TextButton(onPressed: _handleRefresh, child: const Text("새로고침", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold))),
          TextButton(onPressed: _handleClose, child: const Text("닫기", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
          if (_isSorted || _selectedSectionHeader != null || _showUnfinishedOnly || _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty || _quantitySearchQuery.isNotEmpty || _isSubheadingViewMode || _showMainNumbersOnly || _columnFilters.values.any((s) => s.isNotEmpty)) 
            TextButton(
              onPressed: _resetSort,
              child: const Text("필터리셋", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))
            ),
          TextButton.icon(onPressed: () { _forgetFocus(); setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red), label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white))),
        ],
      ),
      body: SafeArea(
        child: Listener(
          onPointerDown: (_) => _clearHighlight(), // ❗ 사용자가 화면에 손을 대는 순간 하이라이트 제거
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              if (!_isEditMode) Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    _topBtn("설정", _openSettings),
                    const SizedBox(width: 4),
                    _topBtn("엑셀선택", () => _pickSource('file')),
                    const SizedBox(width: 4),
                    _topBtn("PDF폴더", () => _pickSource('dir')),
                    const SizedBox(width: 4),
                    _topBtn("부분제목", () {
                      setState(() { _isSubheadingViewMode = !_isSubheadingViewMode; });
                      _applyFilterAndSort();
                    }, bgColor: _isSubheadingViewMode ? Colors.blue : Colors.indigo[800]),
                    const SizedBox(width: 4),
                    _topBtn("행삭제", () => setState(() => _isEditMode = true), bgColor: Colors.orange[800]),
                    const SizedBox(width: 4),
                    if (isSmbPdf) ...[
                      _topBtn("PDF동기화", _isSyncing ? null : _syncAllPdfs, bgColor: Colors.deepOrange[900]),
                      const SizedBox(width: 4),
                    ],
                    _topBtn("리셋", _showResetConfirm, bgColor: Colors.red[700]),
                    const SizedBox(width: 4),
                    _topBtn("저장", () { _forgetFocus(); _manualSave(); }, bgColor: Colors.green[700]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: _searchController, focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: "품목코드 검색",
                          prefixIcon: (_searchController.text.isEmpty && !_searchFocusNode.hasFocus) ? const Icon(Icons.search, size: 20) : null,
                          prefixIconConstraints: const BoxConstraints(minWidth: 30),
                          suffixIcon: _searchController.text.isNotEmpty ? IconButton(
                            icon: const Icon(Icons.clear, size: 20), 
                            onPressed: () { 
                              _searchController.clear(); 
                              setState(() => _searchQuery = ""); 
                              _applyFilterAndSort(); 
                              // ❗ 검색어 삭제 시 이전 위치로 복구
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (_scrollController.hasClients) _scrollController.jumpTo(_preSearchScrollOffset);
                              });
                            }
                          ) : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                        ),
                        onChanged: (val) { 
                          // ❗ 검색 시작 시점의 위치 저장
                          if (_searchQuery.isEmpty && val.isNotEmpty) {
                            _preSearchScrollOffset = _scrollController.offset;
                          }
                          setState(() => _searchQuery = val); 
                          _applyFilterAndSort(); 
                          // ❗ 검색어를 다 지웠을 때 이전 위치로 복구
                          if (val.isEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) _scrollController.jumpTo(_preSearchScrollOffset);
                            });
                          }
                        },
                      ),
                    ),
                    Expanded(flex: 6, child: _buildSummaryWidget(isDark)),
                  ],
                ),
              ),
              _buildHeader(context),
              Expanded(
                child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
                  controller: _scrollController,
                  itemCount: _displayItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = _displayItems[idx];
                    if (item.isSubheading) {
                      return GestureDetector(
                        onTap: () {
                          if (_isEditMode) _toggleSectionSelection(item.itemCode);
                          else if (_isSubheadingViewMode) {
                            if (item.realIndex == -1) {
                              setState(() => _isSubheadingViewMode = false);
                            } else {
                              setState(() {
                                _selectedSectionHeader = item.itemCode;
                                _isSubheadingViewMode = false;
                              });
                            }
                            _applyFilterAndSort();
                          } else {
                            setState(() { if (_selectedSectionHeader == item.itemCode) _selectedSectionHeader = null; else _selectedSectionHeader = item.itemCode; });
                            _applyFilterAndSort();
                          }
                        },
                        child: Container(
                          height: _subheadingHeight,
                          padding: const EdgeInsets.symmetric(horizontal: 12), 
                          alignment: Alignment.centerLeft,
                          color: _selectedSectionHeader == item.itemCode ? Colors.blueGrey : (isDark ? Colors.white10 : Colors.grey[300]), 
                          width: double.infinity, 
                          child: Row(children: [Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), if (_selectedSectionHeader == item.itemCode) const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.check_circle, size: 16, color: Colors.blueAccent)), const Spacer(), if (_isEditMode) Icon(_isSectionSelected(item.itemCode) ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue)]),
                        ),
                      );
                    }
                    return _buildDataRow(item, isDark);
                  },
                ),
              ),
              if (_isSyncing) const LinearProgressIndicator(minHeight: 2, color: Colors.orange),
              Offstage(child: TextField(focusNode: _dummyFocusNode, readOnly: true)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(ItemModel item, bool isDark) {
    final bool isSelected = _selectedIndices.contains(item.realIndex);
    final Color? rowColor = _isEditMode ? (isSelected ? Colors.blue.withOpacity(0.2) : null) : (item.complete ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green[50]) : null);
    
    // ❗ 줄 전체 하이라이트 여부
    final bool isHighlighted = item.realIndex == _highlightedRealIndex;

    return GestureDetector(
      onTap: () { if (_isEditMode) setState(() { if (_selectedIndices.contains(item.realIndex)) _selectedIndices.remove(item.realIndex); else _selectedIndices.add(item.realIndex); }); },
      child: Container(
        decoration: BoxDecoration(
          color: rowColor, 
          border: isHighlighted 
              ? Border.all(color: Colors.blue, width: 2) // ❗ 줄 전체 파란색 테두리
              : Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))
        ), 
        height: 45,
        child: Row(children: [
          if (_isEditMode) Container(width: 35, alignment: Alignment.center, child: Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20)),
          InkWell(onTap: _forgetFocus, child: SizedBox(width: 35, child: Text(item.displayNo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)))),
          Expanded(flex: 5, child: InkWell(onTap: _isEditMode ? null : () => _handleItemClick(item), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8), 
            alignment: Alignment.centerLeft, 
            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(item.itemCode, style: TextStyle(fontSize: 13, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold)))))),
          InkWell(onTap: _forgetFocus, child: SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)))),
          _checkBtn(item.complete, Colors.green, _isEditMode ? null : () { _forgetFocus(); setState(() { item.complete = !item.complete; if (item.complete) item.complement = ""; }); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); if (_showUnfinishedOnly) _applyFilterAndSort(); }, isDark),
          _textBtn(item.complement, Colors.orange, _isEditMode ? null : () => _showComplementDialog(item), isDark),
          _textBtn(item.process, Colors.blueGrey, _isEditMode ? null : () => _showProcessDialog(item), isDark),
          Expanded(flex: 3, child: _RemarksCell(
            item: item, 
            enabled: !_isEditMode, 
            onSave: () {
              if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
            },
            onForgetFocus: _forgetFocus,
          )),
        ]),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[800], height: 40,
      child: Row(children: [
        if (_isEditMode) const SizedBox(width: 35), 
        _headerBtn("No", "no", 35), 
        Expanded(flex: 5, child: _headerBtn("품목코드", "itemCode", null)), 
        _headerBtn("수량", "quantity", 40), 
        _headerBtn("완료", "complete", 50), 
        _headerBtn("보완", "complement", 50), 
        _headerBtn("공정", "process", 50), 
        Expanded(flex: 3, child: _headerBtn("비고", "remarks", null))
      ]),
    );
  }

  Widget _headerBtn(String label, String? colKey, double? width) {
    bool isTarget = colKey != null && _currentSortCol == colKey;
    bool isNoFilterActive = colKey == 'no' && _showMainNumbersOnly;
    
    // ❗ 해당 열에 필터가 적용되어 있는지 확인
    bool isFilterActive = false;
    if (colKey == 'complete' || colKey == 'complement' || colKey == 'process' || colKey == 'quantity') {
      isFilterActive = _columnFilters[colKey!]?.isNotEmpty ?? false;
      if (colKey == 'quantity' && _quantitySearchQuery.isNotEmpty) isFilterActive = true;
    } else if (colKey == 'remarks') {
      isFilterActive = _remarksFilterQuery.isNotEmpty || _remarksExcludeQuery.isNotEmpty;
    }

    return InkWell(
      onTap: colKey == null ? null : () => _sortBy(colKey), 
      child: Container(
        width: width, 
        alignment: Alignment.center, 
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, 
          children: [
            Flexible(
              child: Text(
                label, 
                style: TextStyle(
                  color: (isNoFilterActive || isFilterActive) ? Colors.yellow : Colors.white, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 13
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ), 
            if (isTarget) Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18),
            if (isFilterActive && !isTarget) const Icon(Icons.filter_alt, color: Colors.yellow, size: 14),
          ]
        )
      )
    );
  }

  Widget _checkBtn(bool val, Color color, VoidCallback? onTap, bool isDark) {
    return InkWell(onTap: onTap, child: Container(width: 50, alignment: Alignment.center, color: val ? color.withOpacity(0.4) : (isDark ? Colors.white10 : Colors.grey[100]), child: val ? Icon(Icons.check, color: isDark ? Colors.white : color, size: 24) : null));
  }

  Widget _textBtn(String text, Color color, VoidCallback? onTap, bool isDark) {
    return InkWell(onTap: onTap, child: Container(width: 50, padding: const EdgeInsets.symmetric(horizontal: 2), alignment: Alignment.center, color: text.isNotEmpty ? color.withOpacity(0.3) : (isDark ? Colors.white10 : Colors.grey[100]), child: FittedBox(fit: BoxFit.scaleDown, child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : (text.isNotEmpty ? color : Colors.black))))));
  }

  void _showError(String title, String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(msg)), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  Future<void> _manualSave({bool silent = false}) async {
    if (_excelPath.isEmpty) return;
    bool ok = await _excelService.saveExcel(_excelPath, _originalItems);
    if (ok && !silent) _showSnackBar("💾 저장 성공!");
    else if (!ok) _showError("저장 실패", "파일 쓰기 권한이 없습니다.");
  }

  // ❗ 가상 번호(예: 2, 2-1, 10-1) 정렬을 위한 비교 함수
  int _compareDisplayNo(String a, String b) {
    List<String> partA = a.split('-');
    List<String> partB = b.split('-');
    
    int mainA = int.tryParse(partA[0]) ?? 0;
    int mainB = int.tryParse(partB[0]) ?? 0;
    
    if (mainA != mainB) return mainA.compareTo(mainB);
    
    int subA = (partA.length > 1) ? (int.tryParse(partA[1]) ?? 0) : 0;
    int subB = (partB.length > 1) ? (int.tryParse(partB[1]) ?? 0) : 0;
    
    return subA.compareTo(subB);
  }
}

class _RemarksCell extends StatefulWidget {
  final ItemModel item;
  final bool enabled;
  final VoidCallback onSave;
  final VoidCallback onForgetFocus;

  const _RemarksCell({
    required this.item,
    required this.enabled,
    required this.onSave,
    required this.onForgetFocus,
  });

  @override
  State<_RemarksCell> createState() => _RemarksCellState();
}

class _RemarksCellState extends State<_RemarksCell> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.remarks);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // 포커스를 잃었을 때 데이터 저장
      widget.item.remarks = _controller.text;
      widget.onSave();
    }
  }

  @override
  void didUpdateWidget(_RemarksCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 외부(예: 뷰어)에서 비고가 변경된 경우 반영
    if (widget.item.remarks != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.item.remarks;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          TextField(
            focusNode: _focusNode,
            enabled: widget.enabled,
            controller: _controller,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: ''),
            onChanged: (val) => widget.item.remarks = val,
            onSubmitted: (val) {
              widget.item.remarks = val;
              widget.onSave();
              widget.onForgetFocus();
            },
            onTapOutside: (_) {
              widget.onForgetFocus();
            },
          ),
          if (_controller.text.isNotEmpty && widget.enabled)
            Positioned(
              right: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() => _controller.clear());
                  widget.item.remarks = "";
                  widget.onSave();
                },
                child: Icon(Icons.cancel, size: 18, color: Colors.grey[600]),
              ),
            ),
        ],
      ),
    );
  }
}
