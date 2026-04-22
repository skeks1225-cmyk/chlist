import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_model.dart';
import '../services/excel_service.dart';
import 'pdf_view_screen.dart';
import 'dart:io';

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
        _currentFileName = path.split('/').last.split('\\').last;
        _excelPath = path;
      });
      _saveSettings();
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.\n구조를 확인해 주세요.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result != null && result.files.single.path != null) {
      _loadExcelData(result.files.single.path!);
    }
  }

  Future<void> _pickPdfFolder() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      setState(() {
        _pdfFolderPath = result;
      });
      _saveSettings();
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

  void _showInfo(String title, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  Future<void> _manualSave() async {
    if (_excelPath.isEmpty) return;
    bool success = await _excelService.saveExcel(_excelPath, _items);
    if (success) {
      _showInfo("알림", "저장 완료");
    } else {
      _showError("오류", "저장에 실패했습니다.");
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
                Expanded(child: ElevatedButton(onPressed: _pickExcel, child: const Text("엑셀 선택", style: TextStyle(fontSize: 11)))),
                const SizedBox(width: 4),
                Expanded(child: ElevatedButton(onPressed: _pickPdfFolder, child: const Text("PDF 폴더", style: TextStyle(fontSize: 11)))),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _manualSave,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                  child: const Text("저장", style: TextStyle(fontSize: 11)),
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
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: IntrinsicHeight(
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
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: TextField(
                                  controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                                  style: const TextStyle(fontSize: 10),
                                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.all(4)),
                                  onChanged: (val) {
                                    item.remarks = val;
                                    if (_autoSave && _excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
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
      height: 30,
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
