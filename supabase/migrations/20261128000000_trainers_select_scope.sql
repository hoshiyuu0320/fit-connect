-- =============================================================================
-- Migration: trainers_select_scope
-- 目的: public.trainers を読める行と列を、役ごとに要る分だけにする。
--   trainers_select_all（FOR SELECT TO public USING (true)。20260131000001）をやめ、
--   役ごとの SELECT のポリシー 3 本と、anon の列単位の GRANT に置き換える。
--
-- テスト: supabase/tests/trainers_rls_test.sql（ポリシー・権限・役ごとの読み取り。
--   BEGIN...ROLLBACK で DB に何も残さない）。rls_baseline_test.sql の許可リストも合わせて直した
--
-- この migration のあと、読めるもの:
--   anon（ログイン前）: 全部の行の id・name・profile_image_url だけ
--     - Mobile の登録で、QR・招待コードのトレーナー id から名前と画像を引くため
--       （registration_provider.dart の fetchTrainerInfo。どの版のアプリもこの 3 列を id で引く）
--     - ポリシーは trainers_select_anon（TO anon USING (true)）。列は GRANT で 3 列に絞る。
--       ほかの列を選ぶと（select * も）権限エラー（42501）になる。テーブル単位の権限は持たない
--   authenticated（ログイン後）: 自分に関係する行だけ、全部の列
--     - トレーナーは自分の行（trainers_select_own）
--     - 顧客は担当トレーナーの行（trainers_select_client_trainer。自分の clients の行の trainer_id）
--     - ほかの行は 0 行（エラーにはならない）
--     - 列は絞らない（テーブル単位の SELECT をそのまま残す）。Web（設定画面など）も、どの版の
--       Mobile も select * で読むので、列単位の GRANT にすると 42501 で失敗するため
--   messages_guard_insert()（SECURITY INVOKER。20260922000200）は、トレーナーが送るメッセージで、
--   呼び出し元の権限のまま自分の trainers の行を探す。trainers_select_own が無いと、トレーナーからの
--   送信が MESSAGES_INVALID_SENDER_TYPE で拒否される（column_write_guards_test.sql の f2 などで落ちる）。
--   ほかに trainers を読む関数は SECURITY DEFINER、Edge Function と Web の API は service_role なので、
--   この migration の影響を受けない
--   Realtime（trainers は supabase_realtime にある）の変更の通知も、同じ行と列の権限に従う。
--   顧客は担当トレーナーの行の UPDATE を今までどおり受け取る
--
-- 既知の残り（意図どおり。docs/tasks/2026-07-10-integration-decisions.md 判断5）:
--   anon は今もトレーナー全員の id・name・profile_image_url を一覧できる。登録の時点では顧客の
--   行が無く、DB では相手のトレーナーを絞れないため。短い招待コードを入れて、トレーナーの id で
--   引く形をやめるのが予定の直し方
--
-- 最後の確認（DO ブロック）: anon の列とテーブルの権限、authenticated の SELECT、SELECT に効く
--   ポリシーの組が上のとおりかを確かめ、違えば例外で止める（migration ごと戻る）。
--   本番では、別の付与者による GRANT が REVOKE のあとも残りうる。黙って穴を残さないため
--
-- 冪等性: ポリシーは DROP POLICY IF EXISTS のあとに作る。REVOKE / GRANT は何度流しても同じ状態になる
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. SELECT のポリシー（trainers_select_all を 3 本に置き換える）
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "trainers_select_all" ON public.trainers;

-- anon: 登録でトレーナーを id から引く（読める列は 2. の GRANT で 3 列に絞る）
DROP POLICY IF EXISTS "trainers_select_anon" ON public.trainers;
CREATE POLICY "trainers_select_anon"
  ON public.trainers
  FOR SELECT
  TO anon
  USING (true);

-- トレーナー: 自分の行（messages_guard_insert もこれで自分の行を見る）
DROP POLICY IF EXISTS "trainers_select_own" ON public.trainers;
CREATE POLICY "trainers_select_own"
  ON public.trainers
  FOR SELECT
  TO authenticated
  USING (id = (SELECT auth.uid()));

-- 顧客: 担当トレーナーの行（clients のポリシーは trainers を参照しないので、再帰にならない）
DROP POLICY IF EXISTS "trainers_select_client_trainer" ON public.trainers;
CREATE POLICY "trainers_select_client_trainer"
  ON public.trainers
  FOR SELECT
  TO authenticated
  USING (id IN (SELECT c.trainer_id
                  FROM public.clients c
                 WHERE c.client_id = (SELECT auth.uid())));

-- -----------------------------------------------------------------------------
-- 2. anon の権限: テーブル単位の権限をすべて外し、3 列の SELECT だけにする
--   authenticated の権限は変えない（テーブル単位の SELECT が残る。書き込みは
--   20260712000000 §4 の列単位の GRANT のまま）
-- -----------------------------------------------------------------------------
REVOKE ALL ON public.trainers FROM anon;
GRANT SELECT (id, name, profile_image_url) ON public.trainers TO anon;

-- -----------------------------------------------------------------------------
-- 3. 確かめる（違えば例外で止め、この migration ごと戻す）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_bad      text;
  v_actual   text;
  v_expected text := 'trainers_select_anon FOR SELECT TO anon PERMISSIVE; '
                  || 'trainers_select_client_trainer FOR SELECT TO authenticated PERMISSIVE; '
                  || 'trainers_select_own FOR SELECT TO authenticated PERMISSIVE';
BEGIN
  -- (a) anon が SELECT できる列は id・name・profile_image_url だけ
  SELECT string_agg(format('%s（%s）', a.attname,
                           CASE WHEN has_column_privilege('anon', 'public.trainers', a.attname, 'SELECT')
                                THEN '読める' ELSE '読めない' END),
                    ', ' ORDER BY a.attnum)
    INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.trainers'::regclass
     AND a.attnum > 0
     AND NOT a.attisdropped
     AND has_column_privilege('anon', 'public.trainers', a.attname, 'SELECT')
         <> (a.attname IN ('id', 'name', 'profile_image_url'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trainers の anon の列の権限が想定と違う: %（読めるのは id・name・profile_image_url だけのはず）。'
                    '別の付与者や PUBLIC への GRANT が残っていないか確かめる', v_bad;
  END IF;

  -- (b) anon はテーブル単位の権限を持たない
  SELECT string_agg(u.priv, ', ' ORDER BY u.ord)
    INTO v_bad
    FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'])
         WITH ORDINALITY AS u(priv, ord)
   WHERE has_table_privilege('anon', 'public.trainers', u.priv);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'trainers の anon にテーブル単位の権限が残っている: %。'
                    '別の付与者や PUBLIC への GRANT が残っていないか確かめる', v_bad;
  END IF;

  -- (c) authenticated はテーブル単位の SELECT を持つ（Web と Mobile の select * に要る）
  IF NOT has_table_privilege('authenticated', 'public.trainers', 'SELECT') THEN
    RAISE EXCEPTION 'trainers の authenticated にテーブル単位の SELECT が無い（Web と Mobile の select * が 42501 で失敗する）';
  END IF;

  -- (d) SELECT に効くポリシー（FOR SELECT と FOR ALL）は 1. の 3 本だけ
  SELECT string_agg(format('%s FOR %s TO %s %s', p.policyname, p.cmd,
                           array_to_string(p.roles, ', '), p.permissive),
                    '; ' ORDER BY p.policyname)
    INTO v_actual
    FROM pg_policies p
   WHERE p.schemaname = 'public'
     AND p.tablename = 'trainers'
     AND p.cmd IN ('SELECT', 'ALL');
  IF v_actual IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'trainers の SELECT に効くポリシーが想定と違う: %（想定: %）。ほかのポリシーが残っていないか確かめる',
      coalesce(v_actual, 'なし'), v_expected;
  END IF;
END $$;
