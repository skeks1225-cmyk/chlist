import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
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
  PdfControllerPinch? _pdfController;
  String _currentPdfPath = "";
  // ❗ 뷰어 강제 새로고침을 위한 키
  Key _viewerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPdf();
  }

  void _loadPdf() {
    final item = widget.items[_currentIndex];
    final path = "${widget.pdfFolderPath}/${item.itemCode}.pdf";
    
    // 리소스 완전 해제
    _pdfController?.dispose();
    
    if (File(path).existsSync()) {
      _currentPdfPath = path;
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(path),
        initialPage: 1,
      );
    } else {
      _currentPdfPath = "";
      _pdfController = null;
    }
    // ❗ 키를 새로 생성하여 위젯을 뿌리부터 다시 그림 (로딩 루프 방지)
    _viewerKey = UniqueKey();
    setState(() {});
  }

  // ❗ FIT 버튼: 현재 파일을 다시 로드하여 초기 상태(가로 핏)로 복구
  void _resetFit() {
    _loadPdf(); 
  }

  void _next() {
    if (_currentIndex < widget.items.length - 1) {
      _currentIndex++;
      _loadPdf();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _loadPdf();
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
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
          TextButton(
            onPressed: _resetFit,
            child: const Text("FIT", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: _pdfController != null
                ? PdfViewPinch(
                    key: _viewerKey, // ❗ 가변 키 적용
                    controller: _pdfController!,
                    builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                      options: const DefaultBuilderOptions(),
                      documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                      pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
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
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
