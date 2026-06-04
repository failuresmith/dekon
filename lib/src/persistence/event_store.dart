import 'package:sqflite/sqflite.dart';

import '../domain/events/events.dart';

enum EventWriteStatus { accepted, duplicate, unsupported }

class EventWriteResult {
  const EventWriteResult(this.status, this.eventId, {this.reason});

  final EventWriteStatus status;
  final String eventId;
  final String? reason;
}

class ConflictingDuplicateEventException implements Exception {
  ConflictingDuplicateEventException(this.eventId);

  final String eventId;

  @override
  String toString() {
    return 'ConflictingDuplicateEventException: event_id $eventId has '
        'different stored payload data.';
  }
}

class UnsupportedEventRecord {
  const UnsupportedEventRecord({
    required this.eventId,
    required this.reason,
    required this.storedAt,
  });

  final String eventId;
  final String reason;
  final DateTime storedAt;
}

class EventStore {
  EventStore(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  Future<EventWriteResult> append(EventEnvelope event) {
    return _db.transaction((txn) async {
      return _appendInTransaction(txn, event);
    });
  }

  Future<List<EventWriteResult>> appendAll(List<EventEnvelope> events) {
    return _db.transaction((txn) async {
      final results = <EventWriteResult>[];
      for (final event in events) {
        results.add(await _appendInTransaction(txn, event));
      }
      return List<EventWriteResult>.unmodifiable(results);
    });
  }

  Future<EventWriteResult> appendInTransaction(
    Transaction txn,
    EventEnvelope event,
  ) {
    return _appendInTransaction(txn, event);
  }

  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS count FROM events');
    return rows.single['count'] as int;
  }

  Future<List<EventEnvelope>> fetchEvents() async {
    final rows = await _db.query('events', orderBy: 'hlc ASC, event_id ASC');
    return rows.map(EventEnvelope.fromStorage).toList(growable: false);
  }

  Future<List<EventEnvelope>> fetchEventsAfter({
    String? hlc,
    String? eventId,
    required int limit,
  }) async {
    final safeLimit = limit.clamp(1, 1000).toInt();
    final rows = hlc == null
        ? await _db.query(
            'events',
            orderBy: 'hlc ASC, event_id ASC',
            limit: safeLimit,
          )
        : await _db.query(
            'events',
            where: eventId == null
                ? 'hlc > ?'
                : '(hlc > ? OR (hlc = ? AND event_id > ?))',
            whereArgs: eventId == null ? [hlc] : [hlc, hlc, eventId],
            orderBy: 'hlc ASC, event_id ASC',
            limit: safeLimit,
          );
    return rows.map(EventEnvelope.fromStorage).toList(growable: false);
  }

  Future<List<UnsupportedEventRecord>> fetchUnsupportedEvents() async {
    final rows = await _db.query(
      'unsupported_events',
      orderBy: 'stored_at ASC',
    );
    return rows
        .map(
          (row) => UnsupportedEventRecord(
            eventId: row['event_id'] as String,
            reason: row['reason'] as String,
            storedAt: DateTime.parse(row['stored_at'] as String),
          ),
        )
        .toList(growable: false);
  }

  EventWriteResult _handleDuplicate(
    EventEnvelope event,
    Map<String, Object?> existing,
  ) {
    if (existing['payload_hash'] != event.payloadHash ||
        existing['payload_json'] != event.canonicalPayloadJson) {
      throw ConflictingDuplicateEventException(event.eventId);
    }
    return EventWriteResult(EventWriteStatus.duplicate, event.eventId);
  }

  Future<EventWriteResult> _appendInTransaction(
    Transaction txn,
    EventEnvelope event,
  ) async {
    final validation = EventValidator.validateForStorage(event);
    final existing = await txn.query(
      'events',
      columns: ['payload_hash', 'payload_json'],
      where: 'event_id = ?',
      whereArgs: [event.eventId],
      limit: 1,
    );
    if (existing.isNotEmpty) return _handleDuplicate(event, existing.single);

    final receivedAt = _now().toUtc();
    final unsupportedReason = validation.unsupportedReason;
    await txn.insert('events', _eventRow(event, receivedAt, unsupportedReason));
    if (unsupportedReason != null) {
      await txn.insert('unsupported_events', {
        'event_id': event.eventId,
        'reason': unsupportedReason,
        'stored_at': receivedAt.toIso8601String(),
      });
      return EventWriteResult(
        EventWriteStatus.unsupported,
        event.eventId,
        reason: unsupportedReason,
      );
    }
    return EventWriteResult(EventWriteStatus.accepted, event.eventId);
  }

  Map<String, Object?> _eventRow(
    EventEnvelope event,
    DateTime receivedAt,
    String? unsupportedReason,
  ) {
    return {
      'event_id': event.eventId,
      'device_id': event.deviceId,
      'hlc': event.hlc.toString(),
      'type': event.type,
      'entity_id': event.entityId,
      'schema_version': event.schemaVersion,
      'payload_json': event.canonicalPayloadJson,
      'payload_hash': event.payloadHash,
      'created_at': event.createdAt.toIso8601String(),
      'received_at': receivedAt.toIso8601String(),
      'supported': unsupportedReason == null ? 1 : 0,
    };
  }
}
