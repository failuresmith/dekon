import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../application/application.dart';
import '../sync/sync.dart';
import 'cashier_sync_status.dart';

typedef CashierSyncOperation = Future<void> Function();
typedef CashierProjectionStreamFactory = Future<Stream<Object?>> Function();
typedef CashierProjectionMessageHandler =
    Future<void> Function(Object? message);

class CashierSyncController {
  CashierSyncController({
    required this.repository,
    this.pingMainDevice,
    this.syncWithMainDevice,
    this.openProjectionStream,
    this.applyProjectionMessage,
    this.syncServiceDiscovery = const NoopSyncServiceDiscovery(),
    this.syncTransfers,
    this.pollInterval = const Duration(seconds: 1),
    this.syncWaitTimeout = const Duration(seconds: 25),
  });

  static const _minimumSyncVisibleDuration = Duration(seconds: 1);
  static const _projectionStreamRetryDelay = Duration(seconds: 5);

  final DekonRepository repository;
  final CashierSyncOperation? pingMainDevice;
  final CashierSyncOperation? syncWithMainDevice;
  final CashierProjectionStreamFactory? openProjectionStream;
  final CashierProjectionMessageHandler? applyProjectionMessage;
  final SyncServiceDiscovery syncServiceDiscovery;
  final Stream<SyncTransferActivity>? syncTransfers;
  final Duration? pollInterval;
  final Duration syncWaitTimeout;

  final _statusChanges = StreamController<CashierSyncStatus>.broadcast();

  var _connected = false;
  var _transferring = false;
  var _snapshotSyncInProgress = false;
  var _refreshing = false;
  var _refreshAgain = false;
  var _unpaired = false;
  var _started = false;
  var _disposed = false;
  int? _lastAppliedProjectionVersion;
  var _pendingOutboxCount = 0;
  var _conflictedOutboxCount = 0;
  String? _lastErrorCode;
  Timer? _timer;
  Timer? _transferHideTimer;
  StreamSubscription<SyncTransferActivity>? _transferSubscription;
  StreamSubscription<void>? _eventsChangedSubscription;
  StreamSubscription<Object?>? _projectionSubscription;
  LanSyncClient? _projectionClient;
  WebSocket? _projectionSocket;
  String? _projectionPeerDeviceId;
  Timer? _projectionRetryTimer;
  var _openingProjectionStream = false;
  var _closingProjectionStream = false;
  var _projectionStreamFallback = false;

  CashierSyncStatus get status => _status;
  Stream<CashierSyncStatus> get statusChanges => _statusChanges.stream;
  bool get isTransferring => _transferring;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscribeToRepository();
    scheduleMicrotask(() {
      if (!_disposed) unawaited(_refresh());
    });
  }

  void handleLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      _clearProjectionStreamFallback();
      _closeProjectionStream();
      unawaited(_refresh());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _closeProjectionStream();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _transferHideTimer?.cancel();
    _projectionRetryTimer?.cancel();
    await _transferSubscription?.cancel();
    await _eventsChangedSubscription?.cancel();
    _closeProjectionStream();
    await _statusChanges.close();
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    do {
      _timer?.cancel();
      _refreshing = true;
      _refreshAgain = false;
      try {
        await _pingMainDevice();
      } on CashierUnpairedException {
        await _handleUnpaired();
        _refreshing = false;
        continue;
      } catch (error) {
        _setLastErrorCode(_syncErrorCode(error));
        _setConnected(false);
        _refreshing = false;
        continue;
      }
      _unpaired = false;
      _setConnected(true);
      try {
        _setSnapshotSyncInProgress(true);
        await _syncWithMainDevice();
        await _refreshStatusDetails(clearLastError: true);
        _setConnected(true);
        await _startProjectionStream(keepConnectedOnFailure: true);
      } on CashierUnpairedException {
        await _handleUnpaired();
      } catch (error) {
        await _refreshStatusDetails(errorCode: _syncErrorCode(error));
        _setConnected(true);
      } finally {
        _setSnapshotSyncInProgress(false);
        _refreshing = false;
      }
    } while (!_disposed && _refreshAgain);
    _scheduleNextRefresh();
  }

  void _subscribeToRepository() {
    _subscribeToTransfers();
    _eventsChangedSubscription = repository.eventsChanged.listen((_) {
      if (!_disposed) unawaited(_refresh());
    });
  }

  void _subscribeToTransfers() {
    _transferSubscription = (syncTransfers ?? repository.syncTransfers).listen(
      _showTransferActivity,
    );
  }

  void _showTransferActivity(SyncTransferActivity activity) {
    if (_disposed || activity.eventCount <= 0) return;
    final previousStatus = _status;
    _transferHideTimer?.cancel();
    _connected = true;
    if (!_transferring) {
      _transferring = true;
      _notifyStatusChanged(previousStatus);
    }
    _transferHideTimer = Timer(
      _minimumSyncVisibleDuration,
      _hideTransferActivity,
    );
  }

  Future<void> _pingMainDevice() {
    final injected = pingMainDevice;
    if (injected != null) return injected();
    return _withMainPeer((client, peer) => client.pingPeer(peer.deviceId));
  }

  Future<void> _syncWithMainDevice() {
    final injected = syncWithMainDevice;
    if (injected != null) return injected();
    return _withMainPeer(
      (client, peer) => client.syncWithPeer(
        peer.deviceId,
        waitForRemoteEvents: !_shouldUseProjectionStream,
        waitTimeout: syncWaitTimeout,
      ),
    );
  }

  Future<void> _startProjectionStream({
    bool keepConnectedOnFailure = false,
  }) async {
    if (!_shouldUseProjectionStream ||
        _openingProjectionStream ||
        _projectionSubscription != null) {
      return;
    }
    _openingProjectionStream = true;
    try {
      final stream = await _openProjectionStream();
      if (_disposed) {
        _closeProjectionStream();
        return;
      }
      _closingProjectionStream = false;
      _projectionSubscription = stream.listen(
        (message) {
          unawaited(_applyProjectionMessage(message));
        },
        onError: (_) {
          _handleProjectionStreamClosed();
        },
        onDone: _handleProjectionStreamClosed,
        cancelOnError: true,
      );
      _clearProjectionStreamFallback();
      _setConnected(true);
    } on CashierUnpairedException {
      await _handleUnpaired();
    } catch (error) {
      _setLastErrorCode(_syncErrorCode(error));
      _closeProjectionStream();
      if (keepConnectedOnFailure) {
        _projectionStreamFallback = true;
        _scheduleProjectionStreamRetry();
        _setConnected(true);
      } else {
        _setConnected(false);
      }
    } finally {
      _openingProjectionStream = false;
    }
  }

  Future<Stream<Object?>> _openProjectionStream() async {
    final injected = openProjectionStream;
    if (injected != null) return injected();
    final store = repository.createSyncStore();
    final peers = await store.trustedPeers();
    TrustedPeer? peer;
    for (final candidate in peers) {
      if (candidate.baseUrl != null) {
        peer = candidate;
        break;
      }
    }
    if (peer == null) {
      throw SyncClientException('Main device is not paired.');
    }
    final client = LanSyncClient(
      store: store,
      serviceDiscovery: syncServiceDiscovery,
    );
    _projectionClient = client;
    _projectionPeerDeviceId = peer.deviceId;
    final socket = await client.openCashierProjectionStream(peer.deviceId);
    _projectionSocket = socket;
    return socket;
  }

  Future<void> _applyProjectionMessage(Object? message) async {
    try {
      final injected = applyProjectionMessage;
      if (injected != null) {
        await injected(message);
      } else {
        final peerDeviceId = _projectionPeerDeviceId;
        final client = _projectionClient;
        if (peerDeviceId == null || client == null) {
          throw SyncClientException('Projection stream is not connected.');
        }
        await client.applyCashierProjectionMessage(peerDeviceId, message);
      }
      _setConnected(true);
    } on CashierUnpairedException {
      await _handleUnpaired();
    } catch (error) {
      _setLastErrorCode(_syncErrorCode(error));
      _setConnected(true);
      unawaited(_refresh());
    }
  }

  Future<void> _handleUnpaired() async {
    _clearProjectionStreamFallback();
    _closeProjectionStream();
    await repository.markCashierUnpairBackupRequired();
    _unpaired = true;
    _setLastErrorCode('peer_unpaired');
    _setConnected(false);
  }

  void _handleProjectionStreamClosed() {
    if (_closingProjectionStream || _disposed) return;
    _projectionSubscription = null;
    _projectionSocket = null;
    _projectionClient?.close();
    _projectionClient = null;
    _projectionPeerDeviceId = null;
    if (!_disposed) unawaited(_refresh());
  }

  void _closeProjectionStream() {
    _closingProjectionStream = true;
    final subscription = _projectionSubscription;
    _projectionSubscription = null;
    unawaited(subscription?.cancel());
    final socket = _projectionSocket;
    _projectionSocket = null;
    unawaited(socket?.close());
    _projectionClient?.close();
    _projectionClient = null;
    _projectionPeerDeviceId = null;
  }

  void _clearProjectionStreamFallback() {
    _projectionRetryTimer?.cancel();
    _projectionRetryTimer = null;
    _projectionStreamFallback = false;
  }

  void _scheduleProjectionStreamRetry() {
    if (_disposed || !_usesProjectionStream) return;
    _projectionRetryTimer?.cancel();
    _projectionRetryTimer = Timer(_projectionStreamRetryDelay, () {
      _projectionRetryTimer = null;
      if (_disposed) return;
      _projectionStreamFallback = false;
      unawaited(_refresh());
    });
  }

  bool get _usesProjectionStream {
    return openProjectionStream != null ||
        (pingMainDevice == null && syncWithMainDevice == null);
  }

  bool get _shouldUseProjectionStream =>
      _usesProjectionStream && !_projectionStreamFallback;

  Future<void> _refreshStatusDetails({
    String? errorCode,
    bool clearLastError = false,
  }) async {
    final store = repository.createSyncStore();
    final counts = await store.cashierSaleOutboxCounts();
    final lastApplied = await store.lastAppliedCashierProjectionVersion();
    final peerError = await store.firstTrustedPeerLastError();
    final pending =
        (counts[CashierSaleCommandOutboxStatus.queued] ?? 0) +
        (counts[CashierSaleCommandOutboxStatus.syncing] ?? 0);
    final conflicted = counts[CashierSaleCommandOutboxStatus.conflict] ?? 0;
    if (_disposed) return;
    final previousStatus = _status;
    _pendingOutboxCount = pending;
    _conflictedOutboxCount = conflicted;
    _lastAppliedProjectionVersion = lastApplied;
    if (clearLastError) {
      _lastErrorCode = peerError;
    } else if (errorCode != null) {
      _lastErrorCode = errorCode;
    } else {
      _lastErrorCode ??= peerError;
    }
    _notifyStatusChanged(previousStatus);
  }

  Future<void> _withMainPeer(
    Future<void> Function(LanSyncClient client, TrustedPeer peer) body,
  ) async {
    final store = repository.createSyncStore();
    final peers = await store.trustedPeers();
    TrustedPeer? peer;
    for (final candidate in peers) {
      if (candidate.baseUrl != null) {
        peer = candidate;
        break;
      }
    }
    if (peer == null) {
      throw SyncClientException('Main device is not paired.');
    }
    final client = LanSyncClient(
      store: store,
      serviceDiscovery: syncServiceDiscovery,
    );
    try {
      await body(client, peer);
    } finally {
      client.close();
    }
  }

  CashierSyncStatus get _status {
    final projectionStreamConnected =
        !_usesProjectionStream || _projectionSubscription != null;
    final stale =
        !_connected ||
        (_connected && _usesProjectionStream && !projectionStreamConnected);
    final degraded =
        _connected &&
        !_unpaired &&
        (_projectionStreamFallback || stale || _lastErrorCode != null);
    return CashierSyncStatus(
      transportReachable: _connected,
      projectionStreamConnected: projectionStreamConnected,
      snapshotSyncInProgress: _transferring || _snapshotSyncInProgress,
      lastAppliedProjectionVersion: _lastAppliedProjectionVersion,
      pendingOutboxCount: _pendingOutboxCount,
      conflictedOutboxCount: _conflictedOutboxCount,
      stale: stale,
      degraded: degraded,
      lastErrorCode: _lastErrorCode,
      unpaired: _unpaired,
    );
  }

  void _setConnected(bool connected) {
    if (_disposed || _connected == connected) return;
    final previousStatus = _status;
    _connected = connected;
    _notifyStatusChanged(previousStatus);
  }

  void _setSnapshotSyncInProgress(bool inProgress) {
    if (_disposed || _snapshotSyncInProgress == inProgress) return;
    final previousStatus = _status;
    _snapshotSyncInProgress = inProgress;
    _notifyStatusChanged(previousStatus);
  }

  void _setLastErrorCode(String? code) {
    if (_disposed || _lastErrorCode == code) return;
    final previousStatus = _status;
    _lastErrorCode = code;
    _notifyStatusChanged(previousStatus);
  }

  void _hideTransferActivity() {
    if (_disposed || !_transferring) return;
    final previousStatus = _status;
    _transferHideTimer?.cancel();
    _transferHideTimer = null;
    _transferring = false;
    _notifyStatusChanged(previousStatus);
  }

  void _notifyStatusChanged(CashierSyncStatus previousStatus) {
    final current = _status;
    if (current == previousStatus || _statusChanges.isClosed) return;
    _statusChanges.add(current);
  }

  void _scheduleNextRefresh() {
    if (_disposed || pollInterval == null) return;
    _timer = Timer(pollInterval!, () {
      if (!_disposed) unawaited(_refresh());
    });
  }

  String _syncErrorCode(Object error) {
    if (error is SyncTimeoutException) return error.code;
    if (error is CashierSaleCommandRejectedException) return error.code;
    if (error is CashierUnpairedException) return 'peer_unpaired';
    return 'sync_failed';
  }
}
