import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'messages_provider.g.dart';

/// MessageRepositoryのProvider
@riverpod
MessageRepository messageRepository(MessageRepositoryRef ref) {
  return MessageRepository();
}

/// ページネーション付きメッセージ管理Provider
@riverpod
class PaginatedMessages extends _$PaginatedMessages {
  static const _pageSize = 30;
  RealtimeChannel? _channel;

  @override
  Future<PaginatedMessagesState> build() async {
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final trainerId = ref.watch(currentTrainerIdProvider);

    if (user == null || trainerId == null) {
      return PaginatedMessagesState.empty;
    }

    // 前回のchannelがあれば解除
    await _channel?.unsubscribe();
    _channel = null;

    final repository = ref.watch(messageRepositoryProvider);
    final messages = await repository.fetchMessages(
      userId: user.id,
      otherUserId: trainerId,
      limit: _pageSize,
    );

    // Realtime channelセットアップ
    _setupRealtimeChannel(user.id, trainerId);

    // dispose時にchannel解除
    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });

    return PaginatedMessagesState(
      messages: messages,
      hasMore: messages.length >= _pageSize,
      isLoadingMore: false,
    );
  }

  /// 古いメッセージを追加ロード
  Future<void> loadMore() async {
    final currentState = state.valueOrNull;
    if (currentState == null ||
        !currentState.hasMore ||
        currentState.isLoadingMore) {
      return;
    }

    state = AsyncData(currentState.copyWith(isLoadingMore: true));

    try {
      final user = ref.read(authNotifierProvider).valueOrNull;
      final trainerId = ref.read(currentTrainerIdProvider);
      if (user == null || trainerId == null) return;

      final repository = ref.read(messageRepositoryProvider);
      final oldestMessage = currentState.messages.first;

      final olderMessages = await repository.fetchMessages(
        userId: user.id,
        otherUserId: trainerId,
        limit: _pageSize,
        before: oldestMessage.createdAt,
      );

      // 最新のstateを再取得（fetch中にRealtimeで新着が追加された可能性）
      final latestState = state.valueOrNull;
      if (latestState == null) return;

      // 重複排除（安全策）
      final existingIds = latestState.messages.map((m) => m.id).toSet();
      final newMessages =
          olderMessages.where((m) => !existingIds.contains(m.id)).toList();

      state = AsyncData(latestState.copyWith(
        messages: [...newMessages, ...latestState.messages],
        hasMore: olderMessages.length >= _pageSize,
        isLoadingMore: false,
      ));
    } catch (e) {
      final latestState = state.valueOrNull;
      if (latestState != null) {
        state = AsyncData(latestState.copyWith(isLoadingMore: false));
      }
    }
  }

  /// メッセージを送信（楽観的更新）
  Future<void> sendMessage({
    required String content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    final trainerId = ref.read(currentTrainerIdProvider);

    if (user == null || trainerId == null) {
      throw Exception('User or trainer not found');
    }

    final repository = ref.read(messageRepositoryProvider);
    final sentMessage = await repository.sendMessage(
      senderId: user.id,
      receiverId: trainerId,
      senderType: 'client',
      receiverType: 'trainer',
      content: content,
      imageUrls: imageUrls,
      tags: tags,
      replyToMessageId: replyToMessageId,
      metadata: metadata,
    );

    // 楽観的更新: ローカルstateに即追加
    final currentState = state.valueOrNull;
    if (currentState != null) {
      state = AsyncData(currentState.copyWith(
        messages: [...currentState.messages, sentMessage],
      ));
    }
  }

  /// メッセージを編集（5分以内）
  Future<bool> editMessage({
    required String messageId,
    required String newContent,
    List<String>? newTags,
  }) async {
    final repository = ref.read(messageRepositoryProvider);
    final result = await repository.editMessage(
      messageId: messageId,
      newContent: newContent,
      newTags: newTags,
    );

    if (result != null) {
      // ローカルstateで該当メッセージを置換
      final currentState = state.valueOrNull;
      if (currentState != null) {
        final updatedMessages = currentState.messages.map((m) {
          return m.id == messageId ? result : m;
        }).toList();
        state = AsyncData(currentState.copyWith(messages: updatedMessages));
      }
      return true;
    }
    return false;
  }

  /// 会話のメッセージを既読にする
  Future<void> markConversationAsRead() async {
    final trainerId = ref.read(currentTrainerIdProvider);
    if (trainerId == null) return;

    final repository = ref.read(messageRepositoryProvider);
    await repository.markConversationAsRead(trainerId);
    ref.invalidate(unreadMessageCountProvider);
  }

  /// Realtime channelセットアップ
  void _setupRealtimeChannel(String userId, String otherUserId) {
    final repository = ref.read(messageRepositoryProvider);
    _channel = repository.subscribeToMessages(
      userId: userId,
      otherUserId: otherUserId,
      onInsert: (message) {
        final currentState = state.valueOrNull;
        if (currentState == null) return;

        // 重複チェック（楽観的更新済みの自分のメッセージ）
        final alreadyExists =
            currentState.messages.any((m) => m.id == message.id);
        if (alreadyExists) return;

        state = AsyncData(currentState.copyWith(
          messages: [...currentState.messages, message],
        ));

        // 相手からの新着メッセージの場合、未読数を更新
        if (message.senderId != userId) {
          ref.invalidate(unreadMessageCountProvider);
        }
      },
      onUpdate: (message) {
        final currentState = state.valueOrNull;
        if (currentState == null) return;

        final updatedMessages = currentState.messages.map((m) {
          return m.id == message.id ? message : m;
        }).toList();
        state = AsyncData(currentState.copyWith(messages: updatedMessages));
      },
    );
  }
}

/// 未読メッセージ数を取得するProvider
@riverpod
Future<int> unreadMessageCount(UnreadMessageCountRef ref) async {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  if (user == null) return 0;

  final repository = ref.watch(messageRepositoryProvider);
  return repository.getUnreadCount(userId: user.id);
}

/// 特定のメッセージをIDで取得するProvider
@riverpod
Future<Message?> messageById(MessageByIdRef ref, String messageId) async {
  final repository = ref.watch(messageRepositoryProvider);
  return repository.getMessageById(messageId);
}
