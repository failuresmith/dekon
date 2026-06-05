import 'package:dekon/src/application/application.dart';
import 'package:dekon/src/ui/ui_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts Gregorian dates to Persian calendar dates', () {
    final current = PersianCalendar.fromGregorian(DateTime(2026, 6, 5));
    final nowruz = PersianCalendar.fromGregorian(DateTime(2026, 3, 21));
    final leapYearEnd = PersianCalendar.fromGregorian(DateTime(2025, 3, 20));

    expect(current.year, 1405);
    expect(current.month, 3);
    expect(current.day, 15);
    expect(nowruz.year, 1405);
    expect(nowruz.month, 1);
    expect(nowruz.day, 1);
    expect(leapYearEnd.year, 1403);
    expect(leapYearEnd.month, 12);
    expect(leapYearEnd.day, 30);
  });

  test('converts Persian dates back to local Gregorian dates', () {
    expect(
      PersianCalendar.toGregorianDate(year: 1405, month: 1, day: 1),
      DateTime(2026, 3, 21),
    );
    expect(
      PersianCalendar.toGregorianDate(year: 1403, month: 12, day: 30),
      DateTime(2025, 3, 20),
    );
  });

  test('builds Persian month and year report ranges', () {
    final month = PersianCalendar.monthRangeContaining(DateTime(2026, 6, 5));
    final year = PersianCalendar.yearRangeContaining(DateTime(2026, 6, 5));

    expect(month.startLocal, DateTime(2026, 5, 22));
    expect(month.endLocalExclusive, DateTime(2026, 6, 22));
    expect(year.startLocal, DateTime(2026, 3, 21));
    expect(year.endLocalExclusive, DateTime(2027, 3, 21));
  });

  test('formats Farsi dates with Persian calendar values', () {
    final strings = UiStrings.forPreferences(
      language: AppLanguage.farsi,
      moneyUnit: MoneyUnit.rial,
    );
    final dateTime = DateTime(2026, 6, 5, 9, 8, 7);

    expect(strings.timestamp(dateTime), '۱۴۰۵/۰۳/۱۵ ۰۹:۰۸:۰۷');
    expect(strings.humanDate(dateTime), '۱۵ خرداد ۱۴۰۵');
    expect(strings.monthYear(dateTime), 'خرداد ۱۴۰۵');
    expect(strings.shortNumericDate(dateTime), '۳/۱۵');
  });

  test('keeps English date formatting Gregorian', () {
    final strings = UiStrings.forPreferences(
      language: AppLanguage.english,
      moneyUnit: MoneyUnit.rial,
    );
    final dateTime = DateTime(2026, 6, 5, 9, 8, 7);

    expect(strings.timestamp(dateTime), '2026-06-05 09:08:07');
    expect(strings.humanDate(dateTime), '5 June 2026');
    expect(strings.monthYear(dateTime), 'June 2026');
    expect(strings.shortNumericDate(dateTime), '6/5');
  });
}
