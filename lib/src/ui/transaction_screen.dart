import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_lookup_field.dart';

enum TransactionMode { sell, buy }

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    required this.repository,
    required this.mode,
    this.scanBarcode = showBarcodeScannerDialog,
  });

  final DekonRepository repository;
  final TransactionMode mode;
  final BarcodeScanLauncher scanBarcode;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final _quantityController = TextEditingController(text: '1');
  final _lines = <TransactionLineDraft>[];
  var _saving = false;

  bool get _isSell => widget.mode == TransactionMode.sell;
  String get _title => _isSell ? 'Sell' : 'Buy';

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                key: Key('${_title.toLowerCase()}-quantity'),
                controller: _quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Qty'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ProductLookupField(
                repository: widget.repository,
                onProductSelected: _addProduct,
                scanBarcode: widget.scanBarcode,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_lines.isEmpty)
          const Text('No items')
        else
          ..._lines.indexed.map((entry) => _lineTile(entry.$1, entry.$2)),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: Key(_isSell ? 'finish-sale' : 'finish-purchase'),
          onPressed: _saving || _lines.isEmpty ? null : _finish,
          icon: Icon(_isSell ? Icons.check_circle : Icons.inventory),
          label: Text(_saving ? 'Saving' : 'Save $_title'),
        ),
      ],
    );
  }

  Widget _lineTile(int index, TransactionLineDraft line) {
    final amount = _isSell ? line.saleTotalMinor : line.purchaseTotalMinor;
    return ListTile(
      dense: true,
      title: Text(line.product.name),
      subtitle: Text('Qty ${line.quantity.g} - ${formatMoney(amount)}'),
      trailing: IconButton(
        tooltip: 'Remove item',
        onPressed: () => setState(() => _lines.removeAt(index)),
        icon: const Icon(Icons.delete),
      ),
    );
  }

  void _addProduct(ProductSummary product) {
    final quantity = double.tryParse(_quantityController.text.trim()) ?? 0;
    if (quantity <= 0) {
      _message('Quantity must be positive');
      return;
    }
    setState(() {
      _lines.add(TransactionLineDraft(product: product, quantity: quantity));
      _quantityController.text = '1';
    });
  }

  Future<void> _finish() async {
    if (_isSell && await widget.repository.saleWouldMakeNegative(_lines)) {
      final proceed = await _confirmNegativeStock();
      if (proceed != true) return;
    }
    setState(() => _saving = true);
    try {
      if (_isSell) {
        await widget.repository.recordSale(_lines);
        _message('Sale saved');
      } else {
        await widget.repository.recordPurchase(_lines);
        _message('Purchase saved');
      }
      setState(_lines.clear);
    } catch (error) {
      _message('Save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmNegativeStock() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Negative stock warning'),
        content: const Text(
          'This sale will make one or more products negative.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-negative-stock'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
