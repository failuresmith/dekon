import 'dart:async';

import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/cashier_sync_indicator.dart';
import 'package:dekon/src/ui/cashier_sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('indicator is red when main device ping fails', (tester) async {
    final repository = await createTestRepository();
    var syncCalled = false;
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {
              throw SyncClientException('main device unavailable');
            },
            syncWithMainDevice: () async {
              syncCalled = true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-disconnected')),
        findsOneWidget,
      );
      expect(syncCalled, false);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets(
    'indicator is solid green when connected with no event transfer',
    (tester) async {
      final repository = await createTestRepository();
      final statuses = <CashierSyncStatus>[];
      try {
        await tester.pumpWidget(
          _indicatorApp(
            CashierSyncIndicator(
              repository: repository,
              pollInterval: null,
              pingMainDevice: () async {},
              syncWithMainDevice: () async {},
              onStatusChanged: statuses.add,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const Key('cashier-sync-indicator-synced')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashier-sync-indicator-breathing')),
          findsNothing,
        );
        expect(statuses.last.visualState, CashierSyncVisualState.synced);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.close();
      }
    },
  );

  testWidgets(
    'indicator stays connected when projection stream falls back after sync',
    (tester) async {
      final repository = await createTestRepository();
      final statuses = <CashierSyncStatus>[];
      try {
        await tester.pumpWidget(
          _indicatorApp(
            CashierSyncIndicator(
              repository: repository,
              pollInterval: null,
              pingMainDevice: () async {},
              syncWithMainDevice: () async {},
              openProjectionStream: () async {
                throw SyncClientException('Projection stream unavailable.');
              },
              onStatusChanged: statuses.add,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const Key('cashier-sync-indicator-degraded')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashier-sync-indicator-disconnected')),
          findsNothing,
        );
        expect(statuses.last.visualState, CashierSyncVisualState.degraded);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.close();
      }
    },
  );

  testWidgets('indicator shows conflict state when outbox is conflicted', (
    tester,
  ) async {
    final repository = await createTestRepository();
    const commandId = '019e9239-2222-7000-8000-000000000101';
    try {
      final store = repository.createSyncStore();
      await store.enqueueCashierSaleCommand(
        command: CashierSaleCommand(
          commandId: commandId,
          occurredAt: DateTime.utc(2026, 6, 4, 12),
          lines: const [
            CashierSaleCommandLine(productId: 'product-1', quantity: 1),
          ],
        ),
        lines: const [
          CashierSaleOutboxLine(
            productId: 'product-1',
            productName: 'Tea',
            quantity: 1,
            unitPriceMinor: 100,
            lineTotalMinor: 100,
          ),
        ],
      );
      await store.markCashierSaleCommandConflict(
        commandId: commandId,
        errorCode: CashierSaleCommandException.insufficientStock,
        productIds: const ['product-1'],
      );

      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {},
            syncWithMainDevice: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-conflicted')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('indicator shows unpaired state when main revokes cashier', (
    tester,
  ) async {
    final repository = await createTestRepository();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {
              throw const CashierUnpairedException();
            },
            syncWithMainDevice: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-unpaired')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('indicator retries projection stream after fallback', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final stream = StreamController<Object?>.broadcast();
    var projectionAttempts = 0;
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {},
            syncWithMainDevice: () async {},
            openProjectionStream: () async {
              projectionAttempts += 1;
              if (projectionAttempts == 1) {
                throw SyncClientException('Projection stream unavailable.');
              }
              return stream.stream;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(projectionAttempts, 1);
      expect(
        find.byKey(const Key('cashier-sync-indicator-degraded')),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump();

      expect(projectionAttempts, 2);
      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await stream.close();
      await repository.close();
    }
  });

  testWidgets('dropped projection stream refreshes before reconnecting', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final firstStream = StreamController<Object?>.broadcast();
    final secondStream = StreamController<Object?>.broadcast();
    final events = <String>[];
    final appliedMessages = <Object?>[];
    var openAttempts = 0;
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
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
              return openAttempts == 1
                  ? firstStream.stream
                  : secondStream.stream;
            },
            applyProjectionMessage: (message) async {
              events.add('apply');
              appliedMessages.add(message);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(events, ['ping', 'sync', 'open']);

      await firstStream.close();
      await tester.pump();
      await tester.pump();

      expect(events, ['ping', 'sync', 'open', 'ping', 'sync', 'open']);

      secondStream.add('fresh-delta');
      await tester.pump();
      await tester.pump();

      expect(events, ['ping', 'sync', 'open', 'ping', 'sync', 'open', 'apply']);
      expect(appliedMessages, ['fresh-delta']);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!firstStream.isClosed) await firstStream.close();
      if (!secondStream.isClosed) await secondStream.close();
      await repository.close();
    }
  });

  testWidgets('indicator breathes green for at least one second on transfer', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final transfers = StreamController<SyncTransferActivity>.broadcast();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            syncTransfers: transfers.stream,
            pingMainDevice: () async {},
            syncWithMainDevice: () async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      transfers.add(
        const SyncTransferActivity(
          direction: SyncTransferDirection.received,
          eventCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-syncing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-breathing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 999));

      expect(
        find.byKey(const Key('cashier-sync-indicator-syncing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
    } finally {
      await transfers.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets(
    'indicator is degraded when sync fails after successful ping and transfer',
    (tester) async {
      final repository = await createTestRepository();
      final transfers = StreamController<SyncTransferActivity>.broadcast();
      try {
        await tester.pumpWidget(
          _indicatorApp(
            CashierSyncIndicator(
              repository: repository,
              pollInterval: null,
              syncTransfers: transfers.stream,
              pingMainDevice: () async {},
              syncWithMainDevice: () async {
                transfers.add(
                  const SyncTransferActivity(
                    direction: SyncTransferDirection.received,
                    eventCount: 1,
                  ),
                );
                throw SyncClientException('sync failed');
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const Key('cashier-sync-indicator-syncing')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(
          find.byKey(const Key('cashier-sync-indicator-degraded')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('cashier-sync-indicator-disconnected')),
          findsNothing,
        );
      } finally {
        await transfers.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await repository.close();
      }
    },
  );

  testWidgets('indicator does not breathe only because sync is in progress', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final syncCompleter = Completer<void>();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {},
            syncWithMainDevice: () => syncCompleter.future,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-breathing')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 1500));

      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );

      syncCompleter.complete();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('indicator refreshes when the app resumes', (tester) async {
    final repository = await createTestRepository();
    var pingCount = 0;
    var syncCount = 0;
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {
              pingCount++;
            },
            syncWithMainDevice: () async {
              syncCount++;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(pingCount, 1);
      expect(syncCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(pingCount, 2);
      expect(syncCount, 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('indicator applies messages from the projection stream', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final stream = StreamController<Object?>.broadcast();
    final messages = <Object?>[];
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {},
            syncWithMainDevice: () async {},
            openProjectionStream: () async => stream.stream,
            applyProjectionMessage: (message) async {
              messages.add(message);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      stream.add('{"type":"snapshot_required","projection_version":1}');
      await tester.pump();
      await tester.pump();

      expect(messages, ['{"type":"snapshot_required","projection_version":1}']);
      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await stream.close();
      await repository.close();
    }
  });

  testWidgets('indicator stays green when projection message handling fails', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final stream = StreamController<Object?>.broadcast();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          CashierSyncIndicator(
            repository: repository,
            pollInterval: null,
            pingMainDevice: () async {},
            syncWithMainDevice: () async {},
            openProjectionStream: () async => stream.stream,
            applyProjectionMessage: (_) async {
              throw SyncClientException('Projection apply failed.');
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      stream.add('{"type":"snapshot_required","projection_version":1}');
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('cashier-sync-indicator-synced')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-disconnected')),
        findsNothing,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await stream.close();
      await repository.close();
    }
  });
}

Widget _indicatorApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
