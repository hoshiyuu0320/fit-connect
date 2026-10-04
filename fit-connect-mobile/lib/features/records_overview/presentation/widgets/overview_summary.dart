import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';

/// 摂取カロリーの棒グラフ 1 本（1 日、または 1 週間）
class OverviewBar {
  const OverviewBar({
    required this.date,
    required this.calories,
    required this.highlighted,
    required this.label,
  });

  /// 1 日の棒はその日、1 週間の棒はその週の最初の日（期間の先頭で欠けた週は期間の開始日）
  final DateTime date;

  /// 1 日の摂取カロリー（週の棒は記録した日の平均）。**記録がなければ null**（0 と区別する）
  final double? calories;

  /// 今日（今日を含む週）の棒
  final bool highlighted;

  /// 棒の下の x ラベル。空なら出さない
  final String label;
}

/// サマリタブの表示用に、日次の栄養トレンド（[DailyNutritionStat]）を集計した値。
///
/// 画面（`RecordsOverviewScreen`）はこの値を整形して並べるだけにする。
/// 日次の集計そのもの（体重・カロリー・PFC の日付ごとの値）は
/// `nutritionTrendProvider` のまま。ここで足すのは「1 日平均」と「棒グラフの束ね方」だけ。
///
/// **今日は 1 日平均に入れない**（今日はまだ途中で低く出るため）。
/// 過去の日に 1 件も記録がないときだけ、今日を含めて平均する。
class OverviewSummary {
  const OverviewSummary._({
    required this.start,
    required this.end,
    required this.weightDays,
    required this.averageStart,
    required this.averageEnd,
    required this.calorieDayCount,
    required this.averageCalories,
    required this.pfcDayCount,
    required this.averageProtein,
    required this.averageFat,
    required this.averageCarbs,
    required this.bars,
    required this.weeklyBars,
    required this.hasAnyRecord,
  });

  /// 1 日の棒で出せる最大の日数。超えたら 1 週間ごとの棒にする
  static const int maxDailyBars = 14;

  factory OverviewSummary.from(
    List<DailyNutritionStat> days, {
    required DateTime today,
  }) {
    final todayDate = DateTime(today.year, today.month, today.day);
    final sorted = [...days]..sort((a, b) => a.date.compareTo(b.date));

    final start = sorted.isEmpty ? todayDate : sorted.first.date;
    final end = sorted.isEmpty ? todayDate : sorted.last.date;

    bool hasCalories(DailyNutritionStat d) => d.calories > 0;
    bool hasPfc(DailyNutritionStat d) =>
        d.protein > 0 || d.fat > 0 || d.carbs > 0;

    // 1 日平均の対象: 今日を除いた日。過去に記録が 1 日もなければ今日も含める
    var averageDays =
        sorted.where((d) => d.date.isBefore(todayDate)).toList();
    if (!averageDays.any(hasCalories) && !averageDays.any(hasPfc)) {
      averageDays = sorted;
    }

    final calorieDays = averageDays.where(hasCalories).toList();
    final pfcDays = averageDays.where(hasPfc).toList();

    double? mean(Iterable<DailyNutritionStat> source,
        double Function(DailyNutritionStat) pick) {
      final list = source.toList();
      if (list.isEmpty) return null;
      return list.map(pick).reduce((a, b) => a + b) / list.length;
    }

    final weeklyBars = sorted.length > maxDailyBars;
    final bars = weeklyBars
        ? _weeklyBars(sorted, todayDate)
        : _dailyBars(sorted, todayDate);

    return OverviewSummary._(
      start: start,
      end: end,
      weightDays: sorted.where((d) => d.weight != null).toList(),
      averageStart: averageDays.isEmpty ? todayDate : averageDays.first.date,
      averageEnd: averageDays.isEmpty ? todayDate : averageDays.last.date,
      calorieDayCount: calorieDays.length,
      averageCalories: mean(calorieDays, (d) => d.calories),
      pfcDayCount: pfcDays.length,
      averageProtein: mean(pfcDays, (d) => d.protein),
      averageFat: mean(pfcDays, (d) => d.fat),
      averageCarbs: mean(pfcDays, (d) => d.carbs),
      bars: bars,
      weeklyBars: weeklyBars,
      hasAnyRecord: sorted.any((d) => d.hasAnyRecord),
    );
  }

  /// 期間の最初の日・最後の日（今日）
  final DateTime start;
  final DateTime end;

  /// 体重を記録した日（古い順。1 日 1 件）
  final List<DailyNutritionStat> weightDays;

  /// 1 日平均の対象にした範囲
  final DateTime averageStart;
  final DateTime averageEnd;

  /// 摂取カロリーを記録した日数（1 日平均の対象のうち）
  final int calorieDayCount;

  /// 摂取カロリーの 1 日平均（記録した日の平均）。記録がなければ null
  final double? averageCalories;

  /// PFC を記録した日数と、その日の 1 日平均。記録がなければ null
  final int pfcDayCount;
  final double? averageProtein;
  final double? averageFat;
  final double? averageCarbs;

  /// 棒グラフ（古い順）
  final List<OverviewBar> bars;

  /// 棒が 1 週間ごとの平均か（日数が [maxDailyBars] を超えるとき）
  final bool weeklyBars;

  /// 期間のどこかに、体重・食事の記録があるか
  final bool hasAnyRecord;

  static const List<String> _weekdayLabels = [
    '月',
    '火',
    '水',
    '木',
    '金',
    '土',
    '日'
  ];

  static List<OverviewBar> _dailyBars(
    List<DailyNutritionStat> days,
    DateTime today,
  ) {
    final n = days.length;
    // 1 週間以内は曜日を全部、それ以上は日付を 5 つほどに間引く（正本: 1・4・7・10・13）
    final showWeekday = n <= 7;
    final step = (n / 5).ceil().clamp(1, n == 0 ? 1 : n).toInt();
    return [
      for (var i = 0; i < n; i++)
        OverviewBar(
          date: days[i].date,
          calories: days[i].calories > 0 ? days[i].calories : null,
          highlighted: days[i].date == today,
          label: showWeekday
              ? _weekdayLabels[days[i].date.weekday - 1]
              : (i % step == 0 ? '${days[i].date.day}' : ''),
        ),
    ];
  }

  static List<OverviewBar> _weeklyBars(
    List<DailyNutritionStat> days,
    DateTime today,
  ) {
    // 月曜はじまりの週ごとにまとめる
    final weeks = <List<DailyNutritionStat>>[];
    DateTime? currentKey;
    for (final d in days) {
      final key = DateTime(
        d.date.year,
        d.date.month,
        d.date.day - (d.date.weekday - 1),
      );
      if (currentKey == null || key != currentKey) {
        weeks.add([]);
        currentKey = key;
      }
      weeks.last.add(d);
    }

    final step = (weeks.length / 5).ceil().clamp(1, weeks.length).toInt();
    return [
      for (var i = 0; i < weeks.length; i++)
        () {
          final week = weeks[i];
          // 今日はまだ途中なので、ほかに記録した日があれば平均に入れない
          final recorded = week.where((d) => d.calories > 0).toList();
          final settled = recorded.where((d) => d.date != today).toList();
          final source = settled.isNotEmpty ? settled : recorded;
          final calories = source.isEmpty
              ? null
              : source.map((d) => d.calories).reduce((a, b) => a + b) /
                  source.length;
          final first = week.first.date;
          return OverviewBar(
            date: first,
            calories: calories,
            highlighted: week.any((d) => d.date == today),
            label: i % step == 0 ? '${first.month}/${first.day}' : '',
          );
        }(),
    ];
  }
}
