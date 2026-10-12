import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_month_card.dart';

/// 運動の月カレンダー。運動した日（記録とプランの完了）に単色の点を付ける。
///
/// 回数の濃淡（青）はやめ、食事タブと同じ [RecordMonthCard] の「点」表現に揃えた。
/// 表示する月と、前の月・次の月は画面が持つ（一覧が同じ月になるように）。
class ExerciseMonthCalendar extends StatelessWidget {
  const ExerciseMonthCalendar({
    super.key,
    required this.month,
    required this.recordedDays,
    this.hasError = false,
    this.onRetry,
    this.onPreviousMonth,
    this.onNextMonth,
  });

  /// 表示する月（月初）
  final DateTime month;

  /// 運動した日（日付だけにした値）。null は読込中
  final Set<DateTime>? recordedDays;

  final bool hasError;
  final VoidCallback? onRetry;

  /// 前の月
  final VoidCallback? onPreviousMonth;

  /// 次の月。null なら押せない（今月より先へは進まない）
  final VoidCallback? onNextMonth;

  @override
  Widget build(BuildContext context) {
    return RecordMonthCard(
      month: month,
      recordedDays: recordedDays,
      hasError: hasError,
      onRetry: onRetry,
      onPreviousMonth: onPreviousMonth,
      onNextMonth: onNextMonth,
    );
  }
}

// ============================================
// Previews
// ============================================

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

Set<DateTime> _previewDays() {
  final now = DateTime.now();
  return {
    for (var day = 1; day <= now.day; day += 2)
      DateTime(now.year, now.month, day),
  };
}

@Preview(name: 'ExerciseMonthCalendar - 通常')
Widget previewExerciseMonthCalendar() {
  final now = DateTime.now();
  return _previewApp(
    Brightness.light,
    ExerciseMonthCalendar(
      month: DateTime(now.year, now.month, 1),
      recordedDays: _previewDays(),
      onPreviousMonth: () {},
    ),
  );
}

@Preview(name: 'ExerciseMonthCalendar - ダーク')
Widget previewExerciseMonthCalendarDark() {
  final now = DateTime.now();
  return _previewApp(
    Brightness.dark,
    ExerciseMonthCalendar(
      month: DateTime(now.year, now.month, 1),
      recordedDays: _previewDays(),
      onPreviousMonth: () {},
    ),
  );
}

@Preview(name: 'ExerciseMonthCalendar - 読込中')
Widget previewExerciseMonthCalendarLoading() {
  final now = DateTime.now();
  return _previewApp(
    Brightness.light,
    ExerciseMonthCalendar(
      month: DateTime(now.year, now.month, 1),
      recordedDays: null,
      onPreviousMonth: () {},
    ),
  );
}
