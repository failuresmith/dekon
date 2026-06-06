import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_lookup_field.dart';
import 'transaction_quantity_input.dart';
import 'ui_strings.dart';

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
  String get _emptyStateText => _isSell
      ? context.strings.sellEmptyState
      : context.strings.restockEmptyState;
  int get _totalMinor => _lines.fold(
    0,
    (sum, line) =>
        sum + (_isSell ? line.saleTotalMinor : line.purchaseTotalMinor),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          children: [
            ProductLookupField(
              repository: widget.repository,
              onProductSelected: _addProduct,
              scanBarcode: widget.scanBarcode,
              allowCreateProduct: !_isSell,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _lines.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      itemCount: _lines.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _lineTile(index, _lines[index]),
                    ),
            ),
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              _summaryPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isSell
                  ? Icons.shopping_cart_outlined
                  : Icons.inventory_2_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            Text(
              context.strings.noProductsAddedYet,
              key: Key(_isSell ? 'sell-empty-title' : 'restock-empty-title'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _emptyStateText,
              key: Key(_isSell ? 'sell-empty-help' : 'restock-empty-help'),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(int index, TransactionLineDraft line) {
    final amount = _isSell ? line.saleTotalMinor : line.purchaseTotalMinor;
    final isNegative = _negativeProductIds.contains(line.product.productId);
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
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
                      Text(
                        _isSell
                            ? context.strings.eachPrice(
                                context.strings.money(line.unitPriceMinor),
                              )
                            : context.strings.currentStock(
                                context.strings.quantity(line.product.quantity),
                              ),
                      ),
                      if (!_isSell)
                        Text(
                          context.strings.purchaseCostEach(
                            context.strings.money(line.unitCostMinor),
                          ),
                        ),
                    ],
                  ),
                ),
                _quantityControls(index, line),
                IconButton(
                  key: Key('remove-line-$index'),
                  tooltip: context.strings.removeProduct,
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                context.strings.money(amount),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (isNegative)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber, color: colors.error, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.strings.availableStockWarning(
                          context.strings.quantity(line.product.quantity),
                        ),
                        key: Key('negative-warning-${line.product.productId}'),
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ],
                ),
              ),
          ],
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
          tooltip: context.strings.decreaseQuantity,
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
          tooltip: context.strings.increaseQuantity,
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            _changeQuantity(index, 1);
          },
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _summaryPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.strings.itemsCount(_lines.length),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  context.strings.money(_totalMinor),
                  key: Key(_isSell ? 'sale-total' : 'purchase-total'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: Key(_isSell ? 'finish-sale' : 'finish-purchase'),
              onPressed: _saving || _lines.isEmpty ? null : _finish,
              icon: Icon(_isSell ? Icons.check_circle : Icons.inventory),
              label: Text(
                _saving
                    ? context.strings.saving
                    : _isSell
                    ? context.strings.completeSale
                    : context.strings.addToInventory,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addProduct(ProductSummary product) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
    if (_saving) return;
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (_isSell) {
        final negativeProductIds = await widget.repository
            .negativeStockProductIds(_lines);
        if (!mounted) return;
        if (negativeProductIds.isNotEmpty) {
          setState(() {
            _negativeProductIds
              ..clear()
              ..addAll(negativeProductIds);
          });
          final proceed = await _confirmNegativeStock(negativeProductIds);
          if (!mounted) return;
          if (proceed != true) return;
        } else {
          setState(_negativeProductIds.clear);
        }
      }
      if (_isSell) {
        await widget.repository.recordSale(_lines);
        if (!mounted) return;
        _message(messenger, strings.saleCompleted);
      } else {
        await widget.repository.recordPurchase(_lines);
        if (!mounted) return;
        _message(messenger, strings.inventoryUpdated);
      }
      setState(() {
        _lines.clear();
        _negativeProductIds.clear();
      });
    } catch (error) {
      if (mounted) _message(messenger, strings.saveFailed(error));
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
        title: Text(context.strings.negativeStockWarning),
        content: Text(context.strings.negativeStockContent(names)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.strings.cancel),
          ),
          FilledButton(
            key: const Key('confirm-negative-stock'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.strings.continueAction),
          ),
        ],
      ),
    );
  }

  void _message(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}

Future<void> showTransactionHistoryDialog({
  required BuildContext context,
  required DekonRepository repository,
  required TransactionMode mode,
}) async {
  final isSell = mode == TransactionMode.sell;
  final kind = isSell
      ? TransactionHistoryKind.sale
      : TransactionHistoryKind.purchase;
  final history = await repository.transactionHistory(kind);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) =>
        _TransactionHistoryDialog(isSell: isSell, history: history),
  );
}

class _TransactionHistoryDialog extends StatefulWidget {
  const _TransactionHistoryDialog({
    required this.isSell,
    required this.history,
  });

  final bool isSell;
  final List<TransactionHistoryEntry> history;

  @override
  State<_TransactionHistoryDialog> createState() {
    return _TransactionHistoryDialogState();
  }
}

class _TransactionHistoryDialogState extends State<_TransactionHistoryDialog> {
  TransactionHistoryEntry? _selectedEntry;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final selectedEntry = _selectedEntry;
    return AlertDialog(
      title: _title(strings, selectedEntry),
      content: SizedBox(
        width: double.maxFinite,
        child: selectedEntry == null
            ? _historyList(strings)
            : _historyDetail(strings, selectedEntry),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.close),
        ),
      ],
    );
  }

  Widget _title(UiStrings strings, TransactionHistoryEntry? selectedEntry) {
    final showingDetail = selectedEntry != null;
    final title = showingDetail
        ? _detailTitle(strings)
        : _historyTitle(strings);
    if (selectedEntry == null) return Text(title);
    return Row(
      children: [
        IconButton(
          key: const Key('transaction-history-back'),
          tooltip: strings.back,
          onPressed: () => setState(() => _selectedEntry = null),
          icon: const BackButtonIcon(),
        ),
        const SizedBox(width: 4),
        Expanded(child: Text(title)),
      ],
    );
  }

  String _historyTitle(UiStrings strings) {
    return widget.isSell ? strings.saleHistory : strings.restockHistory;
  }

  String _detailTitle(UiStrings strings) {
    return widget.isSell ? strings.saleDetail : strings.restockDetail;
  }

  Widget _historyList(UiStrings strings) {
    if (widget.history.isEmpty) return Text(strings.noPreviousTransactions);
    return _boundedContent(
      ListView.separated(
        shrinkWrap: true,
        itemCount: widget.history.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = widget.history[index];
          return ListTile(
            key: Key('transaction-history-entry-$index'),
            title: Text(strings.money(entry.totalMinor)),
            subtitle: Text(
              '${strings.timestamp(entry.occurredAt)}\n'
              '${_historyLineSummary(entry, strings)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(_detailIcon(context)),
            onTap: () => setState(() => _selectedEntry = entry),
          );
        },
      ),
    );
  }

  Widget _historyDetail(UiStrings strings, TransactionHistoryEntry entry) {
    final itemCount = entry.lines.isEmpty ? 2 : entry.lines.length + 1;
    return _boundedContent(
      ListView.separated(
        shrinkWrap: true,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == 0) return _historyDetailSummary(strings, entry);
          if (entry.lines.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(strings.noLineDetails),
            );
          }
          final lineIndex = index - 1;
          final line = entry.lines[lineIndex];
          return ListTile(
            key: Key('transaction-history-line-$lineIndex'),
            contentPadding: EdgeInsets.zero,
            title: Text(line.productName),
            subtitle: Text(
              strings.lineQuantity(strings.quantity(line.quantity)),
            ),
            trailing: Text(
              strings.money(line.lineTotalMinor),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        },
      ),
    );
  }

  Widget _historyDetailSummary(
    UiStrings strings,
    TransactionHistoryEntry entry,
  ) {
    return Padding(
      key: const Key('transaction-history-detail-summary'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.timestamp(entry.occurredAt)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(strings.itemsCount(entry.lines.length))),
              Text(
                strings.transactionTotal(strings.money(entry.totalMinor)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _boundedContent(Widget child) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      child: child,
    );
  }
}

IconData _detailIcon(BuildContext context) {
  return Directionality.of(context) == TextDirection.rtl
      ? Icons.chevron_left
      : Icons.chevron_right;
}

String _historyLineSummary(TransactionHistoryEntry entry, UiStrings strings) {
  if (entry.lines.isEmpty) return strings.noLineDetails;
  return entry.lines
      .map((line) => '${line.productName} x${strings.quantity(line.quantity)}')
      .join(', ');
}
