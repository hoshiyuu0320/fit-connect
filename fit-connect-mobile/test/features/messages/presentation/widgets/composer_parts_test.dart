import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/quick_action_bar.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_preview.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_quote.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/tag_suggestion_list.dart';

/// 入力エリアの部品（クイック操作・タグの候補・返信バナー・返信先の行）
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
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QuickActionBar', () {
    testWidgets('体重・食事・運動のチップと「# で手入力」を出す', (tester) async {
      await _pump(tester, QuickActionBar(onTap: (_) {}));

      expect(find.text('体重'), findsOneWidget);
      expect(find.text('食事'), findsOneWidget);
      expect(find.text('運動'), findsOneWidget);
      expect(find.text('で手入力'), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsOneWidget);
      expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
      expect(find.byIcon(LucideIcons.dumbbell), findsOneWidget);
      expect(find.byIcon(LucideIcons.hash), findsOneWidget);
    });

    testWidgets('押すと対応するフォームの種類を返す', (tester) async {
      final tapped = <String>[];
      await _pump(tester, QuickActionBar(onTap: tapped.add));

      await tester.tap(find.text('体重'));
      await tester.tap(find.text('食事'));
      await tester.tap(find.text('運動'));
      expect(tapped, ['weight', 'meal', 'exercise']);
    });

    testWidgets('チップは surface・角丸 20・高さ 40 で、タッチ領域は 44 以上', (tester) async {
      await _pump(tester, QuickActionBar(onTap: (_) {}));

      final chip = tester.widget<DecoratedBox>(find
          .ancestor(
              of: find.text('体重'), matching: find.byType(DecoratedBox))
          .first);
      final decoration = chip.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));
      expect(
        tester.getSize(find.ancestor(
            of: find.text('体重'), matching: find.byType(DecoratedBox)).first).height,
        40,
      );

      final target = tester.getSize(find.bySemanticsLabel('体重を記録'));
      expect(target.height, greaterThanOrEqualTo(44));
      expect(target.width, greaterThanOrEqualTo(44));
    });

    testWidgets('文字 1.35 でも横にはみ出さない（チップは折り返す）', (tester) async {
      await _pump(tester, QuickActionBar(onTap: (_) {}), textScale: 1.35);
      expect(tester.takeException(), isNull);
      expect(find.text('運動'), findsOneWidget);
    });
  });

  group('TagSuggestionList', () {
    testWidgets('「#食」で食事の 4 候補を見出し付きで出す', (tester) async {
      await _pump(tester, TagSuggestionList(query: '#食', onSelect: (_, __, ___) {}));

      expect(find.text('タグの候補'), findsOneWidget);
      for (final tag in ['#食事:朝食', '#食事:昼食', '#食事:夕食', '#食事:間食']) {
        expect(find.text(tag), findsOneWidget);
      }
      expect(find.byIcon(LucideIcons.utensils), findsNWidgets(4));
    });

    testWidgets('行は高さ 44 以上で、押すと onSelect（タグ・空白を足すか・入力例）', (tester) async {
      String? tag;
      bool? addSpace;
      String? example;
      await _pump(
        tester,
        TagSuggestionList(
          query: '#食事:昼',
          onSelect: (t, s, e) {
            tag = t;
            addSpace = s;
            example = e;
          },
        ),
      );

      final row = find.ancestor(
          of: find.text('#食事:昼食'), matching: find.byType(ConstrainedBox));
      expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('#食事:昼食'));
      expect(tag, '#食事:昼食');
      expect(addSpace, isTrue);
      expect(example, contains('#食事:昼食'));
    });

    testWidgets('「#」だけならカテゴリ（食事・運動・体重）を出す', (tester) async {
      await _pump(tester, TagSuggestionList(query: '#', onSelect: (_, __, ___) {}));
      expect(find.text('#食事'), findsOneWidget);
      expect(find.text('#運動'), findsOneWidget);
      expect(find.text('#体重'), findsOneWidget);
    });

    testWidgets('候補が無いときは何も出さない', (tester) async {
      await _pump(
          tester, TagSuggestionList(query: '#ZZZ', onSelect: (_, __, ___) {}));
      expect(find.text('タグの候補'), findsNothing);
    });

    testWidgets('カードは surface・角丸 20', (tester) async {
      await _pump(tester, TagSuggestionList(query: '#食', onSelect: (_, __, ___) {}));
      final card = tester.widget<DecoratedBox>(find
          .ancestor(
              of: find.text('タグの候補'), matching: find.byType(DecoratedBox))
          .first);
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surface);
      expect(decoration.borderRadius, BorderRadius.circular(20));
    });

    testWidgets('文字 1.35 でも横にはみ出さない', (tester) async {
      await _pump(
          tester, TagSuggestionList(query: '#食', onSelect: (_, __, ___) {}),
          textScale: 1.35);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReplyPreview / ReplyQuote', () {
    testWidgets('「{名前}に返信」＋引用 1 行＋閉じる', (tester) async {
      var closed = 0;
      await _pump(
        tester,
        ReplyPreview(
          senderName: '田中トレーナー',
          messageContent: 'お疲れさまでした。\n最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
          onCancel: () => closed++,
        ),
      );

      expect(find.text('田中トレーナーに返信'), findsOneWidget);
      final quote = tester.widget<Text>(find.textContaining('お疲れさまでした。 最後の'));
      expect(quote.maxLines, 1);
      expect(quote.overflow, TextOverflow.ellipsis);

      final close = find.bySemanticsLabel('返信をやめる');
      expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
      await tester.tap(close);
      expect(closed, 1);
    });

    testWidgets('自分のメッセージへの返信は「自分のメッセージに返信」', (tester) async {
      await _pump(
        tester,
        ReplyPreview(
          senderName: ReplyQuote.selfName,
          messageContent: 'こんにちは',
          onCancel: () {},
        ),
      );
      expect(find.text('自分のメッセージに返信'), findsOneWidget);
    });

    testWidgets('バナーは surface・角丸 16・reply アイコン 16', (tester) async {
      await _pump(
        tester,
        ReplyPreview(
          senderName: '田中トレーナー',
          messageContent: 'こんにちは',
          onCancel: () {},
        ),
      );
      final banner = tester.widget<DecoratedBox>(find
          .ancestor(
              of: find.text('田中トレーナーに返信'),
              matching: find.byType(DecoratedBox))
          .first);
      final decoration = banner.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surface);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.reply)).size, 16);
    });

    testWidgets('ReplyQuote の言い回し（返す側と返信先で変わる）', (tester) async {
      expect(
        ReplyQuote.captionFor(senderName: '田中トレーナー', isUserMessage: true),
        '田中トレーナーへの返信',
      );
      expect(
        ReplyQuote.captionFor(
            senderName: ReplyQuote.selfName, isUserMessage: true),
        '自分のメッセージへの返信',
      );
      expect(
        ReplyQuote.captionFor(
            senderName: ReplyQuote.selfName, isUserMessage: false),
        'あなたへの返信',
      );
    });

    testWidgets('返信先の行は reply アイコン 13 と caption（本文は 1 行に省略）', (tester) async {
      await _pump(
        tester,
        const ReplyQuote(
          senderName: '田中トレーナー',
          messageContent: '朝食の記録、ありがとうございます。',
          isUserMessage: true,
        ),
      );
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.reply)).size, 13);
      expect(
        find.textContaining('田中トレーナーへの返信 · 朝食の記録、ありがとうございます。'),
        findsOneWidget,
      );
    });

    testWidgets('文字 1.35 でも横にはみ出さない', (tester) async {
      await _pump(
        tester,
        ReplyPreview(
          senderName: '田中トレーナー',
          messageContent: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
          onCancel: () {},
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
