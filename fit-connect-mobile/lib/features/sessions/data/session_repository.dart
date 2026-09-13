import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

/// セッション（トレーナーとの予約）の取得を担うRepository。
/// ※ features/schedules（トレーナーの稼働可能時間）とは別ドメイン。
///
/// 「今後 / 過去」の仕分け規則は **終了時刻（session_date + duration_minutes）** の
/// 一本（= SessionModel.isUpcoming）。ステータスでは分けないので、
/// 未来のキャンセル/完了も「今後」に残る（顧客が変更に気付けるようにするため。
/// キャンセルであることの提示はステータスバッジの責務）。
///
/// 顧客は sessions テーブルを直接 SELECT できない（顧客用の SELECT ポリシーを置いていない）。
/// sessions.memo はトレーナーが自分用に書く内輪メモで、行単位の RLS では列を隠せないため、
/// 顧客の読み取りは必要な列だけを返す SECURITY DEFINER 関数 get_my_sessions
/// （auth.uid() 本人のセッションのみ・memo を含まない）に一本化している。
/// テーブル直 SELECT や client_notes との embed に戻すと、エラーにならず
/// 空 / null が返って黙って壊れるので注意。
class SessionRepository {
  /// [client] はテストで偽のサーバーへ向けたクライアントを渡すためのもの（省略時はアプリ共通のクライアント）
  SessionRepository({SupabaseClient? client})
      : _supabase = client ?? SupabaseService.client;

  final SupabaseClient _supabase;

  /// 顧客自身のセッションを返す RPC。引数はすべて省略可で、
  /// p_from（この時刻以降）/ p_before（この時刻より前）/ p_ids（id 指定）で絞れる。
  /// 戻り列は sessions から memo を除いたもの（SessionModel の受け皿と一致）
  static const _sessionsRpc = 'get_my_sessions';

  /// 紐づく共有ノートの取得列（`client_notes` キーとして各セッション行に差し込む）。
  ///
  /// 列は ClientNoteDetailScreen が必要とする全フィールドを揃えてある。
  /// 行タップ時に追加クエリを投げずに詳細を開けるようにするため
  /// （ノートは短文＋添付URLの配列で、一覧の最大50件ぶんでも十分軽い）。
  /// ノート側の見出しに出すセッション日時・種別は、ここでは取らず
  /// 親セッション自身から補う（SessionModel.sharedNotes 参照）。
  static const _noteColumns = 'id, client_id, trainer_id, title, content, '
      'file_urls, is_shared, shared_at, session_id, created_at, updated_at';

  /// サーバ側フィルタに持たせる余裕（＝想定する最長のセッション時間）。
  /// PostgREST は session_date + duration_minutes の計算列で絞り込めないため、
  /// 「開始済みだがまだ終了していない」セッションを取りこぼさないよう、
  /// この分だけ手前から粗く取得し、正確な仕分けはクライアント側で endTime を見て行う。
  static const _maxSessionDuration = Duration(hours: 24);

  /// 今後のセッション一覧を取得（クライアント用）。
  /// 終了時刻が未来のものを開始時刻の昇順で返す。
  ///
  /// RPC 自体が auth.uid() 本人に絞っているので、client_id の一致は念のための明示。
  Future<List<SessionModel>> getUpcomingSessions({
    required String clientId,
  }) async {
    final fromIso =
        DateTime.now().subtract(_maxSessionDuration).toUtc().toIso8601String();

    final response = await _supabase
        .rpc(_sessionsRpc, params: {'p_from': fromIso})
        .eq('client_id', clientId)
        .order('session_date', ascending: true);

    final sessionRows = _rows(response);
    final noteRows = await _fetchSharedNotes(
      clientId: clientId,
      sessionRows: sessionRows,
    );

    return attachSharedNotes(sessionRows, noteRows)
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
        .rpc(_sessionsRpc, params: {'p_before': nowIso})
        .eq('client_id', clientId)
        .order('session_date', ascending: false)
        .limit(50);

    final sessionRows = _rows(response);
    final noteRows = await _fetchSharedNotes(
      clientId: clientId,
      sessionRows: sessionRows,
    );

    return attachSharedNotes(sessionRows, noteRows)
        .where((session) => !session.isUpcoming)
        .toList();
  }

  /// [sessionRows] に紐づく共有ノートを1回のクエリでまとめて取る（セッションごとには投げない）。
  /// セッションが0件なら問い合わせない。
  ///
  /// 顧客向けRLS（clients_select_shared_notes）が
  /// `is_shared = true AND client_id = auth.uid()` なので、ここには
  /// **共有済みノートしか入ってこない**（未共有ノートの存在も漏れない）。
  /// クエリでも is_shared を明示し、念のためクライアント側でも
  /// SessionModel.sharedNotes で is_shared を通す。
  ///
  /// ノートは一覧の行に出す導線のための付加情報なので、取得に失敗しても例外は
  /// 伝播させず「ノートなし」として扱う。ノートを使わないホームの次回セッションカード
  /// まで巻き添えでエラー表示にしないため（ノート自体はカルテ一覧から開ける）。
  Future<List<Map<String, dynamic>>> _fetchSharedNotes({
    required String clientId,
    required List<Map<String, dynamic>> sessionRows,
  }) async {
    final sessionIds = sessionIdsOf(sessionRows);
    if (sessionIds.isEmpty) return const [];

    try {
      final response = await _supabase
          .from('client_notes')
          .select(_noteColumns)
          .eq('client_id', clientId)
          .eq('is_shared', true)
          .inFilter('session_id', sessionIds);
      return _rows(response);
    } catch (e) {
      debugPrint('[SessionRepository] 紐づくノートの取得に失敗（ノート導線なしで表示を継続）: $e');
      return const [];
    }
  }

  /// セッション行の id 一覧（ノート取得の inFilter 用）。重複・欠損は除く
  @visibleForTesting
  static List<String> sessionIdsOf(List<Map<String, dynamic>> sessionRows) =>
      sessionRows.map((row) => row['id']).whereType<String>().toSet().toList();

  /// RPC のセッション行に、別クエリで取った共有ノートを振り分けて SessionModel にする。
  ///
  /// 各行に `client_notes` キーで「session_id が一致するノートの配列」を差し込んでから
  /// SessionModel.fromJson に渡す（SessionModel.notes の JSON 受け皿は embed 時代のまま）。
  /// ノートが無いセッションは空配列になり、どのセッションにも一致しないノート
  /// （session_id が null / 結果に無いセッションを指す）は捨てる。行の順序は保つ
  @visibleForTesting
  static List<SessionModel> attachSharedNotes(
    List<Map<String, dynamic>> sessionRows,
    List<Map<String, dynamic>> noteRows,
  ) {
    final notesBySessionId = <String, List<Map<String, dynamic>>>{};
    for (final note in noteRows) {
      final sessionId = note['session_id'];
      if (sessionId is String) {
        (notesBySessionId[sessionId] ??= []).add(note);
      }
    }

    return [
      for (final row in sessionRows)
        SessionModel.fromJson({
          ...row,
          'client_notes': notesBySessionId[row['id']] ?? const [],
        }),
    ];
  }

  /// PostgREST のレスポンス（JSON 配列）を行の Map のリストにする
  static List<Map<String, dynamic>> _rows(dynamic response) =>
      List<Map<String, dynamic>>.from(response as List);
}
