import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart'; // ❗ 최신 2.2.24 버전 사용
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxPureTest(),
  ));
}

class PdfrxPureTest extends StatefulWidget {
  const PdfrxPureTest({super.key});

  @override
  State<PdfrxPureTest> createState() => _PdfrxPureTestState();
}

class _PdfrxPureTestState extends State<PdfrxPureTest> {
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
        title: const Text("pdfrx 최신버전 순정 테스트"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _selectedPath == null
            ? ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("테스트할 도면 선택"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 60),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    // ❗ 최신 버전의 가장 기본적인 호출 방식
                    child: PdfViewer.file(
                      _selectedPath!,
                    ),
                  ),
                  Container(
                    color: Colors.grey[900],
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
