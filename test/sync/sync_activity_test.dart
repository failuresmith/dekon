import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('peer message log retains entries until explicitly cleared', () async {
    final bus = SyncActivityBus();
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
        ['/events?page=0', '/events?page=1', '/events?page=2'],
      );

      bus.clearPeerMessages();

      expect(bus.peerMessageSnapshot(), isEmpty);
    } finally {
      await bus.close();
    }
  });

  test(
    'peer message log trims oldest entries when the memory cap is exceeded',
    () async {
      final first = _message(path: '/events?page=1', bodyContent: 'a' * 200);
      final second = _message(path: '/events?page=2', bodyContent: 'b' * 200);
      final bus = SyncActivityBus(
        maxPeerMessageBytes:
            first.estimatedMemoryBytes + second.estimatedMemoryBytes - 1,
      );
      try {
        bus.recordPeerMessage(first);
        bus.recordPeerMessage(second);

        expect(
          [for (final message in bus.peerMessageSnapshot()) message.path],
          ['/events?page=2'],
        );
      } finally {
        await bus.close();
      }
    },
  );

  test('peer message log drops oversized single messages', () async {
    final oversized = _message(path: '/events', bodyContent: 'a' * 200);
    final bus = SyncActivityBus(
      maxPeerMessageBytes: oversized.estimatedMemoryBytes - 1,
    );
    try {
      bus.recordPeerMessage(oversized);

      expect(bus.peerMessageSnapshot(), isEmpty);
    } finally {
      await bus.close();
    }
  });
}

SyncPeerMessage _message({required String path, required String bodyContent}) {
  return SyncPeerMessage(
    timestamp: DateTime.utc(2026, 6, 5, 12),
    direction: SyncPeerMessageDirection.sent,
    method: 'GET',
    path: path,
    bodyContent: bodyContent,
  );
}
