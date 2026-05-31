import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

part 'nutrition_trend_provider.g.dart';

/// 体重 + 食事の日次集計（栄養トレンド）を返す Provider。
///
/// 既存の [weightRecordsProvider] / [mealRecordsProvider] を watch し、
/// `period` の範囲 (startDate 〜 today) の連続した日付配列に対して
/// 日単位の体重 / カロリー / PFC を集計する。
@riverpod
Future<List<DailyNutritionStat>> nutritionTrend(
  NutritionTrendRef ref, {
  PeriodFilter period = PeriodFilter.month,
}) async {
  // 既存 Provider を購読してデータを取得
  final weightRecords = await ref.watch(
    weightRecordsProvider(period: period).future,
  );
  final mealRecords = await ref.watch(
    mealRecordsProvider(period: period).future,
  );

  // 範囲: 開始日 〜 今日
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = _normalizeDate(period.getStartDate());

  // PeriodFilter.all は最古日(2000-01-01)を返すので、
  // 実データの最小日に丸めて日数膨張を抑止する
  final effectiveStart = _effectiveStart(
    requested: start,
    weightRecords: weightRecords,
    mealRecords: mealRecords,
    fallback: today,
  );

  // 日付 -> stat マップで初期化
  final Map<DateTime, DailyNutritionStat> map = {};
  for (var d = effectiveStart;
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))) {
    map[d] = DailyNutritionStat(date: d);
  }

  // 体重: 同日複数件あれば最新（recordedAt が新しい方）を採用
  // weightRecordsProvider は recorded_at desc の順で返るが、明示的に並べる
  final weightSorted = [...weightRecords]
    ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  for (final w in weightSorted) {
    final key = _normalizeDate(w.recordedAt);
    final existing = map[key];
    if (existing == null) continue;
    map[key] = existing.copyWith(weight: w.weight);
  }

  // 食事: 同日複数件は合算
  for (final m in mealRecords) {
    final key = _normalizeDate(m.recordedAt);
    final existing = map[key];
    if (existing == null) continue;
    map[key] = existing.copyWith(
      calories: existing.calories + (m.calories ?? 0),
      protein: existing.protein + (m.proteinG ?? 0),
      fat: existing.fat + (m.fatG ?? 0),
      carbs: existing.carbs + (m.carbsG ?? 0),
    );
  }

  // 日付昇順で返す
  final result = map.values.toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  return result;
}

DateTime _normalizeDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

DateTime _effectiveStart({
  required DateTime requested,
  required List<WeightRecord> weightRecords,
  required List<MealRecord> mealRecords,
  required DateTime fallback,
}) {
  // PeriodFilter.all 用: 2000-01-01 はそのまま使うと膨大な空配列になるので
  // 実データの最古日に丸める
  final sentinel = DateTime(2010, 1, 1);
  if (requested.isAfter(sentinel)) return requested;

  DateTime? oldest;
  for (final r in weightRecords) {
    final d = _normalizeDate(r.recordedAt);
    if (oldest == null || d.isBefore(oldest)) oldest = d;
  }
  for (final r in mealRecords) {
    final d = _normalizeDate(r.recordedAt);
    if (oldest == null || d.isBefore(oldest)) oldest = d;
  }
  return oldest ?? fallback;
}
