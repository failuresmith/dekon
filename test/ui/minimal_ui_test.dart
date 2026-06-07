import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/event_fixtures.dart';
import '../helpers/test_app.dart';

const _frontRegisterDeviceId = '018f2f12-7b60-7a15-8c7d-000000000002';

void main() {
  testWidgets('first run defaults to Farsi when no language is saved', (
    tester,
  ) async {
    final repository = await createTestRepository();

    expect(AppLanguage.fromStorage(null), AppLanguage.farsi);
    expect(AppLanguage.fromStorage('unknown'), AppLanguage.farsi);
    expect(AppLanguage.fromStorage('en'), AppLanguage.english);
    expect(await repository.appLanguage(), AppLanguage.farsi);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('راه اندازی این دستگاه'), findsOneWidget);
    expect(find.text('Set up this device'), findsNothing);
    expect(find.byKey(const Key('onboarding-main-device')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-cashier-device')), findsOneWidget);
  });

  testWidgets('first run asks for device role and main enters app', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository();

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
    final repository = await createEnglishTestRepository();
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
    final repository = await createEnglishTestRepository(onboarded: true);

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
    expect(find.byKey(const Key('finish-sale')), findsNothing);

    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sell-history')), findsNothing);
    expect(find.byKey(const Key('restock-history')), findsOneWidget);
    expect(find.byKey(const Key('restock-empty-title')), findsOneWidget);
    expect(find.byKey(const Key('restock-empty-help')), findsOneWidget);
    expect(find.byKey(const Key('finish-purchase')), findsNothing);

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sell-history')), findsNothing);
    expect(find.byKey(const Key('restock-history')), findsNothing);
  });

  testWidgets('transaction summary appears only after adding an item', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Summary Tea',
      barcode: 'SUMMARY-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sale-total')), findsNothing);
    expect(find.byKey(const Key('finish-sale')), findsNothing);

    await _submitLookup(tester, 'SUMMARY-TEA');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sale-total')), findsOneWidget);
    expect(find.byKey(const Key('finish-sale')), findsOneWidget);

    await tester.tap(find.byKey(const Key('remove-line-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sale-total')), findsNothing);
    expect(find.byKey(const Key('finish-sale')), findsNothing);

    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('purchase-total')), findsNothing);
    expect(find.byKey(const Key('finish-purchase')), findsNothing);

    await _submitLookup(tester, 'SUMMARY-TEA');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('purchase-total')), findsOneWidget);
    expect(find.byKey(const Key('finish-purchase')), findsOneWidget);
  });

  testWidgets('Settings language choice updates copy and persists', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);

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

  testWidgets('Settings money unit changes display while storing Rial', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    await repository.createProduct(
      name: 'Toman Tea',
      barcode: 'TOMAN-TEA',
      salePriceMinor: 10000,
      purchaseCostMinor: 5000,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-money-unit-tile')), findsOneWidget);
    expect(find.text('Displayed as Rial. Stored as Rial.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-money-unit-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('money-unit-option-toman')));
    await tester.pumpAndSettle();

    expect(await repository.appMoneyUnit(), MoneyUnit.toman);
    expect(find.text('Money unit updated'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _submitLookup(tester, 'TOMAN-TEA');
    await tester.pumpAndSettle();

    expect(find.text('1,000 Toman each'), findsOneWidget);
    final saleTotal = tester.widget<Text>(find.byKey(const Key('sale-total')));
    expect(saleTotal.data, '1,000 Toman');

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Saffron');
    await tester.enterText(
      find.byKey(const Key('product-sale-price')),
      '1,500',
    );
    await tester.enterText(find.byKey(const Key('product-cost')), '750');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    final created = await repository.productsMatchingName('Saffron');
    expect(created.single.salePriceMinor, 15000);
    expect(created.single.purchaseCostMinor, 7500);
  });

  testWidgets('product money fields select current value for replacement', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Price Tea',
      barcode: 'PRICE-TEA',
      salePriceMinor: 1200,
      purchaseCostMinor: 700,
    );

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('inventory-product-${product.productId}')));
    await tester.pumpAndSettle();

    final salePriceFinder = find.byKey(const Key('product-sale-price'));
    await tester.tap(salePriceFinder);
    await tester.pump();

    final salePriceField = tester.widget<TextFormField>(salePriceFinder);
    expect(salePriceField.controller?.text, '1,200');
    expect(
      salePriceField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );

    await tester.enterText(salePriceFinder, '1500');
    await tester.pump();

    final costFinder = find.byKey(const Key('product-cost'));
    await tester.tap(costFinder);
    await tester.pump();

    final costField = tester.widget<TextFormField>(costFinder);
    expect(costField.controller?.text, '700');
    expect(
      costField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.enterText(costFinder, '800');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    final updated = await repository.productById(product.productId);
    expect(updated?.salePriceMinor, 1500);
    expect(updated?.purchaseCostMinor, 800);
  });

  testWidgets('Farsi language renders app numbers with readable Persian font', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    await repository.setAppLanguage(AppLanguage.farsi);
    final product = await repository.createProduct(
      name: 'Tea',
      barcode: 'FA-TEA-1',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 3),
    ]);
    await repository.recordSale([
      TransactionLineDraft(product: product, quantity: 1),
    ]);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'FA-TEA-1');
    await tester.pumpAndSettle();

    expect(find.text('تعداد کالا: ۱'), findsOneWidget);
    expect(find.text('هر عدد ۴۰۰ ریال'), findsOneWidget);
    final theme = Theme.of(
      tester.element(find.byKey(const Key('finish-sale'))),
    );
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Vazirmatn');
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      contains('Noto Sans Arabic'),
    );
    expect(find.text('4.00'), findsNothing);

    final quantityField = tester.widget<TextField>(
      find.byKey(const Key('line-quantity-0')),
    );
    expect(quantityField.controller?.text, '۱');

    await tester.enterText(find.byKey(const Key('line-quantity-0')), '۲');
    await tester.pumpAndSettle();

    final saleTotal = tester.widget<Text>(find.byKey(const Key('sale-total')));
    expect(saleTotal.data, '۸۰۰ ریال');
    expect(find.text('8.00'), findsNothing);

    await tester.tap(find.text('گزارش ها'));
    await tester.pumpAndSettle();

    expect(find.text('درآمد'), findsOneWidget);
    expect(find.text('۴۰۰ ریال'), findsOneWidget);
  });

  testWidgets('root tab state is preserved while switching screens', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);

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

  testWidgets(
    'main shell hides connection indicator without live cashier socket',
    (tester) async {
      final repository = await createEnglishTestRepository(onboarded: true);
      try {
        await repository.createSyncStore().trustCashierPeer(
          deviceId: _frontRegisterDeviceId,
          sharedSecret: 'shared-secret',
        );

        await tester.pumpWidget(testApp(repository));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('main-cashier-connection-indicator-connected')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('cashier-sync-indicator-disconnected')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('main-cashier-connection-indicator')),
          findsNothing,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.close();
      }
    },
  );

  testWidgets('Device Sync count updates when a cashier pairs while open', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    try {
      await tester.pumpWidget(testApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-device-sync-tile')));
      await tester.pumpAndSettle();

      expect(find.text('0 devices paired'), findsOneWidget);

      await repository.createSyncStore().trustCashierPeer(
        deviceId: _frontRegisterDeviceId,
        sharedSecret: 'shared-secret',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 device paired'), findsOneWidget);
      expect(find.text('Cashier-1'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('cashier shell shows read-only Inventory and hides admin flows', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository();
    final product = await repository.createProduct(
      name: 'Cashier Tea',
      barcode: 'CASHIER-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 3),
    ]);
    await repository.lockDeviceRole(DeviceRole.cashierDevice);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Restock'), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Reports'), findsNothing);
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

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    expect(find.text('Stock: 3\nSale price: 400 Rial'), findsOneWidget);

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-sale-sync-warning')), findsOneWidget);

    await _submitLookup(tester, 'CASHIER-TEA');
    await tester.pumpAndSettle();

    final finishSale = tester.widget<FilledButton>(
      find.byKey(const Key('finish-sale')),
    );
    expect(finishSale.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Sale saved on this cashier. It will sync when the main device returns.',
      ),
      findsOneWidget,
    );
    expect((await repository.cashierSaleOutboxSummary()).queuedCount, 1);

    await tester.tap(find.byKey(const Key('sell-history')));
    await tester.pumpAndSettle();

    expect(find.text('Sale history'), findsOneWidget);
    expect(find.textContaining('Cashier Tea x1'), findsOneWidget);
    expect(
      find.byKey(const Key('transaction-history-pending-approval-0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('transaction-history-entry-0')));
    await tester.pumpAndSettle();

    expect(find.text('Sale detail'), findsOneWidget);
    expect(find.text('Not approved by main device yet'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory-add-product')), findsNothing);
    expect(find.text('Stock: 2\nSale price: 400 Rial'), findsOneWidget);
    expect(find.text('Stock: 3\nSale price: 400 Rial'), findsNothing);
    await tester.tap(find.byKey(Key('inventory-product-${product.productId}')));
    await tester.pumpAndSettle();

    expect(find.text('Cashier Tea'), findsWidgets);
    expect(find.text('Stock: 2'), findsOneWidget);
    expect(find.text('Sale price: 400 Rial'), findsOneWidget);
    expect(find.text('Barcode: CASHIER-TEA'), findsOneWidget);
    expect(find.text('Edit Product'), findsNothing);
    expect(find.text('Purchase cost'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-backup-restore-tile')), findsNothing);
    expect(find.byKey(const Key('settings-device-sync-tile')), findsOneWidget);
  });

  testWidgets('unknown barcode opens product creation and adds the item', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);

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
    await tester.enterText(find.byKey(const Key('product-sale-price')), '250');
    await tester.enterText(find.byKey(const Key('product-cost')), '125');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    expect(find.text('Beans'), findsOneWidget);
  });

  testWidgets('product search filters matching products by name', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);

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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    expect(total.data, '12,500 Rial');

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
    final repository = await createEnglishTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'DATE-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Dates');
    await tester.enterText(find.byKey(const Key('product-cost')), '125');
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);

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
    await tester.enterText(find.byKey(const Key('product-sale-price')), '250');
    await tester.enterText(find.byKey(const Key('product-cost')), '125');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    expect(find.text('Beans'), findsOneWidget);
  });

  testWidgets('Restock persists purchase and Reports show totals', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await _submitLookup(tester, 'FLOUR-1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-product-from-lookup')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Flour');
    await tester.enterText(find.byKey(const Key('product-cost')), '150');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('line-unit-cost-0')), '175');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-purchase')));
    await tester.pumpAndSettle();

    expect(find.text('Inventory updated'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Restock Amount'), findsOneWidget);
    expect(find.text('175 Rial'), findsOneWidget);
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();

    expect(find.text('Flour'), findsOneWidget);
    expect(find.textContaining('Stock: 1'), findsOneWidget);
  });

  testWidgets('Reports use summary tiles and drill-down routes', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
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
    expect(find.text('400 Rial'), findsOneWidget);
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
    expect(find.text('Restock Amount'), findsWidgets);
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
    final repository = await createEnglishTestRepository(onboarded: true);
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
    final repository = await createEnglishTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Register Tea',
      barcode: 'REGISTER-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 1),
    ]);
    await repository.recordSale([
      TransactionLineDraft(product: product, quantity: 1),
    ]);
    await _importFrontRegisterTransactions(repository, product.productId);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-report-filter')), findsOneWidget);
    expect(find.text('1,200 Rial'), findsOneWidget);
    expect(find.byKey(const Key('low-stock-report-metric')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cashier-report-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashier-1').last);
    await tester.pumpAndSettle();

    expect(find.text('800 Rial'), findsOneWidget);
    expect(find.text('1,200 Rial'), findsNothing);
    expect(find.byKey(const Key('low-stock-report-metric')), findsNothing);

    await tester.tap(find.byKey(const Key('sales-report-metric')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Register Tea x2'), findsOneWidget);
    expect(find.textContaining('Register Tea x1'), findsNothing);
  });

  testWidgets('Sale history filters by creator and exposes date range', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    final product = await repository.createProduct(
      name: 'Register Tea',
      barcode: 'SALE-HISTORY-REGISTER-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: product, quantity: 3),
    ]);
    await repository.recordSale([
      TransactionLineDraft(product: product, quantity: 1),
    ]);
    await _importFrontRegisterTransactions(repository, product.productId);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sell-history')));
    await tester.pumpAndSettle();

    expect(find.text('Sale history'), findsOneWidget);
    expect(
      find.byKey(const Key('sale-history-creator-filter')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sale-history-date-filter')), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
    expect(find.textContaining('Created by: This device'), findsOneWidget);
    expect(find.textContaining('Created by: Cashier-1'), findsOneWidget);
    expect(find.textContaining('Register Tea x1'), findsOneWidget);
    expect(find.textContaining('Register Tea x2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sale-history-creator-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashier-1').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Register Tea x2'), findsOneWidget);
    expect(find.textContaining('Register Tea x1'), findsNothing);
    expect(find.textContaining('Created by: Cashier-1'), findsOneWidget);
    expect(find.textContaining('Created by: This device'), findsNothing);
  });

  testWidgets('Sell persists sale after stock check', (tester) async {
    final repository = await createEnglishTestRepository(onboarded: true);
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
    expect(find.text('400 Rial'), findsOneWidget);
  });

  testWidgets('Transaction history opens readable sale and restock details', (
    tester,
  ) async {
    final repository = await createEnglishTestRepository(onboarded: true);
    final tea = await repository.createProduct(
      name: 'Tea',
      barcode: 'DETAIL-TEA',
      salePriceMinor: 400,
      purchaseCostMinor: 150,
    );
    final sugar = await repository.createProduct(
      name: 'Sugar',
      barcode: 'DETAIL-SUGAR',
      salePriceMinor: 250,
      purchaseCostMinor: 100,
    );
    await repository.recordPurchase([
      TransactionLineDraft(product: tea, quantity: 5),
      TransactionLineDraft(product: sugar, quantity: 7),
    ]);
    await repository.recordSale([
      TransactionLineDraft(product: tea, quantity: 2),
      TransactionLineDraft(product: sugar, quantity: 3),
    ]);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sell-history')));
    await tester.pumpAndSettle();

    expect(find.text('Sale history'), findsOneWidget);
    expect(find.textContaining('Tea x2'), findsOneWidget);
    expect(find.textContaining('Sugar x3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('transaction-history-entry-0')));
    await tester.pumpAndSettle();

    expect(find.text('Sale detail'), findsOneWidget);
    expect(find.text('Total: 1,550 Rial'), findsOneWidget);
    final saleTeaLine = find.byKey(const Key('transaction-history-line-0'));
    final saleSugarLine = find.byKey(const Key('transaction-history-line-1'));
    expect(
      find.descendant(of: saleTeaLine, matching: find.text('Tea')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: saleTeaLine, matching: find.text('Quantity: 2')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: saleTeaLine, matching: find.text('800 Rial')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: saleSugarLine, matching: find.text('Sugar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: saleSugarLine, matching: find.text('Quantity: 3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('transaction-history-back')));
    await tester.pumpAndSettle();

    expect(find.text('Sale history'), findsOneWidget);
    expect(find.text('Sale detail'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restock-history')));
    await tester.pumpAndSettle();

    expect(find.text('Restock history'), findsOneWidget);
    await tester.tap(find.byKey(const Key('transaction-history-entry-0')));
    await tester.pumpAndSettle();

    expect(find.text('Restock detail'), findsOneWidget);
    expect(find.text('Total: 1,450 Rial'), findsOneWidget);
    final restockTeaLine = find.byKey(const Key('transaction-history-line-0'));
    final restockSugarLine = find.byKey(
      const Key('transaction-history-line-1'),
    );
    expect(
      find.descendant(of: restockTeaLine, matching: find.text('Quantity: 5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: restockSugarLine, matching: find.text('Quantity: 7')),
      findsOneWidget,
    );
  });

  testWidgets('Sell blocks negative stock before completion', (tester) async {
    final repository = await createEnglishTestRepository(onboarded: true);
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

    expect(
      find.textContaining(
        'Only 0 is available in stock. Restock this product before completing the sale.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sale completed'), findsNothing);
  });
}

Future<void> _submitLookup(WidgetTester tester, String query) async {
  final field = find.byKey(const Key('barcode-entry'));
  await tester.tap(field);
  await tester.enterText(field, query);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
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
          {
            'product_id': productId,
            'quantity': 2,
            'unit_price_minor': 400,
            'cost_total_minor': 300,
            'cost_allocations': [
              {
                'lot_id':
                    'front-register-purchase-1:${EventTypes.inventoryPurchaseRecorded}:0',
                'source_event_id': 'front-register-purchase-1',
                'quantity': 2,
                'unit_cost_minor': 150,
                'cost_minor': 300,
              },
            ],
          },
        ],
      },
    ),
  ]);
}
