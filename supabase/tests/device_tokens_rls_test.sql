-- =============================================================================
-- device_tokens テーブル RLS テスト（通知基盤 / 20260719000100_create_device_tokens.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/device_tokens_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL DEVICE_TOKENS RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 検証ケース:
--   1. anon: SELECT 拒否（REVOKE ALL による permission denied）
--   2. 本人(A): SELECT 可（自分の行が見える）
--   3. 本人(A): INSERT 可（自分の user_id でトークン登録）
--   4. 本人(A): UPDATE 可（last_seen_at 更新 = upsert の DO UPDATE 相当）
--   5. 本人(A): DELETE 可（ログアウト時のトークン削除）
--   6. 他人(B): SELECT 0 行（RLS でフィルタ）
--   7. 他人(B): INSERT 拒否（user_id=A への偽装は WITH CHECK violation）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   user A: aaaaaaaa-1111-0000-0000-00000000000a（本人。client 想定）
--   user B: bbbbbbbb-1111-0000-0000-00000000000b（他人）
--   token D: dddddddd-1111-0000-0000-00000000000d（user A の既存トークン行）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (user A/B, device_token D)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-1111-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-device-a@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-1111-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-device-b@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.device_tokens (id, user_id, user_type, platform, token) VALUES
  ('dddddddd-1111-0000-0000-00000000000d',
   'aaaaaaaa-1111-0000-0000-00000000000a',
   'client', 'ios', 'rls-test-fcm-token-a-1');

-- -----------------------------------------------------------------------------
-- ケース1: anon は SELECT 不可（REVOKE ALL ON device_tokens FROM anon）
-- -----------------------------------------------------------------------------
\echo '--- case 1: anon SELECT は permission denied であること'

SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.device_tokens;
  RAISE EXCEPTION 'FAIL: anon が device_tokens を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース2-5: 本人(A)は SELECT / INSERT / UPDATE / DELETE 可
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case 2: 本人(A) SELECT で自分の行が見えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-1111-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-1111-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.device_tokens
  WHERE id = 'dddddddd-1111-0000-0000-00000000000d';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 SELECT で対象行が見えない (cnt=%)', cnt;
  END IF;
  RAISE NOTICE 'OK: 本人 SELECT 可（自分の行 1 行が見える）';
END $$;

\echo '--- case 3: 本人(A) INSERT ができること'

DO $$
BEGIN
  INSERT INTO public.device_tokens (user_id, user_type, platform, token)
  VALUES ('aaaaaaaa-1111-0000-0000-00000000000a',
          'client', 'android', 'rls-test-fcm-token-a-2');
  RAISE NOTICE 'OK: 本人 INSERT 可';
END $$;

\echo '--- case 4: 本人(A) UPDATE（last_seen_at 更新）ができること'

DO $$
DECLARE n int;
BEGIN
  UPDATE public.device_tokens
  SET last_seen_at = now()
  WHERE id = 'dddddddd-1111-0000-0000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 UPDATE が % 行（期待 1 行）', n;
  END IF;
  RAISE NOTICE 'OK: 本人 UPDATE 可（1 行更新）';
END $$;

\echo '--- case 5: 本人(A) DELETE（ログアウト時のトークン削除）ができること'

DO $$
DECLARE n int;
BEGIN
  DELETE FROM public.device_tokens
  WHERE user_id = 'aaaaaaaa-1111-0000-0000-00000000000a'
    AND token = 'rls-test-fcm-token-a-2';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 DELETE が % 行（期待 1 行）', n;
  END IF;
  RAISE NOTICE 'OK: 本人 DELETE 可（1 行削除）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース6-7: 他人(B)は SELECT 0 行 / INSERT（user_id=A 偽装）拒否
-- -----------------------------------------------------------------------------
\echo '--- case 6: 他人(B) SELECT が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-1111-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-1111-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.device_tokens;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人 SELECT は 0 行';
END $$;

\echo '--- case 7: 他人(B) の INSERT（user_id=A への偽装）が拒否されること'

DO $$
BEGIN
  INSERT INTO public.device_tokens (user_id, user_type, platform, token)
  VALUES ('aaaaaaaa-1111-0000-0000-00000000000a',
          'client', 'ios', 'rls-test-fcm-token-forged');
  RAISE EXCEPTION 'FAIL: 他人が user_id=A で INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: 他人 INSERT は RLS WITH CHECK violation (42501) で拒否';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL DEVICE_TOKENS RLS TESTS PASSED'
