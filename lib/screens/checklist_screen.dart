import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:external_path/external_path.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
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
  List<ItemModel> _items = [];
  String _excelPath = "";
  String _pdfFolderPath = "";
  String _currentFileName = "파일을 선택하세요";
  bool _autoSave = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _ensureBaseDirectory();
  }

  // ❗ 기본 경로 보장: Download/CheckSheet
  Future<void> _ensureBaseDirectory() async {
    String downloadPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOADS);
    final baseDir = Directory("$downloadPath/CheckSheet");
    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _excelPath = prefs.getString('excelPath') ?? "";
      _pdfFolderPath = prefs.getString('pdfFolderPath') ?? "";
      _autoSave = prefs.getBool('autoSave') ?? true;
    });
    if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) {
      _loadExcelData(_excelPath);
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
  }

  // ❗ 마지막 사용 폴더 저장 (폴더 기억용)
  Future<void> _saveLastDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastDir', p.dirname(path));
  }

  Future<void> _loadExcelData(String path) async {
    setState(() => _isLoading = true);
    try {
      final items = await _excelService.loadExcel(path);
      setState(() {
        _items = items;
        _currentFileName = p.basename(path);
        _excelPath = path;
      });
      _saveSettings();
      _saveLastDir(path);
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openCustomPicker(String mode) async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    final prefs = await SharedPreferences.getInstance();
    String? lastDir = prefs.getString('lastDir');
    String downloadPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOWNLOADS);
    
    // 우선순위: 마지막 사용 폴더 -> Download/CheckSheet -> Download
    String startPath = lastDir ?? "$downloadPath/CheckSheet";
    if (!Directory(startPath).existsSync()) {
      startPath = downloadPath;
    }

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
            title: Text(p.basename(initialPath), style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text(".. 상위 폴더로"),
                    onTap: () { Navigator.pop(ctx); _showFileBrowser(mode, p.dirname(initialPath)); },
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: entities.length,
                      itemBuilder: (c, i) {
                        final e = entities[i];
                        final isDir = e is Directory;
                        return ListTile(
                          leading: Icon(isDir ? Icons.folder : Icons.description, color: isDir ? Colors.amber : Colors.blue),
                          title: Text(p.basename(e.path), style: const TextStyle(fontSize: 14)),
                          onTap: () {
                            if (isDir) { Navigator.pop(ctx); _showFileBrowser(mode, e.path); }
                            else if (mode == 'file') { Navigator.pop(ctx); _loadExcelData(e.path); }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (mode == 'dir') 
                TextButton(
                  onPressed: () {
                    setState(() => _pdfFolderPath = initialPath);
                    _saveSettings();
                    _saveLastDir(initialPath + "/fake.pdf");
                    Navigator.pop(ctx);
                  },
                  child: const Text("현재 폴더 선택", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
            ],
          );
        },
      ),
    );
  }

  void _showError(String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인", style: TextStyle(fontSize: 16)))],
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Center(child: Text(msg, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _manualSave({bool silent = false}) async {
    if (_excelPath.isEmpty) return;
    bool ok = await _excelService.saveExcel(_excelPath, _items);
    if (ok) { if (!silent) _showSnackBar("💾 저장 성공!"); }
    else { _showError("저장 실패", "다른 앱에서 사용 중이거나 권한이 없습니다."); }
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
    if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
  }

  void _sortBy(String col) {
    setState(() {
      if (col == 'itemCode') _items.sort((a, b) => a.itemCode.compareTo(b.itemCode));
      else if (col == 'no') _items.sort((a, b) => (int.tryParse(a.no) ?? 0).compareTo(int.tryParse(b.no) ?? 0));
      else if (col == 'quantity') _items.sort((a, b) => (int.tryParse(a.quantity) ?? 0).compareTo(int.tryParse(b.quantity) ?? 0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); },
            icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red, size: 26),
            label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white, fontSize: 16)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () => _openCustomPicker('file'), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 55)), child: const Text("엑셀 선택", style: TextStyle(fontSize: 16)))),
                const SizedBox(width: 6),
                Expanded(child: ElevatedButton(onPressed: () => _openCustomPicker('dir'), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 55)), child: const Text("PDF 폴더", style: TextStyle(fontSize: 16)))),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _manualSave,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, minimumSize: const Size(90, 55)),
                  child: const Text("저장", style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
          _buildHeader(context),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, idx) {
                    final item = _items[idx];
                    return Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!))),
                      height: 65,
                      child: Row(
                        children: [
                          SizedBox(width: 45, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15))),
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                  items: _items,
                                  initialIndex: idx,
                                  pdfFolderPath: _pdfFolderPath,
                                  onStatusUpdate: (it, type) => _toggleStatus(it, type),
                                ),
                              )),
                              child: Container(
                                color: isDark ? Colors.blueGrey[900] : Colors.blue[50],
                                alignment: Alignment.center,
                                child: Text(item.itemCode, style: TextStyle(fontSize: 15, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          SizedBox(width: 45, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15))),
                          _buildCheckBtn(context, item.complete, Colors.green, () => _toggleStatus(item, 'complete')),
                          _buildCheckBtn(context, item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage')),
                          _buildCheckBtn(context, item.rework, Colors.red, () => _toggleStatus(item, 'rework')),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: TextField(
                                controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                                style: const TextStyle(fontSize: 15),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: '비고'),
                                onSubmitted: (val) {
                                  item.remarks = val;
                                  if (_autoSave && _excelPath.isNotEmpty) _manualSave(silent: true);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? Colors.grey[900] : Colors.grey[800],
      height: 45,
      child: Row(
        children: [
          const SizedBox(width: 45, child: Center(child: Text("No", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const Expanded(flex: 3, child: Center(child: Text("품목코드", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const SizedBox(width: 45, child: Center(child: Text("Qty", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const SizedBox(width: 55, child: Center(child: Text("완료", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const SizedBox(width: 55, child: Center(child: Text("부족", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const SizedBox(width: 55, child: Center(child: Text("재작", style: TextStyle(color: Colors.white, fontSize: 16)))),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 16)))),
        ],
      ),
    );
  }

  Widget _buildCheckBtn(BuildContext context, bool val, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 55,
        alignment: Alignment.center,
        // ❗ 테두리(border) 제거 완료
        decoration: BoxDecoration(color: val ? color.withOpacity(0.3) : Colors.transparent),
        child: val ? Icon(Icons.check, color: color, size: 28) : null,
      ),
    );
  }
}
