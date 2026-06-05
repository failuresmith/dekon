import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/events/events.dart';
import '../backup/backup.dart';
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

  BackupService createBackupService() {
    return BackupService(database: _db);
  }

  Future<DeviceRole> deviceRole() async {
    return (await deviceRoleSettings()).role;
  }

  Future<DeviceRoleSettings> deviceRoleSettings() async {
    final rows = await _db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?)',
      whereArgs: const [
        'device_role',
        'device_role_locked',
        'device_onboarding_completed',
      ],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
    return DeviceRoleSettings(
      role: DeviceRole.fromStorage(values['device_role']),
      locked: values['device_role_locked'] == 'true',
      onboardingCompleted: values['device_onboarding_completed'] == 'true',
    );
  }

  Future<void> setDeviceRole(DeviceRole role) async {
    final settings = await deviceRoleSettings();
    if (settings.locked && settings.role != role) {
      throw StateError('Device role is locked after pairing.');
    }
    await _setAppSetting('device_role', role.storageValue);
  }

  Future<void> completeDeviceOnboarding(DeviceRole role) async {
    final settings = await deviceRoleSettings();
    if (settings.locked && settings.role != role) {
      throw StateError('Device role is locked after pairing.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': role.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_onboarding_completed',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> lockDeviceRole(DeviceRole role) async {
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('app_settings', {
        'key': 'device_role',
        'value': role.storageValue,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_role_locked',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'key': 'device_onboarding_completed',
        'value': 'true',
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
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

  Future<void> softDeleteProduct(String productId) async {
    await _commit(
      _event(
        type: EventTypes.productDeactivated,
        entityId: productId,
        payload: const {'reason': 'soft_delete'},
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

  Future<List<ProductSummary>> productsMatchingName(String query) async {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return const [];
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, COALESCE(i.quantity, 0) AS quantity
      FROM products_projection p
      LEFT JOIN inventory_projection i ON i.product_id = p.product_id
      WHERE p.active = 1 AND LOWER(p.name) LIKE ? ESCAPE '\\'
      ORDER BY p.name ASC
      LIMIT 20
      ''',
      ['%${_escapeLike(value)}%'],
    );
    return rows.map(_productFromRow).toList(growable: false);
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

  Future<Set<String>> negativeStockProductIds(
    List<TransactionLineDraft> lines,
  ) async {
    final stock = <String, double>{};
    for (final line in lines) {
      stock[line.product.productId] = await _stockFor(line.product.productId);
    }
    final negativeProductIds = <String>{};
    for (final line in lines) {
      final next = (stock[line.product.productId] ?? 0) - line.quantity;
      if (next < 0) negativeProductIds.add(line.product.productId);
      stock[line.product.productId] = next;
    }
    return negativeProductIds;
  }

  Future<bool> saleWouldMakeNegative(List<TransactionLineDraft> lines) async {
    return (await negativeStockProductIds(lines)).isNotEmpty;
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

  Future<ReportSummary> reportSummary({ReportDateRange? range}) async {
    final reportRange = range ?? _localDayRange(_now());
    final stockRows = await _stockRows();
    return ReportSummary(
      range: reportRange,
      stockRows: stockRows,
      salesMinor: await _rangeTotal(TransactionHistoryKind.sale, reportRange),
      purchasesMinor: await _rangeTotal(
        TransactionHistoryKind.purchase,
        reportRange,
      ),
      grossMarginMinor: await _grossMarginEstimate(reportRange),
      lowStockRows: stockRows.where((row) => row.quantity <= 0).toList(),
      unsyncedEventCount: await _eventStore.count(),
      lastSyncAt: await _lastSyncAt(),
    );
  }

  Future<List<TransactionHistoryEntry>> transactionHistory(
    TransactionHistoryKind kind, {
    ReportDateRange? range,
    int? limit = 20,
  }) async {
    final source = _transactionSource(kind);
    final where = ['e.type = ?', '${source.alias}.${source.statusColumn} = 0'];
    final args = <Object?>[_transactionType(kind)];
    if (range != null) {
      where.add('${source.alias}.occurred_at >= ?');
      where.add('${source.alias}.occurred_at < ?');
      args
        ..add(range.startUtc.toIso8601String())
        ..add(range.endUtcExclusive.toIso8601String());
    }
    final sqlLimit = limit == null ? '' : 'LIMIT ${limit.clamp(1, 500)}';
    final rows = await _db.rawQuery('''
      SELECT e.entity_id, e.payload_json, e.created_at
      FROM events e
      JOIN ${source.table} ${source.alias}
        ON ${source.alias}.${source.idColumn} = e.entity_id
      WHERE ${where.join(' AND ')}
      ORDER BY ${source.alias}.occurred_at DESC, e.created_at DESC
      $sqlLimit
      ''', args);
    final entries = <TransactionHistoryEntry>[];
    for (final row in rows) {
      entries.add(await _historyFromRow(kind, row));
    }
    return entries;
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

  ReportDateRange _localDayRange(DateTime value) {
    final start = DateTime(value.year, value.month, value.day);
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: start.add(const Duration(days: 1)),
    );
  }

  Future<int> _rangeTotal(
    TransactionHistoryKind kind,
    ReportDateRange range,
  ) async {
    final source = _transactionSource(kind);
    final rows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_minor), 0) AS total
      FROM ${source.table}
      WHERE occurred_at >= ?
        AND occurred_at < ?
        AND ${source.statusColumn} = 0
      ''',
      [
        range.startUtc.toIso8601String(),
        range.endUtcExclusive.toIso8601String(),
      ],
    );
    return rows.single['total'] as int;
  }

  Future<int> _grossMarginEstimate(ReportDateRange range) async {
    final rows = await _db.rawQuery(
      '''
      SELECT e.payload_json
      FROM events e
      JOIN sales_projection s ON s.sale_id = e.entity_id
      WHERE e.type = ?
        AND s.voided = 0
        AND s.occurred_at >= ?
        AND s.occurred_at < ?
      ''',
      [
        EventTypes.inventorySaleRecorded,
        range.startUtc.toIso8601String(),
        range.endUtcExclusive.toIso8601String(),
      ],
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

  Future<TransactionHistoryEntry> _historyFromRow(
    TransactionHistoryKind kind,
    Map<String, Object?> row,
  ) async {
    final payload = _decodePayload(row['payload_json'] as String);
    final createdAt = DateTime.parse(row['created_at'] as String);
    final lines = await _historyLines(kind, payload);
    final totalMinor =
        _optionalInt(payload, 'total_minor') ??
        lines.fold<int>(0, (sum, line) => sum + line.lineTotalMinor);
    return TransactionHistoryEntry(
      id: row['entity_id'] as String,
      kind: kind,
      occurredAt: _optionalDateTime(payload, 'occurred_at') ?? createdAt,
      totalMinor: totalMinor,
      lines: lines,
    );
  }

  Future<List<TransactionHistoryLine>> _historyLines(
    TransactionHistoryKind kind,
    Map<String, Object?> payload,
  ) async {
    final rawLines = payload['line_items'];
    if (rawLines is! List) return const [];
    final lines = <TransactionHistoryLine>[];
    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final line = Map<String, Object?>.from(raw);
      final productId = line['product_id'];
      if (productId is! String) continue;
      final quantity = _optionalNumber(line, 'quantity') ?? 0;
      final unitMinor = switch (kind) {
        TransactionHistoryKind.sale =>
          _optionalInt(line, 'unit_price_minor') ?? 0,
        TransactionHistoryKind.purchase =>
          _optionalInt(line, 'unit_cost_minor') ?? 0,
      };
      final product = await productById(productId);
      lines.add(
        TransactionHistoryLine(
          productName: product?.name ?? 'Unknown product',
          quantity: quantity,
          lineTotalMinor: (quantity * unitMinor).round(),
        ),
      );
    }
    return lines;
  }

  Map<String, Object?> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const {};
  }

  String _transactionType(TransactionHistoryKind kind) {
    return switch (kind) {
      TransactionHistoryKind.sale => EventTypes.inventorySaleRecorded,
      TransactionHistoryKind.purchase => EventTypes.inventoryPurchaseRecorded,
    };
  }

  _TransactionSource _transactionSource(TransactionHistoryKind kind) {
    return switch (kind) {
      TransactionHistoryKind.sale => const _TransactionSource(
        table: 'sales_projection',
        alias: 's',
        idColumn: 'sale_id',
        statusColumn: 'voided',
      ),
      TransactionHistoryKind.purchase => const _TransactionSource(
        table: 'purchase_projection',
        alias: 'p',
        idColumn: 'purchase_id',
        statusColumn: 'corrected',
      ),
    };
  }

  DateTime? _optionalDateTime(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int? _optionalInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    return value is int ? value : null;
  }

  double? _optionalNumber(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  Future<void> _setAppSetting(String key, String value) {
    return _db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

class _TransactionSource {
  const _TransactionSource({
    required this.table,
    required this.alias,
    required this.idColumn,
    required this.statusColumn,
  });

  final String table;
  final String alias;
  final String idColumn;
  final String statusColumn;
}
