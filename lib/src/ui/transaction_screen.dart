import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_lookup_field.dart';
import 'transaction_quantity_input.dart';

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
  final _lines = <TransactionLineDraft>[];
  final _negativeProductIds = <String>{};
  var _saving = false;

  bool get _isSell => widget.mode == TransactionMode.sell;
  String get _title => _isSell ? 'Sell' : 'Buy';
  int get _totalMinor => _lines.fold(
    0,
    (sum, line) =>
        sum + (_isSell ? line.saleTotalMinor : line.purchaseTotalMinor),
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            IconButton(
              key: Key(_isSell ? 'sell-history' : 'buy-history'),
              tooltip: 'History',
              onPressed: _showHistory,
              icon: const Icon(Icons.history),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ProductLookupField(
          repository: widget.repository,
          onProductSelected: _addProduct,
          scanBarcode: widget.scanBarcode,
          allowCreateProduct: !_isSell,
        ),
        const SizedBox(height: 16),
        if (_lines.isEmpty)
          const Text('No items')
        else
          ..._lines.indexed.map((entry) => _lineTile(entry.$1, entry.$2)),
        if (_lines.isNotEmpty) ...[const SizedBox(height: 12), _totalPanel()],
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
    final isNegative = _negativeProductIds.contains(line.product.productId);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        key: Key('transaction-line-${line.product.productId}'),
        decoration: BoxDecoration(
          border: Border.all(
            color: isNegative ? colors.error : Theme.of(context).dividerColor,
            width: isNegative ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(formatMoney(amount)),
                      ],
                    ),
                  ),
                  _quantityControls(index, line),
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: () => _removeLine(index),
                    icon: const Icon(Icons.delete),
                  ),
                ],
              ),
              if (isNegative)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Not enough stock: ${line.product.quantity.g} available.',
                    key: Key('negative-warning-${line.product.productId}'),
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quantityControls(int index, TransactionLineDraft line) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('decrease-line-$index'),
          tooltip: 'Decrease quantity',
          onPressed: line.quantity <= 1
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _changeQuantity(index, -1);
                },
          icon: const Icon(Icons.remove_circle_outline),
        ),
        TransactionQuantityInput(
          key: ValueKey('quantity-input-${line.product.productId}'),
          fieldKey: Key('line-quantity-$index'),
          value: line.quantity,
          onChanged: (quantity) => _setQuantity(index, quantity),
        ),
        IconButton(
          key: Key('increase-line-$index'),
          tooltip: 'Increase quantity',
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            _changeQuantity(index, 1);
          },
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _totalPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _isSell ? 'Total sale amount' : 'Total purchase amount',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              formatMoney(_totalMinor),
              key: Key(_isSell ? 'sale-total' : 'purchase-total'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _addProduct(ProductSummary product) {
    setState(() {
      _negativeProductIds.clear();
      final index = _lines.indexWhere(
        (line) => line.product.productId == product.productId,
      );
      if (index == -1) {
        _lines.add(TransactionLineDraft(product: product, quantity: 1));
        return;
      }
      final current = _lines[index];
      _lines[index] = TransactionLineDraft(
        product: current.product,
        quantity: current.quantity + 1,
        unitPriceMinor: current.unitPriceMinor,
        unitCostMinor: current.unitCostMinor,
      );
    });
  }

  void _setQuantity(int index, double quantity) {
    if (!quantity.isFinite || quantity <= 0) return;
    final current = _lines[index];
    setState(() {
      _negativeProductIds.clear();
      _lines[index] = TransactionLineDraft(
        product: current.product,
        quantity: quantity,
        unitPriceMinor: current.unitPriceMinor,
        unitCostMinor: current.unitCostMinor,
      );
    });
  }

  void _changeQuantity(int index, double delta) {
    final current = _lines[index];
    final nextQuantity = current.quantity + delta;
    if (nextQuantity <= 0) return;
    _setQuantity(index, nextQuantity);
  }

  void _removeLine(int index) {
    setState(() {
      _negativeProductIds.clear();
      _lines.removeAt(index);
    });
  }

  Future<void> _finish() async {
    if (_isSell) {
      final negativeProductIds = await widget.repository
          .negativeStockProductIds(_lines);
      if (negativeProductIds.isNotEmpty) {
        setState(() {
          _negativeProductIds
            ..clear()
            ..addAll(negativeProductIds);
        });
        final proceed = await _confirmNegativeStock(negativeProductIds);
        if (proceed != true) return;
      } else {
        setState(_negativeProductIds.clear);
      }
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
      setState(() {
        _lines.clear();
        _negativeProductIds.clear();
      });
    } catch (error) {
      _message('Save failed: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirmNegativeStock(Set<String> productIds) {
    final names = _lines
        .where((line) => productIds.contains(line.product.productId))
        .map((line) => line.product.name)
        .join(', ');
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Negative stock warning'),
        content: Text(
          'This sale will make stock negative for: $names.\n'
          'The affected row is highlighted.',
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

  Future<void> _showHistory() async {
    final kind = _isSell
        ? TransactionHistoryKind.sale
        : TransactionHistoryKind.purchase;
    final history = await widget.repository.transactionHistory(kind);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isSell ? 'Sale History' : 'Buy History'),
        content: SizedBox(
          width: double.maxFinite,
          child: history.isEmpty
              ? const Text('No previous transactions')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    return ListTile(
                      title: Text(formatMoney(entry.totalMinor)),
                      subtitle: Text(
                        '${_timestamp(entry.occurredAt)}\n'
                        '${_historyLineSummary(entry)}',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _historyLineSummary(TransactionHistoryEntry entry) {
    if (entry.lines.isEmpty) return 'No line details';
    return entry.lines
        .map((line) => '${line.productName} x${line.quantity.g}')
        .join(', ');
  }

  String _timestamp(DateTime dateTime) {
    return dateTime.toLocal().toString().split('.').first;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
