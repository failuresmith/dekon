import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';

typedef CashierConnectionCheck = Future<bool> Function();

class MainCashierConnectionIndicator extends StatefulWidget {
  const MainCashierConnectionIndicator({
    super.key,
    required this.repository,
    this.isCashierConnected,
    this.pollInterval = const Duration(seconds: 15),
  });

  final DekonRepository repository;
  final CashierConnectionCheck? isCashierConnected;
  final Duration? pollInterval;

  @override
  State<MainCashierConnectionIndicator> createState() =>
      _MainCashierConnectionIndicatorState();
}

class _MainCashierConnectionIndicatorState
    extends State<MainCashierConnectionIndicator>
    with SingleTickerProviderStateMixin {
  static const _size = 8.0;
  static const _minimumVisibleDuration = Duration(seconds: 1);

  late final AnimationController _breathing;
  late final Animation<double> _opacity;

  var _refreshing = false;
  var _visible = false;
  Timer? _timer;
  Timer? _hideTimer;
  DateTime? _visibleSince;

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
  void didUpdateWidget(MainCashierConnectionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _timer?.cancel();
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hideTimer?.cancel();
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('main-cashier-connection-indicator'),
      width: _size,
      height: _size,
      child: FadeTransition(
        key: const Key('main-cashier-connection-indicator-breathing'),
        opacity: _opacity,
        child: DecoratedBox(
          key: const Key('main-cashier-connection-indicator-connected'),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _timer?.cancel();
    _refreshing = true;
    try {
      final connected = await _isCashierConnected();
      if (connected) {
        _showConnected();
      } else {
        _hideConnected();
      }
    } finally {
      _refreshing = false;
      _scheduleNextRefresh();
    }
  }

  Future<bool> _isCashierConnected() {
    final injected = widget.isCashierConnected;
    if (injected != null) return injected();
    return widget.repository.hasRecentlyConnectedCashier();
  }

  void _showConnected() {
    if (!mounted) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_visible) {
      _visibleSince = DateTime.now();
      setState(() => _visible = true);
    }
    if (!_breathing.isAnimating) _breathing.repeat(reverse: true);
  }

  void _hideConnected() {
    if (!mounted || !_visible) return;
    final visibleSince = _visibleSince;
    final remaining = visibleSince == null
        ? Duration.zero
        : _minimumVisibleDuration - DateTime.now().difference(visibleSince);
    if (remaining > Duration.zero) {
      _hideTimer?.cancel();
      _hideTimer = Timer(remaining, _hideConnectedNow);
      return;
    }
    _hideConnectedNow();
  }

  void _hideConnectedNow() {
    if (!mounted || !_visible) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    _visibleSince = null;
    _breathing.stop();
    _breathing.value = 1;
    setState(() => _visible = false);
  }

  void _scheduleNextRefresh() {
    final pollInterval = widget.pollInterval;
    if (!mounted || pollInterval == null) return;
    _timer = Timer(pollInterval, () {
      if (mounted) unawaited(_refresh());
    });
  }
}
