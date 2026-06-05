import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/application.dart';

class ReportTrendChart extends StatelessWidget {
  const ReportTrendChart({
    super.key,
    required this.buckets,
    required this.period,
  });

  final List<ReportTrendBucket> buckets;
  final ReportTrendPeriod period;

  static const _salesColor = Color(0xFF2E7D32);
  static const _purchasesColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final maxMinor = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.maxMinor),
    );
    if (buckets.isEmpty || maxMinor == 0) {
      return const Center(
        key: Key('report-trend-empty'),
        child: Text('No sales or purchases in this period'),
      );
    }
    return Column(
      key: const Key('report-trend-chart'),
      children: [
        const _Legend(),
        const SizedBox(height: 12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final bucket in buckets)
                Expanded(
                  child: _BucketBars(
                    bucket: bucket,
                    period: period,
                    maxMinor: maxMinor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendItem(color: ReportTrendChart._salesColor, label: 'Sales'),
        SizedBox(width: 16),
        _LegendItem(
          color: ReportTrendChart._purchasesColor,
          label: 'Purchases',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: 10),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _BucketBars extends StatelessWidget {
  const _BucketBars({
    required this.bucket,
    required this.period,
    required this.maxMinor,
  });

  final ReportTrendBucket bucket;
  final ReportTrendPeriod period;
  final int maxMinor;

  @override
  Widget build(BuildContext context) {
    final label = _bucketLabel(bucket.range.startLocal, period);
    return Semantics(
      label:
          '$label sales ${formatMoney(bucket.salesMinor)} purchases '
          '${formatMoney(bucket.purchasesMinor)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Bar(
                    valueMinor: bucket.salesMinor,
                    maxMinor: maxMinor,
                    color: ReportTrendChart._salesColor,
                  ),
                  const SizedBox(width: 3),
                  _Bar(
                    valueMinor: bucket.purchasesMinor,
                    maxMinor: maxMinor,
                    color: ReportTrendChart._purchasesColor,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  String _bucketLabel(DateTime start, ReportTrendPeriod period) {
    return switch (period) {
      ReportTrendPeriod.day => '${start.month}/${start.day}',
      ReportTrendPeriod.week => '${start.month}/${start.day}',
      ReportTrendPeriod.month => _monthName(start.month),
      ReportTrendPeriod.year => start.year.toString(),
    };
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.valueMinor,
    required this.maxMinor,
    required this.color,
  });

  final int valueMinor;
  final int maxMinor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawHeight = constraints.maxHeight * valueMinor / maxMinor;
          final height = valueMinor == 0 ? 0.0 : math.max(4.0, rawHeight);
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
