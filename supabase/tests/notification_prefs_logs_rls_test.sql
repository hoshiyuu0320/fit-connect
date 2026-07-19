-- =============================================================================
-- notification_preferences / notification_logs RLS テスト
-- （通知基盤 / 20260719010000_create_notification_prefs_and_logs.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/notification_prefs_logs_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL NOTIFICATION PREFS/LOGS RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 検証ケース:
--   [notification_preferences]
--   1. anon: SELECT 拒否（REVOKE ALL による permission denied）
--   2. 本人(A): upsert 可（INSERT ... ON CONFLICT DO UPDATE で enabled 切替）+ updated_at トリガー発火
--   3. 本人(A): SELECT 可（自分の行が見える）
--   4. 他人(B): SELECT 0 行（RLS でフィルタ）
--   5. 他人(B): INSERT 拒否（user_id=A への偽装は WITH CHECK violation）
--   [notification_logs]
--   6. anon: SELECT 拒否（REVOKE ALL による permission denied）
--   7. 本人(A): INSERT 拒否（INSERT ポリシー無し = service_role 専用書き込み）
--   8. 本人(A): SELECT 可（自分宛ログ 1 行が見える）+ UPDATE/DELETE は 0 行（ポリシー無し）
--   9. 他人(B): SELECT 0 行（RLS でフィルタ）
--  10. service_role: INSERT 可 + dedup_key 重複 INSERT が ON CONFLICT DO NOTHING で 0 行
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   user A: aaaaaaaa-2222-0000-0000-00000000000a（本人）
--   user B: bbbbbbbb-2222-0000-0000-00000000000b（他人）
--   pref  : user A の (kind='goal_achievement') 既存行（updated_at は 1 日前に細工し
--           トリガーによる更新を検証可能にする）
--   log   : user A 宛の既存ログ 1 行
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (user A/B, preference, log)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-2222-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-notif-a@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-2222-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-notif-b@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.notification_preferences (user_id, kind, enabled, updated_at) VALUES
  ('aaaaaaaa-2222-0000-0000-00000000000a', 'goal_achievement', true, now() - interval '1 day');

INSERT INTO public.notification_logs (user_id, kind, dedup_key, title, body, status) VALUES
  ('aaaaaaaa-2222-0000-0000-00000000000a', 'message',
   'message:rls-test-existing-log', '新着メッセージ', 'テスト本文', 'sent');

-- -----------------------------------------------------------------------------
-- ケース1: anon は notification_preferences を SELECT 不可（REVOKE ALL）
-- -----------------------------------------------------------------------------
\echo '--- case 1: [prefs] anon SELECT は permission denied であること'

SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.notification_preferences;
  RAISE EXCEPTION 'FAIL: anon が notification_preferences を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース2-3: 本人(A)は upsert / SELECT 可
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case 2: [prefs] 本人(A) upsert（ON CONFLICT DO UPDATE）可 + updated_at トリガー発火'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-2222-0000-0000-00000000000a';

DO $$
DECLARE
  v_enabled boolean;
  v_updated timestamptz;
BEGIN
  -- 新規 kind の upsert（INSERT 経路）
  INSERT INTO public.notification_preferences (user_id, kind, enabled, quiet_hours_start, quiet_hours_end)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'message', true, '22:00', '07:00')
  ON CONFLICT (user_id, kind)
  DO UPDATE SET enabled = EXCLUDED.enabled,
                quiet_hours_start = EXCLUDED.quiet_hours_start,
                quiet_hours_end = EXCLUDED.quiet_hours_end;

  -- 既存 kind の upsert（DO UPDATE 経路。enabled を false へ）
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'goal_achievement', false)
  ON CONFLICT (user_id, kind)
  DO UPDATE SET enabled = EXCLUDED.enabled;

  SELECT enabled, updated_at INTO v_enabled, v_updated
  FROM public.notification_preferences
  WHERE user_id = 'aaaaaaaa-2222-0000-0000-00000000000a' AND kind = 'goal_achievement';

  IF v_enabled THEN
    RAISE EXCEPTION 'FAIL: upsert 後も enabled=true のまま（DO UPDATE が効いていない）';
  END IF;
  -- setup で updated_at を 1 日前に細工済み。トリガーが now() に更新したことを確認
  IF v_updated < now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: updated_at トリガーが発火していない (updated_at=%)', v_updated;
  END IF;
  RAISE NOTICE 'OK: 本人 upsert 可（INSERT/DO UPDATE 両経路）+ updated_at トリガー発火';
END $$;

\echo '--- case 3: [prefs] 本人(A) SELECT で自分の行が見えること'

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.notification_preferences;
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 本人 SELECT が % 行（期待 2 行: message / goal_achievement）', cnt;
  END IF;
  RAISE NOTICE 'OK: 本人 SELECT 可（自分の 2 行が見える）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース4-5: 他人(B)は SELECT 0 行 / INSERT（user_id=A 偽装）拒否
-- -----------------------------------------------------------------------------
\echo '--- case 4: [prefs] 他人(B) SELECT が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-2222-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-2222-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.notification_preferences;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人 SELECT は 0 行';
END $$;

\echo '--- case 5: [prefs] 他人(B) の INSERT（user_id=A への偽装）が拒否されること'

DO $$
BEGIN
  INSERT INTO public.notification_preferences (user_id, kind, enabled)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'message', false);
  RAISE EXCEPTION 'FAIL: 他人が user_id=A で INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: 他人 INSERT は RLS WITH CHECK violation (42501) で拒否';
  WHEN unique_violation THEN
    RAISE EXCEPTION 'FAIL: RLS より先に UNIQUE 違反（WITH CHECK が機能していない疑い）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース6: anon は notification_logs を SELECT 不可（REVOKE ALL）
-- -----------------------------------------------------------------------------
\echo '--- case 6: [logs] anon SELECT は permission denied であること'

SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.notification_logs;
  RAISE EXCEPTION 'FAIL: anon が notification_logs を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース7-8: 本人(A)は INSERT 拒否 / SELECT 可 / UPDATE・DELETE は 0 行
-- -----------------------------------------------------------------------------
\echo '--- case 7: [logs] 本人(A) でも INSERT 拒否であること（service_role 専用書き込み）'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-2222-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-2222-0000-0000-00000000000a';

DO $$
BEGIN
  INSERT INTO public.notification_logs (user_id, kind, dedup_key)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'message', 'message:rls-test-forged-by-user');
  RAISE EXCEPTION 'FAIL: authenticated が notification_logs へ INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: authenticated INSERT は RLS violation (42501) で拒否';
END $$;

\echo '--- case 8: [logs] 本人(A) SELECT 可 + UPDATE/DELETE は 0 行（ポリシー無し）'

DO $$
DECLARE
  cnt int;
  n int;
BEGIN
  SELECT count(*) INTO cnt FROM public.notification_logs;
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 SELECT が % 行（期待 1 行）', cnt;
  END IF;

  UPDATE public.notification_logs SET status = 'failed'
  WHERE dedup_key = 'message:rls-test-existing-log';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: 本人 UPDATE が % 行成功（期待 0 行 = ポリシー無し）', n;
  END IF;

  DELETE FROM public.notification_logs
  WHERE dedup_key = 'message:rls-test-existing-log';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: 本人 DELETE が % 行成功（期待 0 行 = ポリシー無し）', n;
  END IF;

  RAISE NOTICE 'OK: 本人 SELECT 可（1 行）+ UPDATE/DELETE は 0 行';
END $$;

-- -----------------------------------------------------------------------------
-- ケース9: 他人(B)は SELECT 0 行
-- -----------------------------------------------------------------------------
\echo '--- case 9: [logs] 他人(B) SELECT が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-2222-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-2222-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.notification_logs;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人 SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース10: service_role は INSERT 可 + dedup_key 重複は ON CONFLICT DO NOTHING で 0 行
-- -----------------------------------------------------------------------------
\echo '--- case 10: [logs] service_role INSERT 可 + dedup 重複 INSERT が 0 行であること'

SET LOCAL ROLE service_role;

DO $$
DECLARE n int;
BEGIN
  -- 1回目: 新規 dedup_key → 1 行（自分が送信担当）
  INSERT INTO public.notification_logs (user_id, kind, dedup_key, status)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'message', 'message:rls-test-dedup-1', 'pending')
  ON CONFLICT (dedup_key) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の新規 INSERT が % 行（期待 1 行）', n;
  END IF;

  -- 2回目: 同じ dedup_key → 0 行（冪等スキップ判定）
  INSERT INTO public.notification_logs (user_id, kind, dedup_key, status)
  VALUES ('aaaaaaaa-2222-0000-0000-00000000000a', 'message', 'message:rls-test-dedup-1', 'pending')
  ON CONFLICT (dedup_key) DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: dedup 重複 INSERT が % 行（期待 0 行）', n;
  END IF;

  RAISE NOTICE 'OK: service_role INSERT 可（1 行）+ dedup 重複は 0 行（冪等）';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL NOTIFICATION PREFS/LOGS RLS TESTS PASSED'
