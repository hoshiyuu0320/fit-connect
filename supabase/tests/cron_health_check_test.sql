-- =============================================================================
-- cron 失敗の監視（20261101000000_cron_health_monitor.sql）の DB 側テスト
-- （設計書 §4・§7: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md）
--
-- 応答の分類 cron_http_result_problem、確認の本体 run_cron_health_check、両表の権限を検証する自己完結テスト。
-- cron の command（5本の登録内容・記録の有無）は cron_jobs_test.sql が確かめる。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/cron_health_check_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CRON HEALTH CHECK TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データ（ジョブ・実行履歴・応答を含む）は BEGIN...ROLLBACK 内で作成され、DB には一切残らない。
--   pg_cron と pg_net のワーカーは未コミットの行を見ないので、試験のジョブは動かず HTTP も飛ばない
-- - 時刻はすべて now() からの相対で作る（run_cron_health_check は引数を取らない。本実行に時刻を
--   差し込める口を作らないため）。now() はトランザクションの開始時刻に固定されるので、閾値の前後を
--   秒の単位でぶらさずに確かめられる
-- - cron.timezone はセッションで変えられない（postmaster の設定）ので、予定時刻の期待値は「今の設定で
--   その時刻に動く M H * * * を作る」形で組み立てる。GMT 以外でも同じテストが通る
--   （cron.timezone = 'Asia/Tokyo' で再起動した隔離スタックでも確認する。計算を UTC 固定にする誤りは
--    そちらで落ちる）
--
-- 検証ケース:
--   (a) 分類: 設計書 §4.2 の全行（content が NULL・配列、outcome: null を含む）と判定の順序。
--       send-session-reminders の outcome.failed・cleanup-ai-images の failed は見ない
--   (b) 手順1: failed / start_time が NULL の failed / 時刻が両方 NULL の failed / 止まった行 /
--       48時間より前 / 1時間以内の実行中 / 削除したジョブ / detail は 200 文字まで
--   (c) 手順2: 予定時刻に実行があるとき・無いとき・2日前の予定・49時間前の予定・5分以内の予定・
--       窓（−1分〜+1時間）の内外・7日動いていないとき・初回実行の直後・止めて再開した直後（その予定時刻より
--       前に実行が無ければ出さない）・inactive・M H * * * 以外の形・jobname が NULL
--   (d) 手順3: 応答あり（200・500・タイムアウト・接続失敗）/ 15分以内の応答なし / 15分超 / 48時間超 / 評価済みは見ない
--   (e) 番号の巻き戻り: 同じ request_id の古い行と古い応答があっても INSERT が通り、新しい失敗が記録され、
--       古い応答を拾わない。一意制約が無いこと
--   (f) 2回呼んでも重複しない（セッションの TimeZone が違っても同じキーになる）
--   (g) 返り値: 通知済みは返らない・id の昇順・列
--   (h) 掃除: 90日の前後・未通知は残す・時刻が両方 NULL の failed の問題は残す（消すと再通知になる）
--   (i) 権限: anon / authenticated は表も関数もシーケンスも不可、service_role は §4.1 の範囲だけ。
--       関数の属性（SECURITY DEFINER / search_path / 揮発性）と RLS
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 既に記録があるスタックでも結果が変わらないよう、この2表は空にする（ROLLBACK で戻る）
DELETE FROM public.cron_health_problems;
DELETE FROM public.cron_http_requests;

SELECT current_setting('cron.timezone') AS "cron.timezone";

-- -----------------------------------------------------------------------------
-- 共通のヘルパー
-- -----------------------------------------------------------------------------

-- 問題が1行あり、jobname / kind / summary が期待どおりであること
CREATE FUNCTION pg_temp.expect_problem(
  p_label text, p_key text, p_jobname text, p_kind text, p_summary text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v record;
BEGIN
  SELECT p.jobname, p.kind, p.summary INTO v
  FROM public.cron_health_problems p WHERE p.source_key = p_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: % : 問題 % が記録されていない', p_label, p_key;
  END IF;
  IF v.jobname IS DISTINCT FROM p_jobname OR v.kind IS DISTINCT FROM p_kind OR v.summary IS DISTINCT FROM p_summary THEN
    RAISE EXCEPTION 'FAIL: % : 問題 % が (%, %, %)（期待 (%, %, %)）',
      p_label, p_key, v.jobname, v.kind, v.summary, p_jobname, p_kind, p_summary;
  END IF;
  RAISE NOTICE 'OK: % → % (%)', p_label, p_kind, p_summary;
END $$;

CREATE FUNCTION pg_temp.expect_no_problem(p_label text, p_key text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cron_health_problems p WHERE p.source_key = p_key) THEN
    RAISE EXCEPTION 'FAIL: % : 問題 % が記録された（期待 記録なし）', p_label, p_key;
  END IF;
  RAISE NOTICE 'OK: % → 問題なし', p_label;
END $$;

-- 今の cron.timezone でその時刻に動く毎日の schedule（M H * * *）
CREATE FUNCTION pg_temp.daily_schedule(p_at timestamptz) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT extract(minute FROM p_at AT TIME ZONE current_setting('cron.timezone'))::int
         || ' '
         || extract(hour FROM p_at AT TIME ZONE current_setting('cron.timezone'))::int
         || ' * * *';
$$;

-- ジョブの実行履歴を1行足す（時刻は start_time = p_at、end_time はその1秒後）。
-- postgres には cron.runid_seq の権限が無いので、runid は 930001〜 を自前で振る（本物の runid と重ならない大きさ）
CREATE TEMP SEQUENCE chk_runid START 930001;

CREATE FUNCTION pg_temp.add_run(p_jobname text, p_at timestamptz, p_status text DEFAULT 'succeeded')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO cron.job_run_details (runid, jobid, status, start_time, end_time, command, return_message)
  SELECT nextval('chk_runid'), j.jobid, p_status, p_at, p_at + interval '1 second', j.command, 'SELECT 1'
  FROM cron.job j
  WHERE j.jobname = p_jobname;
$$;

-- -----------------------------------------------------------------------------
-- ケース(a): 分類（§4.2 の表）
-- -----------------------------------------------------------------------------
\echo '--- case a: [分類] cron_http_result_problem が §4.2 の全行のとおりであること'

CREATE TEMP TABLE result_cases (
  label text PRIMARY KEY,
  jobname text NOT NULL,
  status_code integer,
  timed_out boolean,
  error_msg text,
  content text,
  expected_kind text,      -- NULL = 問題なし（0行）
  expected_summary text
) ON COMMIT DROP;

INSERT INTO result_cases VALUES
  -- HTTP まで届かなかった
  -- 実際の pg_net 0.14.0 の形（隔離スタックで確認）: タイムアウトも接続失敗も status_code と timed_out は NULL で、
  -- error_msg だけで見分ける。timed_out = true は pg_net の版が変わったときのために残す
  ('pg_net のタイムアウト',      'auto-skip-workouts', NULL, NULL,
   'Timeout of 60000 ms reached. Total time: 60009.180000 ms (DNS time: 0.010000 ms, TCP/SSL handshake time: 1.498000 ms, HTTP Request/Response time: 60007.658000 ms)',
   NULL, 'no_response', 'タイムアウト'),
  ('pg_net の接続失敗',          'auto-skip-workouts', NULL, NULL, 'Couldn''t connect to server', NULL, 'no_response', '接続失敗'),
  ('timed_out',                  'auto-skip-workouts', NULL, true,  'Timeout was reached', NULL, 'no_response', 'タイムアウト'),
  ('timed_out（error_msg なし）','auto-skip-workouts', NULL, true,  NULL, NULL, 'no_response', 'タイムアウト'),
  ('timed_out は status より先', 'auto-skip-workouts', 200,  true,  NULL, '{"status":"ok"}', 'no_response', 'タイムアウト'),
  ('error_msg（名前解決）',      'auto-skip-workouts', NULL, false, 'Could not resolve host', NULL, 'no_response', '接続失敗'),
  ('error_msg は status より先', 'auto-skip-workouts', 500,  false, 'Connection reset', '{}', 'no_response', '接続失敗'),
  -- 2xx 以外
  ('401',                        'cleanup-ai-images', 401, false, NULL, '{"error":"Unauthorized"}', 'http_error', 'HTTP 401'),
  ('404',                        'cleanup-ai-images', 404, false, NULL, NULL, 'http_error', 'HTTP 404'),
  ('500',                        'cleanup-ai-images', 500, false, NULL, '{"error":"x"}', 'http_error', 'HTTP 500'),
  ('503（JSON でない本文）',     'cleanup-ai-images', 503, false, NULL, '<html>', 'http_error', 'HTTP 503'),
  ('199（2xx の下）',            'cleanup-ai-images', 199, false, NULL, '{}', 'http_error', 'HTTP 199'),
  ('300（2xx の上）',            'cleanup-ai-images', 300, false, NULL, '{}', 'http_error', 'HTTP 300'),
  -- status_code が NULL（pg_net は返さないはずの形。HTTP <code> が作れない）
  ('status_code NULL',           'cleanup-ai-images', NULL, false, NULL, NULL, 'bad_result', '応答が不正'),
  ('status_code NULL で本文は正常', 'cleanup-ai-images', NULL, false, NULL, '{"status":"ok","dry_run":false}', 'bad_result', '応答が不正'),
  -- 2xx で中身が読めない
  ('content NULL',               'auto-skip-workouts', 200, false, NULL, NULL, 'bad_result', '応答が不正'),
  ('空の content',               'auto-skip-workouts', 200, false, NULL, '', 'bad_result', '応答が不正'),
  ('JSON でない',                'auto-skip-workouts', 200, false, NULL, 'OK', 'bad_result', '応答が不正'),
  ('JSON の配列',                'auto-skip-workouts', 200, false, NULL, '[{"status":"ok"}]', 'bad_result', '応答が不正'),
  ('JSON の数',                  'auto-skip-workouts', 200, false, NULL, '1', 'bad_result', '応答が不正'),
  ('JSON の文字列',              'auto-skip-workouts', 200, false, NULL, '"ok"', 'bad_result', '応答が不正'),
  ('JSON の null',               'auto-skip-workouts', 204, false, NULL, 'null', 'bad_result', '応答が不正'),
  -- dry run のまま
  ('dryRun true',                'auto-skip-workouts', 200, false, NULL, '{"status":"ok","dryRun":true}', 'bad_result', 'dry run のまま'),
  ('dry_run true',               'cleanup-ai-images',  200, false, NULL, '{"status":"ok","dry_run":true}', 'bad_result', 'dry run のまま'),
  ('dry run は detection より先','notify-trainer-alerts', 200, false, NULL, '{"dryRun":true,"detectionReady":false}', 'bad_result', 'dry run のまま'),
  ('dryRun false',               'auto-skip-workouts', 200, false, NULL, '{"status":"ok","dryRun":false}', NULL, NULL),
  ('dry_run false',              'cleanup-ai-images',  299, false, NULL, '{"status":"ok","dry_run":false}', NULL, NULL),
  ('dryRun が文字列の true',     'auto-skip-workouts', 200, false, NULL, '{"dryRun":"true"}', NULL, NULL),
  -- notify-trainer-alerts
  ('自動チェック未完了',         'notify-trainer-alerts', 200, false, NULL,
   '{"status":"ok","dryRun":false,"detectionReady":false,"outcome":{"sent":0,"failed":0}}', 'bad_result', '自動チェック未完了'),
  ('outcome: null',              'notify-trainer-alerts', 200, false, NULL,
   '{"status":"ok","dryRun":false,"detectionReady":true,"outcome":null}', 'bad_result', '送信結果不明'),
  ('outcome なし',               'notify-trainer-alerts', 200, false, NULL,
   '{"status":"ok","dryRun":false,"detectionReady":true}', 'bad_result', '送信結果不明'),
  ('outcome が配列',             'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":[]}', 'bad_result', '送信結果不明'),
  ('failed 1',                   'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"sent":2,"partial":0,"skipped":0,"failed":1,"pending":0,"duplicate":0,"missing":0,"skippedBy":{"no_tokens":0,"disabled":0,"quiet_hours":0,"vapid":0,"other":0}}}',
   'bad_result', '送信失敗 1件'),
  ('pending 1',                  'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":0,"pending":1,"missing":0,"skippedBy":{"vapid":0}}}', 'bad_result', '送信失敗 1件'),
  ('missing 1',                  'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":0,"pending":0,"missing":1,"skippedBy":{"vapid":0}}}', 'bad_result', '送信失敗 1件'),
  ('skippedBy.vapid 1',          'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":0,"pending":0,"missing":0,"skipped":1,"skippedBy":{"vapid":1}}}', 'bad_result', '送信失敗 1件'),
  ('4種の合計',                  'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":2,"pending":3,"missing":4,"skippedBy":{"vapid":5}}}', 'bad_result', '送信失敗 14件'),
  ('送信の問題なし',             'notify-trainer-alerts', 200, false, NULL,
   '{"status":"ok","dryRun":false,"detectionReady":true,"trainerCount":3,"alreadyLogged":0,"digests":[],"outcome":{"sent":2,"partial":1,"skipped":2,"failed":0,"pending":0,"duplicate":null,"missing":0,"skippedBy":{"no_tokens":1,"disabled":1,"quiet_hours":0,"vapid":0,"other":0}}}',
   NULL, NULL),
  ('件数が数でない（例外）',     'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":"abc"}}', 'bad_result', '応答が不正'),
  ('skippedBy が無い',           'notify-trainer-alerts', 200, false, NULL,
   '{"detectionReady":true,"outcome":{"failed":0}}', NULL, NULL),
  -- 他のジョブでは見ない項目
  ('他のジョブの detectionReady false', 'auto-skip-workouts', 200, false, NULL, '{"detectionReady":false}', NULL, NULL),
  ('send-session-reminders の outcome.failed は見ない', 'send-session-reminders', 200, false, NULL,
   '{"status":"ok","dryRun":false,"outcome":{"sent":0,"failed":5}}', NULL, NULL),
  ('send-session-reminders の outcome なしは問題なし', 'send-session-reminders', 200, false, NULL,
   '{"status":"ok","dryRun":false}', NULL, NULL),
  ('cleanup-ai-images の failed は見ない', 'cleanup-ai-images', 200, false, NULL,
   '{"status":"ok","dry_run":false,"deleted":1,"failed":3}', NULL, NULL),
  -- timed_out が NULL は false と同じ
  ('timed_out NULL',             'auto-skip-workouts', 200, NULL, NULL, '{"status":"ok"}', NULL, NULL);

DO $$
DECLARE
  v_case record;
  v_rows integer;
  v_kind text;
  v_summary text;
BEGIN
  FOR v_case IN SELECT * FROM result_cases ORDER BY label LOOP
    SELECT count(*), min(p.kind), min(p.summary) INTO v_rows, v_kind, v_summary
    FROM public.cron_http_result_problem(
      v_case.jobname, v_case.status_code, v_case.timed_out, v_case.error_msg, v_case.content
    ) p;

    IF v_case.expected_kind IS NULL THEN
      IF v_rows <> 0 THEN
        RAISE EXCEPTION 'FAIL: % : (%, %) が返った（期待 0 行）', v_case.label, v_kind, v_summary;
      END IF;
    ELSIF v_rows <> 1 OR v_kind IS DISTINCT FROM v_case.expected_kind
          OR v_summary IS DISTINCT FROM v_case.expected_summary THEN
      RAISE EXCEPTION 'FAIL: % : % 行 (%, %)（期待 1 行 (%, %)）',
        v_case.label, v_rows, v_kind, v_summary, v_case.expected_kind, v_case.expected_summary;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 分類 % ケース', (SELECT count(*) FROM result_cases);
END $$;

\echo '--- case a-2: [分類] detail（error_msg か本文の先頭、200 文字まで）'

DO $$
DECLARE
  v_detail text;
BEGIN
  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', NULL, true, 'Timeout was reached', NULL) p;
  IF v_detail IS DISTINCT FROM 'Timeout was reached' THEN
    RAISE EXCEPTION 'FAIL: タイムアウトの detail が %', v_detail;
  END IF;

  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', NULL, false, 'refused', NULL) p;
  IF v_detail IS DISTINCT FROM 'refused' THEN
    RAISE EXCEPTION 'FAIL: 接続失敗の detail が %', v_detail;
  END IF;

  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', 500, false, NULL, '{"error":"boom"}') p;
  IF v_detail IS DISTINCT FROM '{"error":"boom"}' THEN
    RAISE EXCEPTION 'FAIL: HTTP 500 の detail が %', v_detail;
  END IF;

  -- 日本語（マルチバイト）でも文字数で切る
  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', 500, false, NULL, repeat('失', 1000)) p;
  IF v_detail IS DISTINCT FROM repeat('失', 200) THEN
    RAISE EXCEPTION 'FAIL: 本文の detail が 200 文字に切られていない（% 文字）', char_length(v_detail);
  END IF;

  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', NULL, true, repeat('e', 1000), NULL) p;
  IF char_length(v_detail) IS DISTINCT FROM 200 THEN
    RAISE EXCEPTION 'FAIL: error_msg の detail が 200 文字に切られていない（% 文字）', char_length(v_detail);
  END IF;

  -- 例外の経路（JSON でない本文）も本文の先頭を残す
  SELECT p.detail INTO v_detail FROM public.cron_http_result_problem('x', 200, false, NULL, repeat('z', 1000)) p;
  IF v_detail IS DISTINCT FROM repeat('z', 200) THEN
    RAISE EXCEPTION 'FAIL: JSON でない本文の detail が %', left(v_detail, 40);
  END IF;
  RAISE NOTICE 'OK: detail は error_msg か本文の先頭で、200 文字まで';
END $$;

-- -----------------------------------------------------------------------------
-- 試験データ: 手順1（実行履歴）。ジョブは手順2の対象にならない schedule（毎年1回）で作る
--   runid は 910001〜 に固定する（本物の runid と重ならない大きさ）
-- -----------------------------------------------------------------------------
\echo '--- setup: 手順1〜3 の試験データ作成'

DO $$
BEGIN
  PERFORM cron.schedule('chk-failed', '0 0 1 1 *', 'SELECT 1');
END $$;

INSERT INTO cron.job_run_details (runid, jobid, status, return_message, start_time, end_time)
SELECT v.runid, j.jobid, v.status, v.message, now() + v.start_at, now() + v.end_at
FROM (VALUES
  (910001::bigint, 'failed',    'boom',                interval '-1 hour',    interval '-59 minutes'),
  -- 起動前に失敗した行は start_time が NULL（job startup timeout など）
  (910002,         'failed',    'job startup timeout', NULL,                  interval '-2 hours'),
  -- starting のまま DB が再起動した行は時刻がどちらも NULL
  (910003,         'failed',    'server restarted',    NULL,                  NULL),
  (910004,         'running',   NULL,                  interval '-70 minutes', NULL),
  (910005,         'running',   NULL,                  interval '-50 minutes', NULL),
  (910006,         'failed',    'at 47h',              interval '-47 hours',  interval '-47 hours'),
  (910007,         'failed',    'at 49h',              interval '-49 hours',  interval '-49 hours'),
  (910008,         'running',   NULL,                  interval '-47 hours',  NULL),
  (910009,         'running',   NULL,                  interval '-49 hours',  NULL),
  (910010,         'succeeded', '1 row',               interval '-1 hour',    interval '-1 hour'),
  (910012,         'starting',  NULL,                  NULL,                  NULL),
  (910013,         'failed',    repeat('長', 500),     interval '-1 hour',    interval '-1 hour'),
  (910015,         NULL,        NULL,                  interval '-2 hours',   NULL),
  (910016,         'failed',    'end only at 49h',     NULL,                  interval '-49 hours')
) AS v(runid, status, message, start_at, end_at)
CROSS JOIN cron.job j
WHERE j.jobname = 'chk-failed';

-- cron.job に無いジョブ（削除したジョブ）の失敗と、jobid が NULL の失敗（どちらも確認を止めない）
INSERT INTO cron.job_run_details (runid, jobid, status, return_message, start_time, end_time)
VALUES
  (910011, 99999999, 'failed', 'deleted job', now() - interval '1 hour', now() - interval '1 hour'),
  (910014, NULL,     'failed', 'no jobid',    now() - interval '1 hour', now() - interval '1 hour');

-- -----------------------------------------------------------------------------
-- 試験データ: 手順2（毎日のジョブ）
--   sched = 予定時刻（今から scheduled_ago 前を分で切り捨てた時刻。今の cron.timezone で M H を作る）。
--   runs = 実行履歴（sched からの相対）。expected = 未実行になる予定時刻（sched からの相対）
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE daily_cases (
  jobname text PRIMARY KEY,
  scheduled_ago interval NOT NULL,
  runs interval[] NOT NULL,
  active boolean NOT NULL DEFAULT true,
  expected interval[] NOT NULL,
  sched timestamptz
) ON COMMIT DROP;

INSERT INTO daily_cases (jobname, scheduled_ago, runs, active, expected) VALUES
  -- 予定時刻に実行があるとき / 無いとき
  ('chk-daily-ran',        '30 minutes', '{0,-1 day}',          true, '{}'),
  ('chk-daily-missed',     '30 minutes', '{-1 day}',            true, '{0}'),
  -- 2日前の予定（47時間前は窓の中）。今日の分も無いので2つ
  ('chk-daily-47h',        '47 hours',   '{-1 day}',            true, '{0,1 day}'),
  -- 49時間前の予定は窓の外。残りの2つだけ
  ('chk-daily-49h',        '49 hours',   '{-1 day}',            true, '{1 day,2 days}'),
  -- 5分以内の予定はまだ見ない（6分前は見る）
  ('chk-daily-3min',       '3 minutes',  '{-1 day}',            true, '{}'),
  ('chk-daily-6min',       '6 minutes',  '{-1 day}',            true, '{0}'),
  -- 実行の窓（−1分〜+1時間）
  ('chk-daily-before-30s', '2 hours',    '{-30 seconds,-1 day}', true, '{}'),
  ('chk-daily-after-59m',  '2 hours',    '{59 minutes,-1 day}', true, '{}'),
  ('chk-daily-before-2m',  '2 hours',    '{-2 minutes,-1 day}', true, '{0}'),
  ('chk-daily-after-61m',  '2 hours',    '{61 minutes,-1 day}', true, '{0}'),
  -- 直近7日に1回も動いていないジョブは対象外（6日前に動いていれば対象）
  ('chk-daily-6days',      '30 minutes', '{-6 days}',           true, '{0,-1 day}'),
  ('chk-daily-8days',      '30 minutes', '{-8 days}',           true, '{}'),
  ('chk-daily-never',      '30 minutes', '{}',                  true, '{}'),
  -- その予定時刻より前に実行が無ければ出さない。新設のジョブの初回実行の直後に、まだ動いていなかった
  -- 昨日の予定時刻（窓の中）を未実行にしない
  ('chk-daily-first-run',  '30 minutes', '{0}',                 true, '{}'),
  -- 7日以上止めて再開したジョブ（10日前の実行の後に今日初めて動いた）も同じ
  ('chk-daily-resumed',    '30 minutes', '{-10 days,0}',        true, '{}'),
  -- 判定は予定時刻ごと: 12時間前に初めて動いたジョブは、今日の予定だけが未実行（昨日の予定は出さない）
  ('chk-daily-first-12h',  '30 minutes', '{-12 hours}',         true, '{0}'),
  -- inactive は人が止めたものなので見ない
  ('chk-daily-inactive',   '30 minutes', '{-1 day}',            false, '{}');

UPDATE daily_cases SET sched = date_trunc('minute', now() - scheduled_ago);

DO $$
DECLARE
  v_case record;
  v_offset interval;
BEGIN
  FOR v_case IN SELECT * FROM daily_cases LOOP
    PERFORM cron.schedule(v_case.jobname, pg_temp.daily_schedule(v_case.sched), 'SELECT 1');
    IF NOT v_case.active THEN
      PERFORM cron.alter_job((SELECT j.jobid FROM cron.job j WHERE j.jobname = v_case.jobname), active := false);
    END IF;
    FOREACH v_offset IN ARRAY v_case.runs LOOP
      PERFORM pg_temp.add_run(v_case.jobname, v_case.sched + v_offset);
    END LOOP;
  END LOOP;

  -- 失敗した実行も「動いた」に数える（失敗は手順1で出る。二重に数えない）
  PERFORM cron.schedule('chk-daily-failed-run', pg_temp.daily_schedule(now() - interval '30 minutes'), 'SELECT 1');
  PERFORM pg_temp.add_run('chk-daily-failed-run', date_trunc('minute', now() - interval '30 minutes'), 'failed');
  PERFORM pg_temp.add_run('chk-daily-failed-run', date_trunc('minute', now() - interval '30 minutes') - interval '1 day');

  -- start_time が NULL の実行は end_time で見る
  PERFORM cron.schedule('chk-daily-end-only', pg_temp.daily_schedule(now() - interval '30 minutes'), 'SELECT 1');
  INSERT INTO cron.job_run_details (runid, jobid, status, return_message, start_time, end_time)
  SELECT nextval('chk_runid'), j.jobid, 'failed', 'job startup timeout', NULL,
         date_trunc('minute', now() - interval '30 minutes') + interval '10 seconds'
  FROM cron.job j WHERE j.jobname = 'chk-daily-end-only';
  PERFORM pg_temp.add_run('chk-daily-end-only', date_trunc('minute', now() - interval '30 minutes') - interval '1 day');

  -- M H * * * 以外の形は見ない（どれも最近動いていて、今の時刻の前後に実行が無い）
  PERFORM cron.schedule('chk-other-monitor', '40 11,21 * * *', 'SELECT 1');
  PERFORM cron.schedule('chk-other-every5', '*/5 * * * *', 'SELECT 1');
  PERFORM cron.schedule('chk-other-weekly', '0 0 * * 1', 'SELECT 1');
  PERFORM cron.schedule('chk-other-monthly', '0 0 1 * *', 'SELECT 1');
  PERFORM cron.schedule('chk-other-seconds', '30 seconds', 'SELECT 1');
  PERFORM pg_temp.add_run('chk-other-monitor', now() - interval '3 days');
  PERFORM pg_temp.add_run('chk-other-every5', now() - interval '3 days');
  PERFORM pg_temp.add_run('chk-other-weekly', now() - interval '3 days');
  PERFORM pg_temp.add_run('chk-other-monthly', now() - interval '3 days');
  PERFORM pg_temp.add_run('chk-other-seconds', now() - interval '3 days');

  -- jobname が NULL のジョブ（cron.schedule の2引数版）でも確認を止めない
  PERFORM set_config('chk.unnamed_jobid',
    cron.schedule(pg_temp.daily_schedule(now() - interval '30 minutes'), 'SELECT 1')::text, true);
  INSERT INTO cron.job_run_details (runid, jobid, status, start_time, end_time)
  VALUES (nextval('chk_runid'), current_setting('chk.unnamed_jobid')::bigint, 'succeeded',
          now() - interval '3 days', now() - interval '3 days');
END $$;

-- -----------------------------------------------------------------------------
-- 試験データ: 手順3（HTTP の応答）
--   request_id は 920000 台に固定する（ローカルの本物の番号と重ならない大きさ）
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE request_cases (
  label text PRIMARY KEY,
  request_id bigint NOT NULL,
  jobname text NOT NULL,
  requested_ago interval NOT NULL,
  response_ago interval,      -- NULL = 応答なし
  status_code integer,
  timed_out boolean,
  error_msg text,
  content text,
  expected_kind text,         -- NULL = 問題なし
  expected_summary text,
  expected_checked boolean NOT NULL,
  row_id bigint
) ON COMMIT DROP;

INSERT INTO request_cases
  (label, request_id, jobname, requested_ago, response_ago, status_code, timed_out, error_msg, content,
   expected_kind, expected_summary, expected_checked)
VALUES
  ('応答あり 200',         920001, 'auto-skip-workouts', '3 hours', '3 hours', 200, false, NULL, '{"status":"ok","dryRun":false}',
   NULL, NULL, true),
  ('応答あり 500',         920002, 'cleanup-ai-images',  '3 hours', '3 hours', 500, false, NULL, '{"error":"boom"}',
   'http_error', 'HTTP 500', true),
  ('応答あり タイムアウト', 920003, 'cleanup-ai-images',  '3 hours', '3 hours', NULL, NULL, 'Timeout of 60000 ms reached. Total time: 60009.180000 ms', NULL,
   'no_response', 'タイムアウト', true),
  ('応答あり 接続失敗',     920006, 'cleanup-ai-images',  '3 hours', '3 hours', NULL, NULL, 'Couldn''t connect to server', NULL,
   'no_response', '接続失敗', true),
  ('応答あり 発射と同時刻', 920004, 'auto-skip-workouts', '3 hours', '3 hours', 401, false, NULL, '{}',
   'http_error', 'HTTP 401', true),
  ('応答あり 分類に jobname が渡る', 920005, 'notify-trainer-alerts', '3 hours', '3 hours', 200, false, NULL, '{"detectionReady":false}',
   'bad_result', '自動チェック未完了', true),
  -- 応答なし
  ('応答なし 10分',        920011, 'auto-skip-workouts', '10 minutes', NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, false),
  ('応答なし 20分',        920012, 'auto-skip-workouts', '20 minutes', NULL, NULL, NULL, NULL, NULL,
   'no_response', '結果不明', true),
  ('応答なし 47時間',      920013, 'auto-skip-workouts', '47 hours', NULL, NULL, NULL, NULL, NULL,
   'no_response', '結果不明', true),
  ('応答なし 49時間',      920014, 'auto-skip-workouts', '49 hours', NULL, NULL, NULL, NULL, NULL,
   NULL, NULL, true);

DO $$
DECLARE
  v_case record;
  v_id bigint;
  v_requested_at timestamptz;
BEGIN
  FOR v_case IN SELECT * FROM request_cases ORDER BY request_id LOOP
    v_requested_at := now() - v_case.requested_ago;
    INSERT INTO public.cron_http_requests (jobname, request_id, requested_at)
    VALUES (v_case.jobname, v_case.request_id, v_requested_at)
    RETURNING id INTO v_id;
    UPDATE request_cases SET row_id = v_id WHERE label = v_case.label;

    IF v_case.response_ago IS NOT NULL THEN
      INSERT INTO net._http_response (id, status_code, timed_out, error_msg, content, created)
      VALUES (v_case.request_id, v_case.status_code, v_case.timed_out, v_case.error_msg, v_case.content,
              now() - v_case.response_ago);
    END IF;
  END LOOP;
END $$;

-- 番号の巻き戻り（ケース e）
--   rollback_a: 古い行（評価済み）と古い応答（500）。同じ番号で新しい行を入れ、新しい応答は 500。
--     新しい失敗が新しい行の req:<id> で記録され、古い行は評価し直さない
--   rollback_b: 古い行（評価済み）と古い応答（500）。同じ番号で新しい行を入れ、20分たっても新しい応答は無い。
--     古い応答を拾わず 結果不明 になる（HTTP 500 にしない）
--   rollback_c: 古い応答（500）だけが残っていて、新しい応答は 200。問題なし
--   rollback_d: 発射の後に同じ番号の応答が2つ（200 の後に、番号がまた戻って別の要求の 500）。
--     発射の後で最初の応答を見る
CREATE TEMP TABLE rollback_rows (label text PRIMARY KEY, row_id bigint NOT NULL) ON COMMIT DROP;

DO $$
DECLARE
  v_id bigint;
BEGIN
  -- rollback_a
  INSERT INTO public.cron_http_requests (jobname, request_id, requested_at, checked_at)
  VALUES ('auto-skip-workouts', 920021, now() - interval '3 days', now() - interval '3 days')
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('a_old', v_id);
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES (920021, 500, false, '{"error":"old"}', now() - interval '3 days');

  -- cron の command と同じ形の INSERT（一意制約があるとここで落ち、本番の HTTP の cron が飛ばなくなる）
  INSERT INTO public.cron_http_requests (jobname, request_id)
  SELECT 'auto-skip-workouts', 920021::bigint
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('a_new', v_id);
  -- now() = 発射の時刻 なので、created は同時刻以降にする
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES (920021, 503, false, '{"error":"new"}', now());

  -- rollback_b
  INSERT INTO public.cron_http_requests (jobname, request_id, requested_at, checked_at)
  VALUES ('cleanup-ai-images', 920022, now() - interval '3 days', now() - interval '3 days')
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('b_old', v_id);
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES (920022, 500, false, '{"error":"old"}', now() - interval '3 days');

  INSERT INTO public.cron_http_requests (jobname, request_id, requested_at)
  VALUES ('cleanup-ai-images', 920022, now() - interval '20 minutes')
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('b_new', v_id);

  -- rollback_c
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES (920023, 500, false, '{"error":"old"}', now() - interval '3 days');
  INSERT INTO public.cron_http_requests (jobname, request_id, requested_at)
  VALUES ('send-session-reminders', 920023, now() - interval '1 hour')
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('c_new', v_id);
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES (920023, 200, false, '{"status":"ok","dryRun":false}', now() - interval '59 minutes');

  -- rollback_d
  INSERT INTO public.cron_http_requests (jobname, request_id, requested_at)
  VALUES ('send-session-reminders', 920024, now() - interval '2 hours')
  RETURNING id INTO v_id;
  INSERT INTO rollback_rows VALUES ('d_new', v_id);
  INSERT INTO net._http_response (id, status_code, timed_out, content, created)
  VALUES
    (920024, 500, false, '{"error":"later request"}', now() - interval '10 minutes'),
    (920024, 200, false, '{"status":"ok","dryRun":false}', now() - interval '119 minutes');
END $$;

-- 掃除（ケース h）の試験データ
INSERT INTO public.cron_http_requests (jobname, request_id, requested_at, checked_at)
VALUES
  ('chk-clean-old',   920031, now() - interval '91 days', now() - interval '91 days'),
  ('chk-clean-keep',  920032, now() - interval '89 days', now() - interval '89 days'),
  -- 未評価のまま古くなった行は、手順3で checked_at を埋めたうえで同じ実行で消える
  ('chk-clean-unchecked', 920033, now() - interval '91 days', NULL);

INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary, notified_at, created_at)
VALUES
  ('test:notified-91', 'chk-clean', 'job_failed', now() - interval '91 days', '失敗', now() - interval '91 days', now() - interval '91 days'),
  ('test:notified-89', 'chk-clean', 'job_failed', now() - interval '89 days', '失敗', now() - interval '89 days', now() - interval '89 days'),
  -- 未通知は何日たっても消さない（宛先を設定した後の確認で送る）
  ('test:unnotified-old', 'chk-clean', 'job_failed', now() - interval '100 days', '失敗', NULL, now() - interval '100 days'),
  -- 最近通知した問題（通知までに時間がかかった古い問題も、通知から90日は残す）
  ('test:notified-recently', 'chk-clean', 'job_failed', now() - interval '100 days', '失敗', now() - interval '1 day', now() - interval '100 days');

-- 時刻がどちらも NULL の failed の問題: 消すと次の確認で記録し直されて、もう1回通知してしまう
INSERT INTO cron.job_run_details (runid, jobid, status, return_message, start_time, end_time)
SELECT 910021, j.jobid, 'failed', 'server restarted', NULL, NULL
FROM cron.job j WHERE j.jobname = 'chk-failed';
INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary, notified_at, created_at)
VALUES ('run:910021', 'chk-failed', 'job_failed', now() - interval '91 days', '失敗', now() - interval '91 days', now() - interval '91 days');

-- -----------------------------------------------------------------------------
-- 1回目の確認（以降のケースはこの結果を見る。セッションの TimeZone は既定のまま）
-- -----------------------------------------------------------------------------
\echo '--- run: 1回目の run_cron_health_check'

CREATE TEMP TABLE first_run ON COMMIT DROP AS
  SELECT row_number() OVER () AS position, r.* FROM public.run_cron_health_check() r;

-- -----------------------------------------------------------------------------
-- ケース(b): 手順1
-- -----------------------------------------------------------------------------
\echo '--- case b: [手順1] 失敗・止まった行の記録'

SELECT pg_temp.expect_problem('failed',                   'run:910001', 'chk-failed', 'job_failed', '失敗');
SELECT pg_temp.expect_problem('start_time が NULL の failed', 'run:910002', 'chk-failed', 'job_failed', '失敗');
SELECT pg_temp.expect_problem('時刻が両方 NULL の failed',   'run:910003', 'chk-failed', 'job_failed', '失敗');
SELECT pg_temp.expect_problem('70分止まった行',            'run:910004', 'chk-failed', 'job_failed', '未完了');
SELECT pg_temp.expect_no_problem('50分の実行中',           'run:910005');
SELECT pg_temp.expect_problem('47時間前の failed',         'run:910006', 'chk-failed', 'job_failed', '失敗');
SELECT pg_temp.expect_no_problem('49時間前の failed',      'run:910007');
SELECT pg_temp.expect_problem('47時間前に止まった行',      'run:910008', 'chk-failed', 'job_failed', '未完了');
SELECT pg_temp.expect_no_problem('49時間前に止まった行',   'run:910009');
SELECT pg_temp.expect_no_problem('succeeded',              'run:910010');
SELECT pg_temp.expect_problem('削除したジョブ',            'run:910011', 'jobid:99999999', 'job_failed', '失敗');
SELECT pg_temp.expect_no_problem('時刻が無い starting',    'run:910012');
SELECT pg_temp.expect_problem('jobid が NULL',             'run:910014', 'jobid:不明', 'job_failed', '失敗');
SELECT pg_temp.expect_problem('status が NULL で止まった行', 'run:910015', 'chk-failed', 'job_failed', '未完了');
SELECT pg_temp.expect_no_problem('end_time だけの 49時間前の failed', 'run:910016');

DO $$
DECLARE
  v record;
BEGIN
  -- occurred_at（start_time → end_time → 記録した時刻）・detail（return_message、200 文字まで）
  SELECT p.occurred_at, p.detail INTO v FROM public.cron_health_problems p WHERE p.source_key = 'run:910001';
  IF v.occurred_at IS DISTINCT FROM now() - interval '1 hour' OR v.detail IS DISTINCT FROM 'boom' THEN
    RAISE EXCEPTION 'FAIL: run:910001 の occurred_at / detail が % / %', v.occurred_at, v.detail;
  END IF;

  SELECT p.occurred_at, p.detail INTO v FROM public.cron_health_problems p WHERE p.source_key = 'run:910002';
  IF v.occurred_at IS DISTINCT FROM now() - interval '2 hours' OR v.detail IS DISTINCT FROM 'job startup timeout' THEN
    RAISE EXCEPTION 'FAIL: run:910002（start_time が NULL）の occurred_at / detail が % / %', v.occurred_at, v.detail;
  END IF;

  SELECT p.occurred_at INTO v FROM public.cron_health_problems p WHERE p.source_key = 'run:910003';
  IF v.occurred_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: run:910003（時刻が両方 NULL）の occurred_at が %（期待 記録した時刻）', v.occurred_at;
  END IF;

  SELECT p.detail INTO v FROM public.cron_health_problems p WHERE p.source_key = 'run:910013';
  IF v.detail IS DISTINCT FROM repeat('長', 200) THEN
    RAISE EXCEPTION 'FAIL: run:910013 の detail が 200 文字に切られていない（% 文字）', char_length(v.detail);
  END IF;

  RAISE NOTICE 'OK: occurred_at と detail';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): 手順2
--   source_key の epoch を sched（今の cron.timezone の M H で作った時刻）から組み立てるので、
--   予定時刻の計算を cron.timezone と違う時刻帯で行うと落ちる
-- -----------------------------------------------------------------------------
\echo '--- case c: [手順2] 動かなかった毎日のジョブ（cron.timezone の時刻計算を含む）'

DO $$
DECLARE
  v_case record;
  v_actual text[];
  v_expected text[];
BEGIN
  FOR v_case IN SELECT * FROM daily_cases ORDER BY jobname LOOP
    SELECT COALESCE(array_agg(p.source_key ORDER BY p.source_key), '{}') INTO v_actual
    FROM public.cron_health_problems p
    WHERE p.jobname = v_case.jobname AND p.kind = 'missed_run';

    SELECT COALESCE(array_agg(k ORDER BY k), '{}') INTO v_expected
    FROM (
      SELECT 'missed:' || v_case.jobname || ':' || extract(epoch FROM v_case.sched + o)::bigint AS k
      FROM unnest(v_case.expected) AS o
    ) s;

    IF v_actual IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'FAIL: % の未実行が %（期待 %。sched = %）', v_case.jobname, v_actual, v_expected, v_case.sched;
    END IF;
    RAISE NOTICE 'OK: % の未実行は % 件', v_case.jobname, cardinality(v_actual);
  END LOOP;
END $$;

DO $$
DECLARE
  v record;
  v_sched timestamptz := date_trunc('minute', now() - interval '30 minutes');
  v_key text;
BEGIN
  -- 中身（occurred_at = 予定時刻、summary = 未実行）
  v_key := 'missed:chk-daily-missed:' || extract(epoch FROM v_sched)::bigint;
  SELECT p.occurred_at, p.summary, p.kind, p.jobname, p.detail INTO v
  FROM public.cron_health_problems p WHERE p.source_key = v_key;
  IF v.occurred_at IS DISTINCT FROM v_sched OR v.summary IS DISTINCT FROM '未実行'
     OR v.kind IS DISTINCT FROM 'missed_run' OR v.jobname IS DISTINCT FROM 'chk-daily-missed' THEN
    RAISE EXCEPTION 'FAIL: % の中身が %', v_key, v;
  END IF;

  -- 失敗した実行・start_time が NULL の実行は「動いた」に数える
  IF EXISTS (SELECT 1 FROM public.cron_health_problems p
             WHERE p.jobname IN ('chk-daily-failed-run', 'chk-daily-end-only') AND p.kind = 'missed_run') THEN
    RAISE EXCEPTION 'FAIL: 失敗した実行・start_time が NULL の実行が未実行に数えられた';
  END IF;
  IF (SELECT count(*) FROM public.cron_health_problems p
      WHERE p.jobname = 'chk-daily-failed-run' AND p.kind = 'job_failed') <> 1 THEN
    RAISE EXCEPTION 'FAIL: 失敗した実行が job_failed として記録されていない';
  END IF;

  -- M H * * * 以外の形は見ない
  IF EXISTS (SELECT 1 FROM public.cron_health_problems p
             WHERE p.jobname LIKE 'chk-other-%') THEN
    RAISE EXCEPTION 'FAIL: M H * * * 以外の schedule のジョブが未実行に数えられた: %',
      (SELECT array_agg(p.source_key) FROM public.cron_health_problems p WHERE p.jobname LIKE 'chk-other-%');
  END IF;

  -- jobname が NULL のジョブ（jobid:<id> と書く。今日の分と昨日の分が無い）
  v_key := 'missed:jobid:' || current_setting('chk.unnamed_jobid') || ':' || extract(epoch FROM v_sched)::bigint;
  PERFORM pg_temp.expect_problem('jobname が NULL のジョブ', v_key,
    'jobid:' || current_setting('chk.unnamed_jobid'), 'missed_run', '未実行');

  RAISE NOTICE 'OK: 手順2 の中身・失敗した実行・他の形・jobname が NULL';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 手順3
-- -----------------------------------------------------------------------------
\echo '--- case d: [手順3] HTTP の応答（応答あり・15分以内・15分超・48時間超）'

DO $$
DECLARE
  v_case record;
  v_key text;
  v_checked timestamptz;
  v record;
BEGIN
  FOR v_case IN SELECT * FROM request_cases ORDER BY request_id LOOP
    v_key := 'req:' || v_case.row_id;
    IF v_case.expected_kind IS NULL THEN
      PERFORM pg_temp.expect_no_problem(v_case.label, v_key);
    ELSE
      PERFORM pg_temp.expect_problem(v_case.label, v_key, v_case.jobname, v_case.expected_kind, v_case.expected_summary);
      SELECT p.occurred_at INTO v FROM public.cron_health_problems p WHERE p.source_key = v_key;
      IF v.occurred_at IS DISTINCT FROM now() - v_case.requested_ago THEN
        RAISE EXCEPTION 'FAIL: % の occurred_at が %（期待 発射の時刻）', v_case.label, v.occurred_at;
      END IF;
    END IF;

    SELECT q.checked_at INTO v_checked FROM public.cron_http_requests q WHERE q.id = v_case.row_id;
    IF (v_checked IS NOT NULL) IS DISTINCT FROM v_case.expected_checked THEN
      RAISE EXCEPTION 'FAIL: % の checked_at が %（期待 埋まる=%）', v_case.label, v_checked, v_case.expected_checked;
    END IF;
  END LOOP;

  -- 500 の detail は本文の先頭
  SELECT p.detail INTO v FROM public.cron_health_problems p
  WHERE p.source_key = 'req:' || (SELECT c.row_id FROM request_cases c WHERE c.label = '応答あり 500');
  IF v.detail IS DISTINCT FROM '{"error":"boom"}' THEN
    RAISE EXCEPTION 'FAIL: HTTP 500 の detail が %', v.detail;
  END IF;

  RAISE NOTICE 'OK: 手順3 の % ケース', (SELECT count(*) FROM request_cases);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): 番号の巻き戻り（設計書 §2・§4.1「重要」）
-- -----------------------------------------------------------------------------
\echo '--- case e: [番号の巻き戻り] 同じ request_id でも INSERT が通り、新しい失敗が記録され、古い応答を拾わないこと'

DO $$
DECLARE
  v_row bigint;
  v_cnt integer;
BEGIN
  -- request_id に一意の索引が無い（PK / UNIQUE / 一意索引のどれでも cron の INSERT が落ちる）
  SELECT count(*) INTO v_cnt
  FROM pg_catalog.pg_index i
  JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
  WHERE i.indrelid = 'public.cron_http_requests'::regclass
    AND i.indisunique
    AND a.attname = 'request_id';
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: cron_http_requests.request_id に一意の索引がある（番号が戻ると cron の INSERT が失敗し、HTTP も飛ばなくなる）';
  END IF;

  -- a: 新しい行の req:<id> に新しい応答（503）。古い行は評価し直さない
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'a_new';
  PERFORM pg_temp.expect_problem('巻き戻り a: 新しい失敗', 'req:' || v_row, 'auto-skip-workouts', 'http_error', 'HTTP 503');
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'a_old';
  PERFORM pg_temp.expect_no_problem('巻き戻り a: 古い行は評価し直さない', 'req:' || v_row);

  -- b: 古い応答（500）を拾わず 結果不明
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'b_new';
  PERFORM pg_temp.expect_problem('巻き戻り b: 古い応答を拾わない', 'req:' || v_row, 'cleanup-ai-images', 'no_response', '結果不明');
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'b_old';
  PERFORM pg_temp.expect_no_problem('巻き戻り b: 古い行は評価し直さない', 'req:' || v_row);

  -- c: 古い応答（500）があっても、新しい応答（200）で問題なし
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'c_new';
  PERFORM pg_temp.expect_no_problem('巻き戻り c: 新しい応答で評価する', 'req:' || v_row);
  IF (SELECT q.checked_at FROM public.cron_http_requests q WHERE q.id = v_row) IS NULL THEN
    RAISE EXCEPTION 'FAIL: 巻き戻り c: checked_at が埋まっていない';
  END IF;

  -- d: 発射の後で最初の応答（200）を見る（後から来た別の要求の 500 を拾わない）
  SELECT row_id INTO v_row FROM rollback_rows WHERE label = 'd_new';
  PERFORM pg_temp.expect_no_problem('巻き戻り d: 発射の後で最初の応答を見る', 'req:' || v_row);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): 2回呼んでも重複しない
--   セッションの TimeZone を変えて呼ぶ（PostgREST のセッションの TimeZone に左右されないこと。
--   予定時刻の計算がセッションの TimeZone に依存すると、別の epoch の未実行が増えて落ちる）
-- -----------------------------------------------------------------------------
\echo '--- case f: [冪等] 2回呼んでも問題が増えないこと（セッションの TimeZone が違っても）'

DO $$
DECLARE
  v_before bigint;
  v_after bigint;
  v_second bigint;
  v_first bigint;
  v_tz text;
BEGIN
  SELECT count(*) INTO v_first FROM first_run;
  FOREACH v_tz IN ARRAY ARRAY['Asia/Tokyo', 'America/Los_Angeles', 'UTC'] LOOP
    EXECUTE format('SET LOCAL TIME ZONE %L', v_tz);
    SELECT count(*) INTO v_before FROM public.cron_health_problems;
    SELECT count(*) INTO v_second FROM public.run_cron_health_check();
    SELECT count(*) INTO v_after FROM public.cron_health_problems;
    IF v_after <> v_before OR v_second <> v_first THEN
      RAISE EXCEPTION 'FAIL: TimeZone % で呼び直すと問題が % 件 → % 件 / 返り値 % 件 → % 件',
        v_tz, v_before, v_after, v_first, v_second;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 呼び直しても問題は % 件のまま（未通知 % 件）', v_after, v_second;
END $$;

SET LOCAL TIME ZONE 'UTC';

-- -----------------------------------------------------------------------------
-- ケース(g): 返り値
-- -----------------------------------------------------------------------------
\echo '--- case g: [返り値] 未通知だけを id の昇順で返す。通知済みは返らない'

DO $$
DECLARE
  v_expected bigint[];
  v_actual bigint[];
  v_id bigint;
BEGIN
  SELECT array_agg(p.id ORDER BY p.id) INTO v_expected
  FROM public.cron_health_problems p WHERE p.notified_at IS NULL;

  SELECT array_agg(r.id ORDER BY r.position) INTO v_actual FROM first_run r;
  IF v_actual IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'FAIL: 返り値の id の並びが未通知の問題の id の昇順と違う（% / %）', v_actual, v_expected;
  END IF;

  -- 列の値（detail を含めて表と同じ）
  IF EXISTS (
    SELECT 1
    FROM first_run r
    JOIN public.cron_health_problems p ON p.id = r.id
    WHERE (r.jobname, r.kind, r.summary, r.detail, r.occurred_at)
          IS DISTINCT FROM (p.jobname, p.kind, p.summary, p.detail, p.occurred_at)
  ) THEN
    RAISE EXCEPTION 'FAIL: 返り値の列が表の値と違う';
  END IF;

  -- 通知済みにすると返らない（次の呼び出しで、その id だけが消える）
  SELECT p.id INTO v_id FROM public.cron_health_problems p WHERE p.source_key = 'run:910001';
  UPDATE public.cron_health_problems SET notified_at = now() WHERE id = v_id;
  IF EXISTS (SELECT 1 FROM public.run_cron_health_check() r WHERE r.id = v_id) THEN
    RAISE EXCEPTION 'FAIL: 通知済みの問題が返った';
  END IF;
  IF (SELECT count(*) FROM public.run_cron_health_check()) <> cardinality(v_expected) - 1 THEN
    RAISE EXCEPTION 'FAIL: 通知済みにした1件以外の数が変わった';
  END IF;
  -- 通知済みの失敗は記録し直されない（source_key で1回だけ）
  IF (SELECT count(*) FROM public.cron_health_problems p WHERE p.source_key = 'run:910001') <> 1 THEN
    RAISE EXCEPTION 'FAIL: 通知済みの失敗が記録し直された';
  END IF;
  RAISE NOTICE 'OK: 未通知だけを id の昇順で返す（% 件）', cardinality(v_expected);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): 掃除
-- -----------------------------------------------------------------------------
\echo '--- case h: [掃除] 90日より前の発射記録と通知済みの問題を消す'

DO $$
DECLARE
  v_requests text[];
  v_problems text[];
BEGIN
  SELECT array_agg(q.jobname ORDER BY q.jobname) INTO v_requests
  FROM public.cron_http_requests q WHERE q.jobname LIKE 'chk-clean-%';
  IF v_requests IS DISTINCT FROM ARRAY['chk-clean-keep'] THEN
    RAISE EXCEPTION 'FAIL: 発射記録の掃除の結果が %（期待 89日前の行だけが残る）', v_requests;
  END IF;

  SELECT array_agg(p.source_key ORDER BY p.source_key) INTO v_problems
  FROM public.cron_health_problems p WHERE p.source_key LIKE 'test:%';
  IF v_problems IS DISTINCT FROM ARRAY['test:notified-89', 'test:notified-recently', 'test:unnotified-old'] THEN
    RAISE EXCEPTION 'FAIL: 問題の掃除の結果が %（期待 89日前の通知済み・最近の通知済み・未通知が残る）', v_problems;
  END IF;

  -- 時刻が両方 NULL の failed の問題は消さない（行が残っていて、未通知に戻っていない）
  IF NOT EXISTS (
    SELECT 1 FROM public.cron_health_problems p
    WHERE p.source_key = 'run:910021' AND p.notified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'FAIL: 時刻が両方 NULL の failed の問題が消されて記録し直された（同じ失敗をもう1回通知する）';
  END IF;

  RAISE NOTICE 'OK: 掃除';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i): 権限と属性（§4.1・§4.2・§4.3）
-- -----------------------------------------------------------------------------
\echo '--- case i: [権限] anon / authenticated は不可、service_role は §4.1 の範囲だけ'

-- p_role で実行して 42501（permission denied）になること
CREATE FUNCTION pg_temp.expect_denied(p_role text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
    RAISE EXCEPTION 'FAIL: % が実行できてしまった: %', p_role, p_sql;
  EXCEPTION
    WHEN insufficient_privilege THEN
      NULL;
  END;
  RESET ROLE;
END $$;

-- p_role で実行できること
CREATE FUNCTION pg_temp.expect_allowed(p_role text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  EXECUTE p_sql;
  RESET ROLE;
END $$;

DO $$
DECLARE
  v_role text;
  v_sql text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH v_sql IN ARRAY ARRAY[
      'SELECT count(*) FROM public.cron_http_requests',
      $s$INSERT INTO public.cron_http_requests (jobname, request_id) VALUES ('x', 1)$s$,
      'UPDATE public.cron_http_requests SET checked_at = now()',
      'DELETE FROM public.cron_http_requests',
      'SELECT count(*) FROM public.cron_health_problems',
      $s$INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary) VALUES ('x', 'x', 'job_failed', now(), 'x')$s$,
      'UPDATE public.cron_health_problems SET notified_at = now()',
      'DELETE FROM public.cron_health_problems',
      $s$SELECT nextval('public.cron_http_requests_id_seq')$s$,
      $s$SELECT nextval('public.cron_health_problems_id_seq')$s$,
      'SELECT * FROM public.run_cron_health_check()',
      $s$SELECT * FROM public.cron_http_result_problem('x', 200, false, NULL, '{}')$s$
    ] LOOP
      PERFORM pg_temp.expect_denied(v_role, v_sql);
    END LOOP;
    RAISE NOTICE 'OK: % は表も関数もシーケンスも不可', v_role;
  END LOOP;

  -- service_role: 読むのは未通知の問題だけ。書けるのは notified_at だけ。RPC は実行できる
  PERFORM pg_temp.expect_allowed('service_role', 'SELECT count(*) FROM public.cron_health_problems');
  PERFORM pg_temp.expect_allowed('service_role', $s$UPDATE public.cron_health_problems SET notified_at = now() WHERE source_key = 'test:unnotified-old'$s$);
  -- Edge Function の更新と同じ形（WHERE の id / notified_at は SELECT の権限で読む）
  PERFORM pg_temp.expect_allowed('service_role', $s$UPDATE public.cron_health_problems SET notified_at = now() WHERE id >= 1 AND id <= 2 AND notified_at IS NULL$s$);
  PERFORM pg_temp.expect_allowed('service_role', 'SELECT count(*) FROM public.run_cron_health_check()');
  FOREACH v_sql IN ARRAY ARRAY[
    'SELECT count(*) FROM public.cron_http_requests',
    $s$INSERT INTO public.cron_http_requests (jobname, request_id) VALUES ('x', 1)$s$,
    'UPDATE public.cron_http_requests SET checked_at = now()',
    'DELETE FROM public.cron_http_requests',
    $s$INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary) VALUES ('x', 'x', 'job_failed', now(), 'x')$s$,
    $s$UPDATE public.cron_health_problems SET detail = 'x'$s$,
    $s$UPDATE public.cron_health_problems SET summary = 'x'$s$,
    'DELETE FROM public.cron_health_problems',
    $s$SELECT nextval('public.cron_http_requests_id_seq')$s$,
    $s$SELECT nextval('public.cron_health_problems_id_seq')$s$,
    $s$SELECT * FROM public.cron_http_result_problem('x', 200, false, NULL, '{}')$s$
  ] LOOP
    PERFORM pg_temp.expect_denied('service_role', v_sql);
  END LOOP;
  RAISE NOTICE 'OK: service_role は SELECT + UPDATE (notified_at) + RPC だけ';

  -- has_*_privilege でも固定する
  IF has_column_privilege('service_role', 'public.cron_health_problems', 'detail', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL: service_role が cron_health_problems.detail を UPDATE できる';
  END IF;
  IF NOT has_column_privilege('service_role', 'public.cron_health_problems', 'notified_at', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL: service_role が cron_health_problems.notified_at を UPDATE できない';
  END IF;
  IF has_function_privilege('service_role', 'public.cron_http_result_problem(text, integer, boolean, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: service_role が cron_http_result_problem を実行できる';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'public.cron_http_requests', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR has_any_column_privilege(v_role, 'public.cron_http_requests', 'SELECT, INSERT, UPDATE, REFERENCES')
       OR has_sequence_privilege(v_role, 'public.cron_http_requests_id_seq', 'USAGE, SELECT, UPDATE')
       OR has_sequence_privilege(v_role, 'public.cron_health_problems_id_seq', 'USAGE, SELECT, UPDATE') THEN
      RAISE EXCEPTION 'FAIL: % に cron_http_requests かシーケンスの権限がある', v_role;
    END IF;
  END LOOP;
END $$;

\echo '--- case i-2: [属性] 関数の属性・PUBLIC への付与・RLS'

DO $$
DECLARE
  c_run constant regprocedure := 'public.run_cron_health_check()'::regprocedure;
  c_classify constant regprocedure :=
    'public.cron_http_result_problem(text, integer, boolean, text, text)'::regprocedure;
  v record;
BEGIN
  SELECT p.prosecdef, p.provolatile, p.proconfig, p.pronargs, p.proacl, r.rolname AS owner INTO v
  FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
  WHERE p.oid = c_run;
  IF NOT v.prosecdef OR v.provolatile <> 'v' OR NOT ('search_path=""' = ANY (v.proconfig))
     OR v.pronargs <> 0 OR v.owner <> 'postgres' THEN
    RAISE EXCEPTION 'FAIL: run_cron_health_check の属性が %', v;
  END IF;

  SELECT p.prosecdef, p.provolatile, p.proconfig INTO v FROM pg_catalog.pg_proc p WHERE p.oid = c_classify;
  IF v.prosecdef OR v.provolatile <> 'i' OR NOT ('search_path=""' = ANY (v.proconfig)) THEN
    RAISE EXCEPTION 'FAIL: cron_http_result_problem の属性が %', v;
  END IF;

  -- proacl が NULL は既定権限（= PUBLIC に EXECUTE）。grantee = 0 は PUBLIC
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    WHERE p.oid IN (c_run, c_classify) AND p.proacl IS NULL
  ) OR EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
    WHERE p.oid IN (c_run, c_classify) AND a.grantee = 0
  ) THEN
    RAISE EXCEPTION 'FAIL: PUBLIC が関数を実行できる';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE c.oid IN ('public.cron_http_requests'::regclass, 'public.cron_health_problems'::regclass,
                    'public.cron_http_requests_id_seq'::regclass, 'public.cron_health_problems_id_seq'::regclass)
      AND a.grantee = 0
  ) THEN
    RAISE EXCEPTION 'FAIL: PUBLIC に表かシーケンスの権限がある';
  END IF;

  -- RLS 有効・ポリシー無し
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    WHERE c.oid IN ('public.cron_http_requests'::regclass, 'public.cron_health_problems'::regclass)
      AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FAIL: RLS が有効でない';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename IN ('cron_http_requests', 'cron_health_problems')
  ) THEN
    RAISE EXCEPTION 'FAIL: ポリシーがある（期待 無し）';
  END IF;

  -- 未評価の行の部分インデックス
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_indexes i
    WHERE i.schemaname = 'public' AND i.tablename = 'cron_http_requests'
      AND i.indexdef LIKE '%WHERE (checked_at IS NULL)%'
  ) THEN
    RAISE EXCEPTION 'FAIL: checked_at IS NULL の部分インデックスが無い';
  END IF;

  -- kind の CHECK（未知の種別は入らない）
  BEGIN
    INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary)
    VALUES ('test:bad-kind', 'x', 'unknown', now(), 'x');
    RAISE EXCEPTION 'FAIL: 未知の kind を INSERT できた';
  EXCEPTION
    WHEN check_violation THEN
      NULL;
  END;

  RAISE NOTICE 'OK: 関数の属性・PUBLIC への付与なし・RLS 有効でポリシー無し・部分インデックス・kind の CHECK';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CRON HEALTH CHECK TESTS PASSED'
