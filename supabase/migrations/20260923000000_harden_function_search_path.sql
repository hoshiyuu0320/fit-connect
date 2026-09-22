-- =============================================================================
-- Migration: harden_function_search_path
-- 関数 9 本の search_path 固定と EXECUTE の最小権限化（フェーズ5.10）: Supabase Security
-- Advisor が報告している 0011 function_search_path_mutable（6 本）と
-- 0028 anon_security_definer_function_executable（3 本）を解消する。search_path は 9 本とも
-- 空文字に固定し、トリガー関数 6 本の EXECUTE はオーナーだけに絞る。can_edit_message は
-- 本文に送信者条件を足し、EXECUTE を authenticated だけにする
--
-- 仕様出典: docs/tasks/IMPLEMENTATION_TASKS.md フェーズ5 5.10 / docs/tasks/lessons.md
--           （「SECURITY DEFINER 関数の権限是正（フェーズ5.6、2026-09-13）で得た知見」）
--
-- 対象（本体を書き換えるかどうかで 2 通りに分ける）:
--   CREATE OR REPLACE で本体を書き換える:
--     セクション 1. public.can_edit_message(message_id uuid)                 SECURITY DEFINER
--   ALTER FUNCTION ... SET search_path = '' だけ（本体は一文字も変えない）:
--     セクション 2. public.update_updated_at_column()                        トリガー関数
--                   public.update_sessions_updated_at()                      トリガー関数
--                   public.update_trainer_schedules_updated_at()             トリガー関数
--     セクション 3. public.call_parse_message_tags()                         トリガー関数・SECURITY DEFINER（#89 以降）
--     セクション 4. public.enforce_client_limit()                            トリガー関数・SECURITY DEFINER
--                   public.enforce_client_note_session_consistency()         トリガー関数・SECURITY DEFINER
--     セクション 5. public.get_last_messages_for_trainer(p_trainer_id uuid)  LANGUAGE sql STABLE
--                   public.get_unread_counts_for_trainer(p_trainer_id uuid)  LANGUAGE sql STABLE
--   フェーズ5.6（#87、20260913000500 / 000510）で是正済みの calculate_achievement_rate /
--   check_goal_achievement / issue_recurring_tickets / mark_messages_as_read には触れない
--   call_parse_message_tags は、フェーズ5.7（#89、20260922000100_secure_parse_message_tags_webhook.sql。
--   リモート適用済み）が既に SECURITY DEFINER / search_path '' / EXECUTE はオーナーのみ に
--   作り直している。本 migration のこの関数への ALTER / REVOKE は、リモートでも fresh DB でも
--   no-op になる（セクション 0・3 参照）
--
-- 背景（2026-09-22 発見、2026-09-23 更新）:
--   - Supabase Security Advisor（get_advisors security）の報告:
--       - 2026-09-22: 0011_function_search_path_mutable（WARN）7 本: update_trainer_schedules_updated_at /
--         get_last_messages_for_trainer / get_unread_counts_for_trainer / can_edit_message /
--         update_updated_at_column / update_sessions_updated_at / call_parse_message_tags。
--         0028_anon_security_definer_function_executable（WARN）3 本: can_edit_message(uuid) /
--         enforce_client_limit()（トリガー関数）/ enforce_client_note_session_consistency()
--         （トリガー関数）。3 本とも authenticated からも実行できる
--       - 2026-09-23（#89 の適用後）: 0011 は call_parse_message_tags を除く 6 本（#89 で解消）。
--         0028 は同じ 3 本。0029_authenticated_security_definer_function_executable（WARN）は
--         7 本: calculate_achievement_rate / can_edit_message / enforce_client_limit /
--         enforce_client_note_session_consistency / get_alert_detection_status / get_my_sessions /
--         mark_messages_as_read
--   - リモート（project viribpvnpgtgtmeulcmx）の実属性（2026-09-22 に読み取り専用の
--     `supabase db dump --linked --schema public`、2026-09-23 に MCP の読み取り専用 SELECT で確認）:
--       - 9 本とも owner postgres
--       - call_parse_message_tags 以外の 8 本: EXECUTE は PUBLIC / anon / authenticated /
--         service_role に付いている。付与元は 20260913000510 の「背景」と同じ Supabase
--         プラットフォームの既定（PostgreSQL が関数の作成時に PUBLIC へ付ける EXECUTE と、
--         public スキーマに対する role postgres の default privileges）で、fresh DB でも同じ
--         ACL になる。search_path は 6 本が未設定、enforce_client_limit /
--         enforce_client_note_session_consistency の 2 本は SET search_path TO 'public', 'pg_temp'。
--         SECURITY DEFINER は can_edit_message / enforce_* の 2 本の 3 本で、残り 5 本は INVOKER
--       - call_parse_message_tags: #89 の定義のまま（md5(prosrc) 7e1f035007b30bc620c9282c0eceeb5b /
--         SECURITY DEFINER / proconfig {search_path=""} / ACL {postgres=X/postgres}）
--   - public スキーマに対して anon / authenticated が持つのは USAGE だけ（CREATE は無い）。
--     search_path の固定は、関数の動作を呼び出し側の search_path や、スキーマ・権限の将来の
--     変更に左右されないようにするための多層防御として行う
--   - can_edit_message は 5.6 のフォローアップ候補（docs/tasks/IMPLEMENTATION_TASKS.md 5.6 の
--     末尾）だった。anon を含む誰でも、任意のメッセージ ID について作成から 5 分以内かどうかを
--     知ることができた（セクション 1 参照）
--
-- リモートとのドリフト（2026-09-22 実測・2026-09-23 再確認。追認 migration は不要）:
--   - リモートの migration 履歴は 20260922200000（#91）まで適用済みで、develop/1.0.0 と同じ
--   - call_parse_message_tags 以外の 8 本は、リモートの本体の md5(prosrc) が、repo の migration
--     だけで作った DB（fresh DB）の本体の md5 と一致する。2026-09-22 は、dump の関数定義を
--     ローカル DB の scratch スキーマへ読み込んで md5(prosrc) を計算し、fresh DB の値と比べた
--     （手順の対照として 5.6 で是正済みの関数 2 本も同じ手順で比べ、こちらも一致した）。
--     2026-09-23 は、リモートで md5(prosrc) を直接 SELECT し、セクション 0 の期待値と一致した
--   - call_parse_message_tags は #89 の本体で、#89 を含む fresh DB（今の develop）の本体と同一
--   - よって 20260913000500 のような「リモート実定義の追認」は要らず、repo の最新定義を
--     起点にしてよい。各関数の repo の最新定義:
--       can_edit_message / update_updated_at_column / update_sessions_updated_at
--                                               … 20251230131753_remote_schema.sql
--       update_trainer_schedules_updated_at     … 20260216221905_create_trainer_schedules.sql
--       get_last_messages_for_trainer           … 20260223045727_add_get_last_messages_for_trainer_rpc.sql
--       get_unread_counts_for_trainer           … 20260223083354_add_get_unread_counts_for_trainer_rpc.sql
--       enforce_client_limit                    … 20260712100000_enforce_client_limit.sql
--       call_parse_message_tags                 … 20260922000100_secure_parse_message_tags_webhook.sql（#89）
--       enforce_client_note_session_consistency … 20260906000100_add_session_id_to_client_notes.sql
--   - 確認したのは 2026-09-23 時点なので、push までにリモートで変わっていないことは
--     適用時にセクション 0 のガードで確かめる
--
-- 方針（呼び出し元の全数調査に基づく最小権限）:
--   呼び出し元は fit-connect/src・fit-connect-mobile/lib・supabase/functions・リモートの dump に
--   含まれる SQL の関数 / ポリシー / ビュー（storage / auth スキーマを含む）・repo の cron
--   migration を全数 grep して特定した。9 本を呼ぶ SQL の関数・ポリシー・ビュー・cron ジョブ・
--   Edge Function は無い（トリガー関数 6 本を参照するのは下表のトリガーだけ）。
--   トリガーの定義はリモートの dump と fresh DB で同一。2026-09-23 の fresh DB（#89 / #90 / #91 を
--   含む develop）でも、9 本を参照する他の SQL 関数が無いことを pg_proc で再確認した
--   （#90 / #91 は 9 本のどれにも触れない）。
--
--   関数                                       呼び出し元                                     search_path  是正後の EXECUTE
--   can_edit_message(uuid)                     Mobile の editMessage（自分の送信メッセージ）  ''           authenticated のみ
--   update_updated_at_column()                 トリガー set_updated_at 系（11 テーブル）      ''           なし（オーナーのみ）
--   update_sessions_updated_at()               トリガー（sessions）                           ''           なし（オーナーのみ）
--   update_trainer_schedules_updated_at()      トリガー（trainer_schedules）                  ''           なし（オーナーのみ）
--   call_parse_message_tags()                  トリガー（messages の INSERT / UPDATE）        '' ※2        なし（オーナーのみ）※2
--   enforce_client_limit()                     トリガー（clients）                            '' ※1        なし（オーナーのみ）
--   enforce_client_note_session_consistency()  トリガー（client_notes）                       '' ※1        なし（オーナーのみ）
--   get_last_messages_for_trainer(uuid)        Web（ログイン中のトレーナー）                  ''           変更しない
--   get_unread_counts_for_trainer(uuid)        Web（ログイン中のトレーナー）                  ''           変更しない
--   ※1 旧 SET search_path TO 'public', 'pg_temp'。他の 6 本（call_parse_message_tags を除く）は未設定
--   ※2 #89 が既に設定済み（SECURITY DEFINER も #89 による）。本 migration の ALTER / REVOKE は no-op
--   「オーナーのみ」= オーナー postgres だけが EXECUTE を持ち、GRANT は書かない
--   （呼び出し元とトリガー名の詳細は各セクションのコメント参照）
--
--   共通:
--     - 9 本とも SET search_path = '' に固定する。本体が参照するテーブル・関数は
--       スキーマ修飾済み（public.xxx / auth.uid() / net.http_post）か、NEW / OLD / TG_OP と
--       組み込みの関数・演算子・型だけで、空の search_path で解決できない名前は無い
--       （各セクションで確認）
--     - 空の search_path での名前の検索順（正確には）:
--         - 関数・演算子: pg_catalog だけ（セッションの一時スキーマ pg_temp は関数・演算子の
--           検索には一切使われない）
--         - 関係名（テーブル・ビュー等）と型名: search_path に pg_temp を明示しないと、pg_temp が
--           pg_catalog より「先に」検索される
--       9 本の関係名はすべてスキーマ修飾済みなので影響しない。一方、本体の DECLARE などには
--       無修飾の型名がある（text / timestamptz（TIMESTAMPTZ）/ uuid / jsonb。auth.uid() の本文の
--       ::jsonb / ::uuid も呼び出し元の search_path で解決される）。integer / bigint / boolean の
--       ように文法上のキーワードである型名は常に pg_catalog の型になるが、text / uuid 等は
--       同じセッションに同名の一時型があればそちらに解決される（ローカルで確認済み）
--     - この一時型による差し替えは anon / authenticated / service_role からは成立しない:
--       成立させるには、関数を呼ぶ同じセッションで先に CREATE TYPE pg_temp.xxx などの DDL を
--       実行する必要があるが、PostgREST は任意の SQL を実行せず、動的 SQL を実行する RPC も無い
--       （トリガー関数は DML を発行したセッションで動くが、そのセッションも PostgREST のもの）
--     - それでも '' を採るのは、5.6 の 4 本・#89（5.7）・Supabase の推奨（Advisor 0011 の是正例）と
--       揃えるため。プロジェクト全体で 'pg_catalog, pg_temp'（pg_temp を明示的に最後に置く）へ
--       移すかどうかは別途の判断とする（enforce_* の 2 本についての理論上のトレードオフは
--       セクション 4 参照）
--     - 本体の書き換えが要らない 8 本は CREATE OR REPLACE ではなく ALTER FUNCTION ... SET で
--       固定する。ALTER は本体（prosrc）・owner・ACL・COMMENT・言語・揮発性・SECURITY 属性を
--       そのまま残し、proconfig だけを変える。本体が一文字も変わらないので、レビュー済みの
--       本体とリモートの本体が同一であることを md5 で確かめられる（セクション 0。SECURITY
--       属性（prosecdef）も dump 時点と同じであることを確かめる）。
--       本体が変わっていても、search_path が既に空文字に固定済みなら ALTER は no-op なので
--       受け入れる（セクション 0。#89 適用済みの call_parse_message_tags がこれに当たり、
--       リモートと fresh DB ではこれが通常の経路）
--     - SECURITY DEFINER / owner postgres は変えない（5.6 と同じく実行権限のモデルは変えず、
--       誰が呼べるかと search_path だけを是正する）
--     - LANGUAGE sql の関数は SET 句を持つとインライン展開されなくなる（セクション 5 の 2 本。
--       Web から RPC として呼ぶだけなので影響は無い）
--     - EXECUTE を絞る関数は、PostgreSQL 既定の PUBLIC への EXECUTE を REVOKE で明示的に
--       剥がしてから必要なロールにだけ GRANT する（lessons.md: anon は PUBLIC のメンバーなので
--       FROM anon だけでは閉じない）
--     - COMMENT は can_edit_message だけ書き直す。他の 8 本の COMMENT は変えない
--
--   今後の注意:
--     - ALTER で固定した 8 本の search_path = '' は DB の中（proconfig）にしか無く、repo の
--       関数定義（各 migration の CREATE 文）には現れない。今後この 8 本を CREATE OR REPLACE で
--       作り直すときは、SET search_path = '' を必ず書き直すこと。書かないと固定は黙って外れる
--       （CREATE OR REPLACE は ACL を保持するので権限は残り、気付きにくい）。本体を変えたら、
--       本 migration のガードに相当する後続 migration の期待 md5 と、
--       supabase/tests/function_search_path_privileges_test.sql の固定値も更新すること
--     - Supabase の default privileges により、public に新しく作る関数には anon /
--       authenticated / service_role への EXECUTE が自動で付く（PUBLIC にも PostgreSQL 既定で
--       付く）。新しいトリガー関数を作るときは、本 migration と同じ
--       REVOKE ALL ... FROM PUBLIC / anon / authenticated / service_role を毎回書くこと
--
--   関数内で発火するトリガーについて（lessons.md「SET search_path = '' は関数内で発火する
--   トリガーにも効く」）:
--     関数の SET search_path は、その関数の DML が発火させたトリガー関数にも引き継がれる。
--     9 本はいずれもトリガーのあるテーブルに DML をしないので、この経路で空の search_path が
--     他の関数に波及することは無い:
--       - can_edit_message / enforce_client_limit / enforce_client_note_session_consistency /
--         get_last_messages_for_trainer / get_unread_counts_for_trainer は SELECT だけ
--       - call_parse_message_tags（#89 の本体）は vault.decrypted_secrets を SELECT して
--         net.http_post を呼ぶだけ。net.http_post が INSERT する net.http_request_queue に
--         トリガーは無い（本 migration はこの関数を実質的に変えない。セクション 3）
--       - update_updated_at_column / update_sessions_updated_at /
--         update_trainer_schedules_updated_at は NEW を書き換えて返すだけで DML をしない
--
--   Supabase Advisor への効果（2026-09-23 のリモートの報告に対して）:
--     - 0011_function_search_path_mutable: 6 件 → 0 件（今の 6 件はすべて本 migration の対象。
--       call_parse_message_tags の分は #89 で解消済み）
--     - 0028_anon_security_definer_function_executable: 3 件 → 0 件（can_edit_message と
--       トリガー関数 2 本から anon / PUBLIC の EXECUTE を剥がすため）
--     - 0029_authenticated_security_definer_function_executable（WARN）: 7 件 → 5 件。
--       enforce_client_limit / enforce_client_note_session_consistency は authenticated からも
--       剥がすので消える。残る 5 件のうち、本 migration の 9 本に当たるのは can_edit_message
--       だけで、これは意図どおり（ログインユーザー全員に開くが、判定できるのは自分の送信
--       メッセージだけ）。ほかの 4 件は authenticated に開いている既存の SECURITY DEFINER 関数
--       （calculate_achievement_rate / mark_messages_as_read（5.6）、get_my_sessions
--       （20260913000300）、get_alert_detection_status（20260914000200））で、それぞれの
--       migration の判断どおり残る（本 migration では扱わない）
--     - call_parse_message_tags は SECURITY DEFINER だが、EXECUTE はオーナーのみなので
--       0028 / 0029 は出ない（#89 の適用時点で既に出ていない）
--     - オーナー作業の指摘（Auth の漏えいパスワード保護の有効化、Postgres 15.8.1.102 の
--       アップグレード）は本 migration の範囲外
--
-- 適用順:
--   - 2026-09-23 の時点で、リモートは 20260922200000 まで適用済み。並行していた次の 3 本は
--     すべて develop にマージ済みかつリモート適用済みで、保留中の並行作業は無い:
--       - #89（フェーズ5.7）: 20260922000100_secure_parse_message_tags_webhook.sql
--       - #90（フェーズ5.8）: 20260922000200_column_write_guards.sql
--       - #91（フェーズ9.2）: 20260922200000_triage_unreplied.sql
--     #90 / #91 は 9 本のどれにも触れない（#91 は INVOKER の get_unreplied_clients_for_trainer を
--     足すだけ）
--   - 本 migration（20260923000000）はそれらすべての後ろに並ぶため、--include-all は不要。
--     （本 migration は当初 20260922000100、次に 20260922000200 で作っていたが、それぞれ #89 /
--     #90 が同じ版を使ったため振り直した。リモートの 20260922000200 は #90 の版である）
--   - push 前のオーナー確認: push の直前に `supabase migration list --linked` と
--     `supabase db push --dry-run` の両方で、未適用が 20260923000000 の 1 本だけであることを
--     確かめる。それ以外の版が未適用に並ぶとき、またはリモートにしか無い版があるとき
--     （`supabase db push` は Remote migration versions not found で止まる）は push しない
--   - push のログに出る想定の出力: セクション 0 のガードが call_parse_message_tags についてだけ
--     次の NOTICE を出す（#89 が本体を作り直し、search_path を固定済みのため。想定どおりで、
--     push は続行される）:
--       NOTICE:  REMOTE_DRIFT_ACCEPTED_ALREADY_PINNED: function public.call_parse_message_tags()
--       has md5(prosrc)=7e1f035007b30bc620c9282c0eceeb5b (expected 5c0b99091b07e9017b1666d0b5ab84e2
--       as of the 2026-09-22 remote dump) and prosecdef=t (dump: f), but its search_path is already
--       pinned to ''; the ALTER in this migration is a no-op
--     ほかの関数についての NOTICE や、REMOTE_DRIFT_SINCE_CAPTURE の例外が出た場合は、リモートが
--     2026-09-23 の確認以降に変わっている（例外なら migration 全体が失敗し、何も適用されない）。
--     リモートの現状を確かめてから対処すること
--   - push 後の確認（SQL エディタ、postgres で実行）:
--       SELECT p.oid::regprocedure AS fn,
--              has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
--              has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
--              has_function_privilege('service_role',  p.oid, 'EXECUTE') AS service_role,
--              p.prosecdef,
--              p.proconfig,
--              p.proacl
--       FROM pg_catalog.pg_proc p
--       WHERE p.oid = ANY (ARRAY[
--         'public.can_edit_message(uuid)',
--         'public.update_updated_at_column()',
--         'public.update_sessions_updated_at()',
--         'public.update_trainer_schedules_updated_at()',
--         'public.call_parse_message_tags()',
--         'public.enforce_client_limit()',
--         'public.enforce_client_note_session_consistency()',
--         'public.get_last_messages_for_trainer(uuid)',
--         'public.get_unread_counts_for_trainer(uuid)'
--       ]::regprocedure[])
--       ORDER BY 1;
--     期待値:
--       - proconfig: 9 本とも {search_path=""}
--       - prosecdef: can_edit_message / enforce_client_limit / enforce_client_note_session_consistency /
--         call_parse_message_tags（#89 による）が t、ほかの 5 本は f
--       - EXECUTE（anon / authenticated / service_role）: can_edit_message は f / t / f。
--         トリガー関数 6 本は f / f / f（proacl は {postgres=X/postgres} だけ）。get_* の 2 本は
--         t / t / t（ACL は変えていない）
--     あわせて Security Advisor を再実行し、0011 が 0 件、0028 が 0 件、0029 が 5 件
--     （can_edit_message と既存の 4 本 calculate_achievement_rate / mark_messages_as_read /
--     get_my_sessions / get_alert_detection_status。いずれも意図どおり）であることを確かめる
--   - 動作の確認（スモークテスト）: Mobile で送信直後の自分のメッセージを編集できること
--     （can_edit_message と messages の set_updated_at）、Web のメッセージ一覧に最新メッセージと
--     未読数が出ること（get_* の 2 本）。call_parse_message_tags はリモートでは何も変わらない
--     （Webhook の経路は #89 の push 後に #89 のオーナーが本番で E2E 確認済み）
--   - アプリのリリースは不要（既存の呼び出し元はすべてそのまま動く）:
--       - Mobile は can_edit_message を常に自分の送信メッセージに対して authenticated として呼ぶ
--       - Web の get_last_messages_for_trainer / get_unread_counts_for_trainer は EXECUTE も
--         結果も変わらない
--       - トリガーは EXECUTE の剥奪後も発火し続ける（セクション 2 参照）
--
-- 影響範囲:
--   - Web（fit-connect/src）は can_edit_message もトリガー関数も呼ばない
--   - #90 のガード用トリガー（clients_guard_protected_columns / messages_guard_insert /
--     messages_guard_update）とは独立している。本 migration はそれらのトリガー関数に触れず、
--     9 本は clients / messages に DML をしないので、空の search_path がそれらに引き継がれる
--     ことも無い。同じテーブルの既存トリガー（enforce_client_limit_trigger / on_message_insert /
--     on_message_update / set_updated_at）とは併存し、発火も変わらない
--   - #89 との関係: call_parse_message_tags は「#89 の本体 + SECURITY DEFINER + search_path '' +
--     オーナーのみの EXECUTE」のまま変わらない。本 migration の ALTER（同じ値の再設定）と
--     REVOKE（既に無い権限の剥奪）は no-op。anon に EXECUTE が無いので Advisor の 0028 も出ない
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 事前ガード: 2026-09-22 の dump 以降のリモートのドリフト検知
--    9 本の本体（pg_proc.prosrc）の md5 と SECURITY 属性（pg_proc.prosecdef）を、2026-09-22 の
--    dump 時点の値（= #89 より前の fresh DB の値。call_parse_message_tags 以外の 8 本は
--    2026-09-23 のリモートとも一致。ヘッダーの「リモートとのドリフト」参照）と比べる。
--    受け入れる条件は関数の扱い（CREATE OR REPLACE か ALTER か）で異なり、受け入れられなければ
--    例外（REMOTE_DRIFT_SINCE_CAPTURE）で migration 全体を失敗させる。関数が存在しない場合は、
--    どちらの扱いでも同じ例外で止める。
--
--    CREATE OR REPLACE で書き換える can_edit_message（厳格）:
--      md5(prosrc) と prosecdef（true = SECURITY DEFINER）がどちらも dump 時点の値と一致する
--      場合だけ受け入れる。一致しないまま適用すると、リモートでの変更を本 migration が黙って
--      元に戻してしまうため
--
--    ALTER で search_path = '' に固定するだけの 8 本（次のどちらかなら受け入れる）:
--      (a) md5(prosrc) と prosecdef がどちらも dump 時点の値と一致する（レビューした状態）
--          「無修飾のテーブル・関数参照を含まず、空の search_path でも動く」とレビューしたのは
--          dump 時点の本体である。本体が無修飾の参照を使う形に変わっていると、search_path = ''
--          がその参照を解決できなくなり、実行時に壊れる（例: enforce_client_limit なら顧客登録、
--          enforce_client_note_session_consistency ならカルテの保存が失敗する）。ALTER はエラーに
--          ならないので、適用時ではなく利用者の操作で初めて発覚する。それを適用前に止める。
--          prosecdef も比べるのは、ALTER がこの属性を dump 時点のまま残し、各関数の判断が
--          それを前提にしているため（例: get_* の 2 本は INVOKER なので行は RLS が決める、
--          として EXECUTE を変えない。DEFINER に変わっていれば RLS をバイパスしたまま
--          anon に開いた状態を、本 migration が見過ごすことになる）
--      (b) md5 は違うが、proconfig が既に ARRAY['search_path=""']（= SET search_path = '' 済み）
--          本体を変えた側が自分で search_path を空文字に固定しているので、空の search_path で
--          動くことはその変更の側で担保されている。本 migration の ALTER は同じ値の再設定
--          （no-op）になり、本体を元に戻すことも動作を変えることも無い。REVOKE も害が無い
--          （トリガー関数 6 本は EXECUTE を剥がしてもトリガーの発火は変わらず、CREATE OR
--          REPLACE では戻り値の型を変えられないのでトリガー関数のままである。get_* の 2 本は
--          ACL を変えない）。この経路では prosecdef は問わない（本体を作り直した側の判断）
--          (b) で受け入れたときは RAISE NOTICE（REMOTE_DRIFT_ACCEPTED_ALREADY_PINNED）で関数名・
--          md5・prosecdef を出す。push のログで、どの関数がこの経路で通ったかを確かめられる
--      call_parse_message_tags は (b) が通常の経路:
--          #89（20260922000100_secure_parse_message_tags_webhook.sql、フェーズ5.7）が
--          SECURITY DEFINER / SET search_path = '' の新しい本体（md5 7e1f0350…）で作り直し、
--          リモートにも適用済みで、develop にも入っている。したがってリモートでも fresh DB でも、
--          md5 は期待値 5c0b9909…（#89 より前の本体）と一致せず prosecdef も true だが、(b) で
--          受け入れ、NOTICE を 1 件出す（想定どおり。ヘッダーの「適用順」に出力例）。
--          期待値を #89 の md5 に差し替えずに残しているのは、(a) を「本 migration がレビューした
--          本体」、(b) を「別の migration が自ら search_path を固定した本体」と分け、その区別を
--          push のログに残すため（#89 の本体が空の search_path で動くことは #89 の側で確かめ、
--          本番で E2E 確認済み）
--      proconfig は完全一致で比べる（search_path 以外の設定も付いている場合や、別の
--      search_path に固定されている場合は (b) に当たらず止める）
--
--    - ACL は本 migration が明示的に上書きする対象なので比べない（get_* の 2 本は上書きしないが、
--      ACL の是正は範囲外。セクション 5）。SECURITY 属性を本 migration が明示的に設定するのは
--      can_edit_message（SECURITY DEFINER で作り直す）だけで、ALTER の 8 本は dump 時点の
--      ままにするので、上記のとおり prosecdef は比べる
--    - リモートでも fresh DB（`supabase db reset`）でも、call_parse_message_tags は (b)、
--      ほかの 8 本は (a)（can_edit_message は md5 と prosecdef の一致）で通る
--    - 是正済みの DB（本 migration を適用した後）に本ファイルを流し直すと、本体を書き換えた
--      can_edit_message だけがこのガードで止まる（ALTER の 8 本は (a) か (b) で通り、ALTER 自体も
--      何度流しても同じ結果になる）。migration は 1 回しか適用されないので問題ない
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  c_pinned    constant text[] := ARRAY['search_path=""'];  -- SET search_path = '' を付けた関数の proconfig
  v_fn        record;
  v_oid       oid;
  v_md5       text;
  v_secdef    boolean;
  v_proconfig text[];
BEGIN
  FOR v_fn IN
    SELECT t.signature, t.expected_md5, t.expected_secdef, t.change
    FROM (VALUES
      -- expected_secdef: 2026-09-22 の dump 時点の prosecdef（true = SECURITY DEFINER）
      (1, 'public.can_edit_message(uuid)',                      '07dc981df87b0187421dc90a9726aa94', true,  'CREATE OR REPLACE'),
      (2, 'public.update_updated_at_column()',                  'da5ac28a58c8b4bb30209bf0d3d7082c', false, 'ALTER'),
      (3, 'public.update_sessions_updated_at()',                'da5ac28a58c8b4bb30209bf0d3d7082c', false, 'ALTER'),
      (4, 'public.update_trainer_schedules_updated_at()',       '301a884953d37769916294bb60562e05', false, 'ALTER'),
      (5, 'public.call_parse_message_tags()',                   '5c0b99091b07e9017b1666d0b5ab84e2', false, 'ALTER'),
      (6, 'public.enforce_client_limit()',                      '06cc8fece5fb8490563b43f4f20c11cb', true,  'ALTER'),
      (7, 'public.enforce_client_note_session_consistency()',   'bfdbafb4eb8e623fc2d2041200791c50', true,  'ALTER'),
      (8, 'public.get_last_messages_for_trainer(uuid)',         'a155740854167fa6510d34194d88217b', false, 'ALTER'),
      (9, 'public.get_unread_counts_for_trainer(uuid)',         '8e8f7398ea0ebdd1328721c6abd2522b', false, 'ALTER')
    ) AS t(ord, signature, expected_md5, expected_secdef, change)
    ORDER BY t.ord
  LOOP
    v_oid := to_regprocedure(v_fn.signature);

    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s does not exist (expected md5(prosrc)=%s as of the 2026-09-22 remote dump)',
                v_fn.signature, v_fn.expected_md5
              ),
              HINT    = '2026-09-22 の dump 時点で存在した関数がありません。リモートの現状を確認し、本 migration の対象と期待 md5 を見直してから再適用してください。';
    END IF;

    SELECT md5(p.prosrc), p.prosecdef, p.proconfig
    INTO v_md5, v_secdef, v_proconfig
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_oid;

    -- レビューした本体のまま（can_edit_message はこの場合だけ受け入れる。ALTER の 8 本は (a)）。
    -- SECURITY 属性もレビューした状態のままであること
    IF v_md5 IS NOT DISTINCT FROM v_fn.expected_md5 THEN
      IF v_secdef IS DISTINCT FROM v_fn.expected_secdef THEN
        RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
          USING ERRCODE = 'P0001',
                DETAIL  = format(
                  'function %s has the reviewed body (md5(prosrc)=%s) but prosecdef=%s, expected prosecdef=%s (2026-09-22 remote dump); proconfig=%s',
                  v_fn.signature, v_md5, v_secdef, v_fn.expected_secdef, coalesce(v_proconfig::text, 'NULL')
                ),
                HINT    = '関数本体は 2026-09-22 の dump 時点のままですが、SECURITY DEFINER / INVOKER が dump 時点と異なります。本 migration の権限の判断（INVOKER なら行は RLS が決める、等）はその属性を前提にしているため中止しました。リモートで属性が変わった経緯を確認し、本 migration の方針と期待値を見直してから再適用してください。';
      END IF;
      CONTINUE;
    END IF;

    -- (b) ALTER の 8 本だけ: 本体は変わっているが search_path は既に空文字に固定済み。
    --     本 migration の ALTER は no-op になるので、NOTICE を出して受け入れる（prosecdef は問わない）
    IF v_fn.change = 'ALTER' AND v_proconfig IS NOT DISTINCT FROM c_pinned THEN
      RAISE NOTICE 'REMOTE_DRIFT_ACCEPTED_ALREADY_PINNED: function % has md5(prosrc)=% (expected % as of the 2026-09-22 remote dump) and prosecdef=% (dump: %), but its search_path is already pinned to ''''; the ALTER in this migration is a no-op',
        v_fn.signature, v_md5, v_fn.expected_md5, v_secdef, v_fn.expected_secdef
        USING HINT = '本体の変更が、search_path = '''' を自ら設定した migration（例: #89 の call_parse_message_tags。リモートと fresh DB ではこの 1 件が出るのが想定どおり）によるものかを確認してください。';
      CONTINUE;
    END IF;

    RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'function %s has md5(prosrc)=%s, expected %s (2026-09-22 remote dump); prosecdef=%s; proconfig=%s',
              v_fn.signature, v_md5, v_fn.expected_md5, v_secdef, coalesce(v_proconfig::text, 'NULL')
            ),
            HINT    = CASE v_fn.change
              WHEN 'CREATE OR REPLACE' THEN
                '関数本体が 2026-09-22 の dump 以降に変わっています。このまま適用すると CREATE OR REPLACE がその変更を元に戻すため中止しました。現定義を追認する migration を先に置き、本 migration の本体と期待 md5 をそれに合わせてから再適用してください。'
              ELSE
                '関数本体が 2026-09-22 の dump 以降に変わっており、search_path も空文字に固定されていません。空の search_path で動くとレビューしたのは dump 時点の本体のため中止しました。現定義を dump で取り直し、無修飾のテーブル・関数参照が無い（search_path = '''' で動く）ことを確認してから、期待 md5 を更新して再適用してください。'
            END;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. can_edit_message(uuid)
--    呼び出したユーザー自身が送信したメッセージで、作成から 5 分以内かを返す（編集可否の
--    事前判定）。本体は 20251230131753 の定義（2026-09-22 の dump でリモートと同一。適用時は
--    セクション 0 のガードで再確認する）に送信者条件を足し、public.messages を修飾したもの。
--    本文の行末空白は落としている。
--    本 migration 適用後の本体の md5(prosrc) は c2b26f33f8dd6b96edae211a71a0e314（ローカルで
--    適用して DB から読んだ値。後続の migration でこの関数のガードを書くときの期待値。
--    下の本体を変えるときは、この値も取り直すこと）。
--
--    呼び出し元:
--      - Mobile のみ: fit-connect-mobile/lib/features/messages/data/message_repository.dart の
--        editMessage が、自分の送信メッセージを UPDATE する前に
--        rpc('can_edit_message', {'message_id': id}) で呼ぶ（UI はトーク画面
--        message_screen.dart の _editMessage）
--      - Web は呼ばない。SQL の関数・ポリシー・ビューからの参照も無い（messages の RLS
--        ポリシー "Users can edit own messages within 5 minutes" は
--        sender_id = auth.uid() AND now() - created_at < 5 分 を自前で書いており、本関数を
--        使っていない）。service_role で呼ぶ箇所も無い
--      → EXECUTE は authenticated のみ（PUBLIC / anon / service_role から剥がす）
--
--    署名と引数名（message_id）は変えない（Mobile が {'message_id': ...} で渡すため）。
--    戻り値・言語（plpgsql）・揮発性（既定の VOLATILE）・SECURITY DEFINER / owner postgres も
--    維持する（5.6 と同じく実行権限のモデルは変えない）。
--
--    送信者条件（m.sender_id = auth.uid()）を足す理由:
--      - 是正前は、呼べる人なら誰でも（anon を含む）任意のメッセージ ID について「作成から
--        5 分以内か」を知ることができた（5.6 のフォローアップ候補）。SECURITY DEFINER なので
--        messages の RLS も効いていなかった
--      - 実際にメッセージを編集できるのは送信者だけ（RLS ポリシー "Users can edit own messages
--        within 5 minutes" が sender_id = auth.uid() を要求する）。送信者以外に false を返すのは
--        ポリシーとも関数名（編集できるか）とも一致する
--      - Mobile は常に自分の送信メッセージについて呼ぶので、Mobile の挙動は変わらない
--      - auth.uid() が NULL（service_role・postgres・JWT クレーム無し）のときはどの行にも
--        一致せず false を返す
--      - 送信者以外には「自分のではない」「存在しない」「5 分を過ぎた」のどれも同じ false に
--        なり、区別できない（他人のメッセージの存在確認や作成時刻の推定に使わせない）
--
--    search_path は空文字に固定し、テーブルは完全修飾（public.messages）で書く
--    （auth.uid() は元から修飾済み。auth.uid() 自身の本文も組み込み関数しか使わない）。
--
--    anon は GRANT 層で止める:
--      本文だけで見ると、顧客のクレーム（sub = 顧客 UUID）を持つ合成された anon セッションは
--      その顧客本人として扱われ、その顧客の送信メッセージについて判定できてしまう。実際の
--      anon キーのリクエストは sub を持たないので false になるが、GRANT 層が唯一の防壁になる
--      ケースがあるため、anon の EXECUTE は剥がしたままにすること（lessons.md 5.6 の知見と同じ）。
--    Advisor の 0029_authenticated_security_definer_function_executable（WARN）は
--    この関数では意図どおり残る。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_edit_message(message_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  msg_created_at TIMESTAMPTZ;
BEGIN
  -- 判定するのは呼び出し元自身の送信メッセージだけ（理由は migration の
  -- 20260923000000_harden_function_search_path.sql セクション 1 のコメント参照）
  SELECT m.created_at INTO msg_created_at
  FROM public.messages m
  WHERE m.id = message_id
    AND m.sender_id = auth.uid();

  IF msg_created_at IS NULL THEN
    RETURN false;
  END IF;

  RETURN (NOW() - msg_created_at) < INTERVAL '5 minutes';
END;
$function$;

COMMENT ON FUNCTION public.can_edit_message(uuid) IS
  '呼び出したユーザー自身の送信メッセージ（sender_id = auth.uid()）で、作成から5分以内か（編集できるか）を判定する。'
  '送信者以外・存在しない ID・5分経過はいずれも false で区別しない。'
  '呼び出しは Mobile の editMessage（message_repository.dart）。EXECUTE は authenticated のみ。'
  '仕様: docs/tasks/IMPLEMENTATION_TASKS.md 5.10 / supabase/migrations/20260923000000_harden_function_search_path.sql';

-- EXECUTE を authenticated のみに限定
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon /
--   service_role への EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.can_edit_message(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_edit_message(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.can_edit_message(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.can_edit_message(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. updated_at 更新用のトリガー関数 3 本
--    update_updated_at_column() / update_sessions_updated_at()（20251230131753）と
--    update_trainer_schedules_updated_at()（20260216221905）。いずれも INVOKER の plpgsql で、
--    本体は NEW.updated_at = NOW()（または now()）; RETURN NEW; だけ。
--
--    参照しているトリガー（リモートの dump と fresh DB で同一）:
--      - update_updated_at_column: exercise_records / meal_records / messages / sleep_records /
--        weight_records の set_updated_at、alerts / app_config / notification_preferences /
--        payments / trainer_billing / trainers の set_updated_at_<テーブル名>
--      - update_sessions_updated_at: sessions の trigger_update_sessions_updated_at
--      - update_trainer_schedules_updated_at: trainer_schedules の
--        trigger_update_trainer_schedules_updated_at
--      （storage.update_updated_at_column は storage スキーマの別関数で、対象外）
--
--    search_path = '' が安全な理由:
--      本体が使うのは NEW と組み込みの now() だけで、テーブルも関数も名前で引かない。
--      DML もしないので、他のトリガーへ空の search_path が波及することも無い
--
--    EXECUTE をすべて剥がしてよい理由（トリガー関数 6 本共通。セクション 3・4 も同じ）:
--      - PostgreSQL がトリガー関数の EXECUTE を確認するのは CREATE TRIGGER の時だけで、
--        トリガーが発火する時には確認しない。したがって authenticated / service_role / anon が
--        対象テーブルに INSERT / UPDATE しても、トリガーはこれまでどおり発火する
--      - トリガー関数を直接呼ぶ者はいない（呼び出し元の全数調査で RPC・cron・Edge Function・
--        他の SQL からの呼び出しは無し）。仮に直接呼んでも、ACL の確認を通った後で
--        "trigger functions can only be called as triggers"（0A000）で失敗する
--      - 今後の migration で update_updated_at_column を別テーブルのトリガーに使い回す場合も、
--        migration はオーナー postgres として実行されるので CREATE TRIGGER は通る
--      → GRANT は書かず、オーナー postgres だけが EXECUTE を持つ状態にする
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.update_updated_at_column() SET search_path = '';
ALTER FUNCTION public.update_sessions_updated_at() SET search_path = '';
ALTER FUNCTION public.update_trainer_schedules_updated_at() SET search_path = '';

-- EXECUTE をオーナー（postgres）のみに限定。GRANT は書かない
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon /
--   authenticated / service_role への EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.update_updated_at_column() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_updated_at_column() FROM anon;
REVOKE ALL ON FUNCTION public.update_updated_at_column() FROM authenticated;
REVOKE ALL ON FUNCTION public.update_updated_at_column() FROM service_role;

REVOKE ALL ON FUNCTION public.update_sessions_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_sessions_updated_at() FROM anon;
REVOKE ALL ON FUNCTION public.update_sessions_updated_at() FROM authenticated;
REVOKE ALL ON FUNCTION public.update_sessions_updated_at() FROM service_role;

REVOKE ALL ON FUNCTION public.update_trainer_schedules_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_trainer_schedules_updated_at() FROM anon;
REVOKE ALL ON FUNCTION public.update_trainer_schedules_updated_at() FROM authenticated;
REVOKE ALL ON FUNCTION public.update_trainer_schedules_updated_at() FROM service_role;

-- -----------------------------------------------------------------------------
-- 3. call_parse_message_tags()
--    messages の INSERT / content の UPDATE を Edge Function parse-message-tags へ送る Webhook の
--    トリガー関数。最新定義は #89 の 20260922000100_secure_parse_message_tags_webhook.sql
--    （送信先 URL と apikey を Vault から読み、Vault が揃っていなければ送らない。SECURITY DEFINER /
--    SET search_path = '' / EXECUTE はオーナーのみ）。リモートも fresh DB（今の develop）も
--    この定義である。
--
--    参照しているトリガー（リモートと fresh DB で同一）:
--      - messages の on_message_insert（AFTER INSERT）と on_message_update
--        （AFTER UPDATE OF content）
--
--    本 migration での扱い（リモートでも fresh DB でも no-op）:
--      - search_path も EXECUTE も、#89 が本 migration の方針どおりに設定済み。セクション 0 の
--        ガードは (b)（search_path 固定済み）で受け入れ、NOTICE を 1 件出す
--      - 下の ALTER は同じ値の再設定、REVOKE は既に無い権限の剥奪で、どちらも状態を変えない。
--        それでも残すのは、9 本の最終状態（search_path '' とオーナーのみの EXECUTE）を本 migration
--        だけを読めば確かめられるようにするため。本体・SECURITY DEFINER・COMMENT には触れない
--
--    空の search_path での動作（#89 の本体について）:
--      - 本体は vault.decrypted_secrets と net.http_post をスキーマ修飾し、ほかは NEW / OLD /
--        TG_OP と組み込み（jsonb_build_object / coalesce / rtrim / format と jsonb の || 演算子）だけ
--      - net.http_post（pg_net）自身が呼び出し側の search_path に依存しないこと:
--          - リモートの pg_net は 0.14.0 でローカルと同じ（2026-09-23 に MCP の読み取り専用
--            SELECT で確認）。リモートの net.http_post は proconfig が NULL（ローカルのイメージでは
--            SET search_path = net 付き）なので、呼び出し側の search_path（ここでは ''）のまま
--            動くが、0.14.0 の本体は内部の名前を net.* に修飾している
--          - 実際に #89 の適用後、リモートの call_parse_message_tags は search_path '' で
--            net.http_post を呼んでおり、#89 のオーナーが本番でタグ付きメッセージの E2E（記録の
--            作成）を確認済み。Webhook の経路は本番で実証されている
--      - net.http_post が INSERT する net.http_request_queue にトリガーは無いので、空の
--        search_path が他の関数へ波及することも無い
--
--    EXECUTE がオーナーのみでよい理由は、セクション 2 の「EXECUTE をすべて剥がしてよい理由」と
--    同じ（メッセージを INSERT / UPDATE する authenticated の操作でもトリガーは発火する）。
--    SECURITY DEFINER だが anon / authenticated に EXECUTE が無いので、Advisor の 0028 / 0029 は
--    出ない
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.call_parse_message_tags() SET search_path = '';

-- EXECUTE をオーナー（postgres）のみに限定。GRANT は書かない
REVOKE ALL ON FUNCTION public.call_parse_message_tags() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.call_parse_message_tags() FROM anon;
REVOKE ALL ON FUNCTION public.call_parse_message_tags() FROM authenticated;
REVOKE ALL ON FUNCTION public.call_parse_message_tags() FROM service_role;

-- -----------------------------------------------------------------------------
-- 4. enforce_client_limit() / enforce_client_note_session_consistency()
--    BEFORE トリガーで業務制約を強制する SECURITY DEFINER のトリガー関数:
--      - enforce_client_limit（20260712100000）: プラン別の顧客数上限。clients の
--        enforce_client_limit_trigger（BEFORE INSERT OR UPDATE OF trainer_id）から呼ばれる。
--        上限到達時は CLIENT_LIMIT_REACHED（P0001）
--      - enforce_client_note_session_consistency（20260906000100）: client_notes.session_id が
--        指すセッションの顧客・トレーナーとの一致。client_notes の
--        enforce_client_note_session_consistency_trigger（BEFORE INSERT OR UPDATE）から
--        呼ばれる。不一致時は NOTE_SESSION_MISMATCH（P0001）
--    Advisor の 0011 の対象ではない（search_path は 'public', 'pg_temp' に固定済み）が、
--    0028（anon が SECURITY DEFINER 関数を実行できる）と 0029（authenticated が実行できる）の
--    対象だった。
--
--    search_path を 'public', 'pg_temp' から '' に変える理由（追加のハードニング）:
--      - 2 本とも SECURITY DEFINER（定義者 postgres の権限で RLS を跨いで読む）なので、
--        5.6 の 4 本と揃えて空文字にする
--      - 本体は public.trainers / public.clients / public.sessions を完全修飾で参照し、
--        それ以外は組み込み（count / format / now / COALESCE 等）だけなので、空の
--        search_path でもそのまま動く
--      - SELECT しかしないので、空の search_path が他のトリガーへ波及することも無い
--
--    pg_temp の位置についての理論上のトレードオフ（ヘッダーの「共通」参照）:
--      旧設定 'public', 'pg_temp' は pg_temp を明示的に「最後」に置いていたので、一時スキーマの
--      型が組み込みの型を差し替える余地が無かった。'' では pg_temp が関係名と型名の検索で
--      「先頭」になる。関係名はすべてスキーマ修飾済みなので関係ないが、DECLARE の text /
--      timestamptz / uuid（enforce_client_limit の integer / bigint はキーワードなので常に
--      pg_catalog）は、同じセッションに同名の一時型があればそちらに解決される。これを使うには
--      INSERT / UPDATE と同じセッションで一時型を作る DDL が要り、anon / authenticated /
--      service_role（PostgREST 経由）からは成立しないため、5.6 / #89（5.7）/ Supabase の推奨との
--      一貫性を優先して '' にする。一方で旧設定の public を外すことで、public に同名の関数・
--      型が置かれた場合の差し替えの余地は無くなる
--
--    EXECUTE はすべて剥がす（理由はセクション 2 の「EXECUTE をすべて剥がしてよい理由」）。
--    これで 2 本の 0028 と 0029 が解消する。顧客の登録・担当替え（clients の INSERT / trainer_id の
--    UPDATE）とカルテの保存（client_notes の INSERT / UPDATE）では、これまでどおりトリガーが
--    発火して上限・一致を強制する
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.enforce_client_limit() SET search_path = '';
ALTER FUNCTION public.enforce_client_note_session_consistency() SET search_path = '';

-- EXECUTE をオーナー（postgres）のみに限定。GRANT は書かない
REVOKE ALL ON FUNCTION public.enforce_client_limit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_client_limit() FROM anon;
REVOKE ALL ON FUNCTION public.enforce_client_limit() FROM authenticated;
REVOKE ALL ON FUNCTION public.enforce_client_limit() FROM service_role;

REVOKE ALL ON FUNCTION public.enforce_client_note_session_consistency() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_client_note_session_consistency() FROM anon;
REVOKE ALL ON FUNCTION public.enforce_client_note_session_consistency() FROM authenticated;
REVOKE ALL ON FUNCTION public.enforce_client_note_session_consistency() FROM service_role;

-- -----------------------------------------------------------------------------
-- 5. get_last_messages_for_trainer(uuid) / get_unread_counts_for_trainer(uuid)
--    トレーナーのメッセージ一覧用の RPC（LANGUAGE sql STABLE、INVOKER）:
--      - get_last_messages_for_trainer（20260223045727）: 相手ごとの最新メッセージ
--      - get_unread_counts_for_trainer（20260223083354）: 担当顧客ごとの未読数
--
--    呼び出し元:
--      - Web のみ: fit-connect/src/lib/supabase/getLastMessagesForClients.ts /
--        getUnreadCounts.ts から、ログイン中のトレーナー（authenticated）として呼ぶ
--
--    search_path = '' が安全な理由:
--      本体は public.messages / public.clients を完全修飾で参照し、それ以外は組み込みの
--      count と演算子・CASE / DISTINCT ON だけ。DML もしない
--
--    SET 句によるインライン展開の停止:
--      SET 句を持つ SQL 関数はプランナーにインライン展開されなくなる。2 本は PostgREST から
--      RPC として単独で呼ばれるだけで、他のクエリに埋め込んで最適化される使い方はしないため
--      影響は無い（関数内のクエリ自体の計画は変わらない）
--
--    EXECUTE は変えない（本 migration の範囲外）:
--      INVOKER なので、返る行は呼び出し元のロールに対する messages / clients の RLS が決める。
--      Advisor の 0028 / 0029 の対象でもない。ACL（PUBLIC / anon / authenticated /
--      service_role に EXECUTE）には手を付けない
-- -----------------------------------------------------------------------------
ALTER FUNCTION public.get_last_messages_for_trainer(uuid) SET search_path = '';
ALTER FUNCTION public.get_unread_counts_for_trainer(uuid) SET search_path = '';
