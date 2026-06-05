import 'package:dekon/src/application/application.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
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
    },
  );
}
