import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_model.dart';
import '../services/smb_service.dart';
import '../widgets/qr_scanner_dialog.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

class PdfViewerScreen extends StatefulWidget {
  final List<ItemModel> allItems;
  final List<ItemModel> filteredItems;
  final int initialIndex;
  final String pdfFolderPath;
  final SmbService smbService;
  final List<String> processList;
  final Map<String, int> processColors;
  final int completeMode;
  final double doubleTapZoom;
  final double maxZoom;
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
    this.doubleTapZoom = 3.0,
    this.maxZoom = 10.0,
    required this.onStatusUpdate,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> with TickerProviderStateMixin {
  late int _currentIndex;
  String _currentPdfPath = "";

  // pdfrx 렌더링
  PdfDocument? _pdfDoc;
  ui.Image? _currentUiImage;
  bool _isRerendering = false;
  double _renderedAtScale = 1.0;

  // 줌/패닝 상태 (InteractiveViewer 제거 → 직접 Matrix4 관리)
  Matrix4 _matrix = Matrix4.identity();
  double _currentScale = 1.0;
  BoxConstraints? _viewportConstraints;
  Size? _pdfPageSize;

  // 핀치줌 제스처 시작 시 스냅샷
  Matrix4 _scaleStartMatrix = Matrix4.identity();
  double _scaleStartScale = 1.0;
  Offset _scaleStartFocalPoint = Offset.zero;

  // 스와이프 감지용
  bool _isSwipeGesture = false;

  // 더블탭
  Offset? _doubleTapOffset;
  AnimationController? _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;

  // PageView
  late PageController _pageController;

  // UI
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ItemModel> _searchResults = [];
  bool _isLoading = false;

  bool get _isZoomed => _currentScale > 1.05;

  Matrix4 _getInitialMatrix() {
    if (_viewportConstraints == null || _pdfPageSize == null) return Matrix4.identity();
    final viewW = _viewportConstraints!.maxWidth;
    final viewH = _viewportConstraints!.maxHeight;
    final pageRatio = _pdfPageSize!.width / _pdfPageSize!.height;
    final viewRatio = viewW / viewH;

    double contentW, contentH;
    if (pageRatio > viewRatio) {
      contentW = viewW;
      contentH = viewW / pageRatio;
    } else {
      contentW = viewH * pageRatio;
      contentH = viewH;
    }
    return Matrix4.translationValues((viewW - contentW) / 2, (viewH - contentH) / 2, 0);
  }

  void _clampMatrix() {
    if (_viewportConstraints == null || _pdfPageSize == null || _currentScale <= 1.0) {
      _matrix = _getInitialMatrix();
      return;
    }

    final viewW = _viewportConstraints!.maxWidth;
    final viewH = _viewportConstraints!.maxHeight;
    final pageRatio = _pdfPageSize!.width / _pdfPageSize!.height;
    final viewRatio = viewW / viewH;

    double contentW, contentH;
    if (pageRatio > viewRatio) {
      contentW = viewW;
      contentH = viewW / pageRatio;
    } else {
      contentW = viewH * pageRatio;
      contentH = viewH;
    }

    final S = _currentScale;
    final offsetX = (viewW - contentW * S) / 2;
    final offsetY = (viewH - contentH * S) / 2;

    final tx = _matrix.storage[12];
    final ty = _matrix.storage[13];

    // S=1일 때의 Matrix 기준으로 클램핑
    _matrix.storage[12] = tx.clamp(-(S - 1) * contentW + offsetX, offsetX);
    _matrix.storage[13] = ty.clamp(-(S - 1) * contentH + offsetY, offsetY);
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _loadPdf();
    _searchFocusNode.addListener(() {
      if (mounted && !_searchFocusNode.hasFocus) setState(() => _searchResults = []);
    });
  }

  Future<void> _loadPdf() async {
    final item = widget.allItems[_currentIndex];
    final String cleanCode = item.itemCode.trim();
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _currentUiImage = null;
      _matrix = _getInitialMatrix();
      _currentScale = 1.0;
      _renderedAtScale = 1.0;
    });

    try { await _pdfDoc?.dispose(); } catch (_) {}
    _pdfDoc = null;

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
    _currentPdfPath = localPath;

    if (File(localPath).existsSync()) {
      try {
        _pdfDoc = await PdfDocument.openFile(localPath);
        if (_pdfDoc!.pages.isNotEmpty) {
          final page = _pdfDoc!.pages[0];
          _pdfPageSize = Size(page.width, page.height);
          await _renderPage(scale: 1.0);
        } else {
          if (mounted) setState(() { _isLoading = false; });
        }
      } catch (e) {
        debugPrint("PDF load error: $e");
        if (mounted) setState(() { _isLoading = false; });
      }
    } else {
      if (mounted) setState(() { _isLoading = false; _currentPdfPath = ""; });
    }
  }

  /// pdfrx 재렌더링 — 현재 배율에 맞는 해상도로 선명하게 렌더링
  Future<void> _renderPage({required double scale}) async {
    if (_pdfDoc == null || _pdfDoc!.pages.isEmpty || _isRerendering) return;
    _isRerendering = true;
    try {
      final page = _pdfDoc!.pages[0];
      double renderWidth = page.width * scale * 1.5;
      double renderHeight = page.height * scale * 1.5;
      const double maxPx = 6144.0;
      if (renderWidth > maxPx) {
        renderHeight = renderHeight * (maxPx / renderWidth);
        renderWidth = maxPx;
      }
      if (renderHeight > maxPx) {
        renderWidth = renderWidth * (maxPx / renderHeight);
        renderHeight = maxPx;
      }
      final pdfImage = await page.render(fullWidth: renderWidth, fullHeight: renderHeight);
      if (pdfImage != null && mounted) {
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          pdfImage.pixels, pdfImage.width, pdfImage.height,
          ui.PixelFormat.rgba8888, (img) => completer.complete(img),
        );
        final uiImage = await completer.future;
        if (mounted) {
          setState(() {
            _currentUiImage?.dispose();
            _currentUiImage = uiImage;
            _renderedAtScale = scale;
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() { _isLoading = false; });
      }
    } catch (e) {
      debugPrint("PDF render error: $e");
      if (mounted) setState(() { _isLoading = false; });
    } finally {
      _isRerendering = false;
    }
  }

  void _maybeRerenderAt(double scale) {
    if ((scale - _renderedAtScale).abs() / _renderedAtScale > 0.3) {
      _renderPage(scale: scale);
    }
  }

  // ── 핀치줌 제스처 ────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails details) {
    _scaleStartMatrix = _matrix.clone();
    _scaleStartScale = _currentScale;
    _scaleStartFocalPoint = details.localFocalPoint;
    // 단일 손가락 + FIT 상태일 때는 스와이프 감지 모드
    _isSwipeGesture = details.pointerCount <= 1 && !_isZoomed;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      // ─── 핀치줌 ────────────────────────────────────────────
      _isSwipeGesture = false;
      final double newScale = (_scaleStartScale * details.scale).clamp(1.0, widget.maxZoom);
      
      if (newScale <= 1.0) {
        setState(() {
          _matrix = Matrix4.identity();
          _currentScale = 1.0;
        });
        return;
      }

      final double scaleDelta = newScale / _scaleStartScale;
      final Offset focalDelta = details.localFocalPoint - _scaleStartFocalPoint;

      // 핀치 시작 기준 포인트 주변으로 확대 + 핀치 이동량만큼 패닝
      final Matrix4 delta = Matrix4.identity()
        ..translate(_scaleStartFocalPoint.dx + focalDelta.dx,
                    _scaleStartFocalPoint.dy + focalDelta.dy)
        ..scale(scaleDelta)
        ..translate(-_scaleStartFocalPoint.dx, -_scaleStartFocalPoint.dy);

      final Matrix4 newMatrix = delta.multiplied(_scaleStartMatrix);
      setState(() {
        _matrix = newMatrix;
        _currentScale = newScale;
        _clampMatrix();
      });
    } else if (details.pointerCount == 1 && _isZoomed) {
      // ─── 단일 손가락 패닝 (확대 상태) ───────────────────────
      _isSwipeGesture = false;
      final Matrix4 newMatrix = _matrix.clone();
      newMatrix.translate(details.focalPointDelta.dx, details.focalPointDelta.dy);
      setState(() {
        _matrix = newMatrix;
        _clampMatrix();
      });
    }
    // 단일 손가락 + FIT 상태: 스와이프로 처리 (onScaleEnd에서 이전/다음 호출)
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // ─── 스와이프로 이전/다음 전환 ──────────────────────────
    if (_isSwipeGesture && !_isZoomed) {
      final velocityX = details.velocity.pixelsPerSecond.dx;
      if (velocityX < -300) _next();      // 왼쪽 스와이프 → 다음
      else if (velocityX > 300) _prev();  // 오른쪽 스와이프 → 이전
    }
    // ─── 핀치줌 종료 후 재렌더링 ────────────────────────────
    _maybeRerenderAt(_currentScale);
  }

  // ── 더블탭 Matrix4 피벗 확대/FIT 복귀 ───────────────────────
  void _handleDoubleTap() {
    Matrix4 targetMatrix;
    if (_isZoomed) {
      targetMatrix = Matrix4.identity();
    } else {
      final tap = _doubleTapOffset ?? Offset.zero;
      final scale = widget.doubleTapZoom;
      targetMatrix = Matrix4.identity()
        ..translate(-tap.dx * (scale - 1), -tap.dy * (scale - 1))
        ..scale(scale);
    }
    _animateToMatrix(targetMatrix);
  }

  void _animateToMatrix(Matrix4 target) {
    _zoomAnimController?.dispose();
    _zoomAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _zoomAnimation = Matrix4Tween(begin: _matrix, end: target)
      .animate(CurvedAnimation(parent: _zoomAnimController!, curve: Curves.easeOut));
    _zoomAnimation!.addListener(() {
      if (mounted) setState(() {
        _matrix = _zoomAnimation!.value;
        _currentScale = _matrix.getMaxScaleOnAxis();
      });
    });
    // ❗ 애니메이션 완료 후 재렌더링 (더블탭은 onScaleEnd가 호출되지 않으므로 여기서 처리)
    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _maybeRerenderAt(_currentScale);
      }
    });
    _zoomAnimController!.forward();
  }

  void _resetFit() => _animateToMatrix(Matrix4.identity());

  // ── 이전/다음 품목 이동 ───────────────────────────────────────
  void _prev() {
    final currentItem = widget.allItems[_currentIndex];
    int prevTargetIdx = -1;
    for (int i = widget.filteredItems.length - 1; i >= 0; i--) {
      if (widget.filteredItems[i].realIndex < currentItem.realIndex) { prevTargetIdx = i; break; }
    }
    if (prevTargetIdx != -1) {
      final newIdx = widget.allItems.indexOf(widget.filteredItems[prevTargetIdx]);
      if (newIdx != -1) {
        setState(() { _currentIndex = newIdx; });
        _pageController.jumpToPage(_currentIndex);
        _loadPdf();
      }
    }
  }

  void _next() {
    final currentItem = widget.allItems[_currentIndex];
    int nextTargetIdx = -1;
    for (int i = 0; i < widget.filteredItems.length; i++) {
      if (widget.filteredItems[i].realIndex > currentItem.realIndex) { nextTargetIdx = i; break; }
    }
    if (nextTargetIdx != -1) {
      final newIdx = widget.allItems.indexOf(widget.filteredItems[nextTargetIdx]);
      if (newIdx != -1) {
        setState(() { _currentIndex = newIdx; });
        _pageController.jumpToPage(_currentIndex);
        _loadPdf();
      }
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
      _pageController.jumpToPage(_currentIndex);
      _searchFocusNode.unfocus();
      _loadPdf();
    }
  }

  // ── 다이얼로그 ────────────────────────────────────────────────
  void _showCompleteTimeDialog(ItemModel item) {
    String record = item.completeTime.isEmpty ? "기록 없음" : item.completeTime;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))),
        const SizedBox(height: 8),
        const Text("완료 입력 시간", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
      content: Text("입력시간 : $record", style: const TextStyle(fontSize: 16)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
    ));
  }

  void _showComplementDialog(ItemModel item) {
    String lastRecord = item.complementTime.isNotEmpty ? "마지막 기록: ${item.complement}: ${item.complementTime}" : "마지막 기록: 없음";
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("보완 선택", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(lastRecord, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.blue)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogBtn("부족", Colors.orange, () { item.complement = "부족"; item.complete = false; item.complementTime = DateTime.now().toString().substring(0, 16); }),
        _dialogBtn("재작업", Colors.red, () { item.complement = "재작업"; item.complete = false; item.complementTime = DateTime.now().toString().substring(0, 16); }),
        const Divider(),
        _dialogBtn("지우기", Colors.grey, () { item.complement = ""; item.complementTime = ""; }),
        _dialogBtn("선택취소", Colors.blueGrey, () {}),
      ]),
    ));
  }

  void _showProcessDialog(ItemModel item) {
    String lastRecord = item.processTime.isNotEmpty ? "마지막 기록: ${item.process}: ${item.processTime}" : "마지막 기록: 없음";
    List<String> sortedDisplayList = List.from(widget.processList);
    bool hasFinished = sortedDisplayList.remove("완료");
    if (hasFinished) sortedDisplayList.add("완료");
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("공정 선택", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(lastRecord, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.blue)),
      ]),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3, childAspectRatio: 1.8, mainAxisSpacing: 8, crossAxisSpacing: 8,
          children: sortedDisplayList.map((p) {
            int? colorVal = widget.processColors[p];
            Color btnColor = colorVal != null ? Color(colorVal) :
              p == "완료" ? Colors.purple : p == "보류" ? Colors.red :
              ["용접","도장","도금","인쇄"].contains(p) ? Colors.orange : Colors.blueGrey[700]!;
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              onPressed: () { setState(() { item.process = p; item.processTime = DateTime.now().toString().substring(0, 16); }); widget.onStatusUpdate(item, 'process'); Navigator.pop(ctx); },
              child: Text(p),
            );
          }).toList(),
        ),
        const Divider(),
        _dialogBtn("지우기", Colors.grey, () { item.process = ""; item.processTime = ""; }),
        _dialogBtn("선택취소", Colors.blueGrey, () {}),
      ]))),
    ));
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      onPressed: () { setState(onSelected); widget.onStatusUpdate(widget.allItems[_currentIndex], 'update'); Navigator.pop(context); },
      child: Text(label),
    ));
  }

  Widget _navArrowBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Container(width: 55, height: 55, alignment: Alignment.center,
        child: Icon(icon, color: isDark ? Colors.blue[300] : Colors.blue[700], size: 24)));
  }

  Future<void> _showCompleteConfirmDialog(ItemModel item) async {
    bool isChecking = !item.complete;
    bool? confirm = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isChecking ? "완료 체크 확인" : "완료 체크 해제 확인"),
        content: Text("[${item.itemCode}]\n항목을 ${isChecking ? '완료 처리' : '미완료 처리'}하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ));
    if (confirm == true) { widget.onStatusUpdate(item, 'complete'); setState(() {}); }
  }

  @override
  void dispose() {
    _zoomAnimController?.dispose();
    _currentUiImage?.dispose();
    try { _pdfDoc?.dispose(); } catch (_) {}
    _pageController.dispose();
    _remarksController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.allItems[_currentIndex];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? Colors.black : Colors.white;
    bool hasPrev = widget.filteredItems.any((i) => i.realIndex < item.realIndex);
    bool hasNext = widget.filteredItems.any((i) => i.realIndex > item.realIndex);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) { if (didPop) return; Navigator.pop(context, item.itemCode); },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (item.subheadingTitle.isNotEmpty)
              Text(item.subheadingTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70), overflow: TextOverflow.ellipsis),
            Row(children: [
              Text(item.itemCode, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text("(수량: ${item.quantity})", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.yellowAccent)),
            ]),
          ]),
          backgroundColor: isDark ? Colors.black : Colors.blueGrey[900], foregroundColor: Colors.white,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context, item.itemCode)),
          actions: [TextButton(onPressed: _resetFit, child: const Text("FIT", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold, fontSize: 16)))],
        ),
        backgroundColor: bgColor,
        body: Column(children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            _viewportConstraints = constraints;
            return Stack(children: [
              // ── PDF 뷰어 영역 ─────────────────────────────────
              Container(
                color: bgColor,
                child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.blue))
                  : _currentUiImage != null
                    ? PageView.builder(
                        controller: _pageController,
                        // ❗ 항상 NeverScrollable: 스와이프는 onScaleEnd 속도 감지로 처리
                        //    → InteractiveViewer/ScaleGestureRecognizer 와의 제스처 경쟁 완전 차단
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (idx) {
                          if (idx != _currentIndex) {
                            setState(() { _currentIndex = idx; });
                            _loadPdf();
                          }
                        },
                        itemCount: widget.allItems.length,
                        itemBuilder: (ctx, pageIdx) {
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onDoubleTapDown: (details) { _doubleTapOffset = details.localPosition; },
                            onDoubleTap: _handleDoubleTap,
                            // ❗ onScale 하나로 핀치줌 + 패닝 + 스와이프 감지 통합
                            //    ScaleGestureRecognizer가 모든 터치를 담당하므로
                            //    PageView HorizontalDragGestureRecognizer와의 경쟁이 없음
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onScaleEnd: _onScaleEnd,
                            child: Transform(
                              transform: _matrix,
                              child: Container(
                                color: bgColor,
                                alignment: Alignment.center,
                                child: RawImage(
                                  image: _currentUiImage,
                                  fit: BoxFit.contain,
                                  width: constraints.maxWidth,
                                  height: constraints.maxHeight,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 50),
                        const SizedBox(height: 10),
                        Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text("파일: ${item.itemCode}.pdf", style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12)),
                      ])),
              ),
              // ── 화살표 네비게이션 ─────────────────────────────
              Positioned(left: 5, bottom: 5, child: Row(children: [
                _navArrowBtn(Icons.arrow_back, hasPrev ? _prev : () {}, isDark),
                _navArrowBtn(Icons.arrow_forward, hasNext ? _next : () {}, isDark),
              ])),
              // ── 검색 자동완성 목록 ────────────────────────────
              if (_searchResults.isNotEmpty)
                Positioned(left: 8, bottom: 2, child: Container(
                  width: MediaQuery.of(context).size.width * 0.45,
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight - 5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -2))],
                  ),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ListView.separated(
                    padding: EdgeInsets.zero, shrinkWrap: true,
                    itemCount: _searchResults.length,
                    separatorBuilder: (ctx, idx) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]),
                    itemBuilder: (ctx, idx) {
                      final res = _searchResults[idx];
                      return ListTile(
                        dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        title: Text(res.itemCode, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87, fontWeight: res == item ? FontWeight.bold : FontWeight.normal)),
                        trailing: res == item ? const Icon(Icons.check_circle, size: 14, color: Colors.blue) : null,
                        onTap: () => _jumpToItem(res),
                      );
                    },
                  )),
                )),
            ]);
          })),

          // ── 하단 패널 ─────────────────────────────────────────
          SafeArea(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            color: isDark ? Colors.grey[900] : Colors.white,
            child: Column(children: [
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                Expanded(child: TextField(
                  controller: _searchController, focusNode: _searchFocusNode,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "코드 검색...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                    prefixIcon: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty) ? null : const Icon(Icons.search, size: 18),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchResults = []; }); }),
                      IconButton(icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.blue), onPressed: () async {
                        _searchFocusNode.unfocus();
                        final prefs = await SharedPreferences.getInstance();
                        final double currentZoom = prefs.getDouble('scannerZoom') ?? 0.0;
                        if (!context.mounted) return;
                        final String? result = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => QrScannerDialog(initialZoom: currentZoom)));
                        if (result != null && result.isNotEmpty) {
                          String? code;
                          if (result.startsWith("CODE:")) {
                            final parts = result.split('|');
                            code = parts[0].replaceFirst("CODE:", "");
                            if (parts.length > 1 && parts[1].startsWith("ZOOM:")) {
                              final double? z = double.tryParse(parts[1].replaceFirst("ZOOM:", ""));
                              if (z != null) { final p = await SharedPreferences.getInstance(); await p.setDouble('scannerZoom', z); }
                            }
                          } else if (result.startsWith("ZOOM:")) {
                            final double? z = double.tryParse(result.replaceFirst("ZOOM:", ""));
                            if (z != null) { final p = await SharedPreferences.getInstance(); await p.setDouble('scannerZoom', z); }
                            return;
                          } else { code = result; }
                          if (code == null || code.isEmpty) return;
                          String cleaned = code.replaceAll('<NUL>', '').replaceAll('<NULL>', '').trim().replaceAll(RegExp(r'[\x00-\x1F]'), '');
                          if (cleaned.toUpperCase().endsWith('-S')) cleaned = cleaned.substring(0, cleaned.length - 2);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("스캔: $result → 정제: $cleaned"), duration: const Duration(seconds: 2)));
                          final target = widget.allItems.cast<ItemModel?>().firstWhere((it) => it?.itemCode == cleaned, orElse: () => null);
                          if (target != null) _jumpToItem(target);
                          else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("해당 품목을 찾을 수 없습니다."), duration: Duration(seconds: 1)));
                        }
                      }),
                    ]),
                    filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: _onSearchChanged,
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: _remarksController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "비고...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                    filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    suffixIcon: _remarksController.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() => _remarksController.clear()); item.remarks = ""; widget.onStatusUpdate(item, 'remarks'); })
                      : null,
                  ),
                  onChanged: (val) { item.remarks = val; setState(() {}); },
                  onSubmitted: (val) { item.remarks = val; widget.onStatusUpdate(item, 'remarks'); },
                )),
              ])),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _statusBtn("완료", Colors.green, item.complete, () {
                  if (widget.completeMode == 0) { widget.onStatusUpdate(item, 'complete'); setState(() {}); }
                  else if (widget.completeMode == 2) { _showCompleteConfirmDialog(item); }
                }, onDoubleTap: () {
                  if (widget.completeMode == 1) { widget.onStatusUpdate(item, 'complete'); setState(() {}); }
                }, onLongPress: () => _showCompleteTimeDialog(item)),
                _statusBtn("공정", Colors.blueGrey, item.process.isNotEmpty, () => _showProcessDialog(item)),
                _statusBtn("보완", Colors.orange, item.complement.isNotEmpty, () => _showComplementDialog(item)),
              ]),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                ElevatedButton.icon(onPressed: hasPrev ? _prev : null, icon: const Icon(Icons.arrow_back), label: const Text("이전", style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: hasPrev ? (isDark ? Colors.white : Colors.blueGrey[900]) : Colors.grey)),
                Text("${_currentIndex + 1} / ${widget.allItems.length}", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(onPressed: hasNext ? _next : null, icon: const Icon(Icons.arrow_forward), label: const Text("다음", style: TextStyle(fontSize: 15)),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: hasNext ? (isDark ? Colors.white : Colors.blueGrey[900]) : Colors.grey)),
              ]),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _statusBtn(String label, Color color, bool active, VoidCallback onTap, {VoidCallback? onLongPress, VoidCallback? onDoubleTap}) {
    final item = widget.allItems[_currentIndex];
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    String subText = "";
    if (label == "보완") subText = item.complement;
    if (label == "공정") {
      subText = item.process;
      if (active) {
        int? colorVal = widget.processColors[subText];
        if (colorVal != null) color = Color(colorVal);
        else if (subText == "완료") color = Colors.purple;
        else if (subText == "보류") color = Colors.red;
        else if (["용접","도장","도금","인쇄"].contains(subText)) color = Colors.orange;
      }
    }
    Color bgColor = active ? color : (isDark ? Colors.grey[800]! : Colors.grey[300]!);
    Color fgColor = active ? Colors.white : (isDark ? Colors.white70 : Colors.black54);
    return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Material(
      color: bgColor, borderRadius: BorderRadius.circular(8), elevation: active ? 2 : 0,
      child: InkWell(onTap: onTap, onDoubleTap: onDoubleTap, onLongPress: onLongPress, borderRadius: BorderRadius.circular(8),
        child: Container(height: 55, alignment: Alignment.center, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: TextStyle(fontWeight: subText.isEmpty ? FontWeight.bold : FontWeight.normal, fontSize: subText.isEmpty ? 15 : 12, color: fgColor)),
          if (subText.isNotEmpty) Text(subText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: fgColor), overflow: TextOverflow.ellipsis),
        ]))),
    )));
  }
}
