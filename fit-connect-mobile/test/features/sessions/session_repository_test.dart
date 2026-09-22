import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;
import 'package:fit_connect_mobile/features/sessions/data/session_repository.dart';

import '../../shared/fake_supabase_rest_server.dart';

const _clientId = '22222222-2222-2222-2222-222222222222';
const _rpcPath = '/rest/v1/rpc/get_my_sessions';
const _notesPath = '/rest/v1/client_notes';

/// get_my_sessions（RPC）が返すセッション1行。memo は戻り列に無い
Map<String, dynamic> makeSessionRow({
  required String id,
  String sessionDate = '2026-09-10T09:00:00Z',
  String? sessionType = 'パーソナルトレーニング',
}) =>
    {
      'id': id,
      'trainer_id': '11111111-1111-1111-1111-111111111111',
      'client_id': '22222222-2222-2222-2222-222222222222',
      'session_date': sessionDate,
      'duration_minutes': 60,
      'status': 'completed',
      'session_type': sessionType,
      'ticket_id': null,
      'recurrence_group_id': null,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
    };

/// client_notes を session_id の inFilter で別取得したノート1行
Map<String, dynamic> makeNoteRow({
  required String id,
  required String? sessionId,
  String createdAt = '2026-09-10T11:00:00Z',
}) =>
    {
      'id': id,
      'client_id': '22222222-2222-2222-2222-222222222222',
      'trainer_id': '11111111-1111-1111-1111-111111111111',
      'title': 'ノート $id',
      'content': '本日の内容',
      'file_urls': <String>[],
      'is_shared': true,
      'shared_at': createdAt,
      'session_id': sessionId,
      'created_at': createdAt,
      'updated_at': createdAt,
    };

void main() {
  group('SessionRepository.attachSharedNotes', () {
    test('ノートが0件なら全セッションの notes が空になり、行の順序は保たれる', () {
      final sessions = SessionRepository.attachSharedNotes(
        [makeSessionRow(id: 's-2'), makeSessionRow(id: 's-1')],
        [],
      );

      expect(sessions.map((s) => s.id), ['s-2', 's-1']);
      expect(sessions.every((s) => s.notes.isEmpty), isTrue);
      expect(sessions.every((s) => !s.hasSharedNote), isTrue);
    });

    test('ノートを session_id ごとに該当セッションへ振り分ける', () {
      final sessions = SessionRepository.attachSharedNotes(
        [
          makeSessionRow(id: 's-1'),
          makeSessionRow(id: 's-2'),
          makeSessionRow(id: 's-3'),
        ],
        [
          makeNoteRow(id: 'n-1a', sessionId: 's-1'),
          makeNoteRow(id: 'n-2', sessionId: 's-2'),
          makeNoteRow(
            id: 'n-1b',
            sessionId: 's-1',
            createdAt: '2026-09-11T11:00:00Z',
          ),
        ],
      );

      expect(sessions[0].notes.map((n) => n.id), ['n-1a', 'n-1b']);
      expect(sessions[1].notes.map((n) => n.id), ['n-2']);
      // ノートの無いセッションは空（導線を出さない）
      expect(sessions[2].notes, isEmpty);
      expect(sessions[2].hasSharedNote, isFalse);
      // 行から開くのは最新の共有ノート
      expect(sessions[0].sharedNote?.id, 'n-1b');
    });

    test('振り分けたノートには親セッションの日時・種別が補われる', () {
      final sessions = SessionRepository.attachSharedNotes(
        [
          makeSessionRow(
            id: 's-1',
            sessionDate: '2026-09-10T09:00:00Z',
            sessionType: 'ストレッチ',
          ),
        ],
        [makeNoteRow(id: 'n-1', sessionId: 's-1')],
      );

      final note = sessions.single.sharedNote!;
      expect(note.session?.sessionDate.toUtc(), DateTime.utc(2026, 9, 10, 9));
      expect(note.session?.sessionType, 'ストレッチ');
    });

    test('session_id が null のノートはどのセッションにも付かない', () {
      final sessions = SessionRepository.attachSharedNotes(
        [makeSessionRow(id: 's-1')],
        [makeNoteRow(id: 'n-orphan', sessionId: null)],
      );

      expect(sessions.single.notes, isEmpty);
    });

    test('RPC 結果に無いセッションを指すノートは捨てる', () {
      final sessions = SessionRepository.attachSharedNotes(
        [makeSessionRow(id: 's-1')],
        [
          makeNoteRow(id: 'n-1', sessionId: 's-1'),
          makeNoteRow(id: 'n-other', sessionId: 's-not-in-result'),
        ],
      );

      expect(sessions, hasLength(1));
      expect(sessions.single.notes.map((n) => n.id), ['n-1']);
    });

    test('セッションが空なら空リスト（ノートがあっても行は増えない）', () {
      expect(SessionRepository.attachSharedNotes([], []), isEmpty);
      expect(
        SessionRepository.attachSharedNotes(
          [],
          [makeNoteRow(id: 'n-1', sessionId: 's-1')],
        ),
        isEmpty,
      );
    });

    test('入力の行 Map は書き換えない（client_notes キーは付け足さない）', () {
      final sessionRow = makeSessionRow(id: 's-1');
      final noteRow = makeNoteRow(id: 'n-1', sessionId: 's-1');

      SessionRepository.attachSharedNotes([sessionRow], [noteRow]);

      expect(sessionRow.containsKey('client_notes'), isFalse);
      expect(noteRow.containsKey('sessions'), isFalse);
    });
  });

  group('SessionRepository.sessionIdsOf', () {
    test('セッション行の id を重複なく返す', () {
      expect(
        SessionRepository.sessionIdsOf([
          makeSessionRow(id: 's-1'),
          makeSessionRow(id: 's-2'),
          makeSessionRow(id: 's-1'),
        ]),
        ['s-1', 's-2'],
      );
    });

    test('セッションが0件なら空', () {
      expect(SessionRepository.sessionIdsOf([]), isEmpty);
    });
  });

  // 本物の SupabaseClient を偽サーバーへ向け、Repository が組み立てる HTTP リクエストと
  // 応答に対する振る舞いを確かめる（RPC の引数名・絞り込み・並び順の取り違えを検出する）
  group('SessionRepository（偽サーバー経由）', () {
    late FakeSupabaseRestServer server;
    late SupabaseClient client;
    late SessionRepository repository;

    setUp(() async {
      server = await FakeSupabaseRestServer.start();
      client = server.client();
      repository = SessionRepository(client: client);
    });

    tearDown(() async {
      await client.dispose();
      await server.close();
    });

    String isoFromNow(Duration offset) =>
        DateTime.now().add(offset).toUtc().toIso8601String();

    test('getUpcomingSessions: get_my_sessions を p_from だけで呼び、本人・開始時刻の昇順で絞る',
        () async {
      server.respond(_rpcPath, [
        makeSessionRow(
            id: 's-1', sessionDate: isoFromNow(const Duration(days: 1))),
        makeSessionRow(
            id: 's-2', sessionDate: isoFromNow(const Duration(days: 2))),
      ]);
      server.respond(_notesPath, [makeNoteRow(id: 'n-1', sessionId: 's-2')]);

      final before = DateTime.now();
      final sessions =
          await repository.getUpcomingSessions(clientId: _clientId);

      expect(server.requests, hasLength(2));
      final rpc = server.requests[0];
      expect(rpc.method, 'POST');
      expect(rpc.path, _rpcPath);
      // p_from（開催中を取りこぼさないよう 24 時間手前）だけを渡し、p_before / p_ids は渡さない
      final params = rpc.body! as Map<String, dynamic>;
      expect(params.keys, ['p_from']);
      final from = DateTime.parse(params['p_from'] as String);
      expect(
        from.difference(before.subtract(const Duration(hours: 24))).abs(),
        lessThan(const Duration(minutes: 1)),
      );
      expect(rpc.query['client_id'], 'eq.$_clientId');
      expect(rpc.query['order'], startsWith('session_date.asc'));
      expect(rpc.query.containsKey('limit'), isFalse);

      // 紐づく共有ノートは 1 回のクエリで取る（本人・共有済み・結果のセッション id だけ）
      final notes = server.requests[1];
      expect(notes.method, 'GET');
      expect(notes.path, _notesPath);
      expect(notes.query['client_id'], 'eq.$_clientId');
      expect(notes.query['is_shared'], 'eq.true');
      expect(notes.query['session_id'], 'in.("s-1","s-2")');

      expect(sessions.map((s) => s.id), ['s-1', 's-2']);
      expect(sessions[0].hasSharedNote, isFalse);
      expect(sessions[1].sharedNote?.id, 'n-1');
    });

    test('getPastSessions: get_my_sessions を p_before だけで呼び、開始時刻の降順・最大50件で取る',
        () async {
      server.respond(_rpcPath, [
        makeSessionRow(
            id: 's-new', sessionDate: isoFromNow(const Duration(days: -1))),
        makeSessionRow(
            id: 's-old', sessionDate: isoFromNow(const Duration(days: -8))),
      ]);
      server.respond(_notesPath, []);

      final before = DateTime.now();
      final sessions = await repository.getPastSessions(clientId: _clientId);

      final rpc = server.requests.first;
      expect(rpc.path, _rpcPath);
      final params = rpc.body! as Map<String, dynamic>;
      expect(params.keys, ['p_before']);
      final pBefore = DateTime.parse(params['p_before'] as String);
      expect(pBefore.difference(before).abs(),
          lessThan(const Duration(minutes: 1)));
      expect(rpc.query['client_id'], 'eq.$_clientId');
      expect(rpc.query['order'], startsWith('session_date.desc'));
      expect(rpc.query['limit'], '50');

      expect(sessions.map((s) => s.id), ['s-new', 's-old']);
    });

    test('セッションが0件ならノートの問い合わせを投げない', () async {
      server.respond(_rpcPath, []);

      final upcoming =
          await repository.getUpcomingSessions(clientId: _clientId);
      final past = await repository.getPastSessions(clientId: _clientId);

      expect(upcoming, isEmpty);
      expect(past, isEmpty);
      expect(server.requests.map((r) => r.path), [_rpcPath, _rpcPath]);
    });

    test('ノートの取得が 5xx でもセッションは返る（ノート導線なしで表示を継続）', () async {
      server.respond(_rpcPath, [
        makeSessionRow(
            id: 's-1', sessionDate: isoFromNow(const Duration(days: 1))),
      ]);
      server.respond(_notesPath, {'message': 'upstream error'}, status: 503);

      final sessions =
          await repository.getUpcomingSessions(clientId: _clientId);

      expect(sessions.map((s) => s.id), ['s-1']);
      expect(sessions.single.hasSharedNote, isFalse);
    });

    test('get_my_sessions の失敗は呼び出し元へ伝える（エラー表示・リトライに乗せる）', () async {
      server.respond(
        _rpcPath,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
        status: 404,
      );

      await expectLater(
        repository.getUpcomingSessions(clientId: _clientId),
        throwsA(isA<PostgrestException>()),
      );
      // セッションが取れなければノートは問い合わせない
      expect(server.requests.map((r) => r.path), [_rpcPath]);
    });
  });
}
