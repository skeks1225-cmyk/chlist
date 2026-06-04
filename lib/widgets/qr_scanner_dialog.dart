import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class QrScannerDialog extends StatefulWidget {
  final double initialZoom;
  const QrScannerDialog({super.key, required this.initialZoom});

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(autoStart: false); // ❗ 수동 시작 설정
  late double _currentZoom;
  bool _isCameraStarted = false; // ❗ 카메라 시작 여부 플래그

  @override
  void initState() {
    super.initState();
    _currentZoom = widget.initialZoom;
    _startCamera(); // ❗ 비동기 시작 호출
  }

  Future<void> _startCamera() async {
    try {
      // 카메라 시작 대기
      await _controller.start();
      if (mounted) {
        // 시작 직후 즉시 줌 적용
        await _controller.setZoomScale(_currentZoom);
        setState(() {
          _isCameraStarted = true;
        });
      }
    } catch (e) {
      debugPrint("Scanner Start Error: $e");
    }
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
    // ❗ 소수점 두 자리까지 표시하여 정밀도 향상
    String zoomText = _currentZoom.toStringAsFixed(2);

    return AlertDialog(
      title: const Text("바코드/QR 스캔", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        height: 400, // ❗ 버튼 2줄 배치를 고려해 높이 약간 상향
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
                            Navigator.pop(context, "CODE:$code|ZOOM:$_currentZoom");
                          }
                        }
                      },
                    ),
                    if (!_isCameraStarted)
                      Container(
                        color: Colors.black,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    if (_isCameraStarted)
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
                            "Zoom: $zoomText", // ❗ 0.xx 형태로 표시
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
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
                  // ❗ 0.1 단위로 세분화된 버튼들 (1행: 0.0~0.5 / 2행: 0.6~1.0)
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _zoomQuickBtn("0.0", 0.0),
                          _zoomQuickBtn("0.1", 0.1),
                          _zoomQuickBtn("0.2", 0.2),
                          _zoomQuickBtn("0.3", 0.3),
                          _zoomQuickBtn("0.4", 0.4),
                          _zoomQuickBtn("0.5", 0.5),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _zoomQuickBtn("0.6", 0.6),
                          _zoomQuickBtn("0.7", 0.7),
                          _zoomQuickBtn("0.8", 0.8),
                          _zoomQuickBtn("0.9", 0.9),
                          _zoomQuickBtn("1.0", 1.0),
                          const SizedBox(width: 40), // ❗ 1행과 균형을 맞추기 위한 빈 공간
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, "ZOOM:$_currentZoom"),
          child: const Text("취소"),
        ),
        // ... (나머지 IconButton들은 유지)
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
