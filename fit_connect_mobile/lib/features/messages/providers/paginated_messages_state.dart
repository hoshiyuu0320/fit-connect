import 'package:fit_connect_mobile/features/messages/models/message_model.dart';

class PaginatedMessagesState {
  final List<Message> messages; // 時系列順（古→新）
  final bool hasMore; // 追加ロード可能か
  final bool isLoadingMore; // 追加ロード中か

  const PaginatedMessagesState({
    required this.messages,
    required this.hasMore,
    required this.isLoadingMore,
  });

  PaginatedMessagesState copyWith({
    List<Message>? messages,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return PaginatedMessagesState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  static const empty = PaginatedMessagesState(
    messages: [],
    hasMore: true,
    isLoadingMore: false,
  );
}
