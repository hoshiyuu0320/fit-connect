import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';

import '../../record_reminders/fake_record_reminder_sync.dart';
import '../messages_test_support.dart';

/// PaginatedMessages.sendMessage が、送れたメッセージのタグを記録のリマインダーへ渡すテスト。
///
/// 送信の本体（sendMessage）は本物を使い、読み込み（build）・リポジトリ・ログイン・
/// 予約し直しを偽物に差し替える（Supabase には出ない）。
class _EmptyMessages extends PaginatedMessages {
  @override
  Future<PaginatedMessagesState> build() async => PaginatedMessagesState.empty;
}

/// 送信だけを扱うリポジトリ（ほかのメソッドは呼ばれない）
class _FakeMessageRepository implements MessageRepository {
  /// 渡すと送信がこの例外で失敗する
  Object? sendError;

  @override
  Future<Message> sendMessage({
    required String senderId,
    required String receiverId,
    required String senderType,
    required String receiverType,
    String? content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    final error = sendError;
    if (error != null) throw error;
    return testMessage(
      id: 'sent-1',
      mine: true,
      content: content ?? '',
      at: DateTime(2026, 11, 7, 19, 30),
      tags: tags,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeMessageRepository repository;
  late FakeRecordReminderSync sync;
  late ProviderContainer container;

  setUp(() async {
    repository = _FakeMessageRepository();
    sync = FakeRecordReminderSync();
    container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith(FakeAuth.new),
      currentTrainerIdProvider.overrideWith((ref) => testTrainerId),
      messageRepositoryProvider.overrideWithValue(repository),
      paginatedMessagesProvider.overrideWith(_EmptyMessages.new),
      recordReminderSyncProvider.overrideWithValue(sync),
    ]);
    addTearDown(container.dispose);
    // autoDispose なので購読して保つ
    container.listen(authNotifierProvider, (_, __) {});
    container.listen(paginatedMessagesProvider, (_, __) {});
    await container.read(authNotifierProvider.future);
    await container.read(paginatedMessagesProvider.future);
  });

  PaginatedMessages notifier() =>
      container.read(paginatedMessagesProvider.notifier);

  test('送れたら、送ったタグを記録のリマインダーへ渡す', () async {
    await notifier().sendMessage(
      content: '#食事:夕食 カレーライス',
      tags: ['#食事:夕食'],
    );

    expect(sync.sentTags, [
      ['#食事:夕食'],
    ]);
    // 送ったメッセージは画面にも出ている（これまでどおり）
    expect(
      container.read(paginatedMessagesProvider).requireValue.messages.single.id,
      'sent-1',
    );
  });

  test('タグなしで送ったときは、空のタグを渡す（何も推定しない）', () async {
    await notifier().sendMessage(content: 'こんにちは');

    expect(sync.sentTags, [<String>[]]);
  });

  test('送れなかったら渡さない（例外はそのまま投げる）', () async {
    repository.sendError = Exception('network');

    await expectLater(
      notifier().sendMessage(content: '#体重 62.4kg', tags: ['#体重']),
      throwsException,
    );

    expect(sync.sentTags, isEmpty);
    expect(sync.log, isEmpty);
  });
}
