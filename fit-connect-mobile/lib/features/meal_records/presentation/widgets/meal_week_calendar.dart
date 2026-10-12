import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'record_date_format.dart';

/// 今週の食事の回数（Riverpod から日別の件数を取る）。見た目は [MealWeekCard]。
class MealWeekCalendar extends ConsumerWidget {
  final void Function(DateTime date, int mealCount)? onDayTap;

  const MealWeekCalendar({
    super.key,
    this.onDayTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = recordDayOf(now);
    final weekStart = recordWeekStartOf(today);

    // 日曜の 23:59:59 までを問い合わせる（日曜 0:00 までだと日曜の記録が落ちる）
    final countsAsync = ref.watch(
      mealRecordCountsProvider(
        startDate: weekStart,
        endDate: recordWeekEndOf(weekStart),
      ),
    );

    return MealWeekCard(
      today: today,
      counts: countsAsync.valueOrNull,
      hasError: countsAsync.hasError && !countsAsync.hasValue,
      onRetry: () => ref.invalidate(mealRecordCountsProvider),
      onDayTap: onDayTap,
    );
  }
}

/// 「今週の記録」カード。月曜から日曜までの 7 日を並べ、各日の下に食事の回数を「3回」と書く。
/// 正本は `record-screens.js` の `MealsTab` の 2 枚目のカード。
///
/// - 余白は上 16・左右 10・下 8（`FcWeekStrip` を端まで広げるため）。見出しは左右 10 を足して他のカードと揃える
/// - 印は回数の文字（textPrimary・tabular）。記録のない日・未来の日は何も出さない
/// - 今日の日付は surfaceSecondary の円 + accent
/// - [counts] が null のあいだは、各日の印をスケルトンにして配置を保つ
class MealWeekCard extends StatelessWidget {
  const MealWeekCard({
    super.key,
    required this.today,
    required this.counts,
    this.hasError = false,
    this.onRetry,
    this.onDayTap,
  });

  /// 今日（日付だけ）
  final DateTime today;

  /// 日付ごとの食事の件数。null は読込中
  final Map<DateTime, int>? counts;

  /// 取得に失敗したとき
  final bool hasError;
  final VoidCallback? onRetry;

  /// 日付を押したとき（未来の日は呼ばれない）。null なら表示専用
  final void Function(DateTime date, int mealCount)? onDayTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final weekStart = recordWeekStartOf(today);
    final markStyle = AppTextStyles.caption(context).copyWith(
      color: colors.textPrimary,
      fontFeatures: AppTextStyles.tabularFigures,
    );

    final days = <FcWeekDay>[];
    for (var i = 0; i < 7; i++) {
      final date = DateTime(weekStart.year, weekStart.month, weekStart.day + i);
      final isFuture = date.isAfter(today);
      final count = counts?[date] ?? 0;

      Widget? mark;
      if (counts == null) {
        mark = hasError ? null : const FcSkeleton(width: 20, height: 12);
      } else if (!isFuture && count > 0) {
        mark = Text('$count回', style: markStyle);
      }

      days.add(
        FcWeekDay(
          date: date,
          selected: date == today,
          markWidget: mark,
          semanticLabel: '${date.month}月${date.day}日 '
              '${FcWeekStrip.weekdayLabel(date)}曜日'
              '${date == today ? '、今日' : ''}'
              '${counts == null || isFuture ? '' : count > 0 ? '、$count回' : '、記録なし'}',
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
          if (hasError && counts == null)
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
                    if (date.isAfter(today)) return;
                    onDayTap!(date, counts?[date] ?? 0);
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

Map<DateTime, int> _previewCounts(DateTime today) {
  final weekStart = recordWeekStartOf(today);
  const sample = [3, 2, 3, 2, 1, 3, 2];
  return {
    for (var i = 0; i < 7; i++)
      if (!DateTime(weekStart.year, weekStart.month, weekStart.day + i)
          .isAfter(today))
        DateTime(weekStart.year, weekStart.month, weekStart.day + i): sample[i],
  };
}

@Preview(name: 'MealWeekCard - 通常')
Widget previewMealWeekCard() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1,
    MealWeekCard(today: today, counts: _previewCounts(today)),
  );
}

@Preview(name: 'MealWeekCard - ダーク')
Widget previewMealWeekCardDark() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.dark,
    1,
    MealWeekCard(today: today, counts: _previewCounts(today)),
  );
}

@Preview(name: 'MealWeekCard - 読込中')
Widget previewMealWeekCardLoading() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1,
    MealWeekCard(today: today, counts: null),
  );
}

@Preview(name: 'MealWeekCard - 文字拡大 1.35')
Widget previewMealWeekCardLargeText() {
  final today = recordDayOf(DateTime.now());
  return _previewApp(
    Brightness.light,
    1.35,
    MealWeekCard(today: today, counts: _previewCounts(today)),
  );
}
