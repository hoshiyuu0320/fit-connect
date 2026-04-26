import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_quote.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final String timestamp;
  final List<String>? tags;
  final List<String>? images;
  final bool isSystem;
  final String? messageId;
  final String? replyToContent;
  final String? replyToSenderName;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final bool isEdited;
  final bool isRead;
  final String? trainerProfileImageUrl;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.timestamp,
    this.tags,
    this.images,
    this.isSystem = false,
    this.messageId,
    this.replyToContent,
    this.replyToSenderName,
    this.onReply,
    this.onEdit,
    this.isEdited = false,
    this.isRead = false,
    this.trainerProfileImageUrl,
  });

  /// メッセージからタグ部分を除去した本文を取得
  String get _messageWithoutTags {
    // タグパターン: #食事:朝食, #運動:筋トレ, #体重 など
    final tagPattern = RegExp(r'#(食事|運動|体重)(?::[^\s]+)?');
    return message.replaceAll(tagPattern, '').trim();
  }

  /// 長押しメニューを表示
  void _showContextMenu(BuildContext context) {
    if (onReply == null && onEdit == null) return;

    final colors = AppColors.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onReply != null)
                ListTile(
                  leading: Icon(LucideIcons.reply, color: AppColors.primary600),
                  title: const Text('返信'),
                  onTap: () {
                    Navigator.pop(context);
                    onReply!();
                  },
                ),
              if (isUser && onEdit != null)
                ListTile(
                  leading:
                      Icon(LucideIcons.pencil, color: AppColors.primary600),
                  title: const Text('編集'),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.amber100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.amber700.withOpacity(0.2)),
          ),
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.amber800,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final displayMessage = _messageWithoutTags;

    return GestureDetector(
      onLongPress: (onReply != null || onEdit != null)
          ? () => _showContextMenu(context)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 8, top: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceDim,
                  shape: BoxShape.circle,
                ),
                child: trainerProfileImageUrl != null
                    ? ClipOval(
                        child: Image.network(
                          trainerProfileImageUrl!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                              LucideIcons.user,
                              size: 18,
                              color: colors.textHint),
                        ),
                      )
                    : Icon(LucideIcons.user, size: 18, color: colors.textHint),
              ),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.primary600 : colors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: isUser ? null : Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ReplyQuote（返信がある場合に最初に表示）
                        if (replyToContent != null &&
                            replyToSenderName != null) ...[
                          ReplyQuote(
                            senderName: replyToSenderName!,
                            messageContent: replyToContent!,
                            isUserMessage: isUser,
                          ),
                        ],

                        // Tags（先に表示）
                        if (tags != null && tags!.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: tags!
                                .map((tag) => _buildTag(tag, isUser))
                                .toList(),
                          ),
                          if (displayMessage.isNotEmpty)
                            const SizedBox(height: 8),
                        ],

                        // メッセージ本文（タグを除去して表示）
                        if (displayMessage.isNotEmpty)
                          _buildRichText(displayMessage, isUser, colors),

                        // Images
                        if (images != null && images!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 100,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              shrinkWrap: true,
                              itemCount: images!.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                return GestureDetector(
                                  onTap: () {
                                    FullScreenImageViewer.show(
                                      context: context,
                                      imageUrls: images!,
                                      initialIndex: index,
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      images![index],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUser && isRead) ...[
                        Text(
                          '既読',
                          style: TextStyle(
                            color: colors.textHint,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          ' ・ ',
                          style: TextStyle(
                            color: colors.textHint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (isEdited) ...[
                        Text(
                          '編集済み',
                          style: TextStyle(
                            color: colors.textHint,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          ' ・ ',
                          style: TextStyle(
                            color: colors.textHint,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      Text(
                        timestamp,
                        style: TextStyle(
                          color: colors.textHint,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥/💬絵文字をLucideIconsのWidgetSpanに変換してリッチテキストを返す
  Widget _buildRichText(String text, bool isUser, AppColorsExtension colors) {
    final emojiPattern = RegExp(r'(🔥|💬)');
    final matches = emojiPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          color: isUser ? Colors.white : colors.textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
      );
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    final textColor = isUser ? Colors.white : colors.textPrimary;
    final textStyle = TextStyle(color: textColor, fontSize: 14, height: 1.4);

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: textStyle,
        ));
      }

      final emoji = match.group(0);
      final IconData icon;
      if (emoji == '🔥') {
        icon = LucideIcons.flame;
      } else {
        icon = LucideIcons.messageCircle;
      }

      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(icon, size: 16, color: textColor),
        ),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: textStyle));
    }

    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildTag(String tag, bool isUser) {
    final icon = _getTagIcon(tag);

    // タグの表示テキスト（#がなければ追加）
    final displayTag = tag.startsWith('#') ? tag : '#$tag';
    final color = isUser ? Colors.white : AppColors.primary600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isUser ? Colors.white.withOpacity(0.2) : AppColors.primary50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            displayTag,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// タグに応じたアイコンを取得
  IconData? _getTagIcon(String tag) {
    // 食事タグ
    if (tag.contains('朝食')) return LucideIcons.sunrise;
    if (tag.contains('昼食')) return LucideIcons.sun;
    if (tag.contains('夕食') || tag.contains('晩')) return LucideIcons.moon;
    if (tag.contains('間食')) return LucideIcons.cookie;
    if (tag.contains('食事')) return LucideIcons.utensils;

    // 運動タグ
    if (tag.contains('筋トレ')) return LucideIcons.dumbbell;
    if (tag.contains('有酸素')) return LucideIcons.activity;
    if (tag.contains('ランニング') || tag.contains('走')) return LucideIcons.activity;
    if (tag.contains('ウォーキング') || tag.contains('歩')) return LucideIcons.footprints;
    if (tag.contains('自転車') || tag.contains('サイクリング')) return LucideIcons.bike;
    if (tag.contains('水泳') || tag.contains('プール')) return LucideIcons.waves;
    if (tag.contains('ヨガ')) return LucideIcons.flower2;
    if (tag.contains('運動')) return LucideIcons.dumbbell;

    // 体重タグ
    if (tag.contains('体重')) return LucideIcons.scale;

    return null;
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MessageBubble - User (Basic)')
Widget previewMessageBubbleUser() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MessageBubble(
            message: 'こんにちは！',
            isUser: true,
            timestamp: '12:34',
            onReply: () {},
            onEdit: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - Trainer (Basic)')
Widget previewMessageBubbleTrainer() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MessageBubble(
            message: 'トレーニングお疲れ様です！',
            isUser: false,
            timestamp: '12:35',
            onReply: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - With Reply')
Widget previewMessageBubbleWithReply() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              MessageBubble(
                message: 'はい、頑張ります！',
                isUser: true,
                timestamp: '12:35',
                replyToContent: '今日のトレーニングお疲れ様でした！',
                replyToSenderName: 'トレーナー',
                onReply: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '明日は筋トレの日ですね',
                isUser: false,
                timestamp: '12:36',
                replyToContent: 'はい、頑張ります！',
                replyToSenderName: '自分',
                onReply: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - With Tags')
Widget previewMessageBubbleWithTags() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MessageBubble(
            message: '#食事:朝食 サラダとゆで卵を食べました',
            isUser: true,
            timestamp: '08:30',
            tags: ['#食事:朝食'],
            onReply: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - System Message')
Widget previewMessageBubbleSystem() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MessageBubble(
            message: '目標を達成しました！🎉',
            isUser: false,
            timestamp: '14:20',
            isSystem: true,
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - With Images')
Widget previewMessageBubbleWithImages() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MessageBubble(
            message: '#食事:昼食 今日のランチです',
            isUser: true,
            timestamp: '12:30',
            tags: ['#食事:昼食'],
            images: [
              'https://picsum.photos/seed/lunch1/300/300',
              'https://picsum.photos/seed/lunch2/300/300',
            ],
            onReply: () {},
            onEdit: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - Edited Message')
Widget previewMessageBubbleEdited() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              MessageBubble(
                message: '訂正：今日は10km走りました！',
                isUser: true,
                timestamp: '14:30',
                isEdited: true,
                onReply: () {},
                onEdit: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '素晴らしいですね！次回は15kmに挑戦してみましょう',
                isUser: false,
                timestamp: '14:32',
                isEdited: true,
                onReply: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - Edit Menu Demo')
Widget previewMessageBubbleEditMenu() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Builder(
            builder: (context) {
              final colors = AppColors.of(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '長押しでメニュー表示（自分のメッセージ）',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MessageBubble(
                    message: 'このメッセージを長押ししてください',
                    isUser: true,
                    timestamp: '12:34',
                    onReply: () {},
                    onEdit: () {},
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '長押しでメニュー表示（相手のメッセージ - 編集不可）',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  MessageBubble(
                    message: '返信のみ可能です',
                    isUser: false,
                    timestamp: '12:35',
                    onReply: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - Workout Report')
Widget previewMessageBubbleWorkoutReport() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              MessageBubble(
                message: 'ワークアウト完了！\n🔥 消費カロリー: 350kcal\n💬 今日は脚トレを頑張りました！',
                isUser: true,
                timestamp: '18:30',
                tags: ['#運動:筋トレ'],
                onReply: () {},
                onEdit: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '素晴らしい成果ですね！🔥 消費カロリーも十分です。💬 次回はスクワットを増やしましょう',
                isUser: false,
                timestamp: '18:35',
                onReply: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MessageBubble - Read Receipt')
Widget previewMessageBubbleReadReceipt() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              MessageBubble(
                message: '既読メッセージです',
                isUser: true,
                timestamp: '12:34',
                isRead: true,
                onReply: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '既読かつ編集済みメッセージ',
                isUser: true,
                timestamp: '12:35',
                isRead: true,
                isEdited: true,
                onReply: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '未読メッセージです',
                isUser: true,
                timestamp: '12:36',
                isRead: false,
                onReply: () {},
              ),
              const SizedBox(height: 16),
              MessageBubble(
                message: '相手のメッセージ（既読表示なし）',
                isUser: false,
                timestamp: '12:37',
                isRead: true,
                onReply: () {},
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
