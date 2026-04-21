import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/checklist_item.dart';
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
  List<ChecklistItem> _items = [];
  String _excelPath = "";
  String _pdfFolderPath = "";
  String _currentFileName = "파일을 선택하세요";
  bool _autoSave = true;

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
      if (_excelPath.isNotEmpty && File(_excelPath).existsSync()) {
        _loadExcelData(_excelPath);
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('excelPath', _excelPath);
    await prefs.setString('pdfFolderPath', _pdfFolderPath);
    await prefs.setBool('autoSave', _autoSave);
  }

  Future<void> _loadExcelData(String path) async {
    try {
      final items = await _excelService.loadExcel(path);
      setState(() {
        _items = items;
        _currentFileName = path.split(Platform.pathSeparator).last;
        _excelPath = path;
      });
      _saveSettings();
    } catch (e) {
      _showError("로드 오류", e.toString());
    }
  }

  Future<void> _pickExcel() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (result != null) {
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

  void _updateStatus(ChecklistItem item, String type) {
    setState(() {
      if (type == 'complete') {
        item.isComplete = !item.isComplete;
        if (item.isComplete) {
          item.isShortage = false;
          item.isRework = false;
        }
      } else if (type == 'shortage') {
        item.isShortage = !item.isShortage;
        if (item.isShortage) {
          item.isComplete = false;
          item.isRework = false;
        }
      } else if (type == 'rework') {
        item.isRework = !item.isRework;
        if (item.isRework) {
          item.isComplete = false;
          item.isShortage = false;
        }
      }
    });
    if (_autoSave) _excelService.saveExcel(_excelPath, _items);
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
            label: Text(_autoSave ? "자동저장 ON" : "자동저장 OFF", style: const TextStyle(color: Colors.white)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _pickExcel, child: const Text("엑셀선택"))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: _pickPdfFolder, child: const Text("PDF폴더"))),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _excelService.saveExcel(_excelPath, _items),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                  child: const Text("저장"),
                ),
              ],
            ),
          ),
          _buildHeader(),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (ctx, idx) => _buildRow(_items[idx]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.grey[800],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: const [
          SizedBox(width: 40, child: Text("No", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text("품목코드", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          Expanded(flex: 1, child: Text("수량", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          SizedBox(width: 50, child: Text("완료", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          SizedBox(width: 50, child: Text("부족", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          SizedBox(width: 50, child: Text("재작", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildRow(ChecklistItem item) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
      height: 40,
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (ctx) => PdfViewScreen(
                  items: _items,
                  initialIndex: _items.indexOf(item),
                  pdfFolderPath: _pdfFolderPath,
                  onStatusUpdate: (it, type) => _updateStatus(it, type),
                ),
              )),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.blue[50],
                alignment: Alignment.center,
                child: Text(item.itemCode, style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          Expanded(flex: 1, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          _buildCheckBtn(item.isComplete, Colors.green, () => _updateStatus(item, 'complete')),
          _buildCheckBtn(item.isShortage, Colors.orange, () => _updateStatus(item, 'shortage')),
          _buildCheckBtn(item.isRework, Colors.red, () => _updateStatus(item, 'rework')),
        ],
      ),
    );
  }

  Widget _buildCheckBtn(bool val, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 50,
        height: double.infinity,
        decoration: BoxDecoration(
          color: val ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: val ? Icon(Icons.check, color: color, size: 20) : null,
      ),
    );
  }
}
