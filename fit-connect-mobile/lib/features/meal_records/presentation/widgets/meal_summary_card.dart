import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'meal_type.dart';
import 'record_date_format.dart';

/// 「今日の食事」の 1 区分（朝食・昼食・夕食・間食）
class MealSlot {
  const MealSlot({
    required this.label,
    required this.mealType,
    this.firstRecordedAt,
    this.count = 0,
  });

  /// 朝食 / 昼食 / 夕食 / 間食
  final String label;

  /// breakfast / lunch / dinner / snack
  final String mealType;

  /// その区分で最初に記録した日時（記録なしなら null）
  final DateTime? firstRecordedAt;

  /// その区分の記録の件数
  final int count;

  bool get recorded => count > 0;

  /// 読み上げ用（例:「朝食、記録あり、8:10」）
  String get semanticLabel {
    if (!recorded) return '$label、未記録';
    final time =
        firstRecordedAt == null ? '' : '、${recordTimeLabel(firstRecordedAt!)}';
    final more = count > 1 ? '、ほか${count - 1}件' : '';
    return '$label、記録あり$time$more';
  }
}

/// 「今日の食事」カード。朝食・昼食・夕食・間食のそれぞれが、記録済みか未記録かを示す。
/// 正本は `record-screens.js` の `MealsTab` の先頭のカード。
///
/// - 見出し: utensils「今日の食事」＋ 右に今日の日付「9月13日（日）」
/// - 4 列: ラベル（14）→ 完了マーク 24（記録あり = 塗り + チェック / 未記録 = 枠だけ）→ 時刻（12・tabular）または「未記録」
/// - 色や絵文字で区分を塗り分けない。記録の有無は形（チェックの有無）と文言でも伝える
/// - [loading] のあいだはマークと時刻をスケルトンにして配置を保つ（未取得を「未記録」と見せない）
class MealSummaryCard extends StatelessWidget {
  const MealSummaryCard({
    super.key,
    required this.date,
    required this.slots,
    this.loading = false,
    this.hasError = false,
    this.onRetry,
  });

  /// 今日の日付（見出しの右に出す）
  final DateTime date;

  /// 4 区分（`MealSummaryCard.slotsFrom` で作れる）
  final List<MealSlot> slots;

  final bool loading;

  /// 取得に失敗したとき（4 区分を「未記録」と見せず、失敗したことを伝える）
  final bool hasError;
  final VoidCallback? onRetry;

  /// 1 日分の食事記録から 4 区分を作る（朝食・昼食・夕食・間食の順。ほかの区分は含めない）
  static List<MealSlot> slotsFrom(List<MealRecord> records) {
    return [
      for (final slot in mealTypeSlots)
        () {
          final matching = records
              .where((r) => r.mealType.toLowerCase() == slot.type)
              .toList()
            ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
          return MealSlot(
            label: slot.label,
            mealType: slot.type,
            firstRecordedAt:
                matching.isEmpty ? null : matching.first.recordedAt,
            count: matching.length,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FcCardHead(
            icon: LucideIcons.utensils,
            label: '今日の食事',
            note: recordDateLabel(date),
          ),
          if (hasError)
            FcInlineNotice.error(
              message: '今日の食事を読み込めませんでした',
              actionLabel: onRetry == null ? null : '再試行',
              onAction: onRetry,
            )
          else
            Semantics(
              label: loading ? '読み込み中' : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < slots.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _SlotColumn(slot: slots[i], loading: loading),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlotColumn extends StatelessWidget {
  const _SlotColumn({required this.slot, required this.loading});

  final MealSlot slot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final time = slot.firstRecordedAt;

    return Semantics(
      container: true,
      label: loading ? slot.label : slot.semanticLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            slot.label,
            textAlign: TextAlign.center,
            style: AppTextStyles.label(context),
          ),
          const SizedBox(height: 6),
          if (loading)
            const FcSkeleton.circle(size: 24)
          else
            FcDoneMark(done: slot.recorded, size: 24),
          const SizedBox(height: 6),
          if (loading)
            const FcSkeleton.line(width: 32, height: 12)
          else
            Text(
              slot.recorded && time != null ? recordTimeLabel(time) : '未記録',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(context)
                  .copyWith(fontFeatures: AppTextStyles.tabularFigures),
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

List<MealSlot> _previewSlots() {
  final today = DateTime.now();
  return [
    MealSlot(
      label: '朝食',
      mealType: 'breakfast',
      firstRecordedAt: DateTime(today.year, today.month, today.day, 8, 10),
      count: 1,
    ),
    MealSlot(
      label: '昼食',
      mealType: 'lunch',
      firstRecordedAt: DateTime(today.year, today.month, today.day, 12, 30),
      count: 1,
    ),
    const MealSlot(label: '夕食', mealType: 'dinner'),
    const MealSlot(label: '間食', mealType: 'snack'),
  ];
}

@Preview(name: 'MealSummaryCard - 今日の食事')
Widget previewMealSummaryCard() => _previewApp(
      Brightness.light,
      1,
      MealSummaryCard(date: DateTime.now(), slots: _previewSlots()),
    );

@Preview(name: 'MealSummaryCard - ダーク')
Widget previewMealSummaryCardDark() => _previewApp(
      Brightness.dark,
      1,
      MealSummaryCard(date: DateTime.now(), slots: _previewSlots()),
    );

@Preview(name: 'MealSummaryCard - まだ記録なし')
Widget previewMealSummaryCardEmpty() => _previewApp(
      Brightness.light,
      1,
      MealSummaryCard(
        date: DateTime.now(),
        slots: MealSummaryCard.slotsFrom(const []),
      ),
    );

@Preview(name: 'MealSummaryCard - 読込中')
Widget previewMealSummaryCardLoading() => _previewApp(
      Brightness.light,
      1,
      MealSummaryCard(
        date: DateTime.now(),
        slots: MealSummaryCard.slotsFrom(const []),
        loading: true,
      ),
    );

@Preview(name: 'MealSummaryCard - 文字拡大 1.35')
Widget previewMealSummaryCardLargeText() => _previewApp(
      Brightness.light,
      1.35,
      MealSummaryCard(date: DateTime.now(), slots: _previewSlots()),
    );
