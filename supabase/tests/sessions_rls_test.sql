-- =============================================================================
-- sessions 顧客用 SELECT ポリシー RLS テスト
-- （フェーズ8.3 前半 / 20260906000000_sessions_client_select.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト
-- （payments_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/sessions_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL SESSIONS RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - Seed.sql のセッションと混ざらないよう、件数の集計は必ず試験用 2 行
--   （S1 / S2）に限定して行う
--
-- 検証ケース（計画書レーンA-2）:
--   (a) 本人クライアント C: 自分のセッション S1 のみ 1 行見える
--   (b) 他人のクライアント D: C のセッション S1 は 0 行（自分の S2 だけ見える）
--   (c) 担当トレーナー T: S1 / S2 の 2 行が従来どおり見える（回帰確認。
--       PERMISSIVE ポリシーの OR 結合でトレーナーの可視範囲が変わらないこと）
--   (d-1) anon（JWT クレーム無し）: 0 行（sessions は anon にもテーブル権限が
--       あるため permission denied ではなく RLS の 0 行で現れる）
--   (d-2) anon（JWT クレームに顧客 C の UUID が入っている状態）: 0 行
--       = sessions_client_select の TO authenticated 限定が効いていることの直接検証。
--       (d-1) は auth.uid() が NULL になるだけで role 限定を検証できない（ポリシーから
--       TO authenticated を外しても PASS してしまう）ため、本ケースが必須
--   (e) 顧客 C は書込不可: INSERT 拒否 / UPDATE 0 行 / DELETE 0 行
--       （顧客用に追加したのは SELECT 1 本のみであること）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T: aaaaaaaa-8306-0000-0000-00000000000a（S1 / S2 の担当トレーナー）
--   client  C: bbbbbbbb-8306-0000-0000-00000000000b（本人。T の担当クライアント）
--   client  D: cccccccc-8306-0000-0000-00000000000c（他人。同じく T の担当）
--   session S1: dddddddd-8306-0000-0000-00000000000d（C のセッション）
--   session S2: eeeeeeee-8306-0000-0000-00000000000e（D のセッション）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T / client C・D / session S1・S2)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-8306-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-sessions-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-8306-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-sessions-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('cccccccc-8306-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-sessions-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-8306-0000-0000-00000000000a', 'RLSテスト トレーナーT',
   'rls-test-sessions-t@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('bbbbbbbb-8306-0000-0000-00000000000b', 'RLSテスト顧客C',
   'aaaaaaaa-8306-0000-0000-00000000000a'),
  ('cccccccc-8306-0000-0000-00000000000c', 'RLSテスト顧客D',
   'aaaaaaaa-8306-0000-0000-00000000000a');

INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type
) VALUES
  ('dddddddd-8306-0000-0000-00000000000d',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'bbbbbbbb-8306-0000-0000-00000000000b',
   now() + interval '1 day', 60, 'scheduled', 'RLSテスト: Cのセッション'),
  ('eeeeeeee-8306-0000-0000-00000000000e',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'cccccccc-8306-0000-0000-00000000000c',
   now() + interval '2 day', 90, 'confirmed', 'RLSテスト: Dのセッション');

-- -----------------------------------------------------------------------------
-- ケース(a): 本人クライアント C は自分のセッション S1 のみ見える
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case a: 本人クライアント(C) に自分の S1 だけが見えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) SELECT が % 行（期待 1 行 = S1 のみ）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) に自分のセッション S1 が見えない (cnt=%)', cnt;
  END IF;
  RAISE NOTICE 'OK: 本人(C) は自分のセッション S1 のみ SELECT 可（1 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 他人のクライアント D には C のセッション S1 が見えない
-- -----------------------------------------------------------------------------
\echo '--- case b: 他人クライアント(D) に C の S1 が見えないこと'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-8306-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-8306-0000-0000-00000000000c';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人クライアント(D) に C の S1 が % 行見えている（期待 0 行）', cnt;
  END IF;

  -- 自分のセッション S2 は見えること（ポリシーが過剰に絞っていないことの確認）
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id = 'eeeeeeee-8306-0000-0000-00000000000e';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 他人クライアント(D) に自分の S2 が見えない (cnt=%)', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人クライアント(D) は C の S1 が 0 行（自分の S2 のみ 1 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): 担当トレーナー T は従来どおり S1 / S2 の 2 行が見える（回帰確認）
--   顧客用 SELECT は PERMISSIVE のため既存のトレーナー用 SELECT と OR 結合され、
--   トレーナーの可視範囲は増減しない
-- -----------------------------------------------------------------------------
\echo '--- case c: 担当トレーナー(T) に S1・S2 の 2 行が従来どおり見えること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-8306-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-8306-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) SELECT が % 行（期待 2 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) は S1・S2 の 2 行を SELECT 可（回帰なし）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d-1): anon（JWT クレーム無し）は 0 行
--   sessions は anon にも GRANT ALL が残っている（20251230131753）ため、
--   permission denied ではなく RLS によるフィルタで 0 行になる
--   ※ 既存のトレーナー用4本は role 未指定（TO PUBLIC）で anon ロールでも評価される。
--     直前のケースで設定した JWT クレームが残っていると auth.uid() がトレーナーの
--     UUID を返し、トレーナー用 SELECT が通ってしまうため、両形式を空にしてから
--     ロールを切り替える（auth.uid() は nullif(..., '') で NULL に落ちる）
-- -----------------------------------------------------------------------------
\echo '--- case d-1: anon（クレーム無し）に試験セッションが 0 行であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon（クレーム無し）SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d-2): anon ロール + 顧客 C の JWT クレームでも 0 行
--   sessions_client_select の `TO authenticated` 限定が効いていることの直接検証。
--   (d-1) はクレームを空にしているため auth.uid() が NULL になって 0 行になるだけで、
--   ポリシーから TO authenticated を外しても PASS してしまう（偽陰性）。
--   ここでは auth.uid() が顧客 C を返す状態のまま anon ロールで実行し、
--   「判定式は真だが role が違うのでポリシーが適用されない」ことを確認する。
--   （anon は authenticated のメンバーではないため TO authenticated は評価されない）
--   ※ トレーナー用4本は TO PUBLIC だが判定式が auth.uid() = trainer_id であり、
--     C の UUID では真にならないため、ここで 1 行でも見えたら role 限定の抜けを意味する
-- -----------------------------------------------------------------------------
\echo '--- case d-2: anon ロール + 顧客(C) クレームでも 0 行であること（TO authenticated 限定の検証）'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  -- 前提確認: auth.uid() が顧客 C を返している（クレームが効いている）こと。
  -- ここが NULL だと (d-1) と同じ偽陰性テストに退化してしまう
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-8306-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C の UUID）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで % 行見えている（期待 0 行）。sessions_client_select の TO authenticated 限定が効いていない', cnt;
  END IF;
  RAISE NOTICE 'OK: anon ロール + 顧客(C) クレームでも 0 行（sessions_client_select は anon に適用されない）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e): 顧客 C は INSERT / UPDATE / DELETE できない
--   追加したのは SELECT 1 本のみで、書込は既存のトレーナー用ポリシーしか無い
-- -----------------------------------------------------------------------------
\echo '--- case e-1: 顧客(C) の INSERT が拒否されること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';

DO $$
BEGIN
  INSERT INTO public.sessions (
    trainer_id, client_id, session_date, duration_minutes, status
  ) VALUES (
    'aaaaaaaa-8306-0000-0000-00000000000a',
    'bbbbbbbb-8306-0000-0000-00000000000b',
    now() + interval '3 day', 60, 'scheduled'
  );
  RAISE EXCEPTION 'FAIL: 顧客(C) が sessions を INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: 顧客 INSERT は RLS WITH CHECK violation (42501) で拒否';
END $$;

\echo '--- case e-2: 顧客(C) の UPDATE が 0 行であること'

DO $$
DECLARE n int;
BEGIN
  UPDATE public.sessions
  SET status = 'cancelled'
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客 UPDATE が % 行更新できてしまった（期待 0 行）', n;
  END IF;
  RAISE NOTICE 'OK: 顧客 UPDATE は 0 行（更新対象にならない）';
END $$;

\echo '--- case e-3: 顧客(C) の DELETE が 0 行であること'

DO $$
DECLARE n int;
BEGIN
  DELETE FROM public.sessions
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客 DELETE が % 行削除できてしまった（期待 0 行）', n;
  END IF;
  RAISE NOTICE 'OK: 顧客 DELETE は 0 行（削除対象にならない）';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL SESSIONS RLS TESTS PASSED'
