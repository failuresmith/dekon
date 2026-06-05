import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../sync/sync.dart';

typedef CashierSyncOperation = Future<void> Function();

class CashierSyncIndicator extends StatefulWidget {
  const CashierSyncIndicator({
    super.key,
    required this.repository,
    this.pingMainDevice,
    this.syncWithMainDevice,
    this.syncTransfers,
    this.pollInterval = const Duration(seconds: 1),
    this.syncWaitTimeout = const Duration(seconds: 25),
  });

  final DekonRepository repository;
  final CashierSyncOperation? pingMainDevice;
  final CashierSyncOperation? syncWithMainDevice;
  final Stream<SyncTransferActivity>? syncTransfers;
  final Duration? pollInterval;
  final Duration syncWaitTimeout;

  @override
  State<CashierSyncIndicator> createState() => _CashierSyncIndicatorState();
}

class _CashierSyncIndicatorState extends State<CashierSyncIndicator>
    with SingleTickerProviderStateMixin {
  static const _size = 8.0;
  static const _minimumSyncVisibleDuration = Duration(seconds: 1);

  late final AnimationController _breathing;
  late final Animation<double> _opacity;

  var _connected = false;
  var _transferring = false;
  var _refreshing = false;
  var _refreshAgain = false;
  Timer? _timer;
  Timer? _transferHideTimer;
  StreamSubscription<SyncTransferActivity>? _transferSubscription;
  StreamSubscription<void>? _eventsChangedSubscription;

  @override
  void initState() {
    super.initState();
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
      _subscribeToRepository();
      unawaited(_refresh());
    } else if (oldWidget.syncTransfers != widget.syncTransfers) {
      _transferSubscription?.cancel();
      _subscribeToTransfers();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _transferHideTimer?.cancel();
    _transferSubscription?.cancel();
    _eventsChangedSubscription?.cancel();
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final color = switch (status) {
      _CashierSyncIndicatorStatus.disconnected => Colors.red.shade600,
      _CashierSyncIndicatorStatus.syncing => Colors.green.shade600,
      _CashierSyncIndicatorStatus.synced => Colors.green.shade600,
    };
    final circle = DecoratedBox(
      key: Key('cashier-sync-indicator-${status.name}'),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return SizedBox(
      key: const Key('cashier-sync-indicator'),
      width: _size,
      height: _size,
      child: status == _CashierSyncIndicatorStatus.syncing
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
        _setConnected(true);
        await _syncWithMainDevice();
        _setConnected(true);
      } catch (_) {
        _setConnected(false);
      } finally {
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
    _transferHideTimer?.cancel();
    _connected = true;
    if (!_transferring) {
      setState(() => _transferring = true);
      _breathing.repeat(reverse: true);
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
        waitForRemoteEvents: true,
        waitTimeout: widget.syncWaitTimeout,
      ),
    );
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
    final client = LanSyncClient(store: store);
    try {
      await body(client, peer);
    } finally {
      client.close();
    }
  }

  _CashierSyncIndicatorStatus get _status {
    if (_transferring) return _CashierSyncIndicatorStatus.syncing;
    return _connected
        ? _CashierSyncIndicatorStatus.synced
        : _CashierSyncIndicatorStatus.disconnected;
  }

  void _setConnected(bool connected) {
    if (!mounted || _connected == connected) return;
    setState(() => _connected = connected);
  }

  void _hideTransferActivity() {
    if (!mounted || !_transferring) return;
    _transferHideTimer?.cancel();
    _transferHideTimer = null;
    _breathing.stop();
    _breathing.value = 1;
    setState(() => _transferring = false);
  }

  void _scheduleNextRefresh() {
    final pollInterval = widget.pollInterval;
    if (!mounted || pollInterval == null) return;
    _timer = Timer(pollInterval, () {
      if (mounted) unawaited(_refresh());
    });
  }
}

enum _CashierSyncIndicatorStatus { disconnected, syncing, synced }
