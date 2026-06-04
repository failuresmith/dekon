import 'package:dekon/src/domain/events/events.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/event_fixtures.dart';

void main() {
  test('accepts a valid supported event envelope', () {
    final result = EventValidator.validateForStorage(makeTestEvent());

    expect(result.disposition, EventValidationDisposition.supported);
  });

  test('rejects payload hash mismatch', () {
    expect(
      () => EventValidator.validateForStorage(
        makeTestEvent(payloadHashOverride: 'not-a-real-hash'),
      ),
      throwsA(isA<EventValidationException>()),
    );
  });

  test('rejects unknown event type for current schema', () {
    expect(
      () => EventValidator.validateForStorage(makeTestEvent(type: 'unknown')),
      throwsA(isA<EventValidationException>()),
    );
  });

  test('classifies future schemas as unsupported but storable', () {
    final result = EventValidator.validateForStorage(
      makeTestEvent(schemaVersion: EventSchema.currentVersion + 1),
    );

    expect(result.disposition, EventValidationDisposition.unsupportedSchema);
    expect(result.unsupportedReason, contains('newer than supported'));
  });
}
