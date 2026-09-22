/**
 * フェーズ9.1 自動チェック（public.alerts / get_alert_detection_status）の型。
 *
 * - 既存 components/dashboard/AlertItem.tsx の AlertType（チケット・プランの表示用）とは別物。
 *   名前が衝突しないよう、こちらは ClientAlertType とする
 * - payload は判定時点の値・閾値・期間・変種だけを持つ（表示用の文字列は持たない）。
 *   文言は lib/alerts/describeAlert.ts が payload から組み立てる
 * - 日付はすべて JST の暦日 'YYYY-MM-DD'。payload は時刻を持たない（オーナー決定 2026-09-13 (2)）
 */

/** alerts.alert_type（CHECK と一致させる。種別を増やすときは migration と同時に足す） */
export type ClientAlertType = 'weight_change' | 'record_gap'

/** alerts.severity（low は将来用で、PR1 では作られない） */
export type AlertSeverity = 'high' | 'medium' | 'low'

/** alerts.status（resolved は終端。「今日の対応」に出るのは open だけ） */
export type AlertStatus = 'open' | 'acknowledged' | 'resolved'

// ---------------------------------------------------------------------------
// payload（v でバージョンを持つ。PR1 は v:1 だけ）
// ---------------------------------------------------------------------------

/** 体重の比較窓（直近7日 / その前の7日） */
export type WeightChangeWindow = {
  from: string
  to: string
  /** 窓の中の日ごとの代表値（中央値）の平均 */
  avg_kg: number
  /** 代表値がある日数（3日以上のときだけ評価する） */
  days: number
}

/** ① 体重急変 */
export type WeightChangePayload = {
  v: 1
  direction: 'increase' | 'decrease'
  recent: WeightChangeWindow
  previous: WeightChangeWindow
  /** 直近の窓の平均 − 前の窓の平均 */
  delta_kg: number
  /** delta_kg ÷ 前の窓の平均 × 100 */
  delta_pct: number
  threshold: { pct: number; kg: number }
  /** 減量目的（purpose='diet'）の減少で medium に下げたときだけ入る */
  severity_reason?: 'diet_decrease'
}

/** ② 記録途絶の変種（上から1つだけ当てる） */
export type RecordGapVariant = 'not_started' | 'no_data' | 'no_record'

type RecordGapPayloadBase = {
  v: 1
  /** 途絶の初日。日数は gap_to − gap_from + 1 で表示時に出す（今日の日付に依らない） */
  gap_from: string
  /** 途絶の最終日 */
  gap_to: string
  /** 最終到着日 R（サーバー時刻の痕跡の JST 日付。登録日を含む） */
  last_activity_on: string
  threshold_days: number
}

/** 一度も記録が無い（gap_from = 登録日） */
export type RecordGapNotStartedPayload = RecordGapPayloadBase & {
  variant: 'not_started'
  last_record_on: null
}

/** 到着（記録・同期）が threshold_days 日以上無い（gap_from = R + 1） */
export type RecordGapNoDataPayload = RecordGapPayloadBase & {
  variant: 'no_data'
  last_record_on: string
}

/** 到着はあるのに記録が threshold_days 日以上無い（gap_to = min(R, 対象日) − 1） */
export type RecordGapNoRecordPayload = RecordGapPayloadBase & {
  variant: 'no_record'
  last_record_on: string
}

export type RecordGapPayload =
  | RecordGapNotStartedPayload
  | RecordGapNoDataPayload
  | RecordGapNoRecordPayload

export type ClientAlertPayload = WeightChangePayload | RecordGapPayload

// ---------------------------------------------------------------------------
// 行・RPC・API
// ---------------------------------------------------------------------------

/**
 * getOpenAlerts が返すアラート（alerts の行 + 顧客の表示用の列）。
 * payload は DB の jsonb をそのまま持つ（型は信用せず、describeAlert が実行時に確かめる）。
 */
export type ClientAlert = {
  id: string
  client_id: string
  alert_type: ClientAlertType
  severity: AlertSeverity
  status: AlertStatus
  payload: unknown
  /** この発生を最初に検知した対象日 */
  first_detected_on: string
  /** open になった日（新規・再浮上）か、open のまま重大度が上がった日 */
  surfaced_on: string
  /** 条件の成立を最後に確かめた対象日 */
  last_detected_on: string
  acknowledged_at: string | null
  reopened_count: number
  client_name: string
  client_profile_image_url: string | null
}

/** RPC get_alert_detection_status() の1行（人数は呼び出したトレーナーの担当顧客だけ・表示した時点の数） */
export type AlertDetectionStatus = {
  /** cron detect-client-alerts が active か */
  enabled: boolean
  /** 最後に成功した本実行の時刻（alert_detection_runs の最新行。ISO）。未実行なら null */
  last_succeeded_at: string | null
  /** 最後に成功した本実行の対象日（JST） */
  last_target_date: string | null
  monitored_count: number
  excluded_no_account: number
  excluded_not_started: number
  excluded_inactive: number
}

/** PATCH /api/alerts/[id] の body.action */
export type AlertPatchAction = 'acknowledge' | 'reopen'

/** PATCH /api/alerts/[id] の成功レスポンス（条件に合わず更新0行でも、今の status を 200 で返す） */
export type AlertPatchResponse = {
  status: 'ok'
  alert: { id: string; status: AlertStatus }
}
