import 'package:dekon/src/domain/events/events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical JSON sorts object keys recursively', () {
    final left = canonicalJsonEncode({
      'z': [
        {'b': 2, 'a': 1},
      ],
      'a': true,
    });

    expect(left, '{"a":true,"z":[{"a":1,"b":2}]}');
  });

  test('payload hash is stable across map insertion order', () {
    final first = payloadHash({
      'name': 'Coffee',
      'prices': {'sale': 12, 'cost': 7},
    });
    final second = payloadHash({
      'prices': {'cost': 7, 'sale': 12},
      'name': 'Coffee',
    });

    expect(first, second);
  });

  test('canonical JSON rejects non-finite numbers', () {
    expect(
      () => canonicalJsonEncode({'bad': double.nan}),
      throwsA(isA<CanonicalJsonException>()),
    );
  });
}
