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

  String _currentSortCol = ""; 
  bool _isAscending = true;   

  String _smbShareName = "체크시트"; 

  final String _baseDownloadPath = "/storage/emulated/0/Download";

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
    await _loadSettings();
    await _ensureBaseDirectory();
    _autoConnectSMB(); 
  }

  Future<void> _autoConnectSMB() async {
    final prefs = await SharedPreferences.getInstance();
    String ip = prefs.getString('smbIp') ?? "";
    String user = prefs.getString('smbUser') ?? "";
    String pass = prefs.getString('smbPass') ?? "";
    if (ip.isNotEmpty && user.isNotEmpty) {
      await _smbService.testConnection(ip, user, pass);
    }
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
      _smbShareName = prefs.getString('smbShareName') ?? "체크시트";
      _smbService.setConfig(
        prefs.getString('smbIp') ?? "",
        prefs.getString('smbUser') ?? "",
        prefs.getString('smbPass') ?? "",
      );
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) _loadExcelData(_excelPath);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
    await prefs.setString('smbShareName', _smbShareName);
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

  void _resetSort() {
    setState(() {
      _displayItems = List.from(_originalItems);
      _isSorted = false;
      _currentSortCol = "";
    });
  }

  void _sortBy(String col) {
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
          case 'shortage':
            cmp = (a.shortage ? 1 : 0).compareTo(b.shortage ? 1 : 0);
            break;
          case 'rework':
            cmp = (a.rework ? 1 : 0).compareTo(b.rework ? 1 : 0);
            break;
        }
        return _isAscending ? cmp : -cmp;
      });
      _displayItems = dataOnly;
    });
  }

  Future<void> _pickSource(String mode) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.phone_android), title: const Text("내 휴대폰"), onTap: () { Navigator.pop(ctx); _openCustomPicker(mode); }),
          ListTile(leading: const Icon(Icons.computer), title: const Text("PC 공유폴더 (SMB)"), onTap: () { Navigator.pop(ctx); _openSmbShares(mode); }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _openExternalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ipController = TextEditingController(text: prefs.getString('smbIp'));
    final userController = TextEditingController(text: prefs.getString('smbUser'));
    final passController = TextEditingController(text: prefs.getString('smbPass'));
    final shareController = TextEditingController(text: _smbShareName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("외부설정 (SMB)"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소")),
              TextField(controller: userController, decoration: const InputDecoration(labelText: "ID")),
              TextField(controller: passController, decoration: const InputDecoration(labelText: "PW"), obscureText: true),
              TextField(controller: shareController, decoration: const InputDecoration(labelText: "공유폴더명 (예: 체크시트)")),
              const SizedBox(height: 10),
              
              // ❗ 1. 기존 버튼 원상 복구 (안정성 확보)
              ElevatedButton(
                onPressed: () async {
                  String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                  _showError(err == null ? "성공" : "접속 실패", err ?? "✅ 접속 성공!");
                },
                child: const Text("접속 테스트"),
              ),
              const Divider(height: 30),
              
              // ❗ 2. 완전히 분리된 별도 테스트 버튼 (실패해도 영향 없도록)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
                onPressed: () async {
                  _showSnackBar("정찰 테스트 시작...");
                  try {
                    final List<dynamic> shares = await MethodChannel('org.example.checksheet/smb').invokeMethod('testDiscovery', {
                      'ip': ipController.text,
                      'user': userController.text,
                      'pass': passController.text,
                    });
                    _showError("정찰 결과", shares.isEmpty ? "검색된 폴더 없음" : "[발견됨]\n${shares.join('\n')}");
                  } catch (e) {
                    _showError("정찰 실패", "오류 발생: $e");
                  }
                },
                child: const Text("공유목록 정찰 테스트 (jCIFS)"),
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
            setState(() => _smbShareName = shareController.text); 
            await prefs.setString('smbShareName', _smbShareName);
            _smbService.setConfig(ipController.text, userController.text, passController.text);
            Navigator.pop(ctx);
          }, child: const Text("저장")),
        ],
      ),
    );
  }

  void _openSmbShares(String mode) async {
    setState(() => _isLoading = true);
    List<String> shares = await _smbService.listShares();
    setState(() => _isLoading = false);
    if (!mounted) return;

    if (shares.isNotEmpty && shares[0].startsWith("ERROR:")) {
      _showError("탐색 실패", shares[0].replaceFirst("ERROR:", "").trim());
      return;
    }

    Set<String> uniqueShares = {};
    if (_smbShareName.isNotEmpty) uniqueShares.add(_smbShareName);
    for (var s in shares) {
      if (s != "설정된 공유폴더" && s != "Shared" && s != "Users" && s != "Public") {
        uniqueShares.add(s);
      }
    }
    List<String> displayList = uniqueShares.toList();

    if (displayList.isEmpty) { _showError("오류", "공유폴더를 찾을 수 없습니다."); return; }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("공유폴더 선택"),
        content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: displayList.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.folder_shared), title: Text(displayList[i]), onTap: () { Navigator.pop(ctx); _showSmbFiles(displayList[i], "", mode); }))),
      ),
    );
  }

  void _showSmbFiles(String share, String path, String mode) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> files = await _smbService.listFiles(share, path);
    setState(() => _isLoading = false);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$share/$path"),
        content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
          if (path != "") ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showSmbFiles(share, p.dirname(path) == "." ? "" : p.dirname(path), mode); }),
          Expanded(child: ListView.builder(itemCount: files.length, itemBuilder: (c, i) {
            final f = files[i];
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

  Future<void> _openCustomPicker(String mode) async {
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(_currentFileName, style: const TextStyle(fontSize: 12))]),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          if (_isSorted) TextButton(onPressed: _resetSort, child: const Text("정렬리셋", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); }, icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red), label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white))),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                _topBtn("외부설정", _openExternalSettings, isDark),
                const SizedBox(width: 4),
                _topBtn("엑셀선택", () => _pickSource('file'), isDark),
                const SizedBox(width: 4),
                _topBtn("PDF폴더", () => _pickSource('dir'), isDark),
                const SizedBox(width: 4),
                ElevatedButton(onPressed: _showResetConfirm, style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, minimumSize: const Size(60, 45)), child: const Text("리셋")),
                const SizedBox(width: 4),
                ElevatedButton(onPressed: _manualSave, style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, minimumSize: const Size(60, 45)), child: const Text("저장")),
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
        ],
      ),
    );
  }

  void _showResetConfirm() {
    if (_originalItems.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋"), content: const Text("모든 체크와 비고를 지우시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { _resetAllData(); Navigator.pop(ctx); }, child: const Text("예", style: TextStyle(color: Colors.red)))]));
  }

  void _resetAllData() {
    setState(() { for (var item in _originalItems) { item.complete = false; item.shortage = false; item.rework = false; item.remarks = ""; } _displayItems = List.from(_originalItems); _isSorted = false; _currentSortCol = ""; });
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
  }

  Widget _topBtn(String label, VoidCallback onTap, bool isDark) {
    return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45), padding: EdgeInsets.zero), child: Text(label, style: const TextStyle(fontSize: 12))));
  }

  Future<void> _handleItemClick(ItemModel item) async {
    String finalPdfPath = "$_baseDownloadPath/CheckSheet";
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
      } catch (e) {
        debugPrint("SMB Sync Error: $e");
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      finalPdfPath = _pdfFolderPath;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(
      items: _displayItems.where((i) => !i.isSubheading).toList(),
      initialIndex: _displayItems.where((i) => !i.isSubheading).toList().indexOf(item),
      pdfFolderPath: _pdfFolderPath, 
      smbService: _smbService,
      onStatusUpdate: (it, type) => _toggleStatus(it, type),
    )));
  }

  Widget _buildDataRow(ItemModel item, bool isDark) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))),
      height: 45,
      child: Row(
        children: [
          SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
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
          SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          _checkBtn(item.complete, Colors.green, () => _toggleStatus(item, 'complete'), isDark),
          _checkBtn(item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage'), isDark),
          _checkBtn(item.rework, Colors.red, () => _toggleStatus(item, 'rework'), isDark),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextField(
            controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: ''),
            onChanged: (val) => item.remarks = val,
            onTapOutside: (event) {
              FocusScope.of(context).unfocus();
              if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
            },
            onSubmitted: (val) {
              item.remarks = val;
              if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
            },
          ))),
        ],
      ),
    );
  }

  void _toggleStatus(ItemModel item, String type) {
    setState(() {
      if (type == 'complete') { item.complete = !item.complete; if (item.complete) { item.shortage = false; item.rework = false; } }
      else if (type == 'shortage') { item.shortage = !item.shortage; if (item.shortage) { item.complete = false; item.rework = false; } }
      else if (type == 'rework') { item.rework = !item.rework; if (item.rework) { item.complete = false; item.shortage = false; } }
    });
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
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
          Container(
            color: isDark ? Colors.white10 : Colors.black12,
            child: Row(children: [
              _headerBtn("완료", "complete", 50),
              _headerBtn("부족", "shortage", 50),
              _headerBtn("재작업", "rework", 50),
            ]),
          ),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _headerBtn(String label, String colKey, double? width) {
    bool isTarget = _currentSortCol == colKey;
    return InkWell(
      onTap: () => _sortBy(colKey),
      child: Container(
        width: width,
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            if (isTarget)
              Icon(_isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: Colors.yellow, size: 18),
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
