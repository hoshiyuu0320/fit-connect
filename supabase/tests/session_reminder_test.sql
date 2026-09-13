-- =============================================================================
-- セッション前日リマインダー 対象抽出関数 / 通知種別 CHECK / cron 登録テスト
-- （フェーズ8.3② / 20260913000000_session_reminder.sql
--   + 20260913000100_session_reminder_cron_target_date.sql）
--
-- find_sessions_for_reminder(target_date) の抽出条件（JST 暦日・status）と
-- EXECUTE 権限、notification_preferences.kind の CHECK 拡張、cron ジョブ
-- 'send-session-reminders' の登録内容を検証する自己完結テスト
-- （sessions_rls_test.sql / notification_prefs_logs_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/session_reminder_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL SESSION REMINDER TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - seed.sql のセッションと混ざらないよう、件数・並びの検証は必ず試験用の
--   セッション（S1〜S10）に限定して行う
--
-- JST 暦日境界の検証方針（重要）:
--   DB の TimeZone は UTC。timestamptz を UTC 日付で判定する実装（CURRENT_DATE 比較や
--   ::date キャスト）だと、対象日 JST 0:00〜8:59 のセッションは「前日」扱いで漏れ、
--   翌々日 JST 0:00〜8:59 のセッションは「対象日」扱いで混入する。本テストは
--   UTC 日付と JST 日付が食い違う時刻（対象日 JST 0:00 / 0:30 = 前日 UTC 15:00 / 15:30、
--   翌々日 JST 0:00 = 対象日 UTC 15:00）を必ず含め、UTC 判定の実装では PASS しないようにしている。
--
-- 検証ケース（計画書レーンA-4）:
--   (a-1) JST 暦日の境界: 対象日 0:00 / 0:30 / 23:30 / 23:59:59 JST は含む、
--         前日 23:59:59 JST と翌々日 0:00 JST は含まない
--   (a-2) 戻り値: session_date 昇順・trainer_name = trainers.name・target_date の
--         エコー・同一顧客の同日複数セッションは複数行
--   (a-3) 既定引数: 引数省略時は JST の「明日」が対象になる（UTC 日付ではない）
--   (b)   status: scheduled / confirmed は対象、cancelled / completed は除外
--   (c)   EXECUTE 権限: service_role は可（(a)(b) で実証）、authenticated / anon は
--         permission denied
--   (d)   notification_preferences.kind: 本人が 'session_reminder' を upsert できる
--         （Mobile の通知設定トグル経路）/ 未知の kind は check_violation
--   (e)   CHECK 作り直しの回帰: 既存種別 'message' / 'goal_achievement' が引き続き
--         INSERT できる（DROP → ADD で既存種別を落としていないこと）
--   (f)   cron 登録: jobname 'send-session-reminders' が存在し、active=false・
--         schedule '0 11 * * *'・command が Vault の project_url / secret_key を
--         apikey ヘッダーで送り、body に target_date を含み、timeout_milliseconds を
--         指定していること。旧方式の Authorization ヘッダーを含まないこと
--   (g)   既定引数の退行検知: 関数定義の引数テキストに 'Asia/Tokyo' が含まれる
--         （(a-3) は now() と同じ式で期待値を作るため同語反復になり得る。定義文字列で補強）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T : aaaaaaaa-0913-0000-0000-00000000000a（全セッションの担当トレーナー）
--   client  C : bbbbbbbb-0913-0000-0000-00000000000b（同日複数セッションを持つ顧客）
--   client  D : cccccccc-0913-0000-0000-00000000000c（別顧客）
--   対象日は 2026-09-13（JST）。session_date は JST 表記の固定値で INSERT する
--   session S1 : 11111111-0913-0000-0000-000000000001 C / 09-13 00:00:00 JST / scheduled  ← 含む（UTC では 09-12 15:00）
--   session S2 : 22222222-0913-0000-0000-000000000002 C / 09-13 00:30:00 JST / scheduled  ← 含む（UTC では 09-12 15:30）
--   session S3 : 33333333-0913-0000-0000-000000000003 D / 09-13 23:30:00 JST / confirmed  ← 含む（UTC では 09-13 14:30）
--   session S4 : 44444444-0913-0000-0000-000000000004 C / 09-13 23:59:59 JST / scheduled  ← 含む（UTC では 09-13 14:59:59）
--   session S5 : 55555555-0913-0000-0000-000000000005 C / 09-12 23:59:59 JST / scheduled  ← 含まない（前日）
--   session S6 : 66666666-0913-0000-0000-000000000006 C / 09-14 00:00:00 JST / scheduled  ← 含まない（翌々日。UTC では 09-13 15:00 = UTC 判定だと混入する）
--   session S7 : 77777777-0913-0000-0000-000000000007 C / 09-13 12:00:00 JST / cancelled  ← 含まない（status）
--   session S8 : 88888888-0913-0000-0000-000000000008 C / 09-13 13:00:00 JST / completed  ← 含まない（status）
--   session S9 : 99999999-0913-0000-0000-000000000009 C / JST の明日 12:00 / scheduled   ← 既定引数で含む
--   session S10: a0a0a0a0-0913-0000-0000-000000000010 C / JST の今日 12:00 / scheduled   ← 既定引数で含まない
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T / client C・D / session S1〜S10)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-0913-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'reminder-test-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-0913-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'reminder-test-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('cccccccc-0913-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'reminder-test-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-0913-0000-0000-00000000000a', 'リマインダーテスト トレーナーT',
   'reminder-test-t@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('bbbbbbbb-0913-0000-0000-00000000000b', 'リマインダーテスト顧客C',
   'aaaaaaaa-0913-0000-0000-00000000000a'),
  ('cccccccc-0913-0000-0000-00000000000c', 'リマインダーテスト顧客D',
   'aaaaaaaa-0913-0000-0000-00000000000a');

INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type
) VALUES
  ('11111111-0913-0000-0000-000000000001',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-13 00:00:00+09', 60, 'scheduled', 'リマインダーテスト: 対象日 0:00'),
  ('22222222-0913-0000-0000-000000000002',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-13 00:30:00+09', 60, 'scheduled', 'リマインダーテスト: 対象日 0:30'),
  ('33333333-0913-0000-0000-000000000003',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'cccccccc-0913-0000-0000-00000000000c',
   '2026-09-13 23:30:00+09', 45, 'confirmed', 'リマインダーテスト: 対象日 23:30'),
  ('44444444-0913-0000-0000-000000000004',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-13 23:59:59+09', 60, 'scheduled', 'リマインダーテスト: 対象日 23:59:59'),
  ('55555555-0913-0000-0000-000000000005',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-12 23:59:59+09', 60, 'scheduled', 'リマインダーテスト: 前日 23:59:59'),
  ('66666666-0913-0000-0000-000000000006',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-14 00:00:00+09', 60, 'scheduled', 'リマインダーテスト: 翌々日 0:00'),
  ('77777777-0913-0000-0000-000000000007',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-13 12:00:00+09', 60, 'cancelled', 'リマインダーテスト: cancelled'),
  ('88888888-0913-0000-0000-000000000008',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   '2026-09-13 13:00:00+09', 60, 'completed', 'リマインダーテスト: completed'),
  -- 既定引数（JST の明日）検証用。JST 暦日を timestamp で作ってから JST として解釈する
  ('99999999-0913-0000-0000-000000000009',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   (((now() AT TIME ZONE 'Asia/Tokyo')::date + 1)::timestamp + interval '12 hours') AT TIME ZONE 'Asia/Tokyo',
   60, 'scheduled', 'リマインダーテスト: JST 明日 12:00'),
  ('a0a0a0a0-0913-0000-0000-000000000010',
   'aaaaaaaa-0913-0000-0000-00000000000a', 'bbbbbbbb-0913-0000-0000-00000000000b',
   ((now() AT TIME ZONE 'Asia/Tokyo')::date::timestamp + interval '12 hours') AT TIME ZONE 'Asia/Tokyo',
   60, 'scheduled', 'リマインダーテスト: JST 今日 12:00');

-- -----------------------------------------------------------------------------
-- ケース(a-1): JST 暦日の境界（service_role として実行 = Edge Function の RPC 相当）
-- -----------------------------------------------------------------------------
\echo '--- case a-1: 対象日 2026-09-13 の JST 暦日境界（含む 4 件 / 含まない 2 件）'

SET LOCAL ROLE service_role;

DO $$
DECLARE
  v_ids uuid[];
BEGIN
  SELECT coalesce(array_agg(r.session_id), '{}') INTO v_ids
  FROM public.find_sessions_for_reminder('2026-09-13') r
  WHERE r.session_id IN ('11111111-0913-0000-0000-000000000001',
                         '22222222-0913-0000-0000-000000000002',
                         '33333333-0913-0000-0000-000000000003',
                         '44444444-0913-0000-0000-000000000004',
                         '55555555-0913-0000-0000-000000000005',
                         '66666666-0913-0000-0000-000000000006');

  -- 含む側（S1 / S2 は UTC 日付では前日になる時刻。UTC 判定の実装だとここで落ちる）
  IF NOT ('11111111-0913-0000-0000-000000000001' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: S1（対象日 0:00 JST = 前日 15:00 UTC）が含まれない';
  END IF;
  IF NOT ('22222222-0913-0000-0000-000000000002' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: S2（対象日 0:30 JST = 前日 15:30 UTC）が含まれない';
  END IF;
  IF NOT ('33333333-0913-0000-0000-000000000003' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: S3（対象日 23:30 JST）が含まれない';
  END IF;
  IF NOT ('44444444-0913-0000-0000-000000000004' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: S4（対象日 23:59:59 JST）が含まれない';
  END IF;

  -- 含まない側（S6 は UTC 日付では対象日になる時刻。UTC 判定の実装だとここで落ちる）
  IF '55555555-0913-0000-0000-000000000005' = ANY (v_ids) THEN
    RAISE EXCEPTION 'FAIL: S5（前日 23:59:59 JST）が含まれている';
  END IF;
  IF '66666666-0913-0000-0000-000000000006' = ANY (v_ids) THEN
    RAISE EXCEPTION 'FAIL: S6（翌々日 0:00 JST = 対象日 15:00 UTC）が含まれている';
  END IF;

  IF array_length(v_ids, 1) <> 4 THEN
    RAISE EXCEPTION 'FAIL: 境界ケースの抽出件数が % 件（期待 4 件）', array_length(v_ids, 1);
  END IF;
  RAISE NOTICE 'OK: JST 暦日境界 — 0:00 / 0:30 / 23:30 / 23:59:59 は含み、前日 23:59:59 / 翌々日 0:00 は含まない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(a-2): 戻り値の並び・列内容・同一顧客の複数行
-- -----------------------------------------------------------------------------
\echo '--- case a-2: session_date 昇順 / trainer_name・target_date / 同一顧客の同日複数セッションは複数行'

DO $$
DECLARE
  v_ids uuid[];
  v_row record;
  cnt int;
BEGIN
  -- 並び: 対象日の 4 件が session_date 昇順（S1 → S2 → S3 → S4）で返ること
  SELECT coalesce(array_agg(r.session_id), '{}') INTO v_ids
  FROM public.find_sessions_for_reminder('2026-09-13') r
  WHERE r.session_id IN ('11111111-0913-0000-0000-000000000001',
                         '22222222-0913-0000-0000-000000000002',
                         '33333333-0913-0000-0000-000000000003',
                         '44444444-0913-0000-0000-000000000004');
  IF v_ids <> ARRAY['11111111-0913-0000-0000-000000000001',
                    '22222222-0913-0000-0000-000000000002',
                    '33333333-0913-0000-0000-000000000003',
                    '44444444-0913-0000-0000-000000000004']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: 並びが session_date 昇順でない（%）', v_ids;
  END IF;

  -- 列内容: S3（顧客 D / confirmed）の行を検証
  SELECT * INTO v_row
  FROM public.find_sessions_for_reminder('2026-09-13') r
  WHERE r.session_id = '33333333-0913-0000-0000-000000000003';
  IF v_row.client_id <> 'cccccccc-0913-0000-0000-00000000000c'::uuid THEN
    RAISE EXCEPTION 'FAIL: S3 の client_id が % （期待 顧客 D）', v_row.client_id;
  END IF;
  IF v_row.trainer_id <> 'aaaaaaaa-0913-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: S3 の trainer_id が % （期待 トレーナー T）', v_row.trainer_id;
  END IF;
  IF v_row.trainer_name <> 'リマインダーテスト トレーナーT' THEN
    RAISE EXCEPTION 'FAIL: S3 の trainer_name が % （期待 trainers.name）', v_row.trainer_name;
  END IF;
  IF v_row.session_date <> '2026-09-13 23:30:00+09'::timestamptz THEN
    RAISE EXCEPTION 'FAIL: S3 の session_date が % （期待 2026-09-13 23:30 JST）', v_row.session_date;
  END IF;
  IF v_row.duration_minutes <> 45 THEN
    RAISE EXCEPTION 'FAIL: S3 の duration_minutes が % （期待 45）', v_row.duration_minutes;
  END IF;
  IF v_row.session_type <> 'リマインダーテスト: 対象日 23:30' THEN
    RAISE EXCEPTION 'FAIL: S3 の session_type が % ', v_row.session_type;
  END IF;
  IF v_row.target_date <> '2026-09-13'::date THEN
    RAISE EXCEPTION 'FAIL: S3 の target_date が % （期待 引数 2026-09-13 のエコー）', v_row.target_date;
  END IF;

  -- 同一顧客 C の同日セッション（S1 / S2 / S4）は 3 行返ること（1 顧客 1 行に畳まない）
  SELECT count(*) INTO cnt
  FROM public.find_sessions_for_reminder('2026-09-13') r
  WHERE r.client_id = 'bbbbbbbb-0913-0000-0000-00000000000b'
    AND r.session_id IN ('11111111-0913-0000-0000-000000000001',
                         '22222222-0913-0000-0000-000000000002',
                         '44444444-0913-0000-0000-000000000004');
  IF cnt <> 3 THEN
    RAISE EXCEPTION 'FAIL: 顧客 C の同日セッションが % 行（期待 3 行 = セッションごとに 1 行）', cnt;
  END IF;

  RAISE NOTICE 'OK: 並びは session_date 昇順、trainer_name / target_date 等の列が正しく、同一顧客は複数行';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(a-3): 既定引数は JST の「明日」
--   S9（JST 明日 12:00）は含み、S10（JST 今日 12:00）は含まないこと。
--   戻りの target_date が (now() AT TIME ZONE 'Asia/Tokyo')::date + 1 と一致すること
-- -----------------------------------------------------------------------------
\echo '--- case a-3: 引数省略時は JST の明日が対象になること'

DO $$
DECLARE
  v_ids uuid[];
  v_target date;
BEGIN
  SELECT coalesce(array_agg(r.session_id), '{}'), min(r.target_date) INTO v_ids, v_target
  FROM public.find_sessions_for_reminder() r
  WHERE r.session_id IN ('99999999-0913-0000-0000-000000000009',
                         'a0a0a0a0-0913-0000-0000-000000000010');

  IF NOT ('99999999-0913-0000-0000-000000000009' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: 既定引数で S9（JST 明日 12:00）が含まれない';
  END IF;
  IF 'a0a0a0a0-0913-0000-0000-000000000010' = ANY (v_ids) THEN
    RAISE EXCEPTION 'FAIL: 既定引数で S10（JST 今日 12:00）が含まれている';
  END IF;
  IF v_target <> (now() AT TIME ZONE 'Asia/Tokyo')::date + 1 THEN
    RAISE EXCEPTION 'FAIL: 既定引数の target_date が % （期待 JST の明日 %）',
      v_target, (now() AT TIME ZONE 'Asia/Tokyo')::date + 1;
  END IF;
  RAISE NOTICE 'OK: 既定引数は JST の明日（S9 のみ抽出、target_date=%）', v_target;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): status による絞り込み
-- -----------------------------------------------------------------------------
\echo '--- case b: scheduled / confirmed は対象、cancelled / completed は除外されること'

DO $$
DECLARE
  v_ids uuid[];
BEGIN
  SELECT coalesce(array_agg(r.session_id), '{}') INTO v_ids
  FROM public.find_sessions_for_reminder('2026-09-13') r
  WHERE r.session_id IN ('11111111-0913-0000-0000-000000000001',
                         '33333333-0913-0000-0000-000000000003',
                         '77777777-0913-0000-0000-000000000007',
                         '88888888-0913-0000-0000-000000000008');

  IF NOT ('11111111-0913-0000-0000-000000000001' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: scheduled の S1 が含まれない';
  END IF;
  IF NOT ('33333333-0913-0000-0000-000000000003' = ANY (v_ids)) THEN
    RAISE EXCEPTION 'FAIL: confirmed の S3 が含まれない';
  END IF;
  IF '77777777-0913-0000-0000-000000000007' = ANY (v_ids) THEN
    RAISE EXCEPTION 'FAIL: cancelled の S7 が含まれている';
  END IF;
  IF '88888888-0913-0000-0000-000000000008' = ANY (v_ids) THEN
    RAISE EXCEPTION 'FAIL: completed の S8 が含まれている';
  END IF;
  RAISE NOTICE 'OK: scheduled / confirmed のみ対象（cancelled / completed は除外）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(c): EXECUTE 権限
--   関数は SECURITY DEFINER のため、EXECUTE が漏れると顧客ロールから
--   全トレーナーの予定（他人のセッション）を読めてしまう。authenticated / anon は
--   permission denied (42501) で拒否されること。
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case c-1: authenticated（顧客 C）からの EXECUTE が拒否されること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0913-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0913-0000-0000-00000000000b';

DO $$
BEGIN
  PERFORM count(*) FROM public.find_sessions_for_reminder('2026-09-13');
  RAISE EXCEPTION 'FAIL: authenticated が find_sessions_for_reminder を EXECUTE できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: authenticated の EXECUTE は permission denied (42501)';
END $$;

RESET ROLE;

\echo '--- case c-2: anon からの EXECUTE が拒否されること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.find_sessions_for_reminder('2026-09-13');
  RAISE EXCEPTION 'FAIL: anon が find_sessions_for_reminder を EXECUTE できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon の EXECUTE は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d): notification_preferences.kind の CHECK 拡張
--   Mobile の通知設定トグルと同じ経路（本人が RLS 経由で upsert）で検証する
-- -----------------------------------------------------------------------------
\echo '--- case d-1: [prefs] 本人(C) が kind=session_reminder を upsert できること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0913-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0913-0000-0000-00000000000b';

DO $$
DECLARE v_enabled boolean;
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('bbbbbbbb-0913-0000-0000-00000000000b', 'session_reminder', false)
  ON CONFLICT (user_id, kind)
  DO UPDATE SET enabled = EXCLUDED.enabled;

  SELECT enabled INTO v_enabled
  FROM public.notification_preferences
  WHERE user_id = 'bbbbbbbb-0913-0000-0000-00000000000b' AND kind = 'session_reminder';
  IF v_enabled IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: kind=session_reminder の行が enabled=% （期待 false の行が 1 行）',
      coalesce(v_enabled::text, 'NULL（行なし）');
  END IF;
  RAISE NOTICE 'OK: 本人は kind=session_reminder を upsert 可（CHECK 拡張済み）';
END $$;

\echo '--- case d-2: [prefs] 未知の kind は check_violation で拒否されること'

DO $$
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('bbbbbbbb-0913-0000-0000-00000000000b', 'unknown_kind', false);
  RAISE EXCEPTION 'FAIL: 未知の kind を INSERT できてしまった（CHECK が効いていない）';
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'OK: 未知の kind は check_violation (23514) で拒否';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): CHECK 作り直しの回帰
--   20260913000000 は DROP CONSTRAINT → ADD CONSTRAINT で CHECK を作り直している。
--   既存種別 'message' / 'goal_achievement' が新しい CHECK から漏れていると、
--   既存のトグル操作（Mobile）が check_violation で落ちるため、ここで固定する
-- -----------------------------------------------------------------------------
\echo '--- case e: [prefs] 既存種別 message / goal_achievement が引き続き INSERT できること'

DO $$
DECLARE cnt int;
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES
    ('bbbbbbbb-0913-0000-0000-00000000000b', 'message', false),
    ('bbbbbbbb-0913-0000-0000-00000000000b', 'goal_achievement', false);

  SELECT count(*) INTO cnt
  FROM public.notification_preferences
  WHERE user_id = 'bbbbbbbb-0913-0000-0000-00000000000b'
    AND kind IN ('message', 'goal_achievement');
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: message / goal_achievement の行が % 行（期待 2 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 既存種別 message / goal_achievement は CHECK 作り直し後も INSERT 可';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(f): cron ジョブ 'send-session-reminders' の登録内容（postgres として実行）
--   20260913000000 で inactive 登録し、20260913000100 で command を
--   「target_date を cron 側で計算して body に入れる + timeout 60s」に書き換えている。
--   command の文字列検査で以下を固定する:
--     - Vault の project_url / secret_key を参照し、secret キーは apikey ヘッダーで送る
--     - 旧方式の Authorization ヘッダー（Bearer + 旧 service_role_key）を含まない
--     - body に target_date を含む（本送信は target_date 必須の契約）
--     - timeout_milliseconds を指定している（pg_net 既定 5000ms では候補ごとの
--       OAuth + FCM + DB 往復で切れる）
-- -----------------------------------------------------------------------------
\echo '--- case f: cron ジョブ send-session-reminders の登録内容（inactive / 0 11 * * * / command）'

DO $$
DECLARE
  v_job record;
BEGIN
  SELECT jobname, schedule, active, command INTO v_job
  FROM cron.job
  WHERE jobname = 'send-session-reminders';

  IF v_job.jobname IS NULL THEN
    RAISE EXCEPTION 'FAIL: cron ジョブ send-session-reminders が登録されていない';
  END IF;
  IF v_job.active IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: send-session-reminders が active=%（期待 false = 有効化はオーナー判断）', v_job.active;
  END IF;
  IF v_job.schedule <> '0 11 * * *' THEN
    RAISE EXCEPTION 'FAIL: send-session-reminders の schedule が %（期待 0 11 * * * = JST 20:00）', v_job.schedule;
  END IF;

  IF position('/functions/v1/send-session-reminders' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command が Edge Function send-session-reminders を呼んでいない';
  END IF;
  IF position('project_url' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command が Vault の project_url を参照していない';
  END IF;
  IF position('secret_key' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command が Vault の secret_key を参照していない';
  END IF;
  IF position('apikey' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command が apikey ヘッダーを送っていない';
  END IF;
  IF position('Authorization' IN v_job.command) > 0 THEN
    RAISE EXCEPTION 'FAIL: command が旧方式の Authorization ヘッダーを含んでいる';
  END IF;
  IF position('target_date' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command の body に target_date が無い（本送信は target_date 必須）';
  END IF;
  IF position('timeout_milliseconds' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: command に timeout_milliseconds が無い（pg_net 既定 5000ms のまま）';
  END IF;

  RAISE NOTICE 'OK: send-session-reminders は inactive / 0 11 * * * / apikey 方式 / target_date + timeout 指定あり';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 既定引数の退行検知
--   (a-3) は期待値を (now() AT TIME ZONE 'Asia/Tokyo')::date + 1 で作るため、
--   関数の既定が UTC 日付（CURRENT_DATE + 1）に退行しても JST 0:00〜8:59 以外の
--   時間帯では PASS してしまう。関数定義の引数テキストで 'Asia/Tokyo' を固定する
-- -----------------------------------------------------------------------------
\echo '--- case g: find_sessions_for_reminder の既定引数が JST（Asia/Tokyo）で定義されていること'

DO $$
DECLARE
  v_args text;
BEGIN
  v_args := pg_get_function_arguments('public.find_sessions_for_reminder'::regproc);
  IF position('Asia/Tokyo' IN v_args) = 0 THEN
    RAISE EXCEPTION 'FAIL: 既定引数に Asia/Tokyo が含まれない（%）', v_args;
  END IF;
  RAISE NOTICE 'OK: 既定引数は JST で定義（%）', v_args;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL SESSION REMINDER TESTS PASSED'
