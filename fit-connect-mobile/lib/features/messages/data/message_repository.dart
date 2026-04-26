import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageRepository {
  final _supabase = SupabaseService.client;

  /// メッセージを取得（トレーナーとのやり取り）
  Future<List<Message>> getMessages({
    required String userId,
    required String otherUserId,
    int? limit,
  }) async {
    var query = _supabase
        .from('messages')
        .select()
        .or('sender_id.eq.$userId,receiver_id.eq.$userId')
        .or('sender_id.eq.$otherUserId,receiver_id.eq.$otherUserId')
        .order('created_at', ascending: false);

    if (limit != null) {
      query = query.limit(limit);
    }

    final response = await query;
    final messages =
        (response as List).map((json) => Message.fromJson(json)).toList();

    // 時系列順にソート（古い順）
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// ページネーション付きメッセージ取得（cursor-based）
  Future<List<Message>> fetchMessages({
    required String userId,
    required String otherUserId,
    int limit = 30,
    DateTime? before,
  }) async {
    var query = _supabase.from('messages').select().or(
        'and(sender_id.eq.$userId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$userId)');

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final response =
        await query.order('created_at', ascending: false).limit(limit);
    final messages =
        (response as List).map((json) => Message.fromJson(json)).toList();

    // 時系列順にソート（古い順）
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  /// Realtime channel購読
  RealtimeChannel subscribeToMessages({
    required String userId,
    required String otherUserId,
    required void Function(Message message) onInsert,
    required void Function(Message message) onUpdate,
  }) {
    final channel = _supabase.channel('messages:$userId:$otherUserId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final message = Message.fromJson(payload.newRecord);
            // 該当する会話ペアのメッセージのみ処理
            if ((message.senderId == userId &&
                    message.receiverId == otherUserId) ||
                (message.senderId == otherUserId &&
                    message.receiverId == userId)) {
              onInsert(message);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final message = Message.fromJson(payload.newRecord);
            if ((message.senderId == userId &&
                    message.receiverId == otherUserId) ||
                (message.senderId == otherUserId &&
                    message.receiverId == userId)) {
              onUpdate(message);
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// メッセージを送信
  Future<Message> sendMessage({
    required String senderId,
    required String receiverId,
    required String senderType,
    required String receiverType,
    String? content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
  }) async {
    final response = await _supabase
        .from('messages')
        .insert({
          'sender_id': senderId,
          'receiver_id': receiverId,
          'sender_type': senderType,
          'receiver_type': receiverType,
          'content': content,
          'image_urls': imageUrls,
          'tags': tags,
          'reply_to_message_id': replyToMessageId,
          'is_edited': false,
        })
        .select()
        .single();

    return Message.fromJson(response);
  }

  /// メッセージを編集（5分以内）
  Future<Message?> editMessage({
    required String messageId,
    required String newContent,
    List<String>? newTags,
  }) async {
    // 編集可能かチェック
    final canEdit = await _supabase.rpc('can_edit_message', params: {
      'message_id': messageId,
    });

    if (canEdit != true) {
      return null; // 編集期限切れ
    }

    final response = await _supabase
        .from('messages')
        .update({
          'content': newContent,
          'tags': newTags,
          'is_edited': true,
          'edited_at': DateTime.now().toIso8601String(),
        })
        .eq('id', messageId)
        .select()
        .single();

    return Message.fromJson(response);
  }

  /// 会話単位でメッセージを既読にする（SECURITY DEFINER関数経由）
  Future<void> markConversationAsRead(String otherUserId) async {
    await _supabase.rpc('mark_messages_as_read', params: {
      'p_other_user_id': otherUserId,
    });
  }

  /// 未読メッセージ数を取得
  Future<int> getUnreadCount({
    required String userId,
  }) async {
    final response = await _supabase
        .from('messages')
        .select('id')
        .eq('receiver_id', userId)
        .isFilter('read_at', null);

    return (response as List).length;
  }

  /// メッセージを削除
  Future<void> deleteMessage(String messageId) async {
    await _supabase.from('messages').delete().eq('id', messageId);
  }

  /// IDでメッセージを取得
  Future<Message?> getMessageById(String messageId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('id', messageId)
          .maybeSingle();

      if (response == null) return null;
      return Message.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
