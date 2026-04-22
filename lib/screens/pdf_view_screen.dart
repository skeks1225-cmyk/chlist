import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/item_model.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final List<ItemModel> items;
  final int initialIndex;
  final String pdfFolderPath;
  final Function(ItemModel, String) onStatusUpdate;

  const PdfViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.pdfFolderPath,
    required this.onStatusUpdate,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _currentIndex;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  String _currentPdfPath = "";

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _updatePath();
  }

  void _updatePath() {
    final item = widget.items[_currentIndex];
    final path = "${widget.pdfFolderPath}/${item.itemCode}.pdf";
    setState(() {
      _currentPdfPath = File(path).existsSync() ? path : "";
    });
  }

  void _next() {
    if (_currentIndex < widget.items.length - 1) {
      setState(() {
        _currentIndex++;
        _updatePath();
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _updatePath();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(item.itemCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // 전체 화면 핏 버튼 추가
          IconButton(
            icon: const Icon(Icons.fullscreen_exit),
            onPressed: () => _pdfViewerController.zoomLevel = 1.0,
          )
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: _currentPdfPath.isNotEmpty
                ? SfPdfViewer.file(
                    File(_currentPdfPath),
                    controller: _pdfViewerController,
                    // ❗ 핵심 설정: 핀치 줌을 자유롭게 허용
                    enableDoubleTapZooming: true,
                    interactionMode: PdfInteractionMode.pan,
                  )
                : const Center(child: Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: Colors.white, fontSize: 16))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            color: Colors.grey[900],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusBtn("완료", Colors.green, item.complete, () {
                      widget.onStatusUpdate(item, 'complete');
                      setState(() {});
                      Future.delayed(const Duration(milliseconds: 300), () => _next());
                    }),
                    _buildStatusBtn("부족", Colors.orange, item.shortage, () {
                      widget.onStatusUpdate(item, 'shortage');
                      setState(() {});
                    }),
                    _buildStatusBtn("재작업", Colors.red, item.rework, () {
                      widget.onStatusUpdate(item, 'rework');
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
                      style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45)),
                    ),
                    Text("${_currentIndex + 1} / ${widget.items.length}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(
                      onPressed: _next, 
                      icon: const Icon(Icons.arrow_forward), 
                      label: const Text("다음", style: TextStyle(fontSize: 15)),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45)),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusBtn(String label, Color color, bool active, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? color : Colors.grey[700],
        foregroundColor: Colors.white,
        minimumSize: const Size(100, 50),
        elevation: active ? 8 : 2,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
