import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/home/providers/latest_trainer_comment_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';

import 'home_test_support.dart';

/// 取得の呼び出しだけを記録するリポジトリ（Supabase に出ない・Realtime を張らない）。
/// `fetchMessages` 以外を呼ぶとテストが落ちる（`noSuchMethod`）。
class _FakeMessageRepository implements MessageRepository {
  _FakeMessageRepository(this.all, {this.fail = false});

  /// 会話の全メッセージ（古い順）
  final List<Message> all;
  final bool fail;
  final List<({int limit, DateTime? before})> calls = [];

  @override
  Future<List<Message>> fetchMessages({
    required String userId,
    required String otherUserId,
    int limit = 30,
    DateTime? before,
  }) async {
    calls.add((limit: limit, before: before));
    if (fail) throw StateError('failed to fetch');
    final older = before == null
        ? all
        : all.where((m) => m.createdAt.isBefore(before)).toList();
    // 新しいほうから limit 件を、古い順で返す（本物と同じ）
    final page = older.length <= limit
        ? older
        : older.sublist(older.length - limit);
    return [...page];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} は呼ばれないはず');
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<supabase.User?> build() async => const supabase.User(
        id: 'client-1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );
}

class _SignedOutAuth extends AuthNotifier {
  @override
  Future<supabase.User?> build() async => null;
}

void main() {
  final base = DateTime(2026, 9, 13, 9, 0);
  Message m(
    String id,
    String sender,
    int minutes, {
    String content = 'メッセージ',
    List<String>? tags,
    String? replyTo,
  }) =>
      sampleMessage(
        id: id,
        sender: sender,
        content: content,
        at: base.add(Duration(minutes: minutes)),
        tags: tags,
        replyTo: replyTo,
      );

  // 未読数（新着のきっかけ）をテストから動かすための状態
  final unread = StateProvider<int>((ref) => 0);

  ProviderContainer containerFor(
    _FakeMessageRepository repo, {
    Client? client,
    bool signedOut = false,
    bool noClient = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => signedOut ? _SignedOutAuth() : _FakeAuth(),
        ),
        currentClientProvider.overrideWith(
          (ref) async => noClient ? null : (client ?? sampleClient()),
        ),
        messageRepositoryProvider.overrideWithValue(repo),
        unreadMessageCountProvider.overrideWith((ref) async => ref.watch(unread)),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose なので、読む間は購読して生かしておく（画面が watch している状態）
    container.listen(latestTrainerCommentProvider, (_, __) {});
    return container;
  }

  group('latestTrainerCommentProvider', () {
    test('トレーナーの最新メッセージと、返信先の記録の種別を返す', () async {
      final repo = _FakeMessageRepository([
        m('c1', 'client', 0, content: '朝食です', tags: ['#食事:朝食']),
        m('t1', 'trainer', 10, content: 'いいですね', replyTo: 'c1'),
        m('c2', 'client', 20, content: 'ありがとうございます'),
      ]);
      final container = containerFor(repo);

      final result = await container.read(latestTrainerCommentProvider.future);

      expect(result, isNotNull);
      expect(result!.message.id, 't1');
      expect(result.recordLabel, '朝食');
      expect(result.body, 'いいですね');
    });

    test('メッセージが無ければ null（エラーではない）', () async {
      final container = containerFor(_FakeMessageRepository([]));

      final result = await container.read(latestTrainerCommentProvider.future);

      expect(result, isNull);
    });

    test('トレーナーのメッセージが無ければ null', () async {
      final container = containerFor(
        _FakeMessageRepository([m('c1', 'client', 0), m('c2', 'client', 5)]),
      );

      expect(await container.read(latestTrainerCommentProvider.future), isNull);
    });

    test('取得に失敗したら AsyncError', () async {
      final container = containerFor(_FakeMessageRepository([], fail: true));

      await expectLater(
        container.read(latestTrainerCommentProvider.future),
        throwsA(isA<StateError>()),
      );
      expect(container.read(latestTrainerCommentProvider).hasError, isTrue);
    });

    test('サインアウト中・クライアント情報が無いときは取得に出ず null', () async {
      final repo = _FakeMessageRepository([m('t1', 'trainer', 0)]);

      final signedOut = containerFor(repo, signedOut: true);
      expect(await signedOut.read(latestTrainerCommentProvider.future), isNull);
      final noClient = containerFor(repo, noClient: true);
      expect(await noClient.read(latestTrainerCommentProvider.future), isNull);
      expect(repo.calls, isEmpty);
    });

    test('ホーム用の取得は 1 回だけ（最新ページにトレーナーが居れば遡らない）', () async {
      final repo = _FakeMessageRepository([
        m('t1', 'trainer', 0),
        m('c1', 'client', 5),
      ]);
      final container = containerFor(repo);

      await container.read(latestTrainerCommentProvider.future);

      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.limit, 30);
      expect(repo.calls.single.before, isNull);
    });
  });

  group('latestTrainerCommentProvider 更新のきっかけ', () {
    test('未読数が変わったら取り直す。最初の読み込み完了では取り直さない', () async {
      final repo = _FakeMessageRepository([m('t1', 'trainer', 0)]);
      final container = containerFor(repo);

      await container.read(latestTrainerCommentProvider.future);
      await container.read(unreadMessageCountProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(repo.calls, hasLength(1));

      // 新着（未読数 0 → 1）
      container.read(unread.notifier).state = 1;
      await container.read(unreadMessageCountProvider.future);
      await Future<void>.delayed(Duration.zero);
      await container.read(latestTrainerCommentProvider.future);

      expect(repo.calls, hasLength(2));
    });
  });

  group('fetchLatestTrainerComment', () {
    test('自分のメッセージが 1 ページ以上続いても、遡ってトレーナーの最新を探す', () async {
      final repo = _FakeMessageRepository([
        m('t-old', 'trainer', 0, content: '前のコメント'),
        for (var i = 0; i < 40; i++) m('c$i', 'client', 10 + i),
      ]);

      final result = await fetchLatestTrainerComment(
        repository: repo,
        userId: 'client-1',
        trainerId: 'trainer-1',
      );

      expect(result!.message.id, 't-old');
      expect(repo.calls, hasLength(2));
      expect(repo.calls[1].before, isNotNull);
    });

    test('遡るのは最大 maxPages まで。見つからなければ null', () async {
      final repo = _FakeMessageRepository([
        for (var i = 0; i < 100; i++) m('c$i', 'client', i),
      ]);

      final result = await fetchLatestTrainerComment(
        repository: repo,
        userId: 'client-1',
        trainerId: 'trainer-1',
        pageSize: 10,
        maxPages: 3,
      );

      expect(result, isNull);
      expect(repo.calls, hasLength(3));
    });

    test('ページに満たなければそれ以上は遡らない', () async {
      final repo = _FakeMessageRepository([m('c1', 'client', 0)]);

      final result = await fetchLatestTrainerComment(
        repository: repo,
        userId: 'client-1',
        trainerId: 'trainer-1',
      );

      expect(result, isNull);
      expect(repo.calls, hasLength(1));
    });
  });
}
