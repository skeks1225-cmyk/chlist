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
        // 경로 구분자 문제 해결을 위해 path lib 사용 고려 (여기서는 간단히 처리)
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

  void _toggleStatus(ItemModel item, String type) {
    setState(() {
      if (type == 'complete') {
        item.complete = !item.complete;
        if (item.complete) {
          item.shortage = false;
          item.rework = false;
        }
      } else if (type == 'shortage') {
        item.shortage = !item.shortage;
        if (item.shortage) {
          item.complete = false;
          item.rework = false;
        }
      } else if (type == 'rework') {
        item.rework = !item.rework;
        if (item.rework) {
          item.complete = false;
          item.shortage = false;
        }
      }
    });
    if (_autoSave && _excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
  }

  void _showResetConfirm() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("데이터 리셋"),
        content: const Text("모든 체크와 비고를 지우시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("아니오")),
          TextButton(
            onPressed: () {
              setState(() {
                for (var item in _items) {
                  item.complete = false;
                  item.shortage = false;
                  item.rework = false;
                  item.remarks = "";
                }
              });
              if (_autoSave && _excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
              Navigator.pop(ctx);
            },
            child: const Text("예"),
          ),
        ],
      ),
    );
  }

  void _sortBy(String col) {
    setState(() {
      if (col == 'itemCode') {
        _items.sort((a, b) => a.itemCode.compareTo(b.itemCode));
      } else if (col == 'no') {
        _items.sort((a, b) {
          int? na = int.tryParse(a.no);
          int? nb = int.tryParse(b.no);
          if (na == null || nb == null) return a.no.compareTo(b.no);
          return na.compareTo(nb);
        });
      } else if (col == 'quantity') {
        _items.sort((a, b) {
          int? qa = int.tryParse(a.quantity);
          int? qb = int.tryParse(b.quantity);
          if (qa == null || qb == null) return a.quantity.compareTo(b.quantity);
          return qa.compareTo(qb);
        });
      }
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
            label: Text(_autoSave ? "자동저장 ON" : "자동저장 OFF", style: const TextStyle(color: Colors.white, fontSize: 12)),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: _pickExcel, child: const Text("엑셀 선택", style: TextStyle(fontSize: 12)))),
                const SizedBox(width: 4),
                Expanded(child: ElevatedButton(onPressed: _pickPdfFolder, child: const Text("PDF 폴더", style: TextStyle(fontSize: 12)))),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _showResetConfirm,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
                  child: const Text("리셋", style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () {
                    if (_excelPath.isNotEmpty) _excelService.saveExcel(_excelPath, _items);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                  child: const Text("저장", style: TextStyle(fontSize: 12)),
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
                      height: 45,
                      child: Row(
                        children: [
                          SizedBox(width: 40, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
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
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                color: Colors.blue[50],
                                alignment: Alignment.center,
                                child: Text(item.itemCode, style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                          Expanded(flex: 1, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
                          _buildCheckBtn(item.complete, Colors.green, () => _toggleStatus(item, 'complete')),
                          _buildCheckBtn(item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage')),
                          _buildCheckBtn(item.rework, Colors.red, () => _toggleStatus(item, 'rework')),
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
          _buildHeaderBtn("No", 40, () => _sortBy('no')),
          Expanded(flex: 3, child: _buildHeaderBtn("품목코드", null, () => _sortBy('itemCode'))),
          Expanded(flex: 1, child: _buildHeaderBtn("수량", null, () => _sortBy('quantity'))),
          _buildHeaderBtn("완료", 50, null),
          _buildHeaderBtn("부족", 50, null),
          _buildHeaderBtn("재작", 50, null),
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
        child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
