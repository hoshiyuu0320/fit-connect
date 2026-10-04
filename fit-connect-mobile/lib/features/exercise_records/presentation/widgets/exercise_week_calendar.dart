import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_date_format.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'exercise_kind.dart';

/// 「今週の記録」カード（運動）。月曜から日曜までの 7 日を並べ、運動した日の下に
/// その日の主な種類のアイコン（筋トレ = dumbbell / 有酸素 = footprints）を出す。
/// 正本は `record-screens.js` の `ExerciseTab` の週のカード。
///
/// - 余白は上 16・左右 10・下 8。見出しは左右 10 を足して他のカードと揃える
/// - [kindsByDay] は日付（時刻なし）→ その日にあった系統の集合（運動の記録とプランの完了をまとめたもの）。
///   null は読込中（各日の印をスケルトンにして配置を保つ）
/// - その日の主な種類: 筋トレがあれば dumbbell、なければ有酸素の footprints。
///   どちらでもない運動（ヨガなど）だけの日は単色の点。色は割り振らない
/// - [filter] が筋トレ・有酸素のときは、その系統の日だけに印を出す（null = すべて）
/// - 今日の日付は surfaceSecondary の円 + accent。表示専用（[onDayTap] を渡すと日付を押せる）
class ExerciseWeekCalendar extends StatelessWidget {
  const ExerciseWeekCalendar({
    super.key,
    required this.today,
    required this.kindsByDay,
    this.filter,
    this.hasError = false,
    this.onRetry,
    this.onDayTap,
  });

  /// 今日（日付だけ）
  final DateTime today;

  /// 日付 → その日にあった系統。null は読込中
  final Map<DateTime, Set<ExerciseKind>>? kindsByDay;

  /// 種類フィルタ（null = すべて）
  final ExerciseKind? filter;

  /// 取得に失敗したとき（印を出さず、失敗したことを伝える）
  final bool hasError;
  final VoidCallback? onRetry;

  /// 日付を押したとき（未来の日は呼ばれない）。null なら表示専用
  final ValueChanged<DateTime>? onDayTap;

  /// その日の印にする系統。無ければ null
  static ExerciseKind? markKind(
      Set<ExerciseKind>? kinds, ExerciseKind? filter) {
    if (kinds == null || kinds.isEmpty) return null;
    if (filter != null) return kinds.contains(filter) ? filter : null;
    if (kinds.contains(ExerciseKind.strength)) return ExerciseKind.strength;
    if (kinds.contains(ExerciseKind.cardio)) return ExerciseKind.cardio;
    return ExerciseKind.other;
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = recordWeekStartOf(today);

    final days = <FcWeekDay>[];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
      final isFuture = date.isAfter(today);
      final kind = markKind(kindsByDay?[date], filter);

      Widget? mark;
      String status = '';
      if (kindsByDay == null) {
        mark = hasError ? null : const FcSkeleton(width: 16, height: 16);
      } else if (!isFuture && kind != null) {
        mark = switch (kind) {
          ExerciseKind.strength => const Icon(LucideIcons.dumbbell, size: 16),
          ExerciseKind.cardio => const Icon(LucideIcons.footprints, size: 16),
          ExerciseKind.other => const FcDot(),
        };
        status = switch (kind) {
          ExerciseKind.strength => '、筋トレ',
          ExerciseKind.cardio => '、有酸素',
          ExerciseKind.other => '、運動の記録あり',
        };
      }

      days.add(
        FcWeekDay(
          date: date,
          selected: date == today,
          markWidget: mark,
          semanticLabel: '${date.month}月${date.day}日 '
              '${FcWeekStrip.weekdayLabel(date)}曜日'
              '${date == today ? '、今日' : ''}$status',
        ),
      );
    }

    return FcCard(
      paddingOverride: const EdgeInsets.fromLTRB(10, 16, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: FcCardHead(
              icon: LucideIcons.calendarDays,
              label: '今週の記録',
              note: recordWeekRangeLabel(weekStart),
              bottomSpacing: 10,
            ),
          ),
          if (hasError && kindsByDay == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: FcInlineNotice.error(
                message: '今週の記録を読み込めませんでした',
                actionLabel: onRetry == null ? null : '再試行',
                onAction: onRetry,
              ),
            ),
          FcWeekStrip(
            days: days,
            onSelect: onDayTap == null
                ? null
                : (date) {
                    if (!date.isAfter(today)) onDayTap!(date);
                  },
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(Brightness brightness, double textScale, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  );
}

Map<DateTime, Set<ExerciseKind>> _previewKinds(DateTime today) {
  final weekStart = recordWeekStartOf(today);
  DateTime day(int i) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + i);
  return {
    day(0): {ExerciseKind.strength},
    day(2): {ExerciseKind.strength},
    day(5): {ExerciseKind.cardio},
  };
}

@Preview(name: 'ExerciseWeekCalendar - 通常')
Widget previewExerciseWeekCalendar() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1,
    ExerciseWeekCalendar(today: today, kindsByDay: _previewKinds(today)),
  );
}

@Preview(name: 'ExerciseWeekCalendar - ダーク')
Widget previewExerciseWeekCalendarDark() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.dark,
    1,
    ExerciseWeekCalendar(today: today, kindsByDay: _previewKinds(today)),
  );
}

@Preview(name: 'ExerciseWeekCalendar - 読込中')
Widget previewExerciseWeekCalendarLoading() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1,
    ExerciseWeekCalendar(today: today, kindsByDay: null),
  );
}

@Preview(name: 'ExerciseWeekCalendar - 文字拡大 1.35')
Widget previewExerciseWeekCalendarLargeText() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1.35,
    ExerciseWeekCalendar(today: today, kindsByDay: _previewKinds(today)),
  );
}
