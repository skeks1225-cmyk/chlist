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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPdf();
  }

  void _loadPdf() {
    final item = widget.items[_currentIndex];
    final path = "${widget.pdfFolderPath}/${item.itemCode}.pdf";
    
    // 이전 컨트롤러 해제 필수 (메모리 및 갱신 에러 방지)
    _pdfController?.dispose();
    
    if (File(path).existsSync()) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openFile(path),
        initialPage: 1,
      );
      _currentPdfPath = path;
    } else {
      _pdfController = null;
      _currentPdfPath = "";
    }
    setState(() {}); // UI 강제 갱신
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
        title: Text(item.itemCode, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: _pdfController != null
                ? PdfViewPinch(
                    controller: _pdfController!,
                    // 핏 옵션: 축소 시 화면에 맞게 조절되도록 설정
                    builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                      options: const DefaultBuilderOptions(),
                      documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                      pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
                    ),
                  )
                : const Center(child: Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: Colors.white))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            color: Colors.grey[900],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusBtn("완료", Colors.green, item.complete, () {
                      widget.onStatusUpdate(item, 'complete');
                      setState(() {});
                      _next();
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
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(onPressed: _prev, icon: const Icon(Icons.arrow_back), label: const Text("이전")),
                    Text("${_currentIndex + 1} / ${widget.items.length}", style: const TextStyle(color: Colors.white)),
                    ElevatedButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: const Text("다음")),
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
        minimumSize: const Size(90, 45),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
