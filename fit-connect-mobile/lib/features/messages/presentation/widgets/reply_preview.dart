import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ReplyPreview extends StatelessWidget {
  final String messageContent;
  final VoidCallback onCancel;

  const ReplyPreview({
    super.key,
    required this.messageContent,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(
          top: BorderSide(color: colors.border),
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.reply, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '返信先',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  messageContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 16, color: colors.textHint),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ReplyPreview - Short Message')
Widget previewReplyPreviewShort() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ReplyPreview(
              messageContent: 'こんにちは！',
              onCancel: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'ReplyPreview - Long Message')
Widget previewReplyPreviewLong() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ReplyPreview(
              messageContent:
                  'これは非常に長いメッセージで、1行に収まりきらないため省略されるはずです。テストメッセージです。',
              onCancel: () {},
            ),
          ],
        ),
      ),
    ),
  );
}
