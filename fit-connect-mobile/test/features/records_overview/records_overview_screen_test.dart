import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/screens/records_overview_screen.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'records_test_fixtures.dart';

/// 1 日平均の範囲の表記（`9/1〜9/12`）。今日の前日までが対象
String _range(DateTime today, int count) {
  final first = DateTime(today.year, today.month, today.day - (count - 1));
  final last = DateTime(today.year, today.month, today.day - 1);
  return '${first.month}/${first.day}〜${last.month}/${last.day}';
}

/// 取得を数えて、[fail] のあいだは失敗させるための小さな状態
class _Flaky {
  _Flaky({this.fail = false});

  bool fail;
  int calls = 0;
}

/// 食事記録を [_Flaky] で取得する（本物の `mealRecordsProvider` の差し替え）
class _FlakyMealRecords extends MealRecords {
  _FlakyMealRecords(this.box);

  final _Flaky box;

  @override
  Future<List<MealRecord>> build({
    PeriodFilter period = PeriodFilter.month,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    box.calls++;
    if (box.fail) throw Exception('meals failed');
    return const [];
  }
}

/// 数値＋単位の表示（[FcNum]）
Finder _num(String value, String unit) => find.byWidgetPredicate(
      (w) => w is FcNum && w.value == value && w.unit == unit,
    );

void main() {
  final today = dateOnly(DateTime.now());

  List<Override> normalOverrides() => recordsOverrides(
        days: sampleDays(today),
        records: sampleWeights(today),
        goal: sampleGoal(),
      );

  group('通常（正本の「サマリ」）', () {
    testWidgets('体重・摂取カロリー・PFC のカードが、正本の文言で並ぶ', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );

      // 期間セグメント（今週 / 今月 / 3ヶ月）
      expect(find.text('今週'), findsOneWidget);
      expect(find.text('今月'), findsOneWidget);
      expect(find.text('3ヶ月'), findsOneWidget);
      expect(find.text('全期間'), findsNothing);

      // 体重カード
      expect(find.text('体重'), findsOneWidget);
      expect(_num('62.4', 'kg'), findsOneWidget);
      expect(
        find.text('${expectedJpDate(today)}7:30 · 目標 65.0 kg'),
        findsOneWidget,
      );

      // 摂取カロリーカード
      expect(find.text('摂取カロリー'), findsOneWidget);
      expect(_num('1,987', 'kcal'), findsOneWidget);
      expect(
        find.text('1日平均 · ${_range(today, 13)}のうち記録した10日'),
        findsOneWidget,
      );

      // PFC カード
      expect(find.text('PFCバランス（1日平均）'), findsOneWidget);
      expect(find.text('たんぱく質'), findsOneWidget);
      expect(find.text('記録した10日の平均'), findsOneWidget);
      expect(find.text('95 g'), findsOneWidget);
      expect(find.text('脂質'), findsOneWidget);
      expect(find.text('64 g'), findsOneWidget);
      expect(find.text('炭水化物'), findsOneWidget);
      expect(find.text('250 g'), findsOneWidget);

      // 推定であることの明記（カードの見出しの右 ×2 ＋ 注記）
      expect(find.text('推定'), findsNWidgets(2));
      expect(
        find.text('カロリーとPFCは、食事の写真と内容からの推定値です。'),
        findsOneWidget,
      );
    });

    testWidgets('旧デザインの要素（凡例・タンパク質・栄養トレンドの見出し）は残っていない', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );

      expect(find.text('栄養トレンド'), findsNothing);
      expect(find.text('タンパク質'), findsNothing);
      expect(find.text('摂取 kcal'), findsNothing);
      expect(find.text('目標'), findsNothing);
    });

    testWidgets('グラフは正本の部品（折れ線 1 つ・棒 13 本）で、読み上げの見出しがある', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );

      expect(find.byType(FcLineChart), findsOneWidget);
      expect(find.byType(FcBars), findsOneWidget);
      for (var i = 0; i < 13; i++) {
        expect(find.byKey(ValueKey('fc-bar-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('fc-bar-13')), findsNothing);

      expect(find.bySemanticsLabel(RegExp('の体重の推移、61.6 kgから62.4 kg')), findsOneWidget);
      expect(find.bySemanticsLabel('1日ごとの摂取カロリー'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('最後の棒（今日）だけ accent、ほかは textSecondary の 28%、記録のない日は線', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );
      final colors = AppColorsExtension.light;

      Color colorOf(int i) {
        final box = tester.widget<DecoratedBox>(find.byKey(ValueKey('fc-bar-$i')));
        return (box.decoration as BoxDecoration).color!;
      }

      expect(colorOf(12), colors.accent);
      expect(colorOf(0), colors.textSecondary.withValues(alpha: 0.28));
      // 食事の記録がない日（3 日目・6 日目）は 0 の棒ではなく separator の線
      expect(colorOf(2), colors.separator);
      expect(tester.getSize(find.byKey(const ValueKey('fc-bar-2'))).height, 2);
      expect(colorOf(5), colors.separator);
    });

    testWidgets('PFC の色分け（旧 pfc 色・カテゴリ色）を使わない', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );
      final oldCategoryColors = <Color>{
        AppColors.pfcProtein,
        AppColors.pfcFat,
        AppColors.pfcCarbs,
        AppColors.amber300,
        AppColors.rose100,
        AppColors.indigo600,
      };
      final used = <Color>{
        for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)))
          if (box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).color != null)
            (box.decoration as BoxDecoration).color!,
      };
      expect(used.intersection(oldCategoryColors), isEmpty);
    });
  });

  group('期間の切り替え', () {
    testWidgets('今週に切り替えると、その期間の集計に変わる', (tester) async {
      // 今週は 3 日ぶん（今日を除く 2 日の平均 = 1,500 kcal）
      final weekDays = [
        for (var i = 0; i < 3; i++)
          DailyNutritionStat(
            date: DateTime(today.year, today.month, today.day - (2 - i)),
            calories: i == 0 ? 1400 : (i == 1 ? 1600 : 700),
            protein: 60,
            fat: 40,
            carbs: 180,
          ),
      ];
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          trend: (p) async =>
              p == PeriodFilter.week ? weekDays : sampleDays(today),
          records: sampleWeights(today),
          goal: sampleGoal(),
        ),
      );
      expect(_num('1,987', 'kcal'), findsOneWidget);

      await tester.tap(find.text('今週'));
      await tester.pumpAndSettle();

      expect(_num('1,500', 'kcal'), findsOneWidget);
      expect(find.text('1日平均 · ${_range(today, 3)}のうち記録した2日'), findsOneWidget);
      expect(find.text('記録した2日の平均'), findsOneWidget);
      expect(find.text('60 g'), findsOneWidget);
    });

    testWidgets('選択中のセグメントは actionFill の塗り、ほかは surface', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );
      Color fillOf(String label) {
        final container = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (container.decoration as BoxDecoration).color!;
      }

      final colors = AppColorsExtension.light;
      expect(fillOf('今月'), colors.actionFill);
      expect(fillOf('今週'), colors.surface);
    });
  });

  group('食事や体重の記録が一部ない', () {
    testWidgets('食事の記録が無ければカロリー・PFC は「記録がありません」「未記録」。0 とは出さない', (tester) async {
      final onlyWeight = [
        for (var i = 0; i < 5; i++)
          DailyNutritionStat(
            date: DateTime(today.year, today.month, today.day - (4 - i)),
            weight: i == 4 ? 62.4 : null,
          ),
      ];
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          days: onlyWeight,
          records: sampleWeights(today),
          goal: sampleGoal(),
        ),
      );

      expect(find.text('この期間の食事の記録はありません。'), findsOneWidget);
      expect(find.text('未記録'), findsNWidgets(3));
      expect(find.text('0 g'), findsNothing);
      expect(find.textContaining('kcal'), findsNothing);
      expect(find.byType(FcBars), findsNothing);
    });

    testWidgets('体重の記録が無ければ体重カードは文言だけ（0 kg を出さない）', (tester) async {
      final onlyMeals = [
        for (final d in sampleDays(today)) DailyNutritionStat(
          date: d.date,
          calories: d.calories,
          protein: d.protein,
          fat: d.fat,
          carbs: d.carbs,
        ),
      ];
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(days: onlyMeals, goal: sampleGoal()),
      );

      expect(find.text('この期間の体重の記録はありません。'), findsOneWidget);
      expect(find.byType(FcLineChart), findsNothing);
      expect(_num('0.0', 'kg'), findsNothing);
    });

    testWidgets('目標が未設定なら、目標線も「目標 〇 kg」も出さない', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          days: sampleDays(today),
          records: sampleWeights(today),
          goal: sampleGoal(target: null),
        ),
      );
      expect(find.text('${expectedJpDate(today)}7:30'), findsOneWidget);
      expect(find.textContaining('目標'), findsNothing);
      expect(tester.widget<FcLineChart>(find.byType(FcLineChart)).goal, isNull);
    });
  });

  group('状態', () {
    testWidgets('期間内に記録が 1 件も無ければ「まだ記録がありません」', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          days: [
            for (var i = 0; i < 13; i++)
              DailyNutritionStat(
                date: DateTime(today.year, today.month, today.day - (12 - i)),
              ),
          ],
          goal: sampleGoal(),
        ),
      );
      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(find.byType(FcStateMessage), findsOneWidget);
      expect(find.byType(FcLineChart), findsNothing);
      // 期間の切り替えは残る
      expect(find.text('今月'), findsOneWidget);
    });

    group('記録なしの「メッセージから記録する」', () {
      List<Override> emptyOverrides() => recordsOverrides(
            days: [
              for (var i = 0; i < 13; i++)
                DailyNutritionStat(
                  date: DateTime(today.year, today.month, today.day - (12 - i)),
                ),
            ],
            goal: sampleGoal(),
          );

      testWidgets('コールバックがあれば入口が出て、押すと呼ばれる', (tester) async {
        var opened = 0;
        await pumpRecordsPage(
          tester,
          RecordsOverviewScreen(onOpenMessages: () => opened++),
          overrides: emptyOverrides(),
        );

        expect(find.text('メッセージから記録する'), findsOneWidget);
        expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);

        await tester.tap(find.text('メッセージから記録する'));
        await tester.pump();
        expect(opened, 1);
      });

      testWidgets('コールバックが null なら入口は出さず、文言だけ', (tester) async {
        await pumpRecordsPage(
          tester,
          const RecordsOverviewScreen(),
          overrides: emptyOverrides(),
        );
        expect(find.text('まだ記録がありません'), findsOneWidget);
        expect(find.text('メッセージから記録する'), findsNothing);
        expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
      });

      testWidgets('記録があるときは、コールバックがあっても入口は出さない', (tester) async {
        await pumpRecordsPage(
          tester,
          RecordsOverviewScreen(onOpenMessages: () {}),
          overrides: normalOverrides(),
        );
        expect(find.text('メッセージから記録する'), findsNothing);
      });
    });

    testWidgets('読込中は配置を保つスケルトン。0 や「未記録」を出さない', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          trend: (_) => Completer<List<DailyNutritionStat>>().future,
          goal: sampleGoal(),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(FcCard), findsNWidgets(3));
      expect(find.text('未記録'), findsNothing);
      expect(find.textContaining('kcal'), findsNothing);
      handle.dispose();
    });

    group('再試行は、栄養トレンドが待っている体重・食事の取得も読み直す', () {
      /// 食事の取得を、呼ばれるたびに数えて、[fail] のあいだは失敗させる
      List<Override> flakyOverrides({
        required _Flaky meals,
        required _Flaky weights,
      }) =>
          [
            for (final period in PeriodFilter.values) ...[
              weightRecordsProvider(period: period).overrideWith(
                () => LoadingWeightRecords(() async {
                  weights.calls++;
                  if (weights.fail) throw Exception('weights failed');
                  return sampleWeights(today);
                }),
              ),
              mealRecordsProvider(period: period).overrideWith(
                () => _FlakyMealRecords(meals),
              ),
            ],
            currentGoalProvider.overrideWith((ref) async => sampleGoal()),
          ];

      testWidgets('食事の取得が失敗していても、再試行で食事を取り直して表示できる', (tester) async {
        final meals = _Flaky(fail: true);
        final weights = _Flaky();
        await pumpRecordsPage(
          tester,
          const RecordsOverviewScreen(),
          overrides: flakyOverrides(meals: meals, weights: weights),
        );

        expect(find.text('読み込めませんでした'), findsOneWidget);
        expect(meals.calls, 1);

        meals.fail = false;
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();

        // 食事を取り直した（キャッシュされた失敗を返し続けない）
        expect(meals.calls, 2);
        expect(find.text('読み込めませんでした'), findsNothing);
        expect(find.byType(FcLineChart), findsOneWidget);
        expect(find.text('PFCバランス（1日平均）'), findsOneWidget);
      });

      testWidgets('食事の取得が別の画面にも購読されていて失敗が保持されていても、再試行で取り直せる', (tester) async {
        // 食事の取得（今月）をほかの場所も購読していると、トレンドだけ読み直しても
        // 保持された失敗が返り続ける。再試行は食事の取得そのものを無効化する必要がある
        final meals = _Flaky(fail: true);
        final weights = _Flaky();
        await pumpRecordsPage(
          tester,
          Column(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  ref.watch(mealRecordsProvider(period: PeriodFilter.month));
                  return const SizedBox.shrink();
                },
              ),
              const Expanded(child: RecordsOverviewScreen()),
            ],
          ),
          overrides: flakyOverrides(meals: meals, weights: weights),
        );

        expect(find.text('読み込めませんでした'), findsOneWidget);
        expect(meals.calls, 1);

        meals.fail = false;
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();

        expect(meals.calls, 2);
        expect(find.text('読み込めませんでした'), findsNothing);
        expect(find.byType(FcLineChart), findsOneWidget);
      });

      testWidgets('体重の取得が失敗していても、再試行で体重を取り直して表示できる', (tester) async {
        final meals = _Flaky();
        final weights = _Flaky(fail: true);
        await pumpRecordsPage(
          tester,
          const RecordsOverviewScreen(),
          overrides: flakyOverrides(meals: meals, weights: weights),
        );

        expect(find.text('読み込めませんでした'), findsOneWidget);
        final weightCalls = weights.calls;

        weights.fail = false;
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();

        expect(weights.calls, greaterThan(weightCalls));
        expect(find.text('読み込めませんでした'), findsNothing);
        expect(find.byType(FcLineChart), findsOneWidget);
      });

      testWidgets('再試行しても失敗し続けるあいだは、失敗の表示のまま（読込中のまま固まらない）', (tester) async {
        final meals = _Flaky(fail: true);
        await pumpRecordsPage(
          tester,
          const RecordsOverviewScreen(),
          overrides: flakyOverrides(meals: meals, weights: _Flaky()),
        );
        await tester.tap(find.text('再試行'));
        await tester.pumpAndSettle();

        expect(meals.calls, 2);
        expect(find.text('読み込めませんでした'), findsOneWidget);
        expect(find.text('再試行'), findsOneWidget);
      });
    });

    testWidgets('読み込みに失敗したら、原因の文字列を見せずに再試行を出す', (tester) async {
      var calls = 0;
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: recordsOverrides(
          trend: (_) async {
            calls++;
            throw Exception('SocketException: 内部のエラー文字列');
          },
          goal: sampleGoal(),
        ),
      );

      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);

      final before = calls;
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
    });
  });

  group('ダーク・文字拡大・タッチ領域', () {
    testWidgets('ダークでも例外なく描画され、カードは surface（ダーク）の不透明な面', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);

      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard).first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((card.decoration as BoxDecoration).color, AppColorsExtension.dark.surface);
    });

    for (final period in [PeriodFilter.month, PeriodFilter.threeMonths]) {
      testWidgets('文字 1.35 倍（${period.label}）でも横にはみ出さず、最後までスクロールできる', (tester) async {
        await pumpRecordsPage(
          tester,
          const RecordsOverviewScreen(),
          overrides: recordsOverrides(
            days: sampleDays(today, count: period == PeriodFilter.month ? 13 : 92),
            records: sampleWeights(today),
            goal: sampleGoal(),
          ),
          textScale: 1.35,
        );
        if (period == PeriodFilter.threeMonths) {
          await tester.tap(find.text('3ヶ月'));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);

        // 注記まで届く
        await tester.dragUntilVisible(
          find.text('カロリーとPFCは、食事の写真と内容からの推定値です。'),
          find.byType(ListView),
          const Offset(0, -300),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(ListView)).width, 390);
      });
    }

    testWidgets('期間セグメントのタッチ領域は 44 以上', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );
      for (final label in ['今週', '今月', '3ヶ月']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(FcPressable)),
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('左右の余白は 20、狭い画面（幅 340）では 16', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
      );
      expect(tester.getTopLeft(find.byType(FcCard).first).dx, 20);
      expect(tester.getSize(find.byType(FcCard).first).width, 350);

      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
        size: const Size(340, 700),
      );
      expect(tester.getTopLeft(find.byType(FcCard).first).dx, 16);
    });

    testWidgets('本文の下はナビぶん（MediaQuery の下余白）を空けて、最後の注記がナビに隠れない', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsOverviewScreen(),
        overrides: normalOverrides(),
        size: const Size(390, 2000),
      );
      final caption = find.text('カロリーとPFCは、食事の写真と内容からの推定値です。');
      final listBottom = tester.getBottomLeft(find.byType(ListView)).dy;
      // 全部が収まる高さなので、スクロール領域の末尾の余白（121）が残る
      expect(listBottom - tester.getBottomLeft(caption).dy, greaterThanOrEqualTo(121));
    });
  });
}
