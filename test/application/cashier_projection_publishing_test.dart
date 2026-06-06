import 'dart:convert';

import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'product rename publishes one sanitized Cashier product upsert',
    () async {
      await _withRepository((repository) async {
        final updates = <Map<String, Object?>>[];
        final subscription = repository.cashierProjectionUpdates.listen(
          updates.add,
        );
        addTearDown(subscription.cancel);

        final product = await repository.createProduct(
          name: 'Tea',
          barcode: 'TEA-1',
          sku: 'INTERNAL-TEA',
          unit: 'box',
          salePriceMinor: 1000,
          purchaseCostMinor: 600,
        );
        await _flushStream();
        updates.clear();

        await repository.updateProduct(
          _copyProduct(product, name: 'Premium Tea'),
        );
        await _flushStream();

        final version = await repository
            .createSyncStore()
            .cashierInventoryProjectionVersion();
        final update = updates.single;
        final payload = update['payload'] as Map<String, Object?>;
        final serializedProduct = payload['product'] as Map<String, Object?>;

        expect(version, 2);
        expect(update['projection_version'], 2);
        expect(update['type'], cashierProjectionProductUpsert);
        expect(serializedProduct['name'], 'Premium Tea');
        _expectNoPrivateProductFields(jsonEncode(update));
      });
    },
  );

  test(
    'private-only product edit does not advance Cashier projection',
    () async {
      await _withRepository((repository) async {
        final product = await repository.createProduct(
          name: 'Rice',
          barcode: 'RICE-1',
          salePriceMinor: 2000,
          purchaseCostMinor: 1200,
        );
        final updates = <Map<String, Object?>>[];
        final subscription = repository.cashierProjectionUpdates.listen(
          updates.add,
        );
        addTearDown(subscription.cancel);

        await repository.updateProduct(
          _copyProduct(product, purchaseCostMinor: 1300),
        );
        await _flushStream();

        final version = await repository
            .createSyncStore()
            .cashierInventoryProjectionVersion();

        expect(version, 1);
        expect(updates, isEmpty);
      });
    },
  );

  test('visible and private product edit increments projection once', () async {
    await _withRepository((repository) async {
      final updates = <Map<String, Object?>>[];
      final subscription = repository.cashierProjectionUpdates.listen(
        updates.add,
      );
      addTearDown(subscription.cancel);

      final product = await repository.createProduct(
        name: 'Dates',
        barcode: 'DATES-1',
        salePriceMinor: 1500,
        purchaseCostMinor: 700,
      );
      await _flushStream();
      updates.clear();

      await repository.updateProduct(
        _copyProduct(product, name: 'Fresh Dates', purchaseCostMinor: 800),
      );
      await _flushStream();

      final version = await repository
          .createSyncStore()
          .cashierInventoryProjectionVersion();

      expect(version, 2);
      expect(updates, hasLength(1));
      expect(updates.single['projection_version'], 2);
      _expectNoPrivateProductFields(jsonEncode(updates.single));
    });
  });

  test('stock mutations publish sanitized inventory patches', () async {
    await _withRepository((repository) async {
      final product = await repository.createProduct(
        name: 'Beans',
        barcode: 'BEANS-1',
        salePriceMinor: 500,
        purchaseCostMinor: 250,
      );
      final updates = <Map<String, Object?>>[];
      final subscription = repository.cashierProjectionUpdates.listen(
        updates.add,
      );
      addTearDown(subscription.cancel);

      await repository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 5),
      ]);
      await _flushStream();

      final purchasedUpdate = updates.single;
      final purchasedPayload =
          purchasedUpdate['payload'] as Map<String, Object?>;
      final purchasedProducts = purchasedPayload['products'] as List;
      final purchasedProduct = purchasedProducts.single as Map<String, Object?>;

      expect(purchasedUpdate['projection_version'], 2);
      expect(purchasedUpdate['type'], cashierProjectionInventoryPatch);
      expect(purchasedProduct['product_id'], product.productId);
      expect(purchasedProduct['stock_quantity'], 5);
      _expectNoPrivateProductFields(jsonEncode(purchasedUpdate));

      updates.clear();
      final stockedProduct = await repository.productById(product.productId);
      await repository.recordSale([
        TransactionLineDraft(product: stockedProduct!, quantity: 2),
      ]);
      await _flushStream();

      final soldUpdate = updates.single;
      final soldPayload = soldUpdate['payload'] as Map<String, Object?>;
      final soldProducts = soldPayload['products'] as List;
      final soldProduct = soldProducts.single as Map<String, Object?>;
      final version = await repository
          .createSyncStore()
          .cashierInventoryProjectionVersion();

      expect(version, 3);
      expect(soldUpdate['projection_version'], 3);
      expect(soldProduct['stock_quantity'], 3);
      _expectNoPrivateProductFields(jsonEncode(soldUpdate));
    });
  });

  test('last-applied Cashier projection cursor persists', () async {
    await _withRepository((repository) async {
      final store = repository.createSyncStore();

      expect(await store.lastAppliedCashierProjectionVersion(), 0);
      await store.setLastAppliedCashierProjectionVersion(12);

      expect(
        await repository
            .createSyncStore()
            .lastAppliedCashierProjectionVersion(),
        12,
      );
    });
  });
}

Future<void> _withRepository(
  Future<void> Function(DekonRepository repository) body,
) async {
  final db = await CoreDatabase.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
    singleInstance: false,
  );
  final repository = await DekonRepository.open(database: db);
  try {
    await body(repository);
  } finally {
    await repository.close();
  }
}

ProductSummary _copyProduct(
  ProductSummary product, {
  String? name,
  String? barcode,
  String? sku,
  String? unit,
  int? salePriceMinor,
  int? purchaseCostMinor,
  bool? active,
}) {
  return ProductSummary(
    productId: product.productId,
    name: name ?? product.name,
    barcode: barcode ?? product.barcode,
    sku: sku ?? product.sku,
    unit: unit ?? product.unit,
    salePriceMinor: salePriceMinor ?? product.salePriceMinor,
    purchaseCostMinor: purchaseCostMinor ?? product.purchaseCostMinor,
    active: active ?? product.active,
    quantity: product.quantity,
  );
}

Future<void> _flushStream() {
  return Future<void>.delayed(Duration.zero);
}

void _expectNoPrivateProductFields(String encoded) {
  expect(encoded, isNot(contains('purchase_cost_minor')));
  expect(encoded, isNot(contains('purchaseCostMinor')));
  expect(encoded, isNot(contains('unit_cost_minor')));
  expect(encoded, isNot(contains('unit_price_minor')));
  expect(encoded, isNot(contains('sku')));
  expect(encoded, isNot(contains('INTERNAL')));
  expect(encoded, isNot(contains('supplier')));
  expect(encoded, isNot(contains('margin')));
  expect(encoded, isNot(contains('profit')));
}
