import 'dart:async';

import 'package:dekon/src/ui/cashier_sync_controller.dart';
import 'package:dekon/src/ui/cashier_sync_status.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  test(
    'controller starts foreground sync without widget mount internals',
    () async {
      final repository = await createTestRepository();
      final statuses = <CashierSyncStatus>[];
      var pingCount = 0;
      var syncCount = 0;
      final controller = CashierSyncController(
        repository: repository,
        pollInterval: null,
        pingMainDevice: () async {
          pingCount += 1;
        },
        syncWithMainDevice: () async {
          syncCount += 1;
        },
      );
      final subscription = controller.statusChanges.listen(statuses.add);
      try {
        controller.start();
        await _flush();

        expect(pingCount, 1);
        expect(syncCount, 1);
        expect(statuses.last.visualState, CashierSyncVisualState.synced);
      } finally {
        await subscription.cancel();
        await controller.dispose();
        await repository.close();
      }
    },
  );

  test(
    'app resume refreshes snapshot before reopening projection stream',
    () async {
      final repository = await createTestRepository();
      final firstStream = StreamController<Object?>.broadcast();
      final secondStream = StreamController<Object?>.broadcast();
      final events = <String>[];
      var openAttempts = 0;
      final controller = CashierSyncController(
        repository: repository,
        pollInterval: null,
        pingMainDevice: () async {
          events.add('ping');
        },
        syncWithMainDevice: () async {
          events.add('sync');
        },
        openProjectionStream: () async {
          events.add('open');
          openAttempts += 1;
          return openAttempts == 1 ? firstStream.stream : secondStream.stream;
        },
      );
      try {
        controller.start();
        await _flush();

        controller.handleLifecycleState(AppLifecycleState.paused);
        controller.handleLifecycleState(AppLifecycleState.resumed);
        await _flush();

        expect(events, ['ping', 'sync', 'open', 'ping', 'sync', 'open']);
      } finally {
        await controller.dispose();
        if (!firstStream.isClosed) await firstStream.close();
        if (!secondStream.isClosed) await secondStream.close();
        await repository.close();
      }
    },
  );

  test('controller serializes overlapping refresh triggers', () async {
    final repository = await createTestRepository();
    final firstSync = Completer<void>();
    var syncCount = 0;
    var activeSyncs = 0;
    var maxActiveSyncs = 0;
    final controller = CashierSyncController(
      repository: repository,
      pollInterval: null,
      pingMainDevice: () async {},
      syncWithMainDevice: () async {
        syncCount += 1;
        activeSyncs += 1;
        if (activeSyncs > maxActiveSyncs) maxActiveSyncs = activeSyncs;
        if (syncCount == 1) await firstSync.future;
        activeSyncs -= 1;
      },
    );
    try {
      controller.start();
      await _flush();

      await repository.createProduct(name: 'Queued Refresh');
      await _flush();
      firstSync.complete();
      await _flush();

      expect(syncCount, 2);
      expect(maxActiveSyncs, 1);
    } finally {
      await controller.dispose();
      await repository.close();
    }
  });
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
