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
        title: const Text("pdfrx 순정 테스트"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _selectedPath == null
            ? ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("도면 선택하기"),
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
                      // ❗ 모든 커스텀 기능을 빼고 라이브러리 기본값으로만 실행
                      params: PdfViewerParams(
                        onViewerReady: (document, controller) {
                          debugPrint("뷰어 준비 완료");
                        },
                        onError: (error) {
                          debugPrint("에러 발생: $error");
                        },
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.black,
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _selectedPath = null),
                          child: const Text("다른 파일 선택", style: TextStyle(color: Colors.white)),
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
