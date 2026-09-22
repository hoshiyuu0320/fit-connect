-- =============================================================================
-- 関数 9 本の search_path 固定 / EXECUTE 最小権限化 / can_edit_message の送信者条件 テスト
-- （fix/function-search-path-hardening、フェーズ5.10）
--
-- 仕様出典: docs/tasks/IMPLEMENTATION_TASKS.md フェーズ5 5.10
--
-- 対象: public.can_edit_message(uuid)                        SECURITY DEFINER（本体を書き換え）
--       public.update_updated_at_column()                     トリガー関数
--       public.update_sessions_updated_at()                   トリガー関数
--       public.update_trainer_schedules_updated_at()          トリガー関数
--       public.call_parse_message_tags()                      トリガー関数（本体・SECURITY 属性は #89 のもの。下記参照）
--       public.enforce_client_limit()                         トリガー関数・SECURITY DEFINER
--       public.enforce_client_note_session_consistency()      トリガー関数・SECURITY DEFINER
--       public.get_last_messages_for_trainer(uuid)            LANGUAGE sql STABLE（INVOKER）
--       public.get_unread_counts_for_trainer(uuid)            LANGUAGE sql STABLE（INVOKER）
--
-- 検証対象の migration:
--   supabase/migrations/20260923000000_harden_function_search_path.sql
--     （9 本とも SET search_path = '' / トリガー関数 6 本の EXECUTE をオーナーのみに /
--       can_edit_message に送信者条件を足して EXECUTE を authenticated のみに）
--
-- call_parse_message_tags の扱い（#89 は develop にマージ済み）:
--   #89（フェーズ5.7、supabase/migrations/20260922000100_secure_parse_message_tags_webhook.sql）が
--   call_parse_message_tags を作り直しており、develop の本体は常に #89 のもの（送信先 URL と apikey を
--   Vault の project_url / secret_key から読む / Vault が揃っていなければ送らず WARNING
--   'PARSE_MESSAGE_TAGS_SKIPPED: ...' / SECURITY DEFINER / search_path 空文字 / EXECUTE はオーナーのみ）。
--   本 migration はこの関数の本体と SECURITY 属性には触れず、ALTER で search_path = '' を、REVOKE で
--   オーナーのみの EXECUTE を（#89 と同じ値で）明示するだけ。そこで本テストは:
--   - 本 migration が保証するものだけを固定する: proconfig = {search_path=""} / owner postgres /
--     ACL の grantee がちょうど {postgres}（PUBLIC なし）/ anon・authenticated・service_role の EXECUTE が
--     すべて f / トリガー on_message_insert・on_message_update の存在と有効 / (a)(b)(c) の直接呼び出しが
--     GRANT 層で拒否 / (d) のオーナーの直接呼び出しが 0A000
--   - md5(prosrc)・prosecdef・送信先 URL の形・ヘッダー・payload の構成は固定しない。これらは #89 の
--     持ち物で、supabase/tests/parse_message_tags_webhook_test.sql が検証する
--   - 「EXECUTE を剥がしてもメッセージの Webhook トリガーは発火し続ける」ことは (i) で確かめる。
--     #89 の本体は Vault が空だと何もキューに入れないため、parse_message_tags_webhook_test.sql と同じく
--     既存の Vault シークレットを退避したうえで、トランザクション内でダミーの project_url / secret_key を
--     登録してから検査する（下記「Webhook に関する安全性」）。検査するのは、キューの行の url が
--     '/functions/v1/parse-message-tags' で終わること、body の type と record.id という最小限の事実だけ
--
-- 是正前（リモート）は 9 本とも PUBLIC / anon / authenticated / service_role に EXECUTE が
-- 付いており、7 本は search_path 未設定、enforce_* の 2 本は search_path = public, pg_temp
-- だった（call_parse_message_tags はその後 #89 で search_path '' / オーナーのみに是正済み）。
-- can_edit_message は anon を含む誰でも、任意のメッセージ ID について「作成から 5 分以内か」を
-- 知ることができた。本テストは是正後の状態と、既存の呼び出し経路（トリガーの発火 / Mobile の
-- editMessage / Web の RPC 2 本）が壊れていないことを固定する自己完結テスト
-- （definer_functions_privileges_test.sql のパターン踏襲）。
--
-- 是正後の EXECUTE マトリクス（has_function_privilege）と呼び出し元:
--   関数                                     anon  authenticated  service_role  呼び出し元
--   can_edit_message                          ×         ○              ×        Mobile の editMessage（自分の送信メッセージ）
--   update_updated_at_column                  ×         ×              ×        トリガー set_updated_at 系（11 テーブル）
--   update_sessions_updated_at                ×         ×              ×        トリガー（sessions）
--   update_trainer_schedules_updated_at       ×         ×              ×        トリガー（trainer_schedules）
--   call_parse_message_tags                   ×         ×              ×        トリガー（messages の INSERT / UPDATE OF content）
--   enforce_client_limit                      ×         ×              ×        トリガー（clients）
--   enforce_client_note_session_consistency   ×         ×              ×        トリガー（client_notes）
--   get_last_messages_for_trainer             ○         ○              ○        Web（ログイン中のトレーナー）※ ACL は変更しない
--   get_unread_counts_for_trainer             ○         ○              ○        Web（ログイン中のトレーナー）※ ACL は変更しない
--   9 本とも proconfig = {search_path=""} / owner postgres。
--   本 migration は SECURITY 属性を変えない（can_edit_message は SECURITY DEFINER のまま作り直す）。
--   本テストが固定する SECURITY 属性: DEFINER = can_edit_message / enforce_client_limit /
--   enforce_client_note_session_consistency、INVOKER = updated_at 系 3 本と get_* の 2 本。
--   call_parse_message_tags（#89 で SECURITY DEFINER）は固定しない。
--   ACL の grantee: トリガー関数 6 本 = {postgres} だけ / can_edit_message = {authenticated, postgres}
--   （いずれも PUBLIC なし）/ get_* 2 本 = PUBLIC + {anon, authenticated, postgres, service_role}
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/function_search_path_privileges_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL FUNCTION SEARCH_PATH PRIVILEGE TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データ（Vault の退避・ダミーのシークレットを含む）は BEGIN...ROLLBACK 内で作成され、
--   DB には一切残らない
-- - seed.sql のデータと混ざらないよう、件数・状態の検証は必ず試験用の行
--   （UUID が 5ea10000-0922-4000-8000- で始まる行）に限定する
-- - 拒否の層を SQLSTATE / SQLERRM で区別する（期待と違う層で拒否されたら FAIL）:
--     GRANT 層            : 42501 かつ SQLERRM LIKE 'permission denied for function %'  … (a) (b) (c-1) (c-2)
--     トリガー専用の制限  : 0A000 かつ SQLERRM = 'trigger functions can only be called as triggers' … (d)
--   PostgreSQL は関数呼び出しの EXECUTE を先に確認し、トリガー関数の「トリガー以外からの
--   呼び出し禁止」はその後の実行時に確認する。したがって (a)(b)(c) で 0A000 が返ったら
--   「EXECUTE が残っている」ことを意味し、FAIL にする。(d) はオーナー（postgres）の直接呼び出しが
--   0A000 に達すること（= オーナーは EXECUTE を持ち、(a)(b)(c) の拒否が ACL によること）の対照
-- - 業務制約のトリガーが投げる例外（CLIENT_LIMIT_REACHED / NOTE_SESSION_MISMATCH、いずれも
--   P0001）は SQLSTATE と SQLERRM の両方で確認し、それ以外のエラー（RLS 違反・関係が見つからない
--   等）は FAIL として報告する。とくに本体が無修飾のテーブル参照を含むと、空の search_path の
--   下では 42P01（relation does not exist）になるため、(g)(h) はそれを FAIL として検出する
-- - updated_at の検証は「トランザクション開始時刻 = now()」との一致で行う（now() はトランザクション
--   内で一定）。試験データの updated_at は 1 日前（メッセージは作成時刻）にしておき、トリガーが
--   発火しなければ一致しないようにする
-- - #90（フェーズ5.8、20260922000200_column_write_guards.sql）のガード用トリガー
--   （clients_guard_protected_columns / messages_guard_insert / messages_guard_update と clients の
--   列 GRANT）の下で動くように書いている: 試験データは postgres で投入し、authenticated の INSERT /
--   UPDATE はアプリと同じ正規の操作だけにする（顧客 → 担当トレーナー宛ての送信 / Mobile の
--   editMessage と同じ列（content, tags, is_edited, edited_at）の編集 / Web の既読化と同じ read_at
--   だけの更新 / clients の INSERT は client_id, trainer_id, name だけ）。既存顧客の trainer_id の
--   付け替えは service_role で行い、authenticated から created_at を指定することはしない
--
-- Webhook（call_parse_message_tags → parse-message-tags）に関する安全性:
--   - 本番の URL は一切使わない。setup で既存の Vault シークレット project_url / secret_key を
--     別名へ退避し（開発者のローカル Vault に登録済みでも、トリガーがそれを読まないように）、
--     (i) の直前に、トランザクション内でダミーの project_url = 'http://searchpath-test.invalid'
--     （RFC 2606 の予約 TLD .invalid。名前解決されない）と secret_key = ダミー値を登録する。
--     Vault の退避・登録はどちらも ROLLBACK で元に戻る
--   - net.http_post は net.http_request_queue へ行を INSERT するだけで、pg_net のワーカーが
--     送信するのはコミット済みの行だけである。本テストは全体を BEGIN...ROLLBACK で包むため、
--     (i) でキューに入る行はコミットされず、ワーカーからは見えないまま ROLLBACK で破棄される
--     （psql が途中で異常終了した場合も、接続の切断でトランザクションは中止・破棄される）。
--     したがって本テストから HTTP 要求が送られることは無い（宛先もダミー）
--   - 二重の安全策として、試験データの投入中は on_message_insert をトランザクション内で無効化し、
--     Webhook そのものを検証する (i) の直前にだけ有効化する（ALTER TABLE もトランザクショナルなので
--     ROLLBACK で元に戻る）。(i) の手前で試験用メッセージを参照するキューの行が 0 行であることも確認する
--   - (i) で見つけたキューの行の url が本番のホスト（viribpvnpgtgtmeulcmx）を含んでいたら FAIL にする
--     （宛先の形そのものは固定しないが、本テストの要求が本番を向いていないことだけは確かめる）
--   - ALTER TABLE は messages / clients に SHARE ROW EXCLUSIVE ロックを取るため、本テスト実行中の
--     わずかな間は他セッションの messages / clients への書込みが待たされる
--
-- 検証ケース（「GRANT 層」「トリガー専用の制限」は上記 SQLSTATE / SQLERRM による区別）:
--   setup 9 関数が存在すること。検証に使うトリガー 17 本が存在し、有効（tgenabled = 'O'）で、
--         期待どおりの関数を呼ぶこと。既存の Vault シークレット project_url / secret_key の退避
--   (a)   anon（JWT クレーム無し）: EXECUTE を剥がした 7 本（トリガー関数 6 本 + can_edit_message）が
--         すべて 42501 / GRANT 層
--   (b)   anon ロール + 顧客 C1 の JWT クレーム（クレーム付き anon）: 同じ 7 本が 42501 / GRANT 層。
--         can_edit_message(M_FRESH) は本文上 C1 本人の送信メッセージとして true を返す呼び出しなので、
--         ここは anon の EXECUTE 剥奪でしか PASS しない（docs/tasks/lessons.md「クレーム付き anon」）
--   (c-1) authenticated（C1）: トリガー関数 6 本の直接呼び出しが 42501 / GRANT 層（0A000 ではない）
--   (c-2) service_role: トリガー関数 6 本と can_edit_message が 42501 / GRANT 層
--   (d)   オーナー（postgres・クレーム無し）: トリガー関数 6 本の直接呼び出しが 0A000
--         （trigger functions can only be called as triggers）= オーナーは EXECUTE を保持し、
--         (a)(b)(c) が ACL で拒否されていることの対照
--   (e)   can_edit_message の判定（送信者条件）: C1 の M_FRESH = true / M_OLD（10 分前）= false /
--         M_T2C（C1 は受信者）= false / 存在しない ID = false / NULL = false、トレーナー T の
--         M_FRESH（T は受信者）= false / M_T2C（T が送信者）= true、他人トレーナー T2 の M_FRESH = false、
--         postgres（クレーム無し = auth.uid() NULL）の M_FRESH = false。
--         あわせて RLS との整合: C1 が false の M_OLD を editMessage と同じ列で UPDATE すると 0 行
--         （true の側 = 自分の新しいメッセージを UPDATE できることは (i) の編集で確認する）
--   (f)   updated_at トリガーは EXECUTE を持たない呼び出し元でも発火する:
--         T の sessions S1 / service_role の sessions S3 / T の trainer_schedules / C1 の weight_records /
--         T の trainers を UPDATE → 1 行ずつ更新され、updated_at が now() になる
--   (g)   enforce_client_limit（SECURITY DEFINER・空の search_path）: Free の T（顧客 2 名）へ
--         C3 が自分の clients 行を INSERT → 成功（3 名）/ C4 が INSERT → CLIENT_LIMIT_REACHED
--         （C4 は RLS で T の顧客を 1 行も見られない = 定義者権限で public.clients を数えている）/
--         service_role が T2 の顧客 D を T へ付け替え → CLIENT_LIMIT_REACHED /
--         対照: service_role が D の name や同じ trainer_id を UPDATE → 成功
--   (h)   enforce_client_note_session_consistency（SECURITY DEFINER・空の search_path）:
--         T が (C1, T, S1) のノートを INSERT → 成功 / (C1, T, S2) を INSERT → NOTE_SESSION_MISMATCH
--         （T は RLS で S2 を見られない）/ 成功したノートの session_id を S2 へ UPDATE →
--         NOTE_SESSION_MISMATCH / service_role の (C1, T, S2) INSERT → NOTE_SESSION_MISMATCH
--   (i)   Webhook トリガー（call_parse_message_tags・authenticated に EXECUTE なし）: ダミーの Vault を
--         登録し、on_message_insert / on_message_update を有効にしたまま、
--         C1 の送信（INSERT）→ 1 行成功し、net.http_request_queue にちょうど 1 行
--         （url が '/functions/v1/parse-message-tags' で終わる / body.type = INSERT / body.record.id = 新しい ID）/
--         C1 の編集（editMessage と同じ列の content の UPDATE）→ 1 行成功し、キューにちょうど 1 行追加
--         （body.type = UPDATE / body.record.id = 同じ ID）/
--         受信者 T の既読化（read_at だけ）→ 1 行ずつ成功し、キューの行は増えず、messages.updated_at が now()
--   (j)   Web の RPC 2 本（空の search_path・INVOKER）: T の get_last_messages_for_trainer(T) が
--         C1 との会話の最新メッセージを、get_unread_counts_for_trainer(T) が C1 → T の未読数を返す /
--         T2 が p_trainer_id = T で呼ぶと 0 行（messages / clients の RLS）/ anon（クレーム無し）も 0 行
--   (k)   定義の固定（カタログ検査）: 9 本の proconfig = {search_path=""} / owner postgres /
--         ACL の grantee 集合 / PUBLIC エントリの有無 / anon・authenticated・service_role の EXECUTE
--         マトリクス。call_parse_message_tags 以外の 8 本はさらに prosecdef と md5(prosrc)
--         （ALTER の 7 本は本体不変、can_edit_message は新しい本体）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 前提確認 1: 対象の 9 関数が存在すること
--   存在しない関数を各ケースで直接呼ぶと 42883 の素のエラーで落ちて原因が分かりにくいため、
--   ここで明示的に FAIL させる
-- -----------------------------------------------------------------------------
\echo '--- setup: 前提確認（対象の 9 関数が存在すること）'

DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.can_edit_message(uuid)',
    'public.update_updated_at_column()',
    'public.update_sessions_updated_at()',
    'public.update_trainer_schedules_updated_at()',
    'public.call_parse_message_tags()',
    'public.enforce_client_limit()',
    'public.enforce_client_note_session_consistency()',
    'public.get_last_messages_for_trainer(uuid)',
    'public.get_unread_counts_for_trainer(uuid)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION 'FAIL: 前提崩れ — % が存在しない', v_sig;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 対象の 9 関数が存在する';
END $$;

-- -----------------------------------------------------------------------------
-- 前提確認 2: トリガー関数 6 本を呼ぶトリガーが存在し、有効で、期待どおりの関数を呼ぶこと
--   (f)(g)(h)(i) は「EXECUTE を剥がしてもトリガーは発火する」ことを検証するため、
--   トリガー自体が無い・無効・別の関数を呼んでいると、それらのケースの結論が変わってしまう。
--   migration ヘッダーの一覧（update_updated_at_column は 11 テーブル）をすべて確認する。
--   試験データ投入で on_message_insert / enforce_client_limit_trigger を一時的に無効化する前に
--   確認する（コミット済みの無効化はここで検出し、後段の ENABLE で覆い隠さない）
-- -----------------------------------------------------------------------------
\echo '--- setup: 前提確認（トリガー 17 本が存在し、有効で、期待どおりの関数を呼ぶこと）'

DO $$
DECLARE
  r         record;
  v_trg     record;
  v_checked int := 0;
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      ('clients',                  'enforce_client_limit_trigger',                    'public.enforce_client_limit()'),
      ('client_notes',             'enforce_client_note_session_consistency_trigger', 'public.enforce_client_note_session_consistency()'),
      ('messages',                 'on_message_insert',                               'public.call_parse_message_tags()'),
      ('messages',                 'on_message_update',                               'public.call_parse_message_tags()'),
      ('sessions',                 'trigger_update_sessions_updated_at',              'public.update_sessions_updated_at()'),
      ('trainer_schedules',        'trigger_update_trainer_schedules_updated_at',     'public.update_trainer_schedules_updated_at()'),
      ('messages',                 'set_updated_at',                                  'public.update_updated_at_column()'),
      ('weight_records',           'set_updated_at',                                  'public.update_updated_at_column()'),
      ('exercise_records',         'set_updated_at',                                  'public.update_updated_at_column()'),
      ('meal_records',             'set_updated_at',                                  'public.update_updated_at_column()'),
      ('sleep_records',            'set_updated_at',                                  'public.update_updated_at_column()'),
      ('trainers',                 'set_updated_at_trainers',                         'public.update_updated_at_column()'),
      ('alerts',                   'set_updated_at_alerts',                           'public.update_updated_at_column()'),
      ('app_config',               'set_updated_at_app_config',                       'public.update_updated_at_column()'),
      ('notification_preferences', 'set_updated_at_notification_preferences',         'public.update_updated_at_column()'),
      ('payments',                 'set_updated_at_payments',                         'public.update_updated_at_column()'),
      ('trainer_billing',          'set_updated_at_trainer_billing',                  'public.update_updated_at_column()')
    ) AS t(tbl, tgname, fn)
  LOOP
    SELECT tg.tgenabled, tg.tgfoid
      INTO v_trg
    FROM pg_trigger tg
    WHERE tg.tgrelid = to_regclass('public.' || r.tbl)
      AND tg.tgname = r.tgname
      AND NOT tg.tgisinternal;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'FAIL: 前提崩れ — トリガー %.% が存在しない', r.tbl, r.tgname;
    END IF;
    IF v_trg.tgfoid IS DISTINCT FROM to_regprocedure(r.fn)::oid THEN
      RAISE EXCEPTION 'FAIL: 前提崩れ — トリガー %.% が % を呼んでいない（実際 %）',
        r.tbl, r.tgname, r.fn, v_trg.tgfoid::regprocedure;
    END IF;
    IF v_trg.tgenabled IS DISTINCT FROM 'O' THEN
      RAISE EXCEPTION 'FAIL: 前提崩れ — トリガー %.% が有効でない（tgenabled=%、期待 O）', r.tbl, r.tgname, v_trg.tgenabled;
    END IF;
    v_checked := v_checked + 1;
  END LOOP;
  RAISE NOTICE 'OK: トリガー % 本が存在し、有効で、期待どおりの関数を呼ぶ', v_checked;
END $$;

-- -----------------------------------------------------------------------------
-- 既存の Vault シークレットの退避（postgres として実行）
--   call_parse_message_tags（#89 の本体）は Vault の project_url / secret_key が揃っているときだけ
--   Webhook をキューに入れる。開発者のローカル Vault に登録済みでも、本テストのトリガーがそれ
--   （たとえば本番の URL）を読まないよう、2 つを別名へ改名しておく（parse_message_tags_webhook_test.sql
--   と同じ方法）。改名はトランザクション内なので ROLLBACK で戻る。改名後の名前にはシークレットの
--   id を含める（vault.secrets.name は一意索引付き）。
--   (i) の直前に、ダミーの project_url / secret_key をトランザクション内で登録する
-- -----------------------------------------------------------------------------
\echo '--- setup: 既存の Vault シークレット project_url / secret_key を別名へ退避（ROLLBACK で戻る）'

DO $$
DECLARE
  r       record;
  v_moved int := 0;
BEGIN
  FOR r IN
    SELECT s.id, s.name
    FROM vault.secrets s
    WHERE s.name IN ('project_url', 'secret_key')
  LOOP
    PERFORM vault.update_secret(
      r.id,
      new_name := r.name || '__moved_by_function_search_path_test__' || r.id::text
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
--   trainer  T      : 5ea10000-0922-4000-8000-000000000001（Free・trial_ends_at NULL → 顧客上限 3 名。顧客 C1・C2）
--   trainer  T2     : 5ea10000-0922-4000-8000-000000000002（Business。顧客 D。C1 とは無関係）
--   client   C1     : 5ea10000-0922-4000-8000-000000000011（T の顧客）
--   client   C2     : 5ea10000-0922-4000-8000-000000000012（T の顧客）
--   user     C3     : 5ea10000-0922-4000-8000-000000000013（auth.users のみ。(g) で自分の clients 行を作る）
--   user     C4     : 5ea10000-0922-4000-8000-000000000014（auth.users のみ。(g) で上限に当たる）
--   client   D      : 5ea10000-0922-4000-8000-000000000015（T2 の顧客）
--   session  S1     : 5ea10000-0922-4000-8000-000000000021（T / C1。updated_at 1 日前）
--   session  S2     : 5ea10000-0922-4000-8000-000000000022（T2 / D。updated_at 1 日前）
--   session  S3     : 5ea10000-0922-4000-8000-000000000023（T / C2。updated_at 1 日前。(f) の service_role 用）
--   schedule SCH    : 5ea10000-0922-4000-8000-000000000031（T / 月曜。updated_at 1 日前）
--   weight   W      : 5ea10000-0922-4000-8000-000000000041（C1。updated_at 1 日前）
--   message  M_FRESH: 5ea10000-0922-4000-8000-000000000051（C1 → T / 1 分前 / 未読）
--   message  M_OLD  : 5ea10000-0922-4000-8000-000000000052（C1 → T / 10 分前 / 未読）
--   message  M_T2C  : 5ea10000-0922-4000-8000-000000000053（T → C1 / 2 分前 / 未読）
--   message  M_HOOK : 5ea10000-0922-4000-8000-000000000054（(i) で C1 が送信する。作成時刻は既定の now()）
--   message  X      : 5ea10000-0922-4000-8000-000000000059（作成しない。(e) で存在しない ID として使う）
--   note     N1     : 5ea10000-0922-4000-8000-000000000061（(h) で T が作る。C1 / S1）
--   note     N2/N3  : 5ea10000-0922-4000-8000-000000000062 / 63（(h) の拒否される INSERT 用）
--   T の trainers.updated_at も 1 日前にしておく。
--   M_FRESH / M_T2C を「今」ではなく 1〜2 分前にしているのは、(i) で作る M_HOOK（作成時刻 = now()）と
--   作成時刻が同じにならないようにするため（(j) の get_last_messages_for_trainer は DISTINCT ON で
--   相手ごとの最新 1 件を選ぶので、同時刻だと結果が決まらない）。いずれも 5 分以内なので、
--   本文から送信者条件を落とした can_edit_message は true を返す（(e) の判別力は変わらない）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T・T2 / client C1・C2・D / user C3・C4 / session S1〜S3 / schedule / weight / message M_FRESH・M_OLD・M_T2C)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('5ea10000-0922-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-t2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000011', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-c1@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000012', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-c2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000013', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-c3@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000014', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-c4@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('5ea10000-0922-4000-8000-000000000015', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'searchpath-test-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

-- trial_ends_at の既定は now() + 14 日（= Pro トライアル中で上限 10 名）なので、T は明示的に NULL にして
-- Free（上限 3 名）にする
INSERT INTO public.trainers (id, name, email, subscription_plan, trial_ends_at, updated_at) VALUES
  ('5ea10000-0922-4000-8000-000000000001', 'SEARCHPATHテスト トレーナーT',
   'searchpath-test-t@example.com', 'free', NULL, now() - interval '1 day'),
  ('5ea10000-0922-4000-8000-000000000002', 'SEARCHPATHテスト トレーナーT2',
   'searchpath-test-t2@example.com', 'business', NULL, now() - interval '1 day');

-- 試験データの投入を検証対象の enforce_client_limit に依存させないため、clients の INSERT の間だけ
-- トリガーを無効化する（コミット済みの無効化は前提確認 2 で検出済み。ALTER TABLE はトランザクショナル
-- なので ROLLBACK で元に戻る）。本体が壊れていた場合に、試験データの投入ではなく (g) で FAIL として
-- 検出するため
ALTER TABLE public.clients DISABLE TRIGGER enforce_client_limit_trigger;

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  ('5ea10000-0922-4000-8000-000000000011', 'SEARCHPATHテスト顧客C1',
   '5ea10000-0922-4000-8000-000000000001'),
  ('5ea10000-0922-4000-8000-000000000012', 'SEARCHPATHテスト顧客C2',
   '5ea10000-0922-4000-8000-000000000001'),
  ('5ea10000-0922-4000-8000-000000000015', 'SEARCHPATHテスト顧客D',
   '5ea10000-0922-4000-8000-000000000002');

ALTER TABLE public.clients ENABLE TRIGGER enforce_client_limit_trigger;

-- updated_at は INSERT では BEFORE UPDATE トリガーが発火しないので、明示した 1 日前のまま入る
INSERT INTO public.sessions (
  id, trainer_id, client_id, session_date, duration_minutes, status, session_type, updated_at
) VALUES
  ('5ea10000-0922-4000-8000-000000000021',
   '5ea10000-0922-4000-8000-000000000001', '5ea10000-0922-4000-8000-000000000011',
   now() + interval '1 day', 60, 'scheduled', 'SEARCHPATHテスト: S1 T/C1', now() - interval '1 day'),
  ('5ea10000-0922-4000-8000-000000000022',
   '5ea10000-0922-4000-8000-000000000002', '5ea10000-0922-4000-8000-000000000015',
   now() + interval '1 day', 60, 'scheduled', 'SEARCHPATHテスト: S2 T2/D', now() - interval '1 day'),
  ('5ea10000-0922-4000-8000-000000000023',
   '5ea10000-0922-4000-8000-000000000001', '5ea10000-0922-4000-8000-000000000012',
   now() + interval '2 day', 60, 'scheduled', 'SEARCHPATHテスト: S3 T/C2', now() - interval '1 day');

INSERT INTO public.trainer_schedules (
  id, trainer_id, day_of_week, start_time, end_time, is_available, updated_at
) VALUES
  ('5ea10000-0922-4000-8000-000000000031', '5ea10000-0922-4000-8000-000000000001',
   1, '09:00', '18:00', true, now() - interval '1 day');

INSERT INTO public.weight_records (id, client_id, weight, recorded_at, source, updated_at) VALUES
  ('5ea10000-0922-4000-8000-000000000041', '5ea10000-0922-4000-8000-000000000011',
   70, now() - interval '1 day', 'manual', now() - interval '1 day');

-- messages の on_message_insert トリガー（call_parse_message_tags）は、Vault の project_url / secret_key が
-- 揃っていれば pg_net 経由で parse-message-tags を呼ぶ。Vault は setup で退避済み（この時点では未登録）
-- なので WARNING が出るだけでキューには入らず、入ってもコミットされない限りワーカーは送信しない
-- （ROLLBACK で破棄される）が、二重の安全策としてトランザクション内で無効化する
-- （ヘッダーの「Webhook に関する安全性」参照）。(i) の直前で有効化する。
-- set_updated_at（BEFORE UPDATE）と on_message_update（AFTER UPDATE OF content）は無効化しない
ALTER TABLE public.messages DISABLE TRIGGER on_message_insert;

INSERT INTO public.messages (
  id, sender_id, receiver_id, sender_type, receiver_type, content, created_at, updated_at
) VALUES
  ('5ea10000-0922-4000-8000-000000000051',
   '5ea10000-0922-4000-8000-000000000011', '5ea10000-0922-4000-8000-000000000001',
   'client', 'trainer', 'SEARCHPATHテスト: M_FRESH C1→T',
   now() - interval '1 minute', now() - interval '1 minute'),
  ('5ea10000-0922-4000-8000-000000000052',
   '5ea10000-0922-4000-8000-000000000011', '5ea10000-0922-4000-8000-000000000001',
   'client', 'trainer', 'SEARCHPATHテスト: M_OLD C1→T',
   now() - interval '10 minutes', now() - interval '10 minutes'),
  ('5ea10000-0922-4000-8000-000000000053',
   '5ea10000-0922-4000-8000-000000000001', '5ea10000-0922-4000-8000-000000000011',
   'trainer', 'client', 'SEARCHPATHテスト: M_T2C T→C1',
   now() - interval '2 minutes', now() - interval '2 minutes');

-- -----------------------------------------------------------------------------
-- ケース(a): anon（JWT クレーム無し）は EXECUTE を剥がした 7 本をどれも実行できない（GRANT 層で拒否）
--   PostgREST の /rest/v1/rpc/<関数名> は公開 anon キーだけで呼べる。トリガー関数は直接呼んでも
--   0A000 で失敗するだけだが、ACL の段階で閉じていることを確認する（Advisor 0028 の解消）。
--   can_edit_message は、このセッション（クレーム無し = auth.uid() NULL）では本文が false を返すだけ
--   なので、ここで 42501 になるのは anon の EXECUTE が剥奪されている場合だけ。
--   呼び出しは関数ごとに PERFORM と同じ「SELECT public.関数(...)」を動的に実行する
--   （EXECUTE の確認は静的な PERFORM と同じく実行開始時に行われる）。
--   ※ 先行ケースのクレームが残らないよう、両形式を空にしてからロールを切り替える
-- -----------------------------------------------------------------------------
\echo '--- case a: anon（クレーム無し）から 7 関数とも EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
DECLARE
  r record;
BEGIN
  -- 前提確認: anon ロールで、クレームが残っていないこと
  IF current_user IS DISTINCT FROM 'anon' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 anon / NULL）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'update_updated_at_column()',                'SELECT public.update_updated_at_column()'),
      (2, 'update_sessions_updated_at()',              'SELECT public.update_sessions_updated_at()'),
      (3, 'update_trainer_schedules_updated_at()',     'SELECT public.update_trainer_schedules_updated_at()'),
      (4, 'call_parse_message_tags()',                 'SELECT public.call_parse_message_tags()'),
      (5, 'enforce_client_limit()',                    'SELECT public.enforce_client_limit()'),
      (6, 'enforce_client_note_session_consistency()', 'SELECT public.enforce_client_note_session_consistency()'),
      (7, 'can_edit_message(M_FRESH)',                 'SELECT public.can_edit_message(''5ea10000-0922-4000-8000-000000000051''::uuid)')
    ) AS t(ord, label, stmt)
    ORDER BY t.ord
  LOOP
    BEGIN
      EXECUTE r.stmt;
      RAISE EXCEPTION 'FAIL: anon（クレーム無し）が % を EXECUTE できてしまった', r.label;
    EXCEPTION
      WHEN insufficient_privilege THEN
        IF SQLERRM NOT LIKE 'permission denied for function %' THEN
          RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ % の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', r.label, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: anon（クレーム無し）→ % は 42501（%）', r.label, SQLERRM;
      WHEN feature_not_supported THEN
        RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ % が ACL を通過し、トリガー専用の制限（0A000）に達した（EXECUTE が残っている: %）', r.label, SQLERRM;
    END;
  END LOOP;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(b): anon ロール + 顧客 C1 の JWT クレームでも 7 本とも EXECUTE できない
--   auth.uid() が C1 を返す状態のまま DB ロールだけ anon にし、GRANT 層で拒否されることを
--   直接検証する（docs/tasks/lessons.md「クレーム付き anon」）。
--   can_edit_message(M_FRESH) は、本文上は「C1 本人が 1 分前に送ったメッセージ」なので true を返す
--   呼び出しである。ここで 42501 になるのは anon の EXECUTE が剥奪されている場合だけ
--   （migration セクション 1「anon は GRANT 層で止める」）
-- -----------------------------------------------------------------------------
\echo '--- case b: anon ロール + 顧客(C1) クレームでも 7 関数とも EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';
SET LOCAL ROLE anon;

DO $$
DECLARE
  r record;
BEGIN
  -- 前提確認: auth.uid() が顧客 C1 を返している（クレームが効いている）こと。
  -- ここが NULL だと (a) と同じケースに退化してしまう
  IF current_user IS DISTINCT FROM 'anon'
     OR auth.uid() IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000011'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 anon / 顧客C1 の UUID）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'update_updated_at_column()',                'SELECT public.update_updated_at_column()'),
      (2, 'update_sessions_updated_at()',              'SELECT public.update_sessions_updated_at()'),
      (3, 'update_trainer_schedules_updated_at()',     'SELECT public.update_trainer_schedules_updated_at()'),
      (4, 'call_parse_message_tags()',                 'SELECT public.call_parse_message_tags()'),
      (5, 'enforce_client_limit()',                    'SELECT public.enforce_client_limit()'),
      (6, 'enforce_client_note_session_consistency()', 'SELECT public.enforce_client_note_session_consistency()'),
      (7, 'can_edit_message(M_FRESH)',                 'SELECT public.can_edit_message(''5ea10000-0922-4000-8000-000000000051''::uuid)')
    ) AS t(ord, label, stmt)
    ORDER BY t.ord
  LOOP
    BEGIN
      EXECUTE r.stmt;
      RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C1) クレームで % を EXECUTE できてしまった（anon の EXECUTE が残っている）', r.label;
    EXCEPTION
      WHEN insufficient_privilege THEN
        IF SQLERRM NOT LIKE 'permission denied for function %' THEN
          RAISE EXCEPTION 'FAIL: anon + 顧客(C1) クレーム → % の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', r.label, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: anon + 顧客(C1) クレーム → % は 42501（%）', r.label, SQLERRM;
      WHEN feature_not_supported THEN
        RAISE EXCEPTION 'FAIL: anon + 顧客(C1) クレーム → % が ACL を通過し、トリガー専用の制限（0A000）に達した（EXECUTE が残っている: %）', r.label, SQLERRM;
    END;
  END LOOP;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(c-1): authenticated（顧客 C1）はトリガー関数 6 本を直接実行できない（GRANT 層で拒否）
--   トリガー関数は authenticated からも EXECUTE を剥がしている（Advisor 0029 を出さないため。
--   トリガーの発火は EXECUTE を確認しないので不要）。42501 ではなく 0A000 が返った場合は
--   authenticated に EXECUTE が残っているので FAIL
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式 request.jwt.claim.sub から
--   解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case c-1: authenticated（顧客 C1）からトリガー関数 6 本とも EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';

DO $$
DECLARE
  r record;
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated'
     OR auth.uid() IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000011'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 authenticated / 顧客C1 の UUID）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'update_updated_at_column()',                'SELECT public.update_updated_at_column()'),
      (2, 'update_sessions_updated_at()',              'SELECT public.update_sessions_updated_at()'),
      (3, 'update_trainer_schedules_updated_at()',     'SELECT public.update_trainer_schedules_updated_at()'),
      (4, 'call_parse_message_tags()',                 'SELECT public.call_parse_message_tags()'),
      (5, 'enforce_client_limit()',                    'SELECT public.enforce_client_limit()'),
      (6, 'enforce_client_note_session_consistency()', 'SELECT public.enforce_client_note_session_consistency()')
    ) AS t(ord, label, stmt)
    ORDER BY t.ord
  LOOP
    BEGIN
      EXECUTE r.stmt;
      RAISE EXCEPTION 'FAIL: authenticated（C1）が % を EXECUTE できてしまった', r.label;
    EXCEPTION
      WHEN insufficient_privilege THEN
        IF SQLERRM NOT LIKE 'permission denied for function %' THEN
          RAISE EXCEPTION 'FAIL: authenticated（C1）→ % の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', r.label, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: authenticated（C1）→ % は 42501（%）', r.label, SQLERRM;
      WHEN feature_not_supported THEN
        RAISE EXCEPTION 'FAIL: authenticated（C1）→ % が ACL を通過し、トリガー専用の制限（0A000）に達した（authenticated に EXECUTE が残っている: %）', r.label, SQLERRM;
    END;
  END LOOP;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(c-2): service_role はトリガー関数 6 本も can_edit_message も実行できない（GRANT 層で拒否）
--   service_role キーの JWT は sub を持たないため auth.uid() は NULL。can_edit_message は
--   本文上 false を返すだけなので、ここで 42501 になるのは service_role の EXECUTE が剥奪されて
--   いる場合だけ（service_role から呼ぶ箇所は無い: migration セクション 1）
-- -----------------------------------------------------------------------------
\echo '--- case c-2: service_role からトリガー関数 6 本と can_edit_message が EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  r record;
BEGIN
  IF current_user IS DISTINCT FROM 'service_role' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 service_role / NULL）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'update_updated_at_column()',                'SELECT public.update_updated_at_column()'),
      (2, 'update_sessions_updated_at()',              'SELECT public.update_sessions_updated_at()'),
      (3, 'update_trainer_schedules_updated_at()',     'SELECT public.update_trainer_schedules_updated_at()'),
      (4, 'call_parse_message_tags()',                 'SELECT public.call_parse_message_tags()'),
      (5, 'enforce_client_limit()',                    'SELECT public.enforce_client_limit()'),
      (6, 'enforce_client_note_session_consistency()', 'SELECT public.enforce_client_note_session_consistency()'),
      (7, 'can_edit_message(M_FRESH)',                 'SELECT public.can_edit_message(''5ea10000-0922-4000-8000-000000000051''::uuid)')
    ) AS t(ord, label, stmt)
    ORDER BY t.ord
  LOOP
    BEGIN
      EXECUTE r.stmt;
      RAISE EXCEPTION 'FAIL: service_role が % を EXECUTE できてしまった', r.label;
    EXCEPTION
      WHEN insufficient_privilege THEN
        IF SQLERRM NOT LIKE 'permission denied for function %' THEN
          RAISE EXCEPTION 'FAIL: service_role → % の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', r.label, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: service_role → % は 42501（%）', r.label, SQLERRM;
      WHEN feature_not_supported THEN
        RAISE EXCEPTION 'FAIL: service_role → % が ACL を通過し、トリガー専用の制限（0A000）に達した（service_role に EXECUTE が残っている: %）', r.label, SQLERRM;
    END;
  END LOOP;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(d): オーナー（postgres・クレーム無し）の対照
--   オーナー postgres は ACL の postgres=X/postgres で EXECUTE を持つので、直接呼ぶと ACL を通過し、
--   plpgsql の「トリガー関数はトリガーとしてしか呼べない」制限（0A000 feature_not_supported、
--   'trigger functions can only be called as triggers'）で失敗する。
--   これで (a)(b)(c) の 42501 が「トリガー関数だから」ではなく ACL による拒否であることと、
--   オーナーが EXECUTE を失っていない（今後の migration の CREATE TRIGGER が通る）ことを確かめる。
--   postgres はこのスタックでは superuser ではない（rolsuper = false）ため、ACL の確認は省略されない
-- -----------------------------------------------------------------------------
\echo '--- case d: オーナー（postgres）のトリガー関数 6 本の直接呼び出しが 0A000（トリガー専用の制限）であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  r record;
BEGIN
  IF current_user IS DISTINCT FROM 'postgres' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 postgres / NULL）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'update_updated_at_column()',                'SELECT public.update_updated_at_column()'),
      (2, 'update_sessions_updated_at()',              'SELECT public.update_sessions_updated_at()'),
      (3, 'update_trainer_schedules_updated_at()',     'SELECT public.update_trainer_schedules_updated_at()'),
      (4, 'call_parse_message_tags()',                 'SELECT public.call_parse_message_tags()'),
      (5, 'enforce_client_limit()',                    'SELECT public.enforce_client_limit()'),
      (6, 'enforce_client_note_session_consistency()', 'SELECT public.enforce_client_note_session_consistency()')
    ) AS t(ord, label, stmt)
    ORDER BY t.ord
  LOOP
    BEGIN
      EXECUTE r.stmt;
      RAISE EXCEPTION 'FAIL: postgres が % を直接実行でき、エラーにならなかった（期待 0A000）', r.label;
    EXCEPTION
      WHEN feature_not_supported THEN
        IF SQLERRM IS DISTINCT FROM 'trigger functions can only be called as triggers' THEN
          RAISE EXCEPTION 'FAIL: postgres → % の 0A000 のメッセージが想定外（実際 %）', r.label, SQLERRM;
        END IF;
        RAISE NOTICE 'OK: postgres（オーナー）→ % は ACL を通過して 0A000（%）', r.label, SQLERRM;
      WHEN insufficient_privilege THEN
        RAISE EXCEPTION 'FAIL: オーナー postgres が % の EXECUTE を持っていない（%）', r.label, SQLERRM;
      WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN
          RAISE;
        END IF;
        RAISE EXCEPTION 'FAIL: postgres → % が想定外のエラー（期待 0A000 / 実際 % %）', r.label, SQLSTATE, SQLERRM;
    END;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): can_edit_message の判定（送信者条件 m.sender_id = auth.uid()）
--   本体は「呼び出し元自身の送信メッセージで、作成から 5 分以内」のときだけ true。
--   送信者以外・存在しない ID・5 分経過・auth.uid() NULL はいずれも false で区別しない。
--   SECURITY DEFINER（messages の RLS をバイパス）なので、false になるのは本文の送信者条件による。
--   本文から送信者条件を落とすと、受信者（C1 の M_T2C / T の M_FRESH）・無関係な T2・postgres が
--   5 分以内のメッセージについて true になり、ここで FAIL する。
--   search_path = '' の下でも public.messages に到達できること（C1 の M_FRESH = true）も兼ねる。
--   RLS との整合: false の M_OLD を C1 が Mobile の editMessage と同じ列で UPDATE すると 0 行
--   （ポリシー "Users can edit own messages within 5 minutes"）。true の側（自分の新しいメッセージは
--   UPDATE できる）は (i) の M_HOOK の編集で確認する（Webhook の行を (i) にまとめるため）
-- -----------------------------------------------------------------------------
\echo '--- case e-1: 顧客(C1) の can_edit_message が M_FRESH=true / M_OLD・M_T2C・存在しない ID・NULL=false であること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';

DO $$
DECLARE
  b      boolean;
  v_rows int;
BEGIN
  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000051');
  IF b IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(M_FRESH) が %（期待 true = 自分の送信・1 分前）', coalesce(b::text, 'NULL');
  END IF;

  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000052');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(M_OLD) が %（期待 false = 10 分前）', coalesce(b::text, 'NULL');
  END IF;

  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000053');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(M_T2C) が %（期待 false = C1 は受信者。送信者条件が効いていない）', coalesce(b::text, 'NULL');
  END IF;

  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000059');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(存在しない ID) が %（期待 false）', coalesce(b::text, 'NULL');
  END IF;

  b := public.can_edit_message(NULL::uuid);
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(NULL) が %（期待 false）', coalesce(b::text, 'NULL');
  END IF;

  -- RLS との整合: false の M_OLD は editMessage と同じ列の UPDATE でも 0 行（5 分ポリシー）
  UPDATE public.messages
     SET content = 'SEARCHPATHテスト: M_OLD 編集の試み',
         tags = ARRAY['searchpath']::text[],
         is_edited = true,
         edited_at = now()
   WHERE id = '5ea10000-0922-4000-8000-000000000052';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 0 THEN
    RAISE EXCEPTION 'FAIL: C1 が 10 分前の M_OLD を UPDATE できてしまった（% 行。RLS の 5 分ポリシーと不整合）', v_rows;
  END IF;

  RAISE NOTICE 'OK: C1 の can_edit_message は M_FRESH=true / M_OLD=false / M_T2C（受信者）=false / 存在しない ID=false / NULL=false、M_OLD の UPDATE は 0 行';
END $$;

\echo '--- case e-2: トレーナー(T) の can_edit_message が M_FRESH（受信者）=false / M_T2C（送信者）=true であること'

SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000001';

DO $$
DECLARE
  b boolean;
BEGIN
  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000051');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: T の can_edit_message(M_FRESH) が %（期待 false = T は受信者。送信者条件が効いていない）', coalesce(b::text, 'NULL');
  END IF;

  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000053');
  IF b IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: T の can_edit_message(M_T2C) が %（期待 true = T の送信・2 分前）', coalesce(b::text, 'NULL');
  END IF;

  RAISE NOTICE 'OK: T の can_edit_message は M_FRESH（受信者）=false / M_T2C（自分の送信）=true';
END $$;

\echo '--- case e-3: 他人トレーナー(T2) の can_edit_message(M_FRESH) が false であること'

SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000002","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000002';

DO $$
DECLARE
  b boolean;
BEGIN
  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000051');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: T2 の can_edit_message(M_FRESH) が %（期待 false = 無関係なユーザー。他人のメッセージの作成時刻が漏れる）', coalesce(b::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: 他人トレーナー(T2) の can_edit_message(M_FRESH) = false';
END $$;

RESET ROLE;

\echo '--- case e-4: postgres（クレーム無し = auth.uid() NULL）の can_edit_message(M_FRESH) が false であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  b boolean;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — クレームが残っている（auth.uid()=%）', auth.uid();
  END IF;

  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000051');
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: postgres（クレーム無し）の can_edit_message(M_FRESH) が %（期待 false = auth.uid() NULL はどの行にも一致しない）', coalesce(b::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: postgres（クレーム無し）の can_edit_message(M_FRESH) = false';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): updated_at 更新トリガーは EXECUTE を持たない呼び出し元の UPDATE でも発火する
--   PostgreSQL はトリガー関数の EXECUTE を CREATE TRIGGER の時にしか確認しない。トリガー関数 3 本
--   （update_sessions_updated_at / update_trainer_schedules_updated_at / update_updated_at_column）の
--   EXECUTE を剥がした後も、authenticated / service_role の UPDATE で updated_at が now() になること。
--   試験データの updated_at は 1 日前なので、トリガーが発火しなければ now() と一致しない。
--   service_role は S1 ではなく S3 で確かめる（S1 は T の UPDATE で既に now() になっており、
--   postgres で 1 日前に戻そうとしてもその UPDATE 自体でトリガーが発火して now() になるため）。
--   確認は RLS の影響を受けない postgres で行う
-- -----------------------------------------------------------------------------
\echo '--- case f: authenticated / service_role の UPDATE で updated_at トリガーが発火すること（sessions / trainer_schedules / weight_records / trainers）'

DO $$
DECLARE
  v_cnt int;
BEGIN
  -- 前提確認: 検証する 5 行の updated_at がまだ 1 日前であること
  SELECT
      (SELECT count(*) FROM public.sessions s
        WHERE s.id IN ('5ea10000-0922-4000-8000-000000000021', '5ea10000-0922-4000-8000-000000000023')
          AND s.updated_at = now() - interval '1 day')
    + (SELECT count(*) FROM public.trainer_schedules ts
        WHERE ts.id = '5ea10000-0922-4000-8000-000000000031' AND ts.updated_at = now() - interval '1 day')
    + (SELECT count(*) FROM public.weight_records w
        WHERE w.id = '5ea10000-0922-4000-8000-000000000041' AND w.updated_at = now() - interval '1 day')
    + (SELECT count(*) FROM public.trainers t
        WHERE t.id = '5ea10000-0922-4000-8000-000000000001' AND t.updated_at = now() - interval '1 day')
    INTO v_cnt;
  IF v_cnt <> 5 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — updated_at が 1 日前の試験行が % 行（期待 5 行: S1 / S3 / SCH / W / T）', v_cnt;
  END IF;
END $$;

-- f-1: トレーナー T が自分のセッション S1 のメモを更新（Web のスケジュール画面と同じ経路）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000001';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.sessions
     SET memo = 'SEARCHPATHテスト: T のメモ'
   WHERE id = '5ea10000-0922-4000-8000-000000000021';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の sessions S1 の UPDATE が % 行（期待 1 行）', v_rows;
  END IF;

  -- f-3: T が自分の稼働スケジュールを更新
  UPDATE public.trainer_schedules
     SET is_available = false
   WHERE id = '5ea10000-0922-4000-8000-000000000031';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の trainer_schedules の UPDATE が % 行（期待 1 行）', v_rows;
  END IF;

  -- f-5: T が自分のプロフィール（trainers.name）を更新
  UPDATE public.trainers
     SET name = 'SEARCHPATHテスト トレーナーT（更新）'
   WHERE id = '5ea10000-0922-4000-8000-000000000001';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の trainers の UPDATE が % 行（期待 1 行）', v_rows;
  END IF;
END $$;

-- f-4: 顧客 C1 が自分の体重記録のメモを更新（Mobile の体重記録編集と同じ経路）
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.weight_records
     SET notes = 'SEARCHPATHテスト: C1 のメモ'
   WHERE id = '5ea10000-0922-4000-8000-000000000041';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: C1 の weight_records の UPDATE が % 行（期待 1 行）', v_rows;
  END IF;
END $$;

RESET ROLE;

-- f-2: service_role（Web の API Route / Edge Function 相当）が S3 のメモを更新
SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.sessions
     SET memo = 'SEARCHPATHテスト: service_role のメモ'
   WHERE id = '5ea10000-0922-4000-8000-000000000023';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の sessions S3 の UPDATE が % 行（期待 1 行）', v_rows;
  END IF;
END $$;

RESET ROLE;

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_ts timestamptz;
BEGIN
  SELECT s.updated_at INTO v_ts FROM public.sessions s WHERE s.id = '5ea10000-0922-4000-8000-000000000021';
  IF v_ts IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: T の UPDATE 後の sessions S1.updated_at が %（期待 now() = %。trigger_update_sessions_updated_at が発火していない）', v_ts, now();
  END IF;

  SELECT s.updated_at INTO v_ts FROM public.sessions s WHERE s.id = '5ea10000-0922-4000-8000-000000000023';
  IF v_ts IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: service_role の UPDATE 後の sessions S3.updated_at が %（期待 now() = %。trigger_update_sessions_updated_at が発火していない）', v_ts, now();
  END IF;

  SELECT ts.updated_at INTO v_ts FROM public.trainer_schedules ts WHERE ts.id = '5ea10000-0922-4000-8000-000000000031';
  IF v_ts IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: T の UPDATE 後の trainer_schedules.updated_at が %（期待 now() = %。trigger_update_trainer_schedules_updated_at が発火していない）', v_ts, now();
  END IF;

  SELECT w.updated_at INTO v_ts FROM public.weight_records w WHERE w.id = '5ea10000-0922-4000-8000-000000000041';
  IF v_ts IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: C1 の UPDATE 後の weight_records.updated_at が %（期待 now() = %。set_updated_at が発火していない）', v_ts, now();
  END IF;

  SELECT t.updated_at INTO v_ts FROM public.trainers t WHERE t.id = '5ea10000-0922-4000-8000-000000000001';
  IF v_ts IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: T の UPDATE 後の trainers.updated_at が %（期待 now() = %。set_updated_at_trainers が発火していない）', v_ts, now();
  END IF;

  RAISE NOTICE 'OK: EXECUTE を持たない authenticated（T / C1）と service_role の UPDATE で、sessions（S1・S3）/ trainer_schedules / weight_records / trainers の updated_at が now() に更新された';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): enforce_client_limit（SECURITY DEFINER のトリガー関数・空の search_path・EXECUTE なし）
--   T は Free（trial_ends_at NULL）なので上限 3 名。既存の顧客は C1・C2 の 2 名。
--   - C3 が自分の clients 行（client_id = C3, trainer_id = T）を INSERT → 成功（T は 3 名）
--     （Mobile の顧客登録と同じ経路。列は client_id / trainer_id / name だけ）
--   - C4 が同様に INSERT → CLIENT_LIMIT_REACHED（P0001）。C4 は RLS で T の顧客を 1 行も
--     見られないので、上限に当たるのはトリガーが定義者権限で public.clients を数えている場合だけ
--   - service_role が T2 の顧客 D を T へ付け替え（UPDATE OF trainer_id）→ CLIENT_LIMIT_REACHED
--   - 対照: service_role の D の name 更新 / 同じ trainer_id の UPDATE（トリガーは発火するが
--     担当替えではないので素通し）→ 成功
--   本体に無修飾のテーブル参照があると、空の search_path では 42P01 になる。成功を期待する操作の
--   エラーも、拒否を期待する操作の想定外のエラーも FAIL として報告する
-- -----------------------------------------------------------------------------
\echo '--- case g-1: 顧客(C3) の clients INSERT（T の 3 人目）が成功すること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000013","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000013';

DO $$
DECLARE
  v_rows int;
BEGIN
  BEGIN
    INSERT INTO public.clients (client_id, trainer_id, name)
    VALUES ('5ea10000-0922-4000-8000-000000000013',
            '5ea10000-0922-4000-8000-000000000001',
            'SEARCHPATHテスト顧客C3');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: C3 の clients INSERT（T の 3 人目 = 上限内）が失敗した（% %）', SQLSTATE, SQLERRM;
  END;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: C3 の clients INSERT が % 行（期待 1 行）', v_rows;
  END IF;
  RAISE NOTICE 'OK: C3 の clients INSERT（T の 3 人目）は成功';
END $$;

\echo '--- case g-2: 顧客(C4) の clients INSERT（T の 4 人目）が CLIENT_LIMIT_REACHED で拒否されること'

SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000014","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000014';

DO $$
DECLARE
  v_cnt   int;
  v_state text;
  v_msg   text;
BEGIN
  -- 前提確認: C4 は RLS で T の顧客を 1 行も見られないこと
  SELECT count(*) INTO v_cnt
  FROM public.clients c
  WHERE c.trainer_id = '5ea10000-0922-4000-8000-000000000001';
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — C4 から T の顧客が % 行見える（期待 0 行）', v_cnt;
  END IF;

  BEGIN
    INSERT INTO public.clients (client_id, trainer_id, name)
    VALUES ('5ea10000-0922-4000-8000-000000000014',
            '5ea10000-0922-4000-8000-000000000001',
            'SEARCHPATHテスト顧客C4');
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;

  IF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: C4 の clients INSERT（Free の T の 4 人目）が拒否されなかった（enforce_client_limit が効いていない）';
  END IF;
  IF v_state IS DISTINCT FROM 'P0001' OR v_msg IS DISTINCT FROM 'CLIENT_LIMIT_REACHED' THEN
    RAISE EXCEPTION 'FAIL: C4 の clients INSERT の拒否が想定外（期待 P0001 CLIENT_LIMIT_REACHED / 実際 % %）', v_state, v_msg;
  END IF;
  RAISE NOTICE 'OK: C4 の clients INSERT は % %（C4 からは T の顧客が見えない = 定義者権限で数えている）', v_state, v_msg;
END $$;

RESET ROLE;

\echo '--- case g-3: service_role の顧客(D) の T への付け替えが CLIENT_LIMIT_REACHED で拒否され、担当替えでない UPDATE は成功すること'

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_rows  int;
  v_state text;
  v_msg   text;
BEGIN
  BEGIN
    UPDATE public.clients
       SET trainer_id = '5ea10000-0922-4000-8000-000000000001'
     WHERE client_id = '5ea10000-0922-4000-8000-000000000015';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;

  IF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: service_role の D の T への付け替え（T の 4 人目）が拒否されなかった';
  END IF;
  IF v_state IS DISTINCT FROM 'P0001' OR v_msg IS DISTINCT FROM 'CLIENT_LIMIT_REACHED' THEN
    RAISE EXCEPTION 'FAIL: service_role の D の付け替えの拒否が想定外（期待 P0001 CLIENT_LIMIT_REACHED / 実際 % %）', v_state, v_msg;
  END IF;

  -- 対照 1: 担当替えを伴わない name の更新
  BEGIN
    UPDATE public.clients
       SET name = 'SEARCHPATHテスト顧客D（更新）'
     WHERE client_id = '5ea10000-0922-4000-8000-000000000015';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: service_role の D の name 更新が失敗した（% %）', SQLSTATE, SQLERRM;
  END;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の D の name 更新が % 行（期待 1 行）', v_rows;
  END IF;

  -- 対照 2: trainer_id を同じ値で UPDATE（UPDATE OF trainer_id でトリガーは発火するが、担当替えではないので素通し）
  BEGIN
    UPDATE public.clients
       SET trainer_id = '5ea10000-0922-4000-8000-000000000002'
     WHERE client_id = '5ea10000-0922-4000-8000-000000000015';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: service_role の D の同じ trainer_id での UPDATE が失敗した（% %）', SQLSTATE, SQLERRM;
  END;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の D の同じ trainer_id での UPDATE が % 行（期待 1 行）', v_rows;
  END IF;

  RAISE NOTICE 'OK: service_role の D の T への付け替えは % %、name 更新・同じ trainer_id の UPDATE は成功', v_state, v_msg;
END $$;

RESET ROLE;

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_ids uuid[];
  v_d   uuid;
BEGIN
  SELECT coalesce(array_agg(c.client_id ORDER BY c.client_id), '{}') INTO v_ids
  FROM public.clients c
  WHERE c.trainer_id = '5ea10000-0922-4000-8000-000000000001';
  IF v_ids <> ARRAY['5ea10000-0922-4000-8000-000000000011',
                    '5ea10000-0922-4000-8000-000000000012',
                    '5ea10000-0922-4000-8000-000000000013']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (g) 後の T の顧客が %（期待 C1・C2・C3 の 3 名）', v_ids;
  END IF;

  SELECT c.trainer_id INTO v_d FROM public.clients c WHERE c.client_id = '5ea10000-0922-4000-8000-000000000015';
  IF v_d IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000002'::uuid THEN
    RAISE EXCEPTION 'FAIL: (g) 後の D の担当トレーナーが %（期待 T2 のまま）', v_d;
  END IF;
  RAISE NOTICE 'OK: (g) 後の T の顧客は C1・C2・C3 の 3 名、D は T2 の担当のまま';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): enforce_client_note_session_consistency（SECURITY DEFINER のトリガー関数・空の search_path・EXECUTE なし）
--   - T が (C1, T, S1) のノート N1 を INSERT → 成功（Web のカルテ保存と同じ経路）
--   - T が (C1, T, S2) を INSERT → NOTE_SESSION_MISMATCH（P0001）。S2 は T2 / D のセッションで、
--     T は RLS で S2 を見られないため、拒否されるのはトリガーが定義者権限で public.sessions を
--     読めている場合だけ
--   - T が N1 の session_id を S2 へ UPDATE → NOTE_SESSION_MISMATCH（UPDATE でも発火する）
--   - service_role の (C1, T, S2) INSERT → NOTE_SESSION_MISMATCH
-- -----------------------------------------------------------------------------
\echo '--- case h: カルテの session_id 整合性トリガーが authenticated / service_role の INSERT・UPDATE で働くこと'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000001';

DO $$
DECLARE
  v_cnt   int;
  v_rows  int;
  v_state text;
  v_msg   text;
BEGIN
  -- 前提確認: T は RLS で S2 を見られないこと
  SELECT count(*) INTO v_cnt FROM public.sessions s WHERE s.id = '5ea10000-0922-4000-8000-000000000022';
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — T から S2（T2 のセッション）が見える（% 行）', v_cnt;
  END IF;

  -- h-1: 正しい紐づけ（C1 / T / S1）
  BEGIN
    INSERT INTO public.client_notes (id, client_id, trainer_id, title, content, session_id)
    VALUES ('5ea10000-0922-4000-8000-000000000061',
            '5ea10000-0922-4000-8000-000000000011',
            '5ea10000-0922-4000-8000-000000000001',
            'SEARCHPATHテスト: S1 のカルテ', '',
            '5ea10000-0922-4000-8000-000000000021');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: T の (C1, T, S1) のノート INSERT が失敗した（% %）', SQLSTATE, SQLERRM;
  END;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の (C1, T, S1) のノート INSERT が % 行（期待 1 行）', v_rows;
  END IF;

  -- h-2: 他トレーナーのセッション S2 を指定した INSERT
  v_state := NULL; v_msg := NULL;
  BEGIN
    INSERT INTO public.client_notes (id, client_id, trainer_id, title, content, session_id)
    VALUES ('5ea10000-0922-4000-8000-000000000062',
            '5ea10000-0922-4000-8000-000000000011',
            '5ea10000-0922-4000-8000-000000000001',
            'SEARCHPATHテスト: S2 を指定したカルテ', '',
            '5ea10000-0922-4000-8000-000000000022');
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: T の (C1, T, S2) のノート INSERT が拒否されなかった（enforce_client_note_session_consistency が効いていない）';
  END IF;
  IF v_state IS DISTINCT FROM 'P0001' OR v_msg IS DISTINCT FROM 'NOTE_SESSION_MISMATCH' THEN
    RAISE EXCEPTION 'FAIL: T の (C1, T, S2) のノート INSERT の拒否が想定外（期待 P0001 NOTE_SESSION_MISMATCH / 実際 % %）', v_state, v_msg;
  END IF;

  -- h-3: 正しく作ったノートの session_id を S2 へ付け替える UPDATE
  v_state := NULL; v_msg := NULL;
  BEGIN
    UPDATE public.client_notes
       SET session_id = '5ea10000-0922-4000-8000-000000000022'
     WHERE id = '5ea10000-0922-4000-8000-000000000061';
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: T の N1 の session_id を S2 へ付け替える UPDATE が拒否されなかった';
  END IF;
  IF v_state IS DISTINCT FROM 'P0001' OR v_msg IS DISTINCT FROM 'NOTE_SESSION_MISMATCH' THEN
    RAISE EXCEPTION 'FAIL: T の N1 の session_id 付け替えの拒否が想定外（期待 P0001 NOTE_SESSION_MISMATCH / 実際 % %）', v_state, v_msg;
  END IF;

  RAISE NOTICE 'OK: T の (C1, T, S1) の INSERT は成功、(C1, T, S2) の INSERT と N1 の S2 への付け替えは NOTE_SESSION_MISMATCH';
END $$;

RESET ROLE;

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_state text;
  v_msg   text;
BEGIN
  -- h-4: service_role の (C1, T, S2) INSERT
  BEGIN
    INSERT INTO public.client_notes (id, client_id, trainer_id, title, content, session_id)
    VALUES ('5ea10000-0922-4000-8000-000000000063',
            '5ea10000-0922-4000-8000-000000000011',
            '5ea10000-0922-4000-8000-000000000001',
            'SEARCHPATHテスト: service_role の S2 指定', '',
            '5ea10000-0922-4000-8000-000000000022');
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS NULL THEN
    RAISE EXCEPTION 'FAIL: service_role の (C1, T, S2) のノート INSERT が拒否されなかった';
  END IF;
  IF v_state IS DISTINCT FROM 'P0001' OR v_msg IS DISTINCT FROM 'NOTE_SESSION_MISMATCH' THEN
    RAISE EXCEPTION 'FAIL: service_role の (C1, T, S2) のノート INSERT の拒否が想定外（期待 P0001 NOTE_SESSION_MISMATCH / 実際 % %）', v_state, v_msg;
  END IF;
  RAISE NOTICE 'OK: service_role の (C1, T, S2) のノート INSERT は % %', v_state, v_msg;
END $$;

RESET ROLE;

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_ids uuid[];
  v_sid uuid;
BEGIN
  SELECT coalesce(array_agg(n.id ORDER BY n.id), '{}') INTO v_ids
  FROM public.client_notes n
  WHERE n.id IN ('5ea10000-0922-4000-8000-000000000061',
                 '5ea10000-0922-4000-8000-000000000062',
                 '5ea10000-0922-4000-8000-000000000063');
  IF v_ids <> ARRAY['5ea10000-0922-4000-8000-000000000061']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (h) 後に存在する試験用ノートが %（期待 N1 のみ）', v_ids;
  END IF;

  SELECT n.session_id INTO v_sid FROM public.client_notes n WHERE n.id = '5ea10000-0922-4000-8000-000000000061';
  IF v_sid IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000021'::uuid THEN
    RAISE EXCEPTION 'FAIL: (h) 後の N1 の session_id が %（期待 S1 のまま）', coalesce(v_sid::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: (h) 後の試験用ノートは N1（S1 紐づけ）のみ';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i): メッセージの Webhook トリガー（call_parse_message_tags・authenticated に EXECUTE なし）
--   PostgreSQL はトリガー関数の EXECUTE を CREATE TRIGGER の時にしか確認しない。本 migration が
--   call_parse_message_tags の EXECUTE をオーナーだけにしても、authenticated の送信・編集でトリガーは
--   従来どおり発火し、Webhook がキューに入ることを確かめる。
--   call_parse_message_tags の本体は #89 のもの（Vault の project_url / secret_key が揃っているときだけ
--   net.http_post でキューに入れる）なので、parse_message_tags_webhook_test.sql と同じく、Vault を
--   退避した状態（setup）からトランザクション内でダミーの project_url / secret_key を登録してから検査する:
--     project_url = 'http://searchpath-test.invalid'（予約 TLD。本番の URL は使わない）
--     secret_key  = 'sb_secret_searchpath_test_dummy'（ダミー値）
--   Vault の登録もキューの行もコミットされず、ROLLBACK で破棄される。何も送信されない
--   （ヘッダーの「Webhook に関する安全性」参照）。
--   検査するのは次の最小限の事実だけ（URL の組み立て方・ヘッダー・payload の他のキーは #89 の持ち物で、
--   parse_message_tags_webhook_test.sql が検証する）:
--   - C1 の送信（INSERT、C1 → 担当トレーナー T）→ 1 行成功し、キューにちょうど 1 行:
--     url が '/functions/v1/parse-message-tags' で終わる / body.type = 'INSERT' / body.record.id = M_HOOK
--   - C1 の編集（Mobile の editMessage と同じ: can_edit_message → content, tags, is_edited, edited_at の
--     UPDATE）→ 1 行成功し、キューにちょうど 1 行追加: body.type = 'UPDATE' / body.record.id = M_HOOK
--     （あわせて (e) の RLS との整合の true 側: 自分の新しいメッセージは UPDATE できる）
--   - 受信者 T の既読化（Web の markMessagesAsRead と同じく read_at だけ）→ 1 行ずつ成功し、キューの行は
--     増えない（on_message_update は UPDATE OF content）。set_updated_at（update_updated_at_column）が
--     発火し、10 分前の M_OLD の updated_at が now() になる
--   要求の数え方は parse_message_tags_webhook_test.sql と同じ: 各ステップの直前に net.http_request_queue の
--   max(id) を控え（トランザクション内の設定値 searchpath_test.q_before）、ステップ後に id がそれより
--   大きい行を送信先に関係なく数える。body は bytea なので convert_from(body, 'UTF8')::jsonb で読む。
--   件数の検査は postgres に戻してから行う
-- -----------------------------------------------------------------------------
\echo '--- case i: EXECUTE を持たない authenticated の送信・編集で Webhook がキューに入り、既読化では入らないこと（ダミーの Vault）'

ALTER TABLE public.messages ENABLE TRIGGER on_message_insert;

-- i-0: 前提確認とダミーの Vault 登録（postgres）
DO $$
DECLARE
  v_cnt int;
BEGIN
  -- on_message_insert / on_message_update が有効であること
  -- （試験データ投入中に無効化した on_message_insert が直前の ENABLE で戻っていること）
  SELECT count(*) INTO v_cnt
  FROM pg_trigger tg
  WHERE tg.tgrelid = 'public.messages'::regclass
    AND tg.tgname IN ('on_message_insert', 'on_message_update')
    AND tg.tgfoid = 'public.call_parse_message_tags()'::regprocedure
    AND tg.tgenabled = 'O';
  IF v_cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — (i) の開始時点で有効な on_message_insert / on_message_update が % 本（期待 2 本）', v_cnt;
  END IF;

  -- 送信・編集する authenticated が call_parse_message_tags の EXECUTE を持たないこと
  -- （持っていると「EXECUTE なしでも発火する」の検証にならない）
  IF has_function_privilege('authenticated', 'public.call_parse_message_tags()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — authenticated が call_parse_message_tags の EXECUTE を持っている';
  END IF;

  -- ここまでに試験用メッセージの Webhook がキューに入っていないこと
  -- （Vault の退避と、試験データ投入中の on_message_insert 無効化が効いていること）
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.url LIKE '%/functions/v1/parse-message-tags'
    AND (CASE WHEN q.url LIKE '%/functions/v1/parse-message-tags'
              THEN convert_from(q.body, 'UTF8')::jsonb -> 'record' ->> 'id' END)
        LIKE '5ea10000-0922-4000-8000-%';
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — (i) の前に試験用メッセージの Webhook がキューに % 行ある', v_cnt;
  END IF;

  -- ダミーの Vault を登録する（setup で退避済みなので、この時点では未登録のはず）
  IF EXISTS (SELECT 1 FROM vault.decrypted_secrets s WHERE s.name IN ('project_url', 'secret_key')) THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — (i) の開始時点で Vault に project_url / secret_key が登録されている（setup の退避が効いていない）';
  END IF;
  PERFORM vault.create_secret('http://searchpath-test.invalid', 'project_url');
  PERFORM vault.create_secret('sb_secret_searchpath_test_dummy', 'secret_key');

  PERFORM set_config('searchpath_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
  RAISE NOTICE 'OK: (i) の前提（トリガー 2 本が有効 / authenticated に EXECUTE なし / 試験用メッセージの Webhook 0 行）。ダミーの Vault（http://searchpath-test.invalid）を登録した';
END $$;

-- i-1: C1 が担当トレーナー T へ送信（Mobile の送信と同じ列。作成時刻は既定の now()）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';

DO $$
DECLARE
  v_rows int;
BEGIN
  INSERT INTO public.messages (id, sender_id, receiver_id, sender_type, receiver_type, content)
  VALUES ('5ea10000-0922-4000-8000-000000000054',
          '5ea10000-0922-4000-8000-000000000011',
          '5ea10000-0922-4000-8000-000000000001',
          'client', 'trainer', 'searchpath webhook');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: C1 の送信（M_HOOK の INSERT）が % 行（期待 1 行）', v_rows;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL:%' THEN
      RAISE;
    END IF;
    RAISE EXCEPTION 'FAIL: C1 の送信（M_HOOK の INSERT）が失敗した（% %）', SQLSTATE, SQLERRM;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('searchpath_test.q_before')::bigint;
  v_cnt    int;
  v_req    record;
  v_body   jsonb;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: C1 の送信で Webhook の要求が % 件（期待ちょうど 1 件。EXECUTE を剥がした call_parse_message_tags の on_message_insert が発火していない）', v_cnt;
  END IF;

  SELECT q.url, q.body INTO v_req
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  v_body := convert_from(v_req.body, 'UTF8')::jsonb;

  IF v_req.url NOT LIKE '%/functions/v1/parse-message-tags' THEN
    RAISE EXCEPTION 'FAIL: C1 の送信の要求の url が %（期待 ''/functions/v1/parse-message-tags'' で終わる）', v_req.url;
  END IF;
  IF position('viribpvnpgtgtmeulcmx' IN v_req.url) > 0 THEN
    RAISE EXCEPTION 'FAIL: C1 の送信の要求の url が本番のホストを向いている（%）。本テストはダミーの Vault を登録している', v_req.url;
  END IF;
  IF v_body ->> 'type' IS DISTINCT FROM 'INSERT'
     OR v_body -> 'record' ->> 'id' IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000054' THEN
    RAISE EXCEPTION 'FAIL: C1 の送信の要求の body.type / body.record.id が % / %（期待 INSERT / M_HOOK）',
      coalesce(v_body ->> 'type', 'NULL'), coalesce(v_body -> 'record' ->> 'id', 'NULL');
  END IF;

  PERFORM set_config('searchpath_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
  RAISE NOTICE 'OK: EXECUTE を持たない C1 の送信で Webhook が 1 件キューに入った（url % / type=INSERT / record.id=M_HOOK）', v_req.url;
END $$;

-- i-2: C1 が M_HOOK を編集（Mobile の editMessage: can_edit_message で確認してから content, tags, is_edited, edited_at を UPDATE）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000011';

DO $$
DECLARE
  b      boolean;
  v_rows int;
BEGIN
  b := public.can_edit_message('5ea10000-0922-4000-8000-000000000054');
  IF b IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: C1 の can_edit_message(M_HOOK) が %（期待 true = 自分の送信・今）', coalesce(b::text, 'NULL');
  END IF;

  UPDATE public.messages
     SET content = 'searchpath webhook (edited)',
         tags = ARRAY['searchpath']::text[],
         is_edited = true,
         edited_at = now()
   WHERE id = '5ea10000-0922-4000-8000-000000000054';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: C1 の M_HOOK の編集が % 行（期待 1 行。can_edit_message = true と RLS の 5 分ポリシーが不整合）', v_rows;
  END IF;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('searchpath_test.q_before')::bigint;
  v_cnt    int;
  v_req    record;
  v_body   jsonb;
BEGIN
  SELECT count(*) INTO v_cnt
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: C1 の編集で Webhook の要求が % 件（期待ちょうど 1 件。on_message_update が発火していない）', v_cnt;
  END IF;

  SELECT q.url, q.body INTO v_req
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  v_body := convert_from(v_req.body, 'UTF8')::jsonb;

  IF v_req.url NOT LIKE '%/functions/v1/parse-message-tags'
     OR position('viribpvnpgtgtmeulcmx' IN v_req.url) > 0 THEN
    RAISE EXCEPTION 'FAIL: C1 の編集の要求の url が想定外（%）', v_req.url;
  END IF;
  IF v_body ->> 'type' IS DISTINCT FROM 'UPDATE'
     OR v_body -> 'record' ->> 'id' IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000054' THEN
    RAISE EXCEPTION 'FAIL: C1 の編集の要求の body.type / body.record.id が % / %（期待 UPDATE / M_HOOK）',
      coalesce(v_body ->> 'type', 'NULL'), coalesce(v_body -> 'record' ->> 'id', 'NULL');
  END IF;

  PERFORM set_config('searchpath_test.q_before',
    (SELECT coalesce(max(q.id), 0) FROM net.http_request_queue q)::text, true);
  RAISE NOTICE 'OK: C1 の編集（editMessage と同じ列）で Webhook がもう 1 件キューに入った（type=UPDATE / record.id=M_HOOK）';
END $$;

-- i-3: 受信者 T の既読化（Web の markMessagesAsRead と同じく read_at だけを更新）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000001';

DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.messages
     SET read_at = now()
   WHERE id = '5ea10000-0922-4000-8000-000000000054'
     AND receiver_id = '5ea10000-0922-4000-8000-000000000001'
     AND read_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の M_HOOK の既読化が % 行（期待 1 行）', v_rows;
  END IF;

  -- updated_at の検証用: 10 分前に作られ updated_at も 10 分前の M_OLD も既読にする
  UPDATE public.messages
     SET read_at = now()
   WHERE id = '5ea10000-0922-4000-8000-000000000052'
     AND receiver_id = '5ea10000-0922-4000-8000-000000000001'
     AND read_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の M_OLD の既読化が % 行（期待 1 行）', v_rows;
  END IF;
END $$;

RESET ROLE;

DO $$
DECLARE
  v_before bigint := current_setting('searchpath_test.q_before')::bigint;
  v_cnt    int;
  v_urls   text;
  v_hook   record;
  v_old    record;
BEGIN
  -- 既読化（read_at だけの UPDATE）ではキューの行が増えないこと（送信先に関係なく数える）
  SELECT count(*), string_agg(q.url, ', ' ORDER BY q.id) INTO v_cnt, v_urls
  FROM net.http_request_queue q
  WHERE q.id > v_before;
  IF v_cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: T の既読化（read_at だけの UPDATE）で要求が % 件積まれた（期待 0 件。url: %）', v_cnt, v_urls;
  END IF;

  SELECT m.read_at, m.updated_at, m.content, m.is_edited INTO v_hook
  FROM public.messages m WHERE m.id = '5ea10000-0922-4000-8000-000000000054';
  IF v_hook.read_at IS NULL THEN
    RAISE EXCEPTION 'FAIL: T の既読化後も M_HOOK が未読のまま';
  END IF;
  IF v_hook.content IS DISTINCT FROM 'searchpath webhook (edited)' OR v_hook.is_edited IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: M_HOOK の content / is_edited が想定外（% / %）', v_hook.content, v_hook.is_edited;
  END IF;

  SELECT m.read_at, m.updated_at INTO v_old
  FROM public.messages m WHERE m.id = '5ea10000-0922-4000-8000-000000000052';
  IF v_old.read_at IS NULL THEN
    RAISE EXCEPTION 'FAIL: T の既読化後も M_OLD が未読のまま';
  END IF;
  IF v_old.updated_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: T の既読化後の M_OLD.updated_at が %（期待 now() = %。set_updated_at（update_updated_at_column）が発火していない）', v_old.updated_at, now();
  END IF;

  RAISE NOTICE 'OK: T の既読化（read_at だけ）は成功し、要求は 0 件、M_OLD.updated_at が now() に更新された';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(j): Web の RPC 2 本（LANGUAGE sql STABLE・INVOKER・空の search_path）
--   ACL は変えていない（PUBLIC / anon / authenticated / service_role が EXECUTE を持つ）。INVOKER なので
--   返る行は呼び出し元に対する messages / clients の RLS が決める。search_path = '' でも
--   public.messages / public.clients に到達して従来どおりの結果を返すことを確かめる。
--   この時点の T の会話は C1 とのものだけ:
--     M_HOOK（C1 → T / now() / 編集後 'searchpath webhook (edited)' / 既読）… 最新
--     M_FRESH（C1 → T / 1 分前 / 未読）/ M_T2C（T → C1 / 2 分前）/ M_OLD（C1 → T / 10 分前 / 既読）
--   期待値: get_last_messages_for_trainer(T) = C1 の 1 行（content = 'searchpath webhook (edited)'、
--   created_at = now()）、get_unread_counts_for_trainer(T) = C1 の 1 行（unread_count = 1 = M_FRESH）。
--   まず postgres で試験用の行からこの期待値を確かめてから（前提確認）、各ロールで呼ぶ
-- -----------------------------------------------------------------------------
\echo '--- case j: Web の RPC 2 本が T には C1 の最新メッセージ・未読数を返し、T2・anon には 0 行であること'

DO $$
DECLARE
  v_cnt     int;
  v_content text;
  v_unread  bigint;
BEGIN
  -- 前提確認 1: T と C1 の会話の最新メッセージは M_HOOK の 1 件だけ（同時刻の行が無い）
  SELECT count(*) INTO v_cnt
  FROM public.messages m
  WHERE ((m.sender_id = '5ea10000-0922-4000-8000-000000000001' AND m.receiver_id = '5ea10000-0922-4000-8000-000000000011')
      OR (m.sender_id = '5ea10000-0922-4000-8000-000000000011' AND m.receiver_id = '5ea10000-0922-4000-8000-000000000001'))
    AND m.created_at = (
      SELECT max(m2.created_at) FROM public.messages m2
      WHERE (m2.sender_id = '5ea10000-0922-4000-8000-000000000001' AND m2.receiver_id = '5ea10000-0922-4000-8000-000000000011')
         OR (m2.sender_id = '5ea10000-0922-4000-8000-000000000011' AND m2.receiver_id = '5ea10000-0922-4000-8000-000000000001'));
  SELECT m.content INTO v_content
  FROM public.messages m
  WHERE (m.sender_id = '5ea10000-0922-4000-8000-000000000001' AND m.receiver_id = '5ea10000-0922-4000-8000-000000000011')
     OR (m.sender_id = '5ea10000-0922-4000-8000-000000000011' AND m.receiver_id = '5ea10000-0922-4000-8000-000000000001')
  ORDER BY m.created_at DESC
  LIMIT 1;
  IF v_cnt <> 1 OR v_content IS DISTINCT FROM 'searchpath webhook (edited)' THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — T と C1 の会話の最新メッセージが % 件 / content=%（期待 1 件 / searchpath webhook (edited)）', v_cnt, coalesce(v_content, 'NULL');
  END IF;

  -- 前提確認 2: C1 → T の未読（sender_type = client）は 1 件（M_FRESH）
  SELECT count(*) INTO v_unread
  FROM public.messages m
  WHERE m.sender_id = '5ea10000-0922-4000-8000-000000000011'
    AND m.receiver_id = '5ea10000-0922-4000-8000-000000000001'
    AND m.sender_type = 'client'
    AND m.read_at IS NULL;
  IF v_unread <> 1 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — C1 → T の未読が % 件（期待 1 件 = M_FRESH）', v_unread;
  END IF;

  -- 前提確認 3: T のメッセージの相手は C1 だけ（C2・C3 とはやりとりが無い）
  SELECT count(DISTINCT CASE WHEN m.sender_id = '5ea10000-0922-4000-8000-000000000001' THEN m.receiver_id ELSE m.sender_id END)
    INTO v_cnt
  FROM public.messages m
  WHERE m.sender_id = '5ea10000-0922-4000-8000-000000000001'
     OR m.receiver_id = '5ea10000-0922-4000-8000-000000000001';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — T のメッセージの相手が % 人（期待 1 人 = C1）', v_cnt;
  END IF;

  RAISE NOTICE 'OK: 期待値の前提（T の会話は C1 のみ / 最新 = M_HOOK / C1 → T の未読 1 件）';
END $$;

-- j-1: トレーナー T（Web のメッセージ一覧と同じ呼び出し）
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000001';

DO $$
DECLARE
  v_cnt int;
  r     record;
BEGIN
  SELECT count(*) INTO v_cnt FROM public.get_last_messages_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の get_last_messages_for_trainer(T) が % 行（期待 1 行 = C1）', v_cnt;
  END IF;
  SELECT * INTO r FROM public.get_last_messages_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF r.client_id IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000011'::uuid
     OR r.content IS DISTINCT FROM 'searchpath webhook (edited)'
     OR r.created_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: T の get_last_messages_for_trainer(T) が client_id=% / content=% / created_at=%（期待 C1 / searchpath webhook (edited) / %）',
      r.client_id, coalesce(r.content, 'NULL'), r.created_at, now();
  END IF;

  SELECT count(*) INTO v_cnt FROM public.get_unread_counts_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: T の get_unread_counts_for_trainer(T) が % 行（期待 1 行 = C1）', v_cnt;
  END IF;
  SELECT * INTO r FROM public.get_unread_counts_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF r.sender_id IS DISTINCT FROM '5ea10000-0922-4000-8000-000000000011'::uuid
     OR r.unread_count IS DISTINCT FROM 1::bigint THEN
    RAISE EXCEPTION 'FAIL: T の get_unread_counts_for_trainer(T) が sender_id=% / unread_count=%（期待 C1 / 1）', r.sender_id, r.unread_count;
  END IF;

  RAISE NOTICE 'OK: T の get_last_messages_for_trainer(T) = C1 の最新（searchpath webhook (edited)）/ get_unread_counts_for_trainer(T) = C1 の未読 1';
END $$;

-- j-2: 他人トレーナー T2 が p_trainer_id = T で呼ぶ（INVOKER なので RLS で T の会話は見えない）
SET LOCAL request.jwt.claims = '{"sub":"5ea10000-0922-4000-8000-000000000002","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '5ea10000-0922-4000-8000-000000000002';

DO $$
DECLARE
  v_last   int;
  v_unread int;
BEGIN
  SELECT count(*) INTO v_last   FROM public.get_last_messages_for_trainer('5ea10000-0922-4000-8000-000000000001');
  SELECT count(*) INTO v_unread FROM public.get_unread_counts_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF v_last <> 0 OR v_unread <> 0 THEN
    RAISE EXCEPTION 'FAIL: T2 が p_trainer_id = T で呼ぶと get_last_messages_for_trainer % 行 / get_unread_counts_for_trainer % 行（期待 0 行 / 0 行。INVOKER + RLS）', v_last, v_unread;
  END IF;
  RAISE NOTICE 'OK: T2 が p_trainer_id = T で呼ぶと 2 本とも 0 行';
END $$;

RESET ROLE;

-- j-3: anon（クレーム無し）
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
DECLARE
  v_last   int;
  v_unread int;
BEGIN
  IF current_user IS DISTINCT FROM 'anon' OR auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — current_user=% / auth.uid()=%（期待 anon / NULL）',
      current_user, coalesce(auth.uid()::text, 'NULL');
  END IF;

  SELECT count(*) INTO v_last   FROM public.get_last_messages_for_trainer('5ea10000-0922-4000-8000-000000000001');
  SELECT count(*) INTO v_unread FROM public.get_unread_counts_for_trainer('5ea10000-0922-4000-8000-000000000001');
  IF v_last <> 0 OR v_unread <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が p_trainer_id = T で呼ぶと get_last_messages_for_trainer % 行 / get_unread_counts_for_trainer % 行（期待 0 行 / 0 行）', v_last, v_unread;
  END IF;
  RAISE NOTICE 'OK: anon（クレーム無し）が p_trainer_id = T で呼ぶと 2 本とも 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(k): 定義の固定（カタログ検査。postgres として実行）
--   - prosecdef: can_edit_message / enforce_client_limit / enforce_client_note_session_consistency は
--     SECURITY DEFINER のまま、updated_at 系 3 本と get_* の 2 本は INVOKER のまま（本 migration は
--     実行権限のモデルを変えていない）
--   - proconfig: 9 本とも {search_path=""} ちょうど（SET search_path = ''）
--   - owner: postgres
--   - md5(prosrc): ALTER FUNCTION で search_path だけを変えた 7 本は本体が一文字も変わっていないこと
--     （migration セクション 0 のガードと同じ値）。CREATE OR REPLACE した can_edit_message は
--     送信者条件入りの新しい本体（migration セクション 1 に記載の値）
--   - call_parse_message_tags は prosecdef と md5 を固定しない（本体と SECURITY DEFINER は #89 の持ち物で、
--     parse_message_tags_webhook_test.sql が固定する）。proconfig / owner / ACL / EXECUTE マトリクスは
--     本 migration が保証するものとして検査する（下の表で exp_secdef / exp_md5 を NULL = 固定しない）
--   - proacl: 9 本とも NULL でない（NULL = 既定権限 = PUBLIC に EXECUTE がある状態）
--   - PUBLIC（grantee = 0）: トリガー関数 6 本と can_edit_message には無いこと。get_* の 2 本には
--     あること（ACL は意図的に変えていない。INVOKER なので返る行は RLS が決める）
--   - PUBLIC 以外の grantee 集合がちょうど期待どおり（余計なロールなし）。
--     （pg_get_userbyid は name 型を返し、name[] と text[] は比較できないため text にキャストする。
--       DISTINCT 付きの集約では ORDER BY に引数と同じ式を書く必要がある）
--   - has_function_privilege の EXECUTE マトリクスがヘッダーの表どおり
--   - can_edit_message の署名（引数名 message_id / 戻り値 boolean）と、get_* の揮発性（STABLE）も固定する
--     （Mobile は rpc('can_edit_message', {'message_id': ...}) で呼ぶ）
-- -----------------------------------------------------------------------------
\echo '--- case k: 9 関数の定義固定（SECURITY 属性 / search_path 空文字 / owner / 本体の md5 / ACL / EXECUTE マトリクス）'

DO $$
DECLARE
  r          record;
  v_fn       record;
  v_got      boolean;
  v_public   boolean;
  v_grantees text[];
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      (1, 'public.can_edit_message(uuid)',                    true,  'c2b26f33f8dd6b96edae211a71a0e314', false, true,  false, false, ARRAY['authenticated', 'postgres']),
      (2, 'public.update_updated_at_column()',                false, 'da5ac28a58c8b4bb30209bf0d3d7082c', false, false, false, false, ARRAY['postgres']),
      (3, 'public.update_sessions_updated_at()',              false, 'da5ac28a58c8b4bb30209bf0d3d7082c', false, false, false, false, ARRAY['postgres']),
      (4, 'public.update_trainer_schedules_updated_at()',     false, '301a884953d37769916294bb60562e05', false, false, false, false, ARRAY['postgres']),
      (5, 'public.call_parse_message_tags()',                 NULL,  NULL,                               false, false, false, false, ARRAY['postgres']),
      (6, 'public.enforce_client_limit()',                    true,  '06cc8fece5fb8490563b43f4f20c11cb', false, false, false, false, ARRAY['postgres']),
      (7, 'public.enforce_client_note_session_consistency()', true,  'bfdbafb4eb8e623fc2d2041200791c50', false, false, false, false, ARRAY['postgres']),
      (8, 'public.get_last_messages_for_trainer(uuid)',       false, 'a155740854167fa6510d34194d88217b', true,  true,  true,  true,  ARRAY['anon', 'authenticated', 'postgres', 'service_role']),
      (9, 'public.get_unread_counts_for_trainer(uuid)',       false, '8e8f7398ea0ebdd1328721c6abd2522b', true,  true,  true,  true,  ARRAY['anon', 'authenticated', 'postgres', 'service_role'])
    ) AS t(ord, sig, exp_secdef, exp_md5, exp_anon, exp_authenticated, exp_service_role, exp_public, exp_grantees)
    ORDER BY t.ord
  LOOP
    SELECT p.oid, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) AS owner, p.proacl,
           md5(p.prosrc) AS src_md5
      INTO v_fn
    FROM pg_proc p
    WHERE p.oid = to_regprocedure(r.sig);

    IF v_fn.oid IS NULL THEN
      RAISE EXCEPTION 'FAIL: % が存在しない', r.sig;
    END IF;

    -- prosecdef / md5 は exp_* が NULL の関数（call_parse_message_tags = #89 の持ち物）では固定しない
    IF r.exp_secdef IS NOT NULL AND v_fn.prosecdef IS DISTINCT FROM r.exp_secdef THEN
      RAISE EXCEPTION 'FAIL: % の prosecdef が %（期待 %。SECURITY 属性は変えない）', r.sig, v_fn.prosecdef, r.exp_secdef;
    END IF;
    IF r.exp_md5 IS NOT NULL AND v_fn.src_md5 IS DISTINCT FROM r.exp_md5 THEN
      RAISE EXCEPTION 'FAIL: % の md5(prosrc) が %（期待 %。本体が migration の想定と違う）', r.sig, v_fn.src_md5, r.exp_md5;
    END IF;

    IF v_fn.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
      RAISE EXCEPTION 'FAIL: % の proconfig が %（期待 {search_path=""} = SET search_path = '''' ）',
        r.sig, coalesce(v_fn.proconfig::text, 'NULL（search_path 未設定）');
    END IF;
    IF v_fn.owner IS DISTINCT FROM 'postgres' THEN
      RAISE EXCEPTION 'FAIL: % の owner が %（期待 postgres）', r.sig, v_fn.owner;
    END IF;
    IF v_fn.proacl IS NULL THEN
      RAISE EXCEPTION 'FAIL: % の proacl が NULL（既定権限 = PUBLIC に EXECUTE がある状態）', r.sig;
    END IF;

    v_public := EXISTS (SELECT 1 FROM aclexplode(v_fn.proacl) a WHERE a.grantee = 0);
    IF v_public IS DISTINCT FROM r.exp_public THEN
      IF r.exp_public THEN
        RAISE EXCEPTION 'FAIL: % の ACL に PUBLIC への付与が無い（本 migration は get_* の ACL を変えない。%）', r.sig, v_fn.proacl;
      ELSE
        RAISE EXCEPTION 'FAIL: % の ACL に PUBLIC への付与が残っている（%）', r.sig, v_fn.proacl;
      END IF;
    END IF;

    SELECT array_agg(DISTINCT pg_get_userbyid(a.grantee)::text ORDER BY pg_get_userbyid(a.grantee)::text)
      INTO v_grantees
    FROM aclexplode(v_fn.proacl) a
    WHERE a.grantee <> 0;
    IF v_grantees IS DISTINCT FROM r.exp_grantees THEN
      RAISE EXCEPTION 'FAIL: % の ACL の grantee 集合（PUBLIC 以外）が %（期待 % ちょうど。ACL %）',
        r.sig, coalesce(v_grantees::text, 'NULL'), r.exp_grantees, v_fn.proacl;
    END IF;

    v_got := has_function_privilege('anon', v_fn.oid, 'EXECUTE');
    IF v_got IS DISTINCT FROM r.exp_anon THEN
      RAISE EXCEPTION 'FAIL: % の anon EXECUTE が %（期待 %）', r.sig, v_got, r.exp_anon;
    END IF;
    v_got := has_function_privilege('authenticated', v_fn.oid, 'EXECUTE');
    IF v_got IS DISTINCT FROM r.exp_authenticated THEN
      RAISE EXCEPTION 'FAIL: % の authenticated EXECUTE が %（期待 %）', r.sig, v_got, r.exp_authenticated;
    END IF;
    v_got := has_function_privilege('service_role', v_fn.oid, 'EXECUTE');
    IF v_got IS DISTINCT FROM r.exp_service_role THEN
      RAISE EXCEPTION 'FAIL: % の service_role EXECUTE が %（期待 %）', r.sig, v_got, r.exp_service_role;
    END IF;

    RAISE NOTICE 'OK: % — prosecdef=% / search_path 空文字 / owner postgres / md5 % / PUBLIC=% / grantee=% / anon=% authenticated=% service_role=%',
      r.sig,
      CASE WHEN r.exp_secdef IS NULL THEN v_fn.prosecdef::text || '（固定しない: #89 の持ち物）' ELSE r.exp_secdef::text END,
      CASE WHEN r.exp_md5 IS NULL THEN '固定しない（#89 の持ち物。parse_message_tags_webhook_test.sql が検証）' ELSE '一致' END,
      r.exp_public, v_grantees, r.exp_anon, r.exp_authenticated, r.exp_service_role;
  END LOOP;

  -- can_edit_message の署名（Mobile が {'message_id': ...} で渡す）と get_* の揮発性
  IF (SELECT p.proargnames FROM pg_proc p WHERE p.oid = 'public.can_edit_message(uuid)'::regprocedure)
       IS DISTINCT FROM ARRAY['message_id']
     OR (SELECT p.prorettype FROM pg_proc p WHERE p.oid = 'public.can_edit_message(uuid)'::regprocedure)
       IS DISTINCT FROM 'boolean'::regtype THEN
    RAISE EXCEPTION 'FAIL: can_edit_message の引数名 / 戻り値が変わっている（期待 message_id / boolean）';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid IN ('public.get_last_messages_for_trainer(uuid)'::regprocedure,
                    'public.get_unread_counts_for_trainer(uuid)'::regprocedure)
      AND p.provolatile IS DISTINCT FROM 's'
  ) THEN
    RAISE EXCEPTION 'FAIL: get_last_messages_for_trainer / get_unread_counts_for_trainer が STABLE でない';
  END IF;
  RAISE NOTICE 'OK: can_edit_message の署名（message_id → boolean）と get_* の STABLE を維持';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL FUNCTION SEARCH_PATH PRIVILEGE TESTS PASSED'
