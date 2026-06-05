import 'package:flutter/material.dart';

import '../application/application.dart';

Future<ProductSummary?> showProductFormDialog({
  required BuildContext context,
  required DekonRepository repository,
  ProductSummary? product,
  String? initialBarcode,
}) {
  return showDialog<ProductSummary?>(
    context: context,
    builder: (context) => _ProductFormDialog(
      repository: repository,
      product: product,
      initialBarcode: initialBarcode,
    ),
  );
}

class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({
    required this.repository,
    this.product,
    this.initialBarcode,
  });

  final DekonRepository repository;
  final ProductSummary? product;
  final String? initialBarcode;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _sku;
  late final TextEditingController _salePrice;
  late final TextEditingController _cost;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _barcode = TextEditingController(
      text: product?.barcode ?? widget.initialBarcode ?? '',
    );
    _sku = TextEditingController(text: product?.sku ?? '');
    _salePrice = TextEditingController(
      text: product == null ? '0.00' : formatMoney(product.salePriceMinor),
    );
    _cost = TextEditingController(
      text: product == null ? '0.00' : formatMoney(product.purchaseCostMinor),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _sku.dispose();
    _salePrice.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return AlertDialog(
      title: Text(editing ? 'Edit Product' : 'Create Product'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('product-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: _required,
              ),
              TextFormField(
                key: const Key('product-barcode'),
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'Barcode'),
              ),
              TextFormField(
                controller: _sku,
                decoration: const InputDecoration(
                  labelText: 'SKU - Internal Product Code',
                ),
              ),
              TextFormField(
                key: const Key('product-sale-price'),
                controller: _salePrice,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sale price'),
                validator: _money,
              ),
              TextFormField(
                key: const Key('product-cost'),
                controller: _cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Purchase cost'),
                validator: _money,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton.icon(
            onPressed: _saving ? null : _deactivate,
            icon: const Icon(Icons.block),
            label: const Text('Deactivate'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('save-product'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(_saving ? 'Saving' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final existing = widget.product;
      final product = existing == null
          ? await widget.repository.createProduct(
              name: _name.text,
              barcode: _barcode.text,
              sku: _sku.text,
              salePriceMinor: parseMoneyMinor(_salePrice.text),
              purchaseCostMinor: parseMoneyMinor(_cost.text),
            )
          : ProductSummary(
              productId: existing.productId,
              name: _name.text.trim(),
              barcode: _barcode.text.trim().isEmpty
                  ? null
                  : _barcode.text.trim(),
              sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
              unit: existing.unit,
              salePriceMinor: parseMoneyMinor(_salePrice.text),
              purchaseCostMinor: parseMoneyMinor(_cost.text),
              active: existing.active,
              quantity: existing.quantity,
            );
      if (existing != null) await widget.repository.updateProduct(product);
      if (mounted) Navigator.pop(context, product);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deactivate() async {
    await widget.repository.deactivateProduct(widget.product!.productId);
    if (mounted) Navigator.pop(context);
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Product save failed: $error')));
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
}
