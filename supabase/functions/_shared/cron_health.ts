/**
 * cron 失敗の監視（check-cron-health）の純関数群。
 * 設計: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §5
 *
 * DB・ネットワークに依存しない（テスト: cron_health_test.ts。外部依存ゼロで deno test できる）。
 */

/** 通知のタイトル（ジョブ名・詳細は入れない。本文は formatProblemsBody） */
export const CRON_FAILURE_TITLE = '自動処理で問題が起きています'
/** 通知のクリック先 */
export const CRON_FAILURE_URL = '/dashboard'
/** test_notification のタイトル（実際の失敗と見間違えないよう、CRON_FAILURE_TITLE とは変える） */
export const TEST_NOTIFICATION_TITLE = '自動処理の監視'
/** test_notification の本文 */
export const TEST_NOTIFICATION_BODY = 'テスト通知です'
/** test_notification の tag（同じ tag の前のテスト通知を置き換えてよい） */
export const TEST_NOTIFICATION_TAG = 'cron_failure_test'

/** 本文に名前を出す問題の数。残りは「ほかN件」にまとめる */
const MAX_PROBLEMS_IN_BODY = 3

// ============================================================
// リクエストの検証
// ============================================================

export interface CheckRequest {
  /** 送らない（真偽値の false のときだけ false） */
  dryRun: boolean
  /** 確認をせずテスト通知を送る（dryRun が false のときだけ true になる） */
  testNotification: boolean
}

/**
 * Edge Function の body を読む。エラーにはしない（cron は常に正しい body を送り、手動実行の誤りは dry run に倒れる）。
 * - body が JSON のオブジェクトでない（null・配列・文字列・数値）ときは {} として扱う（= dry run）
 * - dry_run: 真偽値の false のときだけ本送信。省略・'false'・0・null は dry run
 * - test_notification: 真偽値の true で、かつ本送信のときだけ有効
 */
export function parseCheckRequest(body: unknown): CheckRequest {
  const input: Record<string, unknown> =
    typeof body === 'object' && body !== null && !Array.isArray(body)
      ? (body as Record<string, unknown>)
      : {}

  const dryRun = input.dry_run !== false
  return { dryRun, testNotification: !dryRun && input.test_notification === true }
}

// ============================================================
// 宛先（secret CRON_ALERT_TRAINER_IDS）
// ============================================================

export interface RecipientIds {
  /** 小文字にそろえて重複を除いた trainer_id（書かれた順） */
  ids: string[]
  /** 捨てた値の数（UUID の形でないもの。空の要素は数えない）。呼び出し側が console.warn する */
  invalidCount: number
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** カンマ区切りの trainer_id を読む。未設定（undefined / 空文字）は0人 */
export function parseRecipientIds(raw: string | null | undefined): RecipientIds {
  const ids: string[] = []
  let invalidCount = 0
  for (const part of (raw ?? '').split(',')) {
    const value = part.trim()
    if (value === '') continue
    if (!UUID_RE.test(value)) {
      invalidCount += 1
      continue
    }
    const id = value.toLowerCase()
    if (!ids.includes(id)) ids.push(id)
  }
  return { ids, invalidCount }
}

// ============================================================
// 通知の文面・キー
// ============================================================

/**
 * 例: 'auto-skip-workouts（HTTP 500）・cleanup-ai-images（失敗）・notify-trainer-alerts（未実行）・ほか2件'。
 * detail は入れない（ロック画面と notification_logs に残るため）
 */
export function formatProblemsBody(problems: readonly { jobname: string; summary: string }[]): string {
  const parts = problems
    .slice(0, MAX_PROBLEMS_IN_BODY)
    .map((problem) => `${problem.jobname}（${problem.summary}）`)
  const rest = problems.length - MAX_PROBLEMS_IN_BODY
  if (rest > 0) parts.push(`ほか${rest}件`)
  return parts.join('・')
}

/**
 * dedup キー。同じ問題の同じ時間（UTC）内の再実行は1通。
 * 届かなかった分は次の確認で別のキーになり送り直せる（notification_logs の行は同じキーで送り直せない）
 */
export function problemsDedupKey(trainerId: string, firstId: number, lastId: number, at: Date): string {
  return `cron_failure:${trainerId}:${firstId}-${lastId}:${at.toISOString().slice(0, 13)}`
}

/**
 * 通知の tag。問題ごとに変える（同じ tag だと、ブラウザを閉じている間に届いた前の通知が後の通知に置き換えられ、
 * 前の問題に気づけないまま通知済みになる。sw.js は data.tag を優先する）
 */
export function problemsTag(firstId: number, lastId: number): string {
  return `cron_failure:${firstId}-${lastId}`
}

/** test_notification の dedup キー。分単位（同じ分の再実行は1通。経路を繰り返し試せるようにする） */
export function testNotificationDedupKey(trainerId: string, at: Date): string {
  return `cron_failure_test:${trainerId}:${at.toISOString().slice(0, 16)}`
}

/** notification_logs の status が「届いた」（1通以上を送れた）か。no_tokens の skipped・failed・pending は届いていない */
export function isDeliveredStatus(status: unknown): boolean {
  return status === 'sent' || status === 'partial'
}

// ============================================================
// 送信と「届いたか」の判定（送信と DB の読み取りは引数で受ける）
// ============================================================

export interface DispatchOptions {
  recipientIds: readonly string[]
  dedupKeyOf: (trainerId: string) => string
  /**
   * 1人分を送る（index.ts は sendNotification を渡す）。結果は notification_logs で見るので戻り値は使わない。
   * sendNotification は例外を外に出さないので、捕まるのは呼び出し前の例外だけ
   */
  send: (trainerId: string, dedupKey: string) => Promise<void>
  /** dedup キーに一致する notification_logs の status を読み直す。読めなければ例外（一時障害の再試行は呼び出し側） */
  readStatuses: (dedupKeys: string[]) => Promise<readonly unknown[]>
}

/**
 * 宛先ごとに順に1通送り、notification_logs を引き直して1人にでも届いたか（sent / partial）を返す。
 * - 同じ時間の再実行は送信が dedup で何もしなくても、前の sent を読んで true になる（notified_at の更新だけが
 *   前回失敗したときに、二重に送らず埋められる）
 * - 1人の送信で例外になっても、他の宛先には送って判定する
 * - 読み直しに失敗したら false（届いたか分からないときは通知済みにしない。もう1回通知する方が、通知が欠けるより軽い）
 * - 宛先が0人なら何もせず false
 */
export async function dispatchAndCheckDelivered(options: DispatchOptions): Promise<boolean> {
  const { recipientIds, dedupKeyOf, send, readStatuses } = options
  if (recipientIds.length === 0) return false

  for (const trainerId of recipientIds) {
    try {
      await send(trainerId, dedupKeyOf(trainerId))
    } catch (e) {
      console.error(`[check-cron-health] Failed to dispatch (trainer ${trainerId}):`, e)
    }
  }

  try {
    const statuses = await readStatuses(recipientIds.map((trainerId) => dedupKeyOf(trainerId)))
    return statuses.some((status) => isDeliveredStatus(status))
  } catch (e) {
    console.warn('[check-cron-health] Notifications dispatched but failed to read notification_logs:', e)
    return false
  }
}
