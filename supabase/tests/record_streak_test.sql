-- =============================================================================
-- 記録の連続 get_record_streak（20261123000000_record_streak.sql）のテスト
-- （設計書 §3〜§5.3: docs/superpowers/specs/2026-11-23-record-streak-design.md）
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/record_streak_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL RECORD STREAK TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - 試験用の行は UUID が 5a7e1123-0000-4000-8000- で始まる。関数は引数の client_id で絞るので、
--   seed のデータとは混ざらない
-- - 日時はすべて now()（トランザクションの開始時刻で固定）からの相対で、日本時間の「今日」を基準に作る
--   （関数は時刻を差し込む引数を持たない。設計書 §5.1）
-- - 関数は必ずロール authenticated + 呼び出し元の JWT クレーム（SET LOCAL）で呼ぶ（pg_temp.expect_streak）。
--   顧客本人が RLS の下で自分の記録と workout_plans.plan_type を読めることを、同時に確かめる。
--   試験データの投入・削除は postgres（RLS を通らない）で行う
-- - 各ケースは、セッションの TimeZone を UTC / Asia/Tokyo / Pacific/Kiritimati（UTC+14）/ Etc/GMT+12（UTC-12）
--   に変えて 4 回呼び、どれでも同じ結果になることを確かめる。日付をセッションの TimeZone で出す誤り
--   （current_date、timestamptz の ::date など）は、実行する時刻によらずどれかで落ちる
--   （JST の 21 時より前は UTC-12 の日付が、19 時以降は UTC+14 の日付が JST と違う）
-- - as_of_date を UTC で固定して出す誤りは、JST の 0〜9 時に実行したときしか挙動で区別できない
--   （それ以外の時刻は UTC と JST の日付が同じで、結果も同じ）。そのため (g) で関数の本文に
--   (now() AT TIME ZONE 'Asia/Tokyo')::date があることも確かめる
--
-- 試験データ:
--   トレーナー T（顧客 A の担当）/ トレーナー T2（顧客 B の担当）
--   顧客 A（主な呼び出し元）/ 顧客 B（A から見た他人）
--   プラン A_self（T の self_guided）/ A_session（T の session）/ B_self（T2 の self_guided）
--
-- 検証ケース:
--   (a) 記録なし → (今日, false, 0)。p_client_id が NULL でも 1 行
--   (b) 数える記録 1 件だけ（今日）→ (今日, true, 0): 体重 manual / message / source NULL、
--       食事 manual / message、運動 manual / message、睡眠 manual（評価なし）、睡眠 healthkit + 評価、
--       self_guided の完了（予定日は 3 日前。数えるのは完了した日）
--   (c) 数えない記録だけ → (今日, false, 0): 体重 healthkit、評価の無い healthkit の睡眠、session の完了、
--       finished_at の無い完了、pending / partial / skipped の割り当て（partial・skipped は finished_at あり）、
--       今日より後の日付の記録（明日 00:00:00 JST の体重・明日の食事・明日の睡眠・明日の完了・1 年後の運動）
--   (d) 日付の境目（JST）: 今日 00:00:00 は今日、昨日 23:59:59 は昨日（体重・食事・運動・ワークアウト）。
--       昨日 00:00:00 は昨日、一昨日 23:59:59 は一昨日、今日 23:59:59 は今日（体重）。
--       今日 00:00:00 JST と昨日 00:00:00 JST は、UTC の日付で切るとそれぞれ前の日になる（前提として確かめる）
--   (e) 連続: 昨日・一昨日 → 2 / 3 日前が抜けると 4 日前以降は数えない / 同じ日の複数件は 1 日 /
--       今日・昨日・一昨日 → (true, 2) / 今日と一昨日（昨日なし）→ (true, 0) / 昨日なし → 0 /
--       5 種類の記録をまたいで 10 日 / 数えない記録は抜けた日を埋めない / 今日より後の日付は連続を変えない /
--       400 日（期間の上限が無い）
--   (f) RLS: 前提（本人・担当トレーナーがプランの plan_type を読める、本人は他人の記録を直接読めない）/
--       A → A / A が B の id → (今日, false, 0) / B → B / B が A の id / 担当トレーナー T → A は A と同じ値 /
--       T → B（担当外）/ T2 → B / T2 → A（担当外）/ sub の無い authenticated → (今日, false, 0)
--   (g) 権限と属性: anon（クレームなし・A のクレーム付き）は EXECUTE できない（42501）/
--       SECURITY INVOKER・search_path=""・STABLE・LANGUAGE sql / 引数と戻り値の契約（Mobile が使う）/
--       EXECUTE は authenticated あり・anon なし・PUBLIC なし / as_of_date の式 / COMMENT
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

SELECT now() AT TIME ZONE 'Asia/Tokyo' AS "now (JST)", current_setting('TimeZone') AS "session TimeZone";

-- -----------------------------------------------------------------------------
-- 共通のヘルパー
-- -----------------------------------------------------------------------------

-- 試験用の id（それ以外の名前、たとえば 'none' は NULL）
CREATE FUNCTION pg_temp.id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_name
    WHEN 'T'         THEN '5a7e1123-0000-4000-8000-00000000a001'
    WHEN 'T2'        THEN '5a7e1123-0000-4000-8000-00000000a002'
    WHEN 'A'         THEN '5a7e1123-0000-4000-8000-00000000c001'
    WHEN 'B'         THEN '5a7e1123-0000-4000-8000-00000000c002'
    WHEN 'A_self'    THEN '5a7e1123-0000-4000-8000-00000000b001'
    WHEN 'A_session' THEN '5a7e1123-0000-4000-8000-00000000b002'
    WHEN 'B_self'    THEN '5a7e1123-0000-4000-8000-00000000b003'
  END::uuid
$$;

-- 日本時間の今日（関数の as_of_date と同じ定義）
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'Asia/Tokyo')::date
$$;

-- 日本時間で「今日から p_day 日目の p_time」の時刻
CREATE FUNCTION pg_temp.jst(p_day integer, p_time time) RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT ((pg_temp.today() + p_day) + p_time) AT TIME ZONE 'Asia/Tokyo'
$$;

-- 記録を 1 件足す（postgres で実行）
--   p_kind  : weight / meal / exercise / sleep / workout
--   p_day   : 日本時間の今日からの日数（0 = 今日、-1 = 昨日、1 = 明日）
--   p_time  : 日本時間の時刻（weight / meal / exercise の recorded_at、workout の finished_at。sleep は使わない）
--   p_source: weight / meal / exercise / sleep の source。p_rating: sleep の wakeup_rating
--   p_plan  : workout のプラン（self / session。顧客ごとの id は pg_temp.id(<顧客>_<p_plan>)）
--   p_status: workout の status。p_finished: workout の finished_at を入れるか
CREATE FUNCTION pg_temp.add_record(
  p_client text,
  p_kind text,
  p_day integer,
  p_time time DEFAULT '12:00',
  p_source text DEFAULT 'manual',
  p_rating smallint DEFAULT NULL,
  p_plan text DEFAULT 'self',
  p_status text DEFAULT 'completed',
  p_finished boolean DEFAULT true
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_client uuid := pg_temp.id(p_client);
  v_at timestamptz := pg_temp.jst(p_day, p_time);
BEGIN
  CASE p_kind
    WHEN 'weight' THEN
      INSERT INTO public.weight_records (client_id, weight, recorded_at, source)
      VALUES (v_client, 60.5, v_at, p_source);
    WHEN 'meal' THEN
      INSERT INTO public.meal_records (client_id, meal_type, recorded_at, source)
      VALUES (v_client, 'lunch', v_at, p_source);
    WHEN 'exercise' THEN
      INSERT INTO public.exercise_records (client_id, exercise_type, duration, recorded_at, source)
      VALUES (v_client, 'walking', 30, v_at, p_source);
    WHEN 'sleep' THEN
      INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source)
      VALUES (v_client, pg_temp.today() + p_day, 420, p_rating, p_source);
    WHEN 'workout' THEN
      -- 予定日は完了の 3 日前（数えるのは finished_at の日付で、assigned_date ではない）
      INSERT INTO public.workout_assignments
        (trainer_id, client_id, plan_id, assigned_date, status, started_at, finished_at)
      SELECT p.trainer_id, v_client, p.id, pg_temp.today() + p_day - 3, p_status,
             v_at - interval '30 minutes', CASE WHEN p_finished THEN v_at END
        FROM public.workout_plans p
       WHERE p.id = pg_temp.id(p_client || '_' || p_plan);
      IF NOT FOUND THEN
        RAISE EXCEPTION 'テストの誤り: プラン %_% が無い', p_client, p_plan;
      END IF;
    ELSE
      RAISE EXCEPTION 'テストの誤り: 未知の記録の種類 %', p_kind;
  END CASE;
END $$;

-- 顧客 A・B の記録を消す（ケースごとに空から始める）
CREATE FUNCTION pg_temp.clear_records() RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_clients uuid[] := ARRAY[pg_temp.id('A'), pg_temp.id('B')];
BEGIN
  DELETE FROM public.weight_records      WHERE client_id = ANY (v_clients);
  DELETE FROM public.meal_records        WHERE client_id = ANY (v_clients);
  DELETE FROM public.exercise_records    WHERE client_id = ANY (v_clients);
  DELETE FROM public.sleep_records       WHERE client_id = ANY (v_clients);
  DELETE FROM public.workout_assignments WHERE client_id = ANY (v_clients);
END $$;

-- p_caller（'A' / 'B' / 'T' / 'T2' / 'none' = sub の無い authenticated）の JWT クレームを SET LOCAL し、
-- ロール authenticated で get_record_streak(p_target) を呼ぶ。ちょうど 1 行
-- (今日（JST）, p_recorded_today, p_streak) が返ること。セッションの TimeZone を 4 通りに変えて確かめる。
-- ロールを切り替えている間は public.get_record_streak だけを呼ぶ（pg_temp の関数は呼ばない）
CREATE FUNCTION pg_temp.expect_streak(
  p_label text, p_caller text, p_target text, p_recorded_today boolean, p_streak integer
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_caller uuid := pg_temp.id(p_caller);
  v_target uuid := pg_temp.id(p_target);
  v_today date := pg_temp.today();
  v_orig_tz text := current_setting('TimeZone');
  v_claims text;
  v_tz text;
  v_rows bigint;
  v_as_of date;
  v_recorded boolean;
  v_streak integer;
BEGIN
  v_claims := CASE WHEN v_caller IS NULL THEN '{"role":"authenticated"}'
                   ELSE json_build_object('sub', v_caller, 'role', 'authenticated')::text END;

  FOREACH v_tz IN ARRAY ARRAY['UTC', 'Asia/Tokyo', 'Pacific/Kiritimati', 'Etc/GMT+12'] LOOP
    PERFORM set_config('TimeZone', v_tz, true);
    PERFORM set_config('request.jwt.claims', v_claims, true);
    PERFORM set_config('request.jwt.claim.sub', coalesce(v_caller::text, ''), true);
    SET LOCAL ROLE authenticated;

    SELECT count(*), max(s.as_of_date), bool_or(s.recorded_today), max(s.streak_until_yesterday)
      INTO v_rows, v_as_of, v_recorded, v_streak
      FROM public.get_record_streak(v_target) s;

    RESET ROLE;
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);

    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'FAIL: % [TimeZone %] : % 行（期待 1 行）', p_label, v_tz, v_rows;
    END IF;
    IF (v_as_of, v_recorded, v_streak) IS DISTINCT FROM (v_today, p_recorded_today, p_streak) THEN
      RAISE EXCEPTION 'FAIL: % [TimeZone %] : (%, %, %)（期待 (%, %, %)）',
        p_label, v_tz, v_as_of, v_recorded, v_streak, v_today, p_recorded_today, p_streak;
    END IF;
  END LOOP;

  PERFORM set_config('TimeZone', v_orig_tz, true);
  RAISE NOTICE 'OK: % → (%, %, %)', p_label, v_today, p_recorded_today, p_streak;
END $$;

-- -----------------------------------------------------------------------------
-- 試験データ（postgres として実行）: トレーナー T・T2、顧客 A（T の担当）・B（T2 の担当）、プラン 3 本
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T・T2 / client A・B / plan A_self・A_session・B_self)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT pg_temp.id(n), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'streak-test-' || lower(n) || '@example.com', 'x', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['T', 'T2', 'A', 'B']) AS n;

INSERT INTO public.trainers (id, name, email) VALUES
  (pg_temp.id('T'),  'ストリークテスト トレーナーT',  'streak-test-t@example.com'),
  (pg_temp.id('T2'), 'ストリークテスト トレーナーT2', 'streak-test-t2@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  (pg_temp.id('A'), 'ストリークテスト顧客A', pg_temp.id('T')),
  (pg_temp.id('B'), 'ストリークテスト顧客B', pg_temp.id('T2'));

INSERT INTO public.workout_plans (id, trainer_id, title, plan_type) VALUES
  (pg_temp.id('A_self'),    pg_temp.id('T'),  'ストリークテスト: セルフガイド',       'self_guided'),
  (pg_temp.id('A_session'), pg_temp.id('T'),  'ストリークテスト: セッション',         'session'),
  (pg_temp.id('B_self'),    pg_temp.id('T2'), 'ストリークテスト: T2 のセルフガイド', 'self_guided');

-- -----------------------------------------------------------------------------
-- ケース(a): 記録なし
-- -----------------------------------------------------------------------------
\echo '--- case a: 記録なし → (今日, false, 0)。必ず 1 行'

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.expect_streak('記録なし', 'A', 'A', false, 0);
  PERFORM pg_temp.expect_streak('p_client_id が NULL', 'A', 'none', false, 0);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b)(c)(d): 記録 1 件だけのケース（表で回す）
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE single_cases (
  no integer GENERATED ALWAYS AS IDENTITY,
  grp text NOT NULL,             -- b / c / d
  label text NOT NULL,
  kind text NOT NULL,
  day integer NOT NULL,
  at time NOT NULL DEFAULT '12:00',
  source text DEFAULT 'manual',
  rating smallint,
  plan text NOT NULL DEFAULT 'self',
  status text NOT NULL DEFAULT 'completed',
  finished boolean NOT NULL DEFAULT true,
  expected_today boolean NOT NULL,
  expected_streak integer NOT NULL
) ON COMMIT DROP;

-- (b) 数える記録それぞれ。今日に 1 件だけ → (true, 0)
INSERT INTO single_cases (grp, label, kind, day, source, rating, expected_today, expected_streak) VALUES
  ('b', '体重 manual',                  'weight',   0, 'manual',    NULL, true, 0),
  ('b', '体重 message',                 'weight',   0, 'message',   NULL, true, 0),
  ('b', '体重 source NULL',             'weight',   0, NULL,        NULL, true, 0),
  ('b', '食事 manual',                  'meal',     0, 'manual',    NULL, true, 0),
  ('b', '食事 message',                 'meal',     0, 'message',   NULL, true, 0),
  ('b', '運動 manual',                  'exercise', 0, 'manual',    NULL, true, 0),
  ('b', '運動 message',                 'exercise', 0, 'message',   NULL, true, 0),
  -- source の条件だけで数える（評価なし）
  ('b', '睡眠 manual（評価なし）',      'sleep',    0, 'manual',    NULL, true, 0),
  -- 評価の条件だけで数える（ヘルスケアの行に本人が評価を書き足した形。source は healthkit のまま）
  ('b', '睡眠 healthkit + 目覚めの評価', 'sleep',   0, 'healthkit', 2,    true, 0);
INSERT INTO single_cases (grp, label, kind, day, plan, status, finished, expected_today, expected_streak) VALUES
  -- 本人が workout_plans の plan_type を読めないと JOIN で落ちて false になる
  ('b', 'self_guided の完了（予定日は 3 日前）', 'workout', 0, 'self', 'completed', true, true, 0);

-- (c) 数えない記録だけ → (false, 0)
INSERT INTO single_cases (grp, label, kind, day, at, source, rating, expected_today, expected_streak) VALUES
  ('c', '体重 healthkit',                     'weight',   0,   '12:00',    'healthkit', NULL, false, 0),
  ('c', '睡眠 healthkit（評価なし）',          'sleep',    0,   '12:00',    'healthkit', NULL, false, 0),
  -- 今日より後の日付
  ('c', '明日 00:00:00 JST の体重 manual',     'weight',   1,   '00:00:00', 'manual',    NULL, false, 0),
  ('c', '明日の食事',                         'meal',     1,   '12:00',    'manual',    NULL, false, 0),
  ('c', '明日の睡眠 manual',                  'sleep',    1,   '12:00',    'manual',    NULL, false, 0),
  ('c', '1 年後の運動',                       'exercise', 365, '12:00',    'manual',    NULL, false, 0);
INSERT INTO single_cases (grp, label, kind, day, plan, status, finished, expected_today, expected_streak) VALUES
  ('c', 'session の完了',                     'workout', 0, 'session', 'completed', true,  false, 0),
  ('c', '完了で finished_at なし',            'workout', 0, 'self',    'completed', false, false, 0),
  ('c', 'pending（finished_at なし）',        'workout', 0, 'self',    'pending',   false, false, 0),
  ('c', 'partial（finished_at あり）',        'workout', 0, 'self',    'partial',   true,  false, 0),
  ('c', 'skipped（finished_at あり）',        'workout', 0, 'self',    'skipped',   true,  false, 0),
  ('c', '明日の self_guided の完了',          'workout', 1, 'self',    'completed', true,  false, 0);

-- (d) 日付の境目（JST）
INSERT INTO single_cases (grp, label, kind, day, at, expected_today, expected_streak) VALUES
  ('d', '体重: 今日 00:00:00 JST は今日',                'weight',   0,  '00:00:00', true,  0),
  ('d', '体重: 昨日 23:59:59 JST は昨日',                'weight',   -1, '23:59:59', false, 1),
  ('d', '食事: 今日 00:00:00 JST は今日',                'meal',     0,  '00:00:00', true,  0),
  ('d', '食事: 昨日 23:59:59 JST は昨日',                'meal',     -1, '23:59:59', false, 1),
  ('d', '運動: 今日 00:00:00 JST は今日',                'exercise', 0,  '00:00:00', true,  0),
  ('d', '運動: 昨日 23:59:59 JST は昨日',                'exercise', -1, '23:59:59', false, 1),
  ('d', 'ワークアウト: 今日 00:00:00 JST の完了は今日', 'workout',  0,  '00:00:00', true,  0),
  ('d', 'ワークアウト: 昨日 23:59:59 JST の完了は昨日', 'workout',  -1, '23:59:59', false, 1),
  ('d', '体重: 昨日 00:00:00 JST は昨日',                'weight',   -1, '00:00:00', false, 1),
  ('d', '体重: 一昨日 23:59:59 JST は一昨日',            'weight',   -2, '23:59:59', false, 0),
  -- 今の時刻より後でも、今日の日付なら今日
  ('d', '体重: 今日 23:59:59 JST は今日',                'weight',   0,  '23:59:59', true,  0);

CREATE FUNCTION pg_temp.run_single_cases(p_grp text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_case record;
BEGIN
  FOR v_case IN SELECT * FROM single_cases WHERE grp = p_grp ORDER BY no LOOP
    PERFORM pg_temp.clear_records();
    PERFORM pg_temp.add_record('A', v_case.kind, v_case.day, v_case.at, v_case.source, v_case.rating,
                               v_case.plan, v_case.status, v_case.finished);
    PERFORM pg_temp.expect_streak(v_case.label, 'A', 'A', v_case.expected_today, v_case.expected_streak);
  END LOOP;
END $$;

\echo '--- case b: [数える記録] それぞれ今日に 1 件だけ → (今日, true, 0)'
DO $$ BEGIN PERFORM pg_temp.run_single_cases('b'); END $$;

\echo '--- case c: [数えない記録] それだけ → (今日, false, 0)'
DO $$ BEGIN PERFORM pg_temp.run_single_cases('c'); END $$;

\echo '--- case d: [日付の境目] 日本時間の日付で数える（UTC の日付で切ると誤る組み合わせを含む）'

DO $$
BEGIN
  -- 前提: UTC の日付で切ると、今日 00:00:00 JST は昨日、昨日 00:00:00 JST は一昨日になる
  -- （= 下の 今日 00:00:00 / 昨日 00:00:00 のケースは、UTC の日付で数える実装では落ちる）。
  -- 昨日 23:59:59 JST は UTC でも昨日なので、今日 00:00:00 JST と並べると「UTC では同じ日・JST では別の日」
  IF (pg_temp.jst(0, '00:00:00') AT TIME ZONE 'UTC')::date IS DISTINCT FROM pg_temp.today() - 1
     OR (pg_temp.jst(-1, '00:00:00') AT TIME ZONE 'UTC')::date IS DISTINCT FROM pg_temp.today() - 2
     OR (pg_temp.jst(-1, '23:59:59') AT TIME ZONE 'UTC')::date IS DISTINCT FROM pg_temp.today() - 1 THEN
    RAISE EXCEPTION 'FAIL: 前提: 境目の時刻の UTC の日付が想定と違う（today = %）', pg_temp.today();
  END IF;

  PERFORM pg_temp.run_single_cases('d');
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): 連続（記録が複数あるケース）
-- -----------------------------------------------------------------------------
\echo '--- case e: [連続] 昨日から過去へ、抜けた日の手前まで数える'

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', -1);
  PERFORM pg_temp.add_record('A', 'meal', -2);
  PERFORM pg_temp.expect_streak('昨日・一昨日 → 2', 'A', 'A', false, 2);
END $$;

DO $$
BEGIN
  -- 3 日前が抜けている。4〜6 日前の記録は数えない
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', -1);
  PERFORM pg_temp.add_record('A', 'weight', -2);
  PERFORM pg_temp.add_record('A', 'weight', -4);
  PERFORM pg_temp.add_record('A', 'weight', -5);
  PERFORM pg_temp.add_record('A', 'weight', -6);
  PERFORM pg_temp.expect_streak('3 日前が抜けると 4 日前以降は数えない → 2', 'A', 'A', false, 2);
END $$;

DO $$
BEGIN
  -- 昨日に 5 件（体重 2・食事・運動・睡眠）、一昨日に 5 件（体重 3・食事 2）
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight',   -1, '07:00');
  PERFORM pg_temp.add_record('A', 'weight',   -1, '21:00');
  PERFORM pg_temp.add_record('A', 'meal',     -1, '12:00');
  PERFORM pg_temp.add_record('A', 'exercise', -1, '18:00');
  PERFORM pg_temp.add_record('A', 'sleep',    -1);
  PERFORM pg_temp.add_record('A', 'weight',   -2, '06:00');
  PERFORM pg_temp.add_record('A', 'weight',   -2, '12:00');
  PERFORM pg_temp.add_record('A', 'weight',   -2, '22:00');
  PERFORM pg_temp.add_record('A', 'meal',     -2, '08:00');
  PERFORM pg_temp.add_record('A', 'meal',     -2, '19:00');
  PERFORM pg_temp.expect_streak('同じ日の複数件は 1 日 → 2', 'A', 'A', false, 2);
END $$;

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', 0);
  PERFORM pg_temp.add_record('A', 'meal', -1);
  PERFORM pg_temp.add_record('A', 'exercise', -2);
  PERFORM pg_temp.expect_streak('今日・昨日・一昨日 → (true, 2)（今日は昨日までの日数に入れない）', 'A', 'A', true, 2);
END $$;

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', 0);
  PERFORM pg_temp.add_record('A', 'weight', -2);
  PERFORM pg_temp.expect_streak('今日と一昨日（昨日なし）→ (true, 0)', 'A', 'A', true, 0);
END $$;

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', -2);
  PERFORM pg_temp.add_record('A', 'weight', -3);
  PERFORM pg_temp.expect_streak('昨日なし・一昨日・3 日前 → 0', 'A', 'A', false, 0);
END $$;

DO $$
BEGIN
  -- 1〜10 日前を 5 種類の記録で 1 日ずつ埋める（どの日も 1 種類だけ）。11 日前が抜け、12 日前は数えない
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight',   -1);
  PERFORM pg_temp.add_record('A', 'meal',     -2);
  PERFORM pg_temp.add_record('A', 'exercise', -3);
  PERFORM pg_temp.add_record('A', 'sleep',    -4, p_source => 'healthkit', p_rating => 3::smallint);
  PERFORM pg_temp.add_record('A', 'workout',  -5);
  PERFORM pg_temp.add_record('A', 'weight',   -6, p_source => 'message');
  PERFORM pg_temp.add_record('A', 'sleep',    -7, p_source => 'manual');
  PERFORM pg_temp.add_record('A', 'meal',     -8, p_source => 'message');
  PERFORM pg_temp.add_record('A', 'exercise', -9, p_source => 'message');
  PERFORM pg_temp.add_record('A', 'weight',   -10, p_source => NULL);
  PERFORM pg_temp.add_record('A', 'weight',   -12);
  PERFORM pg_temp.expect_streak('5 種類の記録をまたいで 10 日 → 10', 'A', 'A', false, 10);
END $$;

DO $$
BEGIN
  -- 一昨日には数えない記録しか無い → 昨日の 1 日だけ
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight',  -1);
  PERFORM pg_temp.add_record('A', 'weight',  -2, p_source => 'healthkit');
  PERFORM pg_temp.add_record('A', 'sleep',   -2, p_source => 'healthkit');
  PERFORM pg_temp.add_record('A', 'workout', -2, p_plan => 'session');
  PERFORM pg_temp.add_record('A', 'workout', -2, p_status => 'partial');
  PERFORM pg_temp.add_record('A', 'workout', -2, p_finished => false);
  PERFORM pg_temp.add_record('A', 'weight',  -3);
  PERFORM pg_temp.expect_streak('数えない記録は抜けた日を埋めない → 1', 'A', 'A', false, 1);
END $$;

DO $$
BEGIN
  -- 明日・明後日・3 日後の記録があっても、昨日までの連続は変わらない（今日にも入らない）
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'weight', -1);
  PERFORM pg_temp.add_record('A', 'weight', -2);
  PERFORM pg_temp.add_record('A', 'weight', 1, '00:00:00');
  PERFORM pg_temp.add_record('A', 'meal', 2);
  PERFORM pg_temp.add_record('A', 'sleep', 3);
  PERFORM pg_temp.add_record('A', 'workout', 1);
  PERFORM pg_temp.expect_streak('今日より後の日付は連続を変えない → 2', 'A', 'A', false, 2);
END $$;

DO $$
BEGIN
  -- 1〜400 日前の毎日（期間の上限が無いこと）。401 日前が抜け、402 日前は数えない
  PERFORM pg_temp.clear_records();
  FOR i IN 1..400 LOOP
    PERFORM pg_temp.add_record('A', 'meal', -i);
  END LOOP;
  PERFORM pg_temp.add_record('A', 'meal', -402);
  PERFORM pg_temp.expect_streak('400 日続く → 400', 'A', 'A', false, 400);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): RLS（SECURITY INVOKER。見える行だけを数える）
--   A の記録は、どの日も 1 種類だけにする（トレーナーにどれか 1 種類が見えないと日数が変わる）:
--     今日 = 食事 / 昨日 = self_guided の完了 / 一昨日 = healthkit の睡眠 + 評価 / 3 日前 = 運動 /
--     4 日前 = 体重 message / 5 日前 = なし / 6 日前 = 体重 manual → (true, 4)
--   B の記録: 今日 = 体重 / 昨日 = 食事 / 一昨日 = self_guided の完了（T2 のプラン）→ (true, 2)
-- -----------------------------------------------------------------------------
\echo '--- case f: [RLS] 他人の client_id は (今日, false, 0)、担当トレーナーは本人と同じ値'

DO $$
BEGIN
  PERFORM pg_temp.clear_records();
  PERFORM pg_temp.add_record('A', 'meal',     0);
  PERFORM pg_temp.add_record('A', 'workout',  -1);
  PERFORM pg_temp.add_record('A', 'sleep',    -2, p_source => 'healthkit', p_rating => 1::smallint);
  PERFORM pg_temp.add_record('A', 'exercise', -3);
  PERFORM pg_temp.add_record('A', 'weight',   -4, p_source => 'message');
  PERFORM pg_temp.add_record('A', 'weight',   -6);
  PERFORM pg_temp.add_record('B', 'weight',   0);
  PERFORM pg_temp.add_record('B', 'meal',     -1);
  PERFORM pg_temp.add_record('B', 'workout',  -2);
END $$;

-- 前提: 顧客 A は自分に割り当てられたプランの plan_type を読め（clients_read_assigned_plans）、
--       B の記録は直接読めない（関数ではなく RLS が隠していること）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5a7e1123-0000-4000-8000-00000000c001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5a7e1123-0000-4000-8000-00000000c001';

DO $$
DECLARE
  v_plan_type text;
  v_cnt integer;
BEGIN
  SELECT p.plan_type INTO v_plan_type
    FROM public.workout_plans p WHERE p.id = '5a7e1123-0000-4000-8000-00000000b001';
  IF v_plan_type IS DISTINCT FROM 'self_guided' THEN
    RAISE EXCEPTION 'FAIL: 前提: 顧客 A が自分に割り当てられたプランの plan_type を読めない（%）', v_plan_type;
  END IF;

  SELECT count(*) INTO v_cnt
    FROM public.workout_assignments a
    JOIN public.workout_plans p ON p.id = a.plan_id
   WHERE a.client_id = '5a7e1123-0000-4000-8000-00000000c001';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 前提: 顧客 A に自分の割り当てとプランの JOIN が % 行（期待 1 行）', v_cnt;
  END IF;

  SELECT (SELECT count(*) FROM public.weight_records WHERE client_id = '5a7e1123-0000-4000-8000-00000000c002')
       + (SELECT count(*) FROM public.meal_records WHERE client_id = '5a7e1123-0000-4000-8000-00000000c002')
       + (SELECT count(*) FROM public.workout_assignments WHERE client_id = '5a7e1123-0000-4000-8000-00000000c002')
    INTO v_cnt;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 前提: 顧客 A が B の記録を % 行直接読める（期待 0 行）', v_cnt;
  END IF;
  RAISE NOTICE 'OK: 前提: 顧客 A は自分のプランの plan_type を読め、B の記録は読めない';
END $$;

-- 前提: 担当トレーナー T は A のプランの plan_type と A の記録を読める
SET LOCAL request.jwt.claims = '{"sub":"5a7e1123-0000-4000-8000-00000000a001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5a7e1123-0000-4000-8000-00000000a001';

DO $$
DECLARE
  v_plan_type text;
BEGIN
  SELECT p.plan_type INTO v_plan_type
    FROM public.workout_plans p WHERE p.id = '5a7e1123-0000-4000-8000-00000000b001';
  IF v_plan_type IS DISTINCT FROM 'self_guided' THEN
    RAISE EXCEPTION 'FAIL: 前提: トレーナー T が自分のプランの plan_type を読めない（%）', v_plan_type;
  END IF;
  RAISE NOTICE 'OK: 前提: トレーナー T は自分のプランの plan_type を読める';
END $$;

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
BEGIN
  PERFORM pg_temp.expect_streak('A → A', 'A', 'A', true, 4);
  PERFORM pg_temp.expect_streak('A が B の id で呼ぶ（B には今日・昨日・一昨日の記録がある）', 'A', 'B', false, 0);
  PERFORM pg_temp.expect_streak('B → B', 'B', 'B', true, 2);
  PERFORM pg_temp.expect_streak('B が A の id で呼ぶ', 'B', 'A', false, 0);
  PERFORM pg_temp.expect_streak('担当トレーナー T → A（A と同じ値）', 'T', 'A', true, 4);
  PERFORM pg_temp.expect_streak('トレーナー T → B（担当外）', 'T', 'B', false, 0);
  PERFORM pg_temp.expect_streak('担当トレーナー T2 → B（B と同じ値）', 'T2', 'B', true, 2);
  PERFORM pg_temp.expect_streak('トレーナー T2 → A（担当外）', 'T2', 'A', false, 0);
  PERFORM pg_temp.expect_streak('sub の無い authenticated → A', 'none', 'A', false, 0);
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 権限と属性
--   anon は 2 通り（docs/tasks/lessons.md「クレーム付き anon」）: (g-1) クレームなし、
--   (g-2) A のクレームを持った anon。記録の表の顧客用ポリシーは TO の指定が無く anon にも効くので、
--   (g-2) で anon に EXECUTE が残っていれば A の (true, 4) が返ってしまう。拒否は GRANT 層
--   （42501 かつ 'permission denied for function get_record_streak'）であることまで確かめる
-- -----------------------------------------------------------------------------
\echo '--- case g-1: [権限] anon（クレームなし）は get_record_streak を実行できない'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.get_record_streak('5a7e1123-0000-4000-8000-00000000c001');
    RAISE EXCEPTION 'FAIL: anon（クレームなし）が get_record_streak を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function get_record_streak%' THEN
        RAISE;
      END IF;
  END;
  RAISE NOTICE 'OK: anon（クレームなし）は permission denied (42501)';
END $$;

RESET ROLE;

\echo '--- case g-2: [権限] anon + 顧客 A のクレームでも実行できない'

SET LOCAL request.jwt.claims = '{"sub":"5a7e1123-0000-4000-8000-00000000c001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5a7e1123-0000-4000-8000-00000000c001';
SET LOCAL ROLE anon;

DO $$
BEGIN
  -- 前提: auth.uid() が A を返している（NULL だと (g-1) と同じ条件になる）
  IF auth.uid() IS DISTINCT FROM '5a7e1123-0000-4000-8000-00000000c001'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提: anon で auth.uid() が %（期待 顧客 A）', coalesce(auth.uid()::text, 'NULL');
  END IF;

  BEGIN
    PERFORM 1 FROM public.get_record_streak('5a7e1123-0000-4000-8000-00000000c001');
    RAISE EXCEPTION 'FAIL: anon + 顧客 A のクレームで get_record_streak を実行できてしまった（anon の EXECUTE が剥がれていない）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function get_record_streak%' THEN
        RAISE;
      END IF;
  END;
  RAISE NOTICE 'OK: anon + 顧客 A のクレームでも permission denied (42501)';
END $$;

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

\echo '--- case g-3: [属性] SECURITY INVOKER・search_path・STABLE・契約・EXECUTE の付与先'

DO $$
DECLARE
  c_fn constant regprocedure := 'public.get_record_streak(uuid)'::regprocedure;
  v record;
BEGIN
  SELECT p.prosecdef, p.provolatile, p.proconfig, p.proacl, p.proretset, p.prosrc, l.lanname,
         pg_get_function_identity_arguments(p.oid) AS args,
         pg_get_function_result(p.oid) AS result,
         obj_description(p.oid, 'pg_proc') AS description
    INTO v
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
   WHERE p.oid = c_fn;

  IF v.prosecdef THEN
    RAISE EXCEPTION 'FAIL: get_record_streak が SECURITY DEFINER（期待 INVOKER。RLS が外れる）';
  END IF;
  IF v.provolatile <> 's' THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の揮発性が %（期待 s = STABLE）', v.provolatile;
  END IF;
  IF v.proconfig IS NULL OR NOT ('search_path=""' = ANY (v.proconfig)) THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の search_path が空文字に固定されていない（proconfig = %）',
      coalesce(v.proconfig::text, 'NULL');
  END IF;
  IF v.lanname <> 'sql' THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の言語が %（期待 sql）', v.lanname;
  END IF;

  -- Mobile の契約: rpc('get_record_streak', params: {'p_client_id': ...}) の 1 行目を読む
  IF v.args IS DISTINCT FROM 'p_client_id uuid' THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の引数が %（期待 p_client_id uuid。時刻を差し込む引数は作らない）', v.args;
  END IF;
  IF NOT v.proretset
     OR v.result IS DISTINCT FROM 'TABLE(as_of_date date, recorded_today boolean, streak_until_yesterday integer)' THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の戻り値が %（期待 TABLE(as_of_date date, recorded_today boolean, streak_until_yesterday integer)）', v.result;
  END IF;

  -- as_of_date は DB の今の JST の日付（UTC で固定する誤りは JST の 0〜9 時にしか挙動で出ないので、式でも固定する）
  IF position($s$(now() AT TIME ZONE 'Asia/Tokyo')::date$s$ IN v.prosrc) = 0 THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の本文に (now() AT TIME ZONE ''Asia/Tokyo'')::date が無い';
  END IF;

  IF v.description IS NULL THEN
    RAISE EXCEPTION 'FAIL: get_record_streak に COMMENT が無い';
  END IF;

  -- EXECUTE: authenticated あり / anon なし / PUBLIC なし
  -- （proacl が NULL は既定権限 = PUBLIC に EXECUTE。grantee = 0 は PUBLIC）
  IF NOT has_function_privilege('authenticated', c_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated が get_record_streak を実行できない';
  END IF;
  IF has_function_privilege('anon', c_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon が get_record_streak の EXECUTE を持っている';
  END IF;
  IF v.proacl IS NULL THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の proacl が NULL（既定権限 = PUBLIC に EXECUTE のまま）';
  END IF;
  IF EXISTS (SELECT 1 FROM aclexplode(v.proacl) a WHERE a.grantee = 0) THEN
    RAISE EXCEPTION 'FAIL: get_record_streak の EXECUTE が PUBLIC に付いている（%）', v.proacl;
  END IF;

  RAISE NOTICE 'OK: SECURITY INVOKER / search_path="" / STABLE / sql / 引数と戻り値の契約 / as_of_date の式 / COMMENT / EXECUTE は authenticated のみ（anon・PUBLIC なし。ACL = %）', v.proacl;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL RECORD STREAK TESTS PASSED'
