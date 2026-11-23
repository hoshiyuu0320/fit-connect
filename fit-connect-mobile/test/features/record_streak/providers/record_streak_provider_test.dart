import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/record_streak/data/record_streak_repository.dart';
import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';
import 'package:fit_connect_mobile/features/record_streak/providers/record_streak_provider.dart';

import '../fake_record_streak_repository.dart';

const _clientA = 'client-a';
const _clientB = 'client-b';

/// DB の今日（get_record_streak の as_of_date）
const _dbToday = '2026-11-23';

/// 日本時間の日時 [local]（'2026-11-23T08:00:00' など）の瞬間
DateTime _jst(String local) => DateTime.parse('$local+09:00');

/// 送った時刻（端末の時計の既定。サーバーの送信時刻も、渡さなければこれと同じ）
final _sentAt = _jst('2026-11-23T08:00:00');

/// ログイン中のクライアント（テストで切り替える。null はログアウト）
final _signedInClientId = StateProvider<String?>((ref) => _clientA);

RecordStreakStatus _status({
  String asOfDate = _dbToday,
  bool recordedToday = false,
  int untilYesterday = 0,
}) =>
    RecordStreakStatus(
      asOfDate: asOfDate,
      recordedToday: recordedToday,
      streakUntilYesterday: untilYesterday,
    );

void main() {
  late FakeRecordStreakRepository repository;

  /// 端末の今の時刻（先取りが、送ってからの時間を数える時計）
  late DateTime deviceNow;
  late ProviderContainer container;

  setUp(() {
    repository = FakeRecordStreakRepository()
      // A は昨日まで 12 日続いていて、今日はまだ。B は続いていない
      ..results[_clientA] = _status(untilYesterday: 12)
      ..results[_clientB] = _status();
    deviceNow = _sentAt;
    container = ProviderContainer(overrides: [
      currentClientIdProvider
          .overrideWith((ref) => ref.watch(_signedInClientId)),
      recordStreakRepositoryProvider.overrideWithValue(repository),
      recordStreakTagOverlayProvider
          .overrideWith(() => RecordStreakTagOverlay(now: () => deviceNow)),
    ]);
    addTearDown(container.dispose);
  });

  /// ホームの行が見ている間（購読している間）だけ、自動破棄の provider が生きている
  ProviderSubscription<AsyncValue<RecordStreakView?>> showHome() =>
      container.listen(recordStreakViewProvider, (_, __) {});

  /// DB の取得が終わるまで進めて、ホームに出す状態を返す
  Future<AsyncValue<RecordStreakView?>> settledView() async {
    await container.read(recordStreakProvider.future);
    return container.read(recordStreakViewProvider);
  }

  void signInAs(String? clientId) =>
      container.read(_signedInClientId.notifier).state = clientId;

  /// メッセージを送れたことにする（PaginatedMessages.sendMessage と同じ呼び方）。
  /// [createdAt] はサーバーが付けた送信時刻（既定は端末の今の時刻と同じ）
  void send(List<String> tags, {DateTime? createdAt}) => container
      .read(recordStreakTagOverlayProvider.notifier)
      .onMessageSent(tags, createdAt: createdAt ?? deviceNow);

  group('recordStreakProvider', () {
    test('ログインしていなければ null（取得しない）。ホームの状態は AsyncData(null)', () async {
      signInAs(null);
      showHome();

      expect(await container.read(recordStreakProvider.future), isNull);
      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(null),
      );
      expect(repository.fetchedClientIds, isEmpty);
    });

    test('ログイン中は、今のクライアントで取得する', () async {
      showHome();

      expect(
        await container.read(recordStreakProvider.future),
        _status(untilYesterday: 12),
      );
      expect(repository.fetchedClientIds, [_clientA]);
      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('invalidate で取り直す（前面に戻ったとき・目覚めの評価を付けたとき）', () async {
      showHome();
      await settledView();
      expect(repository.fetchedClientIds, [_clientA]);

      // ほかの画面・端末で記録した
      repository.results[_clientA] =
          _status(recordedToday: true, untilYesterday: 12);
      container.invalidate(recordStreakProvider);

      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
      expect(repository.fetchedClientIds, [_clientA, _clientA]);
    });

    test('ホームを離れると破棄され、戻ると取り直す（自動破棄）', () async {
      final home = showHome();
      await settledView();

      home.close();
      await container.pump();
      expect(container.exists(recordStreakProvider), isFalse);
      expect(container.exists(recordStreakViewProvider), isFalse);

      showHome();
      await settledView();
      expect(repository.fetchedClientIds, [_clientA, _clientA]);
    });
  });

  group('recordStreakViewProvider', () {
    test('読み込み中は AsyncLoading、読めたらデータ', () async {
      final gate = repository.gate = Completer<void>();
      showHome();

      final loading = container.read(recordStreakViewProvider);
      expect(loading, isA<AsyncLoading<RecordStreakView?>>());
      expect(loading.hasValue, isFalse);

      gate.complete();
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('読めなければ AsyncError（ホームは行を出さない）', () async {
      repository.error = Exception('offline');
      showHome();

      await expectLater(
        container.read(recordStreakProvider.future),
        throwsException,
      );
      final view = container.read(recordStreakViewProvider);
      expect(view, isA<AsyncError<RecordStreakView?>>());
      expect(view.error, isA<Exception>());
      expect(view.hasValue, isFalse);
    });

    test('読み直し（invalidate）の間は前の値のまま（isRefreshing。when はデータ側）', () async {
      showHome();
      await settledView();

      final gate = repository.gate = Completer<void>();
      repository.results[_clientA] =
          _status(recordedToday: true, untilYesterday: 12);
      container.invalidate(recordStreakProvider);

      final refreshing = container.read(recordStreakViewProvider);
      expect(refreshing.isRefreshing, isTrue);
      expect(refreshing.valueOrNull, const RecordStreakAlive(days: 12));
      expect(
        refreshing.when(
          data: (_) => 'data',
          loading: () => 'loading',
          error: (_, __) => 'error',
        ),
        'data',
      );

      gate.complete();
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
    });
  });

  group('送ったタグの先取り（RecordStreakTagOverlay）', () {
    test('記録になるタグを送ると、取り直さずに今日記録済みになる（同じクライアント・DB の今日と同じ日・送ってすぐ）', () async {
      showHome();
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );

      send(['#体重']);

      expect(
        container.read(recordStreakTagOverlayProvider),
        (clientId: _clientA, jstDateKey: _dbToday, sentAt: _sentAt),
      );
      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
      // DB はまだ記録なし（取り直していない）
      expect(repository.fetchedClientIds, [_clientA]);
    });

    test('続いていない人が送ると 1 日目になる', () async {
      signInAs(_clientB);
      showHome();
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakNone()),
      );

      send(['#食事:間食']);

      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 1)),
      );
    });

    test('記録にならないタグ・タグなしでは何もしない（最初のタグだけを見る）', () async {
      showHome();
      await settledView();

      for (final tags in [
        <String>[],
        ['#メモ'],
        [' #体重'],
        ['#体重 '],
        ['#メモ', '#体重'],
        ['#meal'],
      ]) {
        send(tags);
        expect(
          container.read(recordStreakTagOverlayProvider),
          isNull,
          reason: '$tags',
        );
      }
      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('ログインしていないときに送っても覚えない', () {
      signInAs(null);

      send(['#体重']);

      expect(container.read(recordStreakTagOverlayProvider), isNull);
    });

    test('日付はサーバーの送信時刻（日本時間）で決める。端末の時計が遅れていても、記録と同じ日になる', () async {
      // 端末の時計は 15 秒遅れていて、まだ前の日の 23:59:50。サーバーの送信時刻はもう 11-23
      deviceNow = _jst('2026-11-22T23:59:50');
      showHome();
      await settledView();

      send(['#体重'], createdAt: _jst('2026-11-23T00:00:05'));

      expect(
        container.read(recordStreakTagOverlayProvider),
        (clientId: _clientA, jstDateKey: _dbToday, sentAt: deviceNow),
      );
      expect(
        container.read(recordStreakViewProvider),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
    });

    test('0 時の直前に送り、0 時を過ぎて DB の今日が次の日になると、前の日の先取りは効かない（60 秒以内でも）', () async {
      deviceNow = _jst('2026-11-23T23:59:58');
      showHome();
      await settledView();
      send(['#体重']);
      expect(
        container.read(recordStreakViewProvider).valueOrNull,
        const RecordStreakRecordedToday(days: 13),
      );

      // 5 秒後に読み直すと、DB の今日はもう次の日（記録は作られて、昨日までが 13 日になった。今日はまだ）
      deviceNow = _jst('2026-11-24T00:00:03');
      repository.results[_clientA] =
          _status(asOfDate: '2026-11-24', untilYesterday: 13);
      container.invalidate(recordStreakProvider);

      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 13)),
      );
    });

    test('別のクライアントの先取りは効かない（ログアウトしても消さず、client id で区別する）', () async {
      showHome();
      await settledView();
      send(['#運動:完了']);
      expect(
        container.read(recordStreakViewProvider).valueOrNull,
        const RecordStreakRecordedToday(days: 13),
      );

      // ログアウト → 行は出ない（null）
      signInAs(null);
      expect(await settledView(), const AsyncData<RecordStreakView?>(null));

      // 別の人でログイン → A の先取りは効かない
      signInAs(_clientB);
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakNone()),
      );
      expect(repository.fetchedClientIds, [_clientA, _clientB]);

      // 送ってから 60 秒のうちに A で入り直すと、A の先取りはまだ効く
      signInAs(_clientA);
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
    });

    test('送ってからちょうど 60 秒までは、ホームを離れて戻っても今日記録済み（DB にまだ記録が無くても）', () async {
      final home = showHome();
      await settledView();
      send(['#食事:夕食']);

      home.close();
      await container.pump();
      expect(container.exists(recordStreakProvider), isFalse);

      deviceNow = _sentAt.add(RecordStreakTagOverlay.window);
      showHome();
      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 13)),
      );
      expect(repository.fetchedClientIds, [_clientA, _clientA]);
    });

    test('60 秒を過ぎたら DB の値だけを見る（タグが記録にならなかった・タグを消す編集をしたときは、読み直せば元に戻る）',
        () async {
      showHome();
      await settledView();
      // サーバーが記録にしないタグ（全角の数字など。アプリでは見分けない）
      send(['#体重']);
      expect(
        container.read(recordStreakViewProvider).valueOrNull,
        const RecordStreakRecordedToday(days: 13),
      );

      // 60 秒を過ぎてから読み直す（前面に戻った）。DB に今日の記録は無いまま
      deviceNow = _sentAt.add(
        RecordStreakTagOverlay.window + const Duration(milliseconds: 1),
      );
      container.invalidate(recordStreakProvider);

      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('60 秒を過ぎてからホームを開いても効かない（ホームを離れていた間に過ぎた）', () async {
      final home = showHome();
      await settledView();
      send(['#運動']);
      home.close();
      await container.pump();

      deviceNow = _sentAt.add(const Duration(minutes: 5));
      showHome();

      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('端末の時計が送った時刻より前に戻っていたら効かない（時計を動かした）', () async {
      showHome();
      await settledView();
      send(['#体重']);

      deviceNow = _sentAt.subtract(const Duration(seconds: 1));
      container.invalidate(recordStreakProvider);

      expect(
        await settledView(),
        const AsyncData<RecordStreakView?>(RecordStreakAlive(days: 12)),
      );
    });

    test('RecordStreakTagOverlay.window は 60 秒', () {
      expect(RecordStreakTagOverlay.window, const Duration(seconds: 60));
    });
  });
}
