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
    expect(find.text('Restock'), findsOneWidget);
    expect(find.text('Buy'), findsNothing);
    expect(find.text('Add'), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byKey(const Key('sell-history')), findsOneWidget);
    expect(find.byKey(const Key('restock-history')), findsNothing);
    expect(find.byKey(const Key('open-settings')), findsOneWidget);
    expect(find.byKey(const Key('sell-empty-title')), findsOneWidget);
    expect(find.byKey(const Key('sell-empty-help')), findsOneWidget);
    expect(_filledButton(find.byKey(const Key('finish-sale'))).onPressed, null);

    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sell-history')), findsNothing);
    expect(find.byKey(const Key('restock-history')), findsOneWidget);
    expect(find.byKey(const Key('restock-empty-title')), findsOneWidget);
    expect(find.byKey(const Key('restock-empty-help')), findsOneWidget);
    expect(
      _filledButton(find.byKey(const Key('finish-purchase'))).onPressed,
      null,
    );

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sell-history')), findsNothing);
    expect(find.byKey(const Key('restock-history')), findsNothing);
  });

  testWidgets('Settings language choice updates copy and persists', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-language-tile')), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-language-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-option-fa')));
    await tester.pumpAndSettle();

    expect(await repository.appLanguage(), AppLanguage.farsi);
    expect(find.text('زبان به روز شد'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('فروش'), findsWidgets);
    expect(find.text('تنظیمات'), findsNothing);
  });

  testWidgets('root tab state is preserved while switching screens', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'STATE-1');

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    final barcodeField = tester.widget<TextField>(
      find.byKey(const Key('barcode-entry')),
    );
    expect(barcodeField.controller?.text, 'STATE-1');
  });

  testWidgets('main shell shows green indicator for connected cashier', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    try {
      await repository.createSyncStore().trustCashierPeer(
        deviceId: _frontRegisterDeviceId,
        sharedSecret: 'shared-secret',
      );

      await tester.pumpWidget(testApp(repository));
      await _pumpUntilFound(
        tester,
        find.byKey(const Key('main-cashier-connection-indicator-connected')),
      );

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-connected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-disconnected')),
        findsNothing,
      );
      expect(
        (tester.getCenter(
                  find.byKey(const Key('main-cashier-connection-indicator')),
                ) -
                tester.getCenter(find.byKey(const Key('open-settings'))))
            .distance,
        lessThan(1),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('cashier shell shows Inventory and scopes Reports to device', (
    tester,
  ) async {
    final repository = await createTestRepository();
    await repository.lockDeviceRole(DeviceRole.cashierDevice);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Restock'), findsOneWidget);
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
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'ABC-1');
    await tester.pumpAndSettle();
    expect(find.text('This barcode is not in your inventory.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
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
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'tea');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Green Tea'), findsOneWidget);
    expect(find.text('Coffee'), findsNothing);
  });

  testWidgets('Sell does not create unknown products', (tester) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'MISS-1');
    await tester.pumpAndSettle();

    expect(
      find.text('Product not found. Restock it into inventory first.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('product-name')), findsNothing);
    expect(await repository.products(), isEmpty);
  });

  testWidgets('Restock quantity count supports numeric replacement', (
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
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'BULK-RICE');
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
    expect(find.text('Stock: 125'), findsOneWidget);
  });

  testWidgets('Restock and Sell are the Inventory stock mutation path', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'DATE-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
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
    expect(find.text('Stock: 2'), findsOneWidget);
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
    await _submitLookup(tester, 'DATE-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Stock: 1'), findsOneWidget);
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
    await tester.tap(find.byKey(Key('inventory-product-${product.productId}')));
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
    expect(find.text('No products in inventory'), findsOneWidget);
  });

  testWidgets('Inventory search and low-stock filter use compact rows', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    final stocked = await repository.createProduct(
      name: 'Stocked Tea',
      barcode: 'STOCKED-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: stocked, quantity: 2),
    ]);
    final empty = await repository.createProduct(
      name: 'Empty Soda',
      barcode: 'EMPTY-SODA',
      salePriceMinor: 250,
      purchaseCostMinor: 100,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory-search-field')), findsOneWidget);
    expect(find.byKey(const Key('inventory-low-stock-filter')), findsOneWidget);
    expect(find.byKey(const Key('inventory-add-product')), findsOneWidget);
    expect(
      find.byKey(Key('inventory-product-${stocked.productId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('inventory-product-${empty.productId}')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('inventory-search-field')),
      'soda',
    );
    await tester.pumpAndSettle();

    expect(find.text('Empty Soda'), findsOneWidget);
    expect(find.text('Stocked Tea'), findsNothing);

    await tester.enterText(find.byKey(const Key('inventory-search-field')), '');
    await tester.tap(find.byKey(const Key('inventory-low-stock-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Empty Soda'), findsOneWidget);
    expect(find.text('Stocked Tea'), findsNothing);

    await tester.tap(find.byKey(Key('inventory-product-${empty.productId}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Product'), findsOneWidget);
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

  testWidgets('scanned known barcode adds item to Restock flow', (
    tester,
  ) async {
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
    await tester.tap(find.text('Restock'));
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
    await _submitLookup(tester, 'SALT-1');
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
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-barcode')));
    await tester.pumpAndSettle();

    expect(find.text('This barcode is not in your inventory.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
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

  testWidgets('Restock persists purchase and Reports show totals', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'FLOUR-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Flour');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.50');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();

    expect(find.text('Inventory updated'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Purchases'), findsOneWidget);
    expect(find.text('1.50'), findsOneWidget);
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Flour'), findsOneWidget);
    expect(find.textContaining('Stock: 1'), findsOneWidget);
  });

  testWidgets('Reports use summary tiles and drill-down routes', (
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
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);
    expect(find.text('Low-stock Items'), findsOneWidget);
    expect(find.byKey(const Key('reports-view-trend-button')), findsOneWidget);
    expect(find.text('Empty Soda'), findsNothing);
    expect(find.textContaining('Unsynced events:'), findsNothing);
    expect(find.textContaining('Last sync:'), findsNothing);
    expect(find.byKey(const Key('sync-warning')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const Key('reports-view-trend-button'))).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const Key('low-stock-report-metric'))).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('reports-view-trend-button')));
    await tester.pumpAndSettle();

    expect(find.text('Sales Trend'), findsOneWidget);
    expect(find.byKey(const Key('report-trend-period-day')), findsOneWidget);
    expect(find.byKey(const Key('report-trend-period-week')), findsOneWidget);
    expect(find.byKey(const Key('report-trend-period-month')), findsOneWidget);
    expect(find.byKey(const Key('report-trend-period-year')), findsOneWidget);
    expect(find.byKey(const Key('report-trend-chart')), findsOneWidget);
    expect(
      find.byKey(const Key('report-trend-selection-summary')),
      findsOneWidget,
    );
    expect(find.text('Revenue'), findsWidgets);
    expect(find.text('Purchases'), findsWidgets);
    expect(find.byKey(const Key('report-trend-text-summary')), findsOneWidget);
    final bucketFinder = find.byWidgetPredicate(
      (widget) => widget.key.toString().contains('report-trend-bucket-'),
    );
    expect(bucketFinder, findsWidgets);

    await tester.tap(bucketFinder.first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('report-trend-selection-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('report-trend-period-month')));
    await tester.pumpAndSettle();

    expect(find.text('Last 12 months'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

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

    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Daily Sales'), findsNothing);
  });

  testWidgets('Reports sync warning refreshes while the view stays open', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Live Sync Tea',
      barcode: 'LIVE-SYNC-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 2),
    ]);
    final syncStore = repository.createSyncStore();
    await syncStore.trustPeer(
      deviceId: _frontRegisterDeviceId,
      displayName: 'Cashier-1',
      sharedSecret: 'shared-secret',
      baseUrl: 'http://main.local',
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-warning')), findsOneWidget);
    expect(
      find.text(
        '2 transactions have not synced yet. Check Device Sync in Settings.',
      ),
      findsOneWidget,
    );

    final events = await syncStore.fetchEventsAfter(null, limit: 100);
    await syncStore.updatePushCursor(
      _frontRegisterDeviceId,
      SyncCursor.fromEvent(events.last),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-warning')), findsNothing);
    expect(find.textContaining('Last sync:'), findsNothing);
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
    await tester.tap(find.text('Cashier-1').last);
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
    await _submitLookup(tester, 'TEA-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Sale completed'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sell-history')));
    await tester.pumpAndSettle();

    expect(find.text('Sale history'), findsOneWidget);
    expect(find.textContaining('Tea x1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Revenue'), findsOneWidget);
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
    await _submitLookup(tester, 'RICE-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Negative stock warning'), findsOneWidget);
    expect(
      find.textContaining('Only 0 is available in stock.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-negative-stock')));
    await tester.pumpAndSettle();

    expect(find.text('Sale completed'), findsOneWidget);
  });
}

FilledButton _filledButton(Finder finder) {
  return finder.evaluate().single.widget as FilledButton;
}

Future<void> _submitLookup(WidgetTester tester, String query) async {
  final field = find.byKey(const Key('barcode-entry'));
  await tester.tap(field);
  await tester.enterText(field, query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<void> _importFrontRegisterTransactions(
  DekonRepository repository,
  String productId,
) async {
  final store = repository.createSyncStore();
  await store.trustPeer(
    deviceId: _frontRegisterDeviceId,
    displayName: 'Cashier-1',
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
