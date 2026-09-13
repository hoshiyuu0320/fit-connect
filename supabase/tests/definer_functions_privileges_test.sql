-- =============================================================================
-- SECURITY DEFINER 関数 4 本の EXECUTE 権限 / search_path / 呼び出し元チェック テスト
-- （fix/definer-function-privileges）
--
-- 対象: public.calculate_achievement_rate(uuid, numeric)
--       public.check_goal_achievement(uuid, numeric)
--       public.issue_recurring_tickets()
--       public.mark_messages_as_read(uuid)
--
-- 検証対象の migration:
--   supabase/migrations/20260913000500_capture_remote_definer_functions.sql
--     （リモートにだけ存在した mark_messages_as_read / calculate_achievement_rate の実定義の追認）
--   supabase/migrations/20260913000510_harden_definer_functions.sql
--     （EXECUTE の最小権限化 / SET search_path = '' / calculate_achievement_rate の呼び出し元チェック）
--
-- 是正前（リモート）は 4 本とも PUBLIC / anon / authenticated / service_role に EXECUTE が
-- 付いており、公開 anon キーだけで PostgREST（/rest/v1/rpc/<関数名>）から postgres 権限で
-- 実行できた。また 3 本は search_path 未設定（mark_messages_as_read は search_path=public）。
-- 本テストは是正後の状態（呼び出し経路ごとの最小権限 + SET search_path = '' + 本文の
-- 呼び出し元チェック）と、既存の呼び出し経路（Mobile / Edge Function / pg_cron）が
-- 壊れていないことを固定する自己完結テスト
-- （session_reminder_test.sql / sessions_rls_test.sql のパターン踏襲）。
--
-- 是正後の EXECUTE マトリクス（has_function_privilege）と呼び出し元:
--   関数                        anon  authenticated  service_role  呼び出し元
--   calculate_achievement_rate   ×         ○              ○        Mobile（本人）/ Edge Function parse-message-tags
--   check_goal_achievement       ×         ×              ○        Edge Function parse-message-tags のみ
--   issue_recurring_tickets      ×         ×              ×        pg_cron 'issue-recurring-tickets'（postgres = オーナー）
--   mark_messages_as_read        ×         ○              ×        Mobile（本人）
--   4 本とも SECURITY DEFINER / SET search_path = '' / owner postgres / PUBLIC への付与なし /
--   ACL の grantee は上表の ○ のロールとオーナー postgres だけ
--
-- calculate_achievement_rate は authenticated に開くため、本文で呼び出し元を確認する:
--   - auth.uid() あり: 本人（auth.uid() = p_client_id）または担当トレーナー
--     （public.clients.trainer_id = auth.uid()）のみ許可。それ以外は 42501
--     （p_client_id が NULL / 存在しない顧客でも拒否側に倒れる）
--   - auth.uid() なし: JWT の role クレームが service_role（Edge Function）か、
--     クレーム自体が無い（postgres 等の直接 DB セッション）場合のみ許可。それ以外は 42501
--   - 拒否は RAISE EXCEPTION 'ACHIEVEMENT_RATE_FORBIDDEN'（ERRCODE 42501）
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/definer_functions_privileges_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL DEFINER FUNCTION PRIVILEGE TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - GRANT 層の拒否も本文チェックの拒否も SQLSTATE 42501（insufficient_privilege）で現れる。
--   拒否ケースはどちらも WHEN insufficient_privilege で受けたうえで、SQLERRM でどちらの層の
--   拒否かを区別する（期待と違う層で拒否されたら FAIL）:
--     GRANT 層    : SQLERRM LIKE 'permission denied for function %'  … (a) (b) (c-2) (f-2) (h-2)
--     本文チェック: SQLERRM = 'ACHIEVEMENT_RATE_FORBIDDEN'           … (c-4) (d-1) (g) (h-3)
--   後者は migration が「呼び出し側の識別用に固定」としているメッセージ文字列の固定も兼ねる
-- - mark_messages_as_read はリモートにしか無かった関数のため、取り込みマイグレーション
--   （20260913000500）適用前のローカル DB では setup の前提確認で FAIL する
-- - calculate_achievement_rate の期待値はリモートの本文（開始体重 NULL なら最古の体重記録に
--   フォールバック / 体重記録も無ければ目標一致で 100・それ以外 0）に合わせている
-- - seed.sql のデータと混ざらないよう、件数・状態の検証は必ず試験用の行に限定する
--   （(i-1) の cron 実行では seed の期日到来サブスクリプションも処理されうる）
--
-- 検証ケース（「GRANT 層」「本文チェック」は上記 SQLERRM による区別）:
--   (a)   anon（JWT クレーム無し）: 4 関数とも EXECUTE 拒否（42501 / GRANT 層）
--   (b)   anon ロール + 顧客 C の JWT クレーム（クレーム付き anon）: 4 関数とも EXECUTE 拒否
--         （42501 / GRANT 層）= GRANT 層の直接検証。calculate_achievement_rate は auth.uid() = C なら
--         本文チェックを通ってしまうため、ここは anon の EXECUTE 剥奪でしか PASS しない
--         （docs/tasks/lessons.md「クレーム付き anon」の教訓）
--   (c-1) 本人 C: calculate_achievement_rate(C, 75 / 85 / 65) = 50.0 / 0 / 100
--   (c-2) 本人 C: check_goal_achievement / issue_recurring_tickets は EXECUTE 拒否（42501 / GRANT 層）
--   (d-1) 他人の顧客 D: calculate_achievement_rate(C, 75) は 42501（本文チェック）
--   (d-2) D 自身のデータ: calculate_achievement_rate(D, 60 / 61) = 100 / 0
--         （開始体重 NULL・体重記録なし）
--   (d-3) D の mark_messages_as_read(T): D 宛ての M3 だけが既読（M1・M2・M4 は未読のまま）
--   (c-3) C の mark_messages_as_read(T): C 宛ての M1・M2 が既読、C→T の M4 は未読のまま
--         （(d-3) の後に実行する。C より先に D が呼ぶことで、D の呼び出しが C 宛ての
--          M1・M2 に波及していないことを「未読のまま」として観測できる）
--   (c-4) 本人 C: calculate_achievement_rate(NULL, 75) / (clients に存在しない顧客 X, 75) は
--         42501（本文チェック）。NULL は IS DISTINCT FROM により拒否側に倒れること、
--         存在しない顧客は 0 を返さず拒否されること
--   (e)   本人 E: calculate_achievement_rate(E, 65) = 50.0（開始体重 NULL → 最古の体重記録
--         70kg にフォールバック。search_path = '' でも public.weight_records に到達できること）
--   (f)   担当トレーナー T: calculate_achievement_rate(C, 75) = 50.0 / check_goal_achievement・
--         issue_recurring_tickets は 42501（GRANT 層）/ mark_messages_as_read(C) で M4 が既読
--   (g)   他人トレーナー T2: calculate_achievement_rate(C, 75) は 42501（本文チェック）
--   (h-1) service_role（Edge Function 相当）: calculate_achievement_rate(C, 75) = 50.0 /
--         check_goal_achievement(C, 70 / 70.1) = true / false
--   (h-2) service_role: mark_messages_as_read / issue_recurring_tickets は EXECUTE 拒否（42501 / GRANT 層）
--   (h-3) authenticated ロール + sub の無いクレーム（role=authenticated）:
--         calculate_achievement_rate(C, 75) は 42501（本文チェック。「sub が無ければ許可」に
--         なっていないこと。(h-1) の許可が role クレーム service_role で判定されていることの負の対照）
--   (i-1) オーナー / cron 経路（postgres・クレーム無し）: cron.job の jobname = 'issue-recurring-tickets'
--         の全行（一意キーは (jobname, username) で複数行ありうる）の username が EXECUTE を持つこと
--         （0 行なら FAIL）。先頭行（jobid 順）の command を 1 回だけ動的 EXECUTE → 試験用
--         サブスクリプションからチケット 1 枚・未払い payments 1 行が発行され、next_issue_date が
--         1 か月進むこと
--   (i-2) 直接 DB セッション（postgres・クレーム無し）: calculate_achievement_rate(C, 75) = 50.0
--   (j)   定義の固定: 4 関数とも prosecdef / proconfig = {search_path=""} / owner postgres /
--         proacl 非 NULL / PUBLIC エントリなし / ACL の grantee 集合が期待どおり（余計なロール
--         なし）/ anon・authenticated・service_role の EXECUTE マトリクス（上表どおり）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 前提確認: 対象の 4 関数が存在すること
--   mark_messages_as_read はリモートにだけ存在していた（ローカルは取り込みマイグレーション
--   20260913000500 で追加）。
--   存在しない関数を各ケースで直接呼ぶと 42883 の素のエラーで落ちて原因が分かりにくいため、
--   ここで明示的に FAIL させる
-- -----------------------------------------------------------------------------
\echo '--- setup: 前提確認（対象の 4 関数が存在すること）'

DO $$
DECLARE
  v_sig text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.calculate_achievement_rate(uuid, numeric)',
    'public.check_goal_achievement(uuid, numeric)',
    'public.issue_recurring_tickets()',
    'public.mark_messages_as_read(uuid)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION 'FAIL: 前提崩れ — % が存在しない（mark_messages_as_read はリモートにしか無かったため、取り込みマイグレーション 20260913000500 の適用が必要）', v_sig;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: 対象の 4 関数が存在する';
END $$;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer  T  : defd0000-0913-4000-8000-000000000001（C / D / E の担当トレーナー）
--   trainer  T2 : defd0000-0913-4000-8000-000000000002（他人トレーナー。担当顧客なし）
--   client   C  : defd0000-0913-4000-8000-000000000011（T の顧客。開始 80kg → 目標 70kg）
--   client   D  : defd0000-0913-4000-8000-000000000012（T の顧客。開始体重 NULL・目標 60kg・体重記録なし）
--   client   E  : defd0000-0913-4000-8000-000000000013（T の顧客。開始体重 NULL・目標 60kg）
--   client   X  : defd0000-0913-4000-8000-000000000019（作成しない。(c-4) で clients に存在しない顧客として使う）
--   weight   W1 : defd0000-0913-4000-8000-000000000031（E / 70kg / 30 日前 = 最古）
--   weight   W2 : defd0000-0913-4000-8000-000000000032（E / 66kg / 1 日前 = 最新）
--   message  M1 : defd0000-0913-4000-8000-000000000021（T → C / 未読）
--   message  M2 : defd0000-0913-4000-8000-000000000022（T → C / 未読）
--   message  M3 : defd0000-0913-4000-8000-000000000023（T → D / 未読）
--   message  M4 : defd0000-0913-4000-8000-000000000024（C → T / 未読）
--   template TT : defd0000-0913-4000-8000-000000000041（T の月契約テンプレート。10000 円 / 1 か月）
--   subscr.  SUB: defd0000-0913-4000-8000-000000000051（C の active サブスクリプション。next_issue_date = 今日）
--   T の顧客は 3 名。clients の BEFORE トリガー enforce_client_limit は Free プランでも 3 名まで
--   許可するため、トライアル期限の有無に関係なく上限内に収まる
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T・T2 / client C・D・E / weight W1・W2 / message M1〜M4 / template TT / subscription SUB)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('defd0000-0913-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'definer-test-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('defd0000-0913-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'definer-test-t2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('defd0000-0913-4000-8000-000000000011', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'definer-test-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('defd0000-0913-4000-8000-000000000012', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'definer-test-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('defd0000-0913-4000-8000-000000000013', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'definer-test-e@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('defd0000-0913-4000-8000-000000000001', 'DEFINERテスト トレーナーT',
   'definer-test-t@example.com'),
  ('defd0000-0913-4000-8000-000000000002', 'DEFINERテスト トレーナーT2',
   'definer-test-t2@example.com');

INSERT INTO public.clients (client_id, name, trainer_id, initial_weight, target_weight) VALUES
  ('defd0000-0913-4000-8000-000000000011', 'DEFINERテスト顧客C',
   'defd0000-0913-4000-8000-000000000001', 80, 70),
  ('defd0000-0913-4000-8000-000000000012', 'DEFINERテスト顧客D',
   'defd0000-0913-4000-8000-000000000001', NULL, 60),
  ('defd0000-0913-4000-8000-000000000013', 'DEFINERテスト顧客E',
   'defd0000-0913-4000-8000-000000000001', NULL, 60);

-- 最新の W2 を先に INSERT する（ORDER BY recorded_at を落とした実装が物理順で
-- 最古の W1 を偶然拾って PASS しないように）
INSERT INTO public.weight_records (id, client_id, weight, recorded_at, source) VALUES
  ('defd0000-0913-4000-8000-000000000032', 'defd0000-0913-4000-8000-000000000013',
   66, now() - interval '1 day', 'manual'),
  ('defd0000-0913-4000-8000-000000000031', 'defd0000-0913-4000-8000-000000000013',
   70, now() - interval '30 days', 'manual');

-- messages の on_message_insert トリガー（call_parse_message_tags）は pg_net 経由で
-- 「本番」の parse-message-tags URL を呼ぶ。pg_net の要求は net.http_request_queue への
-- INSERT で、コミットされない限りワーカーは送信しない（ROLLBACK で破棄される）が、
-- 試験データを本番へ送らないための二重の安全策としてトランザクション内で無効化する。
-- ALTER TABLE もトランザクショナルなので最後の ROLLBACK（または異常終了）で元に戻る。
-- （ALTER TABLE は messages に SHARE ROW EXCLUSIVE ロックを取るため、本テスト実行中の
--   わずかな間は他セッションの messages 書込みが待たされる）
-- set_updated_at（BEFORE UPDATE）は無効化しない（既読化の UPDATE で従来どおり発火させる）。
-- on_message_update は AFTER UPDATE OF content のため、read_at だけの既読化では発火しない
ALTER TABLE public.messages DISABLE TRIGGER on_message_insert;

INSERT INTO public.messages (
  id, sender_id, receiver_id, sender_type, receiver_type, content
) VALUES
  ('defd0000-0913-4000-8000-000000000021',
   'defd0000-0913-4000-8000-000000000001', 'defd0000-0913-4000-8000-000000000011',
   'trainer', 'client', 'DEFINERテスト: M1 T→C'),
  ('defd0000-0913-4000-8000-000000000022',
   'defd0000-0913-4000-8000-000000000001', 'defd0000-0913-4000-8000-000000000011',
   'trainer', 'client', 'DEFINERテスト: M2 T→C'),
  ('defd0000-0913-4000-8000-000000000023',
   'defd0000-0913-4000-8000-000000000001', 'defd0000-0913-4000-8000-000000000012',
   'trainer', 'client', 'DEFINERテスト: M3 T→D'),
  ('defd0000-0913-4000-8000-000000000024',
   'defd0000-0913-4000-8000-000000000011', 'defd0000-0913-4000-8000-000000000001',
   'client', 'trainer', 'DEFINERテスト: M4 C→T');

INSERT INTO public.ticket_templates (
  id, trainer_id, template_name, ticket_type, total_sessions, valid_months, is_recurring, price_yen
) VALUES
  ('defd0000-0913-4000-8000-000000000041', 'defd0000-0913-4000-8000-000000000001',
   'DEFINERテスト 月4回プラン', 'personal', 4, 1, true, 10000);

INSERT INTO public.ticket_subscriptions (
  id, template_id, client_id, status, start_date, next_issue_date
) VALUES
  ('defd0000-0913-4000-8000-000000000051', 'defd0000-0913-4000-8000-000000000041',
   'defd0000-0913-4000-8000-000000000011', 'active', CURRENT_DATE, CURRENT_DATE);

-- -----------------------------------------------------------------------------
-- ケース(a): anon（JWT クレーム無し）は 4 関数とも EXECUTE できない（GRANT 層で拒否）
--   PostgREST の /rest/v1/rpc/<関数名> は公開 anon キーだけで呼べるため、anon に EXECUTE が
--   残っていると誰でも SECURITY DEFINER（postgres 権限）で実行できてしまう。
--   calculate_achievement_rate における GRANT 層と本文チェックの関係:
--   - この合成セッション（anon ロールでクレームが一切無い）では、本文チェックは
--     「クレーム無し = 直接 DB セッション」として許可側に入る。したがって (a) で止めているのは
--     GRANT 層だけ
--   - 実際の anon キー / publishable キーによるリクエストには {"role":"anon"} のクレームが付くので、
--     本文の ELSIF（sub 無し・role が service_role 以外）でも拒否される。本文は二層目の防御
--   - そのため {"role":"anon"} のような現実のクレームで試すと、anon の EXECUTE が残っていても
--     本文の 42501 で PASS してしまい、GRANT 層の剥奪漏れが見えない。本文が許可側に入る合成
--     セッション（(a) = クレーム無し / (b) = 顧客 C のクレーム）を使って GRANT 層だけを切り出して
--     検証し、さらに SQLERRM が 'permission denied for function ...'（GRANT 層）であることを確認する
--   ※ 先行ケースのクレームが残らないよう、両形式を空にしてからロールを切り替える
-- -----------------------------------------------------------------------------
\echo '--- case a: anon（クレーム無し）から 4 関数とも EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  BEGIN
    PERFORM public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が calculate_achievement_rate を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ calculate_achievement_rate の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon（クレーム無し）→ calculate_achievement_rate は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70);
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が check_goal_achievement を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ check_goal_achievement の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon（クレーム無し）→ check_goal_achievement は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.issue_recurring_tickets();
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が issue_recurring_tickets を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ issue_recurring_tickets の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon（クレーム無し）→ issue_recurring_tickets は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000001');
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が mark_messages_as_read を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon（クレーム無し）→ mark_messages_as_read の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon（クレーム無し）→ mark_messages_as_read は 42501（%）', SQLERRM;
  END;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(b): anon ロール + 顧客 C の JWT クレームでも 4 関数とも EXECUTE できない
--   (a) の SQLSTATE（42501）だけでは「クレーム無しで本文チェックに落ちた」のか「GRANT で落ちた」
--   のかを区別できない関数がある（docs/tasks/lessons.md「クレーム付き anon」）。ここでは auth.uid() が顧客 C を
--   返す状態のまま DB ロールだけ anon にし、GRANT 層で拒否されることを直接検証する。
--   calculate_achievement_rate(C, ...) は本文チェック上は本人として許可される呼び出しなので、
--   ここで 42501 になるのは anon の EXECUTE が剥奪されている場合だけ。
--   (a) と同じく、拒否の SQLERRM が 'permission denied for function ...'（GRANT 層）であることも確認する
-- -----------------------------------------------------------------------------
\echo '--- case b: anon ロール + 顧客(C) クレームでも 4 関数とも EXECUTE 拒否（42501 / GRANT 層）であること'

SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000011';
SET LOCAL ROLE anon;

DO $$
BEGIN
  -- 前提確認: auth.uid() が顧客 C を返している（クレームが効いている）こと。
  -- ここが NULL だと (a) と同じケースに退化してしまう
  IF auth.uid() IS DISTINCT FROM 'defd0000-0913-4000-8000-000000000011'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C の UUID）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  BEGIN
    PERFORM public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで calculate_achievement_rate を EXECUTE できてしまった（anon の EXECUTE が残っている）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon + 顧客(C) クレーム → calculate_achievement_rate の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon + 顧客(C) クレーム → calculate_achievement_rate は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70);
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで check_goal_achievement を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon + 顧客(C) クレーム → check_goal_achievement の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon + 顧客(C) クレーム → check_goal_achievement は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.issue_recurring_tickets();
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで issue_recurring_tickets を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon + 顧客(C) クレーム → issue_recurring_tickets の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon + 顧客(C) クレーム → issue_recurring_tickets は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000001');
    RAISE EXCEPTION 'FAIL: anon ロール + 顧客(C) クレームで mark_messages_as_read を EXECUTE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: anon + 顧客(C) クレーム → mark_messages_as_read の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: anon + 顧客(C) クレーム → mark_messages_as_read は 42501（%）', SQLERRM;
  END;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(c-1)(c-2): 本人クライアント C（Mobile の達成率表示と同じ経路）
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
--   期待値: 開始 80kg → 目標 70kg なので (80 - 現在) / (80 - 70) * 100 を 0〜100 に丸め、
--   小数 1 桁に四捨五入（75kg → 50.0 / 85kg → 0（下限）/ 65kg → 100（上限））
-- -----------------------------------------------------------------------------
\echo '--- case c-1: 本人(C) の calculate_achievement_rate(C, 75 / 85 / 65) が 50.0 / 0 / 100 であること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000011';

DO $$
DECLARE
  v numeric;
BEGIN
  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  IF v IS DISTINCT FROM 50.0 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) calculate_achievement_rate(C, 75) が %（期待 50.0）', coalesce(v::text, 'NULL');
  END IF;

  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 85);
  IF v IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) calculate_achievement_rate(C, 85) が %（期待 0 = 下限で丸め）', coalesce(v::text, 'NULL');
  END IF;

  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 65);
  IF v IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'FAIL: 本人(C) calculate_achievement_rate(C, 65) が %（期待 100 = 上限で丸め）', coalesce(v::text, 'NULL');
  END IF;

  RAISE NOTICE 'OK: 本人(C) の calculate_achievement_rate は 75kg=50.0 / 85kg=0 / 65kg=100';
END $$;

\echo '--- case c-2: 本人(C) から check_goal_achievement / issue_recurring_tickets が EXECUTE 拒否（42501 / GRANT 層）であること'

DO $$
BEGIN
  BEGIN
    PERFORM public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70);
    RAISE EXCEPTION 'FAIL: 本人(C) が check_goal_achievement を EXECUTE できてしまった（Edge Function 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: 本人(C) → check_goal_achievement の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 本人(C) → check_goal_achievement は 42501（authenticated に EXECUTE なし: %）', SQLERRM;
  END;

  BEGIN
    PERFORM public.issue_recurring_tickets();
    RAISE EXCEPTION 'FAIL: 本人(C) が issue_recurring_tickets を EXECUTE できてしまった（cron 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: 本人(C) → issue_recurring_tickets の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 本人(C) → issue_recurring_tickets は 42501（authenticated に EXECUTE なし: %）', SQLERRM;
  END;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d-1)(d-2): 他人のクライアント D
--   D は authenticated なので EXECUTE は通る。C の達成率は本文の呼び出し元チェックで
--   拒否されること（D は C 本人でも C の担当トレーナーでもない）。
--   D 自身のデータは開始体重 NULL・体重記録なしのため、目標 60kg と一致すれば 100、
--   それ以外は 0（リモート本文の分岐）
-- -----------------------------------------------------------------------------
\echo '--- case d-1: 他人クライアント(D) の calculate_achievement_rate(C, 75) が 42501 ACHIEVEMENT_RATE_FORBIDDEN であること（本文チェック）'

SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000012","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000012';

DO $$
BEGIN
  PERFORM public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  RAISE EXCEPTION 'FAIL: 他人クライアント(D) が C の calculate_achievement_rate を実行できてしまった（他人の体重進捗が漏れる）';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM IS DISTINCT FROM 'ACHIEVEMENT_RATE_FORBIDDEN' THEN
      RAISE EXCEPTION 'FAIL: 他人クライアント(D) → calculate_achievement_rate(C) の 42501 が本文チェックの拒否でない（期待 SQLERRM = ACHIEVEMENT_RATE_FORBIDDEN / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: 他人クライアント(D) → calculate_achievement_rate(C) は 42501 %（本文の呼び出し元チェック）', SQLERRM;
END $$;

\echo '--- case d-2: 他人クライアント(D) 自身の calculate_achievement_rate(D, 60 / 61) が 100 / 0 であること'

DO $$
DECLARE
  v numeric;
BEGIN
  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000012', 60);
  IF v IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION 'FAIL: D calculate_achievement_rate(D, 60) が %（期待 100 = 開始体重・体重記録なしで目標一致）', coalesce(v::text, 'NULL');
  END IF;

  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000012', 61);
  IF v IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'FAIL: D calculate_achievement_rate(D, 61) が %（期待 0 = 開始体重・体重記録なしで目標不一致）', coalesce(v::text, 'NULL');
  END IF;

  RAISE NOTICE 'OK: D 自身の calculate_achievement_rate は 60kg=100 / 61kg=0（本人は許可）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d-3): D の mark_messages_as_read(T)
--   本文は receiver_id = auth.uid() で絞るため、D 宛ての M3 だけが既読になり、
--   C 宛ての M1・M2 と C→T の M4 は未読のまま残ること。
--   C の既読化（c-3）より先に実行することで、D の呼び出しが C 宛てに波及していないことを
--   「M1・M2 が未読のまま」として観測できる
--   ※ 既読状態の確認は postgres（RLS バイパス）で行う。メッセージ ID 末尾 21〜24 = M1〜M4
-- -----------------------------------------------------------------------------
\echo '--- case d-3: 他人クライアント(D) の mark_messages_as_read(T) で M3 だけが既読になること'

DO $$
BEGIN
  PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000001');
END $$;

RESET ROLE;

DO $$
DECLARE
  v_read uuid[];
BEGIN
  SELECT coalesce(array_agg(m.id ORDER BY m.id), '{}') INTO v_read
  FROM public.messages m
  WHERE m.id IN ('defd0000-0913-4000-8000-000000000021',
                 'defd0000-0913-4000-8000-000000000022',
                 'defd0000-0913-4000-8000-000000000023',
                 'defd0000-0913-4000-8000-000000000024')
    AND m.read_at IS NOT NULL;
  IF v_read <> ARRAY['defd0000-0913-4000-8000-000000000023']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: D の mark_messages_as_read(T) 後の既読が %（期待 M3 のみ。M1・M2 は C 宛て、M4 は C→T）', v_read;
  END IF;
  RAISE NOTICE 'OK: D の既読化は D 宛ての M3 のみ（M1・M2・M4 は未読のまま）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c-3): 本人 C の mark_messages_as_read(T)（Mobile のトーク画面を開いたときの経路）
--   C 宛ての M1・M2 が既読になり、C が送信者の M4（C→T）は未読のまま残ること
-- -----------------------------------------------------------------------------
\echo '--- case c-3: 本人(C) の mark_messages_as_read(T) で M1・M2 が既読、M4 は未読のままであること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000011';

DO $$
BEGIN
  PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000001');
END $$;

RESET ROLE;

DO $$
DECLARE
  v_read uuid[];
BEGIN
  SELECT coalesce(array_agg(m.id ORDER BY m.id), '{}') INTO v_read
  FROM public.messages m
  WHERE m.id IN ('defd0000-0913-4000-8000-000000000021',
                 'defd0000-0913-4000-8000-000000000022',
                 'defd0000-0913-4000-8000-000000000023',
                 'defd0000-0913-4000-8000-000000000024')
    AND m.read_at IS NOT NULL;
  IF v_read <> ARRAY['defd0000-0913-4000-8000-000000000021',
                     'defd0000-0913-4000-8000-000000000022',
                     'defd0000-0913-4000-8000-000000000023']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: C の mark_messages_as_read(T) 後の既読が %（期待 M1・M2・M3。M4 は C→T なので未読のまま）', v_read;
  END IF;
  RAISE NOTICE 'OK: C の既読化で M1・M2 が既読（M4 は未読のまま）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c-4): 本人 C が calculate_achievement_rate に NULL / 存在しない顧客 X を渡す（本文チェック）
--   - NULL: 本文は本人判定を v_caller_uid IS DISTINCT FROM p_client_id で行う。<> だと
--     p_client_id が NULL のとき条件全体が NULL になって IF を素通り（= 許可）し、clients が
--     0 行 → 目標 NULL → 0 が返る。NULL が拒否側に倒れる（fail closed）ことを固定する
--   - 存在しない顧客 X: 本人でも担当顧客でもないので拒否されること（0 を返さないこと）。
--     0 が返る実装だと、他人の client_id が存在するかどうかを 0 / 42501 の違いで探れてしまう
--   前提確認（X が clients に無いこと）は RLS の影響を受けない postgres で行う
-- -----------------------------------------------------------------------------
\echo '--- case c-4: 本人(C) の calculate_achievement_rate(NULL, 75) / (存在しない顧客 X, 75) が 42501 ACHIEVEMENT_RATE_FORBIDDEN であること（本文チェック）'

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.clients c
    WHERE c.client_id = 'defd0000-0913-4000-8000-000000000019'
  ) THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 存在しない顧客として使う X（defd0000-0913-4000-8000-000000000019）が clients に存在する';
  END IF;
END $$;

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000011","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000011';

DO $$
DECLARE
  v numeric;
BEGIN
  BEGIN
    v := public.calculate_achievement_rate(NULL::uuid, 75);
    RAISE EXCEPTION 'FAIL: 本人(C) の calculate_achievement_rate(NULL, 75) が拒否されず % を返した（NULL が呼び出し元チェックを素通りしている）', coalesce(v::text, 'NULL');
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM IS DISTINCT FROM 'ACHIEVEMENT_RATE_FORBIDDEN' THEN
        RAISE EXCEPTION 'FAIL: 本人(C) → calculate_achievement_rate(NULL, 75) の 42501 が本文チェックの拒否でない（期待 SQLERRM = ACHIEVEMENT_RATE_FORBIDDEN / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 本人(C) → calculate_achievement_rate(NULL, 75) は 42501 %（NULL は拒否側に倒れる）', SQLERRM;
  END;

  BEGIN
    v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000019', 75);
    RAISE EXCEPTION 'FAIL: 本人(C) の calculate_achievement_rate(存在しない顧客 X, 75) が拒否されず % を返した（期待 42501。値を返すと顧客の存在確認に使える）', coalesce(v::text, 'NULL');
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM IS DISTINCT FROM 'ACHIEVEMENT_RATE_FORBIDDEN' THEN
        RAISE EXCEPTION 'FAIL: 本人(C) → calculate_achievement_rate(存在しない顧客 X, 75) の 42501 が本文チェックの拒否でない（期待 SQLERRM = ACHIEVEMENT_RATE_FORBIDDEN / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 本人(C) → calculate_achievement_rate(存在しない顧客 X, 75) は 42501 %（0 ではなく拒否）', SQLERRM;
  END;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e): 本人 E（開始体重 NULL → 最古の体重記録にフォールバック）
--   最古の W1 = 70kg を開始体重とみなし (70 - 65) / (70 - 60) * 100 = 50.0。
--   最新の W2 = 66kg を使うと 16.7 になる。
--   SET search_path = '' の下では weight_records を public. 修飾しないと到達できないため、
--   本ケースが通ることで public.weight_records への参照が正しいことも確認できる
-- -----------------------------------------------------------------------------
\echo '--- case e: 本人(E) の calculate_achievement_rate(E, 65) が 50.0 であること（最古の体重記録 70kg 起点）'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000013","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000013';

DO $$
DECLARE
  v numeric;
BEGIN
  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000013', 65);
  IF v IS DISTINCT FROM 50.0 THEN
    RAISE EXCEPTION 'FAIL: 本人(E) calculate_achievement_rate(E, 65) が %（期待 50.0 = 最古の体重記録 70kg 起点。16.7 なら最新の 66kg を使っている）', coalesce(v::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: 本人(E) の calculate_achievement_rate(E, 65) = 50.0（最古の体重記録 70kg にフォールバック）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): 担当トレーナー T
--   C の達成率は担当トレーナーとして許可（本文チェックの clients.trainer_id 分岐）。
--   check_goal_achievement / issue_recurring_tickets は authenticated に EXECUTE が無いので 42501。
--   mark_messages_as_read(C) で T 宛ての M4（C→T）が既読になること
-- -----------------------------------------------------------------------------
\echo '--- case f-1: 担当トレーナー(T) の calculate_achievement_rate(C, 75) が 50.0 であること'

SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000001';

DO $$
DECLARE
  v numeric;
BEGIN
  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  IF v IS DISTINCT FROM 50.0 THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) calculate_achievement_rate(C, 75) が %（期待 50.0）', coalesce(v::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) は C の calculate_achievement_rate を実行可（50.0）';
END $$;

\echo '--- case f-2: 担当トレーナー(T) から check_goal_achievement / issue_recurring_tickets が EXECUTE 拒否（42501 / GRANT 層）であること'

DO $$
BEGIN
  BEGIN
    PERFORM public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70);
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) が check_goal_achievement を EXECUTE できてしまった（Edge Function 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: 担当トレーナー(T) → check_goal_achievement の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 担当トレーナー(T) → check_goal_achievement は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.issue_recurring_tickets();
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) が issue_recurring_tickets を EXECUTE できてしまった（cron 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: 担当トレーナー(T) → issue_recurring_tickets の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: 担当トレーナー(T) → issue_recurring_tickets は 42501（%）', SQLERRM;
  END;
END $$;

\echo '--- case f-3: 担当トレーナー(T) の mark_messages_as_read(C) で M4 が既読になること'

DO $$
BEGIN
  PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000011');
END $$;

RESET ROLE;

DO $$
DECLARE
  v_read_at timestamptz;
BEGIN
  SELECT m.read_at INTO v_read_at
  FROM public.messages m
  WHERE m.id = 'defd0000-0913-4000-8000-000000000024';
  IF v_read_at IS NULL THEN
    RAISE EXCEPTION 'FAIL: 担当トレーナー(T) の mark_messages_as_read(C) 後も M4（C→T）が未読のまま';
  END IF;
  RAISE NOTICE 'OK: 担当トレーナー(T) の既読化で M4 が既読';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 他人トレーナー T2
--   authenticated なので EXECUTE は通るが、C 本人でも C の担当でもないため
--   本文の呼び出し元チェックで拒否されること
-- -----------------------------------------------------------------------------
\echo '--- case g: 他人トレーナー(T2) の calculate_achievement_rate(C, 75) が 42501 ACHIEVEMENT_RATE_FORBIDDEN であること（本文チェック）'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"defd0000-0913-4000-8000-000000000002","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'defd0000-0913-4000-8000-000000000002';

DO $$
BEGIN
  PERFORM public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  RAISE EXCEPTION 'FAIL: 他人トレーナー(T2) が C の calculate_achievement_rate を実行できてしまった（他トレーナーの顧客の体重進捗が漏れる）';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM IS DISTINCT FROM 'ACHIEVEMENT_RATE_FORBIDDEN' THEN
      RAISE EXCEPTION 'FAIL: 他人トレーナー(T2) → calculate_achievement_rate(C) の 42501 が本文チェックの拒否でない（期待 SQLERRM = ACHIEVEMENT_RATE_FORBIDDEN / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: 他人トレーナー(T2) → calculate_achievement_rate(C) は 42501 %（本文の呼び出し元チェック）', SQLERRM;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-1)(h-2): service_role（Edge Function parse-message-tags の RPC 相当）
--   service_role キーの JWT は sub を持たないため auth.uid() は NULL。
--   calculate_achievement_rate は本文チェックの「role クレーム = service_role」分岐で許可、
--   check_goal_achievement は service_role にだけ EXECUTE がある。
--   mark_messages_as_read（Mobile 専用）/ issue_recurring_tickets（cron 専用）は service_role
--   にも EXECUTE を与えない
--   期待値: C は開始 80kg > 目標 70kg の減量目標なので 現在 <= 70 で達成（70 → true / 70.1 → false）
-- -----------------------------------------------------------------------------
\echo '--- case h-1: service_role の calculate_achievement_rate(C, 75) = 50.0 / check_goal_achievement(C, 70 / 70.1) = true / false であること'

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v numeric;
  b boolean;
BEGIN
  -- 前提確認: sub の無いクレーム（auth.uid() が NULL）であること
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — service_role で auth.uid() が %（期待 NULL）', auth.uid();
  END IF;

  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  IF v IS DISTINCT FROM 50.0 THEN
    RAISE EXCEPTION 'FAIL: service_role calculate_achievement_rate(C, 75) が %（期待 50.0）', coalesce(v::text, 'NULL');
  END IF;

  b := public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70);
  IF b IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: service_role check_goal_achievement(C, 70) が %（期待 true = 目標ちょうど）', coalesce(b::text, 'NULL');
  END IF;

  b := public.check_goal_achievement('defd0000-0913-4000-8000-000000000011', 70.1);
  IF b IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: service_role check_goal_achievement(C, 70.1) が %（期待 false = 目標未達）', coalesce(b::text, 'NULL');
  END IF;

  RAISE NOTICE 'OK: service_role は calculate_achievement_rate(C, 75)=50.0 / check_goal_achievement(C, 70)=true・(C, 70.1)=false';
END $$;

\echo '--- case h-2: service_role から mark_messages_as_read / issue_recurring_tickets が EXECUTE 拒否（42501 / GRANT 層）であること'

DO $$
BEGIN
  BEGIN
    PERFORM public.mark_messages_as_read('defd0000-0913-4000-8000-000000000001');
    RAISE EXCEPTION 'FAIL: service_role が mark_messages_as_read を EXECUTE できてしまった（Mobile 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: service_role → mark_messages_as_read の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: service_role → mark_messages_as_read は 42501（%）', SQLERRM;
  END;

  BEGIN
    PERFORM public.issue_recurring_tickets();
    RAISE EXCEPTION 'FAIL: service_role が issue_recurring_tickets を EXECUTE できてしまった（cron 専用）';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function %' THEN
        RAISE EXCEPTION 'FAIL: service_role → issue_recurring_tickets の 42501 が GRANT 層の拒否でない（期待 SQLERRM LIKE ''permission denied for function %%'' / 実際 %）', SQLERRM;
      END IF;
      RAISE NOTICE 'OK: service_role → issue_recurring_tickets は 42501（%）', SQLERRM;
  END;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-3): authenticated ロール + sub の無いクレーム（role=authenticated）
--   本文チェックの「auth.uid() なし」側は、role クレームが service_role のときだけ許可し、
--   クレームがあるのに service_role でなければ 42501 にする仕様。
--   (h-1) だけでは「auth.uid() が NULL なら許可」という緩い実装でも PASS してしまうため、
--   その負の対照として sub の無い authenticated クレームが拒否されることを確認する
-- -----------------------------------------------------------------------------
\echo '--- case h-3: authenticated ロール + sub の無いクレームの calculate_achievement_rate(C, 75) が 42501 ACHIEVEMENT_RATE_FORBIDDEN であること（本文チェック）'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = '';

DO $$
BEGIN
  -- 前提確認: auth.uid() が NULL であること（sub が残っていると別のケースになる）
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — sub 無しクレームで auth.uid() が %（期待 NULL）', auth.uid();
  END IF;

  PERFORM public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  RAISE EXCEPTION 'FAIL: sub の無い authenticated クレームで calculate_achievement_rate を実行できてしまった（auth.uid() が NULL なら許可、になっている）';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM IS DISTINCT FROM 'ACHIEVEMENT_RATE_FORBIDDEN' THEN
      RAISE EXCEPTION 'FAIL: sub の無い authenticated クレーム → calculate_achievement_rate の 42501 が本文チェックの拒否でない（期待 SQLERRM = ACHIEVEMENT_RATE_FORBIDDEN / 実際 %）', SQLERRM;
    END IF;
    RAISE NOTICE 'OK: sub の無い authenticated クレーム → calculate_achievement_rate は 42501 %（service_role 以外のクレームは拒否）', SQLERRM;
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(i-1): オーナー / cron 経路（postgres・クレーム無し）
--   pg_cron は cron.job.username（= postgres = 関数オーナー）で別バックエンドから command を
--   実行する。ここでは登録済みの command 文字列（SELECT issue_recurring_tickets()）を
--   そのまま動的 EXECUTE し、関数名の解決も含めて cron と同じ呼び出しを再現する。
--   SET search_path = '' の下でも tickets / payments / ticket_subscriptions への書込みが
--   従来どおり動くこと（試験用サブスクリプション SUB の行に限定して検証）。
--   seed の期日到来サブスクリプションも同時に処理されうるため、件数は必ず試験用の
--   顧客 C / SUB に絞る（C のチケット・支払は本ケースで初めて作られる）
--   cron.job の一意キーは (jobname, username) で、同名ジョブが別ユーザーで複数行ありうる。
--   1 行に決め打ちせず、jobname = 'issue-recurring-tickets' の全行について実行ユーザーが
--   EXECUTE を持つことを確認する（0 行なら FAIL）。command の実行は先頭行（jobid 順）の
--   1 回だけ（複数回実行すると発行件数の検証が崩れるため）
-- -----------------------------------------------------------------------------
\echo '--- case i-1: cron ジョブ issue-recurring-tickets の全行の実行ユーザーが EXECUTE を持ち、command で試験用サブスクリプションが発行されること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  v_job      record;
  v_jobs     int := 0;
  v_command  text;
  v_jobid    bigint;
  v_username text;
  v_cnt      int;
  v_ticket   record;
  v_pay      record;
  v_next     date;
BEGIN
  FOR v_job IN
    SELECT j.jobid, j.command, j.username
    FROM cron.job j
    WHERE j.jobname = 'issue-recurring-tickets'
    ORDER BY j.jobid
  LOOP
    v_jobs := v_jobs + 1;

    -- 各行の実行ユーザーが EXECUTE を持つこと（持たないとその行の毎日の発行が permission denied で止まる）
    IF NOT has_function_privilege(v_job.username, 'public.issue_recurring_tickets()', 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: cron ジョブ issue-recurring-tickets（jobid=%）の実行ユーザー % が issue_recurring_tickets を EXECUTE できない',
        v_job.jobid, v_job.username;
    END IF;

    -- 実行するのは先頭行の command だけ
    IF v_jobs = 1 THEN
      v_jobid    := v_job.jobid;
      v_command  := v_job.command;
      v_username := v_job.username;
    END IF;
  END LOOP;

  IF v_jobs = 0 THEN
    RAISE EXCEPTION 'FAIL: cron ジョブ issue-recurring-tickets が登録されていない';
  END IF;

  -- cron と同じ command をそのまま実行する（先頭行の 1 回だけ）
  EXECUTE v_command;

  -- チケット: C 宛てに 1 枚だけ、価格スナップショット 10000 円・valid_from = 今日
  SELECT count(*) INTO v_cnt
  FROM public.tickets t
  WHERE t.client_id = 'defd0000-0913-4000-8000-000000000011';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 顧客 C のチケットが % 枚（期待 1 枚）', v_cnt;
  END IF;

  SELECT t.id, t.price_yen, t.valid_from INTO v_ticket
  FROM public.tickets t
  WHERE t.client_id = 'defd0000-0913-4000-8000-000000000011';
  IF v_ticket.price_yen IS DISTINCT FROM 10000 THEN
    RAISE EXCEPTION 'FAIL: 発行チケットの price_yen が %（期待 10000）', coalesce(v_ticket.price_yen::text, 'NULL');
  END IF;
  IF v_ticket.valid_from IS DISTINCT FROM CURRENT_DATE THEN
    RAISE EXCEPTION 'FAIL: 発行チケットの valid_from が %（期待 %）', v_ticket.valid_from, CURRENT_DATE;
  END IF;

  -- 支払記録: C の未払い 1 行（金額 10000 円・期日 今日・発行チケットと SUB に紐づく）
  SELECT count(*) INTO v_cnt
  FROM public.payments p
  WHERE p.client_id = 'defd0000-0913-4000-8000-000000000011';
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 顧客 C の payments が % 行（期待 1 行）', v_cnt;
  END IF;

  SELECT p.trainer_id, p.ticket_id, p.ticket_subscription_id, p.amount_yen, p.status, p.due_date
    INTO v_pay
  FROM public.payments p
  WHERE p.client_id = 'defd0000-0913-4000-8000-000000000011';
  IF v_pay.status IS DISTINCT FROM 'unpaid' THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の status が %（期待 unpaid）', v_pay.status;
  END IF;
  IF v_pay.amount_yen IS DISTINCT FROM 10000 THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の amount_yen が %（期待 10000）', v_pay.amount_yen;
  END IF;
  IF v_pay.due_date IS DISTINCT FROM CURRENT_DATE THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の due_date が %（期待 %）', coalesce(v_pay.due_date::text, 'NULL'), CURRENT_DATE;
  END IF;
  IF v_pay.ticket_id IS DISTINCT FROM v_ticket.id THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の ticket_id が %（期待 発行チケット %）', coalesce(v_pay.ticket_id::text, 'NULL'), v_ticket.id;
  END IF;
  IF v_pay.ticket_subscription_id IS DISTINCT FROM 'defd0000-0913-4000-8000-000000000051'::uuid THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の ticket_subscription_id が %（期待 SUB）', coalesce(v_pay.ticket_subscription_id::text, 'NULL');
  END IF;
  IF v_pay.trainer_id IS DISTINCT FROM 'defd0000-0913-4000-8000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL: 自動生成 payments の trainer_id が %（期待 テンプレートのトレーナー T）', v_pay.trainer_id;
  END IF;

  -- 次回発行日: 1 か月進む（関数と同じ interval 演算で期待値を作る）
  SELECT s.next_issue_date INTO v_next
  FROM public.ticket_subscriptions s
  WHERE s.id = 'defd0000-0913-4000-8000-000000000051';
  IF v_next IS DISTINCT FROM (CURRENT_DATE + interval '1 month')::date THEN
    RAISE EXCEPTION 'FAIL: SUB の next_issue_date が %（期待 %）', v_next, (CURRENT_DATE + interval '1 month')::date;
  END IF;

  RAISE NOTICE 'OK: cron ジョブ % 行すべての実行ユーザーが EXECUTE を持つ。先頭行（jobid=% / 実行ユーザー %）の command でチケット 1 枚・未払い payments 1 行を発行し、next_issue_date が % に進んだ',
    v_jobs, v_jobid, v_username, v_next;
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i-2): 直接 DB セッション（postgres・クレーム無し）
--   本文チェックの「クレーム自体が無い」分岐は許可されること（SQL エディタ・保守作業の経路）。
--   クレームは NULL ではなく空文字で「無し」を表している。PostgREST が SET LOCAL した
--   セッションはトランザクション終了後に空文字へ戻るため、実装は NULL と空文字を
--   同じ「クレーム無し」として扱うこと（auth.uid() / auth.jwt() も nullif(..., '') で同一視している）
-- -----------------------------------------------------------------------------
\echo '--- case i-2: postgres（クレーム無し）の calculate_achievement_rate(C, 75) が 50.0 であること'

DO $$
DECLARE
  v numeric;
BEGIN
  -- 前提確認: クレームが残っていないこと
  IF auth.uid() IS NOT NULL OR auth.jwt() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — クレームが残っている（auth.uid()=% / auth.jwt()=%）',
      coalesce(auth.uid()::text, 'NULL'), coalesce(auth.jwt()::text, 'NULL');
  END IF;

  v := public.calculate_achievement_rate('defd0000-0913-4000-8000-000000000011', 75);
  IF v IS DISTINCT FROM 50.0 THEN
    RAISE EXCEPTION 'FAIL: postgres（クレーム無し）calculate_achievement_rate(C, 75) が %（期待 50.0）', coalesce(v::text, 'NULL');
  END IF;
  RAISE NOTICE 'OK: postgres（クレーム無し = 直接 DB セッション）は calculate_achievement_rate を実行可（50.0）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(j): 定義の固定（カタログ検査。postgres として実行）
--   - prosecdef: SECURITY DEFINER のまま（本是正は実行モデルを変えず、呼び出し可否を GRANT と本文の呼び出し元チェックで決める。INVOKER 化は RLS 前提の別設計）
--   - proconfig: {search_path=""} ちょうど（SET search_path = ''。public 等を残すと
--     search_path 乗っ取りの余地が残る）
--   - owner: postgres（cron の実行ユーザー / RLS バイパスの前提）
--   - proacl: NULL でない（NULL = 既定権限 = PUBLIC に EXECUTE がある状態）
--   - PUBLIC（grantee = 0）への付与が ACL に無い（REVOKE ... FROM PUBLIC 済み）
--   - ACL の grantee 集合がちょうど期待どおり（上表の ○ のロール + オーナー postgres）。
--     has_function_privilege は anon / authenticated / service_role の 3 ロールしか見ないため、
--     それ以外のロール（例: 既定権限で付与されたロール）への付与が残っていても気付けない。
--     集合一致で余計な grantee が無いことを固定する。pg_get_userbyid(0) は 'unknown (OID=0)' を
--     返すので PUBLIC もこの比較で不一致になるが、原因を明示するため上の grantee = 0 検査も残す。
--     （pg_get_userbyid は name 型を返し、name[] と text[] は比較できないため text にキャストする。
--       DISTINCT 付きの集約では ORDER BY に引数と同じ式を書く必要がある）
--   - has_function_privilege の EXECUTE マトリクスが上表どおり
-- -----------------------------------------------------------------------------
\echo '--- case j: 4 関数の定義固定（SECURITY DEFINER / search_path 空文字 / owner / ACL の grantee 集合 / EXECUTE マトリクス）'

DO $$
DECLARE
  r          record;
  v_fn       record;
  v_got      boolean;
  v_grantees text[];
BEGIN
  FOR r IN
    SELECT *
    FROM (VALUES
      ('public.calculate_achievement_rate(uuid, numeric)', false, true,  true,  ARRAY['authenticated', 'postgres', 'service_role']),
      ('public.check_goal_achievement(uuid, numeric)',     false, false, true,  ARRAY['postgres', 'service_role']),
      ('public.issue_recurring_tickets()',                 false, false, false, ARRAY['postgres']),
      ('public.mark_messages_as_read(uuid)',               false, true,  false, ARRAY['authenticated', 'postgres'])
    ) AS t(sig, exp_anon, exp_authenticated, exp_service_role, exp_grantees)
  LOOP
    SELECT p.oid, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) AS owner, p.proacl
      INTO v_fn
    FROM pg_proc p
    WHERE p.oid = to_regprocedure(r.sig);

    IF v_fn.oid IS NULL THEN
      RAISE EXCEPTION 'FAIL: % が存在しない', r.sig;
    END IF;
    IF v_fn.prosecdef IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'FAIL: % が SECURITY DEFINER でない', r.sig;
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
    IF EXISTS (SELECT 1 FROM aclexplode(v_fn.proacl) a WHERE a.grantee = 0) THEN
      RAISE EXCEPTION 'FAIL: % の ACL に PUBLIC への付与が残っている（%）', r.sig, v_fn.proacl;
    END IF;

    SELECT array_agg(DISTINCT pg_get_userbyid(a.grantee)::text ORDER BY pg_get_userbyid(a.grantee)::text)
      INTO v_grantees
    FROM aclexplode(v_fn.proacl) a;
    IF v_grantees IS DISTINCT FROM r.exp_grantees THEN
      RAISE EXCEPTION 'FAIL: % の ACL の grantee 集合が %（期待 % ちょうど。ACL %）',
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

    RAISE NOTICE 'OK: % — SECURITY DEFINER / search_path 空文字 / owner postgres / PUBLIC なし / grantee=% / anon=% authenticated=% service_role=%',
      r.sig, v_grantees, r.exp_anon, r.exp_authenticated, r.exp_service_role;
  END LOOP;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL DEFINER FUNCTION PRIVILEGE TESTS PASSED'
