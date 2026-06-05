import 'dart:async';

import 'package:dekon/src/sync/sync.dart';
import 'package:dekon/src/ui/main_cashier_connection_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('main indicator stays hidden when no cashier is connected', (
    tester,
  ) async {
    final repository = await createTestRepository();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          MainCashierConnectionIndicator(
            repository: repository,
            pollInterval: null,
            isCashierConnected: () async => false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('main-cashier-connection-indicator')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-disconnected')),
        findsNothing,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('main indicator is solid green when a cashier is connected', (
    tester,
  ) async {
    final repository = await createTestRepository();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          MainCashierConnectionIndicator(
            repository: repository,
            pollInterval: null,
            isCashierConnected: () async => true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-connected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('main-cashier-connection-indicator-breathing')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 999));

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-connected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashier-sync-indicator-disconnected')),
        findsNothing,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.close();
    }
  });

  testWidgets('main indicator breathes during cashier event transfer', (
    tester,
  ) async {
    final repository = await createTestRepository();
    final transfers = StreamController<SyncTransferActivity>.broadcast();
    try {
      await tester.pumpWidget(
        _indicatorApp(
          MainCashierConnectionIndicator(
            repository: repository,
            pollInterval: null,
            syncTransfers: transfers.stream,
            isCashierConnected: () async => true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      transfers.add(
        const SyncTransferActivity(
          direction: SyncTransferDirection.sent,
          eventCount: 1,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-breathing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 999));

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-breathing')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(
        find.byKey(const Key('main-cashier-connection-indicator-breathing')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('main-cashier-connection-indicator-connected')),
        findsOneWidget,
      );
    } finally {
      await transfers.close();
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
