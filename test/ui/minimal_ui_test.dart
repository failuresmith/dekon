import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('first run asks for device role and main enters app', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Set up this device'), findsOneWidget);
    expect(find.byKey(const Key('onboarding-main-device')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-cashier-device')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-main-device')));
    await tester.pumpAndSettle();

    final settings = await repository.deviceRoleSettings();
    expect(settings.role, DeviceRole.mainDevice);
    expect(settings.onboardingCompleted, true);
    expect(find.byKey(const Key('open-settings')), findsOneWidget);
  });

  testWidgets('cashier onboarding requires successful pairing', (tester) async {
    final repository = await createTestRepository();
    final payload = SyncPairingPayload(
      baseUrl: 'http://192.168.1.10:1234',
      serverDeviceId: '019e9239-1111-7000-8000-000000000001',
      pairingSecret: 'pairing-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
    SyncPairingPayload? pairedPayload;

    await tester.pumpWidget(
      testApp(
        repository,
        scanBarcode: (_) async => payload.toQrJson(),
        pairWithMainDevice: (payload) async {
          pairedPayload = payload;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboarding-cashier-device')));
    await tester.pumpAndSettle();

    expect(find.text('Pair cashier device'), findsOneWidget);
    expect(find.byKey(const Key('pair-main-device')), findsOneWidget);
    expect(find.byKey(const Key('open-settings')), findsNothing);

    await tester.tap(find.byKey(const Key('pair-main-device')));
    await tester.pumpAndSettle();

    final settings = await repository.deviceRoleSettings();
    expect(pairedPayload?.serverDeviceId, payload.serverDeviceId);
    expect(settings.role, DeviceRole.cashierDevice);
    expect(settings.locked, true);
    expect(settings.onboardingCompleted, true);
    expect(find.byKey(const Key('open-settings')), findsOneWidget);
  });

  testWidgets('app shell shows focused navigation and settings gear', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byKey(const Key('open-settings')), findsOneWidget);
  });

  testWidgets('unknown barcode opens product creation and adds the item', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'ABC-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Beans');
    await tester.enterText(find.byKey(const Key('product-sale-price')), '2.50');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.25');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    expect(find.text('Beans'), findsOneWidget);
  });

  testWidgets('product search filters matching products by name', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Green Tea',
      barcode: 'GREEN-TEA',
      salePriceMinor: 400,
    );
    await repository.createProduct(
      name: 'Coffee',
      barcode: 'COFFEE-1',
      salePriceMinor: 500,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lookup-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('product-search-input')),
      'tea',
    );
    await tester.pumpAndSettle();

    expect(find.text('Green Tea'), findsOneWidget);
    expect(find.text('Coffee'), findsNothing);
  });

  testWidgets('Sell does not create unknown products', (tester) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'MISS-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();

    expect(
      find.text('Product not found. Buy it into inventory first.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('product-name')), findsNothing);
    expect(await repository.products(), isEmpty);
  });

  testWidgets('Buy creates product and Inventory adjusts purchased stock', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'DATE-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Dates');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.25');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('increase-line-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Dates'), findsOneWidget);
    expect(find.text('Stock 2'), findsOneWidget);
    final product = (await repository.products()).single;
    await tester.tap(find.byKey(Key('stock-decrease-${product.productId}')));
    await tester.pumpAndSettle();

    expect(find.text('Stock 1'), findsOneWidget);
  });

  testWidgets('scanned known barcode adds item to Sell flow', (tester) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Scan Tea',
      barcode: 'TEA-SCAN-1',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );

    await tester.pumpWidget(
      testApp(repository, scanBarcode: (_) async => 'TEA-SCAN-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(find.text('Scan Tea'), findsOneWidget);
  });

  testWidgets('scanned known barcode adds item to Buy flow', (tester) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Sugar',
      barcode: 'SUGAR-1',
      salePriceMinor: 300,
      purchaseCostMinor: 125,
    );

    await tester.pumpWidget(
      testApp(repository, scanBarcode: (_) async => 'SUGAR-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(find.text('Sugar'), findsOneWidget);
  });

  testWidgets('scanner failure preserves manual barcode fallback', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Salt',
      barcode: 'SALT-1',
      salePriceMinor: 100,
      purchaseCostMinor: 40,
    );

    await tester.pumpWidget(
      testApp(
        repository,
        scanBarcode: (_) async {
          throw StateError('permission denied');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(
      find.text('Scan unavailable. Enter barcode manually.'),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'SALT-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();

    expect(find.text('Salt'), findsOneWidget);
  });

  testWidgets('unknown scanned barcode opens product creation and adds item', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(
      testApp(repository, scanBarcode: (_) async => 'SCAN-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    final barcodeField = tester.widget<TextFormField>(
      find.byKey(const Key('product-barcode')),
    );
    expect(barcodeField.controller?.text, 'SCAN-1');
    await tester.enterText(find.byKey(const Key('product-name')), 'Beans');
    await tester.enterText(find.byKey(const Key('product-sale-price')), '2.50');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.25');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    expect(find.text('Beans'), findsOneWidget);
  });

  testWidgets('Buy persists purchase and Reports show totals', (tester) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'FLOUR-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Flour');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.50');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();

    expect(find.text('Purchase saved'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Purchases'), findsOneWidget);
    expect(find.text('1.50'), findsOneWidget);
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Flour'), findsOneWidget);
    expect(find.textContaining('Stock 1'), findsOneWidget);
  });

  testWidgets('Sell persists sale after stock check', (tester) async {
    final repository = await createTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Tea',
      barcode: 'TEA-1',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 3),
    ]);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'TEA-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Sale saved'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sell-history')));
    await tester.pumpAndSettle();

    expect(find.text('Sale History'), findsOneWidget);
    expect(find.textContaining('Tea x1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Daily Sales'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);
  });

  testWidgets('Sell warns before allowing negative stock', (tester) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Rice',
      barcode: 'RICE-1',
      salePriceMinor: 300,
      purchaseCostMinor: 100,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'RICE-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Negative stock warning'), findsOneWidget);
    expect(find.text('Not enough stock: 0 available.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-negative-stock')));
    await tester.pumpAndSettle();

    expect(find.text('Sale saved'), findsOneWidget);
  });
}
