-- =============================================================================
-- Migration: cron_http_timeout
-- cron ジョブ 'auto-skip-workouts' / 'cleanup-ai-images' の pg_net 呼び出しに
-- timeout_milliseconds := 60000 を追加する（Edge Function 側の一時障害リトライ導入に合わせた延長）
--
-- 目的:
--   1. 20260912000000_cron_use_secret_key.sql で書き換えた 2 ジョブの command
--      （pg_net の net.http_post 呼び出し）に timeout_milliseconds だけを追加する。
--      URL・headers（Vault の secret_key を apikey ヘッダーで送る方式）・body は
--      20260912000000 の command と同一のまま
--   2. schedule / active は一切変更しない（有効/無効の状態をそのまま保つ）
--   3. 'send-session-reminders' は 20260913000100 で timeout 延長済みのため触らない
--
-- 背景:
--   - 2026-09-13 04:00 JST の cleanup-ai-images 本番初回実行で、Edge Function 内の
--     rpc('find_orphan_ai_images') が PostgREST から 504 Gateway Timeout（約 7 秒）を受け、
--     関数は 500 で終了した（SQL 自体は 6.5ms。PostgREST 側にログが無い一時障害）
--   - pg_cron（pg_net）はリクエストを enqueue した時点で succeeded 扱いのため、cron 側では
--     失敗に気づけない。そこで 3 つの cron 関数に一時障害（5xx / 通信失敗）の再試行
--     （最大 3 回、待機 1 秒 → 3 秒。supabase/functions/_shared/retry.ts）を入れた
--   - pg_net の既定タイムアウトは 5000ms。再試行を含むと関数の応答は 5 秒を超え得るため、
--     既定のままだと pg_net が先に打ち切り、net._http_response に timed_out=true が残るだけに
--     なる（関数自体は走り続けるが、結果 JSON で成否を確認できない）。
--     send-session-reminders（20260913000100）と同じ 60000ms に延長する
--     （関数側は再試行をリクエスト受付から 40 秒で打ち切る = retry.ts の CRON_RETRY_BUDGET_MS。
--       60 秒はそれに締切直前の最後の1回と応答の余裕を足した値）
--
-- 冪等性:
--   - ジョブが存在する場合のみ cron.alter_job で command を上書きする
--     （存在しなければ何もしない）。何度実行しても同じ command に収束する
--   - cron.alter_job は command 以外の引数（schedule / active 等）を渡さなければ
--     NULL 扱いとなり、既存値を変更しない
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `secret_key` の登録が必要（2026-09-12 登録済み）
--   - timeout の延長は pg_net が応答を待つ時間を延ばすだけで、関数側の挙動は変えない。
--     Edge Function（再試行導入版）のデプロイと順序が前後しても壊れない
--
-- ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--   ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. 'auto-skip-workouts' の command 書き換え（schedule / active は据え置き）
--    毎日 18:00 UTC（JST 03:00）/ body '{}'（dry_run 省略 = 実行）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'auto-skip-workouts';

  IF v_jobid IS NOT NULL THEN
    PERFORM cron.alter_job(
      v_jobid,
      command := $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/auto-skip-workouts',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 60000
      );
      $cmd$
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. 'cleanup-ai-images' の command 書き換え（schedule / active は据え置き）
--    毎日 19:00 UTC（JST 04:00）/ dry_run: false = 実削除
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_jobid bigint;
BEGIN
  SELECT jobid INTO v_jobid FROM cron.job WHERE jobname = 'cleanup-ai-images';

  IF v_jobid IS NOT NULL THEN
    PERFORM cron.alter_job(
      v_jobid,
      command := $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/cleanup-ai-images',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := '{"dry_run": false}'::jsonb,
        timeout_milliseconds := 60000
      );
      $cmd$
    );
  END IF;
END $$;
