-- =============================================================================
-- sessions RLS + 顧客用読み取り関数 get_my_sessions テスト
-- （フェーズ8.4 / 20260913000300_sessions_client_rpc.sql + 20260913000400_sessions_drop_client_select.sql）
--
-- 前提（両 migration の適用後の状態を検証する）:
--   顧客用 SELECT ポリシー sessions_client_select（20260906000000）は 20260913000400 で撤去済みで、
--   顧客は sessions をテーブルから直接読めない（トレーナーの内輪メモ memo を読む経路を無くす）。
--   顧客の読み取りは、列の許可リストを返す SECURITY DEFINER 関数 get_my_sessions() 経由のみ
--   （memo は返さない）。トレーナー用4本（auth.uid() = trainer_id）は従来どおり。
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
-- - Seed.sql のセッションと混ざらないよう、テーブル直 SELECT の件数は必ず試験用の行
--   （S1〜S4）に限定して数える。get_my_sessions() は呼び出し者本人のセッションしか
--   返さないため、試験用ユーザー（C / D / T）で呼んだ結果は全件をそのまま数える
--   （Seed の行が 1 行でも混ざれば FAIL になり、本人限定の検証を兼ねる）
--
-- 検証ケース:
--   (a) 顧客 C: テーブル直 SELECT は自分のセッションも 0 行（ポリシー撤去の確認）
--       = memo を読む経路が無い
--   (b) 顧客 C: get_my_sessions() は自分の S1 のみ 1 行。値は実テーブルのまま、memo キーは無い
--   (c) 他人の顧客 D: get_my_sessions() に C の S1 は出ない（p_ids で S1 を名指ししても 0 行）。
--       自分の S2 は返る
--   (d) 担当トレーナー T: テーブル直 SELECT で S1 / S2 の 2 行・memo も読める（回帰確認）。
--       T の get_my_sessions() は 0 行（T は顧客ではない）
--   (e-1) anon（JWT クレーム無し）: get_my_sessions の EXECUTE が permission denied（42501）。
--         テーブル直 SELECT は 0 行
--   (e-2) anon（JWT クレームに顧客 C の UUID）: 同じく EXECUTE が 42501、テーブル直 SELECT は 0 行
--         = 拒否が「auth.uid() が NULL だから 0 行」ではなく role（anon）単位の EXECUTE 剥奪で
--           効いていることの直接検証。anon に EXECUTE が残っていれば、この状態では C の行が返る
--   (f) p_from（以上）/ p_before（未満）/ p_ids の絞り込みがそれぞれ効くこと
--       （境界・組み合わせ・他人の ID の混入・空配列・全引数省略）
--   (g) メタデータ: 戻り列が許可リストどおりで memo が無い / 引数の契約 /
--       SECURITY DEFINER かつ search_path 固定 / EXECUTE 権限（anon・PUBLIC 不可、
--       authenticated 可）/ sessions_client_select が無くトレーナー用4本は残っている
--   (h) 顧客 C は書込不可: INSERT 拒否 / UPDATE 0 行 / DELETE 0 行
--       （書込は既存のトレーナー用ポリシーしか無いこと）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T: aaaaaaaa-8306-0000-0000-00000000000a（S1〜S4 の担当トレーナー）
--   client  C: bbbbbbbb-8306-0000-0000-00000000000b（本人。T の担当クライアント）
--   client  D: cccccccc-8306-0000-0000-00000000000c（他人。同じく T の担当）
--   session S1: dddddddd-8306-0000-0000-00000000000d（C のセッション。memo 入り）
--   session S2: eeeeeeee-8306-0000-0000-00000000000e（D のセッション。memo 入り）
--   session S3: dddddddd-8306-0000-0000-0000000000d3（C の過去セッション。ケース(f) で追加）
--   session S4: dddddddd-8306-0000-0000-0000000000d4（C の先のセッション。ケース(f) で追加）
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

-- memo は顧客に見せないトレーナーの内輪メモ。ケース(d) でトレーナーには読めること、
-- ケース(a)(b) で顧客にはどの経路でも読めないことを確認する
INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type, memo
) VALUES
  ('dddddddd-8306-0000-0000-00000000000d',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'bbbbbbbb-8306-0000-0000-00000000000b',
   now() + interval '1 day', 60, 'scheduled', 'RLSテスト: Cのセッション',
   'RLSテスト: Cについての内輪メモ'),
  ('eeeeeeee-8306-0000-0000-00000000000e',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'cccccccc-8306-0000-0000-00000000000c',
   now() + interval '2 day', 90, 'confirmed', 'RLSテスト: Dのセッション',
   'RLSテスト: Dについての内輪メモ');

-- -----------------------------------------------------------------------------
-- ケース(a): 顧客 C はテーブル直 SELECT で自分のセッションも 0 行
--   sessions_client_select の撤去により、C に当たるのはトレーナー用 SELECT
--   （auth.uid() = trainer_id）だけになる = memo を読む経路が無い
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case a: 顧客(C) のテーブル直 SELECT が自分のセッションも 0 行であること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) のテーブル直 SELECT が % 行（期待 0 行。sessions_client_select が残っている可能性）', cnt;
  END IF;

  -- 自分が顧客の行（client_id = 本人）を ID で限定せずに数えても 0 行であること
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE client_id = 'bbbbbbbb-8306-0000-0000-00000000000b';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) が client_id = 本人 の行を % 行直接読めている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 顧客(C) のテーブル直 SELECT は自分のセッションも 0 行（memo を読む経路なし）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 顧客 C の get_my_sessions() は自分の S1 だけを 1 行返す
--   全件を数える（C は試験用ユーザーで Seed のセッションは無いため、1 行を超えたら
--   本人以外の行が混ざっている）。値が実テーブルのまま返り、memo キーが無いことも確認する
-- -----------------------------------------------------------------------------
\echo '--- case b: 顧客(C) の get_my_sessions() が自分の S1 のみ 1 行であること'

DO $$
DECLARE
  cnt   int;
  v_row jsonb;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_my_sessions();
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) の get_my_sessions() が % 行（期待 1 行 = S1 のみ）', cnt;
  END IF;

  SELECT to_jsonb(g) INTO v_row FROM public.get_my_sessions() AS g;
  IF v_row->>'id' IS DISTINCT FROM 'dddddddd-8306-0000-0000-00000000000d' THEN
    RAISE EXCEPTION 'FAIL: 顧客(C) の get_my_sessions() が S1 以外を返した: %', v_row;
  END IF;
  IF v_row ? 'memo' THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions() の結果に memo キーが含まれている: %', v_row;
  END IF;
  IF v_row->>'trainer_id' IS DISTINCT FROM 'aaaaaaaa-8306-0000-0000-00000000000a'
     OR v_row->>'client_id' IS DISTINCT FROM 'bbbbbbbb-8306-0000-0000-00000000000b'
     OR (v_row->>'duration_minutes')::int IS DISTINCT FROM 60
     OR v_row->>'status' IS DISTINCT FROM 'scheduled'
     OR v_row->>'session_type' IS DISTINCT FROM 'RLSテスト: Cのセッション'
     OR (v_row->>'session_date')::timestamptz IS DISTINCT FROM now() + interval '1 day' THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions() の S1 の値が実テーブルと異なる: %', v_row;
  END IF;
  RAISE NOTICE 'OK: 顧客(C) の get_my_sessions() は S1 のみ 1 行（値は実テーブルどおり・memo キー無し）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): 他人の顧客 D の get_my_sessions() に C の S1 は出ない
--   p_ids で S1 を名指ししても本人条件（client_id = auth.uid()）と AND になるため 0 行
-- -----------------------------------------------------------------------------
\echo '--- case c: 他人の顧客(D) の get_my_sessions() に C の S1 が出ないこと'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-8306-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-8306-0000-0000-00000000000c';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_my_sessions()
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人の顧客(D) の get_my_sessions() に C の S1 が % 行出ている（期待 0 行）', cnt;
  END IF;

  SELECT count(*) INTO cnt
  FROM public.get_my_sessions(p_ids => ARRAY['dddddddd-8306-0000-0000-00000000000d']::uuid[]);
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 他人の顧客(D) が p_ids で C の S1 を % 行取得できた（期待 0 行）', cnt;
  END IF;

  -- 自分のセッション S2 は返ること（関数が過剰に絞っていないことの確認）
  SELECT count(*) INTO cnt FROM public.get_my_sessions();
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 他人の顧客(D) の get_my_sessions() が % 行（期待 1 行 = S2 のみ）', cnt;
  END IF;
  SELECT count(*) INTO cnt FROM public.get_my_sessions()
  WHERE id = 'eeeeeeee-8306-0000-0000-00000000000e';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 他人の顧客(D) の get_my_sessions() に自分の S2 が無い (cnt=%)', cnt;
  END IF;
  RAISE NOTICE 'OK: 他人の顧客(D) には C の S1 が 0 行（p_ids 名指しでも 0 行。自分の S2 のみ 1 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 担当トレーナー T はテーブル直 SELECT で S1 / S2 の 2 行・memo も読める
--   トレーナー用 SELECT には触れていないことの回帰確認。
--   T の get_my_sessions() は 0 行（T が顧客のセッションは無い）
-- -----------------------------------------------------------------------------
\echo '--- case d: 担当トレーナー(T) は S1・S2 と memo を直接読め、get_my_sessions() は 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-8306-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-8306-0000-0000-00000000000a';

DO $$
DECLARE
  cnt    int;
  v_memo text;
BEGIN
  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) のテーブル直 SELECT が % 行（期待 2 行）', cnt;
  END IF;

  SELECT memo INTO v_memo FROM public.sessions
  WHERE id = 'dddddddd-8306-0000-0000-00000000000d';
  IF v_memo IS DISTINCT FROM 'RLSテスト: Cについての内輪メモ' THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) が S1 の memo を読めない（%）', coalesce(v_memo, 'NULL');
  END IF;

  SELECT count(*) INTO cnt FROM public.get_my_sessions();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) の get_my_sessions() が % 行（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) は S1・S2 の 2 行と memo を SELECT 可（回帰なし）。get_my_sessions() は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e-1): anon（JWT クレーム無し）は get_my_sessions を実行できない
--   EXECUTE は authenticated のみ（PUBLIC / anon から REVOKE 済み）なので 42501。
--   例外ハンドラは insufficient_privilege だけを拾い、さらに SQLERRM が関数の
--   EXECUTE 拒否であることまで確認する（別の理由の 42501 を PASS にしない）。
--   テーブル直 SELECT は、sessions に anon のテーブル権限が残っている（20251230131753）ため
--   permission denied ではなく RLS の 0 行で現れる。
--   ※ トレーナー用4本は role 未指定（TO PUBLIC）で anon でも評価される。直前のケースの
--     JWT クレームが残っていると auth.uid() がトレーナーの UUID を返してトレーナー用
--     SELECT が通ってしまうため、両形式を空にしてからロールを切り替える
--     （auth.uid() は nullif(..., '') で NULL に落ちる）
-- -----------------------------------------------------------------------------
\echo '--- case e-1: anon（クレーム無し）が get_my_sessions を実行できず、テーブル直 SELECT も 0 行であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  BEGIN
    PERFORM 1 FROM public.get_my_sessions();
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が get_my_sessions を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function get_my_sessions%' THEN
        RAISE;
      END IF;
  END;

  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）のテーブル直 SELECT に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon（クレーム無し）は get_my_sessions が permission denied (42501)、テーブル直 SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e-2): anon ロール + 顧客 C の JWT クレームでも get_my_sessions を実行できない
--   (e-1) は auth.uid() が NULL の状態なので、「anon でも実行はできるが本人条件で
--   0 行になる」関数との区別は SQLSTATE でしか付かない。ここでは auth.uid() が顧客 C を
--   返す状態のまま anon で呼び、role 単位の EXECUTE 剥奪で拒否されることを直接確認する
--   （anon に EXECUTE が残っていれば、この状態では C の S1 が返ってしまう）
--   ※ トレーナー用4本は TO PUBLIC だが判定式が auth.uid() = trainer_id であり、
--     C の UUID では真にならないため、テーブル直 SELECT は 0 行のはず
-- -----------------------------------------------------------------------------
\echo '--- case e-2: anon ロール + 顧客(C) クレームでも get_my_sessions を実行できないこと'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  -- 前提確認: auth.uid() が顧客 C を返している（クレームが効いている）こと。
  -- ここが NULL だと (e-1) と同じ条件に退化してしまう
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-8306-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C の UUID）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  BEGIN
    PERFORM 1 FROM public.get_my_sessions();
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで get_my_sessions を実行できてしまった（anon の EXECUTE が剥がれていない）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function get_my_sessions%' THEN
        RAISE;
      END IF;
  END;

  SELECT count(*) INTO cnt FROM public.sessions
  WHERE id IN ('dddddddd-8306-0000-0000-00000000000d',
               'eeeeeeee-8306-0000-0000-00000000000e');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームのテーブル直 SELECT に % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon ロール + 顧客(C) クレームでも get_my_sessions は permission denied (42501)、テーブル直 SELECT は 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(f): p_from / p_before / p_ids の絞り込み
--   C のセッションを 3 件にしてから（S3 = 7日前 / S1 = 1日後 / S4 = 30日後）検証する。
--   now() はトランザクション開始時刻で固定のため、S1 の開始時刻は now() + 1 day と一致する。
--   結果は ID の集合で比較する（並び順は呼び出し側に任せる契約のため、ここでは問わない）
-- -----------------------------------------------------------------------------
\echo '--- case f: p_from / p_before / p_ids の絞り込みがそれぞれ効くこと'

INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type
) VALUES
  ('dddddddd-8306-0000-0000-0000000000d3',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'bbbbbbbb-8306-0000-0000-00000000000b',
   now() - interval '7 day', 60, 'completed', 'RLSテスト: Cの過去セッション'),
  ('dddddddd-8306-0000-0000-0000000000d4',
   'aaaaaaaa-8306-0000-0000-00000000000a',
   'bbbbbbbb-8306-0000-0000-00000000000b',
   now() + interval '30 day', 60, 'scheduled', 'RLSテスト: Cの先のセッション');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-8306-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-8306-0000-0000-00000000000b';

DO $$
DECLARE
  s1     constant uuid := 'dddddddd-8306-0000-0000-00000000000d';
  s2     constant uuid := 'eeeeeeee-8306-0000-0000-00000000000e';
  s3     constant uuid := 'dddddddd-8306-0000-0000-0000000000d3';
  s4     constant uuid := 'dddddddd-8306-0000-0000-0000000000d4';
  v_got  uuid[];
  v_want uuid[];
BEGIN
  -- (f-0) 全引数省略（NULL）は絞り込み無し = C の 3 件すべて
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions() g ORDER BY g.id);
  v_want := ARRAY(SELECT x FROM unnest(ARRAY[s1, s3, s4]) x ORDER BY x);
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-0) 引数省略の結果が % （期待 % = S1・S3・S4）', v_got, v_want;
  END IF;

  -- (f-1) p_from は「以上」: S1 の開始時刻ちょうどを渡すと S1 自身も含む
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(p_from => now() + interval '1 day') g ORDER BY g.id);
  v_want := ARRAY(SELECT x FROM unnest(ARRAY[s1, s4]) x ORDER BY x);
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-1) p_from の結果が % （期待 % = S1・S4）', v_got, v_want;
  END IF;

  -- (f-2) p_before は「未満」: S1 の開始時刻ちょうどを渡すと S1 は含まない
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(p_before => now() + interval '1 day') g ORDER BY g.id);
  v_want := ARRAY[s3];
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-2) p_before の結果が % （期待 % = S3 のみ）', v_got, v_want;
  END IF;

  -- (f-3) p_from と p_before の組み合わせは AND（[now, now + 7 day) = S1 のみ）
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(
                    p_from => now(), p_before => now() + interval '7 day') g ORDER BY g.id);
  v_want := ARRAY[s1];
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-3) p_from + p_before の結果が % （期待 % = S1 のみ）', v_got, v_want;
  END IF;

  -- (f-4) p_ids は指定 ID に限定する。他人（D）の S2 を混ぜても返らない
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(p_ids => ARRAY[s3, s4, s2]) g ORDER BY g.id);
  v_want := ARRAY(SELECT x FROM unnest(ARRAY[s3, s4]) x ORDER BY x);
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-4) p_ids の結果が % （期待 % = S3・S4。他人の S2 は返らない）', v_got, v_want;
  END IF;

  -- (f-5) p_ids と日付の組み合わせも AND（S3・S4 のうち now 以降 = S4 のみ）
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(p_from => now(), p_ids => ARRAY[s3, s4]) g ORDER BY g.id);
  v_want := ARRAY[s4];
  IF v_got IS DISTINCT FROM v_want THEN
    RAISE EXCEPTION 'FAIL: (f-5) p_ids + p_from の結果が % （期待 % = S4 のみ）', v_got, v_want;
  END IF;

  -- (f-6) p_ids の空配列は NULL（絞り込み無し）とは別扱いで 0 行
  v_got  := ARRAY(SELECT g.id FROM public.get_my_sessions(p_ids => ARRAY[]::uuid[]) g ORDER BY g.id);
  IF cardinality(v_got) <> 0 THEN
    RAISE EXCEPTION 'FAIL: (f-6) p_ids に空配列を渡して % が返った（期待 0 行）', v_got;
  END IF;

  RAISE NOTICE 'OK: p_from（以上）/ p_before（未満）/ p_ids の絞り込みと組み合わせ（AND）が期待どおり';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(g): 関数・ポリシーのメタデータ検証（postgres として実行）
--   - 戻り列（RETURNS TABLE の列 = proargmodes が 't'）が許可リストどおりで memo が無い
--   - 引数の契約（名前・型・既定値の数）。Mobile は PostgREST の body キーで引数名を使う
--   - SECURITY DEFINER かつ search_path が空文字に固定されている
--   - EXECUTE: anon 不可（PUBLIC への付与も無い）/ authenticated 可
--   - sessions_client_select が無く、トレーナー用4本は残っている
--     （SELECT 系ポリシーはトレーナー用1本だけ = 顧客に直読みを開くポリシーが無い）
-- -----------------------------------------------------------------------------
\echo '--- case g: get_my_sessions の戻り列・SECURITY DEFINER・search_path・権限、sessions のポリシー構成'

DO $$
DECLARE
  v_fn       constant regprocedure :=
    'public.get_my_sessions(timestamptz, timestamptz, uuid[])'::regprocedure;
  v_out_cols text[];
  v_result   text;
  v_args     text;
  v_ndefault int;
  v_secdef   boolean;
  v_config   text[];
  cnt        int;
BEGIN
  SELECT array_agg(a.name ORDER BY a.ord)
    INTO v_out_cols
    FROM pg_proc p,
         unnest(p.proargnames, p.proargmodes) WITH ORDINALITY AS a(name, mode, ord)
   WHERE p.oid = v_fn
     AND a.mode = 't';

  IF 'memo' = ANY (v_out_cols) THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の戻り列に memo が含まれている（%）', v_out_cols;
  END IF;
  IF v_out_cols IS DISTINCT FROM ARRAY[
       'id', 'trainer_id', 'client_id', 'session_date', 'duration_minutes', 'status',
       'session_type', 'ticket_id', 'recurrence_group_id', 'created_at', 'updated_at'
     ] THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の戻り列が許可リストと異なる（%）', v_out_cols;
  END IF;

  -- 列の型まで含めた戻り値の契約（Mobile の SessionModel が依存する）
  v_result := pg_get_function_result(v_fn);
  IF v_result IS DISTINCT FROM
       'TABLE(id uuid, trainer_id uuid, client_id uuid, '
       'session_date timestamp with time zone, duration_minutes integer, status text, '
       'session_type text, ticket_id uuid, recurrence_group_id uuid, '
       'created_at timestamp with time zone, updated_at timestamp with time zone)' THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の戻り値の型が契約と異なる（%）', v_result;
  END IF;

  v_args := pg_get_function_identity_arguments(v_fn);
  SELECT p.pronargdefaults, p.prosecdef, p.proconfig
    INTO v_ndefault, v_secdef, v_config
    FROM pg_proc p
   WHERE p.oid = v_fn;
  IF v_args IS DISTINCT FROM
       'p_from timestamp with time zone, p_before timestamp with time zone, p_ids uuid[]'
     OR v_ndefault <> 3 THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の引数が契約と異なる（% / 既定値 % 個）', v_args, v_ndefault;
  END IF;

  IF NOT v_secdef THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions が SECURITY DEFINER になっていない';
  END IF;
  IF v_config IS NULL OR NOT ('search_path=""' = ANY (v_config)) THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の search_path が空文字に固定されていない（proconfig=%）',
      coalesce(v_config::text, 'NULL');
  END IF;

  IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: anon が get_my_sessions の EXECUTE 権限を持っている';
  END IF;
  IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: authenticated が get_my_sessions の EXECUTE 権限を持っていない';
  END IF;
  -- proacl が NULL（未変更）なら既定の PUBLIC EXECUTE が生きているため acldefault で補う
  IF EXISTS (
    SELECT 1
      FROM pg_proc p,
           aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
     WHERE p.oid = v_fn
       AND a.grantee = 0  -- 0 = PUBLIC
  ) THEN
    RAISE EXCEPTION 'FAIL: get_my_sessions の EXECUTE が PUBLIC に付与されたまま';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'sessions'
       AND policyname = 'sessions_client_select'
  ) THEN
    RAISE EXCEPTION 'FAIL: 顧客用 SELECT ポリシー sessions_client_select が残っている';
  END IF;

  SELECT count(*) INTO cnt FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'sessions'
     AND policyname IN ('Trainers can view their own sessions',
                        'Trainers can insert their own sessions',
                        'Trainers can update their own sessions',
                        'Trainers can delete their own sessions');
  IF cnt <> 4 THEN
    RAISE EXCEPTION 'FAIL: トレーナー用ポリシーが % 本（期待 4 本）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'sessions'
     AND cmd IN ('SELECT', 'ALL');
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: sessions の SELECT 系ポリシーが % 本（期待 1 本 = トレーナー用のみ）', cnt;
  END IF;

  RAISE NOTICE 'OK: 戻り列は許可リスト（memo 無し）/ SECURITY DEFINER / search_path="" / EXECUTE は authenticated のみ / sessions_client_select 撤去・トレーナー用4本は維持';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): 顧客 C は INSERT / UPDATE / DELETE できない
--   書込は既存のトレーナー用ポリシーしか無い（顧客用には一度も書込権を与えていない）
-- -----------------------------------------------------------------------------
\echo '--- case h-1: 顧客(C) の INSERT が拒否されること'

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

\echo '--- case h-2: 顧客(C) の UPDATE が 0 行であること'

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

\echo '--- case h-3: 顧客(C) の DELETE が 0 行であること'

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
