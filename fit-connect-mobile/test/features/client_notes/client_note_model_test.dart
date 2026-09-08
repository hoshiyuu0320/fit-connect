import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';

/// ClientNoteRepository の明示列指定で返ってくる1行（`sessions` は付けずに返す）
Map<String, dynamic> makeNoteJson() => {
      'id': 'note-1',
      'client_id': '22222222-2222-2222-2222-222222222222',
      'trainer_id': '11111111-1111-1111-1111-111111111111',
      'title': 'セッションの記録',
      'content': '本日の内容',
      'file_urls': <String>['notes/a.jpg#写真.jpg'],
      'is_shared': true,
      'shared_at': '2026-09-10T11:00:00Z',
      'session_id': '00000000-0000-0000-0000-000000000001',
      'created_at': '2026-09-10T11:00:00Z',
      'updated_at': '2026-09-10T11:00:00Z',
    };

void main() {
  group('ClientNote.fromJson', () {
    test('snake_caseのカラム名を正しくマッピングする', () {
      final note = ClientNote.fromJson(makeNoteJson());

      expect(note.id, 'note-1');
      expect(note.clientId, '22222222-2222-2222-2222-222222222222');
      expect(note.trainerId, '11111111-1111-1111-1111-111111111111');
      expect(note.title, 'セッションの記録');
      expect(note.fileUrls, ['notes/a.jpg#写真.jpg']);
      expect(note.isShared, isTrue);
      expect(note.sharedAt?.toUtc(), DateTime.utc(2026, 9, 10, 11));
      expect(note.sessionId, '00000000-0000-0000-0000-000000000001');
      expect(note.createdAt.toUtc(), DateTime.utc(2026, 9, 10, 11));
    });

    // `client_notes.session_id → sessions.id` の embed（sessions(session_date, session_type)）
    test('embed された sessions を LinkedSession として読む', () {
      final json = makeNoteJson()
        ..['sessions'] = {
          'session_date': '2026-09-10T09:00:00Z',
          'session_type': 'パーソナルトレーニング',
        };

      final note = ClientNote.fromJson(json);

      expect(note.session, isNotNull);
      expect(note.session!.sessionDate.toUtc(), DateTime.utc(2026, 9, 10, 9));
      expect(note.session!.sessionType, 'パーソナルトレーニング');
    });

    test('session_type が null の sessions も読める（種別未設定のセッション）', () {
      final json = makeNoteJson()
        ..['sessions'] = {
          'session_date': '2026-09-10T09:00:00Z',
          'session_type': null,
        };

      final note = ClientNote.fromJson(json);

      expect(note.session?.sessionDate.toUtc(), DateTime.utc(2026, 9, 10, 9));
      expect(note.session?.sessionType, isNull);
    });

    test('sessions キーが無いJSONでも落ちず null になる（embed しない経路）', () {
      final note = ClientNote.fromJson(makeNoteJson());

      // session_id があっても embed していなければ日時は出せない
      expect(note.sessionId, isNotNull);
      expect(note.session, isNull);
    });

    test('session_id が無いノートは sessions も null で返る（紐づけ無し）', () {
      final json = makeNoteJson()
        ..['session_id'] = null
        ..['sessions'] = null;

      final note = ClientNote.fromJson(json);

      expect(note.sessionId, isNull);
      expect(note.session, isNull);
    });

    test('廃止した session_number が混ざっていても無視されて落ちない', () {
      final json = makeNoteJson()..['session_number'] = 3;

      final note = ClientNote.fromJson(json);

      expect(note.id, 'note-1');
      // モデルに持たないので toJson にも出ない
      expect(note.toJson().containsKey('session_number'), isFalse);
    });
  });

  group('ClientNote.withSession', () {
    test('紐づくセッションだけを差し込み、他のフィールドはそのまま', () {
      final original = ClientNote.fromJson(makeNoteJson());
      final linked = LinkedSession(
        sessionDate: DateTime.utc(2026, 9, 10, 9),
        sessionType: 'ストレッチ',
      );

      final note = original.withSession(linked);

      expect(note.session, same(linked));
      expect(note.id, original.id);
      expect(note.clientId, original.clientId);
      expect(note.trainerId, original.trainerId);
      expect(note.title, original.title);
      expect(note.content, original.content);
      expect(note.fileUrls, original.fileUrls);
      expect(note.isShared, original.isShared);
      expect(note.sharedAt, original.sharedAt);
      expect(note.sessionId, original.sessionId);
      expect(note.createdAt, original.createdAt);
      expect(note.updatedAt, original.updatedAt);
      // 元のインスタンスは変わらない
      expect(original.session, isNull);
    });
  });
}
