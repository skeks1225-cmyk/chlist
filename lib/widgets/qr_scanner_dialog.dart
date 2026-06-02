import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({super.key});

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: const Text("QR 코드 스캔", style: TextStyle(fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 300,
        height: 300,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(
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
}
