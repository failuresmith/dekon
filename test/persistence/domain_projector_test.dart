import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/event_fixtures.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<T> withProjectionDb<T>(
    Future<T> Function(Database db, EventStore store, DomainProjector projector)
    body,
  ) async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      return await body(db, EventStore(db), DomainProjector(db));
    } finally {
      await db.close();
    }
  }

  Future<void> appendAndApply(
    EventStore store,
    DomainProjector projector,
    EventEnvelope event,
  ) async {
    await store.append(event);
    await projector.apply(event);
  }

  test('projects product create, field update, and deactivation', () async {
    await withProjectionDb((db, store, projector) async {
      await appendAndApply(store, projector, _productCreated('000201'));
      await appendAndApply(
        store,
        projector,
        _fieldSet('000202', 'name', 'Espresso', physical: 2000),
      );
      await appendAndApply(
        store,
        projector,
        _deactivated('000203', physical: 3000),
      );

      final product = (await db.query('products_projection')).single;
      expect(product['name'], 'Espresso');
      expect(product['barcode'], '123');
      expect(product['active'], 0);
    });
  });

  test('enforces active barcode uniqueness transactionally', () async {
    await withProjectionDb((db, store, projector) async {
      await appendAndApply(store, projector, _productCreated('000211'));
      final conflicting = _productCreated('000212', productId: 'product-2');
      await store.append(conflicting);

      expect(
        () => projector.apply(conflicting),
        throwsA(isA<DatabaseException>()),
      );
      final rows = await db.query('products_projection');
      expect(rows.map((row) => row['product_id']), ['product-1']);
    });
  });

  test('field-level product conflicts converge regardless of order', () async {
    Future<String> applyInOrder(List<EventEnvelope> events) {
      return withProjectionDb((db, store, projector) async {
        await appendAndApply(store, projector, _productCreated('000221'));
        for (final event in events) {
          await appendAndApply(store, projector, event);
        }
        final row = (await db.query('products_projection')).single;
        return row['name'] as String;
      });
    }

    final older = _fieldSet('000222', 'name', 'Older', physical: 2000);
    final newer = _fieldSet('000223', 'name', 'Newer', physical: 3000);

    expect(await applyInOrder([newer, older]), 'Newer');
    expect(await applyInOrder([older, newer]), 'Newer');
  });

  test('inventory converges for out-of-order purchase and sale', () async {
    Future<double> applyInOrder(List<EventEnvelope> events) {
      return withProjectionDb((db, store, projector) async {
        for (final event in events) {
          await appendAndApply(store, projector, event);
        }
        final row = (await db.query('inventory_projection')).single;
        return (row['quantity'] as num).toDouble();
      });
    }

    final purchase = _purchase('000231', quantity: 10);
    final sale = _sale('000232', quantity: 4);

    expect(await applyInOrder([sale, purchase]), 6);
    expect(await applyInOrder([purchase, sale]), 6);
  });

  test(
    'inventory totals include purchase, sale, void, and adjustment',
    () async {
      await withProjectionDb((db, store, projector) async {
        for (final event in [
          _purchase('000241', quantity: 10, totalMinor: 5000),
          _sale('000242', quantity: 3, totalMinor: 2400),
          _saleVoided('000243', quantity: 3),
          _adjustment('000244', quantityDelta: -2),
          _purchaseCorrected('000245', quantityDelta: 1),
        ]) {
          await appendAndApply(store, projector, event);
        }

        final inventory = (await db.query('inventory_projection')).single;
        final sale = (await db.query('sales_projection')).single;
        final purchase = (await db.query('purchase_projection')).single;

        expect(inventory['quantity'], 9);
        expect(sale['voided'], 1);
        expect(purchase['total_minor'], 5000);
        expect(purchase['corrected'], 1);
      });
    },
  );

  test('projector duplicate application does not duplicate totals', () async {
    await withProjectionDb((db, store, projector) async {
      final purchase = _purchase('000251', quantity: 5);
      await store.append(purchase);

      final first = await projector.apply(purchase);
      final second = await projector.apply(purchase);

      final inventory = (await db.query('inventory_projection')).single;
      expect(first.status, ProjectionApplyStatus.applied);
      expect(second.status, ProjectionApplyStatus.duplicate);
      expect(inventory['quantity'], 5);
    });
  });
}

EventEnvelope _productCreated(String suffix, {String productId = 'product-1'}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.productCreated,
    entityId: productId,
    payload: const {
      'name': 'Coffee',
      'barcode': '123',
      'sku': 'COF',
      'unit': 'each',
      'sale_price_minor': 1000,
      'purchase_cost_minor': 600,
      'active': true,
    },
  );
}

EventEnvelope _fieldSet(
  String suffix,
  String field,
  Object? value, {
  required int physical,
}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.productFieldSet,
    payload: {'field': field, 'value': value},
    physicalTimeMillis: physical,
  );
}

EventEnvelope _deactivated(String suffix, {required int physical}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.productDeactivated,
    payload: const {'reason': 'manual'},
    physicalTimeMillis: physical,
  );
}

EventEnvelope _purchase(
  String suffix, {
  required double quantity,
  int totalMinor = 0,
}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.inventoryPurchaseRecorded,
    entityId: 'purchase-$suffix',
    payload: {
      'total_minor': totalMinor,
      'line_items': [
        {
          'product_id': 'product-1',
          'quantity': quantity,
          'unit_cost_minor': 500,
        },
      ],
    },
  );
}

EventEnvelope _sale(
  String suffix, {
  required double quantity,
  int totalMinor = 0,
}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.inventorySaleRecorded,
    entityId: 'sale-1',
    payload: {
      'total_minor': totalMinor,
      'line_items': [
        {
          'product_id': 'product-1',
          'quantity': quantity,
          'unit_price_minor': 800,
        },
      ],
    },
  );
}

EventEnvelope _saleVoided(String suffix, {required double quantity}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.saleVoided,
    entityId: 'sale-1',
    payload: {
      'sale_id': 'sale-1',
      'line_items': [
        {'product_id': 'product-1', 'quantity': quantity},
      ],
    },
  );
}

EventEnvelope _adjustment(String suffix, {required double quantityDelta}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.inventoryAdjustmentRecorded,
    entityId: 'adjustment-$suffix',
    payload: {
      'line_items': [
        {'product_id': 'product-1', 'quantity_delta': quantityDelta},
      ],
    },
  );
}

EventEnvelope _purchaseCorrected(
  String suffix, {
  required double quantityDelta,
}) {
  return makeTestEvent(
    eventId: _eventId(suffix),
    type: EventTypes.purchaseCorrected,
    entityId: 'purchase-000241',
    payload: {
      'purchase_id': 'purchase-000241',
      'line_items': [
        {'product_id': 'product-1', 'quantity_delta': quantityDelta},
      ],
    },
  );
}

String _eventId(String suffix) {
  return '018f2f12-7b60-7a15-8c7d-000000$suffix';
}
