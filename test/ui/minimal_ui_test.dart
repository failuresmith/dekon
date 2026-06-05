import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/event_fixtures.dart';
import '../helpers/test_app.dart';

const _frontRegisterDeviceId = '018f2f12-7b60-7a15-8c7d-000000000002';

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

  testWidgets('cashier shell shows Inventory and scopes Reports to device', (
    tester,
  ) async {
    final repository = await createTestRepository();
    await repository.lockDeviceRole(DeviceRole.cashierDevice);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byKey(const Key('cashier-sync-indicator')), findsOneWidget);
    expect(
      find.byKey(const Key('cashier-sync-indicator-disconnected')),
      findsOneWidget,
    );
    expect(
      (tester.getCenter(find.byKey(const Key('cashier-sync-indicator'))) -
              tester.getCenter(find.byKey(const Key('open-settings'))))
          .distance,
      lessThan(1),
    );

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('This Device Reports'), findsOneWidget);
    expect(find.byKey(const Key('local-device-report-scope')), findsOneWidget);
    expect(find.byKey(const Key('low-stock-report-metric')), findsNothing);
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

  testWidgets('Buy quantity count supports numeric replacement', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Bulk Rice',
      barcode: 'BULK-RICE',
      salePriceMinor: 150,
      purchaseCostMinor: 100,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'BULK-RICE');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();

    final quantityFinder = find.byKey(const Key('line-quantity-0'));
    await tester.tap(quantityFinder);
    await tester.pump();

    final focusedField = tester.widget<TextField>(quantityFinder);
    expect(
      focusedField.keyboardType,
      const TextInputType.numberWithOptions(decimal: true),
    );
    expect(
      focusedField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );

    await tester.enterText(quantityFinder, '125');
    await tester.pumpAndSettle();

    final editedField = tester.widget<TextField>(quantityFinder);
    expect(editedField.controller?.text, '125');
    final total = tester.widget<Text>(find.byKey(const Key('purchase-total')));
    expect(total.data, '125.00');

    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Bulk Rice'), findsOneWidget);
    expect(find.text('Stock 125'), findsOneWidget);
  });

  testWidgets('Buy and Sell are the Inventory stock mutation path', (
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
    expect(
      find.byKey(Key('stock-decrease-${product.productId}')),
      findsNothing,
    );
    expect(
      find.byKey(Key('stock-increase-${product.productId}')),
      findsNothing,
    );

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'DATE-1');
    await tester.tap(find.byKey(const Key('lookup-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Stock 1'), findsOneWidget);
  });

  testWidgets('Inventory delete is a soft delete for auditability', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Audit Beans',
      barcode: 'AUDIT-1',
      salePriceMinor: 250,
      purchaseCostMinor: 125,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('edit-${product.productId}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('soft-delete-product')));
    await tester.pumpAndSettle();

    expect(find.text('Delete product?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-soft-delete-product')));
    await tester.pumpAndSettle();

    final retainedProduct = await repository.productById(product.productId);
    expect(retainedProduct, isNotNull);
    expect(retainedProduct!.active, false);
    expect(await repository.productByBarcodeOrSku('AUDIT-1'), isNull);
    expect((await repository.products()).single.productId, product.productId);
    expect(find.text('Audit Beans'), findsNothing);
    expect(find.text('No products'), findsOneWidget);
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

  testWidgets('Reports use summary tiles and drill-down modals', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    final tea = await repository.createProduct(
      name: 'Report Tea',
      barcode: 'REPORT-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.createProduct(
      name: 'Empty Soda',
      barcode: 'EMPTY-SODA',
      salePriceMinor: 250,
      purchaseCostMinor: 100,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: tea, quantity: 3),
    ]);
    await repository.recordSale([
      TransactionLineDraft(product: tea, quantity: 1),
    ]);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report-period-day')), findsOneWidget);
    expect(find.byKey(const Key('report-period-week')), findsOneWidget);
    expect(find.byKey(const Key('report-period-month')), findsOneWidget);
    expect(find.byKey(const Key('report-period-custom')), findsOneWidget);
    expect(find.text('Daily Sales'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);
    expect(find.text('Low Stock'), findsOneWidget);
    expect(find.text('Empty Soda'), findsNothing);
    expect(find.textContaining('Unsynced events:'), findsOneWidget);
    expect(find.textContaining('Last sync:'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('sync-status'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('sales-report-metric'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('sales-report-metric')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Report Tea x1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('low-stock-report-metric')));
    await tester.pumpAndSettle();

    expect(find.text('Empty Soda'), findsOneWidget);
    expect(find.text('Qty 0'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('report-period-week')));
    await tester.pumpAndSettle();

    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Daily Sales'), findsNothing);
  });

  testWidgets('Reports can filter performance by cashier', (tester) async {
    final repository = await createTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Register Tea',
      barcode: 'REGISTER-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordSale([
      TransactionLineDraft(product: product, quantity: 1),
    ]);
    await _importFrontRegisterTransactions(repository, product.productId);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-report-filter')), findsOneWidget);
    expect(find.text('12.00'), findsOneWidget);
    expect(find.byKey(const Key('low-stock-report-metric')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cashier-report-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Front Register').last);
    await tester.pumpAndSettle();

    expect(find.text('8.00'), findsOneWidget);
    expect(find.text('12.00'), findsNothing);
    expect(find.byKey(const Key('low-stock-report-metric')), findsNothing);

    await tester.tap(find.byKey(const Key('sales-report-metric')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Register Tea x2'), findsOneWidget);
    expect(find.textContaining('Register Tea x1'), findsNothing);
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

Future<void> _importFrontRegisterTransactions(
  DekonRepository repository,
  String productId,
) async {
  final store = repository.createSyncStore();
  await store.trustPeer(
    deviceId: _frontRegisterDeviceId,
    displayName: 'Front Register',
    sharedSecret: 'shared-secret',
  );
  final now = DateTime.now().toUtc();
  await store.importEvents([
    makeTestEvent(
      eventId: '018f2f12-7b60-7a15-8c7d-000000500001',
      deviceId: _frontRegisterDeviceId,
      type: EventTypes.inventoryPurchaseRecorded,
      entityId: 'front-register-purchase-1',
      physicalTimeMillis: now.millisecondsSinceEpoch,
      createdAt: now,
      payload: {
        'occurred_at': now.toIso8601String(),
        'total_minor': 600,
        'line_items': [
          {'product_id': productId, 'quantity': 4, 'unit_cost_minor': 150},
        ],
      },
    ),
    makeTestEvent(
      eventId: '018f2f12-7b60-7a15-8c7d-000000500002',
      deviceId: _frontRegisterDeviceId,
      type: EventTypes.inventorySaleRecorded,
      entityId: 'front-register-sale-1',
      physicalTimeMillis: now.millisecondsSinceEpoch + 1,
      createdAt: now.add(const Duration(milliseconds: 1)),
      payload: {
        'occurred_at': now.toIso8601String(),
        'total_minor': 800,
        'line_items': [
          {'product_id': productId, 'quantity': 2, 'unit_price_minor': 400},
        ],
      },
    ),
  ]);
}
