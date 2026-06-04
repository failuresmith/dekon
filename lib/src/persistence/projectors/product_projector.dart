import 'package:sqflite/sqflite.dart';

import '../../domain/events/events.dart';
import 'projection_result.dart';

class ProductProjector {
  ProductProjector(this._txn);

  static const _fields = {
    'name',
    'barcode',
    'sku',
    'unit',
    'sale_price_minor',
    'purchase_cost_minor',
    'active',
  };

  final Transaction _txn;

  Future<void> applyCreated(EventEnvelope event) async {
    await _ensureProduct(event);
    final payload = event.payload;
    await _applyField(event, 'name', _string(payload, 'name', fallback: ''));
    await _applyField(event, 'barcode', _nullableString(payload, 'barcode'));
    await _applyField(event, 'sku', _nullableString(payload, 'sku'));
    await _applyField(
      event,
      'unit',
      _string(payload, 'unit', fallback: 'each'),
    );
    await _applyField(
      event,
      'sale_price_minor',
      _int(payload, 'sale_price_minor'),
    );
    await _applyField(
      event,
      'purchase_cost_minor',
      _int(payload, 'purchase_cost_minor'),
    );
    await _applyField(event, 'active', _boolAsInt(payload, 'active'));
  }

  Future<void> applyFieldSet(EventEnvelope event) async {
    final field = _string(event.payload, 'field');
    if (!_fields.contains(field)) {
      throw ProjectionException('Unsupported product field: $field.');
    }
    await _ensureProduct(event);
    await _applyField(event, field, _fieldValue(field, event.payload['value']));
  }

  Future<void> applyDeactivated(EventEnvelope event) async {
    await _ensureProduct(event);
    await _applyField(event, 'active', 0);
  }

  Future<void> _ensureProduct(EventEnvelope event) async {
    final now = event.createdAt.toIso8601String();
    await _txn.insert('products_projection', {
      'product_id': event.entityId,
      'created_at': now,
      'updated_at': now,
      'updated_hlc': event.hlc.toString(),
      'updated_device_id': event.deviceId,
      'updated_event_id': event.eventId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _applyField(
    EventEnvelope event,
    String field,
    Object? value,
  ) async {
    if (!await _incomingWins(event, field)) return;
    await _txn.update(
      'products_projection',
      {
        field: value,
        'updated_at': event.createdAt.toIso8601String(),
        'updated_hlc': event.hlc.toString(),
        'updated_device_id': event.deviceId,
        'updated_event_id': event.eventId,
      },
      where: 'product_id = ?',
      whereArgs: [event.entityId],
    );
    await _txn.insert('product_field_versions', {
      'product_id': event.entityId,
      'field_name': field,
      'hlc': event.hlc.toString(),
      'device_id': event.deviceId,
      'event_id': event.eventId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> _incomingWins(EventEnvelope event, String field) async {
    final rows = await _txn.query(
      'product_field_versions',
      where: 'product_id = ? AND field_name = ?',
      whereArgs: [event.entityId, field],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final existing = rows.single;
    final existingHlc = HybridLogicalTimestamp.parse(existing['hlc'] as String);
    final hlcOrder = event.hlc.compareTo(existingHlc);
    if (hlcOrder != 0) return hlcOrder > 0;
    final deviceOrder = event.deviceId.compareTo(
      existing['device_id'] as String,
    );
    if (deviceOrder != 0) return deviceOrder > 0;
    return event.eventId.compareTo(existing['event_id'] as String) > 0;
  }

  Object? _fieldValue(String field, Object? value) {
    return switch (field) {
      'name' => _requiredString(value, field),
      'barcode' || 'sku' => _nullableFieldString(value, field),
      'unit' => _requiredString(value, field),
      'sale_price_minor' || 'purchase_cost_minor' => _requiredInt(value, field),
      'active' => _requiredBoolAsInt(value, field),
      _ => throw ProjectionException('Unsupported product field: $field.'),
    };
  }

  static String _string(
    Map<String, Object?> payload,
    String key, {
    String? fallback,
  }) {
    final value = payload[key];
    if (value == null && fallback != null) return fallback;
    return _requiredString(value, key);
  }

  static String _requiredString(Object? value, String key) {
    if (value is String) return value;
    throw ProjectionException('$key must be a string.');
  }

  static String? _nullableString(Map<String, Object?> payload, String key) {
    return _nullableFieldString(payload[key], key);
  }

  static String? _nullableFieldString(Object? value, String key) {
    if (value == null || value is String) return value as String?;
    throw ProjectionException('$key must be a string or null.');
  }

  static int _int(Map<String, Object?> payload, String key) {
    return _requiredInt(payload[key] ?? 0, key);
  }

  static int _requiredInt(Object? value, String key) {
    if (value is int && value >= 0) return value;
    throw ProjectionException('$key must be a non-negative integer.');
  }

  static int _boolAsInt(Map<String, Object?> payload, String key) {
    return _requiredBoolAsInt(payload[key] ?? true, key);
  }

  static int _requiredBoolAsInt(Object? value, String key) {
    if (value is bool) return value ? 1 : 0;
    throw ProjectionException('$key must be a boolean.');
  }
}
