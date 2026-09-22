-- =============================================================================
-- Migration: client_alert_detection
-- フェーズ9.1（トレーナー介入 / 異常検知 MVP）その3: 検知の評価・本実行・検知状態の関数と、
-- 06:00 JST の cron ジョブ 'detect-client-alerts'（inactive で登録）を追加する
--
-- 仕様出典: docs/tasks/2026-09-13-trainer-intervention-plan.md
--   「設計判断」1〜3・7〜10 /「検知ルールの仕様」/「状態遷移」/「冪等性とガード」/
--   「cron と Edge Function」/「契約 > RPC get_alert_detection_status()」
--
-- 関数（どれも SECURITY DEFINER・search_path = '' で、テーブル・関数は完全修飾）:
--   1. evaluate_client_alerts(p_target_date, p_as_of) … STABLE。監視対象の顧客について
--      (client_id, trainer_id, alert_type, state, severity, payload) を返すだけで書き込まない。
--      dry run とバックテストを兼ねる（MCP の読み取り・BEGIN READ ONLY の中でも実行できる）
--   2. run_client_alert_detection(p_target_date) … VOLATILE。evaluate の結果で alerts の
--      状態を遷移させ、alert_detection_runs に1行残す本実行。対象日は必須で既定値は無く、
--      締め時刻も受け取らない（本実行に時刻を差し込める口は運用で誤用しうるため）。
--      dry_run フラグも持たない（dry run は evaluate を使う）
--   3. get_alert_detection_status() … STABLE。呼び出したトレーナー（auth.uid()）について、
--      cron の有効・無効、最後に成功した本実行、担当顧客の監視数・対象外の理由別の人数を返す
--   EXECUTE: 1・2 は service_role のみ（cron は postgres で実行）、3 は authenticated のみ
--
-- 検知ルール（詳細は各関数の COMMENT と計画書）:
--   - 対象日 D = 実行した日の JST の暦日。評価の窓は D−1 で閉じる
--   - 締め時刻 as_of = p_as_of、指定が無ければ LEAST(now(), D+1 の JST 0:00)。
--     記録は到着と計測の両方が as_of 以前のものだけを見る
--   - ① weight_change: 直近 D−7〜D−1 と前 D−14〜D−8 の、JST 日ごとの中央値の平均を比べる。
--     |Δ%| ≥ 3.0 または |Δkg| ≥ 2.0 で成立、両方が 8 割未満で解消（ヒステリシス）
--   - ② record_gap: 未開始（not_started）→ 記録・同期なし（no_data）→ 記録なし（no_record）の
--     上から1つ。3日以上で成立、7日以上で high
--
-- cron（設計判断1）: SQL 関数を pg_cron から直接呼ぶ（Edge Function・Vault・pg_net は不要）。
--   例外は cron.job_run_details に failed として残るので、HTTP 経由の cron のように
--   「succeeded と記録されたのに中身は失敗」が起きない。有効化はリモートで dry run と
--   30日バックテストをした後にオーナーが行う（手順: docs/tasks/2026-07-10-cron-vault-setup.md）
--
-- 通知: 本 migration では sendNotification を呼ばず、通知種別も足さない（VAPID 設定後の後続タスク）
--
-- 冪等性: CREATE OR REPLACE と REVOKE / GRANT / COMMENT、cron は jobname の存在確認付きで
--   登録するため、何度実行しても同じ状態になる（既存ジョブの schedule / active には触れない）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. evaluate_client_alerts(p_target_date, p_as_of)
--    監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、
--    weight_change と record_gap の2行を返す。state は
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
  -- ===== 定数（閾値・窓の長さ・日数はここ1箇所。根拠は計画書「検知ルールの仕様」）=====
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
    FROM g_eval ge;
END;
$$;

COMMENT ON FUNCTION public.evaluate_client_alerts(date, timestamptz) IS
  '異常検知の評価（読み取り専用。dry run とバックテストを兼ねる）。'
  '監視対象（client_activity_snapshot の exclusion_reason IS NULL）の顧客ごとに、'
  'weight_change と record_gap の2行 (client_id, trainer_id, alert_type, state, severity, payload) を返す。'
  'state: detected / cleared / unknown（評価できない・成立値と解消値の間。状態を変えない）。'
  'severity は detected のときだけ。p_target_date は JST の暦日（既定は JST の今日）、'
  'p_as_of は締め時刻（既定は LEAST(now(), D+1 の JST 0:00)。D の JST 0:00 より前・now() より後は例外）。'
  '閾値・窓・日数の定数は関数の冒頭1箇所にある。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「検知ルールの仕様」';

REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.evaluate_client_alerts(date, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_client_alerts(date, timestamptz) TO service_role;

-- -----------------------------------------------------------------------------
-- 2. run_client_alert_detection(p_target_date)
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
                                              AND e.payload->>'variant' = 'no_record'))),
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
  'detected.weight_change / detected.record_gap.{not_started,no_data,no_record} / '
  'opened（新規）/ updated（継続した行すべて。escalated・reopened を含む）/ '
  'escalated（open のまま重大度が上がり surfaced_on を更新）/ reopened（対応済みから再浮上）/ '
  'resolved.{cleared,expired,reassigned,ineligible}（expired は 14 日再確認されない weight_change と、'
  '顧客が not_started / inactive になった record_gap。ineligible は no_account / self / snapshot に居ない顧客）/ '
  'severity_lowered（diet の減少で medium に下げた検知数）。'
  '件数だけで client_id や健康に関する値は入れない。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「状態遷移」「冪等性とガード」';

REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM anon;
REVOKE ALL ON FUNCTION public.run_client_alert_detection(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.run_client_alert_detection(date) TO service_role;

-- -----------------------------------------------------------------------------
-- 3. get_alert_detection_status()
--    Web の「今日の対応」の検知状態と対象外の人数（契約: 計画書「RPC get_alert_detection_status()」）。
--      enabled              : cron ジョブ detect-client-alerts の active（ジョブが無ければ false）
--      last_succeeded_at    : 最後に成功した本実行の finished_at（無ければ NULL = 未実行）
--      last_target_date     : その本実行の対象日
--      monitored_count / excluded_no_account / excluded_not_started / excluded_inactive:
--        呼び出したトレーナー（auth.uid()）の担当顧客だけを、表示した時点
--        （client_activity_snapshot(JST の今日, now(), auth.uid())）で数える。
--        06:00 時点の値ではない。自己登録（self）はどれにも数えない。全トレーナー合算の
--        runs.stats からは出さない
--    呼び出したのがトレーナー（trainers に行がある）でなければ 0 行。
--    引数でトレーナー ID を受け取らず、戻り列は許可リストで固定する。
--
--    SECURITY DEFINER の理由: client_activity_snapshot（service_role 専用）・auth.users・
--    alert_detection_runs・cron.job を定義者（postgres）の権限で読むため。
--    返すのは auth.uid() 本人の担当顧客の人数と、全体で1つの検知状態だけ
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_alert_detection_status()
RETURNS TABLE (
  enabled boolean,
  last_succeeded_at timestamptz,
  last_target_date date,
  monitored_count integer,
  excluded_no_account integer,
  excluded_not_started integer,
  excluded_inactive integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    coalesce(
      (SELECT bool_or(j.active) FROM cron.job j WHERE j.jobname = 'detect-client-alerts'),
      false
    ),
    lr.finished_at,
    lr.target_date,
    pop.monitored,
    pop.no_account,
    pop.not_started,
    pop.inactive
  FROM public.trainers t
  CROSS JOIN LATERAL (
    SELECT
      (count(*) FILTER (WHERE s.exclusion_reason IS NULL))::integer          AS monitored,
      (count(*) FILTER (WHERE s.exclusion_reason = 'no_account'))::integer  AS no_account,
      (count(*) FILTER (WHERE s.exclusion_reason = 'not_started'))::integer AS not_started,
      (count(*) FILTER (WHERE s.exclusion_reason = 'inactive'))::integer    AS inactive
    FROM public.client_activity_snapshot(
      (now() AT TIME ZONE 'Asia/Tokyo')::date, now(), t.id) AS s
  ) pop
  LEFT JOIN LATERAL (
    SELECT r.finished_at, r.target_date
      FROM public.alert_detection_runs r
     ORDER BY r.finished_at DESC
     LIMIT 1
  ) lr ON true
  WHERE t.id = auth.uid();
$$;

COMMENT ON FUNCTION public.get_alert_detection_status() IS
  '呼び出したトレーナー（auth.uid()）向けの検知状態: enabled（cron detect-client-alerts の active）/ '
  'last_succeeded_at・last_target_date（alert_detection_runs の最新行）/ '
  'monitored_count・excluded_no_account・excluded_not_started・excluded_inactive'
  '（担当顧客を表示した時点の client_activity_snapshot で数える。自己登録は数えない）。'
  'トレーナーでなければ 0 行。Web のダッシュボード「今日の対応」が RPC で呼ぶ。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「契約」';

-- EXECUTE を authenticated のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon へも EXECUTE が付与されるため明示的に剥がす）
REVOKE ALL ON FUNCTION public.get_alert_detection_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_alert_detection_status() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_alert_detection_status() TO authenticated;

-- -----------------------------------------------------------------------------
-- 4. cron ジョブ 'detect-client-alerts' の新規登録（無効状態）
--    毎日 21:00 UTC（= 翌日 06:00 JST。pg_cron は UTC 基準）に、JST の今日を対象日として
--    本実行を呼ぶ。SQL を直接実行するので HTTP・Vault・pg_net・apikey・タイムアウトの設定は要らない
--    （issue-recurring-tickets と同じ形。20260710020000 参照）。
--    例外は cron.job_run_details に failed として残る。
--
--    ※ 意図的に「無効(inactive)」で登録する。有効化はリモートで evaluate の dry run と
--      30日バックテストをした後のオーナー判断とする。
--      有効化手順: docs/tasks/2026-07-10-cron-vault-setup.md「detect-client-alerts」
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付き
--      ドル引用 $cmd$ 〜 $cmd$ で記述している。
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'detect-client-alerts') THEN
    PERFORM cron.schedule(
      'detect-client-alerts',
      '0 21 * * *',
      $cmd$SELECT public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);$cmd$
    );

    -- 作成直後に無効化（上記コメントの通り、有効化はオーナー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'detect-client-alerts'),
      active := false
    );
  END IF;
END $$;
