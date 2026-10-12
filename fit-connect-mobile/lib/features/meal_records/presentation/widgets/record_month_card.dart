import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'record_date_format.dart';

/// 月カード（食事・運動の記録タブで共通）。正本は `record-screens.js` の `MonthGrid`。
///
/// - 見出し: calendar-days「9月」＋ 右に「記録した日 11日」。前の月・次の月の操作を右端に添える
///   （正本の見本には無いが、現行アプリの「月移動」を残すため）
/// - 7 列（月曜はじまり）。曜日はキャプション、日付は円 28（今日 = surfaceSecondary の面 + accent + 500、
///   未来 = textSecondary）、**記録した日の下に 5px の accent の点**
/// - 緑や青の濃淡（回数の多さ）は使わない。印は有る／無いの単色の点だけ
/// - 文字拡大では日付の円が広がるだけで、列は崩れない
///
/// [recordedDays] は日付だけ（時刻なし）の集合。null は読込中（点を出さず、配置は保つ）。
/// 食事・運動の両方から使うので、基盤（lib/shared）へ昇格してほしい（最終報告に記載）。
class RecordMonthCard extends StatelessWidget {
  const RecordMonthCard({
    super.key,
    required this.month,
    required this.recordedDays,
    this.today,
    this.hasError = false,
    this.onRetry,
    this.onPreviousMonth,
    this.onNextMonth,
    this.onDayTap,
  });

  /// 表示する月（月初）
  final DateTime month;

  /// 記録のある日（日付だけにした値）。null は読込中
  final Set<DateTime>? recordedDays;

  /// 今日。テスト・プレビュー用（null なら現在の日付）
  final DateTime? today;

  /// 記録日の取得に失敗したとき
  final bool hasError;
  final VoidCallback? onRetry;

  /// 前の月。null なら押せない
  final VoidCallback? onPreviousMonth;

  /// 次の月。null なら押せない（今月より先へは進まない）
  final VoidCallback? onNextMonth;

  /// 日付を押したとき（未来の日は呼ばれない）。null なら日付は表示専用
  final ValueChanged<DateTime>? onDayTap;

  /// 前の月・次の月ボタンの大きさ（タッチ領域 44）
  static const double _navSize = AppSizes.minTouch;

  /// 前の月・次の月アイコンの大きさ
  static const double _navIconSize = 18;

  /// 見出しの文字（14 × 行高 1.5）の高さ
  static const double _headLabelHeight = 14 * 1.5;

  /// 見出し行がボタンで 44 になるぶんの、上下のはみ出し。
  /// カードの上余白から引いて、見出しの文字の位置を正本（カード上端から 20）に揃える
  static const double _headBleed = (_navSize - _headLabelHeight) / 2;

  /// 次の月ボタンの右のはみ出し。矢印のアイコンの右端を、本文の右端（カードの右余白 20）に揃える
  static const double _endBleed = (_navSize - _navIconSize) / 2;

  /// 日付の円
  static const double _dayCircle = 28;

  /// 日付 1 マスの最小の高さ（円 28 + 間 2 + 点のぶん）
  static const double _cellMinHeight = 38;

  /// 記録の点
  static const double _dotSize = 5;

  /// 「9月」「2025年9月」（今年は年を省く）
  static String monthLabel(DateTime month, DateTime today) =>
      month.year == today.year
          ? '${month.month}月'
          : '${month.year}年${month.month}月';

  @override
  Widget build(BuildContext context) {
    final now = today ?? DateTime.now();
    final todayDay = recordDayOf(now);
    final days = recordedDays;
    final recordedInMonth = days?.where(
      (d) => d.year == month.year && d.month == month.month,
    );
    final count = recordedInMonth?.length;

    const padding = AppSpacing.cardPadding;
    return FcCard(
      paddingOverride: const EdgeInsets.fromLTRB(
        padding,
        padding - _headBleed,
        padding - _endBleed,
        padding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, now, count),
          // 見出し行の下の余白 12 から、行の下側のはみ出しぶんを引く
          const SizedBox(height: 12 - _headBleed),
          if (hasError) ...[
            Padding(
              padding: const EdgeInsets.only(right: _endBleed, bottom: 12),
              child: FcInlineNotice.error(
                message: '記録した日を読み込めませんでした',
                actionLabel: onRetry == null ? null : '再試行',
                onAction: onRetry,
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: _endBleed),
            child: _buildGrid(context, todayDay),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DateTime now, int? count) {
    final colors = AppColors.of(context);

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(LucideIcons.calendarDays, size: 17, color: colors.accent),
        ),
        const SizedBox(width: 6),
        Semantics(
          header: true,
          child: Text(
            monthLabel(month, now),
            style: AppTextStyles.label(context)
                .copyWith(color: colors.accent, height: 1.5),
          ),
        ),
      ],
    );

    final Widget note = count == null
        ? Semantics(
            label: hasError ? null : '読み込み中',
            child: const FcSkeleton(width: 72, height: 14),
          )
        : Text(
            '記録した日 $count日',
            style: AppTextStyles.supplement(context),
          );

    final nextEnabled = onNextMonth != null;
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (count != null || !hasError) note,
        const SizedBox(width: 4),
        _MonthNavButton(
          icon: LucideIcons.chevronLeft,
          semanticLabel: '前の月',
          onPressed: onPreviousMonth,
        ),
        _MonthNavButton(
          icon: LucideIcons.chevronRight,
          semanticLabel: '次の月',
          onPressed: nextEnabled ? onNextMonth : null,
        ),
      ],
    );

    // 収まるときは左右に振り分け、収まらない（文字拡大・狭い画面）ときは折り返す
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [label, trailing],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, DateTime todayDay) {
    final firstDay = DateTime(month.year, month.month, 1);
    final leading = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((leading + daysInMonth) / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 曜日（キャプション・下 4）
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              for (final weekday in ['月', '火', '水', '木', '金', '土', '日'])
                Expanded(
                  child: Text(
                    weekday,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption(context),
                  ),
                ),
            ],
          ),
        ),
        for (var row = 0; row < rows; row++) ...[
          // 行の間 4
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < 7; column++)
                Expanded(
                  child: _buildCell(
                    context,
                    todayDay,
                    row * 7 + column - leading + 1,
                    daysInMonth,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    DateTime todayDay,
    int dayNumber,
    int daysInMonth,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: _cellMinHeight);
    }
    final date = DateTime(month.year, month.month, dayNumber);
    final isToday = date == todayDay;
    final isFuture = date.isAfter(todayDay);
    final recorded = recordedDays?.contains(date) ?? false;

    final cell = _DayCell(
      date: date,
      isToday: isToday,
      isFuture: isFuture,
      recorded: recorded,
      circleSize: _dayCircle,
      minHeight: _cellMinHeight,
      dotSize: _dotSize,
    );

    final semanticLabel = '${month.month}月$dayNumber日'
        '${isToday ? '、今日' : ''}'
        '${recorded ? '、記録あり' : ''}';

    final tap = onDayTap;
    if (tap == null || isFuture) {
      return Semantics(
        container: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: cell,
      );
    }
    return FcPressable(
      onTap: () => tap(date),
      semanticLabel: semanticLabel,
      minSize: const Size(0, AppSizes.minTouch),
      child: cell,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isFuture,
    required this.recorded,
    required this.circleSize,
    required this.minHeight,
    required this.dotSize,
  });

  final DateTime date;
  final bool isToday;
  final bool isFuture;
  final bool recorded;
  final double circleSize;
  final double minHeight;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final Color textColor = isToday
        ? colors.accent
        : isFuture
            ? colors.textSecondary
            : colors.textPrimary;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Align(
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(
                minWidth: circleSize,
                minHeight: circleSize,
              ),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? colors.surfaceSecondary : Colors.transparent,
              ),
              // 円の大きさは 28 を下限に文字へ合わせる（alignment を使うとマスの幅いっぱいに広がる）
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  '${date.day}',
                  style: AppTextStyles.label(context).copyWith(
                    fontWeight: isToday ? FontWeight.w500 : FontWeight.w400,
                    color: textColor,
                    fontFeatures: AppTextStyles.tabularFigures,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (recorded) FcDot(size: dotSize) else SizedBox(height: dotSize),
          ],
        ),
      ),
    );
  }
}

/// 前の月・次の月ボタン（44×44・アイコン 18）。押せないときは薄くする
class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    return FcPressable(
      onTap: onPressed,
      enabled: enabled,
      semanticLabel: semanticLabel,
      minSize: const Size.square(RecordMonthCard._navSize),
      child: SizedBox(
        width: RecordMonthCard._navSize,
        height: RecordMonthCard._navSize,
        child: Center(
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Icon(
              icon,
              size: RecordMonthCard._navIconSize,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Set<DateTime> _previewRecordedDays(DateTime today) {
  final month = DateTime(today.year, today.month, 1);
  return {
    for (var day = 1; day <= today.day; day++)
      if (day % 3 != 0 && day != 6) DateTime(month.year, month.month, day),
  };
}

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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

@Preview(name: 'RecordMonthCard - 通常')
Widget previewRecordMonthCard() {
  final today = DateTime.now();
  return _previewApp(
    Brightness.light,
    1,
    RecordMonthCard(
      month: DateTime(today.year, today.month, 1),
      recordedDays: _previewRecordedDays(today),
      onPreviousMonth: () {},
    ),
  );
}

@Preview(name: 'RecordMonthCard - ダーク')
Widget previewRecordMonthCardDark() {
  final today = DateTime.now();
  return _previewApp(
    Brightness.dark,
    1,
    RecordMonthCard(
      month: DateTime(today.year, today.month, 1),
      recordedDays: _previewRecordedDays(today),
      onPreviousMonth: () {},
    ),
  );
}

@Preview(name: 'RecordMonthCard - 読込中')
Widget previewRecordMonthCardLoading() {
  final today = DateTime.now();
  return _previewApp(
    Brightness.light,
    1,
    RecordMonthCard(
      month: DateTime(today.year, today.month, 1),
      recordedDays: null,
      onPreviousMonth: () {},
    ),
  );
}

@Preview(name: 'RecordMonthCard - 文字拡大 1.35')
Widget previewRecordMonthCardLargeText() {
  final today = DateTime.now();
  return _previewApp(
    Brightness.light,
    1.35,
    RecordMonthCard(
      month: DateTime(today.year, today.month, 1),
      recordedDays: _previewRecordedDays(today),
      onPreviousMonth: () {},
    ),
  );
}
