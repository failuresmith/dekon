import 'dart:math' as math;

import 'package:shamsi_date/shamsi_date.dart';

import 'models.dart';

class PersianCalendarDate {
  const PersianCalendarDate({
    required this.year,
    required this.month,
    required this.day,
  });

  factory PersianCalendarDate.fromJalali(Jalali date) {
    return PersianCalendarDate(
      year: date.year,
      month: date.month,
      day: date.day,
    );
  }

  final int year;
  final int month;
  final int day;
}

class PersianCalendar {
  PersianCalendar._();

  static PersianCalendarDate fromGregorian(DateTime dateTime) {
    return PersianCalendarDate.fromJalali(
      Jalali.fromDateTime(dateTime.toLocal()),
    );
  }

  static DateTime toGregorianDate({
    required int year,
    required int month,
    required int day,
  }) {
    return Jalali(year, month, day).toDateTime();
  }

  static ReportDateRange monthRangeContaining(DateTime dateTime) {
    final persian = Jalali.fromDateTime(dateTime.toLocal());
    final start = Jalali(persian.year, persian.month).toDateTime();
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: addMonths(start, 1),
    );
  }

  static ReportDateRange yearRangeContaining(DateTime dateTime) {
    final persian = Jalali.fromDateTime(dateTime.toLocal());
    final start = Jalali(persian.year).toDateTime();
    final end = Jalali(persian.year + 1).toDateTime();
    return ReportDateRange(startLocal: start, endLocalExclusive: end);
  }

  static DateTime addMonths(DateTime dateTime, int monthDelta) {
    final persian = Jalali.fromDateTime(dateTime.toLocal());
    final targetMonthIndex = persian.year * 12 + persian.month - 1 + monthDelta;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final day = math.min(persian.day, daysInMonth(year, month));
    return Jalali(
      year,
      month,
      day,
      persian.hour,
      persian.minute,
      persian.second,
      persian.millisecond,
    ).toDateTime();
  }

  static int daysInMonth(int year, int month) {
    return Jalali(year, month).monthLength;
  }

  static bool isLeapYear(int year) {
    return Jalali(year).isLeapYear();
  }
}
