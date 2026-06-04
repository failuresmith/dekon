import 'canonical_json.dart';
import 'event_envelope.dart';
import 'event_hash.dart';
import 'event_schema.dart';
import 'event_types.dart';

enum EventValidationDisposition { supported, unsupportedSchema }

class EventValidationResult {
  const EventValidationResult.supported()
    : disposition = EventValidationDisposition.supported,
      unsupportedReason = null;

  const EventValidationResult.unsupportedSchema(this.unsupportedReason)
    : disposition = EventValidationDisposition.unsupportedSchema;

  final EventValidationDisposition disposition;
  final String? unsupportedReason;
}

class EventValidationException implements Exception {
  EventValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'EventValidationException: ${errors.join('; ')}';
}

class EventValidator {
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static final _uuidV7 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static EventValidationResult validateForStorage(EventEnvelope event) {
    final errors = <String>[];
    if (!_uuidV7.hasMatch(event.eventId)) {
      errors.add('event_id must be UUIDv7.');
    }
    if (!_uuid.hasMatch(event.deviceId)) {
      errors.add('device_id must be a UUID.');
    }
    if (event.hlc.nodeId != event.deviceId) {
      errors.add('hlc node_id must match device_id.');
    }
    if (event.hlc.physicalTimeMillis <= 0) {
      errors.add('hlc physical time must be positive.');
    }
    if (event.hlc.logicalCounter < 0) {
      errors.add('hlc logical counter must be non-negative.');
    }
    if (event.type.trim().isEmpty) {
      errors.add('type is required.');
    }
    if (event.entityId.trim().isEmpty) {
      errors.add('entity_id is required.');
    }
    if (event.schemaVersion <= 0) {
      errors.add('schema_version must be positive.');
    }
    _validatePayloadHash(event, errors);

    if (errors.isNotEmpty) throw EventValidationException(errors);
    if (EventSchema.isFutureVersion(event.schemaVersion)) {
      return EventValidationResult.unsupportedSchema(
        'schema_version ${event.schemaVersion} is newer than supported '
        'version ${EventSchema.currentVersion}.',
      );
    }
    if (!EventSchema.isSupported(event.schemaVersion)) {
      throw EventValidationException([
        'schema_version ${event.schemaVersion} is not supported.',
      ]);
    }
    if (!EventTypes.supported.contains(event.type)) {
      throw EventValidationException(['type is not supported: ${event.type}.']);
    }
    return const EventValidationResult.supported();
  }

  static void _validatePayloadHash(EventEnvelope event, List<String> errors) {
    try {
      final expectedHash = payloadHash(event.payload);
      if (event.payloadHash != expectedHash) {
        errors.add('payload_hash does not match canonical payload.');
      }
    } on CanonicalJsonException catch (error) {
      errors.add(error.message);
    }
  }
}
