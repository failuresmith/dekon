String formatMoney(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

int parseMoneyMinor(String input) {
  final normalized = input.trim();
  if (normalized.isEmpty) return 0;
  final value = double.tryParse(normalized);
  if (value == null || value < 0 || !value.isFinite) {
    throw const FormatException('Enter a valid non-negative amount.');
  }
  return (value * 100).round();
}
