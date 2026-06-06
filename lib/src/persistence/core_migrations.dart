import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/events/event_types.dart';

typedef MigrationBody = Future<void> Function(DatabaseExecutor db);

class CoreMigration {
  const CoreMigration({
    required this.version,
    required this.name,
    required this.apply,
  });

  final int version;
  final String name;
  final MigrationBody apply;
}

abstract final class CoreMigrations {
  static const currentVersion = 7;

  static final List<CoreMigration> migrations = [
    CoreMigration(
      version: 1,
      name: 'initial_event_log',
      apply: _initialEventLog,
    ),
    CoreMigration(
      version: 2,
      name: 'sync_and_projection_tables',
      apply: _syncAndProjectionTables,
    ),
    CoreMigration(
      version: 3,
      name: 'lan_sync_peer_secret',
      apply: _lanSyncPeerSecret,
    ),
    CoreMigration(version: 4, name: 'app_settings', apply: _appSettings),
    CoreMigration(
      version: 5,
      name: 'inventory_lot_costing',
      apply: _inventoryLotCosting,
    ),
    CoreMigration(
      version: 6,
      name: 'cashier_sale_command_outbox',
      apply: _cashierSaleCommandOutbox,
    ),
    CoreMigration(
      version: 7,
      name: 'cashier_applied_projection_ack',
      apply: _cashierAppliedProjectionAck,
    ),
  ];

  static Future<void> apply(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    await _ensureMigrationTable(db);
    await _markHistoricalMigrations(db, oldVersion);
    for (final migration in migrations) {
      if (migration.version > oldVersion && migration.version <= newVersion) {
        await migration.apply(db);
        await db.insert('schema_migrations', {
          'version': migration.version,
          'name': migration.name,
          'applied_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _ensureMigrationTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        applied_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _markHistoricalMigrations(
    DatabaseExecutor db,
    int oldVersion,
  ) async {
    final appliedAt = DateTime.now().toUtc().toIso8601String();
    for (final migration in migrations) {
      if (migration.version <= oldVersion) {
        await db.insert('schema_migrations', {
          'version': migration.version,
          'name': migration.name,
          'applied_at': appliedAt,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _initialEventLog(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS local_device_identity (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        device_id TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        event_id TEXT PRIMARY KEY,
        device_id TEXT NOT NULL,
        hlc TEXT NOT NULL,
        type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        schema_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        created_at TEXT NOT NULL,
        received_at TEXT NOT NULL,
        supported INTEGER NOT NULL CHECK (supported IN (0, 1))
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS events_hlc_idx ON events (hlc, event_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unsupported_events (
        event_id TEXT PRIMARY KEY REFERENCES events(event_id),
        reason TEXT NOT NULL,
        stored_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _syncAndProjectionTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        display_name TEXT,
        trust_status TEXT NOT NULL CHECK (
          trust_status IN ('local', 'trusted', 'revoked')
        ),
        shared_secret_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_seen_at TEXT
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO devices (
        device_id, display_name, trust_status, created_at, updated_at
      )
      SELECT device_id, 'This device', 'local', created_at, created_at
      FROM local_device_identity
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_peers (
        peer_device_id TEXT PRIMARY KEY REFERENCES devices(device_id),
        base_url TEXT,
        last_pulled_hlc TEXT,
        last_pushed_hlc TEXT,
        last_successful_sync_at TEXT,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await _createProductTables(db);
    await _createInventoryAndReportTables(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projection_applied_events (
        event_id TEXT PRIMARY KEY REFERENCES events(event_id),
        applied_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createProductTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products_projection (
        product_id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        barcode TEXT,
        sku TEXT,
        unit TEXT NOT NULL DEFAULT 'each',
        sale_price_minor INTEGER NOT NULL DEFAULT 0,
        purchase_cost_minor INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        updated_hlc TEXT NOT NULL,
        updated_device_id TEXT NOT NULL,
        updated_event_id TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS active_product_barcode_idx
      ON products_projection (barcode)
      WHERE active = 1 AND barcode IS NOT NULL AND barcode <> ''
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_field_versions (
        product_id TEXT NOT NULL REFERENCES products_projection(product_id),
        field_name TEXT NOT NULL,
        hlc TEXT NOT NULL,
        device_id TEXT NOT NULL,
        event_id TEXT NOT NULL,
        PRIMARY KEY (product_id, field_name)
      )
    ''');
  }

  static Future<void> _createInventoryAndReportTables(
    DatabaseExecutor db,
  ) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_projection (
        product_id TEXT PRIMARY KEY,
        quantity REAL NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        updated_hlc TEXT NOT NULL,
        updated_device_id TEXT NOT NULL,
        updated_event_id TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_projection (
        sale_id TEXT PRIMARY KEY,
        occurred_at TEXT NOT NULL,
        total_minor INTEGER NOT NULL DEFAULT 0,
        voided INTEGER NOT NULL DEFAULT 0 CHECK (voided IN (0, 1)),
        updated_at TEXT NOT NULL,
        updated_hlc TEXT NOT NULL,
        updated_device_id TEXT NOT NULL,
        updated_event_id TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_projection (
        purchase_id TEXT PRIMARY KEY,
        occurred_at TEXT NOT NULL,
        total_minor INTEGER NOT NULL DEFAULT 0,
        corrected INTEGER NOT NULL DEFAULT 0 CHECK (corrected IN (0, 1)),
        updated_at TEXT NOT NULL,
        updated_hlc TEXT NOT NULL,
        updated_device_id TEXT NOT NULL,
        updated_event_id TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createInventoryLotTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_lots_projection (
        lot_id TEXT PRIMARY KEY,
        source_event_id TEXT NOT NULL,
        source_line_index INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        product_id TEXT NOT NULL,
        received_at TEXT NOT NULL,
        initial_quantity REAL NOT NULL,
        remaining_quantity REAL NOT NULL,
        unit_cost_minor INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        updated_hlc TEXT NOT NULL,
        updated_device_id TEXT NOT NULL,
        updated_event_id TEXT NOT NULL,
        UNIQUE (source_event_id, source_line_index, source_type)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS inventory_lots_fifo_idx
      ON inventory_lots_projection (
        product_id, received_at, updated_hlc, lot_id
      )
    ''');
  }

  static Future<void> _lanSyncPeerSecret(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE sync_peers ADD COLUMN shared_secret TEXT');
  }

  static Future<void> _appSettings(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _inventoryLotCosting(DatabaseExecutor db) async {
    await _createInventoryLotTables(db);
    await _backfillInventoryLots(db);
  }

  static Future<void> _cashierSaleCommandOutbox(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cashier_sale_command_outbox (
        command_id TEXT PRIMARY KEY,
        status TEXT NOT NULL CHECK (
          status IN ('queued', 'syncing', 'accepted', 'conflict', 'voided')
        ),
        command_json TEXT NOT NULL,
        local_total_minor INTEGER NOT NULL DEFAULT 0,
        snapshot_projection_version INTEGER NOT NULL DEFAULT 0,
        error_code TEXT,
        error_product_ids_json TEXT,
        accepted_event_id TEXT,
        resolution_note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_attempted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS cashier_sale_outbox_status_idx
      ON cashier_sale_command_outbox (status, created_at, command_id)
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cashier_sale_command_outbox_lines (
        command_id TEXT NOT NULL
          REFERENCES cashier_sale_command_outbox(command_id),
        line_index INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price_minor INTEGER NOT NULL DEFAULT 0,
        line_total_minor INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (command_id, line_index)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS cashier_sale_outbox_lines_product_idx
      ON cashier_sale_command_outbox_lines (product_id)
    ''');
  }

  static Future<void> _cashierAppliedProjectionAck(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE sync_peers ADD COLUMN '
      'last_applied_cashier_projection_version INTEGER',
    );
  }

  static Future<void> _backfillInventoryLots(DatabaseExecutor db) async {
    final rows = await db.query(
      'events',
      columns: [
        'event_id',
        'device_id',
        'hlc',
        'type',
        'entity_id',
        'payload_json',
        'created_at',
      ],
      where: 'supported = 1 AND type IN (?, ?, ?, ?, ?)',
      whereArgs: const [
        EventTypes.inventoryPurchaseRecorded,
        EventTypes.inventorySaleRecorded,
        EventTypes.inventoryAdjustmentRecorded,
        EventTypes.saleVoided,
        EventTypes.purchaseCorrected,
      ],
      orderBy: 'hlc ASC, event_id ASC',
    );
    for (final row in rows) {
      final type = row['type'] as String;
      final payload = _decodePayload(row['payload_json'] as String);
      switch (type) {
        case EventTypes.inventoryPurchaseRecorded:
          await _backfillPurchaseLots(db, row, payload);
          break;
        case EventTypes.inventorySaleRecorded:
          await _backfillSaleLotConsumption(db, payload);
          break;
        case EventTypes.inventoryAdjustmentRecorded:
          await _backfillAdjustmentLots(db, row, payload);
          break;
        case EventTypes.saleVoided:
          await _backfillSaleVoidLots(db, row, payload);
          break;
        case EventTypes.purchaseCorrected:
          await _backfillPurchaseCorrectionLots(db, row, payload);
          break;
      }
    }
  }

  static Future<void> _backfillPurchaseLots(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Map<String, Object?> payload,
  ) async {
    final lines = _lineItems(payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      await _insertLot(
        db,
        row,
        line,
        lineIndex: index,
        sourceType: EventTypes.inventoryPurchaseRecorded,
        quantity: _positive(line, 'quantity'),
        unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
        receivedAt: _string(
          payload,
          'occurred_at',
          fallback: row['created_at'],
        ),
      );
    }
  }

  static Future<void> _backfillAdjustmentLots(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Map<String, Object?> payload,
  ) async {
    final lines = _lineItems(payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final delta = _number(line, 'quantity_delta');
      if (delta > 0) {
        await _insertLot(
          db,
          row,
          line,
          lineIndex: index,
          sourceType: EventTypes.inventoryAdjustmentRecorded,
          quantity: delta,
          unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
          receivedAt: _string(
            payload,
            'occurred_at',
            fallback: row['created_at'],
          ),
        );
      } else if (delta < 0) {
        await _consumeFifoLots(db, _productId(line), -delta);
      }
    }
  }

  static Future<void> _backfillPurchaseCorrectionLots(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Map<String, Object?> payload,
  ) async {
    final lines = _lineItems(payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final delta = _number(line, 'quantity_delta');
      if (delta > 0) {
        await _insertLot(
          db,
          row,
          line,
          lineIndex: index,
          sourceType: EventTypes.purchaseCorrected,
          quantity: delta,
          unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
          receivedAt: _string(
            payload,
            'occurred_at',
            fallback: row['created_at'],
          ),
        );
      } else if (delta < 0) {
        await _consumeFifoLots(db, _productId(line), -delta);
      }
    }
  }

  static Future<void> _backfillSaleLotConsumption(
    DatabaseExecutor db,
    Map<String, Object?> payload,
  ) async {
    for (final line in _lineItems(payload)) {
      if (await _consumeAllocatedLots(db, line)) continue;
      await _consumeFifoLots(db, _productId(line), _positive(line, 'quantity'));
    }
  }

  static Future<void> _backfillSaleVoidLots(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Map<String, Object?> payload,
  ) async {
    final lines = _lineItems(payload);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (await _restoreAllocatedLots(db, line)) continue;
      await _insertLot(
        db,
        row,
        line,
        lineIndex: index,
        sourceType: EventTypes.saleVoided,
        quantity: _positive(line, 'quantity'),
        unitCostMinor: _optionalInt(line, 'unit_cost_minor') ?? 0,
        receivedAt: _string(
          payload,
          'occurred_at',
          fallback: row['created_at'],
        ),
      );
    }
  }

  static Future<void> _insertLot(
    DatabaseExecutor db,
    Map<String, Object?> row,
    Map<String, Object?> line, {
    required int lineIndex,
    required String sourceType,
    required double quantity,
    required int unitCostMinor,
    required String receivedAt,
  }) async {
    final now = row['created_at'] as String;
    await db.insert('inventory_lots_projection', {
      'lot_id': '${row['entity_id']}:$sourceType:$lineIndex',
      'source_event_id': row['entity_id'],
      'source_line_index': lineIndex,
      'source_type': sourceType,
      'product_id': _productId(line),
      'received_at': receivedAt,
      'initial_quantity': quantity,
      'remaining_quantity': quantity,
      'unit_cost_minor': unitCostMinor,
      'updated_at': now,
      'updated_hlc': row['hlc'],
      'updated_device_id': row['device_id'],
      'updated_event_id': row['event_id'],
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<bool> _consumeAllocatedLots(
    DatabaseExecutor db,
    Map<String, Object?> line,
  ) async {
    final allocations = line['cost_allocations'];
    if (allocations is! List) return false;
    for (final raw in allocations) {
      if (raw is! Map) continue;
      final allocation = Map<String, Object?>.from(raw);
      final lotId = _string(allocation, 'lot_id');
      final quantity = _positive(allocation, 'quantity');
      await _consumeLotById(db, lotId, quantity);
    }
    return true;
  }

  static Future<bool> _restoreAllocatedLots(
    DatabaseExecutor db,
    Map<String, Object?> line,
  ) async {
    final allocations = line['cost_allocations'];
    if (allocations is! List) return false;
    for (final raw in allocations) {
      if (raw is! Map) continue;
      final allocation = Map<String, Object?>.from(raw);
      final lotId = _string(allocation, 'lot_id');
      final quantity = _positive(allocation, 'quantity');
      final rows = await db.query(
        'inventory_lots_projection',
        columns: ['remaining_quantity'],
        where: 'lot_id = ?',
        whereArgs: [lotId],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final current = (rows.single['remaining_quantity'] as num).toDouble();
      await db.update(
        'inventory_lots_projection',
        {'remaining_quantity': current + quantity},
        where: 'lot_id = ?',
        whereArgs: [lotId],
      );
    }
    return true;
  }

  static Future<void> _consumeFifoLots(
    DatabaseExecutor db,
    String productId,
    double quantity,
  ) async {
    var remaining = quantity;
    final rows = await db.query(
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
      await db.update(
        'inventory_lots_projection',
        {'remaining_quantity': current - consumed},
        where: 'lot_id = ?',
        whereArgs: [row['lot_id']],
      );
      remaining -= consumed;
    }
  }

  static Future<void> _consumeLotById(
    DatabaseExecutor db,
    String lotId,
    double quantity,
  ) async {
    final rows = await db.query(
      'inventory_lots_projection',
      columns: ['remaining_quantity'],
      where: 'lot_id = ?',
      whereArgs: [lotId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = (rows.single['remaining_quantity'] as num).toDouble();
    await db.update(
      'inventory_lots_projection',
      {'remaining_quantity': current - quantity},
      where: 'lot_id = ?',
      whereArgs: [lotId],
    );
  }

  static Map<String, Object?> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return const {};
  }

  static List<Map<String, Object?>> _lineItems(Map<String, Object?> payload) {
    final value = payload['line_items'];
    if (value is! List) return const [];
    return [
      for (final raw in value)
        if (raw is Map) Map<String, Object?>.from(raw),
    ];
  }

  static String _productId(Map<String, Object?> line) =>
      _string(line, 'product_id');

  static String _string(
    Map<String, Object?> payload,
    String key, {
    Object? fallback,
  }) {
    final value = payload[key] ?? fallback;
    if (value is String && value.isNotEmpty) return value;
    return '';
  }

  static int? _optionalInt(Map<String, Object?> payload, String key) {
    final value = payload[key];
    return value is int ? value : null;
  }

  static double _positive(Map<String, Object?> payload, String key) {
    final value = _number(payload, key);
    return value > 0 ? value : 0;
  }

  static double _number(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is num && value.isFinite) return value.toDouble();
    return 0;
  }
}
