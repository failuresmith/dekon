import 'package:dekon/src/application/application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('app shell shows focused navigation and settings gear', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byKey(const Key('open-settings')), findsOneWidget);
  });

  testWidgets('unknown barcode opens product creation and adds the item', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
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
    final repository = await createTestRepository();
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

  testWidgets('Add Product creates initial stock and Inventory adjusts it', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('add-product-name')), 'Dates');
    await tester.enterText(
      find.byKey(const Key('add-product-barcode')),
      'DATE-1',
    );
    await tester.enterText(
      find.byKey(const Key('add-product-initial-stock')),
      '2',
    );
    await tester.tap(find.byKey(const Key('create-product')));
    await tester.pumpAndSettle();

    expect(find.text('Product saved'), findsOneWidget);
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
    final repository = await createTestRepository();
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
    final repository = await createTestRepository();
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
    final repository = await createTestRepository();
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
    final repository = await createTestRepository();

    await tester.pumpWidget(
      testApp(repository, scanBarcode: (_) async => 'SCAN-1'),
    );
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
    final repository = await createTestRepository();

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
    final repository = await createTestRepository();
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
    final repository = await createTestRepository();
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
