import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const MaterialApp(home: PdfTestHome()));
}

class PdfTestHome extends StatefulWidget {
  const PdfTestHome({super.key});

  @override
  State<PdfTestHome> createState() => _PdfTestHomeState();
}

class _PdfTestHomeState extends State<PdfTestHome> {
  String? _selectedPath;

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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedPath = result.files.single.path;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("flutter_pdfview 테스트"),
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _selectedPath == null
            ? ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_open),
                label: const Text("PDF 파일 선택하기"),
              )
            : Column(
                children: [
                  Expanded(
                    child: PDFView(
                      filePath: _selectedPath!,
                      enableSwipe: true,
                      swipeHorizontal: false,
                      autoSpacing: true,
                      pageFling: true,
                      pageSnap: false, // ❗ 자유로운 스크롤을 위해 false
                      fitEachPage: true, // ❗ 페이지별 최적화 핏
                      fitPolicy: FitPolicy.BOTH, // ❗ 전체가 다 보이도록 설정
                      onRender: (pages) {
                        debugPrint("PDF 렌더링 완료: $pages 페이지");
                      },
                      onError: (error) {
                        debugPrint("에러 발생: ${error.toString()}");
                      },
                    ),
                  ),
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _selectedPath = null),
                          child: const Text("파일 다시 선택", style: TextStyle(color: Colors.yellow)),
                        ),
                        const Text("핀치 축소를 마음껏 테스트해보세요", style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  )
                ],
              ),
      ),
    );
  }
}
