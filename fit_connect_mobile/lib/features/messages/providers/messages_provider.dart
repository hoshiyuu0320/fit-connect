import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'messages_provider.g.dart';

/// MessageRepositoryのProvider
@riverpod
MessageRepository messageRepository(MessageRepositoryRef ref) {
  return MessageRepository();
}

/// メッセージリストを取得するProvider（リアルタイム）
@riverpod
Stream<List<Message>> messagesStream(MessagesStreamRef ref) {
  final user = ref.watch(authNotifierProvider).valueOrNull;
  final trainerId = ref.watch(currentTrainerIdProvider);

  if (user == null || trainerId == null) {
    return Stream.value([]);
  }

  final repository = ref.watch(messageRepositoryProvider);
  return repository.getMessagesStream(
    userId: user.id,
    otherUserId: trainerId,
  );
}

/// メッセージ送受信を管理するProvider
@riverpod
class MessagesNotifier extends _$MessagesNotifier {
  @override
  Future<List<Message>> build() async {
    final user = ref.watch(authNotifierProvider).valueOrNull;
    final trainerId = ref.watch(currentTrainerIdProvider);

    if (user == null || trainerId == null) return [];

    final repository = ref.watch(messageRepositoryProvider);
    return repository.getMessages(
      userId: user.id,
      otherUserId: trainerId,
    );
  }

  /// メッセージを送信
  Future<void> sendMessage({
    required String content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
  }) async {
    final user = ref.read(authNotifierProvider).valueOrNull;
    final trainerId = ref.read(currentTrainerIdProvider);

    if (user == null || trainerId == null) {
      throw Exception('User or trainer not found');
    }

    final repository = ref.read(messageRepositoryProvider);
    await repository.sendMessage(
      senderId: user.id,
      receiverId: trainerId,
      senderType: 'client',
      receiverType: 'trainer',
      content: content,
      imageUrls: imageUrls,
      tags: tags,
      replyToMessageId: replyToMessageId,
    );

    ref.invalidateSelf();
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
      ref.invalidateSelf();
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
}

/// 未読メッセージ数を取得するProvider
/// messagesStreamProviderを監視し、メッセージ変更時に自動再取得
@riverpod
Future<int> unreadMessageCount(UnreadMessageCountRef ref) async {
  // Supabase Realtimeの変更を監視して未読数を自動更新
  ref.watch(messagesStreamProvider);

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
