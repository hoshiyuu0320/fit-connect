import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// 会話の中で「どのメッセージへの返信か」を示す 1 行（正本 `message-screens.js` の `ReplyTo`）。
///
/// reply アイコン（13）と「{名前}への返信」を caption（12・textSecondary）で出し、
/// 返信先の本文があれば「 · 本文の冒頭」を同じ行に続ける（長いと省略）。
/// 記録カードや返信の吹き出しの **上** に置く（下余白 6。上の間隔は並べる側が付ける）。
///
/// [senderName] は返信先を書いた人の呼び名（自分のメッセージなら「自分」、トレーナーなら名前）。
/// [isUserMessage] は **返信している側** が自分かどうか。
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.messageContent,
    required this.isUserMessage,
    this.leftInset = defaultLeftInset,
  });

  /// 記録カード（左 22 のインデント）に揃える
  static const double defaultLeftInset = 22;

  /// 返信先が自分のメッセージのときの呼び名（`MessageScreen` が渡す）
  static const String selfName = '自分';

  final String senderName;
  final String messageContent;
  final bool isUserMessage;

  /// 左のインデント。記録カードは 22、トレーナーの吹き出しは 38（アバター 29 + 間隔 9）
  final double leftInset;

  /// 「{名前}への返信」。返信している側と返信先で言い回しを変える。
  ///
  /// - 自分 → トレーナー: 「田中トレーナーへの返信」
  /// - 自分 → 自分: 「自分のメッセージへの返信」
  /// - トレーナー → 自分: 「あなたへの返信」
  /// - トレーナー → トレーナー: 「田中トレーナーのメッセージへの返信」
  static String captionFor({
    required String senderName,
    required bool isUserMessage,
  }) {
    final repliedIsSelf = senderName == selfName;
    if (isUserMessage) {
      return repliedIsSelf ? '自分のメッセージへの返信' : '$senderNameへの返信';
    }
    return repliedIsSelf ? 'あなたへの返信' : '$senderNameのメッセージへの返信';
  }

  /// 入力欄の上の返信バナーの見出し「{名前}に返信」
  static String previewTitleFor(String senderName) =>
      senderName == selfName ? '自分のメッセージに返信' : '$senderNameに返信';

  /// 本文の冒頭を 1 行にまとめる（改行・連続する空白を 1 つの空白に）
  static String oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final caption = AppTextStyles.caption(context);
    final quote = oneLine(messageContent);
    final label =
        captionFor(senderName: senderName, isUserMessage: isUserMessage);
    // 文字拡大では 2 行まで使う（縮めず、名前が切れないようにする）
    final largeText = MediaQuery.textScalerOf(context).scale(12) > 14;

    return Padding(
      padding: EdgeInsets.only(left: leftInset, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Icon(LucideIcons.reply,
                size: 13, color: caption.color), // textSecondary
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (quote.isNotEmpty) TextSpan(text: ' · $quote'),
                ],
              ),
              style: caption,
              maxLines: largeText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required Widget child,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
            vertical: AppSpacing.lg,
          ),
          child: child,
        ),
      ),
    ),
  );
}

@Preview(name: 'ReplyQuote - トレーナーへの返信')
Widget previewReplyQuoteTrainer() {
  return _previewApp(
    brightness: Brightness.light,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReplyQuote(
          senderName: '田中トレーナー',
          messageContent: '今日のトレーニングお疲れ様でした！',
          isUserMessage: true,
        ),
      ],
    ),
  );
}

@Preview(name: 'ReplyQuote - 自分のメッセージ・長い本文')
Widget previewReplyQuoteLong() {
  return _previewApp(
    brightness: Brightness.light,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReplyQuote(
          senderName: ReplyQuote.selfName,
          messageContent:
              'これは非常に長いメッセージです。複数行にわたって表示されるはずですが、1行に省略されます。テストメッセージテストメッセージ。',
          isUserMessage: true,
        ),
      ],
    ),
  );
}

@Preview(name: 'ReplyQuote - ダーク・文字1.35')
Widget previewReplyQuoteDarkLarge() {
  return _previewApp(
    brightness: Brightness.dark,
    textScale: 1.35,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReplyQuote(
          senderName: '田中トレーナー',
          messageContent: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
          isUserMessage: true,
        ),
        SizedBox(height: AppSpacing.lg),
        ReplyQuote(
          senderName: ReplyQuote.selfName,
          messageContent: 'ありがとうございます',
          isUserMessage: false,
          leftInset: 38,
        ),
      ],
    ),
  );
}
