import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/domain/events/events.dart';
import 'package:dekon/src/persistence/persistence.dart';
import 'package:dekon/src/sync/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/event_fixtures.dart';
import '../helpers/test_app.dart';

const _remoteCashierDeviceId = '018f2f12-7b60-7a15-8c7d-000000000002';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'report summary totals are scoped to the requested local date range',
    () async {
      final repository = await createTestRepository(onboarded: true);
      final product = await repository.createProduct(
        name: 'Range Tea',
        barcode: 'RANGE-TEA',
        salePriceMinor: 400,
        purchaseCostMinor: 150,
      );
      await repository.recordPurchase([
        TransactionLineDraft(product: product, quantity: 2),
      ]);
      await repository.recordSale([
        TransactionLineDraft(product: product, quantity: 1),
      ]);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final todaySummary = await repository.reportSummary(
        range: ReportDateRange(
          startLocal: today,
          endLocalExclusive: today.add(const Duration(days: 1)),
        ),
      );
      final futureSummary = await repository.reportSummary(
        range: ReportDateRange(
          startLocal: DateTime(2099),
          endLocalExclusive: DateTime(2099, 1, 2),
        ),
      );

      expect(todaySummary.salesMinor, 400);
      expect(todaySummary.purchasesMinor, 300);
      expect(todaySummary.grossMarginMinor, 250);
      expect(futureSummary.salesMinor, 0);
      expect(futureSummary.purchasesMinor, 0);
      expect(futureSummary.grossMarginMinor, 0);

      final dayTrend = await repository.reportTrend(
        period: ReportTrendPeriod.day,
        anchorLocal: now,
      );
      final weekTrend = await repository.reportTrend(
        period: ReportTrendPeriod.week,
        anchorLocal: now,
      );
      final monthTrend = await repository.reportTrend(
        period: ReportTrendPeriod.month,
        anchorLocal: now,
      );
      final yearTrend = await repository.reportTrend(
        period: ReportTrendPeriod.year,
        anchorLocal: now,
      );

      expect(dayTrend, hasLength(7));
      expect(dayTrend.last.salesMinor, 400);
      expect(dayTrend.last.purchasesMinor, 300);
      expect(weekTrend, hasLength(8));
      expect(monthTrend, hasLength(12));
      expect(yearTrend, hasLength(5));
    },
  );

  test('Persian report trends use Iranian calendar boundaries', () async {
    final repository = await createTestRepository(onboarded: true);
    final anchor = DateTime(2026, 6, 5);

    final weekTrend = await repository.reportTrend(
      period: ReportTrendPeriod.week,
      calendar: ReportCalendar.persian,
      anchorLocal: anchor,
    );
    final monthTrend = await repository.reportTrend(
      period: ReportTrendPeriod.month,
      calendar: ReportCalendar.persian,
      anchorLocal: anchor,
    );
    final yearTrend = await repository.reportTrend(
      period: ReportTrendPeriod.year,
      calendar: ReportCalendar.persian,
      anchorLocal: anchor,
    );
    final gregorianMonthTrend = await repository.reportTrend(
      period: ReportTrendPeriod.month,
      anchorLocal: anchor,
    );

    expect(weekTrend.last.range.startLocal, DateTime(2026, 5, 30));
    expect(weekTrend.last.range.endLocalExclusive, DateTime(2026, 6, 6));
    expect(monthTrend.last.range.startLocal, DateTime(2026, 5, 22));
    expect(monthTrend.last.range.endLocalExclusive, DateTime(2026, 6, 22));
    expect(yearTrend.last.range.startLocal, DateTime(2026, 3, 21));
    expect(yearTrend.last.range.endLocalExclusive, DateTime(2027, 3, 21));
    expect(gregorianMonthTrend.last.range.startLocal, DateTime(2026, 6));
  });

  test(
    'report summary counts local events waiting for outbound sync',
    () async {
      final db = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final repository = await DekonRepository.open(database: db);
      try {
        await repository.completeDeviceOnboarding(DeviceRole.mainDevice);
        final product = await repository.createProduct(
          name: 'Sync Tea',
          barcode: 'SYNC-TEA',
          salePriceMinor: 400,
          purchaseCostMinor: 150,
        );
        await repository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 2),
        ]);

        expect((await repository.reportSummary()).unsyncedEventCount, 0);

        final syncStore = repository.createSyncStore();
        await syncStore.trustPeer(
          deviceId: _remoteCashierDeviceId,
          displayName: 'Main Register',
          sharedSecret: 'shared-secret',
          baseUrl: 'http://main.local',
        );

        expect((await repository.reportSummary()).unsyncedEventCount, 2);

        final events = await syncStore.fetchEventsAfter(null, limit: 100);
        await syncStore.updatePushCursor(
          _remoteCashierDeviceId,
          SyncCursor.fromEvent(events.last),
        );

        expect((await repository.reportSummary()).unsyncedEventCount, 0);

        await _appendRemoteTransactions(db, product.productId);

        expect((await repository.reportSummary()).unsyncedEventCount, 0);

        await repository.recordSale([
          TransactionLineDraft(product: product, quantity: 1),
        ]);

        expect((await repository.reportSummary()).unsyncedEventCount, 1);
      } finally {
        await repository.close();
      }
    },
  );

  test(
    'local-device report scope excludes transactions from other devices',
    () async {
      final db = await CoreDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final repository = await DekonRepository.open(database: db);
      try {
        await repository.completeDeviceOnboarding(DeviceRole.cashierDevice);
        final product = await repository.createProduct(
          name: 'Scoped Tea',
          barcode: 'SCOPED-TEA',
          salePriceMinor: 400,
          purchaseCostMinor: 150,
        );
        await repository.recordPurchase([
          TransactionLineDraft(product: product, quantity: 2),
        ]);
        await repository.recordSale([
          TransactionLineDraft(product: product, quantity: 1),
        ]);
        await repository.createSyncStore().trustPeer(
          deviceId: _remoteCashierDeviceId,
          displayName: 'Cashier-1',
          sharedSecret: 'shared-secret',
        );
        await _appendRemoteTransactions(db, product.productId);

        final today = DateTime.now();
        final range = ReportDateRange(
          startLocal: DateTime(today.year, today.month, today.day),
          endLocalExclusive: DateTime(
            today.year,
            today.month,
            today.day,
          ).add(const Duration(days: 1)),
        );
        final localSummary = await repository.reportSummary(
          range: range,
          scope: ReportScope.localDevice,
        );
        final allSummary = await repository.reportSummary(
          range: range,
          scope: ReportScope.allDevices,
        );
        final localSales = await repository.transactionHistory(
          TransactionHistoryKind.sale,
          range: range,
          scope: ReportScope.localDevice,
          limit: null,
        );
        final cashierFilters = await repository.cashierReportFilters();
        final selectedCashierSummary = await repository.reportSummary(
          range: range,
          deviceId: _remoteCashierDeviceId,
        );
        final selectedCashierTrend = await repository.reportTrend(
          period: ReportTrendPeriod.day,
          deviceId: _remoteCashierDeviceId,
        );

        expect(localSummary.salesMinor, 400);
        expect(localSummary.purchasesMinor, 300);
        expect(localSummary.grossMarginMinor, 250);
        expect(allSummary.salesMinor, 1200);
        expect(allSummary.purchasesMinor, 900);
        expect(allSummary.grossMarginMinor, 750);
        expect(localSales, hasLength(1));
        expect(cashierFilters.single.deviceId, _remoteCashierDeviceId);
        expect(cashierFilters.single.label, 'Cashier-1');
        expect(selectedCashierSummary.salesMinor, 800);
        expect(selectedCashierSummary.purchasesMinor, 600);
        expect(selectedCashierSummary.grossMarginMinor, 500);
        expect(selectedCashierTrend.last.salesMinor, 800);
        expect(selectedCashierTrend.last.purchasesMinor, 600);
      } finally {
        await repository.close();
      }
    },
  );
}

Future<void> _appendRemoteTransactions(Database db, String productId) async {
  final store = EventStore(db);
  final projector = DomainProjector(db);
  final now = DateTime.now().toUtc();
  final purchase = makeTestEvent(
    eventId: '018f2f12-7b60-7a15-8c7d-000000400001',
    deviceId: _remoteCashierDeviceId,
    type: EventTypes.inventoryPurchaseRecorded,
    entityId: 'remote-purchase-1',
    physicalTimeMillis: now.millisecondsSinceEpoch,
    createdAt: now,
    payload: {
      'occurred_at': now.toIso8601String(),
      'total_minor': 600,
      'line_items': [
        {'product_id': productId, 'quantity': 4, 'unit_cost_minor': 150},
      ],
    },
  );
  final sale = makeTestEvent(
    eventId: '018f2f12-7b60-7a15-8c7d-000000400002',
    deviceId: _remoteCashierDeviceId,
    type: EventTypes.inventorySaleRecorded,
    entityId: 'remote-sale-1',
    physicalTimeMillis: now.millisecondsSinceEpoch + 1,
    createdAt: now.add(const Duration(milliseconds: 1)),
    payload: {
      'occurred_at': now.toIso8601String(),
      'total_minor': 800,
      'line_items': [
        {'product_id': productId, 'quantity': 2, 'unit_price_minor': 400},
      ],
    },
  );
  for (final event in [purchase, sale]) {
    await store.append(event);
    await projector.apply(event);
  }
}
