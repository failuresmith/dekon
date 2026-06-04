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
       _authenticator = SyncAuthenticator(now: now);

  final SyncStore store;
  final http.Client _client;
  final SyncAuthenticator _authenticator;

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
    await store.trustPeer(
      deviceId: payload.serverDeviceId,
      displayName: 'Sync server',
      baseUrl: payload.baseUrl,
      sharedSecret: payload.pairingSecret,
    );
    final peer = await store.trustedPeer(payload.serverDeviceId);
    if (peer == null) throw SyncClientException('Paired peer was not stored.');
    return peer;
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
    final response = await _client.get(
      uri,
      headers: _authHeaders('GET', uri, const [], peer),
    );
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
    await store.updatePullCursor(peer.deviceId, nextCursor);
    await store.markPeerSuccess(peer.deviceId);
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
    final response = await _client.post(
      uri,
      headers: {
        'content-type': 'application/json',
        ..._authHeaders('POST', uri, bodyBytes, peer),
      },
      body: body,
    );
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
    }
    await store.markPeerSuccess(peer.deviceId);
    return result;
  }

  Future<TrustedPeer> _requiredPeer(String peerDeviceId) async {
    final peer = await store.trustedPeer(peerDeviceId);
    if (peer == null || peer.baseUrl == null) {
      throw SyncClientException('Trusted peer is missing a base URL.');
    }
    return peer;
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
    );
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
