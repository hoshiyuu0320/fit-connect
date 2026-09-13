-- =============================================================================
-- client_activity_snapshot（活動痕跡・最終記録日・監視対象）のテスト
-- （フェーズ9.1 / 20260914000100_client_activity_snapshot.sql）
--
-- 顧客ごとの 登録日 J（join_on）・最終到着日 R（last_activity_on）・最終記録日 L（last_record_on）・
-- exclusion_reason を、痕跡の種類ごとに1つずつ入れた試験用顧客で検証する自己完結テスト
-- （session_reminder_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/client_activity_snapshot_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CLIENT ACTIVITY SNAPSHOT TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
-- - 検証は試験用の顧客に限る（seed の顧客も snapshot に出るため、client_id で絞る）
-- - messages の AFTER INSERT トリガー（call_parse_message_tags）は本番 URL へ net.http_post を
--   積むため、試験メッセージの INSERT の間だけ session_replication_role = replica でトリガーを
--   止める（ROLLBACK で要求も消えるが二重に防ぐ。net.http_request_queue が増えないことも確かめる）
-- - EXECUTE 権限（service_role のみ）は client_alerts_rls_test.sql で確かめる。ここでは
--   service_role として呼ぶ（検知関数・Edge Function の RPC 相当）
--
-- 対象日 D = 2026-08-20、締め時刻 as_of = 2026-08-20 06:00 JST（= 2026-08-19 21:00 UTC。
-- 06:00 JST の cron と同じ時刻）。D−14 = 08-06、D−15 = 08-05、D−60 = 06-21。
-- 痕跡用の顧客は 06-01 12:00 JST に登録し（J = 06-01）、06-02 に計測した「古い体重」を1件持つ
-- （L の土台。計測が D−60 より前なので R には入らない）。そのうえで痕跡を1種類だけ足し、
-- R がその痕跡の JST 日付になることを見る。
--
-- JST の境界（lessons「JST の『暦日』判定は範囲比較で書く」）:
--   D の JST 0:30 = UTC 08-19 15:30。UTC の日付で判定すると 08-19（= D−1）に入ってしまう。
--   L はこれを数えず（計測日が D−1 以前だけ）、R は数える（到着は as_of 以前）
--
-- 検証ケース（計画書 PR1 レーンA-5）:
--   (a) 痕跡の種類ごとの取り込み: 登録 / 顧客が送ったメッセージ / 顧客宛ての既読 /
--       体重の created_at・updated_at・created_at が NULL（recorded_at を使う）/ 食事 / 運動（created_at NULL）/
--       睡眠の created_at・updated_at / ai_estimation_logs
--   (b) 締め時刻より後に届いたもの（created_at / updated_at / read_at / 登録）は数えない。
--       計測は締め時刻より前でも到着が後の体重・食事・運動、created_at は前でも updated_at が後の睡眠も同じ。
--       R は到着時刻だけで決まる: 計測が締め時刻より後（未来の日時）でも、締め時刻までに届いた記録は
--       R に数える（L には数えない）。締め時刻より後に届いた未来の記録は R にも数えない
--       （表ごとに顧客を分け、体重・食事・運動・睡眠のどれか1つだけ計測時刻で絞っても落ちるようにする）
--   (c) トレーナーが送ったメッセージの created_at は顧客の活動に数えず、顧客宛ての read_at は数える
--   (d) 兼務アカウント: トレーナーとして送ったメッセージ（sender_type = trainer）と、トレーナーとして
--       付けた既読（receiver_type = trainer。Web の既読）は、そのアカウントの顧客としての活動に数えない
--   (e) 端末の時計で書かれる列（device_tokens.last_seen_at、workout_assignments の started_at /
--       finished_at）を使っていない
--   (f) L: 記録4表とメッセージ、sleep は recorded_date、D の JST 0:30 の計測は D−1 に入らない
--   (g) exclusion_reason: no_account / self / not_started（D − J = 14 は監視、15 は対象外）/
--       inactive（R = D−14 は監視、D−15 は対象外）/ 生きている record_gap・weight_change があっても
--       監視は延ばさない（オーナー決定 (1)。監視対象は alerts に依らない）
--   (h) p_trainer_id で担当顧客に絞れる / 締め時刻より後に登録された顧客は返さない
--   (i) 今の担当トレーナー以外（担当関係の無い送信者・別のトレーナー）が送ったメッセージの read_at は
--       R に数えない（messages の INSERT ポリシーは sender_id だけを見るので、送信者が read_at を偽造できる）
--   (j) 登録日が ±infinity（顧客本人が clients.created_at を書き換えた）の顧客は返さず、例外にもならない
--   (k) HealthKit の体重（計測日の 23:59 JST で入る）: D の 05:00 JST に届いた D の体重は、計測時刻が
--       締め時刻 06:00 より後でも R = D にする（体重だけ連携している顧客が同期済みなのに「記録・同期なし」
--       にならない）。締め時刻を 05:00 より前にずらすと数えない
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer T  : aaaaaaaa-0914-0001-0000-00000000000a（ほとんどの試験用顧客の担当）
--   trainer T2 : aaaaaaaa-0914-0001-0000-00000000000b（前の担当 / p_trainer_id の絞り込み用）
--   trainer K  : aaaaaaaa-0914-0001-0000-00000000000c（兼務: T の顧客でもあり、Z の担当でもある）
--   trainer XS : aaaaaaaa-0914-0001-0000-00000000000d（自己登録: 自分自身が顧客）
--   trainer T3 : aaaaaaaa-0914-0001-0000-00000000000e（計測時刻の試験用の顧客 35〜38 の担当。T の顧客数は
--                business の上限 30 人に近いので分ける）
--   client  NN : cccccccc-0914-0001-0000-0000000000NN（下の一覧。15 は K 自身なので欠番）
--     01 REG          : 登録だけ（08-15 10:00 JST）
--     02 MSG          : 顧客が送ったメッセージ 08-18
--     03 READ         : 顧客宛て（07-10 送信）の既読 08-17
--     04 W_CREATED    : 体重 計測 08-10・到着 08-16
--     05 W_UPDATED    : 体重 計測 08-01・到着 08-02・updated_at 08-19
--     06 W_NULL       : 体重 計測 08-12・created_at / updated_at が NULL
--     07 MEAL         : 食事 計測 08-13・到着 08-14
--     08 EX_NULL      : 運動 計測 08-09・created_at が NULL
--     09 SLEEP_C      : 睡眠 起床日 08-12・到着 08-13
--     10 SLEEP_U      : 睡眠 起床日 08-05・到着 08-06・updated_at 08-19
--     11 AI           : AI 推定 08-18
--     12 LATE         : 締め時刻より後に届いた痕跡だけ（+ 08-01 の体重と 07-31 の睡眠。どちらも
--                       updated_at は締め時刻の後）。食事 08-18・運動 08-17 は計測が前で到着が後
--     13 FUTURE_W     : 体重だけ。計測が締め時刻より後（未来）で、到着が 08-18（締め時刻の前）と
--                       08-20 07:00（締め時刻の後）の2件
--     14 TRAINER_MSG  : トレーナーからのメッセージ 08-18（未読）と、別メッセージの既読 08-16
--     16 DEVICE       : device_tokens.last_seen_at と workout の finished_at だけが 08-19
--     17 L_JST        : D の JST 0:30 の体重・食事・運動・メッセージと、08-15 の体重
--     18 L_SLEEP      : 睡眠 起床日 08-19（到着 D 05:00）と起床日 08-20（到着 D 05:30）
--     19 NOACC        : auth.users に行が無い
--     21 NS14         : 登録 08-06（D − J = 14）・記録なし
--     22 NS15         : 登録 08-05（D − J = 15）・記録なし
--     23 IN14         : 最後の痕跡が 08-06（R = D−14）の既読
--     24 IN15         : 最後の痕跡が 08-05（R = D−15）の既読
--     25 LIVEGAP      : R は古いが、今の担当 T の生きている record_gap がある（監視は延ばさない）
--     26 LIVEGAP_OLD  : R は古く、前の担当 T2 の record_gap だけが生きている
--     27 LIVE_WEIGHT  : R は古く、生きているのは weight_change だけ
--     28 RESOLVED_GAP : R は古く、record_gap は resolved
--     29 T2_CLIENT    : T2 の顧客（登録 08-15）
--     30 AFTER        : 締め時刻より後（08-20 07:00 JST）に登録
--     31 Z            : 兼務トレーナー K の顧客
--     32 FORGED_READ  : 今の担当 T 以外（担当関係の無い送信者 X・トレーナー T2）が送ったメッセージの既読だけが新しい
--     33 NEG_INF      : T2 の顧客。登録日 '-infinity'・記録なし
--     34 POS_INF      : T2 の顧客。登録日 'infinity'
--     35 FUTURE_M     : T3 の顧客。食事だけ。計測が未来で、到着が 08-18 と 08-20 07:00
--     36 FUTURE_E     : T3 の顧客。運動だけ。計測が未来で、到着が 08-18 と 08-20 07:10
--     37 FUTURE_S     : T3 の顧客。睡眠だけ。起床日が未来で、到着が 08-18 と 08-20 07:00
--     38 HK_WEIGHT    : T3 の顧客。HealthKit の体重だけ（計測日の 23:59 JST で入る。「古い体重」は持たない）。
--                       08-15 分は 08-15 07:00 に、D（08-20）分は D の 05:00（締め時刻の前）に届いた
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer T・T2・K・XS・T3 / client 01〜38)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'snapshot-test-' || v.id || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-0914-0001-0000-00000000000a'), ('aaaaaaaa-0914-0001-0000-00000000000b'),
    ('aaaaaaaa-0914-0001-0000-00000000000c'), ('aaaaaaaa-0914-0001-0000-00000000000d'),
    ('aaaaaaaa-0914-0001-0000-00000000000e'),
    ('cccccccc-0914-0001-0000-000000000001'), ('cccccccc-0914-0001-0000-000000000002'),
    ('cccccccc-0914-0001-0000-000000000003'), ('cccccccc-0914-0001-0000-000000000004'),
    ('cccccccc-0914-0001-0000-000000000005'), ('cccccccc-0914-0001-0000-000000000006'),
    ('cccccccc-0914-0001-0000-000000000007'), ('cccccccc-0914-0001-0000-000000000008'),
    ('cccccccc-0914-0001-0000-000000000009'), ('cccccccc-0914-0001-0000-000000000010'),
    ('cccccccc-0914-0001-0000-000000000011'), ('cccccccc-0914-0001-0000-000000000012'),
    ('cccccccc-0914-0001-0000-000000000013'), ('cccccccc-0914-0001-0000-000000000014'),
    ('cccccccc-0914-0001-0000-000000000016'), ('cccccccc-0914-0001-0000-000000000017'),
    ('cccccccc-0914-0001-0000-000000000018'),
    -- 19 NOACC は auth.users に入れない
    ('cccccccc-0914-0001-0000-000000000021'), ('cccccccc-0914-0001-0000-000000000022'),
    ('cccccccc-0914-0001-0000-000000000023'), ('cccccccc-0914-0001-0000-000000000024'),
    ('cccccccc-0914-0001-0000-000000000025'), ('cccccccc-0914-0001-0000-000000000026'),
    ('cccccccc-0914-0001-0000-000000000027'), ('cccccccc-0914-0001-0000-000000000028'),
    ('cccccccc-0914-0001-0000-000000000029'), ('cccccccc-0914-0001-0000-000000000030'),
    ('cccccccc-0914-0001-0000-000000000031'), ('cccccccc-0914-0001-0000-000000000032'),
    ('cccccccc-0914-0001-0000-000000000033'), ('cccccccc-0914-0001-0000-000000000034'),
    ('cccccccc-0914-0001-0000-000000000035'), ('cccccccc-0914-0001-0000-000000000036'),
    ('cccccccc-0914-0001-0000-000000000037'), ('cccccccc-0914-0001-0000-000000000038')
  ) AS v(id);

-- 顧客数の上限（enforce_client_limit）に掛からないよう business にしておく（T の顧客は 29 人。
-- business の上限は 30 人なので、計測時刻の試験用の顧客 35〜38 は T3 の担当にする）
INSERT INTO public.trainers (id, name, email, subscription_plan)
SELECT v.id::uuid, v.name, 'snapshot-test-' || v.id || '@example.com', 'business'
  FROM (VALUES
    ('aaaaaaaa-0914-0001-0000-00000000000a', 'スナップショットテスト トレーナーT'),
    ('aaaaaaaa-0914-0001-0000-00000000000b', 'スナップショットテスト トレーナーT2'),
    ('aaaaaaaa-0914-0001-0000-00000000000c', 'スナップショットテスト 兼務K'),
    ('aaaaaaaa-0914-0001-0000-00000000000d', 'スナップショットテスト 自己登録XS'),
    ('aaaaaaaa-0914-0001-0000-00000000000e', 'スナップショットテスト トレーナーT3')
  ) AS v(id, name);

INSERT INTO public.clients (client_id, name, trainer_id, created_at)
SELECT v.id::uuid, 'スナップショットテスト顧客' || v.label, v.trainer::uuid, v.created_at::timestamptz
  FROM (VALUES
    ('cccccccc-0914-0001-0000-000000000001', '01 REG',          'aaaaaaaa-0914-0001-0000-00000000000a', '2026-08-15 10:00+09'),
    ('cccccccc-0914-0001-0000-000000000002', '02 MSG',          'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000003', '03 READ',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000004', '04 W_CREATED',    'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000005', '05 W_UPDATED',    'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000006', '06 W_NULL',       'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000007', '07 MEAL',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000008', '08 EX_NULL',      'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000009', '09 SLEEP_C',      'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000010', '10 SLEEP_U',      'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000011', '11 AI',           'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000012', '12 LATE',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000013', '13 FUTURE_W',     'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000014', '14 TRAINER_MSG',  'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('aaaaaaaa-0914-0001-0000-00000000000c', '15 K（兼務）',    'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000016', '16 DEVICE',       'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000017', '17 L_JST',        'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000018', '18 L_SLEEP',      'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000019', '19 NOACC',        'aaaaaaaa-0914-0001-0000-00000000000a', '2026-08-15 10:00+09'),
    ('aaaaaaaa-0914-0001-0000-00000000000d', '20 SELF',         'aaaaaaaa-0914-0001-0000-00000000000d', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000021', '21 NS14',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-08-06 10:00+09'),
    ('cccccccc-0914-0001-0000-000000000022', '22 NS15',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-08-05 10:00+09'),
    ('cccccccc-0914-0001-0000-000000000023', '23 IN14',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000024', '24 IN15',         'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000025', '25 LIVEGAP',      'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000026', '26 LIVEGAP_OLD',  'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000027', '27 LIVE_WEIGHT',  'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000028', '28 RESOLVED_GAP', 'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000029', '29 T2_CLIENT',    'aaaaaaaa-0914-0001-0000-00000000000b', '2026-08-15 10:00+09'),
    ('cccccccc-0914-0001-0000-000000000030', '30 AFTER',        'aaaaaaaa-0914-0001-0000-00000000000a', '2026-08-20 07:00+09'),
    ('cccccccc-0914-0001-0000-000000000031', '31 Z',            'aaaaaaaa-0914-0001-0000-00000000000c', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000032', '32 FORGED_READ',  'aaaaaaaa-0914-0001-0000-00000000000a', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000033', '33 NEG_INF',      'aaaaaaaa-0914-0001-0000-00000000000b', '-infinity'),
    ('cccccccc-0914-0001-0000-000000000034', '34 POS_INF',      'aaaaaaaa-0914-0001-0000-00000000000b', 'infinity'),
    ('cccccccc-0914-0001-0000-000000000035', '35 FUTURE_M',     'aaaaaaaa-0914-0001-0000-00000000000e', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000036', '36 FUTURE_E',     'aaaaaaaa-0914-0001-0000-00000000000e', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000037', '37 FUTURE_S',     'aaaaaaaa-0914-0001-0000-00000000000e', '2026-06-01 12:00+09'),
    ('cccccccc-0914-0001-0000-000000000038', '38 HK_WEIGHT',    'aaaaaaaa-0914-0001-0000-00000000000e', '2026-06-01 12:00+09')
  ) AS v(id, label, trainer, created_at);

-- 「古い体重」（06-02 計測・到着）。L の土台で、計測が D−60 より前なので R には入らない
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT v.id::uuid, 60.0, '2026-06-02 08:00+09', 'manual', '2026-06-02 08:00+09', '2026-06-02 08:00+09'
  FROM (VALUES
    ('cccccccc-0914-0001-0000-000000000002'), ('cccccccc-0914-0001-0000-000000000003'),
    ('cccccccc-0914-0001-0000-000000000004'), ('cccccccc-0914-0001-0000-000000000005'),
    ('cccccccc-0914-0001-0000-000000000006'), ('cccccccc-0914-0001-0000-000000000007'),
    ('cccccccc-0914-0001-0000-000000000008'), ('cccccccc-0914-0001-0000-000000000009'),
    ('cccccccc-0914-0001-0000-000000000010'), ('cccccccc-0914-0001-0000-000000000011'),
    ('cccccccc-0914-0001-0000-000000000012'), ('cccccccc-0914-0001-0000-000000000013'),
    ('cccccccc-0914-0001-0000-000000000014'), ('aaaaaaaa-0914-0001-0000-00000000000c'),
    ('cccccccc-0914-0001-0000-000000000016'), ('cccccccc-0914-0001-0000-000000000017'),
    ('cccccccc-0914-0001-0000-000000000018'), ('cccccccc-0914-0001-0000-000000000023'),
    ('cccccccc-0914-0001-0000-000000000024'), ('cccccccc-0914-0001-0000-000000000025'),
    ('cccccccc-0914-0001-0000-000000000026'), ('cccccccc-0914-0001-0000-000000000027'),
    ('cccccccc-0914-0001-0000-000000000028'), ('cccccccc-0914-0001-0000-000000000031'),
    ('cccccccc-0914-0001-0000-000000000032'), ('cccccccc-0914-0001-0000-000000000035'),
    ('cccccccc-0914-0001-0000-000000000036'), ('cccccccc-0914-0001-0000-000000000037')
  ) AS v(id);

-- 痕跡ごとの記録（計測 recorded_at / 到着 created_at / updated_at を JST で明示する）
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at) VALUES
  -- 04 W_CREATED: 到着 08-16
  ('cccccccc-0914-0001-0000-000000000004', 61.0, '2026-08-10 23:59+09', 'healthkit', '2026-08-16 08:00+09', '2026-08-16 08:00+09'),
  -- 05 W_UPDATED: 到着 08-02、updated_at 08-19（HealthKit の再同期で値が変わった）
  ('cccccccc-0914-0001-0000-000000000005', 61.0, '2026-08-01 23:59+09', 'healthkit', '2026-08-02 08:00+09', '2026-08-19 07:00+09'),
  -- 06 W_NULL: created_at / updated_at が NULL の古い行 → recorded_at 08-12 を到着として使う
  ('cccccccc-0914-0001-0000-000000000006', 61.0, '2026-08-12 09:00+09', 'manual', NULL, NULL),
  -- 12 LATE: 08-01 の体重（到着 08-01）。updated_at は締め時刻の後なので数えない
  ('cccccccc-0914-0001-0000-000000000012', 61.0, '2026-08-01 08:00+09', 'healthkit', '2026-08-01 08:05+09', '2026-08-20 07:00+09'),
  -- 12 LATE: 計測 08-19 だが、届いたのは締め時刻（08-20 06:00 JST）の後
  ('cccccccc-0914-0001-0000-000000000012', 61.0, '2026-08-19 20:00+09', 'healthkit', '2026-08-20 07:00+09', '2026-08-20 07:00+09'),
  -- 13 FUTURE_W: 計測は 08-25（未来。端末の時計のずれ等）だが、届いたのは 08-18（締め時刻の前）
  --   → R に数える（R は到着だけで決まる）。L には数えない（計測日が D−1 より後）
  ('cccccccc-0914-0001-0000-000000000013', 61.0, '2026-08-25 08:00+09', 'manual', '2026-08-18 08:00+09', '2026-08-18 08:00+09'),
  -- 13 FUTURE_W: 計測 08-26（未来）で、届いたのは締め時刻の後 → R にも数えない
  ('cccccccc-0914-0001-0000-000000000013', 61.0, '2026-08-26 08:00+09', 'manual', '2026-08-20 07:00+09', '2026-08-20 07:00+09'),
  -- 17 L_JST: D の JST 0:30（= UTC 08-19 15:30）の計測は L に入らない。08-15 の計測が L
  ('cccccccc-0914-0001-0000-000000000017', 61.0, '2026-08-20 00:30+09', 'manual', '2026-08-20 00:40+09', '2026-08-20 00:40+09'),
  ('cccccccc-0914-0001-0000-000000000017', 61.0, '2026-08-15 08:00+09', 'manual', '2026-08-15 08:05+09', '2026-08-15 08:05+09'),
  -- 38 HK_WEIGHT: HealthKit の体重は計測日の 23:59 JST で入る。08-15 分は 08-15 07:00 に届いた
  ('cccccccc-0914-0001-0000-000000000038', 61.0, '2026-08-15 23:59+09', 'healthkit', '2026-08-15 07:00+09', '2026-08-15 07:00+09'),
  -- 38 HK_WEIGHT: D（08-20）分は D の 05:00 に届いた。計測時刻（D 23:59）は締め時刻（D 06:00）より後だが、
  --   締め時刻の前に届いているので R = D。L には入らない（計測日が D）
  ('cccccccc-0914-0001-0000-000000000038', 61.0, '2026-08-20 23:59+09', 'healthkit', '2026-08-20 05:00+09', '2026-08-20 05:00+09');

INSERT INTO public.meal_records (client_id, meal_type, recorded_at, source, created_at, updated_at) VALUES
  -- 07 MEAL: 計測 08-13・到着 08-14
  ('cccccccc-0914-0001-0000-000000000007', 'lunch', '2026-08-13 12:00+09', 'manual', '2026-08-14 12:00+09', '2026-08-14 12:00+09'),
  -- 12 LATE: 計測 08-18（締め時刻より前）だが、届いたのは締め時刻の後 → R にも L にも数えない
  ('cccccccc-0914-0001-0000-000000000012', 'dinner', '2026-08-18 19:00+09', 'manual', '2026-08-20 07:00+09', '2026-08-20 07:00+09'),
  -- 17 L_JST: D の JST 0:30
  ('cccccccc-0914-0001-0000-000000000017', 'snack', '2026-08-20 00:30+09', 'manual', '2026-08-20 00:41+09', '2026-08-20 00:41+09'),
  -- 35 FUTURE_M: 計測 08-21（未来）・到着 08-18（締め時刻の前）→ R に数える（L には数えない）
  ('cccccccc-0914-0001-0000-000000000035', 'lunch', '2026-08-21 12:00+09', 'manual', '2026-08-18 12:00+09', '2026-08-18 12:00+09'),
  -- 35 FUTURE_M: 計測 08-22（未来）・到着は締め時刻の後 → R にも数えない
  ('cccccccc-0914-0001-0000-000000000035', 'lunch', '2026-08-22 12:00+09', 'manual', '2026-08-20 07:00+09', '2026-08-20 07:00+09');

INSERT INTO public.exercise_records (client_id, exercise_type, recorded_at, source, created_at, updated_at) VALUES
  -- 08 EX_NULL: created_at が NULL → recorded_at 08-09 を到着として使う
  ('cccccccc-0914-0001-0000-000000000008', 'walking', '2026-08-09 07:00+09', 'manual', NULL, NULL),
  -- 12 LATE: 計測 08-17（締め時刻より前）だが、届いたのは締め時刻の後 → R にも L にも数えない
  ('cccccccc-0914-0001-0000-000000000012', 'walking', '2026-08-17 07:00+09', 'manual', '2026-08-20 07:10+09', '2026-08-20 07:10+09'),
  -- 17 L_JST: D の JST 0:30
  ('cccccccc-0914-0001-0000-000000000017', 'walking', '2026-08-20 00:30+09', 'manual', '2026-08-20 00:42+09', '2026-08-20 00:42+09'),
  -- 36 FUTURE_E: 計測 08-23（未来）・到着 08-18（締め時刻の前）→ R に数える（L には数えない）
  ('cccccccc-0914-0001-0000-000000000036', 'walking', '2026-08-23 07:00+09', 'manual', '2026-08-18 07:30+09', '2026-08-18 07:30+09'),
  -- 36 FUTURE_E: 計測 08-24（未来）・到着は締め時刻の後 → R にも数えない
  ('cccccccc-0914-0001-0000-000000000036', 'walking', '2026-08-24 07:00+09', 'manual', '2026-08-20 07:10+09', '2026-08-20 07:10+09');

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, source, created_at, updated_at) VALUES
  -- 09 SLEEP_C: 起床日 08-12・到着 08-13
  ('cccccccc-0914-0001-0000-000000000009', '2026-08-12', 420, 'healthkit', '2026-08-13 07:00+09', '2026-08-13 07:00+09'),
  -- 10 SLEEP_U: 起床日 08-05・到着 08-06・同期の upsert で updated_at 08-19
  ('cccccccc-0914-0001-0000-000000000010', '2026-08-05', 420, 'healthkit', '2026-08-06 07:00+09', '2026-08-19 22:00+09'),
  -- 12 LATE: 起床日 08-19 だが、届いたのは締め時刻の後
  ('cccccccc-0914-0001-0000-000000000012', '2026-08-19', 420, 'healthkit', '2026-08-20 06:05+09', '2026-08-20 06:05+09'),
  -- 12 LATE: 起床日 07-31・到着 08-01（R・L は 08-01 の体重と同じ日）。締め時刻の後の同期で updated_at だけが動いた
  --   → updated_at は数えない（数えると R = 08-20）
  ('cccccccc-0914-0001-0000-000000000012', '2026-07-31', 420, 'healthkit', '2026-08-01 06:00+09', '2026-08-20 07:00+09'),
  -- 18 L_SLEEP: 起床日 08-19（D−1）は L に入り、起床日 08-20（= D）は入らない
  ('cccccccc-0914-0001-0000-000000000018', '2026-08-19', 420, 'healthkit', '2026-08-20 05:00+09', '2026-08-20 05:00+09'),
  ('cccccccc-0914-0001-0000-000000000018', '2026-08-20', 420, 'healthkit', '2026-08-20 05:30+09', '2026-08-20 05:30+09'),
  -- 37 FUTURE_S: 起床日 08-22（未来）・到着 08-18（締め時刻の前）→ R に数える（L には数えない）
  ('cccccccc-0914-0001-0000-000000000037', '2026-08-22', 420, 'healthkit', '2026-08-18 07:00+09', '2026-08-18 07:00+09'),
  -- 37 FUTURE_S: 起床日 08-23（未来）・到着は締め時刻の後 → R にも数えない
  ('cccccccc-0914-0001-0000-000000000037', '2026-08-23', 420, 'healthkit', '2026-08-20 07:00+09', '2026-08-20 07:00+09');

INSERT INTO public.ai_estimation_logs (client_id, trainer_id, function_name, status, created_at) VALUES
  -- 11 AI: 08-18
  ('cccccccc-0914-0001-0000-000000000011', 'aaaaaaaa-0914-0001-0000-00000000000a',
   'estimate-meal-nutrition', 'success', '2026-08-18 09:00+09'),
  -- 12 LATE: 締め時刻の後
  ('cccccccc-0914-0001-0000-000000000012', 'aaaaaaaa-0914-0001-0000-00000000000a',
   'estimate-meal-nutrition', 'success', '2026-08-20 06:01+09');

-- 16 DEVICE: 端末の時計で書かれる列だけが新しい（R に使わない）
INSERT INTO public.device_tokens (user_id, user_type, platform, token, last_seen_at, created_at) VALUES
  ('cccccccc-0914-0001-0000-000000000016', 'client', 'ios', 'snapshot-test-token',
   '2026-08-19 12:00+09', '2026-06-01 12:00+09');

INSERT INTO public.workout_plans (id, trainer_id, title, created_at, updated_at) VALUES
  ('dddddddd-0914-0001-0000-000000000001', 'aaaaaaaa-0914-0001-0000-00000000000a',
   'スナップショットテスト プラン', '2026-06-01 12:00+09', '2026-06-01 12:00+09');

INSERT INTO public.workout_assignments (
  trainer_id, client_id, assigned_date, plan_id, status, started_at, finished_at, created_at, updated_at
) VALUES
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000016', '2026-08-19',
   'dddddddd-0914-0001-0000-000000000001', 'completed',
   '2026-08-19 11:00+09', '2026-08-19 12:00+09', '2026-06-01 12:00+09', '2026-06-01 12:00+09');

-- 生きている / resolved の alerts。どれがあっても監視は延ばさない（オーナー決定 (1)。
-- 対象外になった顧客の record_gap は本実行が expired で閉じる。client_alert_detection_test.sql 参照）
INSERT INTO public.alerts (
  trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
) VALUES
  -- 25 LIVEGAP: 今の担当 T の生きている record_gap があっても R が古ければ inactive
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000025',
   'record_gap', 'high', 'open', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-19', NULL, NULL),
  -- 26 LIVEGAP_OLD: 前の担当 T2 の record_gap（本実行で reassigned に閉じる前）→ 監視を続けない
  ('aaaaaaaa-0914-0001-0000-00000000000b', 'cccccccc-0914-0001-0000-000000000026',
   'record_gap', 'high', 'open', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-19', NULL, NULL),
  -- 27 LIVE_WEIGHT: 生きているのは weight_change だけ → 監視を続けない
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000027',
   'weight_change', 'high', 'open', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-19', NULL, NULL),
  -- 28 RESOLVED_GAP: record_gap は resolved → 監視を続けない
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000028',
   'record_gap', 'high', 'resolved', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-10',
   '2026-08-11 06:00+09', 'cleared');

-- messages（AFTER INSERT トリガーが本番 URL へ net.http_post を積むので、この INSERT の間だけ止める）
DO $$
BEGIN
  PERFORM set_config('snapshot_test.queue_before', (SELECT count(*) FROM net.http_request_queue)::text, true);
END $$;
SET LOCAL session_replication_role = replica;

INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  -- 02 MSG: 顧客が送ったメッセージ 08-18
  ('cccccccc-0914-0001-0000-000000000002', 'aaaaaaaa-0914-0001-0000-00000000000a', 'client', 'trainer',
   'スナップショットテスト: 顧客→トレーナー', '2026-08-18 12:00+09', NULL),
  -- 03 READ: 07-10 に送られたトレーナーのメッセージを 08-17 に既読（Mobile が now() で書く分）
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000003', 'trainer', 'client',
   'スナップショットテスト: 既読', '2026-07-10 12:00+09', '2026-08-17 21:00+09'),
  -- 12 LATE: 締め時刻の後の送信と既読
  ('cccccccc-0914-0001-0000-000000000012', 'aaaaaaaa-0914-0001-0000-00000000000a', 'client', 'trainer',
   'スナップショットテスト: 締め時刻の後の送信', '2026-08-20 06:30+09', NULL),
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000012', 'trainer', 'client',
   'スナップショットテスト: 締め時刻の後の既読', '2026-07-10 12:00+09', '2026-08-20 06:10+09'),
  -- 14 TRAINER_MSG: トレーナーが 08-18 に送った（未読）→ 数えない。別メッセージの既読 08-16 → 数える
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000014', 'trainer', 'client',
   'スナップショットテスト: 未読', '2026-08-18 10:00+09', NULL),
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000014', 'trainer', 'client',
   'スナップショットテスト: 既読', '2026-07-10 10:00+09', '2026-08-16 20:00+09'),
  -- 15 K（兼務）: トレーナーとして Z に送った 08-19 → K の活動に数えない
  ('aaaaaaaa-0914-0001-0000-00000000000c', 'cccccccc-0914-0001-0000-000000000031', 'trainer', 'client',
   'スナップショットテスト: 兼務K→顧客Z', '2026-08-19 09:00+09', NULL),
  -- 15 K（兼務）: Z から届いたメッセージを Web で既読 08-18（receiver_type = trainer）→ 数えない
  ('cccccccc-0914-0001-0000-000000000031', 'aaaaaaaa-0914-0001-0000-00000000000c', 'client', 'trainer',
   'スナップショットテスト: 顧客Z→兼務K', '2026-07-20 09:00+09', '2026-08-18 20:00+09'),
  -- 15 K（兼務）: 顧客として T に送った 08-10 → 数える（R = L = 08-10）
  ('aaaaaaaa-0914-0001-0000-00000000000c', 'aaaaaaaa-0914-0001-0000-00000000000a', 'client', 'trainer',
   'スナップショットテスト: 兼務K→トレーナーT', '2026-08-10 12:00+09', NULL),
  -- 17 L_JST: D の JST 0:30 に顧客が送った → R には入るが L には入らない
  ('cccccccc-0914-0001-0000-000000000017', 'aaaaaaaa-0914-0001-0000-00000000000a', 'client', 'trainer',
   'スナップショットテスト: D の 0:30', '2026-08-20 00:30+09', NULL),
  -- 23 IN14: 08-06（D−14）の既読
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000023', 'trainer', 'client',
   'スナップショットテスト: D−14 の既読', '2026-07-10 10:00+09', '2026-08-06 20:00+09'),
  -- 24 IN15: 08-05（D−15）の既読
  ('aaaaaaaa-0914-0001-0000-00000000000a', 'cccccccc-0914-0001-0000-000000000024', 'trainer', 'client',
   'スナップショットテスト: D−15 の既読', '2026-07-10 10:00+09', '2026-08-05 20:00+09'),
  -- 32 FORGED_READ: auth.users にも trainers にも行が無い送信者 X が、トレーナーを装って既読付きで入れた
  --   （INSERT ポリシーは sender_id = auth.uid() だけなので、read_at も送信者が書ける）→ 数えない
  ('eeeeeeee-0914-0001-0000-0000000000ee', 'cccccccc-0914-0001-0000-000000000032', 'trainer', 'client',
   'スナップショットテスト: 偽造の既読', '2026-08-19 09:00+09', '2026-08-19 10:00+09'),
  -- 32 FORGED_READ: 今の担当ではないトレーナー T2 が送ったメッセージの既読 → 数えない
  ('aaaaaaaa-0914-0001-0000-00000000000b', 'cccccccc-0914-0001-0000-000000000032', 'trainer', 'client',
   'スナップショットテスト: 別のトレーナーの既読', '2026-08-10 09:00+09', '2026-08-18 21:00+09');

SET LOCAL session_replication_role = origin;

DO $$
BEGIN
  IF (SELECT count(*) FROM net.http_request_queue)
     <> current_setting('snapshot_test.queue_before')::bigint THEN
    RAISE EXCEPTION 'FAIL: 試験メッセージの INSERT で net.http_request_queue が増えた（トリガーが止まっていない）';
  END IF;
END $$;

-- 期待値（grp ごとに下のケースで検証する。exp_returned = false は snapshot に出ないこと）
CREATE TEMP TABLE snapshot_expected (
  grp text NOT NULL,
  label text NOT NULL,
  client_id uuid NOT NULL,
  exp_join date,
  exp_r date,
  exp_l date,
  exp_reason text,
  exp_returned boolean NOT NULL DEFAULT true
) ON COMMIT DROP;

INSERT INTO snapshot_expected (grp, label, client_id, exp_join, exp_r, exp_l, exp_reason) VALUES
  -- (a) 痕跡の種類ごと
  ('a', '01 REG（登録）',                 'cccccccc-0914-0001-0000-000000000001', '2026-08-15', '2026-08-15', NULL,         NULL),
  ('a', '02 MSG（顧客の送信）',           'cccccccc-0914-0001-0000-000000000002', '2026-06-01', '2026-08-18', '2026-08-18', NULL),
  ('a', '03 READ（顧客宛ての既読）',      'cccccccc-0914-0001-0000-000000000003', '2026-06-01', '2026-08-17', '2026-06-02', NULL),
  ('a', '04 W_CREATED（体重の到着）',     'cccccccc-0914-0001-0000-000000000004', '2026-06-01', '2026-08-16', '2026-08-10', NULL),
  ('a', '05 W_UPDATED（体重の updated_at）', 'cccccccc-0914-0001-0000-000000000005', '2026-06-01', '2026-08-19', '2026-08-01', NULL),
  ('a', '06 W_NULL（created_at NULL）',   'cccccccc-0914-0001-0000-000000000006', '2026-06-01', '2026-08-12', '2026-08-12', NULL),
  ('a', '07 MEAL（食事の到着）',          'cccccccc-0914-0001-0000-000000000007', '2026-06-01', '2026-08-14', '2026-08-13', NULL),
  ('a', '08 EX_NULL（運動 created_at NULL）', 'cccccccc-0914-0001-0000-000000000008', '2026-06-01', '2026-08-09', '2026-08-09', NULL),
  ('a', '09 SLEEP_C（睡眠の到着）',       'cccccccc-0914-0001-0000-000000000009', '2026-06-01', '2026-08-13', '2026-08-12', NULL),
  ('a', '10 SLEEP_U（睡眠の updated_at）', 'cccccccc-0914-0001-0000-000000000010', '2026-06-01', '2026-08-19', '2026-08-05', NULL),
  ('a', '11 AI（AI 推定）',               'cccccccc-0914-0001-0000-000000000011', '2026-06-01', '2026-08-18', '2026-06-02', NULL),
  -- (b) 締め時刻より後の到着・未来の日時（R は到着だけで決まる。未来の計測は L に入らない）
  ('b', '12 LATE（締め時刻の後の到着）',  'cccccccc-0914-0001-0000-000000000012', '2026-06-01', '2026-08-01', '2026-08-01', 'inactive'),
  ('b', '13 FUTURE_W（未来の計測の体重）', 'cccccccc-0914-0001-0000-000000000013', '2026-06-01', '2026-08-18', '2026-06-02', NULL),
  ('b', '35 FUTURE_M（未来の計測の食事）', 'cccccccc-0914-0001-0000-000000000035', '2026-06-01', '2026-08-18', '2026-06-02', NULL),
  ('b', '36 FUTURE_E（未来の計測の運動）', 'cccccccc-0914-0001-0000-000000000036', '2026-06-01', '2026-08-18', '2026-06-02', NULL),
  ('b', '37 FUTURE_S（未来の起床日の睡眠）', 'cccccccc-0914-0001-0000-000000000037', '2026-06-01', '2026-08-18', '2026-06-02', NULL),
  -- (c) トレーナーの送信は数えず、顧客宛ての既読は数える
  ('c', '14 TRAINER_MSG',                 'cccccccc-0914-0001-0000-000000000014', '2026-06-01', '2026-08-16', '2026-06-02', NULL),
  -- (d) 兼務アカウント
  ('d', '15 K（兼務）',                   'aaaaaaaa-0914-0001-0000-00000000000c', '2026-06-01', '2026-08-10', '2026-08-10', NULL),
  -- (e) 端末の時計の列を使わない
  ('e', '16 DEVICE',                      'cccccccc-0914-0001-0000-000000000016', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  -- (f) L の JST 境界と sleep の recorded_date
  ('f', '17 L_JST',                       'cccccccc-0914-0001-0000-000000000017', '2026-06-01', '2026-08-20', '2026-08-15', NULL),
  ('f', '18 L_SLEEP',                     'cccccccc-0914-0001-0000-000000000018', '2026-06-01', '2026-08-20', '2026-08-19', NULL),
  -- (g) exclusion_reason
  ('g', '19 NOACC',                       'cccccccc-0914-0001-0000-000000000019', '2026-08-15', '2026-08-15', NULL,         'no_account'),
  ('g', '20 SELF',                        'aaaaaaaa-0914-0001-0000-00000000000d', '2026-06-01', '2026-06-01', NULL,         'self'),
  ('g', '21 NS14（D − J = 14）',          'cccccccc-0914-0001-0000-000000000021', '2026-08-06', '2026-08-06', NULL,         NULL),
  ('g', '22 NS15（D − J = 15）',          'cccccccc-0914-0001-0000-000000000022', '2026-08-05', '2026-08-05', NULL,         'not_started'),
  ('g', '23 IN14（R = D−14）',            'cccccccc-0914-0001-0000-000000000023', '2026-06-01', '2026-08-06', '2026-06-02', NULL),
  ('g', '24 IN15（R = D−15）',            'cccccccc-0914-0001-0000-000000000024', '2026-06-01', '2026-08-05', '2026-06-02', 'inactive'),
  ('g', '25 LIVEGAP',                     'cccccccc-0914-0001-0000-000000000025', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  ('g', '26 LIVEGAP_OLD',                 'cccccccc-0914-0001-0000-000000000026', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  ('g', '27 LIVE_WEIGHT',                 'cccccccc-0914-0001-0000-000000000027', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  ('g', '28 RESOLVED_GAP',                'cccccccc-0914-0001-0000-000000000028', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  -- (h) 他の担当の顧客（p_trainer_id の絞り込み）と、兼務トレーナー K の顧客
  ('h', '29 T2_CLIENT',                   'cccccccc-0914-0001-0000-000000000029', '2026-08-15', '2026-08-15', NULL,         NULL),
  ('h', '31 Z',                           'cccccccc-0914-0001-0000-000000000031', '2026-06-01', '2026-07-20', '2026-07-20', 'inactive'),
  -- (i) 今の担当以外が送ったメッセージの既読は数えない（R は登録日のまま）
  ('i', '32 FORGED_READ',                 'cccccccc-0914-0001-0000-000000000032', '2026-06-01', '2026-06-01', '2026-06-02', 'inactive'),
  -- (k) HealthKit の体重（計測日の 23:59 JST）が D の 05:00 に届いた → R = D、L = 08-15
  ('k', '38 HK_WEIGHT（HealthKit の体重）', 'cccccccc-0914-0001-0000-000000000038', '2026-06-01', '2026-08-20', '2026-08-15', NULL);

INSERT INTO snapshot_expected (grp, label, client_id, exp_returned) VALUES
  ('h', '30 AFTER（締め時刻の後に登録）', 'cccccccc-0914-0001-0000-000000000030', false),
  -- (j) 登録日が ±infinity の顧客は返さない
  ('j', '33 NEG_INF（登録日 -infinity）', 'cccccccc-0914-0001-0000-000000000033', false),
  ('j', '34 POS_INF（登録日 infinity）',  'cccccccc-0914-0001-0000-000000000034', false);

GRANT SELECT ON snapshot_expected TO service_role;

-- 以降の snapshot 呼び出しは service_role として行う
SET LOCAL ROLE service_role;

-- -----------------------------------------------------------------------------
-- ケース(a)〜(g): 期待値表と snapshot(D, as_of) を突き合わせる
--   grp ごとに1ブロック。食い違った顧客を全部並べてから FAIL にする
-- -----------------------------------------------------------------------------
\echo '--- case a: 痕跡の種類ごとの取り込み（登録・送信・既読・体重 created/updated/NULL・食事・運動・睡眠 created/updated・AI）'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: J %s（期待 %s）/ R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.join_on, e.exp_join, g.last_activity_on, e.exp_r,
                           g.last_record_on, e.exp_l, g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'a'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 痕跡の取り込みが期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 痕跡の種類ごとに R がその JST 日付になる（登録日・created_at が NULL なら recorded_at を含む）';
END $$;

\echo '--- case b: 締め時刻より後に届いた痕跡は数えず、未来の計測でも締め時刻までに届いた記録は R に数えること（L には数えない）'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: J %s（期待 %s）/ R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.join_on, e.exp_join, g.last_activity_on, e.exp_r,
                           g.last_record_on, e.exp_l, g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'b'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 締め時刻・未来の日時の扱いが期待と異なる（FUTURE_* の R が 06-01・inactive なら、その表の R を計測時刻でも絞っている）:\n%', v_bad;
  END IF;

  -- 未来の計測で締め時刻の後（08-20 07:00 / 07:10）に届いた行は、締め時刻を 08:00 JST にずらすと R に入る
  -- （R = 08-20）。06:00 で数えないのは到着が後だから。L は未来の計測を数えないので 06-02 のまま
  SELECT string_agg(format('%s: R %s / L %s（期待 R 2026-08-20 / L 2026-06-02）',
                           x.label, g.last_activity_on, g.last_record_on), E'\n')
    INTO v_bad
    FROM (VALUES
      ('13 FUTURE_W', 'cccccccc-0914-0001-0000-000000000013'::uuid),
      ('35 FUTURE_M', 'cccccccc-0914-0001-0000-000000000035'::uuid),
      ('36 FUTURE_E', 'cccccccc-0914-0001-0000-000000000036'::uuid),
      ('37 FUTURE_S', 'cccccccc-0914-0001-0000-000000000037'::uuid)
    ) AS x(label, client_id)
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 08:00+09') g
      ON g.client_id = x.client_id
   WHERE g.client_id IS NULL
      OR (g.last_activity_on, g.last_record_on) IS DISTINCT FROM ('2026-08-20'::date, '2026-06-02'::date);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 締め時刻を 08:00 JST にずらしても、未来の計測で後から届いた行が R に入らない / 未来の計測が L に入っている:\n%', v_bad;
  END IF;

  -- 締め時刻を後ろ（08-20 08:00 JST）にずらすと、LATE の後から届いた痕跡が入る
  -- （R = 08-20: 体重・食事の到着 07:00 / 運動の到着 07:10 / updated_at 07:00、
  --   L = 08-19: 計測 08-19 の体重・起床日 08-19 の睡眠。食事 08-18・運動 08-17 より新しい）
  IF (SELECT (g.last_activity_on, g.last_record_on)
        FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 08:00+09') g
       WHERE g.client_id = 'cccccccc-0914-0001-0000-000000000012')
     IS DISTINCT FROM ('2026-08-20'::date, '2026-08-19'::date) THEN
    RAISE EXCEPTION 'FAIL: 締め時刻を 08:00 JST にずらしても LATE の後から届いた痕跡が数えられていない';
  END IF;
  RAISE NOTICE 'OK: 締め時刻より後の到着（体重・食事・運動・睡眠）・updated_at（体重・睡眠）・既読・送信・AI 推定は数えない（締め時刻をずらすと入る）。未来の計測でも締め時刻までに届いた記録は4表とも R に数え、L には数えない';
END $$;

\echo '--- case c: トレーナーの送信は顧客の活動に数えず、顧客宛ての既読は数えること'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: R %s（期待 %s）/ L %s（期待 %s）',
                           e.label, g.last_activity_on, e.exp_r, g.last_record_on, e.exp_l), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'c'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: トレーナーのメッセージの扱いが期待と異なる（08-18 の送信を数えている疑い）:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: トレーナーが 08-18 に送った分は数えず、顧客の既読 08-16 が R になる';
END $$;

\echo '--- case d: 兼務アカウントのトレーナーとしての送信・既読を顧客としての活動に数えないこと'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: R %s（期待 %s）/ L %s（期待 %s）',
                           e.label, g.last_activity_on, e.exp_r, g.last_record_on, e.exp_l), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'd'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 兼務アカウントの痕跡が type で分けられていない（R = 08-19 ならトレーナーとしての送信、08-18 なら Web の既読を数えている）:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 兼務 K はトレーナーとしての送信（08-19）・Web の既読（08-18）を数えず、顧客としての送信 08-10 が R と L';
END $$;

\echo '--- case e: 端末の時計で書かれる列（device_tokens.last_seen_at・workout の finished_at）を使っていないこと'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: R %s（期待 %s）/ L %s（期待 %s）',
                           e.label, g.last_activity_on, e.exp_r, g.last_record_on, e.exp_l), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'e'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 端末の時計の列が R に入っている疑い:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: last_seen_at / finished_at が 08-19 でも R は登録日 06-01 のまま（inactive）';
END $$;

\echo '--- case f: L は記録4表とメッセージの最新の計測日で、D の JST 0:30 は D−1 に入らないこと'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: R %s（期待 %s）/ L %s（期待 %s）',
                           e.label, g.last_activity_on, e.exp_r, g.last_record_on, e.exp_l), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'f'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: L の JST 境界・sleep の recorded_date の扱いが期待と異なる（L_JST の L が 08-19 なら UTC の日付で判定している）:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: D の JST 0:30（UTC 08-19 15:30）の体重・食事・運動・メッセージは L に入らず R に入る。sleep は recorded_date で判定';
END $$;

\echo '--- case g: exclusion_reason（no_account / self / not_started 14・15 / inactive 14・15 / 生きているアラートでは延ばさない）'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: J %s（期待 %s）/ R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.join_on, e.exp_join, g.last_activity_on, e.exp_r,
                           g.last_record_on, e.exp_l, g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'g'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: exclusion_reason が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: no_account / self / not_started（D − J = 14 は監視・15 は対象外）/ inactive（R = D−14 は監視・D−15 は対象外）/ 生きている record_gap・weight_change があっても監視は延ばさない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(h): p_trainer_id の絞り込みと、締め時刻より後に登録された顧客
-- -----------------------------------------------------------------------------
\echo '--- case h: p_trainer_id で担当顧客に絞れ、締め時刻より後に登録された顧客は返らないこと'

DO $$
DECLARE
  v_bad  text;
  v_got  uuid[];
  cnt    int;
BEGIN
  -- 絞り込み無し: 他の担当の顧客（29 / 31）も期待どおり、30 AFTER は返らない
  SELECT string_agg(format('%s: returned=%s（期待 %s）R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.client_id IS NOT NULL, e.exp_returned, g.last_activity_on, e.exp_r,
                           g.last_record_on, e.exp_l, g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'h'
     AND ((g.client_id IS NOT NULL) <> e.exp_returned
          OR (e.exp_returned
              AND (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
                  IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason)));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 他の担当の顧客・締め時刻の後の登録の扱いが期待と異なる:\n%', v_bad;
  END IF;

  -- p_trainer_id = T2: T2 の顧客 29 だけ
  v_got := ARRAY(
    SELECT g.client_id
      FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09',
                                           'aaaaaaaa-0914-0001-0000-00000000000b') g
     ORDER BY g.client_id);
  IF v_got IS DISTINCT FROM ARRAY['cccccccc-0914-0001-0000-000000000029']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: p_trainer_id = T2 の結果が %（期待 29 T2_CLIENT のみ）', v_got;
  END IF;

  -- p_trainer_id = T: T の顧客 29 人のうち、締め時刻の後に登録した 30 を除く 28 人。
  -- 他の担当の顧客（29 / 31 / 20 SELF / 33・34 / T3 の 35〜38）は入らない
  SELECT count(*) INTO cnt
    FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09',
                                         'aaaaaaaa-0914-0001-0000-00000000000a') g;
  IF cnt <> 28 THEN
    RAISE EXCEPTION 'FAIL: p_trainer_id = T の結果が % 行（期待 28 行）', cnt;
  END IF;
  SELECT count(*) INTO cnt
    FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09',
                                         'aaaaaaaa-0914-0001-0000-00000000000a') g
   WHERE g.trainer_id <> 'aaaaaaaa-0914-0001-0000-00000000000a';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: p_trainer_id = T の結果に他の担当の顧客が % 行混ざっている', cnt;
  END IF;

  -- 締め時刻を登録の後（08-20 08:00 JST）にずらすと 30 AFTER も返る
  SELECT count(*) INTO cnt
    FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 08:00+09',
                                         'aaaaaaaa-0914-0001-0000-00000000000a') g
   WHERE g.client_id = 'cccccccc-0914-0001-0000-000000000030';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: 締め時刻を 08:00 JST にずらしても 30 AFTER が返らない';
  END IF;

  RAISE NOTICE 'OK: p_trainer_id で担当顧客に絞れる（T2 → 1 行 / T → 28 行）。締め時刻より後に登録された顧客は返さない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i): 今の担当トレーナー以外が送ったメッセージの既読は R に数えない
-- -----------------------------------------------------------------------------
\echo '--- case i: 担当関係の無い送信者・別のトレーナーが送ったメッセージの既読で R が動かないこと'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.last_activity_on, e.exp_r, g.last_record_on, e.exp_l,
                           g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'i'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 今の担当以外の既読を R に数えている（R = 08-19 なら担当関係の無い送信者、08-18 なら T2 の分）:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 担当関係の無い送信者（08-19）・今の担当ではない T2（08-18）の既読は数えず、R は登録日 06-01 のまま（inactive）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(j): 登録日が ±infinity の顧客（顧客本人が clients.created_at を書き換えた）
--   '-infinity' のまま日付の引き算をすると 22008（cannot subtract infinite dates）で落ちる。
--   返さないうえで、絞り込み無し・担当トレーナー（T2）での呼び出しがどちらも例外にならないこと
-- -----------------------------------------------------------------------------
\echo '--- case j: 登録日が ±infinity の顧客は返さず、snapshot が例外にならないこと'

DO $$
DECLARE
  v_bad text;
  v_got uuid[];
BEGIN
  SELECT string_agg(format('%s: returned=%s（期待 %s）', e.label, g.client_id IS NOT NULL, e.exp_returned), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'j'
     AND (g.client_id IS NOT NULL) <> e.exp_returned;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: 登録日が ±infinity の顧客が返っている:\n%', v_bad;
  END IF;

  -- 担当トレーナー T2 で絞っても例外にならず、有限の登録日の 29 だけ（締め時刻を後ろにずらしても同じ）
  v_got := ARRAY(
    SELECT g.client_id
      FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 08:00+09',
                                           'aaaaaaaa-0914-0001-0000-00000000000b') g
     ORDER BY g.client_id);
  IF v_got IS DISTINCT FROM ARRAY['cccccccc-0914-0001-0000-000000000029']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: p_trainer_id = T2 の結果が %（期待 29 T2_CLIENT のみ。±infinity の 33・34 は返さない）', v_got;
  END IF;
  RAISE NOTICE 'OK: 登録日が -infinity / infinity の顧客は返さず、snapshot は例外にならない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(k): HealthKit の体重（計測日の 23:59 JST で入る）
--   体重だけ連携している顧客が D に計測し、アプリが D の 05:00 JST（06:00 の本実行より前）に同期した。
--   届いた D の体重は計測時刻（D 23:59）が締め時刻（D 06:00）より後だが、R は到着時刻だけで決まるので R = D。
--   計測時刻でも絞ると R = 08-15（前回の到着）になり、(D−1) − R = 4 ≥ 3 で「記録・同期なし」（no_data）に
--   なる（evaluate 側は client_alert_detection_test.sql の case d-healthkit）
-- -----------------------------------------------------------------------------
\echo '--- case k: HealthKit の体重（計測日の 23:59 JST）が締め時刻の前に届けば、計測時刻が後でも R = D になること'

DO $$
DECLARE
  v_bad text;
  r     record;
BEGIN
  SELECT string_agg(format('%s: J %s（期待 %s）/ R %s（期待 %s）/ L %s（期待 %s）/ reason %s（期待 %s）',
                           e.label, g.join_on, e.exp_join, g.last_activity_on, e.exp_r,
                           g.last_record_on, e.exp_l, g.exclusion_reason, e.exp_reason), E'\n')
    INTO v_bad
    FROM pg_temp.snapshot_expected e
    LEFT JOIN public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
      ON g.client_id = e.client_id
   WHERE e.grp = 'k'
     AND (g.client_id IS NULL
          OR (g.join_on, g.last_activity_on, g.last_record_on, g.exclusion_reason)
             IS DISTINCT FROM (e.exp_join, e.exp_r, e.exp_l, e.exp_reason));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: HealthKit の体重（計測日の 23:59 JST・D の 05:00 着）の扱いが期待と異なる（R が 08-15 なら計測時刻でも R を絞っている）:\n%', v_bad;
  END IF;

  -- no_data の条件 (D−1) − R ≥ 3 に当たらない（R = D なので −1）
  SELECT g.last_activity_on INTO r
    FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 06:00+09') g
   WHERE g.client_id = 'cccccccc-0914-0001-0000-000000000038';
  IF r.last_activity_on IS NULL OR ('2026-08-19'::date - r.last_activity_on) >= 3 THEN
    RAISE EXCEPTION 'FAIL: HealthKit の体重だけの顧客が no_data の条件 (D−1) − R ≥ 3 に当たる（R %）', r.last_activity_on;
  END IF;

  -- 締め時刻を D の 04:59 JST（D の体重が届く前）にずらすと数えない → R = 08-15（前回の到着）。L は 08-15 のまま
  SELECT g.last_activity_on, g.last_record_on INTO r
    FROM public.client_activity_snapshot('2026-08-20', '2026-08-20 04:59+09') g
   WHERE g.client_id = 'cccccccc-0914-0001-0000-000000000038';
  IF (r.last_activity_on, r.last_record_on) IS DISTINCT FROM ('2026-08-15'::date, '2026-08-15'::date) THEN
    RAISE EXCEPTION 'FAIL: 締め時刻を D の 04:59 JST にずらしたときの R / L が期待と異なる（R % / L %。期待 R 08-15 / L 08-15。R = 08-20 なら締め時刻より後の到着を数えている）',
      r.last_activity_on, r.last_record_on;
  END IF;
  RAISE NOTICE 'OK: D の 05:00 に届いた D 23:59 JST の体重で R = D（締め時刻 06:00。no_data の条件に当たらない）。締め時刻を 04:59 にずらすと数えない（R = 08-15）';
END $$;

RESET ROLE;

ROLLBACK;

\echo ''
\echo 'ALL CLIENT ACTIVITY SNAPSHOT TESTS PASSED'
