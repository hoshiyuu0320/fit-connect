-- =============================================================================
-- 睡眠悪化アラート（sleep_decline）のテスト
-- （フェーズ9.1 拡張 ③ / 20261003000000_alert_sleep_decline.sql。
--   設計: docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4・§8.1）
--
-- 実行方法（リポジトリルートから。20261003000000 まで適用したローカル Supabase スタックで）:
--   docker exec -i supabase_db_<project_id> psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/sleep_decline_alert_test.sql
--   <project_id> は使うスタックの supabase/config.toml の project_id。
--   migration の検証は隔離したスタックで行い、共有スタック（supabase_db_fit-connect）には当てない
--
-- - 全ケース成功時のみ最終行に「ALL SLEEP DECLINE ALERT TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 方針（client_alert_detection_test.sql と同じ）:
--   - BEGIN の直後に alerts と alert_detection_runs を DELETE する（ROLLBACK で戻る）
--   - 件数・状態の assert は試験用の顧客に限る（evaluate / 本実行は全顧客を評価する）
--   - 対象日は過去の固定日（2026-09）。evaluate の既定の締め時刻 = D+1 の JST 0:00
--   - sleep_records の created_at / updated_at は必ず明示する（既定値の now() のままだと、過去の
--     対象日では締め時刻より後になり、窓にも最終到着日 R にも入らない）。省略した行は起床日の
--     08:00 JST に届いたものとする
--   - 監視対象にするため、各顧客の最終到着 R が D − 14 以降になるようにする（睡眠の created_at で足りる）
--   - 関数は postgres（cron と同じ実行ロール）で呼ぶ
--   - 本実行のシナリオ（第2部）は、シナリオごとに顧客を作り、終わったら顧客（CASCADE で睡眠の記録・
--     alerts も）と alert_detection_runs を消してから次へ進む（「最後の本実行より前は例外」のガードと、
--     他のシナリオの本実行で状態が動かないようにするため）
--
-- 検証ケース（番号は設計 §8.1）:
--   第0部 CHECK
--   (23) alerts は alert_type = 'sleep_decline' を受け付け、未知の値を拒む
--   第1部 evaluate（D = 2026-09-20。直近の窓 09-13〜09-19、前の窓 09-06〜09-12）
--   (1)  睡眠時間が成立（前 7晩・直近 5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の全体
--   (2)  境界: Δ = −60 は成立、Δ = −59.5 は保留（丸めると −60 だが成立しない）
--   (3)  解消: Δ = −47 は cleared、Δ = −48 は保留
--   (4)  直近の窓が3晩（目覚め評価なし）→ unknown
--   (5)  範囲: 119分・961分の晩は数えず、120分・960分ちょうどは数える
--   (6)  外れ値: 毎晩 383 分で前の窓に 900 分が1晩 → 成立しない。直近4晩のうち1晩だけ 140 分 → 成立しない
--   (7)  窓の境界: D−8 の晩は前の窓、D−7 の晩は直近の窓、D−15 の晩は窓の外
--   (8)  登録日: 登録日より前の晩は数えない。D = J + 10 は評価できず、D = J + 11 は評価できる
--   (9)  created_at > as_of の晩は数えない
--   (10) 当日 D の晩と未来の日付は数えない。顧客が書ける値（recorded_date = ±infinity、睡眠時間が負・0・
--        integer の最大値）でも evaluate は落ちず、その晩は数えない（設計 §7）
--   (11) delta_minutes は丸める前の中央値どうしの差から出る（340.5 − 400 → −60。341 − 400 = −59 ではない）
--   (12) 目覚め評価だけで成立（睡眠時間が NULL・範囲外の行の評価、[1, 1, 2]）→ triggers ["wakeup"]・前の窓は nights 0。
--        登録直後（前の窓の from が to より後）でも目覚め評価で成立する
--   (13) 目覚め評価の境界: 平均ちょうど 1.5（[1, 1, 2, 2]）は保留、[2, 2, 2] は解消
--   (14) 両方成立 → triggers ["duration", "wakeup"]
--   (15) 設計 §4.4 の表の代表的な組み合わせ。規則1（成立）が規則2（保留・不足）より先であること
--        （不足 + 成立・成立 + 保留・保留 + 成立 は detected）と、不足・保留 + 解消 は unknown のまま
--        であること（登録直後で前の窓が空の顧客を含む）。目覚め評価は直近の窓だけで数えること
--        （D−8 の評価は数えない）
--   (16) 監視対象でない顧客（no_account・self）には行が無い。データの無い監視対象には unknown の行がある
--        （監視対象1名につき3行）。全行で「detected ⇔ medium ⇔ triggers が空でない」・severity_reason なし
--   第2部 run
--   (17) 新規 → open・medium・surfaced_on = D。同じ D の再実行は件数が増えない
--   (18) 保留（unknown）の日は status・last_detected_on・payload が変わらない
--   (19) 後の日に cleared → resolved（cleared）
--   (20) 期限切れ: last_detected_on = D − 14 の生きている行は（対応済みでも）expired、D − 13 の open の行は
--        残る（評価は unknown）。評価されない（inactive）顧客の古い行も expired
--   (21) 対応済みの行は、成立が続いても対応済みのまま
--   (22) stats に detected.sleep_decline（数値）があり、evaluate の detected の件数と一致する
--   第3部 登録内容
--   (24) 再定義の後も両関数が SECURITY DEFINER・search_path = ''、EXECUTE は service_role だけ（proacl と PUBLIC を含めて）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DELETE FROM public.alerts;
DELETE FROM public.alert_detection_runs;

-- -----------------------------------------------------------------------------
-- 共通の試験データ（postgres として実行。RLS バイパス）
--   trainer T  : aaaaaaaa-1003-0001-0000-00000000000a（試験用顧客の担当。business）
--   trainer T2 : aaaaaaaa-1003-0001-0000-00000000000b（顧客 29〜34 の担当。business。T の顧客数が上限 30 に
--                当たらないように分ける）
--   trainer XS : aaaaaaaa-1003-0001-0000-00000000000d（自己登録: 自分自身が顧客）
--   client  NN : cccccccc-1003-0001-0000-0000000000NN（第1部 01〜34、第2部 41・51〜53）
-- -----------------------------------------------------------------------------
\echo '--- setup: 共通の試験データ作成 (trainer T・T2・XS)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-' || v.id || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a'),
    ('aaaaaaaa-1003-0001-0000-00000000000b'),
    ('aaaaaaaa-1003-0001-0000-00000000000d')
  ) AS v(id);

INSERT INTO public.trainers (id, name, email, subscription_plan)
SELECT v.id::uuid, v.name, 'sleep-alert-test-' || v.id || '@example.com', 'business'
  FROM (VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a', '睡眠テスト トレーナーT'),
    ('aaaaaaaa-1003-0001-0000-00000000000b', '睡眠テスト トレーナーT2'),
    ('aaaaaaaa-1003-0001-0000-00000000000d', '睡眠テスト 自己登録XS')
  ) AS v(id, name);

-- =============================================================================
-- 第1部: evaluate_client_alerts（D = 2026-09-20、既定の締め時刻 = 2026-09-21 0:00 JST）
--   D−15 = 09-05、D−14 = 09-06、D−8 = 09-12、D−7 = 09-13、D−1 = 09-19
--   01 DUR_MET      : 前 [390,395,400,400,405,410,420]（中央値 400）・直近 [320,325,330,340,345]（330）
--   02 BND60        : 前 400×4・直近 340×4（Δ −60）
--   03 BND59_5      : 前 [400,400,401,401]（400.5）・直近 341×4（Δ −59.5）
--   04 CLR47        : 前 400×4・直近 353×4（Δ −47）     05 CLR48 : 前 400×4・直近 352×4（Δ −48）
--   06 RECENT3      : 前 400×7・直近 300×3
--   07 RANGE        : 前 960×4 + 961×1・直近 120×4 + 119×1
--   08 OUT_PREV900  : 毎晩 383、前の窓の 09-08 だけ 900
--   09 OUT_RECENT140: 前 383×4・直近 [383,383,383,140]
--   10 WIN_BND      : 09-05（D−15）・09-06（D−14）・09-10〜09-12（09-12 = D−8）は 400、
--                     09-13（D−7）・09-15・09-17・09-19（D−1）は 330
--   11 JOIN         : 登録 09-09 10:00。09-01〜09-09 は登録時に一括で届いた（09-01〜09-08 は 330、09-09 は 400）。
--                     09-10〜09-12 は 400、09-13〜09-19 は 330
--   12 ASOF         : 前 400×4・直近 330×4。うち 09-19 の晩だけ 09-20 07:00 JST に届く
--   13 DAY_D_FUTURE : 前 400×4・直近 330×3。D（09-20）の晩と未来（09-25）の晩も締め時刻までに届いている
--   14 UNROUNDED    : 前 400×4・直近 [340,340,341,341]（340.5）
--   15 WAKE_ONLY    : 睡眠時間 NULL / 60 / NULL の行の評価 [1, 1, 2]
--   16 WAKE_NEWJOIN : 登録 09-16 10:00。睡眠時間 NULL の評価 [1, 1, 1]（09-16〜09-18）
--   17 WAKE_15      : 評価 [1, 1, 2, 2]               18 WAKE_20 : 評価 [2, 2, 2]
--   19 BOTH         : 前 400×4・直近 330×4、評価 [1, 1, 2, 1]
--   20 MET_WCLR     : 前 400×4・直近 330×4、評価 [3, 3, 3]
--   21 CLR_WPEND    : 前 400×4・直近 400×4、評価 [1, 2, 2]
--   22 CLR_WNONE    : 前 400×4・直近 400×4、評価なし
--   23 CLR_WINSUF   : 前 400×4・直近 400×4、評価 [1, 1]
--   24 INSUF_WCLR   : 前 400×4・直近 400×3、評価 [3, 3, 3]
--   25 NONE_WINSUF  : 睡眠時間 NULL の評価 [1, 1]
--   26 NOAUTH       : auth.users に行が無い（データは成立する形）
--   27 NODATA       : 登録 09-15 12:00・睡眠の記録なし（監視対象）
--   28 HOSTILE      : 前 400×4・直近 330×3 に加え、-5 / 2147483647 / 0 分の晩と、起床日 infinity / -infinity の晩
--   （29〜34 は T2 の担当。規則の順序と評価の窓を見る）
--   29 JOIN_WMET    : 登録 09-14 10:00。HealthKit 400×6（09-14〜09-19、直近の窓だけで前の窓は空）、評価 [1, 1, 1]
--   30 PEND_WCLR    : 前 400×4・直近 345×4（Δ −55 = 保留）、評価 [3, 3, 3]
--   31 WIN_D8       : 前 400×4・直近 400×4。評価は 09-12（D−8）に 1、09-14・09-15 に 1（直近の窓は 2回）
--   32 JOIN_WCLR    : 登録 09-14 10:00。HealthKit 400×6（09-14〜09-19）、評価 [3, 3, 3]
--   33 MET_WPEND    : 前 400×4・直近 330×4（Δ −70 = 成立）、評価 [1, 2, 2]（平均 1.67 = 保留）
--   34 PEND_WMET    : 前 400×4・直近 345×4（Δ −55 = 保留）、評価 [1, 1, 1]
--   XS SELF         : 自己登録（データは成立する形）
-- =============================================================================
\echo '--- 第1部 setup: evaluate 用の試験用顧客 01〜34 と XS'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['01','02','03','04','05','06','07','08','09','10','11','12','13','14',
                    '15','16','17','18','19','20','21','22','23','24','25','27','28',
                    '29','30','31','32','33','34']) AS n;  -- 26 NOAUTH は入れない

INSERT INTO public.clients (client_id, name, trainer_id, purpose, created_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, '睡眠テスト顧客' || v.n,
       'aaaaaaaa-1003-0001-0000-00000000000a', 'health_improvement', v.created_at::timestamptz
  FROM (VALUES
    ('01', '2026-07-01 12:00+09'), ('02', '2026-07-01 12:00+09'), ('03', '2026-07-01 12:00+09'),
    ('04', '2026-07-01 12:00+09'), ('05', '2026-07-01 12:00+09'), ('06', '2026-07-01 12:00+09'),
    ('07', '2026-07-01 12:00+09'), ('08', '2026-07-01 12:00+09'), ('09', '2026-07-01 12:00+09'),
    ('10', '2026-07-01 12:00+09'), ('11', '2026-09-09 10:00+09'), ('12', '2026-07-01 12:00+09'),
    ('13', '2026-07-01 12:00+09'), ('14', '2026-07-01 12:00+09'), ('15', '2026-07-01 12:00+09'),
    ('16', '2026-09-16 10:00+09'), ('17', '2026-07-01 12:00+09'), ('18', '2026-07-01 12:00+09'),
    ('19', '2026-07-01 12:00+09'), ('20', '2026-07-01 12:00+09'), ('21', '2026-07-01 12:00+09'),
    ('22', '2026-07-01 12:00+09'), ('23', '2026-07-01 12:00+09'), ('24', '2026-07-01 12:00+09'),
    ('25', '2026-07-01 12:00+09'), ('26', '2026-07-01 12:00+09'), ('27', '2026-09-15 12:00+09'),
    ('28', '2026-07-01 12:00+09')
  ) AS v(n, created_at);

-- 29〜34 は T2 の担当（T は 28 名で、business の上限 30 名に当たらないようにするため）
INSERT INTO public.clients (client_id, name, trainer_id, purpose, created_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, '睡眠テスト顧客' || v.n,
       'aaaaaaaa-1003-0001-0000-00000000000b', 'health_improvement', v.created_at::timestamptz
  FROM (VALUES
    ('29', '2026-09-14 10:00+09'), ('30', '2026-07-01 12:00+09'), ('31', '2026-07-01 12:00+09'),
    ('32', '2026-09-14 10:00+09'), ('33', '2026-07-01 12:00+09'), ('34', '2026-07-01 12:00+09')
  ) AS v(n, created_at);

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('aaaaaaaa-1003-0001-0000-00000000000d', '睡眠テスト 自己登録XS',
   'aaaaaaaa-1003-0001-0000-00000000000d', '2026-07-01 12:00+09');

-- 同じ値が続く晩（毎晩 1 行。評価なし。到着 arrived を省略した行は起床日の 08:00 JST）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || r.n)::uuid, g.d::date, r.minutes, NULL, 'healthkit',
       coalesce(r.arrived::timestamptz, (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'),
       coalesce(r.arrived::timestamptz, (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo')
  FROM (VALUES
    ('02', '2026-09-09', '2026-09-12', 400, NULL), ('02', '2026-09-16', '2026-09-19', 340, NULL),
    ('03', '2026-09-16', '2026-09-19', 341, NULL),
    ('04', '2026-09-09', '2026-09-12', 400, NULL), ('04', '2026-09-16', '2026-09-19', 353, NULL),
    ('05', '2026-09-09', '2026-09-12', 400, NULL), ('05', '2026-09-16', '2026-09-19', 352, NULL),
    ('06', '2026-09-06', '2026-09-12', 400, NULL),
    ('07', '2026-09-06', '2026-09-09', 960, NULL), ('07', '2026-09-13', '2026-09-16', 120, NULL),
    ('08', '2026-09-06', '2026-09-07', 383, NULL), ('08', '2026-09-09', '2026-09-19', 383, NULL),
    ('09', '2026-09-09', '2026-09-12', 383, NULL), ('09', '2026-09-16', '2026-09-18', 383, NULL),
    -- 11 JOIN: 登録（09-09 10:00）時の初回連携で、09-01〜09-08 の 330 と 09-09 の 400 が一括で届いた
    ('11', '2026-09-01', '2026-09-08', 330, '2026-09-09 10:05+09'),
    ('11', '2026-09-09', '2026-09-09', 400, '2026-09-09 10:05+09'),
    ('11', '2026-09-10', '2026-09-12', 400, NULL), ('11', '2026-09-13', '2026-09-19', 330, NULL),
    ('12', '2026-09-09', '2026-09-12', 400, NULL),
    ('13', '2026-09-09', '2026-09-12', 400, NULL),
    ('14', '2026-09-09', '2026-09-12', 400, NULL),
    ('19', '2026-09-09', '2026-09-12', 400, NULL),
    ('20', '2026-09-09', '2026-09-12', 400, NULL),
    ('21', '2026-09-09', '2026-09-12', 400, NULL),
    ('22', '2026-09-09', '2026-09-12', 400, NULL), ('22', '2026-09-16', '2026-09-19', 400, NULL),
    ('23', '2026-09-09', '2026-09-12', 400, NULL),
    ('24', '2026-09-09', '2026-09-12', 400, NULL),
    ('26', '2026-09-09', '2026-09-12', 400, NULL), ('26', '2026-09-16', '2026-09-19', 330, NULL),
    ('28', '2026-09-09', '2026-09-12', 400, NULL)
  ) AS r(n, from_day, to_day, minutes, arrived)
 CROSS JOIN LATERAL generate_series(r.from_day::date, r.to_day::date, interval '1 day') AS g(d);

-- 1晩ずつ値を指定する行（評価・到着を含む。睡眠時間が NULL の行は手動の評価だけ）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, v.day::date, v.minutes, v.rating,
       CASE WHEN v.minutes IS NULL THEN 'manual' ELSE 'healthkit' END,
       coalesce(v.arrived::timestamptz, (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'),
       coalesce(v.arrived::timestamptz, (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo')
  FROM (VALUES
    -- 01 DUR_MET
    ('01', '2026-09-06', 390, NULL, NULL), ('01', '2026-09-07', 395, NULL, NULL),
    ('01', '2026-09-08', 400, NULL, NULL), ('01', '2026-09-09', 400, NULL, NULL),
    ('01', '2026-09-10', 405, NULL, NULL), ('01', '2026-09-11', 410, NULL, NULL),
    ('01', '2026-09-12', 420, NULL, NULL),
    ('01', '2026-09-13', 320, NULL, NULL), ('01', '2026-09-14', 325, NULL, NULL),
    ('01', '2026-09-15', 330, NULL, NULL), ('01', '2026-09-17', 340, NULL, NULL),
    ('01', '2026-09-19', 345, NULL, NULL),
    -- 03 BND59_5: 前の窓の中央値 400.5
    ('03', '2026-09-09', 400, NULL, NULL), ('03', '2026-09-10', 400, NULL, NULL),
    ('03', '2026-09-11', 401, NULL, NULL), ('03', '2026-09-12', 401, NULL, NULL),
    -- 06 RECENT3: 直近の窓は3晩
    ('06', '2026-09-13', 300, NULL, NULL), ('06', '2026-09-15', 300, NULL, NULL),
    ('06', '2026-09-17', 300, NULL, NULL),
    -- 07 RANGE: 961 と 119 は範囲外
    ('07', '2026-09-10', 961, NULL, NULL), ('07', '2026-09-17', 119, NULL, NULL),
    -- 08 OUT_PREV900: 前の窓に1晩だけ 900（平均なら前の窓 456.9 で Δ −73.9 の成立になる）
    ('08', '2026-09-08', 900, NULL, NULL),
    -- 09 OUT_RECENT140: 直近の窓に1晩だけ 140（平均なら直近 322.25 で Δ −60.75 の成立になる）
    ('09', '2026-09-19', 140, NULL, NULL),
    -- 10 WIN_BND
    ('10', '2026-09-05', 400, NULL, NULL), ('10', '2026-09-06', 400, NULL, NULL),
    ('10', '2026-09-10', 400, NULL, NULL), ('10', '2026-09-11', 400, NULL, NULL),
    ('10', '2026-09-12', 400, NULL, NULL),
    ('10', '2026-09-13', 330, NULL, NULL), ('10', '2026-09-15', 330, NULL, NULL),
    ('10', '2026-09-17', 330, NULL, NULL), ('10', '2026-09-19', 330, NULL, NULL),
    -- 12 ASOF: 09-19 の晩だけ 09-20 07:00 JST に届く
    ('12', '2026-09-13', 330, NULL, NULL), ('12', '2026-09-15', 330, NULL, NULL),
    ('12', '2026-09-17', 330, NULL, NULL), ('12', '2026-09-19', 330, NULL, '2026-09-20 07:00+09'),
    -- 13 DAY_D_FUTURE: D（09-20）の晩と未来（09-25）の晩は締め時刻までに届いているが窓の外
    ('13', '2026-09-13', 330, NULL, NULL), ('13', '2026-09-15', 330, NULL, NULL),
    ('13', '2026-09-17', 330, NULL, NULL),
    ('13', '2026-09-20', 330, NULL, '2026-09-20 08:00+09'),
    ('13', '2026-09-25', 330, NULL, '2026-09-20 09:00+09'),
    -- 14 UNROUNDED: 直近の窓の中央値 340.5
    ('14', '2026-09-16', 340, NULL, NULL), ('14', '2026-09-17', 340, NULL, NULL),
    ('14', '2026-09-18', 341, NULL, NULL), ('14', '2026-09-19', 341, NULL, NULL),
    -- 15 WAKE_ONLY: 睡眠時間が NULL / 範囲外（60）の行の評価も数える
    ('15', '2026-09-15', NULL, 1, NULL), ('15', '2026-09-17', 60, 1, NULL),
    ('15', '2026-09-19', NULL, 2, NULL),
    -- 16 WAKE_NEWJOIN: 登録（09-16 10:00）の後に付けた評価
    ('16', '2026-09-16', NULL, 1, '2026-09-16 21:00+09'), ('16', '2026-09-17', NULL, 1, '2026-09-17 21:00+09'),
    ('16', '2026-09-18', NULL, 1, '2026-09-18 21:00+09'),
    -- 17 WAKE_15 / 18 WAKE_20
    ('17', '2026-09-13', NULL, 1, NULL), ('17', '2026-09-15', NULL, 1, NULL),
    ('17', '2026-09-17', NULL, 2, NULL), ('17', '2026-09-19', NULL, 2, NULL),
    ('18', '2026-09-14', NULL, 2, NULL), ('18', '2026-09-16', NULL, 2, NULL),
    ('18', '2026-09-18', NULL, 2, NULL),
    -- 19 BOTH
    ('19', '2026-09-16', 330, 1, NULL), ('19', '2026-09-17', 330, 1, NULL),
    ('19', '2026-09-18', 330, 2, NULL), ('19', '2026-09-19', 330, 1, NULL),
    -- 20 MET_WCLR
    ('20', '2026-09-16', 330, 3, NULL), ('20', '2026-09-17', 330, 3, NULL),
    ('20', '2026-09-18', 330, 3, NULL), ('20', '2026-09-19', 330, NULL, NULL),
    -- 21 CLR_WPEND
    ('21', '2026-09-16', 400, 1, NULL), ('21', '2026-09-17', 400, 2, NULL),
    ('21', '2026-09-18', 400, 2, NULL), ('21', '2026-09-19', 400, NULL, NULL),
    -- 23 CLR_WINSUF
    ('23', '2026-09-16', 400, 1, NULL), ('23', '2026-09-17', 400, 1, NULL),
    ('23', '2026-09-18', 400, NULL, NULL), ('23', '2026-09-19', 400, NULL, NULL),
    -- 24 INSUF_WCLR
    ('24', '2026-09-17', 400, 3, NULL), ('24', '2026-09-18', 400, 3, NULL),
    ('24', '2026-09-19', 400, 3, NULL),
    -- 25 NONE_WINSUF
    ('25', '2026-09-17', NULL, 1, NULL), ('25', '2026-09-19', NULL, 1, NULL),
    -- 28 HOSTILE: 有効な晩は直近 3晩だけ。範囲外の睡眠時間と ±infinity の起床日は、締め時刻までに届いていても数えない
    ('28', '2026-09-13', 330, NULL, NULL), ('28', '2026-09-15', 330, NULL, NULL),
    ('28', '2026-09-17', 330, NULL, NULL),
    ('28', '2026-09-14', -5, NULL, NULL), ('28', '2026-09-16', 2147483647, NULL, NULL),
    ('28', '2026-09-18', 0, NULL, NULL),
    ('28', 'infinity',  300, NULL, '2026-09-19 08:00+09'), ('28', '-infinity', 300, NULL, '2026-09-19 08:00+09'),
    -- 29 JOIN_WMET: 登録直後の HealthKit。睡眠時間は 直近 6晩・前 0晩 で「不足」、評価 [1, 1, 1] は「成立」→ detected
    ('29', '2026-09-14', 400, NULL, NULL), ('29', '2026-09-15', 400, NULL, NULL), ('29', '2026-09-16', 400, NULL, NULL),
    ('29', '2026-09-17', 400, 1, NULL), ('29', '2026-09-18', 400, 1, NULL), ('29', '2026-09-19', 400, 1, NULL),
    -- 30 PEND_WCLR: 睡眠時間は Δ −55 で「保留」、評価 [3, 3, 3] は「解消」→ unknown（前 400×4 + 直近 345×4）
    ('30', '2026-09-09', 400, NULL, NULL), ('30', '2026-09-10', 400, NULL, NULL), ('30', '2026-09-11', 400, NULL, NULL),
    ('30', '2026-09-12', 400, NULL, NULL),
    ('30', '2026-09-16', 345, 3, NULL), ('30', '2026-09-17', 345, 3, NULL),
    ('30', '2026-09-18', 345, 3, NULL), ('30', '2026-09-19', 345, NULL, NULL),
    -- 31 WIN_D8: 睡眠時間は Δ 0 で「解消」。評価は D−8（09-12）に 1 回あり、直近の窓には 09-14・09-15 の 2 回だけ。
    --   直近の窓だけで数えれば「不足」（解消は止まらず cleared）、14日全体で数えると 3 回・平均 1.00 で「成立」になる
    ('31', '2026-09-09', 400, NULL, NULL), ('31', '2026-09-10', 400, NULL, NULL), ('31', '2026-09-11', 400, NULL, NULL),
    ('31', '2026-09-12', 400, 1, NULL),
    ('31', '2026-09-14', 400, 1, NULL), ('31', '2026-09-15', 400, 1, NULL),
    ('31', '2026-09-16', 400, NULL, NULL), ('31', '2026-09-17', 400, NULL, NULL),
    -- 32 JOIN_WCLR: 登録直後の HealthKit。睡眠時間は「不足」（前の窓が空）、評価 [3, 3, 3] は「解消」→ unknown
    ('32', '2026-09-14', 400, NULL, NULL), ('32', '2026-09-15', 400, NULL, NULL), ('32', '2026-09-16', 400, NULL, NULL),
    ('32', '2026-09-17', 400, 3, NULL), ('32', '2026-09-18', 400, 3, NULL), ('32', '2026-09-19', 400, 3, NULL),
    -- 33 MET_WPEND: 睡眠時間は Δ −70 で「成立」、評価 [1, 2, 2]（平均 1.67）は「保留」→ detected（前 400×4 + 直近 330×4）
    ('33', '2026-09-09', 400, NULL, NULL), ('33', '2026-09-10', 400, NULL, NULL), ('33', '2026-09-11', 400, NULL, NULL),
    ('33', '2026-09-12', 400, NULL, NULL),
    ('33', '2026-09-16', 330, 1, NULL), ('33', '2026-09-17', 330, 2, NULL),
    ('33', '2026-09-18', 330, 2, NULL), ('33', '2026-09-19', 330, NULL, NULL),
    -- 34 PEND_WMET: 睡眠時間は Δ −55 で「保留」、評価 [1, 1, 1] は「成立」→ detected（前 400×4 + 直近 345×4）
    ('34', '2026-09-09', 400, NULL, NULL), ('34', '2026-09-10', 400, NULL, NULL), ('34', '2026-09-11', 400, NULL, NULL),
    ('34', '2026-09-12', 400, NULL, NULL),
    ('34', '2026-09-16', 345, 1, NULL), ('34', '2026-09-17', 345, 1, NULL),
    ('34', '2026-09-18', 345, 1, NULL), ('34', '2026-09-19', 345, NULL, NULL)
  ) AS v(n, day, minutes, rating, arrived);

-- XS SELF: 自己登録の顧客（データは成立する形: 前 400×4・直近 330×4）
INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT 'aaaaaaaa-1003-0001-0000-00000000000d', g.d::date,
       CASE WHEN g.d < '2026-09-13' THEN 400 ELSE 330 END, NULL, 'healthkit',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM generate_series('2026-09-09'::date, '2026-09-19'::date, interval '1 day') AS g(d)
 WHERE g.d::date NOT IN ('2026-09-13', '2026-09-14', '2026-09-15');

-- -----------------------------------------------------------------------------
-- ケース(23): CHECK は sleep_decline を受け付け、未知の値を拒む
--   resolved の行として入れて、生きている行の一意性（alerts_live_client_type_key）には触れない。
--   入れた行はこのブロックの最後に消す
-- -----------------------------------------------------------------------------
\echo '--- case 23: alerts.alert_type の CHECK が sleep_decline を受け付け、未知の値を拒むこと'

DO $$
BEGIN
  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, status, payload,
      first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
    ) VALUES
      ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
       'sleep_decline', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'FAIL: (23) alerts が alert_type = ''sleep_decline'' を拒んだ（%）', SQLERRM;
  END;

  -- 既存の2種別も今までどおり入る
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
  ) VALUES
    ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
     'weight_change', 'high', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared'),
    ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
     'record_gap', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');

  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, status, payload,
      first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
    ) VALUES
      ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000027',
       'sleep_quality', 'medium', 'resolved', '{"v":1}', '2026-09-01', '2026-09-01', '2026-09-01', now(), 'cleared');
    RAISE EXCEPTION 'FAIL: (23) 未知の alert_type（sleep_quality）を受け付けた';
  EXCEPTION
    WHEN check_violation THEN
      IF SQLERRM NOT LIKE '%alerts_alert_type_check%' THEN RAISE; END IF;
  END;

  DELETE FROM public.alerts WHERE client_id = 'cccccccc-1003-0001-0000-000000000027';
  RAISE NOTICE 'OK: CHECK は weight_change / record_gap / sleep_decline を受け付け、未知の値（sleep_quality）を alerts_alert_type_check で拒む';
END $$;

-- 既定の締め時刻（D+1 の JST 0:00）での評価結果（試験用顧客だけ。全種別）
CREATE TEMP TABLE eval_0920 ON COMMIT DROP AS
  SELECT e.*
    FROM public.evaluate_client_alerts('2026-09-20') e
   WHERE e.client_id::text LIKE 'cccccccc-1003-0001-%'
      OR e.client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';

-- -----------------------------------------------------------------------------
-- ケース(1): 睡眠時間が成立（payload の全体を比べる）
-- -----------------------------------------------------------------------------
\echo '--- case 1: 睡眠時間が成立（前 7晩・直近 5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の全体'

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000001' AND e.alert_type = 'sleep_decline';
  IF r.client_id IS NULL THEN
    RAISE EXCEPTION 'FAIL: (1) 監視対象の顧客 01 に sleep_decline の評価行が無い';
  END IF;
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["duration"],
          "recent":   {"from": "2026-09-13", "to": "2026-09-19", "median_minutes": 330, "nights": 5},
          "previous": {"from": "2026-09-06", "to": "2026-09-12", "median_minutes": 400, "nights": 7},
          "delta_minutes": -70,
          "wakeup": {"avg": null, "count": 0},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (1) 睡眠時間の成立が期待と異なる: % / % / %', r.state, r.severity, r.payload;
  END IF;
  RAISE NOTICE 'OK: 前 7晩（中央値 400）・直近 5晩（330）で Δ −70 → detected・medium、payload は設計 §4.6 の形';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(2)(3)(4): 成立・解消の境界と晩の数
-- -----------------------------------------------------------------------------
\echo '--- case 2-4: Δ −60 は成立・−59.5 は保留 / −47 は解消・−48 は保留 / 直近3晩は評価しない'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: %s / %s / %s（期待 %s / %s / triggers %s / delta %s / 直近 %s晩・%s / 前 %s晩・%s）',
                           x.n, e.state, e.severity, e.payload,
                           x.exp_state, x.exp_severity, x.exp_triggers, x.exp_delta,
                           x.exp_recent_nights, x.exp_recent_median, x.exp_previous_nights, x.exp_previous_median), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (2) Δ = −60 ちょうどは成立
      ('02', 'detected', 'medium', '["duration"]', -60, 4, 340, 4, 400),
      -- (2) Δ = −59.5 は保留（delta_minutes は丸めると −60 だが成立しない。前の窓の中央値 400.5 は 401 と出る）
      ('03', 'unknown',  NULL,     '[]',           -60, 4, 341, 4, 401),
      -- (3) Δ = −47 は解消
      ('04', 'cleared',  NULL,     '[]',           -47, 4, 353, 4, 400),
      -- (3) Δ = −48 ちょうどは保留
      ('05', 'unknown',  NULL,     '[]',           -48, 4, 352, 4, 400),
      -- (4) 直近の窓が3晩 → 評価しない（差は出るが unknown）
      ('06', 'unknown',  NULL,     '[]',          -100, 3, 300, 7, 400)
    ) AS x(n, exp_state, exp_severity, exp_triggers, exp_delta,
           exp_recent_nights, exp_recent_median, exp_previous_nights, exp_previous_median)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, e.severity, e.payload->'triggers', (e.payload->>'delta_minutes')::numeric,
          (e.payload->'recent'->>'nights')::int, (e.payload->'recent'->>'median_minutes')::numeric,
          (e.payload->'previous'->>'nights')::int, (e.payload->'previous'->>'median_minutes')::numeric)
         IS DISTINCT FROM
         (x.exp_state, x.exp_severity, x.exp_triggers::jsonb, x.exp_delta::numeric,
          x.exp_recent_nights, x.exp_recent_median::numeric, x.exp_previous_nights, x.exp_previous_median::numeric);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (2)-(4) 境界・晩の数の判定が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: Δ −60 は detected、−59.5 は unknown（delta_minutes −60）、−47 は cleared、−48 は unknown、直近3晩は unknown';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(5)(6)(7): 範囲外の晩・外れ値・窓の境界
-- -----------------------------------------------------------------------------
\echo '--- case 5-7: 119 / 961 分は数えず 120 / 960 分は数える / 1晩の外れ値では成立しない / D−8 は前・D−7 は直近・D−15 は外'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s: %s / %s（期待 %s / delta %s / 直近 %s晩・%s / 前 %s晩・%s）',
                           x.n, e.state, e.payload,
                           x.exp_state, x.exp_delta,
                           x.exp_recent_nights, x.exp_recent_median, x.exp_previous_nights, x.exp_previous_median), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (5) 前の窓は 960×4（961 は数えない）、直近の窓は 120×4（119 は数えない）
      ('07', 'detected', -840, 4, 120, 4, 960),
      -- (6) 前の窓の 900 が1晩あっても中央値は 383 のまま
      ('08', 'cleared',     0, 7, 383, 7, 383),
      -- (6) 直近の窓の 140 が1晩あっても中央値は 383 のまま
      ('09', 'cleared',     0, 4, 383, 4, 383),
      -- (7) 前の窓は 09-06（D−14）・09-10・09-11・09-12（D−8）の4晩、直近の窓は 09-13（D−7）〜09-19 の4晩。
      --     09-05（D−15）は数えない
      ('10', 'detected',  -70, 4, 330, 4, 400)
    ) AS x(n, exp_state, exp_delta, exp_recent_nights, exp_recent_median, exp_previous_nights, exp_previous_median)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, (e.payload->>'delta_minutes')::numeric,
          (e.payload->'recent'->>'nights')::int, (e.payload->'recent'->>'median_minutes')::numeric,
          (e.payload->'previous'->>'nights')::int, (e.payload->'previous'->>'median_minutes')::numeric)
         IS DISTINCT FROM
         (x.exp_state, x.exp_delta::numeric,
          x.exp_recent_nights, x.exp_recent_median::numeric, x.exp_previous_nights, x.exp_previous_median::numeric);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (5)-(7) 範囲外・外れ値・窓の境界の判定が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 範囲は 120〜960 分（両端を含む）、1晩の外れ値は中央値で吸収、窓の境界は D−14 / D−8 / D−7 / D−1';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(8)(9)(10): 登録日・締め時刻・当日と未来の晩
-- -----------------------------------------------------------------------------
\echo '--- case 8-10: 登録日より前の晩は数えない（J+10 は評価しない・J+11 は評価する）/ 締め時刻より後に届いた晩・当日と未来の晩・顧客が書いた異常値は数えない'

DO $$
DECLARE r record;
BEGIN
  -- (8) D = J + 11（09-20）: 前の窓は登録日 09-09 から4晩（登録前の 09-06〜09-08 は数えない）→ 評価して detected
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000011' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected'
     OR r.payload->'previous'->>'from' IS DISTINCT FROM '2026-09-09'
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 4
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 7 THEN
    RAISE EXCEPTION 'FAIL: (8) D = J + 11 の評価が期待（detected・前の窓は 09-09 から4晩）と異なる: % / %', r.state, r.payload;
  END IF;

  -- (8) D = J + 10（09-19）: 前の窓は 09-09〜09-11 の3晩 → 評価しない。
  --     登録前の晩も数えると前の窓が7晩（中央値 330）になり、Δ 0 の cleared になる
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-19') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000011' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR r.payload->'previous'->>'from' IS DISTINCT FROM '2026-09-09'
     OR r.payload->'previous'->>'to' IS DISTINCT FROM '2026-09-11'
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (8) D = J + 10 の評価が期待（unknown・前の窓は 09-09〜09-11 の3晩）と異なる（登録前の晩を数えている疑い）: % / %',
      r.state, r.payload;
  END IF;

  -- (9) 締め時刻 06:00 JST では 09-19 の晩（07:00 に届く）を数えず直近3晩で unknown。08:00 にずらすと4晩で detected
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-20', '2026-09-20 06:00+09') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000012' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (9) 締め時刻 06:00 JST で、後から届いた晩を数えている疑い: % / %', r.state, r.payload;
  END IF;
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-09-20', '2026-09-20 08:00+09') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000012' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'FAIL: (9) 締め時刻を 08:00 JST にずらしても届いた晩が窓に入らない: % / %', r.state, r.payload;
  END IF;

  -- (10) D（09-20）の晩と未来（09-25）の晩は、締め時刻までに届いていても数えない → 直近3晩で unknown
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000013' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown' OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3
     OR r.payload->'recent'->>'to' IS DISTINCT FROM '2026-09-19' THEN
    RAISE EXCEPTION 'FAIL: (10) 当日 D の晩か未来の日付の晩を数えている疑い: % / %', r.state, r.payload;
  END IF;

  -- (10) 顧客が書ける値: ±infinity の起床日と、範囲外（-5 / 2147483647 / 0）の睡眠時間は数えない（評価は落ちない）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000028' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 3
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 330
     OR (r.payload->'previous'->>'nights')::int IS DISTINCT FROM 4 THEN
    RAISE EXCEPTION 'FAIL: (10) ±infinity の起床日か範囲外の睡眠時間を数えている疑い: % / %', r.state, r.payload;
  END IF;
  RAISE NOTICE 'OK: 登録前の晩は数えず J+10 は unknown・J+11 は detected。締め時刻より後に届いた晩・当日 D と未来の晩・±infinity の晩は数えない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(11)(12): 丸める前の差 / 目覚め評価だけで成立
-- -----------------------------------------------------------------------------
\echo '--- case 11-12: delta_minutes は丸める前の差を丸める / 目覚め評価だけで成立（前の窓は nights 0、登録直後も）'

DO $$
DECLARE r record;
BEGIN
  -- (11) 直近 340.5・前 400.0 → delta_minutes は round(−59.5) = −60（round(340.5) − 400 = −59 ではない）。
  --      判定は丸める前の −59.5 なので保留（unknown）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000014' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'unknown'
     OR (r.payload->>'delta_minutes')::numeric IS DISTINCT FROM -60
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 341
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400 THEN
    RAISE EXCEPTION 'FAIL: (11) delta_minutes が丸める前の中央値どうしの差から出ていない: % / %', r.state, r.payload;
  END IF;

  -- (12) 睡眠時間が NULL・範囲外（60）の行の評価 [1, 1, 2]（平均 1.33）だけで成立。睡眠時間は「なし」
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000015' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["wakeup"],
          "recent":   {"from": "2026-09-13", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-06", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": 1.33, "count": 3},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (12) 目覚め評価だけの成立が期待と異なる: % / % / %', r.state, r.severity, r.payload;
  END IF;

  -- (12) 登録直後（J = 09-16）: 直近の窓は 09-16 から、前の窓は from（09-16）が to（09-12）より後で nights 0。
  --      評価 [1, 1, 1] で成立する
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000016' AND e.alert_type = 'sleep_decline';
  IF r.state IS DISTINCT FROM 'detected'
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": ["wakeup"],
          "recent":   {"from": "2026-09-16", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-16", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": 1.00, "count": 3},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (12) 登録直後の目覚め評価の成立・窓の from が期待と異なる: % / %', r.state, r.payload;
  END IF;
  RAISE NOTICE 'OK: delta_minutes は round(340.5 − 400) = −60 で unknown。目覚め評価だけで detected（triggers ["wakeup"]・前の窓 nights 0。登録直後は from が実際の期間）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(13)(14)(15): 目覚め評価の境界・両方成立・§4.4 の表
-- -----------------------------------------------------------------------------
\echo '--- case 13-15: 目覚め評価 1.5 ちょうどは保留・2.0 は解消 / 両方成立 / §4.4 の表の組み合わせ'

DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s（%s）: %s / %s（期待 %s / triggers %s / wakeup %s）',
                           x.n, x.label, e.state, e.payload, x.exp_state, x.exp_triggers, x.exp_wakeup), E'\n')
    INTO v_bad
    FROM (VALUES
      -- (13) 平均ちょうど 1.5 は保留（睡眠時間なし + 目覚め評価が保留 → unknown）
      ('17', '睡眠時間なし + 目覚め評価 保留（1.5 ちょうど）', 'unknown',  '[]',                     '{"avg": 1.50, "count": 4}'),
      -- (13) [2, 2, 2] は解消（§4.4: 睡眠時間なし + 目覚め評価 解消 → cleared）
      ('18', '睡眠時間なし + 目覚め評価 解消（2.0 ちょうど）', 'cleared',  '[]',                     '{"avg": 2.00, "count": 3}'),
      -- (14) 両方成立
      ('19', '睡眠時間 成立 + 目覚め評価 成立',                'detected', '["duration", "wakeup"]', '{"avg": 1.25, "count": 4}'),
      -- (15) §4.4 の表
      ('20', '睡眠時間 成立 + 目覚め評価 解消',                'detected', '["duration"]',           '{"avg": 3.00, "count": 3}'),
      ('21', '睡眠時間 解消 + 目覚め評価 保留',                'unknown',  '[]',                     '{"avg": 1.67, "count": 3}'),
      ('22', '睡眠時間 解消 + 目覚め評価 なし',                'cleared',  '[]',                     '{"avg": null, "count": 0}'),
      ('23', '睡眠時間 解消 + 目覚め評価 不足',                'cleared',  '[]',                     '{"avg": 1.00, "count": 2}'),
      ('24', '睡眠時間 不足 + 目覚め評価 解消',                'unknown',  '[]',                     '{"avg": 3.00, "count": 3}'),
      ('25', '睡眠時間 なし + 目覚め評価 不足',                'unknown',  '[]',                     '{"avg": 1.00, "count": 2}'),
      -- §4.4 の規則1（成立）は規則2（保留・不足）より先。規則2が先だと、次の3つは unknown になる
      ('29', '睡眠時間 不足（登録直後・前の窓が空） + 目覚め評価 成立', 'detected', '["wakeup"]',    '{"avg": 1.00, "count": 3}'),
      ('33', '睡眠時間 成立 + 目覚め評価 保留',                'detected', '["duration"]',           '{"avg": 1.67, "count": 3}'),
      ('34', '睡眠時間 保留 + 目覚め評価 成立',                'detected', '["wakeup"]',             '{"avg": 1.00, "count": 3}'),
      -- 保留・不足は、目覚め評価が解消でも解消させない（unknown）
      ('30', '睡眠時間 保留 + 目覚め評価 解消',                'unknown',  '[]',                     '{"avg": 3.00, "count": 3}'),
      ('32', '睡眠時間 不足（登録直後・前の窓が空） + 目覚め評価 解消', 'unknown', '[]',             '{"avg": 3.00, "count": 3}'),
      -- 目覚め評価は直近の窓だけで数える（D−8 の評価は数えない）。数えると 3回・平均 1.00 で成立し detected になる
      ('31', '睡眠時間 解消 + 目覚め評価 不足（D−8 の評価は数えない）', 'cleared', '[]',             '{"avg": 1.00, "count": 2}')
    ) AS x(n, label, exp_state, exp_triggers, exp_wakeup)
    LEFT JOIN pg_temp.eval_0920 e
      ON e.client_id = ('cccccccc-1003-0001-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'sleep_decline'
   WHERE (e.state, e.payload->'triggers', e.payload->'wakeup')
         IS DISTINCT FROM (x.exp_state, x.exp_triggers::jsonb, x.exp_wakeup::jsonb);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (13)-(15) 目覚め評価・全体の状態が期待と異なる:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: 目覚め評価 1.5 は保留・2.0 は解消、両方成立は triggers ["duration","wakeup"]、§4.4 の表の組み合わせが期待どおり（成立が保留・不足より先。不足・保留 + 解消は unknown。D−8 の評価は数えない）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(16): 監視対象と行の数・全行の不変条件
-- -----------------------------------------------------------------------------
\echo '--- case 16: no_account・self には行が無く、データの無い監視対象には unknown の行がある（1名3行）。全行の不変条件'

DO $$
DECLARE
  r     record;
  cnt   int;
  v_bad text;
BEGIN
  -- 26 NOAUTH（auth.users に行が無い）と XS（自己登録）は、成立する形のデータがあっても評価しない
  SELECT count(*) INTO cnt FROM pg_temp.eval_0920 e
   WHERE e.client_id IN ('cccccccc-1003-0001-0000-000000000026', 'aaaaaaaa-1003-0001-0000-00000000000d');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (16) 監視対象でない顧客（no_account / self）が % 行評価されている', cnt;
  END IF;

  -- 27 NODATA: 睡眠の記録が無い監視対象にも unknown の行が1行ある（窓は登録日 09-15 から）
  SELECT * INTO r FROM pg_temp.eval_0920 e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000027' AND e.alert_type = 'sleep_decline';
  IF r.client_id IS NULL OR r.state IS DISTINCT FROM 'unknown' OR r.severity IS NOT NULL
     OR r.trainer_id IS DISTINCT FROM 'aaaaaaaa-1003-0001-0000-00000000000a'::uuid
     OR r.payload IS DISTINCT FROM
        '{"v": 1,
          "triggers": [],
          "recent":   {"from": "2026-09-15", "to": "2026-09-19", "median_minutes": null, "nights": 0},
          "previous": {"from": "2026-09-15", "to": "2026-09-12", "median_minutes": null, "nights": 0},
          "delta_minutes": null,
          "wakeup": {"avg": null, "count": 0},
          "threshold": {"drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3}}'::jsonb THEN
    RAISE EXCEPTION 'FAIL: (16) データの無い監視対象（27）の sleep_decline 行が期待と異なる: %', row_to_json(r);
  END IF;

  -- 監視対象の顧客は3行（weight_change・record_gap・sleep_decline）ずつ
  SELECT string_agg(format('%s: %s', g.client_id, g.types), E'\n') INTO v_bad
    FROM (
      SELECT e.client_id, array_agg(e.alert_type ORDER BY e.alert_type) AS types
        FROM pg_temp.eval_0920 e
       GROUP BY e.client_id
    ) g
   WHERE g.types IS DISTINCT FROM ARRAY['record_gap', 'sleep_decline', 'weight_change'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (16) 種別ごとに1行ずつ（3行）になっていない顧客がある:\n%', v_bad;
  END IF;
  SELECT count(DISTINCT e.client_id) INTO cnt FROM pg_temp.eval_0920 e;
  IF cnt <> 33 THEN
    RAISE EXCEPTION 'FAIL: (16) 評価された試験用顧客が % 名（期待 33 名 = 01〜25・27〜34）', cnt;
  END IF;

  -- 全行の不変条件: detected ⇔ severity = medium ⇔ triggers が空でない。severity_reason は入れない。v = 1
  SELECT string_agg(format('%s: %s / %s / %s', e.client_id, e.state, e.severity, e.payload), E'\n') INTO v_bad
    FROM pg_temp.eval_0920 e
   WHERE e.alert_type = 'sleep_decline'
     AND (   (e.state = 'detected') IS DISTINCT FROM (e.severity IS NOT DISTINCT FROM 'medium')
          OR (e.state = 'detected') IS DISTINCT FROM (jsonb_array_length(e.payload->'triggers') > 0)
          OR (e.state <> 'detected' AND e.severity IS NOT NULL)
          OR e.payload ? 'severity_reason'
          OR (e.payload->>'v')::int IS DISTINCT FROM 1);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (16) sleep_decline の行の不変条件（detected ⇔ medium ⇔ triggers あり・severity_reason なし）が崩れている:\n%', v_bad;
  END IF;
  RAISE NOTICE 'OK: no_account・self は評価せず、データの無い監視対象は unknown。監視対象は3行ずつ、全行で detected ⇔ medium ⇔ triggers あり';
END $$;

-- 第1部の顧客を片付ける（CASCADE で睡眠の記録・alerts も消える）
DELETE FROM public.clients
 WHERE client_id::text LIKE 'cccccccc-1003-0001-%'
    OR client_id = 'aaaaaaaa-1003-0001-0000-00000000000d';

-- =============================================================================
-- 第2部-1: 状態遷移（ケース 17・18・19・21・22）
--   41 S1: 登録 07-01。09-06〜09-12 は 400、09-13〜09-19 は 330、09-26〜09-29 は 400（どれも起床日の 08:00 JST に届く）
--   本実行: 09-20 → 09-20（再実行）→ 対応済み → 09-21 → 09-26 → 09-30
--     09-20: 前 400×7・直近 330×7 → detected（新規）
--     09-21: 前 [400×6, 330]（400）・直近 330×6 → detected（対応済みのまま継続）
--     09-26: 直近の窓（09-19〜09-25）は 09-19 の1晩だけ → unknown（何も変えない）
--     09-30: 前（09-16〜09-22）330×4・直近（09-23〜09-29）400×4 → Δ +70 で cleared
-- =============================================================================
\echo '--- 第2部-1 setup: 状態遷移用の顧客 S1'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('cccccccc-1003-0001-0000-000000000041', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sleep-alert-test-c41@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('cccccccc-1003-0001-0000-000000000041', '睡眠テスト顧客41',
   'aaaaaaaa-1003-0001-0000-00000000000a', '2026-07-01 12:00+09');

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT 'cccccccc-1003-0001-0000-000000000041', g.d::date, r.minutes, NULL, 'healthkit',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (g.d::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM (VALUES
    ('2026-09-06', '2026-09-12', 400),
    ('2026-09-13', '2026-09-19', 330),
    ('2026-09-26', '2026-09-29', 400)
  ) AS r(from_day, to_day, minutes)
 CROSS JOIN LATERAL generate_series(r.from_day::date, r.to_day::date, interval '1 day') AS g(d);

\echo '--- case 17・22: 新規は open・medium・surfaced_on = D、stats に detected.sleep_decline。同じ D の再実行で件数が増えない'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-09-20');

  -- (22) stats の detected に sleep_decline（数値。S1 の1件以上）
  IF NOT (v_res->'stats'->'detected' ? 'sleep_decline')
     OR jsonb_typeof(v_res->'stats'->'detected'->'sleep_decline') IS DISTINCT FROM 'number'
     OR (v_res->'stats'->'detected'->>'sleep_decline')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (22) stats に detected.sleep_decline（数値・1以上）が無い: %', v_res->'stats';
  END IF;
  -- (22) その値は、同じ D の evaluate の detected の件数と一致する（state で絞らずに数えていないこと）
  IF (v_res->'stats'->'detected'->>'sleep_decline')::int IS DISTINCT FROM
     (SELECT count(*)::int FROM public.evaluate_client_alerts('2026-09-20') e
       WHERE e.alert_type = 'sleep_decline' AND e.state = 'detected') THEN
    RAISE EXCEPTION 'FAIL: (22) stats の detected.sleep_decline が evaluate の detected の件数と異なる: %', v_res->'stats';
  END IF;

  -- (17) 新規: open・medium・first_detected_on = surfaced_on = last_detected_on = D
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF r.id IS NULL OR r.status <> 'open' OR r.severity <> 'medium'
     OR r.trainer_id <> 'aaaaaaaa-1003-0001-0000-00000000000a'
     OR (r.first_detected_on, r.surfaced_on, r.last_detected_on)
        IS DISTINCT FROM ('2026-09-20'::date, '2026-09-20'::date, '2026-09-20'::date)
     OR r.reopened_count <> 0 OR r.acknowledged_at IS NOT NULL OR r.resolved_at IS NOT NULL
     OR r.payload->'triggers' IS DISTINCT FROM '["duration"]'::jsonb
     OR (r.payload->>'delta_minutes')::numeric IS DISTINCT FROM -70
     OR (r.payload->'recent'->>'median_minutes')::numeric IS DISTINCT FROM 330
     OR (r.payload->'previous'->>'median_minutes')::numeric IS DISTINCT FROM 400 THEN
    RAISE EXCEPTION 'FAIL: (17) 睡眠悪化の新規行が期待と異なる: %', row_to_json(r);
  END IF;
  PERFORM set_config('sleep_test.s1_id', r.id::text, true);

  -- (17) 同じ D の再実行: 行は増えず同じ行のまま、新規 0
  v_res := public.run_client_alert_detection('2026-09-20');
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で sleep_decline の行が % 件になった（期待 1 件）', cnt;
  END IF;
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline';
  IF r.id <> current_setting('sleep_test.s1_id')::uuid OR r.status <> 'open' OR r.surfaced_on <> '2026-09-20' THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で行が変わった: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->>'opened')::int <> 0 THEN
    RAISE EXCEPTION 'FAIL: (17) 同じ D の再実行で新規が % 件（期待 0）: %', v_res->'stats'->>'opened', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 09-20 に open・medium・surfaced_on 09-20 で作成、stats.detected.sleep_decline = %。再実行で件数は増えない', v_res->'stats'->'detected'->>'sleep_decline';
END $$;

-- ---- トレーナーが S1 を「対応済み」にする（API Route の条件付き UPDATE と同じ形）----
DO $$
DECLARE n int;
BEGIN
  UPDATE public.alerts
     SET status = 'acknowledged', acknowledged_at = now()
   WHERE id = current_setting('sleep_test.s1_id')::uuid AND status = 'open';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: S1 を対応済みにできない（% 行）', n;
  END IF;
END $$;

\echo '--- case 21・18: 対応済みは成立が続いても対応済みのまま / 保留（unknown）の日は status・last_detected_on・payload が変わらない'

DO $$
DECLARE
  r         record;
  v_payload jsonb;
  v_state   text;
BEGIN
  -- (21) 09-21 も成立（重大度は medium のまま上がらない）→ acknowledged のまま、last_detected_on と payload だけ進む
  PERFORM public.run_client_alert_detection('2026-09-21');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.acknowledged_at IS NULL OR r.reopened_count <> 0
     OR r.severity <> 'medium' OR r.surfaced_on <> '2026-09-20' OR r.last_detected_on <> '2026-09-21'
     OR (r.payload->'recent'->>'nights')::int IS DISTINCT FROM 6
     OR r.payload->'recent'->>'from' IS DISTINCT FROM '2026-09-14' THEN
    RAISE EXCEPTION 'FAIL: (21) 成立が続いた対応済みの S1 が期待と異なる（acknowledged のまま・last_detected_on 09-21）: %', row_to_json(r);
  END IF;
  v_payload := r.payload;

  -- (18) 09-26 は直近の窓が1晩で評価できない（unknown）
  SELECT e.state INTO v_state FROM public.evaluate_client_alerts('2026-09-26') e
   WHERE e.client_id = 'cccccccc-1003-0001-0000-000000000041' AND e.alert_type = 'sleep_decline';
  IF v_state IS DISTINCT FROM 'unknown' THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 09-26 の S1 の評価が %（期待 unknown）', v_state;
  END IF;
  PERFORM public.run_client_alert_detection('2026-09-26');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.resolved_at IS NOT NULL OR r.last_detected_on <> '2026-09-21'
     OR r.payload IS DISTINCT FROM v_payload THEN
    RAISE EXCEPTION 'FAIL: (18) 保留（unknown）の日に S1 が変わった: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: 対応済みの S1 は 09-21 の成立でも acknowledged のまま（last_detected_on 09-21）。09-26 の unknown では何も変わらない';
END $$;

\echo '--- case 19: 後の日に cleared → resolved（cleared）'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-09-30');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('sleep_test.s1_id')::uuid;
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'cleared' OR r.resolved_at IS NULL
     OR r.last_detected_on <> '2026-09-21' THEN
    RAISE EXCEPTION 'FAIL: (19) 睡眠が戻った S1 が resolved（cleared）になっていない: %', row_to_json(r);
  END IF;
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000041' AND a.alert_type = 'sleep_decline'
     AND a.resolved_at IS NULL;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (19) 解消した後も S1 に生きている sleep_decline が % 件ある', cnt;
  END IF;
  IF (v_res->'stats'->'resolved'->>'cleared')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (19) stats の resolved.cleared が 1 未満: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 09-30 に Δ +70 で S1 は resolved（cleared）';
END $$;

-- 第2部-1 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-1003-0001-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-2: 期限切れ（ケース 20。D = 2026-09-30、D−14 = 09-16、D−13 = 09-17）
--   51: 監視対象・直近の窓が2晩（09-27・09-28）で unknown。生きている sleep_decline（acknowledged）、
--       last_detected_on = 09-16（D−14）→ expired（対応済みの行も期限切れで閉じる。閉じないと、
--       alerts_live_client_type_key のせいで、その顧客の睡眠がまた悪化しても新しい行が作られない）
--   52: 51 と同じデータ。生きている sleep_decline（open）、last_detected_on = 09-17（D−13）→ 残る
--   53: inactive（最終到着 08-01）で評価されない。生きている sleep_decline（open）、
--       last_detected_on = 09-10 → expired（監視対象から外れた顧客の行も閉じる）
--   51・52 の評価は cleared にならない（cleared だと、評価の段が先に D−13 の行も解消で閉じてしまい、
--   「D−14 は期限切れで閉じ、D−13 は残る」という境界を確かめられない）
-- =============================================================================
\echo '--- 第2部-2 setup: 期限切れ用の顧客 51・52・53'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sleep-alert-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['51','52','53']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, created_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || n)::uuid, '睡眠テスト顧客' || n,
       'aaaaaaaa-1003-0001-0000-00000000000a', '2026-07-01 12:00+09'
  FROM unnest(ARRAY['51','52','53']) AS n;

INSERT INTO public.sleep_records (client_id, recorded_date, total_sleep_minutes, wakeup_rating, source, created_at, updated_at)
SELECT ('cccccccc-1003-0001-0000-0000000000' || v.n)::uuid, v.day::date, 400, NULL, 'healthkit',
       (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo',
       (v.day::date + time '08:00') AT TIME ZONE 'Asia/Tokyo'
  FROM (VALUES
    ('51', '2026-09-27'), ('51', '2026-09-28'),
    ('52', '2026-09-27'), ('52', '2026-09-28'),
    ('53', '2026-08-01')
  ) AS v(n, day);

INSERT INTO public.alerts (
  trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, acknowledged_at
) VALUES
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000051',
   'sleep_decline', 'medium', 'acknowledged', '{"v":1}', '2026-09-10', '2026-09-10', '2026-09-16', now()),
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000052',
   'sleep_decline', 'medium', 'open', '{"v":1}', '2026-09-10', '2026-09-10', '2026-09-17', NULL),
  ('aaaaaaaa-1003-0001-0000-00000000000a', 'cccccccc-1003-0001-0000-000000000053',
   'sleep_decline', 'medium', 'open', '{"v":1}', '2026-09-05', '2026-09-05', '2026-09-10', NULL);

\echo '--- case 20: last_detected_on = D−14 の生きている sleep_decline は（対応済みでも）expired、D−13 の open は残る（評価は unknown）。評価されない顧客の行も expired。stats の件数'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  v_bad text;
BEGIN
  -- 前提: 51・52 の評価は unknown（cleared ではない）、53 は評価されない（inactive）
  SELECT string_agg(format('%s: %s', e.client_id, e.state), ', ') INTO v_bad
    FROM public.evaluate_client_alerts('2026-09-30') e
   WHERE e.alert_type = 'sleep_decline'
     AND ((e.client_id IN ('cccccccc-1003-0001-0000-000000000051', 'cccccccc-1003-0001-0000-000000000052')
           AND e.state <> 'unknown')
          OR e.client_id = 'cccccccc-1003-0001-0000-000000000053');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 期限切れ用の顧客の評価が期待（51・52 は unknown、53 は評価なし）と異なる: %', v_bad;
  END IF;

  v_res := public.run_client_alert_detection('2026-09-30');

  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000051';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' OR r.last_detected_on <> '2026-09-16' THEN
    RAISE EXCEPTION 'FAIL: (20) last_detected_on = D−14 の sleep_decline（対応済み）が expired になっていない: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000052';
  IF r.id IS NULL OR r.resolved_at IS NOT NULL OR r.status <> 'open' OR r.last_detected_on <> '2026-09-17' THEN
    RAISE EXCEPTION 'FAIL: (20) last_detected_on = D−13 の sleep_decline（open）が閉じられた / 変わった: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-1003-0001-0000-000000000053';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'FAIL: (20) 評価されない（inactive）顧客の古い sleep_decline が expired になっていない: %', row_to_json(r);
  END IF;
  -- (22) この日の 51・52 は unknown なので、state で絞らずに数えると detected の件数より多くなる
  IF (v_res->'stats'->'detected'->>'sleep_decline')::int IS DISTINCT FROM
     (SELECT count(*)::int FROM public.evaluate_client_alerts('2026-09-30') e
       WHERE e.alert_type = 'sleep_decline' AND e.state = 'detected') THEN
    RAISE EXCEPTION 'FAIL: (22) stats の detected.sleep_decline が evaluate の detected の件数と異なる: %', v_res->'stats';
  END IF;
  IF (v_res->'stats'->'resolved'->>'expired')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (20) stats の resolved.expired が 2 未満（51 と 53）: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: D−14 の sleep_decline は対応済みでも expired、D−13 の open は残る。inactive の顧客の古い行も expired。stats は evaluate の detected の件数と一致';
END $$;

-- 第2部-2 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-1003-0001-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第3部: 登録内容（ケース 24）
-- =============================================================================
\echo '--- case 24: 両関数が SECURITY DEFINER・search_path = ""、EXECUTE は service_role だけ（proacl と PUBLIC を含めて）'

DO $$
DECLARE
  v_fn       regprocedure;
  r          record;
  v_grantees text[];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure
  ] LOOP
    SELECT p.prosecdef, p.proconfig, p.proacl INTO r FROM pg_proc p WHERE p.oid = v_fn;
    IF NOT r.prosecdef THEN
      RAISE EXCEPTION 'FAIL: (24) % が SECURITY DEFINER になっていない', v_fn;
    END IF;
    IF r.proconfig IS NULL OR NOT ('search_path=""' = ANY (r.proconfig)) THEN
      RAISE EXCEPTION 'FAIL: (24) % の search_path が空文字に固定されていない（proconfig=%）',
        v_fn, coalesce(r.proconfig::text, 'NULL');
    END IF;
    -- proacl が NULL = 既定権限（PUBLIC に EXECUTE）
    IF r.proacl IS NULL THEN
      RAISE EXCEPTION 'FAIL: (24) % の proacl が NULL（既定権限 = PUBLIC に EXECUTE が付いたまま）', v_fn;
    END IF;
    -- EXECUTE を持つのはオーナー（postgres）と service_role だけ（PUBLIC = grantee 0 を含めて数える）
    SELECT array_agg(g.grantee_name ORDER BY g.grantee_name) INTO v_grantees
      FROM (
        SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee)::text END AS grantee_name
          FROM pg_proc p, aclexplode(p.proacl) AS a
         WHERE p.oid = v_fn AND a.privilege_type = 'EXECUTE'
      ) g;
    IF v_grantees IS DISTINCT FROM ARRAY['postgres', 'service_role'] THEN
      RAISE EXCEPTION 'FAIL: (24) % の EXECUTE の付与先が %（期待 {postgres,service_role}）', v_fn, v_grantees;
    END IF;
    IF has_function_privilege('anon', v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL: (24) % の EXECUTE 権限が期待（anon・authenticated なし、service_role あり）と異なる', v_fn;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: evaluate_client_alerts・run_client_alert_detection は SECURITY DEFINER + search_path = ""、EXECUTE は postgres と service_role だけ';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL SLEEP DECLINE ALERT TESTS PASSED'
