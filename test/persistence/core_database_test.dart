import 'dart:io';

import 'package:dekon/src/persistence/persistence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('creates the full schema through migrations', () async {
    final db = await CoreDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    try {
      final tables = await _tableNames(db);
      expect(
        tables,
        containsAll({
          'schema_migrations',
          'local_device_identity',
          'devices',
          'events',
          'unsupported_events',
          'sync_peers',
          'products_projection',
          'product_field_versions',
          'inventory_projection',
          'sales_projection',
          'purchase_projection',
          'projection_applied_events',
          'cashier_sale_command_outbox',
          'cashier_sale_command_outbox_lines',
          'customers',
          'sale_customer_links',
        }),
      );
      expect(await db.getVersion(), CoreDatabase.schemaVersion);
    } finally {
      await db.close();
    }
  });

  test('upgrades a legacy v1 event-log database to current schema', () async {
    final tempDir = await Directory.systemTemp.createTemp('dekon_db_test_');
    final dbPath = p.join(tempDir.path, 'legacy.sqlite');
    try {
      final legacy = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => _createLegacyV1(db),
        ),
      );
      await legacy.close();

      final upgraded = await CoreDatabase.open(
        path: dbPath,
        factory: databaseFactoryFfi,
      );
      try {
        expect(await upgraded.getVersion(), CoreDatabase.schemaVersion);
        expect(await _tableNames(upgraded), contains('products_projection'));
        expect(await _tableNames(upgraded), contains('customers'));
      } finally {
        await upgraded.close();
      }
    } finally {
      await databaseFactoryFfi.deleteDatabase(dbPath);
      await tempDir.delete(recursive: true);
    }
  });
}

Future<Set<String>> _tableNames(Database db) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name'] as String).toSet();
}

Future<void> _createLegacyV1(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE local_device_identity (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      device_id TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE events (
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
  await db.execute('CREATE INDEX events_hlc_idx ON events (hlc, event_id)');
  await db.execute('''
    CREATE TABLE unsupported_events (
      event_id TEXT PRIMARY KEY REFERENCES events(event_id),
      reason TEXT NOT NULL,
      stored_at TEXT NOT NULL
    )
  ''');
}
