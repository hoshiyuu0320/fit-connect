/**
 * 「今日の対応」の優先度スコアと並び順（純関数）。
 *
 * 式（計画書「契約 > スコア triageScore」。カタログ 2-A の初期式に上限を付けたもの）:
 *   min(未返信の時間, 72) × 2
 *   + open のアラート1件ごとに high 30 / medium 10
 *   + open の record_gap の日数（上限14）× 5
 * - 期日×達成率の +20 は入れない（calculate_achievement_rate を使わない。拡張で検討）
 * - acknowledged / resolved のアラートは点に入れない
 * - スコアは並べるためだけに使い、画面には出さない（見かけの精度を持たせない）
 * - 同点のときは、未返信が古い順 → 最初の検知日が古い順 → 名前 → 顧客 ID（安定させるため）
 * - 重みはここに定数で置き、テストで固定する（migration なしで調整できる。設計判断14）
 * - 未返信の時間は表示時点の now から数える。now は引数で受ける（テストで固定できるように）
 * - サーバーからも import されうるので、React や 'use client' に依存させない
 */

import { describeAlert, normalizeSeverity, toJstDateOnly } from '@/lib/alerts/describeAlert'
import type { AlertSeverity } from '@/types/alert'

export type TriageScoreWeights = {
  /** 未返信1時間あたりの点 */
  unrepliedPointsPerHour: number
  /** 未返信の時間の上限（これより長く待たせても点は増えない） */
  unrepliedMaxHours: number
  /** open のアラート1件の点（重要度別） */
  alertSeverityPoints: Readonly<Record<AlertSeverity, number>>
  /** open の record_gap の途絶1日あたりの点 */
  recordGapPointsPerDay: number
  /** 途絶の日数の上限（これより長く途切れても点は増えない） */
  recordGapMaxDays: number
}

export const TRIAGE_SCORE_WEIGHTS: Readonly<TriageScoreWeights> = {
  unrepliedPointsPerHour: 2,
  unrepliedMaxHours: 72,
  // low は将来用（PR1・PR2 では作られない）で、計画の式に無いので点を付けない。
  // 未知の重要度は normalizeSeverity で medium に丸める（表示と同じ扱い）
  alertSeverityPoints: { high: 30, medium: 10, low: 0 },
  recordGapPointsPerDay: 5,
  recordGapMaxDays: 14,
}

const HOUR_MS = 60 * 60 * 1000

// ---------------------------------------------------------------------------
// スコア
// ---------------------------------------------------------------------------

/**
 * 未返信の時間（時間単位で切り捨て、0以上）。since・now が読めなければ 0。
 * 切り捨てにするのは、表示の「未返信 18時間」と揃え、スコアを整数に保つため
 * （同点の判定が浮動小数の誤差に左右されない）。端末の時計が遅れていて since が未来でも負にしない。
 */
export function unrepliedElapsedHours(since: string, now: Date): number {
  const sinceMs = Date.parse(since)
  const nowMs = now.getTime()
  if (Number.isNaN(sinceMs) || Number.isNaN(nowMs)) return 0
  return Math.max(0, Math.floor((nowMs - sinceMs) / HOUR_MS))
}

/** スコアに入れるアラート。DB の値（ClientAlert）をそのまま渡せるよう、型は緩く受ける */
export type TriageScoreAlert = {
  alert_type: string
  severity: string
  status: string
  payload: unknown
}

export type TriageScoreInput = {
  /** 顧客のアラート（open 以外が混ざっていても点に入れない） */
  alerts: readonly TriageScoreAlert[]
  /**
   * 未返信。未返信が無ければ null。
   * since は未返信のうち最も古いメッセージの送信時刻（ISO）、now は表示時点
   */
  unreplied: { since: string; now: Date } | null
}

/** アラート1件の点。open でなければ 0。record_gap は途絶の日数（上限あり）の分を足す */
export function alertScore(alert: TriageScoreAlert): number {
  if (alert.status !== 'open') return 0
  const w = TRIAGE_SCORE_WEIGHTS
  const severityPoints = w.alertSeverityPoints[normalizeSeverity(alert.severity)]
  if (alert.alert_type !== 'record_gap') return severityPoints
  // 日数（gap_to − gap_from + 1）の定義は describeAlert に一本化する。payload が壊れていれば 0 日
  const days = describeAlert(alert).gapDays ?? 0
  return severityPoints + Math.min(days, w.recordGapMaxDays) * w.recordGapPointsPerDay
}

/** 未返信の点 */
export function unrepliedScore(elapsedHours: number): number {
  const w = TRIAGE_SCORE_WEIGHTS
  return Math.min(Math.max(0, elapsedHours), w.unrepliedMaxHours) * w.unrepliedPointsPerHour
}

/** 顧客1人の優先度スコア */
export function triageScore(input: TriageScoreInput): number {
  const unreplied =
    input.unreplied === null
      ? 0
      : unrepliedScore(unrepliedElapsedHours(input.unreplied.since, input.unreplied.now))
  return input.alerts.reduce((sum, alert) => sum + alertScore(alert), unreplied)
}

// ---------------------------------------------------------------------------
// 並び順
// ---------------------------------------------------------------------------

/** 並び順に使う値（行1つ分） */
export type TriageSortKey = {
  score: number
  /** 未返信のうち最も古いメッセージの送信時刻（ISO）。未返信が無ければ null */
  unrepliedSince: string | null
  /** open のアラートのうち最も古い first_detected_on（JST の暦日）。アラートが無ければ null */
  firstDetectedOn: string | null
  clientName: string
  clientId: string
}

function compareAsc(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

/** 古い順。値が無い（null・読めない）方を後ろにする */
function compareOldestFirst<T>(a: T | null, b: T | null, compare: (x: T, y: T) => number): number {
  if (a === null || b === null) return a === b ? 0 : a === null ? 1 : -1
  return compare(a, b)
}

function toTime(value: string | null): number | null {
  if (value === null) return null
  const ms = Date.parse(value)
  return Number.isNaN(ms) ? null : ms
}

/**
 * スコアの高い順 → 未返信が古い順 → 最初の検知日が古い順 → 名前 → 顧客 ID。
 * 未返信・アラートが無い行は、その段では後ろに回す。
 * 未返信の時刻は文字列でなく時刻で比べる（タイムゾーンの表記が違っても順序を誤らない）
 */
export function compareTriagePriority(a: TriageSortKey, b: TriageSortKey): number {
  return (
    b.score - a.score ||
    compareOldestFirst(toTime(a.unrepliedSince), toTime(b.unrepliedSince), (x, y) => x - y) ||
    compareOldestFirst(toJstDateOnly(a.firstDetectedOn), toJstDateOnly(b.firstDetectedOn), compareAsc) ||
    a.clientName.localeCompare(b.clientName, 'ja') ||
    compareAsc(a.clientId, b.clientId)
  )
}
