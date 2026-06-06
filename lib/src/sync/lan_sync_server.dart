import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../domain/events/events.dart';
import 'cashier_product_projection.dart';
import 'sync_access_control.dart';
import 'sync_activity.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';
import 'sync_store.dart';

class LanSyncServer {
  LanSyncServer({required this.store, DateTime Function()? now})
    : _authenticator = SyncAuthenticator(now: now),
      _authorization = const AuthorizationService(),
      _now = now ?? DateTime.now;

  static const _defaultEventsWaitTimeout = Duration(seconds: 25);
  static const _maxEventsWaitTimeout = Duration(seconds: 30);

  final SyncStore store;
  final SyncAuthenticator _authenticator;
  final AuthorizationService _authorization;
  final DateTime Function() _now;
  HttpServer? _server;
  String? _baseUrl;
  SyncPairingPayload? _pairingPayload;
  StreamSubscription<Map<String, Object?>>? _projectionSubscription;
  final _projectionSockets = <WebSocket, String>{};

  bool get isRunning => _server != null;
  String? get serverUrl => _baseUrl;
  String? get pairingQrData {
    final payload = _pairingPayload;
    if (payload == null || payload.expiresAt.isBefore(_now().toUtc())) {
      return null;
    }
    return payload.toQrJson();
  }

  Handler get handler => _handle;

  Future<void> start({
    InternetAddress? address,
    int port = 0,
    Duration pairingTtl = const Duration(minutes: 10),
    bool enablePairing = true,
  }) async {
    if (_server != null) {
      if (enablePairing) startPairing(ttl: pairingTtl);
      return;
    }
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    _projectionSubscription = store.activityBus?.cashierProjectionUpdates
        .listen(_broadcastProjectionUpdate);
    server.listen((request) {
      unawaited(_handleHttpRequest(request));
    });
    final host = await _displayHost(server);
    _baseUrl = 'http://$host:${server.port}';
    if (enablePairing) startPairing(ttl: pairingTtl);
  }

  SyncPairingPayload startPairing({
    Duration ttl = const Duration(minutes: 10),
  }) {
    final baseUrl = _baseUrl;
    if (_server == null || baseUrl == null) {
      throw StateError('Sync server must be running before pairing starts.');
    }
    return createPairingPayload(baseUrl: baseUrl, ttl: ttl);
  }

  SyncPairingPayload createPairingPayload({
    required String baseUrl,
    Duration ttl = const Duration(minutes: 10),
  }) {
    _baseUrl = baseUrl;
    final payload = SyncPairingPayload(
      baseUrl: baseUrl,
      serverDeviceId: store.localDeviceId,
      pairingSecret: SyncSecrets.generate(),
      expiresAt: _now().toUtc().add(ttl),
    );
    _pairingPayload = payload;
    return payload;
  }

  Future<void> unpairCashier(String deviceId) async {
    final trimmed = deviceId.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(deviceId, 'deviceId');
    await _sendUnpairMessage(trimmed);
    await store.revokePeer(trimmed);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _baseUrl = null;
    _pairingPayload = null;
    await _projectionSubscription?.cancel();
    _projectionSubscription = null;
    for (final socket in _projectionSockets.keys.toList()) {
      await socket.close();
    }
    _projectionSockets.clear();
    await server?.close(force: true);
  }

  Future<void> _sendUnpairMessage(String deviceId) async {
    final message = jsonEncode(
      serializeCashierUnpairedMessage(deviceId: deviceId),
    );
    final sockets = _projectionSockets.entries
        .where((entry) => entry.value == deviceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final socket in sockets) {
      try {
        socket.add(message);
        await socket.close(WebSocketStatus.normalClosure, 'unpaired');
      } on Object {
        _projectionSockets.remove(socket);
        unawaited(socket.close());
      }
    }
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (request.method == 'GET' &&
        request.uri.path == '/cashier/projection-stream') {
      await _projectionStream(request);
      return;
    }
    await shelf_io.handleRequest(request, handler);
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
        if (peer == null) {
          return _authenticationFailed(request, const []);
        }
        return _events(request, peer);
      }
      if (request.method == 'GET' && path == '/cashier/inventory-snapshot') {
        final peer = await _authenticate(request, const []);
        if (peer == null) {
          return _authenticationFailed(request, const []);
        }
        return _cashierInventorySnapshot(request, peer);
      }
      if (request.method == 'POST' && path == '/cashier/sales') {
        final bodyBytes = utf8.encode(body ?? '');
        final peer = await _authenticate(request, bodyBytes);
        if (peer == null) return _authenticationFailed(request, bodyBytes);
        return _postCashierSale(request, body ?? '', peer);
      }
      if (request.method == 'POST' && path == '/events') {
        final bodyBytes = utf8.encode(body ?? '');
        final peer = await _authenticate(request, bodyBytes);
        if (peer == null) return _authenticationFailed(request, bodyBytes);
        return _postEvents(request, body ?? '', peer);
      }
      if (request.method == 'GET' && path == '/sync/state') {
        final peer = await _authenticate(request, const []);
        if (peer == null) {
          return _authenticationFailed(request, const []);
        }
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
    _authorization.requireCapability(
      principal: _remoteCashierPrincipal(peer),
      capability: Capability.viewCashierInventory,
    );
    final query = request.requestedUri.queryParameters;
    final limit = _limit(query['limit']);
    final cursor = SyncCursor.parse(query['since']);
    var page = await _cashierEventPage(peer, cursor, limit);
    if (page.events.isEmpty && _shouldWaitForEvents(query)) {
      await store.waitForEventsAfter(
        cursor,
        timeout: _eventsWaitTimeout(query['wait_ms']),
      );
      page = await _cashierEventPage(peer, cursor, limit);
    }
    final events = page.events;
    if (events.isNotEmpty) {
      store.notifyTransfer(SyncTransferDirection.sent, events.length);
    }
    await store.markPeerSuccess(peer.deviceId);
    return _json({
      'events': [for (final event in events) EventCodec.toJson(event)],
      'next_cursor': page.nextCursor?.encode(),
      'has_more': page.hasMore,
    }, request: request);
  }

  Future<Response> _cashierInventorySnapshot(
    Request request,
    TrustedPeer peer,
  ) async {
    _authorization.requireCapability(
      principal: _remoteCashierPrincipal(peer),
      capability: Capability.viewCashierInventory,
    );
    final snapshot = await store.cashierInventorySnapshot();
    await store.markPeerSuccess(peer.deviceId);
    return _json({
      ...snapshot.toJson(),
      'server_time': _now().toUtc().toIso8601String(),
    }, request: request);
  }

  Future<Response> _postCashierSale(
    Request request,
    String body,
    TrustedPeer peer,
  ) async {
    _authorization.requireCapability(
      principal: _remoteCashierPrincipal(peer),
      capability: Capability.recordSale,
    );
    try {
      final command = CashierSaleCommand.fromJson(_decodeMap(body));
      final result = await store.recordCashierSaleCommand(
        cashierDeviceId: peer.deviceId,
        command: command,
      );
      if (!result.duplicate) {
        store.notifyTransfer(SyncTransferDirection.received, 1);
      }
      await store.markPeerSuccess(peer.deviceId);
      return _json({
        ...result.toJson(),
        'server_time': _now().toUtc().toIso8601String(),
      }, request: request);
    } on CashierSaleCommandException catch (error) {
      return _json(
        {
          'error': error.code,
          if (error.productIds.isNotEmpty) 'product_ids': error.productIds,
          'server_time': _now().toUtc().toIso8601String(),
        },
        status: _saleCommandStatus(error),
        request: request,
      );
    } on EventValidationException {
      return _json(
        {
          'error': CashierSaleCommandException.invalidCommand,
          'server_time': _now().toUtc().toIso8601String(),
        },
        status: HttpStatus.badRequest,
        request: request,
      );
    }
  }

  Future<void> _projectionStream(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await _rawJson(request, {
        'error': 'websocket_upgrade_required',
      }, status: HttpStatus.badRequest);
      return;
    }
    final peer = await _authenticateRaw(request);
    if (peer == null) {
      if (await _isRevokedRawRequest(request)) {
        await _rawJson(request, {
          'error': 'peer_unpaired',
          'server_time': _now().toUtc().toIso8601String(),
        }, status: HttpStatus.forbidden);
        return;
      }
      await _rawJson(request, {
        'error': 'unauthorized',
        'server_time': _now().toUtc().toIso8601String(),
      }, status: HttpStatus.unauthorized);
      return;
    }
    try {
      _authorization.requireCapability(
        principal: _remoteCashierPrincipal(peer),
        capability: Capability.viewCashierInventory,
      );
    } on AuthorizationException {
      await _rawJson(request, {
        'error': AuthorizationException.permissionDenied,
      }, status: HttpStatus.forbidden);
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _projectionSockets[socket] = peer.deviceId;
    await store.markPeerSuccess(peer.deviceId);
    socket.done.whenComplete(() {
      _projectionSockets.remove(socket);
    });
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
    final authorizationRejected = <EventRejection>[];
    final authorizedEvents = <EventEnvelope>[];
    for (final event in events) {
      if (event.deviceId != peer.deviceId) {
        authorizationRejected.add(
          EventRejection(
            eventId: event.eventId,
            reason: AuthorizationException.permissionDenied,
          ),
        );
        continue;
      }
      final capability = capabilityForRemoteEvent(event);
      if (capability == null) {
        authorizationRejected.add(
          EventRejection(
            eventId: event.eventId,
            reason: AuthorizationException.permissionDenied,
          ),
        );
        continue;
      }
      try {
        _authorization.requireCapability(
          principal: _remoteCashierPrincipal(peer),
          capability: capability,
        );
        authorizedEvents.add(event);
      } on AuthorizationException catch (error) {
        authorizationRejected.add(
          EventRejection(eventId: event.eventId, reason: error.code),
        );
      }
    }
    final result = (await store.importEvents(
      authorizedEvents,
    )).withRejected([...malformed, ...authorizationRejected]);
    if (result.hasEventOutcomes) {
      store.notifyTransfer(
        SyncTransferDirection.received,
        authorizedEvents.length,
      );
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

  Future<TrustedPeer?> _authenticateRaw(HttpRequest request) async {
    final deviceId = request.headers.value(SyncAuthHeaders.deviceId);
    if (deviceId == null) return null;
    final peer = await store.trustedPeer(deviceId);
    if (peer == null) return null;
    final valid = _authenticator.verify(
      headers: _rawHeaders(request),
      method: request.method,
      uri: request.requestedUri,
      bodyBytes: const [],
      sharedSecret: peer.sharedSecret,
    );
    return valid ? peer : null;
  }

  Future<Response> _authenticationFailed(
    Request request,
    List<int> bodyBytes,
  ) async {
    if (await _isRevokedRequest(request, bodyBytes)) {
      return _peerUnpaired(request);
    }
    return _unauthorized(request);
  }

  Future<bool> _isRevokedRequest(Request request, List<int> bodyBytes) async {
    final deviceId = request.headers[SyncAuthHeaders.deviceId];
    if (deviceId == null) return false;
    final peer = await store.revokedPeer(deviceId);
    if (peer == null) return false;
    return _authenticator.verify(
      headers: request.headers,
      method: request.method,
      uri: request.requestedUri,
      bodyBytes: bodyBytes,
      sharedSecret: peer.sharedSecret,
    );
  }

  Future<bool> _isRevokedRawRequest(HttpRequest request) async {
    final deviceId = request.headers.value(SyncAuthHeaders.deviceId);
    if (deviceId == null) return false;
    final peer = await store.revokedPeer(deviceId);
    if (peer == null) return false;
    return _authenticator.verify(
      headers: _rawHeaders(request),
      method: request.method,
      uri: request.requestedUri,
      bodyBytes: const [],
      sharedSecret: peer.sharedSecret,
    );
  }

  Map<String, String> _rawHeaders(HttpRequest request) {
    return {
      for (final name in [
        SyncAuthHeaders.deviceId,
        SyncAuthHeaders.timestamp,
        SyncAuthHeaders.bodyHash,
        SyncAuthHeaders.signature,
      ])
        if (request.headers.value(name) != null)
          name: request.headers.value(name)!,
    };
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

  Response _peerUnpaired(Request request) {
    return _json(
      {
        'error': 'peer_unpaired',
        'server_time': _now().toUtc().toIso8601String(),
      },
      status: HttpStatus.forbidden,
      request: request,
    );
  }

  Future<void> _rawJson(
    HttpRequest request,
    Object body, {
    required int status,
  }) async {
    final encoded = jsonEncode(body);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(encoded);
    await request.response.close();
  }

  void _broadcastProjectionUpdate(Map<String, Object?> update) {
    if (_projectionSockets.isEmpty) return;
    final encoded = jsonEncode(update);
    for (final socket in _projectionSockets.keys.toList()) {
      try {
        socket.add(encoded);
      } on Object {
        _projectionSockets.remove(socket);
        unawaited(socket.close());
      }
    }
  }

  DevicePrincipal _remoteCashierPrincipal(TrustedPeer peer) {
    return DevicePrincipal(
      deviceId: peer.deviceId,
      role: SyncDeviceRole.cashier,
      isLocalMainDevice: false,
    );
  }

  Future<_CashierEventPage> _cashierEventPage(
    TrustedPeer peer,
    SyncCursor? cursor,
    int limit,
  ) async {
    final safeEvents = <EventEnvelope>[];
    var scanCursor = cursor;
    var nextCursor = cursor;
    var hasMore = false;
    const scanLimit = 100;
    while (safeEvents.length < limit) {
      final rawPage = await store.fetchEventsAfter(
        scanCursor,
        limit: scanLimit,
      );
      if (rawPage.isEmpty) break;
      for (final event in rawPage) {
        scanCursor = SyncCursor.fromEvent(event);
        final safeEvent = cashierSafeEventFor(
          event: event,
          cashierDeviceId: peer.deviceId,
        );
        if (safeEvent == null) continue;
        safeEvents.add(safeEvent);
        nextCursor = SyncCursor.fromEvent(event);
        if (safeEvents.length == limit) {
          hasMore = true;
          break;
        }
      }
      if (safeEvents.length == limit || rawPage.length < scanLimit) {
        if (safeEvents.isEmpty) nextCursor = scanCursor;
        break;
      }
    }
    return _CashierEventPage(
      events: safeEvents,
      nextCursor: nextCursor,
      hasMore: hasMore,
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

  int _saleCommandStatus(CashierSaleCommandException error) {
    return switch (error.code) {
      CashierSaleCommandException.invalidCommand => HttpStatus.badRequest,
      _ => HttpStatus.conflict,
    };
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

class _CashierEventPage {
  const _CashierEventPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<EventEnvelope> events;
  final SyncCursor? nextCursor;
  final bool hasMore;
}
