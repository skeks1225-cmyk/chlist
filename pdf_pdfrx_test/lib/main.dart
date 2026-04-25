import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxPerfectSwipeTest(),
  ));
}

class PdfrxPerfectSwipeTest extends StatefulWidget {
  const PdfrxPerfectSwipeTest({super.key});

  @override
  State<PdfrxPerfectSwipeTest> createState() => _PdfrxPerfectSwipeTestState();
}

class _PdfrxPerfectSwipeTestState extends State<PdfrxPerfectSwipeTest> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();
  String _gestureStatus = "대기 중";

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
        title: const Text("pdfrx 진짜 최종 제스처"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          if (_currentIndex != -1)
            Center(child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Text("${_currentIndex + 1} / ${_allFiles.length}"),
            )),
        ],
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
                      maxScale: 15.0,
                      // ❗ [최신 API] 조작 종료 시점 감지
                      onInteractionEnd: (details) {
                        // ❗ pdfrx 2.2.24에서 줌(배율)을 가져오는 유일한 공식 방법
                        final double currentZoom = _pdfController.currentMatrix.storage[0];
                        final double vx = details.velocity.pixelsPerSecond.dx;

                        setState(() {
                          _gestureStatus = "배율: ${currentZoom.toStringAsFixed(2)}, 속도: ${vx.toStringAsFixed(0)}";
                        });

                        // 1.05 이하(전체핏)일 때만 파일 넘기기 작동
                        if (currentZoom <= 1.05) {
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
                Container(
                  width: double.infinity,
                  color: Colors.black,
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: Text(_gestureStatus, style: const TextStyle(color: Colors.yellow, fontSize: 12)),
                  ),
                ),
              ],
            ),
    );
  }
}
