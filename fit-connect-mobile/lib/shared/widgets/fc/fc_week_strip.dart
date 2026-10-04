import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc_marks.dart';
import 'fc_pressable.dart';

/// 週ストリップの 1 日の印
enum FcDayMark {
  /// 印なし
  none,

  /// 塗りの点（記録した日・実施した日）
  filled,

  /// 中抜きの点（予定のみ・日付が過ぎた）
  hollow,
}

/// 週ストリップの 1 日分のデータ
class FcWeekDay {
  const FcWeekDay({
    required this.date,
    this.mark = FcDayMark.none,
    this.markWidget,
    this.selected = false,
    this.today = false,
    this.semanticLabel,
  });

  final DateTime date;
  final FcDayMark mark;

  /// 点以外の印（`FcDoneMark(size: 16)`・「2回」の文字・アイコンなど）。渡すと [mark] より優先する。
  /// 印の行は accent の色・12 の文字が既定（文字の色を変えたいときは自分で指定する）。
  /// 読み上げに含めたいときは [semanticLabel] を渡す
  final Widget? markWidget;

  /// 選択中の日（surfaceSecondary の円・accent の文字・太さ 500）
  final bool selected;

  /// 今日（選択されていなければ accent の太め文字。円の面は付かない）
  final bool today;

  /// 読み上げ（例:「4日 月曜日、記録あり」）。null なら日付と印から作る
  final String? semanticLabel;
}

/// 7 日の週ストリップ（曜日・日付・印）。正本は `parts.js` の `WeekStrip`。
///
/// - 7 等分で並び、各日は 曜日（12 / textSecondary）・日付の円（34・文字 16）・印の行（最小高さ 20）を
///   間隔 6 で縦に積む。各日のタッチ領域は高さ 44 以上
/// - 日付の円は **選択中だけ surfaceSecondary の面 + accent の文字 + 太さ 500**、他は面なし
/// - 印は塗り/中抜きの単色の点（[FcDayMark]）か、任意の部品（[FcWeekDay.markWidget]）。カテゴリで色を変えない
/// - [onSelect] が null なら表示専用（押せない）
/// - 文字拡大では曜日・日付が大きくなるが、日付の円は縮まず広がる
class FcWeekStrip extends StatelessWidget {
  const FcWeekStrip({
    super.key,
    required this.days,
    this.onSelect,
  });

  final List<FcWeekDay> days;
  final ValueChanged<DateTime>? onSelect;

  static const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

  static String weekdayLabel(DateTime date) =>
      _weekdayLabels[(date.weekday - 1) % 7];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days)
          Expanded(
            child: _DayCell(
              day: day,
              onTap: onSelect == null ? null : () => onSelect!(day.date),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.onTap});

  final FcWeekDay day;
  final VoidCallback? onTap;

  String _defaultSemanticLabel() {
    final markLabel = switch (day.mark) {
      FcDayMark.none => '',
      FcDayMark.filled => '、記録あり',
      FcDayMark.hollow => '、予定あり',
    };
    final todayLabel = day.today ? '、今日' : '';
    return '${day.date.month}月${day.date.day}日 ${FcWeekStrip.weekdayLabel(day.date)}曜日$todayLabel$markLabel';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final emphasized = day.selected || day.today;

    final dateStyle = AppTextStyles.body(context).copyWith(
      fontWeight: emphasized ? FontWeight.w500 : FontWeight.w400,
      color: emphasized ? colors.accent : colors.textPrimary,
      fontFeatures: AppTextStyles.tabularFigures,
    );

    final Widget? markContent = day.markWidget ??
        (day.mark == FcDayMark.none
            ? null
            : FcDot(filled: day.mark == FcDayMark.filled));

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          FcWeekStrip.weekdayLabel(day.date),
          style: AppTextStyles.caption(context),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: day.selected ? colors.surfaceSecondary : Colors.transparent,
          ),
          child: Text('${day.date.day}', style: dateStyle),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Center(
            widthFactor: 1,
            child: markContent == null
                ? null
                : IconTheme.merge(
                    data: IconThemeData(color: colors.accent),
                    child: DefaultTextStyle.merge(
                      style: AppTextStyles.caption(context)
                          .copyWith(color: colors.accent),
                      child: markContent,
                    ),
                  ),
          ),
        ),
      ],
    );

    return FcPressable(
      onTap: onTap,
      enabled: onTap != null,
      isButton: onTap != null,
      selected: day.selected,
      semanticLabel: day.semanticLabel ?? _defaultSemanticLabel(),
      minSize: const Size(0, AppSizes.minTouch),
      child: content,
    );
  }
}
