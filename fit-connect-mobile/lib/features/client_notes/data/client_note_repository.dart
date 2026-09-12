import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class ClientNoteRepository {
  final _supabase = SupabaseService.client;

  /// 一覧で取得する列。
  ///
  /// 末尾の `sessions(...)` は `client_notes.session_id → sessions.id` のFKを使った
  /// embed（受け皿は ClientNote.session）。顧客用RLS（sessions_client_select:
  /// `client_id = auth.uid()`）で自分のセッションは読めるので、一覧・詳細の
  /// 見出しに要る日時と種別だけを一緒に取る。session_id が null のノートでは
  /// `sessions` も null で返る。
  ///
  /// `select()` の全列取得をやめて明示指定にしているのは、embed を足すためと、
  /// 廃止した session_number（DROP 済み）のような列変更で取得が壊れないようにするため
  static const _columns =
      'id, client_id, trainer_id, title, content, file_urls, '
      'is_shared, shared_at, session_id, created_at, updated_at, '
      'sessions(session_date, session_type)';

  /// 共有済みカルテ一覧を取得（クライアント用）
  Future<List<ClientNote>> getSharedNotes({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select(_columns)
        .eq('client_id', clientId)
        .eq('is_shared', true)
        .order('created_at', ascending: false);

    return (response as List).map((json) => ClientNote.fromJson(json)).toList();
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
}
