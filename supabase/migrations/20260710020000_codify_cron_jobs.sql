-- =============================================================================
-- Migration: codify_cron_jobs
-- フェーズ5.3（カタログ cat7 5-A）: リポジトリ管理外だった pg_cron 設定の migration 化
--
-- 目的:
--   1. pg_cron / pg_net 拡張の有効化を migration として明文化する
--   2. リモートDBに直接作成され migration 欠落していた `issue_recurring_tickets()`
--      関数と cron ジョブ 'issue-recurring-tickets' を追認する
--   3. デプロイ済み ACTIVE なのに cron が存在せず一度も動いていなかった
--      Edge Function `auto-skip-workouts` の cron ジョブを「無効(inactive)状態」で
--      新規登録する（有効化はユーザー判断。ファイル末尾のコメント参照）
--
-- リモートには no-op である理由（2026-07-10 リモートDB実測に基づく）:
--   - CREATE EXTENSION IF NOT EXISTS: リモートは pg_cron 1.6 / pg_net 0.14 が
--     有効済みのため no-op
--   - issue_recurring_tickets(): CREATE OR REPLACE はリモートでも実行されるが、
--     リモート実定義と一言一句同一のため実質 no-op
--   - 'issue-recurring-tickets' ジョブ: jobname 存在チェック付きで作成するため、
--     リモート（jobid=1 で存在・active）には一切触れない
--   - 'auto-skip-workouts' ジョブ: リモートに存在しないため新規作成されるが、
--     作成直後に inactive 化するため実行されず、動作への影響なし
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `service_role_key` のシークレット登録が必要
--     （現状 Vault は空。登録手順: docs/tasks/2026-07-10-cron-vault-setup.md）
--   - シークレット未登録でもジョブの「登録」自体は成功する（command 文字列は
--     ジョブ実行時に評価されるため）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. 拡張の有効化（リモートでは既に有効なので no-op）
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- -----------------------------------------------------------------------------
-- 2. issue_recurring_tickets() の追認
--    リモートDBに直接作成されていた定期チケット発行関数。
--    2026-07-10 リモート実測の実定義を一言一句そのまま収録
--    （同一定義への CREATE OR REPLACE のため実質 no-op）。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_recurring_tickets()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  sub RECORD;
  new_valid_from DATE;
  new_valid_until DATE;
BEGIN
  FOR sub IN
    SELECT ts.*, tt.template_name, tt.ticket_type, tt.total_sessions, tt.valid_months
    FROM ticket_subscriptions ts
    JOIN ticket_templates tt ON ts.template_id = tt.id
    WHERE ts.status = 'active'
      AND ts.next_issue_date <= CURRENT_DATE
  LOOP
    new_valid_from := sub.next_issue_date;
    new_valid_until := sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL;

    -- チケット発行
    INSERT INTO tickets (client_id, ticket_name, ticket_type, total_sessions, remaining_sessions, valid_from, valid_until)
    VALUES (
      sub.client_id,
      sub.template_name,
      sub.ticket_type,
      sub.total_sessions,
      sub.total_sessions,
      new_valid_from,
      new_valid_until
    );

    -- 次回発行日を翌月に更新
    UPDATE ticket_subscriptions
    SET next_issue_date = sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL
    WHERE id = sub.id;
  END LOOP;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. cron ジョブ 'issue-recurring-tickets' の追認
--    毎日 00:00 UTC（JST 09:00）に定期チケットを発行する既存ジョブ。
--    リモートには jobid=1・active で登録済みのため、存在しない場合のみ作成する
--    （既存ジョブのスケジュール・状態には一切触れない）。
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'issue-recurring-tickets') THEN
    PERFORM cron.schedule('issue-recurring-tickets', '0 0 * * *', 'SELECT issue_recurring_tickets()');
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. cron ジョブ 'auto-skip-workouts' の新規登録（無効状態）
--    毎日 18:00 UTC（JST 03:00）に Edge Function `auto-skip-workouts` を
--    pg_net 経由で HTTP POST 呼び出しする。URL / service_role キーは Vault の
--    `project_url` / `service_role_key` シークレットからジョブ実行時に解決する。
--
--    ※ 意図的に「無効(inactive)」で登録する。有効化は繰越問題（カタログ cat2 8-A）
--      修正後にユーザー判断とする。現存25件の期限切れ pending 課題が初回実行で
--      一括スキップされてしまうため、修正前の有効化は行わないこと。
--      有効化手順: docs/tasks/2026-07-10-cron-vault-setup.md
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--      ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto-skip-workouts') THEN
    PERFORM cron.schedule(
      'auto-skip-workouts',
      '0 18 * * *',
      $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/auto-skip-workouts',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
        ),
        body := '{}'::jsonb
      );
      $cmd$
    );

    -- 作成直後に無効化（上記コメントの通り、有効化はユーザー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'auto-skip-workouts'),
      active := false
    );
  END IF;
END $$;
