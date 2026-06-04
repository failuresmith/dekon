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
  });

  final DekonRepository repository;
  final ValueChanged<ProductSummary> onProductSelected;
  final BarcodeScanLauncher scanBarcode;

  @override
  State<ProductLookupField> createState() => _ProductLookupFieldState();
}

class _ProductLookupFieldState extends State<ProductLookupField> {
  final _controller = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('barcode-entry'),
            controller: _controller,
            decoration: const InputDecoration(labelText: 'Barcode or SKU'),
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
        IconButton.filled(
          key: const Key('lookup-product'),
          tooltip: 'Find or create product',
          onPressed: _busy ? null : _lookup,
          icon: const Icon(Icons.search),
        ),
      ],
    );
  }

  Future<void> _scan() async {
    try {
      final scanned = await widget.scanBarcode(context);
      if (!mounted || scanned == null || scanned.trim().isEmpty) return;
      _controller.text = scanned.trim();
      await _lookup();
    } catch (_) {
      if (mounted) _message('Scan unavailable. Enter barcode manually.');
    }
  }

  Future<void> _lookup() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() => _busy = true);
    try {
      var product = await widget.repository.productByBarcodeOrSku(query);
      if (product == null && mounted) {
        product = await showProductFormDialog(
          context: context,
          repository: widget.repository,
          initialBarcode: query,
        );
      }
      if (product != null) {
        widget.onProductSelected(product);
        _controller.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
