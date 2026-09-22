-- =============================================================================
-- get_unreplied_clients_for_trainer()（未返信の顧客）のテスト
-- （フェーズ9.2 / 20260922200000_triage_unreplied.sql）
--
-- 未返信の定義（計画書「契約 > RPC get_unreplied_clients_for_trainer()」）を、ケースごとに
-- 1人ずつ用意した試験用の顧客で検証する自己完結テスト
-- （client_alerts_rls_test.sql / sessions_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/triage_unreplied_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL TRIAGE UNREPLIED TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - 日時はすべて now()（= トランザクション開始時刻。関数の中の now() と同じ値）からの相対で入れる
-- - messages の AFTER INSERT トリガー（call_parse_message_tags）は本番 URL へ net.http_post を
--   積むため、試験メッセージの INSERT の間だけ session_replication_role = replica でトリガーを
--   止める（ROLLBACK で要求も消えるが二重に防ぐ。net.http_request_queue が増えないことも確かめる）
-- - 関数は SECURITY INVOKER なので、トレーナーのケースは authenticated + JWT クレームで呼ぶ
--   （messages / clients の RLS が効く状態）。ケース(l) は BYPASSRLS の service_role で呼び、
--   RLS が無くても関数自身の条件だけで絞れていること（二重の守りの関数側）を確かめる
--
-- 検証ケース（計画書 PR2 レーンA-2 の (a)〜(i) と、追加の (j)〜(m)）:
--   (a) トレーナーの最後の送信より後にタグ無しが2件 → 1行（unreplied_since は古い方、count は 2。
--       返信より前のタグ無しと、返信より後のタグ付きは数えない。担当関係の無い第三者（トレーナー B）が
--       その顧客に送ったメッセージは A の返信に数えない）
--   (b) タグ付きしか無い → 0行 / tags が NULL・空配列 → タグ無しとして数える
--   (c) トレーナーが返信した → 0行（返信がタグ付きでも同じ）。返信が複数あれば最後の返信より後だけを数える。
--       返信と同じ時刻の顧客のメッセージは「返信より後」ではないので数えない
--   (d) 最新の未返信が7日より前（7日と1分前）→ 0行。6日23時間59分前・ちょうど7日前 → 1行。
--       最新が7日以内なら、7日より前の未返信も unreplied_since / count に入る
--   (e) 他のトレーナー宛て / 担当が替わった / clients に無い顧客のメッセージ → 0行。
--       トレーナー A の結果は期待の8顧客ちょうど（余計な行が無い）
--   (f) トレーナー B が呼んでも A の顧客は出ない（B の顧客だけ）
--   (g) 顧客本人が呼ぶと 0 行（兼務でトレーナーでもある顧客が呼んでも、A 側の顧客は出ない）
--   (h-1) anon（JWT クレーム無し）は EXECUTE が permission denied（42501）
--   (h-2) anon（JWT クレームにトレーナー A の UUID）も 42501。messages / clients のポリシーの多くは
--         TO public（anon を含む）なので、anon に EXECUTE が残っていればこの状態で A の行が読めてしまう
--   (i) 自分宛て（sender = receiver。自己登録のトレーナーが自分に送ったもの）は除かれる。
--       自分宛ては sender_type = client なので返信には数えられず、client_id <> auth.uid() だけで除かれる
--   (j) 顧客が書ける created_at の未来・±infinity の値は数えない（トレーナーが返信した後も
--       未来の日時のメッセージで未返信が残り続けない / -infinity が unreplied_since に出ない）
--   (k) 兼務: 担当顧客がトレーナーとして送ったメッセージ（sender_type = trainer）は未返信に数えない。
--       互いに担当し合う2人（L・M）で、自分が相手の顧客として送った記録投稿（sender_type = client）は
--       返信に数えない
--   (l) BYPASSRLS の service_role + クレームでも、関数の条件だけで本人の担当顧客に絞れる
--       （第三者 B が A の顧客に送ったメッセージが見える状態でも、A の返信に数えない）。
--       sub の無い service_role の呼び出しは 0 行
--   (m) メタデータ: SECURITY INVOKER / STABLE / sql / 引数なし / search_path = '' /
--       戻り列の許可リスト / EXECUTE は authenticated のみ（PUBLIC・anon に無い）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer A : aaaaaaaa-0922-0000-0000-00000000000a（自己登録の顧客行も持つ → ケース(i)）
--   trainer B : bbbbbbbb-0922-0000-0000-00000000000b
--   K         : aaaaaaaa-0922-0000-0000-00000000000c（トレーナーでもあり、A の顧客でもある兼務 → (g)(k)）
--   L・M      : aaaaaaaa-0922-0000-0000-00000000000d / …0e（どちらもトレーナーで、互いの顧客でもある → (k)）
--   A の顧客  : cccccccc-0922-0000-0000-0000000000NN（NN = 01〜15。ケースは下のメッセージの注記）
--               c10 は担当替えで B の顧客にする（ケース(e)）
--   B の顧客  : cccccccc-0922-0000-0000-0000000000b1
--   X         : dddddddd-0922-0000-0000-0000000000d1（clients に行が無い送信者 → ケース(e)）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer A・B・K・L・M / A の顧客 c01〜c15・K・A 自身 / B の顧客 b1 / L と M は互いの顧客)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', v.email, 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'triage-test-a@example.com'),
    ('bbbbbbbb-0922-0000-0000-00000000000b', 'triage-test-b@example.com'),
    ('aaaaaaaa-0922-0000-0000-00000000000c', 'triage-test-k@example.com'),
    ('aaaaaaaa-0922-0000-0000-00000000000d', 'triage-test-l@example.com'),
    ('aaaaaaaa-0922-0000-0000-00000000000e', 'triage-test-m@example.com')
  ) AS v(id, email);

-- 顧客数の上限（enforce_client_limit）に掛からないよう business にしておく
INSERT INTO public.trainers (id, name, email, subscription_plan) VALUES
  ('aaaaaaaa-0922-0000-0000-00000000000a', '未返信テスト トレーナーA', 'triage-test-a@example.com', 'business'),
  ('bbbbbbbb-0922-0000-0000-00000000000b', '未返信テスト トレーナーB', 'triage-test-b@example.com', 'business'),
  ('aaaaaaaa-0922-0000-0000-00000000000c', '未返信テスト 兼務K',       'triage-test-k@example.com', 'business'),
  ('aaaaaaaa-0922-0000-0000-00000000000d', '未返信テスト 兼務L',       'triage-test-l@example.com', 'business'),
  ('aaaaaaaa-0922-0000-0000-00000000000e', '未返信テスト 兼務M',       'triage-test-m@example.com', 'business');

INSERT INTO public.clients (client_id, name, trainer_id, profile_image_url)
SELECT v.client_id::uuid, v.name, v.trainer_id::uuid, v.profile_image_url
  FROM (VALUES
    ('cccccccc-0922-0000-0000-000000000001', '未返信テスト c01', 'aaaaaaaa-0922-0000-0000-00000000000a', 'profiles/c01.jpg'),
    ('cccccccc-0922-0000-0000-000000000002', '未返信テスト c02', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000003', '未返信テスト c03', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000004', '未返信テスト c04', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000005', '未返信テスト c05', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000006', '未返信テスト c06', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000007', '未返信テスト c07', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000008', '未返信テスト c08', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000009', '未返信テスト c09', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000010', '未返信テスト c10', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000011', '未返信テスト c11', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000012', '未返信テスト c12', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000013', '未返信テスト c13', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000014', '未返信テスト c14', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    ('cccccccc-0922-0000-0000-000000000015', '未返信テスト c15', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    -- 兼務 K（トレーナーでもあり、A の顧客でもある）
    ('aaaaaaaa-0922-0000-0000-00000000000c', '未返信テスト 兼務K', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    -- A の自己登録（client_id = trainer_id）
    ('aaaaaaaa-0922-0000-0000-00000000000a', '未返信テスト A 本人', 'aaaaaaaa-0922-0000-0000-00000000000a', NULL),
    -- 互いに担当し合う L と M（L は M の顧客、M は L の顧客）
    ('aaaaaaaa-0922-0000-0000-00000000000d', '未返信テスト 兼務L', 'aaaaaaaa-0922-0000-0000-00000000000e', NULL),
    ('aaaaaaaa-0922-0000-0000-00000000000e', '未返信テスト 兼務M', 'aaaaaaaa-0922-0000-0000-00000000000d', NULL),
    ('cccccccc-0922-0000-0000-0000000000b1', '未返信テスト b1',  'bbbbbbbb-0922-0000-0000-00000000000b', NULL)
  ) AS v(client_id, name, trainer_id, profile_image_url);

-- messages（AFTER INSERT トリガーが本番 URL へ net.http_post を積むので、この INSERT の間だけ止める）
DO $$
BEGIN
  PERFORM set_config('triage_test.queue_before', (SELECT count(*) FROM net.http_request_queue)::text, true);
END $$;
SET LOCAL session_replication_role = replica;

-- tags は列の既定値が '{}'（タグ無し）。NULL・タグ付きはケースごとに明示する
INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, tags, created_at)
SELECT v.sender_id::uuid, v.receiver_id::uuid, v.sender_type, v.receiver_type, v.content,
       v.tags::text[], v.created_at
  FROM (VALUES
    -- (a) c01: 返信（3日前）より前のタグ無し・返信より後のタグ無し2件・タグ付き1件。
    --     最新の相談（1時間前）の後に、担当関係の無いトレーナー B が c01 に送った（INSERT のポリシーは
    --     sender_id しか見ないので送れる）。これを A の返信に数えると c01 が消える。authenticated の A には
    --     RLS で見えないので、関数の条件（r.sender_id = auth.uid()）はケース(l) の service_role で確かめる
    ('cccccccc-0922-0000-0000-000000000001', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(a) 返信より前の相談', '{}', now() - interval '4 days'),
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000001', 'trainer', 'client',
     '(a) トレーナーの返信', '{}', now() - interval '3 days'),
    ('cccccccc-0922-0000-0000-000000000001', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(a) 返信より後の相談1', '{}', now() - interval '2 days'),
    ('cccccccc-0922-0000-0000-000000000001', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(a) #体重 記録投稿', '{体重}', now() - interval '1 day'),
    ('cccccccc-0922-0000-0000-000000000001', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(a) 返信より後の相談2', '{}', now() - interval '1 hour'),
    ('bbbbbbbb-0922-0000-0000-00000000000b', 'cccccccc-0922-0000-0000-000000000001', 'trainer', 'client',
     '(a) 第三者 B から c01 へ', '{}', now() - interval '30 minutes'),

    -- (b-1) c02: タグ付きしか無い（ワークアウト達成の「💬 感想」付きも含む）
    ('cccccccc-0922-0000-0000-000000000002', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(b) #体重 記録投稿', '{体重}', now() - interval '2 days'),
    ('cccccccc-0922-0000-0000-000000000002', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(b) #運動:完了 💬 感想', '{運動:完了}', now() - interval '1 hour'),

    -- (b-2) c03: tags が NULL と空配列 → どちらもタグ無し
    ('cccccccc-0922-0000-0000-000000000003', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(b) tags NULL', NULL, now() - interval '3 hours'),
    ('cccccccc-0922-0000-0000-000000000003', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(b) tags 空配列', '{}', now() - interval '2 hours'),

    -- (c-1) c04: 顧客の相談の後にトレーナーが返信した
    ('cccccccc-0922-0000-0000-000000000004', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(c) 相談', '{}', now() - interval '2 days'),
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000004', 'trainer', 'client',
     '(c) 返信', '{}', now() - interval '1 day'),

    -- (c-2) c05: トレーナーの返信がタグ付きでも返信として数える
    ('cccccccc-0922-0000-0000-000000000005', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(c) 相談', '{}', now() - interval '2 days'),
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000005', 'trainer', 'client',
     '(c) タグ付きの返信', '{お知らせ}', now() - interval '1 day'),

    -- (c-4) c15: 顧客のメッセージが返信とちょうど同じ時刻（1日前）→「返信より後」ではないので数えない
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000015', 'trainer', 'client',
     '(c) 返信', '{}', now() - interval '1 day'),
    ('cccccccc-0922-0000-0000-000000000015', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(c) 返信と同じ時刻の相談', '{}', now() - interval '1 day'),

    -- (c-3) c06: 返信が2回。最後の返信（1日前）より後の1件だけを数える
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000006', 'trainer', 'client',
     '(c) 最初の返信', '{}', now() - interval '3 days'),
    ('cccccccc-0922-0000-0000-000000000006', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(c) 最後の返信より前の相談', '{}', now() - interval '2 days'),
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000006', 'trainer', 'client',
     '(c) 最後の返信', '{}', now() - interval '1 day'),
    ('cccccccc-0922-0000-0000-000000000006', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(c) 最後の返信より後の相談', '{}', now() - interval '1 hour'),

    -- (d-1) c07: 最新の未返信が7日と1分前
    ('cccccccc-0922-0000-0000-000000000007', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(d) 7日と1分前', '{}', now() - interval '7 days 1 minute'),

    -- (d-2) c08: 最新の未返信が6日23時間59分前
    ('cccccccc-0922-0000-0000-000000000008', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(d) 6日23時間59分前', '{}', now() - interval '6 days 23 hours 59 minutes'),

    -- (d-3) c14: 最新の未返信がちょうど7日前（境界。7日以内に含める）
    ('cccccccc-0922-0000-0000-000000000014', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(d) ちょうど7日前', '{}', now() - interval '7 days'),

    -- (d-4) c09: 10日前と3日前（返信なし）。最新が7日以内なので10日前の分も数える
    ('cccccccc-0922-0000-0000-000000000009', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(d) 10日前', '{}', now() - interval '10 days'),
    ('cccccccc-0922-0000-0000-000000000009', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(d) 3日前', '{}', now() - interval '3 days'),

    -- (e-1) c10: A の担当だったときに A へ送った（この後 B に担当替え）
    ('cccccccc-0922-0000-0000-000000000010', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(e) 担当替えの前に A へ', '{}', now() - interval '1 hour'),

    -- (e-2) c11: A の顧客が他のトレーナー B 宛てに送った
    ('cccccccc-0922-0000-0000-000000000011', 'bbbbbbbb-0922-0000-0000-00000000000b', 'client', 'trainer',
     '(e) 他のトレーナー宛て', '{}', now() - interval '1 hour'),

    -- (e-3) X: clients に行が無い送信者（削除済みの顧客など）から A へ
    ('dddddddd-0922-0000-0000-0000000000d1', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(e) clients に無い送信者', '{}', now() - interval '1 hour'),

    -- (f) b1: B の顧客から B へ
    ('cccccccc-0922-0000-0000-0000000000b1', 'bbbbbbbb-0922-0000-0000-00000000000b', 'client', 'trainer',
     '(f) B の顧客の相談', '{}', now() - interval '5 hours'),

    -- (i) A の自己登録: A から A 自身へ（sender = receiver）
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(i) 自分宛て', '{}', now() - interval '1 hour'),

    -- (j-1) c12: 未来と +infinity の created_at（顧客が INSERT 時に書ける）。
    --       A は1分前に返信している → 未来の日時のメッセージで未返信が残り続けないこと
    ('cccccccc-0922-0000-0000-000000000012', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(j) +infinity', '{}', 'infinity'::timestamptz),
    ('cccccccc-0922-0000-0000-000000000012', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(j) 1日後', '{}', now() + interval '1 day'),
    ('aaaaaaaa-0922-0000-0000-00000000000a', 'cccccccc-0922-0000-0000-000000000012', 'trainer', 'client',
     '(j) 返信', '{}', now() - interval '1 minute'),

    -- (j-2) c13: -infinity と30分前（返信なし）→ -infinity は数えない
    ('cccccccc-0922-0000-0000-000000000013', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(j) -infinity', '{}', '-infinity'::timestamptz),
    ('cccccccc-0922-0000-0000-000000000013', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(j) 30分前', '{}', now() - interval '30 minutes'),

    -- (k) 兼務 K: 顧客として A に送った（数える）/ トレーナーとして A に送った（数えない）
    ('aaaaaaaa-0922-0000-0000-00000000000c', 'aaaaaaaa-0922-0000-0000-00000000000a', 'client', 'trainer',
     '(k) 顧客として', '{}', now() - interval '2 hours'),
    ('aaaaaaaa-0922-0000-0000-00000000000c', 'aaaaaaaa-0922-0000-0000-00000000000a', 'trainer', 'client',
     '(k) トレーナーとして', '{}', now() - interval '20 minutes'),

    -- (k-2) 互いに担当し合う L・M: M が L の顧客として L に相談（2時間前）→ その後 L が M の顧客として
    --       M に記録を投稿（1時間前、sender_type = client）。L の投稿は L から M への返信ではない
    ('aaaaaaaa-0922-0000-0000-00000000000e', 'aaaaaaaa-0922-0000-0000-00000000000d', 'client', 'trainer',
     '(k) M から L（L の顧客として相談）', '{}', now() - interval '2 hours'),
    ('aaaaaaaa-0922-0000-0000-00000000000d', 'aaaaaaaa-0922-0000-0000-00000000000e', 'client', 'trainer',
     '(k) #体重 70kg（L が M の顧客として投稿）', '{体重}', now() - interval '1 hour')
  ) AS v(sender_id, receiver_id, sender_type, receiver_type, content, tags, created_at);

SET LOCAL session_replication_role = origin;

DO $$
BEGIN
  IF (SELECT count(*) FROM net.http_request_queue)
     <> current_setting('triage_test.queue_before')::bigint THEN
    RAISE EXCEPTION 'FAIL: setup — 試験メッセージの INSERT で net.http_request_queue が増えた（トリガーが止まっていない）';
  END IF;
END $$;

-- (e-1) c10 の担当を A → B に替える（A 宛てのメッセージは残る）
UPDATE public.clients
   SET trainer_id = 'bbbbbbbb-0922-0000-0000-00000000000b'
 WHERE client_id = 'cccccccc-0922-0000-0000-000000000010';

-- -----------------------------------------------------------------------------
-- ケース(a): トレーナーの最後の送信より後にタグ無しが2件 → 1行
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case a: 返信より後のタグ無し2件 → 1行（unreplied_since は古い方、count は 2）'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000a';

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000001';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (a) c01 の行が % 行（期待 1 行）', cnt;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000001';
  IF v_row.unreplied_count IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'FAIL: (a) c01 の unreplied_count が %（期待 2。返信より前・タグ付きは数えない）', v_row.unreplied_count;
  END IF;
  IF v_row.unreplied_since IS DISTINCT FROM now() - interval '2 days' THEN
    RAISE EXCEPTION 'FAIL: (a) c01 の unreplied_since が %（期待 2日前 = 返信より後の古い方）', v_row.unreplied_since;
  END IF;
  IF v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: (a) c01 の latest_unreplied_at が %（期待 1時間前）', v_row.latest_unreplied_at;
  END IF;
  IF v_row.client_name IS DISTINCT FROM '未返信テスト c01'
     OR v_row.profile_image_url IS DISTINCT FROM 'profiles/c01.jpg' THEN
    RAISE EXCEPTION 'FAIL: (a) c01 の client_name / profile_image_url が % / %', v_row.client_name, v_row.profile_image_url;
  END IF;
  RAISE NOTICE 'OK: (a) 返信より後のタグ無し2件 → 1行（since = 2日前、latest = 1時間前、count = 2。第三者 B の送信は返信に数えない）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): タグ付きしか無い → 0行 / tags が NULL・空配列はタグ無し
-- -----------------------------------------------------------------------------
\echo '--- case b: タグ付きだけの顧客は出ず、tags NULL・空配列はタグ無しとして数えること'

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000002';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (b) タグ付きしか無い c02 が % 行出た（期待 0 行。記録投稿は未返信に数えない）', cnt;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000003';
  IF v_row.client_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: (b) tags NULL・空配列の c03 が出ない（期待 1 行）';
  END IF;
  IF v_row.unreplied_count IS DISTINCT FROM 2
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '3 hours'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '2 hours' THEN
    RAISE EXCEPTION 'FAIL: (b) c03 が count=% since=% latest=%（期待 2 / 3時間前 / 2時間前。tags NULL もタグ無し）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;
  RAISE NOTICE 'OK: (b) タグ付きだけの顧客は 0 行、tags NULL・空配列はタグ無しとして数える';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): トレーナーが返信した → 0行（返信がタグ付きでも同じ）/ 最後の返信より後だけを数える /
--   返信と同じ時刻の顧客のメッセージは数えない（「返信より後」は厳密に後）
-- -----------------------------------------------------------------------------
\echo '--- case c: 返信済みは 0 行（タグ付きの返信も返信）、最後の返信より後だけを数え、返信と同じ時刻は数えないこと'

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000004';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (c) 返信済みの c04 が % 行出た（期待 0 行）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000005';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (c) タグ付きで返信した c05 が % 行出た（期待 0 行。返信はタグの有無を問わない）', cnt;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000006';
  IF v_row.unreplied_count IS DISTINCT FROM 1
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '1 hour'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: (c) c06 が count=% since=% latest=%（期待 1 / 1時間前 / 1時間前。最後の返信より後だけ）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;

  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000015';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (c) 返信と同じ時刻のメッセージしか無い c15 が % 行出た（期待 0 行。返信より厳密に後だけを数える）', cnt;
  END IF;
  RAISE NOTICE 'OK: (c) 返信済みは 0 行（タグ付きの返信も返信）、未返信は最後の返信より後だけ（同じ時刻は数えない）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 最新の未返信が7日より前 → 0行（ちょうど7日前は7日以内に含める）
-- -----------------------------------------------------------------------------
\echo '--- case d: 最新の未返信が7日と1分前なら 0 行、6日23時間59分前・ちょうど7日前なら 1 行であること'

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000007';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (d) 最新の未返信が7日と1分前の c07 が % 行出た（期待 0 行）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000008';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (d) 最新の未返信が6日23時間59分前の c08 が % 行（期待 1 行）', cnt;
  END IF;

  -- 境界: ちょうど7日前（now() はトランザクション内で固定なので、関数の中と同じ値）
  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000014';
  IF v_row.client_id IS NULL OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '7 days' THEN
    RAISE EXCEPTION 'FAIL: (d) 最新の未返信がちょうど7日前の c14 が出ない、または latest=%（期待 1 行・7日前。7日以内に含める）',
      v_row.latest_unreplied_at;
  END IF;

  -- 7日の窓は「最新の未返信」に掛かる。それより前の未返信も since / count に入る
  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000009';
  IF v_row.unreplied_count IS DISTINCT FROM 2
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '10 days'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '3 days' THEN
    RAISE EXCEPTION 'FAIL: (d) c09 が count=% since=% latest=%（期待 2 / 10日前 / 3日前）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;
  RAISE NOTICE 'OK: (d) 7日の窓は最新の未返信に掛かる（7日と1分前は 0 行、6日23時間59分前・ちょうど7日前は 1 行、since は10日前も含む）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): 他のトレーナー宛て / 担当が替わった / clients に無い顧客のメッセージ → 0行
--   あわせて、トレーナー A の結果が期待の8顧客ちょうどであること（余計な行が無い）を確かめる
-- -----------------------------------------------------------------------------
\echo '--- case e: 他のトレーナー宛て・担当替え・clients に無い送信者は出ず、A の結果が期待の8顧客ちょうどであること'

DO $$
DECLARE
  cnt   int;
  v_ids uuid[];
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000010';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e) 担当が B に替わった c10 が前のトレーナー A に % 行出た（期待 0 行）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000011';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e) 他のトレーナー B 宛てに送った c11 が A に % 行出た（期待 0 行）', cnt;
  END IF;

  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'dddddddd-0922-0000-0000-0000000000d1';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e) clients に行が無い送信者 X が A に % 行出た（期待 0 行）', cnt;
  END IF;

  v_ids := ARRAY(SELECT f.client_id FROM public.get_unreplied_clients_for_trainer() f ORDER BY f.client_id);
  IF v_ids IS DISTINCT FROM ARRAY[
       'aaaaaaaa-0922-0000-0000-00000000000c',  -- K（兼務。顧客として送った分）
       'cccccccc-0922-0000-0000-000000000001',
       'cccccccc-0922-0000-0000-000000000003',
       'cccccccc-0922-0000-0000-000000000006',
       'cccccccc-0922-0000-0000-000000000008',
       'cccccccc-0922-0000-0000-000000000009',
       'cccccccc-0922-0000-0000-000000000013',
       'cccccccc-0922-0000-0000-000000000014'
     ]::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (e) トレーナー A の結果が %（期待 K・c01・c03・c06・c08・c09・c13・c14）', v_ids;
  END IF;
  RAISE NOTICE 'OK: (e) 他のトレーナー宛て・担当替え・clients に無い送信者は 0 行。A の結果は期待の8顧客ちょうど';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(f): トレーナー B が呼んでも A の顧客は出ない
--   B の担当は b1 と、担当替えで移ってきた c10（c10 のメッセージは A 宛てなので B には出ない）。
--   c11（A の顧客）が B 宛てに送った分も、B の担当顧客ではないので出ない
-- -----------------------------------------------------------------------------
\echo '--- case f: トレーナー(B) には自分の顧客 b1 だけが出ること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0922-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0922-0000-0000-00000000000b';

DO $$
DECLARE
  v_ids uuid[];
  v_row record;
BEGIN
  v_ids := ARRAY(SELECT f.client_id FROM public.get_unreplied_clients_for_trainer() f ORDER BY f.client_id);
  IF v_ids IS DISTINCT FROM ARRAY['cccccccc-0922-0000-0000-0000000000b1']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (f) トレーナー B の結果が %（期待 b1 のみ。A の顧客・A 宛ては出ない）', v_ids;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f;
  IF v_row.unreplied_count IS DISTINCT FROM 1
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '5 hours' THEN
    RAISE EXCEPTION 'FAIL: (f) b1 が count=% since=%（期待 1 / 5時間前）', v_row.unreplied_count, v_row.unreplied_since;
  END IF;
  RAISE NOTICE 'OK: (f) トレーナー B には自分の顧客 b1 だけが出る（A の顧客は出ない）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): 顧客本人が呼ぶと 0 行
--   c01（A の顧客。A からの返信を受け取っている）と、兼務 K（A の顧客で、担当顧客のいないトレーナー）
-- -----------------------------------------------------------------------------
\echo '--- case g: 顧客(c01) 本人・兼務(K) が呼ぶと 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-0922-0000-0000-000000000001","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-0922-0000-0000-000000000001';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (g) 顧客(c01) 本人が呼んで % 行（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: (g) 顧客本人が呼ぶと 0 行';
END $$;

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000c","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000c';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (g) 兼務(K) が呼んで % 行（期待 0 行。K に担当顧客はいない）', cnt;
  END IF;
  RAISE NOTICE 'OK: (g) 兼務(K) が呼んでも、担当の A 側の顧客は出ない（0 行）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-1): anon（JWT クレーム無し）は EXECUTE できない
--   直前のケースのクレームが残っていると auth.uid() が値を返してしまうため、
--   両形式を空にしてからロールを切り替える（auth.uid() は nullif(..., '') で NULL に落ちる）
-- -----------------------------------------------------------------------------
\echo '--- case h-1: anon（クレーム無し）の EXECUTE が permission denied であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM 1 FROM public.get_unreplied_clients_for_trainer();
  RAISE EXCEPTION 'FAIL: (h-1) anon（クレーム無し）が get_unreplied_clients_for_trainer を実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function get_unreplied_clients_for_trainer%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: (h-1) anon（クレーム無し）の EXECUTE は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-2): anon ロール + トレーナー A の JWT クレームでも EXECUTE できない
--   auth.uid() が A を返す状態のまま anon で呼び、role 単位の EXECUTE 剥奪で拒否されることを
--   直接確かめる。messages / clients のポリシーの多くは TO public（anon を含む）で、anon には
--   両テーブルの SELECT 権限もあるので、anon に EXECUTE が残っていればこの状態で A の行が返る
-- -----------------------------------------------------------------------------
\echo '--- case h-2: anon ロール + トレーナー(A) クレームでも EXECUTE が permission denied であること'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000a';
SET LOCAL ROLE anon;

DO $$
BEGIN
  -- 前提確認: auth.uid() がトレーナー A を返している（クレームが効いている）こと
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-0922-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — anon ロールで auth.uid() が %（期待 トレーナーA の UUID）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  BEGIN
    PERFORM 1 FROM public.get_unreplied_clients_for_trainer();
    RAISE EXCEPTION 'FAIL: (h-2) anon ロール + トレーナー(A) クレームで get_unreplied_clients_for_trainer を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function get_unreplied_clients_for_trainer%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: (h-2) anon ロール + トレーナー(A) クレームでも EXECUTE は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(i): 自分宛て（sender = receiver）は除かれる
--   A は自己登録の顧客行（client_id = trainer_id = A）を持ち、A から A 自身へ sender_type = client の
--   タグ無しメッセージがある。A の結果に client_id = A の行は出ない。
--   このメッセージは sender_type = client なので A の返信には数えられない（返信は sender_type = trainer だけ）。
--   そのため client_id <> auth.uid() を外すと A の行が出て、このケースが落ちる
-- -----------------------------------------------------------------------------
\echo '--- case i: 自分宛て（自己登録のトレーナーが自分に送ったもの）が出ないこと'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'aaaaaaaa-0922-0000-0000-00000000000a';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (i) 自分宛て（A → A）が % 行出た（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: (i) 自分宛て（sender = receiver）は出ない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(j): 顧客が書ける created_at の未来・±infinity の値は数えない
--   c12: +infinity と1日後のメッセージがあり、A は1分前に返信済み → 0 行
--        （数えてしまうと、返信しても未返信が消えず、latest_unreplied_at が infinity になる）
--   c13: -infinity と30分前 → 30分前の1件だけ（unreplied_since に -infinity が出ない）
-- -----------------------------------------------------------------------------
\echo '--- case j: 未来・±infinity の created_at を数えないこと'

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000012';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (j) 未来・+infinity の created_at しか残っていない c12 が % 行出た（期待 0 行）', cnt;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000013';
  IF v_row.unreplied_count IS DISTINCT FROM 1
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '30 minutes'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '30 minutes' THEN
    RAISE EXCEPTION 'FAIL: (j) c13 が count=% since=% latest=%（期待 1 / 30分前 / 30分前。-infinity は数えない）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;

  -- どの行にも非有限・未来の日時が出ない（Web の時間計算が NaN にならない）
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer() f
   WHERE NOT isfinite(f.unreplied_since) OR NOT isfinite(f.latest_unreplied_at)
      OR f.latest_unreplied_at > now();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (j) 非有限・未来の日時を持つ行が % 行ある', cnt;
  END IF;
  RAISE NOTICE 'OK: (j) 未来・±infinity の created_at は数えない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(k): 兼務 — 担当顧客がトレーナーとして送ったメッセージは未返信に数えない
--   K → A: 顧客として（2時間前、数える）/ トレーナーとして（20分前、数えない）
-- -----------------------------------------------------------------------------
\echo '--- case k: 兼務(K) がトレーナーとして送ったメッセージを未返信に数えないこと'

DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'aaaaaaaa-0922-0000-0000-00000000000c';
  IF v_row.unreplied_count IS DISTINCT FROM 1
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '2 hours'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '2 hours' THEN
    RAISE EXCEPTION 'FAIL: (k) K が count=% since=% latest=%（期待 1 / 2時間前 / 2時間前。sender_type = trainer は数えない）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;
  RAISE NOTICE 'OK: (k) 兼務の顧客がトレーナーとして送ったメッセージは数えない';
END $$;

-- (k-2) 互いに担当し合う L・M: L が呼ぶと、M の相談（2時間前）は未返信のまま。
--       その後に L が M の顧客として送った記録投稿（sender_type = client）は、L から M への返信ではない
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000d","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000d';

DO $$
DECLARE
  v_ids uuid[];
  v_row record;
BEGIN
  v_ids := ARRAY(SELECT f.client_id FROM public.get_unreplied_clients_for_trainer() f ORDER BY f.client_id);
  IF v_ids IS DISTINCT FROM ARRAY['aaaaaaaa-0922-0000-0000-00000000000e']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (k) 兼務 L の結果が %（期待 M のみ。L が M の顧客として送った投稿を返信に数えている）', v_ids;
  END IF;

  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f;
  IF v_row.unreplied_count IS DISTINCT FROM 1
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '2 hours' THEN
    RAISE EXCEPTION 'FAIL: (k) M が count=% since=%（期待 1 / 2時間前）', v_row.unreplied_count, v_row.unreplied_since;
  END IF;
  RAISE NOTICE 'OK: (k) 互いに担当し合う2人で、相手の顧客として送った投稿（sender_type = client）は返信に数えない';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(l): RLS が効かない状態でも、関数の条件だけで本人の担当顧客に絞れる
--   service_role は BYPASSRLS で、既定権限により EXECUTE も残っている。クレームを付けて呼ぶと
--   messages / clients の RLS は掛からず、関数の WHERE（担当・宛先・種別・タグ・7日）だけが効く。
--   結果が authenticated で呼んだときと同じなら、関数の条件と RLS のどちらか片方が外れても守れる
--   （二重の守り）。sub の無い呼び出し（Edge Function・API Route の supabaseAdmin）は 0 行。
--   RLS が無いと、担当関係の無いトレーナー B が c01 に送ったメッセージも見える。これを A の返信に
--   数えない（返信は r.sender_id = auth.uid() だけ）ことも、c01 の count / since で確かめる
-- -----------------------------------------------------------------------------
\echo '--- case l: service_role（BYPASSRLS）+ クレームでも関数の条件だけで絞れ、sub 無しは 0 行であること'

SET LOCAL ROLE service_role;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0922-0000-0000-00000000000a","role":"service_role"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0922-0000-0000-00000000000a';

DO $$
DECLARE
  v_ids uuid[];
  v_row record;
BEGIN
  v_ids := ARRAY(SELECT f.client_id FROM public.get_unreplied_clients_for_trainer() f ORDER BY f.client_id);
  IF v_ids IS DISTINCT FROM ARRAY[
       'aaaaaaaa-0922-0000-0000-00000000000c',
       'cccccccc-0922-0000-0000-000000000001',
       'cccccccc-0922-0000-0000-000000000003',
       'cccccccc-0922-0000-0000-000000000006',
       'cccccccc-0922-0000-0000-000000000008',
       'cccccccc-0922-0000-0000-000000000009',
       'cccccccc-0922-0000-0000-000000000013',
       'cccccccc-0922-0000-0000-000000000014'
     ]::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (l) RLS なし（service_role）+ A のクレームの結果が %（期待 K・c01・c03・c06・c08・c09・c13・c14。関数の条件が担当顧客に絞れていない / 第三者の送信を返信に数えている）', v_ids;
  END IF;

  -- 第三者 B の送信（30分前）が見えていても、c01 の未返信は authenticated のときと同じ
  SELECT * INTO v_row FROM public.get_unreplied_clients_for_trainer() f
   WHERE f.client_id = 'cccccccc-0922-0000-0000-000000000001';
  IF v_row.unreplied_count IS DISTINCT FROM 2
     OR v_row.unreplied_since IS DISTINCT FROM now() - interval '2 days'
     OR v_row.latest_unreplied_at IS DISTINCT FROM now() - interval '1 hour' THEN
    RAISE EXCEPTION 'FAIL: (l) RLS なしの c01 が count=% since=% latest=%（期待 2 / 2日前 / 1時間前。第三者 B の送信を A の返信に数えている）',
      v_row.unreplied_count, v_row.unreplied_since, v_row.latest_unreplied_at;
  END IF;
  RAISE NOTICE 'OK: (l) RLS なしでも A の結果は authenticated と同じ8顧客（関数の条件で絞れ、第三者の送信を返信に数えない）';
END $$;

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0922-0000-0000-00000000000b","role":"service_role"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0922-0000-0000-00000000000b';

DO $$
DECLARE v_ids uuid[];
BEGIN
  v_ids := ARRAY(SELECT f.client_id FROM public.get_unreplied_clients_for_trainer() f ORDER BY f.client_id);
  IF v_ids IS DISTINCT FROM ARRAY['cccccccc-0922-0000-0000-0000000000b1']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: (l) RLS なし（service_role）+ B のクレームの結果が %（期待 b1 のみ。c10・c11 が出るなら担当の条件が効いていない）', v_ids;
  END IF;
  RAISE NOTICE 'OK: (l) RLS なしでも B の結果は b1 だけ（担当替えの c10・他のトレーナーの顧客 c11 は出ない）';
END $$;

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_unreplied_clients_for_trainer();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (l) sub の無い service_role の呼び出しが % 行（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: (l) sub の無い service_role の呼び出しは 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(m): メタデータ（postgres として実行）
--   - SECURITY INVOKER（prosecdef = false）/ STABLE / LANGUAGE sql / 引数なし
--   - search_path が空文字に固定されている（proconfig = {search_path=""}）
--   - 戻り列が許可リストちょうど
--   - EXECUTE: PUBLIC・anon に無く、authenticated に有る
-- -----------------------------------------------------------------------------
\echo '--- case m: INVOKER / STABLE / sql / 引数なし / search_path / 戻り列 / EXECUTE 権限'

DO $$
DECLARE
  v_fn  regprocedure := 'public.get_unreplied_clients_for_trainer()'::regprocedure;
  v_p   record;
BEGIN
  SELECT p.prosecdef, p.provolatile, l.lanname, p.pronargs, p.proconfig,
         pg_get_function_result(p.oid) AS result
    INTO v_p
    FROM pg_proc p
    JOIN pg_language l ON l.oid = p.prolang
   WHERE p.oid = v_fn;

  IF v_p.prosecdef THEN
    RAISE EXCEPTION 'FAIL: (m) SECURITY DEFINER になっている（期待 INVOKER。RLS を外さない）';
  END IF;
  IF v_p.provolatile <> 's' OR v_p.lanname <> 'sql' OR v_p.pronargs <> 0 THEN
    RAISE EXCEPTION 'FAIL: (m) provolatile=% / lang=% / nargs=%（期待 s / sql / 0）',
      v_p.provolatile, v_p.lanname, v_p.pronargs;
  END IF;
  IF v_p.proconfig IS DISTINCT FROM ARRAY['search_path=""'] THEN
    RAISE EXCEPTION 'FAIL: (m) search_path が空文字に固定されていない（proconfig=%）',
      coalesce(v_p.proconfig::text, 'NULL');
  END IF;
  IF v_p.result IS DISTINCT FROM
     'TABLE(client_id uuid, client_name text, profile_image_url text, '
     'unreplied_since timestamp with time zone, latest_unreplied_at timestamp with time zone, '
     'unreplied_count integer)' THEN
    RAISE EXCEPTION 'FAIL: (m) 戻り列が許可リストと異なる: %', v_p.result;
  END IF;

  -- proacl が NULL（未変更）なら既定の PUBLIC EXECUTE が生きているため acldefault で補う
  IF EXISTS (
    SELECT 1
      FROM pg_proc p,
           aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
     WHERE p.oid = v_fn
       AND a.grantee = 0  -- 0 = PUBLIC
  ) THEN
    RAISE EXCEPTION 'FAIL: (m) EXECUTE が PUBLIC に付与されたまま';
  END IF;
  IF has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: (m) EXECUTE 権限が期待と異なる（anon は無し、authenticated は有り）';
  END IF;
  RAISE NOTICE 'OK: (m) INVOKER / STABLE / sql / 引数なし / search_path = '''' / 戻り列の許可リスト / EXECUTE は authenticated のみ';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL TRIAGE UNREPLIED TESTS PASSED'
