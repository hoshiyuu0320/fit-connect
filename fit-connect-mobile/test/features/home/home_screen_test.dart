import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/coach_comment_card.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/goal_card.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/getting_started_card.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/next_session_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'home_test_support.dart';

/// ホームタブ全体の表示テスト（正本: home-screens.js の `HomeScreen`）。
/// プロバイダーはすべて差し替える（Supabase には出ない）。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> overrides,
    void Function(int)? onRecords,
    VoidCallback? onMessages,
    void Function(String)? onConsult,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    Size size = const Size(390, 1800),
    bool settle = true,
  }) {
    return pumpHome(
      tester,
      HomeScreen(
        onNavigateToRecordsTab: onRecords,
        onNavigateToMessages: onMessages,
        onConsultAboutSession: onConsult,
      ),
      overrides: overrides,
      brightness: brightness,
      textScale: textScale,
      size: size,
      settle: settle,
    );
  }

  /// 画面内の縦位置（上から何番目のカードか）
  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first).dy;

  group('ホーム（通常の日）', () {
    testWidgets('見出し: 今日の日付・「こんにちは、{名前}さん」・ひとこと。絵文字なし', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      final now = DateTime.now();
      const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
      expect(
        find.text('${now.month}月${now.day}日（${weekdays[now.weekday - 1]}）'),
        findsOneWidget,
      );
      expect(find.text('こんにちは、佐藤さん'), findsOneWidget);
      expect(find.text('今日も、自分のペースで。'), findsOneWidget);
      expect(find.textContaining('👋'), findsNothing);
      expect(find.textContaining('頑張りましょう'), findsNothing);
    });

    testWidgets('順序は 目標 → 最新コメント → 次回のセッション → 今日のまとめ。カード間は 16', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      final goal = find.byType(GoalCard);
      final coach = find.byType(CoachCommentCard);
      final session = find.byType(NextSessionCard);
      final summary = find.text('今日のまとめ');

      expect(top(tester, goal), lessThan(top(tester, coach)));
      expect(top(tester, coach), lessThan(top(tester, session)));
      expect(top(tester, session), lessThan(top(tester, summary)));

      // カード間 16
      double bottom(Finder f) => tester.getBottomLeft(f.first).dy;
      expect(top(tester, coach) - bottom(goal), 16);
      expect(top(tester, session) - bottom(coach), 16);
      // 「はじめの3ステップ」は 14 日以上前の登録なので出ない
      expect(find.byType(GettingStartedCardBody), findsNothing);
    });

    testWidgets('目標カード: 現在 / 目標 / 目標まで と開始時の体重（％・進捗バーなし）', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      expect(find.text('現在'), findsOneWidget);
      expect(find.text('目標まで'), findsOneWidget);
      expect(find.text('筋肉をつけて体重を増やす · 開始時 61.0 kg'), findsOneWidget);
      expect(find.textContaining('達成率'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('最新コメント: トレーナーの最新メッセージと、返信先の記録の種別・時刻', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      expect(find.text('田中トレーナー'), findsWidgets);
      expect(find.text('朝食の記録へのコメント · 9:10'), findsOneWidget);
      expect(
        find.text('朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。'),
        findsOneWidget,
      );
      // オンライン表示は出さない
      expect(find.textContaining('オンライン'), findsNothing);
      expect(find.textContaining('最終ログイン'), findsNothing);
    });

    testWidgets('次回のセッション: 日時（全角括弧）・あとN日・補足', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      expect(find.text('次回のセッション'), findsOneWidget);
      expect(find.text('あと2日'), findsOneWidget);
      expect(find.text('60分 · パーソナル · 確定'), findsOneWidget);
      expect(find.textContaining('）19:00'), findsOneWidget);
    });

    testWidgets('今日のまとめ: 4 行', (tester) async {
      await pumpScreen(tester, overrides: normalHomeOverrides());

      expect(find.byType(FcListRow), findsNWidgets(4));
      expect(find.text('前回から +0.1 kg · 7:30'), findsOneWidget);
    });
  });

  group('ホーム（操作）', () {
    testWidgets('最新コメントのカードをタップするとメッセージタブへ', (tester) async {
      var toMessages = 0;
      await pumpScreen(
        tester,
        overrides: normalHomeOverrides(),
        onMessages: () => toMessages++,
      );

      await tester.tap(find.text('朝食の記録へのコメント · 9:10'));
      await tester.pumpAndSettle();

      expect(toMessages, 1);
    });

    testWidgets('今日のまとめの行は記録タブの該当サブタブへ（1=体重 2=食事 3=運動 4=睡眠）', (tester) async {
      final tabs = <int>[];
      await pumpScreen(
        tester,
        overrides: normalHomeOverrides(),
        onRecords: tabs.add,
      );

      for (final title in ['食事', '運動', '体重', '睡眠']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(tabs, [2, 3, 1, 4]);
    });
  });

  group('ホーム（はじめて）', () {
    testWidgets('はじめの3ステップが先頭に出て、目標・コメント・予定・記録は案内の状態', (tester) async {
      final overrides = homeOverrides(
        client: sampleClient(
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          initial: null,
          target: null,
        ),
        goal: sampleClient(initial: null, target: null),
        trainer: sampleTrainer(),
      );
      await pumpScreen(tester, overrides: overrides, onMessages: () {});

      expect(find.text('はじめの3ステップ'), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(top(tester, find.text('はじめの3ステップ')),
          lessThan(top(tester, find.byType(GoalNotSetCard))));

      expect(find.text('目標はまだ設定されていません'), findsOneWidget);
      expect(find.text('田中トレーナーが目標を設定すると、ここに表示されます。'), findsOneWidget);

      expect(find.text('あなたの担当トレーナー'), findsOneWidget);
      expect(
        find.text('まだメッセージはありません。体重や食事の記録も、メッセージから送れます。'),
        findsOneWidget,
      );
      expect(find.text('メッセージを送る'), findsOneWidget);

      expect(find.text('予定はまだありません'), findsOneWidget);
      expect(find.text('日程は田中トレーナーと相談して決めます。'), findsOneWidget);
      expect(find.text('トレーナーに相談する'), findsOneWidget);
      expect(find.text('これまでのセッション'), findsOneWidget);

      expect(find.text('未記録'), findsNWidgets(3));
      expect(find.text('目覚めを記録'), findsOneWidget);
    });

    testWidgets('「メッセージを送る」「トレーナーに相談する」は既存の導線に流れる', (tester) async {
      var toMessages = 0;
      final drafts = <String>[];
      await pumpScreen(
        tester,
        overrides: homeOverrides(
          client: sampleClient(
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          goal: sampleClient(initial: null, target: null),
          trainer: sampleTrainer(),
        ),
        onMessages: () => toMessages++,
        onConsult: drafts.add,
      );

      await tester.tap(find.text('メッセージを送る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('トレーナーに相談する'));
      await tester.pumpAndSettle();

      expect(toMessages, 1);
      expect(drafts, ['']);
    });

    testWidgets('はじめの3ステップを閉じると消え、以後の余白も残らない', (tester) async {
      await pumpScreen(
        tester,
        overrides: homeOverrides(
          client: sampleClient(
            createdAt: DateTime.now().subtract(const Duration(days: 1)),
          ),
          goal: sampleClient(initial: null, target: null),
          trainer: sampleTrainer(),
        ),
      );
      expect(find.text('はじめの3ステップ'), findsOneWidget);
      final goalTopBefore = top(tester, find.byType(GoalNotSetCard));

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.text('はじめの3ステップ'), findsNothing);
      expect(top(tester, find.byType(GoalNotSetCard)), lessThan(goalTopBefore));
    });
  });

  group('ホーム（読み込み中・達成・失敗）', () {
    testWidgets('読み込み中は「こんにちは」だけ。各カードは配置を保つスケルトン', (tester) async {
      await pumpScreen(
        tester,
        overrides: homeOverrides(loading: true),
        settle: false,
      );

      expect(find.text('こんにちは'), findsOneWidget);
      expect(find.byType(GoalCard), findsOneWidget);
      expect(find.byType(CoachCommentCard), findsOneWidget);
      expect(find.byType(NextSessionCardView), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      // 未取得を 0 にしない
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.text('未記録'), findsNothing);
    });

    testWidgets('目標に届いた日: 静かなカード（演出・トロフィー・％なし）', (tester) async {
      final now = DateTime.now();
      final d = DateTime(now.year, now.month, now.day);
      await pumpScreen(
        tester,
        overrides: homeOverrides(
          client: sampleClient(),
          goal: sampleClient(achievedAt: DateTime(now.year, now.month, 2)),
          trainer: sampleTrainer(),
          latestWeight: sampleWeight(
            id: 'w1',
            weight: 65.0,
            at: DateTime(d.year, d.month, d.day, 7, 40),
          ),
          messageSent: true,
        ),
      );

      expect(find.text('目標の 65.0 kg に届きました'), findsOneWidget);
      expect(find.byIcon(LucideIcons.checkCircle2), findsOneWidget);
      expect(find.byIcon(LucideIcons.trophy), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('おめでとう'), findsNothing); // 演出の文言は画面側で出さない
    });

    testWidgets('メッセージを取得できなくても、メッセージ画面への入口は残る', (tester) async {
      var toMessages = 0;
      await pumpScreen(
        tester,
        overrides: homeOverrides(
          client: sampleClient(),
          goal: sampleClient(),
          trainer: sampleTrainer(),
          messagesFail: true,
        ),
        onMessages: () => toMessages++,
      );

      expect(find.textContaining('読み込めませんでした'), findsOneWidget);
      await tester.tap(find.text('メッセージを開く'));
      expect(toMessages, 1);
    });

    for (final (name, brightness) in [
      ('ライト', Brightness.light),
      ('ダーク', Brightness.dark),
    ]) {
      testWidgets('$name・文字 1.35 でも overflow せず、最後までスクロールできる', (tester) async {
        await pumpScreen(
          tester,
          overrides: normalHomeOverrides(),
          brightness: brightness,
          textScale: 1.35,
          size: const Size(390, 844),
        );

        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        // 今日のまとめの最後の行（睡眠）まで届き、ナビぶんの余白の上に収まる
        final sleepBottom = tester.getBottomLeft(find.text('睡眠')).dy;
        expect(sleepBottom, lessThanOrEqualTo(844 - 121));
      });
    }
  });
}
