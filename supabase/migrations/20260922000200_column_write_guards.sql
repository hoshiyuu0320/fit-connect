-- =============================================================================
-- Migration: column_write_guards
-- 目的: public.clients / public.messages に「列単位」の書き込みガードを入れる。
--   行レベルの RLS（誰の行か）はそのまま残し、その上に「その行のどの列を、
--   誰が、どんな値に書いてよいか」を DB 側で強制する層を追加する。
--
-- テスト: supabase/tests/column_write_guards_test.sql
--   （禁止系・正規経路の回帰・カタログ確認。BEGIN...ROLLBACK で DB に何も残さない）
--
-- -----------------------------------------------------------------------------
-- 背景（2026-09-13 にリモートで読み取り専用の pg_policies 照会により確認）
-- -----------------------------------------------------------------------------
-- 行レベルの WITH CHECK は所有者列しか縛っておらず、それ以外の列は全て書けた。
-- さらに 20251230131753_remote_schema.sql の GRANT ALL により anon / authenticated /
-- service_role の全員がテーブル単位の INSERT / UPDATE / DELETE を持ち、REVOKE は
-- どの migration にも無かった。穴は次の 4 つ:
--
--   穴1 clients_update_own（FOR UPDATE TO authenticated
--       USING / WITH CHECK (client_id = auth.uid())）
--       → 顧客が自分の行の trainer_id を書き換えられる（任意のトレーナーへの紐づけ・
--         担当外し）。created_at も書ける（'-infinity' 等。Phase 9 の
--         feature/client-alerts は clients.created_at を登録日として使う）。
--         トレーナーが決める列（目標体重・目的・身長・目標期限など）も全て書ける。
--   穴2 messages の INSERT ポリシー "Users can send messages" /
--       "送信者が自身のみ書き込み可"（重複・TO PUBLIC。WITH CHECK (sender_id = auth.uid())
--       のみ）
--       → receiver_id（担当外の相手・他人の会話）/ receiver_type / sender_type
--         （トレーナー詐称）/ read_at（既読偽装）/ created_at（時系列の改ざん）を偽装して送れる。
--   穴3 messages の UPDATE ポリシー "Users can edit own messages within 5 minutes"
--       （TO PUBLIC。USING (sender_id = auth.uid() AND now() - created_at < 5 分)
--       WITH CHECK (sender_id = auth.uid())）
--       → 送信者が 5 分以内なら全列を書き換えられる。receiver_id の付け替え、
--         read_at の偽装、created_at を未来にして編集可能時間を自分で延長することまで可能。
--   穴4 messages の UPDATE ポリシー "Receivers can mark messages as read"
--       （TO PUBLIC。USING / WITH CHECK (receiver_id = auth.uid())）
--       → 受信者が「既読化」の名目で content / tags / metadata / image_urls を含む
--         全列を書き換えられる（相手の発言の改ざん）。
--
-- -----------------------------------------------------------------------------
-- 正規の書き込み経路の全数調査（2026-09-22 grep 全数。パスはリポジトリルート相対）
-- -----------------------------------------------------------------------------
-- [Mobile]（ロール authenticated、auth.uid() = clients.client_id の顧客本人）
--   clients
--   - C1 fit-connect-mobile/lib/features/auth/providers/registration_provider.dart:177
--        upsert(onConflict: 'client_id') {client_id(= auth uid), trainer_id(QR / 招待の
--        トレーナー), name, email, age(任意), gender(任意)}。初回は行が無い状態で作成。
--        部分失敗後のリトライで既存行に当たることがあり、その場合も「同じ trainer_id」を送る。
--        PostgREST は INSERT ... ON CONFLICT (client_id) DO UPDATE SET
--        <ペイロードの全列> = EXCLUDED.<列> を発行する。
--   - C2 同 registration_provider.dart:203 update {profile_image_url}（アップロード後のパス）
--   - C3 同 registration_provider.dart:211 update {profile_image_url}（Google アバター URL）
--   - C4 fit-connect-mobile/lib/features/auth/data/client_repository.dart:39 update {name}
--   - C5 同 client_repository.dart:52 update {profile_image_url}
--   - C6 fit-connect-mobile/lib/features/onboarding_flow/data/onboarding_repository.dart:28
--        update {onboarding_completed_at}（端末時計の UTC ISO 文字列）
--   - C7 fit-connect-mobile/lib/services/notification_service.dart:409 update {fcm_token}
--   - C8 同 notification_service.dart:441 update {fcm_token: null}（ログアウト時）
--   - C9 同 notification_service.dart:520 update {fcm_token}（トークンリフレッシュ）
--     （C2〜C9 はすべて .eq('client_id', uid)）
--   - C10/C11 fit-connect-mobile/lib/features/goals/data/goal_repository.dart:75 updateGoal
--        {initial_weight, target_weight, goal_deadline, goal_description, goal_set_at,
--        goal_achieved_at} / :87 clearGoalAchievement {goal_achieved_at: null}
--        → どこからも呼ばれていない死にコード（コメント上も「トレーナー側で使用」）。
--          goal_provider.dart が呼ぶのは読み取り系と RPC（calculate_achievement_rate /
--          check_goal_achievement。どちらも clients を SELECT するだけ）のみ。
--   messages
--   - M1 fit-connect-mobile/lib/features/messages/data/message_repository.dart:116
--        insert {sender_id(uid), receiver_id(= 自分の clients.trainer_id),
--        sender_type:'client', receiver_type:'trainer', content, image_urls, tags,
--        reply_to_message_id, is_edited:false, metadata(任意: {meal_estimation:{...}})}
--        + .select().single()。ワークアウト完了の送信は image_urls:null /
--        reply_to_message_id:null / tags:['#運動:完了']。
--   - M2 同 message_repository.dart:151 update {content, tags(null あり), is_edited:true,
--        edited_at: DateTime.now().toIso8601String()} .eq('id')（5 分以内。edited_at は
--        オフセット無しの端末ローカル時刻 = UTC として解釈され 9 時間ずれる既存バグ）。
--   - M3 同 message_repository.dart:168 rpc('mark_messages_as_read', {p_other_user_id})
--        SECURITY DEFINER（所有者 postgres）。リモートに直接作られていた関数を
--        20260913000500 が追認して migration に取り込み、20260913000510 が
--        SET search_path = ''・完全修飾・EXECUTE は authenticated のみ に固めた。
--        どちらも本 migration の base に含まれ、リモートにも適用済み
--        （新規 DB でも必ず存在する）。本体:
--          UPDATE public.messages SET read_at = now()
--          WHERE receiver_id = auth.uid() AND sender_id = p_other_user_id AND read_at IS NULL;
--   - M4 同 message_repository.dart:188 delete → 死にコード（DELETE ポリシーも無い）。
-- [Web]（トレーナー）
--   - fit-connect/src/lib/supabase/markMessagesAsRead.ts:9（browser client = authenticated。
--       fit-connect/src/app/(user_console)/message/page.tsx から呼ばれる）
--       update {read_at: new Date().toISOString()（ブラウザ時計）}
--       .eq('receiver_id', trainerUid).eq('sender_id', clientId).is('read_at', null)
--       → Web で唯一の authenticated による直接書き込み。
--   - fit-connect/src/app/api/messages/send/route.ts:32（supabaseAdmin = service_role）
--       insert {sender_id, receiver_id, content, sender_type:'trainer',
--       receiver_type:'client', image_urls?, reply_to_message_id?}
--   - fit-connect/src/app/api/messages/edit/route.ts:48（service_role）
--       update {content, is_edited:true, edited_at, updated_at}
--   - fit-connect/src/lib/supabase/updateClient.ts:30（service_role。
--       /api/clients/[client_id] から）update clients {age, gender, occupation, height,
--       target_weight, purpose, goal_description, goal_deadline}
--   - fit-connect/src/lib/supabase/sendMessage.ts:13（browser client の messages insert）
--       → どこからも import されていない死にコード。仮に復活しても
--         「トレーナー → 自分の顧客」の形なら本ガードを通る。
--   - トレーナーが clients を書く RLS ポリシーは無く、Web は clients を INSERT しない。
-- [Edge Functions]（すべて service_role）
--   - supabase/functions/parse-message-tags/index.ts:66 update messages {tags}（バックフィル）
--   - supabase/functions/_shared/push.ts:310 update clients {fcm_token: null}
--       （無効になった旧 fcm_token の掃除。parse-message-tags 等から呼ばれる）
--   - supabase/functions/delete-account/index.ts:136 / :146 delete clients / messages
--       （DELETE は本ガードの対象外）
-- [SQL / トリガー]
--   - clients.enforce_client_limit_trigger（BEFORE INSERT OR UPDATE OF trainer_id、
--       SECURITY DEFINER、書き込みなし）
--   - messages.set_updated_at（BEFORE UPDATE、NEW.updated_at = now()）
--   - messages.on_message_insert / on_message_update（AFTER、call_parse_message_tags。
--       20260922000100 以降は SECURITY DEFINER で、Vault の project_url / secret_key が
--       揃う環境でだけ pg_net で parse-message-tags へ POST。messages は書かない）
--   - clients / messages を書く SQL 関数は mark_messages_as_read（20260913000500 /
--     000510）だけ。20260829000200 の UPDATE は migration 実行時（postgres）の
--     一回きりのデータ移行。
--
-- -----------------------------------------------------------------------------
-- 列ごとの判断
-- -----------------------------------------------------------------------------
-- clients（エンドユーザー = authenticated の顧客本人・自分の行）
--   | 列                                          | エンドユーザー                      | service_role / DEFINER |
--   |---------------------------------------------|-------------------------------------|------------------------|
--   | client_id                                   | INSERT（= auth.uid()、RLS）/        | 任意                   |
--   |                                             | UPDATE は同じ値のみ                 |                        |
--   | trainer_id                                  | INSERT（登録）/ UPDATE は同じ値のみ | 任意                   |
--   |                                             | （登録リトライ）。変更は管理者のみ  |                        |
--   | created_at                                  | 不可（DB 既定 now()。INSERT 時強制）| 任意                   |
--   | name, email, age, gender                    | INSERT + UPDATE（本人申告の         | 任意                   |
--   |                                             | プロフィール。登録 upsert・改名）   |                        |
--   | profile_image_url, fcm_token,               | UPDATE のみ                         | 任意                   |
--   | onboarding_completed_at                     |                                     |                        |
--   | occupation, height, target_weight, purpose, | 不可（トレーナーが決める列。        | 任意                   |
--   | goal_description, goal_deadline,            | supabaseAdmin 経由で書く）          |                        |
--   | initial_weight, goal_set_at,                |                                     |                        |
--   | goal_achieved_at, line_user_id              |                                     |                        |
--
-- messages
--   | 列                    | エンドユーザーの INSERT        | 送信者の UPDATE          | 受信者の UPDATE       | service_role / DEFINER |
--   |                       |                                | （RLS: 自分の・5 分以内）|                       |                        |
--   |-----------------------|--------------------------------|--------------------------|-----------------------|------------------------|
--   | id                    | 既定値                         | 不変                     | 不変                  | 任意                   |
--   | sender_id             | = auth.uid() 必須              | 不変                     | 不変                  | 任意                   |
--   | sender_type           | 呼び出し元に一致: clients 行が | 不変                     | 不変                  | 任意                   |
--   |                       | あれば 'client'、trainers 行が |                          |                       |                        |
--   |                       | あれば 'trainer'。他は拒否     |                          |                       |                        |
--   | receiver_id /         | 呼び出し元の相手のみ: 顧客 →   | 不変                     | 不変                  | 任意                   |
--   | receiver_type         | (自分の trainer_id, 'trainer') |                          |                       |                        |
--   |                       | / トレーナー → (trainer_id =   |                          |                       |                        |
--   |                       | 自分の顧客, 'client')          |                          |                       |                        |
--   | content               | 可                             | 可                       | 不可                  | 任意                   |
--   | tags                  | 可                             | 可                       | 不可                  | 任意（バックフィル）   |
--   | image_urls, metadata  | 可                             | 不可                     | 不可                  | 任意                   |
--   | reply_to_message_id   | 可。ただし同じ会話（呼び出し元 | 不可                     | 不可                  | 任意                   |
--   |                       | と受信者の間）のメッセージのみ |                          |                       |                        |
--   | created_at            | now() に強制                   | 不変                     | 不変                  | 任意                   |
--   | read_at               | NULL に強制                    | 不可                     | NULL → 値 の 1 回のみ。| 任意                   |
--   |                       |                                |                          | 値はサーバー now() に | （mark_messages_as_read）|
--   |                       |                                |                          | 強制。取り消し・付け  |                        |
--   |                       |                                |                          | 替え不可              |                        |
--   | is_edited / edited_at | false / NULL に強制            | content か tags が変わっ | 不可                  | 任意                   |
--   |                       |                                | たら true / now() に強制 |                       |                        |
--   |                       |                                | （変わらなければ据え置き）|                       |                        |
--   | updated_at            | now() に強制                   | 無視（set_updated_at が  | 無視                  | 任意                   |
--   |                       |                                | 上書き）                 |                       |                        |
--
--   「送信者の UPDATE」列が使えるのは作成から 5 分以内（now() - OLD.created_at < 5 分）だけ。
--   RLS の "Users can edit own messages within 5 minutes" と同じ式をガード側でも判定する。
--   通常の送信者は 5 分を過ぎると RLS の USING で行ごと除外されトリガーまで届かないので、
--   この条件が効くのは自分宛て（sender_id = receiver_id）の行だけ:
--     UPDATE ポリシーは PERMISSIVE の OR 結合で、"Receivers can mark messages as read"
--     （USING receiver_id = auth.uid()）には時間制限が無い。送信者の許可列を
--     sender_id の一致だけで与えると、5 分を過ぎた自分宛てメッセージの本文を
--     受信者ポリシー経由で編集できてしまう（編集可能時間のすり抜け）。
--     → 5 分を過ぎた自分宛ては「受信者」としての既読化（read_at: NULL → now()）のみ可。
--       5 分以内なら送信者として content / tags も編集できる（is_edited / edited_at は強制値）。
--   自分宛ての行はエンドユーザーには作れない（INSERT ガードの「相手のみ」で拒否）。
--   service_role が作った行・本 migration より前の既存行にだけ存在しうる。
--
-- -----------------------------------------------------------------------------
-- 方式
-- -----------------------------------------------------------------------------
-- clients = 列 GRANT + 小さなトリガー
--   書き手のロールが分かれている（顧客本人 = authenticated、トレーナー側の更新 =
--   service_role）ため、列単位の GRANT で「authenticated が書ける列」を許可リスト化できる。
--   house precedent は 20260712000000_add_billing_foundation.sql §4（trainers の列 GRANT）。
--   列 GRANT は「列を書けるか」しか表現できず「同じ値なら可」を表せないため、
--   client_id / trainer_id / created_at の不変条件だけを BEFORE トリガーで補う。
--   （登録 upsert の衝突経路は client_id / trainer_id を同じ値で SET するので、
--     GRANT で UPDATE 列権限を外すことはできない）
-- messages = トリガー
--   送信者も受信者も同じ authenticated ロールのため、列 GRANT では両者を区別できない。
--   BEFORE INSERT / BEFORE UPDATE トリガーで「呼び出し元がこの行の送信者か受信者か」を
--   判定し、許可された列以外の変更を拒否する。UPDATE は許可リスト方式
--   （to_jsonb(NEW) - 許可列 と to_jsonb(OLD) - 許可列 の比較）で実装し、
--   今後 messages に追加される列も既定で保護される。
-- current_user で判定し auth.role() を使わない理由
--   PostgREST はリクエストごとに SET ROLE authenticated / anon / service_role する。
--   SECURITY DEFINER 関数の中では current_user が所有者（postgres）に変わるため、
--   service_role と DEFINER 経路（mark_messages_as_read）は current_user だけで
--   素通しにできる。auth.role() は JWT クレームを読むだけなので DEFINER 関数の中でも
--   'authenticated' のままで、DEFINER 経路まで制限してしまう。
-- SECURITY INVOKER + SET search_path = '' の理由
--   DEFINER にすると current_user が関数所有者になり、エンドユーザーの判定自体が
--   できなくなる（INVOKER は必須）。search_path は空にして全オブジェクトを
--   スキーマ修飾する（public.* / auth.uid()。組み込みは pg_catalog が暗黙に先頭）。
--   20260913000510 以降 mark_messages_as_read は search_path = '' で動くため、
--   そこから発火しても名前解決が変わらないようにしておく。
-- 参照系の問い合わせは呼び出し元の RLS の下で実行し、見えなければ拒否（fail closed）
--   自分の clients 行（Clients can view own profile）/ trainers 行（trainers_select_all）
--   / トレーナーの担当顧客（トレーナー自身のクライアントだけ見れる）/ 返信先メッセージ
--   （messages の SELECT ポリシー）は、正規の呼び出し元からは既存の SELECT ポリシーで
--   必ず見える。見えないものは「相手ではない / 同じ会話ではない」として拒否する。
-- anon は正規の書き手ではない
--   anon の INSERT / UPDATE（messages は DELETE も）の GRANT を剥奪するので、通常は
--   権限チェックで "permission denied" になりトリガーまで到達しない。トリガー側でも
--   ANON_WRITE_FORBIDDEN で拒否し、将来の migration や Supabase の既定権限で
--   GRANT ALL が anon に戻った場合でも「anon + 顧客の JWT クレーム」を閉じたままにする。
-- エラー
--   RAISE EXCEPTION '<固定コード>' USING ERRCODE = '42501'（insufficient_privilege →
--   PostgREST は 403）。DETAIL に列名・理由、HINT に正規の書き方を入れる。固定コード:
--     CLIENTS_PROTECTED_COLUMN / MESSAGES_SENDER_MISMATCH / MESSAGES_INVALID_SENDER_TYPE /
--     MESSAGES_RECEIVER_NOT_COUNTERPART / MESSAGES_REPLY_OUTSIDE_CONVERSATION /
--     MESSAGES_COLUMN_NOT_UPDATABLE / MESSAGES_READ_AT_IMMUTABLE / ANON_WRITE_FORBIDDEN
--   メッセージ文字列は固定（クライアント・テストはこの文字列で判定する）。変更禁止。
-- RLS ポリシーには一切触れない（行レベルの層として残す）。messages の DELETE ポリシーも
--   追加しない。
-- 権限の最終状態を migration の末尾で検証する（§8）
--   REVOKE は「実行ロール自身が付与した権限」しか外さない（別の grantor が付けた GRANT は
--   残り、WARNING が出るだけでエラーにならない）。リモートはオーナーが手動で適用するため、
--   剥奪が黙って空振りしてトレーナー所有列が書けるまま完了する事態を許さない。
--   authenticated の clients 列権限が許可リストと完全一致しない / anon に書き込み権限が
--   残っている / ガードトリガーが無い・無効 のいずれかなら COLUMN_GUARD_PRIVILEGE_CHECK_FAILED
--   （P0001）で migration 全体を中断（ロールバック）する。
--
-- -----------------------------------------------------------------------------
-- 既知の限界（許容済み）: messages UPDATE の jsonb 比較の盲点
-- -----------------------------------------------------------------------------
--   UPDATE ガードは to_jsonb(行) の比較で「変わったか」を判定するため、JSON にすると
--   同じ表現になる変更は検出できない（エラーにならず素通りする）:
--     - metadata の SQL NULL ⇔ JSON の 'null'::jsonb（行の JSON ではどちらも null）
--     - text[] の添字の下限（image_urls / tags を '[0:1]={a,b}' にしても JSON は ["a","b"]）
--     - metadata 内の数値の scale（jsonb の比較は値で行うため 500 と 500.0 は等しい）
--   セキュリティ上の影響は無い: PostgREST / Realtime が返す API 上の形は変更前と同一で、
--   アプリ・Edge Function・SQL のどこも image_urls[n] の添字アクセスや
--   metadata IS NULL を読んでいない（2026-09-22 grep で確認）。内容そのもの
--   （本文・画像パス・タグ・metadata の値）を変える更新は必ず検出される。
--
-- -----------------------------------------------------------------------------
-- 挙動の変化
-- -----------------------------------------------------------------------------
--   - 顧客は自分の clients.trainer_id を変更できなくなる。
--     20260712100000_enforce_client_limit.sql のヘッダーは「clients_update_own により本人が
--     trainer_id を書き換え可能 = トレーナー乗り換え」を意図的な仕様として書いているが、
--     乗り換えを行う UI はどこにも無く、同じ経路で任意のトレーナーへの紐づけ・担当外しが
--     できてしまう（穴1）。今後トレーナーの付け替えは service_role（管理操作）のみとする。
--     （同 migration 自体は編集しない。enforce_client_limit_trigger は service_role による
--       付け替えでも従来どおり上限を強制する）
--   - Mobile の編集（M2）が送る端末ローカル時刻の edited_at と、Web の既読化
--     （markMessagesAsRead.ts）が送るブラウザ時計の read_at は、サーバーの now() に
--     置き換わる（M2 の 9 時間ずれは DB 側で解消される）。送信者が content / tags を
--     変えない UPDATE（同じ値の再送）は is_edited / edited_at を据え置く no-op になる。
--   - 20260914000100_client_activity_snapshot.sql（public.client_activity_snapshot）の
--     コメントと COMMENT ON FUNCTION にある「Web の既読はブラウザの時計で書く」
--     「送信者が receiver_id と read_at を自由に書ける」という記述は、本 migration の
--     適用後は古くなる（Web の read_at もサーバー now() になり、エンドユーザーは
--     INSERT で read_at / receiver_id を偽装できず、送信者は read_at を書けない）。
--     同関数の絞り込み（receiver_type = 'client' / 今の担当トレーナーが送った分だけ）は
--     適用前に書かれた既存行に対しては引き続き意味があり、害も無いのでそのまま残す。
--     同 migration 自体は編集しない。
--   - 自分宛て（sender_id = receiver_id）のメッセージは、作成から 5 分を過ぎると
--     本文・タグを編集できなくなる（従来は受信者ポリシー経由で無期限に編集できた）。
--     既読化（read_at: NULL → now()）は時間に関係なく可。
--   - messages INSERT 時の created_at / read_at / is_edited / edited_at / updated_at は
--     エンドユーザーが指定しても強制値になる（拒否ではなく黙って上書き）。
--   - anon の clients INSERT / UPDATE、messages INSERT / UPDATE / DELETE の GRANT を剥奪する。
--     これはカタログ cat7 1-B（anon の書き込み系 GRANT の REVOKE）の一部実現にあたる。
--     docs/tasks/IMPLEMENTATION_TASKS.md 5.1 では 1-B が [x] になっているが、実際に
--     REVOKE した migration は存在しなかった（本 migration は clients / messages のみ）。
--
-- -----------------------------------------------------------------------------
-- 互換性（現行のアプリビルドはすべてそのまま動く）
-- -----------------------------------------------------------------------------
--   - C1 登録 upsert: INSERT 列権限 (client_id, trainer_id, name, email, age, gender) で
--     初回作成できる。PostgREST の ON CONFLICT DO UPDATE SET は衝突しない初回でも
--     SET 句の全列に UPDATE 権限を要求するため、client_id / trainer_id にも UPDATE 列権限を
--     付与している。衝突経路（リトライ）は同じ client_id / trainer_id を SET するので
--     トリガーの「同じ値なら可」で通り、created_at は SET 句に無いため不変のまま。
--     DB 既定値（height 170 等）は INSERT 列に含まれないので従来どおり入る。
--   - C2〜C9: いずれも UPDATE 列権限の許可リスト内の列だけを書く。
--   - M1: 自分の trainer_id 宛て・sender_type 'client' / receiver_type 'trainer'・
--     返信先は同じ会話・is_edited:false はそのまま強制値と一致する。
--   - M2: 送信者の許可列（content / tags / is_edited / edited_at）のみを書く。
--   - M3 mark_messages_as_read: SECURITY DEFINER（所有者 postgres）の中では current_user が
--     postgres になるためガード対象外で、従来どおり read_at = now() を書ける。
--     20260913000510 でこの関数は search_path = '' になっているが、ガード関数は
--     自前の SET search_path = '' と完全修飾名で動くので影響を受けない。
--     （20260913000510 のヘッダーは「関数内で発火する messages のトリガー」として
--       set_updated_at / on_message_* を挙げている。本 migration 以降は
--       messages_guard_update もそこで発火するが、current_user = postgres の判定で
--       即 RETURN NEW するだけで、search_path = '' のままでも安全）
--   - Web markMessagesAsRead.ts: 受信者の許可列 read_at（NULL → 値）のみ。WHERE read_at
--     IS NULL 付きなので「既読の付け替え」にも当たらない。
--   - service_role（Web API Route / Edge Functions）はガード対象外、GRANT も変更しない。
--   - 読み取り（SELECT）と Realtime には影響しない。
--   - トリガー関数は発火時に EXECUTE 権限を必要としないため、ガード関数の EXECUTE は
--     PUBLIC / anon / authenticated から剥奪する（RPC 面に出さない）。
--   - BEFORE トリガーは名前順に発火する: clients_guard_protected_columns は
--     enforce_client_limit_trigger より先（顧客による付け替えは上限判定の前に拒否）、
--     messages_guard_update は set_updated_at より先（updated_at は比較対象から除外）。
--
-- -----------------------------------------------------------------------------
-- 適用順・冪等性
-- -----------------------------------------------------------------------------
--   - リモートは 20260922000100 まで適用済み（PR #89 = parse-message-tags の是正。develop には
--     f8646d5 としてマージ済み。PR #88 の 20260914000000〜000200、20260913000200〜000510 も
--     その前に適用済み）。本 migration は当初 20260922000000 で作成したが、#89 の 000100 が
--     先にリモートへ適用されたため、末尾に並ぶよう 20260922000200 に振り直した。この PR を
--     develop にマージした後に develop から push すれば、--include-all 無しで末尾に適用される。
--   - 冪等: CREATE OR REPLACE FUNCTION / DROP TRIGGER IF EXISTS → CREATE TRIGGER /
--     REVOKE → GRANT（テーブル単位の REVOKE は列単位の権限も剥がすので、再実行しても
--     列 GRANT の最終形に収束する）/ 末尾の検証 DO ブロックは読み取りのみ。
--     何度再実行しても同じ最終形になる。
--   - Supabase は各 migration をトランザクション内で実行する（途中失敗・§8 の検証失敗は
--     全体ロールバック）。
-- =============================================================================


-- =============================================================================
-- 1. clients: ガード関数 clients_guard_protected_columns()
-- =============================================================================
-- エンドユーザー（authenticated）だけを対象に:
--   INSERT → created_at を now() に強制（列 GRANT で指定自体できないが二重に守る）
--   UPDATE → client_id / trainer_id / created_at が OLD と異なれば拒否
--            （同じ値の SET は登録 upsert のリトライで必要なので許可）
-- それ以外の列の可否は §4 の列 GRANT が担う。

CREATE OR REPLACE FUNCTION public.clients_guard_protected_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_changed text[] := '{}';
BEGIN
  -- service_role / postgres / SECURITY DEFINER 関数（current_user = 所有者）は対象外
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- anon は clients の正規の書き手ではない（通常は GRANT 剥奪で権限チェックが先に落ちる）
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'ANON_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('table=%s.%s op=%s', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP),
            HINT    = 'anon ロールは clients に書き込めません。ログインしてから操作してください。';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_at := now();
    RETURN NEW;
  END IF;

  IF NEW.client_id IS DISTINCT FROM OLD.client_id THEN
    v_changed := v_changed || 'client_id'::text;
  END IF;
  IF NEW.trainer_id IS DISTINCT FROM OLD.trainer_id THEN
    v_changed := v_changed || 'trainer_id'::text;
  END IF;
  IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    v_changed := v_changed || 'created_at'::text;
  END IF;

  IF cardinality(v_changed) > 0 THEN
    -- メッセージ文字列 'CLIENTS_PROTECTED_COLUMN' は固定。変更禁止。
    RAISE EXCEPTION 'CLIENTS_PROTECTED_COLUMN'
      USING ERRCODE = '42501',
            DETAIL  = format('client_id=%s columns=%s', OLD.client_id,
                             array_to_string(v_changed, ', ')),
            HINT    = 'client_id / trainer_id / created_at は本人からは変更できません（同じ値の再送のみ可）。トレーナーの付け替えは管理者（service_role）が行います。';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.clients_guard_protected_columns() IS
  'clients の BEFORE INSERT OR UPDATE ガード（エンドユーザーのみ）。INSERT は created_at を now() に強制、UPDATE は client_id / trainer_id / created_at の変更を CLIENTS_PROTECTED_COLUMN（42501）で拒否（同じ値は可）。anon は ANON_WRITE_FORBIDDEN。他の列の可否は列 GRANT が担う。仕様: 20260922000200_column_write_guards.sql ヘッダー';


-- =============================================================================
-- 2. messages: ガード関数 messages_guard_insert()
-- =============================================================================
-- 判定順は sender_id → sender_type → 受信者（相手）→ 返信先。通ったら
-- システム列（created_at / read_at / is_edited / edited_at / updated_at）を強制する。
-- 参照系はすべて呼び出し元の RLS の下で実行し、見えなければ拒否（fail closed）。

CREATE OR REPLACE FUNCTION public.messages_guard_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_uid            uuid;
  v_own_trainer_id uuid;
BEGIN
  -- service_role / postgres / SECURITY DEFINER 関数（current_user = 所有者）は対象外
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- anon は messages の正規の書き手ではない（通常は GRANT 剥奪で権限チェックが先に落ちる）
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'ANON_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('table=%s.%s op=%s', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP),
            HINT    = 'anon ロールは messages に書き込めません。ログインしてから操作してください。';
  END IF;

  v_uid := auth.uid();

  -- 1. 送信者は本人のみ（RLS WITH CHECK より先に評価されるため固定コードで返す）
  IF v_uid IS NULL OR NEW.sender_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'MESSAGES_SENDER_MISMATCH'
      USING ERRCODE = '42501',
            DETAIL  = format('sender_id=%s auth.uid()=%s', NEW.sender_id,
                             coalesce(v_uid::text, 'NULL')),
            HINT    = 'sender_id には自分のユーザー ID を指定してください。';
  END IF;

  -- 2. sender_type は呼び出し元の実体に一致すること
  --    'client'  : 自分の clients 行がある（Clients can view own profile で見える）
  --    'trainer' : 自分の trainers 行がある（trainers_select_all で見える）
  IF NEW.sender_type = 'client' THEN
    SELECT c.trainer_id
      INTO v_own_trainer_id
      FROM public.clients c
     WHERE c.client_id = v_uid;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'MESSAGES_INVALID_SENDER_TYPE'
        USING ERRCODE = '42501',
              DETAIL  = format('sender_type=client but no clients row for %s', v_uid),
              HINT    = 'sender_type は自分の種別（顧客なら client、トレーナーなら trainer）を指定してください。';
    END IF;
  ELSIF NEW.sender_type = 'trainer' THEN
    IF NOT EXISTS (SELECT 1 FROM public.trainers t WHERE t.id = v_uid) THEN
      RAISE EXCEPTION 'MESSAGES_INVALID_SENDER_TYPE'
        USING ERRCODE = '42501',
              DETAIL  = format('sender_type=trainer but no trainers row for %s', v_uid),
              HINT    = 'sender_type は自分の種別（顧客なら client、トレーナーなら trainer）を指定してください。';
    END IF;
  ELSE
    RAISE EXCEPTION 'MESSAGES_INVALID_SENDER_TYPE'
      USING ERRCODE = '42501',
            DETAIL  = format('sender_type=%s is not allowed', coalesce(quote_literal(NEW.sender_type), 'NULL')),
            HINT    = 'sender_type は client または trainer のみ指定できます。';
  END IF;

  -- 3. 受信者は呼び出し元の相手のみ
  --    顧客       → (自分の clients.trainer_id, 'trainer')
  --    トレーナー → (trainer_id = 自分 の顧客, 'client')
  --                 （トレーナー自身のクライアントだけ見れる で見える）
  IF NEW.sender_type = 'client' THEN
    IF NEW.receiver_type IS DISTINCT FROM 'trainer'
       OR NEW.receiver_id IS DISTINCT FROM v_own_trainer_id THEN
      RAISE EXCEPTION 'MESSAGES_RECEIVER_NOT_COUNTERPART'
        USING ERRCODE = '42501',
              DETAIL  = format('client %s -> receiver_id=%s receiver_type=%s (expected %s / trainer)',
                               v_uid, NEW.receiver_id, NEW.receiver_type, v_own_trainer_id),
              HINT    = '顧客が送れるのは担当トレーナー宛て（receiver_type = trainer）のみです。';
    END IF;
  ELSE
    IF NEW.receiver_type IS DISTINCT FROM 'client'
       OR NOT EXISTS (
         SELECT 1 FROM public.clients c
          WHERE c.client_id = NEW.receiver_id
            AND c.trainer_id = v_uid
       ) THEN
      RAISE EXCEPTION 'MESSAGES_RECEIVER_NOT_COUNTERPART'
        USING ERRCODE = '42501',
              DETAIL  = format('trainer %s -> receiver_id=%s receiver_type=%s',
                               v_uid, NEW.receiver_id, NEW.receiver_type),
              HINT    = 'トレーナーが送れるのは自分の担当顧客宛て（receiver_type = client）のみです。';
    END IF;
  END IF;

  -- 4. 返信先は同じ会話（呼び出し元 ⇔ 受信者）のメッセージのみ。
  --    messages の SELECT ポリシーで自分が当事者のものしか見えないため、
  --    他人の会話・存在しない ID はここで一律に拒否される
  IF NEW.reply_to_message_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.messages m
        WHERE m.id = NEW.reply_to_message_id
          AND (   (m.sender_id = v_uid AND m.receiver_id = NEW.receiver_id)
               OR (m.sender_id = NEW.receiver_id AND m.receiver_id = v_uid))
     ) THEN
    RAISE EXCEPTION 'MESSAGES_REPLY_OUTSIDE_CONVERSATION'
      USING ERRCODE = '42501',
            DETAIL  = format('reply_to_message_id=%s is not in the conversation %s <-> %s',
                             NEW.reply_to_message_id, v_uid, NEW.receiver_id),
            HINT    = '返信できるのは同じ会話のメッセージのみです。';
  END IF;

  -- 5. システム列は指定されても強制値にする（拒否ではなく上書き）
  NEW.created_at := now();
  NEW.read_at    := NULL;
  NEW.is_edited  := false;
  NEW.edited_at  := NULL;
  NEW.updated_at := now();

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.messages_guard_insert() IS
  'messages の BEFORE INSERT ガード（エンドユーザーのみ）。sender_id = auth.uid()（MESSAGES_SENDER_MISMATCH）→ sender_type が呼び出し元の実体に一致（MESSAGES_INVALID_SENDER_TYPE）→ 受信者が相手（MESSAGES_RECEIVER_NOT_COUNTERPART）→ 返信先が同じ会話（MESSAGES_REPLY_OUTSIDE_CONVERSATION）の順に検証し、created_at / updated_at = now()、read_at / edited_at = NULL、is_edited = false に強制。いずれも 42501。仕様: 20260922000200_column_write_guards.sql ヘッダー';


-- =============================================================================
-- 3. messages: ガード関数 messages_guard_update()
-- =============================================================================
-- 許可リスト方式:
--   許可列 := {updated_at}
--            ∪ (編集可能な送信者なら {content, tags, is_edited, edited_at})
--            ∪ (受信者なら {read_at})
--   「編集可能な送信者」= sender_id = auth.uid() かつ now() - OLD.created_at < 5 分
--   （RLS の編集ポリシーと同じ式。5 分を過ぎた自分宛て行を受信者ポリシー経由で
--     編集させないため。ヘッダー「列ごとの判断」の注記参照）。
--   (to_jsonb(NEW) - 許可列) と (to_jsonb(OLD) - 許可列) が異なれば拒否。
--   送信者でも受信者でもなければ拒否（RLS の USING で通常は到達しない。fail closed）。
-- その上で:
--   受信者 → read_at は NULL → 値 のときだけ now() に強制。既読後の取り消し・付け替えは拒否
--   編集可能な送信者 → content か tags が変わったら is_edited = true / edited_at = now()。
--            変わらなければ is_edited / edited_at は OLD のまま（同じ値の再送は no-op）
-- updated_at は比較から除外（後続の set_updated_at が now() で上書きする）。

CREATE OR REPLACE FUNCTION public.messages_guard_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_uid             uuid;
  v_is_sender       boolean;
  v_sender_editable boolean;
  v_is_receiver     boolean;
  v_allowed         text[] := ARRAY['updated_at'];
  v_new         jsonb;
  v_old         jsonb;
  v_columns     text;
BEGIN
  -- service_role / postgres / SECURITY DEFINER 関数（mark_messages_as_read 等）は対象外
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  -- anon は messages の正規の書き手ではない（通常は GRANT 剥奪で権限チェックが先に落ちる）
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'ANON_WRITE_FORBIDDEN'
      USING ERRCODE = '42501',
            DETAIL  = format('table=%s.%s op=%s', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP),
            HINT    = 'anon ロールは messages に書き込めません。ログインしてから操作してください。';
  END IF;

  v_uid         := auth.uid();
  v_is_sender   := v_uid IS NOT NULL AND OLD.sender_id = v_uid;
  v_is_receiver := v_uid IS NOT NULL AND OLD.receiver_id = v_uid;
  -- 送信者の編集権限は RLS の "Users can edit own messages within 5 minutes" と同じ
  -- 5 分以内に限る。通常の送信者は 5 分を過ぎると RLS で行ごと除外されるため、
  -- 実際に効くのは自分宛て（sender = receiver）の行が時間制限の無い受信者ポリシー
  -- 経由で届いた場合だけ（5 分を過ぎた自分宛て本文の編集を塞ぐ）
  v_sender_editable := v_is_sender
                       AND now() - OLD.created_at < interval '5 minutes';

  IF NOT (v_is_sender OR v_is_receiver) THEN
    RAISE EXCEPTION 'MESSAGES_COLUMN_NOT_UPDATABLE'
      USING ERRCODE = '42501',
            DETAIL  = format('message %s: caller %s is neither sender nor receiver',
                             OLD.id, coalesce(v_uid::text, 'NULL')),
            HINT    = 'メッセージを更新できるのは送信者（本文・タグの編集）と受信者（既読化）のみです。';
  END IF;

  IF v_sender_editable THEN
    v_allowed := v_allowed || ARRAY['content', 'tags', 'is_edited', 'edited_at'];
  END IF;
  IF v_is_receiver THEN
    v_allowed := v_allowed || ARRAY['read_at'];
  END IF;

  v_new := to_jsonb(NEW) - v_allowed;
  v_old := to_jsonb(OLD) - v_allowed;

  IF v_new IS DISTINCT FROM v_old THEN
    SELECT string_agg(coalesce(n.key, o.key), ', ' ORDER BY coalesce(n.key, o.key))
      INTO v_columns
      FROM jsonb_each(v_new) AS n
      FULL JOIN jsonb_each(v_old) AS o ON o.key = n.key
     WHERE n.value IS DISTINCT FROM o.value;

    -- メッセージ文字列 'MESSAGES_COLUMN_NOT_UPDATABLE' は固定。変更禁止。
    RAISE EXCEPTION 'MESSAGES_COLUMN_NOT_UPDATABLE'
      USING ERRCODE = '42501',
            DETAIL  = format('message %s: role=%s%s columns=%s', OLD.id,
                             CASE
                               WHEN v_is_sender AND v_is_receiver THEN 'sender+receiver'
                               WHEN v_is_sender THEN 'sender'
                               ELSE 'receiver'
                             END,
                             CASE
                               WHEN v_is_sender AND NOT v_sender_editable
                                 THEN ' (edit window of 5 minutes has passed)'
                               ELSE ''
                             END,
                             coalesce(v_columns, '(unknown)')),
            HINT    = '送信者が更新できるのは作成から 5 分以内の content / tags のみ、受信者は read_at（未読 → 既読）のみです。';
  END IF;

  -- 受信者: read_at は未読 → 既読の 1 回だけ。値はサーバー時刻に強制
  IF v_is_receiver THEN
    IF OLD.read_at IS NULL AND NEW.read_at IS NOT NULL THEN
      NEW.read_at := now();
    ELSIF OLD.read_at IS NOT NULL AND NEW.read_at IS DISTINCT FROM OLD.read_at THEN
      -- メッセージ文字列 'MESSAGES_READ_AT_IMMUTABLE' は固定。変更禁止。
      RAISE EXCEPTION 'MESSAGES_READ_AT_IMMUTABLE'
        USING ERRCODE = '42501',
              DETAIL  = format('message %s: read_at=%s -> %s', OLD.id, OLD.read_at,
                               coalesce(NEW.read_at::text, 'NULL')),
              HINT    = '既読の取り消し・既読時刻の付け替えはできません。';
    END IF;
  END IF;

  -- 編集可能な送信者: 本文かタグが変わったときだけ編集済みにする（時刻はサーバー時刻）。
  -- 編集できない場合（5 分経過の自分宛て）は is_edited / edited_at が許可列に入らないため、
  -- 変更しようとすれば上の比較で拒否済み（OLD のまま）
  IF v_sender_editable THEN
    IF NEW.content IS DISTINCT FROM OLD.content
       OR NEW.tags IS DISTINCT FROM OLD.tags THEN
      NEW.is_edited := true;
      NEW.edited_at := now();
    ELSE
      NEW.is_edited := OLD.is_edited;
      NEW.edited_at := OLD.edited_at;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.messages_guard_update() IS
  'messages の BEFORE UPDATE ガード（エンドユーザーのみ）。許可列 = updated_at ∪ 作成から 5 分以内の送信者 {content, tags, is_edited, edited_at} ∪ 受信者 {read_at} 以外の変更を MESSAGES_COLUMN_NOT_UPDATABLE で拒否（5 分の条件は RLS の編集ポリシーと同じ式。時間制限の無い受信者ポリシー経由での自分宛て行の編集を塞ぐ）。受信者の read_at は NULL → now() の 1 回のみ（既読後の変更は MESSAGES_READ_AT_IMMUTABLE）。送信者が content / tags を変えたら is_edited = true / edited_at = now()。いずれも 42501。仕様: 20260922000200_column_write_guards.sql ヘッダー';


-- =============================================================================
-- 4. ガード関数を RPC 面から外す
-- =============================================================================
-- トリガー関数は発火時に EXECUTE 権限を必要としない（CREATE TRIGGER 時のみ）。
-- Supabase の既定権限で anon / authenticated に付く EXECUTE を剥奪しておく。

REVOKE ALL ON FUNCTION public.clients_guard_protected_columns() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.messages_guard_insert()           FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.messages_guard_update()           FROM PUBLIC, anon, authenticated;


-- =============================================================================
-- 5. トリガー
-- =============================================================================
-- UPDATE OF <列> の列指定はしない（指定外の列・今後追加される列の UPDATE で
-- 発火せず保護が抜けるため）。BEFORE トリガーは名前順に発火する:
--   clients : clients_guard_protected_columns → enforce_client_limit_trigger
--   messages: messages_guard_update → set_updated_at

DROP TRIGGER IF EXISTS clients_guard_protected_columns ON public.clients;

CREATE TRIGGER clients_guard_protected_columns
  BEFORE INSERT OR UPDATE ON public.clients
  FOR EACH ROW
  EXECUTE FUNCTION public.clients_guard_protected_columns();

DROP TRIGGER IF EXISTS messages_guard_insert ON public.messages;

CREATE TRIGGER messages_guard_insert
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_guard_insert();

DROP TRIGGER IF EXISTS messages_guard_update ON public.messages;

CREATE TRIGGER messages_guard_update
  BEFORE UPDATE ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.messages_guard_update();


-- =============================================================================
-- 6. clients の列レベル GRANT（20260712000000 §4 の trainers と同じ方式）
-- =============================================================================
-- テーブル全体の INSERT / UPDATE を anon / authenticated から剥がし、authenticated
-- にはクライアント（Mobile）が実際に書く列だけを列単位で許可し直す。
-- 非 service_role の clients 書き込み箇所（2026-09-22 grep 全数。詳細はヘッダー）:
--   [INSERT + UPDATE（ON CONFLICT DO UPDATE SET）]
--   - fit-connect-mobile/lib/features/auth/providers/registration_provider.dart:177
--       upsert {client_id, trainer_id, name, email, age?, gender?}
--       → INSERT 列 = client_id, trainer_id, name, email, age, gender。
--         SET 句に同じ列が並ぶため、この 6 列は UPDATE 列権限も必要
--   [UPDATE]
--   - registration_provider.dart:203 / :211、client_repository.dart:52 … profile_image_url
--   - fit-connect-mobile/lib/features/auth/data/client_repository.dart:39 … name
--   - fit-connect-mobile/lib/features/onboarding_flow/data/onboarding_repository.dart:28
--       … onboarding_completed_at
--   - fit-connect-mobile/lib/services/notification_service.dart:409 / :441 / :520 … fcm_token
--   [許可しない（死にコード / service_role 専用）]
--   - goal_repository.dart:75 / :87（initial_weight / target_weight / goal_* 。未使用）
--   - occupation / height / target_weight / purpose / goal_description / goal_deadline は
--     Web の updateClient.ts（supabaseAdmin）、line_user_id はレガシー、created_at は DB 既定
--   [対象外（service_role 経由のため本 GRANT の影響を受けない）]
--   - fit-connect/src/lib/supabase/updateClient.ts:30、supabase/functions/_shared/push.ts:310、
--     supabase/functions/delete-account/index.ts:136
-- テーブル単位の REVOKE は同じ権限の列単位 GRANT もまとめて剥がすため、
-- 再実行しても下の列 GRANT の最終形に収束する。

REVOKE INSERT, UPDATE ON public.clients FROM anon, authenticated;

GRANT INSERT (client_id, trainer_id, name, email, age, gender)
  ON public.clients TO authenticated;
GRANT UPDATE (client_id, trainer_id, name, email, age, gender,
              profile_image_url, fcm_token, onboarding_completed_at)
  ON public.clients TO authenticated;

-- SELECT は既存のまま（Clients can view own profile / トレーナー自身のクライアントだけ見れる）。
-- anon には INSERT / UPDATE を一切戻さない（anon は clients を書かない）。
-- service_role は既存の GRANT ALL のまま（RLS もバイパスする）。


-- =============================================================================
-- 7. messages: anon の書き込み GRANT を剥奪
-- =============================================================================
-- messages の INSERT / UPDATE ポリシーは TO PUBLIC のため、GRANT が残っていると
-- 「anon + 顧客の JWT クレーム」が sender_id = auth.uid() を満たして書けてしまう。
-- anon は messages を書かない。authenticated の INSERT / UPDATE は残す
-- （送信者・受信者とも authenticated のため列 GRANT では区別できず、§2 / §3 の
-- トリガーで判定する）。

REVOKE INSERT, UPDATE, DELETE ON public.messages FROM anon;


-- =============================================================================
-- 8. 権限・トリガーの最終状態の検証（満たさなければ migration 全体を中断）
-- =============================================================================
-- REVOKE は実行ロール自身が付与した権限しか外さない。別の grantor（例: supabase_admin）が
-- 付けた GRANT が残っていても WARNING が出るだけでエラーにならない。リモートはオーナーの
-- 手動適用のため、剥奪が黙って空振りし「トレーナー所有列が書ける」まま完了するのを防ぐ。
-- 検証内容（読み取りのみ。再実行しても同じ判定になる）:
--   (1) authenticated に clients のテーブル単位の INSERT / UPDATE が無い
--   (2) authenticated の clients 列権限が §6 の許可リストと完全一致する（全列を走査。
--       今後追加される列は既定で権限なし = 許可リスト外 = false が期待値）
--   (3) anon に clients / messages の INSERT / UPDATE（列単位を含む）と messages の DELETE が無い
--   (4) ガードトリガー 3 本が存在し、有効（tgenabled 'O' / 'A'）で、正しいガード関数を呼ぶ
-- PUBLIC への付与・ロールの継承による権限も has_*_privilege が拾う。
-- メッセージ文字列 'COLUMN_GUARD_PRIVILEGE_CHECK_FAILED' は固定。変更禁止。

DO $$
DECLARE
  v_ins      text[] := ARRAY['client_id', 'trainer_id', 'name', 'email', 'age', 'gender'];
  v_upd      text[] := ARRAY['client_id', 'trainer_id', 'name', 'email', 'age', 'gender',
                             'profile_image_url', 'fcm_token', 'onboarding_completed_at'];
  v_problems text[] := '{}';
  v_enabled  "char";
  v_fn       oid;
  r          record;
BEGIN
  -- (1) テーブル単位の INSERT / UPDATE が authenticated に残っていないこと
  IF has_table_privilege('authenticated', 'public.clients', 'INSERT') THEN
    v_problems := v_problems || 'authenticated has table-level INSERT on public.clients'::text;
  END IF;
  IF has_table_privilege('authenticated', 'public.clients', 'UPDATE') THEN
    v_problems := v_problems || 'authenticated has table-level UPDATE on public.clients'::text;
  END IF;

  -- (2) authenticated の clients 列権限 = 許可リスト（created_at / target_weight 等は false、
  --     trainer_id / name 等は true）
  FOR r IN
    SELECT a.attname::text AS col
      FROM pg_catalog.pg_attribute a
     WHERE a.attrelid = 'public.clients'::regclass
       AND a.attnum > 0
       AND NOT a.attisdropped
     ORDER BY a.attnum
  LOOP
    IF has_column_privilege('authenticated', 'public.clients', r.col, 'INSERT')
       IS DISTINCT FROM (r.col = ANY (v_ins)) THEN
      v_problems := v_problems || format('authenticated INSERT(public.clients.%s) is %s, expected %s',
        r.col, has_column_privilege('authenticated', 'public.clients', r.col, 'INSERT'),
        r.col = ANY (v_ins));
    END IF;
    IF has_column_privilege('authenticated', 'public.clients', r.col, 'UPDATE')
       IS DISTINCT FROM (r.col = ANY (v_upd)) THEN
      v_problems := v_problems || format('authenticated UPDATE(public.clients.%s) is %s, expected %s',
        r.col, has_column_privilege('authenticated', 'public.clients', r.col, 'UPDATE'),
        r.col = ANY (v_upd));
    END IF;
  END LOOP;

  -- (3) anon の書き込み権限（列単位を含む）が残っていないこと
  FOR r IN
    SELECT * FROM (VALUES
      ('public.clients',  'INSERT'),
      ('public.clients',  'UPDATE'),
      ('public.messages', 'INSERT'),
      ('public.messages', 'UPDATE')
    ) AS v(tbl, priv)
  LOOP
    IF has_any_column_privilege('anon', r.tbl, r.priv) THEN
      v_problems := v_problems || format('anon has %s on %s (table or column level)', r.priv, r.tbl);
    END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.messages', 'DELETE') THEN
    v_problems := v_problems || 'anon has DELETE on public.messages'::text;
  END IF;

  -- (4) ガードトリガーが存在し、有効で、正しい関数を呼ぶこと
  FOR r IN
    SELECT * FROM (VALUES
      ('public.clients',  'clients_guard_protected_columns', 'public.clients_guard_protected_columns()'),
      ('public.messages', 'messages_guard_insert',           'public.messages_guard_insert()'),
      ('public.messages', 'messages_guard_update',           'public.messages_guard_update()')
    ) AS v(tbl, tgname, fn)
  LOOP
    SELECT t.tgenabled, t.tgfoid
      INTO v_enabled, v_fn
      FROM pg_catalog.pg_trigger t
     WHERE t.tgrelid = r.tbl::regclass
       AND t.tgname = r.tgname
       AND NOT t.tgisinternal;
    IF NOT FOUND THEN
      v_problems := v_problems || format('trigger %s on %s is missing', r.tgname, r.tbl);
    ELSIF v_enabled NOT IN ('O', 'A') THEN
      v_problems := v_problems || format('trigger %s on %s is disabled (tgenabled=%s)',
                                         r.tgname, r.tbl, v_enabled);
    ELSIF v_fn IS DISTINCT FROM r.fn::regprocedure::oid THEN
      v_problems := v_problems || format('trigger %s on %s calls %s, expected %s',
                                         r.tgname, r.tbl, v_fn::regprocedure, r.fn);
    END IF;
  END LOOP;

  IF cardinality(v_problems) > 0 THEN
    RAISE EXCEPTION 'COLUMN_GUARD_PRIVILEGE_CHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = array_to_string(v_problems, ' / '),
            HINT    = 'REVOKE が別の grantor の付与を外せていない可能性があります。pg_class.relacl / pg_attribute.attacl の grantor を確認し、その grantor で REVOKE してから再適用してください（migration 全体はロールバック済み）。';
  END IF;

  RAISE NOTICE 'COLUMN_GUARD_PRIVILEGE_CHECK_OK: clients 列権限・anon 剥奪・ガードトリガー 3 本を確認';
END
$$;
