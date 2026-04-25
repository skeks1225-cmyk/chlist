import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxStep1Test(),
  ));
}

class PdfrxStep1Test extends StatefulWidget {
  const PdfrxStep1Test({super.key});

  @override
  State<PdfrxStep1Test> createState() => _PdfrxStep1TestState();
}

class _PdfrxStep1TestState extends State<PdfrxStep1Test> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();
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
        title: const Text("pdfrx 스와이프 (Step 1)"),
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
          : GestureDetector(
              onHorizontalDragStart: (_) {
                _totalDeltaX = 0;
              },
              onHorizontalDragUpdate: (details) {
                _totalDeltaX += details.delta.dx;
              },
              onHorizontalDragEnd: (details) {
                // ❗ Step 1: 줌 조건 없이 속도와 거리만 확인하여 빌드 성공 보장
                final double velocity = details.primaryVelocity ?? 0;
                final double distance = _totalDeltaX;

                if (velocity < -500 && distance < -50) {
                  _goToNext();
                } else if (velocity > 500 && distance > 50) {
                  _goToPrev();
                }
              },
              child: PdfViewer.file(
                _allFiles[_currentIndex],
                controller: _pdfController,
                key: ValueKey(_allFiles[_currentIndex]),
                // ❗ 에러 유발 옵션 모두 제거 (가장 깨끗한 상태)
              ),
            ),
    );
  }
}
