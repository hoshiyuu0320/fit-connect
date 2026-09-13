/**
 * 自動チェックのアラート（alerts 行）の表示内容を payload から組み立てる純関数。
 *
 * - 文言は DB に持たない（導出値は保存しない）。見出し・詳細文・理由のチップ・重要度のラベル・
 *   「記録を見る」のリンク先タブ・途絶の日数を、ここ1箇所で決める
 * - payload は DB の jsonb をそのまま受け取る。未知の alert_type / v・欠けた項目・壊れた日付でも
 *   例外にせず、種別ごとの汎用の文言に落とす（1件の不正で「今日の対応」全体を落とさない）
 * - 日付は JST の暦日 'YYYY-MM-DD' のまま文字列で扱い、Date のローカル時刻に通さない
 *   （new Date('YYYY-MM-DD') は UTC 0時として解釈され、UTC より西のタイムゾーンでは前日になる）
 * - サーバー（API Route）からも import されうるので、React や 'use client' に依存させない
 */

import { toJstDateString } from '@/lib/payments/jstDate'
import type { AlertSeverity } from '@/types/alert'

/** 「記録を見る」の遷移先タブ（/clients/<id>?tab=…） */
export type AlertRecordTab = 'weight' | 'summary'

export type AlertDescription = {
  /** 種別の短い名前。ボタンのアクセシブルな名前に使う（例:「田中さんの体重の変化を対応済みにする」） */
  kindLabel: string
  /** 行に並べる理由のチップ（例:「体重 +2.4kg」「記録・同期なし 4日」） */
  chip: string
  /** 詳細の見出し */
  title: string
  /** 詳細文 */
  detail: string
  /** 表示に使う重要度（未知の値は medium に丸める） */
  severity: AlertSeverity
  /** 重要度の文字ラベル（色だけに頼らない） */
  severityLabel: string
  tab: AlertRecordTab
  /** 記録途絶の日数（gap_to − gap_from + 1）。途絶以外・日付が壊れているときは null */
  gapDays: number | null
  /** payload を解釈して具体的な文言を作れたか（false は汎用の文言） */
  recognized: boolean
}

/** describeAlert が見る列。DB の値をそのまま渡せるよう、型は緩く受ける */
export type DescribableAlert = {
  alert_type: string
  severity: string
  payload: unknown
}

// ---------------------------------------------------------------------------
// 重要度
// ---------------------------------------------------------------------------

const SEVERITY_LABELS: Record<AlertSeverity, string> = {
  high: '要確認',
  medium: '注意',
  low: '参考',
}

const SEVERITY_RANK: Record<AlertSeverity, number> = {
  high: 3,
  medium: 2,
  low: 1,
}

/** 未知の値は medium に丸める（並び順・色・ラベルをどれも決められるようにする） */
export function normalizeSeverity(value: unknown): AlertSeverity {
  return value === 'high' || value === 'medium' || value === 'low' ? value : 'medium'
}

export function severityLabel(value: unknown): string {
  return SEVERITY_LABELS[normalizeSeverity(value)]
}

/** 並び順用（大きいほど重要） */
export function severityRank(value: unknown): number {
  return SEVERITY_RANK[normalizeSeverity(value)]
}

// ---------------------------------------------------------------------------
// 日付（JST の暦日）
// ---------------------------------------------------------------------------

const DATE_ONLY = /^(\d{4})-(\d{2})-(\d{2})$/
const ISO_DATE_TIME = /^\d{4}-\d{2}-\d{2}T/
const DAY_MS = 24 * 60 * 60 * 1000

/** 'YYYY-MM-DD' が実在する日付なら、1970-01-01 からの通算日を返す（日数の差を取るため） */
function toDayNumber(date: string): number | null {
  const match = DATE_ONLY.exec(date)
  if (!match) return null
  const year = Number(match[1])
  const month = Number(match[2])
  const day = Number(match[3])
  const ms = Date.UTC(year, month - 1, day)
  const check = new Date(ms)
  if (
    check.getUTCFullYear() !== year ||
    check.getUTCMonth() !== month - 1 ||
    check.getUTCDate() !== day
  ) {
    return null
  }
  return ms / DAY_MS
}

/**
 * JST の暦日 'YYYY-MM-DD' に揃える。
 * - date 列・payload の日付（'YYYY-MM-DD'）はそのまま使う（Date に通さない）
 * - 時刻付きの ISO 文字列は JST に直す（先頭10文字を切り出すと UTC の日付になり、JST 0:00〜8:59 が前日にずれる）
 * - それ以外の書式・実在しない日付は null
 */
export function toJstDateOnly(value: unknown): string | null {
  if (typeof value !== 'string') return null
  if (DATE_ONLY.test(value)) {
    return toDayNumber(value) === null ? null : value
  }
  if (!ISO_DATE_TIME.test(value)) return null
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return null
  return toJstDateString(parsed)
}

/** 日付を「M/D」（JST の暦日）で表示する。解釈できなければ null */
export function formatJstMonthDay(value: unknown): string | null {
  const date = toJstDateOnly(value)
  if (date === null) return null
  return `${Number(date.slice(5, 7))}/${Number(date.slice(8, 10))}`
}

/** 期間の日数（両端を含む）。from が to より後・日付が壊れているときは null */
export function countDaysInclusive(from: unknown, to: unknown): number | null {
  const fromDate = toJstDateOnly(from)
  const toDate = toJstDateOnly(to)
  const fromDay = fromDate === null ? null : toDayNumber(fromDate)
  const toDay = toDate === null ? null : toDayNumber(toDate)
  if (fromDay === null || toDay === null) return null
  const days = toDay - fromDay + 1
  return days >= 1 ? days : null
}

// ---------------------------------------------------------------------------
// payload の読み取り（型は信用せず、使う項目だけを実行時に確かめる）
// ---------------------------------------------------------------------------

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function toFiniteNumber(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

/** 小数1桁・符号付き（+2.4 / -2.4）。丸めて 0.0 になるときは符号を付けない */
function formatSigned(value: number): string {
  const abs = Math.abs(value).toFixed(1)
  if (abs === '0.0') return abs
  return `${value > 0 ? '+' : '-'}${abs}`
}

/** 「9/6〜9/12」。どちらかが壊れている・逆転しているときは null */
function formatRange(from: unknown, to: unknown): string | null {
  if (countDaysInclusive(from, to) === null) return null
  return `${formatJstMonthDay(from)}〜${formatJstMonthDay(to)}`
}

type WeightChangeView = {
  deltaKg: number
  deltaPct: number
  windowDays: number
  recentRange: string
  previousRange: string
}

function readWeightChange(payload: unknown): WeightChangeView | null {
  if (!isRecord(payload) || payload.v !== 1) return null
  const { recent, previous } = payload
  if (!isRecord(recent) || !isRecord(previous)) return null

  const deltaKg = toFiniteNumber(payload.delta_kg)
  const deltaPct = toFiniteNumber(payload.delta_pct)
  const windowDays = countDaysInclusive(recent.from, recent.to)
  const recentRange = formatRange(recent.from, recent.to)
  const previousRange = formatRange(previous.from, previous.to)
  if (
    deltaKg === null ||
    deltaPct === null ||
    windowDays === null ||
    recentRange === null ||
    previousRange === null
  ) {
    return null
  }
  return { deltaKg, deltaPct, windowDays, recentRange, previousRange }
}

type RecordGapView = {
  variant: unknown
  days: number
  gapFrom: string
  lastRecordOn: string | null
  lastActivityOn: string | null
  /**
   * 最後の記録の翌日より後から途絶を数えているか（= 最後の記録が登録日の前日より前）。
   * no_record は gap_from = max(L, 登録日 − 1) + 1 なので、このとき gap_from は登録日になる
   */
  lastRecordBeforeGap: boolean
}

function readRecordGap(payload: unknown): RecordGapView | null {
  if (!isRecord(payload) || payload.v !== 1) return null
  const days = countDaysInclusive(payload.gap_from, payload.gap_to)
  const gapFrom = formatJstMonthDay(payload.gap_from)
  if (days === null || gapFrom === null) return null
  // 最後の記録日から gap_from まで（両端を含む）が3日以上 = 最後の記録の翌日と gap_from の間に日がある
  const recordToGapDays = countDaysInclusive(payload.last_record_on, payload.gap_from)
  return {
    variant: payload.variant,
    days,
    gapFrom,
    lastRecordOn: formatJstMonthDay(payload.last_record_on),
    lastActivityOn: formatJstMonthDay(payload.last_activity_on),
    lastRecordBeforeGap: recordToGapDays !== null && recordToGapDays > 2,
  }
}

// ---------------------------------------------------------------------------
// 文言
// ---------------------------------------------------------------------------

type DescriptionBody = Omit<AlertDescription, 'severity' | 'severityLabel'>

function describeWeightChange(payload: unknown): DescriptionBody {
  const view = readWeightChange(payload)
  if (view === null) {
    return {
      kindLabel: '体重の変化',
      chip: '体重の変化',
      title: '体重の急な変化',
      detail: '比較の詳しい内容は表示できません。体重の記録を確認してください。',
      tab: 'weight',
      gapDays: null,
      recognized: false,
    }
  }
  const kg = `${formatSigned(view.deltaKg)}kg`
  return {
    kindLabel: '体重の変化',
    chip: `体重 ${kg}`,
    title: '体重の急な変化',
    detail: `${view.windowDays}日平均 ${kg}（${formatSigned(view.deltaPct)}%）。${view.recentRange} と ${view.previousRange} の比較`,
    tab: 'weight',
    gapDays: null,
    recognized: true,
  }
}

function describeRecordGap(payload: unknown): DescriptionBody {
  const view = readRecordGap(payload)
  if (view === null) {
    return {
      kindLabel: '記録の途切れ',
      chip: '記録の途切れ',
      title: '記録の途切れ',
      detail: '詳しい内容は表示できません。顧客の記録を確認してください。',
      tab: 'summary',
      gapDays: null,
      recognized: false,
    }
  }

  const { days, gapFrom } = view
  switch (view.variant) {
    case 'not_started':
      // gap_from = 登録日。記録もメッセージも一度も無い
      return {
        kindLabel: '記録開始前',
        chip: `登録から${days}日・記録なし`,
        title: '記録開始前',
        detail: `${gapFrom} に登録してから、記録もメッセージもありません`,
        tab: 'summary',
        gapDays: days,
        recognized: true,
      }
    case 'no_data':
      // 到着が無いだけで、計測していないとは限らない。「アプリを開いていない」とは書かない
      return {
        kindLabel: '記録・同期なし',
        chip: `記録・同期なし ${days}日`,
        title: `記録・同期なし ${days}日`,
        detail: `${gapFrom} 以降、記録も同期も届いていません（計測していても、アプリを開くまで届かないことがあります）`,
        tab: 'summary',
        gapDays: days,
        recognized: true,
      }
    case 'no_record': {
      // 到着日は日付だけを見せる（時刻は持たない。オーナー決定 2026-09-13 (2)）。
      // 最後の記録が登録日より前（初回連携で取り込んだ分など）のときは、日数を登録日から数えているので
      // 「最後の記録は 8/20 です」と書くと「記録なし 3日」と食い違う → 登録日からの言い方にする
      const lastRecord = view.lastRecordBeforeGap
        ? `${gapFrom} に登録してから記録がありません`
        : view.lastRecordOn !== null
          ? `最後の記録は ${view.lastRecordOn} です`
          : `${gapFrom} 以降、記録がありません`
      const arrived =
        view.lastActivityOn !== null
          ? `（${view.lastActivityOn} まではアプリからのデータが届いています）`
          : ''
      return {
        kindLabel: '記録なし',
        chip: `記録なし ${days}日`,
        title: `記録なし ${days}日`,
        detail: `${lastRecord}${arrived}`,
        tab: 'summary',
        gapDays: days,
        recognized: true,
      }
    }
    default:
      // 未知の変種（Web より先に DB へ足された場合など）。日数の定義は変種によらず共通
      return {
        kindLabel: '記録の途切れ',
        chip: `記録の途切れ ${days}日`,
        title: `記録の途切れ ${days}日`,
        detail: '詳しい内容は表示できません。顧客の記録を確認してください。',
        tab: 'summary',
        gapDays: days,
        recognized: false,
      }
  }
}

function describeUnknown(): DescriptionBody {
  return {
    kindLabel: '自動チェックの検知',
    chip: '自動チェックの検知',
    title: '自動チェックの検知',
    detail: 'この項目の詳しい内容は表示できません。顧客の記録を確認してください。',
    tab: 'summary',
    gapDays: null,
    recognized: false,
  }
}

/** アラート1件の表示内容。alert_type・severity・payload がどんな値でも例外にしない */
export function describeAlert(alert: DescribableAlert): AlertDescription {
  const severity = normalizeSeverity(alert.severity)
  const body =
    alert.alert_type === 'weight_change'
      ? describeWeightChange(alert.payload)
      : alert.alert_type === 'record_gap'
        ? describeRecordGap(alert.payload)
        : describeUnknown()
  return { ...body, severity, severityLabel: SEVERITY_LABELS[severity] }
}

// ---------------------------------------------------------------------------
// リンク先
// ---------------------------------------------------------------------------

/** 「記録を見る」の遷移先（clients/[client_id] は ?tab= を初期値として読む） */
export function clientRecordHref(clientId: string, tab: AlertRecordTab): string {
  return `/clients/${encodeURIComponent(clientId)}?tab=${tab}`
}

/** 「メッセージ」の遷移先（message/page.tsx が ?clientId= を読む） */
export function clientMessageHref(clientId: string): string {
  return `/message?clientId=${encodeURIComponent(clientId)}`
}
