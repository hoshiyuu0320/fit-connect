-- =============================================================================
-- Migration: cron_use_secret_key
-- cron ジョブ 'auto-skip-workouts' / 'cleanup-ai-images' の Edge Function 呼び出し
-- ヘッダーを「Vault の新 secret キーを apikey ヘッダーで送る」方式へ切り替える
--
-- 目的:
--   1. 20260710020000_codify_cron_jobs.sql で登録した 'auto-skip-workouts' と
--      20260829000300_cleanup_ai_images.sql で登録した 'cleanup-ai-images' の
--      command（pg_net の net.http_post 呼び出し）のうち、headers だけを
--      書き換える。URL と body は既存のまま
--   2. schedule / active は一切変更しない（有効/無効の状態をそのまま保つ）
--
-- 背景:
--   - 旧方式は `'Authorization', 'Bearer ' || (Vault の service_role_key)` を送っていたが、
--     本番ではこの旧 service_role キー（JWT）が関数側の値と一致せず 401 になる
--   - Supabase 公式ガイドの方針どおり、新しい secret キー（`sb_secret_...`、JWT ではない）
--     を Vault に `secret_key` という名前で登録し、`apikey` ヘッダーで送る方式に切り替える
--   - Authorization ヘッダーは送らない（新しい secret キーを Bearer で送ると、
--     ゲートウェイが JWT として解析しようとして弾くため）
--   - Edge Function 側の新キー対応は別途実施
--
-- 冪等性:
--   - ジョブが存在する場合のみ cron.alter_job で command を上書きする
--     （存在しなければ何もしない）。何度実行しても同じ結果になる
--   - cron.alter_job は command 以外の引数（schedule / active 等）を渡さなければ
--     NULL 扱いとなり、既存値を変更しない
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `secret_key`（Dashboard → Settings → API Keys の secret キー `default`）
--     の登録が必要。`project_url` は既存どおり必要
--     （登録手順: docs/tasks/2026-07-10-cron-vault-setup.md）
--   - `secret_key` 未登録でも migration 自体は成功する（command 文字列はジョブ実行時に
--     評価されるため）。その場合はジョブ実行時に apikey が NULL になり 401 になるだけ
--   - リモートでは2本とも inactive のため、適用しても実行はされない
--     （有効化は従来どおりオーナー判断）
--
-- ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--   ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. 'auto-skip-workouts' の command 書き換え（schedule / active は据え置き）
--    毎日 18:00 UTC（JST 03:00）/ 現状 inactive
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
        body := '{}'::jsonb
      );
      $cmd$
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. 'cleanup-ai-images' の command 書き換え（schedule / active は据え置き）
--    毎日 19:00 UTC（JST 04:00）/ 現状 inactive / dry_run: false = 実削除
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
        body := '{"dry_run": false}'::jsonb
      );
      $cmd$
    );
  END IF;
END $$;
