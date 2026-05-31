/// 日次の栄養トレンド集計モデル
///
/// 体重 (weight) と食事の合算値（calories / PFC）を 1 日単位で保持する。
/// weight は当日記録が無ければ null、食事は無ければ 0。
class DailyNutritionStat {
  /// 日付（日付単位 0時0分0秒で正規化されている前提）
  final DateTime date;

  /// 当日の体重 (kg)。記録が無ければ null。
  final double? weight;

  /// 当日の合計摂取カロリー (kcal)。記録無しは 0。
  final double calories;

  /// 当日の合計タンパク質 (g)。
  final double protein;

  /// 当日の合計脂質 (g)。
  final double fat;

  /// 当日の合計炭水化物 (g)。
  final double carbs;

  const DailyNutritionStat({
    required this.date,
    this.weight,
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
  });

  /// PFC を kcal 換算した合計値。
  ///
  /// `calories` フィールドと厳密一致しないことがある（手動入力で
  /// PFC 不明だが calories のみ入力されている場合など）。
  /// 棒グラフ積み上げの高さ用に使用する。
  double get pfcKcal => protein * 4 + fat * 9 + carbs * 4;

  /// この日に体重・食事のいずれかの記録があるかどうか。
  bool get hasAnyRecord =>
      weight != null || calories > 0 || protein > 0 || fat > 0 || carbs > 0;

  DailyNutritionStat copyWith({
    DateTime? date,
    double? weight,
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
  }) {
    return DailyNutritionStat(
      date: date ?? this.date,
      weight: weight ?? this.weight,
      calories: calories ?? this.calories,
      protein: protein ?? this.protein,
      fat: fat ?? this.fat,
      carbs: carbs ?? this.carbs,
    );
  }
}
