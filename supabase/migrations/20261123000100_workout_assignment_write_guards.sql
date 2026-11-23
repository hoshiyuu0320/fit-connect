-- =============================================================================
-- Migration: workout_assignment_write_guards
-- 目的（フェーズ5.11）: public.workout_assignments / public.workout_assignment_exercises に
--   「列単位」の書き込みガードを入れる。行レベルの RLS（誰の行か）はそのまま残し、その上に
--   「その行のどの列を、誰が書いてよいか」を DB 側で強制する層を足す（5.8 の clients /
--   messages と同じ考え方。20260922000200_column_write_guards.sql）。
--
-- テスト: supabase/tests/workout_assignment_write_guards_test.sql
--   （禁止系・トリガー層だけの確認・正規経路の回帰・FK の参照動作・カタログ確認。
--     BEGIN...ROLLBACK で DB に何も残さない）
--
-- -----------------------------------------------------------------------------
-- 背景の穴と影響（2026-11-23。ポリシー・権限は本番の読み取り、影響は修正前のスキーマの
-- 隔離スタックで実際に確かめた。以下の穴はどれも DB に直接届く経路 = PostgREST に authenticated /
-- anon で届く要求の話。service_role で書く本番 Web の未認証の API は「残るリスク」と 5.12）
-- -----------------------------------------------------------------------------
-- 両表とも所有者 postgres、relacl は anon / authenticated / service_role に arwdDxt
-- （列 ACL 無し・トリガー無し）。ポリシーは次のとおり:
--   workout_assignments
--     "Clients can update own assignments"  UPDATE TO public  USING (client_id = auth.uid())、WITH CHECK 無し
--       （repo の定義は USING (client_id IN (SELECT clients.client_id FROM clients
--         WHERE clients.client_id = auth.uid()))。どちらでも本 migration の判定は変わらない）
--     "Clients can view own assignments"    SELECT TO public  同じ条件
--     "Trainers can manage their assignments" ALL TO authenticated USING / WITH CHECK (trainer_id = auth.uid())
--   workout_assignment_exercises
--     "Clients can update own assignment exercises" UPDATE TO public
--         USING (assignment_id IN (SELECT id FROM workout_assignments WHERE client_id = auth.uid()))、WITH CHECK 無し
--     "Clients can view own assignment exercises"   SELECT TO public  同じ条件
--     "Trainers can manage assignment exercises"    ALL TO authenticated
--         USING (assignment_id IN (SELECT id FROM workout_assignments WHERE trainer_id = auth.uid()))、WITH CHECK 無し
--   workout_plans
--     "clients_read_assigned_plans" SELECT TO public
--         USING (id IN (SELECT plan_id FROM workout_assignments WHERE client_id = auth.uid()))
--
--   穴1 顧客用の UPDATE ポリシーは行（自分の割り当て）しか縛らず、列を制限しない。
--       WITH CHECK が無いので USING が新しい行にも使われ、client_id と（種目の）assignment_id
--       だけは自分のものに固定されるが、他の列はすべて書ける。確かめた影響:
--       (a) plan_id を他トレーナーのプランに変えると、clients_read_assigned_plans でそのプランの
--           行（題名・説明）が読める（workout_exercises は顧客用ポリシーが無く読めない）
--       (b) trainer_id を別のトレーナーに変えると、元のトレーナーからは割り当てと種目が見えなく
--           なり、付け替え先のトレーナーが割り当てと種目を読み書き・削除できる
--       (d) trainer_note / session_id（他トレーナーのセッションも可）/ started_at /
--           created_at（'-infinity' も可）、種目の exercise_name / target_sets / target_reps /
--           target_weight / memo / order_index / created_at / linked_exercise_id（他人の種目も可）/
--           assignment_id（自分の別の割り当てへ）を書き換えられる。アプリが扱わない
--           セッション型の割り当ての status・種目の actual_sets も書ける
--   穴2 トレーナー用の ALL ポリシーは trainer_id しか縛らない（client_id・plan_id は自由）。
--       (c) トレーナーが authenticated で直接、他トレーナーの顧客に割り当てと種目を INSERT でき、
--           その顧客から見え（自分のプランも clients_read_assigned_plans で読ませられる）、
--           完了にすると顧客の記録の連続（get_record_streak）にも数えられる。顧客の担当
--           トレーナーには見えない
--       （報告された穴1 の表だけでなく、同じ表の全ポリシーを読んで見つかった）
--   穴3 anon にもテーブル単位の INSERT / UPDATE / DELETE があり、顧客用ポリシーは TO public。
--       (e) クレームなしの anon は RLS で 0 行（INSERT は RLS 違反）だが、顧客のクレームを
--           持った anon は顧客と同じに書ける（trainer_id の付け替えも可）
--
-- -----------------------------------------------------------------------------
-- 正規の書き込み経路の全数調査（2026-11-23 grep 全数。パスはリポジトリルート相対）
-- -----------------------------------------------------------------------------
-- [Mobile]（ロール authenticated・顧客本人。呼び出し元は workout_provider.dart だけ）
--   fit-connect-mobile/lib/features/workout/data/workout_repository.dart（すべて .update(map).eq('id', ...)）
--   - M1 toggleExerciseCompletion: workout_assignment_exercises {is_completed, completed_at}
--   - M2 updateActualSets:         workout_assignment_exercises {actual_sets, is_completed, completed_at}
--   - M3 completeAssignment:       workout_assignments {status: 'completed', finished_at,
--                                  client_feedback（任意）, calories（任意）}
--   - M4 skipAssignment:           workout_assignments {status: 'skipped', updated_at}
--   - M5 rescheduleAssignment:     workout_assignments {assigned_date, status: 'pending', updated_at}
--   2026-04-26 の取り込み時点（ストアにある古い版の可能性がある）も同じ列（M5 に status が無いだけ）。
--   読み込みはすべて plan_type = 'self_guided' で絞っており、アプリはセッション型の割り当てを
--   表示も書き込みもしない。
-- [Web]（develop・本番 Web の main とも、書き込みはすべて supabaseAdmin = service_role。
--   ブラウザのクライアントは両表を読むだけ）
--   - fit-connect/src/app/api/workout-assignments/route.ts POST: 割り当ての INSERT
--     {trainer_id, client_id, plan_id, assigned_date, status, session_id} + 種目のコピーの INSERT
--     {assignment_id, exercise_name, target_sets, target_reps, target_weight, order_index,
--      actual_sets, is_completed, memo, linked_exercise_id} + session_id の UPDATE
--   - fit-connect/src/app/api/workout-assignments/[id]/route.ts PATCH {updated_at, assigned_date,
--     status, trainer_note, client_feedback, started_at, finished_at} / DELETE
--   - fit-connect/src/app/api/workout-assignment-exercises/[id]/route.ts PATCH {actual_sets, is_completed, memo}
--   - 参照動作: fit-connect/src/lib/supabase/deleteSession.ts / deleteRecurringSessionsFromDate.ts は
--     ブラウザのクライアント（authenticated のトレーナー）で sessions を DELETE する
--     → workout_assignments.session_id が ON DELETE SET NULL で更新される。
--     プランの削除（DELETE /api/workout-plans/[id]、service_role）→ 割り当て・種目が CASCADE
-- [Edge Functions]（service_role）
--   - supabase/functions/auto-skip-workouts: {status: 'skipped', updated_at}（条件付き UPDATE）
--   - supabase/functions/delete-account: clients の DELETE → 割り当て・種目が CASCADE
-- [SQL] 両表に書く DB の関数・トリガーは無い（get_record_streak は読むだけ）
--
-- 列ごとの判断
--   workout_assignments
--   | 列                                  | 顧客本人（authenticated）           | トレーナー（authenticated） | service_role / 参照動作 |
--   |-------------------------------------|-------------------------------------|-----------------------------|-------------------------|
--   | status, assigned_date, finished_at, | UPDATE（self_guided の自分の行だけ。| 不可（Web は service_role） | 任意                    |
--   | client_feedback, calories,          | M3〜M5）                            |                             |                         |
--   | updated_at                          |                                     |                             |                         |
--   | id, trainer_id, client_id, plan_id, | 不可                                | 不可                        | 任意                    |
--   | created_at, session_id,             |                                     |                             | （session_id は参照動作 |
--   | trainer_note, started_at            |                                     |                             |  の SET NULL を含む）   |
--   | 行の INSERT / DELETE                | 不可（経路が無い）                  | 不可（経路が無い）          | 任意（CASCADE を含む）  |
--   workout_assignment_exercises
--   | actual_sets, is_completed,          | UPDATE（self_guided の自分の        | 不可                        | 任意                    |
--   | completed_at                        | 割り当ての種目だけ。M1・M2）        |                             |                         |
--   | id, assignment_id, exercise_name,   | 不可                                | 不可                        | 任意                    |
--   | target_sets, target_reps,           |                                     |                             |                         |
--   | target_weight, order_index, memo,   |                                     |                             |                         |
--   | linked_exercise_id, created_at      |                                     |                             |                         |
--   | 行の INSERT / DELETE                | 不可                                | 不可                        | 任意（CASCADE を含む）  |
--   今後どちらかの表に足される列は、両層とも既定で「不可」になる（列 GRANT は許可リスト、
--   トリガーは許可列以外の差分を拒否）。
--
-- -----------------------------------------------------------------------------
-- 方式
-- -----------------------------------------------------------------------------
-- 1. GRANT 層: 両表の INSERT / UPDATE / DELETE を anon / authenticated から剥がし、authenticated
--    には顧客が書く列だけ UPDATE を列単位で付け直す（5.8 の clients と同じ）。
--    SELECT・REFERENCES・TRIGGER・TRUNCATE と service_role の権限は触らない
--    （TRUNCATE は PostgREST から使えないので 5.8 と同じく範囲外）。
-- 2. トリガー層: 表ごとに BEFORE INSERT OR UPDATE OR DELETE FOR EACH ROW のガード関数。
--    - current_user が authenticated / anon のときだけ制限する。service_role（Web の API・
--      Edge Functions）と postgres（FK の参照動作・cron・SECURITY DEFINER 関数）は素通し。
--      参照動作（ON DELETE SET NULL / CASCADE）は削除した人のロールではなく参照側の表の
--      所有者として実行されるので、authenticated のトレーナーが Web でセッションを消しても、
--      session_id の SET NULL はここで止まらない（テスト j1）。DELETE で素通しにするときは
--      OLD を返す（BEFORE ROW トリガーが NULL を返すと、その行の操作が黙って取り消される）
--    - anon → ANON_WRITE_FORBIDDEN（5.8 と同じコード）
--    - authenticated の INSERT / DELETE → *_WRITE_FORBIDDEN（正規の経路が無い。GRANT が将来
--      GRANT ALL で戻ると、穴2 のとおりトレーナーが任意の顧客に割り当てを作れてしまうため）
--    - authenticated の UPDATE は次の 3 つをすべて満たすときだけ通す:
--      (1) 呼び出し元がその行の顧客本人（割り当ては auth.uid() = OLD.client_id。種目は呼び出し元の
--          RLS の下で親の割り当て（OLD.assignment_id）を引き、その client_id。見えなければ拒否）
--          → *_NOT_CLIENT
--      (2) プランが self_guided（呼び出し元の RLS の下で workout_plans.plan_type を引く。
--          顧客は clients_read_assigned_plans で読める。見えない・session → 拒否 = fail closed）
--          → *_NOT_SELF_GUIDED。セッション型の結果はトレーナーが Web（service_role）で記録し、
--          アプリは書かない
--      (3) 許可列以外が変わっていない（to_jsonb(NEW) - 許可列 と to_jsonb(OLD) - 許可列 の比較。
--          今後足される列も既定で保護される）→ *_COLUMN_NOT_UPDATABLE
--    - SECURITY INVOKER（DEFINER にすると current_user が所有者になり判定できない）+
--      SET search_path = '' + 完全修飾。参照クエリは呼び出し元の RLS の下で動く。
--      EXECUTE は PUBLIC / anon / authenticated / service_role から剥がす（トリガー関数は
--      発火時に EXECUTE を検査されない。5.10 の lessons）
-- 3. 末尾の検査（§6）: 権限の最終形・トリガー・関数の属性と EXECUTE を検査し、想定と違えば
--    WORKOUT_ASSIGNMENT_GUARD_CHECK_FAILED で migration ごと中断する（REVOKE は自分が付与した
--    権限しか剥がさない。lessons「REVOKE は『自分が付与した権限』しか剥がさない」）。
--
-- 二層にする理由: GRANT 層は列単位の可否を PostgREST の手前で安く拒否し（permission denied →
--   PostgREST は 401 / 403）、トリガー層は GRANT では表せない「誰の行か（顧客本人か・
--   トレーナーか）」「プランの種別」を判定する。顧客もトレーナーも同じ authenticated なので、
--   列 GRANT だけでは「トレーナーが自分の割り当ての status を書く」「顧客がセッション型の
--   status を書く」を止められない。逆にトリガーだけだと、将来 GRANT が戻ったときや
--   トリガーが無効にされたときの防御が一層になる。
-- プラン種別の判定をポリシー（USING）に入れない理由: workout_plans の
--   clients_read_assigned_plans が workout_assignments を参照しているので、workout_assignments の
--   ポリシーから workout_plans を引くと RLS が再帰する。修正前のスキーマの隔離スタックで、
--   USING (plan_id IN (SELECT id FROM workout_plans WHERE plan_type = 'self_guided')) の
--   RESTRICTIVE ポリシーを足すと、顧客・トレーナーとも UPDATE が 42P17
--   "infinite recursion detected in policy for relation workout_assignments" になることを確かめた。
--   トリガー内の参照は RLS の展開ではない（通常のクエリ）ので再帰しない。
-- エラー: RAISE EXCEPTION '<固定コード>' USING ERRCODE = '42501'（insufficient_privilege →
--   PostgREST は authenticated に 403、anon に 401）。DETAIL に行と理由、HINT に正規の書き方。
--   固定コード（メッセージ文字列。クライアント・テストはこの文字列で判定する。変更禁止）:
--     ANON_WRITE_FORBIDDEN /
--     WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN / WORKOUT_ASSIGNMENTS_NOT_CLIENT /
--     WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED / WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE /
--     WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN / WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT /
--     WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED / WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE
--   末尾の検査: WORKOUT_ASSIGNMENT_GUARD_CHECK_FAILED（P0001）
-- RLS ポリシーには一切触れない。
--
-- -----------------------------------------------------------------------------
-- 挙動の変化
-- -----------------------------------------------------------------------------
--   - 顧客が書けるのは、自分の self_guided の割り当ての status / assigned_date / finished_at /
--     client_feedback / calories / updated_at と、その種目の actual_sets / is_completed /
--     completed_at だけになる。セッション型の割り当て・種目には書けない（アプリは書いていない）
--   - トレーナーは authenticated で両表に書けなくなる（INSERT / UPDATE / DELETE とも）。
--     Web は service_role で書くので変わらない
--   - anon は両表に書けなくなる（GRANT 剥奪 + ANON_WRITE_FORBIDDEN）
--   - FK の参照動作（セッションの削除で session_id が NULL・プラン / 顧客 / トレーナーの削除で
--     CASCADE）は変わらない。authenticated のトレーナーがセッションやプランを消した場合も同じ
--
-- 互換性（現行のアプリビルドはすべてそのまま動く）
--   - Mobile M1〜M5（古い版を含む）: 列はすべて許可リストの中、対象は自分の self_guided の行
--   - Web・Edge Functions: service_role のため GRANT もトリガーも影響しない
--   - 読み取り（SELECT・埋め込み）・Realtime・get_record_streak: 変わらない
--   - PostgREST の PATCH は SET 句にペイロードの列だけを並べ、return=minimal（Mobile の既定）は
--     列を返さないので、UPDATE の列権限だけで通る（Mobile は .select() を付けていない）
--
-- -----------------------------------------------------------------------------
-- 残るリスク（許容。値そのものは検証しない）
-- -----------------------------------------------------------------------------
--   - 許可列の値は CHECK 制約（status の 4 値）以外を検証しない: status の遷移（completed →
--     pending など）、finished_at / completed_at / updated_at の時刻（未来・'-infinity' も可）、
--     assigned_date（'infinity' も可）、client_feedback / calories、actual_sets の JSON の形と
--     大きさは、顧客が自分の self_guided の行に自由に書ける。影響は自分の記録とその担当
--     トレーナーの画面だけ。DB で両表を読む関数は get_record_streak（INVOKER・本人の RLS）だけで、
--     ±infinity の日付でも落ちない形になっている（20261123000000）
--   - 「自分で完了にした」記録は自己申告で、記録の連続を水増しできる（アプリで完了を押すのと同じ）
--   - jsonb の比較の盲点: numeric の scale だけの変更（target_weight 60 → 60.0）は「変わっていない」
--     と判定される（値は同じ。5.8 と同じ）
--   - anon / authenticated の TRUNCATE・REFERENCES・TRIGGER は残る（PostgREST から使えない。
--     5.8 と同じく範囲外）
--   - service_role（Web の API Route）は DB では制限しない。Web の所有検証（trainerOwnsClient /
--     trainerOwnsPlan / trainerOwnsAssignment 等）はアプリ側で保つ（5.9 の lessons）
--   - 顧客用ポリシー（TO public）とトレーナー用ポリシーはそのまま。将来 GRANT ALL で表の権限が
--     戻っても、トリガーが authenticated の INSERT / DELETE・顧客本人でない UPDATE・保護列・
--     anon を拒否する（テスト section H）
--   - 本番 Web（Vercel の本番は main から作られる。2026-11-23 時点で main は 2026-04-26 の f895ac5）
--     には 5.5 の API Route の認証が入っていない。割り当て・種目・プランの API（workout-assignments の
--     POST / workout-assignments/[id] の PATCH・DELETE / workout-assignment-exercises/[id] の PATCH /
--     workout-plans/[id] の PUT・DELETE）はログインなしで supabaseAdmin（service_role）を使うので、
--     穴1・穴2 と同じ書き込み（trainer_note・started_at・セッション型の結果・削除・他トレーナーの
--     顧客への作成・プランの種別の変更）が service_role で引き続きできる。本 migration は DB に直接
--     届く経路（PostgREST に authenticated / anon で届く要求）だけを塞ぐ。Web を本番に出すか main を
--     直すまで残る（docs/tasks/IMPLEMENTATION_TASKS.md 5.12）
--
-- -----------------------------------------------------------------------------
-- 適用順・冪等性・適用後の確認
-- -----------------------------------------------------------------------------
--   - 本番の最新は 20261123000000（record_streak。タスク表の記録では 2026-11-23 に適用）。本 migration は
--     その後ろに並ぶので、develop にマージした後に develop から push すれば --include-all 無しで末尾に適用される。
--     push の前に `supabase migration list --linked` と `supabase db push --dry-run` で、
--     未適用がこの 1 本だけであることを確かめる
--   - 冪等: CREATE OR REPLACE FUNCTION / DROP TRIGGER IF EXISTS → CREATE TRIGGER /
--     REVOKE → GRANT（表単位の REVOKE は列単位の権限も剥がすので、再実行しても最終形に収束）/
--     末尾の検査 DO ブロックは読み取りのみ
--   - Supabase は各 migration をトランザクション内で実行する（途中の失敗・§6 の検査の失敗は全体ロールバック）
--   - 適用後の確認（SQL エディタ。すべて期待どおりなら 0 行。隔離スタックで、適用後は 0 行・
--     修正前の状態では 105 行（余分な権限・トリガー無しなど）になることを確かめた）:
--       WITH allowed(tbl, col) AS (VALUES
--         ('workout_assignments', 'status'), ('workout_assignments', 'assigned_date'),
--         ('workout_assignments', 'finished_at'), ('workout_assignments', 'client_feedback'),
--         ('workout_assignments', 'calories'), ('workout_assignments', 'updated_at'),
--         ('workout_assignment_exercises', 'actual_sets'), ('workout_assignment_exercises', 'is_completed'),
--         ('workout_assignment_exercises', 'completed_at'))
--       SELECT 'extra privilege' AS problem, c.table_name AS target, c.grantee AS role,
--              c.column_name || ':' || c.privilege_type AS detail
--         FROM information_schema.column_privileges c
--        WHERE c.table_schema = 'public'
--          AND c.table_name IN ('workout_assignments', 'workout_assignment_exercises')
--          AND c.grantee IN ('anon', 'authenticated') AND c.privilege_type IN ('INSERT', 'UPDATE')
--          AND NOT (c.grantee = 'authenticated' AND c.privilege_type = 'UPDATE'
--                   AND (c.table_name, c.column_name) IN (SELECT tbl, col FROM allowed))
--       UNION ALL
--       SELECT 'extra privilege', t.tbl, r.rolname, 'DELETE'
--         FROM (VALUES ('workout_assignments'), ('workout_assignment_exercises')) t(tbl)
--        CROSS JOIN (VALUES ('anon'), ('authenticated')) r(rolname)
--        WHERE has_table_privilege(r.rolname, 'public.' || t.tbl, 'DELETE')
--       UNION ALL
--       SELECT 'missing privilege', a.tbl, 'authenticated', a.col || ':UPDATE'
--         FROM allowed a
--        WHERE NOT has_column_privilege('authenticated', 'public.' || a.tbl, a.col, 'UPDATE')
--       UNION ALL
--       SELECT 'trigger missing or disabled', v.tgname, NULL, NULL
--         FROM (VALUES ('workout_assignments_guard_write'), ('workout_assignment_exercises_guard_write')) v(tgname)
--        WHERE NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = v.tgname AND t.tgenabled IN ('O', 'A'))
--       UNION ALL
--       SELECT 'guard function EXECUTE', p.proname, r.rolname, NULL
--         FROM pg_proc p
--        CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) r(rolname)
--        WHERE p.pronamespace = 'public'::regnamespace
--          AND p.proname IN ('workout_assignments_guard_write', 'workout_assignment_exercises_guard_write')
--          AND has_function_privilege(r.rolname, p.oid, 'EXECUTE');
--   - PostgREST の接続ロール authenticator の所属が、ちょうど anon / authenticated / service_role の
--     3 つであること（ガードは「anon / authenticated 以外」をすべて素通しにするので、PostgREST が
--     SET ROLE できるロールが増えると、そのロールの要求はガードを通らない）:
--       SELECT r.rolname FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.roleid
--        WHERE m.member = 'authenticator'::regrole;
--   - 修正前に改ざんされた行が無いこと（期待は 0 行。穴1〜3 で書けた値の痕跡を探す。隔離スタックで、
--     きれいなデータでは 0 行、5 種類を模した行はそれぞれ検出されることを確かめた。
--     2 つ目は、管理者（service_role）が顧客の担当を付け替えた後の古い割り当てでも出るので、
--     出たら中身を見て判断する）:
--       SELECT 'plan of another trainer' AS problem, a.id
--         FROM public.workout_assignments a
--         JOIN public.workout_plans p ON p.id = a.plan_id
--        WHERE p.trainer_id IS DISTINCT FROM a.trainer_id
--       UNION ALL
--       SELECT 'trainer_id differs from the client''s trainer', a.id
--         FROM public.workout_assignments a
--         JOIN public.clients c ON c.client_id = a.client_id
--        WHERE c.trainer_id IS DISTINCT FROM a.trainer_id
--       UNION ALL
--       SELECT 'session of another trainer or client', a.id
--         FROM public.workout_assignments a
--         JOIN public.sessions s ON s.id = a.session_id
--        WHERE s.trainer_id IS DISTINCT FROM a.trainer_id OR s.client_id IS DISTINCT FROM a.client_id
--       UNION ALL
--       SELECT 'linked_exercise_id in another assignment', x.id
--         FROM public.workout_assignment_exercises x
--         JOIN public.workout_assignment_exercises l ON l.id = x.linked_exercise_id
--        WHERE l.assignment_id IS DISTINCT FROM x.assignment_id
--       UNION ALL
--       SELECT 'created_at not finite or in the future', a.id
--         FROM public.workout_assignments a
--        WHERE NOT isfinite(a.created_at) OR a.created_at > now()
--       UNION ALL
--       SELECT 'created_at not finite or in the future', x.id
--         FROM public.workout_assignment_exercises x
--        WHERE NOT isfinite(x.created_at) OR x.created_at > now();
--   - あわせて、Mobile でセルフガイドのプランの種目の完了・セットの記録・プランの完了・スキップ・
--     日付の変更ができること、Web で割り当ての作成・編集・削除・種目の記録・セッションの削除が
--     できることを確かめる
--   - 緊急時の戻し方（アプリの正規の書き込みが壊れたとき。原因に合わせて (1) から順に、小さい手当てで
--     済むものを選ぶ）:
--     (1) 正規の書き込みに要る列が許可リストに足りない → その列を §5 の列 GRANT と、ガード関数の
--         c_allowed（トリガーの許可リスト）の両方に足す新しい migration を作る（§6 の検査とテストの
--         許可リストも同じに直す）。片方だけだと、GRANT 層かトリガー層のどちらかで拒否されたまま
--     (2) トリガーが原因（本人・種別の判定の誤りなど）→ トリガーだけを止める。GRANT 層（列権限・
--         INSERT / DELETE の剥奪・anon の剥奪）は残る:
--           ALTER TABLE public.workout_assignments DISABLE TRIGGER workout_assignments_guard_write;
--           ALTER TABLE public.workout_assignment_exercises DISABLE TRIGGER workout_assignment_exercises_guard_write;
--         止めている間は本人・種別の判定が無くなり、顧客がセッション型の行の許可列を、トレーナーが
--         authenticated で自分の割り当ての許可列を書ける（保護列・INSERT / DELETE・anon は GRANT 層が
--         拒否したまま。隔離スタックで確かめた）。直したら ENABLE TRIGGER で戻す
--     (3) 最後の手段: 全部戻す。anon の書き込みまで戻り、背景の穴1〜3 がすべて開く:
--           DROP TRIGGER workout_assignments_guard_write ON public.workout_assignments;
--           DROP TRIGGER workout_assignment_exercises_guard_write ON public.workout_assignment_exercises;
--           DROP FUNCTION public.workout_assignments_guard_write();
--           DROP FUNCTION public.workout_assignment_exercises_guard_write();
--           REVOKE UPDATE ON public.workout_assignments, public.workout_assignment_exercises FROM authenticated;
--           GRANT INSERT, UPDATE, DELETE ON public.workout_assignments, public.workout_assignment_exercises
--             TO anon, authenticated;
--         （隔離スタックで、relacl が修正前と同じ {...,anon=arwdDxt/postgres,authenticated=arwdDxt/postgres,...}
--           に戻り、列 ACL が残らないことを確かめた）
-- =============================================================================


-- =============================================================================
-- 1. workout_assignments: ガード関数 workout_assignments_guard_write()
-- =============================================================================

CREATE OR REPLACE FUNCTION public.workout_assignments_guard_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  -- 顧客本人が書いてよい列（Mobile の completeAssignment / skipAssignment / rescheduleAssignment）。
  -- §5 の列 GRANT・§6 の検査・テストの許可リストと同じにしておくこと
  c_allowed   constant text[] := ARRAY['status', 'assigned_date', 'finished_at',
                                       'client_feedback', 'calories', 'updated_at'];
  v_uid       uuid;
  v_plan_type text;
  v_new       jsonb;
  v_old       jsonb;
  v_columns   text;
BEGIN
  -- service_role / postgres（FK の参照動作・cron・SECURITY DEFINER 関数）は対象外。
  -- DELETE は OLD を返す（NULL を返すと BEFORE ROW トリガーが削除を取り消してしまう）
  IF current_user NOT IN ('authenticated', 'anon') THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  -- anon は正規の書き手ではない（通常は GRANT 剥奪で権限チェックが先に落ちる）
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'ANON_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('table=%s.%s op=%s', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP),
            HINT    = 'anon ロールは workout_assignments に書き込めません。ログインしてから操作してください。';
  END IF;

  -- authenticated の作成・削除の経路は無い（Web は service_role の API で行う）
  IF TG_OP IN ('INSERT', 'DELETE') THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('op=%s assignment=%s',
                             TG_OP, CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END),
            HINT    = '割り当ての作成・削除はトレーナーが Web から行います（エンドユーザーは直接書けません）。';
  END IF;

  -- (1) 呼び出し元がこの行の顧客本人
  v_uid := auth.uid();
  IF v_uid IS NULL OR OLD.client_id IS DISTINCT FROM v_uid THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENTS_NOT_CLIENT' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENTS_NOT_CLIENT'
      USING ERRCODE = '42501',
            DETAIL  = format('assignment=%s caller=%s is not the client of this assignment',
                             OLD.id, coalesce(v_uid::text, 'NULL')),
            HINT    = '割り当てを直接更新できるのは、その割り当ての顧客本人だけです（トレーナーの更新は Web から行います）。';
  END IF;

  -- (2) プランが self_guided（呼び出し元の RLS の下で読む。読めなければ拒否 = fail closed）
  SELECT p.plan_type
    INTO v_plan_type
    FROM public.workout_plans p
   WHERE p.id = OLD.plan_id;

  IF v_plan_type IS DISTINCT FROM 'self_guided' THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED'
      USING ERRCODE = '42501',
            DETAIL  = format('assignment=%s plan=%s plan_type=%s', OLD.id, OLD.plan_id,
                             coalesce(v_plan_type, '(not visible)')),
            HINT    = 'アプリから更新できるのはセルフガイドのプランの割り当てだけです（セッションの結果はトレーナーが記録します）。';
  END IF;

  -- (3) 許可列以外が変わっていない
  v_new := to_jsonb(NEW) - c_allowed;
  v_old := to_jsonb(OLD) - c_allowed;

  IF v_new IS DISTINCT FROM v_old THEN
    SELECT string_agg(coalesce(n.key, o.key), ', ' ORDER BY coalesce(n.key, o.key))
      INTO v_columns
      FROM jsonb_each(v_new) AS n
      FULL JOIN jsonb_each(v_old) AS o ON o.key = n.key
     WHERE n.value IS DISTINCT FROM o.value;

    -- メッセージ文字列 'WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE'
      USING ERRCODE = '42501',
            DETAIL  = format('assignment=%s columns=%s', OLD.id, coalesce(v_columns, '(unknown)')),
            HINT    = '顧客が更新できるのは status / assigned_date / finished_at / client_feedback / calories / updated_at だけです。';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.workout_assignments_guard_write() IS
  'workout_assignments の BEFORE INSERT / UPDATE / DELETE ガード（current_user が authenticated / anon のときだけ）。'
  'anon は ANON_WRITE_FORBIDDEN、authenticated の INSERT / DELETE は WORKOUT_ASSIGNMENTS_WRITE_FORBIDDEN。'
  'UPDATE は 顧客本人（auth.uid() = client_id。違えば WORKOUT_ASSIGNMENTS_NOT_CLIENT）・'
  'プランが self_guided（呼び出し元の RLS で読む。違う・読めなければ WORKOUT_ASSIGNMENTS_NOT_SELF_GUIDED）・'
  '許可列 {status, assigned_date, finished_at, client_feedback, calories, updated_at} 以外が不変'
  '（違えば WORKOUT_ASSIGNMENTS_COLUMN_NOT_UPDATABLE）のときだけ通す。いずれも 42501。'
  'service_role と postgres（FK の参照動作を含む）は素通し。仕様: 20261123000100_workout_assignment_write_guards.sql ヘッダー';


-- =============================================================================
-- 2. workout_assignment_exercises: ガード関数 workout_assignment_exercises_guard_write()
-- =============================================================================

CREATE OR REPLACE FUNCTION public.workout_assignment_exercises_guard_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  -- 顧客本人が書いてよい列（Mobile の toggleExerciseCompletion / updateActualSets）。
  -- §5 の列 GRANT・§6 の検査・テストの許可リストと同じにしておくこと
  c_allowed   constant text[] := ARRAY['actual_sets', 'is_completed', 'completed_at'];
  v_uid       uuid;
  v_client_id uuid;
  v_plan_id   uuid;
  v_plan_type text;
  v_new       jsonb;
  v_old       jsonb;
  v_columns   text;
BEGIN
  -- service_role / postgres（FK の参照動作・cron・SECURITY DEFINER 関数）は対象外。
  -- DELETE は OLD を返す（NULL を返すと BEFORE ROW トリガーが削除を取り消してしまう）
  IF current_user NOT IN ('authenticated', 'anon') THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    END IF;
    RETURN NEW;
  END IF;

  -- anon は正規の書き手ではない（通常は GRANT 剥奪で権限チェックが先に落ちる）
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'ANON_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('table=%s.%s op=%s', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP),
            HINT    = 'anon ロールは workout_assignment_exercises に書き込めません。ログインしてから操作してください。';
  END IF;

  -- authenticated の作成・削除の経路は無い（Web は service_role の API で行う）
  IF TG_OP IN ('INSERT', 'DELETE') THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('op=%s exercise=%s',
                             TG_OP, CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END),
            HINT    = '種目の追加・削除はトレーナーが Web から行います（エンドユーザーは直接書けません）。';
  END IF;

  -- (1) 呼び出し元が親の割り当ての顧客本人（親は呼び出し元の RLS の下で引く。見えなければ拒否）
  v_uid := auth.uid();
  SELECT a.client_id, a.plan_id
    INTO v_client_id, v_plan_id
    FROM public.workout_assignments a
   WHERE a.id = OLD.assignment_id;

  IF v_uid IS NULL OR v_client_id IS NULL OR v_client_id IS DISTINCT FROM v_uid THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT'
      USING ERRCODE = '42501',
            DETAIL  = format('exercise=%s assignment=%s caller=%s is not the client of this assignment',
                             OLD.id, OLD.assignment_id, coalesce(v_uid::text, 'NULL')),
            HINT    = '種目を直接更新できるのは、その割り当ての顧客本人だけです（トレーナーの記録は Web から行います）。';
  END IF;

  -- (2) プランが self_guided（呼び出し元の RLS の下で読む。読めなければ拒否 = fail closed）
  SELECT p.plan_type
    INTO v_plan_type
    FROM public.workout_plans p
   WHERE p.id = v_plan_id;

  IF v_plan_type IS DISTINCT FROM 'self_guided' THEN
    -- メッセージ文字列 'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED'
      USING ERRCODE = '42501',
            DETAIL  = format('exercise=%s assignment=%s plan=%s plan_type=%s', OLD.id, OLD.assignment_id,
                             v_plan_id, coalesce(v_plan_type, '(not visible)')),
            HINT    = 'アプリから記録できるのはセルフガイドのプランの種目だけです（セッションの結果はトレーナーが記録します）。';
  END IF;

  -- (3) 許可列以外が変わっていない
  v_new := to_jsonb(NEW) - c_allowed;
  v_old := to_jsonb(OLD) - c_allowed;

  IF v_new IS DISTINCT FROM v_old THEN
    SELECT string_agg(coalesce(n.key, o.key), ', ' ORDER BY coalesce(n.key, o.key))
      INTO v_columns
      FROM jsonb_each(v_new) AS n
      FULL JOIN jsonb_each(v_old) AS o ON o.key = n.key
     WHERE n.value IS DISTINCT FROM o.value;

    -- メッセージ文字列 'WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE' は固定。変更禁止。
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE'
      USING ERRCODE = '42501',
            DETAIL  = format('exercise=%s columns=%s', OLD.id, coalesce(v_columns, '(unknown)')),
            HINT    = '顧客が更新できるのは actual_sets / is_completed / completed_at だけです。';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.workout_assignment_exercises_guard_write() IS
  'workout_assignment_exercises の BEFORE INSERT / UPDATE / DELETE ガード（current_user が authenticated / anon のときだけ）。'
  'anon は ANON_WRITE_FORBIDDEN、authenticated の INSERT / DELETE は WORKOUT_ASSIGNMENT_EXERCISES_WRITE_FORBIDDEN。'
  'UPDATE は 親の割り当ての顧客本人（呼び出し元の RLS で引く。違う・見えなければ WORKOUT_ASSIGNMENT_EXERCISES_NOT_CLIENT）・'
  'プランが self_guided（違う・読めなければ WORKOUT_ASSIGNMENT_EXERCISES_NOT_SELF_GUIDED）・'
  '許可列 {actual_sets, is_completed, completed_at} 以外が不変（違えば WORKOUT_ASSIGNMENT_EXERCISES_COLUMN_NOT_UPDATABLE）'
  'のときだけ通す。いずれも 42501。service_role と postgres（FK の参照動作を含む）は素通し。'
  '仕様: 20261123000100_workout_assignment_write_guards.sql ヘッダー';


-- =============================================================================
-- 3. ガード関数を RPC 面から外す
-- =============================================================================
-- トリガー関数は発火時に EXECUTE 権限を必要としない（検査は CREATE TRIGGER の時だけ）。
-- 関数を作ると PUBLIC に EXECUTE が付き、Supabase の既定権限で anon / authenticated /
-- service_role にも付くので、すべて剥がす（所有者 postgres だけが持つ）。

REVOKE ALL ON FUNCTION public.workout_assignments_guard_write()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.workout_assignment_exercises_guard_write()
  FROM PUBLIC, anon, authenticated, service_role;


-- =============================================================================
-- 4. トリガー
-- =============================================================================
-- UPDATE OF <列> の列指定はしない（指定外の列・今後足される列の UPDATE で発火せず保護が抜けるため）。
-- 両表とも既存のトリガーは無い（2026-11-23 本番・repo とも）。

DROP TRIGGER IF EXISTS workout_assignments_guard_write ON public.workout_assignments;

CREATE TRIGGER workout_assignments_guard_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.workout_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.workout_assignments_guard_write();

DROP TRIGGER IF EXISTS workout_assignment_exercises_guard_write ON public.workout_assignment_exercises;

CREATE TRIGGER workout_assignment_exercises_guard_write
  BEFORE INSERT OR UPDATE OR DELETE ON public.workout_assignment_exercises
  FOR EACH ROW
  EXECUTE FUNCTION public.workout_assignment_exercises_guard_write();


-- =============================================================================
-- 5. 表・列の権限（GRANT 層）
-- =============================================================================
-- 表単位の INSERT / UPDATE / DELETE を anon / authenticated から剥がし、authenticated には
-- 顧客（Mobile）が実際に書く列だけを UPDATE で付け直す（ヘッダーの M1〜M5）。
-- 表単位の REVOKE は同じ権限の列単位の GRANT もまとめて剥がすので、再実行しても下の最終形に収束する。
-- SELECT・REFERENCES・TRIGGER・TRUNCATE と service_role は触らない。

REVOKE INSERT, UPDATE, DELETE ON public.workout_assignments          FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.workout_assignment_exercises FROM anon, authenticated;

GRANT UPDATE (status, assigned_date, finished_at, client_feedback, calories, updated_at)
  ON public.workout_assignments TO authenticated;
GRANT UPDATE (actual_sets, is_completed, completed_at)
  ON public.workout_assignment_exercises TO authenticated;


-- =============================================================================
-- 6. 権限・トリガー・関数の最終状態の検査（満たさなければ migration 全体を中断）
-- =============================================================================
-- REVOKE は実行ロール自身が付与した権限しか外さない。別の grantor が付けた GRANT が残っていても
-- WARNING が出るだけでエラーにならない。リモートはオーナーの手動適用なので、剥奪が黙って
-- 空振りしたまま完了するのを防ぐ。検査内容（読み取りのみ。再実行しても同じ判定になる）:
--   (1) anon: 両表の INSERT / UPDATE（列単位を含む）・DELETE が無い
--   (2) authenticated: 両表の INSERT（列単位を含む）・DELETE・表単位の UPDATE が無く、UPDATE の
--       列権限が許可リストと完全一致する（全列を走査。今後足される列は false が期待値）。
--       SELECT は残っている（アプリの読み取りを壊していない）
--   (3) service_role: 両表の SELECT / INSERT / UPDATE / DELETE が残っている
--   (4) ガードトリガー 2 本が存在し、有効（tgenabled 'O' / 'A'）で、正しいガード関数を呼び、
--       BEFORE ROW・INSERT / UPDATE / DELETE で発火し、列指定が無い
--   (5) ガード関数 2 本が SECURITY INVOKER・search_path = '' で、EXECUTE を PUBLIC / anon /
--       authenticated / service_role のどれも持たない
-- PUBLIC への付与・ロールの継承による権限も has_*_privilege が拾う。
-- メッセージ文字列 'WORKOUT_ASSIGNMENT_GUARD_CHECK_FAILED' は固定。変更禁止。

DO $$
DECLARE
  v_problems text[] := '{}';
  e          record;
  r          record;
  v_role     text;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES
      ('public.workout_assignments',
       ARRAY['status', 'assigned_date', 'finished_at', 'client_feedback', 'calories', 'updated_at'],
       'workout_assignments_guard_write',
       'public.workout_assignments_guard_write()'),
      ('public.workout_assignment_exercises',
       ARRAY['actual_sets', 'is_completed', 'completed_at'],
       'workout_assignment_exercises_guard_write',
       'public.workout_assignment_exercises_guard_write()')
    ) AS v(tbl, upd, tgname, fn)
  LOOP
    -- (1) anon
    IF has_any_column_privilege('anon', e.tbl, 'INSERT') THEN
      v_problems := v_problems || format('anon has INSERT on %s (table or column level)', e.tbl);
    END IF;
    IF has_any_column_privilege('anon', e.tbl, 'UPDATE') THEN
      v_problems := v_problems || format('anon has UPDATE on %s (table or column level)', e.tbl);
    END IF;
    IF has_table_privilege('anon', e.tbl, 'DELETE') THEN
      v_problems := v_problems || format('anon has DELETE on %s', e.tbl);
    END IF;

    -- (2) authenticated
    IF has_any_column_privilege('authenticated', e.tbl, 'INSERT') THEN
      v_problems := v_problems || format('authenticated has INSERT on %s (table or column level)', e.tbl);
    END IF;
    IF has_table_privilege('authenticated', e.tbl, 'DELETE') THEN
      v_problems := v_problems || format('authenticated has DELETE on %s', e.tbl);
    END IF;
    IF has_table_privilege('authenticated', e.tbl, 'UPDATE') THEN
      v_problems := v_problems || format('authenticated has table-level UPDATE on %s', e.tbl);
    END IF;
    IF NOT has_table_privilege('authenticated', e.tbl, 'SELECT') THEN
      v_problems := v_problems || format('authenticated lost SELECT on %s', e.tbl);
    END IF;
    FOR r IN
      SELECT a.attname::text AS col
        FROM pg_catalog.pg_attribute a
       WHERE a.attrelid = e.tbl::regclass
         AND a.attnum > 0
         AND NOT a.attisdropped
       ORDER BY a.attnum
    LOOP
      IF has_column_privilege('authenticated', e.tbl, r.col, 'UPDATE')
         IS DISTINCT FROM (r.col = ANY (e.upd)) THEN
        v_problems := v_problems || format('authenticated UPDATE(%s.%s) is %s, expected %s',
          e.tbl, r.col, has_column_privilege('authenticated', e.tbl, r.col, 'UPDATE'), r.col = ANY (e.upd));
      END IF;
    END LOOP;

    -- (3) service_role（剥がしていないこと）
    IF NOT (has_table_privilege('service_role', e.tbl, 'SELECT')
            AND has_table_privilege('service_role', e.tbl, 'INSERT')
            AND has_table_privilege('service_role', e.tbl, 'UPDATE')
            AND has_table_privilege('service_role', e.tbl, 'DELETE')) THEN
      v_problems := v_problems || format('service_role lost SELECT / INSERT / UPDATE / DELETE on %s', e.tbl);
    END IF;

    -- (4) トリガー（tgtype: 1 = ROW, 2 = BEFORE, 4 = INSERT, 8 = DELETE, 16 = UPDATE）
    SELECT t.tgenabled, t.tgfoid, t.tgtype::int AS tgtype,
           coalesce(array_length(t.tgattr::int2[], 1), 0) AS n_attr
      INTO r
      FROM pg_catalog.pg_trigger t
     WHERE t.tgrelid = e.tbl::regclass
       AND t.tgname = e.tgname
       AND NOT t.tgisinternal;
    IF NOT FOUND THEN
      v_problems := v_problems || format('trigger %s on %s is missing', e.tgname, e.tbl);
    ELSE
      IF r.tgenabled NOT IN ('O', 'A') THEN
        v_problems := v_problems || format('trigger %s on %s is disabled (tgenabled=%s)',
                                           e.tgname, e.tbl, r.tgenabled);
      END IF;
      IF r.tgfoid IS DISTINCT FROM e.fn::regprocedure::oid THEN
        v_problems := v_problems || format('trigger %s on %s calls %s, expected %s',
                                           e.tgname, e.tbl, r.tgfoid::regprocedure, e.fn);
      END IF;
      IF (r.tgtype & (1 | 2 | 4 | 8 | 16)) <> (1 | 2 | 4 | 8 | 16) OR r.n_attr <> 0 THEN
        v_problems := v_problems || format('trigger %s on %s is not BEFORE ROW INSERT / UPDATE / DELETE without a column list (tgtype=%s, columns=%s)',
                                           e.tgname, e.tbl, r.tgtype, r.n_attr);
      END IF;
    END IF;

    -- (5) ガード関数
    SELECT p.oid, p.prosecdef, p.proconfig, p.proacl
      INTO r
      FROM pg_catalog.pg_proc p
     WHERE p.oid = e.fn::regprocedure::oid;
    IF r.prosecdef THEN
      v_problems := v_problems || format('%s is SECURITY DEFINER', e.fn);
    END IF;
    IF NOT coalesce('search_path=""' = ANY (r.proconfig), false) THEN
      v_problems := v_problems || format('%s does not pin search_path to '''' (proconfig=%s)', e.fn, r.proconfig);
    END IF;
    IF r.proacl IS NULL
       OR EXISTS (SELECT 1 FROM pg_catalog.aclexplode(r.proacl) a WHERE a.grantee = 0) THEN
      v_problems := v_problems || format('PUBLIC has EXECUTE on %s (proacl=%s)', e.fn, r.proacl);
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
      IF has_function_privilege(v_role, r.oid, 'EXECUTE') THEN
        v_problems := v_problems || format('%s has EXECUTE on %s', v_role, e.fn);
      END IF;
    END LOOP;
  END LOOP;

  IF cardinality(v_problems) > 0 THEN
    RAISE EXCEPTION 'WORKOUT_ASSIGNMENT_GUARD_CHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = array_to_string(v_problems, ' / '),
            HINT    = 'REVOKE が別の grantor の付与を外せていない可能性があります。pg_class.relacl / pg_attribute.attacl / pg_proc.proacl の grantor を確認し、その grantor で REVOKE してから再適用してください（migration 全体はロールバック済み）。';
  END IF;

  RAISE NOTICE 'WORKOUT_ASSIGNMENT_GUARD_CHECK_OK: 両表の anon / authenticated / service_role の権限・ガードトリガー 2 本・ガード関数 2 本を確認';
END
$$;
