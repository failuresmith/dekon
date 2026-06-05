import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/ui/persian_date_range_picker.dart';
import 'package:dekon/src/ui/ui_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets(
    'Persian date range picker shows Jalali calendar and returns range',
    (tester) async {
      DateTimeRange? pickedRange;

      await tester.pumpWidget(
        _pickerTestApp(
          onPicked: (range) => pickedRange = range,
          initialDateRange: DateTimeRange(
            start: DateTime(2026, 6, 5),
            end: DateTime(2026, 6, 5),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-persian-date-picker')));
      await tester.pumpAndSettle();

      expect(find.text('خرداد ۱۴۰۵'), findsOneWidget);
      expect(
        find.byKey(const Key('persian-date-visible-month')),
        findsOneWidget,
      );
      expect(find.textContaining('June'), findsNothing);

      await tester.tap(find.byKey(const Key('persian-date-day-1405-3-10')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persian-date-day-1405-3-15')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('persian-date-range-apply')));
      await tester.pumpAndSettle();

      expect(pickedRange?.start, DateTime(2026, 5, 31));
      expect(pickedRange?.end, DateTime(2026, 6, 5));
    },
  );

  testWidgets('Reports custom range opens Persian picker in Farsi', (
    tester,
  ) async {
    final repository = await createTestRepository(onboarded: true);
    await repository.setAppLanguage(AppLanguage.farsi);

    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('گزارش ها'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-period-custom')));
    await tester.pumpAndSettle();

    expect(find.text('بازه دلخواه'), findsOneWidget);
    expect(find.byKey(const Key('persian-date-visible-month')), findsOneWidget);
  });
}

Widget _pickerTestApp({
  required ValueChanged<DateTimeRange?> onPicked,
  required DateTimeRange initialDateRange,
}) {
  final controller = AppLanguageController(
    initialLanguage: AppLanguage.farsi,
    initialMoneyUnit: MoneyUnit.rial,
    saveLanguage: (_) async {},
    saveMoneyUnit: (_) async {},
  );
  return MaterialApp(
    builder: (context, child) => AppLanguageScope(
      controller: controller,
      child: Directionality(
        textDirection: controller.strings.textDirection,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            key: const Key('open-persian-date-picker'),
            onPressed: () async {
              onPicked(
                await showPersianDateRangePicker(
                  context: context,
                  firstDate: DateTime(2021),
                  lastDate: DateTime(2030, 12, 31),
                  initialDateRange: initialDateRange,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}
