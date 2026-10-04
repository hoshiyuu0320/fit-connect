import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/message_bubble.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/chat_input.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_quote.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/trainer_avatar.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:intl/intl.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_filter.dart';
import 'package:fit_connect_mobile/features/messages/providers/message_filter_provider.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// メッセージタブ（トレーナーとの会話）。
///
/// 正本 `message-screens.js` の `ChatScreen`: 上から コーチのヘッダー → 会話 → クイック操作 + 入力。
/// 固定高さの会話で、入力欄は下に固定する（キーボードの真上 / ナビの上）。
/// 自分のメッセージは記録カード、トレーナーのメッセージは吹き出し（[MessageBubble]）。
/// オンライン表示・最終ログイン・既読・未読の数字は出さない。
class MessageScreen extends ConsumerStatefulWidget {
  /// 外部から流し込む定型文（セッションの「変更を相談」など）。
  /// そのまま ChatInput へ透過する
  final String? initialDraft;

  /// 定型文を入力欄へ反映し終えたときに呼ばれる。
  /// 呼び出し側（MainScreen）はここで draft を破棄し、再注入を防ぐ
  final VoidCallback? onDraftConsumed;

  const MessageScreen({
    super.key,
    this.initialDraft,
    this.onDraftConsumed,
  });

  @override
  ConsumerState<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends ConsumerState<MessageScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _replyToMessageId;
  String? _replyToContent;
  String? _replyToSenderName;
  String? _editingMessageId;
  String? _editingMessageContent;
  DateTime? _lastLoadMoreTime;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // 画面表示時に既存の未読メッセージを既読化（ナビの「新着あり」の点を消すため。画面には既読を出さない）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(paginatedMessagesProvider.notifier).markConversationAsRead();
    });
    // AI機能ゲートを画面表示時に先読みし、食事フォームを開いた瞬間に
    // 解決済みになるようにする（モード切替セグメントの遅延表示を防ぐ）。
    // keepAlive 化と併せてセッション中はキャッシュされ、再フェッチも防がれる。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiFeaturesEnabledProvider);
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

  void _setReplyTarget(Message message, String senderName) {
    // 編集モードをクリア
    _clearEditTarget();
    setState(() {
      _replyToMessageId = message.id;
      _replyToContent = message.content ?? '';
      _replyToSenderName = senderName;
    });
  }

  void _clearReplyTarget() {
    setState(() {
      _replyToMessageId = null;
      _replyToContent = null;
      _replyToSenderName = null;
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

  Future<void> _editMessage(String newContent) async {
    if (_editingMessageId == null) return;

    // タグを解析
    final newTags = parseMessageTags(newContent);

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
            const SnackBar(content: Text('編集可能な時間（5分）を過ぎました')),
          );
        }
      }
      _clearEditTarget();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メッセージの編集に失敗しました: $e')),
        );
      }
    }
  }

  Future<void> _handleSend(
      String text,
      List<String>? imageUrls,
      String? replyToId,
      Map<String, dynamic>? metadata) async {
    if (text.trim().isEmpty && (imageUrls == null || imageUrls.isEmpty)) return;

    // 編集モードの場合
    if (_editingMessageId != null) {
      await _editMessage(text);
      return;
    }

    // 通常送信モード
    // Parse tags from message
    final tags = parseMessageTags(text);

    try {
      await ref.read(paginatedMessagesProvider.notifier).sendMessage(
            content: text,
            imageUrls: imageUrls,
            tags: tags,
            replyToMessageId: replyToId,
            metadata: metadata,
          );
      // 記録のみ表示中にタグなしメッセージを送ったら「すべて」に戻す（送ったものが隠れないように）
      if (tags == null || tags.isEmpty) {
        ref
            .read(messageFilterControllerProvider.notifier)
            .setFilter(MessageFilter.all);
      }
      _clearReplyTarget();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateAsync = ref.watch(paginatedMessagesProvider);
    final messageFilter = ref.watch(messageFilterControllerProvider);

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
    final trainerName = trainerDisplayName(trainerProfile?.name);

    // 下部ナビの上へ入力欄を置く。ナビが確保する余白（参照値 93 + 28）のうち、本文との間の 28 は
    // 正本の会話画面にはない（入力欄の下 12 + ナビの上余白 14 で足りる）ので引く。
    // キーボード表示中は padding.bottom が 0 になるので、引いても 0（キーボードの真上に付く）
    final bottomInset = math.max(
      0.0,
      MediaQuery.paddingOf(context).bottom - AppSizes.navContentGap,
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _ChatHeader(
                name: trainerName,
                imageValue: trainerProfile?.profileImageUrl,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    children: [
                      // 会話（高さが足りないときは、絞り込みの行を畳む）
                      Expanded(
                        child: _ThreadArea(
                          filter: messageFilter,
                          onFilterChanged: (filter) => ref
                              .read(messageFilterControllerProvider.notifier)
                              .setFilter(filter),
                          child: stateAsync.when(
                            data: (paginatedState) {
                              final filtered = applyMessageFilter(
                                  paginatedState.messages, messageFilter);
                              if (filtered.isEmpty) {
                                return _EmptyThread(
                                  recordsOnly:
                                      messageFilter == MessageFilter.recordsOnly,
                                );
                              }
                              return _buildMessageList(
                                paginatedState,
                                currentUser?.id,
                                filtered,
                              );
                            },
                            loading: () => const _ThreadSkeleton(),
                            error: (e, _) => _ThreadError(
                              onRetry: () =>
                                  ref.invalidate(paginatedMessagesProvider),
                            ),
                          ),
                        ),
                      ),
                      // 入力（クイック操作 + 入力行）。高さはこの領域まで（フォームを開いたときは中でスクロール）
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: constraints.maxHeight),
                        child: Padding(
                          padding: EdgeInsets.only(bottom: bottomInset),
                          child: ChatInput(
                            onSend: _handleSend,
                            userId: currentUser?.id,
                            replyToMessageId: _replyToMessageId,
                            replyToContent: _replyToContent,
                            replyToSenderName: _replyToSenderName,
                            onCancelReply: _clearReplyTarget,
                            editingMessageId: _editingMessageId,
                            editingMessageContent: _editingMessageContent,
                            onCancelEdit: _clearEditTarget,
                            initialDraft: widget.initialDraft,
                            onDraftConsumed: widget.onDraftConsumed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(PaginatedMessagesState paginatedState,
      String? currentUserId, List<Message> messages) {
    final colors = AppColors.of(context);
    final allMessages = paginatedState.messages;
    final messageFilter = ref.watch(messageFilterControllerProvider);
    final trainerProfile = ref.watch(trainerProfileProvider).valueOrNull;
    final trainerName = trainerDisplayName(trainerProfile?.name);
    final horizontal = AppSpacing.pageHorizontalOf(context);

    // Helper function to find message by ID
    Message? findMessageById(String? id) {
      if (id == null) return null;
      try {
        return allMessages.firstWhere((m) => m.id == id);
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
      padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 6),
      itemCount: sortedDates.length +
          (paginatedState.isLoadingMore || !paginatedState.hasMore ? 1 : 0),
      itemBuilder: (context, dateIndex) {
        // ローディングインジケータ or 「これ以上メッセージはありません」
        if (dateIndex == sortedDates.length) {
          if (paginatedState.isLoadingMore) {
            return Semantics(
              label: '古いメッセージを読み込み中',
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            );
          }
          if (!paginatedState.hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text(
                  messageFilter == MessageFilter.recordsOnly
                      ? 'これ以上記録はありません'
                      : 'これ以上メッセージはありません',
                  style: AppTextStyles.caption(context),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 日付の区切り（前の日との間を少し空ける）
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: MessageDateDivider(_dateLabel(date)),
            ),
            // その日のメッセージ（間は 14）
            for (var i = 0; i < dayMessages.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                child: _buildMessage(
                  dayMessages[i],
                  currentUserId: currentUserId,
                  trainerName: trainerName,
                  trainerImageValue: trainerProfile?.profileImageUrl,
                  replyMessage: findMessageById(dayMessages[i].replyToMessageId),
                  colors: colors,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMessage(
    Message message, {
    required String? currentUserId,
    required String trainerName,
    required String? trainerImageValue,
    required Message? replyMessage,
    required AppColorsExtension colors,
  }) {
    final isUser = message.senderId == currentUserId;
    return MessageBubble(
      message: message.content ?? '',
      messageId: message.id,
      isUser: isUser,
      timestamp: DateFormat('H:mm').format(message.createdAt),
      tags: message.tags,
      images: message.imageUrls,
      replyToContent: replyMessage?.content,
      replyToSenderName: replyMessage != null
          ? (replyMessage.senderId == currentUserId
              ? ReplyQuote.selfName
              : trainerName)
          : null,
      isSystem: false,
      isEdited: message.isEdited,
      trainerName: trainerName,
      trainerProfileImageUrl: trainerImageValue,
      onReply: () => _setReplyTarget(
        message,
        isUser ? ReplyQuote.selfName : trainerName,
      ),
      onEdit: isUser ? () => _setEditTarget(message) : null,
    );
  }
}

/// 日付の区切りの文言。今日 / 昨日 / 「9月13日（日）」
String _dateLabel(DateTime date, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final messageDate = DateTime(date.year, date.month, date.day);

  if (messageDate == today) return '今日';
  if (messageDate == yesterday) return '昨日';
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  return '${date.month}月${date.day}日（${weekdays[date.weekday - 1]}）';
}

// ============================================
// 画面の部品
// ============================================

/// コーチのヘッダー（正本 `ChatHeader` + `CoachHeader`）。
///
/// アバター（46）・名前（25/500/字間 -1）・役割「あなたの担当トレーナー」（14・textSecondary）。
/// 余白 左右 20 / 上 4 / 下 12、下に 1px の separator。オンライン表示・最終ログインは出さない。
class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.name, required this.imageValue});

  final String name;
  final String? imageValue;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final horizontal = AppSpacing.pageHorizontalOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.separator)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 4, horizontal, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TrainerAvatar(name: name, imageValue: imageValue, size: FcAvatar.lg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(name, style: AppTextStyles.coachName(context)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'あなたの担当トレーナー',
                    style: AppTextStyles.label(context)
                        .copyWith(color: colors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 会話の領域。上に絞り込み（すべて / 記録）のタブ、下に会話。
///
/// 正本の会話画面には絞り込みが無いが、現行の機能（記録だけに絞り込める）を残すため、
/// ヘッダーの下に置く。記録画面と同じ [FcSubTabs]（カプセルの中で選択中だけ面と accent の文字）で、
/// 2 項目なので幅いっぱいに等分して広がる。ボタンではなくタブに見えるようにするためで、
/// 選択中はライト・ダークどちらでも面の違いと文字の色・太さの両方で分かる。
/// この領域の高さが足りないとき（キーボード表示中に記録フォームを開いたなど）は、
/// 行ごと畳んで会話に高さを譲る。
class _ThreadArea extends StatelessWidget {
  const _ThreadArea({
    required this.filter,
    required this.onFilterChanged,
    required this.child,
  });

  /// タブの行の余白（上・下）。ヘッダーの下線とタブ、タブと会話の間を空ける
  static const double filterTop = 12;
  static const double filterBottom = 8;

  /// タブの行の高さ（タブ 44 + カプセルの内側余白 4×2 + 上下の余白）
  static const double filterRowHeight =
      AppSizes.minTouch + FcSubTabs.inset * 2 + filterTop + filterBottom;

  /// タブの行を出すのに必要な領域の高さ（タブの行 + 会話に最低限の高さ）
  static const double minHeightForFilter = filterRowHeight + 112;

  final MessageFilter filter;
  final ValueChanged<MessageFilter> onFilterChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (constraints.maxHeight >= minHeightForFilter)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                filterTop,
                horizontal,
                filterBottom,
              ),
              child: FcSubTabs<MessageFilter>(
                items: const [
                  FcSubTabItem(value: MessageFilter.all, label: 'すべて'),
                  FcSubTabItem(value: MessageFilter.recordsOnly, label: '記録'),
                ],
                selected: filter,
                onChanged: onFilterChanged,
              ),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// メッセージが無いとき。会話の下（入力欄の近く）に置き、入力への案内を添える
class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.recordsOnly});

  final bool recordsOnly;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        reverse: true,
        primary: false,
        padding: EdgeInsets.fromLTRB(horizontal, AppSpacing.lg, horizontal, 6),
        child: FcStateMessage.empty(
          title: recordsOnly ? 'まだ記録がありません。' : 'まだメッセージはありません。',
          message: recordsOnly
              ? '体重・食事・運動を記録すると、ここに並びます。下の「体重」「食事」「運動」から記録できます。'
              : '下の入力欄から、トレーナーにメッセージや記録を送れます。',
        ),
      ),
    );
  }
}

/// 読み込みに失敗したとき
class _ThreadError extends StatelessWidget {
  const _ThreadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        reverse: true,
        primary: false,
        padding: EdgeInsets.fromLTRB(horizontal, AppSpacing.lg, horizontal, 6),
        child: FcStateMessage.error(
          title: 'メッセージを読み込めませんでした',
          message: '通信の状態を確認して、もう一度お試しください。',
          actionLabel: '再試行',
          onAction: onRetry,
        ),
      ),
    );
  }
}

/// 読込中。会話と同じ配置のスケルトン（日付 → 記録カード → 返信 → 記録カード）
class _ThreadSkeleton extends StatelessWidget {
  const _ThreadSkeleton();

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return Semantics(
      label: '読み込み中',
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SingleChildScrollView(
          reverse: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Center(child: FcSkeleton.line(width: 96)),
              SizedBox(height: 13),
              Padding(
                padding: EdgeInsets.only(left: RecordMessageCard.indent),
                child: FcSkeleton(height: 92, radius: AppRadius.chatRecordCard),
              ),
              SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FcSkeleton.circle(size: FcAvatar.sm),
                  SizedBox(width: 9),
                  Expanded(
                    child: FcSkeleton(
                        height: 76, radius: AppRadius.chatRecordCard),
                  ),
                ],
              ),
              SizedBox(height: 14),
              Padding(
                padding: EdgeInsets.only(left: RecordMessageCard.indent),
                child: FcSkeleton(height: 72, radius: AppRadius.chatRecordCard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews（Riverpod を使う画面なので、静的な部品の組み合わせで再現する）
// ============================================

enum _PreviewState { normal, empty, loading }

class _PreviewMessageScreen extends StatelessWidget {
  const _PreviewMessageScreen({required this.state});

  final _PreviewState state;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);

    final Widget thread = switch (state) {
      _PreviewState.loading => const _ThreadSkeleton(),
      _PreviewState.empty => const _EmptyThread(recordsOnly: false),
      _PreviewState.normal => ListView(
          reverse: true,
          padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, 6),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: AppSpacing.lg),
                  child: MessageDateDivider('9月13日（日）'),
                ),
                MessageBubble(
                  message: '#体重 62.4 kg',
                  isUser: true,
                  timestamp: '7:30',
                  tags: ['#体重'],
                ),
                SizedBox(height: 14),
                MessageBubble(
                  message: '#食事:朝食 ごはん・卵・ヨーグルト',
                  isUser: true,
                  timestamp: '8:10',
                  tags: ['#食事:朝食'],
                ),
                SizedBox(height: 14),
                MessageBubble(
                  message: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
                  isUser: false,
                  timestamp: '9:10',
                  trainerName: '田中トレーナー',
                ),
                SizedBox(height: 14),
                MessageBubble(
                  message: 'ありがとうございます。昼もたんぱく質を意識してみます。',
                  isUser: true,
                  timestamp: '9:24',
                  isEdited: true,
                  replyToSenderName: '田中トレーナー',
                  replyToContent: '朝食の記録、ありがとうございます。',
                ),
              ],
            ),
          ],
        ),
    };

    return Column(
      children: [
        const _ChatHeader(name: '田中トレーナー', imageValue: null),
        Expanded(
          child: _ThreadArea(
            filter: MessageFilter.all,
            onFilterChanged: (_) {},
            child: thread,
          ),
        ),
        ChatInput(
          onSend: (text, images, replyTo, metadata) async {},
          userId: 'user-123',
        ),
        // 下部ナビの分（参照値 93）
        const SizedBox(height: AppSizes.navReferenceHeight),
      ],
    );
  }
}

Widget _previewApp({
  required Brightness brightness,
  required _PreviewState state,
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
        bottom: false,
        child: _PreviewMessageScreen(state: state),
      ),
    ),
  );
}

@Preview(name: 'MessageScreen - 通常')
Widget previewMessageScreenNormal() =>
    _previewApp(brightness: Brightness.light, state: _PreviewState.normal);

@Preview(name: 'MessageScreen - 空')
Widget previewMessageScreenEmpty() =>
    _previewApp(brightness: Brightness.light, state: _PreviewState.empty);

@Preview(name: 'MessageScreen - 読込中')
Widget previewMessageScreenLoading() =>
    _previewApp(brightness: Brightness.light, state: _PreviewState.loading);

@Preview(name: 'MessageScreen - ダーク')
Widget previewMessageScreenDark() =>
    _previewApp(brightness: Brightness.dark, state: _PreviewState.normal);

@Preview(name: 'MessageScreen - 文字1.35')
Widget previewMessageScreenLarge() => _previewApp(
      brightness: Brightness.light,
      state: _PreviewState.normal,
      textScale: 1.35,
    );
