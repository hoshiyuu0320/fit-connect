-- =============================================================================
-- public の全部の表の RLS とアクセスの可否 ベースラインテスト（タスク 5.4）
--
-- 目的: 次の事故を CI で止める。
--   - anon に表を見せてしまう（anon 全開放事故の再発）
--   - RLS の無い表を足してしまう
--   - 誰でも通すポリシー（USING (true) など）を足してしまう
-- 表の一覧は pg_class から取る。表を足すと、自動でこのテストの対象になる。
--
-- 流し方（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/rls_baseline_test.sql
--   ※ コンテナ名は環境に合わせて読み替える
--
-- - すべて通ったときだけ、最後の行に「ALL RLS BASELINE TESTS PASSED」が出る
-- - 期待と違えば RAISE EXCEPTION 'FAIL: ...' で止まる（何がどう違ったかを書く）
-- - BEGIN ... ROLLBACK の中で動く。DB には何も残らない
-- - 流している間（1 秒ほど）は、全部の表に一時的なトリガーがあり、他の接続の書き込みは待たされる
-- - messages への INSERT で call_parse_message_tags が動く。Vault が空なら外へ送らない
--   （WARNING だけ出る）。登録済みでも pg_net のキューは ROLLBACK で消える。COMMIT にしないこと
--
-- 確かめること:
--   1. 静的な確認（カタログ）
--     1a. public の表（relkind r / p）は、すべて RLS が有効
--     1b. public の view は security_invoker = true。materialized view は置かない
--         （どちらも、そうでなければ RLS を通らずに読める）
--     1c. 条件の無い PERMISSIVE ポリシー（USING か WITH CHECK が true）で、役に public・anon・
--         authenticated（と、anon・authenticated が属する役）を含むものは、許可リストにあるものだけ
--   2. データの用意と網羅の確認（postgres）
--     トレーナー A と顧客 CA、トレーナー B と顧客 CB を作る。全部の表に A / CA の行を入れる
--     （システム用の表はその行）。このテストが入れた守る行が無い表があれば FAIL
--     （前からある行（Seed など）では数えない）
--   3. 振る舞いの確認（anon（JWT のクレーム無し）/ B / CB のそれぞれで、全部の表について）
--     3a. SELECT: 守る行が 1 行も見えない（権限エラー 42501 も可。ほかのエラーは FAIL）。
--         見えてよい表は許可リストに書く
--     3b. UPDATE・DELETE: 守る行に届かない。権限エラー・ガードのトリガーの例外・0 行は、
--         どれも「書けなかった」とする
--     3c. 終わったあと、全部の表の行が、試す前の写し（to_jsonb）と同じ
--   守る行 = B / CB の id をどの列にも含まない行（A / CA の行・システム用の表の行・
--   テストの前から DB にあった行）。B / CB 自身の行は、見えても書けてもよい
--
-- UPDATE・DELETE の試し方:
--   - 列を読まない形（UPDATE t SET 列 = NULL / DELETE FROM t。WHERE も RETURNING も無し）で、
--     全行に試す。列を読むと SELECT のポリシーも重なり、UPDATE / DELETE のポリシーの穴が隠れる
--   - 試す前に、全部の表へ一時的なトリガーを 2 本作る（トリガーは名前の順に動く）
--       先頭の BEFORE UPDATE（"!rls_baseline_same_value"）: NEW を OLD に戻す = 同じ値での上書き
--       最後の BEFORE UPDATE / DELETE（"~rls_baseline_probe"）: 届いた行を記録し、NULL を返す
--     既存のガードのトリガーは、その間で普段どおりに動く。行は変わらないし、消えない
--   - 記録に守る行があれば FAIL。同じ値の上書きは写しの比較では見分けられず、本当に消すと
--     FK の参照が穴を隠すため、この形にした
--   - 試す前に、トリガーの並びと、postgres（RLS もガードも通らない）では全行に届くことを確かめる
--   - 1 回の試みのエラーで止まらないよう、試みごとに PL/pgSQL の EXCEPTION 節（SAVEPOINT）で区切る
--
-- 扱わないこと（表ごとのテストで確かめる）:
--   - INSERT（表ごとに必要な値が違う）
--   - 持ち主ができること（自分の行を読める・書けるか）
--   - 顧客とトレーナーの間の細かい権限、列単位の制限、クレーム付きの anon
--   - TRUNCATE（RLS が効かないが、PostgREST からは呼べない）
--
-- 表を足したときの決まり:
--   - 「2. データの用意」に、その表の A / CA の行を足す（足さないと網羅の確認で FAIL）
--   - anon や他人に見せる表なら、理由を書いて「見えてよい表の許可リスト」に足す
--   - 誰でも通すポリシー（USING (true) / WITH CHECK (true)）を足すときも、
--     理由を書いて「条件の無いポリシーの許可リスト」に足す
--   - view は WITH (security_invoker = true) で作る
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- ヘルパー（pg_temp に作る。ROLLBACK で消える）
-- -----------------------------------------------------------------------------
\echo '--- setup: ヘルパー作成'

-- 試験用の id（b45e0000-5400-4000-8000- で始まる。未知の名前は NULL）
CREATE FUNCTION pg_temp.rb_id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('b45e0000-5400-4000-8000-' || CASE p_name
    WHEN 'A'        THEN '00000000a001'  -- トレーナー A（守る側）
    WHEN 'B'        THEN '00000000a002'  -- トレーナー B（他人のトレーナー）
    WHEN 'CA'       THEN '00000000c001'  -- A の顧客 CA（守る側）
    WHEN 'CB'       THEN '00000000c002'  -- B の顧客 CB（他人の顧客）
    WHEN 'plan'     THEN '00000000b001'  -- A のプラン
    WHEN 'assign'   THEN '00000000b002'  -- A → CA の割り当て
    WHEN 'ticket'   THEN '00000000b003'  -- CA のチケット
    WHEN 'template' THEN '00000000b004'  -- A のチケットのひな形
    WHEN 'subscr'   THEN '00000000b005'  -- CA の定期チケット
    WHEN 'session'  THEN '00000000b006'  -- A ↔ CA のセッション
    WHEN 'msg_ca'   THEN '00000000b007'  -- CA → A のメッセージ
    WHEN 'msg_a'    THEN '00000000b008'  -- A → CA のメッセージ（msg_ca への返信）
  END)::uuid
$$;

-- 呼び出し元を切り替える（SET LOCAL なので、次の切り替えかトランザクションの終わりまで有効）
--   'postgres' : RESET ROLE（クレーム無し。RLS を通らない）
--   'anon'     : クレーム無しの anon（公開キーだけの要求）
--   'B' / 'CB' : その人の authenticated（JWT のクレームに sub を入れる）
-- 切り替えたあと、current_user と auth.uid() を確かめる（前提が崩れたら止める）
CREATE FUNCTION pg_temp.rb_as(p_who text) RETURNS void LANGUAGE plpgsql AS $fn$
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
    WHEN 'B', 'CB' THEN
      v_role := 'authenticated';
      v_sub  := pg_temp.rb_id(p_who);
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

-- public の表の一覧（pg_class から取る。表の名前は決め打ちしない）
CREATE FUNCTION pg_temp.rb_tables() RETURNS SETOF regclass LANGUAGE sql STABLE AS $$
  SELECT c.oid::regclass
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
   ORDER BY c.relname
$$;

-- 全部の表の全行の写し（postgres で取る。RLS を通らない）
--   phase: before（データの用意の前）/ after（用意の後）/ final（振る舞いの確認の後）
CREATE TEMP TABLE rb_rows (
  phase    text     NOT NULL,
  tbl      regclass NOT NULL,
  row_data jsonb    NOT NULL
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.rb_take_snapshot(p_phase text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  t regclass;
BEGIN
  IF current_user IS DISTINCT FROM session_user THEN
    RAISE EXCEPTION 'テストの誤り: 写しは postgres で取る（current_user=%）', current_user;
  END IF;
  DELETE FROM pg_temp.rb_rows WHERE phase = p_phase;
  FOR t IN SELECT * FROM pg_temp.rb_tables() LOOP
    EXECUTE format('INSERT INTO pg_temp.rb_rows (phase, tbl, row_data) SELECT %L, %L::regclass, to_jsonb(x) FROM %s x',
                   p_phase, t, t);
  END LOOP;
END
$fn$;

-- 守る行か: B / CB の id を、どの列の値にも含まない行
CREATE FUNCTION pg_temp.rb_is_protected(p_row jsonb) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM jsonb_each_text(p_row) e
     WHERE e.value IN (pg_temp.rb_id('B')::text, pg_temp.rb_id('CB')::text))
$$;

-- 見つけた問題（section ごとにまとめて FAIL にする）
CREATE TEMP TABLE rb_problems (
  id      bigint GENERATED ALWAYS AS IDENTITY,
  section text NOT NULL,
  detail  text NOT NULL
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.rb_problem_list(p_section text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT E'\n' || string_agg('  - ' || detail, E'\n' ORDER BY id)
    FROM pg_temp.rb_problems
   WHERE section = p_section
$$;

-- -----------------------------------------------------------------------------
-- 許可リスト（どちらも reason が空の行は足せない）
-- -----------------------------------------------------------------------------
\echo '--- setup: 許可リスト'

-- (1) 条件の無いポリシーの許可リスト（1c）。表・ポリシー名・コマンドまで一致したものだけ許す
CREATE TEMP TABLE rb_open_policy_allowlist (
  tbl    text NOT NULL,
  policy text NOT NULL,
  cmd    text NOT NULL,  -- pg_policies.cmd（SELECT / INSERT / UPDATE / DELETE / ALL）
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  PRIMARY KEY (tbl, policy)
) ON COMMIT DROP;

INSERT INTO rb_open_policy_allowlist (tbl, policy, cmd, reason) VALUES
  -- trainers_select_anon（FOR SELECT TO anon USING (true)。20261128000000 で作成）
  --   Mobile の登録（QR の読み取り・招待コードの入力）で、ログイン前に、トレーナーの
  --   id・名前・画像を id で引く（registration_provider.dart の fetchTrainerInfo）。
  --   anon が読めるのは id・name・profile_image_url の 3 列だけ（列単位の GRANT）。
  --   ログイン後に見えるのは、トレーナーは自分の行、顧客は担当トレーナーの行だけ
  --   （trainers_select_own / trainers_select_client_trainer。条件付き）。
  --   詳しくは trainers_rls_test.sql。anon がトレーナー全員を一覧できるのは既知の課題で、
  --   統合判断（2026-07-10-integration-decisions.md 判断5）の招待コードの導入で扱う予定
  ('trainers', 'trainers_select_anon', 'SELECT',
   'Mobile の登録でログイン前にトレーナーを id で引く。anon が読めるのは 3 列だけ（trainers_rls_test.sql）。全員を一覧できるのは統合判断5 の課題'),
  -- app_config_select_all（FOR SELECT TO anon, authenticated USING (true)。20260829000100 で作成）
  --   Mobile が起動時（ログイン前を含む）に、強制アップデートの判定で読む
  --   （app_config_repository.dart）。中身は公開してよい設定だけ（最小バージョン・ストアの URL・
  --   文言）。書き込みのポリシーは無く、更新は service_role だけ
  ('app_config', 'app_config_select_all', 'SELECT',
   'Mobile がログイン前に強制アップデートの判定で読む。公開してよい設定だけ');

-- (2) 見えてよい表の許可リスト（3a）。守る行が見えてよい表と、見てよい役
CREATE TEMP TABLE rb_visible_allowlist (
  tbl    text NOT NULL,
  who    text NOT NULL CHECK (who IN ('anon', 'B', 'CB')),
  reason text NOT NULL CHECK (btrim(reason) <> ''),
  PRIMARY KEY (tbl, who)
) ON COMMIT DROP;

INSERT INTO rb_visible_allowlist (tbl, who, reason)
SELECT v.tbl, unnest(v.who), v.reason
  FROM (VALUES
    -- trainers_select_anon による（(1) と同じ理由）。見えるのは anon だけ（読める 3 列で行を
    -- 突き合わせる）。B には自分の行、CB には担当トレーナー B の行だけが見え、守る行は見えない
    ('trainers',   ARRAY['anon'], 'trainers_select_anon（(1) と同じ理由。anon が読めるのは 3 列だけ）'),
    -- app_config_select_all による（(1) と同じ理由）
    ('app_config', ARRAY['anon', 'B', 'CB'], 'app_config_select_all（(1) と同じ理由）')
  ) AS v(tbl, who, reason);

-- =============================================================================
-- 1. 静的な確認（カタログ）
-- =============================================================================
\echo '--- 1. 静的な確認: RLS の有効・view・条件の無いポリシー'

DO $$
DECLARE
  v_list   text;
  v_tables bigint;
  v_views  bigint;
  v_open   bigint;
BEGIN
  -- 1a. public の表（relkind r / p）は、すべて RLS が有効
  INSERT INTO pg_temp.rb_problems (section, detail)
  SELECT '1', format('[1a] %s: RLS が無効。migration で ALTER TABLE %s ENABLE ROW LEVEL SECURITY を',
                     c.oid::regclass, c.oid::regclass)
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relrowsecurity
   ORDER BY c.relname;

  -- 1b. public の view は security_invoker = true。materialized view は置かない
  --     （security_invoker が無い view は持ち主の権限で読むため、RLS を素通りする。
  --       materialized view は security_invoker を持てず、読むときに RLS が掛からない）
  INSERT INTO pg_temp.rb_problems (section, detail)
  SELECT '1', CASE c.relkind
           WHEN 'm' THEN format('[1b] %s: materialized view は RLS を通らずに読める。public に置かない', c.oid::regclass)
           ELSE format('[1b] %s: view に security_invoker = true が無い（持ち主の権限で読むため RLS を素通りする）。'
                       'WITH (security_invoker = true) で作る', c.oid::regclass)
         END
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')
     AND (c.relkind = 'm'
          OR NOT coalesce((SELECT o.option_value::boolean
                             FROM pg_options_to_table(c.reloptions) o
                            WHERE o.option_name = 'security_invoker'), false))
   ORDER BY c.relname;

  -- 1c. 条件の無い PERMISSIVE ポリシー（USING か WITH CHECK が true）で、役に public・anon・
  --     authenticated（と、anon・authenticated が属する役）を含むものは、許可リストにあるものだけ。
  --     RESTRICTIVE の true は何も開けないので対象にしない
  CREATE TEMP TABLE rb_open_policies ON COMMIT DROP AS
  SELECT p.tablename::text AS tbl, p.policyname::text AS policy, p.cmd, p.roles, p.qual, p.with_check
    FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND p.permissive = 'PERMISSIVE'
     AND (p.qual = 'true' OR p.with_check = 'true')
     AND EXISTS (SELECT 1 FROM unnest(p.roles) AS r(rolname)
                  WHERE CASE WHEN r.rolname = 'public' THEN true
                             ELSE pg_has_role('anon', r.rolname, 'USAGE')
                                  OR pg_has_role('authenticated', r.rolname, 'USAGE') END);

  INSERT INTO pg_temp.rb_problems (section, detail)
  SELECT '1', format('[1c] %s.%s（FOR %s TO %s USING %s WITH CHECK %s）: 条件の無いポリシーが許可リストに無い。'
                     '条件を付けるか、理由を書いて「条件の無いポリシーの許可リスト」に足す',
                     o.tbl, o.policy, o.cmd, array_to_string(o.roles, ', '),
                     coalesce(o.qual, '-'), coalesce(o.with_check, '-'))
    FROM pg_temp.rb_open_policies o
   WHERE NOT EXISTS (SELECT 1 FROM pg_temp.rb_open_policy_allowlist a
                      WHERE a.tbl = o.tbl AND a.policy = o.policy AND a.cmd = o.cmd)
   ORDER BY o.tbl, o.policy;

  INSERT INTO pg_temp.rb_problems (section, detail)
  SELECT '1', format('[1c] 許可リストの %s.%s（FOR %s）に当たる条件の無いポリシーが無い'
                     '（消えた・名前が変わった・条件が付いた・コマンドが変わった）。許可リストを直す',
                     a.tbl, a.policy, a.cmd)
    FROM pg_temp.rb_open_policy_allowlist a
   WHERE NOT EXISTS (SELECT 1 FROM pg_temp.rb_open_policies o
                      WHERE o.tbl = a.tbl AND o.policy = a.policy AND o.cmd = a.cmd)
   ORDER BY a.tbl, a.policy;

  v_list := pg_temp.rb_problem_list('1');
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 静的な確認で % 件の問題%',
      (SELECT count(*) FROM pg_temp.rb_problems WHERE section = '1'), v_list;
  END IF;

  SELECT count(*) INTO v_tables FROM pg_temp.rb_tables();
  SELECT count(*) INTO v_views
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v';
  SELECT count(*) INTO v_open FROM pg_temp.rb_open_policies;
  RAISE NOTICE 'OK: [1a] public の表 % 本は、すべて RLS が有効', v_tables;
  RAISE NOTICE 'OK: [1b] public の view % 本は、すべて security_invoker = true（materialized view は 0 本）', v_views;
  RAISE NOTICE 'OK: [1c] 条件の無いポリシー % 本は、すべて許可リストにある（%）', v_open,
    (SELECT string_agg(tbl || '.' || policy, ', ' ORDER BY tbl, policy) FROM pg_temp.rb_open_policies);
END $$;

-- =============================================================================
-- 2. データの用意（postgres として投入。RLS とガードのトリガーを通らない）
--   表を足したら、ここにその表の A / CA の行を足す（システム用の表なら、その行）
-- =============================================================================
\echo '--- 2. データの用意: トレーナー A / B・顧客 CA / CB と、全部の表の A / CA の行'

DO $$ BEGIN PERFORM pg_temp.rb_take_snapshot('before'); END $$;

-- ユーザー（A・B はトレーナー、CA・CB は顧客）
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT pg_temp.rb_id(n), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'rls-baseline-' || lower(n) || '@example.com', 'x', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['A', 'B', 'CA', 'CB']) AS n;

INSERT INTO public.trainers (id, name, email) VALUES
  (pg_temp.rb_id('A'), 'RLSベースライン トレーナーA', 'rls-baseline-a@example.com'),
  (pg_temp.rb_id('B'), 'RLSベースライン トレーナーB', 'rls-baseline-b@example.com');

INSERT INTO public.clients (client_id, name, trainer_id, email) VALUES
  (pg_temp.rb_id('CA'), 'RLSベースライン 顧客CA', pg_temp.rb_id('A'), 'rls-baseline-ca@example.com'),
  (pg_temp.rb_id('CB'), 'RLSベースライン 顧客CB', pg_temp.rb_id('B'), 'rls-baseline-cb@example.com');

-- ここから下は A / CA の行だけ（B / CB の行は入れない）

-- ワークアウト（プラン → 種目のひな形 → 割り当て → 割り当ての種目）
INSERT INTO public.workout_plans (id, trainer_id, title, plan_type) VALUES
  (pg_temp.rb_id('plan'), pg_temp.rb_id('A'), 'RLSベースライン: Aのプラン', 'self_guided');

INSERT INTO public.workout_exercises (plan_id, name, sets, reps) VALUES
  (pg_temp.rb_id('plan'), 'RLSベースライン: スクワット', 3, 10);

INSERT INTO public.workout_assignments (id, trainer_id, client_id, plan_id, assigned_date, trainer_note) VALUES
  (pg_temp.rb_id('assign'), pg_temp.rb_id('A'), pg_temp.rb_id('CA'), pg_temp.rb_id('plan'),
   CURRENT_DATE, 'RLSベースライン: Aの内輪メモ');

INSERT INTO public.workout_assignment_exercises (assignment_id, exercise_name, memo) VALUES
  (pg_temp.rb_id('assign'), 'RLSベースライン: スクワット', 'RLSベースライン: 種目メモ');

-- チケット（ひな形 → 定期チケット / チケット）
INSERT INTO public.ticket_templates (id, trainer_id, template_name, ticket_type, total_sessions, price_yen) VALUES
  (pg_temp.rb_id('template'), pg_temp.rb_id('A'), 'RLSベースライン: 4回券', 'personal', 4, 20000);

INSERT INTO public.ticket_subscriptions (id, template_id, client_id, start_date, next_issue_date) VALUES
  (pg_temp.rb_id('subscr'), pg_temp.rb_id('template'), pg_temp.rb_id('CA'),
   CURRENT_DATE, CURRENT_DATE + 30);

INSERT INTO public.tickets (id, client_id, ticket_name, ticket_type, total_sessions, remaining_sessions,
                            valid_from, valid_until, price_yen) VALUES
  (pg_temp.rb_id('ticket'), pg_temp.rb_id('CA'), 'RLSベースライン: 4回券', 'personal', 4, 4,
   CURRENT_DATE, CURRENT_DATE + 30, 20000);

-- セッション（チケットを使う）と、それに紐づくカルテ（同じ顧客・同じトレーナーのセッション）
INSERT INTO public.sessions (id, trainer_id, client_id, session_date, status, session_type, memo, ticket_id) VALUES
  (pg_temp.rb_id('session'), pg_temp.rb_id('A'), pg_temp.rb_id('CA'), now() + interval '1 day',
   'scheduled', 'RLSベースライン: パーソナル', 'RLSベースライン: Aの内輪メモ', pg_temp.rb_id('ticket'));

INSERT INTO public.client_notes (client_id, trainer_id, title, content, is_shared, session_id) VALUES
  (pg_temp.rb_id('CA'), pg_temp.rb_id('A'), 'RLSベースライン: カルテ', 'RLSベースライン: 本文',
   true, pg_temp.rb_id('session'));

-- 支払い（チケット・定期チケットに紐づく）と課金
INSERT INTO public.payments (trainer_id, client_id, ticket_id, ticket_subscription_id, amount_yen, status, due_date) VALUES
  (pg_temp.rb_id('A'), pg_temp.rb_id('CA'), pg_temp.rb_id('ticket'), pg_temp.rb_id('subscr'),
   20000, 'unpaid', CURRENT_DATE);

INSERT INTO public.trainer_billing (trainer_id, stripe_customer_id, subscription_status) VALUES
  (pg_temp.rb_id('A'), 'cus_rls_baseline_a', 'active');

-- メッセージ（CA → A と、その返信 A → CA。AFTER INSERT の call_parse_message_tags が動く）
INSERT INTO public.messages (id, sender_id, receiver_id, sender_type, receiver_type, content, reply_to_message_id) VALUES
  (pg_temp.rb_id('msg_ca'), pg_temp.rb_id('CA'), pg_temp.rb_id('A'), 'client', 'trainer',
   'RLSベースライン: CAからAへ', NULL),
  (pg_temp.rb_id('msg_a'), pg_temp.rb_id('A'), pg_temp.rb_id('CA'), 'trainer', 'client',
   'RLSベースライン: AからCAへ', pg_temp.rb_id('msg_ca'));

-- 顧客の記録
INSERT INTO public.weight_records (client_id, weight, notes) VALUES
  (pg_temp.rb_id('CA'), 60.5, 'RLSベースライン');

INSERT INTO public.meal_records (client_id, meal_type, notes, calories) VALUES
  (pg_temp.rb_id('CA'), 'breakfast', 'RLSベースライン', 450);

INSERT INTO public.exercise_records (client_id, exercise_type, duration, memo) VALUES
  (pg_temp.rb_id('CA'), 'walking', 30, 'RLSベースライン');

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, source) VALUES
  (pg_temp.rb_id('CA'), CURRENT_DATE, 420, 'manual');

INSERT INTO public.ai_estimation_logs (client_id, trainer_id, function_name, status) VALUES
  (pg_temp.rb_id('CA'), pg_temp.rb_id('A'), 'estimate-meal-nutrition', 'success');

-- トレーナーの持ち物
INSERT INTO public.alerts (trainer_id, client_id, alert_type, severity, first_detected_on, surfaced_on, last_detected_on) VALUES
  (pg_temp.rb_id('A'), pg_temp.rb_id('CA'), 'record_gap', 'medium', CURRENT_DATE, CURRENT_DATE, CURRENT_DATE);

INSERT INTO public.trainer_schedules (trainer_id, day_of_week, start_time, end_time) VALUES
  (pg_temp.rb_id('A'), 1, '09:00', '18:00');

INSERT INTO public.push_subscriptions (trainer_id, endpoint, p256dh, auth) VALUES
  (pg_temp.rb_id('A'), 'https://push.example.invalid/rls-baseline-a', 'rls-baseline-p256dh', 'rls-baseline-auth');

-- ユーザー単位の表（トレーナー A と顧客 CA の両方の行）
INSERT INTO public.device_tokens (user_id, user_type, platform, token) VALUES
  (pg_temp.rb_id('A'),  'trainer', 'web_push', 'rls-baseline-token-a'),
  (pg_temp.rb_id('CA'), 'client',  'ios',      'rls-baseline-token-ca');

INSERT INTO public.notification_preferences (user_id, kind) VALUES
  (pg_temp.rb_id('A'),  'client_alert'),
  (pg_temp.rb_id('CA'), 'message');

INSERT INTO public.notification_logs (user_id, kind, dedup_key, title, status) VALUES
  (pg_temp.rb_id('A'),  'client_alert', 'rls-baseline:a',  'RLSベースライン', 'sent'),
  (pg_temp.rb_id('CA'), 'message',      'rls-baseline:ca', 'RLSベースライン', 'sent');

INSERT INTO public.user_consents (user_id, user_type, document, version) VALUES
  (pg_temp.rb_id('A'),  'trainer', 'terms',   'rls-baseline'),
  (pg_temp.rb_id('CA'), 'client',  'privacy', 'rls-baseline');

-- システム用の表（持ち主の列が無い。anon / authenticated からは見えも書けもしないはずの行）
INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats) VALUES
  (CURRENT_DATE, now(), now(), now(), '{"rls_baseline": true}');

INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary) VALUES
  ('rls-baseline', 'rls-baseline-job', 'job_failed', now(), 'RLSベースライン');

INSERT INTO public.cron_http_requests (request_id, jobname) VALUES
  (-5400, 'rls-baseline-job');

-- app_config は 1 行だけの表（id = 1。migration が入れる）。行を書き換えて試験用の行にする
INSERT INTO public.app_config (id, update_message) VALUES (1, 'RLSベースライン')
ON CONFLICT (id) DO UPDATE SET update_message = EXCLUDED.update_message;

-- -----------------------------------------------------------------------------
-- 網羅の確認: 全部の表に、このテストが入れた（か書き換えた）守る行がある
--   前からあった行（Seed など）では数えない。新しい表を足した人に、ここへの追加と
--   RLS の判断を促すため
-- -----------------------------------------------------------------------------
\echo '--- 2. 網羅の確認: 全部の表に、このテストが入れた守る行があること'

DO $$
DECLARE
  v_list text;
BEGIN
  PERFORM pg_temp.rb_take_snapshot('after');

  INSERT INTO pg_temp.rb_problems (section, detail)
  SELECT '2', format('%s: このテストが入れた守る行が無い。表 %s の行（A / CA が持ち主の行。システム用の表なら、その行）を '
                     'rls_baseline_test.sql の「2. データの用意」に足してください', t, t)
    FROM pg_temp.rb_tables() AS t
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_temp.rb_rows a
      WHERE a.phase = 'after' AND a.tbl = t AND pg_temp.rb_is_protected(a.row_data)
        AND NOT EXISTS (SELECT 1 FROM pg_temp.rb_rows b
                         WHERE b.phase = 'before' AND b.tbl = t AND b.row_data = a.row_data));

  v_list := pg_temp.rb_problem_list('2');
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 網羅の確認で % 件の問題%',
      (SELECT count(*) FROM pg_temp.rb_problems WHERE section = '2'), v_list;
  END IF;
  RAISE NOTICE 'OK: [2] 全部の表（% 本）に、このテストが入れた守る行がある（全部で % 行。うち守る行 % 行）',
    (SELECT count(*) FROM pg_temp.rb_tables()),
    (SELECT count(*) FROM pg_temp.rb_rows WHERE phase = 'after'),
    (SELECT count(*) FROM pg_temp.rb_rows WHERE phase = 'after' AND pg_temp.rb_is_protected(row_data));
END $$;

-- =============================================================================
-- 3. 振る舞いの確認
-- =============================================================================
\echo '--- 3. 振る舞いの確認: 試しのトリガーの用意'

-- 試しのトリガーが記録した行（anon / authenticated が書き込むので INSERT を渡す）
CREATE TEMP TABLE rb_probe_hits (
  tbl      regclass NOT NULL,
  op       text     NOT NULL,
  row_data jsonb    NOT NULL
) ON COMMIT DROP;
GRANT INSERT ON pg_temp.rb_probe_hits TO anon, authenticated;

-- 先頭の BEFORE UPDATE: NEW を OLD に戻す（同じ値での上書き。既存のガードには何も変えない UPDATE に見える）
CREATE FUNCTION pg_temp.rb_trg_same_value() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  RETURN OLD;
END
$fn$;

-- 最後の BEFORE UPDATE / DELETE: 届いた行を記録し、NULL を返す（行を変えない・消さない）
CREATE FUNCTION pg_temp.rb_trg_probe() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  INSERT INTO pg_temp.rb_probe_hits (tbl, op, row_data) VALUES (TG_RELID::regclass, TG_OP, to_jsonb(OLD));
  RETURN NULL;
END
$fn$;

-- 列を読まない UPDATE（WHERE 無し）。その役が UPDATE できる最初の列に NULL を入れる
-- （UPDATE できる列が無ければ最初の列 = 権限エラー）。identity ALWAYS・生成列は DEFAULT にする。
-- 値は先頭のトリガーが OLD に戻すので、何を入れても同じ値での上書きになる
CREATE FUNCTION pg_temp.rb_update_sql(p_tbl regclass, p_role text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT format('UPDATE %s SET %I = %s', p_tbl, a.attname,
                CASE WHEN a.attidentity::text = 'a' OR a.attgenerated::text <> '' THEN 'DEFAULT' ELSE 'NULL' END)
    FROM pg_attribute a
   WHERE a.attrelid = p_tbl AND a.attnum > 0 AND NOT a.attisdropped
   ORDER BY has_column_privilege(p_role, p_tbl, a.attname, 'UPDATE') DESC, a.attnum
   LIMIT 1
$$;

DO $$
DECLARE
  t regclass;
BEGIN
  -- パーティションには親から複製されるので、親（とふつうの表）にだけ作る
  FOR t IN SELECT c.oid::regclass
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition
            ORDER BY c.relname LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.rb_trg_same_value()',
                   '!rls_baseline_same_value', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION pg_temp.rb_trg_probe()',
                   '~rls_baseline_probe', t);
  END LOOP;
END $$;

-- 並びの確認: BEFORE ROW のトリガーは名前の順（C の照合順）に動く。
-- 試しのトリガーが UPDATE の先頭と最後・DELETE の最後に来ていること
DO $$
DECLARE
  v_list text;
BEGIN
  WITH trg AS (
    SELECT tg.tgrelid, tg.tgname,
           (tg.tgtype & 16) <> 0 AS on_update,
           (tg.tgtype & 8)  <> 0 AS on_delete
      FROM pg_trigger tg
     WHERE tg.tgrelid IN (SELECT * FROM pg_temp.rb_tables())
       AND (tg.tgtype & 1) = 1    -- FOR EACH ROW
       AND (tg.tgtype & 66) = 2   -- BEFORE（INSTEAD OF ではない）
       AND tg.tgenabled IN ('O', 'A')
  ), edges AS (
    SELECT r.tbl,
           (SELECT tgname FROM trg WHERE tgrelid = r.tbl AND on_update ORDER BY tgname COLLATE "C" LIMIT 1)      AS first_update,
           (SELECT tgname FROM trg WHERE tgrelid = r.tbl AND on_update ORDER BY tgname COLLATE "C" DESC LIMIT 1) AS last_update,
           (SELECT tgname FROM trg WHERE tgrelid = r.tbl AND on_delete ORDER BY tgname COLLATE "C" DESC LIMIT 1) AS last_delete
      FROM pg_temp.rb_tables() AS r(tbl)
  )
  SELECT E'\n' || string_agg(format('  - %s: UPDATE の先頭 %s / UPDATE の最後 %s / DELETE の最後 %s',
                                    tbl, first_update, last_update, last_delete), E'\n')
    INTO v_list
    FROM edges
   WHERE first_update IS DISTINCT FROM '!rls_baseline_same_value'
      OR last_update  IS DISTINCT FROM '~rls_baseline_probe'
      OR last_delete  IS DISTINCT FROM '~rls_baseline_probe';
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'テストの誤り: 試しのトリガーの並びが想定と違う（既存のトリガーの名前が ! より前か ~ より後に並んでいる）%', v_list;
  END IF;
  RAISE NOTICE 'OK: 試しのトリガーは、全部の表で UPDATE の先頭と最後・DELETE の最後に並んでいる';
END $$;

-- 自己確認: postgres（RLS もガードも通らない）では、全部の表の全行に届く。
-- 届かない表があれば、この仕組みでは穴を見つけられないので止める
DO $$
DECLARE
  t      regclass;
  v_sql  text;
  v_rows bigint;
  v_hits bigint;
  v_bad  text := '';
BEGIN
  FOR t IN SELECT * FROM pg_temp.rb_tables() LOOP
    SELECT count(*) INTO v_rows FROM pg_temp.rb_rows WHERE phase = 'after' AND tbl = t;
    FOREACH v_sql IN ARRAY ARRAY[pg_temp.rb_update_sql(t, current_user), format('DELETE FROM %s', t)] LOOP
      DELETE FROM pg_temp.rb_probe_hits;
      EXECUTE v_sql;
      SELECT count(*) INTO v_hits FROM pg_temp.rb_probe_hits;
      IF v_hits <> v_rows THEN
        v_bad := v_bad || format(E'\n  - %s: %s 行のうち %s 行にしか届かない（%s）', t, v_rows, v_hits, v_sql);
      END IF;
    END LOOP;
  END LOOP;
  DELETE FROM pg_temp.rb_probe_hits;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'テストの誤り: 試しのトリガーが postgres の UPDATE / DELETE で全行に届かない%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 試しのトリガーは、postgres の UPDATE / DELETE で全部の表の全行に届く';
END $$;

-- -----------------------------------------------------------------------------
-- 役ごとの確認（anon / B / CB で、全部の表について SELECT・UPDATE・DELETE を試す）
--   見つけた問題は rb_problems に貯め、3 つの役が終わってからまとめて FAIL にする
--   （試しは行を変えないので、続けても次の確認を汚さない）
-- -----------------------------------------------------------------------------
CREATE FUNCTION pg_temp.rb_check_as(p_who text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_role    text := CASE WHEN p_who = 'anon' THEN 'anon' ELSE 'authenticated' END;
  t         regclass;
  v_relname text;
  v_cols    text[];
  v_count   bigint;
  v_visible jsonb;
  v_allowed boolean;
  v_sql     text;
  v_op      text;
  v_state   text;
  v_msg     text;
  v_ctx     text;
  v_n_prot  bigint;
  v_n_all   bigint;
  v_example text;
  v_outcome text;
  v_line    text;
  v_ok      boolean;
BEGIN
  FOR t IN SELECT * FROM pg_temp.rb_tables() LOOP
    SELECT c.relname INTO v_relname FROM pg_class c WHERE c.oid = t;
    v_ok := true;

    -- ---- 3a. SELECT: count(*) と、読める列だけの行 ----
    SELECT array_agg(a.attname::text ORDER BY a.attnum) INTO v_cols
      FROM pg_attribute a
     WHERE a.attrelid = t AND a.attnum > 0 AND NOT a.attisdropped
       AND has_column_privilege(v_role, t, a.attname, 'SELECT');
    v_allowed := EXISTS (SELECT 1 FROM pg_temp.rb_visible_allowlist al
                          WHERE al.tbl = v_relname AND al.who = p_who);
    v_count := NULL; v_visible := NULL; v_state := NULL; v_msg := NULL; v_n_prot := 0;

    PERFORM pg_temp.rb_as(p_who);
    BEGIN
      EXECUTE format('SELECT count(*) FROM %s', t) INTO v_count;
      IF v_count > 0 THEN
        EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) FROM (SELECT %s FROM %s) x',
                       (SELECT string_agg(quote_ident(col), ', ') FROM unnest(v_cols) AS col), t)
           INTO v_visible;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    END;
    PERFORM pg_temp.rb_as('postgres');

    IF v_state IS NOT NULL THEN
      IF v_state = '42501' THEN
        v_outcome := '権限なし';
      ELSE
        v_outcome := format('想定外のエラー（%s）', v_msg);
        v_ok := false;
        INSERT INTO pg_temp.rb_problems (section, detail)
        VALUES ('3', format('[%s] %s SELECT: 想定外のエラー %s %s（0 行か権限エラーのはず）',
                            p_who, t, v_state, v_msg));
      END IF;
    ELSE
      -- 見えた行（読める列だけ）と、守る行の写し（同じ列だけ）を突き合わせる
      SELECT count(*), left(min(r.row_data::text), 300)
        INTO v_n_prot, v_example
        FROM pg_temp.rb_rows r
       WHERE r.phase = 'after' AND r.tbl = t AND pg_temp.rb_is_protected(r.row_data)
         AND v_visible IS NOT NULL
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_visible) AS vis(val)
                      WHERE vis.val = (SELECT jsonb_object_agg(e.key, e.value)
                                         FROM jsonb_each(r.row_data) e
                                        WHERE e.key = ANY (v_cols)));
      -- B・CB の行の数より多く見えていれば、読める列で突き合わせられなくても、差の分は守る行
      v_n_prot := greatest(v_n_prot, coalesce(v_count, 0)
                    - (SELECT count(*) FROM pg_temp.rb_rows r
                        WHERE r.phase = 'after' AND r.tbl = t AND NOT pg_temp.rb_is_protected(r.row_data)));
      v_example := coalesce(v_example, '（読める列からは行を特定できない）');
      IF v_n_prot > 0 AND v_allowed THEN
        v_outcome := format('許可リスト（守る行 %s 行が見える）', v_n_prot);
      ELSIF v_n_prot > 0 THEN
        v_outcome := format('守る行が %s 行見える', v_n_prot);
        v_ok := false;
        INSERT INTO pg_temp.rb_problems (section, detail)
        VALUES ('3', format('[%s] %s SELECT: 守る行が %s 行見える（見えた行は全部で %s 行。例: %s）。'
                            '見せてよい表なら、理由を書いて「見えてよい表の許可リスト」に足す',
                            p_who, t, v_n_prot, v_count, v_example));
      ELSIF v_count > 0 THEN
        v_outcome := format('B・CB の行だけ（%s 行）', v_count);
      ELSE
        v_outcome := '0 行';
      END IF;
    END IF;

    IF v_allowed AND v_n_prot = 0 THEN
      v_ok := false;
      INSERT INTO pg_temp.rb_problems (section, detail)
      VALUES ('3', format('[%s] %s SELECT: 「見えてよい表の許可リスト」にあるのに守る行が見えない（%s）。許可リストから外す',
                          p_who, t, v_outcome));
    END IF;
    v_line := 'SELECT ' || v_outcome;

    -- ---- 3b. UPDATE・DELETE: 列を読まない形で全行に試し、試しのトリガーに届いた行を見る ----
    FOREACH v_op IN ARRAY ARRAY['UPDATE', 'DELETE'] LOOP
      v_sql := CASE v_op WHEN 'UPDATE' THEN pg_temp.rb_update_sql(t, v_role)
                         ELSE format('DELETE FROM %s', t) END;
      v_state := NULL; v_msg := NULL; v_ctx := NULL;
      DELETE FROM pg_temp.rb_probe_hits;

      PERFORM pg_temp.rb_as(p_who);
      BEGIN
        EXECUTE v_sql;
      EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_ctx = PG_EXCEPTION_CONTEXT;
      END;
      PERFORM pg_temp.rb_as('postgres');

      -- 試しのトリガー自身のエラーを「書けなかった」と取り違えない
      IF coalesce(strpos(v_ctx, 'rb_trg_'), 0) > 0 THEN
        RAISE EXCEPTION 'テストの誤り: 試しのトリガーでエラー（[%] % %: % %）', p_who, t, v_op, v_state, v_msg;
      END IF;

      SELECT count(*) FILTER (WHERE pg_temp.rb_is_protected(h.row_data)),
             count(*),
             left(min(h.row_data::text) FILTER (WHERE pg_temp.rb_is_protected(h.row_data)), 300)
        INTO v_n_prot, v_n_all, v_example
        FROM pg_temp.rb_probe_hits h;

      IF v_state IS NOT NULL THEN
        -- 権限エラー・ガードのトリガーの例外: 書けなかった（エラーで文ごと戻るので記録も残らない）
        v_outcome := CASE WHEN v_state = '42501' AND v_msg LIKE 'permission denied%' THEN '権限なし'
                          ELSE format('エラー（%s）', v_msg) END;
      ELSIF v_n_prot > 0 THEN
        v_outcome := format('守る行 %s 行に届いた', v_n_prot);
        v_ok := false;
        INSERT INTO pg_temp.rb_problems (section, detail)
        VALUES ('3', format('[%s] %s %s: 守る行 %s 行に届いた（ポリシーと既存のガードを通った。例: %s）。SQL: %s',
                            p_who, t, v_op, v_n_prot, v_example, v_sql));
      ELSIF v_n_all > 0 THEN
        v_outcome := format('B・CB の行だけ（%s 行）', v_n_all);
      ELSE
        v_outcome := '0 行';
      END IF;
      v_line := v_line || ' / ' || v_op || ' ' || v_outcome;
    END LOOP;

    RAISE NOTICE '%: [%] %: %', CASE WHEN v_ok THEN 'OK' ELSE 'NG' END, p_who, t, v_line;
  END LOOP;
END
$fn$;

\echo '--- 3. 振る舞いの確認: anon（JWT のクレーム無し）'
DO $$ BEGIN PERFORM pg_temp.rb_check_as('anon'); END $$;

\echo '--- 3. 振る舞いの確認: B（認証済み・他人のトレーナー）'
DO $$ BEGIN PERFORM pg_temp.rb_check_as('B'); END $$;

\echo '--- 3. 振る舞いの確認: CB（認証済み・他人の顧客）'
DO $$ BEGIN PERFORM pg_temp.rb_check_as('CB'); END $$;

-- -----------------------------------------------------------------------------
-- 3c. 全部の表の行が、試す前の写しと同じ（1 行も変わっていない・消えていない・増えていない）
-- -----------------------------------------------------------------------------
\echo '--- 3c. 振る舞いの確認のあと、全部の表の行が試す前の写しと同じであること'

DO $$
DECLARE
  v_n    bigint;
  v_list text;
BEGIN
  IF current_user IS DISTINCT FROM session_user THEN
    RAISE EXCEPTION 'テストの誤り: 3c は postgres で確かめる（current_user=%）', current_user;
  END IF;
  PERFORM pg_temp.rb_take_snapshot('final');

  WITH a AS (SELECT tbl, row_data FROM pg_temp.rb_rows WHERE phase = 'after'),
       f AS (SELECT tbl, row_data FROM pg_temp.rb_rows WHERE phase = 'final'),
       diff AS (
         SELECT '試す前にあった行が無い（変わった・消えた）' AS kind, x.* FROM (SELECT * FROM a EXCEPT ALL SELECT * FROM f) x
         UNION ALL
         SELECT '試す前に無かった行がある（変わった・増えた）', y.* FROM (SELECT * FROM f EXCEPT ALL SELECT * FROM a) y
       )
  SELECT count(*), E'\n' || string_agg(format('  - %s %s: %s', tbl, kind, left(row_data::text, 300)), E'\n')
    INTO v_n, v_list
    FROM diff;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'FAIL: [3c] 振る舞いの確認のあと、行が試す前の写しと違う（% 行）%', v_n, v_list;
  END IF;
  RAISE NOTICE 'OK: [3c] 全部の表の行（% 行）は、試す前の写しと同じ',
    (SELECT count(*) FROM pg_temp.rb_rows WHERE phase = 'after');
END $$;

-- -----------------------------------------------------------------------------
-- 3a・3b のまとめ（問題があれば、3 つの役の分をまとめて FAIL にする）
-- -----------------------------------------------------------------------------
\echo '--- 3. 振る舞いの確認のまとめ'

DO $$
DECLARE
  v_list text;
BEGIN
  v_list := pg_temp.rb_problem_list('3');
  IF v_list IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 振る舞いの確認で % 件の問題%',
      (SELECT count(*) FROM pg_temp.rb_problems WHERE section = '3'), v_list;
  END IF;
  RAISE NOTICE 'OK: [3a] anon / B / CB のどれにも、許可リストの表のほかは守る行が見えない';
  RAISE NOTICE 'OK: [3b] anon / B / CB のどれも、全部の表で守る行を UPDATE / DELETE できない';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL RLS BASELINE TESTS PASSED'
