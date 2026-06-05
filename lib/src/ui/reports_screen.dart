import 'package:flutter/material.dart';

import '../application/application.dart';

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
  DateTimeRange? _customRange;
  late Future<ReportSummary> _future = _loadSummary();

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
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (widget.scope == ReportScope.localDevice) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Transactions recorded on this device',
                          key: const Key('local-device-report-scope'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _periodSelector(summary.range),
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
        Text(
          _rangeLabel(range),
          key: const Key('report-range-label'),
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
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
    final showInventorySignals = widget.scope == ReportScope.allDevices;
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          _metric(
            key: const Key('sales-report-metric'),
            label: _salesLabel,
            value: formatMoney(summary.salesMinor),
            width: width,
            onTap: () => _showTransactions(
              kind: TransactionHistoryKind.sale,
              title: _salesLabel,
              range: summary.range,
            ),
          ),
          _metric(
            key: const Key('purchases-report-metric'),
            label: 'Purchases',
            value: formatMoney(summary.purchasesMinor),
            width: width,
            onTap: () => _showTransactions(
              kind: TransactionHistoryKind.purchase,
              title: 'Purchases',
              range: summary.range,
            ),
          ),
          _metric(
            key: const Key('gross-margin-report-metric'),
            label: 'Gross Margin',
            value: formatMoney(summary.grossMarginMinor),
            width: width,
          ),
          if (showInventorySignals)
            _metric(
              key: const Key('low-stock-report-metric'),
              label: 'Low Stock',
              value: summary.lowStockRows.length.toString(),
              width: width,
              onTap: () => _showLowStock(summary.lowStockRows),
            ),
        ],
      ),
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
    final lastSync = summary.lastSyncAt == null
        ? 'Never'
        : _timestamp(summary.lastSyncAt!);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: Wrap(
          key: const Key('sync-status'),
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('Unsynced events: ${summary.unsyncedEventCount}'),
            Text('Last sync: $lastSync'),
          ],
        ),
      ),
    );
  }

  Future<void> _showLowStock(List<StockReportRow> rows) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Low Stock'),
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
  }) async {
    final entries = await widget.repository.transactionHistory(
      kind,
      range: range,
      scope: widget.scope,
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

  Future<ReportSummary> _loadSummary() {
    return widget.repository.reportSummary(
      range: _activeRange(),
      scope: widget.scope,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSummary();
    });
    await _future;
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
    final now = DateTime.now();
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

  String get _salesLabel {
    return _period == _ReportPeriod.day ? 'Daily Sales' : 'Sales';
  }

  String get _title {
    return widget.scope == ReportScope.localDevice
        ? 'This Device Reports'
        : 'Reports';
  }

  String _rangeLabel(ReportDateRange range) {
    final endInclusive = range.endLocalExclusive.subtract(
      const Duration(days: 1),
    );
    if (_period == _ReportPeriod.day) return _date(range.startLocal);
    if (_period == _ReportPeriod.month) {
      return '${range.startLocal.year}-${range.startLocal.month.p2}';
    }
    return '${_date(range.startLocal)} - ${_date(endInclusive)}';
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

  String _date(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.p2}-${dateTime.day.p2}';
  }
}

extension on int {
  String get p2 => toString().padLeft(2, '0');
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
