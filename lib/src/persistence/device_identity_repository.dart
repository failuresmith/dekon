import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityRepository {
  DeviceIdentityRepository(this._db, {Uuid? uuid, DateTime Function()? now})
    : _uuid = uuid ?? const Uuid(),
      _now = now ?? DateTime.now;

  final Database _db;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<String> getOrCreate() async {
    final rows = await _db.query(
      'local_device_identity',
      columns: ['device_id'],
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final deviceId = rows.single['device_id'] as String;
      await _ensureDeviceRow(deviceId);
      return deviceId;
    }

    return _db.transaction((txn) async {
      final createdAt = _now().toUtc().toIso8601String();
      final deviceId = _uuid.v7();
      await txn.insert('devices', {
        'device_id': deviceId,
        'display_name': 'This device',
        'trust_status': 'local',
        'created_at': createdAt,
        'updated_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('local_device_identity', {
        'id': 1,
        'device_id': deviceId,
        'created_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final createdRows = await txn.query(
        'local_device_identity',
        columns: ['device_id'],
        where: 'id = ?',
        whereArgs: [1],
        limit: 1,
      );
      final storedDeviceId = createdRows.single['device_id'] as String;
      await txn.insert('devices', {
        'device_id': storedDeviceId,
        'display_name': 'This device',
        'trust_status': 'local',
        'created_at': createdAt,
        'updated_at': createdAt,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return storedDeviceId;
    });
  }

  Future<void> _ensureDeviceRow(String deviceId) async {
    final now = _now().toUtc().toIso8601String();
    await _db.insert('devices', {
      'device_id': deviceId,
      'display_name': 'This device',
      'trust_status': 'local',
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
