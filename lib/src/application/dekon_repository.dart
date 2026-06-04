import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/events/events.dart';
import '../persistence/persistence.dart';
import '../platform/app_database_path.dart';
import '../sync/sync.dart';
import 'models.dart';

class DekonRepository {
  DekonRepository._(
    this._db,
    this._eventStore,
    this._projector, {
    required String deviceId,
    DateTime Function()? now,
    Uuid? uuid,
  }) : _deviceId = deviceId,
       _clock = HybridLogicalClock(nodeId: deviceId),
       _now = now ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final Database _db;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final String _deviceId;
  final HybridLogicalClock _clock;
  final DateTime Function() _now;
  final Uuid _uuid;

  static Future<DekonRepository> open({Database? database}) async {
    final db = database ?? await AppDatabasePath.openCoreDatabase();
    final deviceId = await DeviceIdentityRepository(db).getOrCreate();
    return DekonRepository._(
      db,
      EventStore(db),
      DomainProjector(db),
      deviceId: deviceId,
    );
  }

  Future<void> close() => _db.close();

  SyncStore createSyncStore() {
    return SyncStore(database: _db, localDeviceId: _deviceId);
  }

  LanSyncServer createLanSyncServer() {
    return LanSyncServer(store: createSyncStore());
  }

  LanSyncClient createLanSyncClient() {
    return LanSyncClient(store: createSyncStore());
  }

  Future<ProductSummary> createProduct({
    required String name,
    String? barcode,
    String? sku,
    String unit = 'each',
    int salePriceMinor = 0,
    int purchaseCostMinor = 0,
  }) async {
    final productId = _uuid.v7();
    final event = _event(
      type: EventTypes.productCreated,
      entityId: productId,
      payload: {
        'name': name.trim(),
        'barcode': _blankToNull(barcode),
        'sku': _blankToNull(sku),
        'unit': unit.trim().isEmpty ? 'each' : unit.trim(),
        'sale_price_minor': salePriceMinor,
        'purchase_cost_minor': purchaseCostMinor,
        'active': true,
      },
    );
    await _commit(event);
    return (await productById(productId))!;
  }

  Future<void> updateProduct(ProductSummary product) async {
    final fields = <String, Object?>{
      'name': product.name,
      'barcode': _blankToNull(product.barcode),
      'sku': _blankToNull(product.sku),
      'unit': product.unit,
      'sale_price_minor': product.salePriceMinor,
      'purchase_cost_minor': product.purchaseCostMinor,
      'active': product.active,
    };
    for (final entry in fields.entries) {
      await _commit(
        _event(
          type: EventTypes.productFieldSet,
          entityId: product.productId,
          payload: {'field': entry.key, 'value': entry.value},
        ),
      );
    }
  }

  Future<void> deactivateProduct(String productId) async {
    await _commit(
      _event(
        type: EventTypes.productDeactivated,
        entityId: productId,
        payload: const {'reason': 'manual'},
      ),
    );
  }

  Future<ProductSummary?> productByBarcodeOrSku(String query) async {
    final value = query.trim();
    if (value.isEmpty) return null;
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1 AND (p.barcode = ? OR p.sku = ?)
      LIMIT 1
      ''',
      [value, value],
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.single);
  }

  Future<ProductSummary?> productById(String productId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.product_id = ?
      LIMIT 1
      ''',
      [productId],
    );
    if (rows.isEmpty) return null;
    return _productFromRow(rows.single);
  }

  Future<List<ProductSummary>> products() async {
    final rows = await _db.rawQuery('''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      ORDER BY p.active DESC, p.name ASC
      ''');
    return rows.map(_productFromRow).toList(growable: false);
  }

  Future<bool> saleWouldMakeNegative(List<TransactionLineDraft> lines) async {
    final stock = <String, double>{};
    for (final line in lines) {
      stock[line.product.productId] = await _stockFor(line.product.productId);
    }
    for (final line in lines) {
      final next = (stock[line.product.productId] ?? 0) - line.quantity;
      if (next < 0) return true;
      stock[line.product.productId] = next;
    }
    return false;
  }

  Future<void> recordSale(List<TransactionLineDraft> lines) async {
    if (lines.isEmpty) throw StateError('Sale must have at least one item.');
    await _commit(
      _event(
        type: EventTypes.inventorySaleRecorded,
        entityId: _uuid.v7(),
        payload: {
          'occurred_at': _now().toUtc().toIso8601String(),
          'total_minor': lines.fold<int>(
            0,
            (sum, line) => sum + line.saleTotalMinor,
          ),
          'line_items': [
            for (final line in lines)
              {
                'product_id': line.product.productId,
                'quantity': line.quantity,
                'unit_price_minor': line.unitPriceMinor,
              },
          ],
        },
      ),
    );
  }

  Future<void> recordPurchase(List<TransactionLineDraft> lines) async {
    if (lines.isEmpty) {
      throw StateError('Purchase must have at least one item.');
    }
    await _commit(
      _event(
        type: EventTypes.inventoryPurchaseRecorded,
        entityId: _uuid.v7(),
        payload: {
          'occurred_at': _now().toUtc().toIso8601String(),
          'total_minor': lines.fold<int>(
            0,
            (sum, line) => sum + line.purchaseTotalMinor,
          ),
          'line_items': [
            for (final line in lines)
              {
                'product_id': line.product.productId,
                'quantity': line.quantity,
                'unit_cost_minor': line.unitCostMinor,
              },
          ],
        },
      ),
    );
  }

  Future<ReportSummary> reportSummary() async {
    final stockRows = await _stockRows();
    return ReportSummary(
      stockRows: stockRows,
      dailySalesMinor: await _dailyTotal('sales_projection'),
      dailyPurchasesMinor: await _dailyTotal('purchase_projection'),
      grossMarginMinor: await _grossMarginEstimate(),
      lowStockRows: stockRows.where((row) => row.quantity <= 0).toList(),
      unsyncedEventCount: await _eventStore.count(),
      lastSyncAt: await _lastSyncAt(),
    );
  }

  EventEnvelope _event({
    required String type,
    required String entityId,
    required Map<String, Object?> payload,
  }) {
    return EventEnvelope.local(
      eventId: _uuid.v7(),
      deviceId: _deviceId,
      hlc: _clock.send(_now()),
      type: type,
      entityId: entityId,
      payload: payload,
      createdAt: _now().toUtc(),
    );
  }

  Future<void> _commit(EventEnvelope event) async {
    final write = await _eventStore.append(event);
    if (write.status == EventWriteStatus.duplicate) return;
    await _projector.apply(event);
  }

  Future<double> _stockFor(String productId) async {
    final rows = await _db.query(
      'inventory_projection',
      columns: ['quantity'],
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.single['quantity'] as num).toDouble();
  }

  Future<List<StockReportRow>> _stockRows() async {
    final rows = await _db.rawQuery('''
      SELECT p.product_id, p.name, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1
      ORDER BY p.name ASC
      ''');
    return [
      for (final row in rows)
        StockReportRow(
          productId: row['product_id'] as String,
          name: row['name'] as String,
          quantity: (row['quantity'] as num).toDouble(),
        ),
    ];
  }

  Future<int> _dailyTotal(String table) async {
    final start = DateTime(_now().year, _now().month, _now().day).toUtc();
    final end = start.add(const Duration(days: 1));
    final rows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_minor), 0) AS total
      FROM $table
      WHERE occurred_at >= ? AND occurred_at < ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    return rows.single['total'] as int;
  }

  Future<int> _grossMarginEstimate() async {
    final start = DateTime(_now().year, _now().month, _now().day).toUtc();
    final rows = await _db.query(
      'events',
      columns: ['payload_json'],
      where: 'type = ? AND created_at >= ?',
      whereArgs: [EventTypes.inventorySaleRecorded, start.toIso8601String()],
    );
    var margin = 0;
    for (final row in rows) {
      final payload = jsonDecode(row['payload_json'] as String) as Map;
      final lines = payload['line_items'] as List;
      for (final line in lines.cast<Map>()) {
        final product = await productById(line['product_id'] as String);
        final quantity = (line['quantity'] as num).toDouble();
        final price = line['unit_price_minor'] as int;
        final cost = product?.purchaseCostMinor ?? 0;
        margin += (quantity * (price - cost)).round();
      }
    }
    return margin;
  }

  Future<DateTime?> _lastSyncAt() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(last_successful_sync_at) AS last_sync FROM sync_peers',
    );
    final value = rows.single['last_sync'] as String?;
    if (value == null) return null;
    return DateTime.parse(value);
  }

  ProductSummary _productFromRow(Map<String, Object?> row) {
    return ProductSummary(
      productId: row['product_id'] as String,
      name: row['name'] as String,
      barcode: row['barcode'] as String?,
      sku: row['sku'] as String?,
      unit: row['unit'] as String,
      salePriceMinor: row['sale_price_minor'] as int,
      purchaseCostMinor: row['purchase_cost_minor'] as int,
      active: row['active'] == 1,
      quantity: (row['quantity'] as num).toDouble(),
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
