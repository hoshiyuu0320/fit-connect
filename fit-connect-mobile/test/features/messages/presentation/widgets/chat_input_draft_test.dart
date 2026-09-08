import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';

/// セッションの「変更を相談」からメッセージ入力欄へ定型文を流し込む導線のテスト。
/// 「一度だけ注入される」ことと「編集モードを壊さない」ことを担保する
void main() {
  Widget buildInput({
    String? initialDraft,
    VoidCallback? onDraftConsumed,
    String? editingMessageId,
    String? editingMessageContent,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            ChatInput(
              onSend: (text, imageUrls, replyToMessageId, metadata) async {},
              userId: 'user-1',
              editingMessageId: editingMessageId,
              editingMessageContent: editingMessageContent,
              onCancelEdit: () {},
              initialDraft: initialDraft,
              onDraftConsumed: onDraftConsumed,
            ),
          ],
        ),
      ),
    );
  }

  /// 入力欄の現在値
  String inputText(WidgetTester tester) {
    return tester.widget<TextField>(find.byType(TextField)).controller!.text;
  }

  group('ChatInput 定型文の注入', () {
    testWidgets('初期表示時に initialDraft がセットされ onDraftConsumed が呼ばれる',
        (tester) async {
      var consumedCount = 0;

      await tester.pumpWidget(buildInput(
        initialDraft: '9月10日(水) 18:00 のセッションについて相談です。',
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();

      expect(inputText(tester), '9月10日(水) 18:00 のセッションについて相談です。');
      expect(consumedCount, 1);
    });

    testWidgets('消費後に initialDraft が null に戻っても入力欄はクリアされない', (tester) async {
      var consumedCount = 0;

      await tester.pumpWidget(buildInput(
        initialDraft: '9月10日(水) 18:00 のセッションについて相談です。',
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();

      // 呼び出し側（MainScreen）が draft を破棄した状態を再現
      await tester.pumpWidget(buildInput(
        initialDraft: null,
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();

      expect(inputText(tester), '9月10日(水) 18:00 のセッションについて相談です。');
      // 再ビルドで再注入されない
      expect(consumedCount, 1);
    });

    testWidgets('後から渡された定型文も入力欄に反映される', (tester) async {
      var consumedCount = 0;

      await tester.pumpWidget(buildInput(
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();
      expect(inputText(tester), '');

      await tester.pumpWidget(buildInput(
        initialDraft: '9月12日(金) 10:00 のセッションについて相談です。',
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();

      expect(inputText(tester), '9月12日(金) 10:00 のセッションについて相談です。');
      expect(consumedCount, 1);
    });

    testWidgets('編集モード中は編集内容が優先され定型文で上書きされない', (tester) async {
      var consumedCount = 0;

      await tester.pumpWidget(buildInput(
        editingMessageId: 'message-1',
        editingMessageContent: '編集中のメッセージ',
        initialDraft: '9月10日(水) 18:00 のセッションについて相談です。',
        onDraftConsumed: () => consumedCount++,
      ));
      await tester.pumpAndSettle();

      expect(inputText(tester), '編集中のメッセージ');
      expect(consumedCount, 0);
    });
  });
}
