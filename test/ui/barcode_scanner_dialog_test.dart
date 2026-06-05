import 'package:dekon/src/ui/barcode_scanner_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('scanner frame misses are not reported as camera unavailable', () {
    expect(
      scannerStatusMessageFor(const MobileScannerBarcodeException(null)),
      isNull,
    );
  });

  test('scanner permission and camera failures include diagnostics', () {
    final permissionMessage = scannerStatusMessageFor(
      const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      ),
    );
    expect(
      permissionMessage,
      contains('Camera permission denied. Enter barcode manually.'),
    );
    expect(permissionMessage, contains('Scanner error: permissionDenied'));

    final cameraMessage = scannerStatusMessageFor(
      const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
      ),
    );
    expect(
      cameraMessage,
      contains('Camera unavailable. Enter barcode manually.'),
    );
    expect(cameraMessage, contains('Scanner error: genericError'));
  });
}
