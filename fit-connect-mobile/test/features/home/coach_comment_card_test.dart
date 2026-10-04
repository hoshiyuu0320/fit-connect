import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/features/home/presentation/widgets/coach_comment_card.dart';
import 'package:fit_connect_mobile/features/home/providers/latest_trainer_comment_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'home_test_support.dart';

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

  group('findLatestTrainerComment', () {
    final base = DateTime(2026, 9, 13, 9, 0);

    test('メッセージが無い・トレーナーのメッセージが無いなら null', () {
      expect(findLatestTrainerComment(const []), isNull);
      expect(
        findLatestTrainerComment([
          sampleMessage(id: 'a', sender: 'client', content: 'こんにちは', at: base),
        ]),
        isNull,
      );
    });

    test('並び順に関わらず、トレーナーの最新（createdAt）を選ぶ', () {
      final result = findLatestTrainerComment([
        sampleMessage(
          id: 'new',
          sender: 'trainer',
          content: '新しい',
          at: base.add(const Duration(hours: 2)),
        ),
        sampleMessage(id: 'old', sender: 'trainer', content: '古い', at: base),
        sampleMessage(
          id: 'mine',
          sender: 'client',
          content: '自分の最新',
          at: base.add(const Duration(hours: 5)),
        ),
      ]);

      expect(result!.message.id, 'new');
    });

    test('返信先の記録の種別が分かれば、その詳細（なければ種類）を使う', () {
      final meal = findLatestTrainerComment([
        sampleMessage(
          id: 'c1',
          sender: 'client',
          content: '朝食です',
          at: base,
          tags: ['#食事:朝食'],
        ),
        sampleMessage(
          id: 't1',
          sender: 'trainer',
          content: 'いいですね',
          at: base.add(const Duration(minutes: 10)),
          replyTo: 'c1',
        ),
      ]);
      expect(meal!.recordLabel, '朝食');
      expect(
        meal.contextLine(now: base),
        '朝食の記録へのコメント · 9:10',
      );

      final weight = findLatestTrainerComment([
        sampleMessage(
          id: 'c2',
          sender: 'client',
          content: '65.0kg',
          at: base,
          tags: ['#体重'],
        ),
        sampleMessage(
          id: 't2',
          sender: 'trainer',
          content: 'おめでとう',
          at: base.add(const Duration(minutes: 2)),
          replyTo: 'c2',
        ),
      ]);
      expect(weight!.recordLabel, '体重');
    });

    test('返信先が見つからない・種別のタグが無いときは時刻だけ', () {
      final noReply = findLatestTrainerComment([
        sampleMessage(
          id: 't1',
          sender: 'trainer',
          content: 'こんにちは',
          at: base.add(const Duration(minutes: 5)),
        ),
      ]);
      expect(noReply!.recordLabel, isNull);
      expect(noReply.contextLine(now: base), '9:05');

      final noTag = findLatestTrainerComment([
        sampleMessage(id: 'c', sender: 'client', content: 'ふつうの話', at: base),
        sampleMessage(
          id: 't',
          sender: 'trainer',
          content: '了解です',
          at: base.add(const Duration(minutes: 5)),
          replyTo: 'c',
        ),
      ]);
      expect(noTag!.recordLabel, isNull);

      final missingTarget = findLatestTrainerComment([
        sampleMessage(
          id: 't',
          sender: 'trainer',
          content: '了解です',
          at: base,
          replyTo: 'not-loaded',
        ),
      ]);
      expect(missingTarget!.recordLabel, isNull);
    });

    test('今日以外の時刻は日付つき。画像だけのメッセージは「写真を送りました」', () {
      final result = findLatestTrainerComment([
        sampleMessage(
          id: 'img',
          sender: 'trainer',
          content: '',
          at: DateTime(2026, 9, 12, 21, 3),
          imageUrls: ['path/a.jpg'],
        ),
      ]);

      expect(result!.body, '写真を送りました');
      expect(result.contextLine(now: DateTime(2026, 9, 13, 8)), '9月12日 21:03');
    });

    test('本文も画像も無いメッセージは対象外', () {
      expect(
        findLatestTrainerComment([
          sampleMessage(id: 'blank', sender: 'trainer', content: '  ', at: base),
        ]),
        isNull,
      );
    });
  });

  group('CoachCommentCard', () {
    testWidgets('アバター（イニシャル）・名前・コンテキスト・本文・chevron が出る', (tester) async {
      var taps = 0;
      await pumpCard(
        tester,
        CoachCommentCard(
          coachName: '田中トレーナー',
          contextLine: '朝食の記録へのコメント · 9:10',
          message: '朝食の記録、ありがとうございます。',
          onTap: () => taps++,
        ),
      );

      expect(find.byType(FcAvatar), findsOneWidget);
      expect(tester.getSize(find.byType(FcAvatar)), const Size(39, 39));
      expect(find.text('田中トレーナー'), findsOneWidget);
      expect(find.text('朝食の記録へのコメント · 9:10'), findsOneWidget);
      expect(find.text('朝食の記録、ありがとうございます。'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);

      await tester.tap(find.text('朝食の記録、ありがとうございます。'));
      expect(taps, 1);
    });

    testWidgets('オンライン表示・未読の数字は出さない', (tester) async {
      await pumpCard(
        tester,
        CoachCommentCard(
          coachName: '田中トレーナー',
          message: 'こんにちは',
          onTap: () {},
        ),
      );

      expect(find.textContaining('オンライン'), findsNothing);
      expect(find.textContaining('オフライン'), findsNothing);
      expect(find.textContaining('最終ログイン'), findsNothing);
      expect(find.byIcon(LucideIcons.calendar), findsNothing);
    });

    testWidgets('メッセージが無い: 役割の補足・案内・「メッセージを送る」', (tester) async {
      var sent = 0;
      await pumpCard(
        tester,
        CoachCommentCard.empty(
          coachName: '田中トレーナー',
          onSendMessage: () => sent++,
        ),
      );

      expect(find.text('あなたの担当トレーナー'), findsOneWidget);
      expect(
        find.text('まだメッセージはありません。体重や食事の記録も、メッセージから送れます。'),
        findsOneWidget,
      );
      expect(find.text('メッセージを送る'), findsOneWidget);

      await tester.tap(find.text('メッセージを送る'));
      expect(sent, 1);
    });

    testWidgets('取得に失敗: メッセージ画面への入口は残る', (tester) async {
      var opened = 0;
      await pumpCard(
        tester,
        CoachCommentCard.unavailable(
          coachName: '田中トレーナー',
          onOpenMessages: () => opened++,
        ),
      );

      expect(find.textContaining('読み込めませんでした'), findsOneWidget);
      await tester.tap(find.text('メッセージを開く'));
      expect(opened, 1);
    });

    testWidgets('読み込み中はアバターと 2 行のスケルトンで配置を保つ', (tester) async {
      await pumpCard(tester, const CoachCommentCard.loading());

      expect(find.byType(FcSkeleton), findsNWidgets(5));
      expect(find.text('田中トレーナー'), findsNothing);
    });

    for (final (name, brightness, scale) in [
      ('ライト 1.35', Brightness.light, 1.35),
      ('ダーク 1.35', Brightness.dark, 1.35),
    ]) {
      testWidgets('文字拡大・$name でも overflow せず、押せる領域が 44 以上', (tester) async {
        await pumpCard(
          tester,
          Column(
            children: [
              CoachCommentCard(
                coachName: '田中トレーナー',
                contextLine: '朝食の記録へのコメント · 9:10',
                message: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
                onTap: () {},
              ),
              const SizedBox(height: 16),
              CoachCommentCard.empty(coachName: '田中トレーナー', onSendMessage: () {}),
            ],
          ),
          brightness: brightness,
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        final button = tester.getSize(find.byType(FcButton));
        expect(button.height, greaterThanOrEqualTo(44));
      });
    }
  });
}
