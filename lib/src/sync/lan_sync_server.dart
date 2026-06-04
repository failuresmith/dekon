import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../domain/events/events.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';
import 'sync_store.dart';

class LanSyncServer {
  LanSyncServer({required this.store, DateTime Function()? now})
    : _authenticator = SyncAuthenticator(now: now),
      _now = now ?? DateTime.now;

  final SyncStore store;
  final SyncAuthenticator _authenticator;
  final DateTime Function() _now;
  HttpServer? _server;
  SyncPairingPayload? _pairingPayload;

  bool get isRunning => _server != null;
  String? get serverUrl => _pairingPayload?.baseUrl;
  String? get pairingQrData => _pairingPayload?.toQrJson();
  Handler get handler => _handle;

  Future<void> start({
    InternetAddress? address,
    int port = 0,
    Duration pairingTtl = const Duration(minutes: 10),
  }) async {
    if (_server != null) return;
    final server = await shelf_io.serve(
      handler,
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    final host = await _displayHost(server);
    createPairingPayload(
      baseUrl: 'http://$host:${server.port}',
      ttl: pairingTtl,
    );
  }

  SyncPairingPayload createPairingPayload({
    required String baseUrl,
    Duration ttl = const Duration(minutes: 10),
  }) {
    final payload = SyncPairingPayload(
      baseUrl: baseUrl,
      serverDeviceId: store.localDeviceId,
      pairingSecret: SyncSecrets.generate(),
      expiresAt: _now().toUtc().add(ttl),
    );
    _pairingPayload = payload;
    return payload;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairingPayload = null;
    await server?.close(force: true);
  }

  Future<Response> _handle(Request request) async {
    try {
      final path = request.requestedUri.path;
      if (request.method == 'GET' && path == '/health') return _health();
      if (request.method == 'GET' && path == '/device') return _device();
      if (request.method == 'POST' && path == '/pair') {
        return _pair(await request.readAsString());
      }
      if (request.method == 'GET' && path == '/events') {
        final peer = await _authenticate(request, const []);
        if (peer == null) return _unauthorized();
        return _events(request, peer);
      }
      if (request.method == 'POST' && path == '/events') {
        final body = await request.readAsString();
        final bodyBytes = utf8.encode(body);
        final peer = await _authenticate(request, bodyBytes);
        if (peer == null) return _unauthorized();
        return _postEvents(body, peer);
      }
      if (request.method == 'GET' && path == '/sync/state') {
        final peer = await _authenticate(request, const []);
        if (peer == null) return _unauthorized();
        await store.markPeerSuccess(peer.deviceId);
        return _json(await store.state().then((state) => state.toJson()));
      }
      return _json({'error': 'not_found'}, status: HttpStatus.notFound);
    } on FormatException {
      return _json({'error': 'bad_request'}, status: HttpStatus.badRequest);
    } on Object {
      return _json({
        'error': 'sync_request_failed',
      }, status: HttpStatus.internalServerError);
    }
  }

  Response _health() {
    return _json({
      'status': 'ok',
      'device_id': store.localDeviceId,
      'server_time': _now().toUtc().toIso8601String(),
    });
  }

  Response _device() => _json(store.deviceInfo().toJson());

  Future<Response> _pair(String body) async {
    final payload = _pairingPayload;
    if (payload == null || payload.expiresAt.isBefore(_now().toUtc())) {
      return _json({
        'error': 'pairing_unavailable',
      }, status: HttpStatus.forbidden);
    }
    final decoded = _decodeMap(body);
    if (decoded['pairing_secret'] != payload.pairingSecret) {
      return _unauthorized();
    }
    final peerDeviceId = _requiredString(decoded, 'device_id');
    await store.trustPeer(
      deviceId: peerDeviceId,
      displayName: decoded['display_name'] as String? ?? 'Peer',
      baseUrl: decoded['base_url'] as String?,
      sharedSecret: payload.pairingSecret,
    );
    return _json(store.deviceInfo().toJson());
  }

  Future<Response> _events(Request request, TrustedPeer peer) async {
    final query = request.requestedUri.queryParameters;
    final limit = _limit(query['limit']);
    final cursor = SyncCursor.parse(query['since']);
    final page = await store.fetchEventsAfter(cursor, limit: limit + 1);
    final events = page.take(limit).toList(growable: false);
    await store.markPeerSuccess(peer.deviceId);
    return _json({
      'events': [for (final event in events) EventCodec.toJson(event)],
      'next_cursor': events.isEmpty
          ? cursor?.encode()
          : SyncCursor.fromEvent(events.last).encode(),
      'has_more': page.length > limit,
    });
  }

  Future<Response> _postEvents(String body, TrustedPeer peer) async {
    final decoded = _decodeMap(body);
    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      return _json({
        'error': 'events_must_be_list',
      }, status: HttpStatus.badRequest);
    }
    final events = <EventEnvelope>[];
    final malformed = <EventRejection>[];
    for (var i = 0; i < rawEvents.length; i++) {
      final raw = rawEvents[i];
      try {
        events.add(EventCodec.fromJson(raw));
      } on Object catch (error) {
        malformed.add(
          EventRejection(
            eventId: EventCodec.eventIdFromJson(raw, i),
            reason: error is FormatException ? error.message : 'invalid event',
          ),
        );
      }
    }
    final result = (await store.importEvents(events)).withRejected(malformed);
    await store.markPeerSuccess(peer.deviceId);
    return _json(result.toJson());
  }

  Future<TrustedPeer?> _authenticate(
    Request request,
    List<int> bodyBytes,
  ) async {
    final deviceId = request.headers[SyncAuthHeaders.deviceId];
    if (deviceId == null) return null;
    final peer = await store.trustedPeer(deviceId);
    if (peer == null) return null;
    final valid = _authenticator.verify(
      headers: request.headers,
      method: request.method,
      uri: request.requestedUri,
      bodyBytes: bodyBytes,
      sharedSecret: peer.sharedSecret,
    );
    return valid ? peer : null;
  }

  Response _unauthorized() {
    return _json({'error': 'unauthorized'}, status: HttpStatus.unauthorized);
  }

  Response _json(Object body, {int status = HttpStatus.ok}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Map<String, Object?> _decodeMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('Body must be an object.');
    return {
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value as Object?,
    };
  }

  String _requiredString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field is required.');
    }
    return value.trim();
  }

  int _limit(String? value) {
    final parsed = int.tryParse(value ?? '') ?? 100;
    return parsed.clamp(1, 500).toInt();
  }

  Future<String> _displayHost(HttpServer server) async {
    if (server.address.address != InternetAddress.anyIPv4.address) {
      return server.address.address;
    }
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
    return InternetAddress.loopbackIPv4.address;
  }
}
