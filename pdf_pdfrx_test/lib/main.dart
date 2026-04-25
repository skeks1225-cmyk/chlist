import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const MaterialApp(home: PdfrxTestHome()));
}

class PdfrxTestHome extends StatefulWidget {
  const PdfrxTestHome({super.key});

  @override
  State<PdfrxTestHome> createState() => _PdfrxTestHomeState();
}

class _PdfrxTestHomeState extends State<PdfrxTestHome> {
  String? _selectedPath;
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
        title: const Text("pdfrx 오픈소스 테스트"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _selectedPath == null
            ? ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("오픈소스 도면 테스트"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 60),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: PdfViewer.file(
                      _selectedPath!,
                      controller: _pdfController,
                      params: PdfViewerParams(
                        // ❗ 무제한에 가까운 확대 허용 (최대 20배)
                        maxScale: 20.0,
                        // ❗ 부드러운 스크롤 및 줌 설정
                        enablePaging: true,
                        layoutPages: (pages, params) => PdfPageLayout.column(pages, params),
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.grey[900],
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _selectedPath = null),
                          child: const Text("다시 선택", style: TextStyle(color: Colors.tealAccent)),
                        ),
                        // ❗ 핏 초기화 버튼
                        ElevatedButton(
                          onPressed: () => _pdfController.zoomTo(matrix: Matrix4.identity()),
                          child: const Text("전체핏 초기화"),
                        ),
                      ],
                    ),
                  )
                ],
              ),
      ),
    );
  }
}
