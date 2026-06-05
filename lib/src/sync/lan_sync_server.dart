import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../domain/events/events.dart';
import 'sync_activity.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';
import 'sync_store.dart';

class LanSyncServer {
  LanSyncServer({required this.store, DateTime Function()? now})
    : _authenticator = SyncAuthenticator(now: now),
      _now = now ?? DateTime.now;

  static const _defaultEventsWaitTimeout = Duration(seconds: 25);
  static const _maxEventsWaitTimeout = Duration(seconds: 30);

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
      final body = request.method == 'POST'
          ? await request.readAsString()
          : null;
      _recordPeerMessage(
        direction: SyncPeerMessageDirection.received,
        request: request,
        body: body,
      );
      final path = request.requestedUri.path;
      if (request.method == 'GET' && path == '/health') {
        return _health(request);
      }
      if (request.method == 'GET' && path == '/device') {
        return _device(request);
      }
      if (request.method == 'POST' && path == '/pair') {
        return _pair(request, body ?? '');
      }
      if (request.method == 'GET' && path == '/events') {
        final peer = await _authenticate(request, const []);
        if (peer == null) return _unauthorized(request);
        return _events(request, peer);
      }
      if (request.method == 'POST' && path == '/events') {
        final bodyBytes = utf8.encode(body ?? '');
        final peer = await _authenticate(request, bodyBytes);
        if (peer == null) return _unauthorized(request);
        return _postEvents(request, body ?? '', peer);
      }
      if (request.method == 'GET' && path == '/sync/state') {
        final peer = await _authenticate(request, const []);
        if (peer == null) return _unauthorized(request);
        await store.markPeerSuccess(peer.deviceId);
        return _json(
          await store.state().then((state) => state.toJson()),
          request: request,
        );
      }
      return _json(
        {'error': 'not_found'},
        status: HttpStatus.notFound,
        request: request,
      );
    } on FormatException {
      return _json(
        {'error': 'bad_request'},
        status: HttpStatus.badRequest,
        request: request,
      );
    } on Object {
      return _json(
        {'error': 'sync_request_failed'},
        status: HttpStatus.internalServerError,
        request: request,
      );
    }
  }

  Response _health(Request request) {
    return _json({
      'status': 'ok',
      'device_id': store.localDeviceId,
      'server_time': _now().toUtc().toIso8601String(),
    }, request: request);
  }

  Response _device(Request request) => _json({
    ...store.deviceInfo().toJson(),
    'server_time': _now().toUtc().toIso8601String(),
  }, request: request);

  Future<Response> _pair(Request request, String body) async {
    final payload = _pairingPayload;
    if (payload == null || payload.expiresAt.isBefore(_now().toUtc())) {
      return _json(
        {'error': 'pairing_unavailable'},
        status: HttpStatus.forbidden,
        request: request,
      );
    }
    final decoded = _decodeMap(body);
    final manualPairing = decoded['manual_pairing'] == true;
    if (!manualPairing && decoded['pairing_secret'] != payload.pairingSecret) {
      return _unauthorized(request);
    }
    final peerDeviceId = _requiredString(decoded, 'device_id');
    final assignedDisplayName = await store.trustCashierPeer(
      deviceId: peerDeviceId,
      baseUrl: decoded['base_url'] as String?,
      sharedSecret: payload.pairingSecret,
    );
    return _json({
      ...store.deviceInfo().toJson(),
      'shared_secret': payload.pairingSecret,
      'assigned_display_name': assignedDisplayName,
      'server_time': _now().toUtc().toIso8601String(),
    }, request: request);
  }

  Future<Response> _events(Request request, TrustedPeer peer) async {
    final query = request.requestedUri.queryParameters;
    final limit = _limit(query['limit']);
    final cursor = SyncCursor.parse(query['since']);
    var page = await store.fetchEventsAfter(cursor, limit: limit + 1);
    if (page.isEmpty && _shouldWaitForEvents(query)) {
      await store.waitForEventsAfter(
        cursor,
        timeout: _eventsWaitTimeout(query['wait_ms']),
      );
      page = await store.fetchEventsAfter(cursor, limit: limit + 1);
    }
    final events = page.take(limit).toList(growable: false);
    if (events.isNotEmpty) {
      store.notifyTransfer(SyncTransferDirection.sent, events.length);
    }
    await store.markPeerSuccess(peer.deviceId);
    return _json({
      'events': [for (final event in events) EventCodec.toJson(event)],
      'next_cursor': events.isEmpty
          ? cursor?.encode()
          : SyncCursor.fromEvent(events.last).encode(),
      'has_more': page.length > limit,
    }, request: request);
  }

  Future<Response> _postEvents(
    Request request,
    String body,
    TrustedPeer peer,
  ) async {
    final decoded = _decodeMap(body);
    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      return _json(
        {'error': 'events_must_be_list'},
        status: HttpStatus.badRequest,
        request: request,
      );
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
    if (result.hasEventOutcomes) {
      store.notifyTransfer(SyncTransferDirection.received, events.length);
    }
    await store.markPeerSuccess(peer.deviceId);
    return _json(result.toJson(), request: request);
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

  Response _unauthorized(Request request) {
    return _json(
      {
        'error': 'unauthorized',
        'server_time': _now().toUtc().toIso8601String(),
      },
      status: HttpStatus.unauthorized,
      request: request,
    );
  }

  Response _json(Object body, {int status = HttpStatus.ok, Request? request}) {
    final encoded = jsonEncode(body);
    if (request != null) {
      _recordPeerMessage(
        direction: SyncPeerMessageDirection.sent,
        request: request,
        statusCode: status,
        body: encoded,
      );
    }
    return Response(
      status,
      body: encoded,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  void _recordPeerMessage({
    required SyncPeerMessageDirection direction,
    required Request request,
    int? statusCode,
    String? body,
  }) {
    store.recordPeerMessage(
      SyncPeerMessage(
        timestamp: _now().toUtc(),
        direction: direction,
        method: request.method,
        path: _messagePath(request.requestedUri),
        statusCode: statusCode,
        peerDeviceId: request.headers[SyncAuthHeaders.deviceId],
        summary: SyncPeerMessage.summaryFrom(body),
        bodyPreview: SyncPeerMessage.bodyPreviewFrom(body),
      ),
    );
  }

  String _messagePath(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
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

  bool _shouldWaitForEvents(Map<String, String> query) {
    return query['wait'] == 'true' || query['wait'] == '1';
  }

  Duration _eventsWaitTimeout(String? value) {
    final parsed = int.tryParse(value ?? '');
    if (parsed == null) return _defaultEventsWaitTimeout;
    final clamped = parsed.clamp(0, _maxEventsWaitTimeout.inMilliseconds);
    return Duration(milliseconds: clamped.toInt());
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
