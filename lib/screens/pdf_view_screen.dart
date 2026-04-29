import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; 
import '../models/item_model.dart';
import '../services/smb_service.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final List<ItemModel> items;
  final int initialIndex;
  final String pdfFolderPath;
  final SmbService smbService;
  final List<String> processList;
  final Function(ItemModel, String) onStatusUpdate;

  const PdfViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.pdfFolderPath,
    required this.smbService,
    required this.processList,
    required this.onStatusUpdate,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _currentIndex;
  String _currentPdfPath = "";
  final PdfViewerController _pdfController = PdfViewerController();
  Key _viewerKey = UniqueKey();
  final TextEditingController _remarksController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    final item = widget.items[_currentIndex];
    final String cleanCode = item.itemCode.trim();
    setState(() => _isLoading = true);

    String localPath = "";
    if (widget.pdfFolderPath.startsWith("smb://")) {
      try {
        String shareWithRest = widget.pdfFolderPath.replaceFirst("smb://", "");
        if (shareWithRest.endsWith("/")) shareWithRest = shareWithRest.substring(0, shareWithRest.length - 1);
        int firstSlash = shareWithRest.indexOf("/");
        String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest;
        String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : "";
        String remoteFilePath = folderPath.isEmpty ? "$cleanCode.pdf" : "$folderPath/$cleanCode.pdf";
        localPath = "/storage/emulated/0/Download/CheckSheet/$cleanCode.pdf";
        await widget.smbService.downloadFile(share, remoteFilePath, localPath);
      } catch (e) { debugPrint("Sync Error: $e"); }
    } else {
      localPath = "${widget.pdfFolderPath}/$cleanCode.pdf";
    }

    _remarksController.text = item.remarks;
    setState(() {
      _currentPdfPath = File(localPath).existsSync() ? localPath : "";
      _viewerKey = UniqueKey();
      _isLoading = false;
    });
  }

  void _resetFit() { _loadPdf(); }

  void _next() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() => _currentIndex++);
      _loadPdf();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _loadPdf();
    }
  }

  void _showComplementDialog(ItemModel item) {
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

  void _showProcessDialog(ItemModel item) {
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
                GridView.count(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2, childAspectRatio: 2.5,
                  mainAxisSpacing: 8, crossAxisSpacing: 8,
                  children: widget.processList.map((p) => ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[700], foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    onPressed: () { setState(() { item.process = p; }); widget.onStatusUpdate(item, 'process'); Navigator.pop(ctx); },
                    child: Text(p),
                  )).toList(),
                ),
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
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        onPressed: () { setState(onSelected); widget.onStatusUpdate(widget.items[_currentIndex], 'update'); Navigator.pop(context); },
        child: Text(label),
      ),
    );
  }

  // ❗ 디자인이 수정된 네비게이션 버튼 (작은 크기, < > 모양)
  Widget _navArrowBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 55, height: 55, // 터치 영역은 원형 그대로 유지
        alignment: Alignment.center,
        child: Icon(
          icon, 
          color: isDark ? Colors.blue[300] : Colors.blue[700], 
          size: 28, // 크기를 하단 버튼 아이콘 수준으로 축소
        ),
      ),
    );
  }

  @override
  void dispose() { _remarksController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color viewerBgColor = isDark ? Colors.black : Colors.grey[300]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.itemCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black : Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: _resetFit, child: const Text("FIT", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
      backgroundColor: isDark ? Colors.black : Colors.grey[200],
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _isLoading 
                    ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.blue))
                    : (_currentPdfPath.isNotEmpty
                        ? Container(color: viewerBgColor, child: PdfViewer.file(_currentPdfPath, key: _viewerKey, controller: _pdfController, params: PdfViewerParams(maxScale: 15.0, backgroundColor: viewerBgColor)))
                        : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, color: Colors.red, size: 50), const SizedBox(height: 10), Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)), const SizedBox(height: 5), Text("파일: ${item.itemCode}.pdf", style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12))]))),
                
                // ❗ 위치가 중앙으로 더 모인 < > 모양 버튼
                Positioned(left: 10, top: 80, child: _navArrowBtn(Icons.arrow_back_ios_new, _prev, isDark)),
                Positioned(left: 10, bottom: 80, child: _navArrowBtn(Icons.arrow_forward_ios, _next, isDark)),
                Positioned(right: 10, top: 80, child: _navArrowBtn(Icons.arrow_back_ios_new, _prev, isDark)),
                Positioned(right: 10, bottom: 80, child: _navArrowBtn(Icons.arrow_forward_ios, _next, isDark)),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              color: isDark ? Colors.grey[900] : Colors.white,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _remarksController,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: "비고 입력...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                        filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: _remarksController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel, color: Colors.grey), onPressed: () { setState(() => _remarksController.clear()); item.remarks = ""; widget.onStatusUpdate(item, 'remarks'); }) : null,
                      ),
                      onChanged: (val) { item.remarks = val; setState(() {}); },
                      onSubmitted: (val) { item.remarks = val; widget.onStatusUpdate(item, 'remarks'); },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statusBtn("완료", Colors.green, item.complete, () { widget.onStatusUpdate(item, 'complete'); setState(() {}); }),
                      _statusBtn("보완", Colors.orange, item.complement.isNotEmpty, () => _showComplementDialog(item)),
                      _statusBtn("공정", Colors.blueGrey, item.process.isNotEmpty, () => _showProcessDialog(item)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(onPressed: _prev, icon: const Icon(Icons.arrow_back), label: const Text("이전", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: isDark ? Colors.white : Colors.blueGrey[900])),
                      Text("${_currentIndex + 1} / ${widget.items.length}", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: const Text("다음", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: isDark ? Colors.white : Colors.blueGrey[900])),
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _statusBtn(String label, Color color, bool active, VoidCallback onTap) {
    final item = widget.items[_currentIndex];
    String subText = "";
    if (label == "보완") subText = item.complement;
    if (label == "공정") subText = item.process;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: active ? color : Colors.grey[400]?.withOpacity(0.5), 
            foregroundColor: active ? Colors.white : Colors.black54,
            minimumSize: const Size(0, 55), padding: EdgeInsets.zero,
            elevation: active ? 2 : 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label, 
                style: TextStyle(
                  fontWeight: subText.isEmpty ? FontWeight.bold : FontWeight.normal, 
                  fontSize: subText.isEmpty ? 15 : 12,
                ),
              ),
              if (subText.isNotEmpty) 
                Text(
                  subText, 
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), 
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
