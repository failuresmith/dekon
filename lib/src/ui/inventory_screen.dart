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
          trailing: IconButton(
            key: Key('edit-${product.productId}'),
            tooltip: 'Edit product',
            onPressed: () => _edit(product),
            icon: const Icon(Icons.edit),
          ),
        ),
      ),
    );
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
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
