import 'package:flutter/material.dart';

import '../application/application.dart';
import 'report_trend_chart.dart';

class ReportTrendDialog extends StatefulWidget {
  const ReportTrendDialog({
    super.key,
    required this.repository,
    required this.scope,
    this.deviceId,
  });

  final DekonRepository repository;
  final ReportScope scope;
  final String? deviceId;

  @override
  State<ReportTrendDialog> createState() => _ReportTrendDialogState();
}

class _ReportTrendDialogState extends State<ReportTrendDialog> {
  var _period = ReportTrendPeriod.day;
  late Future<List<ReportTrendBucket>> _future = _loadTrend();

  @override
  Widget build(BuildContext context) {
    final chartHeight = (MediaQuery.sizeOf(context).height * 0.5)
        .clamp(180.0, 260.0)
        .toDouble();
    return Dialog(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sales vs Purchases',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
                SizedBox(height: chartHeight, child: _trendBody()),
              ],
            ),
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
        return ReportTrendChart(buckets: snapshot.requireData, period: _period);
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

  String get _windowLabel {
    return switch (_period) {
      ReportTrendPeriod.day => 'Last 7 days',
      ReportTrendPeriod.week => 'Last 8 weeks',
      ReportTrendPeriod.month => 'Last 12 months',
      ReportTrendPeriod.year => 'Last 5 years',
    };
  }
}
