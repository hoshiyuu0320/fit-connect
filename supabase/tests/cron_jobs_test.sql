-- =============================================================================
-- cron ジョブ（Edge Function 呼び出し 5 本）の登録内容テスト
-- （20260912000000_cron_use_secret_key.sql / 20260913000100_session_reminder_cron_target_date.sql
--   / 20260913000200_cron_http_timeout.sql / 20261004000000_client_alert_push.sql
--   / 20261101000000_cron_health_monitor.sql 適用後の状態）
--
-- pg_cron の 'auto-skip-workouts' / 'cleanup-ai-images' / 'send-session-reminders' /
-- 'notify-trainer-alerts' / 'check-cron-health' について、schedule と command（pg_net の net.http_post
-- 呼び出し）を検証する自己完結テスト（session_reminder_test.sql のケース(f) の書式を踏襲し、5 ジョブへ広げたもの）。
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
-- 検証ケース（5 ジョブすべて）:
--   (a) jobname で 1 件だけ登録され、schedule が期待値
--       auto-skip-workouts '0 18 * * *'（JST 03:00）/ cleanup-ai-images '0 19 * * *'（JST 04:00）/
--       send-session-reminders '0 11 * * *'（JST 20:00）/ notify-trainer-alerts '10 21 * * *'（JST 06:10）/
--       check-cron-health '40 11,21 * * *'（JST 20:40 / 06:40）
--   (b) command が net.http_post で /functions/v1/<ジョブ名> を呼び、Vault の project_url / secret_key を
--       参照して secret キーを apikey ヘッダーで送る。旧方式（Vault の service_role_key・
--       Authorization ヘッダー）を含まない
--   (c) command に timeout_milliseconds を含み、値が 60000 以上（pg_net 既定の 5000ms では、
--       一時障害の再試行を含む関数の応答を待たずに timed_out になり、net._http_response で
--       結果を確認できない）
--   (d) command の body が既存どおり（timeout を足すために command 全体を書き換えているため、
--       body が変わっていないことを固定する）。空白・改行の連続は 1 つの空白に詰めてから比べる
--       （send-session-reminders と notify-trainer-alerts は 'dry_run', false から target_date の式までを
--        1 つの断片にしている。'dry_run', false だけだと target_date の組み立てが壊れても検知できない。
--        send-session-reminders は + 1（JST の明日）まで含む。JST の今日になることは
--        client_alert_push_test.sql で確かめる）
--   (e) command が SQL として解析・計画できる（EXPLAIN。(b)〜(d) は文字列の部分一致なので、
--       カンマ・括弧・$cmd$ の崩れや引数名の誤りで毎回失敗する command でも通ってしまうため）。
--       EXPLAIN（ANALYZE なし）は net.http_post を実行せず、HTTP リクエストも積まない
--   (f) HTTP の 4 本の command が、先頭で net.http_post の戻り値を自分の jobname で
--       public.cron_http_requests に記録する。check-cron-health は記録しない（設計書 §4.4）
--   (g) 監視自身以外で net.http_* を呼ぶ cron が記録を忘れていない（この表に無いジョブも含む。
--       新しい HTTP の cron を足して記録を忘れると、失敗しても通知されない）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 期待値（各ケースで 5 ジョブ分をループして検証する）
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE expected_cron_jobs (
  jobname text PRIMARY KEY,
  schedule text NOT NULL,
  body_fragment text NOT NULL,
  records_request boolean NOT NULL
) ON COMMIT DROP;

INSERT INTO expected_cron_jobs (jobname, schedule, body_fragment, records_request) VALUES
  ('auto-skip-workouts',     '0 18 * * *', $f$body := '{}'::jsonb$f$, true),
  ('cleanup-ai-images',      '0 19 * * *', $f$body := '{"dry_run": false}'::jsonb$f$, true),
  ('send-session-reminders', '0 11 * * *',
   $f$'dry_run', false, 'target_date', to_char(((now() AT TIME ZONE 'Asia/Tokyo')::date + 1), 'YYYY-MM-DD')$f$, true),
  ('notify-trainer-alerts',  '10 21 * * *',
   $f$'dry_run', false, 'target_date', to_char((now() AT TIME ZONE 'Asia/Tokyo')::date, 'YYYY-MM-DD')$f$, true),
  ('check-cron-health',      '40 11,21 * * *', $f$body := '{"dry_run": false}'::jsonb$f$, false);

-- -----------------------------------------------------------------------------
-- ケース(a): 登録と schedule
-- -----------------------------------------------------------------------------
\echo '--- case a: 5 ジョブが 1 件ずつ登録され、schedule が期待値であること'

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

    IF position(v_exp.body_fragment IN regexp_replace(v_command, '\s+', ' ', 'g')) = 0 THEN
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
    -- 末尾の空白と ; を落とした 1 文（command は net.http_post を呼ぶ INSERT か SELECT の 1 文だけのはず）
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

-- -----------------------------------------------------------------------------
-- ケース(f): HTTP の 4 本は発射を cron_http_requests に記録する（check-cron-health は記録しない）
--   空白・改行の連続は 1 つの空白に詰めてから、先頭の形で比べる（途中に INSERT の文字列があるだけでは通さない）
-- -----------------------------------------------------------------------------
\echo '--- case f: HTTP の 4 本が cron_http_requests に記録し、check-cron-health は記録しないこと'

DO $$
DECLARE
  v_exp record;
  v_command text;
  v_prefix text;
BEGIN
  FOR v_exp IN SELECT * FROM expected_cron_jobs ORDER BY jobname LOOP
    SELECT btrim(regexp_replace(command, '\s+', ' ', 'g')) INTO v_command
    FROM cron.job WHERE jobname = v_exp.jobname;

    IF v_exp.records_request THEN
      v_prefix := format(
        'INSERT INTO public.cron_http_requests (jobname, request_id) SELECT %L, net.http_post(',
        v_exp.jobname
      );
      IF left(v_command, char_length(v_prefix)) <> v_prefix THEN
        RAISE EXCEPTION 'FAIL: % の command が発射を記録していない（先頭が %）',
          v_exp.jobname, left(v_command, char_length(v_prefix));
      END IF;
      RAISE NOTICE 'OK: % は cron_http_requests に記録する', v_exp.jobname;
    ELSE
      IF position('cron_http_requests' IN v_command) > 0 THEN
        RAISE EXCEPTION 'FAIL: % は cron_http_requests に記録しない（応答が次の確認まで残らず、自分の失敗を自分では通知できない）',
          v_exp.jobname;
      END IF;
      RAISE NOTICE 'OK: % は cron_http_requests に記録しない', v_exp.jobname;
    END IF;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 監視自身以外で net.http_* を呼ぶ cron は、すべて記録する
--   expected_cron_jobs に無いジョブも見る（DB にある全ジョブが対象）
-- -----------------------------------------------------------------------------
\echo '--- case g: 監視自身以外で net.http_* を呼ぶ cron が記録を忘れていないこと'

DO $$
DECLARE
  v_job record;
  v_prefix text;
  v_count int := 0;
BEGIN
  FOR v_job IN
    SELECT jobname, btrim(regexp_replace(command, '\s+', ' ', 'g')) AS command
    FROM cron.job
    WHERE command ~ 'net\.http_'
      AND jobname IS DISTINCT FROM 'check-cron-health'
    ORDER BY jobname
  LOOP
    v_prefix := format(
      'INSERT INTO public.cron_http_requests (jobname, request_id) SELECT %L, net.http_post(',
      v_job.jobname
    );
    IF left(v_job.command, char_length(v_prefix)) <> v_prefix THEN
      RAISE EXCEPTION 'FAIL: cron ジョブ % は net.http_* を呼ぶが、発射を cron_http_requests に記録していない（失敗しても通知されない）',
        v_job.jobname;
    END IF;
    v_count := v_count + 1;
  END LOOP;

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'FAIL: 監視自身以外で net.http_* を呼ぶ cron が % 本（期待 4 本。増やしたら expected_cron_jobs にも足す）', v_count;
  END IF;
  RAISE NOTICE 'OK: 監視自身以外で net.http_* を呼ぶ cron は % 本で、すべて記録する', v_count;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CRON JOBS TESTS PASSED'
