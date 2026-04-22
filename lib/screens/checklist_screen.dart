import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:external_path/external_path.dart';
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
  
  List<ItemModel> _originalItems = []; // ❗ 저장 및 리셋용 원본 리스트
  List<ItemModel> _displayItems = [];  // ❗ 화면 표시 및 정렬용 리스트
  
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
    } catch (e) {
      _showError("로드 오류", "엑셀 파일을 읽을 수 없습니다.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ❗ 정렬 리셋 기능
  void _resetSort() {
    setState(() {
      _displayItems = List.from(_originalItems);
      _isSorted = false;
    });
  }

  // ❗ 스마트 숫자 정렬 및 소제목 숨기기
  void _sortBy(String col) {
    setState(() {
      _isSorted = true;
      // 1. 소제목 제외한 데이터만 필터링
      _displayItems = _originalItems.where((i) => !i.isSubheading).toList();
      
      // 2. 정렬 수행
      if (col == 'itemCode') {
        _displayItems.sort((a, b) => a.itemCode.compareTo(b.itemCode));
      } else if (col == 'no') {
        _displayItems.sort((a, b) {
          int na = int.tryParse(a.no) ?? 0;
          int nb = int.tryParse(b.no) ?? 0;
          return na.compareTo(nb);
        });
      } else if (col == 'quantity') {
        _displayItems.sort((a, b) {
          int qa = int.tryParse(a.quantity) ?? 0;
          int qb = int.tryParse(b.quantity) ?? 0;
          return qa.compareTo(qb);
        });
      }
    });
  }

  // ❗ 외부설정(SMB) 팝업
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
                bool ok = await _smbService.testConnection(ipController.text, userController.text, passController.text);
                _showSnackBar(ok ? "✅ 접속 성공!" : "❌ 접속 실패");
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
              _smbService.setConfig(ipController.text, userController.text, passController.text);
              Navigator.pop(ctx);
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  Future<void> _manualSave({bool silent = false}) async {
    if (_excelPath.isEmpty) return;
    // ❗ 정렬 상태와 상관없이 항상 _originalItems(원본 순서)를 저장
    bool ok = await _excelService.saveExcel(_excelPath, _originalItems);
    if (ok && !silent) _showSnackBar("💾 저장 성공!");
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("CheckSheet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(_currentFileName, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          if (_isSorted) IconButton(onPressed: _resetSort, icon: const Icon(Icons.refresh), tooltip: "정렬 리셋"),
          TextButton.icon(
            onPressed: () { setState(() => _autoSave = !_autoSave); _saveSettings(); },
            icon: Icon(Icons.save, color: _autoSave ? Colors.green : Colors.red),
            label: Text(_autoSave ? "자동 ON" : "자동 OFF", style: const TextStyle(color: Colors.white)),
          )
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
                _topBtn("엑셀선택", () => _openCustomPicker('file'), isDark),
                const SizedBox(width: 4),
                _topBtn("PDF폴더", () => _openCustomPicker('dir'), isDark),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: _manualSave,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white, minimumSize: const Size(60, 45)),
                  child: const Text("저장"),
                ),
              ],
            ),
          ),
          _buildHeader(context),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _displayItems.length,
                  itemBuilder: (ctx, idx) {
                    final item = _displayItems[idx];
                    // ❗ 소제목 행 디자인
                    if (item.isSubheading) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: isDark ? Colors.white10 : Colors.grey[300],
                        width: double.infinity,
                        child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      );
                    }
                    // 일반 데이터 행 디자인
                    return _buildDataRow(item, isDark, idx);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _topBtn(String label, VoidCallback onTap, bool isDark) {
    return Expanded(child: ElevatedButton(onPressed: onTap, style: ElevatedButton.styleFrom(minimumSize: const Size(0, 45)), child: Text(label, style: const TextStyle(fontSize: 13))));
  }

  Widget _buildDataRow(ItemModel item, bool isDark, int idx) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey[300]!))),
      height: 48,
      child: Row(
        children: [
          SizedBox(width: 35, child: Text(item.no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          Expanded(
            flex: 5,
            child: InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PdfViewerScreen(
                  items: _displayItems.where((i) => !i.isSubheading).toList(),
                  initialIndex: _displayItems.where((i) => !i.isSubheading).toList().indexOf(item),
                  pdfFolderPath: _pdfFolderPath,
                  onStatusUpdate: (it, type) => _toggleStatus(it, type),
                ),
              )),
              child: Container(
                padding: const EdgeInsets.only(left: 8), // ❗ 좌측 정렬
                alignment: Alignment.centerLeft,
                child: Text(item.itemCode, style: TextStyle(fontSize: 14, color: isDark ? Colors.blue[300] : Colors.blue[700], fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
          SizedBox(width: 40, child: Text(item.quantity, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
          _checkBtn(item.complete, Colors.green, () => _toggleStatus(item, 'complete'), isDark),
          _checkBtn(item.shortage, Colors.orange, () => _toggleStatus(item, 'shortage'), isDark),
          _checkBtn(item.rework, Colors.red, () => _toggleStatus(item, 'rework'), isDark),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: TextEditingController(text: item.remarks)..selection = TextSelection.fromPosition(TextPosition(offset: item.remarks.length)),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                onSubmitted: (val) { item.remarks = val; if (_autoSave) _manualSave(silent: true); },
              ),
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
          _headerBtn("No", 35, () => _sortBy('no')),
          Expanded(flex: 5, child: _headerBtn("품목코드", null, () => _sortBy('itemCode'))),
          _headerBtn("수량", 40, () => _sortBy('quantity')),
          // 상태 영역 배경색 차별화
          Container(
            color: isDark ? Colors.white10 : Colors.black12,
            child: Row(
              children: [
                _headerBtn("완료", 50, null),
                _headerBtn("부족", 50, null),
                _headerBtn("재작업", 50, null),
              ],
            ),
          ),
          const Expanded(flex: 3, child: Center(child: Text("비고", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }

  Widget _headerBtn(String label, double? width, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(width: width, alignment: Alignment.center, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
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

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Center(child: Text(msg)), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating));
  }

  // ... (기존 탐색기 메서드 _openCustomPicker, _showFileBrowser 는 그대로 유지 또는 소폭 수정)
  // ... (기존 _showError 메서드 유지)
}
