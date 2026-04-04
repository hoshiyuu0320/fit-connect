import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/message_bubble.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:fit_connect_mobile/features/schedules/providers/trainer_schedule_provider.dart';

class MessageScreen extends ConsumerStatefulWidget {
  const MessageScreen({super.key});

  @override
  ConsumerState<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends ConsumerState<MessageScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _replyToMessageId;
  String? _replyToContent;
  String? _editingMessageId;
  String? _editingMessageContent;
  DateTime? _lastLoadMoreTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 画面表示時に既存の未読メッセージを既読化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paginatedMessagesProvider.notifier).markConversationAsRead();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // reverse: true のListViewでは maxScrollExtent側が上端（古いメッセージ側）
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // デバウンス: 前回のloadMoreから1秒以内は再発火しない
      final now = DateTime.now();
      if (_lastLoadMoreTime != null &&
          now.difference(_lastLoadMoreTime!) < const Duration(seconds: 1)) {
        return;
      }

      final currentState = ref.read(paginatedMessagesProvider).valueOrNull;
      if (currentState != null &&
          currentState.hasMore &&
          !currentState.isLoadingMore) {
        _lastLoadMoreTime = now;
        ref.read(paginatedMessagesProvider.notifier).loadMore();
      }
    }
  }

  void _setReplyTarget(Message message) {
    // 編集モードをクリア
    _clearEditTarget();
    setState(() {
      _replyToMessageId = message.id;
      _replyToContent = message.content ?? '';
    });
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToMessageId = null;
      _replyToContent = null;
    });
  }

  void _setEditTarget(Message message) {
    // 返信モードをクリア
    _clearReplyTarget();
    setState(() {
      _editingMessageId = message.id;
      _editingMessageContent = message.content ?? '';
    });
  }

  void _clearEditTarget() {
    setState(() {
      _editingMessageId = null;
      _editingMessageContent = null;
    });
  }

  /// タグを解析するプライベートメソッド
  List<String>? _parseTags(String text) {
    if (text.contains('#食事') || text.contains('#meal')) {
      if (text.contains('朝食') || text.contains('breakfast')) {
        return ['食事:朝食'];
      } else if (text.contains('昼食') || text.contains('lunch')) {
        return ['食事:昼食'];
      } else if (text.contains('夕食') || text.contains('dinner')) {
        return ['食事:夕食'];
      } else if (text.contains('間食') || text.contains('snack')) {
        return ['食事:間食'];
      } else {
        return ['食事'];
      }
    } else if (text.contains('#体重') || text.contains('#weight')) {
      return ['体重'];
    } else if (text.contains('#運動') || text.contains('#exercise')) {
      if (text.contains('筋トレ')) {
        return ['運動:筋トレ'];
      } else if (text.contains('有酸素') || text.contains('ランニング')) {
        return ['運動:有酸素'];
      } else {
        return ['運動'];
      }
    }
    return null;
  }

  Future<void> _editMessage(String newContent) async {
    if (_editingMessageId == null) return;

    // タグを解析
    final newTags = _parseTags(newContent);

    try {
      final success =
          await ref.read(paginatedMessagesProvider.notifier).editMessage(
                messageId: _editingMessageId!,
                newContent: newContent,
                newTags: newTags,
              );

      if (!success) {
        // 編集期限切れ
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('編集可能な時間（5分）を過ぎました'),
              backgroundColor: AppColors.rose800,
            ),
          );
        }
      }
      _clearEditTarget();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('メッセージの編集に失敗しました: $e'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    }
  }

  Future<void> _handleSend(
      String text, List<String>? imageUrls, String? replyToId) async {
    if (text.trim().isEmpty && (imageUrls == null || imageUrls.isEmpty)) return;

    // 編集モードの場合
    if (_editingMessageId != null) {
      await _editMessage(text);
      return;
    }

    // 通常送信モード
    // Parse tags from message
    final tags = _parseTags(text);

    try {
      await ref.read(paginatedMessagesProvider.notifier).sendMessage(
            content: text,
            imageUrls: imageUrls,
            tags: tags,
            replyToMessageId: replyToId,
          );
      _clearReplyTarget();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('メッセージの送信に失敗しました: $e'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final stateAsync = ref.watch(paginatedMessagesProvider);

    // 自動既読処理: 受信メッセージに未読があれば既読化（新着メッセージ到着時）
    ref.listen<AsyncValue<PaginatedMessagesState>>(paginatedMessagesProvider,
        (previous, next) {
      next.whenData((paginatedState) {
        final userId = ref.read(authNotifierProvider).valueOrNull?.id;
        if (userId == null) return;
        final hasUnread = paginatedState.messages
            .any((m) => m.senderId != userId && m.readAt == null);
        if (hasUnread && mounted) {
          ref.read(paginatedMessagesProvider.notifier).markConversationAsRead();
        }
      });
    });

    final currentUser = ref.watch(authNotifierProvider).valueOrNull;
    final trainerProfile = ref.watch(trainerProfileProvider).valueOrNull;
    final trainerName = trainerProfile?.name ?? 'トレーナー';
    final trainerPresence = ref.watch(trainerPresenceNotifierProvider);
    final isTrainerOnline = trainerPresence.isOnline;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: _buildAppBar(context, trainerName, isTrainerOnline,
            trainerProfile?.profileImageUrl, trainerPresence.lastSeenAt),
        body: Column(
          children: [
            if (!isTrainerOnline)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFFFFFBEB),
                child: Row(
                  children: [
                    Icon(LucideIcons.clock,
                        size: 16, color: AppColors.amber700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'トレーナーは現在オフラインです。返信が遅くなる場合があります。',
                        style: TextStyle(
                          color: AppColors.slate700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: stateAsync.when(
                data: (paginatedState) {
                  if (paginatedState.messages.isEmpty) {
                    return _buildEmptyState(colors);
                  }

                  return _buildMessageList(
                      paginatedState, currentUser?.id, colors);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.alertCircle,
                          size: 48, color: AppColors.rose800),
                      const SizedBox(height: 16),
                      Text(
                        'メッセージの読み込みに失敗しました',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(paginatedMessagesProvider),
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ChatInput(
              onSend: _handleSend,
              userId: currentUser?.id,
              replyToMessageId: _replyToMessageId,
              replyToContent: _replyToContent,
              onCancelReply: _clearReplyTarget,
              editingMessageId: _editingMessageId,
              editingMessageContent: _editingMessageContent,
              onCancelEdit: _clearEditTarget,
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(DateTime? lastSeenAt) {
    if (lastSeenAt == null) return 'オフライン';
    final diff = DateTime.now().difference(lastSeenAt);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, String trainerName,
      bool isOnline, String? profileImageUrl, DateTime? lastSeenAt) {
    final colors = AppColors.of(context);
    return AppBar(
      backgroundColor: colors.surface,
      elevation: 0,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    shape: BoxShape.circle,
                  ),
                  child: profileImageUrl != null
                      ? ClipOval(
                          child: Image.network(
                            profileImageUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Icon(LucideIcons.user, color: colors.textHint),
                          ),
                        )
                      : Icon(LucideIcons.user, color: colors.textHint),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.success : colors.textHint,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trainerName,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isOnline
                      ? 'オンライン'
                      : _formatLastSeen(lastSeenAt),
                  style: TextStyle(
                    color: isOnline ? AppColors.success : colors.textHint,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(LucideIcons.chevronDown, color: colors.textHint),
          onPressed: () {},
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: colors.border, height: 1),
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.messageCircle, size: 64, color: colors.textHint),
          const SizedBox(height: 16),
          Text(
            'メッセージはまだありません',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'トレーナーにメッセージを送りましょう！',
            style: TextStyle(
              color: colors.textHint,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(PaginatedMessagesState paginatedState,
      String? currentUserId, AppColorsExtension colors) {
    final messages = paginatedState.messages;
    final trainerProfile = ref.watch(trainerProfileProvider).valueOrNull;
    final trainerName = trainerProfile?.name ?? 'トレーナー';

    // Helper function to find message by ID
    Message? findMessageById(String? id) {
      if (id == null) return null;
      try {
        return messages.firstWhere((m) => m.id == id);
      } catch (_) {
        return null;
      }
    }

    // Group messages by date
    final groupedMessages = <String, List<Message>>{};
    for (final message in messages) {
      final dateKey = DateFormat('yyyy-MM-dd').format(message.createdAt);
      groupedMessages.putIfAbsent(dateKey, () => []).add(message);
    }

    // Sort dates in descending order (newest first) for reverse List
    final sortedDates = groupedMessages.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      reverse: true,
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedDates.length +
          (paginatedState.isLoadingMore || !paginatedState.hasMore ? 1 : 0),
      itemBuilder: (context, dateIndex) {
        // ローディングインジケータ or 「これ以上メッセージはありません」
        if (dateIndex == sortedDates.length) {
          if (paginatedState.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!paginatedState.hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'これ以上メッセージはありません',
                  style: TextStyle(
                    color: colors.textHint,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final dateKey = sortedDates[dateIndex];
        final dayMessages = groupedMessages[dateKey]!;
        final date = DateTime.parse(dateKey);

        return Column(
          children: [
            // Date divider
            _buildDateDivider(date, colors),
            // Messages for this date
            ...dayMessages.map((message) {
              final replyMessage = findMessageById(message.replyToMessageId);
              final isUser = message.senderId == currentUserId;

              return MessageBubble(
                message: message.content ?? '',
                messageId: message.id,
                isUser: isUser,
                timestamp: DateFormat('HH:mm').format(message.createdAt),
                tags: message.tags,
                images: message.imageUrls,
                replyToContent: replyMessage?.content,
                replyToSenderName: replyMessage != null
                    ? (replyMessage.senderId == currentUserId
                        ? '自分'
                        : trainerName)
                    : null,
                isSystem: false,
                isEdited: message.isEdited,
                isRead: isUser && message.readAt != null,
                trainerProfileImageUrl: trainerProfile?.profileImageUrl,
                onReply: () => _setReplyTarget(message),
                onEdit: isUser ? () => _setEditTarget(message) : null,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(DateTime date, AppColorsExtension colors) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;
    if (messageDate == today) {
      dateText = '今日';
    } else if (messageDate == yesterday) {
      dateText = '昨日';
    } else {
      dateText = DateFormat('M月d日').format(date);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            dateText,
            style: TextStyle(
              color: colors.textHint,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MessageScreen - Static Preview')
Widget previewMessageScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: _PreviewMessageScreen(),
      ),
    ),
  );
}

class _PreviewMessageScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final mockMessages = [
      _MockMessage(
        content: 'こんにちは！今日の調子はいかがですか？',
        isUser: false,
        timestamp: '09:00',
        tags: null,
        images: null,
      ),
      _MockMessage(
        content: '#食事:朝食\nオートミールとバナナを食べました！',
        isUser: true,
        timestamp: '09:15',
        tags: ['食事:朝食'],
        images: ['https://picsum.photos/seed/food1/300/300'],
      ),
      _MockMessage(
        content: 'ヘルシーで良いスタートですね！',
        isUser: false,
        timestamp: '09:20',
        tags: null,
        images: null,
      ),
      _MockMessage(
        content: '#体重 65.5kg\n少し減りました！',
        isUser: true,
        timestamp: '10:00',
        tags: ['体重'],
        images: null,
      ),
      _MockMessage(
        content: '順調ですね！その調子で頑張りましょう',
        isUser: false,
        timestamp: '10:05',
        tags: null,
        images: null,
      ),
    ];

    return Column(
      children: [
        // AppBar
        Container(
          color: colors.surface,
          padding: const EdgeInsets.all(8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.surfaceDim,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.user, color: colors.textHint),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Coach Sarah',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Online',
                      style: TextStyle(
                        color: AppColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Icon(LucideIcons.chevronDown, color: colors.textHint),
              ],
            ),
          ),
        ),
        Container(color: colors.border, height: 1),

        // Messages
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Date divider
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    '今日',
                    style: TextStyle(
                      color: colors.textHint,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Messages
              ...mockMessages.map((msg) => MessageBubble(
                    message: msg.content,
                    isUser: msg.isUser,
                    timestamp: msg.timestamp,
                    tags: msg.tags,
                    images: msg.images,
                    isSystem: false,
                    isEdited: msg.isEdited ?? false,
                  )),
            ],
          ),
        ),

        // Input (static preview)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'メッセージを入力...',
                    style: TextStyle(color: colors.textHint),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.primary600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.send, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MockMessage {
  final String content;
  final bool isUser;
  final String timestamp;
  final List<String>? tags;
  final List<String>? images;
  final bool? isEdited;

  _MockMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.tags,
    this.images,
    this.isEdited,
  });
}
