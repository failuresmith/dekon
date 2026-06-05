import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'ui_strings.dart';

Future<DateTimeRange?> showPersianDateRangePicker({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _PersianDateRangePickerDialog(
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange: initialDateRange,
    ),
  );
}

class _PersianDateRangePickerDialog extends StatefulWidget {
  const _PersianDateRangePickerDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialDateRange,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;

  @override
  State<_PersianDateRangePickerDialog> createState() {
    return _PersianDateRangePickerDialogState();
  }
}

class _PersianDateRangePickerDialogState
    extends State<_PersianDateRangePickerDialog> {
  late final Jalali _firstDate = _dateOnly(
    Jalali.fromDateTime(widget.firstDate),
  );
  late final Jalali _lastDate = _dateOnly(Jalali.fromDateTime(widget.lastDate));
  late final Jalali _firstMonth = Jalali(_firstDate.year, _firstDate.month);
  late final Jalali _lastMonth = Jalali(_lastDate.year, _lastDate.month);
  late Jalali _visibleMonth;
  Jalali? _start;
  Jalali? _end;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    if (initial == null) {
      _visibleMonth = _firstMonth;
      return;
    }
    final start = _clamp(_dateOnly(Jalali.fromDateTime(initial.start)));
    final end = _clamp(_dateOnly(Jalali.fromDateTime(initial.end)));
    _start = start.compareTo(end) <= 0 ? start : end;
    _end = start.compareTo(end) <= 0 ? end : start;
    _visibleMonth = Jalali(_start!.year, _start!.month);
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      scrollable: true,
      title: Text(strings.customDateRange),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _monthHeader(strings),
            const SizedBox(height: 8),
            _weekdayHeader(strings),
            const SizedBox(height: 6),
            _dayGrid(strings),
            const SizedBox(height: 12),
            _selectionSummary(strings),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: const Key('persian-date-range-apply'),
          onPressed: _start == null || _end == null ? null : _submit,
          child: Text(strings.applyDateRange),
        ),
      ],
    );
  }

  Widget _monthHeader(UiStrings strings) {
    return Row(
      children: [
        IconButton(
          key: const Key('persian-date-previous-month'),
          tooltip: strings.previousMonth,
          onPressed: _canShowPreviousMonth ? () => _shiftMonth(-1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${strings.monthName(_visibleMonth.month)} '
            '${strings.integer(_visibleMonth.year)}',
            key: const Key('persian-date-visible-month'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const Key('persian-date-next-month'),
          tooltip: strings.nextMonth,
          onPressed: _canShowNextMonth ? () => _shiftMonth(1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _weekdayHeader(UiStrings strings) {
    return Row(
      children: [
        for (final label in strings.persianWeekdayShortNames)
          Expanded(
            child: Center(
              child: Text(label, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ],
    );
  }

  Widget _dayGrid(UiStrings strings) {
    final cells = <Jalali?>[
      for (var index = 0; index < _visibleMonth.weekDay - 1; index += 1) null,
      for (var day = 1; day <= _visibleMonth.monthLength; day += 1)
        Jalali(_visibleMonth.year, _visibleMonth.month, day),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var rowStart = 0; rowStart < cells.length; rowStart += 7)
          Padding(
            padding: EdgeInsets.only(
              bottom: rowStart + 7 >= cells.length ? 0 : 4,
            ),
            child: Row(
              children: [
                for (final day in cells.skip(rowStart).take(7))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: SizedBox(
                        height: 48,
                        child: day == null
                            ? const SizedBox.shrink()
                            : _dayButton(day, strings),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dayButton(Jalali day, UiStrings strings) {
    final enabled = _isSelectable(day);
    final selected = _isSameDate(day, _start) || _isSameDate(day, _end);
    final inRange = _isInSelectedRange(day);
    final colors = Theme.of(context).colorScheme;
    final backgroundColor = selected
        ? colors.primary
        : inRange
        ? colors.primaryContainer
        : null;
    final foregroundColor = selected
        ? colors.onPrimary
        : enabled
        ? null
        : colors.onSurface.withValues(alpha: 0.38);
    return Semantics(
      selected: selected,
      button: true,
      label: strings.humanDate(day.toDateTime()),
      child: TextButton(
        key: Key('persian-date-day-${day.year}-${day.month}-${day.day}'),
        onPressed: enabled ? () => _select(day) : null,
        style: TextButton.styleFrom(
          minimumSize: const Size.square(48),
          padding: EdgeInsets.zero,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(strings.integer(day.day)),
      ),
    );
  }

  Widget _selectionSummary(UiStrings strings) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        Text(
          strings.dateRangeEndpoint(
            label: strings.startDate,
            value: _start == null
                ? strings.selectDate
                : strings.humanDate(_start!.toDateTime()),
          ),
        ),
        Text(
          strings.dateRangeEndpoint(
            label: strings.endDate,
            value: _end == null
                ? strings.selectDate
                : strings.humanDate(_end!.toDateTime()),
          ),
        ),
      ],
    );
  }

  bool get _canShowPreviousMonth => _visibleMonth.compareTo(_firstMonth) > 0;

  bool get _canShowNextMonth => _visibleMonth.compareTo(_lastMonth) < 0;

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = _visibleMonth.addMonths(delta);
    });
  }

  void _select(Jalali day) {
    setState(() {
      if (_start == null || _end != null || day.compareTo(_start!) < 0) {
        _start = day;
        _end = null;
        return;
      }
      _end = day;
    });
  }

  void _submit() {
    Navigator.pop(
      context,
      DateTimeRange(start: _start!.toDateTime(), end: _end!.toDateTime()),
    );
  }

  bool _isSelectable(Jalali date) {
    return date.compareTo(_firstDate) >= 0 && date.compareTo(_lastDate) <= 0;
  }

  bool _isInSelectedRange(Jalali date) {
    final start = _start;
    final end = _end;
    if (start == null || end == null) return false;
    return date.compareTo(start) > 0 && date.compareTo(end) < 0;
  }

  Jalali _clamp(Jalali date) {
    if (date.compareTo(_firstDate) < 0) return _firstDate;
    if (date.compareTo(_lastDate) > 0) return _lastDate;
    return date;
  }

  Jalali _dateOnly(Jalali date) => Jalali(date.year, date.month, date.day);

  bool _isSameDate(Jalali day, Jalali? other) {
    return other != null &&
        day.year == other.year &&
        day.month == other.month &&
        day.day == other.day;
  }
}
