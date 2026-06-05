import 'package:flutter/material.dart';

import '../application/application.dart';
import 'barcode_scanner_dialog.dart';
import 'product_form_dialog.dart';

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
  final _barcodeController = TextEditingController();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  var _matches = <ProductSummary>[];
  var _busy = false;
  var _searching = false;
  var _showSearch = false;

  @override
  void dispose() {
    _barcodeController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
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
                controller: _barcodeController,
                decoration: const InputDecoration(
                  labelText: 'Scan or enter barcode',
                ),
                onSubmitted: (_) => _lookup(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('scan-barcode'),
              tooltip: 'Scan barcode',
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('lookup-barcode'),
              tooltip: 'Add by barcode or internal code',
              onPressed: _busy ? null : _lookup,
              icon: const Icon(Icons.add_circle),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('lookup-product'),
              tooltip: 'Search products',
              onPressed: _busy ? null : _toggleSearch,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        if (_showSearch) ...[
          const SizedBox(height: 8),
          TextField(
            key: const Key('product-search-input'),
            controller: _searchController,
            focusNode: _searchFocus,
            decoration: InputDecoration(
              labelText: 'Search by product name',
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _searchByName,
          ),
          if (_matches.isNotEmpty)
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
                      subtitle: Text('Stock ${product.quantity.g}'),
                      onTap: () => _selectProduct(product),
                    ),
                ],
              ),
            )
          else if (_searchController.text.trim().isNotEmpty && !_searching)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No matching products'),
            ),
        ],
      ],
    );
  }

  void _toggleSearch() {
    setState(() => _showSearch = !_showSearch);
    if (_showSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  Future<void> _scan() async {
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      _barcodeController.text = scanned.trim();
      await _lookup();
    } catch (_) {
      if (mounted) _message('Scan unavailable. Enter barcode manually.');
    }
  }

  Future<void> _lookup() async {
    final query = _barcodeController.text.trim();
    if (query.isEmpty) return;
    setState(() => _busy = true);
    try {
      var product = await widget.repository.productByBarcodeOrSku(query);
      if (product == null && !widget.allowCreateProduct) {
        if (mounted) {
          _message('Product not found. Buy it into inventory first.');
        }
        return;
      }
      if (product == null && mounted) {
        product = await showProductFormDialog(
          context: context,
          repository: widget.repository,
          initialBarcode: query,
        );
      }
      if (product != null) {
        widget.onProductSelected(product);
        _barcodeController.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _searchByName(String input) async {
    final query = input.trim();
    if (query.isEmpty) {
      setState(() {
        _matches = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final matches = await widget.repository.productsMatchingName(query);
    if (!mounted || _searchController.text.trim() != query) return;
    setState(() {
      _matches = matches;
      _searching = false;
    });
  }

  void _selectProduct(ProductSummary product) {
    widget.onProductSelected(product);
    setState(() {
      _searchController.clear();
      _matches = const [];
      _showSearch = false;
      _searching = false;
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
