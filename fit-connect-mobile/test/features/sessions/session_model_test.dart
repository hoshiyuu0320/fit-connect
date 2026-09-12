import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';

/// テスト用のSessionModelを組み立てるヘルパー
SessionModel makeSession({
  required DateTime sessionDate,
  int durationMinutes = 60,
  String status = 'scheduled',
  List<ClientNote> notes = const [],
}) {
  final createdAt = DateTime.utc(2026, 9, 1);
  return SessionModel(
    id: '00000000-0000-0000-0000-000000000001',
    trainerId: '11111111-1111-1111-1111-111111111111',
    clientId: '22222222-2222-2222-2222-222222222222',
    sessionDate: sessionDate,
    durationMinutes: durationMinutes,
    status: status,
    notes: notes,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

/// embed で返ってくるノート1件を組み立てるヘルパー
ClientNote makeNote({
  required String id,
  required bool isShared,
  required DateTime createdAt,
}) {
  return ClientNote(
    id: id,
    clientId: '22222222-2222-2222-2222-222222222222',
    trainerId: '11111111-1111-1111-1111-111111111111',
    title: 'ノート $id',
    content: '内容',
    isShared: isShared,
    sharedAt: isShared ? createdAt : null,
    sessionId: '00000000-0000-0000-0000-000000000001',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

void main() {
  group('SessionStatus', () {
    test('4値の日本語ラベルを返す', () {
      expect(SessionStatus.scheduled.labelJa, '予定');
      expect(SessionStatus.confirmed.labelJa, '確定');
      expect(SessionStatus.completed.labelJa, '完了');
      expect(SessionStatus.cancelled.labelJa, 'キャンセル');
    });

    test('DB値とenum名が一致している', () {
      expect(SessionStatus.scheduled.name, 'scheduled');
      expect(SessionStatus.confirmed.name, 'confirmed');
      expect(SessionStatus.completed.name, 'completed');
      expect(SessionStatus.cancelled.name, 'cancelled');
    });

    test('tryParseは未知の値でも例外を投げずnullを返す', () {
      expect(SessionStatus.tryParse('confirmed'), SessionStatus.confirmed);
      expect(SessionStatus.tryParse('no_show'), isNull);
      expect(SessionStatus.tryParse(''), isNull);
      expect(SessionStatus.tryParse(null), isNull);
    });

    test('isClosedは完了/キャンセルのみtrue', () {
      expect(SessionStatus.completed.isClosed, isTrue);
      expect(SessionStatus.cancelled.isClosed, isTrue);
      expect(SessionStatus.scheduled.isClosed, isFalse);
      expect(SessionStatus.confirmed.isClosed, isFalse);
    });
  });

  group('SessionModel.statusLabel', () {
    test('既知のステータスは日本語ラベルになる', () {
      expect(
        makeSession(sessionDate: DateTime.utc(2026, 9, 10), status: 'completed')
            .statusLabel,
        '完了',
      );
    });

    test('未知のステータスは生値にフォールバックし落ちない', () {
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10),
        status: 'no_show',
      );
      expect(session.statusType, isNull);
      expect(session.statusLabel, 'no_show');
    });
  });

  group('SessionModel.endTime', () {
    test('開始時刻に所要時間を足した時刻を返す', () {
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9, 0),
        durationMinutes: 90,
      );
      expect(session.endTime, DateTime.utc(2026, 9, 10, 10, 30));
    });

    test('日付をまたぐ場合も正しく計算される', () {
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10, 23, 30),
        durationMinutes: 60,
      );
      expect(session.endTime, DateTime.utc(2026, 9, 11, 0, 30));
    });
  });

  group('SessionModel.isClosed', () {
    test('完了/キャンセルはtrue、予定/確定はfalse', () {
      final date = DateTime.now();
      expect(
          makeSession(sessionDate: date, status: 'completed').isClosed, isTrue);
      expect(
          makeSession(sessionDate: date, status: 'cancelled').isClosed, isTrue);
      expect(makeSession(sessionDate: date, status: 'scheduled').isClosed,
          isFalse);
      expect(makeSession(sessionDate: date, status: 'confirmed').isClosed,
          isFalse);
    });

    test('未知のステータスは「まだ生きている予定」側に倒れる', () {
      expect(
        makeSession(sessionDate: DateTime.now(), status: 'no_show').isClosed,
        isFalse,
      );
    });
  });

  // 仕分け規則: 「今後 / 過去」は終了時刻（session_date + duration_minutes）で分ける。
  // ステータスでは分けない（未来のキャンセル済みも「今後」に残す）
  group('SessionModel.isUpcoming', () {
    test('開始済みでも終了前ならtrue（セッション中に一覧から消えない）', () {
      // 18:00開始60分を18:01に見た状況＝開始1分後・終了59分前
      final started = makeSession(
        sessionDate: DateTime.now().subtract(const Duration(minutes: 1)),
        durationMinutes: 60,
      );
      expect(started.isUpcoming, isTrue);
    });

    test('終了時刻を過ぎたらfalse', () {
      final finished = makeSession(
        sessionDate: DateTime.now().subtract(const Duration(minutes: 61)),
        durationMinutes: 60,
      );
      expect(finished.isUpcoming, isFalse);
    });

    test('未来ならステータスに関わらずtrue（キャンセル/完了も「今後」に残す）', () {
      final future = DateTime.now().add(const Duration(days: 3));
      for (final status in [
        'scheduled',
        'confirmed',
        'cancelled',
        'completed',
        'no_show'
      ]) {
        expect(
          makeSession(sessionDate: future, status: status).isUpcoming,
          isTrue,
          reason: 'status=$status は未来なので「今後」',
        );
      }
    });

    test('過去ならステータスに関わらずfalse', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      for (final status in [
        'scheduled',
        'confirmed',
        'cancelled',
        'completed',
        'no_show'
      ]) {
        expect(
          makeSession(sessionDate: past, status: status).isUpcoming,
          isFalse,
          reason: 'status=$status は過去なので「過去」',
        );
      }
    });
  });

  group('SessionModel.isToday / isTomorrow / daysUntil', () {
    test('現在時刻のセッションは今日扱い', () {
      final session = makeSession(sessionDate: DateTime.now());
      expect(session.daysUntil, 0);
      expect(session.isToday, isTrue);
      expect(session.isTomorrow, isFalse);
    });

    test('24時間後のセッションは明日扱い', () {
      final session =
          makeSession(sessionDate: DateTime.now().add(const Duration(days: 1)));
      expect(session.daysUntil, 1);
      expect(session.isToday, isFalse);
      expect(session.isTomorrow, isTrue);
    });

    test('過去のセッションのdaysUntilは負値', () {
      final session = makeSession(
        sessionDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(session.daysUntil, -2);
      expect(session.isToday, isFalse);
    });

    test('daysUntilFromは基準時刻を指定できる（UIは now を1回だけ引いて渡す）', () {
      final session = makeSession(sessionDate: DateTime.utc(2026, 9, 10, 3, 0));

      // 同じセッションでも基準時刻が変われば日数が変わる
      expect(session.daysUntilFrom(DateTime.utc(2026, 9, 8, 3, 0)), 2);
      expect(session.daysUntilFrom(DateTime.utc(2026, 9, 10, 1, 0)), 0);
      expect(session.daysUntilFrom(DateTime.utc(2026, 9, 12, 3, 0)), -2);
    });

    test('端末のタイムゾーンに関わらずJSTの暦日で区切られる', () {
      // 14:00Z = JST 23:00（同日） / 15:00Z = JST 翌00:00 で暦日が1日ずれる
      final beforeJstMidnight =
          makeSession(sessionDate: DateTime.utc(2026, 9, 10, 14, 0));
      final afterJstMidnight =
          makeSession(sessionDate: DateTime.utc(2026, 9, 10, 15, 0));
      expect(
        afterJstMidnight.daysUntil - beforeJstMidnight.daysUntil,
        1,
      );
    });
  });

  group('SessionModel.fromJson', () {
    test('snake_caseのカラム名を正しくマッピングする', () {
      final json = {
        'id': '00000000-0000-0000-0000-000000000001',
        'trainer_id': '11111111-1111-1111-1111-111111111111',
        'client_id': '22222222-2222-2222-2222-222222222222',
        'session_date': '2026-09-10T09:00:00Z',
        'duration_minutes': 90,
        'status': 'confirmed',
        'session_type': 'パーソナルトレーニング',
        // memo は取得しない列だが、混ざっていても無視されて落ちないこと
        'memo': '肩の可動域を確認',
        'ticket_id': null,
        'recurrence_group_id': '33333333-3333-3333-3333-333333333333',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      };

      final session = SessionModel.fromJson(json);

      expect(session.trainerId, '11111111-1111-1111-1111-111111111111');
      expect(session.clientId, '22222222-2222-2222-2222-222222222222');
      expect(session.sessionDate.toUtc(), DateTime.utc(2026, 9, 10, 9, 0));
      expect(session.durationMinutes, 90);
      expect(session.statusType, SessionStatus.confirmed);
      expect(session.statusLabel, '確定');
      expect(session.sessionType, 'パーソナルトレーニング');
      expect(session.ticketId, isNull);
      // memo はモデルに持たないので toJson にも出ない
      expect(session.toJson().containsKey('memo'), isFalse);
      expect(
        session.recurrenceGroupId,
        '33333333-3333-3333-3333-333333333333',
      );
      expect(session.endTime.toUtc(), DateTime.utc(2026, 9, 10, 10, 30));
    });

    test('client_notes が無いJSONでも空リストになる（embedしない経路）', () {
      final json = {
        'id': '00000000-0000-0000-0000-000000000001',
        'trainer_id': '11111111-1111-1111-1111-111111111111',
        'client_id': '22222222-2222-2222-2222-222222222222',
        'session_date': '2026-09-10T09:00:00Z',
        'duration_minutes': 60,
        'status': 'scheduled',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      };

      final session = SessionModel.fromJson(json);

      expect(session.notes, isEmpty);
      expect(session.sharedNote, isNull);
      expect(session.hasSharedNote, isFalse);
    });

    test('embedされた client_notes を ClientNote として読む', () {
      final json = {
        'id': '00000000-0000-0000-0000-000000000001',
        'trainer_id': '11111111-1111-1111-1111-111111111111',
        'client_id': '22222222-2222-2222-2222-222222222222',
        'session_date': '2026-09-10T09:00:00Z',
        'duration_minutes': 60,
        'status': 'completed',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
        'client_notes': [
          {
            'id': 'note-1',
            'client_id': '22222222-2222-2222-2222-222222222222',
            'trainer_id': '11111111-1111-1111-1111-111111111111',
            'title': '第3回セッションの記録',
            'content': '本日の内容',
            'file_urls': <String>[],
            'is_shared': true,
            'shared_at': '2026-09-10T11:00:00Z',
            'session_id': '00000000-0000-0000-0000-000000000001',
            'created_at': '2026-09-10T11:00:00Z',
            'updated_at': '2026-09-10T11:00:00Z',
          },
        ],
      };

      final session = SessionModel.fromJson(json);

      expect(session.notes, hasLength(1));
      expect(session.sharedNote?.id, 'note-1');
      expect(
        session.sharedNote?.sessionId,
        '00000000-0000-0000-0000-000000000001',
      );
      // 逆向きの sessions(...) は embed しないので生の受け皿は null のまま
      expect(session.notes.single.session, isNull);
    });

    test('廃止した session_number が混ざっていても無視されて落ちない', () {
      final json = {
        'id': '00000000-0000-0000-0000-000000000001',
        'trainer_id': '11111111-1111-1111-1111-111111111111',
        'client_id': '22222222-2222-2222-2222-222222222222',
        'session_date': '2026-09-10T09:00:00Z',
        'duration_minutes': 60,
        'status': 'completed',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
        'client_notes': [
          {
            'id': 'note-1',
            'client_id': '22222222-2222-2222-2222-222222222222',
            'trainer_id': '11111111-1111-1111-1111-111111111111',
            'title': '記録',
            'content': '本日の内容',
            'file_urls': <String>[],
            'is_shared': true,
            'shared_at': '2026-09-10T11:00:00Z',
            'session_id': '00000000-0000-0000-0000-000000000001',
            'session_number': 3,
            'created_at': '2026-09-10T11:00:00Z',
            'updated_at': '2026-09-10T11:00:00Z',
          },
        ],
      };

      final session = SessionModel.fromJson(json);

      expect(session.sharedNote?.id, 'note-1');
      expect(
        session.sharedNote?.toJson().containsKey('session_number'),
        isFalse,
      );
    });
  });

  group('SessionModel.asLinkedSession', () {
    test('自身の日時・種別だけを抜き出す', () {
      final session = SessionModel(
        id: '00000000-0000-0000-0000-000000000001',
        trainerId: '11111111-1111-1111-1111-111111111111',
        clientId: '22222222-2222-2222-2222-222222222222',
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        durationMinutes: 60,
        status: 'completed',
        sessionType: 'パーソナルトレーニング',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      final linked = session.asLinkedSession;
      expect(linked.sessionDate, DateTime.utc(2026, 9, 10, 9));
      expect(linked.sessionType, 'パーソナルトレーニング');
    });
  });

  group('SessionModel.sharedNotes', () {
    test('未共有ノートは混ざっていても除外される', () {
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        notes: [
          makeNote(
            id: 'private',
            isShared: false,
            createdAt: DateTime.utc(2026, 9, 11),
          ),
        ],
      );

      expect(session.notes, hasLength(1));
      expect(session.sharedNotes, isEmpty);
      expect(session.sharedNote, isNull);
      expect(session.hasSharedNote, isFalse);
    });

    test('複数の共有ノートがあれば最新の1件を返す', () {
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        notes: [
          makeNote(
            id: 'old',
            isShared: true,
            createdAt: DateTime.utc(2026, 9, 10),
          ),
          makeNote(
            id: 'newest',
            isShared: true,
            createdAt: DateTime.utc(2026, 9, 12),
          ),
          // 未共有は新しくても選ばれない
          makeNote(
            id: 'private',
            isShared: false,
            createdAt: DateTime.utc(2026, 9, 13),
          ),
        ],
      );

      expect(session.sharedNotes.map((note) => note.id), ['newest', 'old']);
      expect(session.sharedNote?.id, 'newest');
      expect(session.hasSharedNote, isTrue);
    });

    // sessions → client_notes の embed には逆向きの sessions(...) が入らないため、
    // 親セッションの日時・種別を補ってから返す（カルテ詳細のヘッダー表示用）
    test('ノートの session には親セッションの日時・種別が補われる', () {
      final session = SessionModel(
        id: '00000000-0000-0000-0000-000000000001',
        trainerId: '11111111-1111-1111-1111-111111111111',
        clientId: '22222222-2222-2222-2222-222222222222',
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        durationMinutes: 60,
        status: 'completed',
        sessionType: 'ストレッチ',
        notes: [
          makeNote(
            id: 'note-1',
            isShared: true,
            createdAt: DateTime.utc(2026, 9, 10, 11),
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      // 生の受け皿は null のまま（補完は getter 側で行い、元データは触らない）
      expect(session.notes.single.session, isNull);

      final note = session.sharedNote!;
      expect(note.session?.sessionDate, DateTime.utc(2026, 9, 10, 9));
      expect(note.session?.sessionType, 'ストレッチ');
      // 他のフィールドは元のまま
      expect(note.id, 'note-1');
      expect(note.sessionId, '00000000-0000-0000-0000-000000000001');
      expect(note.isShared, isTrue);
    });

    test('既に session が入っているノートは上書きしない', () {
      final embedded = LinkedSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        sessionType: 'embed済み',
      );
      final session = makeSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        notes: [
          makeNote(
            id: 'note-1',
            isShared: true,
            createdAt: DateTime.utc(2026, 9, 10, 11),
          ).withSession(embedded),
        ],
      );

      expect(session.sharedNote?.session, same(embedded));
    });
  });
}
