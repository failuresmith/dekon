import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../application/application.dart';
import 'ui_strings.dart';

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
      title: Text(context.strings.scanBarcode),
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
                    scannerStatusMessageFor(error, strings: context.strings) ??
                        context.strings.cameraUnavailableEnterManual,
                  );
                },
                placeholderBuilder: (context) {
                  return _ScannerMessage(context.strings.startingCamera);
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
          child: Text(context.strings.manualEntry),
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
    final message = scannerStatusMessageFor(error, strings: context.strings);
    if (message == null) return;
    if (mounted && _error != message) setState(() => _error = message);
  }
}

@visibleForTesting
String? scannerStatusMessageFor(Object error, {UiStrings? strings}) {
  final text = strings ?? UiStrings.forLanguage(AppLanguage.defaultLanguage);
  if (error is MobileScannerBarcodeException) return null;

  if (error is MobileScannerException) {
    final action = error.errorCode == MobileScannerErrorCode.permissionDenied
        ? text.cameraPermissionDeniedEnterManual
        : text.cameraUnavailableEnterManual;
    return '$action\n\n${_scannerDebugDetails(error, text)}';
  }

  return '${text.cameraUnavailableEnterManual}\n\n'
      '${text.scannerError(error.runtimeType.toString())}';
}

String _scannerDebugDetails(MobileScannerException error, UiStrings strings) {
  final details = error.errorDetails;
  final lines = <String>[
    strings.scannerError(error.errorCode.name),
    if (_displayValue(details?.code) case final code?)
      strings.platformCode(code),
    if (_displayValue(details?.message) case final message?)
      strings.platformMessage(message),
    if (_displayValue(details?.details) case final platformDetails?)
      strings.platformDetails(platformDetails),
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
