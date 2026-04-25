import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxOfficialEventTest(),
  ));
}

class PdfrxOfficialEventTest extends StatefulWidget {
  const PdfrxOfficialEventTest({super.key});

  @override
  State<PdfrxOfficialEventTest> createState() => _PdfrxOfficialEventTestState();
}

class _PdfrxOfficialEventTestState extends State<PdfrxOfficialEventTest> {
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
        title: const Text("pdfrx 공식 이벤트 테스트"),
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
                label: const Text("파일 선택 (스와이프 테스트)"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : PdfViewer.file(
              _allFiles[_currentIndex],
              controller: _pdfController,
              key: ValueKey(_allFiles[_currentIndex]),
              params: PdfViewerParams(
                maxScale: 10.0,
                // ❗ [지피티 추천] 엔진이 조작 종료를 감지했을 때 실행되는 공식 콜백
                onInteractionEnd: (details) {
                  // 1. 현재 줌 배율이 전체핏(1.0) 근처인지 확인
                  // details.zoom은 엔진이 직접 계산해서 주는 정확한 값입니다.
                  if (details.zoom <= 1.01) {
                    // 2. 수평 이동 속도 확인 (Velocity)
                    // 왼쪽으로 휙: 음수(-), 오른쪽으로 휙: 양수(+)
                    final double vx = details.velocity.pixelsPerSecond.dx;
                    
                    if (vx < -500) {
                      _goToNext(); // 다음 도면
                    } else if (vx > 500) {
                      _goToPrev(); // 이전 도면
                    }
                  }
                },
              ),
            ),
    );
  }
}
