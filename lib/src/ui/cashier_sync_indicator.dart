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
    this.pollInterval = const Duration(seconds: 30),
  });

  final DekonRepository repository;
  final CashierSyncOperation? pingMainDevice;
  final CashierSyncOperation? syncWithMainDevice;
  final Duration? pollInterval;

  @override
  State<CashierSyncIndicator> createState() => _CashierSyncIndicatorState();
}

class _CashierSyncIndicatorState extends State<CashierSyncIndicator>
    with SingleTickerProviderStateMixin {
  static const _size = 8.0;
  static const _minimumSyncVisibleDuration = Duration(seconds: 1);

  late final AnimationController _breathing;
  late final Animation<double> _opacity;

  var _status = _CashierSyncIndicatorStatus.disconnected;
  var _refreshing = false;
  Timer? _timer;

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
  }

  @override
  void didUpdateWidget(CashierSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _timer?.cancel();
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (_status) {
      _CashierSyncIndicatorStatus.disconnected => Colors.red.shade600,
      _CashierSyncIndicatorStatus.syncing => Colors.green.shade600,
      _CashierSyncIndicatorStatus.synced => Colors.green.shade600,
    };
    final circle = DecoratedBox(
      key: Key('cashier-sync-indicator-${_status.name}'),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    return SizedBox(
      key: const Key('cashier-sync-indicator'),
      width: _size,
      height: _size,
      child: _status == _CashierSyncIndicatorStatus.syncing
          ? FadeTransition(
              key: const Key('cashier-sync-indicator-breathing'),
              opacity: _opacity,
              child: circle,
            )
          : circle,
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _timer?.cancel();
    _refreshing = true;
    Future<void>? minimumSyncVisible;
    try {
      await _pingMainDevice();
      _setStatus(_CashierSyncIndicatorStatus.syncing);
      minimumSyncVisible = Future<void>.delayed(_minimumSyncVisibleDuration);
      await _syncWithMainDevice();
      await minimumSyncVisible;
      _setStatus(_CashierSyncIndicatorStatus.synced);
    } catch (_) {
      await minimumSyncVisible;
      _setStatus(_CashierSyncIndicatorStatus.disconnected);
    } finally {
      _refreshing = false;
      _scheduleNextRefresh();
    }
  }

  Future<void> _pingMainDevice() {
    final injected = widget.pingMainDevice;
    if (injected != null) return injected();
    return _withMainPeer((client, peer) => client.pingPeer(peer.deviceId));
  }

  Future<void> _syncWithMainDevice() {
    final injected = widget.syncWithMainDevice;
    if (injected != null) return injected();
    return _withMainPeer((client, peer) => client.syncWithPeer(peer.deviceId));
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

  void _setStatus(_CashierSyncIndicatorStatus status) {
    if (!mounted || _status == status) return;
    setState(() => _status = status);
    if (status == _CashierSyncIndicatorStatus.syncing) {
      _breathing.repeat(reverse: true);
    } else {
      _breathing.stop();
      _breathing.value = 1;
    }
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
