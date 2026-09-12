-- =============================================================================
-- sessions: 顧客用 SELECT ポリシー追加（フェーズ8.3 前半 / カタログ cat4 課題2）
--
-- 仕様出典: docs/tasks/2026-09-06-mobile-session-display-plan.md「レーンA: Supabase（RLS）」
--
-- 背景: sessions にはトレーナー用の4本（SELECT/INSERT/UPDATE/DELETE、いずれも
-- auth.uid() = trainer_id）しか無く、顧客ロールでは SELECT が常に 0 行になる。
-- Mobile のセッション表示（ホームの次回セッションカード / セッション一覧）が
-- 成立しないため、自分が対象のセッションだけを読める SELECT を1本追加する。
--
-- 方針:
--   - 判定式は client_id = auth.uid()。clients の主キーは client_id（auth.users.id
--     と同一 UUID を格納する運用）で id 列は存在せず、sessions.client_id は
--     clients.client_id への FK のため直接比較が正準
--     （weight_records / sleep_records の顧客用ポリシーと同形）
--     ※ カタログ L813 の案 `SELECT id FROM clients` は clients に id 列が無く誤り
--   - PERMISSIVE（既定）で追加する。同一コマンドの PERMISSIVE ポリシーは OR 結合
--     されるため、トレーナー用 SELECT の可視範囲は増えも減りもしない。
--     RESTRICTIVE で追加すると AND 結合になりトレーナーの SELECT が全滅する
--   - TO authenticated に限定する。sessions は anon にも GRANT ALL が残っている
--     （20251230131753）ため、role 未指定だと anon でも評価対象になる
--   - 書込（INSERT/UPDATE/DELETE）は追加しない。予約リクエストは別テーブルで扱う
--     設計であり、顧客に書込権を与えると status 改ざん・他人枠への割込みが可能になる
--
-- 注意:
--   - 既存のトレーナー用4本（"Trainers can view/insert/update/delete their own
--     sessions"）は現状のまま維持し、本 migration では一切触れない
--   - GRANT にも触れない。sessions は authenticated へ GRANT ALL 済みのため追加不要で、
--     REVOKE ALL → GRANT SELECT のように書き直すと Web（トレーナー）側の
--     INSERT/UPDATE/DELETE が権限エラーで全滅する
--   - client_id 単独インデックス（idx_sessions_client_id）が既存のため索引追加も不要
--
-- 【要検討】memo 列の露出について（プロダクト判断待ち・本 migration では未対応）:
--   - RLS は行単位の制御であり列を絞れないため、本ポリシーにより sessions の
--     **全列**が対象顧客に読める状態になる。memo も例外ではない
--   - memo はトレーナー側（Web）の入力欄であり、顧客に見せない前提のメモ
--     （体型の所見・支払い催促・引継ぎ事項など）を書く運用であれば情報漏洩になる
--   - 列単位 GRANT（GRANT SELECT (col,...) ）では解決できない。Web のトレーナーも
--     顧客と同じ authenticated ロールで接続しており、列を絞るとトレーナー側の
--     sessions 参照まで巻き添えで壊れるため
--   - 顧客非公開の記述を許す運用にするなら、内部メモ列を別テーブル
--     （例: session_trainer_notes。トレーナー用ポリシーのみ）へ分離する対応が必要
-- =============================================================================

DROP POLICY IF EXISTS "sessions_client_select" ON public.sessions;

CREATE POLICY "sessions_client_select"
ON public.sessions
FOR SELECT
TO authenticated
USING (client_id = auth.uid());
