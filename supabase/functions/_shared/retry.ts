/**
 * cron 系 Edge Function（auto-skip-workouts / cleanup-ai-images / send-session-reminders）の
 * DB・Storage 呼び出しを、一時障害のときだけ再試行する汎用ヘルパー。
 * push.ts（統一通知ディスパッチャ）も宛先解決などの冪等な読み取りに使う。
 *
 * 背景: 2026-09-13 の cleanup-ai-images 本番初回実行で rpc('find_orphan_ai_images') が PostgREST から
 * 504 Gateway Timeout を受け、関数が 500 で終了した（SQL 自体は 6.5ms の一時障害）。pg_cron（pg_net）は
 * リクエストを投げた時点で succeeded 扱いのため、cron 側では失敗に気づけない。
 *
 * - 操作は「毎回新しいクエリを組み立てる関数」で受け取る。supabase-js のクエリビルダーは thenable で、
 *   同じビルダーを使い回すと組み立て時の値（updated_at 等）のまま送り直すことになるため
 * - 既定は最大3回（初回含む）、待機 1000ms → 3000ms。sleep はテスト用に差し替えられる
 * - 最後の試行の結果は成功・失敗を問わず加工せずに返す（呼び出し側の既存のエラー処理は変わらない）。
 *   操作が例外を投げ続けた場合は最終回の例外をそのまま投げ直す
 * - 再試行してよいのは冪等な操作（読み取り・条件付き update・storage.remove）だけ。
 *   push 送信（push.ts の FCM / Web Push 送信）は二重送信になり得るため包まない
 * - deadline（締切）を渡すと、待機後にその時刻を過ぎる再試行はせずに打ち切る（初回の試行は必ず行う）。
 *   cron 系の関数はリクエスト受付時刻 + CRON_RETRY_BUDGET_MS を全呼び出しに渡し、再試行が重なっても
 *   pg_net のタイムアウト（60 秒）内に応答を返す。超えると net._http_response が timed_out になり、
 *   再試行が起きた＝結果を確認したいときに限って status_code が残らないため
 *
 * 一時障害の判定（supabase-js 2.116.0 が使う postgrest-js / storage-js 2.116.0 のエラー形状に合わせる）:
 *   - PostgREST 応答 { data, error, count, status, statusText }: error があり、status が 0 または 500 以上。
 *     status 0 は fetch の失敗（postgrest-js が例外を捕捉し status 0・code '' の応答に変換する）
 *   - Storage 応答 { data, error }: error に HTTP ステータスが無い（fetch の失敗は status を持たない
 *     StorageUnknownError になる）、または error.status（数値）/ error.statusCode（文字列）が 500 以上
 *     （StorageApiError）
 *   - 操作が例外を投げた場合（fetch の TypeError 等）
 *   4xx（401 / 403 / 404 / 409、PGRST 系・Postgres のクエリエラー等）は再試行しても変わらないので即返す。
 *
 * 補足: postgrest-js 自身も GET（select）に限り 503 / 520 と fetch 失敗を内部で再試行する
 * （最大3回・1s→2s→4s。Retry-After があればその秒数を上限なく待つ。POST の rpc・PATCH の update・
 * storage-js は対象外で、504 はどのメソッドでも対象外）。このヘルパーで包む select はビルダーに
 * .retry(false) を付けて内部の再試行を切り、再試行の方針をこちらに一本化すること
 * （重ねると1呼び出しが最大12リクエスト・25秒超になり、deadline でも抑えられない）。
 */

/** 既定の最大試行回数（初回含む） */
const DEFAULT_MAX_ATTEMPTS = 3
/** 既定の待機時間（n 回目の失敗後に n 番目の値だけ待つ） */
const DEFAULT_DELAYS_MS: readonly number[] = [1000, 3000]
/** ログに出すエラーメッセージの最大長（ゲートウェイの HTML エラーページが丸ごと入ることがあるため） */
const MAX_LOG_MESSAGE_LENGTH = 200

/**
 * cron 系関数が再試行に使える時間（ms）。リクエスト受付からこの時間を過ぎたら新たな再試行をしない
 * （deadline = 受付時刻 + この値）。pg_net のタイムアウト 60 秒（20260913000100 / 20260913000200）から、
 * 締切直前に始めた最後の1回の所要（2026-09-13 の 504 は約7秒で返った）と応答を返す余裕を差し引いた値
 */
export const CRON_RETRY_BUDGET_MS = 40_000

export interface RetryOptions {
  /** ログに出す操作名（例: 'cleanup-ai-images rpc find_orphan_ai_images'）。キーや URL は含めない */
  label: string
  /** 最大試行回数（初回含む）。既定 3 */
  maxAttempts?: number
  /** n 回目の失敗後に待つ ms。足りない分は最後の値を使う。既定 [1000, 3000] */
  delaysMs?: readonly number[]
  /**
   * 再試行の締切（Date.now() 基準の epoch ms）。待機を終えた時点でこの時刻を過ぎるなら再試行せず、
   * その回の結果（または例外）で打ち切る。初回の試行は締切を過ぎていても行う。省略時は締切なし
   */
  deadline?: number
  /** 現在時刻（テストで締切の判定を固定するために差し替える）。既定は Date.now */
  now?: () => number
  /** 待機関数（テストで実際に待たずに待機時間だけ記録するために差し替える）。既定は setTimeout */
  sleep?: (ms: number) => Promise<void>
}

/** 失敗の概要（再試行の判定とログ用） */
interface Failure {
  /** 再試行対象の一時障害か */
  transient: boolean
  /** HTTP ステータス（fetch の失敗・例外などで無ければ null） */
  status: number | null
  message: string
}

const defaultSleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms))

/**
 * エラー値からログ用の1行メッセージを作る（空白・改行を詰め、長ければ切り詰める）。
 * Error インスタンスは name を前置し（'TypeError: fetch failed'）、それ以外は message を使う。
 */
function messageOf(error: unknown): string {
  let text: string
  if (error instanceof Error) {
    text = `${error.name}: ${error.message}`
  } else if (typeof error === 'object' && error !== null && typeof (error as { message?: unknown }).message === 'string') {
    text = (error as { message: string }).message
  } else {
    text = String(error)
  }
  const oneLine = text.replace(/\s+/g, ' ').trim()
  return oneLine.length > MAX_LOG_MESSAGE_LENGTH ? `${oneLine.slice(0, MAX_LOG_MESSAGE_LENGTH)}…` : oneLine
}

/**
 * Storage の error から HTTP ステータスを集める。
 * StorageApiError は status（数値）と statusCode（本文由来の文字列。'InvalidJWT' のような非数値もある）を持つため、
 * 正の整数として読めるものだけを採る。
 */
function storageStatusesOf(error: unknown): number[] {
  if (typeof error !== 'object' || error === null) return []
  const { status, statusCode } = error as { status?: unknown; statusCode?: unknown }
  const statuses: number[] = []
  for (const value of [status, statusCode]) {
    const n = typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN
    if (Number.isInteger(n) && n > 0) statuses.push(n)
  }
  return statuses
}

/**
 * 操作の戻り値を調べ、失敗（error あり）なら概要を返す。成功・判定対象外の値なら null。
 */
function inspectResult(result: unknown): Failure | null {
  if (typeof result !== 'object' || result === null) return null
  const error = (result as { error?: unknown }).error
  if (error === null || error === undefined) return null
  const message = messageOf(error)

  // PostgREST 応答: HTTP ステータスは応答側の status（0 = fetch の失敗）
  const status = (result as { status?: unknown }).status
  if (typeof status === 'number') {
    return { transient: status === 0 || status >= 500, status, message }
  }

  // Storage 応答: HTTP ステータスは error 側。どちらも無ければ fetch の失敗（StorageUnknownError）
  const statuses = storageStatusesOf(error)
  return {
    transient: statuses.length === 0 || statuses.some((s) => s >= 500),
    status: statuses[0] ?? null,
    message,
  }
}

/** 1回の試行の結末（打ち切るときにそのまま返す / 投げ直すために保持する） */
type Settled<T> = { threw: false; value: T } | { threw: true; error: unknown }

/**
 * operation を実行し、一時障害なら待機して呼び直す（判定と既定値はファイル冒頭のコメント参照）。
 * 再試行のたび（と再試行を使い切ったとき・締切で打ち切ったとき）に console.warn で
 * ラベル・試行回数・status・エラーメッセージを出す。
 *
 * @param operation 毎回新しいクエリを組み立てて返す関数（例: () => supabase.rpc('fn')）
 * @param options label（ログ用の操作名）ほか
 * @returns 最後に実行した試行の結果（成功・失敗とも加工せずそのまま）
 */
export async function withRetry<T>(operation: () => PromiseLike<T>, options: RetryOptions): Promise<T> {
  const { label, deadline } = options
  const maxAttempts =
    options.maxAttempts !== undefined && Number.isFinite(options.maxAttempts) && options.maxAttempts >= 1
      ? Math.floor(options.maxAttempts)
      : DEFAULT_MAX_ATTEMPTS
  const delays = options.delaysMs ?? DEFAULT_DELAYS_MS
  const sleep = options.sleep ?? defaultSleep
  const now = options.now ?? Date.now
  const describe = (attempt: number, failure: Failure) =>
    `[retry] ${label}: attempt ${attempt}/${maxAttempts} failed ` +
    `(status=${failure.status ?? 'none'}, error=${failure.message})`
  // 打ち切り: 最後の試行の結果をそのまま返す（例外なら投げ直す）
  const settle = (settled: Settled<T>): T => {
    if (settled.threw) throw settled.error
    return settled.value
  }

  for (let attempt = 1; ; attempt++) {
    let settled: Settled<T>
    let failure: Failure
    try {
      const result = await operation()
      const inspected = inspectResult(result)
      if (inspected === null || !inspected.transient) return result
      settled = { threw: false, value: result }
      failure = inspected
    } catch (e) {
      settled = { threw: true, error: e }
      failure = { transient: true, status: null, message: messageOf(e) }
    }

    if (attempt >= maxAttempts) {
      if (maxAttempts > 1) console.warn(`${describe(attempt, failure)}; giving up`)
      return settle(settled)
    }
    const delay = delays.length === 0 ? 0 : delays[Math.min(attempt, delays.length) - 1]
    if (deadline !== undefined && now() + delay >= deadline) {
      console.warn(`${describe(attempt, failure)}; giving up (retry deadline reached)`)
      return settle(settled)
    }
    console.warn(`${describe(attempt, failure)}; retrying in ${delay}ms`)
    await sleep(delay)
  }
}
