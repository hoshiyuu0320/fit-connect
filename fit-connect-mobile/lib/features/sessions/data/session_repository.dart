import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

/// セッション（トレーナーとの予約）の取得を担うRepository。
/// ※ features/schedules（トレーナーの稼働可能時間）とは別ドメイン。
///
/// 「今後 / 過去」の仕分け規則は **終了時刻（session_date + duration_minutes）** の
/// 一本（= SessionModel.isUpcoming）。ステータスでは分けないので、
/// 未来のキャンセル/完了も「今後」に残る（顧客が変更に気付けるようにするため。
/// キャンセルであることの提示はステータスバッジの責務）。
class SessionRepository {
  final _supabase = SupabaseService.client;

  /// 取得する列。memo はトレーナーが自分用に書く内輪メモで顧客UIには出さないため、
  /// RLS上は読めても端末には運ばない（`select()` の全列取得をやめて明示除外する）。
  ///
  /// 末尾の `client_notes(...)` は `client_notes.session_id → sessions.id` の
  /// FKを使った embed。顧客向けRLS（clients_select_shared_notes）が
  /// `is_shared = true AND client_id = auth.uid()` なので、ここには
  /// **共有済みノートしか入ってこない**（未共有ノートの存在も漏れない）。
  /// 念のためクライアント側でも SessionModel.sharedNotes で is_shared を通す。
  ///
  /// 列は ClientNoteDetailScreen が必要とする全フィールドを揃えてある。
  /// 行タップ時に追加クエリを投げずに詳細を開けるようにするため
  /// （ノートは短文＋添付URLの配列で、一覧の最大50件ぶんでも十分軽い）。
  /// ノート側の見出しに出すセッション日時・種別は、逆向きの `sessions(...)` を
  /// 入れ子にせず親セッション自身から補う（SessionModel.sharedNotes 参照）。
  static const _columns = 'id, trainer_id, client_id, session_date, '
      'duration_minutes, status, session_type, ticket_id, '
      'recurrence_group_id, created_at, updated_at, '
      'client_notes(id, client_id, trainer_id, title, content, file_urls, '
      'is_shared, shared_at, session_id, created_at, updated_at)';

  /// サーバ側フィルタに持たせる余裕（＝想定する最長のセッション時間）。
  /// PostgREST は session_date + duration_minutes の計算列で絞り込めないため、
  /// 「開始済みだがまだ終了していない」セッションを取りこぼさないよう、
  /// この分だけ手前から粗く取得し、正確な仕分けはクライアント側で endTime を見て行う。
  static const _maxSessionDuration = Duration(hours: 24);

  /// 今後のセッション一覧を取得（クライアント用）。
  /// 終了時刻が未来のものを開始時刻の昇順で返す。
  Future<List<SessionModel>> getUpcomingSessions({
    required String clientId,
  }) async {
    final fromIso =
        DateTime.now().subtract(_maxSessionDuration).toUtc().toIso8601String();

    final response = await _supabase
        .from('sessions')
        .select(_columns)
        .eq('client_id', clientId)
        .gte('session_date', fromIso)
        .order('session_date', ascending: true);

    return (response as List)
        .map((json) => SessionModel.fromJson(json))
        .where((session) => session.isUpcoming)
        .toList();
  }

  /// 過去のセッション一覧を取得（クライアント用）。
  /// getUpcomingSessions の補集合＝終了時刻が過去のものを開始時刻の降順で返す。
  ///
  /// 終了時刻が過去なら開始時刻も必ず過去なので、`session_date < now` が
  /// 過不足のない上位集合になる（開催中のものだけが混ざるので後段で落とす）。
  /// そのため最大件数は50件（開催中を除いた結果としてそれ未満になることがある）。
  Future<List<SessionModel>> getPastSessions({
    required String clientId,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final response = await _supabase
        .from('sessions')
        .select(_columns)
        .eq('client_id', clientId)
        .lt('session_date', nowIso)
        .order('session_date', ascending: false)
        .limit(50);

    return (response as List)
        .map((json) => SessionModel.fromJson(json))
        .where((session) => !session.isUpcoming)
        .toList();
  }
}
