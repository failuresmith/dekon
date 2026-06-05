import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_protocol.dart';
import 'sync_security.dart';
import 'sync_store.dart';

class LanSyncClient {
  LanSyncClient({
    required this.store,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _authenticator = SyncAuthenticator(now: now),
       _now = now ?? DateTime.now;

  final SyncStore store;
  final http.Client _client;
  final SyncAuthenticator _authenticator;
  final DateTime Function() _now;
  Duration _serverClockOffset = Duration.zero;

  void close() => _client.close();

  Future<TrustedPeer> pairWithServer(
    SyncPairingPayload payload, {
    String displayName = 'Dekon phone',
  }) async {
    final uri = Uri.parse(payload.baseUrl).resolve('/pair');
    final body = jsonEncode({
      'device_id': store.localDeviceId,
      'display_name': displayName,
      'pairing_secret': payload.pairingSecret,
    });
    final response = await _client.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw SyncClientException('Pairing failed with ${response.statusCode}.');
    }
    _updateClockOffsetFromBody(response.body);
    final result = ManualPairingResult.fromJson(jsonDecode(response.body));
    if (result.deviceInfo.deviceId != payload.serverDeviceId) {
      throw SyncClientException('Main device identity changed during pairing.');
    }
    if (result.sharedSecret != payload.pairingSecret) {
      throw SyncClientException('Pairing secret changed during pairing.');
    }
    await store.trustPeer(
      deviceId: result.deviceInfo.deviceId,
      displayName: result.deviceInfo.displayName,
      baseUrl: payload.baseUrl,
      sharedSecret: payload.pairingSecret,
    );
    await _storeAssignedDisplayName(result.assignedDisplayName);
    final peer = await store.trustedPeer(result.deviceInfo.deviceId);
    if (peer == null) throw SyncClientException('Paired peer was not stored.');
    await syncWithPeer(peer.deviceId);
    return peer;
  }

  Future<TrustedPeer> pairWithManualAddress(
    String address, {
    String displayName = 'Dekon phone',
  }) async {
    final baseUrl = _normalizeManualAddress(address);
    final deviceUri = Uri.parse(baseUrl).resolve('/device');
    final deviceResponse = await _client.get(deviceUri);
    if (deviceResponse.statusCode != 200) {
      throw SyncClientException(
        'Main device lookup failed with ${deviceResponse.statusCode}.',
      );
    }
    _updateClockOffsetFromBody(deviceResponse.body);
    final deviceInfo = SyncDeviceInfo.fromJson(jsonDecode(deviceResponse.body));
    final pairUri = Uri.parse(baseUrl).resolve('/pair');
    final response = await _client.post(
      pairUri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'device_id': store.localDeviceId,
        'display_name': displayName,
        'manual_pairing': true,
      }),
    );
    if (response.statusCode != 200) {
      throw SyncClientException('Pairing failed with ${response.statusCode}.');
    }
    _updateClockOffsetFromBody(response.body);
    final result = ManualPairingResult.fromJson(jsonDecode(response.body));
    if (result.deviceInfo.deviceId != deviceInfo.deviceId) {
      throw SyncClientException('Main device identity changed during pairing.');
    }
    await store.trustPeer(
      deviceId: deviceInfo.deviceId,
      displayName: result.deviceInfo.displayName,
      baseUrl: baseUrl,
      sharedSecret: result.sharedSecret,
    );
    await _storeAssignedDisplayName(result.assignedDisplayName);
    final peer = await store.trustedPeer(deviceInfo.deviceId);
    if (peer == null) throw SyncClientException('Paired peer was not stored.');
    await syncWithPeer(peer.deviceId);
    return peer;
  }

  Future<void> syncWithPeer(String peerDeviceId) async {
    while (true) {
      final result = await pushToPeer(peerDeviceId);
      _throwIfRejected('Push', result);
      if (!result.hasEventOutcomes) break;
    }
    while (true) {
      final result = await pullFromPeer(peerDeviceId);
      _throwIfRejected('Pull', result);
      if (!result.hasEventOutcomes) break;
    }
  }

  Future<void> pingPeer(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final uri = Uri.parse(peer.baseUrl!).resolve('/sync/state');
    final response = await _authenticatedGet(uri, peer);
    if (response.statusCode != 200) {
      throw SyncClientException(
        'Main device ping failed with ${response.statusCode}.',
      );
    }
    await store.markPeerSuccess(peer.deviceId);
  }

  Future<PostEventsResult> pullFromPeer(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final cursor = peer.lastPulledCursor;
    final query = {
      if (cursor != null) 'since': cursor.encode(),
      'limit': '100',
    };
    final uri = Uri.parse(
      peer.baseUrl!,
    ).replace(path: '/events', queryParameters: query);
    final response = await _authenticatedGet(uri, peer);
    if (response.statusCode != 200) {
      throw SyncClientException('Pull failed with ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['events'] is! List) {
      throw SyncClientException('Pull response was malformed.');
    }
    final events = [
      for (final raw in decoded['events'] as List) EventCodec.fromJson(raw),
    ];
    final result = await store.importEvents(events);
    final nextCursor = SyncCursor.parse(decoded['next_cursor'] as String?);
    if (!result.hasRejected) {
      await store.updatePullCursor(peer.deviceId, nextCursor);
      await store.markPeerSuccess(peer.deviceId);
    }
    return result;
  }

  Future<PostEventsResult> pushToPeer(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final events = await store.fetchEventsAfter(
      peer.lastPushedCursor,
      limit: 100,
    );
    if (events.isEmpty) return const PostEventsResult();
    final uri = Uri.parse(peer.baseUrl!).resolve('/events');
    final body = jsonEncode({
      'events': [for (final event in events) EventCodec.toJson(event)],
    });
    final bodyBytes = utf8.encode(body);
    final response = await _authenticatedPost(uri, body, bodyBytes, peer);
    if (response.statusCode != 200) {
      throw SyncClientException('Push failed with ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw SyncClientException('Push response malformed.');
    final result = PostEventsResult(
      accepted: _stringList(decoded['accepted']),
      duplicate: _stringList(decoded['duplicate']),
      unsupported: _stringList(decoded['unsupported']),
      rejected: _rejections(decoded['rejected']),
    );
    if (!result.hasRejected) {
      await store.updatePushCursor(
        peer.deviceId,
        SyncCursor.fromEvent(events.last),
      );
      await store.markPeerSuccess(peer.deviceId);
    }
    return result;
  }

  void _throwIfRejected(String operation, PostEventsResult result) {
    if (!result.hasRejected) return;
    final first = result.rejected.first;
    throw SyncClientException(
      '$operation rejected ${result.rejected.length} event(s). '
      'First rejected event: ${first.eventId}.',
    );
  }

  Future<void> _storeAssignedDisplayName(String? displayName) async {
    if (displayName == null) return;
    await store.updateLocalDeviceDisplayName(displayName);
  }

  Future<TrustedPeer> _requiredPeer(String peerDeviceId) async {
    final peer = await store.trustedPeer(peerDeviceId);
    if (peer == null || peer.baseUrl == null) {
      throw SyncClientException('Trusted peer is missing a base URL.');
    }
    return peer;
  }

  Future<http.Response> _authenticatedGet(Uri uri, TrustedPeer peer) async {
    var response = await _client.get(
      uri,
      headers: _authHeaders('GET', uri, const [], peer),
    );
    if (response.statusCode == 401 &&
        _updateClockOffsetFromBody(response.body)) {
      response = await _client.get(
        uri,
        headers: _authHeaders('GET', uri, const [], peer),
      );
    }
    return response;
  }

  Future<http.Response> _authenticatedPost(
    Uri uri,
    String body,
    List<int> bodyBytes,
    TrustedPeer peer,
  ) async {
    Map<String, String> headers() => {
      'content-type': 'application/json',
      ..._authHeaders('POST', uri, bodyBytes, peer),
    };
    var response = await _client.post(uri, headers: headers(), body: body);
    if (response.statusCode == 401 &&
        _updateClockOffsetFromBody(response.body)) {
      response = await _client.post(uri, headers: headers(), body: body);
    }
    return response;
  }

  String _normalizeManualAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter the main device IP address.');
    }
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw const FormatException('Enter a valid main device IP address.');
    }
    final normalized = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : 0,
    );
    return normalized.toString().replaceFirst(RegExp(r'/$'), '');
  }

  Map<String, String> _authHeaders(
    String method,
    Uri uri,
    List<int> bodyBytes,
    TrustedPeer peer,
  ) {
    return _authenticator.signHeaders(
      method: method,
      uri: uri,
      bodyBytes: bodyBytes,
      deviceId: store.localDeviceId,
      sharedSecret: peer.sharedSecret,
      timestamp: _signedNow(),
    );
  }

  DateTime _signedNow() => _now().toUtc().add(_serverClockOffset);

  bool _updateClockOffsetFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final serverTime = decoded['server_time'];
      if (serverTime is! String) return false;
      final parsed = DateTime.tryParse(serverTime)?.toUtc();
      if (parsed == null) return false;
      _serverClockOffset = parsed.difference(_now().toUtc());
      return true;
    } on Object {
      return false;
    }
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }

  List<EventRejection> _rejections(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map &&
            item['event_id'] is String &&
            item['reason'] is String)
          EventRejection(
            eventId: item['event_id'] as String,
            reason: item['reason'] as String,
          ),
    ];
  }
}

class SyncClientException implements Exception {
  SyncClientException(this.message);

  final String message;

  @override
  String toString() => 'SyncClientException: $message';
}
