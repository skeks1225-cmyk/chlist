import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:external_path/external_path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smb_connect/smb_connect.dart' as smb;
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _ensureBaseDirectory();
  }

  Future<void> _ensureBaseDirectory() async {
    String downloadPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOADS);
    final baseDir = Directory("$downloadPath/CheckSheet");
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
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) _loadExcelData(_excelPath);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
  }

  Future<void> _saveLastDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastDir', p.dirname(path));
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
      });
      _saveSettings();
      _saveLastDir(path);
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetSort() {
    setState(() {
      _displayItems = List.from(_originalItems);
      _isSorted = false;
    });
  }

  void _sortBy(String col) {
    setState(() {
      _isSorted = true;
      _displayItems = _originalItems.where((i) => !i.isSubheading).toList();
      if (col == 'itemCode') {
        _displayItems.sort((a, b) => a.itemCode.compareTo(b.itemCode));
      } else if (col == 'no') {
        _displayItems.sort((a, b) => (int.tryParse(a.no) ?? 0).compareTo(int.tryParse(b.no) ?? 0));
      } else if (col == 'quantity') {
        _displayItems.sort((a, b) => (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0));
      }
    });
  }

  Future<void> _pickSource(String mode) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text("내 휴대폰"),
            onTap: () { Navigator.pop(ctx); _openCustomPicker(mode); },
          ),
          ListTile(
            leading: const Icon(Icons.computer),
            title: const Text("PC 공유폴더 (SMB)"),
            onTap: () { Navigator.pop(ctx); _openSmbShares(mode); },
          ),
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("외부설정 (SMB)", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ipController, decoration: const InputDecoration(labelText: "IP 주소")),
            TextField(controller: userController, decoration: const InputDecoration(labelText: "사용자 ID")),
            TextField(controller: passController, decoration: const InputDecoration(labelText: "비밀번호"), obscureText: true),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                // ❗ 인자 개수 3개로 교정
                String? err = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                _showError(err == null ? "성공" : "접속 실패", err ?? "✅ 접속 성공!");
              },
              child: const Text("접속 테스트"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          TextButton(
            onPressed: () async {
              await prefs.setString('smbIp', ipController.text);
              await prefs.setString('smbUser', userController.text);
              await prefs.setString('smbPass', passController.text);
              // ❗ 인자 개수 3개로 교정
              _smbService.setConfig(ipController.text, userController.text, passController.text);
              Navigator.pop(ctx);
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  void _openSmbShares(String mode) async {
    setState(() => _isLoading = true);
    List<String> shares = await _smbService.listShares();
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (shares.isEmpty) { _showError("오류", "공유폴더를 찾을 수 없습니다. 설정을 확인하세요."); return; }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("공유폴더 선택"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: shares.length,
            itemBuilder: (c, i) => ListTile(
              leading: const Icon(Icons.folder_shared),
              title: Text(shares[i]),
              onTap: () { Navigator.pop(ctx); _showSmbFiles(shares[i], "/", mode); },
            ),
          ),
        ),
      ),
    );
  }

  void _showSmbFiles(String share, String path, String mode) async {
    setState(() => _isLoading = true);
    List<smb.SmbFile> files = await _smbService.listFiles(share, path);
    setState(() => _isLoading = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$share$path"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              if (path != "/") ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showSmbFiles(share, p.dirname(path), mode); }),
              Expanded(
                child: ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (c, i) {
                    final f = files[i];
                    // ❗ .isDirectory 를 함수형태인 .isDirectory() 로 수정
                    bool isDir = f.isDirectory(); 
                    return ListTile(
                      leading: Icon(isDir ? Icons.folder : Icons.description),
                      title: Text(f.name),
                      onTap: () async {
                        if (isDir) { Navigator.pop(ctx); _showSmbFiles(share, "${path == "/" ? "" : path}/${f.name}", mode); }
                        else if (mode == 'file') {
                          Navigator.pop(ctx);
                          _downloadAndLoad(share, "${path == "/" ? "" : path}/${f.name}");
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = "smb://$share$path"); _saveSettings(); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
        ],
      ),
    );
  }

  Future<void> _downloadAndLoad(String share, String remotePath) async {
    setState(() => _isLoading = true);
    String downloadPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOADS);
    String localPath = "$downloadPath/CheckSheet/${p.basename(remotePath)}";
    File? file = await _smbService.downloadFile(share, remotePath, localPath);
    setState(() => _isLoading = false);

    if (file != null) _loadExcelData(file.path);
    else _showError("오류", "파일 다운로드 실패");
  }

  Future<void> _openCustomPicker(String mode) async {
    if (Platform.isAndroid) { if (!await Permission.manageExternalStorage.isGranted) await Permission.manageExternalStorage.request(); }
    final prefs = await SharedPreferences.getInstance();
    String downloadPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOADS);
    String startPath = prefs.getString('lastDir') ?? "$downloadPath/CheckSheet";
    if (!Directory(startPath).existsSync()) startPath = downloadPath;
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
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  ListTile(leading: const Icon(Icons.arrow_upward), title: const Text(".. 상위"), onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); }),
                  Expanded(child: ListView.builder(itemCount: entities.length, itemBuilder: (c, i) {
                    final e = entities[i];
                    final isDir = e is Directory;
                    return ListTile(
                      leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue),
                      title: Text(p.basename(e.path)),
                      onTap: () {
                        if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); }
                        else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); }
                      },
                    );
                  })),
                ],
              ),
            ),
            actions: [
              if (mode == 'dir') TextButton(onPressed: () { setState(() => _pdfFolderPath = initialPath); _saveSettings(); _saveLastDir(initialPath + "/f.pdf"); Navigator.pop(ctx); }, child: const Text("현재 폴더 선택")),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ],
          );
        },
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

  void _toggleStatus(ItemModel item, String type) {
    setState(() {
      if (type == 'complete') {
        item.complete = !item.complete;
        if (item.complete) { item.shortage = false; item.rework = false; }
      } else if (type == 'shortage') {
        item.shortage = !item.shortage;
        if (item.shortage) { item.complete = false; item.rework = false; }
      } else if (type == 'rework') {
        item.rework = !item.rework;
        if (item.rework) { item.complete = false; item.shortage = false; }
      }
    });
    if (_autoSave) _manualSave(silent: true);
  }

  void _showResetConfirm() {
    if (_originalItems.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("데이터 리셋"), content: const Text("모든 체크와 비고를 지우시겠습니까?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")), TextButton(onPressed: () { _resetAllData(); Navigator.pop(ctx); }, child: const Text("예", style: TextStyle(color: Colors.red)))]));
  }

  void _resetAllData() {
    setState(() { for (var item in _originalItems) { item.complete = false; item.shortage = false; item.rework = false; item.remarks = ""; } _displayItems = List.from(_originalItems); _isSorted = false; });
    if (_autoSave) _manualSave(silent: true);
  }

  Widget _topBtn(String label, VoidCallback onTap, bool isDark) {
    return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45), padding: EdgeInsets.zero), child: Text(label, style: const TextStyle(fontSize: 12))));
  }

  Widget _buildDataRow(ItemModel item, bool isDark) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))),
      height: 48,
      child: Row(
        children: [
          SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          Expanded(flex: 5, child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PdfViewerScreen(items: _displayItems.where((i) => !i.isSubheading).toList(), initialIndex: _displayItems.where((i) => !i.isSubheading).toList().indexOf(item), pdfFolderPath: _pdfFolderPath, onStatusUpdate: (it, type) => _toggleStatus(it, type)))),
            child: Container(padding: const EdgeInsets.only(left: 8), alignment: Alignment.centerLeft, child: Text(item.itemCode, style: TextStyle(fontSize: 13, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          )),
          SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          _checkBtn(item.complete, Colors.green, () => _toggleStatus(item, 'complete'), isDark),
          _checkBtn(item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage'), isDark),
          _checkBtn(item.rework, Colors.red, () => _toggleStatus(item, 'rework'), isDark),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: TextField(
            controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            onSubmitted: (val) { item.remarks = val; if (_autoSave) _manualSave(silent: true); },
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
          _headerBtn("No", 35, () => _sortBy('no')),
          Expanded(flex: 5, child: _headerBtn("품목코드", null, () => _sortBy('itemCode'))),
          _headerBtn("수량", 40, () => _sortBy('quantity')),
          Container(color: isDark ? Colors.white10 : Colors.black12, child: Row(children: [_headerBtn("완료", 50, null), _headerBtn("부족", 50, null), _headerBtn("재작업", 50, null)])),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _headerBtn(String label, double? width, VoidCallback? onTap) {
    return InkWell(onTap: onTap, child: Container(width: width, alignment: Alignment.center, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))));
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
}
