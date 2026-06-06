import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_form_dialog.dart';
import 'ui_strings.dart';

enum _InventoryFilter { all, lowStock }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    this.scanBarcode = showBarcodeScannerDialog,
    this.readOnly = false,
  });

  final DekonRepository repository;
  final BarcodeScanLauncher scanBarcode;
  final bool readOnly;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _queryController = TextEditingController();
  late Future<List<ProductSummary>> _future = widget.repository.products();
  var _filter = _InventoryFilter.all;
  var _query = '';
  String? _barcodeForCreate;
  StreamSubscription<void>? _eventsChangedSubscription;
  StreamSubscription<void>? _syncStateChangedSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToRepository();
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _eventsChangedSubscription?.cancel();
      _syncStateChangedSubscription?.cancel();
      _future = widget.repository.products();
      _subscribeToRepository();
    }
  }

  @override
  void dispose() {
    _eventsChangedSubscription?.cancel();
    _syncStateChangedSubscription?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProductSummary>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(context.strings.inventoryFailed(snapshot.error!)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final activeProducts = snapshot.requireData
            .where((product) => product.active)
            .toList(growable: false);
        final visibleProducts = _visibleProducts(activeProducts);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _lookupControls(),
                const SizedBox(height: 12),
                _filterAndCreateRow(),
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: _inventoryList(activeProducts, visibleProducts),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lookupControls() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('inventory-search-field'),
            controller: _queryController,
            decoration: InputDecoration(
              hintText: context.strings.searchProductsOrScanBarcode,
              prefixIcon: const Icon(Icons.search),
            ),
            textInputAction: TextInputAction.search,
            onChanged: _setQuery,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const Key('inventory-scan-button'),
          onPressed: _scanProduct,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(context.strings.scan),
        ),
      ],
    );
  }

  Widget _filterAndCreateRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          key: const Key('inventory-all-filter'),
          label: Text(context.strings.all),
          selected: _filter == _InventoryFilter.all,
          onSelected: (_) => setState(() => _filter = _InventoryFilter.all),
        ),
        ChoiceChip(
          key: const Key('inventory-low-stock-filter'),
          label: Text(context.strings.lowStock),
          selected: _filter == _InventoryFilter.lowStock,
          onSelected: (_) =>
              setState(() => _filter = _InventoryFilter.lowStock),
        ),
        if (!widget.readOnly)
          FilledButton.tonalIcon(
            key: const Key('inventory-add-product'),
            onPressed: () => _addProduct(initialBarcode: _barcodeForCreate),
            icon: const Icon(Icons.add),
            label: Text(context.strings.addProduct),
          ),
      ],
    );
  }

  Widget _inventoryList(
    List<ProductSummary> activeProducts,
    List<ProductSummary> visibleProducts,
  ) {
    if (activeProducts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_emptyInventoryState()],
      );
    }
    if (visibleProducts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_emptyFilteredState()],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: visibleProducts.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _productRow(visibleProducts[index]),
    );
  }

  Widget _emptyInventoryState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 40,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 8),
          Text(
            context.strings.noProductsInInventory,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            widget.readOnly
                ? context.strings.cashierEmptyInventoryHelp
                : context.strings.emptyInventoryHelp,
            textAlign: TextAlign.center,
          ),
          if (!widget.readOnly) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('inventory-empty-add-product'),
              onPressed: () => _addProduct(initialBarcode: _barcodeForCreate),
              icon: const Icon(Icons.add),
              label: Text(context.strings.addProduct),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyFilteredState() {
    final query = _query.trim();
    final message = query.isNotEmpty
        ? context.strings.noProductsFoundFor(query)
        : context.strings.noLowStockProducts;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Text(
        key: const Key('inventory-empty-filtered'),
        message,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _productRow(ProductSummary product) {
    final lowStock = _isLowStock(product);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: context.strings.inventoryProductSemantics(
        name: product.name,
        quantity: context.strings.quantity(product.quantity),
      ),
      child: ListTile(
        key: Key('inventory-product-${product.productId}'),
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        title: Text(product.name),
        subtitle: Text(
          widget.readOnly
              ? [
                  context.strings.stockLabel(
                    context.strings.quantity(product.quantity),
                  ),
                  '${context.strings.salePrice}: '
                      '${context.strings.money(product.salePriceMinor)}',
                ].join('\n')
              : context.strings.stockLabel(
                  context.strings.quantity(product.quantity),
                ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lowStock)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, color: colors.error, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      context.strings.lowStock,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                ),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () =>
            widget.readOnly ? _showReadOnlyProduct(product) : _edit(product),
      ),
    );
  }

  List<ProductSummary> _visibleProducts(List<ProductSummary> products) {
    final query = _query.trim().toLowerCase();
    return [
      for (final product in products)
        if ((_filter == _InventoryFilter.all || _isLowStock(product)) &&
            _matchesQuery(product, query))
          product,
    ];
  }

  bool _matchesQuery(ProductSummary product, String query) {
    if (query.isEmpty) return true;
    return product.name.toLowerCase().contains(query) ||
        (product.barcode?.toLowerCase().contains(query) ?? false) ||
        (product.sku?.toLowerCase().contains(query) ?? false);
  }

  bool _isLowStock(ProductSummary product) => product.quantity <= 0;

  void _setQuery(String query) {
    setState(() {
      _query = query;
      if (_barcodeForCreate != null && query.trim() != _barcodeForCreate) {
        _barcodeForCreate = null;
      }
    });
  }

  Future<void> _scanProduct() async {
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      final query = scanned.trim();
      final product = await widget.repository.productByBarcodeOrSku(query);
      if (!mounted) return;
      if (product != null) {
        if (widget.readOnly) {
          await _showReadOnlyProduct(product);
        } else {
          await _edit(product);
        }
        return;
      }
      setState(() {
        _barcodeForCreate = query;
        _query = query;
        _queryController.text = query;
      });
      _message(context.strings.noProductFoundForBarcode);
    } catch (_) {
      if (mounted) _message(context.strings.scanUnavailableSearchManually);
    }
  }

  Future<void> _addProduct({String? initialBarcode}) async {
    if (widget.readOnly) return;
    await showProductFormDialog(
      context: context,
      repository: widget.repository,
      initialBarcode: initialBarcode,
    );
    if (!mounted) return;
    setState(() => _barcodeForCreate = null);
    await _refresh();
  }

  Future<void> _edit(ProductSummary product) async {
    if (widget.readOnly) {
      await _showReadOnlyProduct(product);
      return;
    }
    await showProductFormDialog(
      context: context,
      repository: widget.repository,
      product: product,
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    _reload();
    await _future;
  }

  void _subscribeToRepository() {
    _eventsChangedSubscription = widget.repository.eventsChanged.listen((_) {
      if (mounted) _reload();
    });
    _syncStateChangedSubscription = widget.repository.syncStateChanged.listen((
      _,
    ) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    setState(() {
      _future = widget.repository.products();
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showReadOnlyProduct(ProductSummary product) {
    final strings = context.strings;
    final barcode = product.barcode?.trim();
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(product.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.stockLabel(strings.quantity(product.quantity))),
            Text(
              '${strings.salePrice}: ${strings.money(product.salePriceMinor)}',
            ),
            if (barcode != null && barcode.isNotEmpty)
              Text('${strings.barcode}: $barcode'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }
}
