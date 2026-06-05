import 'package:flutter/material.dart';

import '../application/application.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final DekonRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<ReportSummary> _future = widget.repository.reportSummary();

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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Reports',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              _status(summary),
              const SizedBox(height: 16),
              _metrics(summary),
              const SizedBox(height: 16),
              Text('Low Stock', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (summary.lowStockRows.isEmpty)
                const Text('No low-stock products')
              else
                for (final row in summary.lowStockRows)
                  ListTile(
                    title: Text(row.name),
                    subtitle: Text('Qty ${row.quantity.g}'),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _status(ReportSummary summary) {
    final lastSync = summary.lastSyncAt?.toLocal().toString() ?? 'Never';
    return Text(
      'Unsynced events: ${summary.unsyncedEventCount} - Last sync: $lastSync',
      key: const Key('sync-status'),
    );
  }

  Widget _metrics(ReportSummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowWidth = (constraints.maxWidth - 12) / 2;
        final cardWidth = constraints.maxWidth >= 340 ? 156.0 : narrowWidth;
        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _metric(
                'Daily Sales',
                formatMoney(summary.dailySalesMinor),
                cardWidth,
              ),
              _metric(
                'Purchases',
                formatMoney(summary.dailyPurchasesMinor),
                cardWidth,
              ),
              _metric(
                'Gross Margin',
                formatMoney(summary.grossMarginMinor),
                cardWidth,
              ),
              _metric(
                'Low Stock',
                summary.lowStockRows.length.toString(),
                cardWidth,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
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
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.reportSummary();
    });
    await _future;
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
