import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

class ReplyQuote extends StatelessWidget {
  final String senderName;
  final String messageContent;
  final bool isUserMessage; // 親メッセージがユーザーのものか

  const ReplyQuote({
    super.key,
    required this.senderName,
    required this.messageContent,
    required this.isUserMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isUserMessage
                ? Colors.white.withOpacity(0.5)
                : AppColors.primary600,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderName,
            style: TextStyle(
              color: isUserMessage
                  ? Colors.white.withOpacity(0.8)
                  : AppColors.primary600,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            messageContent,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isUserMessage
                  ? Colors.white.withOpacity(0.7)
                  : colors.textSecondary,
              fontSize: 12,
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

@Preview(name: 'ReplyQuote - Trainer Message')
Widget previewReplyQuoteTrainer() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Builder(
            builder: (context) {
              final colors = AppColors.of(context);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const ReplyQuote(
                  senderName: 'トレーナー',
                  messageContent: '今日のトレーニングお疲れ様でした！',
                  isUserMessage: false,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'ReplyQuote - User Message')
Widget previewReplyQuoteUser() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const ReplyQuote(
              senderName: '自分',
              messageContent: 'ありがとうございます！明日も頑張ります！',
              isUserMessage: true,
            ),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'ReplyQuote - Long Message')
Widget previewReplyQuoteLong() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Builder(
            builder: (context) {
              final colors = AppColors.of(context);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const ReplyQuote(
                  senderName: 'トレーナー',
                  messageContent:
                      'これは非常に長いメッセージです。複数行にわたって表示されるはずですが、2行で省略されます。テストメッセージテストメッセージテストメッセージ。',
                  isUserMessage: false,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
