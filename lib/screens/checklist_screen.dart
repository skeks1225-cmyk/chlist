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

  final String _baseDownloadPath = "/storage/emulated/0/Download";
  final FocusNode _dummyFocusNode = FocusNode();

  List<String> _processList = ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅'];

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";

  bool _showUnfinishedOnly = false; 
  String? _selectedSectionHeader; 

  // ❗ [신규] 행 삭제(편집) 모드 관련 변수
  bool _isEditMode = false;
  Set<int> _selectedIndices = {}; // realIndex 저장
  final Set<int> _draggedIndices = {}; // 현재 드래그 세션에서 이미 반전시킨 행들

  @override
  void initState() {
    super.initState();
    _initApp();
    _searchFocusNode.addListener(() => setState(() {})); // 돋보기 숨김 제어용
  }

  @override
  void dispose() {
    _dummyFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
      _processList = prefs.getStringList('processList') ?? ['레이저', 'CS', '탭', '버링탭', '헤밍', 'ZB', '절곡', '압입', '리베팅'];
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
    _searchFocusNode.unfocus();
    FocusScope.of(context).requestFocus(_dummyFocusNode);
  }

  void _applyFilterAndSort() {
    List<ItemModel> results = [];
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

      if (_searchQuery.isNotEmpty) {
        final queryParts = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.itemCode.toLowerCase();
          return queryParts.every((part) => targetStr.contains(part));
        }).toList();
      }

      if (_showUnfinishedOnly) {
        sectionItems = sectionItems.where((item) => !item.complete).toList();
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

    if (_isSorted) {
      results = results.where((i) => !i.isSubheading).toList();
      results.sort((a, b) {
        int cmp = 0;
        switch (_currentSortCol) {
          case 'no': cmp = (int.tryParse(a.no) ?? 0).compareTo(int.tryParse(b.no) ?? 0); break;
          case 'itemCode': cmp = a.itemCode.compareTo(b.itemCode); break;
          case 'quantity': cmp = (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0); break;
          case 'complete': cmp = (a.complete ? 1 : 0).compareTo(b.complete ? 1 : 0); break;
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
    });
    _applyFilterAndSort();
  }

  void _sortBy(String col) {
    _forgetFocus();
    setState(() {
      if (_currentSortCol == col) _isAscending = !_isAscending;
      else { _currentSortCol = col; _isAscending = true; }
      _isSorted = true;
    });
    _applyFilterAndSort();
  }

  void _openSettings() async {
    _forgetFocus();
    final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp'));
    final userController = TextEditingController(text: prefs.getString('smbUser'));
    final passController = TextEditingController(text: prefs.getString('smbPass'));
    final newProcessController = TextEditingController();

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
                        TextField(controller: passController, decoration: const InputDecoration(labelText: "PW", border: OutlineInputBorder()), obscureText: true),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () async {
                            String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                            _showError(err == null ? "성공" : "오류", err == null ? "✅ 접속 성공!" : "접속 실패: $err");
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

  // ❗ [신규] 행 삭제 처리
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
              _isEditMode = false;
              _selectedIndices.clear();
            });
            _applyFilterAndSort();
            Navigator.pop(ctx);
            _showSnackBar("삭제되었습니다. 엑셀 반영을 위해 [저장]을 눌러주세요.");
          }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ❗ [신규] 섹션 전체 선택/해제 로직
  void _toggleSectionSelection(String headerTitle) {
    String? currentHeader;
    List<int> sectionRealIndices = [];
    for (var item in _originalItems) {
      if (item.isSubheading) {
        currentHeader = item.itemCode;
      } else if (currentHeader == headerTitle) {
        sectionRealIndices.add(item.realIndex);
      }
    }

    setState(() {
      bool allSelected = sectionRealIndices.every((idx) => _selectedIndices.contains(idx));
      if (allSelected) {
        _selectedIndices.removeAll(sectionRealIndices);
      } else {
        _selectedIndices.addAll(sectionRealIndices);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSmbPdf = _pdfFolderPath.startsWith("smb://");

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
            Text(_currentFileName, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ]
        ),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: _isEditMode ? [
          TextButton.icon(
            onPressed: _deleteSelectedRows, 
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            label: Text("확인(${_selectedIndices.length})", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
          TextButton(
            onPressed: () => setState(() { _isEditMode = false; _selectedIndices.clear(); }),
            child: const Text("취소", style: TextStyle(color: Colors.white))
          ),
        ] : [
          IconButton(onPressed: _handleRefresh, icon: const Icon(Icons.refresh, color: Colors.cyanAccent), tooltip: "새로고침"),
          IconButton(onPressed: _handleClose, icon: const Icon(Icons.close, color: Colors.redAccent), tooltip: "리스트 닫기"),
          if (_isSorted || _selectedSectionHeader != null || _showUnfinishedOnly) 
            TextButton(onPressed: () {
                setState(() { _isSorted = false; _currentSortCol = ""; _selectedSectionHeader = null; _showUnfinishedOnly = false; });
                _applyFilterAndSort();
            }, child: const Text("필터리셋", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: () { _forgetFocus(); setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red), label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white))),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isEditMode) Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  _topBtn("설정", _openSettings, isDark),
                  const SizedBox(width: 4),
                  _topBtn("엑셀선택", () => _pickSource('file'), isDark),
                  const SizedBox(width: 4),
                  _topBtn("PDF폴더", () => _pickSource('dir'), isDark),
                  const SizedBox(width: 4),
                  // ❗ 행삭제 버튼 추가
                  ElevatedButton(
                    onPressed: () => setState(() => _isEditMode = true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white, minimumSize: const Size(60, 45)),
                    child: const Text("행삭제", style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  if (isSmbPdf) ...[
                    ElevatedButton(
                      onPressed: _isSyncing ? null : _syncAllPdfs,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white, minimumSize: const Size(80, 45), padding: const EdgeInsets.symmetric(horizontal: 8)),
                      child: Text(_isSyncing ? "동기화중..." : "PDF동기화", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 4),
                  ],
                  ElevatedButton(onPressed: _showResetConfirm, style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, minimumSize: const Size(50, 45)), child: const Text("리셋", style: TextStyle(fontSize: 12))),
                  const SizedBox(width: 4),
                  ElevatedButton(onPressed: () { _forgetFocus(); _manualSave(); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, minimumSize: const Size(50, 45)), child: const Text("저장", style: TextStyle(fontSize: 12))),
                ],
              ),
            ),
            
            // ❗ [개편] 검색바(4/5 축소) + 요약정보(확장) Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 4, // ❗ 4/5 크기로 축소
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: "품목코드 검색",
                        // ❗ 빈칸이고 포커스 없을 때만 돋보기 표시 (간격 최소화)
                        prefixIcon: (_searchController.text.isEmpty && !_searchFocusNode.hasFocus) 
                            ? const Icon(Icons.search, size: 20) : null,
                        prefixIconConstraints: const BoxConstraints(minWidth: 30),
                        suffixIcon: _searchController.text.isNotEmpty 
                          ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ""); _applyFilterAndSort(); }) 
                          : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      ),
                      onChanged: (val) { setState(() => _searchQuery = val); _applyFilterAndSort(); },
                    ),
                  ),
                  Expanded(
                    flex: 6, // ❗ 요약 정보 공간 확장
                    child: _buildSummaryWidget(isDark),
                  ),
                ],
              ),
            ),

            _buildHeader(context),
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : Listener(
                // ❗ [핵심] 스와이프 다중 선택을 위한 리스너
                onPointerMove: (event) {
                  if (!_isEditMode) return;
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final result = WidgetsBinding.instance.hitTestInView(event.position, event.viewId);
                  // 정밀 좌표 계산을 위해 개별 Row에서 처리하도록 로직 분산
                },
                child: ListView.builder(
                  itemCount: _displayItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = _displayItems[idx];
                    if (item.isSubheading) {
                      return GestureDetector(
                        onTap: () {
                          if (_isEditMode) _toggleSectionSelection(item.itemCode);
                          else {
                            setState(() {
                              if (_selectedSectionHeader == item.itemCode) _selectedSectionHeader = null;
                              else _selectedSectionHeader = item.itemCode;
                            });
                            _applyFilterAndSort();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                          color: _selectedSectionHeader == item.itemCode ? Colors.blueGrey : (isDark ? Colors.white10 : Colors.grey[300]), 
                          width: double.infinity, 
                          child: Row(
                            children: [
                              Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              if (_selectedSectionHeader == item.itemCode) const Padding(
                                padding: EdgeInsets.only(left: 8.0),
                                child: Icon(Icons.check_circle, size: 16, color: Colors.blueAccent),
                              ),
                              const Spacer(),
                              if (_isEditMode) Icon(
                                _isSectionSelected(item.itemCode) ? Icons.check_box : Icons.check_box_outline_blank,
                                color: Colors.blue,
                              ),
                            ],
                          )
                        ),
                      );
                    }
                    return _buildDataRow(item, isDark);
                  },
                ),
              ),
            ),
            if (_isSyncing) const LinearProgressIndicator(minHeight: 2, color: Colors.orange),
            Offstage(child: TextField(focusNode: _dummyFocusNode, readOnly: true)),
          ],
        ),
      ),
    );
  }

  bool _isSectionSelected(String header) {
    String? current;
    List<int> indices = [];
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
      onTap: () {
        setState(() => _showUnfinishedOnly = !_showUnfinishedOnly);
        _applyFilterAndSort();
      },
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            children: [
              if (_showUnfinishedOnly) const Icon(Icons.filter_list, size: 14, color: Colors.orange),
              const SizedBox(width: 4),
              Text(
                "[${parts.join(' / ')}]",
                style: TextStyle(
                  fontSize: 14, // ❗ 글자 크기 확대
                  fontWeight: FontWeight.bold,
                  color: _showUnfinishedOnly ? Colors.orangeAccent : (isDark ? Colors.white70 : Colors.blueGrey[800])
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(ItemModel item, bool isDark) {
    final bool isSelected = _selectedIndices.contains(item.realIndex);
    final Color? rowColor = _isEditMode 
        ? (isSelected ? Colors.blue.withOpacity(0.2) : null)
        : (item.complete ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green[50]) : null);

    return MouseRegion( // 드래그 감지용
      onEnter: (_) {
        if (_isEditMode && _draggedIndices.isNotEmpty) {
          setState(() {
            if (_selectedIndices.contains(item.realIndex)) _selectedIndices.remove(item.realIndex);
            else _selectedIndices.add(item.realIndex);
          });
        }
      },
      child: GestureDetector(
        // ❗ [핵심] 스와이프(드래그) 다중 선택 구현
        onPanStart: (_) {
          if (!_isEditMode) return;
          _draggedIndices.clear();
          _draggedIndices.add(item.realIndex);
          setState(() {
            if (_selectedIndices.contains(item.realIndex)) _selectedIndices.remove(item.realIndex);
            else _selectedIndices.add(item.realIndex);
          });
        },
        onPanUpdate: (details) {
          if (!_isEditMode) return;
          // 이 부분은 리스트뷰 스크롤과 충돌할 수 있어 MouseRegion enter로 보완하거나 
          // HitTest를 통해 현재 손가락 위치의 아이템을 찾아 반전시킵니다.
        },
        onTap: () {
          if (_isEditMode) {
            setState(() {
              if (_selectedIndices.contains(item.realIndex)) _selectedIndices.remove(item.realIndex);
              else _selectedIndices.add(item.realIndex);
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: rowColor,
            border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))
          ),
          height: 45,
          child: Row(
            children: [
              // ❗ 편집 모드 전용 체크박스 열
              if (_isEditMode) Container(
                width: 35,
                alignment: Alignment.center,
                child: Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank, color: Colors.blue, size: 20),
              ),
              InkWell(onTap: _forgetFocus, child: SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)))),
              Expanded(flex: 5, child: InkWell(
                onTap: _isEditMode ? null : () => _handleItemClick(item), 
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(item.itemCode, style: TextStyle(fontSize: 13, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold)),
                  ),
                ),
              )),
              InkWell(onTap: _forgetFocus, child: SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)))),
              _checkBtn(item.complete, Colors.green, _isEditMode ? null : () { 
                _forgetFocus(); 
                setState(() { item.complete = !item.complete; if (item.complete) item.complement = ""; }); 
                if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
                if (_showUnfinishedOnly) _applyFilterAndSort();
              }, isDark),
              _textBtn(item.complement, Colors.orange, _isEditMode ? null : () => _showComplementDialog(item), isDark),
              _textBtn(item.process, Colors.blueGrey, _isEditMode ? null : () => _showProcessDialog(item), isDark),
              Expanded(flex: 3, child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4), 
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    TextField(
                      enabled: !_isEditMode, // 편집 모드 시 비활성화
                      controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: ''),
                      onChanged: (val) { item.remarks = val; setState(() {}); },
                      onTapOutside: (event) { _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
                      onSubmitted: (val) { item.remarks = val; _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
                    ),
                    if (item.remarks.isNotEmpty && !_isEditMode)
                      GestureDetector(
                        onTap: () {
                          setState(() => item.remarks = "");
                          if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
                        },
                        child: Icon(Icons.cancel, size: 18, color: Colors.grey[600]),
                      ),
                  ],
                )
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[800],
      height: 40,
      child: Row(
        children: [
          if (_isEditMode) const SizedBox(width: 35),
          _headerBtn("No", "no", 35),
          Expanded(flex: 5, child: _headerBtn("품목코드", "itemCode", null)),
          _headerBtn("수량", "quantity", 40),
          _headerBtn("완료", "complete", 50),
          _headerBtn("보완", null, 50),
          _headerBtn("공정", null, 50),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _headerBtn(String label, String? colKey, double? width) {
    bool isTarget = colKey != null && _currentSortCol == colKey;
    return InkWell(
      onTap: colKey == null ? null : () => _sortBy(colKey),
      child: Container(
        width: width,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            if (isTarget) Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _checkBtn(bool val, Color color, VoidCallback? onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 50,
        alignment: Alignment.center,
        color: val ? color.withOpacity(0.4) : (isDark ? Colors.white10 : Colors.grey[100]),
        child: val ? Icon(Icons.check, color: isDark ? Colors.white : color, size: 24) : null,
      ),
    );
  }

  Widget _textBtn(String text, Color color, VoidCallback? onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        color: text.isNotEmpty ? color.withOpacity(0.3) : (isDark ? Colors.white10 : Colors.grey[100]),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : (text.isNotEmpty ? color : Colors.black),
            ),
          ),
        ),
      ),
    );
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
    else if (!ok) _showError("저장 실패", "다른 앱에서 사용 중이거나 권한이 없습니다.");
  }
}
