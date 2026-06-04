import 'package:flutter/material.dart';

import '../application/application.dart';
import 'product_form_dialog.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repository});

  final DekonRepository repository;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<_ReportsData> _future = _load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Reports failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _status(data.summary),
              const SizedBox(height: 12),
              _metrics(data.summary),
              const SizedBox(height: 16),
              Text('Stock', style: Theme.of(context).textTheme.titleLarge),
              if (data.summary.stockRows.isEmpty) const Text('No stock yet'),
              for (final row in data.summary.stockRows)
                ListTile(
                  title: Text(row.name),
                  subtitle: Text('Qty ${row.quantity.g}'),
                ),
              const SizedBox(height: 16),
              Text('Products', style: Theme.of(context).textTheme.titleLarge),
              for (final product in data.products)
                ListTile(
                  title: Text(product.name),
                  subtitle: Text(
                    '${product.barcode ?? 'No barcode'} - ${product.active ? 'Active' : 'Inactive'}',
                  ),
                  trailing: IconButton(
                    key: Key('edit-${product.productId}'),
                    tooltip: 'Edit product',
                    onPressed: () => _edit(product),
                    icon: const Icon(Icons.edit),
                  ),
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
      'Unsynced events: ${summary.unsyncedEventCount} • Last sync: $lastSync',
      key: const Key('sync-status'),
    );
  }

  Widget _metrics(ReportSummary summary) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metric('Daily sales', formatMoney(summary.dailySalesMinor)),
        _metric('Daily purchases', formatMoney(summary.dailyPurchasesMinor)),
        _metric('Gross margin', formatMoney(summary.grossMarginMinor)),
        _metric('Low stock', summary.lowStockRows.length.toString()),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return SizedBox(
      width: 152,
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

  Future<_ReportsData> _load() async {
    final summary = await widget.repository.reportSummary();
    final products = await widget.repository.products();
    return _ReportsData(summary: summary, products: products);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _edit(ProductSummary product) async {
    await showProductFormDialog(
      context: context,
      repository: widget.repository,
      product: product,
    );
    await _refresh();
  }
}

class _ReportsData {
  const _ReportsData({required this.summary, required this.products});

  final ReportSummary summary;
  final List<ProductSummary> products;
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
