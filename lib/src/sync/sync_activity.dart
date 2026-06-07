import 'dart:async';
import 'dart:collection';
import 'dart:convert';

class SyncActivityBus {
  SyncActivityBus({this.maxPeerMessageBytes = defaultMaxPeerMessageBytes});

  static const defaultMaxPeerMessageBytes = 10 * 1024 * 1024;

  final int maxPeerMessageBytes;
  final _eventsChanged = StreamController<void>.broadcast();
  final _syncStateChanged = StreamController<void>.broadcast();
  final _transfers = StreamController<SyncTransferActivity>.broadcast();
  final _peerMessages = StreamController<SyncPeerMessage>.broadcast();
  final _cashierProjectionUpdates =
      StreamController<Map<String, Object?>>.broadcast();
  final _peerMessageLog = ListQueue<SyncPeerMessage>();
  int _peerMessageBytes = 0;

  Stream<void> get eventsChanged => _eventsChanged.stream;
  Stream<void> get syncStateChanged => _syncStateChanged.stream;
  Stream<SyncTransferActivity> get transfers => _transfers.stream;
  Stream<SyncPeerMessage> get peerMessages => _peerMessages.stream;
  Stream<Map<String, Object?>> get cashierProjectionUpdates =>
      _cashierProjectionUpdates.stream;

  List<SyncPeerMessage> peerMessageSnapshot() {
    return List.unmodifiable(_peerMessageLog);
  }

  void notifyEventsChanged() {
    if (!_eventsChanged.isClosed) _eventsChanged.add(null);
  }

  void notifySyncStateChanged() {
    if (!_syncStateChanged.isClosed) _syncStateChanged.add(null);
  }

  void notifyTransfer(SyncTransferActivity activity) {
    if (activity.eventCount <= 0 || _transfers.isClosed) return;
    _transfers.add(activity);
  }

  void recordPeerMessage(SyncPeerMessage message) {
    if (_peerMessages.isClosed || maxPeerMessageBytes <= 0) return;
    final messageBytes = message.estimatedMemoryBytes;
    if (messageBytes > maxPeerMessageBytes) {
      _peerMessageLog.clear();
      _peerMessageBytes = 0;
      _peerMessages.add(message);
      return;
    }
    _peerMessageLog.add(message);
    _peerMessageBytes += messageBytes;
    while (_peerMessageBytes > maxPeerMessageBytes &&
        _peerMessageLog.isNotEmpty) {
      _peerMessageBytes -= _peerMessageLog.removeFirst().estimatedMemoryBytes;
    }
    _peerMessages.add(message);
  }

  void notifyCashierProjectionUpdate(Map<String, Object?> update) {
    if (_cashierProjectionUpdates.isClosed) return;
    _cashierProjectionUpdates.add(Map<String, Object?>.unmodifiable(update));
  }

  void clearPeerMessages() {
    _peerMessageLog.clear();
    _peerMessageBytes = 0;
  }

  Future<void> close() async {
    await _eventsChanged.close();
    await _syncStateChanged.close();
    await _transfers.close();
    await _peerMessages.close();
    await _cashierProjectionUpdates.close();
  }
}

class SyncTransferActivity {
  const SyncTransferActivity({
    required this.direction,
    required this.eventCount,
  });

  final SyncTransferDirection direction;
  final int eventCount;
}

enum SyncTransferDirection { sent, received }

class SyncPeerMessage {
  const SyncPeerMessage({
    required this.timestamp,
    required this.direction,
    required this.method,
    required this.path,
    this.statusCode,
    this.peerDeviceId,
    this.summary,
    this.bodyContent,
  });

  final DateTime timestamp;
  final SyncPeerMessageDirection direction;
  final String method;
  final String path;
  final int? statusCode;
  final String? peerDeviceId;
  final String? summary;
  final String? bodyContent;

  int get estimatedMemoryBytes {
    return 64 +
        _stringMemoryBytes(method) +
        _stringMemoryBytes(path) +
        _stringMemoryBytes(peerDeviceId) +
        _stringMemoryBytes(summary) +
        _stringMemoryBytes(bodyContent);
  }

  static String? bodyContentFrom(String? body) {
    final trimmed = body?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(_redact(jsonDecode(trimmed)));
    } on Object {
      return trimmed;
    }
  }

  static int _stringMemoryBytes(String? value) {
    if (value == null) return 0;
    return value.length * 2;
  }

  static String? summaryFrom(String? body) {
    final trimmed = body?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final events = decoded['events'];
      if (events is List) return '${events.length} event(s)';
      if (decoded['shared_secret'] != null) return 'Pairing result';
      if (decoded['pairing_secret'] != null ||
          decoded['manual_pairing'] == true) {
        return 'Pairing request';
      }
      final outcomes = <String>[];
      for (final key in ['accepted', 'duplicate', 'unsupported', 'rejected']) {
        final value = decoded[key];
        if (value is List && value.isNotEmpty) {
          outcomes.add('$key: ${value.length}');
        }
      }
      if (outcomes.isNotEmpty) return outcomes.join(', ');
      final error = decoded['error'];
      if (error is String) return 'error: $error';
      if (decoded['device_id'] != null) return 'Device info';
    } on Object {
      return null;
    }
    return null;
  }

  static Object? _redact(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key: _isSensitiveKey(entry.key)
              ? '[redacted]'
              : _redact(entry.value),
      };
    }
    if (value is List) return [for (final item in value) _redact(item)];
    return value;
  }

  static bool _isSensitiveKey(Object? key) {
    final normalized = key.toString().toLowerCase();
    return normalized.contains('secret') ||
        normalized.contains('signature') ||
        normalized.contains('password') ||
        normalized.contains('token');
  }
}

enum SyncPeerMessageDirection { sent, received }
