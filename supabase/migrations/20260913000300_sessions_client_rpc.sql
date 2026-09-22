-- =============================================================================
-- Migration: sessions_client_rpc
-- sessions.memo の顧客非公開化（フェーズ8.4）その1: 顧客の読み取り用に、列の許可リスト関数
-- get_my_sessions() を追加する。顧客用 SELECT ポリシー sessions_client_select の撤去は
-- 次の 20260913000400_sessions_drop_client_select.sql で行う（2本に分けた理由は下の「適用順」）
--
-- 仕様出典: docs/tasks/IMPLEMENTATION_TASKS.md 8.4 / docs/tasks/lessons.md（2026-09-13）
--
-- 背景（memo の露出）:
--   - 20260906000000 で追加した顧客用 SELECT ポリシー sessions_client_select
--     （TO authenticated USING client_id = auth.uid()）は行単位の制御で、列を絞れない。
--     そのため顧客は、アプリが取得・表示していなくても PostgREST を直接叩けば
--     （例: GET /rest/v1/sessions?select=memo）トレーナーの内輪メモ memo まで読めた
--     （20260906000000 の【要検討】で予見していた問題。本番の memo 記入が 0 件の段階で発見）
--   - オーナー決定: memo は顧客から見えなくする
--   - 列単位 GRANT では解決できない。Web のトレーナーも顧客と同じ authenticated ロールで
--     接続しており、memo の SELECT を剥がすとトレーナー側の参照まで巻き添えで壊れる
--
-- 方針:
--   1. 顧客の読み取りは SECURITY DEFINER 関数 get_my_sessions() に一本化する。
--      戻り列は RETURNS TABLE で固定した許可リストで、memo は含めない。
--      今後 sessions に列が増えても、この関数を書き換えない限り顧客には出ない
--   2. 顧客用 SELECT ポリシー sessions_client_select は DROP する（20260913000400）。
--      顧客がテーブルを直接読む経路そのものを無くし、memo を読む手段を残さない
--   3. トレーナー用4本（"Trainers can view/insert/update/delete their own sessions"）と
--      GRANT には一切触れない（Web 側の挙動は変わらない）
--
-- 適用順（関数の追加とポリシーの撤去を別 migration に分けている理由）:
--   - 旧 Mobile ビルドは sessions を直接読み（SessionRepository の from('sessions') と、
--     ClientNoteRepository の sessions(...) embed）、新ビルドは get_my_sessions を呼ぶ。
--     1本にまとめると、先に適用すれば旧ビルドが（エラーにならず）空表示になり、
--     後に適用すれば新ビルドが関数なし（PGRST202）でエラー表示になる。どちらのビルドも動く
--     期間を作れない。強制アップデート（app_config.min_supported_version）はビルド番号を
--     見ないため、pubspec の version を上げない限り新旧を区別できない
--   - そこで ① 本 migration（関数の追加のみ。ポリシーは残るので旧ビルドもそのまま動く）を
--     リモートへ適用 → ② get_my_sessions を使う Mobile ビルドを行き渡らせる（リモートを向けた
--     新ビルドの QA もここで行う）→ ③ 20260913000400（ポリシーの撤去）を適用、の順にする。
--     ②〜③の間は memo が顧客から読める状態が続くため、③は②の直後に適用すること
--     （2026-09-13 時点で本番の memo 記入は 0 件）
--   - supabase db push は未適用の migration を全部まとめて適用するので、段階を踏むときは
--     1本ずつ適用すること
--
-- なぜビューではなく関数か:
--   - SECURITY DEFINER ビュー（Postgres のビューの既定 = security_invoker 無し）は
--     定義者権限で RLS を跨ぐので、列を絞りつつ client_id = auth.uid() で行を絞る形は作れる。
--     しかし単一テーブルの単純なビューは「自動更新可能ビュー」になり、authenticated に
--     書込権限が残っているとビュー経由の INSERT / UPDATE / DELETE も定義者権限で実行され、
--     sessions の RLS をすり抜けて書き込めてしまう（書込バイパス）。GRANT を SELECT だけに
--     絞っても、将来の GRANT ALL の一括付与などで容易に再発する
--   - Supabase Advisor が 0010_security_definer_view を ERROR として報告する
--   - security_invoker = true のビューは呼び出し者の RLS がそのまま効くため、顧客用の
--     SELECT ポリシーが結局必要になり、テーブル直読みで memo が漏れる元の形に戻る
--   → 関数なら書込の経路がそもそも存在せず、戻り列も型付きで固定できる
--
-- 影響範囲（2026-09-13 ローカル実測）:
--   - sessions を参照する他の関数は enforce_client_note_session_consistency() と
--     find_sessions_for_reminder(date) の2つで、どちらも SECURITY DEFINER のため影響なし。
--     sessions を参照する他テーブルの RLS ポリシー・ビューは無い
--   - Web はトレーナー本人（トレーナー用ポリシー）か supabaseAdmin で sessions を読むため影響なし
--   - 本 migration は関数を足すだけなので、既存の読み取りは何も変わらない。
--     Mobile（顧客）の sessions 直読みが 0 行 / null になるのは 20260913000400 の適用後
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. get_my_sessions(p_from, p_before, p_ids)
--    呼び出したユーザー本人（auth.uid()）が顧客のセッションだけを、許可リストの列で返す。
--    Mobile（顧客）がセッション一覧・ノート見出しの取得に RPC で呼ぶ。
--
--    - 本人の判定は client_id = auth.uid() 固定。引数で他人を指す余地は無く、
--      p_from / p_before / p_ids は「自分のセッションの中での」絞り込みに限る
--      （p_ids に他人のセッション ID を混ぜても、その行は返らない）
--    - p_from は以上（>=）、p_before は未満（<）の半開区間。NULL の引数は条件を掛けない。
--      p_ids に空配列を渡すと 0 行（NULL とは区別する）
--    - 並び順・件数は呼び出し側（PostgREST の order / limit クエリパラメータ）に任せる。
--      SET 句付きの SQL 関数はインライン展開されないため、order / limit は関数の結果に
--      後から掛かる。日付の絞り込みは p_from / p_before で関数内に渡すこと
--      （idx_sessions_client_id / idx_sessions_session_date が効く）
--    - トレーナーが呼んでも自分が顧客のセッションは無いので 0 行（トレーナーはテーブルを
--      トレーナー用ポリシーで直接読む）。service_role には既定権限で EXECUTE が残るが、
--      sub の無い呼び出しでは auth.uid() が NULL となり 0 行
--
--    SECURITY DEFINER の理由:
--      顧客用 SELECT ポリシーを撤去する（20260913000400）ため、呼び出し者権限では sessions が常に 0 行になる。
--      定義者（postgres = テーブルオーナー）権限で読み、行は本文の client_id = auth.uid()、
--      列は RETURNS TABLE の許可リストで絞る。
--      search_path は空文字に固定し、テーブル・関数は完全修飾（public.sessions /
--      auth.uid()）で書く（search_path ハイジャック対策。組み込みの型・演算子は
--      pg_catalog が暗黙に先頭検索されるため修飾不要）。
--      Advisor の 0029_authenticated_security_definer_function_executable（WARN）は
--      この関数では意図どおり（ログインユーザー全員に開けるが、返すのは本人の行だけ）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_sessions(
  p_from timestamptz DEFAULT NULL,
  p_before timestamptz DEFAULT NULL,
  p_ids uuid[] DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  trainer_id uuid,
  client_id uuid,
  session_date timestamptz,
  duration_minutes integer,
  status text,
  session_type text,
  ticket_id uuid,
  recurrence_group_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- memo は意図的に選ばない（トレーナー専用の内輪メモ）。列を足すときは
  -- 「顧客に見せてよい列か」を判断したうえで RETURNS TABLE と両方に追加する
  SELECT
    s.id,
    s.trainer_id,
    s.client_id,
    s.session_date,
    s.duration_minutes,
    s.status,
    s.session_type,
    s.ticket_id,
    s.recurrence_group_id,
    s.created_at,
    s.updated_at
  FROM public.sessions s
  WHERE s.client_id = auth.uid()
    AND (p_from IS NULL OR s.session_date >= p_from)
    AND (p_before IS NULL OR s.session_date < p_before)
    AND (p_ids IS NULL OR s.id = ANY (p_ids));
$$;

COMMENT ON FUNCTION public.get_my_sessions(timestamptz, timestamptz, uuid[]) IS
  '呼び出した顧客本人（client_id = auth.uid()）のセッションを、列の許可リストで返す。'
  'sessions.memo はトレーナー専用の内輪メモのため返さない。顧客は sessions を直接読めず'
  '（顧客用 SELECT ポリシーは 20260913000400 で撤去）、この関数経由でのみ読む。'
  'p_from（以上）/ p_before（未満）/ p_ids は本人のセッション内での絞り込み。'
  '並び順・件数は呼び出し側（PostgREST の order / limit）で指定する。'
  '仕様: supabase/migrations/20260913000300_sessions_client_rpc.sql';

-- EXECUTE を authenticated のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon へも EXECUTE が付与されるため明示的に剥がす）
REVOKE ALL ON FUNCTION public.get_my_sessions(timestamptz, timestamptz, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_sessions(timestamptz, timestamptz, uuid[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_sessions(timestamptz, timestamptz, uuid[]) TO authenticated;
