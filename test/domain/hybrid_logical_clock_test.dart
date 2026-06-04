import 'package:dekon/src/domain/events/events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('send increments logical counter when wall clock regresses', () {
    final clock = HybridLogicalClock(nodeId: 'device-a');

    final first = clock.send(DateTime.fromMillisecondsSinceEpoch(2000));
    final second = clock.send(DateTime.fromMillisecondsSinceEpoch(1000));

    expect(second.physicalTimeMillis, first.physicalTimeMillis);
    expect(second.logicalCounter, first.logicalCounter + 1);
    expect(second.compareTo(first), greaterThan(0));
  });

  test('receive orders after remote timestamp under clock skew', () {
    final clock = HybridLogicalClock(nodeId: 'device-b');
    final remote = HybridLogicalTimestamp(
      physicalTimeMillis: 5000,
      logicalCounter: 3,
      nodeId: 'device-a',
    );

    final received = clock.receive(
      remote,
      DateTime.fromMillisecondsSinceEpoch(1000),
    );

    expect(received.physicalTimeMillis, 5000);
    expect(received.logicalCounter, 4);
    expect(received.compareTo(remote), greaterThan(0));
  });

  test('timestamp string round-trips and preserves ordering fields', () {
    const timestamp = HybridLogicalTimestamp(
      physicalTimeMillis: 42,
      logicalCounter: 7,
      nodeId: 'node',
    );

    expect(HybridLogicalTimestamp.parse(timestamp.toString()), timestamp);
  });
}
