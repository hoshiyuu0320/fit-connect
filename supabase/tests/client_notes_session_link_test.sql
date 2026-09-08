-- =============================================================================
-- client_notes.session_id 整合性トリガー + 顧客可視性テスト
-- （セッション⇔ノート紐づけ / 20260906000100_add_session_id_to_client_notes.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト
-- （sessions_rls_test.sql / payments_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/client_notes_session_link_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CLIENT_NOTES SESSION LINK TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - seed.sql のノートと混ざらないよう、件数の集計は必ず試験用のノート
--   （N0 / N1 / N2）に限定して行う
--
-- 拒否ケースの検証方針（重要）:
--   INSERT が落ちること自体は RLS 違反（42501）や FK 違反（23503）でも起こるため、
--   「落ちた = PASS」にすると偽陽性になる。本テストの拒否ケースは例外ハンドラで
--   SQLSTATE = 'P0001' かつ SQLERRM = 'NOTE_SESSION_MISMATCH'（トリガーが投げる
--   固定文字列）であることを確認し、それ以外は握り潰さず RAISE で再送出する。
--
-- 検証ケース（計画書レーンA-2）:
--   (a) 自分の担当クライアントのセッションには紐づけられる
--       （+ session_id 未指定のノートは従来どおり作成できる回帰確認）
--   (b-1) 他トレーナーの担当クライアントのセッション S3 を指定 → トリガーで拒否
--   (b-2) 自分の顧客 C のセッションだが担当トレーナーが違う S4 → 拒否
--         （trainer_id のみ不一致。トリガーの SECURITY DEFINER が効いていないと
--           参照先 sessions が RLS で 0 行になり素通ししてしまうケース）
--   (c-1) client_id と session.client_id が食い違う（同一トレーナー）→ 拒否
--   (c-2) UPDATE での付け替えも拒否（トリガーが INSERT だけでなく UPDATE も見ている）
--   (d) 顧客からは共有ノートのみ、かつ session_id 付きで読める
--       （未共有ノートは 0 行 = 存在も漏れない）
--   (e) セッション削除で session_id が NULL になる（ノート自体は残る）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T1: aaaaaaaa-9060-0000-0000-00000000000a（本人）
--   trainer T2: bbbbbbbb-9060-0000-0000-00000000000b（他人）
--   client  C : cccccccc-9060-0000-0000-00000000000c（T1 の担当。ノートの対象）
--   client  D : dddddddd-9060-0000-0000-00000000000d（T1 の担当。別顧客）
--   client  E : eeeeeeee-9060-0000-0000-00000000000e（T2 の担当）
--   session S1: 11111111-9060-0000-0000-000000000001（T1 / C）← 正しい紐づけ先
--   session S2: 22222222-9060-0000-0000-000000000002（T1 / D）← 顧客違い
--   session S3: 33333333-9060-0000-0000-000000000003（T2 / E）← 他トレーナー
--   session S4: 44444444-9060-0000-0000-000000000004（T2 / C）← トレーナーのみ違い
--   note    N0: 5555aaaa-9060-0000-0000-000000000005（session_id なし）
--   note    N1: 5555bbbb-9060-0000-0000-000000000006（S1 紐づけ・共有済み）
--   note    N2: 5555cccc-9060-0000-0000-000000000007（S1 紐づけ・未共有）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T1・T2 / client C・D・E / session S1〜S4)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-9060-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-link-test-t1@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-9060-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-link-test-t2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('cccccccc-9060-0000-0000-00000000000c', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-link-test-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('dddddddd-9060-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-link-test-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('eeeeeeee-9060-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'note-link-test-e@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-9060-0000-0000-00000000000a', 'ノート紐づけテスト トレーナーT1',
   'note-link-test-t1@example.com'),
  ('bbbbbbbb-9060-0000-0000-00000000000b', 'ノート紐づけテスト トレーナーT2',
   'note-link-test-t2@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('cccccccc-9060-0000-0000-00000000000c', 'ノート紐づけテスト顧客C',
   'aaaaaaaa-9060-0000-0000-00000000000a'),
  ('dddddddd-9060-0000-0000-00000000000d', 'ノート紐づけテスト顧客D',
   'aaaaaaaa-9060-0000-0000-00000000000a'),
  ('eeeeeeee-9060-0000-0000-00000000000e', 'ノート紐づけテスト顧客E',
   'bbbbbbbb-9060-0000-0000-00000000000b');

-- S4 は「顧客は C のまま、担当トレーナーだけ T2」という組み合わせ。
-- sessions には trainer_id と client_id の担当関係を縛る制約が無いため作成できる
INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type
) VALUES
  ('11111111-9060-0000-0000-000000000001',
   'aaaaaaaa-9060-0000-0000-00000000000a',
   'cccccccc-9060-0000-0000-00000000000c',
   now() - interval '1 day', 60, 'completed', 'ノート紐づけテスト: T1/C'),
  ('22222222-9060-0000-0000-000000000002',
   'aaaaaaaa-9060-0000-0000-00000000000a',
   'dddddddd-9060-0000-0000-00000000000d',
   now() - interval '2 day', 60, 'completed', 'ノート紐づけテスト: T1/D'),
  ('33333333-9060-0000-0000-000000000003',
   'bbbbbbbb-9060-0000-0000-00000000000b',
   'eeeeeeee-9060-0000-0000-00000000000e',
   now() - interval '3 day', 60, 'completed', 'ノート紐づけテスト: T2/E'),
  ('44444444-9060-0000-0000-000000000004',
   'bbbbbbbb-9060-0000-0000-00000000000b',
   'cccccccc-9060-0000-0000-00000000000c',
   now() - interval '4 day', 60, 'completed', 'ノート紐づけテスト: T2/C');

-- -----------------------------------------------------------------------------
-- ケース(a): 担当トレーナー T1 は自分の顧客 C のセッション S1 に紐づけられる
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case a: 担当トレーナー(T1) が自分の顧客(C) のセッション S1 に紐づけられること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9060-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9060-0000-0000-00000000000a';

DO $$
DECLARE v_session_id uuid;
BEGIN
  -- 紐づけ無し（session_id NULL）のノートは従来どおり作成できること（回帰確認）
  INSERT INTO public.client_notes (id, client_id, trainer_id, title, content)
  VALUES ('5555aaaa-9060-0000-0000-000000000005',
          'cccccccc-9060-0000-0000-00000000000c',
          'aaaaaaaa-9060-0000-0000-00000000000a',
          'ノート紐づけテスト: 紐づけ無し', '');

  -- S1 に紐づく共有ノート N1
  INSERT INTO public.client_notes (
    id, client_id, trainer_id, title, content, session_id, is_shared, shared_at
  ) VALUES (
    '5555bbbb-9060-0000-0000-000000000006',
    'cccccccc-9060-0000-0000-00000000000c',
    'aaaaaaaa-9060-0000-0000-00000000000a',
    'ノート紐づけテスト: 共有ノート', 'S1 の共有ノート',
    '11111111-9060-0000-0000-000000000001', true, now()
  );

  -- S1 に紐づく未共有ノート N2（ケース(d) で顧客に見えないことを確認する）
  INSERT INTO public.client_notes (
    id, client_id, trainer_id, title, content, session_id, is_shared
  ) VALUES (
    '5555cccc-9060-0000-0000-000000000007',
    'cccccccc-9060-0000-0000-00000000000c',
    'aaaaaaaa-9060-0000-0000-00000000000a',
    'ノート紐づけテスト: 未共有ノート', 'S1 の未共有ノート',
    '11111111-9060-0000-0000-000000000001', false
  );

  SELECT session_id INTO v_session_id FROM public.client_notes
  WHERE id = '5555bbbb-9060-0000-0000-000000000006';
  IF v_session_id IS DISTINCT FROM '11111111-9060-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: N1 の session_id が % （期待 S1）', coalesce(v_session_id::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: 自分の顧客のセッション S1 に紐づくノートを INSERT 可（紐づけ無しも可）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b-1): 他トレーナー T2 の顧客 E のセッション S3 は指定できない
--   client_id / trainer_id の両方が不一致
-- -----------------------------------------------------------------------------
\echo '--- case b-1: 他トレーナーの顧客のセッション S3 への紐づけがトリガーで拒否されること'

DO $$
BEGIN
  INSERT INTO public.client_notes (client_id, trainer_id, title, content, session_id)
  VALUES ('cccccccc-9060-0000-0000-00000000000c',
          'aaaaaaaa-9060-0000-0000-00000000000a',
          'ノート紐づけテスト: 他トレーナーのセッション', '',
          '33333333-9060-0000-0000-000000000003');
  RAISE EXCEPTION 'FAIL: 他トレーナーの顧客のセッション S3 に紐づけられてしまった';
EXCEPTION
  WHEN OTHERS THEN
    -- トリガー由来（P0001 / NOTE_SESSION_MISMATCH）以外は握り潰さず再送出する。
    -- 直前の FAIL 判定用 RAISE も、RLS 違反 (42501) や FK 違反 (23503) も
    -- ここで通してしまうと「別の理由で落ちたのに PASS」の偽陽性になる
    IF SQLSTATE <> 'P0001' OR SQLERRM <> 'NOTE_SESSION_MISMATCH' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'OK: 他トレーナーのセッション S3 は NOTE_SESSION_MISMATCH (P0001) で拒否';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b-2): 顧客は C で一致するが担当トレーナーが T2 のセッション S4 も拒否
--   トリガー関数が SECURITY DEFINER でないと、実行者 T1 からは sessions の RLS
--   （auth.uid() = trainer_id）により S4 が 0 行に見え、NOT FOUND で素通しする。
--   本ケースはその抜けを直接検出する
-- -----------------------------------------------------------------------------
\echo '--- case b-2: 担当トレーナーだけが違うセッション S4 への紐づけが拒否されること'

DO $$
BEGIN
  INSERT INTO public.client_notes (client_id, trainer_id, title, content, session_id)
  VALUES ('cccccccc-9060-0000-0000-00000000000c',
          'aaaaaaaa-9060-0000-0000-00000000000a',
          'ノート紐づけテスト: 他トレーナー担当の同一顧客セッション', '',
          '44444444-9060-0000-0000-000000000004');
  RAISE EXCEPTION 'FAIL: 担当トレーナーの違うセッション S4 に紐づけられてしまった（SECURITY DEFINER が効いていない可能性）';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLSTATE <> 'P0001' OR SQLERRM <> 'NOTE_SESSION_MISMATCH' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'OK: trainer_id のみ不一致の S4 も NOTE_SESSION_MISMATCH (P0001) で拒否';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c-1): 同一トレーナーでも顧客が違うセッション S2 は指定できない
-- -----------------------------------------------------------------------------
\echo '--- case c-1: 別顧客(D) のセッション S2 への紐づけが拒否されること'

DO $$
BEGIN
  INSERT INTO public.client_notes (client_id, trainer_id, title, content, session_id)
  VALUES ('cccccccc-9060-0000-0000-00000000000c',
          'aaaaaaaa-9060-0000-0000-00000000000a',
          'ノート紐づけテスト: 別顧客のセッション', '',
          '22222222-9060-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL: 別顧客(D) のセッション S2 に紐づけられてしまった';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLSTATE <> 'P0001' OR SQLERRM <> 'NOTE_SESSION_MISMATCH' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'OK: client_id のみ不一致の S2 も NOTE_SESSION_MISMATCH (P0001) で拒否';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c-2): UPDATE による付け替えも拒否される
--   トリガーが BEFORE INSERT だけでなく UPDATE も対象にしていることの検証。
--   併せて、拒否後も元の紐づけ（S1）が保たれていることを確認する
-- -----------------------------------------------------------------------------
\echo '--- case c-2: UPDATE で別顧客のセッションへ付け替えられないこと'

DO $$
DECLARE v_session_id uuid;
BEGIN
  BEGIN
    UPDATE public.client_notes
    SET session_id = '22222222-9060-0000-0000-000000000002'
    WHERE id = '5555bbbb-9060-0000-0000-000000000006';
    RAISE EXCEPTION 'FAIL: UPDATE で別顧客(D) のセッション S2 へ付け替えられてしまった';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLSTATE <> 'P0001' OR SQLERRM <> 'NOTE_SESSION_MISMATCH' THEN
        RAISE;
      END IF;
  END;

  SELECT session_id INTO v_session_id FROM public.client_notes
  WHERE id = '5555bbbb-9060-0000-0000-000000000006';
  IF v_session_id IS DISTINCT FROM '11111111-9060-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: 拒否後の N1 の session_id が % （期待 S1 のまま）',
      coalesce(v_session_id::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: UPDATE も NOTE_SESSION_MISMATCH (P0001) で拒否（S1 の紐づけは保持）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d): 顧客 C からは共有ノート N1 のみが見え、session_id も読める
--   既存の clients_select_shared_notes（is_shared = true AND client_id = auth.uid()）
--   がそのまま効き、未共有ノート N2 と紐づけ無しノート N0 は 0 行になる。
--   「未共有ノートの存在を顧客に匂わせない」ことが要件
-- -----------------------------------------------------------------------------
\echo '--- case d: 顧客(C) には共有ノート N1 だけが session_id 付きで見えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"cccccccc-9060-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-9060-0000-0000-00000000000c';

DO $$
DECLARE
  cnt          int;
  v_session_id uuid;
BEGIN
  SELECT count(*) INTO cnt FROM public.client_notes
  WHERE id IN ('5555aaaa-9060-0000-0000-000000000005',
               '5555bbbb-9060-0000-0000-000000000006',
               '5555cccc-9060-0000-0000-000000000007');
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) SELECT が % 行（期待 1 行 = 共有ノート N1 のみ）', cnt;
  END IF;

  SELECT session_id INTO v_session_id FROM public.client_notes
  WHERE id = '5555bbbb-9060-0000-0000-000000000006';
  IF v_session_id IS DISTINCT FROM '11111111-9060-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) から見た N1 の session_id が % （期待 S1）',
      coalesce(v_session_id::text, 'NULL');
  END IF;

  -- 未共有ノート N2 は同じ S1 に紐づいているが 0 行であること（存在も漏れない）
  SELECT count(*) INTO cnt FROM public.client_notes
  WHERE id = '5555cccc-9060-0000-0000-000000000007';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) に未共有ノート N2 が % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 顧客(C) には共有ノート N1 のみ（session_id=S1）。未共有 N2 は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e): セッション S1 を削除すると session_id が NULL になり、ノートは残る
--   client_notes_session_id_fkey の ON DELETE SET NULL による UPDATE が
--   整合性トリガーに阻まれないこと（session_id IS NULL の早期 RETURN）も同時に検証する
-- -----------------------------------------------------------------------------
\echo '--- case e: セッション削除で session_id が NULL になりノート本体は残ること'

DO $$
DECLARE
  cnt          int;
  v_session_id uuid;
  v_title      text;
BEGIN
  DELETE FROM public.sessions WHERE id = '11111111-9060-0000-0000-000000000001';

  SELECT count(*) INTO cnt FROM public.client_notes
  WHERE id IN ('5555bbbb-9060-0000-0000-000000000006',
               '5555cccc-9060-0000-0000-000000000007');
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: セッション削除でノートが道連れになった（残 % 行 / 期待 2 行）', cnt;
  END IF;

  SELECT session_id, title INTO v_session_id, v_title FROM public.client_notes
  WHERE id = '5555bbbb-9060-0000-0000-000000000006';
  IF v_session_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: セッション削除後も N1 の session_id が % （期待 NULL）', v_session_id;
  END IF;
  IF v_title <> 'ノート紐づけテスト: 共有ノート' THEN
    RAISE EXCEPTION 'FAIL: N1 の title が書き換わっている（%）', v_title;
  END IF;
  RAISE NOTICE 'OK: セッション削除で session_id は NULL、ノート 2 件は内容ごと残存';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CLIENT_NOTES SESSION LINK TESTS PASSED'
