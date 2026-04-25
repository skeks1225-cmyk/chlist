import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxFinalTest(),
  ));
}

class PdfrxFinalTest extends StatefulWidget {
  const PdfrxFinalTest({super.key});

  @override
  State<PdfrxFinalTest> createState() => _PdfrxFinalTestState();
}

class _PdfrxFinalTestState extends State<PdfrxFinalTest> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();
  
  // ❗ 사용자 확인을 위한 상태 메시지
  String _gestureStatus = "제스처 대기 중";

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  Future<void> _pickInitialFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      String pickedPath = result.files.single.path!;
      String dirPath = p.dirname(pickedPath);
      final dir = Directory(dirPath);
      final files = dir.listSync()
          .where((e) => e.path.toLowerCase().endsWith('.pdf'))
          .map((e) => e.path)
          .toList();
      files.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _allFiles = files;
        _currentIndex = _allFiles.indexOf(pickedPath);
      });
    }
  }

  void _goToNext() {
    if (_currentIndex < _allFiles.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _goToPrev() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("pdfrx 제스처 최종 확인"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: _currentIndex == -1
          ? Center(
              child: ElevatedButton.icon(
                onPressed: _pickInitialFile,
                icon: const Icon(Icons.folder_open),
                label: const Text("도면 폴더 연결"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: PdfViewer.file(
                    _allFiles[_currentIndex],
                    controller: _pdfController,
                    key: ValueKey(_allFiles[_currentIndex]),
                    params: PdfViewerParams(
                      maxScale: 10.0,
                      // ❗ [중요] 도면 엔진 내부의 공식 콜백 사용 (충돌 없음)
                      onInteractionEnd: (details) {
                        final double zoom = details.zoom;
                        final double vx = details.velocity.pixelsPerSecond.dx;

                        setState(() {
                          _gestureStatus = "배율: ${zoom.toStringAsFixed(2)}, 속도: ${vx.toStringAsFixed(0)}";
                        });

                        // 전체핏(1.05 이하) 상태에서만 파일 넘기기 작동
                        if (zoom <= 1.05) {
                          if (vx < -500) {
                            _goToNext();
                          } else if (vx > 500) {
                            _goToPrev();
                          }
                        }
                      },
                    ),
                  ),
                ),
                // ❗ 사용자 확인용 하단 상태 바
                Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("${_currentIndex + 1} / ${_allFiles.length}", style: const TextStyle(color: Colors.white)),
                      Text(_gestureStatus, style: const TextStyle(color: Colors.yellow, fontSize: 12)),
                      TextButton(
                        onPressed: () => setState(() => _currentIndex = -1),
                        child: const Text("폴더 재선택", style: TextStyle(color: Colors.cyan)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
