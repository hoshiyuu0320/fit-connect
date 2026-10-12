import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/message_bubble.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/quick_action_bar.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../../messages_test_support.dart';

const _phone = EdgeInsets.only(top: 47, bottom: 34);

/// 絞り込みのタブ（下部ナビにも「記録」があるので、タブの中から探す）
Finder _filterTab(String label) => find.descendant(
      of: find.byType(FcSubTabs<MessageFilter>),
      matching: find.text(label),
    );

void main() {
  setUp(FakeMessages.sent.clear);

  group('ヘッダー', () {
    testWidgets('コーチのヘッダー（名前・「あなたの担当トレーナー」）。オンライン表示・最終ログインは出さない',
        (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );

      expect(find.text('田中トレーナー'), findsWidgets);
      expect(find.text('あなたの担当トレーナー'), findsOneWidget);
      expect(find.textContaining('オンライン'), findsNothing);
      expect(find.textContaining('オフライン'), findsNothing);
      expect(find.textContaining('最終'), findsNothing);
      // アバターは 46
      expect(tester.getSize(find.byType(FcAvatar).first), const Size(46, 46));
    });

    testWidgets('名前が「田中」でも「田中トレーナー」でも、見出しは「田中トレーナー」（二重にならない）',
        (tester) async {
      for (final raw in ['田中', '田中トレーナー']) {
        await pumpMessageScreen(
          tester,
          overrides: messageScreenOverrides(
            messages: sampleThread(),
            trainerName: raw,
          ),
          viewPadding: _phone,
        );

        expect(find.text('田中トレーナー'), findsWidgets, reason: raw);
        expect(find.textContaining('トレーナートレーナー'), findsNothing, reason: raw);
        // 吹き出しの宛名・返信の引用も同じ表記
        expect(find.text('田中トレーナー · 19:12'), findsOneWidget, reason: raw);
        expect(find.textContaining('田中トレーナーへの返信'), findsOneWidget, reason: raw);
      }
    });

    testWidgets('名前は 25px・字間 -1（コーチ名）', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      final name = tester.widget<Text>(find.descendant(
        of: find.byWidgetPredicate((w) => w is Semantics && w.properties.header == true),
        matching: find.text('田中トレーナー'),
      ).first);
      expect(name.style?.fontSize, 25);
      expect(name.style?.letterSpacing, -1);
    });
  });

  group('会話', () {
    testWidgets('日付の区切り・記録カード・トレーナーの吹き出しが並び、既読は出さない', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        size: const Size(390, 1800),
      );

      expect(find.text('今日'), findsOneWidget);
      expect(find.text('昨日'), findsOneWidget);
      expect(find.text('あなたの運動記録 · 有酸素 · 18:20'), findsOneWidget);
      expect(find.text('あなたの体重記録 · 7:30'), findsOneWidget);
      expect(find.text('あなたの朝食記録 · 8:10'), findsOneWidget);
      // タグの無い自分のメッセージは見出しを出さず、時刻を状態行に出す
      expect(find.textContaining('あなたのメッセージ'), findsNothing);
      expect(find.text('ワークアウト完了 · 上半身 · 18:40'), findsOneWidget);
      expect(find.text('運動の記録に追加しました'), findsOneWidget);
      expect(find.text('体重の記録に追加しました'), findsOneWidget);
      expect(find.text('食事の記録に追加しました'), findsOneWidget);
      expect(find.text('プランの完了を報告しました'), findsOneWidget);
      expect(find.text('9:24 · 編集済み'), findsOneWidget);
      expect(find.text('田中トレーナー · 19:12'), findsOneWidget);
      expect(find.textContaining('既読'), findsNothing);
      // 返信先がある記録カードの上に「{名前}への返信」
      expect(find.textContaining('田中トレーナーへの返信'), findsOneWidget);
    });

    testWidgets('自分の通常のメッセージ: 見出し行なし・本文の下に送信時刻（見出しのある記録カードは残る）',
        (tester) async {
      final today = DateTime.now();
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: [
          testMessage(
            id: 'p',
            mine: true,
            content: 'あいうえお',
            at: DateTime(today.year, today.month, today.day, 17, 4),
          ),
          testMessage(
            id: 'w',
            mine: true,
            content: '#体重 62.4 kg',
            tags: const ['#体重'],
            at: DateTime(today.year, today.month, today.day, 17, 5),
          ),
        ]),
        viewPadding: _phone,
      );
      expect(find.text('あいうえお'), findsOneWidget);
      expect(find.text('17:04'), findsOneWidget);
      expect(find.textContaining('あなたのメッセージ'), findsNothing);
      expect(find.text('あなたの体重記録 · 17:05'), findsOneWidget);
      expect(tester.getTopLeft(find.text('17:04')).dy,
          greaterThan(tester.getBottomLeft(find.text('あいうえお')).dy));
    });

    testWidgets('日付の区切りは 13px・textSecondary・中央', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        size: const Size(390, 1800),
      );
      final today = tester.widget<Text>(find.text('今日'));
      expect(today.style?.fontSize, 13);
      expect(today.textAlign, TextAlign.center);
    });

    testWidgets('絞り込み「記録」でタグのあるメッセージだけに絞る（現行の機能を残す）', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        size: const Size(390, 1800),
      );
      expect(find.textContaining('お疲れさまでした。最後のセット'), findsOneWidget);

      await tester.tap(_filterTab('記録'));
      await tester.pumpAndSettle();
      expect(find.textContaining('お疲れさまでした。最後のセット'), findsNothing);
      expect(find.text('あなたの体重記録 · 7:30'), findsOneWidget);

      await tester.tap(_filterTab('すべて'));
      await tester.pumpAndSettle();
      expect(find.textContaining('お疲れさまでした。最後のセット'), findsOneWidget);
    });

    testWidgets('これ以上メッセージが無いときの caption', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        size: const Size(390, 1800),
      );
      expect(find.text('これ以上メッセージはありません'), findsOneWidget);
    });
  });

  group('絞り込みのタブ（すべて / 記録）', () {
    testWidgets('2 項目のタブが幅いっぱい（画面の左右余白の内側）に等分して広がり、ボタン（チップ）ではない',
        (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      expect(find.byType(FcChips<MessageFilter>), findsNothing);
      final tabs = find.byType(FcSubTabs<MessageFilter>);
      expect(tabs, findsOneWidget);
      // 390 - 左右 20
      expect(tester.getSize(tabs).width, 350);
      expect(tester.getTopLeft(tabs).dx, 20);
      // 文言は「すべて」「記録」のまま
      expect(_filterTab('すべて'), findsOneWidget);
      expect(_filterTab('記録'), findsOneWidget);
      // 2 つのタブは、外枠の中でほぼ半分ずつ（文字数の違いの分だけが差）
      Rect faceOf(String label) => tester.getRect(find
          .ancestor(
            of: _filterTab(label),
            matching: find.byType(AnimatedContainer),
          )
          .first);
      final all = faceOf('すべて');
      final records = faceOf('記録');
      expect((all.width - records.width).abs(), lessThan(24));
      expect(all.left, lessThan(records.left));
      // 外枠の内側余白 4 と、タブの間隔 2 を除いて、ほぼ全幅を 2 つで使う
      expect(all.width + records.width, closeTo(350 - 4 * 2 - 2, 1));
    });

    testWidgets('タップ領域は高さ 44 以上', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      for (final label in ['すべて', '記録']) {
        final size = tester.getSize(find
            .ancestor(
              of: _filterTab(label),
              matching: find.byType(FcPressable),
            )
            .first);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });

    for (final (name, brightness, colors) in [
      ('ライト', Brightness.light, AppColorsExtension.light),
      ('ダーク', Brightness.dark, AppColorsExtension.dark),
    ]) {
      testWidgets(
          '$name: 選択中は面（surfaceSecondary）+ accent の文字 + 太字、未選択は面なし + textSecondary',
          (tester) async {
        await pumpMessageScreen(
          tester,
          overrides: messageScreenOverrides(messages: sampleThread()),
          viewPadding: _phone,
          brightness: brightness,
        );

        TextStyle styleOf(String label) =>
            tester.widget<Text>(_filterTab(label)).style!;
        Color? faceOf(String label) {
          final box = tester.widget<AnimatedContainer>(find
              .ancestor(
                of: _filterTab(label),
                matching: find.byType(AnimatedContainer),
              )
              .first);
          return (box.decoration as BoxDecoration).color;
        }

        // 初めは「すべて」が選択中
        expect(styleOf('すべて').color, colors.accent);
        expect(styleOf('すべて').fontWeight, FontWeight.w500);
        expect(faceOf('すべて'), colors.surfaceSecondary);
        expect(styleOf('記録').color, colors.textSecondary);
        expect(styleOf('記録').fontWeight, FontWeight.w400);
        expect(faceOf('記録'), Colors.transparent);

        // 「記録」に切り替えると入れ替わる
        await tester.tap(_filterTab('記録'));
        await tester.pumpAndSettle();
        expect(styleOf('記録').color, colors.accent);
        expect(styleOf('記録').fontWeight, FontWeight.w500);
        expect(faceOf('記録'), colors.surfaceSecondary);
        expect(styleOf('すべて').color, colors.textSecondary);
        expect(faceOf('すべて'), Colors.transparent);
      });
    }

    testWidgets('選択状態は読み上げにも伝わる（selected）', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('すべて').first),
        matchesSemantics(
          label: 'すべて',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('文字 1.35 でも折り返さず、横にはみ出さない', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FcSubTabs<MessageFilter>)).width, 350);
    });

    testWidgets('高さが足りないとき（キーボード + 記録フォーム）は、タブの行ごと畳んで会話に譲る', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides:
            messageScreenOverrides(messages: sampleThread(), aiEnabled: true),
        viewPadding: _phone,
        keyboardHeight: 336,
      );
      // 入力だけのときは、キーボードを出していても会話の領域が足りるのでタブは出る
      expect(find.byType(FcSubTabs<MessageFilter>), findsOneWidget);

      await tester.tap(find.descendant(
          of: find.byType(QuickActionBar), matching: find.text('食事')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(FcSubTabs<MessageFilter>), findsNothing);
    });
  });

  group('状態', () {
    testWidgets('空: 「まだメッセージはありません。」＋入力への案内', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(),
        viewPadding: _phone,
      );
      expect(find.text('まだメッセージはありません。'), findsOneWidget);
      expect(find.textContaining('入力欄'), findsOneWidget);
      // 入力は使える
      expect(find.byType(ChatInput), findsOneWidget);
    });

    testWidgets('空（記録のみ）: 「まだ記録がありません。」', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(
          messages: [
            testMessage(
                id: 'a', mine: false, content: 'こんにちは', at: DateTime.now()),
          ],
        ),
        viewPadding: _phone,
      );
      await tester.tap(_filterTab('記録'));
      await tester.pumpAndSettle();
      expect(find.text('まだ記録がありません。'), findsOneWidget);
    });

    testWidgets('読込中: スケルトン（配置を保つ）・「読み込み中」を読み上げる', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(thread: FakeThread.loading),
        viewPadding: _phone,
        settle: false,
      );
      expect(
        find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == '読み込み中'),
        findsOneWidget,
      );
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(RecordMessageCard), findsNothing);
      // 未取得を 0 や空の文言で見せない
      expect(find.text('まだメッセージはありません。'), findsNothing);
    });

    testWidgets('読み込みに失敗: 理由と「再試行」', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(thread: FakeThread.error),
        viewPadding: _phone,
      );
      expect(find.text('メッセージを読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('操作', () {
    testWidgets('入力して送ると送信される', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      await tester.enterText(find.byType(TextField), 'ありがとうございます');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('送信'));
      await tester.pumpAndSettle();
      expect(FakeMessages.sent, ['ありがとうございます']);
    });

    testWidgets('トレーナーのメッセージを長押し→返信で、入力欄の上に「{名前}に返信」', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      await tester.longPress(find.textContaining('最後のセットが重い').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('返信'));
      await tester.pumpAndSettle();
      expect(find.text('田中トレーナーに返信'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('返信をやめる'));
      await tester.pumpAndSettle();
      expect(find.text('田中トレーナーに返信'), findsNothing);
    });

    testWidgets('自分のメッセージを長押し→編集で、入力欄に本文が入る', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      await tester.longPress(find.textContaining('昼もたんぱく質を意識').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      expect(find.text('メッセージを編集中'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'ありがとうございます。昼もたんぱく質を意識してみます。');
    });

    testWidgets('定型文（initialDraft）は入力欄へ流し込まれる', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        initialDraft: '9月10日(水) 18:00 のセッションについて相談です。',
      );
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '9月10日(水) 18:00 のセッションについて相談です。');
    });
  });

  group('レイアウト', () {
    testWidgets('入力欄は画面の下に固定され、下部ナビの上に収まる（間 = 入力欄の下余白 12 + ナビの上余白 14）',
        (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
      );
      final send = tester.getBottomLeft(find.bySemanticsLabel('送信')).dy;
      // ナビ（高さ 93: 上余白 14 + カプセル 64 + 下 15）の上端 = 844 - 93
      const navTop = 844 - 93;
      expect(send, lessThanOrEqualTo(navTop - 12 + 0.5));
      expect(send, greaterThan(navTop - 12 - 14));
    });

    testWidgets('キーボード表示中は入力欄がキーボードの真上に付く（ナビは隠れる）', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides: messageScreenOverrides(messages: sampleThread()),
        viewPadding: _phone,
        keyboardHeight: 336,
      );
      final send = tester.getBottomLeft(find.bySemanticsLabel('送信')).dy;
      expect(send, lessThanOrEqualTo(844 - 336));
      expect(send, greaterThan(844 - 336 - 16));
    });

    testWidgets('キーボード表示中に記録フォームを開いても、はみ出さない', (tester) async {
      await pumpMessageScreen(
        tester,
        overrides:
            messageScreenOverrides(messages: sampleThread(), aiEnabled: true),
        viewPadding: _phone,
        keyboardHeight: 336,
      );
      await tester.tap(find.descendant(
          of: find.byType(QuickActionBar), matching: find.text('食事')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('メッセージを入力'), findsOneWidget);
    });

    for (final (name, brightness, scale) in [
      ('ダーク', Brightness.dark, 1.0),
      ('文字 1.35', Brightness.light, 1.35),
    ]) {
      testWidgets('$name でも横にはみ出さない', (tester) async {
        await pumpMessageScreen(
          tester,
          overrides: messageScreenOverrides(messages: sampleThread()),
          viewPadding: _phone,
          brightness: brightness,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(
            of: find.byType(QuickActionBar), matching: find.text('食事')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
