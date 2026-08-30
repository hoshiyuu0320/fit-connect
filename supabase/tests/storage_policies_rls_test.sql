-- =============================================================================
-- Storage private 化ポリシー RLS テスト
-- （フェーズ8.2 / 20260829000000_storage_private_and_policies.sql
--   + 20260829000100_create_app_config.sql
--   + 20260830000000_profile_images_anon_select.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト
-- （device_tokens_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/storage_policies_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL STORAGE POLICIES RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - storage.objects への試験行は postgres（RLS バイパス）で直接 INSERT する
--
-- 検証ケース（計画書レーンA-5）:
--   (a) anon: message-photos の SELECT 不可（0 行。storage.objects は anon にも
--       テーブル権限があるため permission denied ではなく RLS の 0 行で現れる）
--   (b) 本人（クライアント C）: 自フォルダ {C}/… と Web アップロード分
--       {T}/{C}/… の両方が SELECT 可
--   (c) 担当トレーナー T: クライアントフォルダ {C}/… と自フォルダ配下
--       {T}/{C}/… の両方が SELECT 可
--   (d) 無関係の authenticated X: SELECT 0 行
--   (e) INSERT: 他人フォルダへは不可（WITH CHECK violation）・自フォルダへは可
--   (f) client-notes: 担当トレーナー T（フォルダ1階層目）と当該クライアント C
--       （フォルダ2階層目）のみ SELECT 可。無関係 X は 0 行
--   (g) app_config: anon が SELECT 可（seed 行 id=1 が読める）
--   (h) profile-images: anon が SELECT 可（登録フロー（QR→TrainerConfirmScreen）は
--       ログイン前に createSignedUrl が必要なため。message-photos の anon 0 行
--       （ケース(a)）は不変）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T: aaaaaaaa-8822-0000-0000-00000000000a（担当トレーナー）
--   client  C: bbbbbbbb-8822-0000-0000-00000000000b（本人。T の担当クライアント）
--   other   X: cccccccc-8822-0000-0000-00000000000c（無関係の authenticated）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T / client C / other X + storage.objects)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-8822-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-storage-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-8822-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-storage-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('cccccccc-8822-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-storage-x@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name) VALUES
  ('aaaaaaaa-8822-0000-0000-00000000000a', 'RLSテストトレーナー');

INSERT INTO public.clients (client_id, trainer_id, name) VALUES
  ('bbbbbbbb-8822-0000-0000-00000000000b',
   'aaaaaaaa-8822-0000-0000-00000000000a', 'RLSテストクライアント');

-- storage.objects へ試験行を直接 INSERT
--   （bucket_id / name / owner / owner_id 以外は DEFAULT・トリガー任せ。
--     バケット行は migration が作成済みの前提 = db reset 後に実行すること）
--   - Mobile アップロード規約: {clientUid}/…
--   - Web アップロード規約:    {trainerUid}/{clientUid}/…
INSERT INTO storage.objects (bucket_id, name, owner, owner_id) VALUES
  ('message-photos',
   'bbbbbbbb-8822-0000-0000-00000000000b/rls_test_photo_own.jpg',
   'bbbbbbbb-8822-0000-0000-00000000000b',
   'bbbbbbbb-8822-0000-0000-00000000000b'),
  ('message-photos',
   'aaaaaaaa-8822-0000-0000-00000000000a/bbbbbbbb-8822-0000-0000-00000000000b/rls_test_photo_web.jpg',
   'aaaaaaaa-8822-0000-0000-00000000000a',
   'aaaaaaaa-8822-0000-0000-00000000000a'),
  ('client-notes',
   'aaaaaaaa-8822-0000-0000-00000000000a/bbbbbbbb-8822-0000-0000-00000000000b/rls_test_note.pdf',
   'aaaaaaaa-8822-0000-0000-00000000000a',
   'aaaaaaaa-8822-0000-0000-00000000000a'),
  ('profile-images',
   'aaaaaaaa-8822-0000-0000-00000000000a/rls_test_profile.jpg',
   'aaaaaaaa-8822-0000-0000-00000000000a',
   'aaaaaaaa-8822-0000-0000-00000000000a');

-- -----------------------------------------------------------------------------
-- ケース(a): anon は message-photos を SELECT できない（0 行）
-- -----------------------------------------------------------------------------
\echo '--- case a: anon は message-photos の試験行が 0 行であること'

SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'message-photos'
    AND name LIKE '%rls\_test\_photo%';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon に message-photos が % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(b): 本人（クライアント C）は自フォルダ + Web アップロード分を SELECT 可
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case b: 本人(C) は自フォルダと {T}/{C}/… の 2 行が見えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8822-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8822-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'message-photos'
    AND name LIKE '%rls\_test\_photo%';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) SELECT が % 行（期待 2 行 = 自フォルダ + Webフォルダ）', cnt;
  END IF;
  RAISE NOTICE 'OK: 本人(C) SELECT 可（2 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): 担当トレーナー T はクライアントフォルダ + 自フォルダ配下を SELECT 可
-- -----------------------------------------------------------------------------
\echo '--- case c: 担当トレーナー(T) は {C}/… と {T}/{C}/… の 2 行が見えること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-8822-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-8822-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'message-photos'
    AND name LIKE '%rls\_test\_photo%';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) SELECT が % 行（期待 2 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) SELECT 可（2 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 無関係の authenticated X は SELECT 0 行
-- -----------------------------------------------------------------------------
\echo '--- case d: 無関係(X) は message-photos の試験行が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-8822-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-8822-0000-0000-00000000000c';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'message-photos'
    AND name LIKE '%rls\_test\_photo%';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 無関係(X) に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 無関係(X) SELECT は 0 行';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): INSERT は他人フォルダ不可・自フォルダ可（クライアント C として）
-- -----------------------------------------------------------------------------
\echo '--- case e-1: 本人(C) の他人フォルダ {X}/… への INSERT が拒否されること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8822-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8822-0000-0000-00000000000b';

DO $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name, owner, owner_id)
  VALUES ('message-photos',
          'cccccccc-8822-0000-0000-00000000000c/rls_test_evil.jpg',
          'bbbbbbbb-8822-0000-0000-00000000000b',
          'bbbbbbbb-8822-0000-0000-00000000000b');
  RAISE EXCEPTION 'FAIL: 他人フォルダへ INSERT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: 他人フォルダへの INSERT は RLS WITH CHECK violation (42501) で拒否';
END $$;

\echo '--- case e-2: 本人(C) の自フォルダ {C}/… への INSERT ができること'

DO $$
BEGIN
  INSERT INTO storage.objects (bucket_id, name, owner, owner_id)
  VALUES ('message-photos',
          'bbbbbbbb-8822-0000-0000-00000000000b/rls_test_new.jpg',
          'bbbbbbbb-8822-0000-0000-00000000000b',
          'bbbbbbbb-8822-0000-0000-00000000000b');
  RAISE NOTICE 'OK: 自フォルダへの INSERT 可';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): client-notes は担当トレーナー T と当該クライアント C のみ SELECT 可
-- -----------------------------------------------------------------------------
\echo '--- case f-1: 担当トレーナー(T) が client-notes の試験行を SELECT できること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-8822-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-8822-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'client-notes'
    AND name LIKE '%rls\_test\_note%';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) の client-notes SELECT が % 行（期待 1 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) は client-notes を SELECT 可';
END $$;

\echo '--- case f-2: 当該クライアント(C) が client-notes の試験行を SELECT できること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8822-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8822-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'client-notes'
    AND name LIKE '%rls\_test\_note%';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 当該クライアント(C) の client-notes SELECT が % 行（期待 1 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 当該クライアント(C) は client-notes を SELECT 可';
END $$;

\echo '--- case f-3: 無関係(X) は client-notes の試験行が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-8822-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-8822-0000-0000-00000000000c';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'client-notes'
    AND name LIKE '%rls\_test\_note%';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 無関係(X) に client-notes が % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 無関係(X) の client-notes SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(g): app_config は anon が SELECT 可（seed 行 id=1）
-- -----------------------------------------------------------------------------
\echo '--- case g: anon が app_config の seed 行 (id=1) を SELECT できること'

SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.app_config WHERE id = 1;
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon の app_config SELECT が % 行（期待 1 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon は app_config を SELECT 可（seed 行 1 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): anon は profile-images を SELECT 可（1 行）
--   登録フロー（QR→TrainerConfirmScreen）がログイン前に createSignedUrl を
--   必要とするための anon SELECT ポリシー（20260830000000）
-- -----------------------------------------------------------------------------
\echo '--- case h: anon が profile-images の試験行を SELECT できること'

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM storage.objects
  WHERE bucket_id = 'profile-images'
    AND name LIKE '%rls\_test\_profile%';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: anon の profile-images SELECT が % 行（期待 1 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon は profile-images を SELECT 可（1 行）';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL STORAGE POLICIES RLS TESTS PASSED'
