import 'package:flutter/material.dart';

import '../application/application.dart';
import 'product_form_dialog.dart';

class ProductLookupField extends StatefulWidget {
  const ProductLookupField({
    super.key,
    required this.repository,
    required this.onProductSelected,
  });

  final DekonRepository repository;
  final ValueChanged<ProductSummary> onProductSelected;

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
        IconButton.filled(
          key: const Key('lookup-product'),
          tooltip: 'Find or create product',
          onPressed: _busy ? null : _lookup,
          icon: const Icon(Icons.search),
        ),
      ],
    );
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
}
