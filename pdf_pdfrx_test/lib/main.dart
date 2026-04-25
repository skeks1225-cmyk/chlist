import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PdfrxSwipeTest(),
  ));
}

class PdfrxSwipeTest extends StatefulWidget {
  const PdfrxSwipeTest({super.key});

  @override
  State<PdfrxSwipeTest> createState() => _PdfrxSwipeTestState();
}

class _PdfrxSwipeTestState extends State<PdfrxSwipeTest> {
  List<String> _allFiles = []; // 선택한 폴더의 모든 PDF 목록
  int _currentIndex = -1;
  final PdfViewerController _pdfController = PdfViewerController();
  
  // ❗ 스와이프 방향 및 속도 감지를 위한 변수
  double _dragStartX = 0;

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

  // ❗ 폴더 내 모든 PDF를 가져와서 테스트 환경 구축
  Future<void> _pickInitialFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      String pickedPath = result.files.single.path!;
      String dirPath = p.dirname(pickedPath);
      
      // 해당 폴더의 모든 PDF 목록 스캔
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
        title: const Text("pdfrx 스와이프 테스트"),
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
                label: const Text("도면 폴더 연결 (파일 하나 선택)"),
                style: ElevatedButton.styleFrom(minimumSize: const Size(200, 60)),
              ),
            )
          : GestureDetector(
              // ❗ [핵심] 스와이프 감지 로직
              onHorizontalDragStart: (details) {
                _dragStartX = details.globalPosition.dx;
              },
              onHorizontalDragEnd: (details) {
                // 1. 현재 줌 배율 확인 (pdfrx 2.x 기준)
                // 1.05는 오차 범위를 고려한 '전체핏' 기준점입니다.
                if (_pdfController.zoom < 1.05) {
                  double velocity = details.primaryVelocity ?? 0;
                  
                  // 2. 휙 넘기는 속도(Velocity) 또는 이동 거리 확인
                  if (velocity < -500) {
                    // 오른쪽에서 왼쪽으로 휙 -> 다음 파일
                    _goToNext();
                  } else if (velocity > 500) {
                    // 왼쪽에서 오른쪽으로 휙 -> 이전 파일
                    _goToPrev();
                  }
                }
              },
              child: Stack(
                children: [
                  PdfViewer.file(
                    _allFiles[_currentIndex],
                    controller: _pdfController,
                    key: ValueKey(_allFiles[_currentIndex]), // 파일 변경 시 뷰어 초기화
                    params: const PdfViewerParams(
                      maxScale: 10.0,
                      enableTextSelection: false, // 조작 간섭 방지
                    ),
                  ),
                  // 안내 메시지 레이어 (잠시 후 사라지게 하거나 생략 가능)
                  if (_pdfController.zoom < 1.05)
                    Positioned(
                      bottom: 20,
                      left: 0, right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                          child: const Text("전체핏 상태입니다. 좌우로 밀어서 도면을 넘기세요.", 
                              style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
