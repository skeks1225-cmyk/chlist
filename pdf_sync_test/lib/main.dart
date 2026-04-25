import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() {
  runApp(const MaterialApp(home: SyncfusionTestHome()));
}

class SyncfusionTestHome extends StatefulWidget {
  const SyncfusionTestHome({super.key});

  @override
  State<SyncfusionTestHome> createState() => _SyncfusionTestHomeState();
}

class _SyncfusionTestHomeState extends State<SyncfusionTestHome> {
  String? _selectedPath;
  final PdfViewerController _pdfViewerController = PdfViewerController();

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
        title: const Text("Syncfusion PDF 테스트"),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _selectedPath == null
            ? ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.file_copy),
                label: const Text("테스트할 도면 선택"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              )
            : Column(
                children: [
                  Expanded(
                    child: SfPdfViewer.file(
                      File(_selectedPath!),
                      controller: _pdfViewerController,
                      // ❗ 기본 확대를 아주 크게 허용 (최대 5배)
                      maxZoomLevel: 5.0, 
                      interactionMode: PdfInteractionMode.pan,
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
                          child: const Text("다른 파일 선택", style: TextStyle(color: Colors.yellow)),
                        ),
                        // ❗ 강제 전체핏 기능 테스트
                        ElevatedButton(
                          onPressed: () => _pdfViewerController.zoomLevel = 1.0,
                          child: const Text("초기화 (1.0x)"),
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
