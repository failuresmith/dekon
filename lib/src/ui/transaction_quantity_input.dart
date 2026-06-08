import 'package:flutter/material.dart';

import '../application/application.dart';
import 'ui_strings.dart';

class TransactionQuantityInput extends StatefulWidget {
  const TransactionQuantityInput({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<TransactionQuantityInput> createState() =>
      _TransactionQuantityInputState();
}

class _TransactionQuantityInputState extends State<TransactionQuantityInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
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
    final language = context.strings.language;
    if (_language == language) return;
    _language = language;
    if (!_focusNode.hasFocus) _syncText(widget.value);
  }

  @override
  void didUpdateWidget(covariant TransactionQuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (!_focusNode.hasFocus || _tracksValue(oldWidget.value)) {
      _syncText(widget.value);
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
    return SizedBox(
      width: 72,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onTap: _selectAll,
        onChanged: _applyIfValid,
        onSubmitted: (_) => _commitOrRevert(),
      ),
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
    final quantity = _parseQuantity(input);
    if (quantity != null) widget.onChanged(quantity);
  }

  void _commitOrRevert() {
    final quantity = _parseQuantity(_controller.text);
    if (quantity == null) {
      _syncText(widget.value);
      return;
    }
    widget.onChanged(quantity);
    _syncText(quantity);
  }

  bool _tracksValue(double value) => _parseQuantity(_controller.text) == value;

  void _syncText(double value) {
    final text = context.strings.quantity(value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  double? _parseQuantity(String input) {
    final quantity = double.tryParse(
      normalizeNumberInput(input).replaceAll(',', '.'),
    );
    if (quantity == null || !quantity.isFinite || quantity <= 0) return null;
    return quantity;
  }
}

extension on double {
  String get g => this == roundToDouble() ? toInt().toString() : toString();
}
