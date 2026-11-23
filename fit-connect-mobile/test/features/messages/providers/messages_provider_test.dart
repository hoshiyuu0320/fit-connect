import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/features/record_streak/providers/record_streak_provider.dart';

import '../../record_reminders/fake_record_reminder_sync.dart';
import '../messages_test_support.dart';

/// 端末の今の時刻（記録の連続の先取りが、送ってからの時間を数える起点）。日本時間 11-23 23:59:50
final _deviceNow = DateTime.parse('2026-11-23T23:59:50+09:00');

/// サーバーが付けた送信時刻（messages.created_at）。端末の時計より 15 秒進んでいて、日本時間ではもう 11-24
final _serverCreatedAt = DateTime.parse('2026-11-24T00:00:05+09:00');

/// PaginatedMessages.sendMessage が、送れたメッセージのタグを記録のリマインダーと
/// 記録の連続の先取りへ渡すテスト。
///
/// 送信の本体（sendMessage）は本物を使い、読み込み（build）・リポジトリ・ログイン・
/// 予約し直し・端末の時計を偽物に差し替える（Supabase には出ない）。
class _EmptyMessages extends PaginatedMessages {
  @override
  Future<PaginatedMessagesState> build() async => PaginatedMessagesState.empty;
}

/// 送信だけを扱うリポジトリ（ほかのメソッドは呼ばれない）。
/// 送れたメッセージの送信時刻（created_at）は [_serverCreatedAt]
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
      at: _serverCreatedAt,
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
      currentClientIdProvider.overrideWith((ref) => testClientId),
      messageRepositoryProvider.overrideWithValue(repository),
      paginatedMessagesProvider.overrideWith(_EmptyMessages.new),
      recordReminderSyncProvider.overrideWithValue(sync),
      recordStreakTagOverlayProvider
          .overrideWith(() => RecordStreakTagOverlay(now: () => _deviceNow)),
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
    expect(container.read(recordStreakTagOverlayProvider), isNull);
  });

  group('記録の連続の先取り', () {
    test('送れたら、記録になるタグなら (今のクライアント, サーバーの送信時刻の日本時間の日付, 端末の今の時刻) を覚える',
        () async {
      await notifier().sendMessage(
        content: '#体重 62.4kg',
        tags: ['#体重'],
      );

      // 日付は端末の時計（まだ 11-23）でなく、サーバーの送信時刻（もう 11-24）で決まる
      expect(
        container.read(recordStreakTagOverlayProvider),
        (clientId: testClientId, jstDateKey: '2026-11-24', sentAt: _deviceNow),
      );
    });

    test('リマインダーでは対象外の #食事:間食 も、記録になるので覚える', () async {
      await notifier().sendMessage(
        content: '#食事:間食 りんご',
        tags: ['#食事:間食'],
      );

      expect(
        container.read(recordStreakTagOverlayProvider),
        (clientId: testClientId, jstDateKey: '2026-11-24', sentAt: _deviceNow),
      );
    });

    test('タグなし・記録にならないタグなら覚えない', () async {
      await notifier().sendMessage(content: 'こんにちは');
      await notifier().sendMessage(content: 'メモ', tags: ['#メモ', '#体重']);

      expect(container.read(recordStreakTagOverlayProvider), isNull);
    });
  });
}
