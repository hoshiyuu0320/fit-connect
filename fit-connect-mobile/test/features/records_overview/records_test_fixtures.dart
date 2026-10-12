import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/records_overview/providers/nutrition_trend_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// 記録タブ（サマリ・体重）のテストで共有する、プロバイダーの差し替えとサンプルデータ。

/// 体重記録をそのまま返す（Supabase に出ない）
class FakeWeightRecords extends WeightRecords {
  FakeWeightRecords(this.data);

  final List<WeightRecord> data;

  @override
  Future<List<WeightRecord>> build({
    PeriodFilter period = PeriodFilter.month,
  }) async =>
      data;
}

/// 体重記録を、呼ばれるたびに [load] で作る（失敗・読込中・読み直しの回数を確かめる）
class LoadingWeightRecords extends WeightRecords {
  LoadingWeightRecords(this.load);

  final Future<List<WeightRecord>> Function() load;

  @override
  Future<List<WeightRecord>> build({
    PeriodFilter period = PeriodFilter.month,
  }) =>
      load();
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 正本（record-screens.js）のサンプル。[today] を最後の日として [count] 日ぶん
/// （13 日なら、食事の記録がない日が 2 日・今日の分は途中の 1160 kcal）。
/// 1 日平均は今日を除く 10 日で 1,987 kcal、PFC は 95 / 64 / 250 g。
List<DailyNutritionStat> sampleDays(DateTime today, {int count = 13}) {
  const weights = <double?>[
    61.6, 61.8, null, 61.7, null, 62.1, null, 62.2, null, null, 62.3, null, 62.4
  ];
  const kcals = <double>[
    1920, 2050, 0, 2010, 1990, 0, 2100, 1950, 1870, 1980, 2040, 1960, 1160
  ];
  final base = dateOnly(today);
  return [
    for (var i = 0; i < count; i++)
      DailyNutritionStat(
        date: DateTime(base.year, base.month, base.day - (count - 1 - i)),
        // 13 日より多いときは、サンプルを繰り返す
        weight: weights[i % 13],
        calories: kcals[i % 13],
        protein: kcals[i % 13] == 0 ? 0 : 95,
        fat: kcals[i % 13] == 0 ? 0 : 64,
        carbs: kcals[i % 13] == 0 ? 0 : 250,
      ),
  ];
}

/// 体重の記録（新しい順）。今日 7:30 の 62.4 kg から 2 日おきに 7 件
List<WeightRecord> sampleWeights(DateTime today) {
  const rows = <(int, int, int, double, String)>[
    (0, 7, 30, 62.4, 'message'),
    (2, 7, 25, 62.3, 'message'),
    (4, 7, 40, 62.2, 'message'),
    (6, 7, 35, 62.1, 'message'),
    (8, 7, 30, 61.7, 'healthkit'),
    (10, 7, 20, 61.8, 'message'),
    (12, 7, 15, 61.6, 'message'),
  ];
  final base = dateOnly(today);
  return [
    for (final (ago, hour, minute, weight, source) in rows)
      WeightRecord(
        id: 'weight-$ago',
        clientId: 'client-1',
        weight: weight,
        recordedAt: DateTime(base.year, base.month, base.day - ago, hour, minute),
        source: source,
        createdAt: base,
        updatedAt: base,
      ),
  ];
}

Client sampleGoal({double? initial = 61.0, double? target = 65.0}) => Client(
      clientId: 'client-1',
      name: '佐藤',
      trainerId: 'trainer-1',
      initialWeight: initial,
      targetWeight: target,
      createdAt: DateTime(2026, 8, 1),
    );

/// 記録タブのプロバイダーをまとめて差し替える。
///
/// - [trend]: 期間ごとの栄養トレンド（既定は [days]）。`Completer` の未完了 Future を返せば読込中、
///   例外を投げればエラー
/// - [records]: 期間ごとの体重記録（新しい順）。[recordsLoader] を渡すと、その Future で読み込む
///   （例外を投げれば失敗、`Completer` の未完了 Future なら読込中）
/// - [goalLoader]: 目標（クライアント）の読み込み。省略すると [goal]
/// - [latest]: 最新の体重記録（既定は [records] の先頭）
List<Override> recordsOverrides({
  List<DailyNutritionStat> days = const [],
  List<WeightRecord> records = const [],
  Future<List<DailyNutritionStat>> Function(PeriodFilter period)? trend,
  List<WeightRecord> Function(PeriodFilter period)? recordsFor,
  Future<List<WeightRecord>> Function(PeriodFilter period)? recordsLoader,
  Future<WeightRecord?> Function()? latest,
  Client? goal,
  Future<Client?> Function()? goalLoader,
  bool goalLoading = false,
}) {
  return [
    for (final period in PeriodFilter.values) ...[
      nutritionTrendProvider(period: period).overrideWith(
        (ref) => trend != null ? trend(period) : Future.value(days),
      ),
      weightRecordsProvider(period: period).overrideWith(
        () => recordsLoader != null
            ? LoadingWeightRecords(() => recordsLoader(period))
            : FakeWeightRecords(
                recordsFor != null ? recordsFor(period) : records,
              ),
      ),
    ],
    latestWeightRecordProvider.overrideWith(
      (ref) => latest != null
          ? latest()
          : Future.value(records.isEmpty ? null : records.first),
    ),
    currentGoalProvider.overrideWith(
      (ref) => goalLoader != null
          ? goalLoader()
          : goalLoading
              ? Completer<Client?>().future
              : Future.value(goal),
    ),
  ];
}

/// 390 × 844（iPhone 想定）に [child] を置いて pump する。
/// ライト／ダークと文字拡大を指定できる。ナビぶんの下余白（121）と上のセーフエリア（47）も再現する。
Future<void> pumpRecordsPage(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  bool settle = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 47, bottom: 121),
          ),
          child: c!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

const List<String> _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// テスト側で持つ日付表記（実装の整形を呼ばずに期待値を作る）: `9月13日（日）`
String expectedJpDate(DateTime d) =>
    '${d.month}月${d.day}日（${_weekdays[d.weekday - 1]}）';
