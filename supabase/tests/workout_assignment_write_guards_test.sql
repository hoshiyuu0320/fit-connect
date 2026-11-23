-- =============================================================================
-- ワークアウトの割り当ての書き込みガード テスト
-- （20261123000100_workout_assignment_write_guards.sql）
--
-- 背景: workout_assignments / workout_assignment_exercises の顧客用 UPDATE ポリシーには
-- WITH CHECK も列の制限も無く、トレーナー用の ALL ポリシーは client_id を縛っていなかった。
-- anon / authenticated はテーブル単位の INSERT / UPDATE / DELETE を持っていた
-- （2026-11-23 に修正前のスキーマの隔離スタックで確認）。
--   - 顧客が自分の割り当ての plan_id を他トレーナーのプランに変えると、そのプラン
--     （題名・説明）が clients_read_assigned_plans で読めた
--   - 顧客が trainer_id を別のトレーナーに変えると、元のトレーナーから消え、付け替え先の
--     トレーナーが割り当てと種目を読み書き・削除できた
--   - 顧客が trainer_note / session_id / started_at / created_at、種目の exercise_name /
--     target_* / memo / order_index / linked_exercise_id / assignment_id を書き換えられ、
--     アプリが扱わないセッション型の割り当ての status・種目の actual_sets も書けた
--   - トレーナーが authenticated で直接、他トレーナーの顧客に割り当てと種目を INSERT でき、
--     その顧客から見えた（付け替え先のプランも読めた。完了にすると顧客の記録の連続にも数えられた）
--   - 顧客のクレームを持った anon も、顧客と同じに書けた（顧客用ポリシーが TO public）
-- 本テストは、正規の書き込み経路（Mobile の 5 つの書き込み / Web の API = service_role /
-- auto-skip-workouts / FK の参照動作）を壊さずに、上記の書き込みだけが拒否されることを確かめる。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/workout_assignment_write_guards_test.sql
--   ※ コンテナ名は環境に合わせて読み替える
--     （本ブランチの開発時は隔離スタック supabase_db_fit-connect-wag を使用）
--
-- - 全ケース成功時のみ最終行に「ALL WORKOUT ASSIGNMENT WRITE GUARDS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--   （試験用の行は UUID が a55e1123-0000-4000-8000- で始まる）
-- - マイグレーション未適用の DB では case b1 で FAIL する（TDD の RED 確認用）
-- - 前提 migration: 20261123000000（get_record_streak。case i6 で呼ぶ）/
--   20261123000100（本ガード）
--
-- 拒否の判定基準（「別の理由で落ちたのに PASS」「0 行 no-op なのに PASS」を防ぐ）:
--   - トリガーによる拒否: SQLSTATE = '42501' かつ SQLERRM = 固定コード の完全一致
--       WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN / WORKOUT_ASSIGNMENTS_NOT_CLIENT /
--       WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED / WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE /
--       WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN / WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT /
--       WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED /
--       WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE / ANON_WRITE_FORBIDDEN
--   - 表・列の権限（GRANT）による拒否: SQLSTATE = '42501' かつ SQLERRM =
--     'permission denied for table <期待する表名>' の完全一致（列の権限が無い UPDATE も表名で
--     報告される。'permission denied for function ...' / 'for schema ...' など別の理由の 42501 では通らない）
--   - 例外が出ずに終わった場合は ROW_COUNT が 0 でも FAIL（UPDATE / DELETE の拒否ケースは、
--     事前に対象行がその呼び出し元から見えることを確かめてから実行する。case a1）
--   - 「0 行」が期待のケース（他人の行・RLS で行が除かれるもの）は、ROW_COUNT = 0 を確かめる
--   - 拒否のあとに行が変わっていないことは、postgres で取ったスナップショット
--     （試験用の全行の to_jsonb）との比較で確かめる（case f1 / h9）
--
-- 試験データ（a55e1123-0000-4000-8000-<下の 12 桁>）:
--   トレーナー T（00000000a001）/ T2（00000000a002。別のトレーナー）
--   顧客 C（00000000c001。T の顧客。主な呼び出し元）/ D（00000000c002。T の別の顧客）/
--        C2（00000000c003。T2 の顧客）/ E（00000000c004。T の顧客。j3 で削除）
--   プラン P_self（T・self_guided）/ P_session（T・session）/ P2_self（T2・self_guided）/
--          P_del（T・self_guided。j2a で service_role が削除）/ P_del2（T・self_guided。j2b で T が削除）
--   セッション S1（T↔C。A_sess が参照）/ S2（T2↔C2）/ S3（T↔C。A_link が参照。j1 で T が削除）
--   割り当て（T→C・pending が既定）:
--     A（P_self。拒否の対象。trainer_note あり）/ A_sess（P_session・session_id = S1）/
--     A_D（T→D）/ A2（T2→C2）/ A_c・A_c2（Mobile の完了）/ A_s（Mobile のスキップ）/
--     A_r（skipped。Mobile の日付の変更）/ A_r2（Mobile の日付の変更・旧版の形）/
--     A_old・A_old_s（予定日が 5 日前。auto-skip の対象 / セッション型で対象外）/
--     A_link（P_session・session_id = S3）/ A_pd（P_del）/ A_pd2（P_del2）/ A_E（T→E）
--   種目: X（A。拒否の対象。memo あり）/ X_sess（A_sess）/ X_D（A_D）/ X2（A2）/
--         X_ok・X_ok2（A。Mobile の書き込み）/ X_pd（A_pd）/ X_pd2（A_pd2）/ X_E（A_E）
--   プランの種目のひな形: WE1・WE2（P_self。Web の POST がコピーする）
--
-- 検証ケース:
--   A. 前提
--     a1  C から A・A_sess・X・X_sess が見える（UPDATE の対象になりうる）。C は A / A_sess のプランの
--         plan_type を読める（clients_read_assigned_plans）。C から A_D・A2・X_D・X2 は見えない。
--         T から A・X が見え、T2 からは見えない
--   B. 割り当ての禁止系（顧客 C・authenticated）
--     b1  保護列（id / trainer_id / client_id / plan_id / created_at / session_id / trainer_note /
--         started_at）を 1 列ずつ UPDATE → 各 permission denied
--     b2  許可列（status）と保護列（trainer_note）を同時に UPDATE → permission denied
--     b3  セッション型の A_sess で許可列（status / finished_at / assigned_date / client_feedback /
--         calories / updated_at）を 1 列ずつ・Mobile の完了の形 → 各 WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED
--     b4  他人の割り当て（A_D・A2）の status → 各 0 行
--     b5  INSERT（自分宛て）/ 自分の A の DELETE → 各 permission denied
--     b6  （fail closed）clients_read_assigned_plans を外すと（プランの種別が読めないと）、正規の
--         Mobile の書き込みも WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED（SAVEPOINT で戻す）
--   C. 種目の禁止系（顧客 C）
--     c1  保護列（id / assignment_id / exercise_name / target_sets / target_reps / target_weight /
--         order_index / memo / linked_exercise_id / created_at）を 1 列ずつ → 各 permission denied
--     c2  セッション型の X_sess で許可列（actual_sets / is_completed / completed_at）を 1 列ずつ・
--         Mobile のセット実績の形 → 各 WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED
--     c3  他人の種目（X_D・X2）の is_completed → 各 0 行
--     c4  INSERT（自分の A へ）/ X の DELETE → 各 permission denied
--   D. トレーナーの直接の書き込み（authenticated）
--     d1  T2 が C（T の顧客）宛ての割り当てを INSERT / T が自分の顧客 C 宛てに INSERT → 各 permission denied
--     d2  T が自分の割り当て A の status → WORKOUT_ASSIGNMENTS_NOT_CLIENT / trainer_note → permission denied
--     d3  T が A を DELETE → permission denied
--     d4  T が A に種目を INSERT → permission denied / X の is_completed → WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT /
--         X の memo → permission denied / X の DELETE → permission denied
--     d5  T2 が A の status（自分の割り当てではない）→ 0 行
--   E. anon
--     e1  anon（クレームなし）: 両表の UPDATE / INSERT / DELETE → 各 permission denied
--     e2  anon + C のクレーム: A の status・trainer_id、X の is_completed → 各 permission denied
--     e3  anon + T のクレーム: INSERT → permission denied
--   F. 拒否後の不変
--     f1  B〜E のあと、試験用の全行がスナップショットと同じ（postgres で比較）
--   H. トリガー層だけ（表の INSERT / UPDATE / DELETE を anon / authenticated に一時的に戻す。
--      将来の GRANT ALL で表の権限が戻っても閉じていることの確認。SAVEPOINT で戻す）
--     h1  C が A の保護列 8 列を 1 列ずつ → 各 WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE
--     h2  C が X の保護列 10 列を 1 列ずつ → 各 WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE
--     h3  C がセッション型 A_sess の trainer_note / X_sess の memo → 各 *_NOT_SELF_GUIDED
--     h4  C の INSERT（割り当て・種目）→ 各 *_WRITE_FORBIDDEN / C の A の DELETE → 0 行
--         （顧客の DELETE ポリシーが無く、RLS がトリガーより先に行を除く）
--     h5  T2 が C 宛てに INSERT → WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN / T の A の DELETE → 同 /
--         T の A の trainer_note → WORKOUT_ASSIGNMENTS_NOT_CLIENT
--     h6  T の種目の INSERT・X の DELETE → 各 WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN /
--         X の memo → WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT
--     h7  anon + C: A の status・X の is_completed → 各 ANON_WRITE_FORBIDDEN /
--         anon + T: INSERT → ANON_WRITE_FORBIDDEN（BEFORE トリガーは WITH CHECK より先）
--     h8  anon（クレームなし）の A の status / anon + C の A の DELETE → 各 0 行（RLS）
--     h9  H のあと試験用の全行がスナップショットと同じ。SAVEPOINT で戻した後に権限が元に戻っている
--   I. 正規経路（回帰確認）
--     i1  Mobile toggleExerciseCompletion（{is_completed, completed_at}: 完了 → 戻す）→ 各 1 行・値
--     i2  Mobile updateActualSets（{actual_sets, is_completed, completed_at}: 途中 → 全セット完了）→ 各 1 行・値
--     i3  Mobile completeAssignment（{status, finished_at, client_feedback, calories} / 感想・カロリー無し）
--         → 各 1 行・値。保護列（trainer_note・started_at・session_id 等）は不変
--     i4  Mobile skipAssignment（{status: skipped, updated_at}）→ 1 行
--     i5  Mobile rescheduleAssignment（{assigned_date, status: pending, updated_at}。skipped → pending）/
--         旧版の形（{assigned_date, updated_at}）→ 各 1 行
--     i6  C の get_record_streak で、i3 の完了が今日の記録として数えられる（i1 の前は false）
--     i7  service_role: Web の POST（割り当ての INSERT・種目のコピーの INSERT・session_id の UPDATE）→ 成功
--     i8  service_role: Web の PATCH（updated_at / assigned_date / status / trainer_note /
--         client_feedback / started_at / finished_at）・種目の PATCH（actual_sets / is_completed / memo）→ 各 1 行・値
--     i9  service_role: auto-skip-workouts（候補の抽出 → 条件付き UPDATE）→ A_old だけ skipped
--     i10 service_role: Web の DELETE → 1 行。種目も CASCADE で消える
--   J. FK の参照動作（ガードは postgres = 参照側の表の所有者として動く参照動作を止めない）
--     j1  T が authenticated でセッション S3 を DELETE（Web の deleteSession.ts の形）→ A_link.session_id が NULL
--     j2a service_role がプラン P_del を DELETE（Web の API）→ A_pd・X_pd が CASCADE で消える
--     j2b T が authenticated でプラン P_del2 を DELETE → A_pd2・X_pd2 が CASCADE で消える
--     j3  service_role が顧客 E を DELETE（delete-account）→ A_E・X_E が CASCADE で消える
--   G. カタログ確認（postgres）
--     g1  ガードトリガー 2 本が存在・有効・BEFORE ROW・INSERT / UPDATE / DELETE・列指定なし・正しい関数
--     g2  ガード関数が SECURITY INVOKER・search_path=""・EXECUTE は PUBLIC / anon / authenticated /
--         service_role のどれにも無い（proacl が NULL でない）
--     g3  anon に両表の INSERT / UPDATE（列単位を含む）・DELETE が無い
--     g4  authenticated: 両表の INSERT（列単位を含む）・DELETE・表単位の UPDATE が無く、UPDATE の
--         列権限が許可リストと完全一致（全列を走査）。SELECT は残っている
--     g5  service_role の両表の SELECT / INSERT / UPDATE / DELETE は残っている
--     g6  authenticator（PostgREST の接続ロール）の所属ロールがちょうど {anon, authenticated, service_role}
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 共通のヘルパー（pg_temp に作成。ROLLBACK と共に消える）
--   SECURITY INVOKER（既定）のため、呼び出し時の current_user のまま DML が実行される
-- -----------------------------------------------------------------------------
\echo '--- setup: ヘルパー作成'

-- 試験用の id（未知の名前は NULL）
CREATE FUNCTION pg_temp.wg_id(p_name text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('a55e1123-0000-4000-8000-' || CASE p_name
    WHEN 'T'         THEN '00000000a001'
    WHEN 'T2'        THEN '00000000a002'
    WHEN 'C'         THEN '00000000c001'
    WHEN 'D'         THEN '00000000c002'
    WHEN 'C2'        THEN '00000000c003'
    WHEN 'E'         THEN '00000000c004'
    WHEN 'P_self'    THEN '00000000b001'
    WHEN 'P_session' THEN '00000000b002'
    WHEN 'P2_self'   THEN '00000000b003'
    WHEN 'P_del'     THEN '00000000b004'
    WHEN 'P_del2'    THEN '00000000b005'
    WHEN 'WE1'       THEN '00000000e001'
    WHEN 'WE2'       THEN '00000000e002'
    WHEN 'S1'        THEN '000000005001'
    WHEN 'S2'        THEN '000000005002'
    WHEN 'S3'        THEN '000000005003'
    WHEN 'A'         THEN '00000000d001'
    WHEN 'A_sess'    THEN '00000000d002'
    WHEN 'A_D'       THEN '00000000d003'
    WHEN 'A2'        THEN '00000000d004'
    WHEN 'A_c'       THEN '00000000d005'
    WHEN 'A_c2'      THEN '00000000d006'
    WHEN 'A_s'       THEN '00000000d007'
    WHEN 'A_r'       THEN '00000000d008'
    WHEN 'A_r2'      THEN '00000000d009'
    WHEN 'A_old'     THEN '00000000d00a'
    WHEN 'A_old_s'   THEN '00000000d00b'
    WHEN 'A_link'    THEN '00000000d00c'
    WHEN 'A_pd'      THEN '00000000d00d'
    WHEN 'A_pd2'     THEN '00000000d00e'
    WHEN 'A_E'       THEN '00000000d00f'
    WHEN 'A_new'     THEN '00000000d0ff'
    WHEN 'X'         THEN '00000000f001'
    WHEN 'X_sess'    THEN '00000000f002'
    WHEN 'X_D'       THEN '00000000f003'
    WHEN 'X2'        THEN '00000000f004'
    WHEN 'X_ok'      THEN '00000000f005'
    WHEN 'X_ok2'     THEN '00000000f006'
    WHEN 'X_pd'      THEN '00000000f007'
    WHEN 'X_pd2'     THEN '00000000f008'
    WHEN 'X_E'       THEN '00000000f009'
    WHEN 'X_new'     THEN '00000000f0ff'
    WHEN 'Z'         THEN '00000000ffff'
  END)::uuid
$$;

-- 呼び出し元を切り替える（SET LOCAL なので次の切り替えかトランザクションの終わりまで有効）
--   'postgres'     : RESET ROLE（クレームなし。RLS を通らない）
--   'service_role' : Web の API・Edge Functions（{"role":"service_role"}）
--   'anon'         : クレームなしの anon（公開キーだけの要求）
--   'anon:<名前>'  : その人の JWT クレームを持った anon（GRANT 層だけを単独で確かめる）
--   それ以外       : その人（pg_temp.wg_id の名前）の authenticated
-- 切り替え後に current_user と auth.uid() が期待どおりかを確かめる（前提崩れの検出）
CREATE FUNCTION pg_temp.wg_as(p_who text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_role   text;
  v_sub    uuid;
  v_claims text := '';
BEGIN
  RESET ROLE;
  IF p_who = 'postgres' THEN
    v_role := NULL;
  ELSIF p_who = 'service_role' THEN
    v_role := 'service_role';
    v_claims := '{"role":"service_role"}';
  ELSIF p_who = 'anon' THEN
    v_role := 'anon';
  ELSE
    v_role := CASE WHEN p_who LIKE 'anon:%' THEN 'anon' ELSE 'authenticated' END;
    v_sub := pg_temp.wg_id(CASE WHEN p_who LIKE 'anon:%' THEN substr(p_who, 6) ELSE p_who END);
    IF v_sub IS NULL THEN
      RAISE EXCEPTION 'テストの誤り: 未知の呼び出し元 %', p_who;
    END IF;
    v_claims := json_build_object('sub', v_sub, 'role', 'authenticated')::text;
  END IF;

  PERFORM set_config('request.jwt.claims', v_claims, true);
  PERFORM set_config('request.jwt.claim.sub', coalesce(v_sub::text, ''), true);
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

--   wg_expect_reject(case, sql, 完全一致候補[], LIKE 候補[])
--     : 例外が出なければ FAIL（ROW_COUNT も表示）。SQLSTATE が 42501 でない、
--       または SQLERRM が候補のどれにも一致しなければ FAIL
--   wg_expect_code(case, sql, 固定コード)  : トリガーによる拒否（SQLERRM 完全一致）
--   wg_expect_denied(case, sql, 表名)      : 権限による拒否（'permission denied for table <表名>' の完全一致）
--   wg_expect_rows(case, sql, 期待行数)    : 正規経路・0 行のケース。例外・行数違いは FAIL
CREATE FUNCTION pg_temp.wg_expect_reject(
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

CREATE FUNCTION pg_temp.wg_expect_code(p_case text, p_sql text, p_code text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  PERFORM pg_temp.wg_expect_reject(p_case, p_sql, ARRAY[p_code], NULL);
END
$fn$;

CREATE FUNCTION pg_temp.wg_expect_denied(p_case text, p_sql text, p_table text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
  -- 表名まで完全一致にする（'permission denied for function ...' / 'for schema ...' など、
  -- 別の理由の 42501 では通らない）
  PERFORM pg_temp.wg_expect_reject(p_case, p_sql, ARRAY['permission denied for table ' || p_table], NULL);
END
$fn$;

CREATE FUNCTION pg_temp.wg_expect_rows(p_case text, p_sql text, p_rows bigint)
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
      RAISE EXCEPTION 'FAIL: [%] 失敗した SQLSTATE=% SQLERRM=% (current_user=%, auth.uid()=%) SQL: %',
        p_case, v_state, v_msg, current_user, coalesce(auth.uid()::text, 'NULL'), p_sql;
  END;

  IF v_rows IS DISTINCT FROM p_rows THEN
    RAISE EXCEPTION 'FAIL: [%] ROW_COUNT=% （期待 %） SQL: %', p_case, v_rows, p_rows, p_sql;
  END IF;

  RAISE NOTICE 'OK: [%] % 行', p_case, v_rows;
END
$fn$;

-- 試験用の全行（両表）のスナップショット。postgres で取り、postgres で比べる
CREATE TEMP TABLE wg_snapshot (tbl text NOT NULL, id uuid NOT NULL, row_data jsonb NOT NULL,
                               PRIMARY KEY (tbl, id)) ON COMMIT DROP;

CREATE FUNCTION pg_temp.wg_take_snapshot() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  DELETE FROM pg_temp.wg_snapshot;
  INSERT INTO pg_temp.wg_snapshot
  SELECT 'workout_assignments', a.id, to_jsonb(a) FROM public.workout_assignments a
   WHERE a.id::text LIKE 'a55e1123-0000-4000-8000-%'
  UNION ALL
  SELECT 'workout_assignment_exercises', x.id, to_jsonb(x) FROM public.workout_assignment_exercises x
   WHERE x.id::text LIKE 'a55e1123-0000-4000-8000-%';
END
$fn$;

CREATE FUNCTION pg_temp.wg_assert_unchanged(p_case text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_diff text;
  v_n    bigint;
BEGIN
  IF current_user IS DISTINCT FROM session_user THEN
    RAISE EXCEPTION 'テストの誤り: wg_assert_unchanged は postgres で呼ぶ（current_user=%）', current_user;
  END IF;
  WITH cur AS (
    SELECT 'workout_assignments' AS tbl, a.id, to_jsonb(a) AS row_data FROM public.workout_assignments a
     WHERE a.id::text LIKE 'a55e1123-0000-4000-8000-%'
    UNION ALL
    SELECT 'workout_assignment_exercises', x.id, to_jsonb(x) FROM public.workout_assignment_exercises x
     WHERE x.id::text LIKE 'a55e1123-0000-4000-8000-%'
  )
  SELECT count(*), string_agg(format('%s %s: before=%s after=%s', coalesce(s.tbl, c.tbl), coalesce(s.id, c.id),
                                     coalesce(s.row_data::text, '(無し)'), coalesce(c.row_data::text, '(無し)')), E'\n')
    INTO v_n, v_diff
    FROM pg_temp.wg_snapshot s
    FULL JOIN cur c ON c.tbl = s.tbl AND c.id = s.id
   WHERE s.row_data IS DISTINCT FROM c.row_data;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'FAIL: [%] 拒否のあとに行が変わっている（% 行）:%', p_case, v_n, E'\n' || v_diff;
  END IF;
  SELECT count(*) INTO v_n FROM pg_temp.wg_snapshot;
  RAISE NOTICE 'OK: [%] 試験用の % 行はスナップショットと同じ', p_case, v_n;
END
$fn$;

-- -----------------------------------------------------------------------------
-- 試験データ（postgres として実行。RLS を通らない・ガードの対象外）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT pg_temp.wg_id(n), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'wag-test-' || lower(n) || '@example.com', 'x', now(), now(), now(),
       '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['T', 'T2', 'C', 'D', 'C2', 'E']) AS n;

INSERT INTO public.trainers (id, name, email) VALUES
  (pg_temp.wg_id('T'),  '割り当てガードテスト トレーナーT',  'wag-test-t@example.com'),
  (pg_temp.wg_id('T2'), '割り当てガードテスト トレーナーT2', 'wag-test-t2@example.com');

INSERT INTO public.clients (client_id, name, trainer_id) VALUES
  (pg_temp.wg_id('C'),  '割り当てガードテスト顧客C',  pg_temp.wg_id('T')),
  (pg_temp.wg_id('D'),  '割り当てガードテスト顧客D',  pg_temp.wg_id('T')),
  (pg_temp.wg_id('C2'), '割り当てガードテスト顧客C2', pg_temp.wg_id('T2')),
  (pg_temp.wg_id('E'),  '割り当てガードテスト顧客E',  pg_temp.wg_id('T'));

INSERT INTO public.workout_plans (id, trainer_id, title, plan_type) VALUES
  (pg_temp.wg_id('P_self'),    pg_temp.wg_id('T'),  'ガードテスト: セルフガイド',          'self_guided'),
  (pg_temp.wg_id('P_session'), pg_temp.wg_id('T'),  'ガードテスト: セッション',            'session'),
  (pg_temp.wg_id('P2_self'),   pg_temp.wg_id('T2'), 'ガードテスト: T2 のセルフガイド',     'self_guided'),
  (pg_temp.wg_id('P_del'),     pg_temp.wg_id('T'),  'ガードテスト: service_role が消す',   'self_guided'),
  (pg_temp.wg_id('P_del2'),    pg_temp.wg_id('T'),  'ガードテスト: T が消す',              'self_guided');

INSERT INTO public.workout_exercises (id, plan_id, name, sets, reps, weight, order_index) VALUES
  (pg_temp.wg_id('WE1'), pg_temp.wg_id('P_self'), 'スクワット', 3, 10, 40, 0),
  (pg_temp.wg_id('WE2'), pg_temp.wg_id('P_self'), 'プランク',   3, NULL, NULL, 1);

INSERT INTO public.sessions (id, trainer_id, client_id, session_date) VALUES
  (pg_temp.wg_id('S1'), pg_temp.wg_id('T'),  pg_temp.wg_id('C'),  now() + interval '1 day'),
  (pg_temp.wg_id('S2'), pg_temp.wg_id('T2'), pg_temp.wg_id('C2'), now() + interval '1 day'),
  (pg_temp.wg_id('S3'), pg_temp.wg_id('T'),  pg_temp.wg_id('C'),  now() + interval '2 days');

-- 予定日は日本時間の今日（auto-skip の対象だけ 5 日前）。created_at は判別用に固定値
INSERT INTO public.workout_assignments
  (id, trainer_id, client_id, plan_id, assigned_date, status, session_id, trainer_note, created_at, updated_at)
SELECT pg_temp.wg_id(v.a), pg_temp.wg_id(v.t), pg_temp.wg_id(v.c), pg_temp.wg_id(v.p),
       (now() AT TIME ZONE 'Asia/Tokyo')::date + v.day_offset, v.status, pg_temp.wg_id(v.s), v.note,
       '2026-01-15 00:00:00+00', '2026-01-15 00:00:00+00'
  FROM (VALUES
    ('A',       'T',  'C',  'P_self',    0,  'pending', NULL, 'T のメモ（顧客は書けない）'),
    ('A_sess',  'T',  'C',  'P_session', 0,  'pending', 'S1', 'セッションのメモ'),
    ('A_D',     'T',  'D',  'P_self',    0,  'pending', NULL, NULL),
    ('A2',      'T2', 'C2', 'P2_self',   0,  'pending', NULL, NULL),
    ('A_c',     'T',  'C',  'P_self',    0,  'pending', NULL, '完了の前のメモ'),
    ('A_c2',    'T',  'C',  'P_self',    0,  'pending', NULL, NULL),
    ('A_s',     'T',  'C',  'P_self',    0,  'pending', NULL, NULL),
    ('A_r',     'T',  'C',  'P_self',    -1, 'skipped', NULL, NULL),
    ('A_r2',    'T',  'C',  'P_self',    0,  'pending', NULL, NULL),
    ('A_old',   'T',  'C',  'P_self',    -5, 'pending', NULL, NULL),
    ('A_old_s', 'T',  'C',  'P_session', -5, 'pending', NULL, NULL),
    ('A_link',  'T',  'C',  'P_session', 1,  'pending', 'S3', NULL),
    ('A_pd',    'T',  'C',  'P_del',     0,  'pending', NULL, NULL),
    ('A_pd2',   'T',  'C',  'P_del2',    0,  'pending', NULL, NULL),
    ('A_E',     'T',  'E',  'P_self',    0,  'pending', NULL, NULL)
  ) AS v(a, t, c, p, day_offset, status, s, note);

INSERT INTO public.workout_assignment_exercises
  (id, assignment_id, exercise_name, target_sets, target_reps, target_weight, order_index, memo, created_at)
SELECT pg_temp.wg_id(v.x), pg_temp.wg_id(v.a), v.name, 3, 10, v.w, v.ord, v.memo, '2026-01-15 00:00:00+00'
  FROM (VALUES
    ('X',      'A',      'スクワット',     40::numeric, 0, 'T のフォーム指示（顧客は書けない）'),
    ('X_sess', 'A_sess', 'ベンチプレス',   60,          0, NULL),
    ('X_D',    'A_D',    'ランジ',         NULL,        0, NULL),
    ('X2',     'A2',     'デッドリフト',   80,          0, NULL),
    ('X_ok',   'A',      'プランク',       NULL,        1, NULL),
    ('X_ok2',  'A',      'ショルダープレス', 20,        2, NULL),
    ('X_pd',   'A_pd',   '腕立て伏せ',     NULL,        0, NULL),
    ('X_pd2',  'A_pd2',  '懸垂',           NULL,        0, NULL),
    ('X_E',    'A_E',    'クランチ',       NULL,        0, NULL)
  ) AS v(x, a, name, w, ord, memo);

-- =============================================================================
-- [section:A] 前提
-- =============================================================================
\echo '--- case a1: 前提（C・T・T2 から見える行、C がプランの種別を読めること）'

DO $$
DECLARE
  v_n int;
  v_types text;
BEGIN
  PERFORM pg_temp.wg_as('C');
  SELECT count(*) INTO v_n FROM public.workout_assignments
   WHERE id IN (pg_temp.wg_id('A'), pg_temp.wg_id('A_sess'));
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — C から A・A_sess が % 行（期待 2）', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.workout_assignment_exercises
   WHERE id IN (pg_temp.wg_id('X'), pg_temp.wg_id('X_sess'), pg_temp.wg_id('X_ok'), pg_temp.wg_id('X_ok2'));
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — C から X・X_sess・X_ok・X_ok2 が % 行（期待 4）', v_n;
  END IF;
  -- C が自分の割り当てのプランの plan_type を読める（ガードの self_guided 判定と
  -- get_record_streak が使う。読めないと正規の書き込みも拒否される = case b6）
  SELECT string_agg(p.plan_type, ',' ORDER BY p.plan_type) INTO v_types
    FROM public.workout_plans p
   WHERE p.id IN (pg_temp.wg_id('P_self'), pg_temp.wg_id('P_session'));
  IF v_types IS DISTINCT FROM 'self_guided,session' THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — C から読めるプランの種別が %（期待 self_guided,session）', v_types;
  END IF;
  SELECT count(*) INTO v_n FROM public.workout_assignments
   WHERE id IN (pg_temp.wg_id('A_D'), pg_temp.wg_id('A2'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — C から他人の割り当て A_D・A2 が % 行見える', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.workout_assignment_exercises
   WHERE id IN (pg_temp.wg_id('X_D'), pg_temp.wg_id('X2'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — C から他人の種目 X_D・X2 が % 行見える', v_n;
  END IF;

  PERFORM pg_temp.wg_as('T');
  SELECT count(*) INTO v_n FROM public.workout_assignments WHERE id = pg_temp.wg_id('A');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — T から A が % 行（期待 1）', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.workout_assignment_exercises WHERE id = pg_temp.wg_id('X');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — T から X が % 行（期待 1）', v_n;
  END IF;

  PERFORM pg_temp.wg_as('T2');
  SELECT count(*) INTO v_n FROM public.workout_assignments WHERE id = pg_temp.wg_id('A');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: a1 前提崩れ — T2 から A が % 行見える', v_n;
  END IF;

  PERFORM pg_temp.wg_as('postgres');
  RAISE NOTICE 'OK: a1 C は自分の A・A_sess・種目とプランの種別が見え、他人の行は見えない。T は A・X が見え、T2 は見えない';
END $$;

-- 拒否系（B〜E）の前のスナップショット
DO $$ BEGIN PERFORM pg_temp.wg_take_snapshot(); END $$;

-- =============================================================================
-- [section:B] 割り当ての禁止系（顧客 C）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース b1: 保護列は 1 列ずつ permission denied（authenticated の UPDATE 列権限は
--   status / assigned_date / finished_at / client_feedback / calories / updated_at だけ）
-- -----------------------------------------------------------------------------
\echo '--- case b1: 顧客 C が A の保護列を 1 列ずつ更新できないこと (permission denied)'

DO $$
DECLARE r record;
BEGIN
  PERFORM pg_temp.wg_as('C');
  FOR r IN
    SELECT * FROM (VALUES
      ('id',           quote_literal(pg_temp.wg_id('Z'))),
      ('trainer_id',   quote_literal(pg_temp.wg_id('T2'))),
      ('client_id',    quote_literal(pg_temp.wg_id('D'))),
      ('plan_id',      quote_literal(pg_temp.wg_id('P2_self'))),
      ('created_at',   '''-infinity'''),
      ('session_id',   quote_literal(pg_temp.wg_id('S2'))),
      ('trainer_note', '''顧客が書き換えたメモ'''),
      ('started_at',   '''2000-01-01 00:00:00+00''')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_denied(
      format('b1 workout_assignments.%s', r.col),
      format('UPDATE public.workout_assignments SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('A')),
      'workout_assignments');
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース b2: 許可列と保護列を同時に書く（Mobile の完了 + trainer_note）→ permission denied
-- -----------------------------------------------------------------------------
\echo '--- case b2: 許可列と保護列を同時に更新できないこと (permission denied)'

DO $$
BEGIN
  PERFORM pg_temp.wg_expect_denied('b2 status + trainer_note',
    format($sql$UPDATE public.workout_assignments
                SET status = 'completed', finished_at = now(), trainer_note = 'x'
                WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'workout_assignments');
END $$;

-- -----------------------------------------------------------------------------
-- ケース b3: セッション型の割り当て（Mobile は表示も書き込みもしない）は、許可列でも
--   WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED（セッションの結果はトレーナーが Web で記録する）
-- -----------------------------------------------------------------------------
\echo '--- case b3: 顧客 C がセッション型の A_sess を更新できないこと (WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED)'

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('status',          '''completed'''),
      ('finished_at',     'now()'),
      ('assigned_date',   '''2030-01-01''::date'),
      ('client_feedback', '''感想'''),
      ('calories',        '300'),
      ('updated_at',      'now()')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_code(
      format('b3 セッション型 A_sess.%s', r.col),
      format('UPDATE public.workout_assignments SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('A_sess')),
      'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED');
  END LOOP;
  PERFORM pg_temp.wg_expect_code('b3 セッション型 A_sess に Mobile の完了の形',
    format($sql$UPDATE public.workout_assignments
                SET status = 'completed', finished_at = now(), client_feedback = 'よかった', calories = 250
                WHERE id = %L$sql$, pg_temp.wg_id('A_sess')),
    'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED');
END $$;

-- -----------------------------------------------------------------------------
-- ケース b4: 他人の割り当て（同じトレーナーの別の顧客 D・別のトレーナーの顧客 C2）は 0 行
-- -----------------------------------------------------------------------------
\echo '--- case b4: 顧客 C が他人の割り当てを更新すると 0 行であること'

DO $$
BEGIN
  PERFORM pg_temp.wg_expect_rows('b4 A_D.status（T の別の顧客）',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A_D')), 0);
  PERFORM pg_temp.wg_expect_rows('b4 A2.status（T2 の顧客）',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A2')), 0);
END $$;

-- -----------------------------------------------------------------------------
-- ケース b5: 顧客の INSERT / DELETE は権限で拒否（顧客には作成・削除の経路が無い）
-- -----------------------------------------------------------------------------
\echo '--- case b5: 顧客 C が割り当てを INSERT / DELETE できないこと (permission denied)'

DO $$
BEGIN
  PERFORM pg_temp.wg_expect_denied('b5 C の INSERT（自分宛て）',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date)
                VALUES (%L, %L, %L, current_date)$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('b5 C が自分の A を DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')),
    'workout_assignments');
END $$;

-- -----------------------------------------------------------------------------
-- ケース b6: プランの種別が読めないときは拒否（fail closed）
--   ガードは顧客の RLS の下で workout_plans.plan_type を引く。clients_read_assigned_plans を
--   外して読めなくすると、正規の Mobile の書き込みでも拒否されることを確かめる（SAVEPOINT で戻す）
-- -----------------------------------------------------------------------------
\echo '--- case b6: プランの種別が読めないと正規の書き込みも拒否されること (WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED)'

DO $$ BEGIN PERFORM pg_temp.wg_as('postgres'); END $$;
SAVEPOINT b6;
DROP POLICY "clients_read_assigned_plans" ON public.workout_plans;

DO $$
BEGIN
  PERFORM pg_temp.wg_as('C');
  PERFORM pg_temp.wg_expect_code('b6 プランが読めない A の Mobile のスキップ',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped', updated_at = now() WHERE id = %L$sql$,
           pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED');
  PERFORM pg_temp.wg_expect_code('b6 プランが読めない A の種目 X_ok の Mobile の完了',
    format($sql$UPDATE public.workout_assignment_exercises SET is_completed = true, completed_at = now() WHERE id = %L$sql$,
           pg_temp.wg_id('X_ok')),
    'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED');
  PERFORM pg_temp.wg_as('postgres');
END $$;

ROLLBACK TO SAVEPOINT b6;

-- =============================================================================
-- [section:C] 種目の禁止系（顧客 C）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース c1: 保護列は 1 列ずつ permission denied（UPDATE 列権限は actual_sets / is_completed /
--   completed_at だけ）
-- -----------------------------------------------------------------------------
\echo '--- case c1: 顧客 C が X の保護列を 1 列ずつ更新できないこと (permission denied)'

DO $$
DECLARE r record;
BEGIN
  PERFORM pg_temp.wg_as('C');
  FOR r IN
    SELECT * FROM (VALUES
      ('id',                 quote_literal(pg_temp.wg_id('Z'))),
      ('assignment_id',      quote_literal(pg_temp.wg_id('A_sess'))),
      ('exercise_name',      '''顧客が書き換えた種目'''),
      ('target_sets',        '1'),
      ('target_reps',        '1'),
      ('target_weight',      '999'),
      ('order_index',        '99'),
      ('memo',               '''顧客が消したメモ'''),
      ('linked_exercise_id', quote_literal(pg_temp.wg_id('X2'))),
      ('created_at',         '''-infinity''')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_denied(
      format('c1 workout_assignment_exercises.%s', r.col),
      format('UPDATE public.workout_assignment_exercises SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('X')),
      'workout_assignment_exercises');
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- ケース c2: セッション型の割り当ての種目は許可列でも
--   WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED
-- -----------------------------------------------------------------------------
\echo '--- case c2: 顧客 C がセッション型の種目 X_sess を更新できないこと (WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED)'

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('actual_sets',  $v$'[{"set_number":1,"reps":99,"weight":999,"done":true}]'::jsonb$v$),
      ('is_completed', 'true'),
      ('completed_at', 'now()')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_code(
      format('c2 セッション型 X_sess.%s', r.col),
      format('UPDATE public.workout_assignment_exercises SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('X_sess')),
      'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED');
  END LOOP;
  PERFORM pg_temp.wg_expect_code('c2 セッション型 X_sess に Mobile のセット実績の形',
    format($sql$UPDATE public.workout_assignment_exercises
                SET actual_sets = '[{"set_number":1,"reps":8,"weight":60.0,"done":true}]'::jsonb,
                    is_completed = true, completed_at = now()
                WHERE id = %L$sql$, pg_temp.wg_id('X_sess')),
    'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED');
END $$;

-- -----------------------------------------------------------------------------
-- ケース c3: 他人の種目は 0 行
-- -----------------------------------------------------------------------------
\echo '--- case c3: 顧客 C が他人の種目を更新すると 0 行であること'

DO $$
BEGIN
  PERFORM pg_temp.wg_expect_rows('c3 X_D.is_completed（T の別の顧客）',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X_D')), 0);
  PERFORM pg_temp.wg_expect_rows('c3 X2.is_completed（T2 の顧客）',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X2')), 0);
END $$;

-- -----------------------------------------------------------------------------
-- ケース c4: 顧客の種目の INSERT / DELETE は権限で拒否
-- -----------------------------------------------------------------------------
\echo '--- case c4: 顧客 C が種目を INSERT / DELETE できないこと (permission denied)'

DO $$
BEGIN
  PERFORM pg_temp.wg_expect_denied('c4 C が自分の A に種目を INSERT',
    format($sql$INSERT INTO public.workout_assignment_exercises (assignment_id, exercise_name)
                VALUES (%L, '顧客が足した種目')$sql$, pg_temp.wg_id('A')),
    'workout_assignment_exercises');
  PERFORM pg_temp.wg_expect_denied('c4 C が X を DELETE',
    format('DELETE FROM public.workout_assignment_exercises WHERE id = %L', pg_temp.wg_id('X')),
    'workout_assignment_exercises');
END $$;

-- =============================================================================
-- [section:D] トレーナーの直接の書き込み（authenticated）
--   Web の書き込みはすべて API Route の supabaseAdmin（service_role）。authenticated の
--   トレーナーには正規の書き込み経路が無い（ブラウザのクライアントは読むだけ）
-- =============================================================================
\echo '--- case d1〜d5: トレーナーが authenticated で割り当て・種目を書けないこと'

DO $$
BEGIN
  -- d1: 他トレーナーの顧客宛て（修正前はこれが通り、C のアプリに表示された）/ 自分の顧客宛て
  PERFORM pg_temp.wg_as('T2');
  PERFORM pg_temp.wg_expect_denied('d1 T2 が C（T の顧客）宛てに INSERT',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date, status)
                VALUES (%L, %L, %L, current_date, 'pending')$sql$,
           pg_temp.wg_id('T2'), pg_temp.wg_id('C'), pg_temp.wg_id('P2_self')),
    'workout_assignments');
  PERFORM pg_temp.wg_as('T');
  PERFORM pg_temp.wg_expect_denied('d1 T が自分の顧客 C 宛てに INSERT',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date, status)
                VALUES (%L, %L, %L, current_date, 'pending')$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'workout_assignments');

  -- d2: 自分の割り当てでも、顧客本人でなければ許可列も書けない（列権限は顧客と共通）
  PERFORM pg_temp.wg_expect_code('d2 T が自分の A の status',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENTS_NOT_CLIENT');
  PERFORM pg_temp.wg_expect_denied('d2 T が自分の A の trainer_note',
    format($sql$UPDATE public.workout_assignments SET trainer_note = 'x' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'workout_assignments');

  -- d3
  PERFORM pg_temp.wg_expect_denied('d3 T が A を DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')),
    'workout_assignments');

  -- d4: 種目
  PERFORM pg_temp.wg_expect_denied('d4 T が A に種目を INSERT',
    format($sql$INSERT INTO public.workout_assignment_exercises (assignment_id, exercise_name)
                VALUES (%L, 'T が足した種目')$sql$, pg_temp.wg_id('A')),
    'workout_assignment_exercises');
  PERFORM pg_temp.wg_expect_code('d4 T が X の is_completed',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X')),
    'WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT');
  PERFORM pg_temp.wg_expect_denied('d4 T が X の memo',
    format($sql$UPDATE public.workout_assignment_exercises SET memo = 'x' WHERE id = %L$sql$, pg_temp.wg_id('X')),
    'workout_assignment_exercises');
  PERFORM pg_temp.wg_expect_denied('d4 T が X を DELETE',
    format('DELETE FROM public.workout_assignment_exercises WHERE id = %L', pg_temp.wg_id('X')),
    'workout_assignment_exercises');

  -- d5: 自分の割り当てでない行は RLS で 0 行
  PERFORM pg_temp.wg_as('T2');
  PERFORM pg_temp.wg_expect_rows('d5 T2 が A の status（T の割り当て）',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')), 0);

  PERFORM pg_temp.wg_as('postgres');
END $$;

-- =============================================================================
-- [section:E] anon
--   顧客用の UPDATE / SELECT ポリシーは TO public なので、表の権限があれば顧客のクレームを
--   持った anon は顧客と同じに書けた（修正前に確認）。GRANT 層で閉じていることを、クレーム
--   なし・クレーム付きの両方で確かめる（トリガー層は H で単独に確かめる）
-- =============================================================================
\echo '--- case e1〜e3: anon が割り当て・種目を書けないこと (permission denied)'

DO $$
BEGIN
  -- e1: クレームなし
  PERFORM pg_temp.wg_as('anon');
  PERFORM pg_temp.wg_expect_denied('e1 anon A.status',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('e1 anon INSERT',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date)
                VALUES (%L, %L, %L, current_date)$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('e1 anon A の DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('e1 anon X.is_completed',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X')),
    'workout_assignment_exercises');
  PERFORM pg_temp.wg_expect_denied('e1 anon 種目の INSERT',
    format($sql$INSERT INTO public.workout_assignment_exercises (assignment_id, exercise_name) VALUES (%L, 'anon')$sql$,
           pg_temp.wg_id('A')),
    'workout_assignment_exercises');
  PERFORM pg_temp.wg_expect_denied('e1 anon X の DELETE',
    format('DELETE FROM public.workout_assignment_exercises WHERE id = %L', pg_temp.wg_id('X')),
    'workout_assignment_exercises');

  -- e2: 顧客 C のクレームを持った anon
  PERFORM pg_temp.wg_as('anon:C');
  PERFORM pg_temp.wg_expect_denied('e2 anon(クレーム=C) A.status',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('e2 anon(クレーム=C) A.trainer_id',
    format('UPDATE public.workout_assignments SET trainer_id = %L WHERE id = %L', pg_temp.wg_id('T2'), pg_temp.wg_id('A')),
    'workout_assignments');
  PERFORM pg_temp.wg_expect_denied('e2 anon(クレーム=C) X.is_completed',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X')),
    'workout_assignment_exercises');

  -- e3: トレーナー T のクレームを持った anon
  PERFORM pg_temp.wg_as('anon:T');
  PERFORM pg_temp.wg_expect_denied('e3 anon(クレーム=T) INSERT',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date)
                VALUES (%L, %L, %L, current_date)$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'workout_assignments');

  PERFORM pg_temp.wg_as('postgres');
END $$;

-- =============================================================================
-- [section:F] 拒否後の不変
-- =============================================================================
\echo '--- case f1: B〜E の拒否のあと、試験用の全行が変わっていないこと'

DO $$ BEGIN PERFORM pg_temp.wg_as('postgres'); END $$;
DO $$ BEGIN PERFORM pg_temp.wg_assert_unchanged('f1 B〜E のあと'); END $$;

-- =============================================================================
-- [section:H] トリガー層だけ（表の権限を一時的に戻す）
--   本番の構成では GRANT 層（列権限・INSERT / DELETE の剥奪）が先に拒否するので、トリガー
--   まで届かない。将来 GRANT ALL（Supabase の既定権限・migration の書き方）で表の権限が
--   戻っても閉じていることを確かめるため、SAVEPOINT の中でだけ anon / authenticated に
--   両表の INSERT / UPDATE / DELETE を戻す（ROLLBACK TO SAVEPOINT で元の権限に戻す）
-- =============================================================================
\echo '--- setup H: anon / authenticated に両表の INSERT / UPDATE / DELETE を一時的に戻す'

DO $$ BEGIN PERFORM pg_temp.wg_as('postgres'); END $$;
SAVEPOINT h;
GRANT INSERT, UPDATE, DELETE ON public.workout_assignments, public.workout_assignment_exercises
  TO anon, authenticated;

DO $$
BEGIN
  IF NOT (has_table_privilege('authenticated', 'public.workout_assignments', 'UPDATE')
          AND has_table_privilege('authenticated', 'public.workout_assignment_exercises', 'INSERT')
          AND has_table_privilege('anon', 'public.workout_assignments', 'UPDATE')
          AND has_table_privilege('anon', 'public.workout_assignments', 'DELETE')) THEN
    RAISE EXCEPTION 'FAIL: setup H 前提崩れ — 一時的な GRANT が効いていない';
  END IF;
END $$;

\echo '--- case h1〜h3: 顧客 C の保護列・セッション型はトリガーで拒否されること'

DO $$
DECLARE r record;
BEGIN
  PERFORM pg_temp.wg_as('C');

  -- h1: 割り当ての保護列（client_id を他人にする変更も、RLS の WITH CHECK より先にトリガーが拒否する）
  FOR r IN
    SELECT * FROM (VALUES
      ('id',           quote_literal(pg_temp.wg_id('Z'))),
      ('trainer_id',   quote_literal(pg_temp.wg_id('T2'))),
      ('client_id',    quote_literal(pg_temp.wg_id('D'))),
      ('plan_id',      quote_literal(pg_temp.wg_id('P2_self'))),
      ('created_at',   '''-infinity'''),
      ('session_id',   quote_literal(pg_temp.wg_id('S2'))),
      ('trainer_note', '''顧客が書き換えたメモ'''),
      ('started_at',   '''2000-01-01 00:00:00+00''')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_code(
      format('h1 workout_assignments.%s', r.col),
      format('UPDATE public.workout_assignments SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('A')),
      'WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE');
  END LOOP;
  PERFORM pg_temp.wg_expect_code('h1 許可列（status）と保護列（trainer_id）を同時に',
    format($sql$UPDATE public.workout_assignments SET status = 'completed', trainer_id = %L WHERE id = %L$sql$,
           pg_temp.wg_id('T2'), pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE');

  -- h2: 種目の保護列（assignment_id を自分の別の割り当てへ移す変更を含む）
  FOR r IN
    SELECT * FROM (VALUES
      ('id',                 quote_literal(pg_temp.wg_id('Z'))),
      ('assignment_id',      quote_literal(pg_temp.wg_id('A_sess'))),
      ('exercise_name',      '''顧客が書き換えた種目'''),
      ('target_sets',        '1'),
      ('target_reps',        '1'),
      ('target_weight',      '999'),
      ('order_index',        '99'),
      ('memo',               '''顧客が消したメモ'''),
      ('linked_exercise_id', quote_literal(pg_temp.wg_id('X2'))),
      ('created_at',         '''-infinity''')
    ) AS v(col, val)
  LOOP
    PERFORM pg_temp.wg_expect_code(
      format('h2 workout_assignment_exercises.%s', r.col),
      format('UPDATE public.workout_assignment_exercises SET %I = %s WHERE id = %L', r.col, r.val, pg_temp.wg_id('X')),
      'WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE');
  END LOOP;

  -- h3: セッション型（保護列でも、種別の判定が先）
  PERFORM pg_temp.wg_expect_code('h3 セッション型 A_sess.trainer_note',
    format($sql$UPDATE public.workout_assignments SET trainer_note = 'x' WHERE id = %L$sql$, pg_temp.wg_id('A_sess')),
    'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED');
  PERFORM pg_temp.wg_expect_code('h3 セッション型 X_sess.memo',
    format($sql$UPDATE public.workout_assignment_exercises SET memo = 'x' WHERE id = %L$sql$, pg_temp.wg_id('X_sess')),
    'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED');
END $$;

\echo '--- case h4: 顧客 C の INSERT はトリガーで拒否、DELETE は RLS で 0 行であること'

DO $$
BEGIN
  PERFORM pg_temp.wg_as('C');
  PERFORM pg_temp.wg_expect_code('h4 C の割り当ての INSERT',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date)
                VALUES (%L, %L, %L, current_date)$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_code('h4 C の種目の INSERT',
    format($sql$INSERT INTO public.workout_assignment_exercises (assignment_id, exercise_name) VALUES (%L, 'x')$sql$,
           pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_rows('h4 C が自分の A を DELETE（顧客の DELETE ポリシーが無い）',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')), 0);
END $$;

\echo '--- case h5/h6: トレーナーの INSERT / DELETE / 顧客本人でない UPDATE がトリガーで拒否されること'

DO $$
BEGIN
  -- h5: 割り当て
  PERFORM pg_temp.wg_as('T2');
  PERFORM pg_temp.wg_expect_code('h5 T2 が C（T の顧客）宛てに INSERT',
    format($sql$INSERT INTO public.workout_assignments (id, trainer_id, client_id, plan_id, assigned_date, status)
                VALUES (%L, %L, %L, %L, current_date, 'pending')$sql$,
           pg_temp.wg_id('A_new'), pg_temp.wg_id('T2'), pg_temp.wg_id('C'), pg_temp.wg_id('P2_self')),
    'WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_as('T');
  PERFORM pg_temp.wg_expect_code('h5 T が A を DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_code('h5 T が A の trainer_note',
    format($sql$UPDATE public.workout_assignments SET trainer_note = 'x' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENTS_NOT_CLIENT');

  -- h6: 種目
  PERFORM pg_temp.wg_expect_code('h6 T が A に種目を INSERT',
    format($sql$INSERT INTO public.workout_assignment_exercises (id, assignment_id, exercise_name) VALUES (%L, %L, 'x')$sql$,
           pg_temp.wg_id('X_new'), pg_temp.wg_id('A')),
    'WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_code('h6 T が X を DELETE',
    format('DELETE FROM public.workout_assignment_exercises WHERE id = %L', pg_temp.wg_id('X')),
    'WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_code('h6 T が X の memo',
    format($sql$UPDATE public.workout_assignment_exercises SET memo = 'x' WHERE id = %L$sql$, pg_temp.wg_id('X')),
    'WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT');
END $$;

\echo '--- case h7/h8: anon の書き込みがトリガー（ANON_WRITE_FORBIDDEN）か RLS（0 行）で止まること'

DO $$
BEGIN
  -- h7: 顧客用ポリシーは TO public なので、表の権限があると行がトリガーまで届く
  PERFORM pg_temp.wg_as('anon:C');
  PERFORM pg_temp.wg_expect_code('h7 anon(クレーム=C) A.status',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')),
    'ANON_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_expect_code('h7 anon(クレーム=C) X.is_completed',
    format('UPDATE public.workout_assignment_exercises SET is_completed = true WHERE id = %L', pg_temp.wg_id('X')),
    'ANON_WRITE_FORBIDDEN');
  PERFORM pg_temp.wg_as('anon:T');
  PERFORM pg_temp.wg_expect_code('h7 anon(クレーム=T) INSERT（BEFORE トリガーは WITH CHECK より先）',
    format($sql$INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date)
                VALUES (%L, %L, %L, current_date)$sql$,
           pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self')),
    'ANON_WRITE_FORBIDDEN');

  -- h8: クレームなし（auth.uid() が NULL）・DELETE ポリシーの無い anon は RLS で 0 行
  PERFORM pg_temp.wg_as('anon');
  PERFORM pg_temp.wg_expect_rows('h8 anon（クレームなし）A.status',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped' WHERE id = %L$sql$, pg_temp.wg_id('A')), 0);
  PERFORM pg_temp.wg_as('anon:C');
  PERFORM pg_temp.wg_expect_rows('h8 anon(クレーム=C) A の DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', pg_temp.wg_id('A')), 0);

  PERFORM pg_temp.wg_as('postgres');
END $$;

\echo '--- case h9: H のあと行が変わっておらず、SAVEPOINT で戻すと権限が元に戻ること'

DO $$ BEGIN PERFORM pg_temp.wg_as('postgres'); END $$;
DO $$ BEGIN PERFORM pg_temp.wg_assert_unchanged('h9 H のあと'); END $$;
ROLLBACK TO SAVEPOINT h;

DO $$
BEGIN
  IF has_table_privilege('authenticated', 'public.workout_assignments', 'UPDATE')
     OR has_any_column_privilege('authenticated', 'public.workout_assignment_exercises', 'INSERT')
     OR has_any_column_privilege('anon', 'public.workout_assignments', 'UPDATE')
     OR has_table_privilege('anon', 'public.workout_assignments', 'DELETE') THEN
    RAISE EXCEPTION 'FAIL: h9 SAVEPOINT で戻した後も一時的な GRANT が残っている';
  END IF;
  RAISE NOTICE 'OK: h9 一時的な GRANT は元に戻った';
END $$;

-- =============================================================================
-- [section:I] 正規経路（回帰確認）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ケース i1〜i6: Mobile（fit-connect-mobile/lib/features/workout/data/workout_repository.dart）
--   の 5 つの書き込みを、送る列の組そのままで行う（すべて .update(map).eq('id', ...)）。
--   時刻は DateTime.now().toUtc().toIso8601String() の形（UTC・マイクロ秒・Z）
-- -----------------------------------------------------------------------------
\echo '--- case i1〜i6: Mobile の 5 つの書き込みが成功し、完了が記録の連続に数えられること'

DO $$
DECLARE
  v_ts      text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  v_today   date := (now() AT TIME ZONE 'Asia/Tokyo')::date;
  v_x       public.workout_assignment_exercises%ROWTYPE;
  v_a       public.workout_assignments%ROWTYPE;
  v_rec     boolean;
BEGIN
  PERFORM pg_temp.wg_as('C');

  -- i6 の前提: C はまだ今日の記録が無い
  SELECT s.recorded_today INTO v_rec FROM public.get_record_streak(pg_temp.wg_id('C')) s;
  IF v_rec IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL: i6 前提崩れ — 完了の前に recorded_today = %（期待 false）', v_rec;
  END IF;

  -- i1 toggleExerciseCompletion: {is_completed, completed_at}（完了 → 戻す）
  PERFORM pg_temp.wg_expect_rows('i1 toggleExerciseCompletion（完了）',
    format($sql$UPDATE public.workout_assignment_exercises SET is_completed = true, completed_at = %L WHERE id = %L$sql$,
           v_ts, pg_temp.wg_id('X_ok')), 1);
  SELECT * INTO v_x FROM public.workout_assignment_exercises WHERE id = pg_temp.wg_id('X_ok');
  IF v_x.is_completed IS DISTINCT FROM true OR v_x.completed_at IS DISTINCT FROM v_ts::timestamptz THEN
    RAISE EXCEPTION 'FAIL: i1 保存された値が違う: %', to_jsonb(v_x);
  END IF;
  PERFORM pg_temp.wg_expect_rows('i1 toggleExerciseCompletion（戻す）',
    format($sql$UPDATE public.workout_assignment_exercises SET is_completed = false, completed_at = NULL WHERE id = %L$sql$,
           pg_temp.wg_id('X_ok')), 1);
  SELECT * INTO v_x FROM public.workout_assignment_exercises WHERE id = pg_temp.wg_id('X_ok');
  IF v_x.is_completed IS DISTINCT FROM false OR v_x.completed_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: i1 戻した値が違う: %', to_jsonb(v_x);
  END IF;

  -- i2 updateActualSets: {actual_sets, is_completed, completed_at}（途中 → 全セット完了）
  PERFORM pg_temp.wg_expect_rows('i2 updateActualSets（途中）',
    format($sql$UPDATE public.workout_assignment_exercises
                SET actual_sets = '[{"set_number":1,"reps":10,"weight":20.0,"done":true},{"set_number":2,"reps":10,"weight":20.0,"done":false}]'::jsonb,
                    is_completed = false, completed_at = NULL
                WHERE id = %L$sql$, pg_temp.wg_id('X_ok2')), 1);
  PERFORM pg_temp.wg_expect_rows('i2 updateActualSets（全セット完了）',
    format($sql$UPDATE public.workout_assignment_exercises
                SET actual_sets = '[{"set_number":1,"reps":10,"weight":20.0,"done":true},{"set_number":2,"reps":8,"weight":22.5,"done":true}]'::jsonb,
                    is_completed = true, completed_at = %L
                WHERE id = %L$sql$, v_ts, pg_temp.wg_id('X_ok2')), 1);
  SELECT * INTO v_x FROM public.workout_assignment_exercises WHERE id = pg_temp.wg_id('X_ok2');
  IF v_x.actual_sets IS DISTINCT FROM '[{"set_number":1,"reps":10,"weight":20.0,"done":true},{"set_number":2,"reps":8,"weight":22.5,"done":true}]'::jsonb
     OR v_x.is_completed IS DISTINCT FROM true OR v_x.completed_at IS DISTINCT FROM v_ts::timestamptz
     OR v_x.exercise_name IS DISTINCT FROM 'ショルダープレス' OR v_x.target_weight IS DISTINCT FROM 20::numeric THEN
    RAISE EXCEPTION 'FAIL: i2 保存された値が違う: %', to_jsonb(v_x);
  END IF;

  -- i3 completeAssignment: {status, finished_at, client_feedback, calories} / 感想・カロリー無し
  PERFORM pg_temp.wg_expect_rows('i3 completeAssignment（感想・カロリーあり）',
    format($sql$UPDATE public.workout_assignments
                SET status = 'completed', finished_at = %L, client_feedback = 'きつかったが完走', calories = 320
                WHERE id = %L$sql$, v_ts, pg_temp.wg_id('A_c')), 1);
  SELECT * INTO v_a FROM public.workout_assignments WHERE id = pg_temp.wg_id('A_c');
  IF v_a.status IS DISTINCT FROM 'completed' OR v_a.finished_at IS DISTINCT FROM v_ts::timestamptz
     OR v_a.client_feedback IS DISTINCT FROM 'きつかったが完走' OR v_a.calories IS DISTINCT FROM 320::numeric
     OR v_a.trainer_note IS DISTINCT FROM '完了の前のメモ' OR v_a.started_at IS NOT NULL OR v_a.session_id IS NOT NULL
     OR v_a.trainer_id IS DISTINCT FROM pg_temp.wg_id('T') OR v_a.plan_id IS DISTINCT FROM pg_temp.wg_id('P_self')
     OR v_a.created_at IS DISTINCT FROM '2026-01-15 00:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'FAIL: i3 保存された値が違う: %', to_jsonb(v_a);
  END IF;
  PERFORM pg_temp.wg_expect_rows('i3 completeAssignment（感想・カロリー無し）',
    format($sql$UPDATE public.workout_assignments SET status = 'completed', finished_at = %L WHERE id = %L$sql$,
           v_ts, pg_temp.wg_id('A_c2')), 1);

  -- i4 skipAssignment: {status: skipped, updated_at}
  PERFORM pg_temp.wg_expect_rows('i4 skipAssignment',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped', updated_at = %L WHERE id = %L$sql$,
           v_ts, pg_temp.wg_id('A_s')), 1);
  SELECT * INTO v_a FROM public.workout_assignments WHERE id = pg_temp.wg_id('A_s');
  IF v_a.status IS DISTINCT FROM 'skipped' OR v_a.updated_at IS DISTINCT FROM v_ts::timestamptz THEN
    RAISE EXCEPTION 'FAIL: i4 保存された値が違う: %', to_jsonb(v_a);
  END IF;

  -- i5 rescheduleAssignment: {assigned_date, status: pending, updated_at}（skipped → pending）/ 旧版の形
  PERFORM pg_temp.wg_expect_rows('i5 rescheduleAssignment（skipped → pending）',
    format($sql$UPDATE public.workout_assignments SET assigned_date = %L, status = 'pending', updated_at = %L WHERE id = %L$sql$,
           to_char(v_today + 2, 'YYYY-MM-DD'), v_ts, pg_temp.wg_id('A_r')), 1);
  SELECT * INTO v_a FROM public.workout_assignments WHERE id = pg_temp.wg_id('A_r');
  IF v_a.status IS DISTINCT FROM 'pending' OR v_a.assigned_date IS DISTINCT FROM v_today + 2 THEN
    RAISE EXCEPTION 'FAIL: i5 保存された値が違う: %', to_jsonb(v_a);
  END IF;
  PERFORM pg_temp.wg_expect_rows('i5 rescheduleAssignment（旧版: status なし）',
    format($sql$UPDATE public.workout_assignments SET assigned_date = %L, updated_at = %L WHERE id = %L$sql$,
           to_char(v_today + 3, 'YYYY-MM-DD'), v_ts, pg_temp.wg_id('A_r2')), 1);

  -- i6 C の完了（A_c・A_c2。finished_at = 今）が今日の記録として数えられる
  SELECT s.recorded_today INTO v_rec FROM public.get_record_streak(pg_temp.wg_id('C')) s;
  IF v_rec IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: i6 C の完了が get_record_streak に数えられない（recorded_today = %）', v_rec;
  END IF;
  RAISE NOTICE 'OK: [i6] C の完了が get_record_streak の今日の記録に数えられる';

  PERFORM pg_temp.wg_as('postgres');
END $$;

-- -----------------------------------------------------------------------------
-- ケース i7〜i10: service_role（Web の API Route の supabaseAdmin・Edge Functions）
-- -----------------------------------------------------------------------------
\echo '--- case i7〜i10: service_role の Web / auto-skip の書き込みが成功すること'

DO $$
DECLARE
  v_ts       text := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
  v_today    date := (now() AT TIME ZONE 'Asia/Tokyo')::date;
  v_new_id   uuid;
  v_sess_id  uuid;
  v_n        bigint;
  v_a        public.workout_assignments%ROWTYPE;
  v_x        public.workout_assignment_exercises%ROWTYPE;
  v_ids      uuid[];
BEGIN
  PERFORM pg_temp.wg_as('service_role');

  -- i7 Web の POST /api/workout-assignments: 割り当ての INSERT（.insert([...]).select().single()）
  INSERT INTO public.workout_assignments (trainer_id, client_id, plan_id, assigned_date, status, session_id)
  VALUES (pg_temp.wg_id('T'), pg_temp.wg_id('C'), pg_temp.wg_id('P_self'), v_today + 1, 'pending', NULL)
  RETURNING id INTO v_new_id;
  IF v_new_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: i7 割り当ての INSERT が行を返さない';
  END IF;
  -- テンプレートの種目のコピー（.insert(rows)）
  INSERT INTO public.workout_assignment_exercises
    (assignment_id, exercise_name, target_sets, target_reps, target_weight, order_index,
     actual_sets, is_completed, memo, linked_exercise_id)
  SELECT v_new_id, we.name, we.sets, coalesce(we.reps, 0), we.weight, we.order_index, NULL, false, NULL, NULL
    FROM public.workout_exercises we
   WHERE we.plan_id = pg_temp.wg_id('P_self')
   ORDER BY we.order_index;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'FAIL: i7 種目のコピーが % 行（期待 2）', v_n;
  END IF;
  -- createSession = true: セッションを作って session_id を紐付ける（.update({session_id}).eq('id')）
  INSERT INTO public.sessions (trainer_id, client_id, session_date, duration_minutes, status)
  VALUES (pg_temp.wg_id('T'), pg_temp.wg_id('C'), now() + interval '1 day', 60, 'scheduled')
  RETURNING id INTO v_sess_id;
  PERFORM pg_temp.wg_expect_rows('i7 Web の POST: session_id の UPDATE',
    format('UPDATE public.workout_assignments SET session_id = %L WHERE id = %L', v_sess_id, v_new_id), 1);
  RAISE NOTICE 'OK: [i7] Web の POST（割り当ての INSERT・種目のコピー 2 行・session_id の UPDATE）';

  -- i8 Web の PATCH /api/workout-assignments/[id]（全列）
  PERFORM pg_temp.wg_expect_rows('i8 Web の PATCH（割り当ての全列）',
    format($sql$UPDATE public.workout_assignments
                SET updated_at = %L, assigned_date = %L, status = 'partial', trainer_note = 'トレーナーのメモ',
                    client_feedback = 'トレーナーが聞き取った感想', started_at = %L, finished_at = %L
                WHERE id = %L$sql$,
           v_ts, to_char(v_today + 4, 'YYYY-MM-DD'), v_ts, v_ts, pg_temp.wg_id('A')), 1);
  SELECT * INTO v_a FROM public.workout_assignments WHERE id = pg_temp.wg_id('A');
  IF v_a.status IS DISTINCT FROM 'partial' OR v_a.trainer_note IS DISTINCT FROM 'トレーナーのメモ'
     OR v_a.started_at IS DISTINCT FROM v_ts::timestamptz OR v_a.assigned_date IS DISTINCT FROM v_today + 4 THEN
    RAISE EXCEPTION 'FAIL: i8 保存された値が違う: %', to_jsonb(v_a);
  END IF;
  -- PATCH /api/workout-assignment-exercises/[id]（actual_sets / is_completed / memo）
  PERFORM pg_temp.wg_expect_rows('i8 Web の PATCH（種目: actual_sets / is_completed / memo）',
    format($sql$UPDATE public.workout_assignment_exercises
                SET actual_sets = '[{"set_number":1,"reps":10,"weight":40,"done":true}]'::jsonb,
                    is_completed = true, memo = 'トレーナーが書いたメモ'
                WHERE id = %L$sql$, pg_temp.wg_id('X')), 1);
  SELECT * INTO v_x FROM public.workout_assignment_exercises WHERE id = pg_temp.wg_id('X');
  IF v_x.memo IS DISTINCT FROM 'トレーナーが書いたメモ' OR v_x.is_completed IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'FAIL: i8 種目の保存された値が違う: %', to_jsonb(v_x);
  END IF;
  -- セッション型の結果もトレーナー（service_role）は記録できる
  PERFORM pg_temp.wg_expect_rows('i8 Web の PATCH（セッション型の種目）',
    format($sql$UPDATE public.workout_assignment_exercises
                SET actual_sets = '[{"set_number":1,"reps":8,"weight":60,"done":true}]'::jsonb, is_completed = true
                WHERE id = %L$sql$, pg_temp.wg_id('X_sess')), 1);
  PERFORM pg_temp.wg_expect_rows('i8 Web の PATCH（セッション型の割り当て）',
    format($sql$UPDATE public.workout_assignments SET updated_at = %L, status = 'completed', finished_at = %L WHERE id = %L$sql$,
           v_ts, v_ts, pg_temp.wg_id('A_sess')), 1);

  -- i9 auto-skip-workouts: 候補の抽出（self_guided・pending・予定日が 3 日より前）→ 条件付き UPDATE
  SELECT array_agg(a.id ORDER BY a.id) INTO v_ids
    FROM public.workout_assignments a
    JOIN public.workout_plans p ON p.id = a.plan_id
   WHERE p.plan_type = 'self_guided' AND a.status = 'pending' AND a.assigned_date < v_today - 3
     AND a.id::text LIKE 'a55e1123-0000-4000-8000-%';
  IF v_ids IS DISTINCT FROM ARRAY[pg_temp.wg_id('A_old')] THEN
    RAISE EXCEPTION 'FAIL: i9 auto-skip の候補が %（期待 A_old だけ）', v_ids;
  END IF;
  PERFORM pg_temp.wg_expect_rows('i9 auto-skip の条件付き UPDATE',
    format($sql$UPDATE public.workout_assignments SET status = 'skipped', updated_at = %L
                WHERE id = ANY (%L::uuid[]) AND status = 'pending' AND assigned_date < %L$sql$,
           v_ts, v_ids, to_char(v_today - 3, 'YYYY-MM-DD')), 1);

  -- i10 Web の DELETE /api/workout-assignments/[id]（種目は CASCADE）
  PERFORM pg_temp.wg_expect_rows('i10 Web の DELETE',
    format('DELETE FROM public.workout_assignments WHERE id = %L', v_new_id), 1);
  SELECT count(*) INTO v_n FROM public.workout_assignment_exercises WHERE assignment_id = v_new_id;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: i10 削除した割り当ての種目が % 行残っている', v_n;
  END IF;
  RAISE NOTICE 'OK: [i10] 種目も CASCADE で消えた';

  PERFORM pg_temp.wg_as('postgres');
END $$;

-- =============================================================================
-- [section:J] FK の参照動作
--   参照動作（ON DELETE SET NULL / CASCADE）の UPDATE / DELETE は、削除した人のロールではなく
--   参照側の表の所有者（postgres）として実行されるので、ガードは current_user = postgres で
--   素通しにする。Web の deleteSession.ts はブラウザのクライアント（authenticated のトレーナー）で
--   sessions を DELETE するので、ここが止まると Web のセッション削除が壊れる
-- =============================================================================
\echo '--- case j1〜j3: FK の参照動作がガードに止められないこと'

DO $$
DECLARE
  v_n bigint;
  v_session uuid;
BEGIN
  -- j1 authenticated の T がセッション S3 を DELETE → A_link.session_id が NULL
  PERFORM pg_temp.wg_as('T');
  PERFORM pg_temp.wg_expect_rows('j1 T が authenticated でセッション S3 を DELETE（deleteSession.ts の形）',
    format('DELETE FROM public.sessions WHERE id = %L', pg_temp.wg_id('S3')), 1);
  PERFORM pg_temp.wg_as('postgres');
  SELECT a.session_id INTO v_session FROM public.workout_assignments a WHERE a.id = pg_temp.wg_id('A_link');
  IF NOT FOUND OR v_session IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: j1 A_link が無い、または session_id が NULL になっていない（%）', v_session;
  END IF;
  RAISE NOTICE 'OK: [j1] A_link.session_id は NULL（ON DELETE SET NULL）';

  -- j2a service_role がプラン P_del を DELETE（Web の DELETE /api/workout-plans/[id]）
  PERFORM pg_temp.wg_as('service_role');
  PERFORM pg_temp.wg_expect_rows('j2a service_role がプラン P_del を DELETE',
    format('DELETE FROM public.workout_plans WHERE id = %L', pg_temp.wg_id('P_del')), 1);
  -- j2b authenticated の T が自分のプラン P_del2 を DELETE（ポリシー上は可能）
  PERFORM pg_temp.wg_as('T');
  PERFORM pg_temp.wg_expect_rows('j2b T が authenticated でプラン P_del2 を DELETE',
    format('DELETE FROM public.workout_plans WHERE id = %L', pg_temp.wg_id('P_del2')), 1);
  -- j3 service_role が顧客 E を DELETE（delete-account）
  PERFORM pg_temp.wg_as('service_role');
  PERFORM pg_temp.wg_expect_rows('j3 service_role が顧客 E を DELETE',
    format('DELETE FROM public.clients WHERE client_id = %L', pg_temp.wg_id('E')), 1);

  PERFORM pg_temp.wg_as('postgres');
  SELECT count(*) INTO v_n FROM public.workout_assignments
   WHERE id IN (pg_temp.wg_id('A_pd'), pg_temp.wg_id('A_pd2'), pg_temp.wg_id('A_E'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: j2/j3 CASCADE で消えるはずの割り当てが % 行残っている', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.workout_assignment_exercises
   WHERE id IN (pg_temp.wg_id('X_pd'), pg_temp.wg_id('X_pd2'), pg_temp.wg_id('X_E'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'FAIL: j2/j3 CASCADE で消えるはずの種目が % 行残っている', v_n;
  END IF;
  RAISE NOTICE 'OK: [j2/j3] プラン・顧客の削除で割り当てと種目が CASCADE で消えた';
END $$;

-- =============================================================================
-- [section:G] カタログ確認（postgres）
-- =============================================================================
\echo '--- case g1/g2: ガードトリガー 2 本とガード関数の定義が設計どおりであること'

DO $$ BEGIN PERFORM pg_temp.wg_as('postgres'); END $$;

DO $$
DECLARE
  e record;
  r record;
  v_role text;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      ('public.workout_assignments',          'workout_assignments_guard_write',
       'public.workout_assignments_guard_write()'),
      ('public.workout_assignment_exercises', 'workout_assignment_exercises_guard_write',
       'public.workout_assignment_exercises_guard_write()')
    ) AS v(tbl, tgname, fn)
  LOOP
    SELECT t.tgenabled, t.tgtype::int AS tgtype,
           coalesce(array_length(t.tgattr::int2[], 1), 0) AS n_attr,
           p.oid AS fn_oid, p.oid::regprocedure::text AS fn_name,
           p.prosecdef, p.proconfig, p.proacl
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
    -- tgtype: 1 = ROW, 2 = BEFORE, 4 = INSERT, 8 = DELETE, 16 = UPDATE
    IF (r.tgtype & 1) = 0 OR (r.tgtype & 2) = 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が BEFORE ROW でない (tgtype=%)', e.tgname, r.tgtype;
    END IF;
    IF (r.tgtype & 4) = 0 OR (r.tgtype & 8) = 0 OR (r.tgtype & 16) = 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が INSERT / UPDATE / DELETE のすべてで発火しない (tgtype=%)', e.tgname, r.tgtype;
    END IF;
    IF r.n_attr <> 0 THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % に UPDATE OF の列指定がある（指定外の列が保護されない）', e.tgname;
    END IF;
    IF r.fn_oid IS DISTINCT FROM e.fn::regprocedure::oid THEN
      RAISE EXCEPTION 'FAIL: g1 トリガー % が % を呼ぶ（期待 %）', e.tgname, r.fn_name, e.fn;
    END IF;
    IF r.prosecdef THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % が SECURITY DEFINER（current_user が所有者になり判定不能）', r.fn_name;
    END IF;
    IF NOT coalesce('search_path=""' = ANY (r.proconfig), false) THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % に SET search_path = '''' が無い (proconfig=%)', r.fn_name, r.proconfig;
    END IF;
    -- proacl が NULL は既定権限 = PUBLIC に EXECUTE。grantee = 0 は PUBLIC
    IF r.proacl IS NULL OR EXISTS (SELECT 1 FROM aclexplode(r.proacl) a WHERE a.grantee = 0) THEN
      RAISE EXCEPTION 'FAIL: g2 ガード関数 % の EXECUTE が PUBLIC に付いている (proacl=%)', r.fn_name, r.proacl;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
      IF has_function_privilege(v_role, r.fn_oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'FAIL: g2 ガード関数 % の EXECUTE が % に残っている', r.fn_name, v_role;
      END IF;
    END LOOP;
    RAISE NOTICE 'OK: g1/g2 % on % → % （BEFORE ROW・INSERT/UPDATE/DELETE・列指定なし・INVOKER・search_path=""・EXECUTE は所有者のみ）',
      e.tgname, e.tbl, r.fn_name;
  END LOOP;
END $$;

\echo '--- case g3〜g5: anon / authenticated / service_role の表・列の権限が設計どおりであること'

DO $$
DECLARE
  e     record;
  r     record;
  v_bad text[] := '{}';
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      ('public.workout_assignments',
       ARRAY['status', 'assigned_date', 'finished_at', 'client_feedback', 'calories', 'updated_at']),
      ('public.workout_assignment_exercises',
       ARRAY['actual_sets', 'is_completed', 'completed_at'])
    ) AS v(tbl, upd)
  LOOP
    -- g3 anon: 書き込み権限なし（列単位を含む）
    IF has_any_column_privilege('anon', e.tbl, 'INSERT') THEN
      v_bad := v_bad || format('anon INSERT on %s', e.tbl);
    END IF;
    IF has_any_column_privilege('anon', e.tbl, 'UPDATE') THEN
      v_bad := v_bad || format('anon UPDATE on %s', e.tbl);
    END IF;
    IF has_table_privilege('anon', e.tbl, 'DELETE') THEN
      v_bad := v_bad || format('anon DELETE on %s', e.tbl);
    END IF;

    -- g4 authenticated: INSERT・DELETE・表単位の UPDATE なし、UPDATE の列権限 = 許可リスト、SELECT あり
    IF has_any_column_privilege('authenticated', e.tbl, 'INSERT') THEN
      v_bad := v_bad || format('authenticated INSERT on %s', e.tbl);
    END IF;
    IF has_table_privilege('authenticated', e.tbl, 'DELETE') THEN
      v_bad := v_bad || format('authenticated DELETE on %s', e.tbl);
    END IF;
    IF has_table_privilege('authenticated', e.tbl, 'UPDATE') THEN
      v_bad := v_bad || format('authenticated のテーブル単位の UPDATE on %s', e.tbl);
    END IF;
    IF NOT has_table_privilege('authenticated', e.tbl, 'SELECT') THEN
      v_bad := v_bad || format('authenticated の SELECT が無い on %s', e.tbl);
    END IF;
    FOR r IN
      SELECT a.attname::text AS col
        FROM pg_attribute a
       WHERE a.attrelid = e.tbl::regclass AND a.attnum > 0 AND NOT a.attisdropped
       ORDER BY a.attnum
    LOOP
      IF has_column_privilege('authenticated', e.tbl, r.col, 'UPDATE') IS DISTINCT FROM (r.col = ANY (e.upd)) THEN
        v_bad := v_bad || format('authenticated UPDATE(%s.%s)=%s（期待 %s）', e.tbl, r.col,
          has_column_privilege('authenticated', e.tbl, r.col, 'UPDATE'), r.col = ANY (e.upd));
      END IF;
    END LOOP;

    -- g5 service_role: 剥がしていない
    IF NOT (has_table_privilege('service_role', e.tbl, 'SELECT')
            AND has_table_privilege('service_role', e.tbl, 'INSERT')
            AND has_table_privilege('service_role', e.tbl, 'UPDATE')
            AND has_table_privilege('service_role', e.tbl, 'DELETE')) THEN
      v_bad := v_bad || format('service_role の SELECT / INSERT / UPDATE / DELETE が欠けている on %s', e.tbl);
    END IF;
  END LOOP;

  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'FAIL: g3〜g5 権限が設計と異なる: %', array_to_string(v_bad, ' / ');
  END IF;
  RAISE NOTICE 'OK: g3〜g5 anon は書き込み権限なし / authenticated は UPDATE の列権限が許可リストと完全一致（INSERT・DELETE なし、SELECT あり）/ service_role は維持';
END $$;

-- -----------------------------------------------------------------------------
-- ケース g6: authenticator（PostgREST の接続ロール）が SET ROLE できるロール
--   ガードは current_user が anon / authenticated 以外なら素通しにする（service_role と
--   FK の参照動作・SECURITY DEFINER 関数を通すため）。authenticator の所属が増えると、
--   その新しいロールのリクエストはガードを素通りする（column_write_guards_test の g6 と同じ）
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
\echo 'ALL WORKOUT ASSIGNMENT WRITE GUARDS TESTS PASSED'
