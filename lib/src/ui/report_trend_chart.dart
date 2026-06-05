import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'ui_strings.dart';

class ReportTrendChart extends StatefulWidget {
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
  State<ReportTrendChart> createState() => _ReportTrendChartState();
}

class _ReportTrendChartState extends State<ReportTrendChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(ReportTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _selectedIndex;
    if (index != null && index >= widget.buckets.length) {
      _selectedIndex = widget.buckets.isEmpty
          ? null
          : widget.buckets.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final buckets = widget.buckets;
    final maxMinor = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.maxMinor),
    );
    if (buckets.isEmpty || maxMinor == 0) {
      return Center(
        key: const Key('report-trend-empty'),
        child: Text(context.strings.noSalesPurchasesInPeriod),
      );
    }
    final selectedIndex = _selectedIndex ?? buckets.length - 1;
    final selectedBucket = buckets[selectedIndex];
    return Column(
      key: const Key('report-trend-chart'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectedBucketSummary(
          bucket: selectedBucket,
          label: _bucketLabel(selectedBucket.range.startLocal, widget.period),
        ),
        const SizedBox(height: 10),
        const _Legend(),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minBucketWidth = switch (widget.period) {
                ReportTrendPeriod.day => 48.0,
                ReportTrendPeriod.week => 52.0,
                ReportTrendPeriod.month => 56.0,
                ReportTrendPeriod.year => 58.0,
              };
              final width = math.max(
                constraints.maxWidth,
                buckets.length * minBucketWidth,
              );
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in buckets.indexed)
                        SizedBox(
                          width: width / buckets.length,
                          child: _BucketBars(
                            bucket: entry.$2,
                            period: widget.period,
                            maxMinor: maxMinor,
                            selected: entry.$1 == selectedIndex,
                            onTap: () =>
                                setState(() => _selectedIndex = entry.$1),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _bucketLabel(DateTime start, ReportTrendPeriod period) {
    return switch (period) {
      ReportTrendPeriod.day => '${start.month}/${start.day}',
      ReportTrendPeriod.week => '${start.month}/${start.day}',
      ReportTrendPeriod.month => context.strings.shortMonthName(start.month),
      ReportTrendPeriod.year => start.year.toString(),
    };
  }
}

class _SelectedBucketSummary extends StatelessWidget {
  const _SelectedBucketSummary({required this.bucket, required this.label});

  final ReportTrendBucket bucket;
  final String label;

  @override
  Widget build(BuildContext context) {
    final netMinor = bucket.salesMinor - bucket.purchasesMinor;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: DecoratedBox(
        key: ValueKey(label),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            key: const Key('report-trend-selection-summary'),
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              _SummaryText(label: context.strings.period, value: label),
              _SummaryText(
                label: context.strings.revenue,
                value: formatMoney(bucket.salesMinor),
              ),
              _SummaryText(
                label: context.strings.purchases,
                value: formatMoney(bucket.purchasesMinor),
              ),
              _SummaryText(
                label: context.strings.net,
                value: formatMoney(netMinor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LegendItem(
          color: ReportTrendChart._salesColor,
          label: context.strings.revenue,
        ),
        const SizedBox(width: 16),
        _LegendItem(
          color: ReportTrendChart._purchasesColor,
          label: context.strings.purchases,
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
    required this.selected,
    required this.onTap,
  });

  final ReportTrendBucket bucket;
  final ReportTrendPeriod period;
  final int maxMinor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _bucketLabel(context, bucket.range.startLocal, period);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: context.strings.reportTrendBucketSemantics(
        label: label,
        revenueAmount: formatMoney(bucket.salesMinor),
        purchasesAmount: formatMoney(bucket.purchasesMinor),
      ),
      child: Material(
        color: selected
            ? colors.primaryContainer.withValues(alpha: 0.35)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('report-trend-bucket-$label'),
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.primary : Colors.transparent,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                      const SizedBox(width: 4),
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
                  style: selected
                      ? Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        )
                      : Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bucketLabel(
    BuildContext context,
    DateTime start,
    ReportTrendPeriod period,
  ) {
    return switch (period) {
      ReportTrendPeriod.day => '${start.month}/${start.day}',
      ReportTrendPeriod.week => '${start.month}/${start.day}',
      ReportTrendPeriod.month => context.strings.shortMonthName(start.month),
      ReportTrendPeriod.year => start.year.toString(),
    };
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
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: height),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return SizedBox(
                  height: value.clamp(0.0, constraints.maxHeight),
                  width: double.infinity,
                  child: child,
                );
              },
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
