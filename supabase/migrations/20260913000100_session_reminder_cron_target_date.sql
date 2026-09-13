-- =============================================================================
-- Migration: session_reminder_cron_target_date
-- cron ジョブ 'send-session-reminders' の command を「対象日を cron 側で明示し、
-- pg_net のタイムアウトを延長する」形に書き換える（フェーズ8.3② レビュー指摘の修正）
--
-- 目的:
--   1. 20260913000000_session_reminder.sql で登録した 'send-session-reminders' の
--      command（pg_net の net.http_post 呼び出し）のうち、body と timeout だけを
--      書き換える。URL と headers は既存のまま（20260912000000 の apikey 方式）
--   2. schedule / active は一切変更しない（inactive のまま。有効化は従来どおり
--      オーナー判断。手順: docs/tasks/2026-07-10-cron-vault-setup.md §3）
--
-- 背景:
--   - body: 旧 command は '{"dry_run": false}' のみで、対象日を Edge Function 側の既定
--     （SQL 関数 find_sessions_for_reminder の DEFAULT = JST の明日）に依存していた。
--     本送信（dry_run=false）で対象日が暗黙だと、手動再実行や関数側の既定変更で
--     「いつの通知か」が cron の意図とずれ得る（dedup_key は対象日を含むため、
--     ずれると二重送信 or 送信漏れになる）。契約を変更し、**dry_run=false の本送信では
--     target_date（YYYY-MM-DD）を必須**とした（省略時は関数が 400 で拒否する）。
--     cron は毎日 11:00 UTC（= JST 20:00）に実行されるため、その時点の JST 暦日 + 1 を
--     `to_char((now() AT TIME ZONE 'Asia/Tokyo')::date + 1, 'YYYY-MM-DD')` で計算して
--     body に入れる（関数側の既定には依存しない。CURRENT_DATE は UTC 日付なので使わない）
--   - timeout_milliseconds: pg_net の既定は 5000ms。send-session-reminders は候補ごとに
--     OAuth（FCM のアクセストークン取得）+ FCM 送信 + notification_logs 書き込みの往復を
--     行うため、候補が数件あるだけで 5 秒を超え得る。pg_net 側でタイムアウトすると
--     net._http_response に timed_out=true が残るだけで関数は走り続ける（送信自体は
--     止まらない）が、結果 JSON が取れず検証できないため 60000ms に延長する
--
-- 冪等性:
--   - ジョブが存在する場合のみ cron.alter_job で command を上書きする
--     （存在しなければ何もしない。20260913000000 が先に適用されるため通常は必ず存在する）。
--     何度実行しても同じ command に収束する
--   - cron.alter_job は command 以外の引数（schedule / active 等）を渡さなければ
--     NULL 扱いとなり、既存値を変更しない
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `secret_key` の登録が必要（2026-09-12 登録済み）
--   - Edge Function `send-session-reminders` が target_date 必須の版にデプロイ済みであること
--     （旧版の関数は target_date を受け取っても無視するだけなので、順序が前後しても壊れない）
--
-- ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--   ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 'send-session-reminders' の command 書き換え（schedule / active は据え置き）
--    毎日 11:00 UTC（JST 20:00）/ 現状 inactive / dry_run: false = 実送信
--    body の target_date は実行時点の JST 暦日 + 1（= JST の明日）を cron 側で計算する
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'send-session-reminders';

  IF v_jobid IS NOT NULL THEN
    PERFORM cron.alter_job(
      v_jobid,
      command := $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/send-session-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := jsonb_build_object(
          'dry_run', false,
          'target_date', to_char(((now() AT TIME ZONE 'Asia/Tokyo')::date + 1), 'YYYY-MM-DD')
        ),
        timeout_milliseconds := 60000
      );
      $cmd$
    );
  END IF;
END $$;
