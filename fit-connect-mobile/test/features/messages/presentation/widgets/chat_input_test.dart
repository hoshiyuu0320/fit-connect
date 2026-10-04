import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/quick_action_bar.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';

/// 入力エリア（正本 `Composer` / `InputRow` / `ComposerTags` / `mode="form"`）
Future<void> _pump(
  WidgetTester tester, {
  Future<void> Function(String, List<String>?, String?, Map<String, dynamic>?)?
      onSend,
  String? replyToContent,
  String? replyToSenderName,
  String? editingMessageId,
  String? editingMessageContent,
  double maxHeight = double.infinity,
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiFeaturesEnabledProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
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
          body: Column(
            children: [
              const Spacer(),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ChatInput(
                  onSend: onSend ?? (text, images, replyTo, metadata) async {},
                  userId: 'user-1',
                  replyToMessageId: replyToContent == null ? null : 'm1',
                  replyToContent: replyToContent,
                  replyToSenderName: replyToSenderName,
                  onCancelReply: () {},
                  editingMessageId: editingMessageId,
                  editingMessageContent: editingMessageContent,
                  onCancelEdit: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 送信ボタンの opacity（無効 = 0.4）
double _sendOpacity(WidgetTester tester, String label) => tester
    .widget<Opacity>(find
        .descendant(
            of: find.bySemanticsLabel(label), matching: find.byType(Opacity))
        .first)
    .opacity;

void main() {
  testWidgets('通常: クイック操作（体重・食事・運動）＋入力行（写真を添付・入力欄・送信）', (tester) async {
    await _pump(tester);

    expect(find.byType(QuickActionBar), findsOneWidget);
    expect(find.text('メッセージを入力'), findsOneWidget);
    expect(find.bySemanticsLabel('写真を添付'), findsOneWidget);
    expect(find.bySemanticsLabel('送信'), findsOneWidget);
    expect(find.byIcon(LucideIcons.arrowUp), findsOneWidget);
    // 丸 44
    expect(tester.getSize(find.bySemanticsLabel('写真を添付')), const Size(44, 44));
    expect(tester.getSize(find.bySemanticsLabel('送信')), const Size(44, 44));
  });

  testWidgets('入力欄は surface・角丸 22・最小高さ 44', (tester) async {
    await _pump(tester);
    final field = tester.widget<Container>(find
        .ancestor(of: find.byType(TextField), matching: find.byType(Container))
        .first);
    final decoration = field.decoration as BoxDecoration;
    expect(decoration.color, AppColorsExtension.light.surface);
    expect(decoration.borderRadius, BorderRadius.circular(22));
    expect(
      tester
          .getSize(find
              .ancestor(
                  of: find.byType(TextField), matching: find.byType(Container))
              .first)
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('空のあいだ送信は opacity 0.4・入力すると押せて、送ると入力欄が空になる', (tester) async {
    final sent = <String>[];
    await _pump(tester, onSend: (text, images, replyTo, metadata) async {
      sent.add(text);
    });

    expect(_sendOpacity(tester, '送信'), 0.4);
    await tester.tap(find.bySemanticsLabel('送信'));
    expect(sent, isEmpty);

    await tester.enterText(find.byType(TextField), 'こんにちは');
    await tester.pump();
    expect(_sendOpacity(tester, '送信'), 1);

    await tester.tap(find.bySemanticsLabel('送信'));
    await tester.pumpAndSettle();
    expect(sent, ['こんにちは']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('# を入力すると「タグの候補」が出て、クイック操作は隠れる。選ぶと入力欄に入る', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), '#食');
    await tester.pumpAndSettle();
    expect(find.text('タグの候補'), findsOneWidget);
    expect(find.byType(QuickActionBar), findsNothing);

    await tester.tap(find.text('#食事:昼食'));
    await tester.pumpAndSettle();
    expect(find.text('タグの候補'), findsNothing);
    expect(find.byType(QuickActionBar), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '#食事:昼食 ');
    // タグ選択後は入力例のヒント
    expect(find.textContaining('例: '), findsOneWidget);
  });

  testWidgets('返信: 「{名前}に返信」のバナー。閉じると onCancelReply', (tester) async {
    await _pump(
      tester,
      replyToContent: 'お疲れさまでした。最後のセットが重いときは…',
      replyToSenderName: '田中トレーナー',
    );
    expect(find.text('田中トレーナーに返信'), findsOneWidget);
    expect(find.bySemanticsLabel('返信をやめる'), findsOneWidget);
  });

  testWidgets('編集: 「メッセージを編集中」のバナー・送信は「編集を保存」（check）', (tester) async {
    await _pump(
      tester,
      editingMessageId: 'm9',
      editingMessageContent: '訂正前の本文',
    );
    expect(find.text('メッセージを編集中'), findsOneWidget);
    expect(find.bySemanticsLabel('編集をやめる'), findsOneWidget);
    expect(find.bySemanticsLabel('編集を保存'), findsOneWidget);
    expect(find.byIcon(LucideIcons.check), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '訂正前の本文');
  });

  testWidgets('記録フォーム: 食事を開いても入力行は残り、「入力欄に入れる」で入力欄へ入る', (tester) async {
    await _pump(tester);

    await tester.tap(find.descendant(
        of: find.byType(QuickActionBar), matching: find.text('体重')));
    await tester.pumpAndSettle();
    expect(find.text('体重を記録'), findsOneWidget);
    expect(find.byType(QuickActionBar), findsNothing);
    expect(find.text('メッセージを入力'), findsOneWidget); // 入力行は残る

    await tester.enterText(find.widgetWithText(TextField, '65.5'), '62.4');
    await tester.pump();
    await tester.tap(find.text('入力欄に入れる'));
    await tester.pumpAndSettle();

    // フォームは閉じて、入力欄に `#体重 62.4kg` が入る
    expect(find.text('体重を記録'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '#体重 62.4kg');
  });

  testWidgets('記録フォームを閉じると会話の入力に戻る', (tester) async {
    await _pump(tester);
    await tester.tap(find.descendant(
        of: find.byType(QuickActionBar), matching: find.text('運動')));
    await tester.pumpAndSettle();
    expect(find.text('運動を記録'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('閉じる'));
    await tester.pumpAndSettle();
    expect(find.text('運動を記録'), findsNothing);
    expect(find.byType(QuickActionBar), findsOneWidget);
  });

  testWidgets('親が高さを制限しても、記録フォームを開いてはみ出さない（フォームの側がスクロール）', (tester) async {
    await _pump(tester, maxHeight: 300);
    await tester.tap(find.descendant(
        of: find.byType(QuickActionBar), matching: find.text('食事')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 入力行は下に見えている
    final inputBottom = tester.getBottomLeft(find.bySemanticsLabel('送信')).dy;
    expect(inputBottom, lessThanOrEqualTo(844));
    expect(find.text('メッセージを入力'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('文字 1.35（${brightness.name}）でも横にはみ出さない', (tester) async {
      await _pump(
        tester,
        textScale: 1.35,
        brightness: brightness,
        replyToContent: 'お疲れさまでした。最後のセットが重いときは…',
        replyToSenderName: '田中トレーナー',
      );
      await tester.enterText(find.byType(TextField), '#食');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
