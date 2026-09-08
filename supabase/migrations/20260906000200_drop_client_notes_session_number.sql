-- =============================================================================
-- client_notes: session_number 列の廃止
-- （ノート連携フォローアップ / レーンA）
--
-- 仕様出典: docs/tasks/2026-09-06-note-link-followup-plan.md「② セッション番号の廃止」
--
-- 背景: session_number は「何回目のセッションか」をトレーナーが手入力する表示用の
-- 通し番号（nullable）で、本番データでの入力実績は 0 件。
-- 直前の 20260906000100 で実データへの参照列 session_id を新設した際は
-- 「役割が異なる」として session_number を残していたが、その後 Web に入れた
-- 自動補完（過去セッション数からの導出）で次の問題が判明した:
--   - 過去セッションを後からキャンセルすると以降の序数が繰り上がり、保存済みカルテの
--     番号と食い違う（序数ドリフト）。導出値を非正規化して保存する限り本質的に消えない
--   - 実データへの参照は session_id に一本化済みで、番号を持ち続ける必然性が無い
-- そこで session_number を廃止し、紐づいたセッションの日付を主役にする
-- （Web / Mobile とも session_id 経由で sessions.session_date を表示する）。
--
-- 方針:
--   - 列を DROP する。本番 0 件のためデータ退避・バックフィルは不要
--   - Web / Mobile の参照（入力欄・自動補完・API の受け取り・#N 表示・モデル）は
--     同一 PR（feature/mobile-session-display）で同時に撤去する。片方だけ先に
--     push すると PostgREST の select 列指定が 42703 で落ちるため、
--     db push は両アプリのリリースと合わせて行うこと
--   - session_id 列の COMMENT は 20260906000100 で「session_number とは別物」と
--     説明していたため、存在しない列への言及を落として書き直す
--   - RLS / トリガー / インデックスには一切触れない。session_number を参照する
--     ポリシー・関数・ビューは無い（2026-09-06 時点のローカル実測: pg_depend /
--     pg_policy / pg_proc の検索で 0 件）ため、CASCADE は付けない
--
-- 冪等性: DROP COLUMN IF EXISTS / COMMENT ON は上書き。
--   何度再実行しても最終形に収束する。
-- =============================================================================

ALTER TABLE public.client_notes DROP COLUMN IF EXISTS session_number;

COMMENT ON COLUMN public.client_notes.session_id IS
  '紐づくセッション（sessions.id）への参照。任意。セッション削除時は NULL になりノート本体は残る。表示上の「何回目か」は保持せず、紐づいたセッションの日付（sessions.session_date）を表示に使う。';
