import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/features/home/presentation/widgets/daily_summary_card.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'home_test_support.dart';

/// `FcRowValue.metric`（Text.rich）の全文
bool _hasRich(String plain) => find
    .byWidgetPredicate((w) =>
        w is RichText &&
        w.text.toPlainText().replaceAll('￼', '') == plain)
    .evaluate()
    .isNotEmpty;

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Override> overrides,
    VoidCallback? onMealsTap,
    VoidCallback? onActivityTap,
    VoidCallback? onWeightTap,
    VoidCallback? onSleepTap,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    bool settle = true,
  }) {
    return pumpHome(
      tester,
      SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: DailySummaryCard(
          onMealsTap: onMealsTap,
          onActivityTap: onActivityTap,
          onWeightTap: onWeightTap,
          onSleepTap: onSleepTap,
        ),
      ),
      overrides: overrides,
      brightness: brightness,
      textScale: textScale,
      settle: settle,
    );
  }

  final today = DateTime.now();
  final d = DateTime(today.year, today.month, today.day);

  List<Override> recorded({
    int meals = 2,
    int exerciseDays = 3,
    SleepRecord? sleep,
    double latest = 62.4,
    double? previous = 62.3,
  }) {
    final latestRecord =
        sampleWeight(id: 'w1', weight: latest, at: DateTime(d.year, d.month, d.day, 7, 30));
    return homeOverrides(
      latestWeight: latestRecord,
      weightHistory: [
        latestRecord,
        if (previous != null)
          sampleWeight(
            id: 'w0',
            weight: previous,
            at: DateTime(d.year, d.month, d.day - 2, 7, 25),
          ),
      ],
      meals: meals,
      exerciseDays: exerciseDays,
      sleep: sleep ?? sampleSleep(),
    );
  }

  group('今日のまとめ（記録あり）', () {
    testWidgets('見出し「今日のまとめ」と 4 行（食事・運動・体重・睡眠）。絵文字・進捗バーは出ない', (tester) async {
      await pumpCard(tester, overrides: recorded());

      expect(find.text('今日のまとめ'), findsOneWidget);
      for (final title in ['食事', '運動', '体重', '睡眠']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(FcListRow), findsNWidgets(4));
      expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
      expect(find.byIcon(LucideIcons.dumbbell), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsOneWidget);
      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      // 区切り線は行の間の 3 本だけ
      expect(find.byType(FcSeparator), findsNWidgets(3));
    });

    testWidgets('値は数値＋単位、運動の補足は今週の起点、体重の補足は前回との差と時刻', (tester) async {
      await pumpCard(tester, overrides: recorded());

      expect(_hasRich('2回'), isTrue);
      expect(_hasRich('3日'), isTrue);
      expect(_hasRich('62.4kg'), isTrue);
      expect(_hasRich('7時間30分'), isTrue);

      final monday = d.subtract(Duration(days: d.weekday - 1));
      expect(find.text('今週（${monday.month}/${monday.day}〜）'), findsOneWidget);
      expect(find.text('前回から +0.1 kg · 7:30'), findsOneWidget);
      expect(find.text('HealthKit'), findsOneWidget);
    });

    testWidgets('体重が減ったときは負の符号。色は変えない', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(latest: 61.8, previous: 62.4),
      );

      final sub = tester.widget<Text>(find.text('前回から -0.6 kg · 7:30'));
      // caption は textSecondary のまま（良し悪しで色分けしない）
      expect(sub.style!.color, isNotNull);
      expect(sub.style!.color, tester.widget<Text>(find.text('HealthKit')).style!.color);
    });

    testWidgets('前回の記録が見つからなければ時刻だけ', (tester) async {
      await pumpCard(tester, overrides: recorded(previous: null));

      expect(find.text('7:30'), findsOneWidget);
      expect(find.textContaining('前回'), findsNothing);
    });

    testWidgets('睡眠が 1 時間未満なら「分」だけ', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(sleep: sampleSleep(minutes: 45)),
      );
      expect(_hasRich('45分'), isTrue);
    });

    testWidgets('目覚めの記録だけなら評価を言葉で（絵文字なし）', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(
          sleep: sampleSleep(minutes: null, rating: WakeupRating.refreshed),
        ),
      );
      expect(find.text('すっきり'), findsOneWidget);
      expect(find.text('目覚めの記録'), findsOneWidget);
    });
  });

  group('今日のまとめ（未記録・読み込み中）', () {
    testWidgets('未記録は 0 ではなく「未記録」。睡眠は「目覚めを記録」の入口', (tester) async {
      await pumpCard(tester, overrides: homeOverrides());

      expect(find.text('未記録'), findsNWidgets(3)); // 食事・運動・体重
      expect(find.text('メッセージから記録できます'), findsOneWidget);
      expect(find.text('ヘルスケアと連携すると自動で入ります'), findsOneWidget);
      expect(find.text('目覚めを記録'), findsOneWidget);
      expect(_hasRich('0回'), isFalse);
      expect(_hasRich('0日'), isFalse);
    });

    testWidgets('読み込み中は各行の値がスケルトン（0 を出さない）', (tester) async {
      await pumpCard(
        tester,
        overrides: homeOverrides(loading: true),
        settle: false,
      );

      expect(find.byType(FcListRow), findsNWidgets(4));
      expect(find.byType(FcSkeleton), findsNWidgets(4));
      expect(find.text('未記録'), findsNothing);
    });
  });

  group('今日のまとめ（操作）', () {
    testWidgets('各行のタップで記録タブの該当サブタブへ（コールバック）', (tester) async {
      final tapped = <String>[];
      await pumpCard(
        tester,
        overrides: recorded(),
        onMealsTap: () => tapped.add('meals'),
        onActivityTap: () => tapped.add('activity'),
        onWeightTap: () => tapped.add('weight'),
        onSleepTap: () => tapped.add('sleep'),
      );

      for (final title in ['食事', '運動', '体重', '睡眠']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(tapped, ['meals', 'activity', 'weight', 'sleep']);
      // 押せる行には chevron
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(4));
    });

    testWidgets('「目覚めを記録」を押すと記録シートが開き、行の遷移は起きない', (tester) async {
      var sleepTaps = 0;
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () => sleepTaps++,
      );

      await tester.tap(find.text('目覚めを記録'));
      await tester.pumpAndSettle();

      expect(find.byType(WakeupRatingSelector), findsOneWidget);
      expect(sleepTaps, 0);
    });

    testWidgets('睡眠の行（「目覚めを記録」以外）を押すと記録タブへ', (tester) async {
      var sleepTaps = 0;
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () => sleepTaps++,
      );

      await tester.tap(find.text('睡眠'));
      await tester.pumpAndSettle();

      expect(sleepTaps, 1);
      expect(find.byType(WakeupRatingSelector), findsNothing);
    });

    testWidgets('「目覚めを記録」は 44×44 以上で、読み上げの操作としても残る', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () {},
      );

      // いちばん近い FcPressable（行全体ではなく、右の「目覚めを記録」だけ）
      final size = tester.getSize(
        find
            .ancestor(
              of: find.text('目覚めを記録'),
              matching: find.byType(FcPressable),
            )
            .first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      // 行の読み上げは未記録としてまとめ、記録は別の操作として足している
      final node = tester.getSemantics(find.byType(FcListRow).last);
      expect(node.label, contains('睡眠'));
      expect(node.label, contains('未記録'));
      handle.dispose();
    });
  });

  group('今日のまとめ（文字拡大・ダーク）', () {
    for (final (name, brightness) in [
      ('ライト', Brightness.light),
      ('ダーク', Brightness.dark),
    ]) {
      testWidgets('$name・文字 1.35 でも overflow せず、行が縦に伸びる', (tester) async {
        await pumpCard(
          tester,
          overrides: homeOverrides(),
          brightness: brightness,
          textScale: 1.35,
          onMealsTap: () {},
          onActivityTap: () {},
          onWeightTap: () {},
          onSleepTap: () {},
        );

        expect(tester.takeException(), isNull);
        for (final row in tester.widgetList(find.byType(FcListRow))) {
          expect(row, isA<FcListRow>());
        }
        final heights = tester
            .widgetList(find.byType(FcListRow))
            .map((w) => tester.getSize(find.byWidget(w)).height);
        for (final h in heights) {
          expect(h, greaterThanOrEqualTo(56));
        }
      });
    }
  });

  group('weightSubLabel', () {
    final now = DateTime(2026, 9, 13, 12);
    final latest = sampleWeight(
      id: 'latest',
      weight: 62.4,
      at: DateTime(2026, 9, 13, 7, 30),
    );

    test('前回との差と時刻。同じ体重なら「前回と同じ」', () {
      final same = sampleWeight(
        id: 'prev',
        weight: 62.4,
        at: DateTime(2026, 9, 11, 7, 30),
      );
      expect(
        DailySummaryCard.weightSubLabel(
            latest: latest, history: [latest, same], now: now),
        '前回と同じ · 7:30',
      );
    });

    test('前回は「最新より前でいちばん新しい記録」', () {
      final older = sampleWeight(
        id: 'older',
        weight: 60.0,
        at: DateTime(2026, 9, 1, 7, 30),
      );
      final prev = sampleWeight(
        id: 'prev',
        weight: 62.0,
        at: DateTime(2026, 9, 12, 7, 30),
      );
      expect(
        DailySummaryCard.weightSubLabel(
            latest: latest, history: [latest, prev, older], now: now),
        '前回から +0.4 kg · 7:30',
      );
    });

    test('履歴が無ければ時刻だけ。今日でなければ日付つき', () {
      expect(
        DailySummaryCard.weightSubLabel(latest: latest, history: null, now: now),
        '7:30',
      );
      expect(
        DailySummaryCard.weightSubLabel(
          latest: latest,
          history: const [],
          now: DateTime(2026, 9, 14, 8),
        ),
        '9月13日 7:30',
      );
    });
  });
}
