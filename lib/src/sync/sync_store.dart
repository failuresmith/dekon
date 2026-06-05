import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../domain/events/events.dart';
import '../persistence/persistence.dart';
import 'sync_activity.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';

class SyncStore {
  SyncStore({
    required Database database,
    required this.localDeviceId,
    EventStore? eventStore,
    DomainProjector? projector,
    this.activityBus,
    DateTime Function()? now,
  }) : _db = database,
       _eventStore = eventStore ?? EventStore(database),
       _projector = projector ?? DomainProjector(database),
       _now = now ?? DateTime.now;

  final Database _db;
  final String localDeviceId;
  final EventStore _eventStore;
  final DomainProjector _projector;
  final SyncActivityBus? activityBus;
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
      await _trustPeerInTransaction(
        txn,
        deviceId: deviceId,
        displayName: displayName,
        sharedSecret: sharedSecret,
        baseUrl: baseUrl,
        now: now,
      );
    });
  }

  Future<String> trustCashierPeer({
    required String deviceId,
    required String sharedSecret,
    String? baseUrl,
  }) async {
    if (deviceId == localDeviceId) {
      throw ArgumentError.value(deviceId, 'deviceId', 'Cannot trust self.');
    }
    final now = _now().toUtc().toIso8601String();
    return _db.transaction((txn) async {
      final displayName = await _cashierDisplayNameForPairing(txn, deviceId);
      await _trustPeerInTransaction(
        txn,
        deviceId: deviceId,
        displayName: displayName,
        sharedSecret: sharedSecret,
        baseUrl: baseUrl,
        now: now,
        lastSeenAt: now,
      );
      return displayName;
    });
  }

  Future<void> updateLocalDeviceDisplayName(String displayName) async {
    final now = _now().toUtc().toIso8601String();
    await _db.update(
      'devices',
      {'display_name': _displayName(displayName), 'updated_at': now},
      where: 'device_id = ?',
      whereArgs: [localDeviceId],
    );
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
    return _trustedPeerFromRow(rows.single);
  }

  Future<List<TrustedPeer>> trustedPeers() async {
    final rows = await _db.rawQuery('''
      SELECT d.device_id, d.display_name, d.trust_status, p.base_url,
             p.shared_secret, p.last_pulled_hlc, p.last_pushed_hlc
      FROM devices d
      JOIN sync_peers p ON p.peer_device_id = d.device_id
      WHERE d.trust_status = 'trusted'
      ORDER BY d.updated_at DESC, d.device_id ASC
      ''');
    final peers = <TrustedPeer>[];
    for (final row in rows) {
      final peer = _trustedPeerFromRow(row);
      if (peer != null) peers.add(peer);
    }
    return peers;
  }

  TrustedPeer? _trustedPeerFromRow(Map<String, Object?> row) {
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
    activityBus?.notifySyncStateChanged();
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

  Future<void> waitForEventsAfter(
    SyncCursor? cursor, {
    required Duration timeout,
  }) async {
    final eventsChanged = activityBus?.eventsChanged;
    if (eventsChanged == null || timeout <= Duration.zero) return;
    final deadline = DateTime.now().add(timeout);

    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return;
      final changed = Completer<void>();
      final subscription = eventsChanged.listen((_) {
        if (!changed.isCompleted) changed.complete();
      });
      try {
        final events = await fetchEventsAfter(cursor, limit: 1);
        if (events.isNotEmpty) return;
        await changed.future.timeout(remaining);
      } on TimeoutException {
        return;
      } finally {
        await subscription.cancel();
      }
    }
  }

  Future<PostEventsResult> importEvents(List<EventEnvelope> events) async {
    final accepted = <String>[];
    final duplicate = <String>[];
    final unsupported = <String>[];
    final rejected = <EventRejection>[];

    final orderedEvents = events.toList(growable: false)
      ..sort(_compareEventCreation);
    for (final event in orderedEvents) {
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

    if (accepted.isNotEmpty || unsupported.isNotEmpty) {
      activityBus?.notifyEventsChanged();
    }

    return PostEventsResult(
      accepted: accepted,
      duplicate: duplicate,
      unsupported: unsupported,
      rejected: rejected,
    );
  }

  int _compareEventCreation(EventEnvelope a, EventEnvelope b) {
    final created = a.createdAt.compareTo(b.createdAt);
    if (created != 0) return created;
    final hlc = a.hlc.compareTo(b.hlc);
    if (hlc != 0) return hlc;
    return a.eventId.compareTo(b.eventId);
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

  void notifyTransfer(SyncTransferDirection direction, int eventCount) {
    activityBus?.notifyTransfer(
      SyncTransferActivity(direction: direction, eventCount: eventCount),
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
    activityBus?.notifySyncStateChanged();
  }

  Future<void> _trustPeerInTransaction(
    Transaction txn, {
    required String deviceId,
    required String displayName,
    required String sharedSecret,
    required String now,
    String? baseUrl,
    String? lastSeenAt,
  }) async {
    await txn.insert('devices', {
      'device_id': deviceId,
      'display_name': _displayName(displayName),
      'trust_status': 'trusted',
      'shared_secret_hash': SyncSecrets.hash(sharedSecret),
      'created_at': now,
      'updated_at': now,
      'last_seen_at': ?lastSeenAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await txn.update(
      'devices',
      {
        'display_name': _displayName(displayName),
        'trust_status': 'trusted',
        'shared_secret_hash': SyncSecrets.hash(sharedSecret),
        'updated_at': now,
        'last_seen_at': ?lastSeenAt,
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
  }

  Future<String> _cashierDisplayNameForPairing(
    Transaction txn,
    String deviceId,
  ) async {
    final existing = await txn.query(
      'devices',
      columns: ['display_name'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final displayName = existing.single['display_name'] as String?;
      if (_cashierNumber(displayName) != null) return displayName!.trim();
    }

    final rows = await txn.query(
      'devices',
      columns: ['display_name'],
      where: 'trust_status = ?',
      whereArgs: const ['trusted'],
    );
    final used = <int>{};
    for (final row in rows) {
      final number = _cashierNumber(row['display_name'] as String?);
      if (number != null) used.add(number);
    }
    var next = 1;
    while (used.contains(next)) {
      next++;
    }
    return 'Cashier-$next';
  }

  int? _cashierNumber(String? displayName) {
    final match = RegExp(
      r'^Cashier-([1-9][0-9]*)$',
    ).firstMatch(displayName?.trim() ?? '');
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
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
