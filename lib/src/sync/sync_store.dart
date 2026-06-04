import 'package:sqflite/sqflite.dart';

import '../domain/events/events.dart';
import '../persistence/persistence.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';

class SyncStore {
  SyncStore({
    required Database database,
    required this.localDeviceId,
    EventStore? eventStore,
    DomainProjector? projector,
    DateTime Function()? now,
  }) : _db = database,
       _eventStore = eventStore ?? EventStore(database),
       _projector = projector ?? DomainProjector(database),
       _now = now ?? DateTime.now;

  final Database _db;
  final String localDeviceId;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final DateTime Function() _now;

  SyncDeviceInfo deviceInfo() {
    return SyncDeviceInfo(deviceId: localDeviceId, displayName: 'Dekon phone');
  }

  Future<void> trustPeer({
    required String deviceId,
    required String displayName,
    required String sharedSecret,
    String? baseUrl,
  }) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot trust self.');
    }
    final now = _now().toUtc().toIso8601String();
    await _db.transaction((txn) async {
      await txn.insert('devices', {
        'device_id': deviceId,
        'display_name': _displayName(displayName),
        'trust_status': 'trusted',
        'shared_secret_hash': SyncSecrets.hash(sharedSecret),
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'devices',
        {
          'display_name': _displayName(displayName),
          'trust_status': 'trusted',
          'shared_secret_hash': SyncSecrets.hash(sharedSecret),
          'updated_at': now,
        },
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );
      await txn.insert('sync_peers', {
        'peer_device_id': deviceId,
        'base_url': baseUrl,
        'shared_secret': sharedSecret,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'sync_peers',
        {
          'base_url': baseUrl,
          'shared_secret': sharedSecret,
          'last_error': null,
          'updated_at': now,
        },
        where: 'peer_device_id = ?',
        whereArgs: [deviceId],
      );
    });
  }

  Future<TrustedPeer?> trustedPeer(String deviceId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT d.device_id, d.display_name, d.trust_status, p.base_url,
             p.shared_secret, p.last_pulled_hlc, p.last_pushed_hlc
      FROM devices d
      JOIN sync_peers p ON p.peer_device_id = d.device_id
      WHERE d.device_id = ? AND d.trust_status = 'trusted'
      LIMIT 1
      ''',
      [deviceId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final secret = row['shared_secret'] as String?;
    if (secret == null || secret.isEmpty) return null;
    return TrustedPeer(
      deviceId: row['device_id'] as String,
      displayName: row['display_name'] as String? ?? 'Peer',
      sharedSecret: secret,
      baseUrl: row['base_url'] as String?,
      lastPulledCursor: SyncCursor.parse(row['last_pulled_hlc'] as String?),
      lastPushedCursor: SyncCursor.parse(row['last_pushed_hlc'] as String?),
    );
  }

  Future<void> markPeerSuccess(String deviceId) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'devices',
      {'last_seen_at': now, 'updated_at': now},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    await _db.update(
      'sync_peers',
      {'last_successful_sync_at': now, 'last_error': null, 'updated_at': now},
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
  }

  Future<void> updatePullCursor(String deviceId, SyncCursor? cursor) {
    return _updateCursor(deviceId, 'last_pulled_hlc', cursor);
  }

  Future<void> updatePushCursor(String deviceId, SyncCursor? cursor) {
    return _updateCursor(deviceId, 'last_pushed_hlc', cursor);
  }

  Future<List<EventEnvelope>> fetchEventsAfter(
    SyncCursor? cursor, {
    required int limit,
  }) {
    return _eventStore.fetchEventsAfter(
      hlc: cursor?.hlc,
      eventId: cursor?.eventId.isEmpty == true ? null : cursor?.eventId,
      limit: limit,
    );
  }

  Future<PostEventsResult> importEvents(List<EventEnvelope> events) async {
    final accepted = <String>[];
    final duplicate = <String>[];
    final unsupported = <String>[];
    final rejected = <EventRejection>[];

    for (final event in events) {
      try {
        final status = await _db.transaction((txn) async {
          final write = await _eventStore.appendInTransaction(txn, event);
          if (_isProjectable(event)) {
            await _projector.applyInTransaction(txn, event);
          }
          return write.status;
        });
        switch (status) {
          case EventWriteStatus.accepted:
            accepted.add(event.eventId);
          case EventWriteStatus.duplicate:
            duplicate.add(event.eventId);
          case EventWriteStatus.unsupported:
            unsupported.add(event.eventId);
        }
      } on Object catch (error) {
        rejected.add(
          EventRejection(eventId: event.eventId, reason: _safeReason(error)),
        );
      }
    }

    return PostEventsResult(
      accepted: accepted,
      duplicate: duplicate,
      unsupported: unsupported,
      rejected: rejected,
    );
  }

  Future<SyncState> state() async {
    final unsupportedRows = await _db.rawQuery(
      'SELECT COUNT(*) AS count FROM unsupported_events',
    );
    final peerRows = await _db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM devices
      WHERE trust_status = 'trusted'
      ''');
    final lastSyncRows = await _db.rawQuery(
      'SELECT MAX(last_successful_sync_at) AS value FROM sync_peers',
    );
    final lastSync = lastSyncRows.single['value'] as String?;
    return SyncState(
      deviceId: localDeviceId,
      eventCount: await _eventStore.count(),
      unsupportedEventCount: unsupportedRows.single['count'] as int,
      trustedPeerCount: peerRows.single['count'] as int,
      lastSuccessfulSyncAt: lastSync == null ? null : DateTime.parse(lastSync),
    );
  }

  Future<void> _updateCursor(
    String deviceId,
    String column,
    SyncCursor? cursor,
  ) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'sync_peers',
      {column: cursor?.encode(), 'updated_at': now},
      where: 'peer_device_id = ?',
      whereArgs: [deviceId],
    );
  }

  bool _isProjectable(EventEnvelope event) {
    return EventSchema.isSupported(event.schemaVersion) &&
        EventTypes.supported.contains(event.type);
  }

  String _safeReason(Object error) {
    if (error is EventValidationException) return error.errors.join('; ');
    if (error is ConflictingDuplicateEventException) {
      return 'conflicting duplicate event';
    }
    return 'event could not be applied';
  }

  String _displayName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Peer' : trimmed;
  }
}
