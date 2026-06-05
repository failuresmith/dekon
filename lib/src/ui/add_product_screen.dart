import 'package:flutter/material.dart';

import '../application/application.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key, required this.repository});

  final DekonRepository repository;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _sku = TextEditingController();
  final _salePrice = TextEditingController(text: '0.00');
  final _cost = TextEditingController(text: '0.00');
  final _initialStock = TextEditingController(text: '0');
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _sku.dispose();
    _salePrice.dispose();
    _cost.dispose();
    _initialStock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Add Product', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                key: const Key('add-product-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _required,
              ),
              TextFormField(
                key: const Key('add-product-barcode'),
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              TextFormField(
                key: const Key('add-product-sku'),
                controller: _sku,
                decoration: const InputDecoration(
                  labelText: 'SKU - Internal Product Code',
                ),
              ),
              TextFormField(
                key: const Key('add-product-sale-price'),
                controller: _salePrice,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sale price'),
                validator: _money,
              ),
              TextFormField(
                key: const Key('add-product-cost'),
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Purchase cost'),
                validator: _money,
              ),
              TextFormField(
                key: const Key('add-product-initial-stock'),
                controller: _initialStock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Initial stock'),
                validator: _quantity,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('create-product'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(_saving ? 'Saving' : 'Create Product'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final product = await widget.repository.createProduct(
        name: _name.text,
        barcode: _barcode.text,
        sku: _sku.text,
        salePriceMinor: parseMoneyMinor(_salePrice.text),
        purchaseCostMinor: parseMoneyMinor(_cost.text),
      );
      final stock = double.parse(_initialStock.text.trim());
      if (stock > 0) {
        await widget.repository.recordInventoryAdjustment(
          product: product,
          quantityDelta: stock,
        );
      }
      _reset();
      _message('Product saved');
    } catch (error) {
      _message('Product save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    _name.clear();
    _barcode.clear();
    _sku.clear();
    _salePrice.text = '0.00';
    _cost.text = '0.00';
    _initialStock.text = '0';
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }

  String? _money(String? value) {
    try {
      parseMoneyMinor(value ?? '');
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _quantity(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0 || !parsed.isFinite) {
      return 'Enter a valid non-negative quantity.';
    }
    return null;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
