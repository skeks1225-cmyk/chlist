import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxMinimalSwipeTest(),
  ));
}

class PdfrxMinimalSwipeTest extends StatefulWidget {
  const PdfrxMinimalSwipeTest({super.key});

  @override
  State<PdfrxMinimalSwipeTest> createState() => _PdfrxMinimalSwipeTestState();
}

class _PdfrxMinimalSwipeTestState extends State<PdfrxMinimalSwipeTest> {
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
        title: const Text("스와이프 이벤트 확인 (최종)"),
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
          : Stack(
              children: [
                // 1. 도면 뷰어 (순정)
                PdfViewer.file(
                  _allFiles[_currentIndex],
                  controller: _pdfController,
                  key: ValueKey(_allFiles[_currentIndex]),
                ),

                // 2. ❗ 최상단 투명 감지 레이어 (줌 조건 없음)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragEnd: (details) {
                      debugPrint("스와이프 신호 들어옴!"); // ❗ 로그 확인용

                      final double velocity = details.primaryVelocity ?? 0;
                      if (velocity < -300) {
                        debugPrint("오른쪽으로 밀었음 -> 다음 파일");
                        _goToNext();
                      } else if (velocity > 300) {
                        debugPrint("왼쪽으로 밀었음 -> 이전 파일");
                        _goToPrev();
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
