import 'dart:convert';

import 'canonical_json.dart';
import 'event_hash.dart' as hashes;
import 'event_schema.dart';
import 'hybrid_logical_clock.dart';

typedef EventPayload = Map<String, Object?>;

class EventEnvelope {
  EventEnvelope({
    required this.eventId,
    required this.deviceId,
    required this.hlc,
    required this.type,
    required this.entityId,
    required EventPayload payload,
    required this.schemaVersion,
    required this.payloadHash,
    required DateTime createdAt,
  }) : payload = Map<String, Object?>.unmodifiable(payload),
       createdAt = createdAt.toUtc();

  factory EventEnvelope.local({
    required String eventId,
    required String deviceId,
    required HybridLogicalTimestamp hlc,
    required String type,
    required String entityId,
    required EventPayload payload,
    int schemaVersion = EventSchema.currentVersion,
    DateTime? createdAt,
  }) {
    final canonicalPayload = canonicalJsonValue(payload) as EventPayload;
    return EventEnvelope(
      eventId: eventId,
      deviceId: deviceId,
      hlc: hlc,
      type: type,
      entityId: entityId,
      payload: canonicalPayload,
      schemaVersion: schemaVersion,
      payloadHash: hashes.payloadHash(canonicalPayload),
      createdAt: createdAt ?? DateTime.now().toUtc(),
    );
  }

  factory EventEnvelope.fromStorage(Map<String, Object?> row) {
    final decoded = jsonDecode(row['payload_json'] as String);
    if (decoded is! Map) {
      throw const FormatException(
        'Stored event payload must be a JSON object.',
      );
    }
    final payload = canonicalJsonValue(decoded) as EventPayload;
    return EventEnvelope(
      eventId: row['event_id'] as String,
      deviceId: row['device_id'] as String,
      hlc: HybridLogicalTimestamp.parse(row['hlc'] as String),
      type: row['type'] as String,
      entityId: row['entity_id'] as String,
      payload: payload,
      schemaVersion: row['schema_version'] as int,
      payloadHash: row['payload_hash'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  final String eventId;
  final String deviceId;
  final HybridLogicalTimestamp hlc;
  final String type;
  final String entityId;
  final EventPayload payload;
  final int schemaVersion;
  final String payloadHash;
  final DateTime createdAt;

  String get canonicalPayloadJson => canonicalJsonEncode(payload);
}
