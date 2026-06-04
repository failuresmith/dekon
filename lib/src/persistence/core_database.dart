import 'package:sqflite/sqflite.dart';

import 'core_migrations.dart';

class CoreDatabase {
  static const schemaVersion = CoreMigrations.currentVersion;

  static Future<Database> open({
    required String path,
    DatabaseFactory? factory,
  }) {
    final selectedFactory = factory ?? databaseFactory;
    return selectedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => CoreMigrations.apply(db, 0, version),
        onUpgrade: CoreMigrations.apply,
        onDowngrade: _failOnDowngrade,
      ),
    );
  }

  static Future<void> createSchema(DatabaseExecutor db) {
    return CoreMigrations.apply(db, 0, schemaVersion);
  }

  static Future<void> _failOnDowngrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw StateError(
      'Refusing to downgrade database from $oldVersion to $newVersion.',
    );
  }
}
