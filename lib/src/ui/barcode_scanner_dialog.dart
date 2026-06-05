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
  var _closing = false;
  String? _error;

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
                onDetect: _handleDetect,
                onDetectError: _handleError,
                errorBuilder: (context, error) {
                  return _ScannerMessage(
                    scannerStatusMessageFor(error) ??
                        'Camera unavailable. Enter barcode manually.',
                  );
                },
                placeholderBuilder: (context) {
                  return const _ScannerMessage('Starting camera...');
                },
              ),
              if (_error != null) _ScannerMessage(_error!),
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
    final message = scannerStatusMessageFor(error);
    if (message == null) return;
    if (mounted && _error != message) setState(() => _error = message);
  }
}

@visibleForTesting
String? scannerStatusMessageFor(Object error) {
  if (error is MobileScannerBarcodeException) return null;

  if (error is MobileScannerException) {
    final action = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? 'Camera permission denied. Enter barcode manually.'
        : 'Camera unavailable. Enter barcode manually.';
    return '$action\n\n${_scannerDebugDetails(error)}';
  }

  return 'Camera unavailable. Enter barcode manually.\n\n'
      'Scanner error: ${error.runtimeType}';
}

String _scannerDebugDetails(MobileScannerException error) {
  final details = error.errorDetails;
  final lines = <String>[
    'Scanner error: ${error.errorCode.name}',
    if (_displayValue(details?.code) case final code?) 'Platform code: $code',
    if (_displayValue(details?.message) case final message?)
      'Platform message: $message',
    if (_displayValue(details?.details) case final platformDetails?)
      'Platform details: $platformDetails',
  ];
  return lines.join('\n');
}

String? _displayValue(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  const maxLength = 240;
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
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
