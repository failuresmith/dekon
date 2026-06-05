import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'report_trend_page.dart';
import 'ui_strings.dart';

enum _ReportPeriod { day, week, month, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    this.scope = ReportScope.allDevices,
  });

  final DekonRepository repository;
  final ReportScope scope;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  var _period = _ReportPeriod.day;
  var _anchorLocal = DateTime.now();
  String? _selectedCashierDeviceId;
  DateTimeRange? _customRange;
  late Future<ReportSummary> _future = _loadSummary();
  late Future<List<CashierReportFilter>> _cashiersFuture = _loadCashiers();
  StreamSubscription<void>? _eventsChangedSubscription;
  StreamSubscription<void>? _syncStateChangedSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToRepository();
  }

  @override
  void didUpdateWidget(ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _eventsChangedSubscription?.cancel();
      _syncStateChangedSubscription?.cancel();
      _future = _loadSummary();
      _cashiersFuture = _loadCashiers();
      _subscribeToRepository();
    }
  }

  @override
  void dispose() {
    _eventsChangedSubscription?.cancel();
    _syncStateChangedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReportSummary>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Reports failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summary = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.scope == ReportScope.localDevice) ...[
                        Text(
                          'Local cashier transactions',
                          key: const Key('local-device-report-scope'),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _periodSelector(summary.range),
                      if (widget.scope == ReportScope.allDevices) ...[
                        const SizedBox(height: 12),
                        _cashierSelector(),
                      ],
                      Expanded(child: Center(child: _metrics(summary))),
                      _syncStatus(summary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _periodSelector(ReportDateRange range) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _periodChip(_ReportPeriod.day, 'Day'),
            _periodChip(_ReportPeriod.week, 'Week'),
            _periodChip(_ReportPeriod.month, 'Month'),
            _periodChip(_ReportPeriod.custom, 'Custom'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              key: const Key('report-previous-period'),
              tooltip: 'Previous $_periodUnitLabel',
              onPressed: () => _shiftPeriod(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _rangeLabel(range),
                key: const Key('report-range-label'),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              key: const Key('report-next-period'),
              tooltip: 'Next $_periodUnitLabel',
              onPressed: () => _shiftPeriod(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget _periodChip(_ReportPeriod period, String label) {
    return ChoiceChip(
      key: Key('report-period-${period.name}'),
      label: Text(label),
      selected: _period == period,
      onSelected: (_) => period == _ReportPeriod.custom
          ? _pickCustomRange()
          : _setPeriod(period),
    );
  }

  Widget _metrics(ReportSummary summary) {
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final narrowWidth = (availableWidth - 12) / 2;
    final width = availableWidth >= 340 ? 156.0 : narrowWidth;
    final showInventorySignals =
        widget.scope == ReportScope.allDevices &&
        _selectedCashierDeviceId == null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                key: const Key('sales-report-metric'),
                label: UiStrings.revenue,
                value: formatMoney(summary.salesMinor),
                width: width,
                onTap: () => _showTransactions(
                  kind: TransactionHistoryKind.sale,
                  title: UiStrings.revenue,
                  range: summary.range,
                  deviceId: _selectedCashierDeviceId,
                ),
              ),
              _metric(
                key: const Key('purchases-report-metric'),
                label: UiStrings.purchases,
                value: formatMoney(summary.purchasesMinor),
                width: width,
                onTap: () => _showTransactions(
                  kind: TransactionHistoryKind.purchase,
                  title: UiStrings.purchases,
                  range: summary.range,
                  deviceId: _selectedCashierDeviceId,
                ),
              ),
              _metric(
                key: const Key('gross-margin-report-metric'),
                label: UiStrings.grossProfit,
                value: formatMoney(summary.grossMarginMinor),
                width: width,
              ),
              if (showInventorySignals)
                _metric(
                  key: const Key('low-stock-report-metric'),
                  label: UiStrings.lowStockItems,
                  value: summary.lowStockRows.length.toString(),
                  width: width,
                  onTap: () => _showLowStock(summary.lowStockRows),
                ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('reports-view-trend-button'),
            onPressed: _showTrendChart,
            icon: const Icon(Icons.stacked_bar_chart),
            label: const Text(UiStrings.viewSalesTrend),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cashierSelector() {
    return FutureBuilder<List<CashierReportFilter>>(
      future: _cashiersFuture,
      builder: (context, snapshot) {
        final cashiers = snapshot.data ?? const <CashierReportFilter>[];
        final selectedDeviceId = _selectedCashierDeviceId;
        final selectedCashierMissing =
            selectedDeviceId != null &&
            cashiers.every((cashier) => cashier.deviceId != selectedDeviceId);
        final filterItems = [
          if (selectedCashierMissing)
            CashierReportFilter(
              deviceId: selectedDeviceId,
              label: 'Selected cashier',
            ),
          ...cashiers,
        ];
        return Center(
          child: SizedBox(
            width: 280,
            child: DropdownButtonFormField<String>(
              key: const Key('cashier-report-filter'),
              initialValue: _selectedCashierDeviceId ?? '',
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Cashier device',
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('All devices')),
                for (final cashier in filterItems)
                  DropdownMenuItem(
                    value: cashier.deviceId,
                    child: Text(cashier.label),
                  ),
              ],
              onChanged: (value) => _setCashierFilter(value),
            ),
          ),
        );
      },
    );
  }

  Widget _metric({
    required Key key,
    required String label,
    required String value,
    required double width,
    VoidCallback? onTap,
  }) {
    final radius = BorderRadius.circular(8);
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: key,
          borderRadius: radius,
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: radius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _syncStatus(ReportSummary summary) {
    if (summary.unsyncedEventCount == 0) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: DecoratedBox(
        key: const Key('sync-warning'),
        decoration: BoxDecoration(
          border: Border.all(color: colors.error),
          borderRadius: BorderRadius.circular(8),
          color: colors.errorContainer.withValues(alpha: 0.35),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, color: colors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${summary.unsyncedEventCount} transactions have not synced yet. '
                  'Check Device Sync in Settings.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shiftPeriod(int direction) {
    setState(() {
      if (_period == _ReportPeriod.custom) {
        final range = _customRange;
        if (range != null) {
          final days = range.duration.inDays + 1;
          _customRange = DateTimeRange(
            start: range.start.add(Duration(days: days * direction)),
            end: range.end.add(Duration(days: days * direction)),
          );
        }
      } else {
        _anchorLocal = switch (_period) {
          _ReportPeriod.day => _anchorLocal.add(Duration(days: direction)),
          _ReportPeriod.week => _anchorLocal.add(Duration(days: 7 * direction)),
          _ReportPeriod.month => DateTime(
            _anchorLocal.year,
            _anchorLocal.month + direction,
            1,
          ),
          _ReportPeriod.custom => _anchorLocal,
        };
      }
      _future = _loadSummary();
    });
  }

  String get _periodUnitLabel {
    return switch (_period) {
      _ReportPeriod.day => 'day',
      _ReportPeriod.week => 'week',
      _ReportPeriod.month => 'month',
      _ReportPeriod.custom => 'range',
    };
  }

  Future<void> _showLowStock(List<StockReportRow> rows) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(UiStrings.lowStock),
        content: SizedBox(
          width: double.maxFinite,
          child: rows.isEmpty
              ? const Text('No low-stock products')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      title: Text(row.name),
                      trailing: Text('Qty ${row.quantity.g}'),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTransactions({
    required TransactionHistoryKind kind,
    required String title,
    required ReportDateRange range,
    String? deviceId,
  }) async {
    final entries = await widget.repository.transactionHistory(
      kind,
      range: range,
      scope: widget.scope,
      deviceId: deviceId,
      limit: null,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: entries.isEmpty
              ? const Text('No transactions')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      title: Text(formatMoney(entry.totalMinor)),
                      subtitle: Text(
                        '${_timestamp(entry.occurredAt)}\n'
                        '${_lineSummary(entry)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTrendChart() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReportTrendPage(
          repository: widget.repository,
          scope: widget.scope,
          deviceId: _selectedCashierDeviceId,
        ),
      ),
    );
  }

  Future<ReportSummary> _loadSummary() {
    return widget.repository.reportSummary(
      range: _activeRange(),
      scope: widget.scope,
      deviceId: _selectedCashierDeviceId,
    );
  }

  Future<List<CashierReportFilter>> _loadCashiers() {
    if (widget.scope != ReportScope.allDevices) return Future.value(const []);
    return widget.repository.cashierReportFilters();
  }

  Future<void> _refresh() async {
    _reload();
    await _future;
  }

  void _subscribeToRepository() {
    _eventsChangedSubscription = widget.repository.eventsChanged.listen((_) {
      if (mounted) _reload();
    });
    _syncStateChangedSubscription = widget.repository.syncStateChanged.listen((
      _,
    ) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    setState(() {
      _future = _loadSummary();
      _cashiersFuture = _loadCashiers();
    });
  }

  void _setCashierFilter(String? value) {
    setState(() {
      _selectedCashierDeviceId = value == null || value.isEmpty ? null : value;
      _future = _loadSummary();
    });
  }

  Future<void> _setPeriod(_ReportPeriod period) async {
    setState(() {
      _period = period;
      _future = _loadSummary();
    });
    await _future;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          _customRange ?? DateTimeRange(start: _dayStart(now), end: now),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = _ReportPeriod.custom;
      _customRange = picked;
      _future = _loadSummary();
    });
    await _future;
  }

  ReportDateRange _activeRange() {
    final now = _anchorLocal;
    return switch (_period) {
      _ReportPeriod.day => _dayRange(now),
      _ReportPeriod.week => _weekRange(now),
      _ReportPeriod.month => _monthRange(now),
      _ReportPeriod.custom => _customReportRange(now),
    };
  }

  ReportDateRange _dayRange(DateTime value) {
    final start = _dayStart(value);
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: start.add(const Duration(days: 1)),
    );
  }

  ReportDateRange _weekRange(DateTime value) {
    final today = _dayStart(value);
    final start = today.subtract(Duration(days: value.weekday - 1));
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: start.add(const Duration(days: 7)),
    );
  }

  ReportDateRange _monthRange(DateTime value) {
    final start = DateTime(value.year, value.month);
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: DateTime(value.year, value.month + 1),
    );
  }

  ReportDateRange _customReportRange(DateTime fallback) {
    final custom = _customRange;
    if (custom == null) return _dayRange(fallback);
    final start = _dayStart(custom.start);
    final end = _dayStart(custom.end).add(const Duration(days: 1));
    return ReportDateRange(startLocal: start, endLocalExclusive: end);
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _rangeLabel(ReportDateRange range) {
    final endInclusive = range.endLocalExclusive.subtract(
      const Duration(days: 1),
    );
    if (_period == _ReportPeriod.day) {
      if (_isSameDay(range.startLocal, DateTime.now())) return 'Today';
      return _humanDate(range.startLocal);
    }
    if (_period == _ReportPeriod.month) {
      return '${_monthName(range.startLocal.month)} ${range.startLocal.year}';
    }
    return '${_humanDate(range.startLocal)} - ${_humanDate(endInclusive)}';
  }

  String _lineSummary(TransactionHistoryEntry entry) {
    if (entry.lines.isEmpty) return 'No line details';
    return entry.lines
        .map((line) => '${line.productName} x${line.quantity.g}')
        .join(', ');
  }

  String _timestamp(DateTime dateTime) {
    return dateTime.toLocal().toString().split('.').first;
  }

  String _humanDate(DateTime dateTime) {
    return '${dateTime.day} ${_monthName(dateTime.month)} ${dateTime.year}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
