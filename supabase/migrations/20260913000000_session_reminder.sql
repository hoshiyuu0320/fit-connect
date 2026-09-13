-- =============================================================================
-- Migration: session_reminder
-- フェーズ8.3②（カタログ cat4 課題3）: セッション前日リマインダーの DB 側基盤
--
-- 仕様出典: docs/tasks/2026-09-12-session-reminder-plan.md 契約・レーンA-1
--   1. notification_preferences.kind の CHECK を拡張し、通知種別 'session_reminder' を
--      追加する。Mobile の通知設定センターがこの kind を upsert するため、CHECK を
--      拡張しないとトグル操作が check_violation で落ちる
--   2. find_sessions_for_reminder(target_date date): 対象日（JST 暦日）に予定されている
--      scheduled / confirmed のセッションを列挙する SQL 関数（EXECUTE は service_role のみ）。
--      Edge Function `send-session-reminders` が RPC で呼び、各行を統一ディスパッチャ
--      （_shared/push.ts の sendNotification）へ渡す
--   3. pg_cron ジョブ 'send-session-reminders': Edge Function `send-session-reminders` を
--      毎日 11:00 UTC（JST 20:00）に呼び出す（dry_run: false = 実送信）。ただし意図的に
--      inactive で登録し、有効化はリモートでの dry run 後にオーナー判断とする
--      （20260829000300 の cleanup-ai-images と同運用）
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `secret_key` のシークレット登録が必要（2026-09-12 登録済み。
--     登録手順: docs/tasks/2026-07-10-cron-vault-setup.md）
--   - シークレット未登録でもジョブの「登録」自体は成功する（command 文字列は
--     ジョブ実行時に評価されるため）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. notification_preferences.kind の CHECK 拡張（'session_reminder' を追加）
--    制約名は 20260719010000 の列内 CHECK に対する自動命名
--    notification_preferences_kind_check（ローカル DB の \d で実名を確認済み）。
--    DROP IF EXISTS → ADD の順で作り直すため、何度実行しても同じ結果になる。
--    既存行は 'message' / 'goal_achievement' のみなので ADD 時の検証で落ちることはない。
-- -----------------------------------------------------------------------------
ALTER TABLE public.notification_preferences
  DROP CONSTRAINT IF EXISTS notification_preferences_kind_check;

ALTER TABLE public.notification_preferences
  ADD CONSTRAINT notification_preferences_kind_check
  CHECK (kind IN ('message','goal_achievement','session_reminder'));

COMMENT ON COLUMN public.notification_preferences.kind IS
  '通知種別。現状 message（メッセージ受信）/ goal_achievement（目標達成）/ '
  'session_reminder（セッション前日リマインダー）。'
  '種別を増やすときは migration で CHECK を拡張する';

-- -----------------------------------------------------------------------------
-- 2. find_sessions_for_reminder(target_date date)
--    target_date（JST の暦日。既定は JST の「明日」）に予定されている
--    scheduled / confirmed のセッションを session_date 昇順で列挙する。
--    同一顧客に同日複数セッションがあれば複数行返す（別セッションとして通知する。
--    dedup_key が session_id を含むため二重送信にはならない）。
--
--    JST 暦日の判定は範囲比較で書く:
--      session_date >= 対象日の JST 0:00  AND  session_date < 翌日の JST 0:00
--    `timestamp（without time zone）AT TIME ZONE 'Asia/Tokyo'` は「その JST 時刻」の
--    timestamptz を返すので、列側には何も掛けずに比較でき idx_sessions_session_date が効く。
--    `(session_date AT TIME ZONE 'Asia/Tokyo')::date = target_date` は列に関数を
--    掛けるため索引が使えない（禁止）。
--    既定値に CURRENT_DATE を使わないのも同じ理由（CURRENT_DATE は UTC 日付。
--    JST 0:00〜8:59 の間は前日を返す）。
--
--    引数名と戻り列名が同じ target_date だが、SQL 関数の本文で名前参照できるのは
--    入力引数だけなので曖昧にならない（PL/pgSQL に書き換えると重複エラーになる）。
--
--    SECURITY DEFINER の理由:
--      sessions / trainers は RLS で行が絞られるテーブルのため、定義者（postgres）
--      権限で全行を参照する。呼び出しは service_role（send-session-reminders
--      Edge Function の RPC）に限定する。search_path 固定（public, pg_temp）で
--      search_path ハイジャックを防ぐ（find_orphan_ai_images と同型）。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_sessions_for_reminder(
  target_date date DEFAULT ((now() AT TIME ZONE 'Asia/Tokyo')::date + 1)
)
RETURNS TABLE (
  session_id uuid,
  client_id uuid,
  trainer_id uuid,
  trainer_name text,
  session_date timestamptz,
  duration_minutes integer,
  session_type text,
  target_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    s.id,
    s.client_id,
    s.trainer_id,
    t.name,
    s.session_date,
    s.duration_minutes,
    s.session_type,
    target_date
  FROM public.sessions s
  -- sessions.trainer_id → trainers.id は FK（ON DELETE CASCADE）のため必ず 1 行対応する
  JOIN public.trainers t ON t.id = s.trainer_id
  WHERE s.status IN ('scheduled', 'confirmed')
    AND s.session_date >= (target_date::timestamp AT TIME ZONE 'Asia/Tokyo')
    AND s.session_date <  ((target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo')
  ORDER BY s.session_date ASC;
$$;

COMMENT ON FUNCTION public.find_sessions_for_reminder(date) IS
  'target_date（JST 暦日。既定は JST の明日）に予定されている scheduled / confirmed の'
  'セッションを session_date 昇順で列挙する（前日リマインダーの対象抽出）。'
  '呼び出しは send-session-reminders Edge Function（service_role RPC）のみ。'
  '仕様: docs/tasks/2026-09-12-session-reminder-plan.md 契約';

-- EXECUTE を service_role のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon / authenticated へ EXECUTE が付与されるため明示的に剥がす）
REVOKE ALL ON FUNCTION public.find_sessions_for_reminder(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_sessions_for_reminder(date) FROM anon;
REVOKE ALL ON FUNCTION public.find_sessions_for_reminder(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_sessions_for_reminder(date) TO service_role;

-- -----------------------------------------------------------------------------
-- 3. cron ジョブ 'send-session-reminders' の新規登録（無効状態）
--    毎日 11:00 UTC（JST 20:00。pg_cron は UTC 基準）に Edge Function
--    `send-session-reminders` を pg_net 経由で HTTP POST 呼び出しする
--    （dry_run: false = 実送信。関数側は dry_run 省略時に dry run となるため明示する）。
--    URL / secret キーは Vault の `project_url` / `secret_key` シークレットから
--    ジョブ実行時に解決し、secret キーは apikey ヘッダーで送る
--    （20260912000000 の方式。Authorization ヘッダーは送らない）。
--
--    ※ 意図的に「無効(inactive)」で登録する。初回から実顧客へ push が飛ぶため、
--      有効化はリモートで dry run（候補一覧のみ返す）の結果を確認した後の
--      オーナー判断とする。有効化手順: docs/tasks/2026-07-10-cron-vault-setup.md
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--      ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-session-reminders') THEN
    PERFORM cron.schedule(
      'send-session-reminders',
      '0 11 * * *',
      $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/send-session-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := '{"dry_run": false}'::jsonb
      );
      $cmd$
    );

    -- 作成直後に無効化（上記コメントの通り、有効化はオーナー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'send-session-reminders'),
      active := false
    );
  END IF;
END $$;
