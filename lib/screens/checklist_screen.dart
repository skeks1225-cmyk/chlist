import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final String _localBase = "/sdcard/Download/CheckSheet";

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _ensureLocalDirectory();
  }

  void _ensureLocalDirectory() {
    final dir = Directory(_localBase);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
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
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.\n권한이나 파일 구조를 확인해 주세요.");
    } finally {
      setState(() => _isLoading = false);
    }
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
      SnackBar(
        content: Center(child: Text(msg, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), 
        duration: const Duration(seconds: 1), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blueGrey[800],
      ),
    );
  }

  Future<void> _manualSave({bool silent = false}) async {
    if (_excelPath.isEmpty) return;
    try {
      bool ok = await _excelService.saveExcel(_excelPath, _items);
      if (ok) {
        if (!silent) _showSnackBar("💾 저장 성공!");
      } else {
        _showError("저장 실패", "파일에 접근할 수 없습니다.\n다른 앱에서 사용 중인지 확인해 주세요.");
      }
    } catch (e) {
      _showError("저장 오류", e.toString());
    }
  }

  Future<void> _pickSource(String mode) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android, size: 28),
            title: const Text("내 휴대폰", style: TextStyle(fontSize: 18)),
            onTap: () { Navigator.pop(ctx); _pickLocal(mode); },
          ),
          ListTile(
            leading: const Icon(Icons.computer, size: 28),
            title: const Text("PC 공유폴더 (SMB)", style: TextStyle(fontSize: 18)),
            onTap: () { Navigator.pop(ctx); _showError("알림", "SMB 연동은 곧 제공됩니다."); },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _pickLocal(String mode) async {
    if (mode == 'file') {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls']);
      if (result != null && result.files.single.path != null) {
        _loadExcelData(result.files.single.path!);
      }
    } else {
      String? result = await FilePicker.platform.getDirectoryPath();
      if (result != null) { setState(() => _pdfFolderPath = result); _saveSettings(); }
    }
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
        title: Text(_currentFileName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); },
            icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red, size: 24),
            label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white, fontSize: 14)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () => _pickSource('file'), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45)), child: const Text("엑셀 선택", style: TextStyle(fontSize: 14)))),
                const SizedBox(width: 4),
                Expanded(child: ElevatedButton(onPressed: () => _pickSource('dir'), style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45)), child: const Text("PDF 폴더", style: TextStyle(fontSize: 14)))),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _manualSave(),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, minimumSize: const Size(80, 45)),
                  child: const Text("저장", style: TextStyle(fontSize: 14)),
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
                      height: 55, // 행 높이 상향
                      child: Row(
                        children: [
                          SizedBox(width: 40, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                          Expanded(
                            flex: 3,
                            child: InkWell(
                              onTap: () {
                                if (_pdfFolderPath.isEmpty) {
                                  _showError("알림", "PDF 폴더를 먼저 선택해 주세요.");
                                  return;
                                }
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => PdfViewerScreen(
                                    items: _items,
                                    initialIndex: idx,
                                    pdfFolderPath: _pdfFolderPath,
                                    onStatusUpdate: (it, type) => _toggleStatus(it, type),
                                  ),
                                ));
                              },

                              child: Container(
                                color: isDark ? Colors.blueGrey[900] : Colors.blue[50],
                                alignment: Alignment.center,
                                child: Text(item.itemCode, style: TextStyle(fontSize: 14, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                          _buildCheckBtn(context, item.complete, Colors.green, () => _toggleStatus(item, 'complete')),
                          _buildCheckBtn(context, item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage')),
                          _buildCheckBtn(context, item.rework, Colors.red, () => _toggleStatus(item, 'rework')),
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: '비고 입력', hintStyle: TextStyle(fontSize: 12)),
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
      height: 40,
      child: Row(
        children: [
          _buildHeaderBtn("No", 40, () => _sortBy('no')),
          Expanded(flex: 3, child: _buildHeaderBtn("품목코드", null, () => _sortBy('itemCode'))),
          _buildHeaderBtn("Qty", 40, () => _sortBy('quantity')),
          _buildHeaderBtn("완료", 50, null),
          _buildHeaderBtn("부족", 50, null),
          _buildHeaderBtn("재작", 50, null),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _buildHeaderBtn(String label, double? width, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _buildCheckBtn(BuildContext context, bool val, Color color, VoidCallback onTap) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: val ? color.withOpacity(0.3) : Colors.transparent, 
          border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!, width: 0.5)
        ),
        child: val ? Icon(Icons.check, color: color, size: 22) : null,
      ),
    );
  }
}
