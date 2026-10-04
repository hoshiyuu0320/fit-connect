import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/home/presentation/utils/home_formatting.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/goal_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'home_test_support.dart';

/// 数値（`FcNum` は Text.rich）
Finder _num(String value) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith(value),
    );

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    Widget card, {
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
  }) {
    return pumpHome(
      tester,
      Padding(padding: const EdgeInsets.all(20), child: card),
      overrides: const [],
      brightness: brightness,
      textScale: textScale,
    );
  }

  group('GoalCard 進行中', () {
    testWidgets('現在 / 目標 / 目標まで の 3 指標と、説明・開始時の体重・期限が出る', (tester) async {
      final now = DateTime.now();
      await pumpCard(
        tester,
        GoalCard(
          currentWeight: 62.4,
          targetWeight: 65.0,
          initialWeight: 61.0,
          targetDate: DateTime(now.year, 12, 31),
          goalDescription: '筋肉をつけて体重を増やす',
        ),
      );

      expect(find.text('目標'), findsNWidgets(2)); // 見出し + 指標のラベル
      expect(find.text('現在'), findsOneWidget);
      expect(find.text('目標まで'), findsOneWidget);
      expect(_num('62.4'), findsOneWidget);
      expect(_num('65.0'), findsOneWidget);
      expect(_num('2.6'), findsOneWidget);
      expect(find.text('筋肉をつけて体重を増やす · 開始時 61.0 kg'), findsOneWidget);
      expect(find.text('12月31日まで'), findsOneWidget);
      expect(find.byType(FcSeparator), findsOneWidget);
    });

    testWidgets('達成率（％）・進捗バー・グラデーションは出さない', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 65.2,
          targetWeight: 60.0,
          initialWeight: 67.5,
        ),
      );

      expect(find.textContaining('%', findRichText: true), findsNothing);
      expect(find.textContaining('達成率'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) {
        final decoration = d.decoration;
        return decoration is BoxDecoration && decoration.gradient != null;
      });
      expect(gradients, isEmpty);
    });

    testWidgets('減量でも増量でも「目標まで」は差の絶対値（符号で色分けしない）', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 65.2,
          targetWeight: 60.0,
          initialWeight: 67.5,
        ),
      );
      expect(_num('5.2'), findsOneWidget);

      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 62.4,
          targetWeight: 65.0,
          initialWeight: 61.0,
        ),
      );
      expect(_num('2.6'), findsOneWidget);
    });

    testWidgets('期限が無ければ右上は空、説明も開始時も無ければ区切りと補足を出さない', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 62.4,
          targetWeight: 65.0,
          initialWeight: null,
        ),
      );
      expect(find.textContaining('まで'), findsOneWidget); // 「目標まで」だけ
      expect(find.byType(FcSeparator), findsNothing);
    });

    testWidgets('現在の体重がまだ無ければ 0 ではなく「—」', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: null,
          targetWeight: 65.0,
          initialWeight: null,
        ),
      );
      expect(_num('—'), findsNWidgets(2));
      expect(_num('0.0'), findsNothing);
    });

    testWidgets('文字拡大 1.35 では指標が折り返して積み直され、overflow しない', (tester) async {
      final now = DateTime.now();
      await pumpCard(
        tester,
        GoalCard(
          currentWeight: 62.4,
          targetWeight: 65.0,
          initialWeight: 61.0,
          targetDate: DateTime(now.year, 12, 31),
          goalDescription: '筋肉をつけて体重を増やす',
        ),
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      // 3 つが 1 行に入らず、2 行以上になる
      final tops = {
        for (final label in ['現在', '目標まで'])
          label: tester.getTopLeft(find.text(label)).dy,
      };
      expect(tops['目標まで']!, greaterThan(tops['現在']!));
    });
  });

  group('GoalCard 達成', () {
    testWidgets('静かなカード: check-circle ＋「目標の 65.0 kg に届きました」＋ 達成日 ＋ 変化量', (tester) async {
      final now = DateTime.now();
      final achievedAt = DateTime(now.year, 12, 2); // 水曜とは限らないので曜日は組み立てる
      const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
      final expectedDate =
          '12月2日（${weekdays[achievedAt.weekday - 1]}）';

      await pumpCard(
        tester,
        GoalCard(
          currentWeight: 65.0,
          targetWeight: 65.0,
          initialWeight: 61.0,
          isAchieved: true,
          goalDescription: '筋肉をつけて体重を増やす',
          achievedAt: achievedAt,
        ),
      );

      expect(find.text('目標の 65.0 kg に届きました'), findsOneWidget);
      expect(find.byIcon(LucideIcons.checkCircle2), findsOneWidget);
      expect(find.text(expectedDate), findsOneWidget);
      expect(find.text('筋肉をつけて体重を増やす · 開始時 61.0 kg から +4.0 kg'),
          findsOneWidget);
      // 演出（トロフィー・100%・金色）は出さない
      expect(find.byIcon(LucideIcons.trophy), findsNothing);
      expect(find.textContaining('100%'), findsNothing);
      expect(find.text('現在'), findsNothing);
    });

    testWidgets('減量の達成は変化量が負の符号つき。色は変えない', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 60.0,
          targetWeight: 60.0,
          initialWeight: 67.5,
          isAchieved: true,
        ),
      );

      expect(find.text('開始時 67.5 kg から -7.5 kg'), findsOneWidget);
      final colors = AppColorsExtension.light;
      final meta = tester.widget<Text>(find.text('開始時 67.5 kg から -7.5 kg'));
      expect(meta.style!.color, colors.textSecondary);
    });

    testWidgets('達成日が分からなければ右上に出さず、ダークでも出る', (tester) async {
      await pumpCard(
        tester,
        const GoalCard(
          currentWeight: 65.0,
          targetWeight: 65.0,
          initialWeight: 61.0,
          isAchieved: true,
        ),
        brightness: Brightness.dark,
      );

      expect(find.text('目標の 65.0 kg に届きました'), findsOneWidget);
      expect(find.textContaining('月'), findsNothing);
    });
  });

  group('GoalCard その他の状態', () {
    testWidgets('読み込み中は見出しとスケルトン（0 を出さない）', (tester) async {
      await pumpCard(tester, const GoalCard.loading());

      expect(find.text('目標'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsNWidgets(6));
      expect(find.textContaining('kg', findRichText: true), findsNothing);
    });

    testWidgets('目標が未設定: 「目標はまだ設定されていません」＋ トレーナー名', (tester) async {
      await pumpCard(
        tester,
        const GoalNotSetCard(trainerName: '田中トレーナー'),
      );

      expect(find.text('目標はまだ設定されていません'), findsOneWidget);
      expect(find.text('田中トレーナーが目標を設定すると、ここに表示されます。'), findsOneWidget);
    });
  });

  group('home_formatting', () {
    test('formatHomeTime: 今日は時刻だけ、それ以外は日付つき', () {
      final now = DateTime(2026, 9, 13, 12);
      expect(formatHomeTime(DateTime(2026, 9, 13, 7, 5), now: now), '7:05');
      expect(formatHomeTime(DateTime(2026, 9, 12, 7, 5), now: now), '9月12日 7:05');
    });

    test('formatDeadline: 年が違うときだけ年を付ける', () {
      final now = DateTime(2026, 9, 13);
      expect(formatDeadline(DateTime(2026, 12, 31), now: now), '12月31日まで');
      expect(formatDeadline(DateTime(2027, 1, 15), now: now), '2027年1月15日まで');
    });

    test('formatWeekStartLabel は今週の月曜', () {
      // 2026-09-13 は日曜 → 週の起点は 9/7（月）
      expect(formatWeekStartLabel(DateTime(2026, 9, 13)), '今週（9/7〜）');
      expect(formatWeekStartLabel(DateTime(2026, 9, 7)), '今週（9/7〜）');
    });
  });
}
