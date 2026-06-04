import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

typedef BarcodeScanLauncher = Future<String?> Function(BuildContext context);

Future<String?> showBarcodeScannerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const BarcodeScannerDialog(),
  );
}

class BarcodeScannerDialog extends StatefulWidget {
  const BarcodeScannerDialog({super.key});

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  final _controller = MobileScannerController();
  var _closing = false;
  String? _error;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan barcode'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _handleDetect,
                onDetectError: _handleError,
              ),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  if (!state.hasCameraPermission) {
                    return const _ScannerMessage(
                      'Camera permission denied. Enter barcode manually.',
                    );
                  }
                  final error = _error;
                  if (error != null) return _ScannerMessage(error);
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('manual-barcode-entry'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Manual entry'),
        ),
      ],
    );
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_closing) return;
    final value = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    _closing = true;
    Navigator.pop(context, value);
  }

  void _handleError(Object error, StackTrace stackTrace) {
    final message = _messageFor(error);
    if (mounted && _error != message) setState(() => _error = message);
  }

  String _messageFor(Object error) {
    if (error is MobileScannerException &&
        error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return 'Camera permission denied. Enter barcode manually.';
    }
    return 'Camera unavailable. Enter barcode manually.';
  }
}

class _ScannerMessage extends StatelessWidget {
  const _ScannerMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            key: const Key('scanner-status'),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      ),
    );
  }
}
