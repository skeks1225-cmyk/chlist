import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxFileSwipeTest(),
  ));
}

class PdfrxFileSwipeTest extends StatefulWidget {
  const PdfrxFileSwipeTest({super.key});

  @override
  State<PdfrxFileSwipeTest> createState() => _PdfrxFileSwipeTestState();
}

class _PdfrxFileSwipeTestState extends State<PdfrxFileSwipeTest> {
  List<String> _allFiles = [];
  PageController? _pageController;
  int _currentIndex = -1;

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

      int initialIndex = files.indexOf(pickedPath);
      
      setState(() {
        _allFiles = files;
        _currentIndex = initialIndex;
        _pageController = PageController(initialPage: initialIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("파일 단위 스와이프 (1파일=1페이지)"),
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
                label: const Text("도면 폴더 연결 (파일 이동 테스트)"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: _allFiles.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                // ❗ 각 슬라이드는 독립된 하나의 PDF 파일입니다.
                return PdfViewer.file(
                  _allFiles[index],
                  key: ValueKey(_allFiles[index]),
                  params: const PdfViewerParams(
                    // 엔진 내부의 수평 스와이프(페이지 이동)를 완전히 꺼서
                    // 부모인 PageView(파일 이동)와 충돌하지 않게 합니다.
                    enablePaging: false, 
                    maxScale: 10.0,
                  ),
                );
              },
            ),
    );
  }
}
