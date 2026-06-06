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
      contains('اجازه دوربین داده نشده است. بارکد را دستی وارد کنید.'),
    );
    expect(permissionMessage, contains('خطای اسکنر: permissionDenied'));

    final cameraMessage = scannerStatusMessageFor(
      const MobileScannerException(
        errorCode: MobileScannerErrorCode.genericError,
      ),
    );
    expect(
      cameraMessage,
      contains('دوربین در دسترس نیست. بارکد را دستی وارد کنید.'),
    );
    expect(cameraMessage, contains('خطای اسکنر: genericError'));
  });
}
