import 'dart:async';

import 'package:flutter/material.dart';

import '../app_config.dart';
import '../application/application.dart';
import '../platform/external_link_actions.dart';
import 'ui_strings.dart';

class SaleReceiptDraft {
  SaleReceiptDraft({
    required this.saleId,
    required this.occurredAt,
    required this.totalMinor,
    required this.lines,
  });

  factory SaleReceiptDraft.fromSale({
    required String saleId,
    required DateTime occurredAt,
    required List<TransactionLineDraft> lines,
  }) {
    return SaleReceiptDraft(
      saleId: saleId,
      occurredAt: occurredAt,
      totalMinor: lines.fold<int>(0, (sum, line) => sum + line.saleTotalMinor),
      lines: [
        for (final line in lines)
          SaleReceiptLine(
            productName: line.product.name,
            quantity: line.quantity,
            lineTotalMinor: line.saleTotalMinor,
          ),
      ],
    );
  }

  final String saleId;
  final DateTime occurredAt;
  final int totalMinor;
  final List<SaleReceiptLine> lines;

  String shareText(UiStrings strings) {
    final buffer = StringBuffer()
      ..writeln(AppConfig.appName)
      ..writeln(strings.saleReceiptNumber(_receiptNumber))
      ..writeln(strings.timestamp(occurredAt))
      ..writeln();
    for (final line in lines) {
      buffer.writeln(
        strings.saleReceiptLine(
          line.productName.trim().isEmpty
              ? strings.unknownProduct
              : line.productName.trim(),
          strings.quantity(line.quantity),
          strings.money(line.lineTotalMinor),
        ),
      );
    }
    buffer
      ..writeln()
      ..writeln(strings.transactionTotal(strings.money(totalMinor)))
      ..writeln(strings.receiptThankYou);
    return buffer.toString().trimRight();
  }

  String get _receiptNumber {
    final compact = saleId.replaceAll('-', '');
    if (compact.length <= 8) return compact;
    return compact.substring(compact.length - 8);
  }
}

class SaleReceiptLine {
  const SaleReceiptLine({
    required this.productName,
    required this.quantity,
    required this.lineTotalMinor,
  });

  final String productName;
  final double quantity;
  final int lineTotalMinor;
}

Future<void> showSaleCompletedDialog({
  required BuildContext context,
  required DekonRepository repository,
  required SaleReceiptDraft receipt,
  required TextShareLauncher shareText,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SaleCompletedDialog(
      repository: repository,
      receipt: receipt,
      shareText: shareText,
    ),
  );
}

class _SaleCompletedDialog extends StatelessWidget {
  const _SaleCompletedDialog({
    required this.repository,
    required this.receipt,
    required this.shareText,
  });

  final DekonRepository repository;
  final SaleReceiptDraft receipt;
  final TextShareLauncher shareText;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.saleCompleted),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.saleReceiptNumber(receipt._receiptNumber)),
          const SizedBox(height: 4),
          Text(strings.transactionTotal(strings.money(receipt.totalMinor))),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('new-sale-after-completion'),
          onPressed: () => Navigator.pop(context),
          child: Text(strings.newSale),
        ),
        FilledButton.icon(
          key: const Key('share-receipt'),
          onPressed: () {
            unawaited(
              showDialog<void>(
                context: context,
                builder: (context) => _ShareReceiptDialog(
                  repository: repository,
                  receipt: receipt,
                  shareText: shareText,
                ),
              ),
            );
          },
          icon: const Icon(Icons.ios_share),
          label: Text(strings.shareReceipt),
        ),
      ],
    );
  }
}

class _ShareReceiptDialog extends StatefulWidget {
  const _ShareReceiptDialog({
    required this.repository,
    required this.receipt,
    required this.shareText,
  });

  final DekonRepository repository;
  final SaleReceiptDraft receipt;
  final TextShareLauncher shareText;

  @override
  State<_ShareReceiptDialog> createState() => _ShareReceiptDialogState();
}

class _ShareReceiptDialogState extends State<_ShareReceiptDialog> {
  final _search = TextEditingController();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  Future<List<CustomerSummary>> _customers = Future.value(const []);
  CustomerSummary? _selectedCustomer;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.shareReceipt),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.receiptReadyToShare(
                  strings.money(widget.receipt.totalMinor),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('receipt-customer-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: strings.searchCustomer,
                ),
                onChanged: _searchCustomers,
              ),
              const SizedBox(height: 8),
              _customerResults(strings),
              const SizedBox(height: 16),
              Text(
                strings.newCustomer,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('receipt-customer-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: strings.phoneNumber,
                ),
                onChanged: (_) {
                  setState(() {
                    _selectedCustomer = null;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('receipt-customer-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: strings.fullNameOptional,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              Text(
                strings.customerWillBeSavedForReceipts,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('receipt-share-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        OutlinedButton(
          key: const Key('share-receipt-without-saving'),
          onPressed: _busy ? null : _shareWithoutSaving,
          child: Text(strings.shareWithoutSaving),
        ),
        FilledButton(
          key: const Key('send-and-save-customer'),
          onPressed: _busy || _phone.text.trim().isEmpty
              ? null
              : _sendAndSaveCustomer,
          child: Text(_busy ? strings.saving : strings.sendAndSaveCustomer),
        ),
      ],
    );
  }

  Widget _customerResults(UiStrings strings) {
    if (_search.text.trim().isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<CustomerSummary>>(
      future: _customers,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text(strings.customerSearchFailed);
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 48,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final customers = snapshot.requireData;
        if (customers.isEmpty) return Text(strings.noCustomersFound);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: customers.length,
            itemBuilder: (context, index) {
              final customer = customers[index];
              final selected = _selectedCustomer?.customerId ==
                  customer.customerId;
              return ListTile(
                key: Key('receipt-customer-result-$index'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected ? Icons.check_circle : Icons.person_outline,
                ),
                title: Text(customer.displayName),
                subtitle: customer.fullName == null
                    ? null
                    : Text(customer.phoneNumber),
                onTap: () => _selectCustomer(customer),
              );
            },
          ),
        );
      },
    );
  }

  void _searchCustomers(String value) {
    setState(() {
      _error = null;
      _customers = widget.repository.customersMatching(value);
    });
  }

  void _selectCustomer(CustomerSummary customer) {
    setState(() {
      _selectedCustomer = customer;
      _phone.text = customer.phoneNumber;
      _name.text = customer.fullName ?? '';
      _error = null;
    });
  }

  Future<void> _shareWithoutSaving() async {
    await _runShare(saveCustomer: false);
  }

  Future<void> _sendAndSaveCustomer() async {
    await _runShare(saveCustomer: true);
  }

  Future<void> _runShare({required bool saveCustomer}) async {
    if (_busy) return;
    final strings = context.strings;
    var shared = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (saveCustomer) {
        final customer = await _saveCustomer();
        await widget.repository.linkCustomerToSale(
          saleId: widget.receipt.saleId,
          customerId: customer.customerId,
        );
      }
      await widget.shareText(
        text: widget.receipt.shareText(strings),
        title: strings.shareReceipt,
      );
      shared = true;
      if (mounted) Navigator.pop(context);
    } on FormatException {
      if (mounted) setState(() => _error = strings.enterValidCustomerPhone);
    } on ExternalShareException {
      if (mounted) setState(() => _error = strings.receiptShareFailed);
    } catch (_) {
      if (mounted) setState(() => _error = strings.customerSaveFailed);
    } finally {
      if (mounted && !shared) setState(() => _busy = false);
    }
  }

  Future<CustomerSummary> _saveCustomer() {
    final selected = _selectedCustomer;
    if (selected != null && _phone.text.trim() == selected.phoneNumber) {
      return widget.repository.saveCustomerForReceipt(
        phoneNumber: selected.phoneNumber,
        fullName: _name.text.trim().isEmpty
            ? selected.fullName
            : _name.text.trim(),
      );
    }
    return widget.repository.saveCustomerForReceipt(
      phoneNumber: _phone.text,
      fullName: _name.text,
    );
  }
}
