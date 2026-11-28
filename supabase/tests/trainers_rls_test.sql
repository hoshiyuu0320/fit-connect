-- =============================================================================
-- trainers の読み取りの RLS・権限テスト（20261128000000_trainers_select_scope.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト。
--
-- 流し方（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   bash supabase/tests/run_all.sh supabase/tests/trainers_rls_test.sql
--   psql で直接流すなら:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/trainers_rls_test.sql
--   ※ コンテナ名は環境に合わせて読み替える
--
-- - すべて通ったときだけ、最後の行に「ALL TRAINERS RLS TESTS PASSED」が出る
-- - 期待と違えば RAISE EXCEPTION 'FAIL: ...' で止まる（何がどう違ったかを書く）
-- - BEGIN ... ROLLBACK の中で動く。DB には何も残らない
-- - 見える行は、その役に見えてよい行だけかで確かめる（Seed の行があっても見えてはいけない）
--
-- 確かめること:
--   1. 静的な確認（カタログ）
--     1a. SELECT に効くポリシー（FOR SELECT / FOR ALL）は次の 3 本だけ。条件の無い
--         USING (true) は trainers_select_anon だけ
--           trainers_select_anon           TO anon（読める列は 1b の 3 列）
--           trainers_select_own            TO authenticated（自分の行）
--           trainers_select_client_trainer TO authenticated（担当トレーナーの行）
--     1b. anon が SELECT できる列は id・name・profile_image_url だけ。列は pg_attribute から
--         全部取るので、列を足すと自動でこの確認の対象になる
--     1c. anon はテーブル単位の権限を 1 つも持たない
--     1d. authenticated はテーブル単位の SELECT を持つ（Web と Mobile は select * で読む）
--   2. データの用意（postgres）
--     トレーナー A と顧客 CA（clients.client_id = CA、trainer_id = A）、トレーナー B と顧客 CB、
--     auth.users にだけいるユーザー U（trainers・clients の行が無い）
--   3. 振る舞いの確認
--     3a. anon（クレーム無し）: A を id で引く（id, name, profile_image_url）と 1 行。
--         ほかの列は、どれを選んでも 42501。select * も 42501
--     3b. A: select * で見えるのは A の行だけ。B は見えない
--     3c. CA: select * で見えるのは A の行だけ。A の subscription_plan・trial_ends_at を読める。
--         B は見えない
--     3d. CB: select * で見えるのは B の行だけ
--     3e. U: trainers の行は 1 行も見えない
--     3f. A は自分の name を UPDATE できる（1 行）。B が A の行を UPDATE しても 0 行
--
-- 扱わないこと:
--   - messages_guard_insert が自分の trainers の行を見られること（column_write_guards_test.sql の
--     トレーナーからの送信。f2 など）
--   - 書き込みの列単位の GRANT（20260712000000 §4）。全部の表の UPDATE・DELETE は rls_baseline_test.sql
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- ヘルパー（pg_temp に作る。ROLLBACK で消える）
-- -----------------------------------------------------------------------------
\echo '--- setup: ヘルパー作成'

-- 試験用の id（7a1e0000-1128-4000-8000- で始まる。未知の名前は NULL）
CREATE FUNCTION pg_temp.tr_id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('7a1e0000-1128-4000-8000-' || CASE p_name
    WHEN 'A'  THEN '0000000000a1'  -- トレーナー A
    WHEN 'B'  THEN '0000000000b1'  -- トレーナー B
    WHEN 'CA' THEN '0000000000c1'  -- A の顧客 CA
    WHEN 'CB' THEN '0000000000c2'  -- B の顧客 CB
    WHEN 'U'  THEN '0000000000d1'  -- auth.users にだけいるユーザー U
  END)::uuid
$$;

-- id の並びを、試験用の名前（A / B / CA / CB / U）で書く（ほかの id はそのまま）。FAIL の文面用
CREATE FUNCTION pg_temp.tr_labels(p_ids uuid[]) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(string_agg(coalesce((SELECT n FROM unnest(ARRAY['A', 'B', 'CA', 'CB', 'U']) AS n
                                        WHERE pg_temp.tr_id(n) = x.i), x.i::text),
                             ', ' ORDER BY x.o),
                  'なし')
    FROM unnest(p_ids) WITH ORDINALITY AS x(i, o)
$$;

-- 呼び出し元を切り替える（rls_baseline_test.sql の rb_as と同じ方法。SET LOCAL なので、
-- 次の切り替えかトランザクションの終わりまで有効）
--   'postgres' : RESET ROLE（クレーム無し。RLS を通らない）
--   'anon'     : クレーム無しの anon（公開キーだけの要求 = ログイン前の Mobile）
--   'A' / 'B' / 'CA' / 'CB' / 'U' : その人の authenticated（JWT のクレームに sub を入れる）
-- 切り替えたあと、current_user と auth.uid() を確かめる（前提が崩れたら止める）
CREATE FUNCTION pg_temp.tr_as(p_who text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_role text;
  v_sub  uuid;
BEGIN
  RESET ROLE;
  CASE p_who
    WHEN 'postgres' THEN
      v_role := NULL;
    WHEN 'anon' THEN
      v_role := 'anon';
    WHEN 'A', 'B', 'CA', 'CB', 'U' THEN
      v_role := 'authenticated';
      v_sub  := pg_temp.tr_id(p_who);
    ELSE
      RAISE EXCEPTION 'テストの誤り: 未知の呼び出し元 %', p_who;
  END CASE;

  PERFORM set_config('request.jwt.claims',
                     CASE WHEN v_sub IS NULL THEN ''
                          ELSE json_build_object('sub', v_sub, 'role', 'authenticated')::text END,
                     true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(v_sub::text, ''), true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  IF v_role IS NOT NULL THEN
    EXECUTE format('SET LOCAL ROLE %I', v_role);
  END IF;

  IF current_user IS DISTINCT FROM coalesce(v_role, session_user) THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — % に切り替えたのに current_user が %', p_who, current_user;
  END IF;
  IF auth.uid() IS DISTINCT FROM v_sub THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — % に切り替えたのに auth.uid() が %', p_who,
      coalesce(auth.uid()::text, 'NULL');
  END IF;
END
$fn$;

-- 今の呼び出し元に見える trainers の行の id（select * で読む = Web の設定画面・Mobile と同じ形）
CREATE FUNCTION pg_temp.tr_visible_ids() RETURNS uuid[] LANGUAGE plpgsql AS $fn$
DECLARE
  v_ids uuid[];
BEGIN
  EXECUTE 'SELECT coalesce(array_agg(t.id ORDER BY t.id), ''{}'') FROM (SELECT * FROM public.trainers) t'
     INTO v_ids;
  RETURN v_ids;
END
$fn$;

-- =============================================================================
-- 1. 静的な確認（カタログ。postgres で見る）
-- =============================================================================
\echo '--- 1. 静的な確認: ポリシー・anon の列とテーブルの権限・authenticated の SELECT'

DO $$
DECLARE
  v_actual   text;
  v_expected text := 'trainers_select_anon（FOR SELECT TO anon / PERMISSIVE）, '
                  || 'trainers_select_client_trainer（FOR SELECT TO authenticated / PERMISSIVE）, '
                  || 'trainers_select_own（FOR SELECT TO authenticated / PERMISSIVE）';
  v_open     text;
  v_bad      text;
  v_ncols    bigint;
  v_problems text[] := '{}';  -- 見つけた問題（全部を確かめてから、まとめて FAIL にする）
BEGIN
  -- 1a. SELECT に効くポリシー（FOR SELECT / FOR ALL）は 3 本だけ
  SELECT string_agg(format('%s（FOR %s TO %s / %s）', p.policyname, p.cmd,
                           array_to_string(p.roles, ', '), p.permissive),
                    ', ' ORDER BY p.policyname)
    INTO v_actual
    FROM pg_policies p
   WHERE p.schemaname = 'public' AND p.tablename = 'trainers' AND p.cmd IN ('SELECT', 'ALL');
  IF v_actual IS DISTINCT FROM v_expected THEN
    v_problems := v_problems || format(
      E'[1a] SELECT に効くポリシー（FOR SELECT / FOR ALL）が想定と違う\n'
      '      実際: %s\n'
      '      期待: %s\n'
      '      読める範囲を変えるなら、20261128000000 のヘッダーの決まりとこのテストも合わせて直す',
      coalesce(v_actual, 'なし'), v_expected);
  END IF;

  -- 1a. 条件の無い USING (true) は trainers_select_anon だけ（anon は 1b の 3 列しか読めない）
  SELECT string_agg(p.policyname, ', ' ORDER BY p.policyname)
    INTO v_open
    FROM pg_policies p
   WHERE p.schemaname = 'public' AND p.tablename = 'trainers' AND p.cmd IN ('SELECT', 'ALL')
     AND p.qual = 'true';
  IF v_open IS DISTINCT FROM 'trainers_select_anon' THEN
    v_problems := v_problems || format(
      '[1a] 条件の無い（USING (true)）SELECT のポリシーが trainers_select_anon だけではない（%s）。'
      'authenticated に見せるのは、自分の行と担当トレーナーの行だけ', coalesce(v_open, 'なし'));
  END IF;

  -- 1b. anon が SELECT できる列は id・name・profile_image_url だけ（全部の列を pg_attribute から取る）
  SELECT count(*),
         string_agg(format('%s（%s）', a.attname,
                           CASE WHEN has_column_privilege('anon', 'public.trainers', a.attname, 'SELECT')
                                THEN 'anon が読める' ELSE 'anon が読めない' END),
                    ', ' ORDER BY a.attnum)
           FILTER (WHERE has_column_privilege('anon', 'public.trainers', a.attname, 'SELECT')
                         <> (a.attname IN ('id', 'name', 'profile_image_url')))
    INTO v_ncols, v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.trainers'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_bad IS NOT NULL THEN
    v_problems := v_problems || format(
      '[1b] anon の列の SELECT が想定と違う: %s。anon が読めるのは、登録で使う id・name・profile_image_url だけ。'
      '列を足したときも、anon に見せるとわざわざ決めた列でなければ、anon からは読めないままにする'
      '（見せると決めたら、GRANT とこのテストの 3 列を合わせて直す）', v_bad);
  END IF;

  -- 1c. anon はテーブル単位の権限を持たない
  SELECT string_agg(u.priv, ', ' ORDER BY u.ord)
    INTO v_bad
    FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'])
         WITH ORDINALITY AS u(priv, ord)
   WHERE has_table_privilege('anon', 'public.trainers', u.priv);
  IF v_bad IS NOT NULL THEN
    v_problems := v_problems || format(
      '[1c] anon にテーブル単位の権限がある: %s（anon が持つのは 3 列の SELECT だけのはず）', v_bad);
  END IF;

  -- 1d. authenticated はテーブル単位の SELECT を持つ
  IF NOT has_table_privilege('authenticated', 'public.trainers', 'SELECT') THEN
    v_problems := v_problems
      || '[1d] authenticated にテーブル単位の SELECT が無い（Web と Mobile の select * が 42501 で失敗する）'::text;
  END IF;

  IF cardinality(v_problems) > 0 THEN
    RAISE EXCEPTION 'FAIL: trainers の静的な確認で % 件の問題%', cardinality(v_problems),
      E'\n  - ' || array_to_string(v_problems, E'\n  - ');
  END IF;

  RAISE NOTICE 'OK: [1a] SELECT に効くポリシーは 3 本（%）。USING (true) は trainers_select_anon だけ', v_actual;
  RAISE NOTICE 'OK: [1b] trainers の % 列のうち、anon が読めるのは id・name・profile_image_url だけ', v_ncols;
  RAISE NOTICE 'OK: [1c] anon は trainers のテーブル単位の権限を持たない';
  RAISE NOTICE 'OK: [1d] authenticated は trainers のテーブル単位の SELECT を持つ';
END $$;

-- =============================================================================
-- 2. データの用意（postgres として投入。RLS を通らない）
-- =============================================================================
\echo '--- 2. データの用意: トレーナー A / B・顧客 CA / CB・ユーザー U'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT pg_temp.tr_id(n), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'trainers-rls-' || lower(n) || '@example.com', 'x', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['A', 'B', 'CA', 'CB', 'U']) AS n;

-- 全部の列に値を入れておく（読めた列が NULL で見分けられない、とならないように）
INSERT INTO public.trainers (id, name, email, profile_image_url, is_online, last_seen_at,
                             subscription_plan, fcm_token, trial_ends_at) VALUES
  (pg_temp.tr_id('A'), 'trainersテスト トレーナーA', 'trainers-rls-a@example.com', 'trainers-rls/a.png',
   true, now(), 'pro', 'trainers-rls-fcm-a', now() + interval '7 days'),
  (pg_temp.tr_id('B'), 'trainersテスト トレーナーB', 'trainers-rls-b@example.com', 'trainers-rls/b.png',
   false, now() - interval '1 hour', 'free', 'trainers-rls-fcm-b', now() + interval '14 days');

INSERT INTO public.clients (client_id, name, trainer_id, email) VALUES
  (pg_temp.tr_id('CA'), 'trainersテスト 顧客CA', pg_temp.tr_id('A'), 'trainers-rls-ca@example.com'),
  (pg_temp.tr_id('CB'), 'trainersテスト 顧客CB', pg_temp.tr_id('B'), 'trainers-rls-cb@example.com');

-- =============================================================================
-- 3. 振る舞いの確認
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 3a. anon（クレーム無し = ログイン前の Mobile）
--   登録の読み取り（registration_provider.dart の fetchTrainerInfo と同じ 3 列を id で）は 1 行。
--   ほかの列は 1 列ずつ選んで、どれも 42501。select * も 42501
-- -----------------------------------------------------------------------------
\echo '--- 3a. anon: 登録の読み取り（3 列を id で）は 1 行。ほかの列と select * は 42501'

DO $$
DECLARE
  v_n      bigint;
  v_name   text;
  v_col    name;
  v_val    text;
  v_row    record;
  v_read   text[] := '{}';
  v_denied text[] := '{}';
BEGIN
  PERFORM pg_temp.tr_as('anon');

  SELECT count(*), min(x.name) INTO v_n, v_name
    FROM (SELECT id, name, profile_image_url FROM public.trainers WHERE id = pg_temp.tr_id('A')) x;
  IF v_n <> 1 OR v_name IS DISTINCT FROM 'trainersテスト トレーナーA' THEN
    RAISE EXCEPTION 'FAIL: [3a] anon が A を id で引くと % 行（名前 %）。期待 1 行（A の名前）。'
                    'Mobile の登録でトレーナーが見つからなくなる', v_n, coalesce(v_name, 'NULL');
  END IF;

  -- 3 列のほかの列（pg_attribute から全部取る。列を足すと自動で対象になる）
  FOR v_col IN
    SELECT a.attname
      FROM pg_attribute a
     WHERE a.attrelid = 'public.trainers'::regclass AND a.attnum > 0 AND NOT a.attisdropped
       AND a.attname NOT IN ('id', 'name', 'profile_image_url')
     ORDER BY a.attnum
  LOOP
    BEGIN
      EXECUTE format('SELECT %I::text FROM public.trainers WHERE id = $1', v_col)
         INTO v_val USING pg_temp.tr_id('A');
      v_read := v_read || v_col::text;
    EXCEPTION
      WHEN insufficient_privilege THEN
        IF SQLERRM NOT LIKE 'permission denied for table trainers%' THEN RAISE; END IF;
        v_denied := v_denied || v_col::text;
    END;
  END LOOP;
  IF cardinality(v_read) > 0 THEN
    RAISE EXCEPTION 'FAIL: [3a] anon が trainers の % を読めた（anon が読めるのは id・name・profile_image_url だけ。'
                    '足した列も、anon に見せると決めたのでなければ読めないままにする）', array_to_string(v_read, ', ');
  END IF;
  IF cardinality(v_denied) = 0 THEN
    RAISE EXCEPTION 'テストの誤り: [3a] 確かめる列が 1 つも無い';
  END IF;

  BEGIN
    EXECUTE 'SELECT * FROM public.trainers WHERE id = $1' INTO v_row USING pg_temp.tr_id('A');
    RAISE EXCEPTION 'FAIL: [3a] anon の select * が通った（anon には 3 列のほかを読ませない）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for table trainers%' THEN RAISE; END IF;
  END;

  PERFORM pg_temp.tr_as('postgres');
  RAISE NOTICE 'OK: [3a] anon は A を 3 列で引ける（1 行）。ほかの % 列（%）と select * は permission denied (42501)',
    cardinality(v_denied), array_to_string(v_denied, ', ');
END $$;

-- -----------------------------------------------------------------------------
-- 3b. トレーナー A: 見えるのは自分の行だけ（Web の select name / select * と同じ）
-- -----------------------------------------------------------------------------
\echo '--- 3b. トレーナー A: select * で見えるのは A の行だけ'

DO $$
DECLARE
  v_ids uuid[];
  v_n   bigint;
BEGIN
  PERFORM pg_temp.tr_as('A');

  v_ids := pg_temp.tr_visible_ids();
  IF v_ids IS DISTINCT FROM ARRAY[pg_temp.tr_id('A')] THEN
    RAISE EXCEPTION 'FAIL: [3b] A（トレーナー）の select * で見える行が %（期待 A の行だけ）', pg_temp.tr_labels(v_ids);
  END IF;

  SELECT count(*) INTO v_n FROM public.trainers WHERE id = pg_temp.tr_id('B');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: [3b] A に B の行が % 行見える（期待 0 行）', v_n;
  END IF;

  PERFORM pg_temp.tr_as('postgres');
  RAISE NOTICE 'OK: [3b] A の select * は自分の行だけ（1 行）。B は 0 行';
END $$;

-- -----------------------------------------------------------------------------
-- 3c. 顧客 CA: 見えるのは担当トレーナー A の行だけ。全部の列を読める
--   （Mobile は担当トレーナーを select * で読む。古い版は subscription_plan・trial_ends_at も読む）
-- -----------------------------------------------------------------------------
\echo '--- 3c. 顧客 CA: select * で見えるのは A の行だけ。A の subscription_plan・trial_ends_at を読める'

DO $$
DECLARE
  v_ids   uuid[];
  v_n     bigint;
  v_plan  text;
  v_trial timestamptz;
BEGIN
  PERFORM pg_temp.tr_as('CA');

  v_ids := pg_temp.tr_visible_ids();
  IF v_ids IS DISTINCT FROM ARRAY[pg_temp.tr_id('A')] THEN
    RAISE EXCEPTION 'FAIL: [3c] CA（A の顧客）の select * で見える行が %（期待 担当トレーナー A の行だけ）',
      pg_temp.tr_labels(v_ids);
  END IF;

  SELECT count(*), min(x.subscription_plan), min(x.trial_ends_at) INTO v_n, v_plan, v_trial
    FROM (SELECT subscription_plan, trial_ends_at FROM public.trainers WHERE id = pg_temp.tr_id('A')) x;
  IF v_n <> 1 OR v_plan IS DISTINCT FROM 'pro' OR v_trial IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'FAIL: [3c] CA が A の subscription_plan・trial_ends_at を読むと % 行（%, %）。'
                    '期待 1 行（pro, %）', v_n, coalesce(v_plan, 'NULL'), coalesce(v_trial::text, 'NULL'),
      now() + interval '7 days';
  END IF;

  SELECT count(*) INTO v_n FROM public.trainers WHERE id = pg_temp.tr_id('B');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: [3c] CA に B（担当ではないトレーナー）の行が % 行見える（期待 0 行）', v_n;
  END IF;

  PERFORM pg_temp.tr_as('postgres');
  RAISE NOTICE 'OK: [3c] CA の select * は担当トレーナー A の行だけ（1 行）。subscription_plan・trial_ends_at を読める。B は 0 行';
END $$;

-- -----------------------------------------------------------------------------
-- 3d. 顧客 CB: 見えるのは担当トレーナー B の行だけ
-- -----------------------------------------------------------------------------
\echo '--- 3d. 顧客 CB: select * で見えるのは B の行だけ'

DO $$
DECLARE
  v_ids uuid[];
BEGIN
  PERFORM pg_temp.tr_as('CB');

  v_ids := pg_temp.tr_visible_ids();
  IF v_ids IS DISTINCT FROM ARRAY[pg_temp.tr_id('B')] THEN
    RAISE EXCEPTION 'FAIL: [3d] CB（B の顧客）の select * で見える行が %（期待 担当トレーナー B の行だけ）',
      pg_temp.tr_labels(v_ids);
  END IF;

  PERFORM pg_temp.tr_as('postgres');
  RAISE NOTICE 'OK: [3d] CB の select * は担当トレーナー B の行だけ（1 行）';
END $$;

-- -----------------------------------------------------------------------------
-- 3e. ユーザー U（ログイン済み。trainers・clients の行が無い）: 1 行も見えない
--   2026-08-29 より前の版の Mobile は、ログインしたまま（clients の行が無いまま）登録の
--   読み取りをすることがあった。その場合は、トレーナーが見つからなくなる（この変更で
--   起きる違いはこの場合だけ。ログイン前の anon の読み取りは 3a のとおり変わらない）
-- -----------------------------------------------------------------------------
\echo '--- 3e. ユーザー U: trainers の行は 1 行も見えない'

DO $$
DECLARE
  v_ids uuid[];
  v_n   bigint;
BEGIN
  PERFORM pg_temp.tr_as('U');

  v_ids := pg_temp.tr_visible_ids();
  IF cardinality(v_ids) <> 0 THEN
    RAISE EXCEPTION 'FAIL: [3e] U（trainers・clients の行が無い）に見える行が %（期待 0 行）', pg_temp.tr_labels(v_ids);
  END IF;

  -- 登録の読み取りと同じ形でも 0 行
  SELECT count(*) INTO v_n
    FROM (SELECT id, name, profile_image_url FROM public.trainers WHERE id = pg_temp.tr_id('A')) x;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: [3e] U が A を id で引くと % 行（期待 0 行）', v_n;
  END IF;

  PERFORM pg_temp.tr_as('postgres');
  RAISE NOTICE 'OK: [3e] U には trainers の行が 1 行も見えない（A を id で引いても 0 行）';
END $$;

-- -----------------------------------------------------------------------------
-- 3f. UPDATE: A は自分の name を更新できる（1 行）。B が A の行を更新しても 0 行
--   （書き込みのポリシー trainers_update_own と列単位の GRANT は変えていない。読み取りの
--     ポリシーを絞っても、自分の行の更新が通ることを確かめる）
-- -----------------------------------------------------------------------------
\echo '--- 3f. UPDATE: A は自分の name を更新できる。B の A の行への UPDATE は 0 行'

DO $$
DECLARE
  v_n    bigint;
  v_name text;
BEGIN
  PERFORM pg_temp.tr_as('A');
  UPDATE public.trainers SET name = 'trainersテスト トレーナーA（A が更新）' WHERE id = pg_temp.tr_id('A');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'FAIL: [3f] A の自分の name の UPDATE が % 行（期待 1 行）', v_n;
  END IF;

  PERFORM pg_temp.tr_as('B');
  UPDATE public.trainers SET name = 'trainersテスト（B が書き換え）' WHERE id = pg_temp.tr_id('A');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: [3f] B が A の行を UPDATE できた（% 行。期待 0 行）', v_n;
  END IF;

  PERFORM pg_temp.tr_as('postgres');
  SELECT t.name INTO v_name FROM public.trainers t WHERE t.id = pg_temp.tr_id('A');
  IF v_name IS DISTINCT FROM 'trainersテスト トレーナーA（A が更新）' THEN
    RAISE EXCEPTION 'FAIL: [3f] A の name が %（期待 A が更新した値）', coalesce(v_name, 'NULL');
  END IF;
  RAISE NOTICE 'OK: [3f] A は自分の name を更新できる（1 行）。B の A の行への UPDATE は 0 行で、A の値のまま';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL TRAINERS RLS TESTS PASSED'
