import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxStackGestureTest(),
  ));
}

class PdfrxStackGestureTest extends StatefulWidget {
  const PdfrxStackGestureTest({super.key});

  @override
  State<PdfrxStackGestureTest> createState() => _PdfrxStackGestureTestState();
}

class _PdfrxStackGestureTestState extends State<PdfrxStackGestureTest> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();

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
        title: const Text("pdfrx 스택 오버레이 테스트"),
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
                icon: const Icon(Icons.folder_copy),
                label: const Text("도면 폴더 연결"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : Stack(
              children: [
                // 1. 바닥 레이어: 도면 뷰어
                PdfViewer.file(
                  _allFiles[_currentIndex],
                  controller: _pdfController,
                  key: ValueKey(_allFiles[_currentIndex]),
                ),

                // 2. ❗ 최상단 레이어: 지피티 추천 스와이프 감지기
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent, // ❗ 터치 신호를 아래로 통과시킴
                    onHorizontalDragEnd: (details) {
                      // ❗ 로그 확인용
                      debugPrint("스와이프 동작 감지됨!");

                      // pdfrx 2.x에서 줌 값을 가져오는 가장 안전한 방법
                      // 에러 방지를 위해 1.05 이하일 때만 작동하도록 설계
                      final double currentZoom = _pdfController.currentValue.zoom;
                      
                      if (currentZoom <= 1.05) {
                        final double velocity = details.primaryVelocity ?? 0;
                        if (velocity < -300) {
                          debugPrint("다음 파일로 이동");
                          _goToNext();
                        } else if (velocity > 300) {
                          debugPrint("이전 파일로 이동");
                          _goToPrev();
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
