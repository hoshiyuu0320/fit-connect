-- =============================================================================
-- トレーナー向けアラートの朝のまとめ通知（フェーズ9.1 拡張 push `client_alert`、PR2）の DB 側テスト
-- （20261004000000_client_alert_push.sql 適用後の状態。設計書 §8・§10.2:
--   docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md）
--
-- notification_preferences.kind の CHECK 拡張（client_alert）と、cron ジョブ
-- 'notify-trainer-alerts' の登録内容（schedule・body の対象日・dry_run・timeout）を検証する自己完結テスト。
-- url / headers（Vault の apikey 方式）と EXPLAIN での解析は cron_jobs_test.sql が4ジョブまとめて確かめる。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/client_alert_push_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CLIENT ALERT PUSH TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - active はアサートしない（cron_jobs_test.sql の慣行。ローカルは migration で inactive のまま、
--   リモートはオーナーが有効化するため環境で値が違う。「無効で登録」は migration 末尾の検査が固定する）
--
-- 検証ケース:
--   (a) CHECK: 本人（トレーナー）が kind = 'client_alert' を RLS 経由で upsert できる（Web の通知設定の経路）
--   (b) CHECK: 未知の kind は check_violation で拒否される
--   (c) CHECK の作り直しの回帰: 既存種別 message / goal_achievement / session_reminder が引き続き INSERT できる
--   (d) cron: jobname 'notify-trainer-alerts' が 1 件で、schedule が '10 21 * * *'（JST 06:10）
--   (e) cron の body: dry_run が false・timeout_milliseconds が 60000
--   (f) cron の body の target_date が「実行時点の JST の今日」になる（+ 1 しない）。
--       文字列の部分一致だけだと UTC の日付に取り違えても通るので、command から to_char(...) の式を
--       正規表現で取り出し、now() を固定した時刻に置き換えて EXECUTE し、返る日付を確かめる:
--         2026-10-03 21:10:00+00（= 06:10 JST）→ 2026-10-04
--         2026-10-03 14:59:59+00（= 23:59:59 JST）→ 2026-10-03
--         2026-10-03 15:00:00+00（= 00:00:00 JST）→ 2026-10-04
--       「+ 1 が無い」は position('+ 1') ではなく正規表現 \+\s*1 で否定する
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ（postgres として実行。RLS バイパス）
--   trainer T : aaaaaaaa-1004-0000-0000-00000000000a
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-1004-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'client-alert-push-test-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-1004-0000-0000-00000000000a', 'まとめ通知テスト トレーナーT',
   'client-alert-push-test-t@example.com');

-- -----------------------------------------------------------------------------
-- ケース(a)〜(c): notification_preferences.kind の CHECK 拡張
--   Web の通知設定と同じ経路（本人が RLS 経由で upsert）で検証する
-- -----------------------------------------------------------------------------
\echo '--- case a: [prefs] 本人(T) が kind=client_alert を upsert できること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-1004-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-1004-0000-0000-00000000000a';

DO $$
DECLARE v_enabled boolean;
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('aaaaaaaa-1004-0000-0000-00000000000a', 'client_alert', false)
  ON CONFLICT (user_id, kind)
  DO UPDATE SET enabled = EXCLUDED.enabled;

  -- 2回目（オン）に戻せる = upsert の更新側も通る
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('aaaaaaaa-1004-0000-0000-00000000000a', 'client_alert', true)
  ON CONFLICT (user_id, kind)
  DO UPDATE SET enabled = EXCLUDED.enabled;

  SELECT enabled INTO v_enabled
  FROM public.notification_preferences
  WHERE user_id = 'aaaaaaaa-1004-0000-0000-00000000000a' AND kind = 'client_alert';
  IF v_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: kind=client_alert の行が enabled=%（期待 true の行が 1 行）',
      coalesce(v_enabled::text, 'NULL（行なし）');
  END IF;
  RAISE NOTICE 'OK: 本人は kind=client_alert を upsert 可（CHECK 拡張済み）';
END $$;

\echo '--- case b: [prefs] 未知の kind は check_violation で拒否されること'

DO $$
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('aaaaaaaa-1004-0000-0000-00000000000a', 'client_alerts', false);
  RAISE EXCEPTION 'FAIL: 未知の kind（client_alerts）を INSERT できてしまった（CHECK が効いていない）';
EXCEPTION
  WHEN check_violation THEN
    RAISE NOTICE 'OK: 未知の kind は check_violation (23514) で拒否';
END $$;

\echo '--- case c: [prefs] 既存種別 message / goal_achievement / session_reminder が引き続き INSERT できること'

DO $$
DECLARE cnt int;
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES
    ('aaaaaaaa-1004-0000-0000-00000000000a', 'message', false),
    ('aaaaaaaa-1004-0000-0000-00000000000a', 'goal_achievement', false),
    ('aaaaaaaa-1004-0000-0000-00000000000a', 'session_reminder', false);

  SELECT count(*) INTO cnt
  FROM public.notification_preferences
  WHERE user_id = 'aaaaaaaa-1004-0000-0000-00000000000a'
    AND kind IN ('message', 'goal_achievement', 'session_reminder');
  IF cnt <> 3 THEN
    RAISE EXCEPTION 'FAIL: 既存種別の行が % 行（期待 3 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 既存種別 message / goal_achievement / session_reminder は CHECK 作り直し後も INSERT 可';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d): cron の登録と schedule（active は断定しない）
-- -----------------------------------------------------------------------------
\echo '--- case d: [cron] notify-trainer-alerts が 1 件で、schedule が 10 21 * * * であること'

DO $$
DECLARE
  cnt int;
  v_schedule text;
BEGIN
  SELECT count(*), min(schedule) INTO cnt, v_schedule
  FROM cron.job WHERE jobname = 'notify-trainer-alerts';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: cron ジョブ notify-trainer-alerts が % 件（期待 1 件）', cnt;
  END IF;
  IF v_schedule <> '10 21 * * *' THEN
    RAISE EXCEPTION 'FAIL: notify-trainer-alerts の schedule が %（期待 10 21 * * * = JST 06:10）', v_schedule;
  END IF;
  RAISE NOTICE 'OK: notify-trainer-alerts は 1 件 / schedule %', v_schedule;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): body の dry_run と timeout
-- -----------------------------------------------------------------------------
\echo '--- case e: [cron] body の dry_run が false、timeout_milliseconds が 60000 であること'

DO $$
DECLARE
  v_command text;
  v_timeout int;
BEGIN
  SELECT command INTO v_command FROM cron.job WHERE jobname = 'notify-trainer-alerts';

  IF v_command !~ $r$'dry_run',\s*false\M$r$ THEN
    RAISE EXCEPTION 'FAIL: command の body に ''dry_run'', false が無い（関数は省略時 dry run で何も送らない）';
  END IF;
  IF v_command ~ $r$'dry_run',\s*true\M$r$ THEN
    RAISE EXCEPTION 'FAIL: command の body に ''dry_run'', true が含まれる';
  END IF;

  v_timeout := substring(v_command FROM 'timeout_milliseconds\s*:=\s*(\d+)')::int;
  IF v_timeout IS DISTINCT FROM 60000 THEN
    RAISE EXCEPTION 'FAIL: timeout_milliseconds が %（期待 60000）', coalesce(v_timeout::text, 'なし');
  END IF;
  RAISE NOTICE 'OK: body は dry_run false / timeout_milliseconds 60000';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): body の target_date が JST の今日になる（+ 1 しない）
-- -----------------------------------------------------------------------------
\echo '--- case f: [cron] target_date の式が実行時点の JST の今日を返すこと（固定時刻で EXECUTE）'

DO $$
DECLARE
  v_command text;
  v_expr text;
  v_case record;
  v_got text;
BEGIN
  SELECT command INTO v_command FROM cron.job WHERE jobname = 'notify-trainer-alerts';

  -- 'target_date', の直後の to_char( ... 'YYYY-MM-DD') を取り出す（最短一致）
  v_expr := substring(v_command FROM $r$'target_date',\s*(to_char\(.*?'YYYY-MM-DD'\))$r$);
  IF v_expr IS NULL THEN
    RAISE EXCEPTION 'FAIL: command から target_date の to_char(...) 式を取り出せない';
  END IF;
  IF v_expr ~ $r$\+\s*1$r$ THEN
    RAISE EXCEPTION 'FAIL: target_date の式に + 1 が含まれる（JST の明日になってしまう）: %', v_expr;
  END IF;
  IF position('now()' IN v_expr) = 0 THEN
    RAISE EXCEPTION 'FAIL: target_date の式が now() を使っていない（固定時刻に置き換えられない）: %', v_expr;
  END IF;

  FOR v_case IN
    SELECT * FROM (VALUES
      ('2026-10-03 21:10:00+00', '2026-10-04', 'cron の実行時刻 21:10 UTC = 06:10 JST'),
      ('2026-10-03 14:59:59+00', '2026-10-03', 'JST 23:59:59（UTC と同じ日付）'),
      ('2026-10-03 15:00:00+00', '2026-10-04', 'JST 00:00:00（UTC はまだ前日）')
    ) AS t(at_utc, expected, label)
  LOOP
    EXECUTE 'SELECT ' || replace(v_expr, 'now()', quote_literal(v_case.at_utc) || '::timestamptz')
      INTO v_got;
    IF v_got IS DISTINCT FROM v_case.expected THEN
      RAISE EXCEPTION 'FAIL: now() = % で target_date が %（期待 %。%）',
        v_case.at_utc, coalesce(v_got, 'NULL'), v_case.expected, v_case.label;
    END IF;
    RAISE NOTICE 'OK: now() = % → target_date % (%)', v_case.at_utc, v_got, v_case.label;
  END LOOP;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CLIENT ALERT PUSH TESTS PASSED'
