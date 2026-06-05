import 'package:flutter/material.dart';

import '../application/application.dart';
import 'product_form_dialog.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.repository});

  final DekonRepository repository;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<ProductSummary>> _future = widget.repository.products();
  final _busyProductIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProductSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Inventory failed: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.requireData
            .where((product) => product.active)
            .toList(growable: false);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Inventory',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              if (products.isEmpty)
                const Text('No products')
              else
                for (final product in products) _productRow(product),
            ],
          ),
        );
      },
    );
  }

  Widget _productRow(ProductSummary product) {
    final busy = _busyProductIds.contains(product.productId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          title: Text(product.name),
          subtitle: Text('Stock ${product.quantity.g}'),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                key: Key('stock-decrease-${product.productId}'),
                tooltip: 'Decrease stock',
                onPressed: busy ? null : () => _adjust(product, -1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                key: Key('stock-increase-${product.productId}'),
                tooltip: 'Increase stock',
                onPressed: busy ? null : () => _adjust(product, 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                key: Key('edit-${product.productId}'),
                tooltip: 'Edit product',
                onPressed: busy ? null : () => _edit(product),
                icon: const Icon(Icons.edit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _adjust(ProductSummary product, double delta) async {
    if (product.quantity + delta < 0) {
      _message('Stock cannot be reduced below 0.');
      return;
    }
    setState(() => _busyProductIds.add(product.productId));
    try {
      await widget.repository.recordInventoryAdjustment(
        product: product,
        quantityDelta: delta,
      );
      await _refresh();
    } catch (error) {
      _message('Stock update failed: $error');
    } finally {
      if (mounted) setState(() => _busyProductIds.remove(product.productId));
    }
  }

  Future<void> _edit(ProductSummary product) async {
    await showProductFormDialog(
      context: context,
      repository: widget.repository,
      product: product,
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.repository.products();
    });
    await _future;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
