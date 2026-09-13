import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class ClientNoteRepository {
  /// [client] はテストで偽のサーバーへ向けたクライアントを渡すためのもの（省略時はアプリ共通のクライアント）
  ClientNoteRepository({SupabaseClient? client})
      : _supabase = client ?? SupabaseService.client;

  final SupabaseClient _supabase;

  /// 一覧で取得する列。
  ///
  /// `select()` の全列取得をやめて明示指定にしているのは、廃止した session_number
  /// （DROP 済み）のような列変更で取得が壊れないようにするため。
  ///
  /// 紐づくセッションの日時・種別は `sessions(...)` の embed では取らない。
  /// 顧客は sessions テーブルを直接 SELECT できず（memo を隠すため顧客用の
  /// SELECT ポリシーを置いていない）、embed は**エラーにならず null になるだけ**なので、
  /// getSharedNotes で get_my_sessions を別に呼んで補う
  static const _columns =
      'id, client_id, trainer_id, title, content, file_urls, '
      'is_shared, shared_at, session_id, created_at, updated_at';

  /// 顧客自身のセッションを必要な列だけ返す RPC（SessionRepository と同じ関数）
  static const _sessionsRpc = 'get_my_sessions';

  /// RPC の戻りから取る列。見出しに要る2列と、ノートへ振り分けるための id だけ
  static const _sessionColumns = 'id, session_date, session_type';

  /// 共有済みカルテ一覧を取得（クライアント用）。
  ///
  /// 一覧・詳細の見出しに要る紐づくセッションの日時・種別は、ノート取得後に
  /// get_my_sessions を1回だけ呼んで各ノートへ差し込む（attachLinkedSessions）
  Future<List<ClientNote>> getSharedNotes({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select(_columns)
        .eq('client_id', clientId)
        .eq('is_shared', true)
        .order('created_at', ascending: false);

    final noteRows = _rows(response);
    final sessionRows =
        await _fetchLinkedSessions(linkedSessionIdsOf(noteRows));

    return attachLinkedSessions(noteRows, sessionRows);
  }

  /// 共有済みカルテ件数を取得（Home画面サマリー用、将来実装）
  Future<int> getSharedNotesCount({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select('id')
        .eq('client_id', clientId)
        .eq('is_shared', true);

    return (response as List).length;
  }

  /// ノートが指すセッションの日時・種別を get_my_sessions でまとめて取る。
  /// 紐づけのあるノートが無ければ問い合わせない。
  ///
  /// get_my_sessions は必要な列だけを返す SECURITY DEFINER 関数で、auth.uid() 本人の
  /// セッションだけに絞る（他人のセッション id を渡しても返らない）。
  ///
  /// 失敗しても例外は伝播させず「セッション情報なし」として扱う。見出しの日時は
  /// 補助情報で、無くても日時なしの見出しになるだけでノートの閲覧は続けられるため
  /// （ノート本体の取得失敗は従来どおり呼び出し元へ伝播する）
  Future<List<Map<String, dynamic>>> _fetchLinkedSessions(
    List<String> sessionIds,
  ) async {
    if (sessionIds.isEmpty) return const [];

    try {
      final response = await _supabase.rpc(_sessionsRpc,
          params: {'p_ids': sessionIds}).select(_sessionColumns);
      return _rows(response);
    } catch (e) {
      debugPrint('[ClientNoteRepository] 紐づくセッションの取得に失敗（日時なしで表示を継続）: $e');
      return const [];
    }
  }

  /// ノート行が指す session_id の一覧（RPC の p_ids 用）。null・重複は除く
  @visibleForTesting
  static List<String> linkedSessionIdsOf(List<Map<String, dynamic>> noteRows) =>
      noteRows
          .map((row) => row['session_id'])
          .whereType<String>()
          .toSet()
          .toList();

  /// ノート行に、RPC で取ったセッションの日時・種別を差し込んで ClientNote にする。
  ///
  /// 各行に `sessions` キーで `{session_date, session_type}` を入れてから
  /// ClientNote.fromJson に渡す（LinkedSession の JSON 受け皿は embed 時代のまま）。
  /// session_id が null のノートや、RPC 結果に無いセッションを指すノートは
  /// `sessions` が null になり、見出しは日時なしで出る。行の順序は保つ
  @visibleForTesting
  static List<ClientNote> attachLinkedSessions(
    List<Map<String, dynamic>> noteRows,
    List<Map<String, dynamic>> sessionRows,
  ) {
    final sessionsById = <String, Map<String, dynamic>>{};
    for (final row in sessionRows) {
      final id = row['id'];
      // session_date は LinkedSession の必須項目。欠けた行で一覧ごと落とさない
      if (id is String && row['session_date'] is String) {
        sessionsById[id] = {
          'session_date': row['session_date'],
          'session_type': row['session_type'],
        };
      }
    }

    return [
      for (final row in noteRows)
        ClientNote.fromJson({
          ...row,
          'sessions': sessionsById[row['session_id']],
        }),
    ];
  }

  /// PostgREST のレスポンス（JSON 配列）を行の Map のリストにする
  static List<Map<String, dynamic>> _rows(dynamic response) =>
      List<Map<String, dynamic>>.from(response as List);
}
