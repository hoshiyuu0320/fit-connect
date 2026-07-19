-- =============================================================================
-- payments テーブル RLS テスト（cat3 機能2-A / 20260712120000_add_payment_records.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/payments_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL PAYMENTS RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 検証ケース:
--   1. anon: SELECT 拒否（REVOKE ALL による permission denied）
--   2. 本人トレーナー(A): SELECT 可（自分の行が見える）
--   3. 本人トレーナー(A): INSERT 可
--   4. 本人トレーナー(A): UPDATE 可（支払済みへの消込を想定）
--   5. 他人トレーナー(B): SELECT 0 行（RLS でフィルタ）
--   6. 他人トレーナー(B): INSERT 拒否（trainer_id 偽装は WITH CHECK violation）
--   7. 他人トレーナー(B): UPDATE 0 行（他人の行は更新対象にならない）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer A: aaaaaaaa-0000-0000-0000-00000000000a（本人）
--   trainer B: bbbbbbbb-0000-0000-0000-00000000000b（他人）
--   client  C: cccccccc-0000-0000-0000-00000000000c（trainer A の顧客）
--   payment D: dddddddd-0000-0000-0000-00000000000d（trainer A の支払記録）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer A/B, client C, payment D)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-trainer-a@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-trainer-b@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-0000-0000-0000-00000000000a', 'RLSテスト トレーナーA', 'rls-test-trainer-a@example.com'),
  ('bbbbbbbb-0000-0000-0000-00000000000b', 'RLSテスト トレーナーB', 'rls-test-trainer-b@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('cccccccc-0000-0000-0000-00000000000c', 'RLSテスト顧客C', 'aaaaaaaa-0000-0000-0000-00000000000a');

INSERT INTO public.payments (id, trainer_id, client_id, amount_yen, status, due_date) VALUES
  ('dddddddd-0000-0000-0000-00000000000d',
   'aaaaaaaa-0000-0000-0000-00000000000a',
   'cccccccc-0000-0000-0000-00000000000c',
   11000, 'unpaid', CURRENT_DATE);

-- -----------------------------------------------------------------------------
-- ケース1: anon は SELECT 不可（REVOKE ALL ON payments FROM anon）
-- -----------------------------------------------------------------------------
\echo '--- case 1: anon SELECT は permission denied であること'

SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.payments;
  RAISE EXCEPTION 'FAIL: anon が payments を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース2-4: 本人トレーナー(A)は SELECT / INSERT / UPDATE 可
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case 2: 本人トレーナー(A) SELECT で自分の行が見えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0000-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0000-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.payments
  WHERE id = 'dddddddd-0000-0000-0000-00000000000d';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 SELECT で対象行が見えない (cnt=%)', cnt;
  END IF;
  RAISE NOTICE 'OK: 本人 SELECT 可（自分の行 1 行が見える）';
END $$;

\echo '--- case 3: 本人トレーナー(A) INSERT ができること'

DO $$
BEGIN
  INSERT INTO public.payments (trainer_id, client_id, amount_yen, status, due_date, note)
  VALUES ('aaaaaaaa-0000-0000-0000-00000000000a',
          'cccccccc-0000-0000-0000-00000000000c',
          5000, 'unpaid', CURRENT_DATE, 'RLSテスト: 本人INSERT');
  RAISE NOTICE 'OK: 本人 INSERT 可';
END $$;

\echo '--- case 4: 本人トレーナー(A) UPDATE（支払済み消込）ができること'

DO $$
DECLARE n int;
BEGIN
  UPDATE public.payments
  SET status = 'paid', method = 'cash', paid_at = now()
  WHERE id = 'dddddddd-0000-0000-0000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人 UPDATE が % 行（期待 1 行）', n;
  END IF;
  RAISE NOTICE 'OK: 本人 UPDATE 可（1 行更新）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース5-7: 他人トレーナー(B)は SELECT 0 行 / INSERT 拒否 / UPDATE 0 行
-- -----------------------------------------------------------------------------
\echo '--- case 5: 他人トレーナー(B) SELECT が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0000-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0000-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.payments;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人トレーナーに % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人 SELECT は 0 行';
END $$;

\echo '--- case 6: 他人トレーナー(B) の INSERT（trainer_id=A への偽装）が拒否されること'

DO $$
BEGIN
  INSERT INTO public.payments (trainer_id, client_id, amount_yen)
  VALUES ('aaaaaaaa-0000-0000-0000-00000000000a',
          'cccccccc-0000-0000-0000-00000000000c',
          9999);
  RAISE EXCEPTION 'FAIL: 他人トレーナーが trainer_id=A で INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: 他人 INSERT は RLS WITH CHECK violation (42501) で拒否';
END $$;

\echo '--- case 7: 他人トレーナー(B) の UPDATE が 0 行であること'

DO $$
DECLARE n int;
BEGIN
  UPDATE public.payments
  SET status = 'paid'
  WHERE id = 'dddddddd-0000-0000-0000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人 UPDATE が % 行更新できてしまった（期待 0 行）', n;
  END IF;
  RAISE NOTICE 'OK: 他人 UPDATE は 0 行（更新対象にならない）';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL PAYMENTS RLS TESTS PASSED'
