import 'dart:convert';

import '../domain/events/events.dart';

const syncProtocolVersion = 1;

class SyncCursor {
  const SyncCursor({required this.hlc, required this.eventId});

  final String hlc;
  final String eventId;

  factory SyncCursor.fromEvent(EventEnvelope event) {
    return SyncCursor(hlc: event.hlc.toString(), eventId: event.eventId);
  }

  static SyncCursor? parse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    try {
      final decoded = utf8.decode(base64Url.decode(_padBase64(trimmed)));
      final map = jsonDecode(decoded);
      if (map is! Map) throw const FormatException('Cursor must be an object.');
      final hlc = map['hlc'];
      final eventId = map['event_id'];
      if (hlc is! String || eventId is! String) {
        throw const FormatException('Cursor is missing fields.');
      }
      return SyncCursor(hlc: hlc, eventId: eventId);
    } on FormatException {
      return SyncCursor(hlc: trimmed, eventId: '');
    }
  }

  String encode() {
    final json = jsonEncode({'hlc': hlc, 'event_id': eventId});
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  static String _padBase64(String value) {
    return value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  }
}

class EventCodec {
  static Map<String, Object?> toJson(EventEnvelope event) {
    return {
      'event_id': event.eventId,
      'device_id': event.deviceId,
      'hlc': event.hlc.toString(),
      'type': event.type,
      'entity_id': event.entityId,
      'schema_version': event.schemaVersion,
      'payload': event.payload,
      'payload_hash': event.payloadHash,
      'created_at': event.createdAt.toIso8601String(),
    };
  }

  static EventEnvelope fromJson(Object? value) {
    final map = _stringMap(value, 'event');
    return EventEnvelope(
      eventId: _stringField(map, 'event_id'),
      deviceId: _stringField(map, 'device_id'),
      hlc: HybridLogicalTimestamp.parse(_stringField(map, 'hlc')),
      type: _stringField(map, 'type'),
      entityId: _stringField(map, 'entity_id'),
      schemaVersion: _intField(map, 'schema_version'),
      payload:
          canonicalJsonValue(_stringMap(map['payload'], 'payload'))
              as EventPayload,
      payloadHash: _stringField(map, 'payload_hash'),
      createdAt: DateTime.parse(_stringField(map, 'created_at')),
    );
  }

  static String eventIdFromJson(Object? value, int index) {
    if (value is Map && value['event_id'] is String) {
      return value['event_id'] as String;
    }
    return 'index:$index';
  }
}

class EventRejection {
  const EventRejection({required this.eventId, required this.reason});

  final String eventId;
  final String reason;

  Map<String, Object?> toJson() => {'event_id': eventId, 'reason': reason};
}

class PostEventsResult {
  const PostEventsResult({
    this.accepted = const [],
    this.duplicate = const [],
    this.unsupported = const [],
    this.rejected = const [],
  });

  final List<String> accepted;
  final List<String> duplicate;
  final List<String> unsupported;
  final List<EventRejection> rejected;

  bool get hasRejected => rejected.isNotEmpty;

  PostEventsResult withRejected(List<EventRejection> extra) {
    return PostEventsResult(
      accepted: accepted,
      duplicate: duplicate,
      unsupported: unsupported,
      rejected: [...extra, ...rejected],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'accepted': accepted,
      'duplicate': duplicate,
      'unsupported': unsupported,
      'rejected': [for (final item in rejected) item.toJson()],
    };
  }
}

class SyncDeviceInfo {
  const SyncDeviceInfo({required this.deviceId, required this.displayName});

  final String deviceId;
  final String displayName;

  factory SyncDeviceInfo.fromJson(Object? value) {
    final map = _stringMap(value, 'device info');
    return SyncDeviceInfo(
      deviceId: _stringField(map, 'device_id'),
      displayName: _stringField(map, 'display_name'),
    );
  }

  Map<String, Object?> toJson() => {
    'protocol_version': syncProtocolVersion,
    'event_schema_version': EventSchema.currentVersion,
    'device_id': deviceId,
    'display_name': displayName,
  };
}

class SyncPairingPayload {
  const SyncPairingPayload({
    required this.baseUrl,
    required this.serverDeviceId,
    required this.pairingSecret,
    required this.expiresAt,
  });

  final String baseUrl;
  final String serverDeviceId;
  final String pairingSecret;
  final DateTime expiresAt;

  factory SyncPairingPayload.fromQrJson(String contents) {
    final decoded = jsonDecode(contents);
    final map = _stringMap(decoded, 'pairing payload');
    final version = _intField(map, 'protocol_version');
    if (version != syncProtocolVersion) {
      throw FormatException('Unsupported sync protocol version: $version.');
    }
    final baseUrl = _stringField(map, 'base_url');
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw const FormatException('base_url must be a valid URL.');
    }
    return SyncPairingPayload(
      baseUrl: baseUrl,
      serverDeviceId: _stringField(map, 'server_device_id'),
      pairingSecret: _stringField(map, 'pairing_secret'),
      expiresAt: DateTime.parse(_stringField(map, 'expires_at')),
    );
  }

  Map<String, Object?> toJson() => {
    'protocol_version': syncProtocolVersion,
    'base_url': baseUrl,
    'server_device_id': serverDeviceId,
    'pairing_secret': pairingSecret,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  String toQrJson() => jsonEncode(toJson());
}

class ManualPairingResult {
  const ManualPairingResult({
    required this.deviceInfo,
    required this.sharedSecret,
  });

  final SyncDeviceInfo deviceInfo;
  final String sharedSecret;

  factory ManualPairingResult.fromJson(Object? value) {
    final map = _stringMap(value, 'manual pairing result');
    return ManualPairingResult(
      deviceInfo: SyncDeviceInfo.fromJson(map),
      sharedSecret: _stringField(map, 'shared_secret'),
    );
  }
}

class SyncState {
  const SyncState({
    required this.deviceId,
    required this.eventCount,
    required this.unsupportedEventCount,
    required this.trustedPeerCount,
    this.lastSuccessfulSyncAt,
  });

  final String deviceId;
  final int eventCount;
  final int unsupportedEventCount;
  final int trustedPeerCount;
  final DateTime? lastSuccessfulSyncAt;

  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'event_count': eventCount,
    'unsupported_event_count': unsupportedEventCount,
    'trusted_peer_count': trustedPeerCount,
    'last_successful_sync_at': lastSuccessfulSyncAt?.toIso8601String(),
  };
}

class TrustedPeer {
  const TrustedPeer({
    required this.deviceId,
    required this.displayName,
    required this.sharedSecret,
    this.baseUrl,
    this.lastPulledCursor,
    this.lastPushedCursor,
  });

  final String deviceId;
  final String displayName;
  final String sharedSecret;
  final String? baseUrl;
  final SyncCursor? lastPulledCursor;
  final SyncCursor? lastPushedCursor;
}

Map<String, Object?> _stringMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  final map = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label contains a non-string key.');
    }
    map[entry.key as String] = entry.value as Object?;
  }
  return map;
}

String _stringField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _intField(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is! int) throw FormatException('$field must be an integer.');
  return value;
}
