-- =============================================================================
-- Migration: client_activity_snapshot
-- フェーズ9.1（トレーナー介入 / 異常検知 MVP）その2: 顧客ごとの「活動」「記録」「監視対象」を
-- 1箇所で定義する関数 client_activity_snapshot を追加する
--
-- 仕様出典: docs/tasks/2026-09-13-trainer-intervention-plan.md
--   「検知ルールの仕様 > 共通」「② 記録途絶」「関数」「オーナー決定（2026-09-13）(1)(2)」
--
-- 背景（横断レビュー 1-7）:
--   - データはアプリが前面にあるときしか届かない（HealthKit 同期は起動時・復帰時・60分タイマー・
--     手動の4つ）。「最後にアプリを起動した時刻」の列は無く、device_tokens.last_seen_at は
--     端末の時計でコールドスタート時にしか書かれない
--   - そこで「計測の途絶」と「アプリからデータが届いていない」を分けるために、サーバー時刻で
--     残る痕跡だけを集めて「最終到着日 R」を作り、計測日の「最終記録日 L」と分けて返す
--
-- 返す列（顧客ごとに1行）:
--   client_id / trainer_id / join_on（登録日 J = clients.created_at の JST 日付）/ purpose /
--   last_activity_on（R）/ last_record_on（L）/ exclusion_reason
--
-- 定義:
--   - R = p_as_of 以前のサーバー時刻の痕跡のうち最も新しいものの JST 日付（下の COMMENT に一覧）。
--     R は「アプリがデータを届けた時刻」なので、記録テーブルの行は到着時刻（created_at。NULL の古い行は
--     recorded_at。weight / sleep は updated_at も）だけで判定し、計測時刻は見ない（計測が p_as_of より
--     後の行でも、p_as_of までに届いていれば数える）。HealthKit の体重は計測日の 23:59 JST で入るので、
--     計測時刻でも絞ると、D の 05:00 に同期された D の体重が 06:00 の締め時刻では数えられず、体重だけ
--     連携している顧客が同期済みなのに「記録・同期なし」（no_data）になる
--   - L = 計測日が D−1 以前で、到着が p_as_of 以前の記録のうち最も新しい JST 日付（全期間）。
--     記録には顧客が送ったメッセージ（タグの有無は問わない）も含める。1件も無ければ NULL
--   - exclusion_reason（上から順に1つ。NULL = 監視対象）
--       1. no_account : auth.users に行が無い（旧フローの顧客。ログインできない）
--       2. self       : client_id = trainer_id（トレーナーの自己登録。人数にも数えない）
--       3. not_started: 記録が一度も無く（L IS NULL）、D − J > 14（オーナー決定 (1):
--                       記録開始前は登録から 14 日以内だけ出し、それ以外は人数だけ）
--       4. inactive   : R < D − 14（2週間以上データなし）
--       5. どれでもなければ NULL
--     生きている record_gap アラートがあっても監視は延ばさない（オーナー決定 (1)。未開始は登録から
--     最大 14 日、記録・同期なしは最終到着から最大 13 日で打ち切る）。対象外になった顧客の record_gap は
--     run_client_alert_detection が resolved（expired）で閉じ、以後は理由別の人数だけに数える。
--     監視対象は alerts に依らないので、evaluate_client_alerts のバックテストは本実行の前後どちらで取っても同じ
--   - p_as_of より後に登録された顧客は返さない（その時点ではまだ存在しないため。
--     過去の日で evaluate_client_alerts を流すバックテストで効く）
--   - 登録日が有限でない（±infinity）顧客も返さない。clients は顧客本人が全列を UPDATE できる
--     （clients_update_own）ので、'-infinity' にされると日付の引き算が例外（22008）になり、全顧客を
--     1トランザクションで処理する本実行が毎日落ちる。その顧客の生きているアラートは本実行が
--     resolved（ineligible）で閉じる
--
-- JST の暦日の扱い（lessons「JST の『暦日』判定は範囲比較で書く」）:
--   - 列には関数を掛けず、`date::timestamp AT TIME ZONE 'Asia/Tokyo'`（その日の JST 0:00 の
--     timestamptz）との範囲比較で絞る。日付への変換は絞った後の SELECT の中だけで行う
--   - CURRENT_DATE（UTC の日付）は使わない。sleep_records は recorded_date（JST の起床日）をそのまま使う
--
-- 性能:
--   - 顧客ごとの相関サブクエリはすべて既存の複合索引で引ける（新しい索引は不要。
--     記録4表 (client_id, recorded_at DESC) / sleep (client_id, recorded_date DESC) /
--     messages (sender_id, created_at DESC)・(receiver_id, created_at DESC) /
--     ai_estimation_logs (client_id, created_at DESC)）
--   - R の記録テーブルは計測時刻で D−60 以降に絞ってから最大値を取る（索引を効かせるための下限だけで、
--     上限は掛けない）。14 日以内に届いた行は計測がそれより最大 30 日前まで（HealthKit の初回連携の
--     読み直し幅）なので漏れない
--
-- 冪等性: CREATE OR REPLACE と REVOKE / GRANT / COMMENT のため、何度実行しても同じ状態になる
-- =============================================================================

CREATE OR REPLACE FUNCTION public.client_activity_snapshot(
  p_target_date date,
  p_as_of timestamptz,
  p_trainer_id uuid DEFAULT NULL
)
RETURNS TABLE (
  client_id uuid,
  trainer_id uuid,
  join_on date,
  purpose text,
  last_activity_on date,
  last_record_on date,
  exclusion_reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH p AS (
    SELECT
      -- D の JST 0:00（L はこれより前に計測されたものだけ = 計測日が D−1 以前）
      (p_target_date::timestamp AT TIME ZONE 'Asia/Tokyo')        AS d0,
      -- R の記録テーブルを計測時刻で絞る下限（D−60 の JST 0:00。索引用で、R に計測時刻の上限は無い）
      ((p_target_date - 60)::timestamp AT TIME ZONE 'Asia/Tokyo') AS scan_from,
      p_target_date - 60                                          AS scan_from_on,
      -- 締め時刻の JST 日付（L で、sleep の recorded_date（日付）が締め時刻以前かをこれで見る）
      (p_as_of AT TIME ZONE 'Asia/Tokyo')::date                   AS as_of_on
  ),
  -- MATERIALIZED: 下の CASE でも R・L を参照するので、インライン展開されると顧客ごとの
  -- 相関サブクエリが2回ずつ計画・実行される（EXPLAIN で確認）。1回で済むよう先に確定させる
  base AS MATERIALIZED (
    SELECT
      c.client_id,
      c.trainer_id,
      c.purpose,
      (c.created_at AT TIME ZONE 'Asia/Tokyo')::date AS join_on,
      EXISTS (
        SELECT 1 FROM auth.users u WHERE u.id = c.client_id
      ) AS has_account,
      -- ---- R: サーバー時刻で残る活動の痕跡（どれも p_as_of 以前だけ）----
      -- 記録テーブル（体重・食事・運動・睡眠）は到着時刻だけで判定する（created_at。NULL の古い行は
      -- recorded_at。weight / sleep は updated_at も p_as_of 以前のものだけ）。計測時刻には p_as_of の
      -- 上限を掛けない（HealthKit の体重は計測日の 23:59 JST で入る。上のヘッダ参照）。計測時刻の
      -- D−60 の下限は、複合索引 (client_id, recorded_at / recorded_date DESC) で引くためのもの
      (GREATEST(
        -- 登録
        c.created_at,
        -- 顧客が送ったメッセージ（兼務アカウントがトレーナーとして送った分は sender_type で除く）
        (SELECT max(m.created_at)
           FROM public.messages m
          WHERE m.sender_id = c.client_id
            AND m.sender_type = 'client'
            AND m.created_at <= p_as_of),
        -- 顧客宛てメッセージの既読（Mobile の mark_messages_as_read が now() で書く分。
        -- Web の既読はブラウザの時計で receiver_type = 'trainer' の行に書くので除かれる）。
        -- 今の担当トレーナーが送った分だけを数える: messages の INSERT ポリシーは sender_id = auth.uid()
        -- だけで、送信者が receiver_id と read_at を自由に書けるため、担当関係の無い第三者や前の担当が
        -- 既読を偽造して R を動かせないようにする
        (SELECT max(m.read_at)
           FROM public.messages m
          WHERE m.receiver_id = c.client_id
            AND m.receiver_type = 'client'
            AND m.sender_id = c.trainer_id
            AND m.sender_type = 'trainer'
            AND m.read_at <= p_as_of),
        -- 体重: 到着（created_at。NULL の古い行は recorded_at）と、HealthKit の再同期で動く updated_at
        (SELECT max(GREATEST(
                  coalesce(w.created_at, w.recorded_at),
                  CASE WHEN w.updated_at <= p_as_of THEN w.updated_at END))
           FROM public.weight_records w
          WHERE w.client_id = c.client_id
            AND w.recorded_at >= p.scan_from
            AND coalesce(w.created_at, w.recorded_at) <= p_as_of),
        -- 食事: 到着（created_at。NULL の古い行は recorded_at）
        (SELECT max(coalesce(ml.created_at, ml.recorded_at))
           FROM public.meal_records ml
          WHERE ml.client_id = c.client_id
            AND ml.recorded_at >= p.scan_from
            AND coalesce(ml.created_at, ml.recorded_at) <= p_as_of),
        -- 運動: 到着（created_at。NULL の古い行は recorded_at）
        (SELECT max(coalesce(ex.created_at, ex.recorded_at))
           FROM public.exercise_records ex
          WHERE ex.client_id = c.client_id
            AND ex.recorded_at >= p.scan_from
            AND coalesce(ex.created_at, ex.recorded_at) <= p_as_of),
        -- 睡眠: 到着（created_at）と、同期のたびの upsert で動く updated_at
        (SELECT max(GREATEST(
                  s.created_at,
                  CASE WHEN s.updated_at <= p_as_of THEN s.updated_at END))
           FROM public.sleep_records s
          WHERE s.client_id = c.client_id
            AND s.recorded_date >= p.scan_from_on
            AND s.created_at <= p_as_of),
        -- AI 推定（顧客がアプリから呼ぶ）
        (SELECT max(l.created_at)
           FROM public.ai_estimation_logs l
          WHERE l.client_id = c.client_id
            AND l.created_at <= p_as_of)
      ) AT TIME ZONE 'Asia/Tokyo')::date AS last_activity_on,
      -- ---- L: 計測日が D−1 以前で、到着が p_as_of 以前の記録の最新の JST 日付（全期間）----
      -- 計測日時は顧客が書ける値なので、'-infinity' の行は記録に数えない（isfinite。L が
      -- '-infinity' になると「記録開始済み」扱いになり、payload にも無効な日付が入る）
      GREATEST(
        (SELECT (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
           FROM public.weight_records w
          WHERE w.client_id = c.client_id
            AND w.recorded_at < p.d0
            AND w.recorded_at <= p_as_of
            AND isfinite(w.recorded_at)
            AND coalesce(w.created_at, w.recorded_at) <= p_as_of
          ORDER BY w.recorded_at DESC
          LIMIT 1),
        (SELECT (ml.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
           FROM public.meal_records ml
          WHERE ml.client_id = c.client_id
            AND ml.recorded_at < p.d0
            AND ml.recorded_at <= p_as_of
            AND isfinite(ml.recorded_at)
            AND coalesce(ml.created_at, ml.recorded_at) <= p_as_of
          ORDER BY ml.recorded_at DESC
          LIMIT 1),
        (SELECT (ex.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
           FROM public.exercise_records ex
          WHERE ex.client_id = c.client_id
            AND ex.recorded_at < p.d0
            AND ex.recorded_at <= p_as_of
            AND isfinite(ex.recorded_at)
            AND coalesce(ex.created_at, ex.recorded_at) <= p_as_of
          ORDER BY ex.recorded_at DESC
          LIMIT 1),
        (SELECT s.recorded_date
           FROM public.sleep_records s
          WHERE s.client_id = c.client_id
            AND s.recorded_date < p_target_date
            AND s.recorded_date <= p.as_of_on
            AND isfinite(s.recorded_date)
            AND s.created_at <= p_as_of
          ORDER BY s.recorded_date DESC
          LIMIT 1),
        -- 顧客が送ったメッセージも記録に含める（カタログ「全記録種別＋メッセージ」）
        (SELECT (m.created_at AT TIME ZONE 'Asia/Tokyo')::date
           FROM public.messages m
          WHERE m.sender_id = c.client_id
            AND m.sender_type = 'client'
            AND m.created_at < p.d0
            AND m.created_at <= p_as_of
            AND isfinite(m.created_at)
          ORDER BY m.created_at DESC
          LIMIT 1)
      ) AS last_record_on
    FROM public.clients c
    CROSS JOIN p
    WHERE (p_trainer_id IS NULL OR c.trainer_id = p_trainer_id)
      AND c.created_at <= p_as_of
      -- 登録日が ±infinity の顧客は返さない（'infinity' は上の条件でも落ちる。上のヘッダ参照）
      AND isfinite(c.created_at)
  )
  SELECT
    b.client_id,
    b.trainer_id,
    b.join_on,
    b.purpose,
    b.last_activity_on,
    b.last_record_on,
    CASE
      WHEN NOT b.has_account                                           THEN 'no_account'
      WHEN b.client_id = b.trainer_id                                  THEN 'self'
      WHEN b.last_record_on IS NULL AND p_target_date - b.join_on > 14 THEN 'not_started'
      WHEN b.last_activity_on < p_target_date - 14                     THEN 'inactive'
      ELSE NULL
    END AS exclusion_reason
  FROM base b;
$$;

COMMENT ON FUNCTION public.client_activity_snapshot(date, timestamptz, uuid) IS
  '顧客ごとの登録日 J・最終到着日 R（last_activity_on）・最終記録日 L（last_record_on）・'
  '監視対象かどうか（exclusion_reason。NULL = 監視対象 / no_account / self / not_started / inactive）を返す。'
  '「活動」「記録」「監視対象」の定義はこの関数1箇所にある（evaluate_client_alerts・'
  'run_client_alert_detection・get_alert_detection_status が使う）。'
  '監視対象は alerts に依らない（生きている record_gap があっても監視は延ばさない。オーナー決定 (1)）。'
  '登録日が締め時刻より後・有限でない顧客は返さない。'
  '活動の痕跡（サーバー時刻・p_as_of 以前だけ）: 登録（clients.created_at）/ '
  '顧客が送ったメッセージの created_at（sender_type = client）/ '
  '今の担当トレーナーが送った顧客宛てメッセージの read_at（receiver_type = client。Mobile が now() で書く分。'
  '送信者は read_at を自由に書けるので、担当関係の無い送信者の既読は数えない）/ '
  'weight・meal・exercise・sleep の created_at（NULL の古い行は recorded_at）/ '
  'weight と sleep の updated_at / ai_estimation_logs.created_at。'
  'R は到着時刻だけで決まる: 記録テーブルの行は到着（created_at / updated_at）が p_as_of 以前なら、'
  '計測時刻が p_as_of より後でも数える（HealthKit の体重は計測日の 23:59 JST で入るため。'
  '計測時刻には索引用の D−60 の下限だけを掛ける）。'
  'L は計測日が D−1 以前かつ到着が p_as_of 以前の記録（と顧客が送ったメッセージ）だけ。'
  '端末の時計で書かれる値（workout の finished_at、device_tokens.last_seen_at）と Web の既読は使わない。'
  '依存関係: 睡眠の updated_at を同期の代わりに使えるのは、Mobile の upsert が同期のたびに'
  '約30行を更新し set_updated_at（BEFORE UPDATE）トリガーが updated_at を動かすから。'
  'weight / sleep を一括 UPDATE する migration を流すと全員が「同期あり」に見えるので、'
  'set_updated_at を一時的に無効にするか、前後で検知を止めること'
  '（docs/tasks/2026-07-10-cron-vault-setup.md「detect-client-alerts」）。'
  'authenticated へ GRANT しない（p_trainer_id に他人の ID を渡せ、auth.users も読むため）。'
  '公開するときは auth.uid() を固定したラッパーを作り、そちらだけを GRANT する'
  '（get_alert_detection_status と同じ形）。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「検知ルールの仕様」';

-- EXECUTE を service_role のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon / authenticated へ EXECUTE が付与されるため明示的に剥がす）。
-- evaluate_client_alerts などの DEFINER 関数からは所有者（postgres）の権限で呼ばれる
REVOKE ALL ON FUNCTION public.client_activity_snapshot(date, timestamptz, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.client_activity_snapshot(date, timestamptz, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.client_activity_snapshot(date, timestamptz, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.client_activity_snapshot(date, timestamptz, uuid) TO service_role;
