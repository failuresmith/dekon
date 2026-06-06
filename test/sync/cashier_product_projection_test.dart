import 'dart:convert';

import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashierProductProjection serialization', () {
    test('serializes only checkout-safe product fields', () {
      final product = _privateProduct();

      final projection = CashierProductProjection.fromProductSummary(product);
      final serialized = serializeCashierProductProjection(projection);
      final encoded = jsonEncode(serialized);

      expect(serialized.keys, {
        'product_id',
        'barcode',
        'name',
        'stock_quantity',
        'sale_price_minor',
        'active',
      });
      expect(serialized['product_id'], product.productId);
      expect(serialized['barcode'], product.barcode);
      expect(serialized['name'], product.name);
      expect(serialized['stock_quantity'], product.quantity);
      expect(serialized['sale_price_minor'], product.salePriceMinor);
      expect(serialized['active'], product.active);
      _expectNoPrivateProductFields(encoded);
    });

    test('redacts private fields from Cashier inventory snapshots', () {
      final product = _privateProduct();

      final snapshot = serializeCashierInventorySnapshot(
        projectionVersion: 3,
        products: [CashierProductProjection.fromProductSummary(product)],
      );
      final encoded = jsonEncode(snapshot);

      expect(snapshot['projection_version'], 3);
      expect(snapshot['products'], hasLength(1));
      _expectNoPrivateProductFields(encoded);
    });

    test('redacts private fields from Cashier projection updates', () {
      final product = _privateProduct();

      final message = serializeCashierProductUpsertMessage(
        projectionVersion: 4,
        product: CashierProductProjection.fromProductSummary(product),
      );
      final encoded = jsonEncode(message);

      expect(message['projection_version'], 4);
      expect(message['type'], cashierProjectionProductUpsert);
      expect(message['payload'], isA<Map<String, Object?>>());
      _expectNoPrivateProductFields(encoded);
    });

    test('redacts private fields from Cashier inventory patches', () {
      final message = serializeCashierInventoryPatchMessage(
        projectionVersion: 5,
        products: const [
          CashierInventoryPatchProduct(
            productId: 'product-1',
            stockQuantity: 3,
          ),
        ],
      );
      final encoded = jsonEncode(message);

      expect(message['projection_version'], 5);
      expect(message['type'], cashierProjectionInventoryPatch);
      expect(encoded, contains('stock_quantity'));
      _expectNoPrivateProductFields(encoded);
    });

    test('parses projection updates into typed checkout-safe payloads', () {
      final productUpdate = CashierProjectionUpdate.fromJson(
        serializeCashierProductUpsertMessage(
          projectionVersion: 6,
          product: CashierProductProjection.fromProductSummary(
            _privateProduct(),
          ),
        ),
      );
      final patchUpdate = CashierProjectionUpdate.fromJson(
        serializeCashierInventoryPatchMessage(
          projectionVersion: 7,
          products: const [
            CashierInventoryPatchProduct(
              productId: 'product-1',
              stockQuantity: 2,
            ),
          ],
        ),
      );
      final snapshotRequired = CashierProjectionUpdate.fromJson(
        serializeCashierSnapshotRequiredMessage(projectionVersion: 8),
      );

      expect(productUpdate.type, cashierProjectionProductUpsert);
      expect(productUpdate.product?.name, 'Saffron');
      expect(patchUpdate.type, cashierProjectionInventoryPatch);
      expect(patchUpdate.products.single.stockQuantity, 2);
      expect(snapshotRequired.type, cashierProjectionSnapshotRequired);
      expect(snapshotRequired.projectionVersion, 8);
    });

    test('rejects malformed projection updates', () {
      expect(
        () => CashierProjectionUpdate.fromJson({
          'projection_version': 1,
          'type': 'unknown',
          'payload': const <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => CashierProjectionUpdate.fromJson({
          'projection_version': 1,
          'type': cashierProjectionProductUpsert,
          'payload': const <String, Object?>{},
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

ProductSummary _privateProduct() {
  return const ProductSummary(
    productId: 'product-1',
    name: 'Saffron',
    barcode: 'BAR-1',
    sku: 'INTERNAL-SKU-1',
    unit: 'private-case-pack',
    salePriceMinor: 12000,
    purchaseCostMinor: 98765,
    active: true,
    quantity: 4,
  );
}

void _expectNoPrivateProductFields(String encoded) {
  expect(encoded, isNot(contains('purchase_cost_minor')));
  expect(encoded, isNot(contains('purchaseCostMinor')));
  expect(encoded, isNot(contains('unit_cost_minor')));
  expect(encoded, isNot(contains('unit_price_minor')));
  expect(encoded, isNot(contains('98765')));
  expect(encoded, isNot(contains('sku')));
  expect(encoded, isNot(contains('INTERNAL-SKU-1')));
  expect(encoded, isNot(contains('unit')));
  expect(encoded, isNot(contains('private-case-pack')));
  expect(encoded, isNot(contains('supplier')));
  expect(encoded, isNot(contains('margin')));
  expect(encoded, isNot(contains('profit')));
}
