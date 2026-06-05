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

  test('scanner permission and camera failures get actionable messages', () {
    expect(
      scannerStatusMessageFor(
        const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
        ),
      ),
      'Camera permission denied. Use manual entry.',
    );

    expect(
      scannerStatusMessageFor(
        const MobileScannerException(
          errorCode: MobileScannerErrorCode.genericError,
        ),
      ),
      'Camera unavailable. Use manual entry.',
    );
  });
}
