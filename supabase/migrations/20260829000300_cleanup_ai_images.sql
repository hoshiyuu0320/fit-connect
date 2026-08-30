-- =============================================================================
-- Migration: cleanup_ai_images
-- フェーズ8.2（カタログ cat7 課題8 施策8-A）:
--   AI推定用にアップロードされたまま未参照となった orphan 画像の掃除基盤
--
-- 仕様出典: docs/tasks/2026-08-29-storage-private-plan.md 設計判断6・レーンA-4
--   1. find_orphan_ai_images(cutoff interval): message-photos の {uid}/ai/ 配下で
--      cutoff より古く、messages.image_urls / meal_records.images のいずれの要素からも
--      参照されていないオブジェクトを列挙する SQL 関数（EXECUTE は service_role のみ）
--   2. pg_cron ジョブ 'cleanup-ai-images': Edge Function `cleanup-ai-images` を
--      日次で呼び出す（dry_run: false = 実削除）。ただし意図的に inactive で登録し、
--      有効化はオーナー判断とする（20260710020000 の auto-skip-workouts と同運用）
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `service_role_key` のシークレット登録が必要
--     （登録手順: docs/tasks/2026-07-10-cron-vault-setup.md）
--   - シークレット未登録でもジョブの「登録」自体は成功する（command 文字列は
--     ジョブ実行時に評価されるため）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. find_orphan_ai_images(cutoff interval)
--    参照判定は「配列要素が LIKE '%' || オブジェクト名 で終わる」こと。
--    フルURL（…/object/public/message-photos/<name>）とバケット相対パス（<name>）の
--    両形式を1つの条件で吸収する（URL→パス正規化 migration との共存・冪等）。
--
--    SECURITY DEFINER の理由:
--      storage.objects の走査と、RLS で行が絞られる messages / meal_records の
--      全行参照判定が必要なため、定義者（postgres）権限で実行する。
--      呼び出しは service_role（cleanup-ai-images Edge Function の RPC）に限定する。
--      search_path 固定（public, pg_temp）で search_path ハイジャックを防ぐ。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.find_orphan_ai_images(cutoff interval DEFAULT '48 hours')
RETURNS TABLE (name text, created_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT o.name, o.created_at
  FROM storage.objects o
  WHERE o.bucket_id = 'message-photos'
    AND o.name LIKE '%/ai/%'
    AND o.created_at < now() - cutoff
    -- messages.image_urls のいずれの要素からも参照されていない
    AND NOT EXISTS (
      SELECT 1
      FROM public.messages m
      CROSS JOIN unnest(coalesce(m.image_urls, '{}')) AS u(val)
      WHERE u.val LIKE '%' || o.name
    )
    -- meal_records.images のいずれの要素からも参照されていない
    AND NOT EXISTS (
      SELECT 1
      FROM public.meal_records r
      CROSS JOIN unnest(coalesce(r.images, '{}')) AS u(val)
      WHERE u.val LIKE '%' || o.name
    );
$$;

COMMENT ON FUNCTION public.find_orphan_ai_images(interval) IS
  'message-photos の {uid}/ai/ 配下で cutoff より古く、messages.image_urls / '
  'meal_records.images から未参照の orphan 画像を列挙する。'
  '呼び出しは cleanup-ai-images Edge Function（service_role RPC）のみ。'
  '仕様: docs/tasks/2026-08-29-storage-private-plan.md 設計判断6';

-- EXECUTE を service_role のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon / authenticated へ EXECUTE が付与されるため明示的に剥がす）
REVOKE ALL ON FUNCTION public.find_orphan_ai_images(interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.find_orphan_ai_images(interval) FROM anon;
REVOKE ALL ON FUNCTION public.find_orphan_ai_images(interval) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.find_orphan_ai_images(interval) TO service_role;

-- -----------------------------------------------------------------------------
-- 2. cron ジョブ 'cleanup-ai-images' の新規登録（無効状態）
--    毎日 19:00 UTC（JST 04:00）に Edge Function `cleanup-ai-images` を
--    pg_net 経由で HTTP POST 呼び出しする（dry_run: false = 実削除）。
--    URL / service_role キーは Vault の `project_url` / `service_role_key`
--    シークレットからジョブ実行時に解決する。
--
--    ※ 意図的に「無効(inactive)」で登録する。有効化は統合QAで dry_run の削除候補が
--      「未参照 /ai/ のみ」であることを確認した後のオーナー判断とする。
--      有効化手順: docs/tasks/2026-07-10-cron-vault-setup.md
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--      ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cleanup-ai-images') THEN
    PERFORM cron.schedule(
      'cleanup-ai-images',
      '0 19 * * *',
      $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/cleanup-ai-images',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
        ),
        body := '{"dry_run": false}'::jsonb
      );
      $cmd$
    );

    -- 作成直後に無効化（上記コメントの通り、有効化はオーナー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'cleanup-ai-images'),
      active := false
    );
  END IF;
END $$;
