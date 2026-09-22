/**
 * 自動チェック（cron detect-client-alerts、06:00 JST）の検知状態の判定（純関数）。
 *
 * - RPC get_alert_detection_status() の1行から「停止中 / 未実行 / 遅延 / 最新」を決める
 * - 対象外の人数（理由別）の文言もここで作る
 * - サーバー（API Route）からも import されうるので、React や 'use client' に依存させない
 */

import { formatJstMonthDay } from '@/lib/alerts/describeAlert'
import type { AlertDetectionStatus } from '@/types/alert'

/**
 * 最後の成功からこの時間を超えたら「遅延」。
 * 実行は1日1回（24時間おき）なので、6時間の余裕を持たせる（06:00 の実行が 12:00 までに終わっていなければ遅延）。
 */
export const DETECTION_DELAY_HOURS = 30

const HOUR_MS = 60 * 60 * 1000
const JST_OFFSET_MS = 9 * HOUR_MS

/**
 * - paused: cron が inactive（止めている・まだ有効化していない）。実行記録の有無より優先する
 * - not_run: 本実行が一度も成功していない
 * - delayed: 最後の成功から DETECTION_DELAY_HOURS 時間を超えた
 * - fresh: それ以外
 */
export type DetectionStateKind = 'paused' | 'not_run' | 'delayed' | 'fresh'

export type DetectionState = {
  kind: DetectionStateKind
  /** 最後に成功した本実行の時刻（ISO）。未実行・解釈できないときは null */
  lastSucceededAt: string | null
  /** 最終チェック時刻の表示（JST「9/13 6:00」）。未実行なら null */
  lastCheckedLabel: string | null
}

/** ISO 日時を JST の「M/D H:mm」にする。解釈できなければ null */
export function formatJstMonthDayTime(value: string): string | null {
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return null
  const date = formatJstMonthDay(parsed.toISOString())
  const jst = new Date(parsed.getTime() + JST_OFFSET_MS)
  const minutes = String(jst.getUTCMinutes()).padStart(2, '0')
  return `${date} ${jst.getUTCHours()}:${minutes}`
}

/** 検知状態を判定する。now は画面を表示した時刻（テストで固定するため引数で受ける） */
export function evaluateDetectionState(
  status: AlertDetectionStatus,
  now: Date
): DetectionState {
  // 解釈できない時刻は「実行記録なし」と同じに扱う
  const raw = status.last_succeeded_at
  const lastSucceededAt = raw !== null && !Number.isNaN(new Date(raw).getTime()) ? raw : null
  const lastCheckedLabel =
    lastSucceededAt === null ? null : formatJstMonthDayTime(lastSucceededAt)

  let kind: DetectionStateKind
  if (!status.enabled) {
    kind = 'paused'
  } else if (lastSucceededAt === null) {
    kind = 'not_run'
  } else if (
    now.getTime() - new Date(lastSucceededAt).getTime() >
    DETECTION_DELAY_HOURS * HOUR_MS
  ) {
    kind = 'delayed'
  } else {
    kind = 'fresh'
  }
  return { kind, lastSucceededAt, lastCheckedLabel }
}

/**
 * 「今日の対応」に出す検知状態の警告文。最新なら null。
 * 停止中・遅延は、いま見えている一覧がいつのチェック結果かを添える。
 */
export function detectionWarning(state: DetectionState): string | null {
  switch (state.kind) {
    case 'paused':
      return state.lastCheckedLabel === null
        ? '自動チェックは停止中です。まだ一度も実行されていません。'
        : `自動チェックは停止中です。表示しているのは ${state.lastCheckedLabel} のチェック結果です。`
    case 'not_run':
      return '自動チェックはまだ実行されていません。毎朝 6:00 に実行されます。'
    case 'delayed':
      return `自動チェックが遅れています。表示しているのは ${state.lastCheckedLabel ?? '前回'} のチェック結果です。`
    case 'fresh':
      return null
  }
}

/** 「最終チェック 9/13 6:00・自動チェックの対象 12人」（未実行なら対象人数だけ） */
export function formatDetectionSummary(
  status: AlertDetectionStatus,
  state: DetectionState
): string {
  const parts: string[] = []
  if (state.lastCheckedLabel !== null) {
    parts.push(`最終チェック ${state.lastCheckedLabel}`)
  }
  parts.push(`自動チェックの対象 ${status.monitored_count}人`)
  return parts.join('・')
}

// ---------------------------------------------------------------------------
// 対象外の人数
// ---------------------------------------------------------------------------

export type ExclusionReason = 'no_account' | 'not_started' | 'inactive'

export type ExclusionItem = {
  reason: ExclusionReason
  label: string
  count: number
}

type ExclusionCountKey = 'excluded_no_account' | 'excluded_not_started' | 'excluded_inactive'

/** 表示の順（計画書 設計判断4: アプリ未登録・記録開始前・2週間以上データなし） */
const EXCLUSION_LABELS: { reason: ExclusionReason; label: string; key: ExclusionCountKey }[] = [
  { reason: 'no_account', label: 'アプリ未登録', key: 'excluded_no_account' },
  { reason: 'not_started', label: '記録開始前', key: 'excluded_not_started' },
  { reason: 'inactive', label: '2週間以上データなし', key: 'excluded_inactive' },
]

/** 対象外の理由別の人数（0人の理由は除く） */
export function listExclusions(status: AlertDetectionStatus): ExclusionItem[] {
  return EXCLUSION_LABELS.map(({ reason, label, key }) => ({
    reason,
    label,
    count: status[key],
  })).filter((item) => item.count > 0)
}

/** 「自動チェックの対象外: アプリ未登録 9人・記録開始前 3人」。対象外がいなければ null */
export function formatExclusionSummary(status: AlertDetectionStatus): string | null {
  const items = listExclusions(status)
  if (items.length === 0) return null
  return `自動チェックの対象外: ${items.map((item) => `${item.label} ${item.count}人`).join('・')}`
}

// ---------------------------------------------------------------------------
// RPC の行の正規化
// ---------------------------------------------------------------------------

function toCount(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : 0
}

function toNullableString(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null
}

/**
 * get_alert_detection_status() の結果（配列 or 1行）を型に揃える。
 * 0行（呼び出したのがトレーナーでない）は null。人数は bigint が文字列で届いても数える。
 */
export function parseAlertDetectionStatus(data: unknown): AlertDetectionStatus | null {
  const row = Array.isArray(data) ? data[0] : data
  if (typeof row !== 'object' || row === null) return null
  const record = row as Record<string, unknown>
  return {
    enabled: record.enabled === true,
    last_succeeded_at: toNullableString(record.last_succeeded_at),
    last_target_date: toNullableString(record.last_target_date),
    monitored_count: toCount(record.monitored_count),
    excluded_no_account: toCount(record.excluded_no_account),
    excluded_not_started: toCount(record.excluded_not_started),
    excluded_inactive: toCount(record.excluded_inactive),
  }
}
