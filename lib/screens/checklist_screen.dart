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

  // Kivy 버전과 동일한 로컬 저장 기본 경로
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
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String title, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 800), behavior: SnackBarBehavior.floating),
    );
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
            onTap: () {
              Navigator.pop(ctx);
              _pickLocal(mode);
            },
          ),
          ListTile(
            leading: const Icon(Icons.computer),
            title: const Text("PC 공유폴더 (SMB)"),
            onTap: () {
              Navigator.pop(ctx);
              // TODO: SMB 브라우저 구현 시 연결
              _showError("알림", "SMB 연동은 다음 패치에서 제공됩니다.");
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickLocal(String mode) async {
    if (mode == 'file') {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result != null && result.files.single.path != null) {
        _loadExcelData(result.files.single.path!);
      }
    } else {
      String? result = await FilePicker.platform.getDirectoryPath();
      if (result != null) {
        setState(() => _pdfFolderPath = result);
        _saveSettings();
      }
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
    if (_autoSave && _excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentFileName, style: const TextStyle(fontSize: 14)),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: () {
              setState(() => _autoSave = !_autoSave);
              _saveSettings();
            },
            icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red),
            label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white, fontSize: 12)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () => _pickSource('file'), child: const Text("엑셀 선택"))),
                const SizedBox(width: 4),
                Expanded(child: ElevatedButton(onPressed: () => _pickSource('dir'), child: const Text("PDF 폴더"))),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () async {
                    if (_excelPath.isNotEmpty) {
                      bool ok = await _excelService.saveExcel(_excelPath, _items);
                      if (ok) _showSnackBar("저장 완료");
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                  child: const Text("저장"),
                ),
              ],
            ),
          ),
          _buildHeader(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, idx) {
                    final item = _items[idx];
                    return Container(
                      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
                      height: 50,
                      child: Row(
                        children: [
                          SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                          Expanded(
                            flex: 2,
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
                                color: Colors.blue[50],
                                alignment: Alignment.center,
                                child: Text(item.itemCode, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          SizedBox(width: 30, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),
                          _buildCheckBtn(item.complete, Colors.green, () => _toggleStatus(item, 'complete')),
                          _buildCheckBtn(item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage')),
                          _buildCheckBtn(item.rework, Colors.red, () => _toggleStatus(item, 'rework')),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: TextField(
                                controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                                style: const TextStyle(fontSize: 10),
                                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                                onSubmitted: (val) {
                                  item.remarks = val;
                                  if (_autoSave && _excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
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

  Widget _buildHeader() {
    return Container(
      color: Colors.grey[800],
      height: 35,
      child: Row(
        children: [
          _buildHeaderBtn("No", 35, () => _sortBy('no')),
          Expanded(flex: 2, child: _buildHeaderBtn("품목코드", null, () => _sortBy('itemCode'))),
          _buildHeaderBtn("Qty", 30, () => _sortBy('quantity')),
          _buildHeaderBtn("완료", 45, null),
          _buildHeaderBtn("부족", 45, null),
          _buildHeaderBtn("재작", 45, null),
          const Expanded(flex: 2, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 11)))),
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
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  Widget _buildCheckBtn(bool val, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 45,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: val ? color.withOpacity(0.2) : Colors.transparent, border: Border.all(color: Colors.grey[200]!, width: 0.5)),
        child: val ? Icon(Icons.check, color: color, size: 16) : null,
      ),
    );
  }
}
