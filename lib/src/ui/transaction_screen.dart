import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import '../platform/external_link_actions.dart';
import 'barcode_scanner_dialog.dart';
import 'cashier_sync_status.dart';
import 'persian_date_range_picker.dart';
import 'product_lookup_field.dart';
import 'sale_receipt_share_dialog.dart';
import 'transaction_quantity_input.dart';
import 'ui_strings.dart';

enum TransactionMode { sell, buy }

class TransactionScreen extends StatefulWidget {
  const TransactionScreen({
    super.key,
    required this.repository,
    required this.mode,
    this.scanBarcode = showBarcodeScannerDialog,
    this.shareText = sharePlainText,
    this.cashierSyncStatus,
  });

  final DekonRepository repository;
  final TransactionMode mode;
  final BarcodeScanLauncher scanBarcode;
  final TextShareLauncher shareText;
  final CashierSyncStatus? cashierSyncStatus;

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final _lines = <TransactionLineDraft>[];
  final _negativeProductIds = <String>{};
  StreamSubscription<void>? _syncStateSubscription;
  var _saving = false;
  var _outboxSummary = CashierSaleOutboxSummary.empty;

  bool get _isSell => widget.mode == TransactionMode.sell;
  bool get _isCashierSell => _isSell && widget.cashierSyncStatus != null;
  CashierSyncStatus? get _cashierStatus => widget.cashierSyncStatus;
  bool get _cashierSaleNeedsSyncWarning {
    final status = _cashierStatus;
    return _isCashierSell &&
        status != null &&
        status.needsAttention &&
        !_cashierSaleHasConflict;
  }

  bool get _cashierSaleHasConflict =>
      _isCashierSell &&
      (_outboxSummary.hasConflict ||
          (widget.cashierSyncStatus?.hasOutboxConflict ?? false));
  bool get _cashierSaleBlocked =>
      _cashierSaleHasConflict ||
      (widget.cashierSyncStatus?.blocksNormalCashierUse ?? false);
  String get _emptyStateText => _isSell
      ? context.strings.sellEmptyState
      : context.strings.restockEmptyState;
  int get _totalMinor => _lines.fold(
    0,
    (sum, line) =>
        sum + (_isSell ? line.saleTotalMinor : line.purchaseTotalMinor),
  );
  double get _totalQuantity =>
    _lines.fold(0, (sum, line) => sum + line.quantity);

  @override
  void initState() {
    super.initState();
    _subscribeToSyncState();
    unawaited(_refreshOutboxSummary());
  }

  @override
  void didUpdateWidget(covariant TransactionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _syncStateSubscription?.cancel();
      _subscribeToSyncState();
      unawaited(_refreshOutboxSummary());
    }
  }

  @override
  void dispose() {
    _syncStateSubscription?.cancel();
    super.dispose();
  }

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
            if (_cashierSaleHasConflict) ...[
              const SizedBox(height: 12),
              _cashierConflictWarning(),
            ] else if (_cashierSaleNeedsSyncWarning) ...[
              const SizedBox(height: 12),
              _cashierSyncWarning(),
            ],
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
            if (!_isSell) ...[
              const SizedBox(height: 8),
              _RestockCostInput(
                key: ValueKey('cost-input-${line.product.productId}'),
                fieldKey: Key('line-unit-cost-$index'),
                valueMinor: line.unitCostMinor,
                onChanged: (value) => _setUnitCost(index, value),
              ),
            ],
            const SizedBox(height: 8),
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
                    '${context.strings.itemsCount(_lines.length)} '
              '(${context.strings.quantity(_totalQuantity)})',
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
              onPressed: _saving || _lines.isEmpty || _cashierSaleBlocked
                  ? null
                  : _finish,
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

  Widget _cashierSyncWarning() {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('cashier-sale-sync-warning'),
      decoration: BoxDecoration(
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.sync_problem, color: colors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.strings.cashierSaleConnectionWarning,
                style: TextStyle(color: colors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cashierConflictWarning() {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: const Key('cashier-sale-conflict-warning'),
      decoration: BoxDecoration(
        border: Border.all(color: colors.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber, color: colors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.strings.cashierSaleConflictWarning,
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('void-conflicted-cashier-sale'),
              onPressed: _saving ? null : _voidConflictedSale,
              icon: const Icon(Icons.undo),
              label: Text(context.strings.voidConflictedSale),
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

  void _setUnitCost(int index, int unitCostMinor) {
    if (unitCostMinor < 0) return;
    final current = _lines[index];
    setState(() {
      _lines[index] = TransactionLineDraft(
        product: current.product,
        quantity: current.quantity,
        unitPriceMinor: current.unitPriceMinor,
        unitCostMinor: unitCostMinor,
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
    final transactionLines = List<TransactionLineDraft>.unmodifiable(_lines);
    setState(() => _saving = true);
    try {
      if (_isSell) {
        final negativeProductIds = await widget.repository
            .negativeStockProductIds(transactionLines);
        if (!mounted) return;
        if (negativeProductIds.isNotEmpty) {
          setState(() {
            _negativeProductIds
              ..clear()
              ..addAll(negativeProductIds);
          });
          return;
        } else {
          setState(_negativeProductIds.clear);
        }
      }
      if (_isSell) {
        final result = await widget.repository.recordSale(transactionLines);
        if (!mounted) return;
        unawaited(_refreshOutboxSummary());
        setState(() {
          _lines.clear();
          _negativeProductIds.clear();
        });
        if (result.status == SaleRecordStatus.conflict ||
            result.saleId == null ||
            result.occurredAt == null) {
          _message(messenger, strings.cashierSaleConflictSaved);
          return;
        }
        if (result.status == SaleRecordStatus.queued) {
          _message(messenger, strings.cashierSaleQueued);
        }
        setState(() => _saving = false);
        await showSaleCompletedDialog(
          context: context,
          repository: widget.repository,
          receipt: SaleReceiptDraft.fromSale(
            saleId: result.saleId!,
            occurredAt: result.occurredAt!,
            lines: transactionLines,
          ),
          shareText: widget.shareText,
        );
        return;
      } else {
        await widget.repository.recordPurchase(transactionLines);
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

  void _message(ScaffoldMessengerState messenger, String text) {
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  void _subscribeToSyncState() {
    _syncStateSubscription = widget.repository.syncStateChanged.listen((_) {
      unawaited(_refreshOutboxSummary());
    });
  }

  Future<void> _refreshOutboxSummary() async {
    if (!_isCashierSell) return;
    final summary = await widget.repository.cashierSaleOutboxSummary();
    if (!mounted) return;
    setState(() => _outboxSummary = summary);
  }

  Future<void> _voidConflictedSale() async {
    final strings = context.strings;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await widget.repository.voidOldestConflictedCashierSale();
      if (!mounted) return;
      await _refreshOutboxSummary();
      _message(messenger, strings.cashierSaleConflictVoided);
    } catch (error) {
      if (mounted) _message(messenger, strings.saveFailed(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _RestockCostInput extends StatefulWidget {
  const _RestockCostInput({
    super.key,
    required this.fieldKey,
    required this.valueMinor,
    required this.onChanged,
  });

  final Key fieldKey;
  final int valueMinor;
  final ValueChanged<int> onChanged;

  @override
  State<_RestockCostInput> createState() => _RestockCostInputState();
}

class _RestockCostInputState extends State<_RestockCostInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  MoneyUnit? _moneyUnit;
  AppLanguage? _language;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = context.strings;
    if (_moneyUnit == strings.moneyUnit && _language == strings.language) {
      return;
    }
    _moneyUnit = strings.moneyUnit;
    _language = strings.language;
    if (!_focusNode.hasFocus) _syncText(widget.valueMinor);
  }

  @override
  void didUpdateWidget(covariant _RestockCostInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueMinor == widget.valueMinor) return;
    if (!_focusNode.hasFocus || _tracksValue(oldWidget.valueMinor)) {
      _syncText(widget.valueMinor);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText:
            '${strings.purchaseCost} (${strings.moneyUnitLabel(strings.moneyUnit)})',
      ),
      onTap: _selectAll,
      onChanged: _applyIfValid,
      onSubmitted: (_) => _commitOrRevert(),
    );
  }

  void _handleFocusChanged() {
    if (_focusNode.hasFocus) {
      _selectAll();
      return;
    }
    _commitOrRevert();
  }

  void _selectAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _applyIfValid(String input) {
    final value = _parse(input);
    if (value != null) widget.onChanged(value);
  }

  void _commitOrRevert() {
    final value = _parse(_controller.text);
    if (value == null) {
      _syncText(widget.valueMinor);
      return;
    }
    widget.onChanged(value);
    _syncText(value);
  }

  bool _tracksValue(int value) => _parse(_controller.text) == value;

  void _syncText(int value) {
    final text = context.strings.moneyInput(value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  int? _parse(String input) {
    try {
      return parseMoneyRial(input, unit: context.strings.moneyUnit);
    } on FormatException {
      return null;
    }
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
  await showDialog<void>(
    context: context,
    builder: (context) => _TransactionHistoryDialog(
      repository: repository,
      isSell: isSell,
      kind: kind,
    ),
  );
}

class _TransactionHistoryDialog extends StatefulWidget {
  const _TransactionHistoryDialog({
    required this.repository,
    required this.isSell,
    required this.kind,
  });

  final DekonRepository repository;
  final bool isSell;
  final TransactionHistoryKind kind;

  @override
  State<_TransactionHistoryDialog> createState() {
    return _TransactionHistoryDialogState();
  }
}

class _TransactionHistoryDialogState extends State<_TransactionHistoryDialog> {
  TransactionHistoryEntry? _selectedEntry;
  String? _selectedCreatorDeviceId;
  DateTimeRange? _customRange;
  late Future<List<TransactionHistoryEntry>> _historyFuture;
  late Future<List<TransactionCreatorFilter>> _creatorFiltersFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
    _creatorFiltersFuture = _loadCreatorFilters();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final selectedEntry = _selectedEntry;
    return AlertDialog(
      title: _title(strings, selectedEntry),
      content: SizedBox(
        width: double.maxFinite,
        child: selectedEntry == null
            ? _historyOverview(strings)
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

  Widget _historyOverview(UiStrings strings) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isSell) ...[
          _historyFilters(strings),
          const SizedBox(height: 12),
        ],
        FutureBuilder<List<TransactionHistoryEntry>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(strings.transactionHistoryFailed);
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _historyList(strings, snapshot.requireData);
          },
        ),
      ],
    );
  }

  Widget _historyFilters(UiStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<List<TransactionCreatorFilter>>(
          future: _creatorFiltersFuture,
          builder: (context, snapshot) {
            final creators =
                snapshot.data ?? const <TransactionCreatorFilter>[];
            return DropdownButtonFormField<String>(
              key: const Key('sale-history-creator-filter'),
              initialValue: _selectedCreatorDeviceId ?? '',
              decoration: InputDecoration(
                isDense: true,
                labelText: strings.createdByField,
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(strings.allPersonnel)),
                for (final creator in _creatorItems(creators))
                  DropdownMenuItem(
                    value: creator.deviceId,
                    child: Text(creator.label),
                  ),
              ],
              onChanged: (value) => _setCreatorFilter(value),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('sale-history-date-filter'),
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.date_range),
                label: Text(_dateRangeLabel(strings)),
              ),
            ),
            if (_customRange != null) ...[
              const SizedBox(width: 8),
              IconButton(
                key: const Key('sale-history-clear-date-filter'),
                tooltip: strings.clearDateRange,
                onPressed: _clearDateRange,
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _historyList(
    UiStrings strings,
    List<TransactionHistoryEntry> history,
  ) {
    if (history.isEmpty) return Text(strings.noPreviousTransactions);
    return _boundedContent(
      ListView.separated(
        shrinkWrap: true,
        itemCount: history.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final entry = history[index];
          return ListTile(
            key: Key('transaction-history-entry-$index'),
            title: Text(strings.money(entry.totalMinor)),
            subtitle: Text(
              '${strings.timestamp(entry.occurredAt)}\n'
              '${strings.createdBy(entry.createdByLabel)}\n'
              '${_historyLineSummary(entry, strings)}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.pendingMainApproval) ...[
                  _PendingMainApprovalIcon(
                    key: Key('transaction-history-pending-approval-$index'),
                    strings: strings,
                  ),
                  const SizedBox(width: 8),
                ],
                Icon(_detailIcon(context)),
              ],
            ),
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
          const SizedBox(height: 4),
          Text(
            strings.createdBy(entry.createdByLabel),
            key: const Key('transaction-history-created-by'),
          ),
          if (entry.pendingMainApproval) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PendingMainApprovalIcon(strings: strings),
                const SizedBox(width: 8),
                Expanded(child: Text(strings.salePendingMainApproval)),
              ],
            ),
          ],
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

  List<TransactionCreatorFilter> _creatorItems(
    List<TransactionCreatorFilter> creators,
  ) {
    final selected = _selectedCreatorDeviceId;
    if (selected == null ||
        selected.isEmpty ||
        creators.any((creator) => creator.deviceId == selected)) {
      return creators;
    }
    return [
      TransactionCreatorFilter(
        deviceId: selected,
        label: context.strings.selectedCreator,
      ),
      ...creators,
    ];
  }

  Future<List<TransactionHistoryEntry>> _loadHistory() {
    final filtered = _selectedCreatorDeviceId != null || _customRange != null;
    return widget.repository.transactionHistory(
      widget.kind,
      range: _activeRange(),
      deviceId: _selectedCreatorDeviceId,
      limit: widget.isSell && filtered ? null : 20,
      includePendingCashierSales: widget.isSell,
    );
  }

  Future<List<TransactionCreatorFilter>> _loadCreatorFilters() {
    if (!widget.isSell) return Future.value(const []);
    return widget.repository.transactionCreatorFilters(
      widget.kind,
      includePendingCashierSales: true,
    );
  }

  void _setCreatorFilter(String? value) {
    setState(() {
      _selectedEntry = null;
      _selectedCreatorDeviceId = value == null || value.isEmpty ? null : value;
      _historyFuture = _loadHistory();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5);
    final lastDate = DateTime(now.year + 1, 12, 31);
    final initialDateRange =
        _customRange ?? DateTimeRange(start: _dayStart(now), end: now);
    final picked = context.strings.reportCalendar == ReportCalendar.persian
        ? await showPersianDateRangePicker(
            context: context,
            firstDate: firstDate,
            lastDate: lastDate,
            initialDateRange: initialDateRange,
          )
        : await showDateRangePicker(
            context: context,
            firstDate: firstDate,
            lastDate: lastDate,
            initialDateRange: initialDateRange,
          );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedEntry = null;
      _customRange = picked;
      _historyFuture = _loadHistory();
    });
  }

  void _clearDateRange() {
    setState(() {
      _selectedEntry = null;
      _customRange = null;
      _historyFuture = _loadHistory();
    });
  }

  ReportDateRange? _activeRange() {
    final custom = _customRange;
    if (custom == null) return null;
    final start = _dayStart(custom.start);
    final end = _dayStart(custom.end).add(const Duration(days: 1));
    return ReportDateRange(startLocal: start, endLocalExclusive: end);
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  String _dateRangeLabel(UiStrings strings) {
    final custom = _customRange;
    if (custom == null) return strings.allDates;
    return '${strings.humanDate(custom.start)} - ${strings.humanDate(custom.end)}';
  }

  Widget _boundedContent(Widget child) {
    final overviewWithFilters = widget.isSell && _selectedEntry == null;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height *
            (overviewWithFilters ? 0.46 : 0.62),
      ),
      child: child,
    );
  }
}

class _PendingMainApprovalIcon extends StatelessWidget {
  const _PendingMainApprovalIcon({super.key, required this.strings});

  final UiStrings strings;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: strings.salePendingMainApproval,
      child: Icon(
        Icons.warning_amber,
        color: Colors.amber.shade700,
        semanticLabel: strings.salePendingMainApproval,
      ),
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
