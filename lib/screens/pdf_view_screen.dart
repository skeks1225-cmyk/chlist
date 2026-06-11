import 'package:flutter/material.dart';
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
  final bool confirmComplete; // ❗ 완료 체크 시 확인창 여부
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
    required this.confirmComplete,
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
      });
    }
  }

  void _resetFit() { _loadPdf(); }

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

  void _showCompleteTimeDialog(ItemModel item) {
    String record = item.completeTime.isEmpty ? "기록 없음" : item.completeTime;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(item.itemCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.blue))),
            const SizedBox(height: 8),
            const Text("완료 입력 시간", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text("입력시간 : $record", style: const TextStyle(fontSize: 16)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("확인"))],
      ),
    );
  }

  void _showComplementDialog(ItemModel item) {
    String lastRecord = "마지막 기록: 없음";
    if (item.complementTime.isNotEmpty) {
      lastRecord = "마지막 기록: ${item.complement}: ${item.complementTime}";
    }
    
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("보완 선택", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(lastRecord, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.blue)),
        ],
      ),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogBtn("부족", Colors.orange, () { 
          item.complement = "부족"; 
          item.complete = false; 
          item.complementTime = DateTime.now().toString().substring(0, 16);
        }),
        _dialogBtn("재작업", Colors.red, () { 
          item.complement = "재작업"; 
          item.complete = false; 
          item.complementTime = DateTime.now().toString().substring(0, 16);
        }),
        const Divider(), 
        _dialogBtn("지우기", Colors.grey, () { 
          item.complement = ""; 
          item.complementTime = "";
        }),
        _dialogBtn("선택취소", Colors.blueGrey, () {}),
      ]),
    ));
  }

  void _showProcessDialog(ItemModel item) {
    String lastRecord = "마지막 기록: 없음";
    if (item.processTime.isNotEmpty) {
      lastRecord = "마지막 기록: ${item.process}: ${item.processTime}";
    }
    
    List<String> sortedDisplayList = List.from(widget.processList);
    bool hasFinished = sortedDisplayList.remove("완료");
    if (hasFinished) sortedDisplayList.add("완료");

    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("공정 선택", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(lastRecord, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.blue)),
        ],
      ),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3, childAspectRatio: 1.8,
          mainAxisSpacing: 8, crossAxisSpacing: 8,
          children: sortedDisplayList.map((p) {
            int? colorVal = widget.processColors[p];
            Color btnColor;
            if (colorVal != null) {
              btnColor = Color(colorVal);
            } else {
              if (p == "완료") btnColor = Colors.purple;
              else if (p == "보류") btnColor = Colors.red;
              else if (["용접", "도장", "도금", "인쇄"].contains(p)) btnColor = Colors.orange;
              else btnColor = Colors.blueGrey[700]!;
            }
            return ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: btnColor, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              onPressed: () { 
                setState(() { 
                  item.process = p; 
                  item.processTime = DateTime.now().toString().substring(0, 16);
                }); 
                widget.onStatusUpdate(item, 'process'); Navigator.pop(ctx); 
              },
              child: Text(p),
            );
          }).toList(),
        ),
        const Divider(), _dialogBtn("지우기", Colors.grey, () { 
          item.process = ""; 
          item.processTime = "";
        }),
        _dialogBtn("선택취소", Colors.blueGrey, () {}),
      ]))),
    ));
  }

  Widget _dialogBtn(String label, Color color, VoidCallback onSelected) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), onPressed: () { setState(onSelected); widget.onStatusUpdate(widget.allItems[_currentIndex], 'update'); Navigator.pop(context); }, child: Text(label)));
  }

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
              _isLoading ? Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.blue)) : (_currentPdfPath.isNotEmpty ? Container(color: viewerBgColor, child: PdfViewer.file(_currentPdfPath, key: _viewerKey, controller: _pdfController, params: PdfViewerParams(maxScale: 15.0, backgroundColor: viewerBgColor))) : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.error_outline, color: Colors.red, size: 50), const SizedBox(height: 10), Text("PDF 파일을 찾을 수 없습니다.", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)), const SizedBox(height: 5), Text("파일: ${item.itemCode}.pdf", style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600], fontSize: 12))]))),
              Positioned(left: 5, bottom: 80, child: Row(children: [_navArrowBtn(Icons.arrow_back, hasPrev ? _prev : () {}, isDark), _navArrowBtn(Icons.arrow_forward, hasNext ? _next : () {}, isDark)])),
              if (_searchResults.isNotEmpty) Positioned(left: 8, bottom: 2, child: Container(width: MediaQuery.of(context).size.width * 0.45, constraints: BoxConstraints(maxHeight: constraints.maxHeight - 5), decoration: BoxDecoration(color: isDark ? Colors.grey[850] : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white10 : Colors.grey[300]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, -2))]), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: ListView.separated(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _searchResults.length, separatorBuilder: (ctx, idx) => Divider(height: 1, color: isDark ? Colors.white10 : Colors.grey[200]), itemBuilder: (ctx, idx) { final res = _searchResults[idx]; return ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), title: Text(res.itemCode, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87, fontWeight: res == item ? FontWeight.bold : FontWeight.normal)), trailing: res == item ? const Icon(Icons.check_circle, size: 14, color: Colors.blue) : null, onTap: () => _jumpToItem(res)); }))))
            ]);
          })),
          SafeArea(child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), color: isDark ? Colors.grey[900] : Colors.white, child: Column(children: [
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
              Expanded(child: TextField(controller: _searchController, focusNode: _searchFocusNode, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), decoration: InputDecoration(hintText: "코드 검색...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]), prefixIcon: (_searchFocusNode.hasFocus || _searchController.text.isNotEmpty) ? null : const Icon(Icons.search, size: 18), suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_searchController.text.isNotEmpty) IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() { _searchController.clear(); _searchResults = []; }); }),
                IconButton(icon: const Icon(Icons.qr_code_scanner, size: 22, color: Colors.blue), onPressed: () async {
                  _searchFocusNode.unfocus();
                  final prefs = await SharedPreferences.getInstance();
                  final double currentZoom = prefs.getDouble('scannerZoom') ?? 0.0;
                  
                  if (!context.mounted) return;
                  final String? result = await Navigator.push<String>(
                    context, 
                    MaterialPageRoute(builder: (_) => QrScannerDialog(initialZoom: currentZoom))
                  );
                  
                  if (result != null && result.isNotEmpty) {
                    String? code;
                    if (result.startsWith("CODE:")) {
                      final parts = result.split('|');
                      code = parts[0].replaceFirst("CODE:", "");
                      if (parts.length > 1 && parts[1].startsWith("ZOOM:")) {
                        final double? newZoom = double.tryParse(parts[1].replaceFirst("ZOOM:", ""));
                        if (newZoom != null) {
                          final prefsSave = await SharedPreferences.getInstance();
                          await prefsSave.setDouble('scannerZoom', newZoom);
                        }
                      }
                    } else if (result.startsWith("ZOOM:")) {
                      final double? newZoom = double.tryParse(result.replaceFirst("ZOOM:", ""));
                      if (newZoom != null) {
                        final prefsSave = await SharedPreferences.getInstance();
                        await prefsSave.setDouble('scannerZoom', newZoom);
                      }
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
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("스캔: $result → 정제: $cleaned"), duration: const Duration(seconds: 2)));
                    }
                    final target = widget.allItems.cast<ItemModel?>().firstWhere((it) => it?.itemCode == cleaned, orElse: () => null);
                    if (target != null) {
                      _jumpToItem(target);
                    } else {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("해당 품목을 찾을 수 없습니다."), duration: Duration(seconds: 1)));
                      }
                    }
                  }
                }),
              ]), filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), onChanged: _onSearchChanged)),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _remarksController, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), decoration: InputDecoration(hintText: "비고...", hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]), filled: true, fillColor: isDark ? Colors.black26 : Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), suffixIcon: _remarksController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.cancel, size: 18, color: Colors.grey), onPressed: () { setState(() => _remarksController.clear()); item.remarks = ""; widget.onStatusUpdate(item, 'remarks'); }) : null), onChanged: (val) { item.remarks = val; setState(() {}); }, onSubmitted: (val) { item.remarks = val; widget.onStatusUpdate(item, 'remarks'); })),
            ])),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _statusBtn("완료", Colors.green, item.complete, () async {
                if (widget.confirmComplete) {
                  bool isChecking = !item.complete;
                  bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(isChecking ? "완료 체크 확인" : "완료 체크 해제 확인"),
                      content: Text("[${item.itemCode}]\n항목을 ${isChecking ? '완료 처리' : '미완료 처리'}하시겠습니까?"),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }
                widget.onStatusUpdate(item, 'complete'); setState(() {}); 
              }, onLongPress: () => _showCompleteTimeDialog(item)), 
              _statusBtn("공정", Colors.blueGrey, item.process.isNotEmpty, () => _showProcessDialog(item)), 
              _statusBtn("보완", Colors.orange, item.complement.isNotEmpty, () => _showComplementDialog(item))
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              ElevatedButton.icon(onPressed: hasPrev ? _prev : null, icon: const Icon(Icons.arrow_back), label: const Text("이전", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: hasPrev ? (isDark ? Colors.white : Colors.blueGrey[900]) : Colors.grey)),
              Text("${_currentIndex + 1} / ${widget.allItems.length}", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(onPressed: hasNext ? _next : null, icon: const Icon(Icons.arrow_forward), label: const Text("다음", style: TextStyle(fontSize: 15)), style: ElevatedButton.styleFrom(minimumSize: const Size(100, 45), backgroundColor: isDark ? Colors.grey[800] : Colors.blueGrey[50], foregroundColor: hasNext ? (isDark ? Colors.white : Colors.blueGrey[900]) : Colors.grey)),
            ])
          ])))
        ]),
      ),
    );
  }

  Widget _statusBtn(String label, Color color, bool active, VoidCallback onTap, {VoidCallback? onLongPress}) {
    final item = widget.allItems[_currentIndex];
    String subText = "";
    if (label == "보완") subText = item.complement;
    if (label == "공정") {
      subText = item.process;
      if (active) {
        int? colorVal = widget.processColors[subText];
        if (colorVal != null) color = Color(colorVal);
        else if (subText == "완료") color = Colors.purple;
        else if (subText == "보류") color = Colors.red;
        else if (["용접", "도장", "도금", "인쇄"].contains(subText)) color = Colors.orange;
      }
    }
    return Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ElevatedButton(onPressed: onTap, onLongPress: onLongPress, style: ElevatedButton.styleFrom(backgroundColor: active ? color : Colors.grey[400]?.withOpacity(0.5), foregroundColor: active ? Colors.white : Colors.black54, minimumSize: const Size(0, 55), padding: EdgeInsets.zero, elevation: active ? 2 : 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(label, style: TextStyle(fontWeight: subText.isEmpty ? FontWeight.bold : FontWeight.normal, fontSize: subText.isEmpty ? 15 : 12)), if (subText.isNotEmpty) Text(subText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)]))));
  }
}
