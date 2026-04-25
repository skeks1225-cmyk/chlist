import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxPageViewTest(),
  ));
}

class PdfrxPageViewTest extends StatefulWidget {
  const PdfrxPageViewTest({super.key});

  @override
  State<PdfrxPageViewTest> createState() => _PdfrxPageViewTestState();
}

class _PdfrxPageViewTestState extends State<PdfrxPageViewTest> {
  List<String> _allFiles = [];
  late PageController _pageController;
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
        // ❗ 현재 선택한 파일 위치에서 시작하는 페이지 컨트롤러 생성
        _pageController = PageController(initialPage: initialIndex);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("스와이프 최종 (PageView)"),
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
          : PageView.builder(
              // ❗ [핵심] 좌우 넘기기를 담당하는 공식 위젯
              controller: _pageController,
              itemCount: _allFiles.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                // 각 페이지마다 독립적인 뷰어 생성
                return PdfViewer.file(
                  _allFiles[index],
                  key: ValueKey(_allFiles[index]),
                );
              },
            ),
    );
  }
}
