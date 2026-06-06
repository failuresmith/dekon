import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'cashier_product_projection.dart';
import 'sync_access_control.dart';
import 'sync_activity.dart';
import 'sync_protocol.dart';
import 'sync_security.dart';
import 'sync_service_discovery.dart';
import 'sync_store.dart';

typedef CashierProjectionWebSocketConnector =
    Future<WebSocket> Function(String url, {Map<String, dynamic>? headers});

class LanSyncTimeouts {
  const LanSyncTimeouts({
    this.ping = const Duration(seconds: 2),
    this.pairing = const Duration(seconds: 8),
    this.saleCommand = const Duration(seconds: 8),
    this.inventorySnapshot = const Duration(seconds: 15),
    this.eventPull = const Duration(seconds: 8),
    this.eventPush = const Duration(seconds: 8),
    this.longPollTransportMargin = const Duration(seconds: 5),
    this.webSocketConnect = const Duration(seconds: 5),
  });

  final Duration ping;
  final Duration pairing;
  final Duration saleCommand;
  final Duration inventorySnapshot;
  final Duration eventPull;
  final Duration eventPush;
  final Duration longPollTransportMargin;
  final Duration webSocketConnect;
}

class LanSyncClient {
  LanSyncClient({
    required this.store,
    this.serviceDiscovery,
    this.timeouts = const LanSyncTimeouts(),
    this.projectionHeartbeatInterval = const Duration(seconds: 15),
    http.Client? client,
    this.webSocketConnector,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _authenticator = SyncAuthenticator(now: now),
       _now = now ?? DateTime.now;

  final SyncStore store;
  final SyncServiceDiscovery? serviceDiscovery;
  final LanSyncTimeouts timeouts;
  final Duration? projectionHeartbeatInterval;
  final CashierProjectionWebSocketConnector? webSocketConnector;
  final http.Client _client;
  final SyncAuthenticator _authenticator;
  final DateTime Function() _now;
  Duration _serverClockOffset = Duration.zero;

  static const _defaultPullWaitTimeout = Duration(seconds: 25);
  static const _maxPullWaitTimeout = Duration(seconds: 30);
  static const _subnetProbeConcurrency = 32;
  static const _subnetProbePerHostTimeout = Duration(milliseconds: 250);
  static const _maxProjectionMessageQueueDepth = 32;

  Future<void> _projectionMessageQueue = Future<void>.value();
  var _projectionMessageQueueDepth = 0;

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
    final response = await _post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: body,
      peerDeviceId: payload.serverDeviceId,
      timeout: timeouts.pairing,
      timeoutCode: SyncTimeoutException.pairing,
      operation: 'Pairing',
    );
    if (response.statusCode != 200) {
      throw SyncClientException('Pairing failed with ${response.statusCode}.');
    }
    _updateClockOffsetFromBody(response.body);
    final result = ManualPairingResult.fromJson(jsonDecode(response.body));
    if (result.deviceInfo.deviceId != payload.serverDeviceId) {
      throw SyncClientException('Main device identity changed during pairing.');
    }
    await store.trustPeer(
      deviceId: result.deviceInfo.deviceId,
      displayName: result.deviceInfo.displayName,
      baseUrl: payload.baseUrl,
      sharedSecret: result.sharedSecret,
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
    final deviceResponse = await _get(
      deviceUri,
      timeout: timeouts.pairing,
      timeoutCode: SyncTimeoutException.pairing,
      operation: 'Pairing device lookup',
    );
    if (deviceResponse.statusCode != 200) {
      throw SyncClientException(
        'Main device lookup failed with ${deviceResponse.statusCode}.',
      );
    }
    _updateClockOffsetFromBody(deviceResponse.body);
    final deviceInfo = SyncDeviceInfo.fromJson(jsonDecode(deviceResponse.body));
    final pairUri = Uri.parse(baseUrl).resolve('/pair');
    final response = await _post(
      pairUri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'device_id': store.localDeviceId,
        'display_name': displayName,
        'manual_pairing': true,
      }),
      peerDeviceId: deviceInfo.deviceId,
      timeout: timeouts.pairing,
      timeoutCode: SyncTimeoutException.pairing,
      operation: 'Manual pairing',
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

  Future<void> syncWithPeer(
    String peerDeviceId, {
    bool waitForRemoteEvents = false,
    Duration waitTimeout = _defaultPullWaitTimeout,
  }) async {
    return _withAddressDiscoveryRetry(
      peerDeviceId,
      () => _syncWithPeer(
        peerDeviceId,
        waitForRemoteEvents: waitForRemoteEvents,
        waitTimeout: waitTimeout,
      ),
    );
  }

  Future<void> _syncWithPeer(
    String peerDeviceId, {
    required bool waitForRemoteEvents,
    required Duration waitTimeout,
  }) async {
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
    await fetchAndApplyCashierInventorySnapshot(peerDeviceId);
    await _drainCashierSaleOutbox(peerDeviceId, limit: 100);
    if (!waitForRemoteEvents) return;
    var waitForNextPull = waitForRemoteEvents;
    while (true) {
      final result = await pullFromPeer(
        peerDeviceId,
        waitForEvents: waitForNextPull,
        waitTimeout: waitTimeout,
      );
      _throwIfRejected('Pull', result);
      if (!result.hasEventOutcomes) break;
      await fetchAndApplyCashierInventorySnapshot(peerDeviceId);
      waitForNextPull = false;
    }
  }

  Future<void> pingPeer(String peerDeviceId) async {
    return _withAddressDiscoveryRetry(
      peerDeviceId,
      () => _pingPeer(peerDeviceId),
    );
  }

  Future<void> _pingPeer(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final uri = Uri.parse(peer.baseUrl!).resolve('/sync/state');
    final response = await _authenticatedGet(
      uri,
      peer,
      timeout: timeouts.ping,
      timeoutCode: SyncTimeoutException.ping,
      operation: 'Main device ping',
    );
    if (response.statusCode != 200) {
      _throwIfPeerUnpaired(response);
      throw SyncClientException(
        'Main device ping failed with ${response.statusCode}.',
      );
    }
    await store.markPeerSuccess(peer.deviceId);
  }

  Future<PostEventsResult> pullFromPeer(
    String peerDeviceId, {
    bool waitForEvents = false,
    Duration waitTimeout = _defaultPullWaitTimeout,
  }) async {
    final peer = await _requiredPeer(peerDeviceId);
    final cursor = peer.lastPulledCursor;
    final query = {
      if (cursor != null) 'since': cursor.encode(),
      'limit': '100',
      if (waitForEvents) ...{
        'wait': 'true',
        'wait_ms': _waitMilliseconds(waitTimeout).toString(),
      },
    };
    final uri = Uri.parse(
      peer.baseUrl!,
    ).replace(path: '/events', queryParameters: query);
    final response = await _authenticatedGet(
      uri,
      peer,
      timeout: _eventPullTimeout(
        waitForEvents: waitForEvents,
        waitTimeout: waitTimeout,
      ),
      timeoutCode: waitForEvents
          ? SyncTimeoutException.eventLongPoll
          : SyncTimeoutException.eventPull,
      operation: waitForEvents ? 'Long-poll event pull' : 'Event pull',
    );
    if (response.statusCode != 200) {
      _throwIfPeerUnpaired(response);
      throw SyncClientException('Pull failed with ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['events'] is! List) {
      throw SyncClientException('Pull response was malformed.');
    }
    final events = [
      for (final raw in decoded['events'] as List) EventCodec.fromJson(raw),
    ];
    if (events.isNotEmpty) {
      store.notifyTransfer(SyncTransferDirection.received, events.length);
    }
    final result = await store.importEvents(events);
    final nextCursor = SyncCursor.parse(decoded['next_cursor'] as String?);
    if (!result.hasRejected) {
      await store.updatePullCursor(peer.deviceId, nextCursor);
      await store.markPeerSuccess(peer.deviceId);
    }
    return result;
  }

  Future<void> fetchAndApplyCashierInventorySnapshot(
    String peerDeviceId,
  ) async {
    final peer = await _requiredPeer(peerDeviceId);
    final uri = Uri.parse(peer.baseUrl!).resolve('/cashier/inventory-snapshot');
    final response = await _authenticatedGet(
      uri,
      peer,
      timeout: timeouts.inventorySnapshot,
      timeoutCode: SyncTimeoutException.inventorySnapshot,
      operation: 'Inventory snapshot',
    );
    if (response.statusCode != 200) {
      _throwIfPeerUnpaired(response);
      throw SyncClientException(
        'Inventory snapshot failed with ${response.statusCode}.',
      );
    }
    _updateClockOffsetFromBody(response.body);
    final snapshot = CashierInventorySnapshot.fromJson(
      jsonDecode(response.body),
    );
    await store.applyCashierInventorySnapshot(snapshot);
    await store.markPeerSuccess(peer.deviceId);
  }

  Future<WebSocket> openCashierProjectionStream(String peerDeviceId) async {
    return _withAddressDiscoveryRetry(
      peerDeviceId,
      () => _openCashierProjectionStream(peerDeviceId),
    );
  }

  Future<WebSocket> _openCashierProjectionStream(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final uri = _webSocketUri(peer.baseUrl!, '/cashier/projection-stream');
    final headers = _authHeaders('GET', uri, const [], peer);
    final connector = webSocketConnector;
    final connect = connector == null
        ? WebSocket.connect(uri.toString(), headers: headers)
        : connector(uri.toString(), headers: headers);
    final socket = await _withTimeout(
      connect,
      timeout: timeouts.webSocketConnect,
      timeoutCode: SyncTimeoutException.projectionStream,
      operation: 'Projection WebSocket connect',
      peerDeviceId: peer.deviceId,
    );
    socket.pingInterval = projectionHeartbeatInterval;
    await store.markPeerSuccess(peer.deviceId);
    return socket;
  }

  Future<CashierSaleCommandResult> submitCashierSaleCommand(
    String peerDeviceId,
    CashierSaleCommand command,
  ) async {
    final peer = await _requiredPeer(peerDeviceId);
    final uri = Uri.parse(peer.baseUrl!).resolve('/cashier/sales');
    final body = jsonEncode(command.toJson());
    final bodyBytes = utf8.encode(body);
    final response = await _authenticatedPost(
      uri,
      body,
      bodyBytes,
      peer,
      timeout: timeouts.saleCommand,
      timeoutCode: SyncTimeoutException.saleCommand,
      operation: 'Sale command submission',
    );
    if (response.statusCode != 200) {
      _throwIfPeerUnpaired(response);
      final rejection = _cashierSaleCommandRejection(response.body);
      if (rejection != null) throw rejection;
      throw SyncClientException(
        'Sale command failed with ${response.statusCode}: '
        '${_errorCodeFromBody(response.body)}.',
      );
    }
    _updateClockOffsetFromBody(response.body);
    final result = CashierSaleCommandResult.fromJson(jsonDecode(response.body));
    final localEvent = cashierSafeEventFor(
      event: result.event,
      cashierDeviceId: store.localDeviceId,
    );
    if (localEvent == null) {
      throw SyncClientException('Sale command response malformed.');
    }
    final importResult = await store.importEvents([localEvent]);
    _throwIfRejected('Sale command import', importResult);
    await fetchAndApplyCashierInventorySnapshot(peerDeviceId);
    await store.markPeerSuccess(peer.deviceId);
    return result;
  }

  Future<void> drainCashierSaleOutbox(
    String peerDeviceId, {
    int limit = 100,
  }) async {
    return _withAddressDiscoveryRetry(
      peerDeviceId,
      () => _drainCashierSaleOutbox(peerDeviceId, limit: limit),
    );
  }

  Future<void> _drainCashierSaleOutbox(
    String peerDeviceId, {
    required int limit,
  }) async {
    for (var index = 0; index < limit; index++) {
      final entry = await store.nextCashierSaleCommandForSync();
      if (entry == null) return;
      final commandId = entry.command.commandId;
      await store.markCashierSaleCommandSyncing(commandId);
      try {
        final result = await submitCashierSaleCommand(
          peerDeviceId,
          entry.command,
        );
        await store.markCashierSaleCommandAccepted(
          commandId: commandId,
          acceptedEventId: result.event.eventId,
        );
      } on CashierSaleCommandRejectedException catch (error) {
        await store.markCashierSaleCommandConflict(
          commandId: commandId,
          errorCode: error.code,
          productIds: error.productIds,
        );
        return;
      } catch (_) {
        await store.markCashierSaleCommandQueued(commandId);
        rethrow;
      }
    }
  }

  Future<CashierProjectionApplyStatus> applyCashierProjectionMessage(
    String peerDeviceId,
    Object? message,
  ) {
    final update = CashierProjectionUpdate.fromJson(
      _decodeProjectionMessage(message),
    );
    if (_projectionMessageQueueDepth >= _maxProjectionMessageQueueDepth) {
      return Future.error(
        SyncClientException('Projection message queue is full.'),
      );
    }
    _projectionMessageQueueDepth += 1;
    final completer = Completer<CashierProjectionApplyStatus>();
    final previous = _projectionMessageQueue;
    _projectionMessageQueue = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(
          await _applyCashierProjectionUpdate(peerDeviceId, update),
        );
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _projectionMessageQueueDepth -= 1;
      }
    });
    return completer.future;
  }

  Future<CashierProjectionApplyStatus> _applyCashierProjectionUpdate(
    String peerDeviceId,
    CashierProjectionUpdate update,
  ) async {
    final peer = await _requiredPeer(peerDeviceId);
    if (update.type == cashierProjectionUnpaired) {
      if (update.targetDeviceId == store.localDeviceId) {
        throw const CashierUnpairedException();
      }
      return CashierProjectionApplyStatus.duplicate;
    }
    final lastApplied = await store.lastAppliedCashierProjectionVersion();
    if (update.projectionVersion <= lastApplied) {
      await store.markPeerSuccess(peer.deviceId);
      return CashierProjectionApplyStatus.duplicate;
    }
    final status = await store.applyCashierProjectionUpdate(update);
    switch (status) {
      case CashierProjectionApplyStatus.applied:
      case CashierProjectionApplyStatus.duplicate:
        await store.markPeerSuccess(peer.deviceId);
      case CashierProjectionApplyStatus.gap:
      case CashierProjectionApplyStatus.snapshotRequired:
        await fetchAndApplyCashierInventorySnapshot(peerDeviceId);
    }
    return status;
  }

  Future<PostEventsResult> pushToPeer(String peerDeviceId) async {
    final peer = await _requiredPeer(peerDeviceId);
    final events = await store.fetchLocalEventsAfter(
      peer.lastPushedCursor,
      limit: 100,
    );
    if (events.isEmpty) return const PostEventsResult();
    final uri = Uri.parse(peer.baseUrl!).resolve('/events');
    final body = jsonEncode({
      'events': [for (final event in events) EventCodec.toJson(event)],
    });
    final bodyBytes = utf8.encode(body);
    final response = await _authenticatedPost(
      uri,
      body,
      bodyBytes,
      peer,
      timeout: timeouts.eventPush,
      timeoutCode: SyncTimeoutException.eventPush,
      operation: 'Event push',
    );
    if (response.statusCode != 200) {
      _throwIfPeerUnpaired(response);
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
    store.notifyTransfer(SyncTransferDirection.sent, events.length);
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

  void _throwIfPeerUnpaired(http.Response response) {
    if (response.statusCode == HttpStatus.forbidden &&
        _errorCodeFromBody(response.body) == 'peer_unpaired') {
      throw const CashierUnpairedException();
    }
  }

  Future<void> _storeAssignedDisplayName(String? displayName) async {
    if (displayName == null) return;
    await store.updateLocalDeviceDisplayName(displayName);
  }

  Future<bool> refreshPeerBaseUrlFromDiscovery(
    String peerDeviceId, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final trustedPeer = await store.trustedPeer(peerDeviceId);
    if (trustedPeer == null) return false;
    final discovery = serviceDiscovery;
    if (discovery == null) {
      return _refreshPeerBaseUrlFromFixedPortSubnet(
        trustedPeer,
        timeout: timeout,
      );
    }
    final List<DiscoveredSyncService> services;
    try {
      services = await discovery.discoverMainServices(timeout: timeout);
    } on Object {
      return _refreshPeerBaseUrlFromFixedPortSubnet(
        trustedPeer,
        timeout: timeout,
      );
    }
    final tried = <String>{};
    for (final service in services) {
      if ((service.deviceId.isNotEmpty && service.deviceId != peerDeviceId) ||
          (service.protocolVersion > 0 &&
              service.protocolVersion != syncProtocolVersion) ||
          !tried.add(service.baseUrl)) {
        continue;
      }
      if (await _verifyDiscoveredPeerBaseUrl(trustedPeer, service.baseUrl)) {
        await store.updateTrustedPeerBaseUrl(
          deviceId: peerDeviceId,
          baseUrl: service.baseUrl,
        );
        return true;
      }
    }
    return _refreshPeerBaseUrlFromFixedPortSubnet(
      trustedPeer,
      timeout: timeout,
    );
  }

  Future<T> _withAddressDiscoveryRetry<T>(
    String peerDeviceId,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on CashierUnpairedException {
      rethrow;
    } on SyncTimeoutException {
      rethrow;
    } catch (error, stackTrace) {
      final refreshed = await refreshPeerBaseUrlFromDiscovery(peerDeviceId);
      if (!refreshed) Error.throwWithStackTrace(error, stackTrace);
      return operation();
    }
  }

  Future<bool> _verifyDiscoveredPeerBaseUrl(
    TrustedPeer trustedPeer,
    String baseUrl, {
    Duration? timeout,
  }) async {
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme || base.host.trim().isEmpty) {
      return false;
    }
    final nonce = SyncSecrets.generate(bytes: 16);
    final uri = base
        .resolve('/sync/state')
        .replace(queryParameters: {'nonce': nonce});
    final peer = TrustedPeer(
      deviceId: trustedPeer.deviceId,
      displayName: trustedPeer.displayName,
      sharedSecret: trustedPeer.sharedSecret,
      baseUrl: baseUrl,
      lastPulledCursor: trustedPeer.lastPulledCursor,
      lastPushedCursor: trustedPeer.lastPushedCursor,
    );
    try {
      final response = await _authenticatedGet(
        uri,
        peer,
        timeout: timeout ?? timeouts.ping,
        timeoutCode: SyncTimeoutException.ping,
        operation: 'Discovered Main verification',
      );
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['device_id'] != trustedPeer.deviceId) {
        return false;
      }
      final responseAuth = decoded['response_auth'];
      if (responseAuth is! Map) return false;
      final responseNonce = responseAuth['nonce'];
      final signature = responseAuth['signature'];
      if (responseNonce is! String ||
          signature is! String ||
          responseNonce != nonce) {
        return false;
      }
      final verified = _authenticator.verifyStateResponse(
        nonce: nonce,
        deviceId: trustedPeer.deviceId,
        sharedSecret: trustedPeer.sharedSecret,
        signature: signature,
      );
      if (verified) await store.markPeerSuccess(trustedPeer.deviceId);
      return verified;
    } on CashierUnpairedException {
      return false;
    } on Object {
      return false;
    }
  }

  Future<bool> _refreshPeerBaseUrlFromFixedPortSubnet(
    TrustedPeer trustedPeer, {
    required Duration timeout,
  }) async {
    final candidates = await _fixedPortSubnetCandidates(
      trustedPeer,
      port: syncDefaultLanPort,
    );
    if (candidates.isEmpty) return false;
    final stopwatch = Stopwatch()..start();
    var nextIndex = 0;
    var found = false;

    Future<bool> worker() async {
      while (!found && nextIndex < candidates.length) {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) return false;
        final index = nextIndex++;
        final baseUrl = candidates[index];
        final perHostTimeout = remaining < _subnetProbePerHostTimeout
            ? remaining
            : _subnetProbePerHostTimeout;
        final verified = await _verifyDiscoveredPeerBaseUrl(
          trustedPeer,
          baseUrl,
          timeout: perHostTimeout,
        );
        if (!verified) continue;
        found = true;
        await store.updateTrustedPeerBaseUrl(
          deviceId: trustedPeer.deviceId,
          baseUrl: baseUrl,
        );
        return true;
      }
      return false;
    }

    final workerCount = candidates.length < _subnetProbeConcurrency
        ? candidates.length
        : _subnetProbeConcurrency;
    final results = await Future.wait([
      for (var i = 0; i < workerCount; i++) worker(),
    ]);
    return results.any((result) => result);
  }

  Future<List<String>> _fixedPortSubnetCandidates(
    TrustedPeer trustedPeer, {
    required int port,
  }) async {
    final prefixes = <String>{};
    final currentHost = Uri.tryParse(trustedPeer.baseUrl ?? '')?.host;
    final currentPrefix = _ipv4SubnetPrefix(currentHost);
    if (currentPrefix != null) prefixes.add(currentPrefix);
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final prefix = _ipv4SubnetPrefix(address.address);
          if (prefix != null) prefixes.add(prefix);
        }
      }
    } on Object {
      // mDNS remains the primary automatic discovery path when interfaces
      // cannot be listed.
    }
    final candidates = <String>[];
    final seen = <String>{};
    for (final prefix in prefixes) {
      for (var host = 1; host <= 254; host++) {
        final baseUrl = 'http://$prefix.$host:$port';
        if (seen.add(baseUrl)) candidates.add(baseUrl);
      }
    }
    return candidates;
  }

  String? _ipv4SubnetPrefix(String? host) {
    if (host == null) return null;
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) return null;
      numbers.add(number);
    }
    if (numbers.first == 127 || numbers.first == 0) return null;
    return '${numbers[0]}.${numbers[1]}.${numbers[2]}';
  }

  Future<TrustedPeer> _requiredPeer(String peerDeviceId) async {
    final peer = await store.trustedPeer(peerDeviceId);
    if (peer == null || peer.baseUrl == null) {
      throw SyncClientException('Trusted peer is missing a base URL.');
    }
    return peer;
  }

  Uri _webSocketUri(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    final scheme = switch (base.scheme) {
      'https' => 'wss',
      _ => 'ws',
    };
    return base.replace(scheme: scheme, path: path, query: null);
  }

  Object? _decodeProjectionMessage(Object? message) {
    if (message is String) return jsonDecode(message);
    if (message is List<int>) return jsonDecode(utf8.decode(message));
    return message;
  }

  Future<http.Response> _authenticatedGet(
    Uri uri,
    TrustedPeer peer, {
    required Duration timeout,
    required String timeoutCode,
    required String operation,
  }) async {
    var response = await _get(
      uri,
      headers: _authHeaders('GET', uri, const [], peer),
      peerDeviceId: peer.deviceId,
      timeout: timeout,
      timeoutCode: timeoutCode,
      operation: operation,
    );
    if (response.statusCode == 401 &&
        _updateClockOffsetFromBody(response.body)) {
      response = await _get(
        uri,
        headers: _authHeaders('GET', uri, const [], peer),
        peerDeviceId: peer.deviceId,
        timeout: timeout,
        timeoutCode: timeoutCode,
        operation: operation,
      );
    }
    return response;
  }

  Future<http.Response> _authenticatedPost(
    Uri uri,
    String body,
    List<int> bodyBytes,
    TrustedPeer peer, {
    required Duration timeout,
    required String timeoutCode,
    required String operation,
  }) async {
    Map<String, String> headers() => {
      'content-type': 'application/json',
      ..._authHeaders('POST', uri, bodyBytes, peer),
    };
    var response = await _post(
      uri,
      headers: headers(),
      body: body,
      peerDeviceId: peer.deviceId,
      timeout: timeout,
      timeoutCode: timeoutCode,
      operation: operation,
    );
    if (response.statusCode == 401 &&
        _updateClockOffsetFromBody(response.body)) {
      response = await _post(
        uri,
        headers: headers(),
        body: body,
        peerDeviceId: peer.deviceId,
        timeout: timeout,
        timeoutCode: timeoutCode,
        operation: operation,
      );
    }
    return response;
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
    String? peerDeviceId,
    required Duration timeout,
    required String timeoutCode,
    required String operation,
  }) async {
    _recordPeerMessage(
      direction: SyncPeerMessageDirection.sent,
      method: 'GET',
      uri: uri,
      peerDeviceId: peerDeviceId,
    );
    final response = await _withTimeout(
      _client.get(uri, headers: headers),
      timeout: timeout,
      timeoutCode: timeoutCode,
      operation: operation,
      peerDeviceId: peerDeviceId,
    );
    _recordPeerMessage(
      direction: SyncPeerMessageDirection.received,
      method: 'GET',
      uri: uri,
      statusCode: response.statusCode,
      peerDeviceId: peerDeviceId,
      body: response.body,
    );
    return response;
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    String? peerDeviceId,
    required Duration timeout,
    required String timeoutCode,
    required String operation,
  }) async {
    _recordPeerMessage(
      direction: SyncPeerMessageDirection.sent,
      method: 'POST',
      uri: uri,
      peerDeviceId: peerDeviceId,
      body: body,
    );
    final response = await _withTimeout(
      _client.post(uri, headers: headers, body: body),
      timeout: timeout,
      timeoutCode: timeoutCode,
      operation: operation,
      peerDeviceId: peerDeviceId,
    );
    _recordPeerMessage(
      direction: SyncPeerMessageDirection.received,
      method: 'POST',
      uri: uri,
      statusCode: response.statusCode,
      peerDeviceId: peerDeviceId,
      body: response.body,
    );
    return response;
  }

  void _recordPeerMessage({
    required SyncPeerMessageDirection direction,
    required String method,
    required Uri uri,
    int? statusCode,
    String? peerDeviceId,
    String? body,
  }) {
    store.recordPeerMessage(
      SyncPeerMessage(
        timestamp: _now().toUtc(),
        direction: direction,
        method: method,
        path: _messagePath(uri),
        statusCode: statusCode,
        peerDeviceId: peerDeviceId,
        summary: SyncPeerMessage.summaryFrom(body),
        bodyPreview: SyncPeerMessage.bodyPreviewFrom(body),
      ),
    );
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

  String _messagePath(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;
    return uri.hasQuery ? '$path?${uri.query}' : path;
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

  int _waitMilliseconds(Duration timeout) {
    return timeout.inMilliseconds
        .clamp(0, _maxPullWaitTimeout.inMilliseconds)
        .toInt();
  }

  Duration _eventPullTimeout({
    required bool waitForEvents,
    required Duration waitTimeout,
  }) {
    if (!waitForEvents) return timeouts.eventPull;
    return Duration(milliseconds: _waitMilliseconds(waitTimeout)) +
        timeouts.longPollTransportMargin;
  }

  Future<T> _withTimeout<T>(
    Future<T> future, {
    required Duration timeout,
    required String timeoutCode,
    required String operation,
    String? peerDeviceId,
  }) async {
    try {
      return await future.timeout(timeout);
    } on TimeoutException catch (_, stackTrace) {
      final exception = SyncTimeoutException(
        code: timeoutCode,
        operation: operation,
        timeout: timeout,
      );
      if (peerDeviceId != null) {
        await store.markPeerFailure(peerDeviceId, timeoutCode);
      }
      Error.throwWithStackTrace(exception, stackTrace);
    }
  }

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

  String _errorCodeFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on Object {
      // Ignore malformed error bodies; callers only need a safe summary.
    }
    return 'sync_request_failed';
  }

  CashierSaleCommandRejectedException? _cashierSaleCommandRejection(
    String body,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['error'] is! String) return null;
      return CashierSaleCommandRejectedException(
        decoded['error'] as String,
        productIds: _stringList(decoded['product_ids']),
      );
    } catch (_) {
      return null;
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

class SyncTimeoutException extends SyncClientException {
  SyncTimeoutException({
    required this.code,
    required this.operation,
    required this.timeout,
  }) : super('$operation timed out after ${timeout.inMilliseconds} ms.');

  static const ping = 'ping_timeout';
  static const pairing = 'pairing_timeout';
  static const saleCommand = 'sale_command_timeout';
  static const inventorySnapshot = 'inventory_snapshot_timeout';
  static const eventPull = 'event_pull_timeout';
  static const eventPush = 'event_push_timeout';
  static const eventLongPoll = 'event_long_poll_timeout';
  static const projectionStream = 'projection_stream_timeout';

  final String code;
  final String operation;
  final Duration timeout;

  @override
  String toString() => 'SyncTimeoutException: $code';
}

class CashierSaleCommandRejectedException implements Exception {
  CashierSaleCommandRejectedException(this.code, {this.productIds = const []});

  final String code;
  final List<String> productIds;

  @override
  String toString() => 'CashierSaleCommandRejectedException: $code';
}

class CashierUnpairedException implements Exception {
  const CashierUnpairedException();

  @override
  String toString() => 'CashierUnpairedException';
}
