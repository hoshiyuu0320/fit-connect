import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;
import 'package:fit_connect_mobile/features/client_notes/data/client_note_repository.dart';

import '../../shared/fake_supabase_rest_server.dart';

const _clientId = '22222222-2222-2222-2222-222222222222';
const _notesPath = '/rest/v1/client_notes';
const _rpcPath = '/rest/v1/rpc/get_my_sessions';

/// ClientNoteRepository の明示列指定で返ってくるノート1行（`sessions` は付かない）
Map<String, dynamic> makeNoteRow({
  required String id,
  required String? sessionId,
}) =>
    {
      'id': id,
      'client_id': '22222222-2222-2222-2222-222222222222',
      'trainer_id': '11111111-1111-1111-1111-111111111111',
      'title': 'ノート $id',
      'content': '本日の内容',
      'file_urls': <String>[],
      'is_shared': true,
      'shared_at': '2026-09-10T11:00:00Z',
      'session_id': sessionId,
      'created_at': '2026-09-10T11:00:00Z',
      'updated_at': '2026-09-10T11:00:00Z',
    };

/// get_my_sessions(p_ids) を select('id, session_date, session_type') で絞った1行
Map<String, dynamic> makeSessionRow({
  required String id,
  String sessionDate = '2026-09-10T09:00:00Z',
  String? sessionType = 'パーソナルトレーニング',
}) =>
    {
      'id': id,
      'session_date': sessionDate,
      'session_type': sessionType,
    };

void main() {
  group('ClientNoteRepository.attachLinkedSessions', () {
    test('ノートが0件なら空リスト', () {
      expect(
        ClientNoteRepository.attachLinkedSessions(
          [],
          [makeSessionRow(id: 's-1')],
        ),
        isEmpty,
      );
    });

    test('各ノートに session_id が一致するセッションの日時・種別を差し込む', () {
      final notes = ClientNoteRepository.attachLinkedSessions(
        [
          makeNoteRow(id: 'n-1', sessionId: 's-1'),
          makeNoteRow(id: 'n-2', sessionId: 's-2'),
          makeNoteRow(id: 'n-3', sessionId: 's-1'),
        ],
        [
          makeSessionRow(
            id: 's-1',
            sessionDate: '2026-09-10T09:00:00Z',
            sessionType: 'ストレッチ',
          ),
          makeSessionRow(
            id: 's-2',
            sessionDate: '2026-09-12T01:30:00Z',
            sessionType: null,
          ),
        ],
      );

      // 行の順序（created_at 降順で取ったまま）は保つ
      expect(notes.map((n) => n.id), ['n-1', 'n-2', 'n-3']);

      expect(
          notes[0].session?.sessionDate.toUtc(), DateTime.utc(2026, 9, 10, 9));
      expect(notes[0].session?.sessionType, 'ストレッチ');
      // 種別未設定のセッションも日時は出せる
      expect(notes[1].session?.sessionDate.toUtc(),
          DateTime.utc(2026, 9, 12, 1, 30));
      expect(notes[1].session?.sessionType, isNull);
      // 同じセッションを指す複数ノートにはそれぞれ入る
      expect(notes[2].session?.sessionType, 'ストレッチ');
    });

    test('session_id が null のノートは session も null（紐づけ無し）', () {
      final notes = ClientNoteRepository.attachLinkedSessions(
        [makeNoteRow(id: 'n-1', sessionId: null)],
        [makeSessionRow(id: 's-1')],
      );

      expect(notes.single.sessionId, isNull);
      expect(notes.single.session, isNull);
    });

    test('RPC 結果に無いセッションを指すノートは session が null（ノート自体は残す）', () {
      final notes = ClientNoteRepository.attachLinkedSessions(
        [
          makeNoteRow(id: 'n-1', sessionId: 's-1'),
          makeNoteRow(id: 'n-2', sessionId: 's-not-in-result'),
        ],
        [makeSessionRow(id: 's-1')],
      );

      expect(notes, hasLength(2));
      expect(notes[0].session, isNotNull);
      // sessionId は保ったまま、日時だけ出せない
      expect(notes[1].sessionId, 's-not-in-result');
      expect(notes[1].session, isNull);
    });

    test('セッションが空（RPC 失敗時など）でもノートは全件そのまま返る', () {
      final notes = ClientNoteRepository.attachLinkedSessions(
        [
          makeNoteRow(id: 'n-1', sessionId: 's-1'),
          makeNoteRow(id: 'n-2', sessionId: null),
        ],
        [],
      );

      expect(notes.map((n) => n.id), ['n-1', 'n-2']);
      expect(notes.every((n) => n.session == null), isTrue);
    });

    test('session_date の欠けたセッション行は無視し、一覧ごと落とさない', () {
      final notes = ClientNoteRepository.attachLinkedSessions(
        [makeNoteRow(id: 'n-1', sessionId: 's-1')],
        [
          {'id': 's-1', 'session_date': null, 'session_type': 'ストレッチ'},
        ],
      );

      expect(notes.single.id, 'n-1');
      expect(notes.single.session, isNull);
    });

    test('入力の行 Map は書き換えない（sessions キーは付け足さない）', () {
      final noteRow = makeNoteRow(id: 'n-1', sessionId: 's-1');

      ClientNoteRepository.attachLinkedSessions(
        [noteRow],
        [makeSessionRow(id: 's-1')],
      );

      expect(noteRow.containsKey('sessions'), isFalse);
    });
  });

  group('ClientNoteRepository.linkedSessionIdsOf', () {
    test('session_id を null を除き重複なく返す', () {
      expect(
        ClientNoteRepository.linkedSessionIdsOf([
          makeNoteRow(id: 'n-1', sessionId: 's-1'),
          makeNoteRow(id: 'n-2', sessionId: null),
          makeNoteRow(id: 'n-3', sessionId: 's-2'),
          makeNoteRow(id: 'n-4', sessionId: 's-1'),
        ]),
        ['s-1', 's-2'],
      );
    });

    test('紐づけのあるノートが無ければ空', () {
      expect(ClientNoteRepository.linkedSessionIdsOf([]), isEmpty);
      expect(
        ClientNoteRepository.linkedSessionIdsOf([
          makeNoteRow(id: 'n-1', sessionId: null),
        ]),
        isEmpty,
      );
    });
  });

  // 本物の SupabaseClient を偽サーバーへ向け、Repository が組み立てる HTTP リクエストと
  // 応答に対する振る舞いを確かめる（RPC の引数名・絞り込みの取り違えを検出する）
  group('ClientNoteRepository.getSharedNotes（偽サーバー経由）', () {
    late FakeSupabaseRestServer server;
    late SupabaseClient client;
    late ClientNoteRepository repository;

    setUp(() async {
      server = await FakeSupabaseRestServer.start();
      client = server.client();
      repository = ClientNoteRepository(client: client);
    });

    tearDown(() async {
      await client.dispose();
      await server.close();
    });

    test('共有済みノートを取り、紐づくセッションを get_my_sessions(p_ids) で1回だけ引いて差し込む', () async {
      server.respond(_notesPath, [
        makeNoteRow(id: 'n-1', sessionId: 's-1'),
        makeNoteRow(id: 'n-2', sessionId: null),
        makeNoteRow(id: 'n-3', sessionId: 's-2'),
        makeNoteRow(id: 'n-4', sessionId: 's-1'),
      ]);
      server.respond(_rpcPath, [
        makeSessionRow(
            id: 's-1',
            sessionDate: '2026-09-10T09:00:00Z',
            sessionType: 'ストレッチ'),
        makeSessionRow(id: 's-2', sessionDate: '2026-09-12T01:30:00Z'),
      ]);

      final notes = await repository.getSharedNotes(clientId: _clientId);

      expect(server.requests, hasLength(2));
      final noteRequest = server.requests[0];
      expect(noteRequest.method, 'GET');
      expect(noteRequest.path, _notesPath);
      expect(noteRequest.query['client_id'], 'eq.$_clientId');
      expect(noteRequest.query['is_shared'], 'eq.true');
      expect(noteRequest.query['order'], startsWith('created_at.desc'));
      // sessions(...) の embed はしない（顧客は sessions を直接読めず、embed は黙って null になる）
      expect(noteRequest.query['select'], isNot(contains('sessions')));

      final rpc = server.requests[1];
      expect(rpc.method, 'POST');
      expect(rpc.path, _rpcPath);
      // p_ids だけを渡す（null を除き重複なし）。戻りは見出しに要る列だけに絞る
      expect(rpc.body, {
        'p_ids': ['s-1', 's-2'],
      });
      expect(rpc.query['select'], 'id,session_date,session_type');

      expect(notes.map((n) => n.id), ['n-1', 'n-2', 'n-3', 'n-4']);
      expect(notes[0].session?.sessionType, 'ストレッチ');
      expect(notes[1].session, isNull);
      expect(notes[2].session?.sessionDate.toUtc(),
          DateTime.utc(2026, 9, 12, 1, 30));
      expect(notes[3].session?.sessionType, 'ストレッチ');
    });

    test('紐づけのあるノートが無ければ get_my_sessions を呼ばない', () async {
      server.respond(_notesPath, [makeNoteRow(id: 'n-1', sessionId: null)]);

      final notes = await repository.getSharedNotes(clientId: _clientId);

      expect(notes.single.id, 'n-1');
      expect(server.requests.map((r) => r.path), [_notesPath]);
    });

    test('get_my_sessions が 5xx でもノートは全件返る（見出しは日時なし）', () async {
      server.respond(_notesPath, [makeNoteRow(id: 'n-1', sessionId: 's-1')]);
      server.respond(_rpcPath, {'message': 'upstream error'}, status: 503);

      final notes = await repository.getSharedNotes(clientId: _clientId);

      expect(notes.single.id, 'n-1');
      expect(notes.single.sessionId, 's-1');
      expect(notes.single.session, isNull);
    });

    test('ノート本体の取得失敗は呼び出し元へ伝える', () async {
      server.respond(
        _notesPath,
        {'code': '42501', 'message': 'permission denied'},
        status: 403,
      );

      await expectLater(
        repository.getSharedNotes(clientId: _clientId),
        throwsA(isA<PostgrestException>()),
      );
      expect(server.requests.map((r) => r.path), [_notesPath]);
    });
  });
}
