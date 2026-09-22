-- =============================================================================
-- cron ジョブ（Edge Function 呼び出し 3 本）の登録内容テスト
-- （20260912000000_cron_use_secret_key.sql / 20260913000100_session_reminder_cron_target_date.sql
--   / 20260913000200_cron_http_timeout.sql 適用後の状態）
--
-- pg_cron の 'auto-skip-workouts' / 'cleanup-ai-images' / 'send-session-reminders' について、
-- schedule と command（pg_net の net.http_post 呼び出し）を検証する自己完結テスト
-- （session_reminder_test.sql のケース(f) の書式を踏襲し、3 ジョブへ広げたもの）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/cron_jobs_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CRON JOBS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 読み取りのみだが、他のテストと同じく BEGIN...ROLLBACK 内で実行し DB には何も残さない
-- - active はアサートしない（ローカルは migration で inactive 登録のまま、リモートは
--   オーナー判断で有効化するため、環境によって値が異なる）
--
-- 検証ケース（3 ジョブすべて）:
--   (a) jobname で 1 件だけ登録され、schedule が期待値
--       auto-skip-workouts '0 18 * * *'（JST 03:00）/ cleanup-ai-images '0 19 * * *'（JST 04:00）/
--       send-session-reminders '0 11 * * *'（JST 20:00）
--   (b) command が net.http_post で /functions/v1/<ジョブ名> を呼び、Vault の project_url / secret_key を
--       参照して secret キーを apikey ヘッダーで送る。旧方式（Vault の service_role_key・
--       Authorization ヘッダー）を含まない
--   (c) command に timeout_milliseconds を含み、値が 60000 以上（pg_net 既定の 5000ms では、
--       一時障害の再試行を含む関数の応答を待たずに timed_out になり、net._http_response で
--       結果を確認できない）
--   (d) command の body が既存どおり（timeout を足すために command 全体を書き換えているため、
--       body が変わっていないことを固定する）
--   (e) command が SQL として解析・計画できる（EXPLAIN。(b)〜(d) は文字列の部分一致なので、
--       カンマ・括弧・$cmd$ の崩れや引数名の誤りで毎回失敗する command でも通ってしまうため）。
--       EXPLAIN（ANALYZE なし）は net.http_post を実行せず、HTTP リクエストも積まない
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 期待値（各ケースで 3 ジョブ分をループして検証する）
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE expected_cron_jobs (
  jobname text PRIMARY KEY,
  schedule text NOT NULL,
  body_fragment text NOT NULL
) ON COMMIT DROP;

INSERT INTO expected_cron_jobs (jobname, schedule, body_fragment) VALUES
  ('auto-skip-workouts',     '0 18 * * *', $f$body := '{}'::jsonb$f$),
  ('cleanup-ai-images',      '0 19 * * *', $f$body := '{"dry_run": false}'::jsonb$f$),
  ('send-session-reminders', '0 11 * * *', $f$'dry_run', false$f$);

-- -----------------------------------------------------------------------------
-- ケース(a): 登録と schedule
-- -----------------------------------------------------------------------------
\echo '--- case a: 3 ジョブが 1 件ずつ登録され、schedule が期待値であること'

DO $$
DECLARE
  v_exp record;
  v_job record;
  cnt int;
BEGIN
  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT count(*) INTO cnt FROM cron.job WHERE jobname = v_exp.jobname;
    IF cnt = 0 THEN
      RAISE EXCEPTION 'FAIL: cron ジョブ % が登録されていない', v_exp.jobname;
    END IF;
    IF cnt > 1 THEN
      RAISE EXCEPTION 'FAIL: cron ジョブ % が % 件登録されている（期待 1 件。重複すると二重実行になる）',
        v_exp.jobname, cnt;
    END IF;

    SELECT jobname, schedule INTO v_job FROM cron.job WHERE jobname = v_exp.jobname;
    IF v_job.schedule <> v_exp.schedule THEN
      RAISE EXCEPTION 'FAIL: % の schedule が %（期待 %）', v_exp.jobname, v_job.schedule, v_exp.schedule;
    END IF;
    RAISE NOTICE 'OK: % は 1 件登録 / schedule %', v_exp.jobname, v_job.schedule;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 呼び出し先と認証（Vault の secret_key を apikey ヘッダーで送る方式）
-- -----------------------------------------------------------------------------
\echo '--- case b: command が /functions/v1/<ジョブ名> を apikey（Vault の secret_key）で呼び、旧方式を含まないこと'

DO $$
DECLARE
  v_exp record;
  v_command text;
BEGIN
  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT command INTO v_command FROM cron.job WHERE jobname = v_exp.jobname;

    IF position('net.http_post' IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が pg_net の net.http_post を呼んでいない', v_exp.jobname;
    END IF;
    IF position(('/functions/v1/' || v_exp.jobname) IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が Edge Function /functions/v1/% を呼んでいない',
        v_exp.jobname, v_exp.jobname;
    END IF;
    IF position('project_url' IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が Vault の project_url を参照していない', v_exp.jobname;
    END IF;
    IF position('secret_key' IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が Vault の secret_key を参照していない', v_exp.jobname;
    END IF;
    IF position('apikey' IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が apikey ヘッダーを送っていない', v_exp.jobname;
    END IF;
    IF position('service_role_key' IN v_command) > 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が旧 Vault キー service_role_key を参照している', v_exp.jobname;
    END IF;
    IF position('Authorization' IN v_command) > 0 THEN
      RAISE EXCEPTION 'FAIL: % の command が旧方式の Authorization ヘッダーを含んでいる', v_exp.jobname;
    END IF;
    RAISE NOTICE 'OK: % は apikey 方式（Vault の project_url / secret_key）で呼び出し、旧方式を含まない', v_exp.jobname;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): pg_net のタイムアウト延長
-- -----------------------------------------------------------------------------
\echo '--- case c: command に timeout_milliseconds（60000 以上）を指定していること'

DO $$
DECLARE
  v_exp record;
  v_command text;
  v_timeout int;
BEGIN
  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT command INTO v_command FROM cron.job WHERE jobname = v_exp.jobname;

    v_timeout := substring(v_command FROM 'timeout_milliseconds\s*:=\s*(\d+)')::int;
    IF v_timeout IS NULL THEN
      RAISE EXCEPTION 'FAIL: % の command に timeout_milliseconds が無い（pg_net 既定 5000ms のまま）', v_exp.jobname;
    END IF;
    IF v_timeout < 60000 THEN
      RAISE EXCEPTION 'FAIL: % の timeout_milliseconds が %（期待 60000 以上）', v_exp.jobname, v_timeout;
    END IF;
    RAISE NOTICE 'OK: % は timeout_milliseconds := %', v_exp.jobname, v_timeout;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): body が既存どおり
-- -----------------------------------------------------------------------------
\echo '--- case d: command の body が既存どおりであること'

DO $$
DECLARE
  v_exp record;
  v_command text;
BEGIN
  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT command INTO v_command FROM cron.job WHERE jobname = v_exp.jobname;

    IF position(v_exp.body_fragment IN v_command) = 0 THEN
      RAISE EXCEPTION 'FAIL: % の command の body が既存と異なる（期待: % を含む）',
        v_exp.jobname, v_exp.body_fragment;
    END IF;
    RAISE NOTICE 'OK: % の body は既存どおり（% を含む）', v_exp.jobname, v_exp.body_fragment;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): command が SQL として解析・計画できる
--   EXPLAIN は構文と関数の引数名（url / headers / body / timeout_milliseconds）の解決までを行い、
--   net.http_post 自体は実行しない。念のため net.http_request_queue の件数が変わらないことも確認する
-- -----------------------------------------------------------------------------
\echo '--- case e: command が EXPLAIN で解析・計画でき、HTTP リクエストを積まないこと'

DO $$
DECLARE
  v_exp record;
  v_command text;
  v_stmt text;
  v_queue_before bigint;
  v_queue_after bigint;
BEGIN
  SELECT count(*) INTO v_queue_before FROM net.http_request_queue;

  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT command INTO v_command FROM cron.job WHERE jobname = v_exp.jobname;
    -- 末尾の空白と ; を落とした 1 文（command は SELECT net.http_post(...) の 1 文だけのはず）
    v_stmt := regexp_replace(v_command, '[\s;]+$', '');

    BEGIN
      EXECUTE 'EXPLAIN (COSTS OFF) ' || v_stmt;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: % の command が SQL として解析・計画できない（% %）',
        v_exp.jobname, SQLSTATE, SQLERRM;
    END;
    RAISE NOTICE 'OK: % の command は EXPLAIN で解析・計画できる', v_exp.jobname;
  END LOOP;

  SELECT count(*) INTO v_queue_after FROM net.http_request_queue;
  IF v_queue_after <> v_queue_before THEN
    RAISE EXCEPTION 'FAIL: EXPLAIN の前後で net.http_request_queue が % 件 → % 件に変わった（HTTP リクエストが積まれた）',
      v_queue_before, v_queue_after;
  END IF;
  RAISE NOTICE 'OK: net.http_request_queue は % 件のまま（EXPLAIN は HTTP リクエストを積まない）', v_queue_after;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CRON JOBS TESTS PASSED'
