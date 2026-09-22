-- =============================================================================
-- messages トリガー関数 call_parse_message_tags() の送信先 / 認証ヘッダー / 権限 テスト
-- （fix/parse-message-tags-webhook）
--
-- 対象: public.call_parse_message_tags()（トリガー on_message_insert / on_message_update）
--
-- 検証対象の migration:
--   supabase/migrations/20260922000100_secure_parse_message_tags_webhook.sql
--     （本番 URL の直書きをやめて Vault の project_url / secret_key で送る / Vault が揃って
--       いなければ送らない / SECURITY DEFINER + SET search_path = '' / EXECUTE を全ロールから剥奪）
--
-- 是正前（20260719000000 の定義 = 2026-09-22 のリモート）は、本番の Edge Function URL を直書きし、
-- 認証ヘッダー無しで net.http_post していた。そのため、コミットされたメッセージは Vault の有無に
-- 関係なく、どの環境からも本番へ送られていた（2026-09-22、ローカルの Seed.sql のメッセージが
-- 本番の notification_logs に 18 行を作った）。本テストは是正後の状態と、アプリの実際の書き込み
-- 経路（authenticated + RLS）でトリガーが「送るべきときだけ、正しい宛先・ヘッダーで」要求を
-- 積むことを固定する自己完結テスト
-- （definer_functions_privileges_test.sql / session_reminder_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/parse_message_tags_webhook_test.sql
--
-- - 全ケース成功時のみ、最後に NOTICE「ALL PARSE MESSAGE TAGS WEBHOOK TESTS PASSED」が出力される
--   （ROLLBACK の後の DO ブロックで出す）
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データ（Vault の退避・試験用シークレットを含む）は BEGIN...ROLLBACK 内で作成され、
--   DB には一切残らない
--
-- 送信の安全性（重要）:
--   - pg_net の要求は net.http_request_queue への INSERT で、ワーカーはコミット済みの行しか
--     見ない。本テストのメッセージ INSERT はすべてトランザクション内で、最後に ROLLBACK する
--     （FAIL で psql が異常終了した場合も、接続が切れてトランザクションは破棄される）ので、
--     実際には 1 件も送信されない
--   - (f) 以降で Vault に入れる試験用の project_url は予約 TLD の http://parse-tags-test.invalid/
--     （RFC 2606。名前解決されない）で、secret_key もダミー値
--   - 是正前の定義（本番 URL 直書き）の DB で流しても、(a) のカタログ検査で FAIL するため、
--     メッセージを 1 件も INSERT しないうちに止まる
--
-- Vault の扱い:
--   - 開発者がローカルの Vault に project_url / secret_key を登録済みでも、未登録でも同じ結果に
--     なるよう、setup で既存の 2 つを vault.update_secret(id, new_name := ...) で別名に退避する
--     （ROLLBACK で元の名前に戻る）。postgres は vault.secrets を直接 UPDATE できないが、
--     vault.create_secret / vault.update_secret の EXECUTE と vault.decrypted_secrets の SELECT を持つ
--
-- 要求の数え方:
--   - 各ステップの直前に net.http_request_queue の max(id) を控え（カスタム GUC
--     parse_tags_test.q_before。トランザクションローカル）、ステップ後に id がそれより大きい行を
--     数える（キューには無関係の行がありうるため件数の絶対値は見ない）。body は bytea なので
--     convert_from(body, 'UTF8')::jsonb で読む
--   - 「0 件」のケースは、送信先に関係なくすべての行を数える（どこへも送らないこと）
--
-- アプリと同じ書き込み経路:
--   - メッセージの INSERT / UPDATE は SET LOCAL ROLE authenticated + request.jwt.claims の sub
--     （PostgREST の set_config(..., true) と同じ）で行い、RLS（INSERT: sender_id = auth.uid() /
--     送信者は 5 分以内なら UPDATE 可 / 受信者は read_at 等を UPDATE 可）を通す。
--     auth.uid() は request.jwt.claim.sub（旧形式）を優先して読むため、両形式を常に揃えて設定する
--   - INSERT / UPDATE は DO ブロックで包み、失敗したら FAIL として報告する（Vault が揃って
--     いないときにメッセージの保存自体が失敗する実装を、素のエラーではなくケース名付きで検出する）
--   - 件数の検査は postgres に戻してから行う（net.http_request_queue への PUBLIC の付与に依存しない）
--
-- 検証ケース:
--   (a) 定義の固定（カタログ）: SECURITY DEFINER / proconfig = {search_path=""} / owner postgres /
--       proacl 非 NULL / PUBLIC（grantee 0）への付与なし / ACL の grantee 集合がちょうど {postgres} /
--       anon・authenticated・service_role の has_function_privilege(EXECUTE) がすべて false
--   (b) 本体に本番の URL（'viribpvnpgtgtmeulcmx' / 'supabase.co'）が含まれない
--   (c) トリガー on_message_insert（AFTER INSERT / FOR EACH ROW）と on_message_update
--       （AFTER UPDATE OF content / FOR EACH ROW）が public.messages 上に有効な状態で存在し、
--       public.call_parse_message_tags() を実行する（この関数を実行するトリガーはこの 2 本だけ）
--   (d) 直接呼び出しの拒否:
--       (d-1) anon（クレーム無し）/ (d-2) authenticated（顧客 C のクレーム）/ (d-3) service_role:
--             PERFORM public.call_parse_message_tags() が 42501 かつ
--             SQLERRM LIKE 'permission denied for function %'（GRANT 層で拒否）
--       (d-4) オーナー postgres でも直接は呼べない（0A000 'trigger functions can only be called
--             as triggers'。migration が「トリガー関数はトリガーからしか実行できない」を DEFINER を
--             トリガー関数自体に付ける根拠にしているため、その前提を固定する）
--       (d-5) anon / authenticated は vault.decrypted_secrets を SELECT できない（42501）
--   (e) Vault が揃っていないときは送らない（メッセージの保存は成功する）:
--       (e-1) Vault 未登録: 顧客 C（authenticated）の INSERT が成功し、要求 0 件
--       (e-2) Vault 未登録: postgres・クレーム無しの INSERT（Seed.sql の経路）も要求 0 件
--       (e-3) secret_key だけ登録（project_url 未登録）: 顧客 C の INSERT が成功し、要求 0 件
--       (e-4) project_url 登録 + secret_key が空文字: 顧客 C の INSERT が成功し、要求 0 件
--   (f) Vault が揃っているとき（project_url は末尾 / 付き）: 顧客 C の INSERT で要求ちょうど 1 件。
--       method POST / url = 'http://parse-tags-test.invalid/functions/v1/parse-message-tags'
--       （末尾 / の二重化なし）/ headers はちょうど {Content-Type: application/json, apikey: ダミー
--       キー}（Authorization なし）/ body の type = 'INSERT'・table = 'messages'・record の
--       キー構成が現行と同一で id / sender_id / sender_type / receiver_id / receiver_type /
--       content が INSERT した行と一致・old_record なし・body に secret キーを含まない
--   (g) 送信者 C の content 編集（5 分以内の UPDATE）で要求ちょうど 1 件: type = 'UPDATE'・
--       record.content = 新しい本文・old_record.content = 編集前の本文・old_record に tags あり
--   (h) 受信者 T の既読化（read_at だけの UPDATE。1 行更新されること）で要求 0 件
--   (i) トレーナー T が送った INSERT でも要求ちょうど 1 件（record.sender_type = 'trainer'。
--       トリガーは送信者種別で絞らず、判断は Edge Function が行う）
--   (j) SAVEPOINT 内の INSERT は要求を 1 件積むが、ROLLBACK TO SAVEPOINT 後は要求 0 件・
--       メッセージも残らない（ロールバックされた INSERT は送られない）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 前提確認: 対象の関数が存在すること
--   存在しない関数を各ケースで参照すると素のエラーで落ちて原因が分かりにくいため、
--   ここで明示的に FAIL させる
-- -----------------------------------------------------------------------------
\echo '--- setup: 前提確認（public.call_parse_message_tags() が存在すること）'

DO $$
BEGIN
  IF to_regprocedure('public.call_parse_message_tags()') IS NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — public.call_parse_message_tags() が存在しない';
  END IF;
  RAISE NOTICE 'OK: public.call_parse_message_tags() が存在する';
END $$;

-- -----------------------------------------------------------------------------
-- 既存の Vault シークレットの退避（postgres として実行）
--   project_url / secret_key が登録済みのローカルスタックでも (e) を「Vault 未登録」の状態で
--   検証できるよう、2 つを別名へ改名する。改名はトランザクション内なので ROLLBACK で戻る。
--   改名後の名前にはシークレットの id を含める（vault.secrets.name は一意索引付き）
-- -----------------------------------------------------------------------------
\echo '--- setup: 既存の Vault シークレット project_url / secret_key を別名へ退避（ROLLBACK で戻る）'

DO $$
DECLARE
  r record;
  v_moved int := 0;
BEGIN
  FOR r IN
    SELECT s.id, s.name
    FROM vault.secrets s
    WHERE s.name IN ('project_url', 'secret_key')
  LOOP
    PERFORM vault.update_secret(
      r.id,
      new_name := r.name || '__moved_by_parse_message_tags_webhook_test__' || r.id::text
    );
    v_moved := v_moved + 1;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM vault.decrypted_secrets s WHERE s.name IN ('project_url', 'secret_key')
  ) THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — Vault の project_url / secret_key を退避できなかった';
  END IF;
  RAISE NOTICE 'OK: Vault の project_url / secret_key は未登録の状態（退避した既存シークレット % 件）', v_moved;
END $$;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T : c0de0922-0000-4000-8000-000000000001
--   client  C : c0de0922-0000-4000-8000-000000000011（T の顧客）
--   メッセージは各ケースの中で、アプリと同じ経路（authenticated + RLS）で作る:
--   message M1 : c0de0922-0000-4000-8000-000000000021（(e-1) C → T / Vault 未登録）
--   message M2 : c0de0922-0000-4000-8000-000000000022（(e-2) C → T / postgres・クレーム無し）
--   message M3 : c0de0922-0000-4000-8000-000000000023（(e-3) C → T / secret_key のみ）
--   message M4 : c0de0922-0000-4000-8000-000000000024（(e-4) C → T / secret_key が空文字）
--   message M5 : c0de0922-0000-4000-8000-000000000025（(f) C → T / (g) で編集 / (h) で既読化）
--   message M6 : c0de0922-0000-4000-8000-000000000026（(i) T → C）
--   message M7 : c0de0922-0000-4000-8000-000000000027（(j) C → T / SAVEPOINT で取り消し）
--   T の顧客は 1 名なので、clients の BEFORE トリガー enforce_client_limit の上限内に収まる
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T / client C)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('c0de0922-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'parse-tags-test-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('c0de0922-0000-4000-8000-000000000011', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'parse-tags-test-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('c0de0922-0000-4000-8000-000000000001', 'タグWebhookテスト トレーナーT',
   'parse-tags-test-t@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('c0de0922-0000-4000-8000-000000000011', 'タグWebhookテスト顧客C',
   'c0de0922-0000-4000-8000-000000000001');

-- -----------------------------------------------------------------------------
-- ケース(a): 定義の固定（カタログ検査。postgres として実行）
--   - prosecdef: SECURITY DEFINER（authenticated の INSERT で発火しても Vault を読めるように）
--   - proconfig: {search_path=""} ちょうど（SET search_path = ''）
--   - owner: postgres（vault.decrypted_secrets を SELECT できるロール）
--   - proacl: NULL でない（NULL = 既定権限 = PUBLIC に EXECUTE がある状態）
--   - PUBLIC（grantee = 0）への付与が ACL に無い
--   - ACL の grantee 集合がちょうど {postgres}（has_function_privilege は 3 ロールしか見ないため、
--     それ以外のロールへの付与の残りを集合一致で検出する。pg_get_userbyid は name 型なので
--     text にキャストして比べる）
--   - anon / authenticated / service_role の EXECUTE がすべて false
-- -----------------------------------------------------------------------------
\echo '--- case a: 定義の固定（SECURITY DEFINER / search_path 空文字 / owner / ACL の grantee 集合 / EXECUTE なし）'

DO $$
DECLARE
  v_fn       record;
  v_grantees text[];
  v_role     text;
BEGIN
  SELECT p.oid, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) AS owner, p.proacl
    INTO v_fn
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.call_parse_message_tags()');

  IF v_fn.prosecdef IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags が SECURITY DEFINER でない（authenticated の INSERT で Vault を読めない）';
  END IF;
  IF v_fn.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags の proconfig が %（期待 {search_path=""} = SET search_path = '''' ）',
      coalesce(v_fn.proconfig::text, 'NULL（search_path 未設定）');
  END IF;
  IF v_fn.owner IS DISTINCT FROM 'postgres' THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags の owner が %（期待 postgres）', v_fn.owner;
  END IF;
  IF v_fn.proacl IS NULL THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags の proacl が NULL（既定権限 = PUBLIC に EXECUTE がある状態）';
  END IF;
  IF EXISTS (SELECT 1 FROM aclexplode(v_fn.proacl) a WHERE a.grantee = 0) THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags の ACL に PUBLIC への付与が残っている（%）', v_fn.proacl;
  END IF;

  SELECT array_agg(DISTINCT pg_get_userbyid(a.grantee)::text ORDER BY pg_get_userbyid(a.grantee)::text)
    INTO v_grantees
  FROM aclexplode(v_fn.proacl) a;
  IF v_grantees IS DISTINCT FROM ARRAY['postgres'] THEN
    RAISE EXCEPTION 'FAIL: (a) call_parse_message_tags の ACL の grantee 集合が %（期待 {postgres} ちょうど。ACL %）',
      coalesce(v_grantees::text, 'NULL'), v_fn.proacl;
  END IF;

  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_function_privilege(v_role, 'public.call_parse_message_tags()', 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: (a) % が call_parse_message_tags の EXECUTE を持っている（期待 false）', v_role;
    END IF;
  END LOOP;

  RAISE NOTICE 'OK: (a) SECURITY DEFINER / search_path 空文字 / owner postgres / PUBLIC なし / grantee={postgres} / anon・authenticated・service_role とも EXECUTE なし';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 本体に本番の URL が残っていない
--   送信先は Vault の project_url から組み立てる。直書きの URL（本番のプロジェクト ref や
--   supabase.co ドメイン）が本体に残っていると、フォールバック等の形で本番へ送る経路が残る
-- -----------------------------------------------------------------------------
\echo '--- case b: 本体に本番の URL（viribpvnpgtgtmeulcmx / supabase.co）が含まれないこと'

DO $$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.call_parse_message_tags()');

  IF position('viribpvnpgtgtmeulcmx' IN v_src) > 0 THEN
    RAISE EXCEPTION 'FAIL: (b) call_parse_message_tags の本体に本番のプロジェクト ref（viribpvnpgtgtmeulcmx）が含まれている';
  END IF;
  IF position('supabase.co' IN v_src) > 0 THEN
    RAISE EXCEPTION 'FAIL: (b) call_parse_message_tags の本体に supabase.co の URL が含まれている';
  END IF;
  RAISE NOTICE 'OK: (b) 本体に本番の URL は含まれない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): トリガーの固定
--   pg_trigger.tgtype のビット: ROW = 1 / BEFORE = 2 / INSERT = 4 / DELETE = 8 / UPDATE = 16 /
--   TRUNCATE = 32 / INSTEAD = 64。AFTER INSERT FOR EACH ROW = 5、AFTER UPDATE FOR EACH ROW = 17。
--   UPDATE OF content は tgattr（int2vector）に content の attnum が 1 つだけ入る
--   （int2vector を int2[] にすると下限 0 の配列になり、配列の = は下限まで比べるため
--    array_to_string で比べる）。
--   tgenabled は 'O'（通常のセッションで発火）か 'A'（常に発火）。'D'（無効）/ 'R'（レプリカ時のみ）は不可。
--   この関数を実行するトリガーがちょうど 2 本であることも固定する（重複トリガーによる二重送信の防止）
-- -----------------------------------------------------------------------------
\echo '--- case c: トリガー on_message_insert / on_message_update の固定'

DO $$
DECLARE
  v_fn_oid         oid := to_regprocedure('public.call_parse_message_tags()');
  v_content_attnum int2;
  v_trg            record;
  v_cnt            int;
BEGIN
  SELECT a.attnum INTO v_content_attnum
  FROM pg_attribute a
  WHERE a.attrelid = 'public.messages'::regclass AND a.attname = 'content' AND NOT a.attisdropped;

  -- on_message_insert: AFTER INSERT / FOR EACH ROW / 列指定なし
  SELECT t.tgtype, t.tgenabled, t.tgfoid, array_to_string(t.tgattr::int2[], ',') AS attrs
    INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.messages'::regclass
    AND t.tgname = 'on_message_insert'
    AND NOT t.tgisinternal;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: (c) public.messages にトリガー on_message_insert が無い';
  END IF;
  IF v_trg.tgfoid IS DISTINCT FROM v_fn_oid THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_insert が public.call_parse_message_tags() を実行していない（%）', v_trg.tgfoid::regprocedure;
  END IF;
  IF v_trg.tgtype <> 5 THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_insert の tgtype が %（期待 5 = AFTER INSERT FOR EACH ROW）', v_trg.tgtype;
  END IF;
  IF v_trg.attrs <> '' THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_insert に列指定がある（attnum %）', v_trg.attrs;
  END IF;
  IF v_trg.tgenabled NOT IN ('O', 'A') THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_insert が有効でない（tgenabled=%）', v_trg.tgenabled;
  END IF;

  -- on_message_update: AFTER UPDATE OF content / FOR EACH ROW
  SELECT t.tgtype, t.tgenabled, t.tgfoid, array_to_string(t.tgattr::int2[], ',') AS attrs
    INTO v_trg
  FROM pg_trigger t
  WHERE t.tgrelid = 'public.messages'::regclass
    AND t.tgname = 'on_message_update'
    AND NOT t.tgisinternal;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: (c) public.messages にトリガー on_message_update が無い';
  END IF;
  IF v_trg.tgfoid IS DISTINCT FROM v_fn_oid THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_update が public.call_parse_message_tags() を実行していない（%）', v_trg.tgfoid::regprocedure;
  END IF;
  IF v_trg.tgtype <> 17 THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_update の tgtype が %（期待 17 = AFTER UPDATE FOR EACH ROW）', v_trg.tgtype;
  END IF;
  IF v_trg.attrs IS DISTINCT FROM v_content_attnum::text THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_update の対象列が attnum %（期待 content の attnum % だけ = UPDATE OF content）',
      v_trg.attrs, v_content_attnum;
  END IF;
  IF v_trg.tgenabled NOT IN ('O', 'A') THEN
    RAISE EXCEPTION 'FAIL: (c) on_message_update が有効でない（tgenabled=%）', v_trg.tgenabled;
  END IF;

  -- この関数を実行するトリガーはこの 2 本だけ（どのテーブル上でも）
  SELECT count(*) INTO v_cnt
  FROM pg_trigger t
  WHERE t.tgfoid = v_fn_oid AND NOT t.tgisinternal;
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (c) call_parse_message_tags を実行するトリガーが % 本（期待 2 本）', v_cnt;
  END IF;

  RAISE NOTICE 'OK: (c) on_message_insert（AFTER INSERT / ROW）と on_message_update（AFTER UPDATE OF content / ROW）が有効で、call_parse_message_tags を実行する';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 直接呼び出しの拒否
--   (d-1)〜(d-3): EXECUTE を持たないロールは GRANT 層（'permission denied for function ...'）で
--   拒否されること。EXECUTE が残っていると、関数本体の手前まで進んで PL/pgSQL の 0A000
--   （trigger functions can only be called as triggers）になるため、SQLERRM で層を見分ける。
--   先行ケースのクレームが残らないよう、両形式を設定してからロールを切り替える
-- -----------------------------------------------------------------------------
\echo '--- case d-1: anon（クレーム無し）の直接呼び出しは 42501 / GRANT 層で拒否されること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM public.call_parse_message_tags();
  RAISE EXCEPTION 'FAIL: (d-1) anon が call_parse_message_tags を直接実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function %' THEN
      RAISE EXCEPTION 'FAIL: (d-1) anon の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: (d-1) anon → 42501（%）', SQLERRM;
  WHEN raise_exception THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (d-1) anon の直接呼び出しが GRANT 層で拒否されなかった（% / %）', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

\echo '--- case d-2: authenticated（顧客 C のクレーム）の直接呼び出しは 42501 / GRANT 層で拒否されること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  PERFORM public.call_parse_message_tags();
  RAISE EXCEPTION 'FAIL: (d-2) authenticated が call_parse_message_tags を直接実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function %' THEN
      RAISE EXCEPTION 'FAIL: (d-2) authenticated の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: (d-2) authenticated → 42501（%）', SQLERRM;
  WHEN raise_exception THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (d-2) authenticated の直接呼び出しが GRANT 層で拒否されなかった（% / %）', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

\echo '--- case d-3: service_role の直接呼び出しは 42501 / GRANT 層で拒否されること'

SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE service_role;

DO $$
BEGIN
  PERFORM public.call_parse_message_tags();
  RAISE EXCEPTION 'FAIL: (d-3) service_role が call_parse_message_tags を直接実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function %' THEN
      RAISE EXCEPTION 'FAIL: (d-3) service_role の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: (d-3) service_role → 42501（%）', SQLERRM;
  WHEN raise_exception THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (d-3) service_role の直接呼び出しが GRANT 層で拒否されなかった（% / %）', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

\echo '--- case d-4: オーナー postgres でも直接は呼べないこと（0A000 trigger functions can only be called as triggers）'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
BEGIN
  PERFORM public.call_parse_message_tags();
  RAISE EXCEPTION 'FAIL: (d-4) postgres が call_parse_message_tags をトリガー以外から実行できてしまった';
EXCEPTION
  WHEN feature_not_supported THEN
    IF SQLERRM <> 'trigger functions can only be called as triggers' THEN
      RAISE EXCEPTION 'FAIL: (d-4) postgres の直接呼び出しの 0A000 が想定のメッセージでない（%）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: (d-4) postgres → 0A000（%）', SQLERRM;
  WHEN raise_exception THEN
    RAISE;
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (d-4) postgres の直接呼び出しが想定外のエラー（% / %）', SQLSTATE, SQLERRM;
END $$;

\echo '--- case d-5: anon / authenticated は vault.decrypted_secrets を SELECT できないこと'

SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM 1 FROM vault.decrypted_secrets;
  RAISE EXCEPTION 'FAIL: (d-5) anon が vault.decrypted_secrets を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: (d-5) anon → 42501（%）', SQLERRM;
END $$;

RESET ROLE;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  PERFORM 1 FROM vault.decrypted_secrets;
  RAISE EXCEPTION 'FAIL: (d-5) authenticated が vault.decrypted_secrets を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: (d-5) authenticated → 42501（%）', SQLERRM;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e-1): Vault 未登録 / 顧客 C（authenticated）の INSERT
--   Mobile のメッセージ送信（message_repository.dart の sendMessage）と同じ列で INSERT する。
--   INSERT は成功し（Vault が無くてもメッセージの保存は止めない）、要求は 1 件も積まれないこと
-- -----------------------------------------------------------------------------
\echo '--- case e-1: Vault 未登録 — 顧客 C の INSERT は成功し、要求は 0 件であること'

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content, image_urls, tags, is_edited
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000021',
    'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
    'client', 'trainer', 'タグWebhookテスト: M1 C→T（Vault 未登録）', '{}', '{}', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (e-1) Vault 未登録で顧客 C のメッセージ INSERT が失敗した（メッセージの保存は止めない想定）: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e-1) Vault 未登録なのに顧客 C の INSERT で要求が % 件積まれた（url: %）', v_cnt, v_urls;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.messages m WHERE m.id = 'c0de0922-0000-4000-8000-000000000021') THEN
    RAISE EXCEPTION 'FAIL: (e-1) M1 が保存されていない';
  END IF;
  RAISE NOTICE 'OK: (e-1) Vault 未登録 — 顧客 C の INSERT は成功し、要求 0 件';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e-2): Vault 未登録 / postgres・クレーム無しの INSERT（Seed.sql の経路）
--   2026-09-22 に本番へ送られていたのはこの経路（supabase db reset の Seed.sql）
-- -----------------------------------------------------------------------------
\echo '--- case e-2: Vault 未登録 — postgres・クレーム無しの INSERT（Seed.sql の経路）も要求 0 件であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);

  BEGIN
    INSERT INTO public.messages (
      id, sender_id, receiver_id, sender_type, receiver_type, content
    ) VALUES (
      'c0de0922-0000-4000-8000-000000000022',
      'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
      'client', 'trainer', 'タグWebhookテスト: M2 C→T（postgres・クレーム無し）'
    );
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: (e-2) Vault 未登録で postgres のメッセージ INSERT が失敗した: % / %', SQLSTATE, SQLERRM;
  END;
END $$;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e-2) Vault 未登録なのに postgres・クレーム無しの INSERT（Seed.sql の経路）で要求が % 件積まれた（url: %）', v_cnt, v_urls;
  END IF;
  RAISE NOTICE 'OK: (e-2) Vault 未登録 — postgres・クレーム無しの INSERT（Seed.sql の経路）も要求 0 件';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e-3): secret_key だけ登録（project_url 未登録）
--   URL を組み立てられないので送らない。送ろうとすると url が NULL になり、
--   net.http_request_queue の NOT NULL 違反でメッセージの INSERT 自体が失敗する
-- -----------------------------------------------------------------------------
\echo '--- case e-3: secret_key だけ登録（project_url 未登録）— 顧客 C の INSERT は成功し、要求は 0 件であること'

DO $$
BEGIN
  PERFORM vault.create_secret('sb_secret_parse_tags_test_dummy', 'secret_key');
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content, image_urls, tags, is_edited
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000023',
    'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
    'client', 'trainer', 'タグWebhookテスト: M3 C→T（secret_key のみ）', '{}', '{}', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (e-3) project_url 未登録で顧客 C のメッセージ INSERT が失敗した（メッセージの保存は止めない想定）: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e-3) project_url 未登録なのに要求が % 件積まれた（url: %）', v_cnt, v_urls;
  END IF;
  RAISE NOTICE 'OK: (e-3) secret_key のみ — 顧客 C の INSERT は成功し、要求 0 件';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e-4): project_url 登録 + secret_key が空文字
--   空文字のキーは未登録と同じ扱い（apikey 無しの要求と同じで、関数側で 401 になるだけなので送らない）
-- -----------------------------------------------------------------------------
\echo '--- case e-4: project_url 登録 + secret_key が空文字 — 顧客 C の INSERT は成功し、要求は 0 件であること'

DO $$
BEGIN
  -- 予約 TLD（.invalid）で末尾 / 付き。(f) で URL の組み立て（末尾 / の除去）も確かめる
  PERFORM vault.create_secret('http://parse-tags-test.invalid/', 'project_url');
  PERFORM vault.update_secret(
    (SELECT s.id FROM vault.secrets s WHERE s.name = 'secret_key'),
    new_secret := ''
  );
  IF (SELECT s.decrypted_secret FROM vault.decrypted_secrets s WHERE s.name = 'secret_key') IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — (e-4) secret_key を空文字にできなかった';
  END IF;
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content, image_urls, tags, is_edited
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000024',
    'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
    'client', 'trainer', 'タグWebhookテスト: M4 C→T（secret_key が空文字）', '{}', '{}', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (e-4) secret_key が空文字で顧客 C のメッセージ INSERT が失敗した（メッセージの保存は止めない想定）: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e-4) secret_key が空文字なのに要求が % 件積まれた（url: %）', v_cnt, v_urls;
  END IF;
  RAISE NOTICE 'OK: (e-4) secret_key が空文字 — 顧客 C の INSERT は成功し、要求 0 件';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): Vault が揃っているとき / 顧客 C（authenticated）の INSERT
--   secret_key をダミー値にして、要求がちょうど 1 件・宛先 / ヘッダー / body が期待どおりで
--   あることを確かめる。
--   - url: project_url の末尾 / を除いて '/functions/v1/parse-message-tags' を付けたもの
--   - headers: ちょうど {Content-Type, apikey}。Authorization は無いこと（secret キーを Bearer で
--     送るとゲートウェイが JWT として弾く）。キー名の比較は照合順序に依存しないよう COLLATE "C"
--   - body: 現行（20260719000000）と同一のキー構成。デプロイ中に動いている旧 Edge Function が
--     record の各フィールドを使うため、キーの欠落も検出する
-- -----------------------------------------------------------------------------
\echo '--- case f: Vault あり — 顧客 C の INSERT で要求ちょうど 1 件（宛先 / apikey ヘッダー / body）'

DO $$
BEGIN
  PERFORM vault.update_secret(
    (SELECT s.id FROM vault.secrets s WHERE s.name = 'secret_key'),
    new_secret := 'sb_secret_parse_tags_test_dummy'
  );
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content, image_urls, tags, is_edited
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000025',
    'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
    'client', 'trainer', '#体重 70.5kg タグWebhookテスト: M5 C→T', '{}', '{}', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (f) Vault ありで顧客 C のメッセージ INSERT が失敗した: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before  bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt     int;
  v_req     record;
  v_body    jsonb;
  v_msg     record;
  v_keys    text[];
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (f) Vault ありの顧客 C の INSERT で要求が % 件（期待ちょうど 1 件）', v_cnt;
  END IF;

  SELECT q.method::text AS method, q.url, q.headers, q.body INTO v_req
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  v_body := convert_from(v_req.body, 'UTF8')::jsonb;

  SELECT m.id, m.sender_id, m.receiver_id, m.sender_type, m.receiver_type, m.content INTO v_msg
  FROM public.messages m
  WHERE m.id = 'c0de0922-0000-4000-8000-000000000025';

  -- 宛先
  IF v_req.method IS DISTINCT FROM 'POST' THEN
    RAISE EXCEPTION 'FAIL: (f) method が %（期待 POST）', v_req.method;
  END IF;
  IF v_req.url IS DISTINCT FROM 'http://parse-tags-test.invalid/functions/v1/parse-message-tags' THEN
    RAISE EXCEPTION 'FAIL: (f) url が %（期待 Vault の project_url から組み立てた http://parse-tags-test.invalid/functions/v1/parse-message-tags）', v_req.url;
  END IF;

  -- ヘッダー（値は FAIL メッセージに出さない）
  IF v_req.headers ->> 'apikey' IS DISTINCT FROM 'sb_secret_parse_tags_test_dummy' THEN
    RAISE EXCEPTION 'FAIL: (f) apikey ヘッダーが Vault の secret_key と一致しない（apikey ヘッダー %）',
      CASE WHEN v_req.headers ? 'apikey' THEN 'あり・値が不一致' ELSE 'なし' END;
  END IF;
  IF v_req.headers ->> 'Content-Type' IS DISTINCT FROM 'application/json' THEN
    RAISE EXCEPTION 'FAIL: (f) Content-Type ヘッダーが %（期待 application/json）', coalesce(v_req.headers ->> 'Content-Type', 'なし');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(v_req.headers) k WHERE lower(k) = 'authorization') THEN
    RAISE EXCEPTION 'FAIL: (f) Authorization ヘッダーが送られている（secret キーは apikey ヘッダーだけで送る）';
  END IF;
  SELECT array_agg(k ORDER BY k COLLATE "C") INTO v_keys FROM jsonb_object_keys(v_req.headers) k;
  IF v_keys IS DISTINCT FROM ARRAY['Content-Type', 'apikey'] THEN
    RAISE EXCEPTION 'FAIL: (f) ヘッダーのキー構成が %（期待 {Content-Type,apikey} ちょうど）', v_keys;
  END IF;

  -- body
  SELECT array_agg(k ORDER BY k COLLATE "C") INTO v_keys FROM jsonb_object_keys(v_body) k;
  IF v_keys IS DISTINCT FROM ARRAY['record', 'table', 'type'] THEN
    RAISE EXCEPTION 'FAIL: (f) body のキー構成が %（期待 {record,table,type}。INSERT では old_record を含まない）', v_keys;
  END IF;
  IF v_body ->> 'type' IS DISTINCT FROM 'INSERT' THEN
    RAISE EXCEPTION 'FAIL: (f) body.type が %（期待 INSERT）', v_body ->> 'type';
  END IF;
  IF v_body ->> 'table' IS DISTINCT FROM 'messages' THEN
    RAISE EXCEPTION 'FAIL: (f) body.table が %（期待 messages）', v_body ->> 'table';
  END IF;
  SELECT array_agg(k ORDER BY k COLLATE "C") INTO v_keys FROM jsonb_object_keys(v_body -> 'record') k;
  IF v_keys IS DISTINCT FROM ARRAY['content', 'created_at', 'id', 'image_urls', 'receiver_id',
                                   'receiver_type', 'sender_id', 'sender_type'] THEN
    RAISE EXCEPTION 'FAIL: (f) body.record のキー構成が %（期待 20260719000000 と同一の 8 キー）', v_keys;
  END IF;
  IF (v_body -> 'record' ->> 'id') IS DISTINCT FROM v_msg.id::text THEN
    RAISE EXCEPTION 'FAIL: (f) body.record.id が %（期待 INSERT した M5 の id %）', v_body -> 'record' ->> 'id', v_msg.id;
  END IF;
  IF (v_body -> 'record' ->> 'sender_id') IS DISTINCT FROM v_msg.sender_id::text
     OR (v_body -> 'record' ->> 'receiver_id') IS DISTINCT FROM v_msg.receiver_id::text THEN
    RAISE EXCEPTION 'FAIL: (f) body.record の sender_id / receiver_id が行と一致しない（% / %）',
      v_body -> 'record' ->> 'sender_id', v_body -> 'record' ->> 'receiver_id';
  END IF;
  IF (v_body -> 'record' ->> 'sender_type') IS DISTINCT FROM 'client'
     OR (v_body -> 'record' ->> 'receiver_type') IS DISTINCT FROM 'trainer' THEN
    RAISE EXCEPTION 'FAIL: (f) body.record の sender_type / receiver_type が % / %（期待 client / trainer）',
      v_body -> 'record' ->> 'sender_type', v_body -> 'record' ->> 'receiver_type';
  END IF;
  IF (v_body -> 'record' ->> 'content') IS DISTINCT FROM v_msg.content THEN
    RAISE EXCEPTION 'FAIL: (f) body.record.content が %（期待 %）', v_body -> 'record' ->> 'content', v_msg.content;
  END IF;
  IF position('sb_secret_parse_tags_test_dummy' IN v_body::text) > 0 THEN
    RAISE EXCEPTION 'FAIL: (f) body に secret キーが含まれている';
  END IF;

  RAISE NOTICE 'OK: (f) Vault あり — 要求 1 件（POST % / apikey ヘッダー = Vault の secret_key / Authorization なし / body.type=INSERT・record.id=M5）', v_req.url;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 送信者 C の content 編集（Mobile の editMessage と同じ列の UPDATE）
--   RLS「Users can edit own messages within 5 minutes」を通る（created_at はこのトランザクションの now()）。
--   on_message_update（AFTER UPDATE OF content）で要求ちょうど 1 件・type = 'UPDATE'・
--   old_record.content = 編集前の本文であること
-- -----------------------------------------------------------------------------
\echo '--- case g: 送信者 C の content 編集で要求ちょうど 1 件（type=UPDATE / old_record.content = 編集前）'

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.messages
  SET content = '#体重 70.2kg タグWebhookテスト: M5 編集後',
      tags = '{}',
      is_edited = true,
      edited_at = now()
  WHERE id = 'c0de0922-0000-4000-8000-000000000025';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: (g) 送信者 C の編集で % 行更新（期待 1 行。RLS で弾かれている）', v_rows;
  END IF;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_req    record;
  v_body   jsonb;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (g) 送信者 C の content 編集で要求が % 件（期待ちょうど 1 件）', v_cnt;
  END IF;

  SELECT q.url, q.headers, q.body INTO v_req
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  v_body := convert_from(v_req.body, 'UTF8')::jsonb;

  IF v_req.url IS DISTINCT FROM 'http://parse-tags-test.invalid/functions/v1/parse-message-tags' THEN
    RAISE EXCEPTION 'FAIL: (g) url が %', v_req.url;
  END IF;
  IF v_req.headers ->> 'apikey' IS DISTINCT FROM 'sb_secret_parse_tags_test_dummy' THEN
    RAISE EXCEPTION 'FAIL: (g) apikey ヘッダーが Vault の secret_key と一致しない';
  END IF;
  IF v_body ->> 'type' IS DISTINCT FROM 'UPDATE' THEN
    RAISE EXCEPTION 'FAIL: (g) body.type が %（期待 UPDATE）', v_body ->> 'type';
  END IF;
  IF (v_body -> 'record' ->> 'id') IS DISTINCT FROM 'c0de0922-0000-4000-8000-000000000025' THEN
    RAISE EXCEPTION 'FAIL: (g) body.record.id が %（期待 M5）', v_body -> 'record' ->> 'id';
  END IF;
  IF (v_body -> 'record' ->> 'content') IS DISTINCT FROM '#体重 70.2kg タグWebhookテスト: M5 編集後' THEN
    RAISE EXCEPTION 'FAIL: (g) body.record.content が %（期待 編集後の本文）', v_body -> 'record' ->> 'content';
  END IF;
  IF (v_body -> 'old_record' ->> 'content') IS DISTINCT FROM '#体重 70.5kg タグWebhookテスト: M5 C→T' THEN
    RAISE EXCEPTION 'FAIL: (g) body.old_record.content が %（期待 編集前の本文）', coalesce(v_body -> 'old_record' ->> 'content', 'NULL');
  END IF;
  IF NOT coalesce((v_body -> 'old_record') ? 'tags', false) THEN
    RAISE EXCEPTION 'FAIL: (g) body.old_record に tags が無い（現行の payload と互換でない）';
  END IF;

  RAISE NOTICE 'OK: (g) 送信者 C の content 編集 — 要求 1 件（type=UPDATE / old_record.content = 編集前の本文）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): 受信者 T の既読化（Web の markMessagesAsRead.ts と同じ read_at だけの UPDATE）
--   RLS「Receivers can mark messages as read」を通って 1 行更新されること（0 件が「更新できなかった
--   から」にならないよう行数と read_at を確かめる）。on_message_update は UPDATE OF content なので
--   発火せず、要求 0 件であること
-- -----------------------------------------------------------------------------
\echo '--- case h: 受信者 T の既読化（read_at だけの UPDATE）は要求 0 件であること'

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000001';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.messages
  SET read_at = now()
  WHERE id = 'c0de0922-0000-4000-8000-000000000025'
    AND receiver_id = 'c0de0922-0000-4000-8000-000000000001'
    AND read_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: (h) 受信者 T の既読化で % 行更新（期待 1 行。RLS で弾かれている）', v_rows;
  END IF;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (h) read_at だけの UPDATE で要求が % 件積まれた（url: %）', v_cnt, v_urls;
  END IF;
  IF (SELECT m.read_at FROM public.messages m WHERE m.id = 'c0de0922-0000-4000-8000-000000000025') IS NULL THEN
    RAISE EXCEPTION 'FAIL: (h) M5 の read_at が設定されていない';
  END IF;
  RAISE NOTICE 'OK: (h) 受信者 T の既読化（read_at だけの UPDATE）— 要求 0 件';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i): トレーナー T が送った INSERT
--   トリガーは送信者種別で絞らない（記録を作るかどうかは Edge Function が sender_type で判断し、
--   トレーナー → 顧客のメッセージでは受信者への通知を送る）。要求ちょうど 1 件であること
-- -----------------------------------------------------------------------------
\echo '--- case i: トレーナー T の INSERT でも要求ちょうど 1 件（record.sender_type = trainer）'

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000001';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000026',
    'c0de0922-0000-4000-8000-000000000001', 'c0de0922-0000-4000-8000-000000000011',
    'trainer', 'client', 'タグWebhookテスト: M6 T→C'
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (i) トレーナー T のメッセージ INSERT が失敗した: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_req    record;
  v_body   jsonb;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (i) トレーナー T の INSERT で要求が % 件（期待ちょうど 1 件）', v_cnt;
  END IF;

  SELECT q.url, q.headers, q.body INTO v_req
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  v_body := convert_from(v_req.body, 'UTF8')::jsonb;

  IF v_req.url IS DISTINCT FROM 'http://parse-tags-test.invalid/functions/v1/parse-message-tags' THEN
    RAISE EXCEPTION 'FAIL: (i) url が %', v_req.url;
  END IF;
  IF v_req.headers ->> 'apikey' IS DISTINCT FROM 'sb_secret_parse_tags_test_dummy' THEN
    RAISE EXCEPTION 'FAIL: (i) apikey ヘッダーが Vault の secret_key と一致しない';
  END IF;
  IF v_body ->> 'type' IS DISTINCT FROM 'INSERT' THEN
    RAISE EXCEPTION 'FAIL: (i) body.type が %（期待 INSERT）', v_body ->> 'type';
  END IF;
  IF (v_body -> 'record' ->> 'id') IS DISTINCT FROM 'c0de0922-0000-4000-8000-000000000026' THEN
    RAISE EXCEPTION 'FAIL: (i) body.record.id が %（期待 M6）', v_body -> 'record' ->> 'id';
  END IF;
  IF (v_body -> 'record' ->> 'sender_id') IS DISTINCT FROM 'c0de0922-0000-4000-8000-000000000001'
     OR (v_body -> 'record' ->> 'sender_type') IS DISTINCT FROM 'trainer' THEN
    RAISE EXCEPTION 'FAIL: (i) body.record の sender_id / sender_type が % / %（期待 T / trainer）',
      v_body -> 'record' ->> 'sender_id', v_body -> 'record' ->> 'sender_type';
  END IF;

  RAISE NOTICE 'OK: (i) トレーナー T の INSERT — 要求 1 件（sender_type=trainer）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(j): ロールバックされた INSERT は送られない
--   SAVEPOINT 内で顧客 C が INSERT すると要求が 1 件積まれる（トリガーが発火した証拠）が、
--   ROLLBACK TO SAVEPOINT の後はその要求もメッセージも見えなくなること。pg_net のワーカーは
--   コミット済みの行しか読まないので、アプリ側でロールバックされた書き込みは送信されない。
--   SAVEPOINT は postgres の状態で取る（ROLLBACK TO SAVEPOINT で SET LOCAL ROLE も巻き戻るため、
--   巻き戻った後が postgres になるように）
-- -----------------------------------------------------------------------------
\echo '--- case j: SAVEPOINT 内の INSERT は ROLLBACK TO SAVEPOINT 後に要求 0 件・メッセージも残らないこと'

DO $$
BEGIN
  PERFORM set_config('parse_tags_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
END $$;

SAVEPOINT parse_tags_test_j;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"c0de0922-0000-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'c0de0922-0000-4000-8000-000000000011';

DO $$
BEGIN
  INSERT INTO public.messages (
    id, sender_id, receiver_id, sender_type, receiver_type, content, image_urls, tags, is_edited
  ) VALUES (
    'c0de0922-0000-4000-8000-000000000027',
    'c0de0922-0000-4000-8000-000000000011', 'c0de0922-0000-4000-8000-000000000001',
    'client', 'trainer', 'タグWebhookテスト: M7 C→T（SAVEPOINT で取り消し）', '{}', '{}', false
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (j) SAVEPOINT 内の顧客 C のメッセージ INSERT が失敗した: % / %', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

-- 取り消す前: 要求が 1 件積まれていること（トリガーが発火したことの確認）
DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (j) 前提崩れ — SAVEPOINT 内の INSERT で要求が % 件（期待 1 件。取り消し前）', v_cnt;
  END IF;
END $$;

ROLLBACK TO SAVEPOINT parse_tags_test_j;

DO $$
DECLARE
  v_before bigint := current_setting('parse_tags_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'FAIL: (j) 前提崩れ — ROLLBACK TO SAVEPOINT 後のロールが %（期待 postgres）', current_user;
  END IF;
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (j) ROLLBACK TO SAVEPOINT 後も要求が % 件残っている（url: %）', v_cnt, v_urls;
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages m WHERE m.id = 'c0de0922-0000-4000-8000-000000000027') THEN
    RAISE EXCEPTION 'FAIL: (j) ROLLBACK TO SAVEPOINT 後も M7 が残っている';
  END IF;
  RAISE NOTICE 'OK: (j) SAVEPOINT 内の INSERT は取り消し前に要求 1 件、ROLLBACK TO SAVEPOINT 後は要求 0 件・メッセージなし';
END $$;

ROLLBACK;

\echo ''
DO $$
BEGIN
  RAISE NOTICE 'ALL PARSE MESSAGE TAGS WEBHOOK TESTS PASSED';
END $$;
