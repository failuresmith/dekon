import 'package:sqflite/sqflite.dart';

import '../../domain/events/events.dart';
import 'projection_result.dart';

class InventoryProjector {
  InventoryProjector(this._txn);

  final Transaction _txn;

  Future<void> applyPurchase(EventEnvelope event) async {
    final total = _int(event.payload, 'total_minor', fallback: 0);
    await _upsertPurchase(event, totalMinor: total, corrected: 0);
    final lines = _lineItems(event.payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      await _addInventory(event, _productId(line), _positive(line, 'quantity'));
      await _addLot(
        event,
        line,
        lineIndex: index,
        sourceType: EventTypes.inventoryPurchaseRecorded,
        quantity: _positive(line, 'quantity'),
        unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
      );
    }
  }

  Future<void> applySale(EventEnvelope event) async {
    final total = _int(event.payload, 'total_minor', fallback: 0);
    await _upsertSale(event, totalMinor: total, voided: null);
    for (final line in _lineItems(event.payload)) {
      await _consumeSaleLots(line);
      await _addInventory(
        event,
        _productId(line),
        -_positive(line, 'quantity'),
      );
    }
  }

  Future<void> applyAdjustment(EventEnvelope event) async {
    final lines = _lineItems(event.payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final delta = _number(line, 'quantity_delta');
      if (delta > 0) {
        await _addLot(
          event,
          line,
          lineIndex: index,
          sourceType: EventTypes.inventoryAdjustmentRecorded,
          quantity: delta,
          unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
        );
      } else if (delta < 0) {
        await _consumeFifoLots(_productId(line), -delta, strict: false);
      }
      await _addInventory(event, _productId(line), delta);
    }
  }

  Future<void> applySaleVoided(EventEnvelope event) async {
    await _markSaleVoided(event);
    final lines = _lineItems(event.payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!await _restoreAllocatedLots(line)) {
        await _addLot(
          event,
          line,
          lineIndex: index,
          sourceType: EventTypes.saleVoided,
          quantity: _positive(line, 'quantity'),
          unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
        );
      }
      await _addInventory(event, _productId(line), _positive(line, 'quantity'));
    }
  }

  Future<void> applyPurchaseCorrected(EventEnvelope event) async {
    await _markPurchaseCorrected(event);
    final lines = _lineItems(event.payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final delta = _number(line, 'quantity_delta');
      if (delta > 0) {
        await _addLot(
          event,
          line,
          lineIndex: index,
          sourceType: EventTypes.purchaseCorrected,
          quantity: delta,
          unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
        );
      } else if (delta < 0) {
        await _consumeFifoLots(_productId(line), -delta, strict: false);
      }
      await _addInventory(event, _productId(line), delta);
    }
  }

  Future<void> _addLot(
    EventEnvelope event,
    Map<String, Object?> line, {
    required int lineIndex,
    required String sourceType,
    required double quantity,
    required int unitCostMinor,
  }) async {
    await _txn.insert('inventory_lots_projection', {
      'lot_id': '${event.entityId}:$sourceType:$lineIndex',
      'source_event_id': event.entityId,
      'source_line_index': lineIndex,
      'source_type': sourceType,
      'product_id': _productId(line),
      'received_at': _occurredAt(event),
      'initial_quantity': quantity,
      'remaining_quantity': quantity,
      'unit_cost_minor': unitCostMinor,
      'updated_at': event.createdAt.toIso8601String(),
      'updated_hlc': event.hlc.toString(),
      'updated_device_id': event.deviceId,
      'updated_event_id': event.eventId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _consumeSaleLots(Map<String, Object?> line) async {
    if (await _consumeAllocatedLots(line)) return;
    await _consumeFifoLots(_productId(line), _positive(line, 'quantity'));
  }

  Future<bool> _consumeAllocatedLots(Map<String, Object?> line) async {
    final allocations = line['cost_allocations'];
    if (allocations is! List) return false;
    for (final raw in allocations) {
      if (raw is! Map) {
        throw ProjectionException('cost_allocations entries must be objects.');
      }
      final allocation = Map<String, Object?>.from(raw);
      await _consumeLotById(
        _string(allocation, 'lot_id'),
        _positive(allocation, 'quantity'),
      );
    }
    return true;
  }

  Future<bool> _restoreAllocatedLots(Map<String, Object?> line) async {
    final allocations = line['cost_allocations'];
    if (allocations is! List) return false;
    for (final raw in allocations) {
      if (raw is! Map) {
        throw ProjectionException('cost_allocations entries must be objects.');
      }
      final allocation = Map<String, Object?>.from(raw);
      final lotId = _string(allocation, 'lot_id');
      final quantity = _positive(allocation, 'quantity');
      final rows = await _txn.query(
        'inventory_lots_projection',
        columns: ['remaining_quantity'],
        where: 'lot_id = ?',
        whereArgs: [lotId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw ProjectionException('Sale void references an unknown lot.');
      }
      final current = (rows.single['remaining_quantity'] as num).toDouble();
      await _txn.update(
        'inventory_lots_projection',
        {'remaining_quantity': current + quantity},
        where: 'lot_id = ?',
        whereArgs: [lotId],
      );
    }
    return true;
  }

  Future<void> _consumeFifoLots(
    String productId,
    double quantity, {
    bool strict = false,
  }) async {
    var remaining = quantity;
    final rows = await _txn.query(
      'inventory_lots_projection',
      columns: ['lot_id', 'remaining_quantity'],
      where: 'product_id = ? AND remaining_quantity > 0',
      whereArgs: [productId],
      orderBy: 'received_at ASC, updated_hlc ASC, lot_id ASC',
    );
    for (final row in rows) {
      if (remaining <= 0) break;
      final current = (row['remaining_quantity'] as num).toDouble();
      final consumed = current < remaining ? current : remaining;
      await _txn.update(
        'inventory_lots_projection',
        {'remaining_quantity': current - consumed},
        where: 'lot_id = ?',
        whereArgs: [row['lot_id']],
      );
      remaining -= consumed;
    }
    if (strict && remaining > 0.000000001) {
      throw ProjectionException('Sale exceeds available inventory lots.');
    }
  }

  Future<void> _consumeLotById(String lotId, double quantity) async {
    final rows = await _txn.query(
      'inventory_lots_projection',
      columns: ['remaining_quantity'],
      where: 'lot_id = ?',
      whereArgs: [lotId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ProjectionException('Sale references an unknown inventory lot.');
    }
    final current = (rows.single['remaining_quantity'] as num).toDouble();
    if (current + 0.000000001 < quantity) {
      throw ProjectionException(
        'Sale exceeds available inventory lot quantity.',
      );
    }
    await _txn.update(
      'inventory_lots_projection',
      {'remaining_quantity': current - quantity},
      where: 'lot_id = ?',
      whereArgs: [lotId],
    );
  }

  Future<void> _addInventory(
    EventEnvelope event,
    String productId,
    double delta,
  ) async {
    final now = event.createdAt.toIso8601String();
    final rows = await _txn.query(
      'inventory_projection',
      columns: ['quantity'],
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _txn.insert('inventory_projection', {
        'product_id': productId,
        'quantity': delta,
        'updated_at': now,
        'updated_hlc': event.hlc.toString(),
        'updated_device_id': event.deviceId,
        'updated_event_id': event.eventId,
      });
      return;
    }
    final current = rows.single['quantity'] as num;
    await _txn.update(
      'inventory_projection',
      {
        'quantity': current.toDouble() + delta,
        'updated_at': now,
        'updated_hlc': event.hlc.toString(),
        'updated_device_id': event.deviceId,
        'updated_event_id': event.eventId,
      },
      where: 'product_id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> _upsertSale(
    EventEnvelope event, {
    required int totalMinor,
    required int? voided,
  }) async {
    final existing = await _txn.query(
      'sales_projection',
      columns: ['voided'],
      where: 'sale_id = ?',
      whereArgs: [event.entityId],
      limit: 1,
    );
    final nextVoided =
        voided ?? (existing.isEmpty ? 0 : existing.single['voided'] as int);
    await _txn.insert(
      'sales_projection',
      _saleRow(event, event.entityId, totalMinor, nextVoided),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _markSaleVoided(EventEnvelope event) async {
    final saleId = _string(event.payload, 'sale_id', fallback: event.entityId);
    final existing = await _txn.query(
      'sales_projection',
      columns: ['total_minor', 'occurred_at'],
      where: 'sale_id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    final totalMinor =
        _optionalInt(event.payload, 'total_minor') ??
        (existing.isEmpty ? 0 : existing.single['total_minor'] as int);
    final occurredAt = existing.isEmpty
        ? _occurredAt(event)
        : existing.single['occurred_at'] as String;
    await _txn.insert(
      'sales_projection',
      _saleRow(event, saleId, totalMinor, 1, occurredAt: occurredAt),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertPurchase(
    EventEnvelope event, {
    required int totalMinor,
    required int? corrected,
  }) async {
    final existing = await _txn.query(
      'purchase_projection',
      columns: ['corrected'],
      where: 'purchase_id = ?',
      whereArgs: [event.entityId],
      limit: 1,
    );
    final nextCorrected =
        corrected ??
        (existing.isEmpty ? 0 : existing.single['corrected'] as int);
    await _txn.insert(
      'purchase_projection',
      _purchaseRow(event, event.entityId, totalMinor, nextCorrected),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _markPurchaseCorrected(EventEnvelope event) async {
    final id = _string(event.payload, 'purchase_id', fallback: event.entityId);
    final existing = await _txn.query(
      'purchase_projection',
      columns: ['total_minor', 'occurred_at'],
      where: 'purchase_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final totalMinor =
        _optionalInt(event.payload, 'total_minor') ??
        (existing.isEmpty ? 0 : existing.single['total_minor'] as int);
    final occurredAt = existing.isEmpty
        ? _occurredAt(event)
        : existing.single['occurred_at'] as String;
    await _txn.insert(
      'purchase_projection',
      _purchaseRow(event, id, totalMinor, 1, occurredAt: occurredAt),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, Object?> _saleRow(
    EventEnvelope event,
    String saleId,
    int totalMinor,
    int voided, {
    String? occurredAt,
  }) {
    return _summaryRow(event)..addAll({
      'sale_id': saleId,
      'occurred_at': occurredAt ?? _occurredAt(event),
      'total_minor': totalMinor,
      'voided': voided,
    });
  }

  Map<String, Object?> _purchaseRow(
    EventEnvelope event,
    String purchaseId,
    int totalMinor,
    int corrected, {
    String? occurredAt,
  }) {
    return _summaryRow(event)..addAll({
      'purchase_id': purchaseId,
      'occurred_at': occurredAt ?? _occurredAt(event),
      'total_minor': totalMinor,
      'corrected': corrected,
    });
  }

  Map<String, Object?> _summaryRow(EventEnvelope event) {
    return {
      'updated_at': event.createdAt.toIso8601String(),
      'updated_hlc': event.hlc.toString(),
      'updated_device_id': event.deviceId,
      'updated_event_id': event.eventId,
    };
  }

  String _occurredAt(EventEnvelope event) {
    return _string(
      event.payload,
      'occurred_at',
      fallback: event.createdAt.toIso8601String(),
    );
  }

  static List<Map<String, Object?>> _lineItems(Map<String, Object?> payload) {
    final value = payload['line_items'];
    if (value is! List) throw ProjectionException('line_items must be a list.');
    return value
        .map((line) {
          if (line is Map) return Map<String, Object?>.from(line);
          throw ProjectionException('line_items entries must be objects.');
        })
        .toList(growable: false);
  }

  static String _productId(Map<String, Object?> line) =>
      _string(line, 'product_id');

  static String _string(
    Map<String, Object?> payload,
    String key, {
    String? fallback,
  }) {
    final value = payload[key];
    if (value == null && fallback != null) return fallback;
    if (value is String && value.isNotEmpty) return value;
    throw ProjectionException('$key must be a non-empty string.');
  }

  static int _int(
    Map<String, Object?> payload,
    String key, {
    required int fallback,
  }) {
    final value = payload[key];
    if (value == null) return fallback;
    if (value is int) return value;
    throw ProjectionException('$key must be an integer.');
  }

  static int? _optionalInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is int) return value;
    throw ProjectionException('$key must be an integer.');
  }

  static double _positive(Map<String, Object?> payload, String key) {
    final value = _number(payload, key);
    if (value > 0) return value;
    throw ProjectionException('$key must be positive.');
  }

  static double _number(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is num && value.isFinite) return value.toDouble();
    throw ProjectionException('$key must be a finite number.');
  }
}
