import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxSwipeTest(),
  ));
}

class PdfrxSwipeTest extends StatefulWidget {
  const PdfrxSwipeTest({super.key});

  @override
  State<PdfrxSwipeTest> createState() => _PdfrxSwipeTestState();
}

class _PdfrxSwipeTestState extends State<PdfrxSwipeTest> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();
  
  // ❗ 거리 측정을 위한 변수
  double _totalDeltaX = 0;

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
        title: const Text("pdfrx 정석 스와이프 테스트"),
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
          : GestureDetector(
              // ❗ [개선] 1. 드래그 거리 누적 시작
              onHorizontalDragStart: (_) {
                _totalDeltaX = 0;
              },
              // ❗ [개선] 2. 실시간 거리 누적 (비고란 포커스 해제 등에도 활용 가능)
              onHorizontalDragUpdate: (details) {
                _totalDeltaX += details.delta.dx;
              },
              // ❗ [개선] 3. 드래그 종료 시점에만 '배율 + 속도 + 거리' 삼위일체 판정
              onHorizontalDragEnd: (details) {
                // pdfrx 2.x에서는 1.0이 기본 전체핏입니다.
                // 미세한 조작 오차를 고려해 1.01로 잡습니다.
                final double currentZoom = _pdfController.zoom;
                
                if (currentZoom <= 1.01) {
                  final double velocity = details.primaryVelocity ?? 0;
                  final double distance = _totalDeltaX;

                  // ❗ 지피티 조언 반영: 속도(500) AND 거리(50) 동시 만족 시에만 이동
                  if (velocity < -500 && distance < -50) {
                    _goToNext(); // 오른쪽에서 왼쪽으로 (다음)
                  } else if (velocity > 500 && distance > 50) {
                    _goToPrev(); // 왼쪽에서 오른쪽으로 (이전)
                  }
                }
              },
              child: PdfViewer.file(
                _allFiles[_currentIndex],
                controller: _pdfController,
                key: ValueKey(_allFiles[_currentIndex]),
                params: const PdfViewerParams(
                  maxScale: 10.0,
                  enableTextSelection: false,
                ),
              ),
            ),
    );
  }
}
