import 'package:sqflite/sqflite.dart';

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
  static const currentVersion = 4;

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
}
