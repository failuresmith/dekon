import 'package:dekon/src/application/application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('app shell shows Sell, Buy, and Reports navigation', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('Sell'), findsWidgets);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
  });

  testWidgets('unknown barcode opens product creation and adds the item', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'ABC-1');
    await tester.tap(find.byKey(const Key('lookup-product')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('product-name')), 'Beans');
    await tester.enterText(find.byKey(const Key('product-sale-price')), '2.50');
    await tester.enterText(find.byKey(const Key('product-cost')), '1.25');
    await tester.tap(find.byKey(const Key('save-product')));
    await tester.pumpAndSettle();

    expect(find.text('Beans'), findsOneWidget);
  });

  testWidgets('Buy persists purchase and Reports show stock and totals', (
    tester,
  ) async {
    final repository = await createTestRepository();

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode-entry')), 'FLOUR-1');
    await tester.tap(find.byKey(const Key('lookup-product')));
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

    expect(find.text('Flour'), findsWidgets);
    expect(find.text('1.50'), findsOneWidget);
    expect(find.textContaining('Qty 1'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('lookup-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Sale saved'), findsOneWidget);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.text('Tea'), findsWidgets);
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
    await tester.tap(find.byKey(const Key('lookup-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish-sale')));
    await tester.pumpAndSettle();

    expect(find.text('Negative stock warning'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-negative-stock')));
    await tester.pumpAndSettle();

    expect(find.text('Sale saved'), findsOneWidget);
  });
}
