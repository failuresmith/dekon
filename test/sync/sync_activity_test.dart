import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('peer message log keeps the newest bounded entries', () async {
    final bus = SyncActivityBus(maxPeerMessages: 2);
    try {
      for (var i = 0; i < 3; i++) {
        bus.recordPeerMessage(
          SyncPeerMessage(
            timestamp: DateTime.utc(2026, 6, 5, 12, 0, i),
            direction: SyncPeerMessageDirection.sent,
            method: 'GET',
            path: '/events?page=$i',
          ),
        );
      }

      expect(
        [for (final message in bus.peerMessageSnapshot()) message.path],
        ['/events?page=1', '/events?page=2'],
      );
    } finally {
      await bus.close();
    }
  });
}
