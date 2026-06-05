import 'dart:math' as math;

import 'models.dart';

class PersianCalendarDate {
  const PersianCalendarDate({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final int month;
  final int day;
}

class PersianCalendar {
  PersianCalendar._();

  static PersianCalendarDate fromGregorian(DateTime dateTime) {
    final local = dateTime.toLocal();
    return _d2j(_g2d(local.year, local.month, local.day));
  }

  static DateTime toGregorianDate({
    required int year,
    required int month,
    required int day,
  }) {
    final gregorian = _d2g(_j2d(year, month, day));
    return DateTime(gregorian.year, gregorian.month, gregorian.day);
  }

  static ReportDateRange monthRangeContaining(DateTime dateTime) {
    final persian = fromGregorian(dateTime);
    final start = toGregorianDate(
      year: persian.year,
      month: persian.month,
      day: 1,
    );
    return ReportDateRange(
      startLocal: start,
      endLocalExclusive: addMonths(start, 1),
    );
  }

  static ReportDateRange yearRangeContaining(DateTime dateTime) {
    final persian = fromGregorian(dateTime);
    final start = toGregorianDate(year: persian.year, month: 1, day: 1);
    final end = toGregorianDate(year: persian.year + 1, month: 1, day: 1);
    return ReportDateRange(startLocal: start, endLocalExclusive: end);
  }

  static DateTime addMonths(DateTime dateTime, int monthDelta) {
    final persian = fromGregorian(dateTime);
    final targetMonthIndex = persian.year * 12 + persian.month - 1 + monthDelta;
    final year = targetMonthIndex ~/ 12;
    final month = targetMonthIndex % 12 + 1;
    final day = math.min(persian.day, daysInMonth(year, month));
    return toGregorianDate(year: year, month: month, day: day);
  }

  static int daysInMonth(int year, int month) {
    if (month <= 6) return 31;
    if (month <= 11) return 30;
    return isLeapYear(year) ? 30 : 29;
  }

  static bool isLeapYear(int year) => _jalCal(year).leap == 0;

  static int _g2d(int gy, int gm, int gd) {
    var day =
        ((gy + ((gm - 8) ~/ 6) + 100100) * 1461) ~/ 4 +
        (153 * ((gm + 9) % 12) + 2) ~/ 5 +
        gd -
        34840408;
    day -= (((gy + 100100 + ((gm - 8) ~/ 6)) ~/ 100) * 3) ~/ 4 - 752;
    return day;
  }

  static _GregorianDate _d2g(int jdn) {
    var value = 4 * jdn + 139361631;
    value += (((((4 * jdn + 183187720) ~/ 146097) * 3) ~/ 4) * 4) - 3908;
    final index = ((value % 1461) ~/ 4) * 5 + 308;
    final day = ((index % 153) ~/ 5) + 1;
    final month = ((index ~/ 153) % 12) + 1;
    final year = (value ~/ 1461) - 100100 + (8 - month) ~/ 6;
    return _GregorianDate(year: year, month: month, day: day);
  }

  static PersianCalendarDate _d2j(int jdn) {
    final gy = _d2g(jdn).year;
    var jy = gy - 621;
    final calibration = _jalCal(jy);
    final firstFarvardin = _g2d(gy, 3, calibration.march);
    var dayOfYear = jdn - firstFarvardin;
    if (dayOfYear >= 0) {
      if (dayOfYear <= 185) {
        return PersianCalendarDate(
          year: jy,
          month: 1 + dayOfYear ~/ 31,
          day: dayOfYear % 31 + 1,
        );
      }
      dayOfYear -= 186;
    } else {
      jy -= 1;
      dayOfYear += calibration.leap == 1 ? 180 : 179;
    }
    return PersianCalendarDate(
      year: jy,
      month: 7 + dayOfYear ~/ 30,
      day: dayOfYear % 30 + 1,
    );
  }

  static int _j2d(int jy, int jm, int jd) {
    final calibration = _jalCal(jy);
    return _g2d(calibration.gy, 3, calibration.march) +
        (jm - 1) * 31 -
        (jm ~/ 7) * (jm - 7) +
        jd -
        1;
  }

  static _PersianCalibration _jalCal(int jy) {
    const breaks = [
      -61,
      9,
      38,
      199,
      426,
      686,
      756,
      818,
      1111,
      1181,
      1210,
      1635,
      2060,
      2097,
      2192,
      2262,
      2324,
      2394,
      2456,
      3178,
    ];
    if (jy < breaks.first || jy >= breaks.last) {
      throw RangeError.value(jy, 'year', 'Unsupported Persian calendar year');
    }

    final gy = jy + 621;
    var leapJ = -14;
    var jp = breaks.first;
    var jump = 0;
    for (var index = 1; index < breaks.length; index += 1) {
      final jm = breaks[index];
      jump = jm - jp;
      if (jy < jm) break;
      leapJ += (jump ~/ 33) * 8 + _mod(jump, 33) ~/ 4;
      jp = jm;
    }
    var n = jy - jp;
    leapJ += (n ~/ 33) * 8 + (_mod(n, 33) + 3) ~/ 4;
    if (_mod(jump, 33) == 4 && jump - n == 4) leapJ += 1;

    final leapG = gy ~/ 4 - (((gy ~/ 100) + 1) * 3) ~/ 4 - 150;
    final march = 20 + leapJ - leapG;
    if (jump - n < 6) n = n - jump + ((jump + 4) ~/ 33) * 33;
    var leap = _mod(_mod(n + 1, 33) - 1, 4);
    if (leap == -1) leap = 4;
    return _PersianCalibration(gy: gy, march: march, leap: leap);
  }

  static int _mod(int value, int divisor) {
    return value - (value ~/ divisor) * divisor;
  }
}

class _GregorianDate {
  const _GregorianDate({
    required this.year,
    required this.month,
    required this.day,
  });

  final int year;
  final int month;
  final int day;
}

class _PersianCalibration {
  const _PersianCalibration({
    required this.gy,
    required this.march,
    required this.leap,
  });

  final int gy;
  final int march;
  final int leap;
}
