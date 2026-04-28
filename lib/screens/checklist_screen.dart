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
  String _searchQuery = "";

  // ❗ [신규] 필터 상태 변수
  bool _showUnfinishedOnly = false; // 미완료 모드
  String? _selectedSectionHeader; // 선택된 부분제목 (itemCode 저장)

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _dummyFocusNode.dispose();
    _searchController.dispose();
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
    FocusScope.of(context).requestFocus(_dummyFocusNode);
  }

  // ❗ [핵심] 고도화된 연동 필터링 엔진
  void _applyFilterAndSort() {
    List<ItemModel> results = [];

    // 1. 섹션별 그룹화 처리
    String? currentHeader;
    Map<String, List<ItemModel>> sectionMap = {};
    List<String> headerOrder = [];

    for (var item in _originalItems) {
      if (item.isSubheading) {
        currentHeader = item.itemCode;
        sectionMap[currentHeader] = [];
        headerOrder.add(currentHeader);
      } else {
        if (currentHeader != null) {
          sectionMap[currentHeader]!.add(item);
        } else {
          // 헤더 없는 최상단 데이터 처리용
          if (!sectionMap.containsKey("ROOT")) {
            sectionMap["ROOT"] = [];
            headerOrder.insert(0, "ROOT");
          }
          sectionMap["ROOT"]!.add(item);
        }
      }
    }

    // 2. 각 필터 적용
    for (var header in headerOrder) {
      // (1) 섹션 필터링: 선택된 섹션이 있으면 다른 섹션은 스킵
      if (_selectedSectionHeader != null && header != _selectedSectionHeader) continue;

      List<ItemModel> sectionItems = List.from(sectionMap[header]!);

      // (2) 검색 필터링
      if (_searchQuery.isNotEmpty) {
        final queryParts = _searchQuery.toLowerCase().split(' ').where((p) => p.isNotEmpty);
        sectionItems = sectionItems.where((item) {
          final targetStr = item.itemCode.toLowerCase();
          return queryParts.every((part) => targetStr.contains(part));
        }).toList();
      }

      // (3) 미완료 모드 필터링
      if (_showUnfinishedOnly) {
        sectionItems = sectionItems.where((item) => !item.complete).toList();
      }

      // ❗ 결과 구성 (데이터가 남아있는 경우에만 헤더와 함께 추가)
      if (sectionItems.isNotEmpty) {
        if (header != "ROOT") {
          results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header));
        }
        results.addAll(sectionItems);
      } else if (_selectedSectionHeader != null && header == _selectedSectionHeader) {
        // 섹션 선택 모드인데 하위 데이터가 없더라도 헤더는 보여줌 (빈 화면 방지)
        results.add(_originalItems.firstWhere((i) => i.isSubheading && i.itemCode == header));
      }
    }

    // 3. 정렬 적용 (검색/섹션 필터 상태가 아닐 때만 전체 정렬 허용)
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
      if (_currentSortCol == col) {
        _isAscending = !_isAscending;
      } else {
        _currentSortCol = col;
        _isAscending = true;
      }
      _isSorted = true;
    });
    _applyFilterAndSort();
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

  // ❗ [개편] 탭 방식 설정 다이얼로그
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
              tabs: [
                Tab(icon: Icon(Icons.dns), text: "연결 설정"),
                Tab(icon: Icon(Icons.settings_suggest), text: "공정 관리"),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 450,
              child: TabBarView(
                children: [
                  // 탭 1: SMB 설정
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
                  // 탭 2: 공정 관리
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
              if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); _saveLastDir(initialPath + "/f.pdf"); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")),
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
                _originalItems = [];
                _displayItems = [];
                _currentFileName = "파일을 선택하세요";
                _excelPath = "";
                _isSorted = false;
                _currentSortCol = "";
                _searchController.clear();
                _searchQuery = "";
                _showUnfinishedOnly = false;
                _selectedSectionHeader = null;
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
    if (_excelPath.isEmpty) {
      _showSnackBar("열려 있는 파일이 없습니다.");
      return;
    }
    if (File(_excelPath).existsSync()) {
      _loadExcelData(_excelPath);
      _showSnackBar("🔄 리스트를 다시 읽어왔습니다.");
    } else {
      _showError("새로고침 실패", "파일을 찾을 수 없습니다. 다시 선택해 주세요.");
    }
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
                ..._processList.map((p) => _dialogBtn(p, Colors.blueGrey[700]!, () { item.process = p; })),
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
          backgroundColor: color,
          foregroundColor: Colors.white,
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

  // ❗ [개편] 요약 정보를 단순 텍스트 위젯으로 변경 (미완료 필터 버튼 역할 수행)
  Widget _buildSummaryWidget(bool isDark) {
    if (_originalItems.isEmpty) return const SizedBox.shrink();
    final dataItems = _originalItems.where((i) => !i.isSubheading);
    int total = dataItems.length;
    int completed = dataItems.where((i) => i.complete).length;
    int shortages = dataItems.where((i) => i.complement == "부족").length;
    int reworks = dataItems.where((i) => i.complement == "재작업").length;
    double percent = total > 0 ? (completed / total) * 100 : 0;
    
    List<String> parts = ["전체 $total", "완료 $completed"];
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
                  fontSize: 11, 
                  fontWeight: FontWeight.bold,
                  // ❗ 필터링 중일 때는 노란색/주황색으로 강조
                  color: _showUnfinishedOnly 
                      ? Colors.orangeAccent 
                      : (isDark ? Colors.white70 : Colors.blueGrey[800])
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        actions: [
          IconButton(onPressed: _handleRefresh, icon: const Icon(Icons.refresh, color: Colors.cyanAccent), tooltip: "새로고침"),
          IconButton(onPressed: _handleClose, icon: const Icon(Icons.close, color: Colors.redAccent), tooltip: "리스트 닫기"),
          if (_isSorted || _selectedSectionHeader != null || _showUnfinishedOnly) 
            TextButton(
              onPressed: () {
                setState(() {
                  _isSorted = false;
                  _currentSortCol = "";
                  _selectedSectionHeader = null;
                  _showUnfinishedOnly = false;
                });
                _applyFilterAndSort();
              }, 
              child: const Text("필터리셋", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold))
            ),
          TextButton.icon(onPressed: () { _forgetFocus(); setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red), label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white))),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  _topBtn("설정", _openSettings, isDark),
                  const SizedBox(width: 4),
                  _topBtn("엑셀선택", () => _pickSource('file'), isDark),
                  const SizedBox(width: 4),
                  _topBtn("PDF폴더", () => _pickSource('dir'), isDark),
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
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "품목코드 검색",
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty 
                          ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ""); _applyFilterAndSort(); }) 
                          : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                        _applyFilterAndSort();
                      },
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _buildSummaryWidget(isDark),
                  ),
                ],
              ),
            ),

            _buildHeader(context),
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
                itemCount: _displayItems.length,
                itemBuilder: (ctx, idx) {
                  final item = _displayItems[idx];
                  if (item.isSubheading) {
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_selectedSectionHeader == item.itemCode) _selectedSectionHeader = null;
                          else _selectedSectionHeader = item.itemCode;
                        });
                        _applyFilterAndSort();
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
                          ],
                        )
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
    );
  }

  void _showResetConfirm() {
    _forgetFocus();
    if (_originalItems.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋"), content: const Text("모든 체크와 비고를 지우시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { _resetAllData(); Navigator.pop(ctx); }, child: const Text("예", style: TextStyle(color: Colors.red)))]));
  }

  void _resetAllData() {
    setState(() { 
      for (var item in _originalItems) { 
        item.complete = false; 
        item.complement = ""; 
        item.process = ""; 
        item.remarks = ""; 
      } 
      _displayItems = List.from(_originalItems); 
      _isSorted = false; 
      _currentSortCol = ""; 
      _selectedSectionHeader = null;
      _showUnfinishedOnly = false;
    });
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
  }

  Widget _topBtn(String label, VoidCallback onTap, bool isDark) {
    return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45), padding: EdgeInsets.zero), child: Text(label, style: const TextStyle(fontSize: 12))));
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
      } catch (e) { debugPrint("SMB Sync Error: $e"); }
      finally { setState(() => _isLoading = false); }
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(
      items: _displayItems.where((i) => !i.isSubheading).toList(),
      initialIndex: _displayItems.where((i) => !i.isSubheading).toList().indexOf(item),
      pdfFolderPath: _pdfFolderPath, 
      smbService: _smbService,
      onStatusUpdate: (it, type) {
        if (type == 'complete') {
          setState(() { it.complete = !it.complete; if (it.complete) it.complement = ""; });
        } else {
          setState(() {});
        }
        if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
      },
    )));
  }

  Widget _buildDataRow(ItemModel item, bool isDark) {
    // ❗ [신규] 완료된 행 강조 색상 정의
    final Color? rowColor = item.complete 
        ? (isDark ? Colors.green.withOpacity(0.2) : Colors.green[50]) 
        : null;

    return Container(
      decoration: BoxDecoration(
        color: rowColor, // ❗ 행 전체 배경색 적용
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))
      ),
      height: 45,
      child: Row(
        children: [
          InkWell(onTap: _forgetFocus, child: SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)))),
          Expanded(flex: 5, child: InkWell(
            onTap: () => _handleItemClick(item), 
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
          _checkBtn(item.complete, Colors.green, () { 
            _forgetFocus(); 
            setState(() { item.complete = !item.complete; if (item.complete) item.complement = ""; }); 
            if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
            // ❗ 필터링 상태일 경우 화면 즉시 갱신
            if (_showUnfinishedOnly) _applyFilterAndSort();
          }, isDark),
          _textBtn(item.complement, Colors.orange, () => _showComplementDialog(item), isDark),
          _textBtn(item.process, Colors.blueGrey, () => _showProcessDialog(item), isDark),
          Expanded(flex: 3, child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4), 
            child: Stack(
              alignment: Alignment.centerRight,
              children: [
                TextField(
                  controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: ''),
                  onChanged: (val) { item.remarks = val; setState(() {}); },
                  onTapOutside: (event) { _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
                  onSubmitted: (val) { item.remarks = val; _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
                ),
                if (item.remarks.isNotEmpty)
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
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[800],
      height: 40,
      child: Row(
        children: [
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

  Widget _checkBtn(bool val, Color color, VoidCallback onTap, bool isDark) {
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

  Widget _textBtn(String text, Color color, VoidCallback onTap, bool isDark) {
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(msg)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating));
  }

  Future<void> _manualSave({bool silent = false}) async {
    if (_excelPath.isEmpty) return;
    bool ok = await _excelService.saveExcel(_excelPath, _originalItems);
    if (ok && !silent) _showSnackBar("💾 저장 성공!");
    else if (!ok) _showError("저장 실패", "다른 앱에서 사용 중이거나 권한이 없습니다.");
  }
}
