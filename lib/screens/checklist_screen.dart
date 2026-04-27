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

  // ❗ 공정 목록 관리
  List<String> _processList = ['레이저', '탭', '버링탭', 'CS', '헤밍', 'ZB', '압입', '리베팅'];

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _dummyFocusNode.dispose();
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
      // 공정 목록 로드
      _processList = prefs.getStringList('processList') ?? ['레이저', '탭', '버링탭', 'CS', '헤밍', 'ZB', '압입', '리베팅'];
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

  void _resetSort() {
    _forgetFocus();
    setState(() {
      _displayItems = List.from(_originalItems);
      _isSorted = false;
      _currentSortCol = "";
    });
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
      List<ItemModel> dataOnly = _originalItems.where((i) => !i.isSubheading).toList();
      dataOnly.sort((a, b) {
        int cmp = 0;
        switch (col) {
          case 'no':
            cmp = (int.tryParse(a.no) ?? 0).compareTo(int.tryParse(b.no) ?? 0);
            break;
          case 'itemCode':
            cmp = a.itemCode.compareTo(b.itemCode);
            break;
          case 'quantity':
            cmp = (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0);
            break;
          case 'complete':
            cmp = (a.complete ? 1 : 0).compareTo(b.complete ? 1 : 0);
            break;
        }
        return _isAscending ? cmp : -cmp;
      });
      _displayItems = dataOnly;
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

  // ❗ [개편] 설정 다이얼로그 (SMB + 공정 관리)
  void _openSettings() async {
    _forgetFocus();
    final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp'));
    final userController = TextEditingController(text: prefs.getString('smbUser'));
    final passController = TextEditingController(text: prefs.getString('smbPass'));
    final newProcessController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("📡 SMB 서버 설정", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소")),
                  TextField(controller: userController, decoration: const InputDecoration(labelText: "ID")),
                  TextField(controller: passController, decoration: const InputDecoration(labelText: "PW"), obscureText: true),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                      String msg = err == null ? "✅ 접속 성공!" : "접속 실패: $err";
                      _showError(err == null ? "성공" : "오류", msg);
                    },
                    child: const Text("접속 테스트"),
                  ),
                  const Divider(height: 30),
                  const Text("⚙️ 공정 목록 관리 (드래그하여 순서 변경)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 300,
                    child: ReorderableListView(
                      shrinkWrap: true,
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
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => setDialogState(() => _processList.removeAt(i)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: newProcessController, decoration: const InputDecoration(hintText: "새 공정명 입력"))),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green, size: 30),
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
              setState(() {}); // 메인 화면 반영
              Navigator.pop(ctx);
            }, child: const Text("저장")),
          ],
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

  // ❗ [신규] 보완 다이얼로그 (부족/재작업 선택)
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

  // ❗ [신규] 공정 다이얼로그 (커스텀 목록 선택)
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSmbPdf = _pdfFolderPath.startsWith("smb://");

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12))]),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _handleRefresh, icon: const Icon(Icons.refresh, color: Colors.cyanAccent), tooltip: "새로고침"),
          IconButton(onPressed: _handleClose, icon: const Icon(Icons.close, color: Colors.redAccent), tooltip: "리스트 닫기"),
          if (_isSorted) TextButton(onPressed: _resetSort, child: const Text("정렬리셋", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
            _buildHeader(context),
            Expanded(
              child: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
                itemCount: _displayItems.length,
                itemBuilder: (ctx, idx) {
                  final item = _displayItems[idx];
                  if (item.isSubheading) {
                    return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), color: isDark ? Colors.white10 : Colors.grey[300], width: double.infinity, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)));
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
    setState(() { for (var item in _originalItems) { item.complete = false; item.complement = ""; item.remarks = ""; } _displayItems = List.from(_originalItems); _isSorted = false; _currentSortCol = ""; });
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
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))),
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
          
          // 완료 칸
          _checkBtn(item.complete, Colors.green, () { 
            _forgetFocus(); 
            setState(() { 
              item.complete = !item.complete; 
              if (item.complete) item.complement = ""; 
            }); 
            if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
          }, isDark),

          // 보완 칸 (부족/재작업)
          _textBtn(item.complement, Colors.orange, () => _showComplementDialog(item), isDark),

          // 공정 칸 (커스텀 공정)
          _textBtn(item.process, Colors.blueGrey, () => _showProcessDialog(item), isDark),

          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextField(
            controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: ''),
            onChanged: (val) => item.remarks = val,
            onTapOutside: (event) { _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
            onSubmitted: (val) { item.remarks = val; _forgetFocus(); if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true); },
          ))),
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

  // ❗ [신규] 텍스트 표시 버튼 (보완, 공정 칸용)
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
