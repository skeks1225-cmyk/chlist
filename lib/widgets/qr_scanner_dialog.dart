import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({super.key});

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController();
  double _currentZoom = 0.0; // 0.0 (1x) ~ 1.0 (3x)

  @override
  void initState() {
    super.initState();
    _loadZoomSettings();
  }

  Future<void> _loadZoomSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentZoom = prefs.getDouble('scannerZoom') ?? 0.0;
    });
    // 초기 줌 설정 적용 (약간의 지연 필요할 수 있음)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _controller.setZoomScale(_currentZoom);
    });
  }

  Future<void> _updateZoom(double value) async {
    setState(() {
      _currentZoom = value;
    });
    _controller.setZoomScale(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('scannerZoom', value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 줌 배율 텍스트 계산 (0.0~1.0 -> 1.0x~3.0x)
    String zoomText = (_currentZoom * 2.0 + 1.0).toStringAsFixed(1);

    return AlertDialog(
      title: const Text("QR 코드 스캔", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        height: 380, // 줌 컨트롤러 공간 확보를 위해 높이 상향
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty) {
                          final String? code = barcodes.first.rawValue;
                          if (code != null && mounted) {
                            Navigator.pop(context, code);
                          }
                        }
                      },
                    ),
                    // 카메라 위 오버레이 UI (줌 배율 표시)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${zoomText}x",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 갤럭시 스타일 줌 컨트롤러 영역
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // 줌 슬라이더
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    ),
                    child: Slider(
                      value: _currentZoom,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) => _updateZoom(val),
                    ),
                  ),
                  // 퀵 숫자 버튼들
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _zoomQuickBtn("1.0", 0.0),
                        _zoomQuickBtn("1.5", 0.25),
                        _zoomQuickBtn("2.0", 0.5),
                        _zoomQuickBtn("2.5", 0.75),
                        _zoomQuickBtn("3.0", 1.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("취소"),
        ),
        IconButton(
          icon: ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, child) {
              switch (state.torchState) {
                case TorchState.off:
                  return const Icon(Icons.flash_off, color: Colors.grey);
                case TorchState.on:
                  return const Icon(Icons.flash_on, color: Colors.yellow);
                case TorchState.unavailable:
                default:
                  return const Icon(Icons.flash_off, color: Colors.red);
              }
            },
          ),
          onPressed: () => _controller.toggleTorch(),
        ),
        IconButton(
          icon: const Icon(Icons.flip_camera_android),
          onPressed: () => _controller.switchCamera(),
        ),
      ],
    );
  }

  Widget _zoomQuickBtn(String label, double value) {
    bool isSelected = (_currentZoom - value).abs() < 0.05;
    return GestureDetector(
      onTap: () => _updateZoom(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }
}
