/// 期間フィルタの列挙型
enum PeriodFilter {
  /// 今日
  today,

  /// 今週
  week,

  /// 今月
  month,

  /// 3ヶ月
  threeMonths,

  /// 全期間
  all;

  /// 表示用ラベル
  String get label {
    switch (this) {
      case PeriodFilter.today:
        return '今日';
      case PeriodFilter.week:
        return '今週';
      case PeriodFilter.month:
        return '今月';
      case PeriodFilter.threeMonths:
        return '3ヶ月';
      case PeriodFilter.all:
        return '全期間';
    }
  }

  /// 短い表示用ラベル
  String get shortLabel {
    switch (this) {
      case PeriodFilter.today:
        return '今日';
      case PeriodFilter.week:
        return '週';
      case PeriodFilter.month:
        return '月';
      case PeriodFilter.threeMonths:
        return '3ヶ月';
      case PeriodFilter.all:
        return '全期間';
    }
  }

  /// フィルタに対応する開始日時を取得
  DateTime getStartDate() {
    final now = DateTime.now();
    switch (this) {
      case PeriodFilter.today:
        return DateTime(now.year, now.month, now.day);
      case PeriodFilter.week:
        // 今週の月曜日
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return DateTime(monday.year, monday.month, monday.day);
      case PeriodFilter.month:
        return DateTime(now.year, now.month, 1);
      case PeriodFilter.threeMonths:
        return DateTime(now.year, now.month - 3, now.day);
      case PeriodFilter.all:
        // 十分に古い日付（実質的に全期間）
        return DateTime(2000, 1, 1);
    }
  }
}
