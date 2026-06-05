import 'dart:async';

import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_form_dialog.dart';
import 'ui_strings.dart';

class ProductLookupField extends StatefulWidget {
  const ProductLookupField({
    super.key,
    required this.repository,
    required this.onProductSelected,
    this.scanBarcode = showBarcodeScannerDialog,
    this.allowCreateProduct = true,
  });

  final DekonRepository repository;
  final ValueChanged<ProductSummary> onProductSelected;
  final BarcodeScanLauncher scanBarcode;
  final bool allowCreateProduct;

  @override
  State<ProductLookupField> createState() => _ProductLookupFieldState();
}

class _ProductLookupFieldState extends State<ProductLookupField> {
  final _queryController = TextEditingController();
  var _matches = <ProductSummary>[];
  var _busy = false;
  var _searching = false;
  String? _notFoundQuery;
  String? _createBarcode;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('barcode-entry'),
                controller: _queryController,
                decoration: InputDecoration(
                  hintText: context.strings.scanBarcodeOrSearchProduct,
                  prefixIcon: const Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: (_) => _submitQuery(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('scan-barcode'),
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(context.strings.scan),
            ),
          ],
        ),
        if (_searching) ...[
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
        if (_matches.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                for (final product in _matches)
                  ListTile(
                    key: Key('product-search-result-${product.productId}'),
                    title: Text(product.name),
                    subtitle: Text(
                      context.strings.stockInline(product.quantity.g),
                    ),
                    onTap: () => _selectProduct(product),
                  ),
              ],
            ),
          ),
        ] else if (_notFoundQuery != null && !_searching) ...[
          const SizedBox(height: 8),
          _notFoundPanel(_notFoundQuery!),
        ],
      ],
    );
  }

  Future<void> _scan() async {
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      final query = scanned.trim();
      _queryController.text = query;
      await _lookupExact(query, barcodeForCreate: query);
    } catch (_) {
      if (mounted) {
        _message(context.strings.scanUnavailableEnterBarcodeManually);
      }
    }
  }

  Future<void> _submitQuery() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() => _busy = true);
    try {
      final exact = await widget.repository.productByBarcodeOrSku(query);
      if (exact != null) {
        _selectProduct(exact);
        return;
      }
      final matches = await widget.repository.productsMatchingName(query);
      if (matches.isNotEmpty) {
        setState(() {
          _matches = matches;
          _searching = false;
          _notFoundQuery = null;
          _createBarcode = null;
        });
        return;
      }
      _showNotFound(query, barcodeForCreate: query);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lookupExact(String query, {String? barcodeForCreate}) async {
    setState(() => _busy = true);
    try {
      final product = await widget.repository.productByBarcodeOrSku(query);
      if (product != null) {
        _selectProduct(product);
        return;
      }
      _showNotFound(query, barcodeForCreate: barcodeForCreate);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onQueryChanged(String input) {
    _searchDebounce?.cancel();
    final query = input.trim();
    if (query.isEmpty) {
      setState(() {
        _matches = const [];
        _searching = false;
        _notFoundQuery = null;
        _createBarcode = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _notFoundQuery = null;
      _createBarcode = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_searchByName(query));
    });
  }

  Future<void> _searchByName(String query) async {
    final matches = await widget.repository.productsMatchingName(query);
    final exact = await widget.repository.productByBarcodeOrSku(query);
    if (!mounted || _queryController.text.trim() != query) return;
    final results = [
      ?exact,
      for (final match in matches)
        if (exact == null || match.productId != exact.productId) match,
    ];
    setState(() {
      _matches = results;
      _searching = false;
      _notFoundQuery = results.isEmpty ? query : null;
    });
  }

  Widget _notFoundPanel(String query) {
    final createBarcode = _createBarcode;
    final isBarcodeMiss = createBarcode != null;
    return DecoratedBox(
      key: const Key('product-not-found-panel'),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isBarcodeMiss
                  ? context.strings.thisBarcodeNotInInventory
                  : '${context.strings.noProductsFoundFor(query)}.',
            ),
            if (!widget.allowCreateProduct) ...[
              const SizedBox(height: 4),
              Text(context.strings.productNotFoundRestockFirst),
            ],
            if (widget.allowCreateProduct) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('create-product-from-lookup'),
                onPressed: _busy
                    ? null
                    : () => _createProduct(initialBarcode: createBarcode),
                icon: const Icon(Icons.add),
                label: Text(context.strings.createNewProduct),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showNotFound(String query, {String? barcodeForCreate}) {
    if (!mounted) return;
    setState(() {
      _matches = const [];
      _searching = false;
      _notFoundQuery = query;
      _createBarcode = barcodeForCreate;
    });
  }

  Future<void> _createProduct({String? initialBarcode}) async {
    setState(() => _busy = true);
    try {
      final product = await showProductFormDialog(
        context: context,
        repository: widget.repository,
        initialBarcode: initialBarcode,
      );
      if (product != null) _selectProduct(product);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectProduct(ProductSummary product) {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onProductSelected(product);
    setState(() {
      _queryController.clear();
      _matches = const [];
      _searching = false;
      _notFoundQuery = null;
      _createBarcode = null;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
