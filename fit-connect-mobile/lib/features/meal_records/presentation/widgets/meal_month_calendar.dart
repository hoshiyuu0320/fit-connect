import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'record_date_format.dart';
import 'record_month_card.dart';

/// 月カレンダー（食事を記録した日に単色の点）。
///
/// 月の移動（前の月・次の月）はここで持ち、変わったら [onMonthChanged] で知らせる。
/// 見た目は共通の [RecordMonthCard]（運動タブと同じ）。回数の濃淡（緑）は使わない。
class MealMonthCalendar extends ConsumerStatefulWidget {
  final void Function(DateTime date, int mealCount)? onDayTap;
  final void Function(DateTime month)? onMonthChanged;

  /// 最初に出す月（月初）。null なら今月。
  /// 親が月を覚えている画面で、スクロールで作り直されても同じ月に戻すために使う
  final DateTime? initialMonth;

  const MealMonthCalendar({
    super.key,
    this.onDayTap,
    this.onMonthChanged,
    this.initialMonth,
  });

  @override
  ConsumerState<MealMonthCalendar> createState() => _MealMonthCalendarState();
}

class _MealMonthCalendarState extends ConsumerState<MealMonthCalendar> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initial = widget.initialMonth;
    _currentMonth = initial != null
        ? DateTime(initial.year, initial.month, 1)
        : DateTime(now.year, now.month, 1);
  }

  void _previousMonth() {
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    setState(() => _currentMonth = newMonth);
    widget.onMonthChanged?.call(newMonth);
  }

  void _nextMonth() {
    final now = DateTime.now();
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (!newMonth.isAfter(DateTime(now.year, now.month, 1))) {
      setState(() => _currentMonth = newMonth);
      widget.onMonthChanged?.call(newMonth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentMonth =
        _currentMonth.year == now.year && _currentMonth.month == now.month;

    // 月末の 23:59:59 までを問い合わせる（0:00 だと最終日の記録が落ちる）
    final countsAsync = ref.watch(
      mealRecordCountsProvider(
        startDate: _currentMonth,
        endDate: recordMonthEndOf(_currentMonth),
      ),
    );
    final counts = countsAsync.valueOrNull;

    return RecordMonthCard(
      month: _currentMonth,
      recordedDays: counts == null
          ? null
          : {
              for (final entry in counts.entries)
                if (entry.value > 0) recordDayOf(entry.key),
            },
      hasError: countsAsync.hasError && !countsAsync.hasValue,
      onRetry: () => ref.invalidate(mealRecordCountsProvider),
      onPreviousMonth: _previousMonth,
      onNextMonth: isCurrentMonth ? null : _nextMonth,
      onDayTap: widget.onDayTap == null
          ? null
          : (date) => widget.onDayTap!(date, counts?[date] ?? 0),
    );
  }
}

// ============================================
// Previews
// ============================================

// MealMonthCalendar は Riverpod のプロバイダーを使うので、プレビューは同じ見た目の
// RecordMonthCard を静的なデータで出したもの。

Widget _previewApp(Brightness brightness, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

RecordMonthCard _previewCard({bool loading = false}) {
  final now = DateTime.now();
  return RecordMonthCard(
    month: DateTime(now.year, now.month, 1),
    recordedDays: loading
        ? null
        : {
            for (var day = 1; day <= now.day; day++)
              if (day % 3 != 0) DateTime(now.year, now.month, day),
          },
    onPreviousMonth: () {},
  );
}

@Preview(name: 'MealMonthCalendar - 食事を記録した日')
Widget previewMealMonthCalendar() =>
    _previewApp(Brightness.light, _previewCard());

@Preview(name: 'MealMonthCalendar - ダーク')
Widget previewMealMonthCalendarDark() =>
    _previewApp(Brightness.dark, _previewCard());

@Preview(name: 'MealMonthCalendar - 読込中')
Widget previewMealMonthCalendarLoading() =>
    _previewApp(Brightness.light, _previewCard(loading: true));
