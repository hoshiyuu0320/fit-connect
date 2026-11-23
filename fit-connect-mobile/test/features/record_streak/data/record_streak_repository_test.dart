import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'package:fit_connect_mobile/features/record_streak/data/record_streak_repository.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';

import '../../../shared/fake_supabase_rest_server.dart';

const _clientId = '22222222-2222-2222-2222-222222222222';
const _rpcPath = '/rest/v1/rpc/get_record_streak';

/// get_record_streak（RETURNS TABLE）が返す 1 行
Map<String, dynamic> _row({
  String asOfDate = '2026-11-23',
  bool recordedToday = false,
  int streakUntilYesterday = 12,
}) =>
    {
      'as_of_date': asOfDate,
      'recorded_today': recordedToday,
      'streak_until_yesterday': streakUntilYesterday,
    };

void main() {
  // 本物の SupabaseClient を偽サーバーへ向け、関数名・引数名の取り違えと、応答への振る舞いを確かめる
  group('RecordStreakRepository（偽サーバー経由）', () {
    late FakeSupabaseRestServer server;
    late SupabaseClient client;
    late RecordStreakRepository repository;

    setUp(() async {
      server = await FakeSupabaseRestServer.start();
      client = server.client();
      repository = RecordStreakRepository(client);
    });

    tearDown(() async {
      await client.dispose();
      await server.close();
    });

    test('get_record_streak を p_client_id だけで呼び、行を RecordStreakStatus にする',
        () async {
      server.respond(_rpcPath, [_row()]);

      final status = await repository.fetch(_clientId);

      expect(server.requests, hasLength(1));
      final rpc = server.requests.single;
      expect(rpc.method, 'POST');
      expect(rpc.path, _rpcPath);
      expect(rpc.body, {'p_client_id': _clientId});
      // 絞り込み・並び順・件数は付けない（関数が 1 行だけ返す）
      expect(rpc.query, isEmpty);

      expect(
        status,
        const RecordStreakStatus(
          asOfDate: '2026-11-23',
          recordedToday: false,
          streakUntilYesterday: 12,
        ),
      );
    });

    test('行が複数あれば 1 行目を読む', () async {
      server.respond(_rpcPath, [
        _row(recordedToday: true, streakUntilYesterday: 3),
        _row(asOfDate: '2026-11-22', streakUntilYesterday: 99),
      ]);

      final status = await repository.fetch(_clientId);

      expect(
        status,
        const RecordStreakStatus(
          asOfDate: '2026-11-23',
          recordedToday: true,
          streakUntilYesterday: 3,
        ),
      );
    });

    test('行が無ければ StateError（関数は必ず 1 行返すので、壊れた応答として扱う）', () async {
      server.respond(_rpcPath, []);

      await expectLater(repository.fetch(_clientId), throwsStateError);
    });

    test('関数のエラー（まだ関数が無い DB など）は呼び出し元へ伝える（ホームは行を出さない）', () async {
      server.respond(
        _rpcPath,
        {'code': 'PGRST202', 'message': 'Could not find the function'},
        status: 404,
      );

      await expectLater(
        repository.fetch(_clientId),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
