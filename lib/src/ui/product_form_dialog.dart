import 'package:flutter/material.dart';

import '../application/application.dart';
import 'ui_strings.dart';

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
  AppLanguage? _priceLanguage;
  MoneyUnit? _priceMoneyUnit;
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
    _salePrice = TextEditingController();
    _cost = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = context.strings;
    final previousUnit = _priceMoneyUnit;
    if (_priceLanguage == strings.language &&
        previousUnit == strings.moneyUnit) {
      return;
    }
    _priceLanguage = strings.language;
    _priceMoneyUnit = strings.moneyUnit;
    _syncPriceController(
      _salePrice,
      fallbackRialValue: widget.product?.salePriceMinor ?? 0,
      previousUnit: previousUnit,
    );
    _syncPriceController(
      _cost,
      fallbackRialValue: widget.product?.purchaseCostMinor ?? 0,
      previousUnit: previousUnit,
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
    final strings = context.strings;
    return AlertDialog(
      title: Text(editing ? strings.editProduct : strings.createProduct),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('product-name'),
                controller: _name,
                decoration: InputDecoration(labelText: strings.name),
                validator: _required,
              ),
              TextFormField(
                key: const Key('product-barcode'),
                controller: _barcode,
                decoration: InputDecoration(labelText: strings.barcode),
              ),
              TextFormField(
                controller: _sku,
                decoration: InputDecoration(
                  labelText: strings.skuInternalProductCode,
                ),
              ),
              TextFormField(
                key: const Key('product-sale-price'),
                controller: _salePrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${strings.salePrice} (${strings.moneyUnitLabel(strings.moneyUnit)})',
                ),
                validator: _money,
              ),
              TextFormField(
                key: const Key('product-cost'),
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '${strings.purchaseCost} (${strings.moneyUnitLabel(strings.moneyUnit)})',
                ),
                validator: _money,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (editing)
          TextButton.icon(
            key: const Key('soft-delete-product'),
            onPressed: _saving ? null : _softDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(strings.delete),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton.icon(
          key: const Key('save-product'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(_saving ? strings.saving : strings.save),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final moneyUnit = context.strings.moneyUnit;
    setState(() => _saving = true);
    try {
      final existing = widget.product;
      final product = existing == null
          ? await widget.repository.createProduct(
              name: _name.text,
              barcode: _barcode.text,
              sku: _sku.text,
              salePriceMinor: parseMoneyRial(_salePrice.text, unit: moneyUnit),
              purchaseCostMinor: parseMoneyRial(_cost.text, unit: moneyUnit),
            )
          : ProductSummary(
              productId: existing.productId,
              name: _name.text.trim(),
              barcode: _barcode.text.trim().isEmpty
                  ? null
                  : _barcode.text.trim(),
              sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
              unit: existing.unit,
              salePriceMinor: parseMoneyRial(_salePrice.text, unit: moneyUnit),
              purchaseCostMinor: parseMoneyRial(_cost.text, unit: moneyUnit),
              active: existing.active,
              quantity: existing.quantity,
            );
      if (existing != null) await widget.repository.updateProduct(product);
      if (mounted) Navigator.pop(context, product);
    } catch (error) {
      if (mounted) _showError(context.strings.productSaveFailed(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _syncPriceController(
    TextEditingController controller, {
    required int fallbackRialValue,
    required MoneyUnit? previousUnit,
  }) {
    final rialValue = previousUnit == null
        ? fallbackRialValue
        : _tryParseRial(controller.text, previousUnit) ?? fallbackRialValue;
    final text = context.strings.moneyInput(rialValue);
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  int? _tryParseRial(String input, MoneyUnit unit) {
    try {
      return parseMoneyRial(input, unit: unit);
    } on FormatException {
      return null;
    }
  }

  Future<void> _softDelete() async {
    final confirmed = await _confirmSoftDelete();
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.repository.softDeleteProduct(widget.product!.productId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) _showError(context.strings.productDeleteFailed(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmSoftDelete() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.strings.deleteProductQuestion),
        content: Text(dialogContext.strings.deleteProductHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.strings.cancel),
          ),
          FilledButton.icon(
            key: const Key('confirm-soft-delete-product'),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: Text(dialogContext.strings.delete),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty
        ? context.strings.requiredField
        : null;
  }

  String? _money(String? value) {
    try {
      parseMoneyRial(value ?? '', unit: context.strings.moneyUnit);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}
