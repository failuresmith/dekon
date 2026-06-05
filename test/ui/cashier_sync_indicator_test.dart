import 'dart:async';

import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/cashier_sync_indicator.dart';
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

  testWidgets('indicator breathes green for at least one second on fast sync', (
    tester,
  ) async {
    final repository = await createTestRepository();
    try {
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
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('indicator keeps breathing while long sync is in progress', (
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
        find.byKey(const Key('cashier-sync-indicator-syncing')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-breathing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1500));

      expect(
        find.byKey(const Key('cashier-sync-indicator-syncing')),
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
}

Widget _indicatorApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}
