import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:pdfrx/pdfrx.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_model.dart';
import '../services/smb_service.dart';
import '../widgets/qr_scanner_dialog.dart';
import 'dart:io';

class PdfViewerScreen extends StatefulWidget {
  final List<ItemModel> allItems; // 전체 품목 (검색용)
  final List<ItemModel> filteredItems; // 필터링된 품목 (이전/다음 이동용)
  final int initialIndex; // allItems에서의 인덱스
  final String pdfFolderPath;
  final SmbService smbService;
  final List<String> processList;
  final Map<String, int> processColors; // ❗ 공정별 색상 정보
  final int completeMode; // ❗ 완료 체크 모드 (0: 클릭, 1: 더블클릭, 2: 확인창)
  final double swipeSensitivity; // ❗ 슬라이드 감도 (0.05 ~ 0.50)
  final Function(ItemModel, String) onStatusUpdate;

  const PdfViewerScreen({
    super.key,
    required this.allItems,
    required this.filteredItems,
    required this.initialIndex,
    required this.pdfFolderPath,
    required this.smbService,
    required this.processList,
    required this.processColors,
    required this.completeMode,
    required this.swipeSensitivity,
    required this.onStatusUpdate,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late int _currentIndex;
  String _currentPdfPath = "";
  final PdfViewerController _pdfController = PdfViewerController();
  Key _viewerKey = UniqueKey();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ItemModel> _searchResults = [];
  bool _isLoading = false;
  double? _fitZoomLevel;      // PDF 로드 시 실제 FIT 배율 저장
  Offset? _doubleTapPosition; // 더블탭 위치 저장 (확대 중심점)

  // ❗ 슬라이드 제스처 관련 변수
  double _swipeStartX = 0;
  double _swipeStartY = 0;
  int _pointerCount = 0;
  bool _isSwipeActionTriggered = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadPdf();
    _searchFocusNode.addListener(() {
      if (mounted && !_searchFocusNode.hasFocus) {
        setState(() => _searchResults = []);
      }
    });
  }

  Future<void> _loadPdf() async {
    final item = widget.allItems[_currentIndex];
    final String cleanCode = item.itemCode.trim();
    if (!mounted) return;
    setState(() => _isLoading = true);

    String localPath = "";
    if (widget.pdfFolderPath.startsWith("smb://")) {
      try {
        String shareWithRest = widget.pdfFolderPath.replaceFirst("smb://", "");
        if (shareWithRest.endsWith("/")) shareWithRest = shareWithRest.substring(0, shareWithRest.length - 1);
        int firstSlash = shareWithRest.indexOf("/");
        String share = firstSlash != -1 ? shareWithRest.substring(0, firstSlash) : shareWithRest;
        String folderPath = firstSlash != -1 ? shareWithRest.substring(firstSlash + 1) : "";
        String remoteFilePath = folderPath.isEmpty ? "$cleanCode.pdf" : "$folderPath/$cleanCode.pdf";
        localPath = "/storage/emulated/0/Download/CheckSheet/$cleanCode.pdf";
        await widget.smbService.downloadFile(share, remoteFilePath, localPath);
      } catch (e) { debugPrint("SMB Sync Error: $e"); }
    } else {
      localPath = "${widget.pdfFolderPath}/$cleanCode.pdf";
    }

    _remarksController.text = item.remarks;
    if (mounted) {
      setState(() {
        _currentPdfPath = File(localPath).existsSync() ? localPath : "";
        _viewerKey = UniqueKey();
        _isLoading = false;
        _fitZoomLevel = null; // 새 PDF 로드 시 FIT 배율 초기화
      });
    }
  }

  void _resetFit() {
    if (!_isLoading && _currentPdfPath.isNotEmpty) {
      final fitZoom = _fitZoomLevel ?? _pdfController.alternativeFitScale ?? 1.0;
      final mediaQuery = MediaQuery.of(context);
      final localCenter = Offset(mediaQuery.size.width / 2, mediaQuery.size.height / 2);
      final globalCenter = _pdfController.localToGlobal(localCenter) ?? Offset.zero;
      final docCenter = _pdfController.globalToDocument(globalCenter) ?? Offset.zero;
      _pdfController.setZoom(docCenter, fitZoom);
    } else {
      _loadPdf();
    }
  }

  void _prev() {
    final currentItem = widget.allItems[_currentIndex];
    int prevTargetIdx = -1;
    for (int i = widget.filteredItems.length - 1; i >= 0; i--) {
      if (widget.filteredItems[i].realIndex < currentItem.realIndex) {
        prevTargetIdx = i;
        break;
      }
    }
    if (prevTargetIdx != -1) {
      final targetItem = widget.filteredItems[prevTargetIdx];
      final newIdx = widget.allItems.indexOf(targetItem);
      if (newIdx != -1) { setState(() { _currentIndex = newIdx; _loadPdf(); }); }
    }
  }

  void _next() {
    final currentItem = widget.allItems[_currentIndex];
    int nextTargetIdx = -1;
    for (int i = 0; i < widget.filteredItems.length; i++) {
      if (widget.filteredItems[i].realIndex > currentItem.realIndex) {
        nextTargetIdx = i;
        break;
      }
    }
    if (nextTargetIdx != -1) {
      final targetItem = widget.filteredItems[nextTargetIdx];
      final newIdx = widget.allItems.indexOf(targetItem);
      if (newIdx != -1) { setState(() { _currentIndex = newIdx; _loadPdf(); }); }
    }
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) { setState(() => _searchResults = []); return; }
    final q = query.toLowerCase();
    setState(() { _searchResults = widget.allItems.where((item) => item.itemCode.toLowerCase().contains(q)).take(15).toList(); });
  }

  void _jumpToItem(ItemModel target) {
    int index = widget.allItems.indexOf(target);
    if (index != -1) {
      setState(() { _currentIndex = index; _searchResults = []; _searchController.clear(); });
      _searchFocusNode.unfocus(); _loadPdf();
    }
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) { return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), onPressed: () { setState(onSelected); widget.onStatusUpdate(widget.allItems[_currentIndex], 'update'); Navigator.pop(context); }, child: Text(label))); }

  Widget _navArrowBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: Container(width: 55, height: 55, alignment: Alignment.center, child: Icon(icon, color: isDark ? Colors.blue[300] : Colors.blue[700], size: 24)));
  }

  @override
  void dispose() { _remarksController.dispose(); _searchController.dispose(); _searchFocusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final item = widget.allItems[_currentIndex];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color viewerBgColor = isDark ? Colors.black : Colors.grey[300]!;
    bool hasPrev = widget.filteredItems.any((i) => i.realIndex < item.realIndex);
    bool hasNext = widget.filteredItems.any((i) => i.realIndex > item.realIndex);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) { if (didPop) return; Navigator.pop(context, item.itemCode); },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (item.subheadingTitle.isNotEmpty) Text(item.subheadingTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70), overflow: TextOverflow.ellipsis),
            Row(
              children: [
                Text(item.itemCode, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text("(수량: ${item.quantity})", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.yellowAccent)),
              ],
            )
          ]),
          backgroundColor: isDark ? Colors.black : Colors.blueGrey[900], foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, item.itemCode)),
          actions: [TextButton(onPressed: _resetFit, child: const Text("FIT", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16)))],
        ),
        backgroundColor: isDark ? Colors.black : Colors.grey[200],
        body: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            return Stack(children: [
              _isLoading
                  ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.blue))
                  : (_currentPdfPath.isNotEmpty
                      ? Container(
                          color: viewerBgColor,
                          child: Listener(
                            onPointerDown: (details) {
                              _pointerCount++;
                              if (_pointerCount == 1) {
                                _swipeStartX = details.localPosition.dx;
                                _swipeStartY = details.localPosition.dy;
                                _isSwipeActionTriggered = false;
                              }
                            },
                            onPointerMove: (details) {
                              if (_pointerCount != 1 || _isSwipeActionTriggered) return;
                              
                              final currentZoom = _pdfController.currentZoom;
                              final fitZoom = _fitZoomLevel ?? 1.0;
                              // FIT 상태일 때만 슬라이드 허용 (1.1배 마진)
                              if (currentZoom > fitZoom * 1.1) return;

                              final dx = details.localPosition.dx - _swipeStartX;
                              final dy = details.localPosition.dy - _swipeStartY;
                              final threshold = constraints.maxWidth * widget.swipeSensitivity;

                              // 가로축 이동이 감도 이상이고 세로축보다 확실히 클 때 (각도 판정)
                              if (dx.abs() > threshold && dx.abs() > dy.abs() * 1.5) {
                                _isSwipeActionTriggered = true;
                                if (dx > 0) {
                                  _prev(); // 오른쪽으로 밀기 -> 이전 파일
                                } else {
                                  _next(); // 왼쪽으로 밀기 -> 다음 파일
                                }
                              }
                            },
                            onPointerUp: (details) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
                            onPointerCancel: (details) => _pointerCount = (_pointerCount - 1).clamp(0, 10),
                            child: PdfViewer.file(
                              _currentPdfPath,
                              key: _viewerKey,
                              controller: _pdfController,
                              params: PdfViewerParams(
                                maxScale: 15.0,
                                backgroundColor: viewerBgColor,
                                // PDF 로드 시 실제 FIT 배율을 캡처
                                calculateInitialZoom: (doc, ctrl, fitScale, coverScale) {
                                  _fitZoomLevel = fitScale;
                                  return fitScale;
                                },
                                viewerOverlayBuilder: (context, size, handleLinkTap) => [
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    // 더블탭 위치 기록 (확대 시 중심점으로 사용)
                                    onDoubleTapDown: (details) {
                                      _doubleTapPosition = details.globalPosition;
                                    },
                                    onDoubleTap: () {
                                      final currentZoom = _pdfController.currentZoom;
                                      final fitZoom = _fitZoomLevel ?? 1.0;
                                      
                                      // FIT 배율 기준으로 확대/축소 판단 (10% 여유)
                                      final isZoomed = currentZoom > fitZoom * 1.1;
                                      
                                      final localCenter = Offset(size.width / 2, size.height / 2);
                                      final globalCenter = _pdfController.localToGlobal(localCenter) ?? Offset.zero;
                                      final docCenter = _pdfController.globalToDocument(globalCenter) ?? Offset.zero;
                                      
                                      if (isZoomed) {
                                        // 확대 상태 → 화면 중앙을 중심으로 FIT 배율로 부드럽게 축소
                                        _pdfController.setZoom(docCenter, fitZoom);
                                      } else {
                                        debugPrint("DoubleTap - Action: Zoom In (3x)");
                                        final tapPos = _doubleTapPosition ?? globalCenter;
                                        final docTapPos = _pdfController.globalToDocument(tapPos) ?? Offset.zero;
                                        _pdfController.setZoom(docTapPos, 3.0);
                                      }
                                    },
                                  )
                                ],
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 50),
                              const SizedBox(height: 10),
                              Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
                              const SizedBox(height: 5),
                              Text("파일: ${item.itemCode}.pdf", style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12)),
                            ],
                          ),
                        )),
              Positioned(left: 5, bottom: 5, child: Row(children: [_navArrowBtn(Icons.arrow_back, hasPrev ? _prev : () {}, isDark), _navArrowBtn(Icons.arrow_forward, hasNext ? _next : () {}, isDark)])),
              if (_searchResults.isNotEmpty) Positioned(left: 8, bottom: 2, child: Container(width: MediaQuery.of(context).size.width * 0.45, constraints: BoxConstraints(maxHeight: constraints.maxHeight - 5), decoration: BoxDecoration(color: isDark ? Colors.grey[850] : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -2))]), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ListView.separated(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _searchResults.length, separatorBuilder: (ctx, idx) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]), itemBuilder: (ctx, idx) { final res = _searchResults[idx]; return ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), title: Text(res.itemCode, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87, fontWeight: res == item ? FontWeight.bold : FontWeight.normal)), trailing: res == item ? const Icon(Icons.check_circle, size: 14, color: Colors.blue) : null, onTap: () => _jumpToItem(res)); }))))
            ]);
          })),
          SafeArea(child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), color: isDark ? Colors.grey[900] : Colors.white, child: Row(children: [
              Expanded(child: TextField(controller: _searchController, focusNode: _searchFocusNode, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), decoration: InputDecoration(hintText: "코드 검색...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]), prefixIcon: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty) ? null : const Icon(Icons.search, size: 18), suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_searchController.text.isNotEmpty) IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchResults = []; }); }),
                IconButton(icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.blue), onPressed: () async {
                  _searchFocusNode.unfocus();
                  final prefs = await SharedPreferences.getInstance();
                  final double currentZoom = prefs.getDouble('scannerZoom') ?? 0.0;
                  
                  if (!mounted) return;
                  final String? result = await Navigator.push<String>(
                    context, 
                    MaterialPageRoute(builder: (_) => QrScannerDialog(initialZoom: currentZoom))
                  );

                  if (result != null && result.isNotEmpty) {
                    String? code;
                    // QR 결과 파싱 로직
                    if (result.startsWith("CODE:")) {
                      final parts = result.split('|');
                      code = parts[0].replaceFirst("CODE:", "");
                    } else if (result.startsWith("ZOOM:")) {
                      return;
                    } else {
                      code = result;
                    }

                    if (code == null || code.isEmpty) return;
                    String cleaned = code.replaceAll('<NUL>', '').replaceAll('<NULL>', '').trim();
                    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F]'), '');
                    if (cleaned.toUpperCase().endsWith('-S')) {
                      cleaned = cleaned.substring(0, cleaned.length - 2);
                    }

                    // 1. 완벽 일치 우선 검색
                    List<ItemModel> matches = [];
                    ItemModel? target = widget.allItems.firstWhere(
                      (i) => i.itemCode == cleaned,
                      orElse: () => ItemModel(realIndex: -1, no: "", displayNo: "", itemCode: "", quantity: "", isSubheading: false)
                    );

                    if (target.realIndex != -1) {
                      matches = [target];
                    } else if (cleaned.contains(RegExp(r'-[0-9]{2}$'))) {
                      // 2. 일치 항목이 없으면 스마트 폴백 매칭 (-## 제거)
                      String strippedCode = cleaned.substring(0, cleaned.lastIndexOf('-'));
                      matches = widget.allItems.where((i) => i.itemCode.startsWith(strippedCode)).toList();
                    }

                    if (matches.isNotEmpty) {
                      _jumpToItem(matches.first);

                      if (matches.length == 1) {
                        // 단일 항목 폴백 매칭 성공 시 토스트 알림
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("품목 ${matches.first.itemCode}(으)로 연결되었습니다."), duration: const Duration(seconds: 2)));
                        }
                      } else {
                        // 3. 중복이나 유사 항목 안내 알림 (중복일 때만 알림창)
                        if (mounted) {
                          String msg = "연결된 품목: ${matches.first.itemCode}";
                          msg += "\n\n기타 발견 항목: ${matches.sublist(1).map((m) => m.itemCode).join(', ')}";
                          showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("코드 인식 알림"), content: Text("인식한 코드: $cleaned\n\n$msg\n\n리스트에 유사한 항목이 있어 혼동될 수 있으니 확인 바랍니다."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
                        }
                      }
                    } else {
                      // 4. 최종 실패 알림
                      if (mounted) {
                        showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("인식 실패"), content: Text("일치하는 품목을 찾을 수 없습니다.\n인식된 코드: '$cleaned'"), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))]));
                      }
                    }
                  }
                }),
              ]), filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), onChanged: _onSearchChanged)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _remarksController, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), decoration: InputDecoration(hintText: "비고...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]), filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), suffixIcon: _remarksController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() => _remarksController.clear()); item.remarks = ""; widget.onStatusUpdate(item, 'remarks'); }) : null), onChanged: (val) { item.remarks = val; setState(() {}); }, onSubmitted: (val) { item.remarks = val; widget.onStatusUpdate(item, 'remarks'); })),
            ])),
          ]))
        ]),
      ),
    );
  }
}
