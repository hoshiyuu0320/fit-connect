-- =============================================================================
-- Migration: alert_sleep_decline
-- フェーズ9.1 拡張 ③: 異常検知に睡眠悪化（sleep_decline）を3つ目の種別として足す。
-- alerts.alert_type の CHECK を作り直し、evaluate_client_alerts に睡眠の判定を、
-- run_client_alert_detection に睡眠の期限切れと stats の集計キーを足す
--
-- 仕様出典: docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md
--   「4. 検知ルールの仕様」「5. DB の変更」「9. リリースとロールバック」
--   土台: docs/tasks/2026-09-13-trainer-intervention-plan.md（9.1 の共通定義・状態遷移）
--
-- 背景:
--   - 9.1 の検知（20260914000200）は体重急変（weight_change）と記録途絶（record_gap）の2種別。
--     カタログ 1-A ③ の睡眠悪化を同じ評価関数の3本目の UNION ALL として足し、監視対象の判定・
--     状態遷移・冪等性・対応済みの操作・「今日の対応」の表示をそのまま使う（設計 §3）
--   - 本番の睡眠データは実質テストデータで、閾値の妥当性は確かめられない（設計 §2）。判定の正しさは
--     supabase/tests/sleep_decline_alert_test.sql の合成データで固定する
--
-- 検知ルール（定数と根拠は evaluate_client_alerts の DECLARE、詳細は設計 §4）:
--   - 晩 = sleep_records の1行。recorded_date（JST の起床日）が [max(D−14, J), D−1] で、
--     created_at が締め時刻以前の行だけを使う
--   - 睡眠時間: 120〜960 分の晩だけを数え、直近 [max(D−7, J), D−1] と前 [max(D−14, J), D−8] の
--     中央値を比べる。両方の窓に 4 晩以上で評価し、Δ ≤ −60 分で成立、Δ > −48 分で解消、間は保留
--   - 目覚め評価: 直近の窓の wakeup_rating の平均（睡眠時間が範囲外・NULL の行も数える）。
--     3 回以上で評価し、平均 < 1.5 で成立、≥ 2.0 で解消、間は保留
--   - 全体: どちらかが成立 → detected / 睡眠時間が保留・不足か目覚め評価が保留 → unknown /
--     どちらかが解消 → cleared / それ以外 → unknown（設計 §4.4 の表）
--   - 重大度は detected のとき常に medium。payload に severity_reason は入れない
--     （run_client_alert_detection の severity_lowered が種別を問わずこのキーを数えるため）
--   - 期限切れ: 生きている sleep_decline で last_detected_on ≤ D − 14 → resolved（expired）
--
-- 変更（この順に実行する。どれかが失敗すると migration 全体が巻き戻る）:
--   0. ドリフトガード: 両関数の本体（prosrc）の md5 が 20260914000200 の定義と一致することを確かめる
--   1. CHECK alerts_alert_type_check を DROP → ADD（'sleep_decline' を足す）
--   2. alerts の列 COMMENT（alert_type / severity / payload / last_detected_on / resolved_reason）
--   3. evaluate_client_alerts を全文で再定義（睡眠の CTE と3本目の UNION ALL）
--   4. run_client_alert_detection を全文で再定義（期限切れ 3-3 と stats の detected.sleep_decline）
--   5. 末尾の検査: 両関数が SECURITY DEFINER・search_path = ''・EXECUTE は service_role だけ
--   変えないもの: client_activity_snapshot / get_alert_detection_status / cron / alerts の索引と RLS
--
-- push 前の確認（オーナー）:
--   `supabase migration list --linked` と `supabase db push --dry-run` で、未適用が
--   20261003000000 の1本だけであることを確かめる。06:00 JST の直前は避ける
--
-- push 後の確認（postgres で実行。件数だけ）:
--   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
--    WHERE c.conrelid = 'public.alerts'::regclass AND c.conname = 'alerts_alert_type_check';
--   SELECT p.oid::regprocedure, p.prosecdef, p.proconfig, p.proacl,
--          has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
--          has_function_privilege('service_role',  p.oid, 'EXECUTE') AS service_role
--     FROM pg_proc p
--    WHERE p.oid IN ('public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
--                    'public.run_client_alert_detection(date)'::regprocedure);
--   SELECT e.alert_type, e.state, count(*) FROM public.evaluate_client_alerts() e
--    GROUP BY 1, 2 ORDER BY 1, 2;
--
-- ロールバック（必要になったときだけ、新しい migration で。設計 §9）:
--   sleep_decline の行を resolved も含めてすべて DELETE → 両関数を 20260914000200 の定義に戻す →
--   CHECK を2種別に戻す（CHECK の ADD は全行を検証するので、resolved にするだけでは戻せない）
--
-- 冪等性: 1回だけ適用する前提。適用後にもう一度流すと、両関数の本体が変わっているので
--   0 のドリフトガードで止まる（REMOTE_DRIFT_SINCE_CAPTURE）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. ドリフトガード
--    本 migration は evaluate_client_alerts と run_client_alert_detection を 20260914000200 の
--    定義を土台に全文で作り直す。リモートで誰かが（migration を経ずに）本体を直していた場合に、
--    それを黙って上書きしないよう、作り直す前に本体（pg_proc.prosrc）の md5 を確かめ、
--    一致しなければ例外で migration 全体を止める。関数が存在しない場合も同じ例外で止める。
--
--    期待値（2026-10-03 に隔離ローカルとリモートの両方で一致を確認済み）:
--      evaluate_client_alerts     : 9c553a939d98fb60d58022897f6a5d4c
--      run_client_alert_detection : 0e80baea1335f09889edac7fc584836f
--    20260914000200 より後の migration は両関数に触れていないので、ローカルで全 migration を
--    流す順序（fresh DB）でもガードは通る。比較するのは本体だけ（SECURITY DEFINER /
--    search_path / ACL は本 migration が明示的に書き直し、5 の末尾の検査で確かめる）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn  record;
  v_oid oid;
  v_md5 text;
BEGIN
  FOR v_fn IN
    SELECT t.signature, t.expected_md5
      FROM (VALUES
        (1, 'public.evaluate_client_alerts(date, timestamptz)', '9c553a939d98fb60d58022897f6a5d4c'),
        (2, 'public.run_client_alert_detection(date)',          '0e80baea1335f09889edac7fc584836f')
      ) AS t(ord, signature, expected_md5)
     ORDER BY t.ord
  LOOP
    v_oid := to_regprocedure(v_fn.signature);

    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s does not exist (expected md5(prosrc)=%s, the definition of 20260914000200)',
                v_fn.signature, v_fn.expected_md5
              ),
              HINT    = '20260914000200 で作った関数がありません。リモートの現状を確かめてから migration を直してください。';
    END IF;

    SELECT md5(p.prosrc)
      INTO v_md5
      FROM pg_catalog.pg_proc p
     WHERE p.oid = v_oid;

    IF v_md5 IS DISTINCT FROM v_fn.expected_md5 THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s has md5(prosrc)=%s, expected %s (the definition of 20260914000200)',
                v_fn.signature, v_md5, v_fn.expected_md5
              ),
              HINT    = '関数本体が 20260914000200 の定義から変わっています。このまま適用すると CREATE OR REPLACE がその変更を上書きするため中止しました。リモートの関数の差分を調べてから migration を直してください。';
    END IF;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. alerts.alert_type の CHECK を作り直す（20260914000000 の方針どおり DROP → ADD）
--    ADD は既存の全行を検証するが、既存の値（weight_change / record_gap）はそのまま通る。
--    IF EXISTS は付けない（制約名が想定と違えば、ここで止めて気づけるようにする）
-- -----------------------------------------------------------------------------
ALTER TABLE public.alerts DROP CONSTRAINT alerts_alert_type_check;
ALTER TABLE public.alerts ADD CONSTRAINT alerts_alert_type_check
  CHECK (alert_type IN ('weight_change', 'record_gap', 'sleep_decline'));

-- -----------------------------------------------------------------------------
-- 2. alerts の列 COMMENT に睡眠悪化の説明を足す（全文で書き直す）
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN public.alerts.alert_type IS
  'weight_change（体重急変）/ record_gap（記録途絶）/ sleep_decline（睡眠悪化）。'
  '種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない';
COMMENT ON COLUMN public.alerts.severity IS
  'high / medium / low（low は将来用）。体重急変は high（purpose=diet の減少だけ medium）、'
  '記録途絶は途絶日数 3〜6 日が medium、7 日以上が high、睡眠悪化は常に medium';
COMMENT ON COLUMN public.alerts.payload IS
  '判定時点の値・閾値・期間・変種（v でバージョンを持つ。日付だけで時刻は持たない）。'
  'weight_change: {v:1, direction, recent:{from,to,avg_kg,days}, previous:{from,to,avg_kg,days}, '
  'delta_kg, delta_pct, threshold:{pct,kg}, severity_reason?}。'
  'record_gap: {v:1, variant:not_started|no_data|no_record, gap_from, gap_to, '
  'last_activity_on, last_record_on, threshold_days}（日数は gap_to − gap_from + 1 で表示時に出す）。'
  'sleep_decline: {v:1, triggers:[duration|wakeup], recent:{from,to,median_minutes,nights}, '
  'previous:{from,to,median_minutes,nights}, delta_minutes, wakeup:{avg,count}, '
  'threshold:{drop_minutes,min_nights,wakeup_avg,min_ratings}}'
  '（from は窓の実際の始まりで、登録直後は前の窓の from が to より後になる。窓が空なら median_minutes は null）。'
  '表示用の文字列は入れない';
COMMENT ON COLUMN public.alerts.last_detected_on IS
  '条件の成立を最後に確かめた対象日（JST の暦日）。weight_change と sleep_decline はこれが'
  '対象日の 14 日前以前になると resolved（expired）';
COMMENT ON COLUMN public.alerts.resolved_reason IS
  'cleared（条件が解消）/ expired（weight_change と sleep_decline は 14 日間再確認されない。'
  'record_gap は顧客が監視対象外 = 登録から 14 日を過ぎた未開始・最終到着から 14 日超 になって'
  '監視を打ち切った）/ reassigned（担当替え）/ ineligible（アプリ未登録・自己登録になった、'
  'または登録日が不正で評価できない）';

-- -----------------------------------------------------------------------------
-- 3. evaluate_client_alerts(p_target_date, p_as_of)
--    監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、
--    weight_change・record_gap・sleep_decline の3行を返す。state は
--      detected（成立）/ cleared（解消）/ unknown（評価できない・成立値と解消値の間。状態を変えない）
--    severity は detected のときだけ入る。payload は判定時点の値（alerts.payload の形）。
--
--    締め時刻の範囲: D の JST 0:00 以降、かつ now() 以前。範囲外は例外にする
--    （未来の対象日は、既定の締め時刻 now() が D の 0:00 より前になるのでここで弾かれる）。
--    過去の日 d に p_as_of = d の 06:00 JST を渡すと、「その朝に見えていたデータ」に近い状態を
--    再現できる（バックテスト）。監視対象は alerts に依らない（snapshot は登録日・記録・
--    メッセージだけで決まる）ので、バックテストは本実行の前後どちらで取っても同じになる
--
--    plpgsql にしたのは、定数を冒頭1箇所にまとめるのと、締め時刻の範囲を例外にするため。
--    戻り列名（client_id など）と表の列名が重なるので #variable_conflict use_column を付け、
--    そのうえで列はすべて別名で修飾する
--
--    20260914000200 からの変更は睡眠悪化（sleep_decline）の追加だけ:
--      - DECLARE に ③ の定数
--      - g_eval の後ろに s_night / s_window / s_eval / s_cond / s_state の CTE
--      - 3本目の UNION ALL
--    体重急変・記録途絶の判定と payload は変えない
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.evaluate_client_alerts(
  p_target_date date DEFAULT ((now() AT TIME ZONE 'Asia/Tokyo')::date),
  p_as_of timestamptz DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  trainer_id uuid,
  alert_type text,
  state text,
  severity text,
  payload jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
  -- ===== 定数（閾値・窓の長さ・日数はここ1箇所。根拠は計画書「検知ルールの仕様」と睡眠悪化の設計 §4）=====
  -- payload の形のバージョン（形を変えたら上げ、Web の describeAlert を合わせる）
  c_payload_version      constant integer := 1;

  -- ---- ① 体重急変 weight_change ----
  -- 見る期間は D−14〜D−1（登録日より前の計測は使わない）。直近の窓 D−7〜D−1 と前の窓
  -- D−14〜D−8 を比べる（カタログ 1-A）。06:00 時点では当日の計測はほとんど届かないので D−1 で閉じる
  c_weight_span_days     constant integer := 14;
  c_weight_recent_days   constant integer := 7;
  -- 各窓に代表値が 3 日以上あるときだけ評価する（実データでは窓の日数条件を外すと ±3% 超が
  -- 9日出るが、すべて1〜2日しかない窓だった）。登録日の下限と合わせ、評価できるのは D ≥ J + 10 から
  c_weight_min_days      constant integer := 3;
  -- 値の範囲（誤入力・単位違いを除く）
  c_weight_min_kg        constant numeric := 20;
  c_weight_max_kg        constant numeric := 300;
  -- 日ごとの代表値はその JST 日の中央値（1日に最大10件・20kg 幅の日がある）。さらに 14日分の
  -- 代表値の中央値から ±15% を超える日は外れ値として除く（60kg の人に誤計測の 80kg が1日混ざると、
  -- 7日平均が約 2.9kg 動いて閾値を超える）
  c_weight_outlier_ratio constant numeric := 0.15;
  -- 成立: |Δ%| ≥ 3.0 または |Δkg| ≥ 2.0（カタログの初期値のまま。実データ 42 client-day の
  -- 最大は 2.62% / 1.67kg で、±3% / ±2kg 超は0件）
  c_weight_pct           constant numeric := 3.0;
  c_weight_kg            constant numeric := 2.0;
  -- 解消: 評価でき、かつ |Δkg| と |Δ%| の両方が成立値の 8 割未満（1.6kg / 2.4%）。
  -- 成立値と解消値の間の日と、評価できない日は unknown（状態を変えない = ヒステリシス）
  c_weight_clear_ratio   constant numeric := 0.8;
  -- 重大度は high。purpose = 'diet' の減少だけ medium に下げる（設計判断10。検知は残す）
  c_weight_severity      constant text := 'high';
  c_weight_diet_severity constant text := 'medium';

  -- ---- ② 記録途絶 record_gap ----
  -- 3日以上で成立（カタログどおり）。3〜6日は medium、7日以上は high
  c_gap_days             constant integer := 3;
  c_gap_high_days        constant integer := 7;

  -- ---- ③ 睡眠悪化 sleep_decline（設計 docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4）----
  -- 晩 = sleep_records の1行（recorded_date は JST の起床日）。見る期間は起床日 D−14〜D−1 で、
  -- 直近の窓 D−7〜D−1 と前の窓 D−14〜D−8 を比べる。当日 D の晩は 06:00 時点ではほとんど届かない
  -- （到着遅れの中央値は約35時間）ので使わない。登録日より前の晩も使わない（初回連携で入る
  -- 過去30日分で、担当になる前の変化を検知しないため。体重と同じ理由）
  c_sleep_span_days      constant integer := 14;
  c_sleep_recent_days    constant integer := 7;
  -- 睡眠時間（total_sleep_minutes。HealthKit の値で覚醒時間を含む）は 120〜960 分（2〜16時間、
  -- 両端を含む）の晩だけを数える。範囲外は時計を外して寝た晩などの計測ミスとして除き、
  -- 晩の数にも入れない（実データは 273〜571 分で、範囲外は0件）
  c_sleep_min_minutes    constant integer := 120;
  c_sleep_max_minutes    constant integer := 960;
  -- 両方の窓に有効な晩が 4 晩以上あるときだけ睡眠時間を評価する（3晩どうしの比較は揺れが大きい。
  -- HealthKit の睡眠は毎晩入るので「週の半分以上」で満たしやすい）。評価できるのは D ≥ J + 11 から
  c_sleep_min_nights     constant integer := 4;
  -- 成立: 直近の窓の中央値 − 前の窓の中央値 ≤ −60 分（カタログの初期値）。窓ごとの代表値は
  -- 1晩の外れ値に強い中央値にする（平均だと、毎晩 383 分の人の前の窓に 803 分が1晩あるだけで
  -- 差がちょうど −60 になる。体重の ±15% の外れ値除外は、日ごとの揺れが大きい睡眠では普通の晩まで
  -- 除いてしまう）。判定は丸める前の差で行う（中央値は 0.5 分刻み。−59.5 は成立しない）
  c_sleep_drop_minutes   constant integer := 60;
  -- 解消: 差 > −48 分（成立値の 8 割。体重と同じヒステリシス）。−60 < 差 ≤ −48 は保留
  c_sleep_clear_ratio    constant numeric := 0.8;
  -- 目覚め評価（1 = だるい、2 = まあまあ、3 = すっきり）は直近の窓の平均を使う。3 回以上あるときだけ
  -- 評価し、平均 < 1.5 で成立（カタログどおり）、平均 ≥ 2.0（まあまあ以上）で解消、間は保留。
  -- 睡眠時間が範囲外・NULL の行の評価も数える（評価は顧客の申告で、睡眠時間とは独立）
  c_sleep_min_ratings    constant integer := 3;
  c_sleep_wakeup_avg     constant numeric := 1.5;
  c_sleep_wakeup_clear   constant numeric := 2.0;
  -- 重大度は常に medium（生活の兆候で、体重の急変ほど急ぎではない。上がることが無いので、
  -- 対応済みの行が再浮上することもない）
  c_sleep_severity       constant text := 'medium';

  v_d0    timestamptz;
  v_as_of timestamptz;
BEGIN
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'evaluate_client_alerts: 対象日（p_target_date）が NULL です'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- D の JST 0:00（列に関数を掛けずに範囲比較するための境界）
  v_d0 := p_target_date::timestamp AT TIME ZONE 'Asia/Tokyo';
  v_as_of := coalesce(
    p_as_of,
    LEAST(now(), (p_target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo')
  );

  IF v_as_of < v_d0 OR v_as_of > now() THEN
    RAISE EXCEPTION 'evaluate_client_alerts: 締め時刻 % が範囲外です（対象日 % の JST 0:00 以降、かつ現在時刻以前）',
      v_as_of, p_target_date
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  RETURN QUERY
  WITH snap AS MATERIALIZED (
    SELECT s.client_id, s.trainer_id, s.join_on, s.purpose,
           s.last_activity_on, s.last_record_on
      FROM public.client_activity_snapshot(p_target_date, v_as_of) AS s
     WHERE s.exclusion_reason IS NULL
  ),
  -- ---- ① 体重急変 ----
  -- 日ごとの代表値 = その JST 日の中央値。[max(D−14, J) の 0:00, D の 0:00) に計測され、
  -- 締め時刻までに届いた 20〜300kg の値だけを使う（source は問わない）
  w_day AS (
    SELECT sn.client_id,
           (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date AS day,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY w.weight))::numeric AS rep
      FROM snap sn
      JOIN public.weight_records w ON w.client_id = sn.client_id
     WHERE w.recorded_at >= (GREATEST(p_target_date - c_weight_span_days, sn.join_on)::timestamp
                             AT TIME ZONE 'Asia/Tokyo')
       AND w.recorded_at < v_d0
       AND coalesce(w.created_at, w.recorded_at) <= v_as_of
       AND w.weight >= c_weight_min_kg
       AND w.weight <= c_weight_max_kg
     GROUP BY sn.client_id, (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
  ),
  w_median AS (
    SELECT d.client_id,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY d.rep))::numeric AS med
      FROM w_day d
     GROUP BY d.client_id
  ),
  -- 外れ値の日を除いてから、直近・前の窓ごとに日数と平均を出す
  w_window AS (
    SELECT d.client_id,
           count(*) FILTER (WHERE d.day >= p_target_date - c_weight_recent_days)  AS recent_days,
           avg(d.rep) FILTER (WHERE d.day >= p_target_date - c_weight_recent_days) AS recent_avg,
           count(*) FILTER (WHERE d.day <  p_target_date - c_weight_recent_days)  AS previous_days,
           avg(d.rep) FILTER (WHERE d.day <  p_target_date - c_weight_recent_days) AS previous_avg
      FROM w_day d
      JOIN w_median m ON m.client_id = d.client_id
     WHERE abs(d.rep - m.med) <= m.med * c_weight_outlier_ratio
     GROUP BY d.client_id
  ),
  w_eval AS (
    SELECT sn.client_id, sn.trainer_id, sn.purpose, sn.join_on,
           coalesce(ww.recent_days, 0)::integer   AS recent_days,
           ww.recent_avg,
           coalesce(ww.previous_days, 0)::integer AS previous_days,
           ww.previous_avg,
           -- Δkg = 直近の窓の平均 − 前の窓の平均、Δ% = Δkg ÷ 前の窓の平均 × 100（numeric で計算する）
           ww.recent_avg - ww.previous_avg                           AS delta_kg,
           (ww.recent_avg - ww.previous_avg) / ww.previous_avg * 100 AS delta_pct
      FROM snap sn
      LEFT JOIN w_window ww ON ww.client_id = sn.client_id
  ),
  w_state AS (
    SELECT we.*,
           CASE
             WHEN we.recent_days < c_weight_min_days
               OR we.previous_days < c_weight_min_days THEN 'unknown'
             WHEN abs(we.delta_pct) >= c_weight_pct
               OR abs(we.delta_kg) >= c_weight_kg THEN 'detected'
             WHEN abs(we.delta_pct) < c_weight_pct * c_weight_clear_ratio
              AND abs(we.delta_kg) < c_weight_kg * c_weight_clear_ratio THEN 'cleared'
             ELSE 'unknown'
           END AS st,
           coalesce(we.purpose = 'diet' AND we.delta_kg < 0, false) AS diet_decrease
      FROM w_eval we
  ),
  -- ---- ② 記録途絶 ----
  -- 上から1つだけ当てる（J = 登録日、R = 最終到着日、L = 最終記録日）
  --   1. L が NULL                → not_started: J 〜 D−1（N = D − J）
  --   2. (D−1) − R ≥ 3            → no_data    : R+1 〜 D−1
  --   3. それ以外                  → no_record  : max(L, J−1)+1 〜 min(R, D)−1
  --      （R より前は同期済みと見なせるので、そこで記録が無い日は「記録が無い」と確定できる。
  --        登録日より前は数えない）
  --   N = gap_to − gap_from + 1 が 3 以上なら detected、そうでなければ cleared
  g_base AS (
    SELECT sn.client_id, sn.trainer_id,
           sn.join_on          AS j,
           sn.last_activity_on AS r,
           sn.last_record_on   AS l,
           CASE
             WHEN sn.last_record_on IS NULL                                  THEN 'not_started'
             WHEN (p_target_date - 1) - sn.last_activity_on >= c_gap_days THEN 'no_data'
             ELSE 'no_record'
           END AS variant
      FROM snap sn
  ),
  g_span AS (
    SELECT g.*,
           CASE g.variant
             WHEN 'not_started' THEN g.j
             WHEN 'no_data'     THEN g.r + 1
             ELSE GREATEST(g.l, g.j - 1) + 1
           END AS gap_from,
           CASE g.variant
             WHEN 'no_record' THEN LEAST(g.r, p_target_date) - 1
             ELSE p_target_date - 1
           END AS gap_to
      FROM g_base g
  ),
  g_eval AS (
    SELECT gs.*, (gs.gap_to - gs.gap_from + 1) AS gap_days
      FROM g_span gs
  ),
  -- ---- ③ 睡眠悪化 ----
  -- 晩: 起床日が [max(D−14, J), D−1] で、締め時刻までに届いた行（source は問わない）。
  -- recorded_date は日付なので、体重のような JST 0:00 の境界への変換は要らない（±infinity の
  -- 日付も比較だけで落ちる）。valid = 睡眠時間が 120〜960 分（NULL・範囲外は false / NULL になり、
  -- 睡眠時間の集計の FILTER から外れる）
  s_night AS (
    SELECT sn.client_id,
           s.recorded_date       AS day,
           s.total_sleep_minutes AS minutes,
           s.wakeup_rating       AS rating,
           (s.total_sleep_minutes >= c_sleep_min_minutes
            AND s.total_sleep_minutes <= c_sleep_max_minutes) AS valid
      FROM snap sn
      JOIN public.sleep_records s ON s.client_id = sn.client_id
     WHERE s.recorded_date >= GREATEST(p_target_date - c_sleep_span_days, sn.join_on)
       AND s.recorded_date <= p_target_date - 1
       AND s.created_at <= v_as_of
  ),
  -- 窓ごとの有効な晩の数と中央値、直近の窓の目覚め評価の回数と平均。
  -- percentile_cont は double precision を返すので numeric にキャストしてから差・丸めを計算する
  -- （double precision の round は偶数丸めで、round(x, 2) も書けない）
  s_window AS (
    SELECT n.client_id,
           count(*) FILTER (WHERE n.valid AND n.day >= p_target_date - c_sleep_recent_days) AS recent_nights,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY n.minutes)
              FILTER (WHERE n.valid AND n.day >= p_target_date - c_sleep_recent_days))::numeric AS recent_median,
           count(*) FILTER (WHERE n.valid AND n.day < p_target_date - c_sleep_recent_days) AS previous_nights,
           (percentile_cont(0.5) WITHIN GROUP (ORDER BY n.minutes)
              FILTER (WHERE n.valid AND n.day < p_target_date - c_sleep_recent_days))::numeric AS previous_median,
           count(n.rating) FILTER (WHERE n.day >= p_target_date - c_sleep_recent_days) AS rating_count,
           avg(n.rating)   FILTER (WHERE n.day >= p_target_date - c_sleep_recent_days) AS rating_avg
      FROM s_night n
     GROUP BY n.client_id
  ),
  s_eval AS (
    SELECT sn.client_id, sn.trainer_id, sn.join_on,
           coalesce(sw.recent_nights, 0)::integer   AS recent_nights,
           sw.recent_median,
           coalesce(sw.previous_nights, 0)::integer AS previous_nights,
           sw.previous_median,
           -- Δ = 直近の窓の中央値 − 前の窓の中央値（分。丸める前の値。どちらかの窓が空なら NULL）
           sw.recent_median - sw.previous_median    AS delta_minutes,
           coalesce(sw.rating_count, 0)::integer    AS rating_count,
           sw.rating_avg
      FROM snap sn
      LEFT JOIN s_window sw ON sw.client_id = sn.client_id
  ),
  -- 条件ごとの状態: none（なし）/ insufficient（不足）/ met（成立）/ pending（保留）/ cleared（解消）
  s_cond AS (
    SELECT se.*,
           CASE
             WHEN se.recent_nights + se.previous_nights = 0                    THEN 'none'
             WHEN se.recent_nights < c_sleep_min_nights
               OR se.previous_nights < c_sleep_min_nights                      THEN 'insufficient'
             WHEN se.delta_minutes <= -c_sleep_drop_minutes                    THEN 'met'
             WHEN se.delta_minutes > -c_sleep_drop_minutes * c_sleep_clear_ratio THEN 'cleared'
             ELSE 'pending'
           END AS duration_st,
           CASE
             WHEN se.rating_count = 0                    THEN 'none'
             WHEN se.rating_count < c_sleep_min_ratings  THEN 'insufficient'
             WHEN se.rating_avg < c_sleep_wakeup_avg     THEN 'met'
             WHEN se.rating_avg >= c_sleep_wakeup_clear  THEN 'cleared'
             ELSE 'pending'
           END AS wakeup_st
      FROM s_eval se
  ),
  -- 全体の状態（上から順に当てる。設計 §4.4 の表）
  --   1. どちらかが成立 → detected
  --   2. 睡眠時間が保留・不足、または目覚め評価が保留 → unknown
  --      （睡眠時間の不足で解消させない: 到着遅れで直近の窓が3晩になる日に目覚め評価だけで解消すると、
  --        翌日に遅れた晩が届いて行が作り直される）
  --   3. どちらかが解消 → cleared（睡眠時間が解消なら、目覚め評価のなし・不足は解消を止めない）
  --   4. それ以外（どちらもなし、睡眠時間がなしで目覚め評価が不足など）→ unknown
  s_state AS (
    SELECT sc.*,
           CASE
             WHEN sc.duration_st = 'met' OR sc.wakeup_st = 'met'         THEN 'detected'
             WHEN sc.duration_st IN ('pending', 'insufficient')
               OR sc.wakeup_st = 'pending'                               THEN 'unknown'
             WHEN sc.duration_st = 'cleared' OR sc.wakeup_st = 'cleared' THEN 'cleared'
             ELSE 'unknown'
           END AS st
      FROM s_cond sc
  )
  SELECT ws.client_id,
         ws.trainer_id,
         'weight_change'::text,
         ws.st,
         CASE WHEN ws.st = 'detected' THEN
           CASE WHEN ws.diet_decrease THEN c_weight_diet_severity ELSE c_weight_severity END
         END,
         jsonb_build_object(
           'v', c_payload_version,
           'direction', CASE WHEN ws.delta_kg > 0 THEN 'increase'
                             WHEN ws.delta_kg < 0 THEN 'decrease' END,
           'recent', jsonb_build_object(
             'from',   p_target_date - c_weight_recent_days,
             'to',     p_target_date - 1,
             'avg_kg', round(ws.recent_avg, 2),
             'days',   ws.recent_days),
           'previous', jsonb_build_object(
             'from',   GREATEST(p_target_date - c_weight_span_days, ws.join_on),
             'to',     p_target_date - c_weight_recent_days - 1,
             'avg_kg', round(ws.previous_avg, 2),
             'days',   ws.previous_days),
           'delta_kg',  round(ws.delta_kg, 2),
           'delta_pct', round(ws.delta_pct, 2),
           'threshold', jsonb_build_object('pct', c_weight_pct, 'kg', c_weight_kg)
         )
         || CASE WHEN ws.st = 'detected' AND ws.diet_decrease
                 THEN jsonb_build_object('severity_reason', 'diet_decrease')
                 ELSE '{}'::jsonb END
    FROM w_state ws
  UNION ALL
  SELECT ge.client_id,
         ge.trainer_id,
         'record_gap'::text,
         CASE WHEN ge.gap_days >= c_gap_days THEN 'detected' ELSE 'cleared' END,
         CASE WHEN ge.gap_days >= c_gap_high_days THEN 'high'
              WHEN ge.gap_days >= c_gap_days      THEN 'medium' END,
         jsonb_build_object(
           'v',                c_payload_version,
           'variant',          ge.variant,
           'gap_from',         ge.gap_from,
           'gap_to',           ge.gap_to,
           'last_activity_on', ge.r,
           'last_record_on',   ge.l,
           'threshold_days',   c_gap_days
         )
    FROM g_eval ge
  UNION ALL
  SELECT ss.client_id,
         ss.trainer_id,
         'sleep_decline'::text,
         ss.st,
         CASE WHEN ss.st = 'detected' THEN c_sleep_severity END,
         jsonb_build_object(
           'v', c_payload_version,
           -- 成立した条件（並びは duration → wakeup）。detected のときだけ1つ以上入り、それ以外は []
           'triggers', to_jsonb(array_remove(ARRAY[
             CASE WHEN ss.duration_st = 'met' THEN 'duration' END,
             CASE WHEN ss.wakeup_st   = 'met' THEN 'wakeup'   END
           ]::text[], NULL)),
           -- from は窓の実際の始まり（登録直後は前の窓の from が to より後になり、nights は 0）。
           -- 中央値は整数に丸める（numeric の round は 0 から遠い方へ: 340.5 → 341）。窓が空なら null
           'recent', jsonb_build_object(
             'from',           GREATEST(p_target_date - c_sleep_recent_days, ss.join_on),
             'to',             p_target_date - 1,
             'median_minutes', round(ss.recent_median),
             'nights',         ss.recent_nights),
           'previous', jsonb_build_object(
             'from',           GREATEST(p_target_date - c_sleep_span_days, ss.join_on),
             'to',             p_target_date - c_sleep_recent_days - 1,
             'median_minutes', round(ss.previous_median),
             'nights',         ss.previous_nights),
           -- 丸める前の中央値どうしの差を丸めたもの（丸めた値どうしの差ではない。−59.5 → −60）
           'delta_minutes', round(ss.delta_minutes),
           'wakeup', jsonb_build_object(
             'avg',   round(ss.rating_avg, 2),
             'count', ss.rating_count),
           'threshold', jsonb_build_object(
             'drop_minutes', c_sleep_drop_minutes,
             'min_nights',   c_sleep_min_nights,
             'wakeup_avg',   c_sleep_wakeup_avg,
             'min_ratings',  c_sleep_min_ratings)
         )
    FROM s_state ss;
END;
$$;

COMMENT ON FUNCTION public.evaluate_client_alerts(date, timestamptz) IS
  '異常検知の評価（読み取り専用。dry run とバックテストを兼ねる）。'
  '監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、'
  'weight_change・record_gap・sleep_decline の3行 (client_id, trainer_id, alert_type, state, severity, payload) を返す。'
  'state: detected / cleared / unknown（評価できない・成立値と解消値の間。状態を変えない）。'
  'severity は detected のときだけ。p_target_date は JST の暦日（既定は JST の今日）、'
  'p_as_of は締め時刻（既定は LEAST(now(), D+1 の JST 0:00)。D の JST 0:00 より前・now() より後は例外）。'
  '閾値・窓・日数の定数は関数の冒頭1箇所にある。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「検知ルールの仕様」、'
  '睡眠悪化は docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4';

REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_client_alerts(date, timestamptz) TO service_role;

-- -----------------------------------------------------------------------------
-- 4. run_client_alert_detection(p_target_date)
--    本実行。evaluate_client_alerts(p_target_date, 締め時刻) の結果で alerts の状態を遷移させ、
--    alert_detection_runs に1行残して jsonb のサマリーを返す。
--    締め時刻は LEAST(now(), D+1 の JST 0:00) 固定（引数では受け取らない）。
--
--    ガード（例外にするのはこの3つだけ）:
--      - 対象日が NULL
--      - 対象日が JST の今日より未来
--      - 対象日が、最後に成功した本実行の対象日より前（古い窓で新しい状態を上書きしないため）
--      同じ対象日の再実行は許す（同じ状態に収束する。今日の対象日なら後から届いたデータの分だけ新しくなる）
--    pg_advisory_xact_lock で直列に実行する（cron と手動実行が重なっても片方ずつ）
--
--    状態遷移（すべて条件付き UPDATE。API と同時に走っても片方しか通らない）:
--      遷移の前に生きている行を FOR UPDATE でロックする。継続（4-1〜4-3）は条件の違う3本の UPDATE で、
--      READ COMMITTED では文ごとに見える状態が変わるため、その間に API の「対応済み」「元に戻す」が
--      コミットされると昇格の再浮上を取りこぼす（4-1 では open、4-2 では acknowledged に見えて
--      どちらにも当たらない）。ロックすれば API の条件付き UPDATE は本実行のコミットまで待つ
--      1. 対象外: 生きている行の顧客が no_account / self、または snapshot に居ない（登録日が
--         締め時刻より後・有限でない = 顧客本人が clients を書き換えた）→ resolved（ineligible）
--      2. 担当替え: 生きている行の trainer_id が今の clients.trainer_id と違う → resolved（reassigned）
--      3. 期限切れ（expired）:
--         3-1. 生きている weight_change で last_detected_on ≤ D − 14（評価されなかった顧客の行にも掛かる）
--         3-2. 生きている record_gap の顧客が not_started（登録から 14 日を過ぎた未開始）/
--              inactive（最終到着から 14 日超）になった。監視を打ち切り、以後は理由別の人数だけに数える
--              （オーナー決定 (1)。未開始は最大 14 日、記録・同期なしは最大 13 日で打ち切られる）
--         3-3. 生きている sleep_decline で last_detected_on ≤ D − 14（3-1 と同じ形。監視対象から外れた
--              顧客は evaluate に行が出ず cleared にならないので、これが無いと生きている行が残り続ける。
--              睡眠時間も目覚め評価も評価できないまま 14 日たった行もここで閉じる）
--      4. 継続: detected で生きている行がある → payload・severity・last_detected_on を更新。
--         重大度が上がったとき、open なら surfaced_on = D、acknowledged で reopened_count = 0 なら
--         open に戻す（acknowledged_at = NULL、reopened_count = 1、surfaced_on = D）
--      5. 新規: detected で生きている行が無い → open で INSERT（first_detected_on = surfaced_on =
--         last_detected_on = D）。生きている行の二重作成は alerts_live_client_type_key が防ぎ、
--         違反したら実行全体がロールバックされる
--      6. 解消: cleared → resolved（cleared）
--      unknown の行は何もしない。resolved は終端で、再発したら新しい行を作る
--
--    評価結果と snapshot は一時表（ON COMMIT DROP）に置いて各段で使い回す。
--    同じトランザクションで2回呼ばれても作り直せるよう、残っていれば先に DROP する
--
--    20260914000200 からの変更は睡眠悪化（sleep_decline）の追加だけ:
--      - DECLARE に c_sleep_expire_days と n_sleep_expired
--      - 期限切れの段 3-3（n_expired に足す）
--      - stats の detected.sleep_decline（detected の件数）
--    それ以外の段・ガード・stats のキーは変えない
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_client_alert_detection(p_target_date date)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- weight_change は 14 日間再確認できなければ期限切れ（last_detected_on ≤ D − 14）
  c_weight_expire_days constant integer := 14;
  -- sleep_decline も 14 日間再確認できなければ期限切れ（体重と同じ。設計 §4.7）
  c_sleep_expire_days  constant integer := 14;
  -- 重大度の順位（昇格の判定に使う。右ほど重い）
  c_severity_order     constant text[] := ARRAY['low', 'medium', 'high'];

  v_started_at   timestamptz := clock_timestamp();
  v_today        date := (now() AT TIME ZONE 'Asia/Tokyo')::date;
  v_last_target  date;
  v_as_of        timestamptz;
  v_reopened     uuid[];
  v_escalated    uuid[];
  n_continued    integer;
  n_opened       integer;
  n_ineligible   integer;
  n_reassigned   integer;
  n_expired      integer;
  n_gap_expired  integer;
  n_sleep_expired integer;
  n_cleared      integer;
  n_lowered      integer;
  v_population   jsonb;
  v_detected     jsonb;
  v_stats        jsonb;
BEGIN
  -- ---- ガード ----
  IF p_target_date IS NULL THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日（p_target_date）が NULL です'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF p_target_date > v_today THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日 % が JST の今日（%）より未来です',
      p_target_date, v_today
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- 同時実行を直列化する（ロックを取ってから「最後に成功した本実行」を読む）
  PERFORM pg_advisory_xact_lock(hashtext('public.run_client_alert_detection'));

  SELECT max(r.target_date) INTO v_last_target FROM public.alert_detection_runs r;
  IF v_last_target IS NOT NULL AND p_target_date < v_last_target THEN
    RAISE EXCEPTION 'run_client_alert_detection: 対象日 % が、最後に成功した本実行の対象日（%）より前です',
      p_target_date, v_last_target
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_as_of := LEAST(now(), (p_target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo');

  -- ---- 評価結果と snapshot を一時表に置く ----
  -- （DROP TABLE IF EXISTS だとセッションに一時スキーマがまだ無いときに NOTICE が出るので、
  --   to_regclass で有無を確かめてから落とす）
  IF to_regclass('pg_temp.client_alert_eval') IS NOT NULL THEN
    DROP TABLE pg_temp.client_alert_eval;
  END IF;
  CREATE TEMP TABLE client_alert_eval ON COMMIT DROP AS
    SELECT e.client_id, e.trainer_id, e.alert_type, e.state, e.severity, e.payload
      FROM public.evaluate_client_alerts(p_target_date, v_as_of) AS e;

  IF to_regclass('pg_temp.client_alert_snap') IS NOT NULL THEN
    DROP TABLE pg_temp.client_alert_snap;
  END IF;
  CREATE TEMP TABLE client_alert_snap ON COMMIT DROP AS
    SELECT s.client_id, s.exclusion_reason
      FROM public.client_activity_snapshot(p_target_date, v_as_of) AS s;

  -- ---- 生きている行をロックしてから遷移させる（上のコメント参照。API は本実行のコミットまで待つ）----
  PERFORM 1 FROM public.alerts a WHERE a.resolved_at IS NULL FOR UPDATE;

  -- ---- 1. 対象外（アプリ未登録・自己登録になった / snapshot に居ない）----
  -- snapshot に居ないのは、登録日が締め時刻より後か有限でない顧客（顧客本人が clients を書き換えた）。
  -- 評価も解消もされないまま残り続けないよう、ここで閉じる
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'ineligible'
   WHERE a.resolved_at IS NULL
     AND (
       EXISTS (
         SELECT 1
           FROM pg_temp.client_alert_snap s
          WHERE s.client_id = a.client_id
            AND s.exclusion_reason IN ('no_account', 'self')
       )
       OR NOT EXISTS (
         SELECT 1 FROM pg_temp.client_alert_snap s WHERE s.client_id = a.client_id
       )
     );
  GET DIAGNOSTICS n_ineligible = ROW_COUNT;

  -- ---- 2. 担当替え（新しい担当の分は下の「新規」で同じ実行の中に作る）----
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'reassigned'
    FROM public.clients c
   WHERE a.resolved_at IS NULL
     AND c.client_id = a.client_id
     AND c.trainer_id <> a.trainer_id;
  GET DIAGNOSTICS n_reassigned = ROW_COUNT;

  -- ---- 3. 期限切れ ----
  -- 3-1. weight_change: 14 日間再確認できない（評価されなかった顧客の行にも掛ける）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'weight_change'
     AND a.last_detected_on <= p_target_date - c_weight_expire_days;
  GET DIAGNOSTICS n_expired = ROW_COUNT;

  -- 3-2. record_gap: 顧客が監視対象外（not_started / inactive）になった → 監視を打ち切る。
  --      生きている行を理由に監視を延ばすと、「登録から42日・記録なし」のような行が対応済みに
  --      しない限り並び続け、対象外の人数にも数えられない（オーナー決定 (1) に反する）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
    FROM pg_temp.client_alert_snap s
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'record_gap'
     AND s.client_id = a.client_id
     AND s.exclusion_reason IN ('not_started', 'inactive');
  GET DIAGNOSTICS n_gap_expired = ROW_COUNT;
  n_expired := n_expired + n_gap_expired;

  -- 3-3. sleep_decline: 14 日間再確認できない（3-1 と同じ形。評価されなかった顧客の行にも掛ける）
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'expired'
   WHERE a.resolved_at IS NULL
     AND a.alert_type = 'sleep_decline'
     AND a.last_detected_on <= p_target_date - c_sleep_expire_days;
  GET DIAGNOSTICS n_sleep_expired = ROW_COUNT;
  n_expired := n_expired + n_sleep_expired;

  -- ---- 4. 継続（生きている行がある detected）----
  -- 4-1. 対応済みのまま重大度が上がり、まだ再浮上していない行 → open に戻す（1回の発生につき1回だけ）
  WITH moved AS (
    UPDATE public.alerts a
       SET status = 'open',
           acknowledged_at = NULL,
           reopened_count = 1,
           surfaced_on = p_target_date,
           severity = e.severity,
           payload = e.payload,
           last_detected_on = GREATEST(a.last_detected_on, p_target_date)
      FROM pg_temp.client_alert_eval e
     WHERE e.state = 'detected'
       AND a.client_id = e.client_id
       AND a.alert_type = e.alert_type
       AND a.trainer_id = e.trainer_id
       AND a.resolved_at IS NULL
       AND a.status = 'acknowledged'
       AND a.reopened_count = 0
       AND array_position(c_severity_order, e.severity) > array_position(c_severity_order, a.severity)
    RETURNING a.id
  )
  SELECT coalesce(array_agg(moved.id), '{}'::uuid[]) INTO v_reopened FROM moved;

  -- 4-2. open のまま重大度が上がった行 → surfaced_on = D（後で push の対象を選ぶ列なので漏らさない）
  WITH moved AS (
    UPDATE public.alerts a
       SET surfaced_on = p_target_date,
           severity = e.severity,
           payload = e.payload,
           last_detected_on = GREATEST(a.last_detected_on, p_target_date)
      FROM pg_temp.client_alert_eval e
     WHERE e.state = 'detected'
       AND a.client_id = e.client_id
       AND a.alert_type = e.alert_type
       AND a.trainer_id = e.trainer_id
       AND a.resolved_at IS NULL
       AND a.status = 'open'
       AND array_position(c_severity_order, e.severity) > array_position(c_severity_order, a.severity)
    RETURNING a.id
  )
  SELECT coalesce(array_agg(moved.id), '{}'::uuid[]) INTO v_escalated FROM moved;

  -- 4-3. それ以外の継続（重大度が同じ・下がった・再浮上済みの昇格）→ 値だけ更新し、status は変えない
  UPDATE public.alerts a
     SET severity = e.severity,
         payload = e.payload,
         last_detected_on = GREATEST(a.last_detected_on, p_target_date)
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'detected'
     AND a.client_id = e.client_id
     AND a.alert_type = e.alert_type
     AND a.trainer_id = e.trainer_id
     AND a.resolved_at IS NULL
     AND a.id <> ALL (v_reopened || v_escalated);
  GET DIAGNOSTICS n_continued = ROW_COUNT;

  -- ---- 5. 新規（生きている行が無い detected）----
  INSERT INTO public.alerts (
    trainer_id, client_id, alert_type, severity, status, payload,
    first_detected_on, surfaced_on, last_detected_on
  )
  SELECT e.trainer_id, e.client_id, e.alert_type, e.severity, 'open', e.payload,
         p_target_date, p_target_date, p_target_date
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'detected'
     AND NOT EXISTS (
       SELECT 1
         FROM public.alerts a
        WHERE a.client_id = e.client_id
          AND a.alert_type = e.alert_type
          AND a.resolved_at IS NULL
     );
  GET DIAGNOSTICS n_opened = ROW_COUNT;

  -- ---- 6. 解消 ----
  UPDATE public.alerts a
     SET status = 'resolved', resolved_at = now(), resolved_reason = 'cleared'
    FROM pg_temp.client_alert_eval e
   WHERE e.state = 'cleared'
     AND a.client_id = e.client_id
     AND a.alert_type = e.alert_type
     AND a.trainer_id = e.trainer_id
     AND a.resolved_at IS NULL;
  GET DIAGNOSTICS n_cleared = ROW_COUNT;

  -- ---- 実行記録（件数だけ。client_id や健康に関する値は入れない）----
  SELECT jsonb_build_object(
           'monitored', count(*) FILTER (WHERE s.exclusion_reason IS NULL),
           'excluded', jsonb_build_object(
             'no_account',  count(*) FILTER (WHERE s.exclusion_reason = 'no_account'),
             'self',        count(*) FILTER (WHERE s.exclusion_reason = 'self'),
             'not_started', count(*) FILTER (WHERE s.exclusion_reason = 'not_started'),
             'inactive',    count(*) FILTER (WHERE s.exclusion_reason = 'inactive')))
    INTO v_population
    FROM pg_temp.client_alert_snap s;

  SELECT jsonb_build_object(
           'weight_change',
             count(*) FILTER (WHERE e.alert_type = 'weight_change' AND e.state = 'detected'),
           'record_gap', jsonb_build_object(
             'not_started', count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'not_started'),
             'no_data',     count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'no_data'),
             'no_record',   count(*) FILTER (WHERE e.alert_type = 'record_gap' AND e.state = 'detected'
                                              AND e.payload->>'variant' = 'no_record')),
           'sleep_decline',
             count(*) FILTER (WHERE e.alert_type = 'sleep_decline' AND e.state = 'detected')),
         count(*) FILTER (WHERE e.state = 'detected' AND e.payload->>'severity_reason' IS NOT NULL)
    INTO v_detected, n_lowered
    FROM pg_temp.client_alert_eval e;

  v_stats := v_population || jsonb_build_object(
    'detected',  v_detected,
    'opened',    n_opened,
    'updated',   cardinality(v_reopened) + cardinality(v_escalated) + n_continued,
    'escalated', cardinality(v_escalated),
    'reopened',  cardinality(v_reopened),
    'resolved',  jsonb_build_object(
      'cleared',    n_cleared,
      'expired',    n_expired,
      'reassigned', n_reassigned,
      'ineligible', n_ineligible),
    'severity_lowered', n_lowered
  );

  INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats)
  VALUES (p_target_date, v_as_of, v_started_at, clock_timestamp(), v_stats);

  RETURN jsonb_build_object(
    'target_date', p_target_date,
    'as_of',       v_as_of,
    'stats',       v_stats
  );
END;
$$;

COMMENT ON FUNCTION public.run_client_alert_detection(date) IS
  '異常検知の本実行（cron detect-client-alerts が 06:00 JST に JST の今日を渡して呼ぶ）。'
  'evaluate_client_alerts の結果で alerts を状態遷移させ（対象外 → 担当替え → 期限切れ → 継続 → 新規 → 解消）、'
  'alert_detection_runs に1行残して {target_date, as_of, stats} を返す。'
  '対象日は必須（既定値なし）、締め時刻は LEAST(now(), D+1 の JST 0:00) 固定。dry run は evaluate を使う。'
  '例外は「対象日が NULL / JST の今日より未来 / 最後に成功した本実行の対象日より前」の3つだけで、同じ対象日の再実行は許す。'
  'stats のキー: monitored（監視数）/ excluded.{no_account,self,not_started,inactive} / '
  'detected.weight_change / detected.record_gap.{not_started,no_data,no_record} / detected.sleep_decline / '
  'opened（新規）/ updated（継続した行すべて。escalated・reopened を含む）/ '
  'escalated（open のまま重大度が上がり surfaced_on を更新）/ reopened（対応済みから再浮上）/ '
  'resolved.{cleared,expired,reassigned,ineligible}（expired は 14 日再確認されない weight_change・sleep_decline と、'
  '顧客が not_started / inactive になった record_gap。ineligible は no_account / self / snapshot に居ない顧客）/ '
  'severity_lowered（diet の減少で medium に下げた検知数）。'
  '件数だけで client_id や健康に関する値は入れない。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「状態遷移」「冪等性とガード」、'
  '睡眠悪化は docs/superpowers/specs/2026-10-03-sleep-decline-alert-design.md §4.7・§4.8';

REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM anon;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.run_client_alert_detection(date) TO service_role;

-- -----------------------------------------------------------------------------
-- 5. 末尾の検査（設計 §5 の 8）
--    REVOKE は自分が付与した権限しか剥がさない（lessons「SECURITY DEFINER 関数の権限是正
--    （フェーズ5.6）」）ので、作り直した後の実際の状態を確かめ、違えば例外で migration 全体を止める:
--      - SECURITY DEFINER のまま
--      - proconfig に search_path=""（既存テストと同じ '= ANY (proconfig)' で比べる。proconfig::text では比べない）
--      - PUBLIC に EXECUTE が無い（proacl が NULL = 既定権限 = PUBLIC に EXECUTE、なので acldefault で補う）
--      - anon / authenticated に EXECUTE が無く、service_role にある（has_function_privilege）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn     regprocedure;
  v_secdef boolean;
  v_config text[];
BEGIN
  FOREACH v_fn IN ARRAY ARRAY[
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure
  ] LOOP
    SELECT p.prosecdef, p.proconfig
      INTO v_secdef, v_config
      FROM pg_catalog.pg_proc p
     WHERE p.oid = v_fn;

    IF v_secdef IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s is not SECURITY DEFINER', v_fn);
    END IF;

    IF v_config IS NULL OR NOT ('search_path=""' = ANY (v_config)) THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s does not pin search_path to '''' (proconfig=%s)',
                               v_fn, coalesce(v_config::text, 'NULL'));
    END IF;

    IF EXISTS (
      SELECT 1
        FROM pg_catalog.pg_proc p,
             aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
       WHERE p.oid = v_fn
         AND a.grantee = 0  -- 0 = PUBLIC
         AND a.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s is still executable by PUBLIC', v_fn);
    END IF;

    IF has_function_privilege('anon', v_fn, 'EXECUTE')
       OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'ALERT_FUNCTION_POSTCHECK_FAILED'
        USING ERRCODE = 'P0001',
              DETAIL  = format('function %s EXECUTE: anon=%s authenticated=%s service_role=%s (expected f / f / t)',
                               v_fn,
                               has_function_privilege('anon', v_fn, 'EXECUTE'),
                               has_function_privilege('authenticated', v_fn, 'EXECUTE'),
                               has_function_privilege('service_role', v_fn, 'EXECUTE'));
    END IF;
  END LOOP;
END $$;
