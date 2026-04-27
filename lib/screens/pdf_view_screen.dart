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
  final Function(ItemModel, String) onStatusUpdate;

  const PdfViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.pdfFolderPath,
    required this.smbService,
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

  void _showError(String title, String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
  }

  void _resetFit() {
    _loadPdf(); 
  }

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

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

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
          TextButton(
            onPressed: _resetFit,
            child: const Text("FIT", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      backgroundColor: isDark ? Colors.black : Colors.grey[200],
      body: Column(
        children: [
          Expanded(
            child: _isLoading 
                ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.blue))
                : (_currentPdfPath.isNotEmpty
                    ? Container(
                        color: viewerBgColor,
                        child: PdfViewer.file(
                          _currentPdfPath,
                          key: _viewerKey,
                          controller: _pdfController,
                          params: PdfViewerParams(
                            maxScale: 15.0,
                            backgroundColor: viewerBgColor,
                            onViewerReady: (document, controller) {
                              debugPrint("뷰어 로드 완료");
                            },
                          ),
                        ),
                      )
                    : Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 50),
                          const SizedBox(height: 10),
                          Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
                          const SizedBox(height: 5),
                          Text("파일: ${item.itemCode}.pdf", style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12)),
                        ],
                      ))),
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
                        hintText: "비고 입력...",
                        hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                        filled: true,
                        fillColor: isDark ? Colors.black26 : Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.blue),
                          onPressed: () {
                            item.remarks = _remarksController.text;
                            widget.onStatusUpdate(item, 'remarks');
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      onChanged: (val) => item.remarks = val,
                      onSubmitted: (val) {
                        item.remarks = val;
                        widget.onStatusUpdate(item, 'remarks');
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statusBtn("완료", Colors.green, item.complete, () { 
                        widget.onStatusUpdate(item, 'complete'); 
                        setState(() {}); 
                      }),
                      // ❗ 부족/재작업 버튼이 '보완' 상태를 업데이트하도록 변경
                      _statusBtn("부족", Colors.orange, item.complement == "부족", () { 
                        item.complement = item.complement == "부족" ? "" : "부족";
                        item.complete = false;
                        widget.onStatusUpdate(item, 'complement'); 
                        setState(() {}); 
                      }),
                      _statusBtn("재작업", Colors.red, item.complement == "재작업", () { 
                        item.complement = item.complement == "재작업" ? "" : "재작업";
                        item.complete = false;
                        widget.onStatusUpdate(item, 'complement'); 
                        setState(() {}); 
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _prev, 
                        icon: const Icon(Icons.arrow_back), 
                        label: const Text("이전", style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(100, 45),
                          backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50],
                          foregroundColor: isDark ? Colors.white : Colors.blueGrey[900],
                        )
                      ),
                      Text("${_currentIndex + 1} / ${widget.items.length}", 
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                      ElevatedButton.icon(
                        onPressed: _next, 
                        icon: const Icon(Icons.arrow_forward), 
                        label: const Text("다음", style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(100, 45),
                          backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50],
                          foregroundColor: isDark ? Colors.white : Colors.blueGrey[900],
                        )
                      ),
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
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? color : Colors.grey[400]?.withOpacity(0.5), 
        foregroundColor: active ? Colors.white : Colors.black54,
        minimumSize: const Size(100, 50),
        elevation: active ? 2 : 0,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
