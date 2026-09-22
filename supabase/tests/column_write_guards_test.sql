-- =============================================================================
-- clients / messages 列単位の書き込みガード テスト
-- （20260922000200_column_write_guards.sql）
--
-- 背景: 行レベルの WITH CHECK は所有者列（clients.client_id / messages.sender_id
-- / receiver_id）しか縛っておらず、それ以外の列はエンドユーザーが自由に書けた。
--   - 顧客が自分の clients 行の trainer_id（任意のトレーナーへの付け替え）・
--     created_at（'-infinity' 等）・トレーナーが決める列（目標体重など）を書き換え可能
--   - messages の INSERT で receiver_id / sender_type / read_at / created_at を偽装可能
--   - messages の UPDATE で送信者は全列（受信者・既読・作成日時 = 編集可能時間の延長）、
--     受信者も全列（本文・タグ・メタデータ）を書き換え可能
--   - anon にも INSERT / UPDATE の GRANT が残っていた（20251230131753 の GRANT ALL）
-- 本テストは、正規の書き込み経路（Mobile / Web / Edge Function / DEFINER 関数）を
-- 壊さずに、上記の不正な書き込みだけが拒否されることを検証する。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/column_write_guards_test.sql
--   ※ コンテナ名は環境に合わせて読み替える
--     （本ブランチの開発時は隔離スタック supabase_db_fit-connect-colguard を使用）
--
-- - 全ケース成功時のみ最終行に「ALL COLUMN WRITE GUARDS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--   （messages への INSERT では AFTER トリガー call_parse_message_tags が発火する。
--     20260922000100 以降、Vault に project_url / secret_key が無いローカルでは POST しない。
--     登録済みの環境でも pg_net のキューはトランザクション内なので ROLLBACK で送信されずに
--     消える。本ファイルを COMMIT に書き換えないこと）
-- - マイグレーション未適用の DB では case a1 で FAIL する（TDD の RED 確認用）
-- - 前提 migration: 20260913000500（mark_messages_as_read の取り込み）/
--   20260913000510（同関数の search_path = '' 化・EXECUTE 最小化）/
--   20260922000200（本ガード）。f5 は本物の mark_messages_as_read を必須とする
--
-- 拒否の判定基準（「別の理由で落ちたのに PASS」「0 行 no-op なのに PASS」を防ぐ）:
--   - トリガーによる拒否: SQLSTATE = '42501' かつ SQLERRM = 固定コード の完全一致
--       CLIENTS_PROTECTED_COLUMN / MESSAGES_SENDER_MISMATCH /
--       MESSAGES_INVALID_SENDER_TYPE / MESSAGES_RECEIVER_NOT_COUNTERPART /
--       MESSAGES_REPLY_OUTSIDE_CONVERSATION / MESSAGES_COLUMN_NOT_UPDATABLE /
--       MESSAGES_READ_AT_IMMUTABLE / ANON_WRITE_FORBIDDEN
--   - 列権限（GRANT）による拒否・anon の拒否: SQLSTATE = '42501' かつ
--     SQLERRM LIKE 'permission denied%'
--   - 例外が出ずに終わった場合は ROW_COUNT が 0 でも FAIL（UPDATE の拒否ケースは
--     事前に対象行がそのユーザーから見えることを確認してから実行する）
--   - 強制される値（created_at / read_at / is_edited / edited_at / updated_at）は
--     読み戻して値そのものを検証する（now() はトランザクション開始時刻で一定）
--
-- 検証ケース:
--   A. clients 禁止系（顧客 C / authenticated。先に C の行が C から見えることを確認）
--     a1  trainer_id を T2 へ変更 → CLIENTS_PROTECTED_COLUMN
--     a1b trainer_id を NULL へ（担当外し）→ CLIENTS_PROTECTED_COLUMN
--         （NOT NULL 制約より先に BEFORE トリガーが評価される）
--     a2  created_at = '-infinity' → permission denied（列権限）
--     a3  トレーナー所有列（occupation, height, target_weight, purpose,
--         goal_description, goal_deadline, initial_weight, goal_set_at,
--         goal_achieved_at, line_user_id）を 1 列ずつ UPDATE → 各 permission denied
--     a4  client_id を別 UUID へ変更 → 42501（RLS WITH CHECK 違反 または
--         CLIENTS_PROTECTED_COLUMN のどちらでも可）
--     a5  登録 upsert の形（ON CONFLICT (client_id) DO UPDATE）で既存行の
--         trainer_id を T2 へ → CLIENTS_PROTECTED_COLUMN
--     a6  未登録ユーザー N が created_at を含めて INSERT → permission denied
--     a7  未登録ユーザー N が target_weight を含めて INSERT → permission denied
--     a8  anon + 顧客 C のクレーム: UPDATE name / UPDATE trainer_id → permission denied、
--         anon + N のクレーム: INSERT → permission denied
--     a9  拒否後も C の行（trainer_id / created_at / トレーナー所有列）が不変
--   B. clients 正規経路（回帰確認）
--     b1  C が name / profile_image_url / fcm_token（設定→NULL）/
--         onboarding_completed_at（端末時刻）を個別に UPDATE → 各 1 行・値が保存される
--     b2  N の新規登録（PostgREST の upsert 形そのまま）→ 成功。created_at = now()、
--         trainer_id = T、トレーナー所有列は既定値
--     b3  N が同じ trainer_id で upsert を再送（衝突経路）→ 1 行・created_at 不変
--     b4  service_role: updateClient.ts の形 / trainer_id 付け替えと戻し /
--         created_at / 残りのトレーナー所有列 → すべて成功
--   C. messages INSERT 禁止系（authenticated）
--     c1  C → T2（担当外トレーナー）→ MESSAGES_RECEIVER_NOT_COUNTERPART
--     c2  C が sender_type 'trainer' を詐称（受信者 C / E）→ MESSAGES_INVALID_SENDER_TYPE
--     c3  C が receiver_type 'client' で受信者 T → MESSAGES_RECEIVER_NOT_COUNTERPART
--     c4  sender_type ''（明示）/ 省略（列既定値 ''）/ 'admin' → MESSAGES_INVALID_SENDER_TYPE
--     c5  T → D（D は T2 の顧客）→ MESSAGES_RECEIVER_NOT_COUNTERPART
--     c6  T が sender_type 'client' を詐称 → MESSAGES_INVALID_SENDER_TYPE
--     c7  C が sender_id = E で送信 → MESSAGES_SENDER_MISMATCH
--     c8  C → T で reply_to_message_id = M4（別会話）→ MESSAGES_REPLY_OUTSIDE_CONVERSATION
--     c8b T → C で reply_to_message_id = M9（T↔E の会話。T からは見える）
--         → MESSAGES_REPLY_OUTSIDE_CONVERSATION（「自分に見える」だけの判定への
--           弱体化を検出。c8 の M4 は C から見えないので区別できない）
--     c11 T → 自分の顧客 C だが receiver_type 'trainer' → MESSAGES_RECEIVER_NOT_COUNTERPART
--     c12 T → 別トレーナー T2（receiver_type 'trainer' / 'client'）
--         → 各 MESSAGES_RECEIVER_NOT_COUNTERPART
--     c9  C → T で read_at / created_at / edited_at / is_edited / updated_at を指定
--         → INSERT は成功するが保存値は read_at NULL / created_at now() /
--           edited_at NULL / is_edited false / updated_at now() に強制される
--     c10 anon + 顧客 C のクレーム: INSERT C → T → permission denied
--   D. messages UPDATE 受信者の禁止系（d1 は T が M1 の受信者）
--     d1  id / content / tags / metadata / image_urls / sender_id / receiver_id /
--         receiver_type / sender_type / created_at / reply_to_message_id /
--         is_edited / edited_at を 1 列ずつ → 各 MESSAGES_COLUMN_NOT_UPDATABLE（M1 は不変）
--     d2  既読済みメッセージの read_at を NULL に戻す / 別時刻に付け替える
--         （受信者 T が M6、受信者 C が M5）→ 各 MESSAGES_READ_AT_IMMUTABLE（read_at 不変）
--   E. messages UPDATE 送信者の禁止系（e1 は C が M1 の送信者。5 分以内）
--     e1  id / receiver_id / receiver_type / sender_type / created_at（編集可能時間の延長）/
--         read_at / metadata / image_urls / reply_to_message_id を 1 列ずつ
--         → 各 MESSAGES_COLUMN_NOT_UPDATABLE（M1 は不変）
--     e2  10 分前の M3 の content → 0 行（RLS の 5 分制限。従来どおり）・本文不変
--     e3  anon + 顧客 C のクレーム: M1 の content UPDATE → permission denied、
--         anon + T のクレーム: M1 の read_at UPDATE → permission denied
--     e4  自分宛てメッセージ（送信者 = 受信者 = T）。受信者ポリシーは 5 分を過ぎても
--         行を通すため、送信者の編集権限は 5 分以内に限ることをガード側でも担保する
--       e4a 10 分前の M7 の content → MESSAGES_COLUMN_NOT_UPDATABLE（M7 不変）
--       e4b 10 分前の M7 の read_at を NULL → 値 → 可（1 行・read_at = now()）
--       e4c 5 分以内の M8 の content → 可（is_edited = true / edited_at = now()）
--   F. messages 正規経路（回帰確認）
--     f1  Mobile 送信の形（食事: 画像・タグ・同一会話への返信・metadata あり /
--         ワークアウト完了: image_urls NULL・返信なし）→ 成功
--     f2  T → C（authenticated で送信）→ 成功
--     f3  Mobile 編集の形（content / tags=NULL / is_edited=true /
--         edited_at=オフセット無しの端末ローカル時刻）→ 1 行。edited_at は now() に強制
--     f3b 送信者が content だけ変更 → is_edited = true / edited_at = now() に強制
--     f3d 送信者が edited_at だけ / is_edited = false だけを送る（content / tags 不変）
--         → 1 行・is_edited / edited_at は送信前の値のまま
--         （未編集の M10: false / NULL のまま、編集済みの M11: true / now()-2分 のまま）
--     f3c 送信者が content = 'x', is_edited = false を送る（M10）
--         → is_edited = true / edited_at = now() に強制
--     f4  Web markMessagesAsRead の形（read_at = ブラウザ時計の ISO 文字列）
--         → 未読の C→T 全件が 1 回で既読。read_at は now() に強制、他の列は不変
--     f5  SECURITY DEFINER 経路（本物の public.mark_messages_as_read。無ければ FAIL）
--         を C が呼ぶ → M2 の read_at = now()
--     f6  service_role: Web 送信の形 INSERT / Web 編集の形 UPDATE（値はそのまま保存）/
--         tags のみ UPDATE（parse-message-tags バックフィル）/
--         created_at・read_at・receiver_id の自由な UPDATE → すべて成功
--   H. ANON_WRITE_FORBIDDEN（トリガー側の anon 分岐）
--     通常は anon の GRANT 剥奪で権限チェックが先に落ち、トリガーの anon 分岐に
--     到達しない。GRANT ALL が anon に戻った場合の二重防御を検証するため、
--     トランザクション内で一時的に anon へ INSERT / UPDATE を GRANT して確認し、
--     G の前に REVOKE し直す（G のカタログ確認を意味のあるものに保つ）
--     h1  anon + C のクレーム: messages INSERT C → T → ANON_WRITE_FORBIDDEN
--     h2  anon + C のクレーム: 送信者として MA の content UPDATE → ANON_WRITE_FORBIDDEN
--     h3  anon + T のクレーム: 受信者として未読 MA の read_at UPDATE → ANON_WRITE_FORBIDDEN
--     h4  anon + N2（未登録）のクレーム: clients INSERT → ANON_WRITE_FORBIDDEN
--     h5  anon + C のクレーム: clients の name UPDATE → 0 行・不変
--         （clients_update_own は TO authenticated のため、トリガーより先に RLS が行を除外）
--     h6  REVOKE 後に anon の INSERT / UPDATE 権限が無いこと（G の前提）
--   G. カタログ確認（postgres）
--     g1  トリガー 3 本（clients_guard_protected_columns / messages_guard_insert /
--         messages_guard_update）が存在・有効・BEFORE ROW・対象イベント・列指定なし
--     g2  ガード関数が SECURITY DEFINER でなく、proconfig に search_path="" を持ち、
--         anon / authenticated に EXECUTE が無い
--     g3  anon に clients / messages の INSERT / UPDATE（列単位含む）と
--         messages の DELETE が無い
--     g4  authenticated の clients 列権限が設計どおり
--         （INSERT: client_id, trainer_id, name, email, age, gender のみ /
--           UPDATE: 上記 + profile_image_url, fcm_token, onboarding_completed_at のみ。
--           created_at / target_weight は不可、name / trainer_id は可）
--     g5  authenticated の messages INSERT / UPDATE、service_role の書き込み権限は残っている
--     g6  authenticator（PostgREST の接続ロール）の所属ロールがちょうど
--         {anon, authenticated, service_role}（直接・推移とも）。ガードは anon /
--         authenticated 以外の current_user を素通しにするため、PostgREST が
--         SET ROLE できるロールがこの 3 つに限られている間だけ安全
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 判定ヘルパー（pg_temp に作成。セッションローカルで ROLLBACK と共に消える）
--   SECURITY INVOKER（既定）のため、呼び出し時の current_user
--   （authenticated / anon / service_role）のまま DML が実行される。
--   EXECUTE は PUBLIC 既定付与のため全ロールから呼べる
--
--   cg_expect_reject(case, sql, 完全一致候補[], LIKE 候補[])
--     : 例外が出なければ FAIL（ROW_COUNT も表示）。SQLSTATE が 42501 でない、
--       または SQLERRM が候補のどれにも一致しなければ FAIL
--   cg_expect_code(case, sql, 固定コード)  : トリガー拒否（SQLERRM 完全一致）
--   cg_expect_denied(case, sql)            : 権限拒否（'permission denied%'）
--   cg_expect_rows(case, sql, 期待行数)    : 正規経路。例外・行数違いは FAIL
-- -----------------------------------------------------------------------------
\echo '--- setup: 判定ヘルパー作成'

CREATE FUNCTION pg_temp.cg_expect_reject(
  p_case  text,
  p_sql   text,
  p_exact text[],
  p_like  text[]
) RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_rows   bigint;
  v_state  text;
  v_msg    text;
  v_raised boolean := false;
BEGIN
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      v_raised := true;
  END;

  IF NOT v_raised THEN
    RAISE EXCEPTION 'FAIL: [%] 拒否されずに実行された (ROW_COUNT=%, current_user=%, auth.uid()=%) SQL: %',
      p_case, v_rows, current_user, coalesce(auth.uid()::text, 'NULL'), p_sql;
  END IF;

  IF v_state IS DISTINCT FROM '42501'
     OR NOT (coalesce(v_msg = ANY (p_exact), false)
             OR coalesce(v_msg LIKE ANY (p_like), false)) THEN
    RAISE EXCEPTION 'FAIL: [%] 期待と異なるエラー SQLSTATE=% SQLERRM=% （期待 SQLSTATE=42501 / SQLERRM=%） SQL: %',
      p_case, v_state, v_msg,
      array_to_string(coalesce(p_exact, '{}'::text[]) || coalesce(p_like, '{}'::text[]), ' または '),
      p_sql;
  END IF;

  RAISE NOTICE 'OK: [%] 42501 / % で拒否', p_case, v_msg;
END
$fn$;

CREATE FUNCTION pg_temp.cg_expect_code(p_case text, p_sql text, p_code text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM pg_temp.cg_expect_reject(p_case, p_sql, ARRAY[p_code], NULL);
END
$fn$;

CREATE FUNCTION pg_temp.cg_expect_denied(p_case text, p_sql text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM pg_temp.cg_expect_reject(p_case, p_sql, NULL, ARRAY['permission denied%']);
END
$fn$;

CREATE FUNCTION pg_temp.cg_expect_rows(p_case text, p_sql text, p_rows bigint)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_rows  bigint;
  v_state text;
  v_msg   text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      RAISE EXCEPTION 'FAIL: [%] 正規経路が失敗した SQLSTATE=% SQLERRM=% (current_user=%) SQL: %',
        p_case, v_state, v_msg, current_user, p_sql;
  END;

  IF v_rows IS DISTINCT FROM p_rows THEN
    RAISE EXCEPTION 'FAIL: [%] ROW_COUNT=% （期待 %） SQL: %', p_case, v_rows, p_rows, p_sql;
  END IF;

  RAISE NOTICE 'OK: [%] % 行', p_case, v_rows;
END
$fn$;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス・ガード対象外ロール）
--   trainer T : aaaaaaaa-9922-0000-0000-00000000000a（メインのトレーナー）
--   trainer T2: aaaaaaaa-9922-0000-0000-0000000000a2（別のトレーナー）
--   client  C : bbbbbbbb-9922-0000-0000-00000000000b（T の顧客。本人）
--   client  E : eeeeeeee-9922-0000-0000-00000000000e（T の 2 人目の顧客）
--   client  D : dddddddd-9922-0000-0000-00000000000d（T2 の顧客）
--   user    N : ffffffff-9922-0000-0000-00000000000f（auth.users のみ。clients 行は未作成
--               = 新規登録ケース用）
--   user    N2: ffffffff-9922-0000-0000-0000000000f2（auth.users のみ。clients 行は最後まで
--               未作成 = h4 の anon 登録ケース用。N は b2 で登録済みになるため別に用意）
--   C の created_at は判別用に固定値 2026-01-15 00:00:00+00 にしておく
--   （「不変」の検証が now() と区別できるように）
--
--   message M1: 11111111-9922-0000-0000-000000000001  C→T  created_at now()      未読
--   message M2: 22222222-9922-0000-0000-000000000002  T→C  created_at now()      未読
--   message M3: 33333333-9922-0000-0000-000000000003  C→T  created_at now()-10分 未読
--   message M4: 44444444-9922-0000-0000-000000000004  D→T2（別の会話）
--   message M5: 55555555-9922-0000-0000-000000000005  T→C  既読（read_at now()-1時間）
--   message M6: 66666666-9922-0000-0000-000000000006  C→T  既読（read_at now()-1時間。
--               受信者 T 側の既読取り消し・付け替え検証用）
--   message M7: 77777777-9922-0000-0000-000000000007  T→T  created_at now()-10分 未読
--               （自分宛て。送信者 = 受信者。e4a / e4b 用）
--   message M8: 88888888-9922-0000-0000-000000000008  T→T  created_at now()      未読
--               （自分宛て。e4c 用）
--   message M9: 99999999-9922-0000-0000-000000000009  T→E（T からは見える別会話。c8b 用）
--   message M10: 10101010-9922-0000-0000-000000000010 C→T  created_at now()      未読・未編集
--               （is_edited false / edited_at NULL。f3d / f3c 専用）
--   message M11: 11111111-9922-0000-0000-000000000011 C→T  created_at now()-3分  未読・編集済み
--               （is_edited true / edited_at now()-2分。f3d 専用）
--   ※ anon 分岐（section H）用の MA は f4 の一括既読化の影響を避けるため H の直前に作成する
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T・T2 / client C・E・D / user N・N2 / message M1〜M11)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('aaaaaaaa-9922-0000-0000-00000000000a', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-t@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('aaaaaaaa-9922-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-t2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('bbbbbbbb-9922-0000-0000-00000000000b', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-c@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('eeeeeeee-9922-0000-0000-00000000000e', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-e@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('dddddddd-9922-0000-0000-00000000000d', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-d@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('ffffffff-9922-0000-0000-00000000000f', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-n@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''),
  ('ffffffff-9922-0000-0000-0000000000f2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'rls-test-colguard-n2@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.trainers (id, name, email) VALUES
  ('aaaaaaaa-9922-0000-0000-00000000000a', 'RLSテスト トレーナーT',
   'rls-test-colguard-t@example.com'),
  ('aaaaaaaa-9922-0000-0000-0000000000a2', 'RLSテスト トレーナーT2',
   'rls-test-colguard-t2@example.com');

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('bbbbbbbb-9922-0000-0000-00000000000b', 'RLSテスト顧客C',
   'aaaaaaaa-9922-0000-0000-00000000000a', '2026-01-15 00:00:00+00'),
  ('eeeeeeee-9922-0000-0000-00000000000e', 'RLSテスト顧客E',
   'aaaaaaaa-9922-0000-0000-00000000000a', now()),
  ('dddddddd-9922-0000-0000-00000000000d', 'RLSテスト顧客D',
   'aaaaaaaa-9922-0000-0000-0000000000a2', now());

INSERT INTO public.messages (
  id, sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at
) VALUES
  ('11111111-9922-0000-0000-000000000001',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'M1 C→T 未読', now(), NULL),
  ('22222222-9922-0000-0000-000000000002',
   'aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
   'trainer', 'client', 'M2 T→C 未読', now(), NULL),
  ('33333333-9922-0000-0000-000000000003',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'M3 C→T 10分前', now() - interval '10 minutes', NULL),
  ('44444444-9922-0000-0000-000000000004',
   'dddddddd-9922-0000-0000-00000000000d', 'aaaaaaaa-9922-0000-0000-0000000000a2',
   'client', 'trainer', 'M4 D→T2 別会話', now(), NULL),
  ('55555555-9922-0000-0000-000000000005',
   'aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
   'trainer', 'client', 'M5 T→C 既読', now() - interval '2 hours', now() - interval '1 hour'),
  ('66666666-9922-0000-0000-000000000006',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'M6 C→T 既読', now() - interval '2 hours', now() - interval '1 hour'),
  ('77777777-9922-0000-0000-000000000007',
   'aaaaaaaa-9922-0000-0000-00000000000a', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'trainer', 'trainer', 'M7 T→T 自分宛て 10分前', now() - interval '10 minutes', NULL),
  ('88888888-9922-0000-0000-000000000008',
   'aaaaaaaa-9922-0000-0000-00000000000a', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'trainer', 'trainer', 'M8 T→T 自分宛て', now(), NULL),
  ('99999999-9922-0000-0000-000000000009',
   'aaaaaaaa-9922-0000-0000-00000000000a', 'eeeeeeee-9922-0000-0000-00000000000e',
   'trainer', 'client', 'M9 T→E 別会話', now(), NULL);

INSERT INTO public.messages (
  id, sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at,
  is_edited, edited_at
) VALUES
  ('10101010-9922-0000-0000-000000000010',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'M10 C→T 未編集', now(), NULL,
   false, NULL),
  ('11111111-9922-0000-0000-000000000011',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'M11 C→T 編集済み', now() - interval '3 minutes', NULL,
   true, now() - interval '2 minutes');

-- =============================================================================
-- [section:A] clients — 禁止系
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 前提: 顧客 C から自分の行が見える（UPDATE の対象になりうる）こと。
--   見えない状態だと UPDATE が 0 行 no-op になり、拒否の検証にならない
-- -----------------------------------------------------------------------------
\echo '--- case a0: 前提確認（顧客 C から自分の clients 行が 1 行見えること）'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE cnt int;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: a0 前提崩れ — auth.uid() が % （期待 顧客C）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT count(*) INTO cnt FROM public.clients
  WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: a0 前提崩れ — 顧客 C から自分の行が % 行（期待 1 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: a0 顧客 C から自分の clients 行が 1 行見える';
END $$;

-- -----------------------------------------------------------------------------
-- ケース a1: trainer_id の付け替え（任意のトレーナーへの紐づけ）は拒否
--   authenticated は登録 upsert のため trainer_id の UPDATE 列権限を持つので、
--   「同じ値なら可・違う値なら不可」はトリガーで判定される
-- -----------------------------------------------------------------------------
\echo '--- case a1: 顧客 C が trainer_id を T2 へ変更できないこと (CLIENTS_PROTECTED_COLUMN)'

DO $$
BEGIN
  PERFORM pg_temp.cg_expect_code(
    'a1 clients.trainer_id → T2',
    $sql$UPDATE public.clients
         SET trainer_id = 'aaaaaaaa-9922-0000-0000-0000000000a2'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$,
    'CLIENTS_PROTECTED_COLUMN');
END $$;

-- -----------------------------------------------------------------------------
-- ケース a1b: trainer_id を NULL にする（担当外し）のも拒否
--   trainer_id は NOT NULL だが、制約チェック（23502）は BEFORE トリガーの後に行われる。
--   ガードが「T2 への付け替え」だけでなく値の変化そのものを拒否していることを、
--   not_null_violation ではなく固定コードで確認する
-- -----------------------------------------------------------------------------
\echo '--- case a1b: 顧客 C が trainer_id を NULL にできないこと (CLIENTS_PROTECTED_COLUMN)'

DO $$
BEGIN
  PERFORM pg_temp.cg_expect_code(
    'a1b clients.trainer_id → NULL',
    $sql$UPDATE public.clients
         SET trainer_id = NULL
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$,
    'CLIENTS_PROTECTED_COLUMN');
END $$;

-- -----------------------------------------------------------------------------
-- ケース a2: created_at の改ざん（Phase 9 の顧客アラートは created_at を登録日とする）
--   authenticated に created_at の UPDATE 列権限が無いことで拒否される
-- -----------------------------------------------------------------------------
\echo '--- case a2: 顧客 C が created_at を -infinity にできないこと (permission denied)'

DO $$
BEGIN
  PERFORM pg_temp.cg_expect_denied(
    'a2 clients.created_at = -infinity',
    $sql$UPDATE public.clients
         SET created_at = '-infinity'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$);
END $$;

-- -----------------------------------------------------------------------------
-- ケース a3: トレーナーが決める列は顧客から 1 列ずつ UPDATE できない
--   値は CHECK 制約を満たすもの（制約違反 23514 で落ちて偽陽性にならないように）
-- -----------------------------------------------------------------------------
\echo '--- case a3: 顧客 C がトレーナー所有列を 1 列ずつ更新できないこと (permission denied)'

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('occupation',       '''会社員'''),
      ('height',           '171'),
      ('target_weight',    '55'),
      ('purpose',          '''diet'''),
      ('goal_description', '''顧客が勝手に書いた目標'''),
      ('goal_deadline',    '''2030-12-31''::date'),
      ('initial_weight',   '70'),
      ('goal_set_at',      '''2000-01-01 00:00:00+00''::timestamptz'),
      ('goal_achieved_at', '''2000-01-01 00:00:00+00''::timestamptz'),
      ('line_user_id',     '''U-rls-test-colguard-9922''')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.cg_expect_denied(
      format('a3 clients.%s', r.col),
      format('UPDATE public.clients SET %I = %s WHERE client_id = %L',
             r.col, r.val, 'bbbbbbbb-9922-0000-0000-00000000000b'));
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース a4: client_id の変更は拒否
--   RLS WITH CHECK (client_id = auth.uid()) 違反・トリガーの CLIENTS_PROTECTED_COLUMN
--   のどちらで落ちてもよいが、42501 で拒否されること
-- -----------------------------------------------------------------------------
\echo '--- case a4: 顧客 C が client_id を別 UUID へ変更できないこと (42501)'

DO $$
BEGIN
  PERFORM pg_temp.cg_expect_reject(
    'a4 clients.client_id → 別 UUID',
    $sql$UPDATE public.clients
         SET client_id = '00000000-9922-0000-0000-0000000000a4'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$,
    ARRAY['CLIENTS_PROTECTED_COLUMN'],
    ARRAY['new row violates row-level security policy%']);
END $$;

-- -----------------------------------------------------------------------------
-- ケース a5: 登録 upsert の形で既存行の trainer_id を変える抜け道も拒否
--   supabase-dart の upsert(onConflict: 'client_id') は
--   INSERT ... ON CONFLICT (client_id) DO UPDATE SET <全ペイロード列> = EXCLUDED.<列>
--   を発行する。衝突時は UPDATE 経路になるためトリガーで拒否される
-- -----------------------------------------------------------------------------
\echo '--- case a5: 登録 upsert の形で既存行の trainer_id を T2 へ変えられないこと (CLIENTS_PROTECTED_COLUMN)'

DO $$
BEGIN
  PERFORM pg_temp.cg_expect_code(
    'a5 clients upsert（既存行・trainer_id 違い）',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b',
                 'aaaaaaaa-9922-0000-0000-0000000000a2',
                 'RLSテスト顧客C', 'rls-test-colguard-c@example.com', 30, 'male')
         ON CONFLICT (client_id) DO UPDATE SET
           client_id  = EXCLUDED.client_id,
           trainer_id = EXCLUDED.trainer_id,
           name       = EXCLUDED.name,
           email      = EXCLUDED.email,
           age        = EXCLUDED.age,
           gender     = EXCLUDED.gender$sql$,
    'CLIENTS_PROTECTED_COLUMN');
END $$;

-- -----------------------------------------------------------------------------
-- ケース a6 / a7: 未登録ユーザー N の INSERT でも、許可列以外は指定できない
--   （INSERT 列権限: client_id, trainer_id, name, email, age, gender のみ）
-- -----------------------------------------------------------------------------
\echo '--- case a6/a7: 未登録ユーザー N が created_at / target_weight を含めて INSERT できないこと (permission denied)'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"ffffffff-9922-0000-0000-00000000000f","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'ffffffff-9922-0000-0000-00000000000f';
SET LOCAL ROLE authenticated;

DO $$
DECLARE cnt int;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'ffffffff-9922-0000-0000-00000000000f'::uuid THEN
    RAISE EXCEPTION 'FAIL: a6 前提崩れ — auth.uid() が % （期待 N）', coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_denied(
    'a6 clients INSERT に created_at を含める',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender, created_at)
         VALUES ('ffffffff-9922-0000-0000-00000000000f',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N', 'rls-test-colguard-n@example.com', 30, 'female',
                 '-infinity')$sql$);

  PERFORM pg_temp.cg_expect_denied(
    'a7 clients INSERT に target_weight を含める',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender, target_weight)
         VALUES ('ffffffff-9922-0000-0000-00000000000f',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N', 'rls-test-colguard-n@example.com', 30, 'female',
                 55)$sql$);

  -- 拒否された INSERT で行が作られていないこと（b2 の前提）
  SELECT count(*) INTO cnt FROM public.clients
  WHERE client_id = 'ffffffff-9922-0000-0000-00000000000f';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: a7 拒否後に N の clients 行が % 行存在する（期待 0 行）', cnt;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- ケース a8: anon は clients に一切書き込めない（INSERT / UPDATE の GRANT 剥奪）
--   docs/tasks/lessons.md「RLS テストの anon ケースは『クレーム付き anon』も
--   入れないと偽陰性になる」に従い、顧客のクレームを入れたまま anon に切り替え、
--   auth.uid() が顧客を返す前提を確認してから検証する。
--   （clients の UPDATE ポリシーは TO authenticated のため、修正前の anon UPDATE は
--     例外なしの 0 行になる。これを PASS にしないよう permission denied を要求する）
-- -----------------------------------------------------------------------------
\echo '--- case a8: anon + クレーム付きで clients の UPDATE / INSERT が permission denied になること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: a8 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_denied(
    'a8 anon(クレーム=C) clients.name UPDATE',
    $sql$UPDATE public.clients SET name = 'anonによる改名'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$);

  PERFORM pg_temp.cg_expect_denied(
    'a8 anon(クレーム=C) clients.trainer_id UPDATE',
    $sql$UPDATE public.clients SET trainer_id = 'aaaaaaaa-9922-0000-0000-0000000000a2'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$);
END $$;

SET LOCAL request.jwt.claims = '{"sub":"ffffffff-9922-0000-0000-00000000000f","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'ffffffff-9922-0000-0000-00000000000f';

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'ffffffff-9922-0000-0000-00000000000f'::uuid THEN
    RAISE EXCEPTION 'FAIL: a8 前提崩れ — anon ロールで auth.uid() が % （期待 N）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_denied(
    'a8 anon(クレーム=N) clients INSERT',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender)
         VALUES ('ffffffff-9922-0000-0000-00000000000f',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N', 'rls-test-colguard-n@example.com', 30, 'female')$sql$);
END $$;

-- -----------------------------------------------------------------------------
-- ケース a9: 拒否された書き込みで C の行が一切変わっていないこと（postgres で確認）
-- -----------------------------------------------------------------------------
\echo '--- case a9: 拒否後も顧客 C の行が不変であること'

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE r public.clients%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.clients
  WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: a9 顧客 C の行が見つからない（client_id が変更された可能性）';
  END IF;
  IF r.trainer_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid
     OR r.created_at IS DISTINCT FROM '2026-01-15 00:00:00+00'::timestamptz
     OR r.name IS DISTINCT FROM 'RLSテスト顧客C'
     OR r.height IS DISTINCT FROM 170::numeric
     OR r.target_weight IS DISTINCT FROM 60::numeric
     OR r.purpose IS DISTINCT FROM 'health_improvement'
     OR r.occupation IS NOT NULL
     OR r.goal_description IS NOT NULL
     OR r.goal_deadline IS NOT NULL
     OR r.initial_weight IS NOT NULL
     OR r.goal_achieved_at IS NOT NULL
     OR r.line_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: a9 拒否後の顧客 C の行が変化している: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: a9 顧客 C の行は不変（trainer_id=T / created_at=固定値 / トレーナー所有列=既定値）';
END $$;

-- =============================================================================
-- [section:B] clients — 正規経路（回帰確認）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース b1: Mobile のプロフィール系 UPDATE（C2〜C9）は従来どおり通る
--   onboarding_completed_at は端末時刻をそのまま保存する（強制しない）
-- -----------------------------------------------------------------------------
\echo '--- case b1: 顧客 C が name / profile_image_url / fcm_token / onboarding_completed_at を更新できること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE r public.clients%ROWTYPE;
BEGIN
  PERFORM pg_temp.cg_expect_rows('b1 clients.name',
    $sql$UPDATE public.clients SET name = 'RLSテスト顧客C（改名）'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b1 clients.profile_image_url',
    $sql$UPDATE public.clients SET profile_image_url = 'bbbbbbbb-9922-0000-0000-00000000000b/avatar.jpg'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b1 clients.fcm_token 設定',
    $sql$UPDATE public.clients SET fcm_token = 'fcm-token-colguard-9922'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);

  SELECT * INTO r FROM public.clients WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF r.fcm_token IS DISTINCT FROM 'fcm-token-colguard-9922' THEN
    RAISE EXCEPTION 'FAIL: b1 fcm_token が % （期待 fcm-token-colguard-9922）', r.fcm_token;
  END IF;

  PERFORM pg_temp.cg_expect_rows('b1 clients.fcm_token = NULL',
    $sql$UPDATE public.clients SET fcm_token = NULL
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b1 clients.onboarding_completed_at（端末時刻）',
    $sql$UPDATE public.clients SET onboarding_completed_at = '2026-09-22T18:30:00+09:00'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);

  SELECT * INTO r FROM public.clients WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF r.name IS DISTINCT FROM 'RLSテスト顧客C（改名）'
     OR r.profile_image_url IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b/avatar.jpg'
     OR r.fcm_token IS NOT NULL
     OR r.onboarding_completed_at IS DISTINCT FROM '2026-09-22T18:30:00+09:00'::timestamptz THEN
    RAISE EXCEPTION 'FAIL: b1 保存値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: b1 プロフィール系 UPDATE の値が保存されている';
END $$;

-- -----------------------------------------------------------------------------
-- ケース b2: 新規登録（registration_provider.dart の upsert）は通る
--   衝突しない初回でも ON CONFLICT DO UPDATE SET 句の列に UPDATE 権限が要る点に注意。
--   created_at は DB 既定 now()、トレーナー所有列は既定値のまま
-- -----------------------------------------------------------------------------
\echo '--- case b2: 未登録ユーザー N の登録 upsert が成功し、created_at・既定値が正しいこと'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"ffffffff-9922-0000-0000-00000000000f","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'ffffffff-9922-0000-0000-00000000000f';
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'ffffffff-9922-0000-0000-00000000000f'::uuid THEN
    RAISE EXCEPTION 'FAIL: b2 前提崩れ — auth.uid() が % （期待 N）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  PERFORM pg_temp.cg_expect_rows('b2 clients 登録 upsert（新規）',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender)
         VALUES ('ffffffff-9922-0000-0000-00000000000f',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N', 'rls-test-colguard-n@example.com', 30, 'female')
         ON CONFLICT (client_id) DO UPDATE SET
           client_id  = EXCLUDED.client_id,
           trainer_id = EXCLUDED.trainer_id,
           name       = EXCLUDED.name,
           email      = EXCLUDED.email,
           age        = EXCLUDED.age,
           gender     = EXCLUDED.gender$sql$, 1);
END $$;

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE r public.clients%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.clients WHERE client_id = 'ffffffff-9922-0000-0000-00000000000f';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: b2 登録後に N の clients 行が無い';
  END IF;
  IF r.created_at IS DISTINCT FROM now()
     OR r.trainer_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid
     OR r.name IS DISTINCT FROM 'RLSテスト新規N'
     OR r.email IS DISTINCT FROM 'rls-test-colguard-n@example.com'
     OR r.age IS DISTINCT FROM 30
     OR r.gender IS DISTINCT FROM 'female'
     OR r.height IS DISTINCT FROM 170::numeric
     OR r.target_weight IS DISTINCT FROM 60::numeric
     OR r.purpose IS DISTINCT FROM 'health_improvement'
     OR r.goal_achieved_at IS NOT NULL
     OR r.initial_weight IS NOT NULL
     OR r.line_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: b2 登録行の値が期待と異なる: %', to_jsonb(r);
  END IF;

  -- b3 で「created_at が変わらない」ことを now() と区別して検証するため固定値にしておく
  UPDATE public.clients SET created_at = '2026-02-01 00:00:00+00'
  WHERE client_id = 'ffffffff-9922-0000-0000-00000000000f';
  RAISE NOTICE 'OK: b2 登録行は created_at=now() / trainer_id=T / トレーナー所有列=既定値';
END $$;

-- -----------------------------------------------------------------------------
-- ケース b3: 登録 upsert の再送（部分失敗後のリトライ）は同じ trainer_id なら通る
--   衝突経路では client_id / trainer_id を同値で SET するため、トリガーは
--   「同じ値なら可」でなければならない。created_at は書き換わらないこと
-- -----------------------------------------------------------------------------
\echo '--- case b3: N が同じ trainer_id で登録 upsert を再送できること（衝突経路・created_at 不変）'

SET LOCAL request.jwt.claims = '{"sub":"ffffffff-9922-0000-0000-00000000000f","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'ffffffff-9922-0000-0000-00000000000f';
SET LOCAL ROLE authenticated;

DO $$
DECLARE r public.clients%ROWTYPE;
BEGIN
  PERFORM pg_temp.cg_expect_rows('b3 clients 登録 upsert（再送・同じ trainer_id）',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender)
         VALUES ('ffffffff-9922-0000-0000-00000000000f',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N（再送）', 'rls-test-colguard-n@example.com', 31, 'female')
         ON CONFLICT (client_id) DO UPDATE SET
           client_id  = EXCLUDED.client_id,
           trainer_id = EXCLUDED.trainer_id,
           name       = EXCLUDED.name,
           email      = EXCLUDED.email,
           age        = EXCLUDED.age,
           gender     = EXCLUDED.gender$sql$, 1);

  SELECT * INTO r FROM public.clients WHERE client_id = 'ffffffff-9922-0000-0000-00000000000f';
  IF r.created_at IS DISTINCT FROM '2026-02-01 00:00:00+00'::timestamptz
     OR r.trainer_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid
     OR r.name IS DISTINCT FROM 'RLSテスト新規N（再送）'
     OR r.age IS DISTINCT FROM 31 THEN
    RAISE EXCEPTION 'FAIL: b3 再送後の値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: b3 再送 upsert は 1 行更新・created_at 不変';
END $$;

-- -----------------------------------------------------------------------------
-- ケース b4: service_role（Web の updateClient.ts / 管理操作）は全列を書ける
-- -----------------------------------------------------------------------------
\echo '--- case b4: service_role が clients のトレーナー所有列・trainer_id・created_at を更新できること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE service_role;

DO $$
DECLARE r public.clients%ROWTYPE;
BEGIN
  -- updateClient.ts の形
  PERFORM pg_temp.cg_expect_rows('b4 service_role updateClient.ts の形',
    $sql$UPDATE public.clients SET
           age = 41, gender = 'male', occupation = 'エンジニア', height = 172.5,
           target_weight = 58, purpose = 'body_make',
           goal_description = 'service_role で更新', goal_deadline = '2030-06-30'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b4 service_role 残りのトレーナー所有列',
    $sql$UPDATE public.clients SET
           initial_weight = 72, goal_set_at = '2026-04-01 00:00:00+00',
           goal_achieved_at = '2026-08-01 00:00:00+00', line_user_id = 'U-colguard-sr-9922'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b4 service_role trainer_id → T2',
    $sql$UPDATE public.clients SET trainer_id = 'aaaaaaaa-9922-0000-0000-0000000000a2'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b4 service_role trainer_id → T（戻し）',
    $sql$UPDATE public.clients SET trainer_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('b4 service_role created_at',
    $sql$UPDATE public.clients SET created_at = '2026-03-01 00:00:00+00'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 1);

  SELECT * INTO r FROM public.clients WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF r.trainer_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid
     OR r.created_at IS DISTINCT FROM '2026-03-01 00:00:00+00'::timestamptz
     OR r.age IS DISTINCT FROM 41
     OR r.gender IS DISTINCT FROM 'male'
     OR r.occupation IS DISTINCT FROM 'エンジニア'
     OR r.height IS DISTINCT FROM 172.5
     OR r.target_weight IS DISTINCT FROM 58::numeric
     OR r.purpose IS DISTINCT FROM 'body_make'
     OR r.goal_description IS DISTINCT FROM 'service_role で更新'
     OR r.goal_deadline IS DISTINCT FROM '2030-06-30'::date
     OR r.initial_weight IS DISTINCT FROM 72::numeric
     OR r.goal_set_at IS DISTINCT FROM '2026-04-01 00:00:00+00'::timestamptz
     OR r.goal_achieved_at IS DISTINCT FROM '2026-08-01 00:00:00+00'::timestamptz
     OR r.line_user_id IS DISTINCT FROM 'U-colguard-sr-9922' THEN
    RAISE EXCEPTION 'FAIL: b4 service_role の更新値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: b4 service_role は clients の全列を更新できる';
END $$;

-- =============================================================================
-- [section:C] messages INSERT — 禁止系
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース c1〜c4, c7, c8: 顧客 C の INSERT
--   判定順は sender_id → sender_type → 受信者（相手）→ 返信先。
--   sender_type は「呼び出し元が clients 行を持つなら 'client'、trainers 行を持つなら
--   'trainer'」以外は不可、受信者は顧客なら (自分の trainer_id, 'trainer') のみ
-- -----------------------------------------------------------------------------
\echo '--- case c1〜c4, c7, c8: 顧客 C の不正な INSERT が固定コードで拒否されること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: c 前提崩れ — auth.uid() が % （期待 顧客C）', coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_code('c1 C → T2（担当外トレーナー）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-0000000000a2',
                 'client', 'trainer', 'c1 担当外トレーナー宛て')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');

  PERFORM pg_temp.cg_expect_code('c2 C が sender_type=trainer を詐称（受信者 C）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'bbbbbbbb-9922-0000-0000-00000000000b',
                 'trainer', 'client', 'c2 トレーナー詐称（自分宛て）')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  PERFORM pg_temp.cg_expect_code('c2 C が sender_type=trainer を詐称（受信者 E）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'eeeeeeee-9922-0000-0000-00000000000e',
                 'trainer', 'client', 'c2 トレーナー詐称（E 宛て）')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  PERFORM pg_temp.cg_expect_code('c3 C が receiver_type=client で T 宛て',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'client', 'client', 'c3 receiver_type 偽装')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');

  PERFORM pg_temp.cg_expect_code('c4 sender_type = 空文字（明示）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 '', 'trainer', 'c4 sender_type 空文字')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  PERFORM pg_temp.cg_expect_code('c4 sender_type 省略（列既定値 空文字）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'trainer', 'c4 sender_type 省略')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  PERFORM pg_temp.cg_expect_code('c4 sender_type = admin',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'admin', 'trainer', 'c4 sender_type admin')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  -- RLS WITH CHECK (sender_id = auth.uid()) より先に BEFORE トリガーが評価されるため、
  -- 固定コード MESSAGES_SENDER_MISMATCH で拒否される
  PERFORM pg_temp.cg_expect_code('c7 C が sender_id = E で送信',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('eeeeeeee-9922-0000-0000-00000000000e', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'client', 'trainer', 'c7 送信者なりすまし')$sql$,
    'MESSAGES_SENDER_MISMATCH');

  PERFORM pg_temp.cg_expect_code('c8 C → T で reply_to = M4（別会話）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content,
                                      reply_to_message_id)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'client', 'trainer', 'c8 別会話への返信',
                 '44444444-9922-0000-0000-000000000004')$sql$,
    'MESSAGES_REPLY_OUTSIDE_CONVERSATION');
END $$;

-- -----------------------------------------------------------------------------
-- ケース c5, c6, c8b, c11, c12: トレーナー T の INSERT
--   受信者はトレーナーなら「trainer_id = 自分の顧客」かつ receiver_type 'client' のみ。
--   c8b の返信先 M9（T→E）は送信者 T 自身からは見える。返信先の判定が
--   「呼び出し元に見えるか」だけに弱まると c8 は（M4 が C から見えないため）PASS し
--   続けるが、c8b は通ってしまい FAIL する（= 同じ会話であることの直接検証）
-- -----------------------------------------------------------------------------
\echo '--- case c5, c6, c8b, c11, c12: トレーナー T の不正な INSERT が固定コードで拒否されること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: c5 前提崩れ — auth.uid() が % （期待 T）', coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_code('c5 T → D（T2 の顧客）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'dddddddd-9922-0000-0000-00000000000d',
                 'trainer', 'client', 'c5 担当外の顧客宛て')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');

  PERFORM pg_temp.cg_expect_code('c6 T が sender_type=client を詐称',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
                 'client', 'client', 'c6 顧客詐称')$sql$,
    'MESSAGES_INVALID_SENDER_TYPE');

  -- c8b 前提: 返信先 M9（T→E）が T から見えること（見えないと c8 と同じく
  -- 「見えないから拒否」になり、同じ会話かどうかの判定を検証できない）
  IF NOT EXISTS (
    SELECT 1 FROM public.messages
    WHERE id = '99999999-9922-0000-0000-000000000009'
      AND sender_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
      AND receiver_id = 'eeeeeeee-9922-0000-0000-00000000000e'
  ) THEN
    RAISE EXCEPTION 'FAIL: c8b 前提崩れ — トレーナー T から T↔E の M9 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_code('c8b T → C で reply_to = M9（T↔E の会話）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content,
                                      reply_to_message_id)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
                 'trainer', 'client', 'c8b 別の顧客との会話への返信',
                 '99999999-9922-0000-0000-000000000009')$sql$,
    'MESSAGES_REPLY_OUTSIDE_CONVERSATION');

  PERFORM pg_temp.cg_expect_code('c11 T → 自分の顧客 C だが receiver_type=trainer',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
                 'trainer', 'trainer', 'c11 receiver_type 偽装')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');

  PERFORM pg_temp.cg_expect_code('c12 T → 別トレーナー T2（receiver_type=trainer）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'aaaaaaaa-9922-0000-0000-0000000000a2',
                 'trainer', 'trainer', 'c12 トレーナー同士（trainer）')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');

  PERFORM pg_temp.cg_expect_code('c12 T → 別トレーナー T2（receiver_type=client）',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'aaaaaaaa-9922-0000-0000-0000000000a2',
                 'trainer', 'client', 'c12 トレーナー同士（client）')$sql$,
    'MESSAGES_RECEIVER_NOT_COUNTERPART');
END $$;

-- -----------------------------------------------------------------------------
-- ケース c9: INSERT 時に指定されたシステム列は黙って強制される
--   read_at → NULL / created_at → now() / edited_at → NULL / is_edited → false /
--   updated_at → now()。INSERT 自体は成功すること
-- -----------------------------------------------------------------------------
\echo '--- case c9: 顧客 C が指定した read_at / created_at / edited_at / is_edited / updated_at が強制されること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_id  uuid;
  r     public.messages%ROWTYPE;
  v_bad text[] := '{}';
BEGIN
  BEGIN
    INSERT INTO public.messages (
      sender_id, receiver_id, sender_type, receiver_type, content,
      read_at, created_at, edited_at, is_edited, updated_at
    ) VALUES (
      'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
      'client', 'trainer', 'c9 強制値テスト',
      now() - interval '1 day', '-infinity', '2000-01-01', true, '2000-01-01'
    ) RETURNING id INTO v_id;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: c9 INSERT 自体が失敗した（強制ではなく拒否になっている）SQLSTATE=% SQLERRM=%',
        SQLSTATE, SQLERRM;
  END;

  SELECT * INTO r FROM public.messages WHERE id = v_id;
  IF r.read_at IS NOT NULL THEN
    v_bad := v_bad || format('read_at=%s（期待 NULL）', r.read_at);
  END IF;
  IF r.created_at IS DISTINCT FROM now() THEN
    v_bad := v_bad || format('created_at=%s（期待 now()=%s）', r.created_at, now());
  END IF;
  IF r.edited_at IS NOT NULL THEN
    v_bad := v_bad || format('edited_at=%s（期待 NULL）', r.edited_at);
  END IF;
  IF r.is_edited IS DISTINCT FROM false THEN
    v_bad := v_bad || format('is_edited=%s（期待 false）', r.is_edited);
  END IF;
  IF r.updated_at IS DISTINCT FROM now() THEN
    v_bad := v_bad || format('updated_at=%s（期待 now()=%s）', r.updated_at, now());
  END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'FAIL: c9 INSERT 時のシステム列が強制されていない: %', array_to_string(v_bad, ' / ');
  END IF;
  RAISE NOTICE 'OK: c9 INSERT は成功し、read_at / created_at / edited_at / is_edited / updated_at は強制値';
END $$;

-- -----------------------------------------------------------------------------
-- ケース c10: anon は messages に INSERT できない（顧客 C のクレーム付き）
--   messages の INSERT ポリシーは TO PUBLIC のため、GRANT が残っていると
--   クレーム付き anon は sender_id = auth.uid() を満たして送信できてしまう
-- -----------------------------------------------------------------------------
\echo '--- case c10: anon + 顧客 C のクレームで messages INSERT が permission denied になること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: c10 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;
  PERFORM pg_temp.cg_expect_denied('c10 anon(クレーム=C) messages INSERT C → T',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'client', 'trainer', 'c10 anon からの送信')$sql$);
END $$;

-- =============================================================================
-- [section:D] messages UPDATE — 受信者の禁止系
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース d1: 受信者 T は M1 の read_at 以外を書き換えられない
--   T は "Receivers can mark messages as read" の USING で M1 を更新対象にできる
--   （前提確認）。受信者に許されるのは read_at（NULL → 値）のみ
-- -----------------------------------------------------------------------------
\echo '--- case d1: 受信者 T が M1 の read_at 以外の列を 1 列ずつ更新できないこと (MESSAGES_COLUMN_NOT_UPDATABLE)'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  r        record;
  v_before jsonb;
  v_after  jsonb;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: d1 前提崩れ — auth.uid() が % （期待 T）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000001'
    AND receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND read_at IS NULL;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: d1 前提崩れ — 受信者 T から未読の M1 が見えない';
  END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('id',                  '''00000000-9922-0000-0000-0000000000d1''::uuid'),
      ('content',             '''受信者による改ざん'''),
      ('tags',                'ARRAY[''#改ざん'']'),
      ('metadata',            '''{"tampered":true}''::jsonb'),
      ('image_urls',          'ARRAY[''tampered/by-receiver.jpg'']'),
      ('sender_id',           '''eeeeeeee-9922-0000-0000-00000000000e''::uuid'),
      ('receiver_id',         '''eeeeeeee-9922-0000-0000-00000000000e''::uuid'),
      ('receiver_type',       '''client'''),
      ('sender_type',         '''trainer'''),
      ('created_at',          'now() - interval ''1 day'''),
      ('reply_to_message_id', '''22222222-9922-0000-0000-000000000002''::uuid'),
      ('is_edited',           'true'),
      ('edited_at',           'now()')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.cg_expect_code(
      format('d1 受信者 T が M1.%s を更新', r.col),
      format('UPDATE public.messages SET %I = %s WHERE id = %L',
             r.col, r.val, '11111111-9922-0000-0000-000000000001'),
      'MESSAGES_COLUMN_NOT_UPDATABLE');
  END LOOP;

  SELECT to_jsonb(m) INTO v_after FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000001';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: d1 拒否後に M1 が変化している: before=% after=%', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: d1 拒否後も M1 は不変';
END $$;

-- -----------------------------------------------------------------------------
-- ケース d2: 既読済みメッセージの read_at は取り消し（NULL）も付け替えもできない
--   受信者に許されるのは「NULL → 値」の 1 回だけ（値はサーバー now() に強制）。
--   既読の取り消しは未読バッジの改ざん、付け替えは既読時刻の改ざんになる。
--   受信者 T（M6: C→T 既読）と受信者 C（M5: T→C 既読）の両方で確認する
--   ※ M5 の受信者は C（T は送信者で、2 時間前のため送信者ポリシーの対象外 =
--     T で実行すると 0 行 no-op になり検証にならない）
-- -----------------------------------------------------------------------------
\echo '--- case d2: 受信者 T（M6）/ 受信者 C（M5）が既読の read_at を取り消し・付け替えできないこと (MESSAGES_READ_AT_IMMUTABLE)'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
DECLARE v_read_at timestamptz;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: d2 前提崩れ — auth.uid() が % （期待 T）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '66666666-9922-0000-0000-000000000006'
    AND receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a';
  IF NOT FOUND OR v_read_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: d2 前提崩れ — 受信者 T から既読の M6 が見えない (read_at=%)', v_read_at;
  END IF;

  PERFORM pg_temp.cg_expect_code('d2 受信者 T が M6.read_at を NULL に戻す',
    $sql$UPDATE public.messages SET read_at = NULL
         WHERE id = '66666666-9922-0000-0000-000000000006'$sql$,
    'MESSAGES_READ_AT_IMMUTABLE');
  PERFORM pg_temp.cg_expect_code('d2 受信者 T が M6.read_at を付け替え',
    $sql$UPDATE public.messages SET read_at = now() - interval '5 minutes'
         WHERE id = '66666666-9922-0000-0000-000000000006'$sql$,
    'MESSAGES_READ_AT_IMMUTABLE');

  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '66666666-9922-0000-0000-000000000006';
  IF v_read_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: d2 拒否後の M6.read_at が % （期待 now() - 1 hour のまま）', v_read_at;
  END IF;
END $$;

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE v_read_at timestamptz;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: d2 前提崩れ — auth.uid() が % （期待 顧客C）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '55555555-9922-0000-0000-000000000005'
    AND receiver_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF NOT FOUND OR v_read_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: d2 前提崩れ — 受信者 C から既読の M5 が見えない (read_at=%)', v_read_at;
  END IF;

  PERFORM pg_temp.cg_expect_code('d2 受信者 C が M5.read_at を NULL に戻す',
    $sql$UPDATE public.messages SET read_at = NULL
         WHERE id = '55555555-9922-0000-0000-000000000005'$sql$,
    'MESSAGES_READ_AT_IMMUTABLE');
  PERFORM pg_temp.cg_expect_code('d2 受信者 C が M5.read_at を付け替え',
    $sql$UPDATE public.messages SET read_at = now() - interval '5 minutes'
         WHERE id = '55555555-9922-0000-0000-000000000005'$sql$,
    'MESSAGES_READ_AT_IMMUTABLE');

  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '55555555-9922-0000-0000-000000000005';
  IF v_read_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: d2 拒否後の M5.read_at が % （期待 now() - 1 hour のまま）', v_read_at;
  END IF;
  RAISE NOTICE 'OK: d2 拒否後も M6 / M5 の read_at は不変';
END $$;

-- =============================================================================
-- [section:E] messages UPDATE — 送信者の禁止系
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース e1: 送信者 C は 5 分以内の M1 でも content / tags（と強制される
--   is_edited / edited_at）以外を書き換えられない
--   created_at の書き換えは 5 分の編集可能時間を自分で延長する抜け道になる
-- -----------------------------------------------------------------------------
\echo '--- case e1: 送信者 C が 5 分以内の M1 で content / tags 以外を 1 列ずつ更新できないこと (MESSAGES_COLUMN_NOT_UPDATABLE)'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  r        record;
  v_before jsonb;
  v_after  jsonb;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: e1 前提崩れ — auth.uid() が % （期待 顧客C）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000001'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND now() - created_at < interval '5 minutes';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: e1 前提崩れ — 送信者 C から 5 分以内の M1 が見えない';
  END IF;

  FOR r IN
    SELECT * FROM (VALUES
      ('id',                  '''00000000-9922-0000-0000-0000000000e1''::uuid'),
      ('receiver_id',         '''eeeeeeee-9922-0000-0000-00000000000e''::uuid'),
      ('receiver_type',       '''client'''),
      ('sender_type',         '''trainer'''),
      ('created_at',          'now() + interval ''1 day'''),
      ('read_at',             'now()'),
      ('metadata',            '''{"tampered":true}''::jsonb'),
      ('image_urls',          'ARRAY[''bbbbbbbb-9922-0000-0000-00000000000b/tampered.jpg'']'),
      ('reply_to_message_id', '''22222222-9922-0000-0000-000000000002''::uuid')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.cg_expect_code(
      format('e1 送信者 C が M1.%s を更新', r.col),
      format('UPDATE public.messages SET %I = %s WHERE id = %L',
             r.col, r.val, '11111111-9922-0000-0000-000000000001'),
      'MESSAGES_COLUMN_NOT_UPDATABLE');
  END LOOP;

  SELECT to_jsonb(m) INTO v_after FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000001';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: e1 拒否後に M1 が変化している: before=% after=%', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: e1 拒否後も M1 は不変';
END $$;

-- -----------------------------------------------------------------------------
-- ケース e2: 5 分を過ぎた M3 は従来どおり編集できない（RLS の USING で 0 行）
--   C から M3 が見えること（SELECT 可）を先に確認し、0 行が「見えないから」では
--   なく編集可能時間の制限によるものであることを担保する
-- -----------------------------------------------------------------------------
\echo '--- case e2: 送信者 C が 10 分前の M3 を編集すると 0 行であること（5 分制限・従来どおり）'

DO $$
DECLARE v_content text;
BEGIN
  SELECT content INTO v_content FROM public.messages
  WHERE id = '33333333-9922-0000-0000-000000000003'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: e2 前提崩れ — 送信者 C から M3 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('e2 送信者 C が 10 分前の M3.content を更新',
    $sql$UPDATE public.messages SET content = 'e2 期限切れの編集'
         WHERE id = '33333333-9922-0000-0000-000000000003'$sql$, 0);

  SELECT content INTO v_content FROM public.messages
  WHERE id = '33333333-9922-0000-0000-000000000003';
  IF v_content IS DISTINCT FROM 'M3 C→T 10分前' THEN
    RAISE EXCEPTION 'FAIL: e2 M3 の本文が % に変わっている', v_content;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- ケース e3: anon は messages を UPDATE できない（クレーム付き）
--   messages の UPDATE ポリシーは TO PUBLIC のため、GRANT が残っていると
--   クレーム付き anon が送信者として本文を、受信者として read_at を書き換えられる
-- -----------------------------------------------------------------------------
\echo '--- case e3: anon + 顧客 C / トレーナー T のクレームで messages UPDATE が permission denied になること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: e3 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;
  PERFORM pg_temp.cg_expect_denied('e3 anon(クレーム=C) M1.content UPDATE',
    $sql$UPDATE public.messages SET content = 'anon による編集'
         WHERE id = '11111111-9922-0000-0000-000000000001'$sql$);
END $$;

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: e3 前提崩れ — anon ロールで auth.uid() が % （期待 T）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;
  PERFORM pg_temp.cg_expect_denied('e3 anon(クレーム=T) M1.read_at UPDATE',
    $sql$UPDATE public.messages SET read_at = now()
         WHERE id = '11111111-9922-0000-0000-000000000001'$sql$);
END $$;

-- -----------------------------------------------------------------------------
-- ケース e4: 自分宛てメッセージ（送信者 = 受信者 = T）
--   RLS の UPDATE ポリシーは PERMISSIVE の OR 結合で、"Receivers can mark messages
--   as read"（USING receiver_id = auth.uid()）は作成から 5 分を過ぎても行を通す。
--   ガードが「送信者か」を sender_id だけで判定すると、10 分前の自分宛てメッセージの
--   本文を受信者ポリシー経由で編集できてしまう（5 分制限のすり抜け）。
--   送信者の許可列（content / tags / is_edited / edited_at）は 5 分以内に限り、
--   受信者としての既読化（read_at: NULL → 値）は時間に関係なく可であること。
--   ※ アプリ経路では T→T は作れない（INSERT ガードで拒否）が、service_role /
--     過去データでは存在しうるため postgres で作成して検証する
-- -----------------------------------------------------------------------------
\echo '--- case e4a: T が 10 分前の自分宛て M7 の content を編集できないこと (MESSAGES_COLUMN_NOT_UPDATABLE)'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_before jsonb;
  v_after  jsonb;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: e4a 前提崩れ — auth.uid() が % （期待 T）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  -- 前提: M7 が T から見え（受信者として UPDATE 対象になりうる）、5 分を過ぎていること
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '77777777-9922-0000-0000-000000000007'
    AND sender_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND now() - created_at >= interval '5 minutes'
    AND read_at IS NULL;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: e4a 前提崩れ — T から 10 分前・未読の自分宛て M7 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_code('e4a T が 10 分前の自分宛て M7.content を編集',
    $sql$UPDATE public.messages SET content = 'e4a 期限切れの編集（受信者ポリシー経由）'
         WHERE id = '77777777-9922-0000-0000-000000000007'$sql$,
    'MESSAGES_COLUMN_NOT_UPDATABLE');

  SELECT to_jsonb(m) INTO v_after FROM public.messages m
  WHERE id = '77777777-9922-0000-0000-000000000007';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: e4a 拒否後に M7 が変化している: before=% after=%', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: e4a 拒否後も M7 は不変';
END $$;

\echo '--- case e4b: T が 10 分前の自分宛て M7 を既読にできること（read_at = now()）'

DO $$
DECLARE
  r        public.messages%ROWTYPE;
  v_before jsonb;
BEGIN
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '77777777-9922-0000-0000-000000000007' AND read_at IS NULL;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: e4b 前提崩れ — T から未読の M7 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('e4b T が 10 分前の自分宛て M7.read_at を NULL → 値',
    $sql$UPDATE public.messages SET read_at = now() - interval '3 minutes'
         WHERE id = '77777777-9922-0000-0000-000000000007' AND read_at IS NULL$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '77777777-9922-0000-0000-000000000007';
  IF r.read_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: e4b M7.read_at が % （期待 now()=%）', r.read_at, now();
  END IF;
  IF (to_jsonb(r) - 'read_at' - 'updated_at') IS DISTINCT FROM (v_before - 'read_at' - 'updated_at') THEN
    RAISE EXCEPTION 'FAIL: e4b 既読化で read_at 以外の列が変化: before=% after=%', v_before, to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: e4b 5 分を過ぎた自分宛て M7 も受信者として既読化できる（read_at = now()・他列不変）';
END $$;

\echo '--- case e4c: T が 5 分以内の自分宛て M8 の content を編集できること（is_edited / edited_at 強制）'

DO $$
DECLARE
  r        public.messages%ROWTYPE;
  v_before jsonb;
BEGIN
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '88888888-9922-0000-0000-000000000008'
    AND sender_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND now() - created_at < interval '5 minutes';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: e4c 前提崩れ — T から 5 分以内の自分宛て M8 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('e4c T が 5 分以内の自分宛て M8.content を編集',
    $sql$UPDATE public.messages SET content = 'e4c 自分宛ての編集'
         WHERE id = '88888888-9922-0000-0000-000000000008'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '88888888-9922-0000-0000-000000000008';
  IF r.content IS DISTINCT FROM 'e4c 自分宛ての編集'
     OR r.is_edited IS DISTINCT FROM true
     OR r.edited_at IS DISTINCT FROM now()
     OR r.read_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: e4c 編集後の値が期待と異なる: content=% is_edited=% edited_at=% read_at=% （期待 e4c 自分宛ての編集 / true / now()=% / NULL）',
      r.content, r.is_edited, r.edited_at, r.read_at, now();
  END IF;
  IF (to_jsonb(r) - 'content' - 'is_edited' - 'edited_at' - 'updated_at')
     IS DISTINCT FROM (v_before - 'content' - 'is_edited' - 'edited_at' - 'updated_at') THEN
    RAISE EXCEPTION 'FAIL: e4c 編集対象外の列が変化: before=% after=%', v_before, to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: e4c 5 分以内の自分宛て M8 は送信者として編集できる（is_edited = true / edited_at = now()）';
END $$;

-- =============================================================================
-- [section:F] messages — 正規経路（回帰確認）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース f1: Mobile の送信（message_repository.dart M1）は通る
--   食事: 画像・タグ・同一会話（M2）への返信・metadata.meal_estimation あり
--   ワークアウト完了: image_urls NULL・reply_to NULL・tags ['#運動:完了']
-- -----------------------------------------------------------------------------
\echo '--- case f1: 顧客 C の Mobile 送信（食事 / ワークアウト完了）が成功すること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE r public.messages%ROWTYPE;
BEGIN
  BEGIN
    INSERT INTO public.messages (
      sender_id, receiver_id, sender_type, receiver_type, content,
      image_urls, tags, reply_to_message_id, is_edited, metadata
    ) VALUES (
      'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
      'client', 'trainer', '#食事 テスト',
      ARRAY['bbbbbbbb-9922-0000-0000-00000000000b/x.jpg'], ARRAY['#食事'],
      '22222222-9922-0000-0000-000000000002', false,
      '{"meal_estimation":{"calories":500}}'::jsonb
    ) RETURNING * INTO r;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: f1 Mobile 送信（食事）が拒否された SQLSTATE=% SQLERRM=%', SQLSTATE, SQLERRM;
  END;
  IF r.sender_id IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid
     OR r.receiver_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid
     OR r.sender_type IS DISTINCT FROM 'client'
     OR r.receiver_type IS DISTINCT FROM 'trainer'
     OR r.content IS DISTINCT FROM '#食事 テスト'
     OR r.image_urls IS DISTINCT FROM ARRAY['bbbbbbbb-9922-0000-0000-00000000000b/x.jpg']
     OR r.tags IS DISTINCT FROM ARRAY['#食事']
     OR r.reply_to_message_id IS DISTINCT FROM '22222222-9922-0000-0000-000000000002'::uuid
     OR r.metadata IS DISTINCT FROM '{"meal_estimation":{"calories":500}}'::jsonb
     OR r.is_edited IS DISTINCT FROM false
     OR r.read_at IS NOT NULL
     OR r.edited_at IS NOT NULL
     OR r.created_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f1 Mobile 送信（食事）の保存値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: f1 Mobile 送信（食事・返信・metadata あり）成功';

  BEGIN
    INSERT INTO public.messages (
      sender_id, receiver_id, sender_type, receiver_type, content,
      image_urls, tags, reply_to_message_id, is_edited
    ) VALUES (
      'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
      'client', 'trainer', '#運動:完了 f1 ワークアウト完了',
      NULL, ARRAY['#運動:完了'], NULL, false
    ) RETURNING * INTO r;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: f1 Mobile 送信（ワークアウト完了）が拒否された SQLSTATE=% SQLERRM=%', SQLSTATE, SQLERRM;
  END;
  IF r.image_urls IS NOT NULL
     OR r.reply_to_message_id IS NOT NULL
     OR r.tags IS DISTINCT FROM ARRAY['#運動:完了']
     OR r.metadata IS NOT NULL
     OR r.sender_type IS DISTINCT FROM 'client' THEN
    RAISE EXCEPTION 'FAIL: f1 Mobile 送信（ワークアウト完了）の保存値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: f1 Mobile 送信（ワークアウト完了・image_urls NULL）成功';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f2: トレーナー T から担当顧客 C への authenticated 送信は通る
-- -----------------------------------------------------------------------------
\echo '--- case f2: トレーナー T → 顧客 C の authenticated 送信が成功すること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
DECLARE r public.messages%ROWTYPE;
BEGIN
  BEGIN
    INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
    VALUES ('aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
            'trainer', 'client', 'f2 トレーナー→顧客')
    RETURNING * INTO r;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: f2 トレーナー → 顧客の送信が拒否された SQLSTATE=% SQLERRM=%', SQLSTATE, SQLERRM;
  END;
  IF r.sender_type IS DISTINCT FROM 'trainer'
     OR r.receiver_type IS DISTINCT FROM 'client'
     OR r.receiver_id IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid
     OR r.read_at IS NOT NULL
     OR r.created_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f2 保存値が期待と異なる: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: f2 トレーナー T → 顧客 C の送信成功';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f3: Mobile の編集（message_repository.dart M2）は通る
--   edited_at は端末ローカル時刻（オフセット無し = 9 時間ずれるバグ）を送ってくるが、
--   サーバーの now() に強制される。宛先・種別・作成日時・既読は変わらない
-- -----------------------------------------------------------------------------
\echo '--- case f3: 顧客 C の Mobile 編集が成功し、edited_at が now() に強制されること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  r        public.messages%ROWTYPE;
  v_before jsonb;
  v_bad    text[] := '{}';
BEGIN
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000001'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND now() - created_at < interval '5 minutes';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: f3 前提崩れ — 送信者 C から 5 分以内の M1 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('f3 Mobile 編集の形（M1）',
    $sql$UPDATE public.messages
         SET content = '編集後', tags = NULL, is_edited = true,
             edited_at = '2030-01-01T09:00:00'
         WHERE id = '11111111-9922-0000-0000-000000000001'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '11111111-9922-0000-0000-000000000001';
  IF r.content IS DISTINCT FROM '編集後' THEN
    v_bad := v_bad || format('content=%s（期待 編集後）', r.content);
  END IF;
  IF r.tags IS NOT NULL THEN
    v_bad := v_bad || format('tags=%s（期待 NULL）', r.tags);
  END IF;
  IF r.is_edited IS DISTINCT FROM true THEN
    v_bad := v_bad || format('is_edited=%s（期待 true）', r.is_edited);
  END IF;
  IF r.edited_at IS DISTINCT FROM now() THEN
    v_bad := v_bad || format('edited_at=%s（期待 now()=%s）', r.edited_at, now());
  END IF;
  IF (to_jsonb(r) - 'content' - 'tags' - 'is_edited' - 'edited_at' - 'updated_at')
     IS DISTINCT FROM (v_before - 'content' - 'tags' - 'is_edited' - 'edited_at' - 'updated_at') THEN
    v_bad := v_bad || format('編集対象外の列が変化: before=%s after=%s', v_before, to_jsonb(r));
  END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'FAIL: f3 編集後の値が期待と異なる: %', array_to_string(v_bad, ' / ');
  END IF;
  RAISE NOTICE 'OK: f3 Mobile 編集成功（edited_at は now() に強制・他列不変）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f3b: 送信者が content だけを変えても is_edited / edited_at は強制される
--   （設計: 送信者 UPDATE で content または tags が変わったら true / now()）
-- -----------------------------------------------------------------------------
\echo '--- case f3b: 送信者 C が content のみ変更 → is_edited = true / edited_at = now() に強制されること'

DO $$
DECLARE
  v_id uuid;
  r    public.messages%ROWTYPE;
BEGIN
  SELECT id INTO v_id FROM public.messages
  WHERE sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND content = '#食事 テスト';
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: f3b 前提崩れ — f1 の食事メッセージが見つからない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('f3b content のみ変更',
    format('UPDATE public.messages SET content = %L WHERE id = %L',
           '#食事 テスト（本文のみ編集）', v_id), 1);

  SELECT * INTO r FROM public.messages WHERE id = v_id;
  IF r.content IS DISTINCT FROM '#食事 テスト（本文のみ編集）'
     OR r.is_edited IS DISTINCT FROM true
     OR r.edited_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f3b content のみの編集で is_edited / edited_at が強制されていない: content=% is_edited=% edited_at=% （期待 true / now()=%）',
      r.content, r.is_edited, r.edited_at, now();
  END IF;
  RAISE NOTICE 'OK: f3b content のみの編集でも is_edited = true / edited_at = now()';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f3d: 送信者が content / tags を変えずに edited_at / is_edited だけを送っても
--   is_edited / edited_at は送信前の値のまま（任意時刻の「編集済み」表示や、
--   編集済みフラグの取り消しはできない）。UPDATE 自体は拒否せず 1 行の no-op。
--   「常に now() / true に強制」する実装とも区別できるよう、未編集の M10
--   （false / NULL）と編集済みの M11（true / now()-2分）の両方で確認する
-- -----------------------------------------------------------------------------
\echo '--- case f3d: 送信者 C が edited_at / is_edited だけを送っても送信前の値のままであること'

DO $$
DECLARE
  r        public.messages%ROWTYPE;
  v_before jsonb;
BEGIN
  -- M10（未編集）: edited_at だけを送る
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '10101010-9922-0000-0000-000000000010'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND now() - created_at < interval '5 minutes'
    AND is_edited = false AND edited_at IS NULL;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: f3d 前提崩れ — 送信者 C から 5 分以内・未編集の M10 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('f3d M10（未編集）に edited_at だけを送る',
    $sql$UPDATE public.messages SET edited_at = '2000-01-01'
         WHERE id = '10101010-9922-0000-0000-000000000010'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '10101010-9922-0000-0000-000000000010';
  IF r.is_edited IS DISTINCT FROM false OR r.edited_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: f3d M10 の is_edited=% edited_at=% （期待 false / NULL のまま）', r.is_edited, r.edited_at;
  END IF;
  IF (to_jsonb(r) - 'updated_at') IS DISTINCT FROM (v_before - 'updated_at') THEN
    RAISE EXCEPTION 'FAIL: f3d M10 の列が変化: before=% after=%', v_before, to_jsonb(r);
  END IF;

  -- M11（編集済み）: edited_at だけ / is_edited = false だけを送る
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = '11111111-9922-0000-0000-000000000011'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND now() - created_at < interval '5 minutes'
    AND is_edited = true AND edited_at = now() - interval '2 minutes';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: f3d 前提崩れ — 送信者 C から 5 分以内・編集済みの M11 が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('f3d M11（編集済み）に edited_at だけを送る',
    $sql$UPDATE public.messages SET edited_at = '2000-01-01'
         WHERE id = '11111111-9922-0000-0000-000000000011'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('f3d M11（編集済み）に is_edited = false だけを送る',
    $sql$UPDATE public.messages SET is_edited = false
         WHERE id = '11111111-9922-0000-0000-000000000011'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '11111111-9922-0000-0000-000000000011';
  IF r.is_edited IS DISTINCT FROM true OR r.edited_at IS DISTINCT FROM now() - interval '2 minutes' THEN
    RAISE EXCEPTION 'FAIL: f3d M11 の is_edited=% edited_at=% （期待 true / now()-2分=% のまま）',
      r.is_edited, r.edited_at, now() - interval '2 minutes';
  END IF;
  IF (to_jsonb(r) - 'updated_at') IS DISTINCT FROM (v_before - 'updated_at') THEN
    RAISE EXCEPTION 'FAIL: f3d M11 の列が変化: before=% after=%', v_before, to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: f3d edited_at / is_edited だけの UPDATE は 1 行の no-op（M10: false / NULL、M11: true / now()-2分 のまま）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f3c: content を変えつつ is_edited = false を送っても true / now() に強制
--   （f3d の後に未編集の M10 で実行する）
-- -----------------------------------------------------------------------------
\echo '--- case f3c: 送信者 C が content と is_edited = false を送る → is_edited = true / edited_at = now()'

DO $$
DECLARE r public.messages%ROWTYPE;
BEGIN
  PERFORM pg_temp.cg_expect_rows('f3c M10 に content = x, is_edited = false',
    $sql$UPDATE public.messages SET content = 'x', is_edited = false
         WHERE id = '10101010-9922-0000-0000-000000000010'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '10101010-9922-0000-0000-000000000010';
  IF r.content IS DISTINCT FROM 'x'
     OR r.is_edited IS DISTINCT FROM true
     OR r.edited_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f3c M10 の content=% is_edited=% edited_at=% （期待 x / true / now()=%）',
      r.content, r.is_edited, r.edited_at, now();
  END IF;
  RAISE NOTICE 'OK: f3c is_edited = false を送っても本文変更で is_edited = true / edited_at = now()';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f4: Web の markMessagesAsRead.ts（トレーナーの唯一の直接書き込み）は通る
--   read_at にブラウザ時計の ISO 文字列（toISOString 形式）を送ってくるが、
--   サーバーの now() に強制される。未読の C→T 全件が 1 回で既読になり、
--   read_at / updated_at 以外の列は変わらない
-- -----------------------------------------------------------------------------
\echo '--- case f4: トレーナー T の Web 既読化が成功し、read_at が now() に強制されること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_ids           uuid[];
  v_before        jsonb;
  v_after         jsonb;
  v_bad           text;
  v_browser_clock text := to_char((now() - interval '3 minutes') AT TIME ZONE 'UTC',
                                  'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: f4 前提崩れ — auth.uid() が % （期待 T）', coalesce(auth.uid()::text, 'NULL');
  END IF;

  SELECT array_agg(id ORDER BY id),
         jsonb_object_agg(id, to_jsonb(m) - 'read_at' - 'updated_at')
    INTO v_ids, v_before
  FROM public.messages m
  WHERE receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND read_at IS NULL;
  IF v_ids IS NULL
     OR NOT (v_ids @> ARRAY['11111111-9922-0000-0000-000000000001',
                            '33333333-9922-0000-0000-000000000003']::uuid[]) THEN
    RAISE EXCEPTION 'FAIL: f4 前提崩れ — 受信者 T から未読の M1 / M3 が見えない (ids=%)', v_ids;
  END IF;

  PERFORM pg_temp.cg_expect_rows(
    format('f4 Web markMessagesAsRead の形（未読 C→T %s 件）', cardinality(v_ids)),
    format('UPDATE public.messages SET read_at = %L
            WHERE receiver_id = %L AND sender_id = %L AND read_at IS NULL',
           v_browser_clock,
           'aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b'),
    cardinality(v_ids));

  SELECT string_agg(format('%s: read_at=%s', id, read_at), ', ')
    INTO v_bad
  FROM public.messages
  WHERE id = ANY (v_ids) AND read_at IS DISTINCT FROM now();
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: f4 read_at がサーバー now()=% に強制されていない（ブラウザ時計 % のまま等）: %',
      now(), v_browser_clock, v_bad;
  END IF;

  SELECT jsonb_object_agg(id, to_jsonb(m) - 'read_at' - 'updated_at')
    INTO v_after
  FROM public.messages m
  WHERE id = ANY (v_ids);
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: f4 既読化で read_at 以外の列が変化: before=% after=%', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: f4 Web 既読化成功（read_at は now() に強制・他列不変）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f5: SECURITY DEFINER の既読化 RPC（Mobile M3: mark_messages_as_read）は通る
--   public.mark_messages_as_read(uuid) は 20260913000500 で migration 化され、
--   20260913000510 で search_path = '' / EXECUTE は authenticated のみに固められた。
--   DEFINER 関数の中では current_user が所有者（postgres）になるためガード対象外で、
--   read_at = now() をそのまま書ける。関数が無い・DEFINER でない場合は
--   「DEFINER 経路の回帰確認」自体が成り立たないため FAIL にする（代替コピーは作らない）
-- -----------------------------------------------------------------------------
\echo '--- case f5: 顧客 C が SECURITY DEFINER の既読化 RPC で T→C を既読にできること'

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE r record;
BEGIN
  SELECT p.prosecdef, pg_get_userbyid(p.proowner) AS owner, p.proconfig,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
    INTO r
  FROM pg_proc p
  WHERE p.oid = to_regprocedure('public.mark_messages_as_read(uuid)');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAIL: f5 前提崩れ — public.mark_messages_as_read(uuid) が存在しない（20260913000500 未適用）';
  END IF;
  IF NOT r.prosecdef OR r.owner IN ('authenticated', 'anon') OR NOT r.auth_exec THEN
    RAISE EXCEPTION 'FAIL: f5 前提崩れ — mark_messages_as_read が DEFINER 経路になっていない (prosecdef=% owner=% authenticated EXECUTE=%)',
      r.prosecdef, r.owner, r.auth_exec;
  END IF;
  RAISE NOTICE 'f5: public.mark_messages_as_read(uuid) は SECURITY DEFINER（owner=% / proconfig=%）', r.owner, r.proconfig;
END $$;

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_read_at timestamptz;
  v_unread  int;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: f5 前提崩れ — auth.uid() が % （期待 顧客C）', coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '22222222-9922-0000-0000-000000000002'
    AND receiver_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF NOT FOUND OR v_read_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: f5 前提崩れ — 受信者 C から未読の M2 が見えない (read_at=%)', v_read_at;
  END IF;

  BEGIN
    PERFORM public.mark_messages_as_read('aaaaaaaa-9922-0000-0000-00000000000a'::uuid);
  EXCEPTION
    WHEN OTHERS THEN
      RAISE EXCEPTION 'FAIL: f5 SECURITY DEFINER の既読化 RPC が失敗した SQLSTATE=% SQLERRM=%', SQLSTATE, SQLERRM;
  END;

  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '22222222-9922-0000-0000-000000000002';
  IF v_read_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f5 M2.read_at が % （期待 now()=%）', v_read_at, now();
  END IF;

  SELECT count(*) INTO v_unread FROM public.messages
  WHERE sender_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
    AND receiver_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND read_at IS NULL;
  IF v_unread <> 0 THEN
    RAISE EXCEPTION 'FAIL: f5 RPC 後も T→C の未読が % 件残っている（期待 0 件）', v_unread;
  END IF;

  -- 既読済みの M5 は WHERE read_at IS NULL で対象外のまま（read_at 不変）
  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = '55555555-9922-0000-0000-000000000005';
  IF v_read_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: f5 既読済み M5 の read_at が % に変わった（期待 now() - 1 hour）', v_read_at;
  END IF;
  RAISE NOTICE 'OK: f5 DEFINER の既読化 RPC で T→C（M2・f2）が read_at = now()、M5 は不変';
END $$;

-- -----------------------------------------------------------------------------
-- ケース f6: service_role（Web の API Route / Edge Function）は全列を書ける
--   - /api/messages/send: INSERT（trainer → client、画像・返信あり）
--   - /api/messages/edit: UPDATE content / is_edited / edited_at / updated_at
--     （edited_at は送った値がそのまま残る。updated_at は set_updated_at が now() に上書き）
--   - parse-message-tags: tags のみ UPDATE（バックフィル）
--   - 管理操作: created_at / read_at / receiver_id の自由な UPDATE
-- -----------------------------------------------------------------------------
\echo '--- case f6: service_role が messages の INSERT / 任意列の UPDATE をできること'

RESET ROLE;
SET LOCAL request.jwt.claims = '{"role":"service_role"}';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE service_role;

DO $$
DECLARE r public.messages%ROWTYPE;
BEGIN
  PERFORM pg_temp.cg_expect_rows('f6 service_role Web 送信の形 INSERT',
    $sql$INSERT INTO public.messages (id, sender_id, receiver_id, content, sender_type, receiver_type,
                                      image_urls, reply_to_message_id)
         VALUES ('f6f6f6f6-9922-0000-0000-0000000000f6',
                 'aaaaaaaa-9922-0000-0000-00000000000a', 'bbbbbbbb-9922-0000-0000-00000000000b',
                 'f6 Web送信', 'trainer', 'client',
                 ARRAY['aaaaaaaa-9922-0000-0000-00000000000a/bbbbbbbb-9922-0000-0000-00000000000b/web.jpg'],
                 '11111111-9922-0000-0000-000000000001')$sql$, 1);

  PERFORM pg_temp.cg_expect_rows('f6 service_role Web 編集の形 UPDATE',
    $sql$UPDATE public.messages
         SET content = 'f6 Web編集後', is_edited = true,
             edited_at = '2026-09-01T00:00:00Z', updated_at = '2026-09-01T00:00:00Z'
         WHERE id = 'f6f6f6f6-9922-0000-0000-0000000000f6'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = 'f6f6f6f6-9922-0000-0000-0000000000f6';
  IF r.content IS DISTINCT FROM 'f6 Web編集後'
     OR r.is_edited IS DISTINCT FROM true
     OR r.edited_at IS DISTINCT FROM '2026-09-01T00:00:00Z'::timestamptz
     OR r.updated_at IS DISTINCT FROM now() THEN
    RAISE EXCEPTION 'FAIL: f6 Web 編集後の値が期待と異なる: %', to_jsonb(r);
  END IF;

  PERFORM pg_temp.cg_expect_rows('f6 service_role tags のみ UPDATE（parse-message-tags）',
    $sql$UPDATE public.messages SET tags = ARRAY['#食事', '#backfill']
         WHERE id = '11111111-9922-0000-0000-000000000001'$sql$, 1);

  PERFORM pg_temp.cg_expect_rows('f6 service_role created_at / read_at / receiver_id を自由に UPDATE',
    $sql$UPDATE public.messages
         SET created_at = now() - interval '1 day', read_at = NULL,
             receiver_id = 'aaaaaaaa-9922-0000-0000-0000000000a2'
         WHERE id = '33333333-9922-0000-0000-000000000003'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('f6 service_role receiver_id を戻す',
    $sql$UPDATE public.messages SET receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a'
         WHERE id = '33333333-9922-0000-0000-000000000003'$sql$, 1);
  PERFORM pg_temp.cg_expect_rows('f6 service_role 既読 M5 の read_at を付け替え',
    $sql$UPDATE public.messages SET read_at = now() - interval '30 minutes'
         WHERE id = '55555555-9922-0000-0000-000000000005'$sql$, 1);

  SELECT * INTO r FROM public.messages WHERE id = '11111111-9922-0000-0000-000000000001';
  IF r.tags IS DISTINCT FROM ARRAY['#食事', '#backfill'] THEN
    RAISE EXCEPTION 'FAIL: f6 M1.tags が % （期待 {#食事,#backfill}）', r.tags;
  END IF;
  SELECT * INTO r FROM public.messages WHERE id = '33333333-9922-0000-0000-000000000003';
  IF r.created_at IS DISTINCT FROM now() - interval '1 day'
     OR r.read_at IS NOT NULL
     OR r.receiver_id IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: f6 M3 の値が期待と異なる: %', to_jsonb(r);
  END IF;
  SELECT * INTO r FROM public.messages WHERE id = '55555555-9922-0000-0000-000000000005';
  IF r.read_at IS DISTINCT FROM now() - interval '30 minutes' THEN
    RAISE EXCEPTION 'FAIL: f6 M5.read_at が % （期待 now() - 30 minutes）', r.read_at;
  END IF;
  RAISE NOTICE 'OK: f6 service_role は messages の全列を書ける';
END $$;

-- =============================================================================
-- [section:H] ANON_WRITE_FORBIDDEN（トリガー側の anon 分岐）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 準備（postgres）: anon に INSERT / UPDATE を一時的に GRANT し、MA を作成する
--   本番の構成では anon の GRANT は剥奪済みで、anon の書き込みは権限チェック
--   （permission denied。a8 / c10 / e3）で落ちてトリガーまで届かない。ここでは
--   「将来 GRANT ALL が anon に戻っても、クレーム付き anon はトリガーで閉じている」
--   ことを検証するため、トランザクション内でだけ GRANT を戻す（ROLLBACK で消える。
--   さらに G の前に REVOKE し直す）
--   message MA: a0a0a0a0-9922-0000-0000-0000000000a0  C→T  created_at now()  未読
--   （f4 の一括既読化の後に作るので未読のまま。送信者 C は 5 分以内・受信者 T は未読）
-- -----------------------------------------------------------------------------
\echo '--- setup H: anon に INSERT / UPDATE を一時 GRANT・MA を作成（postgres）'

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

GRANT INSERT, UPDATE ON public.messages, public.clients TO anon;

INSERT INTO public.messages (
  id, sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at
) VALUES
  ('a0a0a0a0-9922-0000-0000-0000000000a0',
   'bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
   'client', 'trainer', 'MA C→T 未読（anon 分岐用）', now(), NULL);

DO $$
BEGIN
  IF NOT (has_table_privilege('anon', 'public.messages', 'INSERT')
          AND has_table_privilege('anon', 'public.messages', 'UPDATE')
          AND has_table_privilege('anon', 'public.clients', 'INSERT')
          AND has_table_privilege('anon', 'public.clients', 'UPDATE')) THEN
    RAISE EXCEPTION 'FAIL: setup H 前提崩れ — anon への一時 GRANT が効いていない';
  END IF;
  IF EXISTS (SELECT 1 FROM public.clients WHERE client_id = 'ffffffff-9922-0000-0000-0000000000f2') THEN
    RAISE EXCEPTION 'FAIL: setup H 前提崩れ — N2 の clients 行が既に存在する';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- ケース h1 / h2 / h5: anon + 顧客 C のクレーム
--   messages の INSERT / UPDATE / SELECT ポリシーは TO PUBLIC なので、GRANT があると
--   行はトリガーまで届く → ANON_WRITE_FORBIDDEN。
--   clients は UPDATE ポリシー（clients_update_own）が TO authenticated のため、
--   anon では更新対象の行が RLS で除外されトリガーは発火しない（0 行）。
--   SELECT ポリシー（Clients can view own profile）は TO PUBLIC で行自体は見えるので、
--   0 行は「見えないから」ではなく UPDATE ポリシーの role 限定によるもの
-- -----------------------------------------------------------------------------
\echo '--- case h1/h2/h5: anon + 顧客 C のクレームで messages 書き込みが ANON_WRITE_FORBIDDEN、clients UPDATE が 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-9922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-9922-0000-0000-00000000000b';
SET LOCAL ROLE anon;

DO $$
DECLARE
  v_before jsonb;
  v_after  jsonb;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'bbbbbbbb-9922-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'FAIL: h1 前提崩れ — anon ロールで auth.uid() が % （期待 顧客C）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  PERFORM pg_temp.cg_expect_code('h1 anon(クレーム=C) messages INSERT C → T',
    $sql$INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content)
         VALUES ('bbbbbbbb-9922-0000-0000-00000000000b', 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'client', 'trainer', 'h1 anon からの送信')$sql$,
    'ANON_WRITE_FORBIDDEN');

  -- h2 前提: MA が anon(クレーム=C) から見え、送信者ポリシー（5 分以内）の対象であること
  SELECT to_jsonb(m) INTO v_before FROM public.messages m
  WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0'
    AND sender_id = 'bbbbbbbb-9922-0000-0000-00000000000b'
    AND now() - created_at < interval '5 minutes';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: h2 前提崩れ — anon(クレーム=C) から 5 分以内の MA が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_code('h2 anon(クレーム=C) 送信者として MA.content を UPDATE',
    $sql$UPDATE public.messages SET content = 'h2 anon による編集'
         WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0'$sql$,
    'ANON_WRITE_FORBIDDEN');

  SELECT to_jsonb(m) INTO v_after FROM public.messages m
  WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: h2 拒否後に MA が変化している: before=% after=%', v_before, v_after;
  END IF;

  -- h5 前提: C の clients 行が anon(クレーム=C) から見えること
  SELECT to_jsonb(c) INTO v_before FROM public.clients c
  WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'FAIL: h5 前提崩れ — anon(クレーム=C) から C の clients 行が見えない';
  END IF;

  PERFORM pg_temp.cg_expect_rows('h5 anon(クレーム=C) clients.name UPDATE（RLS で 0 行）',
    $sql$UPDATE public.clients SET name = 'h5 anon による改名'
         WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b'$sql$, 0);

  SELECT to_jsonb(c) INTO v_after FROM public.clients c
  WHERE client_id = 'bbbbbbbb-9922-0000-0000-00000000000b';
  IF v_after IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'FAIL: h5 C の clients 行が変化している: before=% after=%', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: h5 C の clients 行は不変（0 行）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース h3: anon + トレーナー T のクレームで、受信者として未読 MA の既読化
--   （受信者ポリシーは TO PUBLIC）→ ANON_WRITE_FORBIDDEN
-- -----------------------------------------------------------------------------
\echo '--- case h3: anon + トレーナー T のクレームで未読 MA の read_at UPDATE が ANON_WRITE_FORBIDDEN であること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-9922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-9922-0000-0000-00000000000a';

DO $$
DECLARE v_read_at timestamptz;
BEGIN
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-9922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: h3 前提崩れ — anon ロールで auth.uid() が % （期待 T）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;
  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0'
    AND receiver_id = 'aaaaaaaa-9922-0000-0000-00000000000a';
  IF NOT FOUND OR v_read_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: h3 前提崩れ — anon(クレーム=T) から未読の MA が見えない (read_at=%)', v_read_at;
  END IF;

  PERFORM pg_temp.cg_expect_code('h3 anon(クレーム=T) 受信者として MA.read_at を UPDATE',
    $sql$UPDATE public.messages SET read_at = now()
         WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0'$sql$,
    'ANON_WRITE_FORBIDDEN');

  SELECT read_at INTO v_read_at FROM public.messages
  WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0';
  IF v_read_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: h3 拒否後に MA.read_at が % （期待 NULL のまま）', v_read_at;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- ケース h4: anon + 未登録ユーザー N2 のクレームで clients INSERT → ANON_WRITE_FORBIDDEN
--   clients_insert_own は TO authenticated なので anon には INSERT ポリシーが無いが、
--   RLS の WITH CHECK（既定拒否）は BEFORE トリガーの後に評価されるため、
--   トリガーの固定コードで拒否される
-- -----------------------------------------------------------------------------
\echo '--- case h4: anon + 未登録ユーザー N2 のクレームで clients INSERT が ANON_WRITE_FORBIDDEN であること'

SET LOCAL request.jwt.claims = '{"sub":"ffffffff-9922-0000-0000-0000000000f2","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'ffffffff-9922-0000-0000-0000000000f2';

DO $$
BEGIN
  IF auth.uid() IS DISTINCT FROM 'ffffffff-9922-0000-0000-0000000000f2'::uuid THEN
    RAISE EXCEPTION 'FAIL: h4 前提崩れ — anon ロールで auth.uid() が % （期待 N2）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;
  PERFORM pg_temp.cg_expect_code('h4 anon(クレーム=N2) clients INSERT',
    $sql$INSERT INTO public.clients (client_id, trainer_id, name, email, age, gender)
         VALUES ('ffffffff-9922-0000-0000-0000000000f2',
                 'aaaaaaaa-9922-0000-0000-00000000000a',
                 'RLSテスト新規N2', 'rls-test-colguard-n2@example.com', 30, 'female')$sql$,
    'ANON_WRITE_FORBIDDEN');
END $$;

-- -----------------------------------------------------------------------------
-- ケース h6: 後片付け（postgres）— anon の INSERT / UPDATE を REVOKE し直し、
--   拒否された書き込みで何も残っていないことを確認する
-- -----------------------------------------------------------------------------
\echo '--- case h6: anon の一時 GRANT を REVOKE し、拒否された書き込みが残っていないこと'

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

REVOKE INSERT, UPDATE ON public.messages, public.clients FROM anon;

DO $$
DECLARE r public.messages%ROWTYPE;
BEGIN
  IF has_table_privilege('anon', 'public.messages', 'INSERT')
     OR has_table_privilege('anon', 'public.messages', 'UPDATE')
     OR has_table_privilege('anon', 'public.clients', 'INSERT')
     OR has_table_privilege('anon', 'public.clients', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL: h6 REVOKE 後も anon に INSERT / UPDATE が残っている';
  END IF;
  IF EXISTS (SELECT 1 FROM public.clients WHERE client_id = 'ffffffff-9922-0000-0000-0000000000f2') THEN
    RAISE EXCEPTION 'FAIL: h6 anon の INSERT で N2 の clients 行が作られている';
  END IF;
  IF EXISTS (SELECT 1 FROM public.messages WHERE content = 'h1 anon からの送信') THEN
    RAISE EXCEPTION 'FAIL: h6 anon の INSERT でメッセージが作られている';
  END IF;
  SELECT * INTO r FROM public.messages WHERE id = 'a0a0a0a0-9922-0000-0000-0000000000a0';
  IF r.content IS DISTINCT FROM 'MA C→T 未読（anon 分岐用）' OR r.read_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: h6 MA が変化している: %', to_jsonb(r);
  END IF;
  RAISE NOTICE 'OK: h6 anon の INSERT / UPDATE を REVOKE し直した（拒否された書き込みの痕跡なし）';
END $$;

-- =============================================================================
-- [section:G] カタログ確認（postgres）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース g1 / g2: ガードトリガーとガード関数の定義
--   - BEFORE ROW・対象イベント（INSERT / UPDATE）を含むこと
--   - UPDATE OF <列> の列指定が無いこと（列指定があると、指定外の列や今後追加
--     される列の UPDATE でトリガーが発火せず保護が抜ける）
--   - 関数は SECURITY INVOKER（DEFINER だと current_user が所有者になり
--     エンドユーザーの判定ができない）かつ search_path = ''
--   - トリガー関数は発火時に EXECUTE 権限不要のため、RPC 面から外す
-- -----------------------------------------------------------------------------
\echo '--- case g1/g2: ガードトリガー 3 本とガード関数の定義が設計どおりであること'

RESET ROLE;
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE
  e record;
  r record;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      ('public.clients',  'clients_guard_protected_columns', true,  true),
      ('public.messages', 'messages_guard_insert',           true,  false),
      ('public.messages', 'messages_guard_update',           false, true)
    ) AS v(tbl, tgname, on_insert, on_update)
  LOOP
    SELECT t.tgenabled, t.tgtype::int AS tgtype,
           coalesce(array_length(t.tgattr::int2[], 1), 0) AS n_attr,
           p.oid AS fn_oid, p.oid::regprocedure::text AS fn_name,
           p.prosecdef, p.proconfig
      INTO r
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE t.tgrelid = e.tbl::regclass
      AND t.tgname = e.tgname
      AND NOT t.tgisinternal;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が % に存在しない', e.tgname, e.tbl;
    END IF;
    IF r.tgenabled NOT IN ('O', 'A') THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が無効 (tgenabled=%)', e.tgname, r.tgenabled;
    END IF;
    IF (r.tgtype & 1) = 0 OR (r.tgtype & 2) = 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が BEFORE ROW でない (tgtype=%)', e.tgname, r.tgtype;
    END IF;
    IF e.on_insert AND (r.tgtype & 4) = 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が INSERT で発火しない (tgtype=%)', e.tgname, r.tgtype;
    END IF;
    IF e.on_update AND (r.tgtype & 16) = 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が UPDATE で発火しない (tgtype=%)', e.tgname, r.tgtype;
    END IF;
    IF r.n_attr <> 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % に UPDATE OF の列指定がある（指定外の列が保護されない）', e.tgname;
    END IF;
    IF r.prosecdef THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % が SECURITY DEFINER（current_user が所有者になり判定不能）', r.fn_name;
    END IF;
    IF NOT coalesce('search_path=""' = ANY (r.proconfig), false) THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % に SET search_path = '''' が無い (proconfig=%)', r.fn_name, r.proconfig;
    END IF;
    IF has_function_privilege('anon', r.fn_oid, 'EXECUTE')
       OR has_function_privilege('authenticated', r.fn_oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % の EXECUTE が anon / authenticated に残っている', r.fn_name;
    END IF;
    RAISE NOTICE 'OK: g1/g2 % on % → % （BEFORE ROW・列指定なし・INVOKER・search_path=""・EXECUTE 剥奪）',
      e.tgname, e.tbl, r.fn_name;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース g3: anon は clients / messages に書き込めない（列単位の GRANT も無い）
-- -----------------------------------------------------------------------------
\echo '--- case g3: anon に clients / messages の INSERT / UPDATE（列単位含む）・messages の DELETE が無いこと'

DO $$
DECLARE e record;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      ('public.clients',  'INSERT'),
      ('public.clients',  'UPDATE'),
      ('public.messages', 'INSERT'),
      ('public.messages', 'UPDATE'),
      ('public.messages', 'DELETE')
    ) AS v(tbl, priv)
  LOOP
    IF has_table_privilege('anon', e.tbl, e.priv) THEN
      RAISE EXCEPTION 'FAIL: g3 anon に % の % 権限（テーブル単位）が残っている', e.tbl, e.priv;
    END IF;
    IF e.priv IN ('INSERT', 'UPDATE') THEN
      IF has_any_column_privilege('anon', e.tbl, e.priv) THEN
        RAISE EXCEPTION 'FAIL: g3 anon に % の % 権限（列単位）が残っている', e.tbl, e.priv;
      END IF;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: g3 anon は clients / messages に書き込み権限なし';
END $$;

-- -----------------------------------------------------------------------------
-- ケース g4: authenticated の clients 列権限が設計どおり
--   全列を走査し、許可リストと完全一致することを確認する
--   （今後追加される列は既定で権限なし = 許可リスト外 = false が期待値）
-- -----------------------------------------------------------------------------
\echo '--- case g4: authenticated の clients 列権限（INSERT / UPDATE）が設計どおりであること'

DO $$
DECLARE
  r     record;
  v_ins text[] := ARRAY['client_id', 'trainer_id', 'name', 'email', 'age', 'gender'];
  v_upd text[] := ARRAY['client_id', 'trainer_id', 'name', 'email', 'age', 'gender',
                        'profile_image_url', 'fcm_token', 'onboarding_completed_at'];
  v_bad text[] := '{}';
BEGIN
  IF has_table_privilege('authenticated', 'public.clients', 'INSERT') THEN
    v_bad := v_bad || 'テーブル単位の INSERT が残っている'::text;
  END IF;
  IF has_table_privilege('authenticated', 'public.clients', 'UPDATE') THEN
    v_bad := v_bad || 'テーブル単位の UPDATE が残っている'::text;
  END IF;

  FOR r IN
    SELECT attname::text AS col
    FROM pg_attribute
    WHERE attrelid = 'public.clients'::regclass AND attnum > 0 AND NOT attisdropped
    ORDER BY attnum
  LOOP
    IF has_column_privilege('authenticated', 'public.clients', r.col, 'INSERT')
       IS DISTINCT FROM (r.col = ANY (v_ins)) THEN
      v_bad := v_bad || format('INSERT(%s)=%s（期待 %s）', r.col,
        has_column_privilege('authenticated', 'public.clients', r.col, 'INSERT'), r.col = ANY (v_ins));
    END IF;
    IF has_column_privilege('authenticated', 'public.clients', r.col, 'UPDATE')
       IS DISTINCT FROM (r.col = ANY (v_upd)) THEN
      v_bad := v_bad || format('UPDATE(%s)=%s（期待 %s）', r.col,
        has_column_privilege('authenticated', 'public.clients', r.col, 'UPDATE'), r.col = ANY (v_upd));
    END IF;
  END LOOP;

  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'FAIL: g4 authenticated の clients 権限が設計と異なる: %', array_to_string(v_bad, ' / ');
  END IF;

  -- 明示確認（設計書 G 項目）: created_at / target_weight は不可、name / trainer_id は可
  IF has_column_privilege('authenticated', 'public.clients', 'created_at', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.clients', 'target_weight', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.clients', 'name', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.clients', 'trainer_id', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL: g4 authenticated の clients UPDATE 列権限（created_at / target_weight / name / trainer_id）が設計と異なる';
  END IF;
  RAISE NOTICE 'OK: g4 authenticated の clients 列権限は許可リストと完全一致';
END $$;

-- -----------------------------------------------------------------------------
-- ケース g5: 剥奪しすぎていないこと
--   authenticated: messages の INSERT / UPDATE（送信者・受信者とも authenticated の
--   ため列 GRANT では区別できずトリガーで判定）と clients の SELECT は残る。
--   service_role: clients / messages の INSERT / UPDATE は残る
-- -----------------------------------------------------------------------------
\echo '--- case g5: authenticated の messages 書き込み・service_role の書き込み権限が残っていること'

DO $$
BEGIN
  IF NOT has_table_privilege('authenticated', 'public.messages', 'INSERT')
     OR NOT has_table_privilege('authenticated', 'public.messages', 'UPDATE')
     OR NOT has_table_privilege('authenticated', 'public.clients', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: g5 authenticated の messages INSERT / UPDATE または clients SELECT が失われている';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.clients', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.clients', 'UPDATE')
     OR NOT has_table_privilege('service_role', 'public.messages', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.messages', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL: g5 service_role の clients / messages 書き込み権限が失われている';
  END IF;
  RAISE NOTICE 'OK: g5 authenticated の messages 書き込み・service_role の書き込み権限は維持';
END $$;

-- -----------------------------------------------------------------------------
-- ケース g6: authenticator（PostgREST の接続ロール）が SET ROLE できるロール
--   ガードは current_user が anon / authenticated 以外なら素通しにする
--   （service_role と SECURITY DEFINER 関数の所有者を通すため）。PostgREST は JWT の
--   role クレームに従って authenticator が所属するロールへ SET ROLE するので、
--   authenticator の所属が {anon, authenticated, service_role} から増えると、
--   その新しいロールのリクエストはガードを素通りする。ここが崩れたらガードの
--   判定条件を見直すこと（2026-09-22 時点でローカル・リモートとも 3 ロールのみ）。
--   直接の所属（pg_auth_members）と、入れ子を含む推移的な所属（pg_has_role MEMBER）の
--   両方を確認する
-- -----------------------------------------------------------------------------
\echo '--- case g6: authenticator の所属ロールがちょうど {anon, authenticated, service_role} であること'

DO $$
DECLARE
  v_expected text[] := ARRAY['anon', 'authenticated', 'service_role'];
  v_direct   text[];
  v_all      text[];
BEGIN
  IF to_regrole('authenticator') IS NULL THEN
    RAISE EXCEPTION 'FAIL: g6 ロール authenticator が存在しない';
  END IF;

  SELECT coalesce(array_agg(r.rolname::text ORDER BY r.rolname), '{}')
    INTO v_direct
  FROM pg_auth_members m
  JOIN pg_roles r ON r.oid = m.roleid
  WHERE m.member = to_regrole('authenticator');

  SELECT coalesce(array_agg(r.rolname::text ORDER BY r.rolname), '{}')
    INTO v_all
  FROM pg_roles r
  WHERE r.rolname <> 'authenticator'
    AND pg_has_role('authenticator', r.oid, 'MEMBER');

  IF v_direct IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'FAIL: g6 authenticator の直接の所属ロールが % （期待 %）', v_direct, v_expected;
  END IF;
  IF v_all IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'FAIL: g6 authenticator の推移的な所属ロールが % （期待 %）', v_all, v_expected;
  END IF;
  RAISE NOTICE 'OK: g6 authenticator の所属ロールは直接・推移とも %', v_direct;
END $$;

-- [section:END]
RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL COLUMN WRITE GUARDS TESTS PASSED'
