import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../sync/sync.dart';
import 'cashier_sync_status.dart';

typedef CashierSyncOperation = Future<void> Function();
typedef CashierProjectionStreamFactory = Future<Stream<Object?>> Function();
typedef CashierProjectionMessageHandler =
    Future<void> Function(Object? message);

class CashierSyncIndicator extends StatefulWidget {
  const CashierSyncIndicator({
    super.key,
    required this.repository,
    this.pingMainDevice,
    this.syncWithMainDevice,
    this.openProjectionStream,
    this.applyProjectionMessage,
    this.syncServiceDiscovery = const NoopSyncServiceDiscovery(),
    this.syncTransfers,
    this.onStatusChanged,
    this.pollInterval = const Duration(seconds: 1),
    this.syncWaitTimeout = const Duration(seconds: 25),
  });

  final DekonRepository repository;
  final CashierSyncOperation? pingMainDevice;
  final CashierSyncOperation? syncWithMainDevice;
  final CashierProjectionStreamFactory? openProjectionStream;
  final CashierProjectionMessageHandler? applyProjectionMessage;
  final SyncServiceDiscovery syncServiceDiscovery;
  final Stream<SyncTransferActivity>? syncTransfers;
  final ValueChanged<CashierSyncStatus>? onStatusChanged;
  final Duration? pollInterval;
  final Duration syncWaitTimeout;

  @override
  State<CashierSyncIndicator> createState() => _CashierSyncIndicatorState();
}

class _CashierSyncIndicatorState extends State<CashierSyncIndicator>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _size = 8.0;
  static const _minimumSyncVisibleDuration = Duration(seconds: 1);
  static const _projectionStreamRetryDelay = Duration(seconds: 5);

  late final AnimationController _breathing;
  late final Animation<double> _opacity;

  var _connected = false;
  var _transferring = false;
  var _snapshotSyncInProgress = false;
  var _refreshing = false;
  var _refreshAgain = false;
  var _unpaired = false;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = CurvedAnimation(
      parent: _breathing,
      curve: Curves.easeInOut,
    ).drive(Tween(begin: 0.35, end: 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
    _subscribeToRepository();
  }

  @override
  void didUpdateWidget(CashierSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _timer?.cancel();
      _transferSubscription?.cancel();
      _eventsChangedSubscription?.cancel();
      _clearProjectionStreamFallback();
      _closeProjectionStream();
      _subscribeToRepository();
      unawaited(_refresh());
    } else if (oldWidget.syncTransfers != widget.syncTransfers) {
      _transferSubscription?.cancel();
      _subscribeToTransfers();
    } else if (oldWidget.openProjectionStream != widget.openProjectionStream ||
        oldWidget.applyProjectionMessage != widget.applyProjectionMessage) {
      _clearProjectionStreamFallback();
      _closeProjectionStream();
      unawaited(_startProjectionStream());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _transferHideTimer?.cancel();
    _projectionRetryTimer?.cancel();
    _transferSubscription?.cancel();
    _eventsChangedSubscription?.cancel();
    _closeProjectionStream();
    _breathing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final visualState = _visualStateFor(status);
    final color = switch (visualState) {
      CashierSyncVisualState.disconnected => Colors.red.shade600,
      CashierSyncVisualState.syncing => Colors.green.shade600,
      CashierSyncVisualState.synced => Colors.green.shade600,
      CashierSyncVisualState.degraded => Colors.amber.shade700,
      CashierSyncVisualState.conflicted => Colors.red.shade600,
      CashierSyncVisualState.unpaired => Colors.red.shade600,
    };
    final circle = DecoratedBox(
      key: Key('cashier-sync-indicator-${visualState.name}'),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return SizedBox(
      key: const Key('cashier-sync-indicator'),
      width: _size,
      height: _size,
      child: visualState == CashierSyncVisualState.syncing
          ? FadeTransition(
              key: const Key('cashier-sync-indicator-breathing'),
              opacity: _opacity,
              child: circle,
            )
          : circle,
    );
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
    } while (mounted && _refreshAgain);
    _scheduleNextRefresh();
  }

  void _subscribeToRepository() {
    _subscribeToTransfers();
    _eventsChangedSubscription = widget.repository.eventsChanged.listen((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  void _subscribeToTransfers() {
    _transferSubscription =
        (widget.syncTransfers ?? widget.repository.syncTransfers).listen(
          _showTransferActivity,
        );
  }

  void _showTransferActivity(SyncTransferActivity activity) {
    if (!mounted || activity.eventCount <= 0) return;
    final previousStatus = _status;
    _transferHideTimer?.cancel();
    _connected = true;
    if (!_transferring) {
      setState(() => _transferring = true);
      _breathing.repeat(reverse: true);
      _notifyStatusChanged(previousStatus);
    }
    _transferHideTimer = Timer(
      _minimumSyncVisibleDuration,
      _hideTransferActivity,
    );
  }

  Future<void> _pingMainDevice() {
    final injected = widget.pingMainDevice;
    if (injected != null) return injected();
    return _withMainPeer((client, peer) => client.pingPeer(peer.deviceId));
  }

  Future<void> _syncWithMainDevice() {
    final injected = widget.syncWithMainDevice;
    if (injected != null) return injected();
    return _withMainPeer(
      (client, peer) => client.syncWithPeer(
        peer.deviceId,
        waitForRemoteEvents: !_shouldUseProjectionStream,
        waitTimeout: widget.syncWaitTimeout,
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
      if (!mounted) {
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
    final injected = widget.openProjectionStream;
    if (injected != null) return injected();
    final store = widget.repository.createSyncStore();
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
      serviceDiscovery: widget.syncServiceDiscovery,
    );
    _projectionClient = client;
    _projectionPeerDeviceId = peer.deviceId;
    final socket = await client.openCashierProjectionStream(peer.deviceId);
    _projectionSocket = socket;
    return socket;
  }

  Future<void> _applyProjectionMessage(Object? message) async {
    try {
      final injected = widget.applyProjectionMessage;
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
    await widget.repository.markCashierUnpairBackupRequired();
    _unpaired = true;
    _setLastErrorCode('peer_unpaired');
    _setConnected(false);
  }

  void _handleProjectionStreamClosed() {
    if (_closingProjectionStream || !mounted) return;
    _projectionSubscription = null;
    _projectionSocket = null;
    _projectionClient?.close();
    _projectionClient = null;
    _projectionPeerDeviceId = null;
    if (mounted) unawaited(_refresh());
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
    if (!mounted || !_usesProjectionStream) return;
    _projectionRetryTimer?.cancel();
    _projectionRetryTimer = Timer(_projectionStreamRetryDelay, () {
      _projectionRetryTimer = null;
      if (!mounted) return;
      _projectionStreamFallback = false;
      unawaited(_refresh());
    });
  }

  bool get _usesProjectionStream {
    return widget.openProjectionStream != null ||
        (widget.pingMainDevice == null && widget.syncWithMainDevice == null);
  }

  bool get _shouldUseProjectionStream =>
      _usesProjectionStream && !_projectionStreamFallback;

  Future<void> _refreshStatusDetails({
    String? errorCode,
    bool clearLastError = false,
  }) async {
    final store = widget.repository.createSyncStore();
    final counts = await store.cashierSaleOutboxCounts();
    final lastApplied = await store.lastAppliedCashierProjectionVersion();
    final peerError = await store.firstTrustedPeerLastError();
    final pending =
        (counts[CashierSaleCommandOutboxStatus.queued] ?? 0) +
        (counts[CashierSaleCommandOutboxStatus.syncing] ?? 0);
    final conflicted = counts[CashierSaleCommandOutboxStatus.conflict] ?? 0;
    if (!mounted) return;
    final previousStatus = _status;
    setState(() {
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
    });
    _notifyStatusChanged(previousStatus);
  }

  Future<void> _withMainPeer(
    Future<void> Function(LanSyncClient client, TrustedPeer peer) body,
  ) async {
    final store = widget.repository.createSyncStore();
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
      serviceDiscovery: widget.syncServiceDiscovery,
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

  CashierSyncVisualState _visualStateFor(CashierSyncStatus status) {
    if (_transferring) return CashierSyncVisualState.syncing;
    if (status.unpaired) return CashierSyncVisualState.unpaired;
    if (status.hasOutboxConflict) return CashierSyncVisualState.conflicted;
    if (!status.transportReachable) {
      return CashierSyncVisualState.disconnected;
    }
    if (status.stale || status.degraded || !status.projectionStreamConnected) {
      return CashierSyncVisualState.degraded;
    }
    return CashierSyncVisualState.synced;
  }

  void _setConnected(bool connected) {
    if (!mounted || _connected == connected) return;
    final previousStatus = _status;
    setState(() => _connected = connected);
    _notifyStatusChanged(previousStatus);
  }

  void _setSnapshotSyncInProgress(bool inProgress) {
    if (!mounted || _snapshotSyncInProgress == inProgress) return;
    final previousStatus = _status;
    setState(() => _snapshotSyncInProgress = inProgress);
    _notifyStatusChanged(previousStatus);
  }

  void _setLastErrorCode(String? code) {
    if (!mounted || _lastErrorCode == code) return;
    final previousStatus = _status;
    setState(() => _lastErrorCode = code);
    _notifyStatusChanged(previousStatus);
  }

  String _syncErrorCode(Object error) {
    if (error is SyncTimeoutException) return error.code;
    if (error is CashierSaleCommandRejectedException) return error.code;
    if (error is CashierUnpairedException) return 'peer_unpaired';
    return 'sync_failed';
  }

  void _hideTransferActivity() {
    if (!mounted || !_transferring) return;
    final previousStatus = _status;
    _transferHideTimer?.cancel();
    _transferHideTimer = null;
    _breathing.stop();
    _breathing.value = 1;
    setState(() => _transferring = false);
    _notifyStatusChanged(previousStatus);
  }

  void _notifyStatusChanged(CashierSyncStatus previousStatus) {
    final status = _status;
    if (status == previousStatus) return;
    widget.onStatusChanged?.call(status);
  }

  void _scheduleNextRefresh() {
    final pollInterval = widget.pollInterval;
    if (!mounted || pollInterval == null) return;
    _timer = Timer(pollInterval, () {
      if (mounted) unawaited(_refresh());
    });
  }
}
