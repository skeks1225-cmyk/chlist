import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../models/item_model.dart';
import 'dart:io';
import 'dart:typed_data';

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
  Key _viewerKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPdf();
  }

  // ❗ 경로 대신 '바이트 데이터'를 메모리로 읽어와서 로드 (100% 화면 표시 보장)
  Future<void> _loadPdf() async {
    final item = widget.items[_currentIndex];
    final path = "${widget.pdfFolderPath}/${item.itemCode}.pdf";
    
    _pdfController?.dispose();
    
    if (File(path).existsSync()) {
      try {
        final Uint8List bytes = await File(path).readAsBytes();
        setState(() {
          _currentPdfPath = path;
          _pdfController = PdfControllerPinch(
            document: PdfDocument.openData(bytes), // ❗ 메모리 로드 방식
            initialPage: 1,
          );
          _viewerKey = UniqueKey();
        });
      } catch (e) {
        _showError("파일 읽기 실패", e.toString());
      }
    } else {
      setState(() {
        _currentPdfPath = "";
        _pdfController = null;
        _viewerKey = UniqueKey();
      });
    }
  }

  void _showError(String title, String msg) {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
  }

  void _resetFit() => _loadPdf();

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
                    key: _viewerKey,
                    controller: _pdfController!,
                    scrollDirection: Axis.vertical, 
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
                    _statusBtn("완료", Colors.green, item.complete, () { widget.onStatusUpdate(item, 'complete'); setState(() {}); }),
                    _statusBtn("부족", Colors.orange, item.shortage, () { widget.onStatusUpdate(item, 'shortage'); setState(() {}); }),
                    _statusBtn("재작업", Colors.red, item.rework, () { widget.onStatusUpdate(item, 'rework'); setState(() {}); }),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(onPressed: _prev, icon: const Icon(Icons.arrow_back), label: const Text("이전", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45))),
                    Text("${_currentIndex + 1} / ${widget.items.length}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ElevatedButton.icon(onPressed: _next, icon: const Icon(Icons.arrow_forward), label: const Text("다음", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45))),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statusBtn(String label, Color color, bool active, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(backgroundColor: active ? color : Colors.grey[700], foregroundColor: Colors.white, minimumSize: const Size(100, 50)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}
