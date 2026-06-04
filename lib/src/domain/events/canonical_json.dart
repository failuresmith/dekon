import 'dart:collection';
import 'dart:convert';

class CanonicalJsonException implements FormatException {
  CanonicalJsonException(this.message, [this.source, this.offset]);

  @override
  final String message;

  @override
  final dynamic source;

  @override
  final int? offset;

  @override
  String toString() => 'CanonicalJsonException: $message';
}

String canonicalJsonEncode(Object? value) =>
    jsonEncode(canonicalJsonValue(value));

Object? canonicalJsonValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw CanonicalJsonException('JSON numbers must be finite.');
    }
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw CanonicalJsonException('JSON numbers must be finite.');
    }
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(canonicalJsonValue));
  }
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw CanonicalJsonException('JSON object keys must be strings.');
      }
      sorted[key] = canonicalJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(sorted);
  }
  throw CanonicalJsonException('Unsupported JSON value: ${value.runtimeType}.');
}
