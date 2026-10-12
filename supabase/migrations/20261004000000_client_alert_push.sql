-- =============================================================================
-- Migration: client_alert_push
-- フェーズ9.1 拡張 push（PR2）: トレーナー向けアラートの朝のまとめ通知の DB 側
--
-- 仕様出典: docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §8
--   1. notification_preferences.kind の CHECK に 'client_alert'（アラートの朝のまとめ）を足す。
--      Web の通知設定がこの kind を upsert するため、拡張しないとトグルが check_violation で落ちる
--   2. pg_cron ジョブ 'notify-trainer-alerts': Edge Function `notify-trainer-alerts` を
--      毎日 21:10 UTC（JST 06:10。06:00 の自動チェック detect-client-alerts の10分後）に呼ぶ。
--      body は dry_run: false と target_date = 実行時点の JST の今日（+ 1 しない）。
--      意図的に「無効(inactive)」で登録し、有効化はオーナー（設計書 §11.2 手順8）
--   3. 末尾で最終形を検査し、違えば RAISE EXCEPTION で migration ごと止める
--
-- 新しい表・関数・権限は無い。既存の関数を書き換えないのでドリフトガードは要らない。
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `secret_key` の登録が必要（2026-09-12 登録済み）
--   - シークレット未登録でもジョブの「登録」自体は成功する（command はジョブ実行時に評価される）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. notification_preferences.kind の CHECK 拡張（'client_alert' を追加）
--    20260913000000_session_reminder.sql と同じ書き方（DROP IF EXISTS → ADD）。
--    既存行は message / goal_achievement / session_reminder のみなので ADD の検証では落ちない
-- -----------------------------------------------------------------------------
ALTER TABLE public.notification_preferences
  DROP CONSTRAINT IF EXISTS notification_preferences_kind_check;

ALTER TABLE public.notification_preferences
  ADD CONSTRAINT notification_preferences_kind_check
  CHECK (kind IN ('message','goal_achievement','session_reminder','client_alert'));

COMMENT ON COLUMN public.notification_preferences.kind IS
  '通知種別。現状 message（メッセージ受信）/ goal_achievement（目標達成）/ '
  'session_reminder（セッション前日リマインダー）/ client_alert（トレーナー向けアラートの朝のまとめ）。'
  '種別を増やすときは migration で CHECK を拡張する';

-- -----------------------------------------------------------------------------
-- 2. cron ジョブ 'notify-trainer-alerts' の新規登録（無効状態）
--    毎日 21:10 UTC（JST 06:10。pg_cron は UTC 基準）に Edge Function `notify-trainer-alerts` を
--    pg_net 経由で HTTP POST する。url の組み立て（関数名を除く）・headers・timeout は 20260913000100 の
--    send-session-reminders の command と同一（Vault の project_url / secret_key を apikey ヘッダーで送る）。
--    違うのは body だけ:
--      - body: dry_run: false（関数は省略時 dry run）と target_date = 実行時点の JST の今日。
--        21:10 UTC は JST の翌日 06:10 なので、(now() AT TIME ZONE 'Asia/Tokyo')::date がその日の D。
--        send-session-reminders と違い + 1 しない。CURRENT_DATE は UTC の日付なので使わない
--      - timeout_milliseconds: 60000（send-session-reminders と同じ。関数の再試行は受付から 40 秒で
--        打ち切る。retry.ts の CRON_RETRY_BUDGET_MS）
--    同名のジョブが無いときだけ登録し、登録直後に無効にする（有効化はオーナー。設計書 §11.2）。
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付きドル引用 $cmd$ で書く
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-trainer-alerts') THEN
    PERFORM cron.schedule(
      'notify-trainer-alerts',
      '10 21 * * *',
      $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/notify-trainer-alerts',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := jsonb_build_object(
          'dry_run', false,
          'target_date', to_char((now() AT TIME ZONE 'Asia/Tokyo')::date, 'YYYY-MM-DD')
        ),
        timeout_milliseconds := 60000
      );
      $cmd$
    );

    -- 作成直後に無効化（有効化はオーナー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'notify-trainer-alerts'),
      active := false
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 3. 最終形の検査（違えば migration ごと止める）
--    - notification_preferences の kind に関する CHECK（contype = 'c' で定義に kind を含むもの）が
--      1本だけで、4種別すべてを含む（制約名が想定と違う環境で、古い CHECK が別名で残るのを見逃さない）
--    - cron.job の 'notify-trainer-alerts' が1件で、schedule '10 21 * * *'・active = false
--      （「無効で登録」の最終形をここで固定する。リリース手順8 の前に有効になっていてはいけない）
--    cron.job は RLS（username = CURRENT_USER）があり、postgres が全ジョブを見られるのは
--    BYPASSRLS による。見えなければ件数 0 として止まる（黙って通さない）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_check_count int;
  v_def text;
  v_kind text;
  v_job_count int;
  v_schedule text;
  v_active boolean;
BEGIN
  SELECT count(*), min(pg_get_constraintdef(c.oid))
    INTO v_check_count, v_def
    FROM pg_catalog.pg_constraint c
   WHERE c.conrelid = 'public.notification_preferences'::regclass
     AND c.contype = 'c'
     AND pg_get_constraintdef(c.oid) ~ '\mkind\M';

  IF v_check_count <> 1 THEN
    RAISE EXCEPTION 'CLIENT_ALERT_PUSH_POSTCHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = format('notification_preferences has %s CHECK constraint(s) on kind (expected 1)',
                             v_check_count);
  END IF;

  FOREACH v_kind IN ARRAY ARRAY['message', 'goal_achievement', 'session_reminder', 'client_alert'] LOOP
    IF position(quote_literal(v_kind) IN v_def) = 0 THEN
      RAISE EXCEPTION 'CLIENT_ALERT_PUSH_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('notification_preferences kind CHECK does not include %s (definition: %s)',
                               v_kind, v_def);
    END IF;
  END LOOP;

  SELECT count(*), min(schedule), bool_and(active)
    INTO v_job_count, v_schedule, v_active
    FROM cron.job
   WHERE jobname = 'notify-trainer-alerts';

  IF v_job_count <> 1 THEN
    RAISE EXCEPTION 'CLIENT_ALERT_PUSH_POSTCHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = format('cron job notify-trainer-alerts: %s row(s) (expected 1)', v_job_count);
  END IF;

  IF v_schedule IS DISTINCT FROM '10 21 * * *' OR v_active IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'CLIENT_ALERT_PUSH_POSTCHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = format('cron job notify-trainer-alerts: schedule=%s active=%s (expected ''10 21 * * *'' / false)',
                             v_schedule, v_active);
  END IF;
END $$;
