import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../sync/sync.dart';
import 'cashier_sync_controller.dart';
import 'cashier_sync_status.dart';

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

  late final AnimationController _breathing;
  late final Animation<double> _opacity;
  late CashierSyncController _controller;
  StreamSubscription<CashierSyncStatus>? _statusSubscription;
  var _status = CashierSyncStatus.disconnected;

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
    _createController();
  }

  @override
  void didUpdateWidget(CashierSyncIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.pingMainDevice != widget.pingMainDevice ||
        oldWidget.syncWithMainDevice != widget.syncWithMainDevice ||
        oldWidget.openProjectionStream != widget.openProjectionStream ||
        oldWidget.applyProjectionMessage != widget.applyProjectionMessage ||
        oldWidget.syncServiceDiscovery != widget.syncServiceDiscovery ||
        oldWidget.syncTransfers != widget.syncTransfers ||
        oldWidget.pollInterval != widget.pollInterval ||
        oldWidget.syncWaitTimeout != widget.syncWaitTimeout) {
      _replaceController();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSubscription?.cancel();
    unawaited(_controller.dispose());
    _breathing.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.handleLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    final visualState = _visualStateFor(_status);
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

  void _createController() {
    _controller = CashierSyncController(
      repository: widget.repository,
      pingMainDevice: widget.pingMainDevice,
      syncWithMainDevice: widget.syncWithMainDevice,
      openProjectionStream: widget.openProjectionStream,
      applyProjectionMessage: widget.applyProjectionMessage,
      syncServiceDiscovery: widget.syncServiceDiscovery,
      syncTransfers: widget.syncTransfers,
      pollInterval: widget.pollInterval,
      syncWaitTimeout: widget.syncWaitTimeout,
    );
    _status = _controller.status;
    _statusSubscription = _controller.statusChanges.listen(_setStatus);
    _controller.start();
  }

  void _replaceController() {
    _statusSubscription?.cancel();
    unawaited(_controller.dispose());
    _createController();
    if (mounted) setState(() {});
  }

  void _setStatus(CashierSyncStatus status) {
    if (!mounted || _status == status) return;
    final previousVisualState = _visualStateFor(_status);
    setState(() => _status = status);
    final visualState = _visualStateFor(status);
    _syncBreathingAnimation(previousVisualState, visualState);
    widget.onStatusChanged?.call(status);
  }

  void _syncBreathingAnimation(
    CashierSyncVisualState previous,
    CashierSyncVisualState current,
  ) {
    if (current == CashierSyncVisualState.syncing &&
        previous != CashierSyncVisualState.syncing) {
      _breathing.repeat(reverse: true);
    } else if (previous == CashierSyncVisualState.syncing &&
        current != CashierSyncVisualState.syncing) {
      _breathing.stop();
      _breathing.value = 1;
    }
  }

  CashierSyncVisualState _visualStateFor(CashierSyncStatus status) {
    if (_controller.isTransferring) return CashierSyncVisualState.syncing;
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
}
