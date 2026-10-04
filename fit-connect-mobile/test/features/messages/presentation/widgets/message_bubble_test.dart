import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/message_bubble.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('describeRecordMessage（記録カードの見出し・アイコン・状態行）', () {
    test('体重: scale ・「あなたの体重記録 · 7:30」・「体重の記録に追加しました」', () {
      final d = describeRecordMessage(tags: const ['#体重'], time: '7:30');
      expect(d.icon, LucideIcons.scale);
      expect(d.heading, 'あなたの体重記録 · 7:30');
      expect(d.status, '体重の記録に追加しました');
      expect(d.isRecord, isTrue);
    });

    test('食事: utensils ・区分ごとの見出し（朝食・昼食・夕食・間食・区分なし）', () {
      for (final (tag, label) in [
        ('#食事:朝食', '朝食'),
        ('#食事:昼食', '昼食'),
        ('#食事:夕食', '夕食'),
        ('#食事:間食', '間食'),
        ('#食事', '食事'),
      ]) {
        final d = describeRecordMessage(tags: [tag], time: '8:10');
        expect(d.icon, LucideIcons.utensils);
        expect(d.heading, 'あなたの$label記録 · 8:10');
        expect(d.status, '食事の記録に追加しました');
      }
    });

    test('運動: 有酸素 = footprints / 筋トレ = dumbbell', () {
      final cardio =
          describeRecordMessage(tags: const ['#運動:有酸素'], time: '18:20');
      expect(cardio.icon, LucideIcons.footprints);
      expect(cardio.heading, 'あなたの運動記録 · 有酸素 · 18:20');
      expect(cardio.status, '運動の記録に追加しました');

      final strength =
          describeRecordMessage(tags: const ['#運動:筋トレ'], time: '18:20');
      expect(strength.icon, LucideIcons.dumbbell);
      expect(strength.heading, 'あなたの運動記録 · 筋トレ · 18:20');
    });

    test('通常のメッセージ: message-circle ・状態行なし（既読は出さない）', () {
      final d = describeRecordMessage(tags: null, time: '9:24');
      expect(d.icon, LucideIcons.messageCircle);
      expect(d.heading, 'あなたのメッセージ · 9:24');
      expect(d.status, isNull);
      expect(d.isRecord, isFalse);
    });

    test('編集済み: 状態行に足す（タグなしなら「編集済み」だけ）', () {
      expect(
        describeRecordMessage(tags: null, time: '9:24', isEdited: true).status,
        '編集済み',
      );
      expect(
        describeRecordMessage(tags: const ['#体重'], time: '7:30', isEdited: true)
            .status,
        '体重の記録に追加しました · 編集済み',
      );
    });

    test('ワークアウト完了: 見出しにプラン名・本文を「消費 280 kcal」＋感想に整える', () {
      const body =
          '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。';
      final d = describeRecordMessage(
        tags: const ['#運動:完了'],
        time: '18:40',
        body: body,
      );
      expect(d.icon, LucideIcons.dumbbell);
      expect(d.heading, 'ワークアウト完了 · 上半身 · 18:40');
      expect(d.status, 'プランの完了を報告しました');
      expect(d.body, '消費 280 kcal\n肩の動きがよくなってきました。');
    });

    test('ワークアウト完了: タグが無くても本文の形で判定する（Web の解析と同じ）', () {
      final d = describeRecordMessage(
        tags: null,
        time: '18:40',
        body: '本日のワークアウトプラン「脚の日」を達成しました！',
      );
      expect(d.heading, 'ワークアウト完了 · 脚の日 · 18:40');
      expect(d.body, '');
    });

    test('ワークアウト完了: 本文が解析できないときは本文をそのまま出す', () {
      final d = describeRecordMessage(
        tags: const ['#運動:完了'],
        time: '18:40',
        body: '脚の日でした',
      );
      expect(d.heading, 'ワークアウト完了 · 18:40');
      expect(d.body, isNull);
    });
  });

  group('MessageBubble', () {
    testWidgets('自分のメッセージは記録カード（見出し・本文・状態行）で、既読は出さない', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '#体重 62.4 kg',
          isUser: true,
          timestamp: '7:30',
          tags: ['#体重'],
          isRead: true,
        ),
      );

      expect(find.text('あなたの体重記録 · 7:30'), findsOneWidget);
      expect(find.text('62.4 kg'), findsOneWidget); // タグは本文から取り除く
      expect(find.text('体重の記録に追加しました'), findsOneWidget);
      expect(find.textContaining('既読'), findsNothing);
    });

    testWidgets('記録カードは surface・角丸 20・左に 22 のインデント', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
        ),
      );

      final card = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(RecordMessageCard),
              matching: find.byType(DecoratedBox))
          .first);
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));

      final left = tester.getTopLeft(find.byType(RecordMessageCard)).dx;
      final cardLeft = tester
          .getTopLeft(find
              .descendant(
                  of: find.byType(RecordMessageCard),
                  matching: find.byType(DecoratedBox))
              .first)
          .dx;
      expect(cardLeft - left, 22);
    });

    testWidgets('ダークでも記録カードは surface の面', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
        ),
        brightness: Brightness.dark,
      );

      final card = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(RecordMessageCard),
              matching: find.byType(DecoratedBox))
          .first);
      expect((card.decoration as BoxDecoration).color,
          AppColorsExtension.dark.surface);
    });

    testWidgets('トレーナーのメッセージは吹き出し + 「{名前} · 19:05」', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'いいペースですね。',
          isUser: false,
          timestamp: '19:05',
          trainerName: '田中トレーナー',
        ),
      );

      expect(find.byType(CoachReplyBubble), findsOneWidget);
      expect(find.text('いいペースですね。'), findsOneWidget);
      expect(find.text('田中トレーナー · 19:05'), findsOneWidget);

      // 先頭はアバター（円）の面なので、吹き出しは最後の面
      final bubble = tester.widget<DecoratedBox>(find
          .descendant(
              of: find.byType(CoachReplyBubble),
              matching: find.byType(DecoratedBox))
          .last);
      final decoration = bubble.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surfaceSecondary);
      // 左上だけ角丸 0・ほかは 20
      expect(
        decoration.borderRadius,
        const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      );
    });

    testWidgets('返信先があると「{名前}への返信」を記録カードの上に出す', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: 'ありがとうございます。',
          isUser: true,
          timestamp: '9:24',
          replyToSenderName: '田中トレーナー',
          replyToContent: '朝食の記録、ありがとうございます。',
        ),
      );

      expect(find.textContaining('田中トレーナーへの返信'), findsOneWidget);
      final caption = tester.getTopLeft(find.textContaining('田中トレーナーへの返信'));
      final card = tester.getTopLeft(find.text('あなたのメッセージ · 9:24'));
      expect(caption.dy, lessThan(card.dy));
    });

    testWidgets('🔥 / 💬 の絵文字は文字ではなくアイコンで出す', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '今日の記録\n🔥 消費カロリー: 350kcal\n💬 脚トレを頑張りました',
          isUser: false,
          timestamp: '18:35',
        ),
      );

      expect(find.textContaining('🔥', findRichText: true), findsNothing);
      expect(find.textContaining('💬', findRichText: true), findsNothing);
      expect(find.byIcon(LucideIcons.flame), findsOneWidget);
      expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);
    });

    testWidgets('ワークアウト完了は「ワークアウト完了 · 上半身 · 18:40」と「消費 280 kcal」に整えて見せる',
        (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。',
          isUser: true,
          timestamp: '18:40',
          tags: ['#運動:完了'],
        ),
      );

      expect(find.text('ワークアウト完了 · 上半身 · 18:40'), findsOneWidget);
      expect(find.textContaining('消費 280 kcal'), findsOneWidget);
      expect(find.textContaining('肩の動きがよくなってきました。'), findsOneWidget);
      expect(find.text('プランの完了を報告しました'), findsOneWidget);
      // 絵文字つきの元の行は出さない
      expect(find.textContaining('消費カロリー'), findsNothing);
    });

    testWidgets('長押しで「返信 / 編集」のメニュー（自分のメッセージ）', (tester) async {
      var replied = 0;
      var edited = 0;
      await _pump(
        tester,
        MessageBubble(
          message: 'こんにちは',
          isUser: true,
          timestamp: '9:24',
          onReply: () => replied++,
          onEdit: () => edited++,
        ),
      );

      await tester.longPress(find.text('こんにちは'));
      await tester.pumpAndSettle();
      expect(find.text('返信'), findsOneWidget);
      expect(find.text('編集'), findsOneWidget);

      await tester.tap(find.text('返信'));
      await tester.pumpAndSettle();
      expect(replied, 1);
      expect(find.text('返信'), findsNothing);

      await tester.longPress(find.text('こんにちは'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      expect(edited, 1);
    });

    testWidgets('トレーナーのメッセージは長押しで「返信」だけ', (tester) async {
      await _pump(
        tester,
        MessageBubble(
          message: 'お疲れさまでした',
          isUser: false,
          timestamp: '19:12',
          onReply: () {},
        ),
      );

      await tester.longPress(find.text('お疲れさまでした'));
      await tester.pumpAndSettle();
      expect(find.text('返信'), findsOneWidget);
      expect(find.text('編集'), findsNothing);
    });

    testWidgets('システムメッセージは中央の控えめな面', (tester) async {
      await _pump(
        tester,
        const MessageBubble(
          message: '目標を達成しました',
          isUser: false,
          timestamp: '14:20',
          isSystem: true,
        ),
      );
      expect(find.text('目標を達成しました'), findsOneWidget);
      expect(find.byType(RecordMessageCard), findsNothing);
      expect(find.byType(CoachReplyBubble), findsNothing);
    });

    for (final isUser in [true, false]) {
      testWidgets('文字 1.35 で横にはみ出さない（${isUser ? '自分' : 'トレーナー'}）',
          (tester) async {
        await _pump(
          tester,
          MessageBubble(
            message: '#食事:昼食 鶏むね肉のグリル定食とサラダ、ごはん少なめ、味噌汁もつけました。とても長い本文でも折り返して縦に伸びます。',
            isUser: isUser,
            timestamp: '12:30',
            tags: isUser ? const ['#食事:昼食'] : null,
            trainerName: '田中トレーナー',
            isEdited: true,
            replyToSenderName: '田中トレーナー',
            replyToContent: '昼食は何を食べましたか。写真があれば送ってください。',
          ),
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('MessageDateDivider', () {
    testWidgets('13px・中央寄せの日付', (tester) async {
      await _pump(tester, const MessageDateDivider('9月13日（日）'));
      final text = tester.widget<Text>(find.text('9月13日（日）'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style?.fontSize, 13);
    });
  });
}
