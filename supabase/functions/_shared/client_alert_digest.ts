/**
 * トレーナー向けアラートの朝のまとめ通知（notify-trainer-alerts）の純関数群。
 * 設計: docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §4・§5
 *
 * DB・ネットワークに依存しない（テスト: client_alert_digest_test.ts。外部依存ゼロで deno test できる）。
 * 「今日（JST）」は呼び出し側が session_reminder_format.ts の formatJstDate(new Date()) で作って渡す。
 */

import { parseTargetDate } from './session_reminder_format.ts'

/** 通知のタイトル（顧客名・種別・数値は入れない。ロック画面と notification_logs に残るため） */
export const DIGEST_TITLE = '今日の対応があります'
/** 通知のクリック先（「今日の対応」があるダッシュボード） */
export const DIGEST_URL = '/dashboard'
/** Web Push の有効期限（秒）。12時間 */
export const DIGEST_TTL_SECONDS = 43200

/** dedup キー。同じ D・同じトレーナーには1回だけ送る */
export function digestDedupKey(trainerId: string, targetDate: string): string {
  return `client_alert_digest:${trainerId}:${targetDate}`
}

/** 通知の tag（sw.js が日ごとに別の通知として出し、古い日付のまとめを閉じる） */
export function digestTag(targetDate: string): string {
  return `client_alert:${targetDate}`
}

// ============================================================
// 集計（§4.2 担当の一致・§4.3 重大度別の人数）
// ============================================================

/**
 * alerts の行（PostgREST: `trainer_id, client_id, severity, clients!inner(trainer_id)`）。
 * clients は多対一の埋め込みで通常はオブジェクトだが、配列でも来うる（配列なら先頭を使う）。
 * null・読めない形は「担当が一致しない」として数えない
 */
export interface AlertRow {
  trainer_id: string
  client_id: string
  severity: string
  clients: { trainer_id: string } | { trainer_id: string }[] | null
}

export interface SeverityCounts {
  high: number
  medium: number
  low: number
}

export interface TrainerDigest extends SeverityCounts {
  trainer_id: string
}

type Severity = keyof SeverityCounts

const SEVERITY_RANK: Record<Severity, number> = { high: 3, medium: 2, low: 1 }

/** 未知の重大度は medium として扱う（Web の normalizeSeverity と同じ） */
function normalizeSeverity(value: unknown): Severity {
  return value === 'high' || value === 'medium' || value === 'low' ? value : 'medium'
}

/** 埋め込みの clients から今の担当トレーナーを読む。読めなければ null */
function currentTrainerOf(clients: unknown): string | null {
  const embedded = Array.isArray(clients) ? clients[0] : clients
  if (typeof embedded !== 'object' || embedded === null) return null
  const trainerId = (embedded as { trainer_id?: unknown }).trainer_id
  return typeof trainerId === 'string' ? trainerId : null
}

/**
 * トレーナーごとに、顧客ごとの一番重い重大度を1つ採って人数を数える。
 * - 今の担当（clients.trainer_id = alerts.trainer_id）の行だけを数える（ダッシュボードの RLS と同じ条件）
 * - 3区分とも0のトレーナーは返さない
 * - トレーナー ID 順（文字列の昇順）
 */
export function buildTrainerDigests(rows: readonly AlertRow[]): TrainerDigest[] {
  // trainer_id → client_id → 一番重い重大度
  const byTrainer = new Map<string, Map<string, Severity>>()
  for (const row of rows) {
    if (typeof row?.trainer_id !== 'string' || typeof row.client_id !== 'string') continue
    if (currentTrainerOf(row.clients) !== row.trainer_id) continue
    const severity = normalizeSeverity(row.severity)
    let clients = byTrainer.get(row.trainer_id)
    if (!clients) {
      clients = new Map()
      byTrainer.set(row.trainer_id, clients)
    }
    const current = clients.get(row.client_id)
    if (current === undefined || SEVERITY_RANK[severity] > SEVERITY_RANK[current]) {
      clients.set(row.client_id, severity)
    }
  }

  const digests: TrainerDigest[] = []
  for (const [trainerId, clients] of byTrainer) {
    const counts: SeverityCounts = { high: 0, medium: 0, low: 0 }
    for (const severity of clients.values()) counts[severity] += 1
    if (counts.high + counts.medium + counts.low === 0) continue
    digests.push({ trainer_id: trainerId, ...counts })
  }
  return digests.sort((a, b) => (a.trainer_id < b.trainer_id ? -1 : a.trainer_id > b.trainer_id ? 1 : 0))
}

// ============================================================
// 文面（§4.4）
// ============================================================

/** 区分名は Web の severityLabel と同じ */
const SEVERITY_LABELS: ReadonlyArray<[Severity, string]> = [
  ['high', '要確認'],
  ['medium', '注意'],
  ['low', '参考'],
]

/** 例: '新しく要確認 1名・注意 2名'。人数が0の区分は書かない */
export function formatDigestBody(counts: SeverityCounts): string {
  const parts = SEVERITY_LABELS.filter(([key]) => counts[key] > 0).map(
    ([key, label]) => `${label} ${counts[key]}名`,
  )
  return `新しく${parts.join('・')}`
}

// ============================================================
// リクエストの検証（§5.1）
// ============================================================

export type NotifyRequest =
  | { ok: true; dryRun: boolean; targetDate: string; trainerId: string | null }
  | { ok: false; error: string }

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * Edge Function の body を検証する。ok: false の error はそのまま 400 の body になる。
 * - body が JSON のオブジェクトでない（null・配列・文字列・数値）ときは {} として扱う（= dry run・今日）
 * - dry_run: 真偽値の false のときだけ本送信。省略・'false'・0・null は dry run
 * - target_date: キーがあって undefined / null でなければ parseTargetDate で検証。todayJst より後は拒否。
 *   本送信では必須。dry run で省略なら todayJst
 * - trainer_id: undefined / null は全員（null）。それ以外は UUID の形の文字列だけ受け付ける（小文字にそろえる）
 */
export function parseNotifyRequest(body: unknown, todayJst: string): NotifyRequest {
  const input: Record<string, unknown> =
    typeof body === 'object' && body !== null && !Array.isArray(body)
      ? (body as Record<string, unknown>)
      : {}

  const dryRun = input.dry_run !== false

  let targetDate: string
  const rawTargetDate = input.target_date
  if (rawTargetDate === undefined || rawTargetDate === null) {
    if (!dryRun) {
      return { ok: false, error: 'target_date (YYYY-MM-DD) is required when dry_run is false' }
    }
    targetDate = todayJst
  } else {
    const parsed = parseTargetDate(rawTargetDate)
    if (parsed === null) {
      return { ok: false, error: 'target_date must be an existing date in YYYY-MM-DD format' }
    }
    // 'YYYY-MM-DD' 同士は文字列比較で日付の前後になる
    if (parsed > todayJst) {
      return { ok: false, error: `target_date must not be later than today (JST ${todayJst})` }
    }
    targetDate = parsed
  }

  let trainerId: string | null = null
  const rawTrainerId = input.trainer_id
  if (rawTrainerId !== undefined && rawTrainerId !== null) {
    if (typeof rawTrainerId !== 'string' || !UUID_RE.test(rawTrainerId)) {
      return { ok: false, error: 'trainer_id must be a UUID' }
    }
    trainerId = rawTrainerId.toLowerCase()
  }

  return { ok: true, dryRun, targetDate, trainerId }
}

// ============================================================
// 送信結果の集計（§5.3 outcome）
// ============================================================

/** notification_logs から集計用に読む列 */
export interface LogRow {
  dedup_key: string
  status: string
  detail: string | null
}

export interface SkippedBy {
  no_tokens: number
  disabled: number
  quiet_hours: number
  vapid: number
  other: number
}

export interface DigestOutcome {
  sent: number
  partial: number
  skipped: number
  failed: number
  pending: number
  /** 送る前から行があって送らなかったキーの数。その読み取りが読めなかったときは null */
  duplicate: number | null
  /** 送ったのにログの行が見つからないキーの数 */
  missing: number
  skippedBy: SkippedBy
}

export function emptyOutcome(): DigestOutcome {
  return {
    sent: 0,
    partial: 0,
    skipped: 0,
    failed: 0,
    pending: 0,
    duplicate: 0,
    missing: 0,
    skippedBy: { no_tokens: 0, disabled: 0, quiet_hours: 0, vapid: 0, other: 0 },
  }
}

/** skipped の行の detail を区分する（push.ts が書く値: no_tokens / disabled / quiet_hours / ...vapid_not_configured...） */
export function classifySkipDetail(detail: string | null): keyof SkippedBy {
  if (detail === 'no_tokens' || detail === 'disabled' || detail === 'quiet_hours') return detail
  if (detail !== null && detail.includes('vapid_not_configured')) return 'vapid'
  return 'other'
}

/**
 * 送った後の notification_logs から outcome を作る。
 * @param keys 今回の対象の dedup キー（trainerCount 件）
 * @param logs 送った後に引き直した行
 * @param duplicateKeys 送る前から行があった（送り直しの対象でない）キー。読めなかったときは null
 * @param dispatchErrorKeys sendNotification を呼ぶ前に例外になったキー（failed に数え、missing にしない）
 */
export function summarizeOutcome(
  keys: readonly string[],
  logs: readonly LogRow[],
  duplicateKeys: ReadonlySet<string> | null,
  dispatchErrorKeys: ReadonlySet<string>,
): DigestOutcome {
  const outcome = emptyOutcome()
  outcome.duplicate = duplicateKeys === null ? null : 0
  const logByKey = new Map(logs.map((log) => [log.dedup_key, log]))

  for (const key of keys) {
    if (duplicateKeys?.has(key)) {
      outcome.duplicate = (outcome.duplicate ?? 0) + 1
      continue
    }
    if (dispatchErrorKeys.has(key)) {
      outcome.failed += 1
      continue
    }
    const log = logByKey.get(key)
    if (!log) {
      outcome.missing += 1
      continue
    }
    switch (log.status) {
      case 'sent':
        outcome.sent += 1
        break
      case 'partial':
        outcome.partial += 1
        break
      case 'skipped':
        outcome.skipped += 1
        outcome.skippedBy[classifySkipDetail(log.detail)] += 1
        break
      case 'failed':
        outcome.failed += 1
        break
      default:
        // 'pending' のまま残った行（push サービスが応答しないまま止まった・status 更新の失敗など）
        outcome.pending += 1
    }
  }
  return outcome
}
