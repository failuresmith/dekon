import 'models.dart';

String formatMoney(int rialValue) =>
    formatMoneyForUnit(rialValue, unit: MoneyUnit.rial);

String formatMoneyForUnit(int rialValue, {required MoneyUnit unit}) {
  return switch (unit) {
    MoneyUnit.rial => _formatGroupedNumber(rialValue.toString()),
    MoneyUnit.toman => _formatTomanValue(rialValue),
  };
}

String normalizeNumberInput(String input) {
  const replacements = {
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '٫': '.',
    '٬': '',
    ',': '',
  };
  var normalized = input.trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}

int parseMoneyRial(String input, {required MoneyUnit unit}) {
  final normalized = normalizeNumberInput(input);
  if (normalized.isEmpty) return 0;
  final value = double.tryParse(normalized);
  if (value == null || value < 0 || !value.isFinite) {
    throw const FormatException('Enter a valid non-negative amount.');
  }
  final rialValue = switch (unit) {
    MoneyUnit.rial => value,
    MoneyUnit.toman => value * 10,
  };
  if (rialValue != rialValue.roundToDouble()) {
    throw const FormatException('Enter a valid Rial amount.');
  }
  return rialValue.round();
}

String _formatTomanValue(int rialValue) {
  final negative = rialValue.isNegative;
  final absolute = rialValue.abs();
  final whole = absolute ~/ 10;
  final remainder = absolute % 10;
  final sign = negative ? '-' : '';
  if (remainder == 0) return '$sign${_formatGroupedNumber(whole.toString())}';
  return '$sign${_formatGroupedNumber(whole.toString())}.$remainder';
}

String _formatGroupedNumber(String value) {
  final negative = value.startsWith('-');
  final digits = negative ? value.substring(1) : value;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}
