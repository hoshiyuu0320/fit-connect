-- =============================================================================
-- Migration: client_alerts
-- フェーズ9.1（トレーナー介入 / 異常検知 MVP）その1: アラートの保存先 alerts と、
-- 検知の本実行の記録 alert_detection_runs を新設する
--
-- 仕様出典: docs/tasks/2026-09-13-trainer-intervention-plan.md
--   「データモデル」「検知ルールの仕様 > 状態遷移」「オーナー決定（2026-09-13）」
--   （カタログ 2026-07-08-solution-catalog.md cat1 1-A と食い違う箇所は統合判断・計画書に従う）
--
-- 背景:
--   - 今のダッシュボードの「N日間記録なし」はクライアント側で組み立てており、アプリ未登録の
--     旧顧客まで「999日」と出る。検知を DB 側に移し、1日1回（06:00 JST）の cron で
--     体重急変（weight_change）と記録途絶（record_gap）を判定して、結果をこの表に残す
--   - 判定・状態遷移は 20260914000100（client_activity_snapshot）と
--     20260914000200（evaluate / run / status 関数と cron）で行う。本 migration は表だけ
--
-- 方針:
--   1. 表示用の文字列（title / body）は持たない。判定時点の値・閾値・期間は payload に入れ、
--      文言は Web の純関数で作る（導出値を保存するとドリフトする。lessons 参照）
--   2. 生きている発生（resolved_at IS NULL）は顧客 × 種別で1件（部分ユニーク索引）。
--      open だけに掛けると、対応済みにした翌朝に同じアラートが作り直される
--   3. 読めるのは「検知した時点の担当トレーナー」かつ「今も担当しているトレーナー」だけ
--      （SELECT ポリシー1本）。顧客本人には見せない。書き込みは service_role（API Route）と
--      検知関数（SECURITY DEFINER）だけで、authenticated には SELECT しか GRANT しない
--   4. push 用の列は持たない（冪等化は notification_logs.dedup_key に統一する。統合判断1）。
--      後で push を足すときは surfaced_on で対象を選ぶ
--   5. alert_detection_runs は運用ログ。成功した本実行ごとに1行（失敗はトランザクションごと
--      巻き戻るので行が残らない）。stats は件数だけで、client_id や健康に関する値は入れない
--
-- 影響範囲:
--   - 既存の表・関数・ポリシーには触れない（新しい表を足すだけ）
--   - clients を DELETE すると alerts も CASCADE で消える（delete-account の退会処理と同じ流れ）
--   - Mobile は変更なし（トレーナー専用の表で、顧客からは読めない）
--
-- 冪等性: CREATE ... IF NOT EXISTS と DO ブロックの存在確認で書いており、何度実行しても
--   同じ状態に収束する（REVOKE / GRANT / COMMENT は再実行しても結果が変わらない）
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. alerts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES public.trainers(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
  alert_type text NOT NULL,
  severity text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  first_detected_on date NOT NULL,
  surfaced_on date NOT NULL,
  last_detected_on date NOT NULL,
  acknowledged_at timestamptz,
  reopened_count smallint NOT NULL DEFAULT 0,
  resolved_at timestamptz,
  resolved_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- 種別を増やすときは DROP CONSTRAINT → ADD CONSTRAINT で作り直し、既存の値を落とさない
  CONSTRAINT alerts_alert_type_check
    CHECK (alert_type IN ('weight_change', 'record_gap')),
  -- low は将来用（MVP の検知ルールは high / medium しか出さない）
  CONSTRAINT alerts_severity_check
    CHECK (severity IN ('high', 'medium', 'low')),
  CONSTRAINT alerts_status_check
    CHECK (status IN ('open', 'acknowledged', 'resolved')),
  CONSTRAINT alerts_resolved_reason_check
    CHECK (resolved_reason IS NULL
           OR resolved_reason IN ('cleared', 'expired', 'reassigned', 'ineligible')),
  -- resolved は終端。resolved_at / resolved_reason は resolved のときだけ入る
  CONSTRAINT alerts_resolved_at_consistency
    CHECK ((status = 'resolved') = (resolved_at IS NOT NULL)),
  CONSTRAINT alerts_resolved_reason_consistency
    CHECK ((resolved_at IS NULL) = (resolved_reason IS NULL)),
  CONSTRAINT alerts_acknowledged_at_consistency
    CHECK (status <> 'acknowledged' OR acknowledged_at IS NOT NULL),
  -- 対応済みからの再浮上は1回の発生につき最大1回（状態遷移 5）
  CONSTRAINT alerts_reopened_count_check
    CHECK (reopened_count BETWEEN 0 AND 1)
);

COMMENT ON TABLE public.alerts IS
  'トレーナー向けの異常検知アラート（フェーズ9.1）。1行 = 1回の発生。'
  '検知と状態遷移は run_client_alert_detection（cron detect-client-alerts、06:00 JST）が行い、'
  'トレーナーの操作（open ⇄ acknowledged）は API Route（PATCH /api/alerts/[id]、service_role）が'
  '条件付き UPDATE で行う。resolved は終端で、再発したら新しい行を作る。'
  '生きている発生（resolved_at IS NULL）は顧客 × 種別で1件（alerts_live_client_type_key）。'
  '表示用の文字列は持たず、payload から Web の純関数で文言を作る。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「データモデル」';

COMMENT ON COLUMN public.alerts.trainer_id IS
  '検知した時点の担当トレーナー。担当が替わると次の本実行で resolved（reassigned）になり、'
  '新しい担当の分は同じ実行の中で作り直される';
COMMENT ON COLUMN public.alerts.client_id IS
  '対象の顧客。clients の DELETE（退会 = delete-account）で CASCADE 削除される';
COMMENT ON COLUMN public.alerts.alert_type IS
  'weight_change（体重急変）/ record_gap（記録途絶）。'
  '種別を増やすときは CHECK を DROP → ADD し、既存の値を落とさない';
COMMENT ON COLUMN public.alerts.severity IS
  'high / medium / low（low は将来用）。体重急変は high（purpose=diet の減少だけ medium）、'
  '記録途絶は途絶日数 3〜6 日が medium、7 日以上が high';
COMMENT ON COLUMN public.alerts.status IS
  'open（未対応）/ acknowledged（対応済み。条件が続く間は作り直さない）/ resolved（終端）。'
  'open → acknowledged（対応済み）と acknowledged → open（元に戻す）はトレーナーの操作。'
  '重大度が上がると acknowledged でも1回だけ open に戻る（reopened_count）';
COMMENT ON COLUMN public.alerts.payload IS
  '判定時点の値・閾値・期間・変種（v でバージョンを持つ。日付だけで時刻は持たない）。'
  'weight_change: {v:1, direction, recent:{from,to,avg_kg,days}, previous:{from,to,avg_kg,days}, '
  'delta_kg, delta_pct, threshold:{pct,kg}, severity_reason?}。'
  'record_gap: {v:1, variant:not_started|no_data|no_record, gap_from, gap_to, '
  'last_activity_on, last_record_on, threshold_days}（日数は gap_to − gap_from + 1 で表示時に出す）。'
  '表示用の文字列は入れない';
COMMENT ON COLUMN public.alerts.first_detected_on IS
  'この発生を最初に検知した対象日（JST の暦日）';
COMMENT ON COLUMN public.alerts.surfaced_on IS
  'open になった日（新規・再浮上）か、open のまま重大度が上がった日（JST の暦日）。'
  '並び順と、後で push の対象を選ぶのに使う';
COMMENT ON COLUMN public.alerts.last_detected_on IS
  '条件の成立を最後に確かめた対象日（JST の暦日）。weight_change はこれが対象日の 14 日前以前に'
  'なると resolved（expired）';
COMMENT ON COLUMN public.alerts.acknowledged_at IS
  '「対応済み」にした時刻。status = acknowledged のときは必ず入る。元に戻す・再浮上で NULL に戻る';
COMMENT ON COLUMN public.alerts.reopened_count IS
  '対応済みから重大度の上昇で再浮上した回数。1回の発生につき最大 1';
COMMENT ON COLUMN public.alerts.resolved_at IS
  'resolved にした時刻。status = resolved のときだけ入る';
COMMENT ON COLUMN public.alerts.resolved_reason IS
  'cleared（条件が解消）/ expired（weight_change は 14 日間再確認されない。record_gap は顧客が'
  '監視対象外 = 登録から 14 日を過ぎた未開始・最終到着から 14 日超 になって監視を打ち切った）/ '
  'reassigned（担当替え）/ ineligible（アプリ未登録・自己登録になった、または登録日が不正で評価できない）';

-- 索引
--   - 生きている発生は顧客 × 種別で1件。検知関数の二重作成はここで unique_violation になり、
--     本実行全体がロールバックされる（cron.job_run_details に failed で残る）
--   - ダッシュボードとサイドバーのバッジ（担当トレーナーの open）用
--   - clients の DELETE の CASCADE 用（部分ユニーク索引は resolved の行を含まないため別に張る）
CREATE UNIQUE INDEX IF NOT EXISTS alerts_live_client_type_key
  ON public.alerts (client_id, alert_type)
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_alerts_trainer_open
  ON public.alerts (trainer_id)
  WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_alerts_client_id
  ON public.alerts (client_id);

-- updated_at 自動更新（既存の public.update_updated_at_column() を再利用。
-- 20251230131753_remote_schema.sql で定義済み・payments 等でも使用中）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'set_updated_at_alerts'
      AND tgrelid = 'public.alerts'::regclass
  ) THEN
    CREATE TRIGGER set_updated_at_alerts
      BEFORE UPDATE ON public.alerts
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- RLS: ポリシーは SELECT 1本だけ（INSERT / UPDATE / DELETE のポリシーは意図的に作らない
-- = authenticated からの書き込みは全て拒否。書き込みは RLS をバイパスする service_role と
-- 検知関数（SECURITY DEFINER、所有者 postgres）だけ）
--   - trainer_id = 本人: 検知した時点の担当トレーナーにだけ見せる
--   - EXISTS（今の担当）: 担当が替わったら、次の本実行で reassigned に閉じるのを待たずに
--     前のトレーナーから見えなくする
--   - サブクエリの列は必ずテーブル名（alerts.client_id）で修飾する。無修飾だと内側の
--     clients の列に解決される（lessons「storage.objects ポリシーのサブクエリ内で…」）。
--     解決先は pg_get_expr(polqual, polrelid) で確認する（supabase/tests/client_alerts_rls_test.sql）
--   - auth.uid() は (SELECT auth.uid()) で包み、行ごとではなく1回だけ評価させる
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'alerts'
      AND policyname = 'alerts_trainer_select'
  ) THEN
    CREATE POLICY "alerts_trainer_select"
      ON public.alerts
      FOR SELECT
      TO authenticated
      USING (
        alerts.trainer_id = (SELECT auth.uid())
        AND EXISTS (
          SELECT 1
            FROM public.clients c
           WHERE c.client_id = alerts.client_id
             AND c.trainer_id = (SELECT auth.uid())
        )
      );
  END IF;
END $$;

-- 権限（ALTER DEFAULT PRIVILEGES 対策）:
-- 20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により anon / authenticated へ
-- GRANT ALL が自動付与されるため、いったん全て剥がして authenticated に SELECT だけを戻す。
-- 顧客も authenticated だが、ポリシーが trainer_id = 本人 なので自分宛ての行は見えない。
-- service_role（API Route の supabaseAdmin）には書き込みが要るので明示的に付与する
REVOKE ALL ON public.alerts FROM anon, authenticated;
GRANT SELECT ON public.alerts TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.alerts TO service_role;

-- -----------------------------------------------------------------------------
-- 2. alert_detection_runs（運用ログ）
--    id は uuid（シーケンスを作らないので、シーケンスの権限を剥がす必要も無い）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.alert_detection_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_date date NOT NULL,
  as_of timestamptz NOT NULL,
  started_at timestamptz NOT NULL,
  finished_at timestamptz NOT NULL,
  stats jsonb NOT NULL
);

COMMENT ON TABLE public.alert_detection_runs IS
  '異常検知の本実行（run_client_alert_detection）の記録。成功した実行ごとに1行'
  '（失敗はトランザクションごと巻き戻るので行が残らない。失敗は cron.job_run_details で見る）。'
  '最新行は get_alert_detection_status の last_succeeded_at / last_target_date になり、'
  'max(target_date) は「古い対象日で新しい状態を上書きしない」ガードに使う。'
  'RLS 有効・ポリシー無し・anon / authenticated の権限無し（service_role と関数だけが読む）';

COMMENT ON COLUMN public.alert_detection_runs.target_date IS
  '対象日 D（JST の暦日）。評価の窓は D−1 で閉じる';
COMMENT ON COLUMN public.alert_detection_runs.as_of IS
  '締め時刻。これより後に届いたデータは見ない（本実行は LEAST(now(), D+1 の 0:00 JST)）';
COMMENT ON COLUMN public.alert_detection_runs.started_at IS
  '本実行を始めた時刻（clock_timestamp）';
COMMENT ON COLUMN public.alert_detection_runs.finished_at IS
  '本実行を終えた時刻（clock_timestamp）。Web の「最終チェック」はこの値';
COMMENT ON COLUMN public.alert_detection_runs.stats IS
  '件数だけのサマリー（監視数、対象外の理由別、種別・変種ごとの検知数、opened / updated / '
  'escalated / reopened、resolved の理由別、diet の減少で重大度を下げた数）。'
  'client_id や健康に関する値は入れない。キーの意味は run_client_alert_detection の COMMENT 参照';

-- 最新行（get_alert_detection_status）と max(target_date)（ガード）の取得用。
-- 1日1行なので件数は少ないが、読むたびに全件を並べ替えないようにする
CREATE INDEX IF NOT EXISTS idx_alert_detection_runs_finished_at
  ON public.alert_detection_runs (finished_at DESC);

CREATE INDEX IF NOT EXISTS idx_alert_detection_runs_target_date
  ON public.alert_detection_runs (target_date DESC);

-- RLS: 有効にしてポリシーは作らない（= anon / authenticated からは常に 0 行。
-- テーブル権限も剥がすので、実際には permission denied になる）
ALTER TABLE public.alert_detection_runs ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.alert_detection_runs FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.alert_detection_runs TO service_role;
