-- =============================================================================
-- 異常検知（evaluate_client_alerts / run_client_alert_detection）と cron 登録のテスト
-- （フェーズ9.1 / 20260914000200_client_alert_detection.sql。snapshot は 20260914000100）
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/client_alert_detection_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CLIENT ALERT DETECTION TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない
--
-- 方針（計画書 PR1 レーンA-6）:
--   - BEGIN の直後に alerts と alert_detection_runs を DELETE する（ROLLBACK で戻る）。
--     QA のための手動実行と順番を気にしなくてよく、「最後の本実行より前は例外」のガードも
--     試験の中で制御できる
--   - 件数・状態の assert は試験用の顧客に限る（本実行は全顧客を評価するので、seed の顧客にも
--     行ができうる。session_reminder_test.sql と同じ）。stats は全体の件数なので「以上」で見るか、
--     再実行の収束（新規 0）のようにデータに依らない性質だけを見る
--   - 対象日は過去の固定日（2026-08）。本実行の締め時刻は既定の LEAST(now(), D+1 の JST 0:00) =
--     D+1 の JST 0:00 になる前提で、到着（created_at / read_at）を JST で明示して書く。
--     締め時刻の境界は evaluate(p_as_of) で確かめる
--   - JST の境界は、UTC の日付で判定すると結果が変わるデータにする
--     （D の JST 0:30 = UTC 前日 15:30。lessons「JST の『暦日』判定は範囲比較で書く」）
--   - 本実行のシナリオ（第2部）は、シナリオごとに顧客を作り、終わったら顧客（CASCADE で記録・
--     alerts も）・メッセージ・alert_detection_runs を消してから次へ進む（他のシナリオの本実行で
--     状態が動かないように）
--   - messages の AFTER INSERT トリガー（call_parse_message_tags）は本番 URL へ net.http_post を
--     積むため、試験メッセージの INSERT の間だけ session_replication_role = replica で止める
--   - 関数は postgres（cron と同じ実行ロール）で呼ぶ。EXECUTE 権限は client_alerts_rls_test.sql で確かめる
--
-- 検証ケース:
--   第1部 evaluate（D = 2026-08-20。書き込まない）
--   (a) JST の境界: (D−7) の JST 0:30 は直近の窓、(D−8) の JST 23:30 は前の窓、D の JST 0:30 は窓の外。
--       最終到着が (D−3) の JST 0:30 なら検知せず、(D−4) の JST 23:30 なら検知
--   (b) 体重: 2.9% / 1.9kg は不成立、3.0% ちょうど / 2.0kg ちょうどで成立。片方の窓が2日なら評価しない。
--       1日10件の中の外れ値は中央値で安定。±15% 超の日と範囲外の値（10kg）は除外。
--       登録日より前の計測は使わない。窓の中で計測しても締め時刻より後に届いた体重は数えない
--   (c) diet の減少は medium（severity_reason = diet_decrease）、diet の増加と他の purpose の減少は high
--   (d) 途絶: 登録翌日・既読だけ・記録なし → 検知しない（登録前の計測が一括で届いていても）/
--       登録から3日 → not_started・N=3・medium / 登録15日超の未開始 → 評価しない（対象外）/
--       no_data（3日で medium、7日で high）/ no_record（前日に既読はあるが記録なし）/
--       最後の記録が登録日より前でも日数は登録日から数える /
--       締め時刻より後に届いた計測は数えずに no_data、締め時刻を後ろにずらすと cleared
--   (d-healthkit) HealthKit の体重（計測日の 23:59 JST で入る）だけの顧客: D の 05:00 JST に届いた D の体重で
--       R = D になり、06:00 の評価で no_data（記録・同期なし）にしない（最終記録の翌日からの no_record 4日）。
--       締め時刻を届く前の D 04:59 にずらすと no_data（R は到着時刻だけで決まる）
--   (e) 対象外: auth が無い / 自己登録 / 最終到着が D−15（生きている行が無い）→ 評価しない
--   (i) evaluate は READ ONLY の中でも実行でき、行数を変えない（run は READ ONLY では失敗する）
--   第2部 run
--   (f) 状態遷移を1本の流れで: 作成 → 同じ日の再実行で行数は変わらず payload が更新 → 対応済み →
--       条件が続いても acknowledged のまま → 7日で high に上がり1回だけ再浮上 → 重大度が下がって
--       また上がる（2回目の昇格）では再浮上しない → cleared → 再発で新しい行。
--       別の顧客で open のまま medium → high に上がると surfaced_on = D。
--       その顧客が登録15日超の未開始（not_started）になると、生きている record_gap は監視を延ばさず
--       expired で閉じる（オーナー決定 (1)）
--   (g) 担当替えは reassigned で閉じ、新しい担当の分ができる。auth.users の削除・自己登録化で ineligible
--   (b') ヒステリシス（3.1% → 2.6% で継続、2.3% で解消）/ 14日再確認されなければ expired
--       （評価されなかった顧客の weight_change にも掛かる）。record_gap は顧客が inactive になると expired
--   (h) ガード: 対象日が NULL / 未来 / 最後の本実行より前なら例外（同じ対象日は許す）。
--       evaluate の締め時刻が範囲外・対象日が NULL / 未来なら例外
--   (j) 本実行が1回成功すると alert_detection_runs が1行増え、stats に client_id が含まれない
--   (k) 生きている行を二重に INSERT すると unique_violation（resolved の行とは共存できる）
--   (n) 登録日が ±infinity の顧客（顧客本人が clients.created_at を書き換えた）がいても、本実行・evaluate・
--       状態 RPC が落ちない（22008 で全トレーナー分の検知が止まらない）。その顧客の生きている行は ineligible
--   第3部 登録内容
--   (l) cron: jobname が1件だけ、schedule が 0 21 * * *、command に run_client_alert_detection と
--       'Asia/Tokyo' を含み net.http_post を含まない。command を EXPLAIN（ANALYZE なし）で解析・計画でき、
--       前後で alerts / alert_detection_runs の件数が変わらない（active はアサートしない）
--   (m) 関数の定義に 'Asia/Tokyo' が含まれる。4つの DEFINER 関数すべてに search_path = "" が設定されている。
--       本実行は遷移の前に生きている行を FOR UPDATE でロックする（API の対応済みと同時に走っても再浮上を落とさない）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DELETE FROM public.alerts;
DELETE FROM public.alert_detection_runs;

-- -----------------------------------------------------------------------------
-- 共通の試験データ（postgres として実行。RLS バイパス）
--   trainer T  : aaaaaaaa-0914-0002-0000-00000000000a（試験用顧客の担当。business）
--   trainer T2 : aaaaaaaa-0914-0002-0000-00000000000b（担当替え先）
--   trainer XS : aaaaaaaa-0914-0002-0000-00000000000d（自己登録: 自分自身が顧客）
--   client  NN : cccccccc-0914-0002-0000-0000000000NN（第1部 01〜27、第2部 41〜83）
-- -----------------------------------------------------------------------------
\echo '--- setup: 共通の試験データ作成 (trainer T・T2・XS)'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-' || v.id || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-0914-0002-0000-00000000000a'),
    ('aaaaaaaa-0914-0002-0000-00000000000b'),
    ('aaaaaaaa-0914-0002-0000-00000000000d')
  ) AS v(id);

INSERT INTO public.trainers (id, name, email, subscription_plan)
SELECT v.id::uuid, v.name, 'detection-test-' || v.id || '@example.com', 'business'
  FROM (VALUES
    ('aaaaaaaa-0914-0002-0000-00000000000a', '検知テスト トレーナーT'),
    ('aaaaaaaa-0914-0002-0000-00000000000b', '検知テスト トレーナーT2'),
    ('aaaaaaaa-0914-0002-0000-00000000000d', '検知テスト 自己登録XS')
  ) AS v(id, name);

-- =============================================================================
-- 第1部: evaluate_client_alerts（D = 2026-08-20、既定の締め時刻 = 2026-08-21 0:00 JST）
--   D−14 = 08-06、D−8 = 08-12、D−7 = 08-13、D−1 = 08-19
--   01 W_BND        : 窓の JST 境界（08-12 23:30 / 08-13 0:30 / 08-20 0:30 の体重）
--   02 R_BND_NO     : 最終到着 08-17 0:30 JST（D−3）→ 検知しない
--   03 R_BND_YES    : 最終到着 08-16 23:30 JST（D−4）→ no_data N=3
--   04 W_PCT29      : 50.0 → 51.45（2.9%）       05 W_KG19  : 80.0 → 81.9（1.9kg）
--   06 W_PCT30      : 50.0 → 51.5（3.0% ちょうど） 07 W_KG20  : 80.0 → 82.0（2.0kg ちょうど）
--   08 W_2DAYS      : 直近の窓が2日               09 W_10PER : 1日10件の中に 81.0 が1件
--   10 W_OUTLIER    : ±15% 超の日と 10kg の値      11 W_PREJOIN: 登録（08-08）前の計測がある
--   12 W_DIET_DEC   : diet 62 → 60                13 W_DIET_INC: diet 60 → 62
--   14 W_OTHER_DEC  : health_improvement 62 → 60
--   15 G_NEW1       : 登録 08-19・既読だけ         16 G_NEW1_PRE: 登録 08-19・登録前の計測が一括で届いた
--   17 G_NEW3       : 登録 08-17・何もなし         18 G_NEW15 : 登録 08-05・何もなし
--   19 G_NODATA7    : 最終到着 08-12              20 G_NOREC : 最終記録 08-15・既読 08-19
--   21 G_PRELAST    : 登録 08-14・最後の記録は登録前の 08-01・既読 08-19
--   22 G_ASOF       : 計測 08-19 の体重が 08-20 07:00 JST に届く
--   23 E_NOAUTH     : auth.users に行が無い（登録 08-15）
--   XS E_SELF       : 自己登録（登録 08-15）
--   25 E_INACT15    : 最終到着 08-05（D−15）
--   26 W_ASOF       : 60.0 → 62.0。直近の窓の3日目（08-18 の計測）が 08-20 07:00 JST に届く
--   27 G_HK         : HealthKit の体重だけ（計測日の 23:59 JST で入る）。08-15 分は 08-15 07:00 に、
--                     D（08-20）分は D の 05:00 JST（06:00 の本実行より前）に届いた
--   ※ 24 は XS 自身なので欠番
-- =============================================================================
\echo '--- 第1部 setup: evaluate 用の試験用顧客 01〜27'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['01','02','03','04','05','06','07','08','09','10','11','12','13','14',
                    '15','16','17','18','19','20','21','22','25','26','27']) AS n;  -- 23 E_NOAUTH は入れない

INSERT INTO public.clients (client_id, name, trainer_id, purpose, created_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || v.n)::uuid, '検知テスト顧客' || v.n,
       'aaaaaaaa-0914-0002-0000-00000000000a', v.purpose, v.created_at::timestamptz
  FROM (VALUES
    ('01', 'health_improvement', '2026-07-01 12:00+09'),
    ('02', 'health_improvement', '2026-07-01 12:00+09'),
    ('03', 'health_improvement', '2026-07-01 12:00+09'),
    ('04', 'health_improvement', '2026-07-01 12:00+09'),
    ('05', 'health_improvement', '2026-07-01 12:00+09'),
    ('06', 'health_improvement', '2026-07-01 12:00+09'),
    ('07', 'health_improvement', '2026-07-01 12:00+09'),
    ('08', 'health_improvement', '2026-07-01 12:00+09'),
    ('09', 'health_improvement', '2026-07-01 12:00+09'),
    ('10', 'health_improvement', '2026-07-01 12:00+09'),
    ('11', 'health_improvement', '2026-08-08 10:00+09'),
    ('12', 'diet',               '2026-07-01 12:00+09'),
    ('13', 'diet',               '2026-07-01 12:00+09'),
    ('14', 'health_improvement', '2026-07-01 12:00+09'),
    ('15', 'health_improvement', '2026-08-19 10:00+09'),
    ('16', 'health_improvement', '2026-08-19 10:00+09'),
    ('17', 'health_improvement', '2026-08-17 12:00+09'),
    ('18', 'health_improvement', '2026-08-05 12:00+09'),
    ('19', 'health_improvement', '2026-07-01 12:00+09'),
    ('20', 'health_improvement', '2026-07-01 12:00+09'),
    ('21', 'health_improvement', '2026-08-14 12:00+09'),
    ('22', 'health_improvement', '2026-07-01 12:00+09'),
    ('23', 'health_improvement', '2026-08-15 12:00+09'),
    ('25', 'health_improvement', '2026-07-01 12:00+09'),
    ('26', 'health_improvement', '2026-07-01 12:00+09'),
    ('27', 'health_improvement', '2026-07-01 12:00+09')
  ) AS v(n, purpose, created_at);

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000d', '検知テスト 自己登録XS',
   'aaaaaaaa-0914-0002-0000-00000000000d', '2026-08-15 12:00+09');

-- 体重（到着 created_at を省略した行は計測 + 5分に届いたものとする）
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || v.n)::uuid, v.w, v.at::timestamptz, 'manual',
       coalesce(v.arrived::timestamptz, v.at::timestamptz + interval '5 minutes'),
       coalesce(v.arrived::timestamptz, v.at::timestamptz + interval '5 minutes')
  FROM (VALUES
    -- 01 W_BND: 前の窓 08-07 / 08-09 / 08-12 23:30 は 60.0、直近の窓 08-13 0:30 / 08-15 / 08-17 は 62.0。
    --   D の 0:30（UTC 08-19 15:30）の 60.0 は窓の外。UTC の日付で判定すると 08-12 23:30 と 08-13 0:30 が
    --   同じ日（UTC 08-12）にまとまり、D の 0:30 が直近の窓に入って Δ = 1.0kg（1.66%）の cleared になる
    ('01', '2026-08-07 08:00+09', 60.0, NULL),
    ('01', '2026-08-09 08:00+09', 60.0, NULL),
    ('01', '2026-08-12 23:30+09', 60.0, NULL),
    ('01', '2026-08-13 00:30+09', 62.0, NULL),
    ('01', '2026-08-15 08:00+09', 62.0, NULL),
    ('01', '2026-08-17 08:00+09', 62.0, NULL),
    ('01', '2026-08-20 00:30+09', 60.0, NULL),
    -- 02 R_BND_NO: 最終到着 08-17 0:30 JST（UTC では 08-16 15:30 = D−4 になり no_data と誤判定される）
    ('02', '2026-08-16 20:00+09', 60.0, '2026-08-17 00:30+09'),
    -- 03 R_BND_YES: 最終到着 08-16 23:30 JST（= D−4）→ no_data N=3（08-17〜08-19）
    ('03', '2026-08-15 20:00+09', 60.0, '2026-08-16 23:30+09'),
    -- 08 W_2DAYS: 前の窓 3日（60.0）、直近の窓 2日（65.0）→ 評価しない
    ('08', '2026-08-07 08:00+09', 60.0, NULL),
    ('08', '2026-08-09 08:00+09', 60.0, NULL),
    ('08', '2026-08-11 08:00+09', 60.0, NULL),
    ('08', '2026-08-14 08:00+09', 65.0, NULL),
    ('08', '2026-08-16 08:00+09', 65.0, NULL),
    -- 09 W_10PER: 前の窓 60.0、直近の窓 61.0。08-18 は10件（61.0 × 9 と 81.0 × 1）。
    --   中央値なら 61.0 で Δ = 1.0kg（1.67%）の cleared。平均だと 63.0 になり unknown
    ('09', '2026-08-07 08:00+09', 60.0, NULL),
    ('09', '2026-08-09 08:00+09', 60.0, NULL),
    ('09', '2026-08-11 08:00+09', 60.0, NULL),
    ('09', '2026-08-14 08:00+09', 61.0, NULL),
    ('09', '2026-08-16 08:00+09', 61.0, NULL),
    ('09', '2026-08-18 07:00+09', 61.0, NULL),
    ('09', '2026-08-18 07:01+09', 61.0, NULL),
    ('09', '2026-08-18 07:02+09', 61.0, NULL),
    ('09', '2026-08-18 07:03+09', 61.0, NULL),
    ('09', '2026-08-18 07:04+09', 61.0, NULL),
    ('09', '2026-08-18 07:05+09', 61.0, NULL),
    ('09', '2026-08-18 07:06+09', 61.0, NULL),
    ('09', '2026-08-18 07:07+09', 61.0, NULL),
    ('09', '2026-08-18 07:08+09', 61.0, NULL),
    ('09', '2026-08-18 07:09+09', 81.0, NULL),
    -- 10 W_OUTLIER: 08-11 は 60.0 と 10.0（範囲外）。08-19 の 70.0 は14日分の中央値 60.0 から +16.7%（外れ値）。
    --   除外すれば両方の窓が 60.0 で cleared。70.0 を残すと直近の平均 62.5 で detected、
    --   10.0 を残すと 08-11 の代表値が 35.0 になって外れ値で落ち、前の窓が2日で unknown
    ('10', '2026-08-07 08:00+09', 60.0, NULL),
    ('10', '2026-08-09 08:00+09', 60.0, NULL),
    ('10', '2026-08-11 08:00+09', 60.0, NULL),
    ('10', '2026-08-11 09:00+09', 10.0, NULL),
    ('10', '2026-08-14 08:00+09', 60.0, NULL),
    ('10', '2026-08-16 08:00+09', 60.0, NULL),
    ('10', '2026-08-18 08:00+09', 60.0, NULL),
    ('10', '2026-08-19 08:00+09', 70.0, NULL),
    -- 11 W_PREJOIN: 登録は 08-08 10:00。08-06 / 08-07 の 62.0 は登録前の計測（登録時に一括で届いた）。
    --   登録後の前の窓 08-08 / 08-10 / 08-12 は 60.0、直近の窓は 62.0 → Δ = 2.0kg で detected。
    --   登録前も使うと前の窓の平均が 60.8 になり Δ = 1.2kg（1.97%）の cleared
    ('11', '2026-08-06 08:00+09', 62.0, '2026-08-08 10:05+09'),
    ('11', '2026-08-07 08:00+09', 62.0, '2026-08-08 10:05+09'),
    ('11', '2026-08-08 20:00+09', 60.0, NULL),
    ('11', '2026-08-10 08:00+09', 60.0, NULL),
    ('11', '2026-08-12 08:00+09', 60.0, NULL),
    ('11', '2026-08-14 08:00+09', 62.0, NULL),
    ('11', '2026-08-16 08:00+09', 62.0, NULL),
    ('11', '2026-08-18 08:00+09', 62.0, NULL),
    -- 16 G_NEW1_PRE: 登録（08-19 10:00）時に、登録前の 07-20 の計測が一括で届いた
    ('16', '2026-07-20 08:00+09', 60.0, '2026-08-19 10:05+09'),
    -- 19 G_NODATA7: 最終到着 08-12 → no_data N=7（08-13〜08-19）
    ('19', '2026-08-11 20:00+09', 60.0, '2026-08-12 08:00+09'),
    -- 20 G_NOREC: 最終記録 08-15（到着も 08-15）。既読は下の messages（08-19）
    ('20', '2026-08-15 08:00+09', 60.0, NULL),
    -- 21 G_PRELAST: 登録（08-14 12:00）前の 08-01 の計測が登録時に届いた。既読は下の messages（08-19）
    ('21', '2026-08-01 08:00+09', 60.0, '2026-08-14 12:05+09'),
    -- 22 G_ASOF: 08-15 の計測（到着 08-15）と、計測 08-19 だが到着が 08-20 07:00 JST の行
    ('22', '2026-08-15 08:00+09', 60.0, NULL),
    ('22', '2026-08-19 08:00+09', 60.0, '2026-08-20 07:00+09'),
    -- 25 E_INACT15: 最終到着 08-05（= D−15）
    ('25', '2026-08-04 08:00+09', 60.0, '2026-08-05 08:00+09'),
    -- 26 W_ASOF: 前の窓 08-07 / 08-09 / 08-11 は 60.0、直近の窓 08-14 / 08-16 / 08-18 は 62.0。
    --   08-18 の計測だけ到着が 08-20 07:00 JST → 締め時刻 06:00 では直近の窓が2日（unknown）、
    --   08:00 にずらすと3日そろって Δ = 2.0kg の detected
    ('26', '2026-08-07 08:00+09', 60.0, NULL),
    ('26', '2026-08-09 08:00+09', 60.0, NULL),
    ('26', '2026-08-11 08:00+09', 60.0, NULL),
    ('26', '2026-08-14 08:00+09', 62.0, NULL),
    ('26', '2026-08-16 08:00+09', 62.0, NULL),
    ('26', '2026-08-18 08:00+09', 62.0, '2026-08-20 07:00+09')
  ) AS v(n, at, w, arrived);

-- 閾値・diet のケース（前の窓 08-07 / 08-09 / 08-11、直近の窓 08-14 / 08-16 / 08-18 の各3日）
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || v.n)::uuid,
       CASE d.win WHEN 'previous' THEN v.previous_kg ELSE v.recent_kg END,
       d.at::timestamptz, 'healthkit',
       d.at::timestamptz + interval '5 minutes', d.at::timestamptz + interval '5 minutes'
  FROM (VALUES
    ('04', 50.0, 51.45),  -- Δ 1.45kg / 2.9%  → 不成立（unknown）
    ('05', 80.0, 81.9),   -- Δ 1.9kg  / 2.375% → 不成立（unknown）
    ('06', 50.0, 51.5),   -- Δ 1.5kg  / 3.0%  → 成立
    ('07', 80.0, 82.0),   -- Δ 2.0kg  / 2.5%  → 成立
    ('12', 62.0, 60.0),   -- diet の減少    → medium
    ('13', 60.0, 62.0),   -- diet の増加    → high
    ('14', 62.0, 60.0)    -- 他の目的の減少 → high
  ) AS v(n, previous_kg, recent_kg)
 CROSS JOIN (VALUES
    ('previous', '2026-08-07 08:00+09'), ('previous', '2026-08-09 08:00+09'), ('previous', '2026-08-11 08:00+09'),
    ('recent',   '2026-08-14 08:00+09'), ('recent',   '2026-08-16 08:00+09'), ('recent',   '2026-08-18 08:00+09')
  ) AS d(win, at);

-- 27 G_HK: HealthKit の体重は計測日の 23:59 JST で入る（到着 created_at のほうが計測時刻より前になる）。
--   08-15 分は 08-15 07:00 に、D（08-20）分は D の 05:00 に届いた
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at) VALUES
  ('cccccccc-0914-0002-0000-000000000027', 60.0, '2026-08-15 23:59+09', 'healthkit',
   '2026-08-15 07:00+09', '2026-08-15 07:00+09'),
  ('cccccccc-0914-0002-0000-000000000027', 60.0, '2026-08-20 23:59+09', 'healthkit',
   '2026-08-20 05:00+09', '2026-08-20 05:00+09');

-- messages（AFTER INSERT トリガーが本番 URL へ net.http_post を積むので、この INSERT の間だけ止める）
SET LOCAL session_replication_role = replica;

INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  -- 15 G_NEW1: 登録当日にトレーナーのメッセージを既読
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000015', 'trainer', 'client',
   '検知テスト: ようこそ', '2026-08-19 10:30+09', '2026-08-19 20:00+09'),
  -- 16 G_NEW1_PRE: 同上
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000016', 'trainer', 'client',
   '検知テスト: ようこそ', '2026-08-19 10:30+09', '2026-08-19 20:00+09'),
  -- 20 G_NOREC: 前日（08-19）に既読
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000020', 'trainer', 'client',
   '検知テスト: 調子はどうですか', '2026-08-10 10:00+09', '2026-08-19 21:00+09'),
  -- 21 G_PRELAST: 前日（08-19）に既読
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000021', 'trainer', 'client',
   '検知テスト: ようこそ', '2026-08-14 13:00+09', '2026-08-19 21:00+09');

SET LOCAL session_replication_role = origin;

-- 既定の締め時刻（D+1 の JST 0:00）での評価結果（試験用顧客だけ）
CREATE TEMP TABLE eval_0820 ON COMMIT DROP AS
  SELECT e.*
    FROM public.evaluate_client_alerts('2026-08-20') e
   WHERE e.client_id::text LIKE 'cccccccc-0914-0002-%'
      OR e.client_id = 'aaaaaaaa-0914-0002-0000-00000000000d';

-- -----------------------------------------------------------------------------
-- ケース(a): JST の境界
-- -----------------------------------------------------------------------------
\echo '--- case a: 体重の窓と最終到着の JST 境界（UTC の日付だと結果が変わるデータ）'

DO $$
DECLARE r record;
BEGIN
  -- 01 W_BND: (D−7) 0:30 は直近、(D−8) 23:30 は前、D 0:30 は窓の外 → 各3日・Δ = +2.0kg で detected
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000001' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'high'
     OR (r.payload->'recent'->>'days')::int IS DISTINCT FROM 3
     OR (r.payload->'previous'->>'days')::int IS DISTINCT FROM 3
     OR (r.payload->'recent'->>'avg_kg')::numeric IS DISTINCT FROM 62.00
     OR (r.payload->'previous'->>'avg_kg')::numeric IS DISTINCT FROM 60.00
     OR (r.payload->>'delta_kg')::numeric IS DISTINCT FROM 2.00
     OR (r.payload->>'delta_pct')::numeric IS DISTINCT FROM 3.33
     OR r.payload->>'direction' IS DISTINCT FROM 'increase' THEN
    RAISE EXCEPTION 'FAIL: (a) 体重の窓の JST 境界が期待と異なる（期待 detected / high / 各3日 / 62.00 vs 60.00）: % / % / %',
      r.state, r.severity, r.payload;
  END IF;
  IF r.payload->'recent'->>'from' IS DISTINCT FROM '2026-08-13'
     OR r.payload->'recent'->>'to' IS DISTINCT FROM '2026-08-19'
     OR r.payload->'previous'->>'from' IS DISTINCT FROM '2026-08-06'
     OR r.payload->'previous'->>'to' IS DISTINCT FROM '2026-08-12'
     OR r.payload->'threshold' IS DISTINCT FROM '{"pct": 3.0, "kg": 2.0}'::jsonb
     OR (r.payload->>'v')::int IS DISTINCT FROM 1
     OR r.payload ? 'severity_reason' THEN
    RAISE EXCEPTION 'FAIL: (a) weight_change の payload の期間・閾値が期待と異なる: %', r.payload;
  END IF;

  -- 02 R_BND_NO: 最終到着 (D−3) 0:30 JST → (D−1) − R = 2 で no_data にならず、記録なしも 0日 → cleared
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000002' AND e.alert_type = 'record_gap';
  IF r.state IS DISTINCT FROM 'cleared' OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-17' THEN
    RAISE EXCEPTION 'FAIL: (a) 最終到着 (D−3) の JST 0:30 で検知している（UTC の日付で判定している疑い）: % / %',
      r.state, r.payload;
  END IF;

  -- 03 R_BND_YES: 最終到着 (D−4) 23:30 JST → no_data・N=3・medium（08-17〜08-19）
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000003' AND e.alert_type = 'record_gap';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload->>'variant' IS DISTINCT FROM 'no_data'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-17'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-19'
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-16'
     OR r.payload->>'last_record_on' IS DISTINCT FROM '2026-08-15'
     OR (r.payload->>'threshold_days')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (a) 最終到着 (D−4) の JST 23:30 で no_data N=3 にならない: % / % / %',
      r.state, r.severity, r.payload;
  END IF;
  RAISE NOTICE 'OK: (D−7) 0:30 は直近・(D−8) 23:30 は前・D 0:30 は窓の外。最終到着 (D−3) 0:30 は検知せず、(D−4) 23:30 は no_data N=3';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 体重の閾値・窓の日数・外れ値・登録日
-- -----------------------------------------------------------------------------
\echo '--- case b: 体重の閾値（2.9% / 1.9kg は不成立、3.0% / 2.0kg ちょうどで成立）・2日の窓・外れ値・登録日'

DO $$
DECLARE
  v_bad text;
  r     record;
BEGIN
  SELECT string_agg(format('%s: %s / %s（期待 %s / %s）%s', x.n, e.state, e.severity, x.exp_state, x.exp_severity, e.payload), E'\n')
    INTO v_bad
    FROM (VALUES
      ('04', 'unknown',  NULL),    -- 2.9% / 1.45kg
      ('05', 'unknown',  NULL),    -- 1.9kg / 2.375%
      ('06', 'detected', 'high'),  -- 3.0% ちょうど
      ('07', 'detected', 'high'),  -- 2.0kg ちょうど
      ('08', 'unknown',  NULL),    -- 直近の窓が2日
      ('09', 'cleared',  NULL),    -- 1日10件の外れ値は中央値で吸収
      ('10', 'cleared',  NULL),    -- ±15% 超の日と範囲外の値を除外
      ('11', 'detected', 'high')   -- 登録日より前の計測は使わない
    ) AS x(n, exp_state, exp_severity)
    LEFT JOIN pg_temp.eval_0820 e
      ON e.client_id = ('cccccccc-0914-0002-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'weight_change'
   WHERE (e.state, e.severity) IS DISTINCT FROM (x.exp_state, x.exp_severity);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (b) 体重の判定が期待と異なる:\n%', v_bad;
  END IF;

  -- 3.0% ちょうど・2.0kg ちょうどの値が payload に正しく残る
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000006' AND e.alert_type = 'weight_change';
  IF (r.payload->>'delta_pct')::numeric IS DISTINCT FROM 3.00 OR (r.payload->>'delta_kg')::numeric IS DISTINCT FROM 1.50 THEN
    RAISE EXCEPTION 'FAIL: (b) 3.0%% ちょうどの payload が期待と異なる: %', r.payload;
  END IF;
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000007' AND e.alert_type = 'weight_change';
  IF (r.payload->>'delta_kg')::numeric IS DISTINCT FROM 2.00 OR (r.payload->>'delta_pct')::numeric IS DISTINCT FROM 2.50 THEN
    RAISE EXCEPTION 'FAIL: (b) 2.0kg ちょうどの payload が期待と異なる: %', r.payload;
  END IF;

  -- 2日しかない窓は days に 2 と出る（評価しない理由が payload で分かる）
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000008' AND e.alert_type = 'weight_change';
  IF (r.payload->'recent'->>'days')::int IS DISTINCT FROM 2 OR (r.payload->'previous'->>'days')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION 'FAIL: (b) 2日の窓の days が期待と異なる: %', r.payload;
  END IF;

  -- 外れ値の日（08-19 の 70.0）を除いて直近の窓は3日
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000010' AND e.alert_type = 'weight_change';
  IF (r.payload->'recent'->>'days')::int IS DISTINCT FROM 3 OR (r.payload->'previous'->>'days')::int IS DISTINCT FROM 3
     OR (r.payload->>'delta_kg')::numeric IS DISTINCT FROM 0.00 THEN
    RAISE EXCEPTION 'FAIL: (b) 外れ値・範囲外の値の除外が期待と異なる: %', r.payload;
  END IF;

  -- 登録前の計測を使わないので、前の窓は登録日 08-08 から3日（payload の previous.from も登録日）
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000011' AND e.alert_type = 'weight_change';
  IF r.payload->'previous'->>'from' IS DISTINCT FROM '2026-08-08'
     OR (r.payload->'previous'->>'days')::int IS DISTINCT FROM 3
     OR (r.payload->'previous'->>'avg_kg')::numeric IS DISTINCT FROM 60.00 THEN
    RAISE EXCEPTION 'FAIL: (b) 登録日より前の計測を使っている疑い: %', r.payload;
  END IF;

  -- 締め時刻: 06:00 JST では 08-18 の計測がまだ届いていない → 直近の窓が2日で unknown。
  -- 08:00 JST（届いた後）にずらすと3日そろって detected
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 06:00+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000026' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'unknown' OR (r.payload->'recent'->>'days')::int IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'FAIL: (b) 締め時刻 06:00 JST で、後から届いた体重を窓に数えている疑い: % / %', r.state, r.payload;
  END IF;
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 08:00+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000026' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'detected' OR (r.payload->'recent'->>'days')::int IS DISTINCT FROM 3
     OR (r.payload->>'delta_kg')::numeric IS DISTINCT FROM 2.00 THEN
    RAISE EXCEPTION 'FAIL: (b) 締め時刻を 08:00 JST にずらしても届いた体重が窓に入らない: % / %', r.state, r.payload;
  END IF;

  RAISE NOTICE 'OK: 2.9%% / 1.9kg は unknown、3.0%% / 2.0kg ちょうどは detected。2日の窓は評価しない。10件の日の外れ値・±15%% 超の日・10kg は除外。登録前の計測・締め時刻より後に届いた計測は使わない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(c): diet の減少だけ medium
-- -----------------------------------------------------------------------------
\echo '--- case c: diet の減少は medium（severity_reason）、diet の増加と他の目的の減少は high'

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000012' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload->>'severity_reason' IS DISTINCT FROM 'diet_decrease'
     OR r.payload->>'direction' IS DISTINCT FROM 'decrease'
     OR (r.payload->>'delta_kg')::numeric IS DISTINCT FROM -2.00
     OR (r.payload->>'delta_pct')::numeric IS DISTINCT FROM -3.23 THEN
    RAISE EXCEPTION 'FAIL: (c) diet の減少が期待と異なる（期待 detected / medium / diet_decrease）: % / % / %',
      r.state, r.severity, r.payload;
  END IF;

  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000013' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'high'
     OR r.payload ? 'severity_reason' OR r.payload->>'direction' IS DISTINCT FROM 'increase' THEN
    RAISE EXCEPTION 'FAIL: (c) diet の増加が期待と異なる（期待 detected / high）: % / % / %', r.state, r.severity, r.payload;
  END IF;

  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000014' AND e.alert_type = 'weight_change';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'high' OR r.payload ? 'severity_reason' THEN
    RAISE EXCEPTION 'FAIL: (c) 他の目的の減少が期待と異なる（期待 detected / high）: % / % / %', r.state, r.severity, r.payload;
  END IF;
  RAISE NOTICE 'OK: diet の減少は medium（severity_reason = diet_decrease）、diet の増加・他の目的の減少は high';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 記録途絶
-- -----------------------------------------------------------------------------
\echo '--- case d: 途絶（登録翌日は検知しない / 登録3日で not_started / 15日超は対象外 / no_data / no_record / 登録日から数える / 締め時刻）'

DO $$
DECLARE
  v_bad text;
  r     record;
BEGIN
  SELECT string_agg(format('%s: %s / %s（期待 %s / %s / %s・%s〜%s）%s',
                           x.n, e.state, e.severity, x.exp_state, x.exp_severity, x.exp_variant,
                           x.exp_from, x.exp_to, e.payload), E'\n')
    INTO v_bad
    FROM (VALUES
      -- 登録翌日・既読だけ・記録なし → not_started N=1 で検知しない
      ('15', 'cleared',  NULL,     'not_started', '2026-08-19', '2026-08-19'),
      -- 登録翌日・登録前の計測が一括で届いた・既読 → 記録なしは登録日から数えて 0日（検知しない）
      ('16', 'cleared',  NULL,     'no_record',   '2026-08-19', '2026-08-18'),
      -- 登録から3日（D = J+3）→ not_started・N=3・medium
      ('17', 'detected', 'medium', 'not_started', '2026-08-17', '2026-08-19'),
      -- no_data 3日 → medium
      ('03', 'detected', 'medium', 'no_data',     '2026-08-17', '2026-08-19'),
      -- no_data 7日 → high
      ('19', 'detected', 'high',   'no_data',     '2026-08-13', '2026-08-19'),
      -- no_record（前日 08-19 に既読、最終記録 08-15）→ 08-16〜08-18 の3日（08-19 は既読の日なので数えない）
      ('20', 'detected', 'medium', 'no_record',   '2026-08-16', '2026-08-18'),
      -- 最後の記録（08-01）が登録日（08-14）より前でも、日数は登録日から数える → 5日
      ('21', 'detected', 'medium', 'no_record',   '2026-08-14', '2026-08-18')
    ) AS x(n, exp_state, exp_severity, exp_variant, exp_from, exp_to)
    LEFT JOIN pg_temp.eval_0820 e
      ON e.client_id = ('cccccccc-0914-0002-0000-0000000000' || x.n)::uuid
     AND e.alert_type = 'record_gap'
   WHERE (e.state, e.severity, e.payload->>'variant', e.payload->>'gap_from', e.payload->>'gap_to')
         IS DISTINCT FROM (x.exp_state, x.exp_severity, x.exp_variant, x.exp_from, x.exp_to);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION E'FAIL: (d) 途絶の判定が期待と異なる:\n%', v_bad;
  END IF;

  -- 登録15日超の未開始（18）は対象外なので評価の行が無い（本実行でも作らない）
  IF EXISTS (SELECT 1 FROM pg_temp.eval_0820 e WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000018') THEN
    RAISE EXCEPTION 'FAIL: (d) 登録15日超の未開始（18）が評価されている（対象外のはず）';
  END IF;

  -- not_started の payload: last_record_on は null、last_activity_on は登録日
  SELECT * INTO r FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000017' AND e.alert_type = 'record_gap';
  IF r.payload->'last_record_on' IS DISTINCT FROM 'null'::jsonb
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-17' THEN
    RAISE EXCEPTION 'FAIL: (d) not_started の payload が期待と異なる: %', r.payload;
  END IF;

  -- 締め時刻: 06:00 JST（計測 08-19 の体重がまだ届いていない）→ no_data N=4 で detected
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 06:00+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000022' AND e.alert_type = 'record_gap';
  IF r.state IS DISTINCT FROM 'detected' OR r.payload->>'variant' IS DISTINCT FROM 'no_data'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-16' OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-19' THEN
    RAISE EXCEPTION 'FAIL: (d) 締め時刻 06:00 JST で、後から届いた計測を数えている疑い: % / %', r.state, r.payload;
  END IF;
  -- 締め時刻を 08:00 JST（届いた後）にずらすと cleared
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 08:00+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000022' AND e.alert_type = 'record_gap';
  IF r.state IS DISTINCT FROM 'cleared' THEN
    RAISE EXCEPTION 'FAIL: (d) 締め時刻を 08:00 JST にずらしても cleared にならない: % / %', r.state, r.payload;
  END IF;

  RAISE NOTICE 'OK: 登録翌日は検知しない / 登録3日で not_started N=3 medium / 15日超は対象外 / no_data 3日 medium・7日 high / no_record / 登録日から数える / 締め時刻より後の到着は数えない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d-healthkit): HealthKit の体重（計測日の 23:59 JST で入る）だけを連携している顧客
--   27 G_HK は D（08-20）に計測し、アプリが D の 05:00 JST に同期した。06:00 の本実行（締め時刻 D 06:00）では、
--   届いた D の体重の計測時刻（D 23:59）は締め時刻より後だが、R は到着時刻だけで決まるので R = D。
--   → no_data（記録・同期なし）にしない。最終記録 08-15 の翌日から D−1 までは記録が無いので no_record 4日。
--   計測時刻でも R を絞ると R = 08-15 になり、同期済みなのに no_data 08-16〜08-19 になる
-- -----------------------------------------------------------------------------
\echo '--- case d-healthkit: HealthKit の体重（計測日の 23:59 JST）が D の 05:00 に届いた顧客は、06:00 の評価で no_data にならないこと'

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 06:00+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000027' AND e.alert_type = 'record_gap';
  IF r.client_id IS NULL OR r.payload->>'variant' IS NOT DISTINCT FROM 'no_data' THEN
    RAISE EXCEPTION 'FAIL: (d-healthkit) 締め時刻 06:00 JST の前に届いた HealthKit の体重を数えず no_data にしている（計測時刻でも R を絞っている疑い）: % / %',
      r.state, r.payload;
  END IF;
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload->>'variant' IS DISTINCT FROM 'no_record'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-16'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-19'
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-20'
     OR r.payload->>'last_record_on' IS DISTINCT FROM '2026-08-15' THEN
    RAISE EXCEPTION 'FAIL: (d-healthkit) 締め時刻 06:00 JST の評価が期待（no_record 08-16〜08-19 medium・R 08-20・L 08-15）と異なる: % / % / %',
      r.state, r.severity, r.payload;
  END IF;

  -- 締め時刻を D の 04:59 JST（D の体重が届く前）にずらすと、まだ届いていないので no_data 08-16〜08-19（R = 08-15）
  SELECT * INTO r FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 04:59+09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000027' AND e.alert_type = 'record_gap';
  IF r.state IS DISTINCT FROM 'detected' OR r.severity IS DISTINCT FROM 'medium'
     OR r.payload->>'variant' IS DISTINCT FROM 'no_data'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-16'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-19'
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-15' THEN
    RAISE EXCEPTION 'FAIL: (d-healthkit) 締め時刻 04:59 JST（D の体重が届く前）の評価が期待（no_data 08-16〜08-19 medium・R 08-15）と異なる: % / % / %',
      r.state, r.severity, r.payload;
  END IF;
  RAISE NOTICE 'OK: D の 05:00 に届いた D 23:59 JST の体重で R = D になり、06:00 の評価は no_data ではなく no_record（08-16〜08-19）。届く前の 04:59 では no_data';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(e): 対象外は評価しない
-- -----------------------------------------------------------------------------
\echo '--- case e: auth が無い / 自己登録 / 最終到着が D−15 の顧客は評価しないこと'

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM pg_temp.eval_0820 e
   WHERE e.client_id IN ('cccccccc-0914-0002-0000-000000000023',
                         'aaaaaaaa-0914-0002-0000-00000000000d',
                         'cccccccc-0914-0002-0000-000000000025');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (e) 対象外の顧客（auth 無し / 自己登録 / D−15）が % 行評価されている', cnt;
  END IF;

  -- 監視対象の顧客は2行（weight_change と record_gap）ずつ返る
  SELECT count(*) INTO cnt FROM pg_temp.eval_0820 e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000001';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (e) 監視対象の顧客の評価が % 行（期待 2 行 = 種別ごと）', cnt;
  END IF;
  RAISE NOTICE 'OK: 対象外（auth 無し / 自己登録 / 最終到着 D−15）は評価せず、監視対象は種別ごとに2行';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(i): evaluate は READ ONLY の中でも実行でき、行数を変えない
--   セーブポイントの中だけ読み取り専用にする（ROLLBACK TO で読み書きに戻る）。
--   対比として、本実行は READ ONLY では失敗することも確かめる
-- -----------------------------------------------------------------------------
\echo '--- case i: evaluate が READ ONLY で実行でき、alerts の行数を変えないこと'

SAVEPOINT read_only_eval;
SET LOCAL transaction_read_only = on;

DO $$
DECLARE
  v_before bigint;
  v_after  bigint;
  n        int;
BEGIN
  SELECT count(*) INTO v_before FROM public.alerts;
  SELECT count(*) INTO n FROM public.evaluate_client_alerts('2026-08-20');
  SELECT count(*) INTO n FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 06:00+09');
  SELECT count(*) INTO v_after FROM public.alerts;
  IF n = 0 THEN
    RAISE EXCEPTION 'FAIL: (i) READ ONLY の evaluate が 0 行（試験データが評価されていない）';
  END IF;
  IF v_before <> v_after THEN
    RAISE EXCEPTION 'FAIL: (i) evaluate の前後で alerts が % → % 行に変わった', v_before, v_after;
  END IF;

  BEGIN
    PERFORM public.run_client_alert_detection('2026-08-20');
    RAISE EXCEPTION 'FAIL: (i) READ ONLY の中で本実行が成功してしまった';
  EXCEPTION
    WHEN read_only_sql_transaction THEN NULL;
  END;
  RAISE NOTICE 'OK: READ ONLY でも evaluate は実行でき（% 行）、alerts は % 行のまま。本実行は READ ONLY では失敗する', n, v_after;
END $$;

ROLLBACK TO SAVEPOINT read_only_eval;

-- 第1部の顧客を片付ける（CASCADE で記録・alerts も消える。messages は FK が無いので明示的に）
DELETE FROM public.messages
 WHERE sender_id::text LIKE 'cccccccc-0914-0002-%' OR receiver_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.clients
 WHERE client_id::text LIKE 'cccccccc-0914-0002-%'
    OR client_id = 'aaaaaaaa-0914-0002-0000-00000000000d';

-- =============================================================================
-- 第2部-1: 状態遷移（ケース f・g）
--   41 F1 : 状態遷移の1本の流れ（登録 08-01 12:00 JST・記録なしから始める）
--   42 F2 : open のまま medium → high（登録 08-01・記録なし）
--   43 G1 : 担当替え（T → T2）
--   44 G2 : auth.users の削除 → ineligible
--   45 G3 : 自己登録化（trainers に行を作り、担当を自分にする）→ ineligible
--   本実行: 08-04 → 08-04（再実行）→ 08-05 → 08-08 → 08-09 → 08-13 → 08-14 → 08-18
--   （締め時刻はそれぞれ D+1 の JST 0:00。到着はその間に収まるように書く）
-- =============================================================================
\echo '--- 第2部-1 setup: 状態遷移用の顧客 F1・F2・G1・G2・G3'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['41','42','43','44','45']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, created_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '検知テスト顧客' || n,
       'aaaaaaaa-0914-0002-0000-00000000000a', '2026-08-01 12:00+09'
  FROM unnest(ARRAY['41','42','43','44','45']) AS n;

-- ---- 本実行 1: D = 08-04（登録から3日）→ 5人とも not_started N=3 medium で新規 ----
\echo '--- case f-1: 作成（08-04: not_started N=3 medium・open・first = surfaced = last = D）'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-08-04');
  PERFORM set_config('det_test.run1_opened', v_res->'stats'->>'opened', true);

  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id::text LIKE 'cccccccc-0914-0002-0000-00000000004%' AND a.resolved_at IS NULL;
  IF cnt <> 5 THEN
    RAISE EXCEPTION 'FAIL: (f-1) 08-04 の本実行で生きている行が % 件（期待 5 件）', cnt;
  END IF;

  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000041' AND a.resolved_at IS NULL;
  IF r.alert_type <> 'record_gap' OR r.status <> 'open' OR r.severity <> 'medium'
     OR r.trainer_id <> 'aaaaaaaa-0914-0002-0000-00000000000a'
     OR (r.first_detected_on, r.surfaced_on, r.last_detected_on)
        IS DISTINCT FROM ('2026-08-04'::date, '2026-08-04'::date, '2026-08-04'::date)
     OR r.reopened_count <> 0 OR r.acknowledged_at IS NOT NULL
     OR r.payload->>'variant' IS DISTINCT FROM 'not_started'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-01'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-03'
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-01' THEN
    RAISE EXCEPTION 'FAIL: (f-1) F1 の新規行が期待と異なる: %', row_to_json(r);
  END IF;
  PERFORM set_config('det_test.f1_id', r.id::text, true);

  IF (v_res->'stats'->>'opened')::int < 5
     OR (v_res->'stats'->'detected'->'record_gap'->>'not_started')::int < 5 THEN
    RAISE EXCEPTION 'FAIL: (f-1) stats の opened / not_started が 5 未満: %', v_res->'stats';
  END IF;
  IF v_res->>'target_date' IS DISTINCT FROM '2026-08-04'
     OR (v_res->>'as_of')::timestamptz IS DISTINCT FROM '2026-08-05 00:00+09'::timestamptz THEN
    RAISE EXCEPTION 'FAIL: (f-1) 戻り値の target_date / as_of が期待と異なる: %', v_res;
  END IF;
  RAISE NOTICE 'OK: 08-04 に5人とも not_started N=3 medium で open 作成（as_of = D+1 の JST 0:00）';
END $$;

-- ---- 本実行 2: 同じ対象日の再実行。後から入った既読（08-04 20:00）が payload に反映される ----
\echo '--- case f-2: 同じ日の再実行で行数は変わらず、payload が更新されること（新規 0・更新 n）'

SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000041', 'trainer', 'client',
   '検知テスト: 記録をお願いします', '2026-08-02 10:00+09', '2026-08-04 20:00+09');
SET LOCAL session_replication_role = origin;

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-08-04');

  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id::text LIKE 'cccccccc-0914-0002-0000-00000000004%';
  IF cnt <> 5 THEN
    RAISE EXCEPTION 'FAIL: (f-2) 再実行で試験用顧客の行数が % 件に変わった（期待 5 件のまま）', cnt;
  END IF;

  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000041' AND a.resolved_at IS NULL;
  IF r.id <> current_setting('det_test.f1_id')::uuid
     OR r.payload->>'last_activity_on' IS DISTINCT FROM '2026-08-04'
     OR r.status <> 'open' OR r.surfaced_on <> '2026-08-04' THEN
    RAISE EXCEPTION 'FAIL: (f-2) 再実行で F1 の payload が更新されていない / 行が変わった: %', row_to_json(r);
  END IF;

  IF (v_res->'stats'->>'opened')::int <> 0
     OR (v_res->'stats'->>'updated')::int <> current_setting('det_test.run1_opened')::int THEN
    RAISE EXCEPTION 'FAIL: (f-2) 再実行の stats が収束していない（期待 opened 0 / updated %）: %',
      current_setting('det_test.run1_opened'), v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 同じ対象日の再実行は新規 0・更新 %、F1 は同じ行のまま payload（last_activity_on）が更新', v_res->'stats'->>'updated';
END $$;

-- ---- トレーナーが F1 を「対応済み」にする（API Route の条件付き UPDATE と同じ形）----
DO $$
DECLARE n int;
BEGIN
  UPDATE public.alerts
     SET status = 'acknowledged', acknowledged_at = now()
   WHERE id = current_setting('det_test.f1_id')::uuid AND status = 'open';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: F1 を対応済みにできない（% 行）', n;
  END IF;
END $$;

-- ---- 本実行 3 の前: G1 を T2 に担当替え、G2 の auth.users を削除、G3 を自己登録化 ----
UPDATE public.clients SET trainer_id = 'aaaaaaaa-0914-0002-0000-00000000000b'
 WHERE client_id = 'cccccccc-0914-0002-0000-000000000043';
DELETE FROM auth.users WHERE id = 'cccccccc-0914-0002-0000-000000000044';
INSERT INTO public.trainers (id, name, email)
VALUES ('cccccccc-0914-0002-0000-000000000045', '検知テスト 自己登録化G3', 'detection-test-c45@example.com');
UPDATE public.clients SET trainer_id = client_id
 WHERE client_id = 'cccccccc-0914-0002-0000-000000000045';

-- ---- 本実行 3: D = 08-05 ----
\echo '--- case f-3 / g: 対応済みは条件が続いても acknowledged のまま。担当替えは reassigned、auth 削除・自己登録化は ineligible'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-08-05');

  -- F1: N=4 medium のまま → acknowledged のまま、last_detected_on だけ進む
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.f1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.severity <> 'medium' OR r.last_detected_on <> '2026-08-05'
     OR r.surfaced_on <> '2026-08-04' OR r.acknowledged_at IS NULL
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-04' THEN
    RAISE EXCEPTION 'FAIL: (f-3) 対応済みの F1 が期待と異なる（acknowledged のまま・last_detected_on = 08-05）: %', row_to_json(r);
  END IF;

  -- G1: T の行は reassigned で閉じ、T2 の新しい行が同じ実行の中でできる
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000043'
     AND a.trainer_id = 'aaaaaaaa-0914-0002-0000-00000000000a';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'reassigned' THEN
    RAISE EXCEPTION 'FAIL: (g) 担当替え前の G1 の行が reassigned で閉じていない: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000043' AND a.resolved_at IS NULL;
  IF r.trainer_id IS DISTINCT FROM 'aaaaaaaa-0914-0002-0000-00000000000b'::uuid
     OR r.status <> 'open' OR r.first_detected_on <> '2026-08-05' OR r.severity <> 'medium' THEN
    RAISE EXCEPTION 'FAIL: (g) 新しい担当 T2 の G1 の行ができていない: %', row_to_json(r);
  END IF;

  -- G2（auth 削除）・G3（自己登録化）: ineligible で閉じ、生きている行は無い
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id IN ('cccccccc-0914-0002-0000-000000000044', 'cccccccc-0914-0002-0000-000000000045')
     AND a.status = 'resolved' AND a.resolved_reason = 'ineligible';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (g) auth 削除・自己登録化の行が ineligible で閉じていない（% 件）', cnt;
  END IF;
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id IN ('cccccccc-0914-0002-0000-000000000044', 'cccccccc-0914-0002-0000-000000000045')
     AND a.resolved_at IS NULL;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (g) auth 削除・自己登録化の顧客に生きている行が % 件ある', cnt;
  END IF;

  IF (v_res->'stats'->'resolved'->>'reassigned')::int < 1
     OR (v_res->'stats'->'resolved'->>'ineligible')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (g) stats の resolved.reassigned / ineligible が期待より少ない: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: 対応済みの F1 は acknowledged のまま。G1 は reassigned → T2 の行を新規、G2・G3 は ineligible';
END $$;

-- ---- 本実行 4: D = 08-08（登録から7日）→ high に昇格 ----
\echo '--- case f-4: 7日で high に上がり、対応済みの F1 は1回だけ再浮上、open の F2 は surfaced_on = D'

DO $$
DECLARE
  v_res jsonb;
  r     record;
BEGIN
  v_res := public.run_client_alert_detection('2026-08-08');

  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.f1_id')::uuid;
  IF r.status <> 'open' OR r.severity <> 'high' OR r.acknowledged_at IS NOT NULL
     OR r.reopened_count <> 1 OR r.surfaced_on <> '2026-08-08' OR r.first_detected_on <> '2026-08-04' THEN
    RAISE EXCEPTION 'FAIL: (f-4) 対応済みの F1 が high への昇格で再浮上していない: %', row_to_json(r);
  END IF;

  -- F2: open のまま medium → high → surfaced_on = D（再浮上ではないので reopened_count は 0）
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000042' AND a.resolved_at IS NULL;
  IF r.status <> 'open' OR r.severity <> 'high' OR r.surfaced_on <> '2026-08-08'
     OR r.reopened_count <> 0 OR r.first_detected_on <> '2026-08-04' THEN
    RAISE EXCEPTION 'FAIL: (f-4) open のまま昇格した F2 の surfaced_on が D になっていない: %', row_to_json(r);
  END IF;

  IF (v_res->'stats'->>'reopened')::int < 1 OR (v_res->'stats'->>'escalated')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (f-4) stats の reopened / escalated が期待より少ない: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: F1 は high で再浮上（open・reopened_count 1・surfaced_on 08-08）、F2 は open のまま surfaced_on = 08-08';
END $$;

-- ---- F1 をもう一度「対応済み」にする ----
DO $$
DECLARE n int;
BEGIN
  UPDATE public.alerts
     SET status = 'acknowledged', acknowledged_at = now()
   WHERE id = current_setting('det_test.f1_id')::uuid AND status = 'open';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: F1 をもう一度対応済みにできない（% 行）', n;
  END IF;
END $$;

-- ---- 本実行 5 の前: F1 のアプリが同期し、08-04 の体重が 08-09 08:00 に届いた。既読も 08-09 ----
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at) VALUES
  ('cccccccc-0914-0002-0000-000000000041', 60.0, '2026-08-04 08:00+09', 'healthkit',
   '2026-08-09 08:00+09', '2026-08-09 08:00+09');
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000041', 'trainer', 'client',
   '検知テスト: 様子はいかがですか', '2026-08-09 08:30+09', '2026-08-09 09:00+09');
SET LOCAL session_replication_role = origin;

-- ---- 本実行 5: D = 08-09 → no_record 08-05〜08-08（4日）medium に下がる ----
\echo '--- case f-5: 変種が変わり重大度が下がっても同じ行のまま（acknowledged のまま）'

DO $$
DECLARE r record;
BEGIN
  PERFORM public.run_client_alert_detection('2026-08-09');

  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.f1_id')::uuid;
  IF r.resolved_at IS NOT NULL OR r.status <> 'acknowledged' OR r.severity <> 'medium'
     OR r.reopened_count <> 1 OR r.surfaced_on <> '2026-08-08'
     OR r.payload->>'variant' IS DISTINCT FROM 'no_record'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-05'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-08' THEN
    RAISE EXCEPTION 'FAIL: (f-5) 変種が no_record に変わった F1 が期待と異なる（同じ行・acknowledged・medium）: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: F1 は同じ行のまま no_record（08-05〜08-08）medium に変わり、acknowledged のまま';
END $$;

-- ---- 本実行 6 の前: 08-12 に既読（記録は無いまま）----
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000041', 'trainer', 'client',
   '検知テスト: 今週の予定', '2026-08-12 20:00+09', '2026-08-12 21:00+09');
SET LOCAL session_replication_role = origin;

-- ---- 本実行 6: D = 08-13 → no_record 08-05〜08-11（7日）high に上がる（2回目の昇格）----
\echo '--- case f-6: 2回目の昇格では再浮上しないこと（acknowledged・reopened_count 1 のまま）'

DO $$
DECLARE r record;
BEGIN
  PERFORM public.run_client_alert_detection('2026-08-13');

  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.f1_id')::uuid;
  IF r.status <> 'acknowledged' OR r.severity <> 'high' OR r.reopened_count <> 1
     OR r.surfaced_on <> '2026-08-08' OR r.last_detected_on <> '2026-08-13'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-11' THEN
    RAISE EXCEPTION 'FAIL: (f-6) 2回目の昇格で F1 が再浮上した / 値が更新されていない: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: 2回目の昇格（medium → high）では再浮上せず、acknowledged のまま severity だけ high';
END $$;

-- ---- 本実行 7 の前: 08-13 の体重が 08-14 07:05 に届く ----
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at) VALUES
  ('cccccccc-0914-0002-0000-000000000041', 60.0, '2026-08-13 07:00+09', 'healthkit',
   '2026-08-14 07:05+09', '2026-08-14 07:05+09');

-- ---- 本実行 7: D = 08-14 → 記録が戻ったので cleared ----
\echo '--- case f-7: 記録が戻ると resolved（cleared）になること'

DO $$
DECLARE r record;
BEGIN
  PERFORM public.run_client_alert_detection('2026-08-14');

  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.f1_id')::uuid;
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'cleared' OR r.resolved_at IS NULL THEN
    RAISE EXCEPTION 'FAIL: (f-7) 記録が戻った F1 が resolved（cleared）になっていない: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: F1 は resolved（cleared）';
END $$;

-- ---- 本実行 8 の前: 08-17 に既読（記録は 08-13 が最後）----
SET LOCAL session_replication_role = replica;
INSERT INTO public.messages (sender_id, receiver_id, sender_type, receiver_type, content, created_at, read_at) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000041', 'trainer', 'client',
   '検知テスト: 最近どうですか', '2026-08-17 20:00+09', '2026-08-17 21:00+09');
SET LOCAL session_replication_role = origin;

-- ---- 本実行 8: D = 08-18 → 再発（no_record 08-14〜08-16）で新しい行 ----
\echo '--- case f-8: 再発すると新しい行を作ること（resolved は終端）/ 登録15日超の未開始になると生きている record_gap は expired'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  v_res := public.run_client_alert_detection('2026-08-18');

  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000041' AND a.resolved_at IS NULL;
  IF r.id IS NULL OR r.id = current_setting('det_test.f1_id')::uuid
     OR r.status <> 'open' OR r.severity <> 'medium' OR r.reopened_count <> 0
     OR r.first_detected_on <> '2026-08-18' OR r.surfaced_on <> '2026-08-18'
     OR r.payload->>'variant' IS DISTINCT FROM 'no_record'
     OR r.payload->>'gap_from' IS DISTINCT FROM '2026-08-14'
     OR r.payload->>'gap_to' IS DISTINCT FROM '2026-08-16' THEN
    RAISE EXCEPTION 'FAIL: (f-8) 再発で新しい行ができていない: %', row_to_json(r);
  END IF;

  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.id = current_setting('det_test.f1_id')::uuid
     AND a.status = 'resolved' AND a.resolved_reason = 'cleared';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (f-8) 前の発生の行が resolved（cleared）のまま残っていない';
  END IF;

  -- F2: 登録から17日（D − J > 14）の未開始は監視対象外（not_started）。生きている record_gap があっても
  -- 監視は延ばさず、expired で閉じる（オーナー決定 (1)。未開始は登録から最大 14 日で打ち切る）。
  -- 最後に確かめたのは 08-14 の本実行（登録13日目・N = 13）のまま
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000042' AND a.resolved_at IS NULL;
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (f-8) 登録17日の未開始 F2 に生きている行が % 件ある（監視が延びている）', cnt;
  END IF;
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000042';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' OR r.resolved_at IS NULL
     OR r.last_detected_on <> '2026-08-14'
     OR r.payload->>'variant' IS DISTINCT FROM 'not_started'
     OR ((r.payload->>'gap_to')::date - (r.payload->>'gap_from')::date + 1) <> 13 THEN
    RAISE EXCEPTION 'FAIL: (f-8) 登録17日の未開始 F2 の行が expired で閉じていない: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->'resolved'->>'expired')::int < 1
     OR (v_res->'stats'->'excluded'->>'not_started')::int < 1 THEN
    RAISE EXCEPTION 'FAIL: (f-8) stats の resolved.expired / excluded.not_started が期待より少ない: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: F1 は再発で新しい行（open・first_detected_on 08-18）、前の行は resolved のまま。登録17日の未開始 F2 は expired で閉じ、人数（not_started）に回る';
END $$;

-- 第2部-1 の片付け
DELETE FROM public.messages
 WHERE sender_id::text LIKE 'cccccccc-0914-0002-%' OR receiver_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.trainers WHERE id = 'cccccccc-0914-0002-0000-000000000045';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-2: ヒステリシス（ケース b'）
--   51 W_HYST: 登録 07-09。前の窓の 07-27 / 07-29 / 07-31 は 60.0、直近の 08-03 / 08-05 / 08-07 は 61.86、
--   08-08 / 08-09 は 60.66。どの対象日でも前の窓は 07-27〜07-31 の3日（平均 60.0）で、直近の平均は
--     D = 08-08: 61.86（+3.1%）→ detected
--     D = 08-09: 61.56（+2.6%）→ unknown（解消値 2.4% 以上なので状態を変えない）
--     D = 08-10: 61.38（+2.3%・1.38kg）→ cleared
-- =============================================================================
\echo '--- 第2部-2 setup: ヒステリシス用の顧客 W_HYST'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
) VALUES
  ('cccccccc-0914-0002-0000-000000000051', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'detection-test-c51@example.com', 'x',
   now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', '');

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('cccccccc-0914-0002-0000-000000000051', '検知テスト顧客51',
   'aaaaaaaa-0914-0002-0000-00000000000a', '2026-07-09 12:00+09');

INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT 'cccccccc-0914-0002-0000-000000000051', v.w, v.at::timestamptz, 'healthkit',
       v.at::timestamptz + interval '5 minutes', v.at::timestamptz + interval '5 minutes'
  FROM (VALUES
    ('2026-07-27 08:00+09', 60.0), ('2026-07-29 08:00+09', 60.0), ('2026-07-31 08:00+09', 60.0),
    ('2026-08-03 08:00+09', 61.86), ('2026-08-05 08:00+09', 61.86), ('2026-08-07 08:00+09', 61.86),
    ('2026-08-08 08:00+09', 60.66), ('2026-08-09 08:00+09', 60.66)
  ) AS v(at, w);

\echo '--- case b-hysteresis: 3.1% で成立 → 2.6% では継続 → 2.3% で解消'

DO $$
DECLARE
  r       record;
  v_state text;
BEGIN
  PERFORM public.run_client_alert_detection('2026-08-08');
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000051' AND a.alert_type = 'weight_change';
  IF r.id IS NULL OR r.status <> 'open' OR (r.payload->>'delta_pct')::numeric IS DISTINCT FROM 3.10 THEN
    RAISE EXCEPTION 'FAIL: (b) 3.1%% で weight_change が成立していない: %', row_to_json(r);
  END IF;
  PERFORM set_config('det_test.hyst_id', r.id::text, true);

  -- 2.6%: 評価はできるが成立値と解消値の間 → unknown（状態を変えない）
  SELECT e.state INTO v_state FROM public.evaluate_client_alerts('2026-08-09') e
   WHERE e.client_id = 'cccccccc-0914-0002-0000-000000000051' AND e.alert_type = 'weight_change';
  IF v_state IS DISTINCT FROM 'unknown' THEN
    RAISE EXCEPTION 'FAIL: (b) 2.6%% の日の評価が %（期待 unknown）', v_state;
  END IF;
  PERFORM public.run_client_alert_detection('2026-08-09');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.hyst_id')::uuid;
  IF r.resolved_at IS NOT NULL OR r.last_detected_on <> '2026-08-08'
     OR (r.payload->>'delta_pct')::numeric IS DISTINCT FROM 3.10 THEN
    RAISE EXCEPTION 'FAIL: (b) 2.6%% の日にアラートが変わった（ヒステリシスが効いていない）: %', row_to_json(r);
  END IF;

  -- 2.3%（1.38kg）: 両方が成立値の8割未満 → cleared
  PERFORM public.run_client_alert_detection('2026-08-10');
  SELECT * INTO r FROM public.alerts a WHERE a.id = current_setting('det_test.hyst_id')::uuid;
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'cleared' THEN
    RAISE EXCEPTION 'FAIL: (b) 2.3%% の日に解消していない: %', row_to_json(r);
  END IF;
  RAISE NOTICE 'OK: 3.1%% で open → 2.6%% では変わらず（last_detected_on 08-08 のまま）→ 2.3%% で resolved（cleared）';
END $$;

-- 第2部-2 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-3: 期限切れ（ケース b'）
--   61 / 62 / 63: 登録 06-01、最終到着 07-01（D = 08-20 では inactive = 評価されない）
--   61: 生きている weight_change、last_detected_on = 08-06（= D−14）→ expired
--   62: 生きている weight_change、last_detected_on = 08-07（= D−13）→ 残る（weight_change は再確認の日数で切る）
--   63: 生きている record_gap、last_detected_on = 07-05 → 顧客が inactive なので expired
--       （監視を延ばさない。記録・同期なしは最終到着から最大 13 日で打ち切る。オーナー決定 (1)）
-- =============================================================================
\echo '--- 第2部-3 setup: 期限切れ用の顧客 61・62・63'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['61','62','63']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, created_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '検知テスト顧客' || n,
       'aaaaaaaa-0914-0002-0000-00000000000a', '2026-06-01 12:00+09'
  FROM unnest(ARRAY['61','62','63']) AS n;

INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, 60.0, '2026-07-01 08:00+09', 'manual',
       '2026-07-01 08:05+09', '2026-07-01 08:05+09'
  FROM unnest(ARRAY['61','62','63']) AS n;

INSERT INTO public.alerts (
  trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, acknowledged_at
) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000061',
   'weight_change', 'high', 'open', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-06', NULL),
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000062',
   'weight_change', 'high', 'acknowledged', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-07', now()),
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000063',
   'record_gap', 'high', 'open', '{"v":1}', '2026-07-05', '2026-07-05', '2026-07-05', NULL);

\echo '--- case b-expiry: 14日再確認されない weight_change は expired（評価されない顧客にも掛かる）/ inactive の record_gap も expired'

DO $$
DECLARE
  v_res jsonb;
  r     record;
BEGIN
  -- 前提: 61 / 62 は評価されない（inactive）
  IF EXISTS (SELECT 1 FROM public.evaluate_client_alerts('2026-08-20') e
              WHERE e.client_id IN ('cccccccc-0914-0002-0000-000000000061',
                                    'cccccccc-0914-0002-0000-000000000062')) THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — 期限切れ用の顧客 61 / 62 が評価されている';
  END IF;

  v_res := public.run_client_alert_detection('2026-08-20');

  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000061';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'FAIL: (b) last_detected_on = D−14 の weight_change が expired になっていない: %', row_to_json(r);
  END IF;
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000062';
  IF r.resolved_at IS NOT NULL OR r.status <> 'acknowledged' THEN
    RAISE EXCEPTION 'FAIL: (b) last_detected_on = D−13 の weight_change が閉じられた: %', row_to_json(r);
  END IF;
  -- record_gap: 顧客が inactive（最終到着 07-01 < D−14）なので、生きている行を理由に監視を延ばさず expired。
  -- 評価されないので値は更新されない（last_detected_on は 07-05 のまま）
  SELECT * INTO r FROM public.alerts a WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000063';
  IF r.status <> 'resolved' OR r.resolved_reason IS DISTINCT FROM 'expired'
     OR r.last_detected_on <> '2026-07-05' THEN
    RAISE EXCEPTION 'FAIL: (b) inactive の顧客の record_gap が expired で閉じていない（監視が延びている疑い）: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->'resolved'->>'expired')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (b) stats の resolved.expired が 2 未満（61 と 63）: %', v_res->'stats';
  END IF;
  RAISE NOTICE 'OK: D−14 の weight_change は expired、D−13 は残る。inactive の顧客の record_gap は expired';
END $$;

-- 第2部-3 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-4: ガード・実行記録・部分ユニーク（ケース h・j・k）
--   71: 登録 08-17・何もなし（D = 08-20 で not_started N=3）
--   72: diet・前の窓 62.0 / 直近の窓 60.0（D = 08-20 で diet の減少 = severity_lowered）
--   73: unique_violation の確認用
-- =============================================================================
\echo '--- 第2部-4 setup: ガード・実行記録・部分ユニーク用の顧客 71・72・73'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['71','72','73']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, purpose, created_at) VALUES
  ('cccccccc-0914-0002-0000-000000000071', '検知テスト顧客71', 'aaaaaaaa-0914-0002-0000-00000000000a',
   'health_improvement', '2026-08-17 12:00+09'),
  ('cccccccc-0914-0002-0000-000000000072', '検知テスト顧客72', 'aaaaaaaa-0914-0002-0000-00000000000a',
   'diet', '2026-07-01 12:00+09'),
  ('cccccccc-0914-0002-0000-000000000073', '検知テスト顧客73', 'aaaaaaaa-0914-0002-0000-00000000000a',
   'health_improvement', '2026-07-01 12:00+09');

INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at)
SELECT 'cccccccc-0914-0002-0000-000000000072',
       CASE WHEN d.at < '2026-08-13' THEN 62.0 ELSE 60.0 END,
       d.at::timestamptz, 'healthkit', d.at::timestamptz + interval '5 minutes', d.at::timestamptz + interval '5 minutes'
  FROM (VALUES ('2026-08-07 08:00+09'), ('2026-08-09 08:00+09'), ('2026-08-11 08:00+09'),
               ('2026-08-14 08:00+09'), ('2026-08-16 08:00+09'), ('2026-08-18 08:00+09')) AS d(at);

\echo '--- case h: ガード（対象日が NULL / 未来 / 最後の本実行より前は例外、同じ対象日は許す）と evaluate の締め時刻の範囲'

DO $$
DECLARE
  v_res jsonb;
  cnt   int;
BEGIN
  BEGIN
    PERFORM public.run_client_alert_detection(NULL);
    RAISE EXCEPTION 'FAIL: (h) 対象日 NULL の本実行が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      IF SQLERRM NOT LIKE '%NULL%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date + 1);
    RAISE EXCEPTION 'FAIL: (h) 未来（JST の明日）の本実行が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      IF SQLERRM NOT LIKE '%未来%' THEN RAISE; END IF;
  END;

  -- 本実行 1 回目（08-20）→ 成功し、alert_detection_runs が 1 行
  v_res := public.run_client_alert_detection('2026-08-20');
  SELECT count(*) INTO cnt FROM public.alert_detection_runs;
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (j) 本実行1回で alert_detection_runs が % 行（期待 1 行）', cnt;
  END IF;
  PERFORM set_config('det_test.run_0820', v_res::text, true);

  -- 最後の本実行（08-20）より前の対象日は例外
  BEGIN
    PERFORM public.run_client_alert_detection('2026-08-19');
    RAISE EXCEPTION 'FAIL: (h) 最後の本実行より前（08-19）の本実行が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN
      IF SQLERRM NOT LIKE '%最後に成功した本実行%' THEN RAISE; END IF;
  END;

  -- 同じ対象日の再実行は許す（2行目が入る）
  PERFORM public.run_client_alert_detection('2026-08-20');
  SELECT count(*) INTO cnt FROM public.alert_detection_runs;
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (h) 同じ対象日の再実行の後、alert_detection_runs が % 行（期待 2 行）', cnt;
  END IF;

  -- evaluate: 締め時刻が D の JST 0:00 より前 / now() より後、対象日が NULL / 未来は例外
  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts('2026-08-20', '2026-08-19 23:59:59+09');
    RAISE EXCEPTION 'FAIL: (h) 締め時刻が D の JST 0:00 より前の evaluate が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts('2026-08-20', now() + interval '1 minute');
    RAISE EXCEPTION 'FAIL: (h) 締め時刻が now() より後の evaluate が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts(NULL);
    RAISE EXCEPTION 'FAIL: (h) 対象日 NULL の evaluate が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts((now() AT TIME ZONE 'Asia/Tokyo')::date + 1);
    RAISE EXCEPTION 'FAIL: (h) 未来の対象日の evaluate が成功してしまった';
  EXCEPTION
    WHEN invalid_parameter_value THEN NULL;
  END;
  -- 境界: 締め時刻 = D の JST 0:00 ちょうどは許す
  PERFORM 1 FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 00:00+09');

  RAISE NOTICE 'OK: 本実行は NULL / 未来 / 最後の本実行より前で例外、同じ対象日は再実行できる。evaluate は締め時刻の範囲外・NULL・未来で例外';
END $$;

\echo '--- case j: 本実行の記録（1回で1行、stats は件数だけで client_id を含まない）'

DO $$
DECLARE
  v_res   jsonb := current_setting('det_test.run_0820')::jsonb;
  v_run   record;
  v_stats jsonb;
BEGIN
  SELECT r.* INTO v_run FROM public.alert_detection_runs r ORDER BY r.finished_at ASC LIMIT 1;
  v_stats := v_run.stats;

  IF v_stats IS DISTINCT FROM v_res->'stats' THEN
    RAISE EXCEPTION 'FAIL: (j) 記録された stats と戻り値の stats が異なる: % / %', v_stats, v_res->'stats';
  END IF;
  IF v_run.target_date <> '2026-08-20' OR v_run.as_of <> '2026-08-21 00:00+09'::timestamptz
     OR v_run.started_at > v_run.finished_at THEN
    RAISE EXCEPTION 'FAIL: (j) 実行記録の target_date / as_of / 時刻が期待と異なる: %', row_to_json(v_run);
  END IF;

  -- キーの形（件数だけ）
  IF NOT (v_stats ?& ARRAY['monitored', 'excluded', 'detected', 'opened', 'updated', 'escalated',
                           'reopened', 'resolved', 'severity_lowered'])
     OR NOT (v_stats->'excluded' ?& ARRAY['no_account', 'self', 'not_started', 'inactive'])
     OR NOT (v_stats->'detected' ?& ARRAY['weight_change', 'record_gap'])
     OR NOT (v_stats->'detected'->'record_gap' ?& ARRAY['not_started', 'no_data', 'no_record'])
     OR NOT (v_stats->'resolved' ?& ARRAY['cleared', 'expired', 'reassigned', 'ineligible']) THEN
    RAISE EXCEPTION 'FAIL: (j) stats のキーが期待と異なる: %', v_stats;
  END IF;

  -- client_id（UUID）や試験用顧客の ID を含まない
  IF v_stats::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' THEN
    RAISE EXCEPTION 'FAIL: (j) stats に UUID が含まれている: %', v_stats;
  END IF;

  -- 71（not_started）と 72（diet の減少）が数に入っている（73 は登録から50日・記録なしで not_started の対象外）
  IF (v_stats->>'monitored')::int < 2
     OR (v_stats->'excluded'->>'not_started')::int < 1
     OR (v_stats->'detected'->'record_gap'->>'not_started')::int < 1
     OR (v_stats->'detected'->>'weight_change')::int < 1
     OR (v_stats->>'severity_lowered')::int < 1
     OR (v_stats->>'opened')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (j) stats の件数が期待より少ない: %', v_stats;
  END IF;
  RAISE NOTICE 'OK: 実行記録は1回で1行、stats は件数だけ（UUID を含まない）: %', v_stats;
END $$;

\echo '--- case k: 生きている行の二重 INSERT は unique_violation（resolved の行とは共存できる）'

DO $$
BEGIN
  -- resolved の行と生きている行は共存できる
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on, resolved_at, resolved_reason
  ) VALUES
    ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000073',
     'record_gap', 'medium', 'resolved', '{"v":1}', '2026-08-01', '2026-08-01', '2026-08-02', now(), 'cleared'),
    ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000073',
     'record_gap', 'medium', 'open', '{"v":1}', '2026-08-10', '2026-08-10', '2026-08-10', NULL, NULL);

  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, status, payload,
      first_detected_on, surfaced_on, last_detected_on
    ) VALUES
      ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000073',
       'record_gap', 'high', 'open', '{"v":1}', '2026-08-11', '2026-08-11', '2026-08-11');
    RAISE EXCEPTION 'FAIL: (k) 生きている record_gap を二重に INSERT できてしまった';
  EXCEPTION
    WHEN unique_violation THEN
      IF SQLERRM NOT LIKE '%alerts_live_client_type_key%' THEN RAISE; END IF;
  END;

  -- 種別が違えば同じ顧客に生きている行を持てる
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on
  ) VALUES
    ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000073',
     'weight_change', 'high', 'open', '{"v":1}', '2026-08-11', '2026-08-11', '2026-08-11');
  RAISE NOTICE 'OK: 生きている行の二重 INSERT は unique_violation（alerts_live_client_type_key）。resolved の行・別の種別とは共存できる';
END $$;

-- 第2部-4 の片付け
DELETE FROM public.clients WHERE client_id::text LIKE 'cccccccc-0914-0002-%';
DELETE FROM public.alert_detection_runs;

-- =============================================================================
-- 第2部-5: 登録日が ±infinity の顧客（ケース n）
--   clients は顧客本人が全列を UPDATE できる（clients_update_own）。'-infinity' にされると日付の
--   引き算が 22008（cannot subtract infinite dates）になり、全顧客を1トランザクションで処理する
--   本実行・evaluate・担当トレーナーの状態 RPC が毎日落ちていた
--   81: 登録 '-infinity'・記録なし（L が NULL で「登録からの日数」を引き算する経路）・生きている record_gap
--   82: 登録 'infinity'（snapshot に居なくなる）・生きている record_gap
--   83: 普通の顧客（登録 08-17・記録なし）→ 同じ実行で not_started N=3 が作られる（他の顧客が巻き添えにならない）
-- =============================================================================
\echo '--- 第2部-5 setup: 登録日が ±infinity の顧客 81・82 と普通の顧客 83'

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT ('cccccccc-0914-0002-0000-0000000000' || n)::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'detection-test-c' || n || '@example.com', 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM unnest(ARRAY['81','82','83']) AS n;

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('cccccccc-0914-0002-0000-000000000081', '検知テスト顧客81', 'aaaaaaaa-0914-0002-0000-00000000000a', '-infinity'),
  ('cccccccc-0914-0002-0000-000000000082', '検知テスト顧客82', 'aaaaaaaa-0914-0002-0000-00000000000a', 'infinity'),
  ('cccccccc-0914-0002-0000-000000000083', '検知テスト顧客83', 'aaaaaaaa-0914-0002-0000-00000000000a', '2026-08-17 12:00+09');

-- 書き換える前に作られていた生きている行
INSERT INTO public.alerts (
  trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, acknowledged_at
) VALUES
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000081',
   'record_gap', 'medium', 'open', '{"v":1}', '2026-08-10', '2026-08-10', '2026-08-10', NULL),
  ('aaaaaaaa-0914-0002-0000-00000000000a', 'cccccccc-0914-0002-0000-000000000082',
   'record_gap', 'medium', 'acknowledged', '{"v":1}', '2026-08-10', '2026-08-10', '2026-08-10', now());

\echo '--- case n: 登録日が ±infinity でも本実行・evaluate・状態 RPC が落ちず、その顧客の生きている行は ineligible'

DO $$
DECLARE
  v_res jsonb;
  r     record;
  cnt   int;
BEGIN
  -- evaluate（dry run・バックテスト）が落ちず、81・82 を評価しない
  SELECT count(*) INTO cnt
    FROM public.evaluate_client_alerts('2026-08-20', '2026-08-20 06:00+09') e
   WHERE e.client_id IN ('cccccccc-0914-0002-0000-000000000081', 'cccccccc-0914-0002-0000-000000000082');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: (n) 登録日が ±infinity の顧客が % 行評価されている', cnt;
  END IF;

  -- 本実行が落ちない（落ちると 22008 で全トレーナー分が巻き戻る）
  BEGIN
    v_res := public.run_client_alert_detection('2026-08-20');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (n) 登録日が ±infinity の顧客がいると本実行が失敗する（% %）', SQLSTATE, SQLERRM;
  END;

  -- 81・82 の生きている行は ineligible で閉じる（評価も解消もされないまま残り続けない）
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id IN ('cccccccc-0914-0002-0000-000000000081', 'cccccccc-0914-0002-0000-000000000082')
     AND a.status = 'resolved' AND a.resolved_reason = 'ineligible';
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: (n) 登録日が ±infinity の顧客の行が ineligible で閉じていない（% 件）', cnt;
  END IF;

  -- 同じ実行で、普通の顧客 83 は not_started N=3 で作られる
  SELECT * INTO r FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0002-0000-000000000083' AND a.resolved_at IS NULL;
  IF r.id IS NULL OR r.payload->>'variant' IS DISTINCT FROM 'not_started' OR r.severity <> 'medium' THEN
    RAISE EXCEPTION 'FAIL: (n) 同じ実行で普通の顧客 83 の行ができていない: %', row_to_json(r);
  END IF;
  IF (v_res->'stats'->'resolved'->>'ineligible')::int < 2 THEN
    RAISE EXCEPTION 'FAIL: (n) stats の resolved.ineligible が 2 未満: %', v_res->'stats';
  END IF;

  -- 担当トレーナー T の状態 RPC も落ちない。T の顧客は 81・82・83 だけで、人数に入るのは 83 の1人
  -- （83 が監視か未開始かは今日の日付で変わるので、合計で見る）
  PERFORM set_config('request.jwt.claims',
                     '{"sub":"aaaaaaaa-0914-0002-0000-00000000000a","role":"authenticated"}', true);
  BEGIN
    SELECT * INTO r FROM public.get_alert_detection_status();
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (n) 登録日が ±infinity の顧客がいると担当トレーナーの状態 RPC が失敗する（% %）', SQLSTATE, SQLERRM;
  END;
  PERFORM set_config('request.jwt.claims', '', true);
  IF r.monitored_count + r.excluded_no_account + r.excluded_not_started + r.excluded_inactive <> 1 THEN
    RAISE EXCEPTION 'FAIL: (n) 状態 RPC の人数の合計が 監視 % / no_account % / not_started % / inactive %（期待 合計 1 = 83 だけ）',
      r.monitored_count, r.excluded_no_account, r.excluded_not_started, r.excluded_inactive;
  END IF;
  RAISE NOTICE 'OK: 登録日 -infinity / infinity の顧客がいても evaluate・本実行・状態 RPC は成功し、その顧客の生きている行は ineligible';
END $$;

-- =============================================================================
-- 第3部: 登録内容（postgres として実行）
-- =============================================================================
\echo '--- case l: cron ジョブ detect-client-alerts の登録内容（1件 / 0 21 * * * / SQL を直接呼ぶ / EXPLAIN できる）'

DO $$
DECLARE
  cnt             int;
  v_job           record;
  v_stmt          text;
  v_alerts_before bigint;
  v_runs_before   bigint;
BEGIN
  SELECT count(*) INTO cnt FROM cron.job WHERE jobname = 'detect-client-alerts';
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: (l) cron ジョブ detect-client-alerts が % 件（期待 1 件。重複すると二重実行になる）', cnt;
  END IF;

  SELECT jobname, schedule, command INTO v_job FROM cron.job WHERE jobname = 'detect-client-alerts';
  IF v_job.schedule <> '0 21 * * *' THEN
    RAISE EXCEPTION 'FAIL: (l) schedule が %（期待 0 21 * * * = 06:00 JST）', v_job.schedule;
  END IF;
  IF position('public.run_client_alert_detection' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: (l) command が run_client_alert_detection を呼んでいない: %', v_job.command;
  END IF;
  IF position('''Asia/Tokyo''' IN v_job.command) = 0 THEN
    RAISE EXCEPTION 'FAIL: (l) command が JST の今日を渡していない（Asia/Tokyo が無い）: %', v_job.command;
  END IF;
  IF position('net.http_post' IN v_job.command) > 0 THEN
    RAISE EXCEPTION 'FAIL: (l) command が HTTP（net.http_post）を使っている: %', v_job.command;
  END IF;

  -- EXPLAIN（ANALYZE なし）は解析・計画だけで関数を実行しない。前後で件数が変わらないことも確かめる
  SELECT count(*) INTO v_alerts_before FROM public.alerts;
  SELECT count(*) INTO v_runs_before FROM public.alert_detection_runs;
  v_stmt := regexp_replace(v_job.command, '[\s;]+$', '');
  BEGIN
    EXECUTE 'EXPLAIN (COSTS OFF) ' || v_stmt;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL: (l) command が SQL として解析・計画できない（% %）', SQLSTATE, SQLERRM;
  END;
  IF (SELECT count(*) FROM public.alerts) <> v_alerts_before
     OR (SELECT count(*) FROM public.alert_detection_runs) <> v_runs_before THEN
    RAISE EXCEPTION 'FAIL: (l) EXPLAIN の前後で alerts / alert_detection_runs の件数が変わった（関数が実行された）';
  END IF;
  RAISE NOTICE 'OK: detect-client-alerts は1件 / 0 21 * * * / % （EXPLAIN できて件数は変わらない）', v_job.command;
END $$;

\echo '--- case m: 関数の定義に Asia/Tokyo があり、DEFINER の4関数すべてに search_path = "" が設定されていること'

DO $$
DECLARE
  v_fn     regprocedure;
  v_secdef boolean;
  v_config text[];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.client_activity_snapshot(date, timestamptz, uuid)'::regprocedure,
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure,
    'public.get_alert_detection_status()'::regprocedure
  ] LOOP
    IF position('Asia/Tokyo' IN pg_get_functiondef(v_fn)) = 0 THEN
      RAISE EXCEPTION 'FAIL: (m) % の定義に Asia/Tokyo が無い（UTC の日付で判定している疑い）', v_fn;
    END IF;

    SELECT p.prosecdef, p.proconfig INTO v_secdef, v_config FROM pg_proc p WHERE p.oid = v_fn;
    IF NOT v_secdef THEN
      RAISE EXCEPTION 'FAIL: (m) % が SECURITY DEFINER になっていない', v_fn;
    END IF;
    IF v_config IS NULL OR NOT ('search_path=""' = ANY (v_config)) THEN
      RAISE EXCEPTION 'FAIL: (m) % の search_path が空文字に固定されていない（proconfig=%）',
        v_fn, coalesce(v_config::text, 'NULL');
    END IF;
  END LOOP;

  -- evaluate の既定の対象日は JST の今日（既定引数の式に Asia/Tokyo）
  IF position('Asia/Tokyo' IN pg_get_function_arguments('public.evaluate_client_alerts(date, timestamptz)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'FAIL: (m) evaluate_client_alerts の既定の対象日が JST で定義されていない';
  END IF;
  -- run は対象日を必須にする（既定値なし）
  IF (SELECT p.pronargdefaults FROM pg_proc p WHERE p.oid = 'public.run_client_alert_detection(date)'::regprocedure) <> 0 THEN
    RAISE EXCEPTION 'FAIL: (m) run_client_alert_detection の対象日に既定値がある（必須のはず）';
  END IF;
  -- run は遷移の前に生きている行を FOR UPDATE でロックする（継続の3本の UPDATE の間に API の対応済みが
  -- 挟まると再浮上を取りこぼすため。同時実行は1セッションのテストでは再現できないので定義で確かめる）
  IF position('FOR UPDATE' IN pg_get_functiondef('public.run_client_alert_detection(date)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'FAIL: (m) run_client_alert_detection が生きている行を FOR UPDATE でロックしていない';
  END IF;
  RAISE NOTICE 'OK: 4関数とも Asia/Tokyo を含み、SECURITY DEFINER + search_path = ""。evaluate の既定は JST の今日、run は対象日必須で生きている行をロックする';
END $$;

ROLLBACK;

-- -----------------------------------------------------------------------------
-- ケース(i) の2: トランザクション全体を READ ONLY で始めても evaluate は実行できる
--   （上のセーブポイントの確認に加え、BEGIN READ ONLY そのもので確かめる。データは今の DB のまま）
-- -----------------------------------------------------------------------------
\echo '--- case i-2: BEGIN READ ONLY の中で evaluate を実行でき、alerts の行数を変えないこと'

BEGIN READ ONLY;

DO $$
DECLARE
  v_before bigint;
  v_after  bigint;
BEGIN
  SELECT count(*) INTO v_before FROM public.alerts;
  PERFORM count(*) FROM public.evaluate_client_alerts();
  PERFORM count(*) FROM public.evaluate_client_alerts((now() AT TIME ZONE 'Asia/Tokyo')::date - 1,
                                                      now() - interval '1 hour');
  SELECT count(*) INTO v_after FROM public.alerts;
  IF v_before <> v_after THEN
    RAISE EXCEPTION 'FAIL: (i-2) evaluate の前後で alerts が % → % 行に変わった', v_before, v_after;
  END IF;
  RAISE NOTICE 'OK: BEGIN READ ONLY の中でも evaluate を実行できる（alerts は % 行のまま）', v_after;
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CLIENT ALERT DETECTION TESTS PASSED'
