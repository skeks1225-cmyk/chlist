import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxPerfectGestureTest(),
  ));
}

class PdfrxPerfectGestureTest extends StatefulWidget {
  const PdfrxPerfectGestureTest({super.key});

  @override
  State<PdfrxPerfectGestureTest> createState() => _PdfrxPerfectGestureTestState();
}

class _PdfrxPerfectGestureTestState extends State<PdfrxPerfectGestureTest> {
  List<String> _allFiles = [];
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();

  // ❗ 제스처 제어를 위한 정밀 변수들
  Offset? _startPos;
  DateTime? _startTime;
  bool _isMultiTouch = false; // 손가락이 2개 이상 닿았는지 확인
  final Set<int> _pointers = {}; // 현재 화면에 닿은 손가락 ID들

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
        title: const Text("pdfrx 줌-스와이프 완성"),
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
                label: const Text("파일 선택"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : Listener(
              // ❗ [핵심] 멀티터치 감지 로직
              onPointerDown: (event) {
                _pointers.add(event.pointer);
                if (_pointers.length == 1) {
                  // 첫 번째 손가락이 닿았을 때만 스와이프 준비
                  _startPos = event.position;
                  _startTime = DateTime.now();
                  _isMultiTouch = false;
                } else {
                  // 손가락이 2개 이상이면 즉시 스와이프 기능 차단 (줌 모드)
                  _isMultiTouch = true;
                }
              },
              onPointerUp: (event) {
                _pointers.remove(event.pointer);
                
                // 멀티터치가 아니었고, 정상적인 드래그 데이터가 있을 때만 판정
                if (!_isMultiTouch && _startPos != null && _startTime != null) {
                  final endPos = event.position;
                  final duration = DateTime.now().difference(_startTime!);
                  final dx = endPos.dx - _startPos!.dx;
                  final dy = (endPos.dy - _startPos!.dy).abs();

                  // 100픽셀 이상, 300ms 이내의 빠른 수평 스와이프만 인정
                  if (dx.abs() > 100 && dy < 50 && duration.inMilliseconds < 300) {
                    if (dx < 0) _goToNext();
                    else _goToPrev();
                  }
                }

                if (_pointers.isEmpty) {
                  _startPos = null;
                  _startTime = null;
                }
              },
              onPointerCancel: (event) {
                _pointers.clear();
                _isMultiTouch = false;
              },
              child: PdfViewer.file(
                _allFiles[_currentIndex],
                controller: _pdfController,
                key: ValueKey(_allFiles[_currentIndex]),
                params: const PdfViewerParams(
                  maxScale: 15.0, // ❗ 시원한 확대를 위해 15배 허용
                ),
              ),
            ),
    );
  }
}
