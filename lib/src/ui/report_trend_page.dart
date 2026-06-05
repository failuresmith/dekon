import 'package:flutter/material.dart';

import '../application/application.dart';
import 'report_trend_chart.dart';
import 'ui_strings.dart';

class ReportTrendPage extends StatefulWidget {
  const ReportTrendPage({
    super.key,
    required this.repository,
    required this.scope,
    this.deviceId,
  });

  final DekonRepository repository;
  final ReportScope scope;
  final String? deviceId;

  @override
  State<ReportTrendPage> createState() => _ReportTrendPageState();
}

class _ReportTrendPageState extends State<ReportTrendPage> {
  var _period = ReportTrendPeriod.day;
  late Future<List<ReportTrendBucket>> _future = _loadTrend();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Trend')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final period in ReportTrendPeriod.values)
                    ChoiceChip(
                      key: Key('report-trend-period-${period.name}'),
                      label: Text(_periodLabel(period)),
                      selected: _period == period,
                      onSelected: (_) => _setPeriod(period),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _windowLabel,
                key: const Key('report-trend-window-label'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Expanded(child: _trendBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trendBody() {
    return FutureBuilder<List<ReportTrendBucket>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Chart failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final buckets = snapshot.requireData;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ReportTrendChart(buckets: buckets, period: _period),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: _trendSummary(buckets),
              child: Text(
                _trendSummary(buckets),
                key: const Key('report-trend-text-summary'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<List<ReportTrendBucket>> _loadTrend() {
    return widget.repository.reportTrend(
      period: _period,
      scope: widget.scope,
      deviceId: widget.deviceId,
    );
  }

  void _setPeriod(ReportTrendPeriod period) {
    setState(() {
      _period = period;
      _future = _loadTrend();
    });
  }

  String _periodLabel(ReportTrendPeriod period) {
    return switch (period) {
      ReportTrendPeriod.day => 'Day',
      ReportTrendPeriod.week => 'Week',
      ReportTrendPeriod.month => 'Month',
      ReportTrendPeriod.year => 'Year',
    };
  }

  String _trendSummary(List<ReportTrendBucket> buckets) {
    final revenue = buckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.salesMinor,
    );
    final purchases = buckets.fold<int>(
      0,
      (sum, bucket) => sum + bucket.purchasesMinor,
    );
    if (revenue == 0 && purchases == 0) {
      return 'No sales or purchases in $_windowLabel.';
    }
    final net = revenue - purchases;
    return 'Sales trend for $_windowLabel. '
        '${UiStrings.revenue}: ${formatMoney(revenue)}. '
        '${UiStrings.purchases}: ${formatMoney(purchases)}. '
        'Net: ${formatMoney(net)}.';
  }

  String get _windowLabel {
    return switch (_period) {
      ReportTrendPeriod.day => 'Last 7 days',
      ReportTrendPeriod.week => 'Last 8 weeks',
      ReportTrendPeriod.month => 'Last 12 months',
      ReportTrendPeriod.year => 'Last 5 years',
    };
  }
}
