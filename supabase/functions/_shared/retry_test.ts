/**
 * retry.ts の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/retry_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能。sleep は差し替えて待機時間を記録するだけで実際には待たない）
 *
 * 応答の形は supabase-js 2.116.0 が返すものを模している:
 *   - PostgREST: { data, error, count, status, statusText }（fetch の失敗は status 0）
 *   - Storage: { data, error }（StorageApiError は error.status 数値 + error.statusCode 文字列、
 *     fetch の失敗は status を持たない StorageUnknownError）
 */

import { withRetry } from './retry.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

function assertJsonEq(actual: unknown, expected: unknown, label: string): void {
  assertEq(JSON.stringify(actual), JSON.stringify(expected), label)
}

/** 1回の呼び出しで実行する処理（応答を返すか例外を投げる） */
type Step = () => PromiseLike<unknown>

interface Outcome {
  result?: unknown
  thrown?: unknown
  /** operation が呼ばれた回数 */
  calls: number
  /** sleep に渡された待機時間 */
  waits: number[]
  /** console.warn の出力 */
  warns: string[]
}

interface RunOptions {
  maxAttempts?: number
  delaysMs?: number[]
  /** 締切（下の仮想時計の時刻） */
  deadline?: number
  /** 仮想時計の開始時刻（既定 0） */
  startAt?: number
}

/**
 * steps を呼び出し1回につき1つずつ実行する操作で withRetry を回し、呼び出し回数・待機・警告ログを記録する。
 * console.warn はテスト中だけ記録用に差し替える（出力を抑え、ログ内容を検証するため）。
 * 現在時刻は仮想時計で、sleep に渡された時間だけ進む（操作自体の所要は 0 とみなす）。
 */
async function run(steps: Step[], options: RunOptions = {}): Promise<Outcome> {
  let calls = 0
  const waits: number[] = []
  const warns: string[] = []
  let clock = options.startAt ?? 0
  const originalWarn = console.warn
  console.warn = (...args: unknown[]) => {
    warns.push(args.map(String).join(' '))
  }
  try {
    const result = await withRetry(
      () => {
        const step = steps[calls]
        calls++
        if (!step) throw new Error(`想定外の呼び出し（${calls} 回目）`)
        return step()
      },
      {
        label: 'test op',
        maxAttempts: options.maxAttempts,
        delaysMs: options.delaysMs,
        deadline: options.deadline,
        now: () => clock,
        sleep: (ms) => {
          waits.push(ms)
          clock += ms
          return Promise.resolve()
        },
      },
    )
    return { result, calls, waits, warns }
  } catch (e) {
    return { thrown: e, calls, waits, warns }
  } finally {
    console.warn = originalWarn
  }
}

/** 値で解決する */
const resolveWith = (value: unknown): Step => () => Promise.resolve(value)
/** 例外で reject する（fetch の TypeError など非同期の失敗） */
const rejectWith = (error: unknown): Step => () => Promise.reject(error)
/** 同期的に例外を投げる（クエリ組み立て中の例外など） */
const throwNow = (error: unknown): Step => () => {
  throw error
}

/** postgrest-js の応答 */
const pg = (status: number, error: unknown = null, data: unknown = null) => ({
  data,
  error,
  count: null,
  status,
  statusText: '',
})
/** storage-js の応答 */
const st = (error: unknown, data: unknown = null) => ({ data, error })
/** storage-js の StorageApiError 相当（HTTP 応答のエラー） */
const storageApiError = (status: number, statusCode: string, message = 'storage error') =>
  Object.assign(new Error(message), { name: 'StorageApiError', __isStorageError: true, status, statusCode })
/** storage-js の StorageUnknownError 相当（fetch の失敗。status / statusCode を持たない） */
const storageUnknownError = (message = 'error sending request') =>
  Object.assign(new Error(message), {
    name: 'StorageUnknownError',
    __isStorageError: true,
    originalError: new TypeError(message),
  })

Deno.test('withRetry: 504 → 成功なら 2 回目の結果を返す（待機は 1000ms の 1 回）', async () => {
  const success = pg(200, null, [{ name: 'a/ai/1.jpg' }])
  const out = await run([resolveWith(pg(504, { message: 'upstream request timeout' })), resolveWith(success)])
  assertEq(out.result, success, '2 回目の結果をそのまま返す')
  assertEq(out.calls, 2, '呼び出し回数')
  assertJsonEq(out.waits, [1000], '待機')
})

Deno.test('withRetry: 4xx（PGRST 系・Postgres のクエリエラー）は再試行せず 1 回目の結果を返す', async () => {
  const cases = [
    pg(400, { code: 'PGRST100', message: 'failed to parse filter' }),
    pg(401, { code: 'PGRST301', message: 'JWT expired' }),
    pg(403, { code: '42501', message: 'permission denied for table sessions' }),
    pg(404, { code: 'PGRST202', message: 'Could not find the function' }),
    pg(406, { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' }),
    pg(409, { code: '23505', message: 'duplicate key value violates unique constraint' }),
  ]
  for (const response of cases) {
    const out = await run([resolveWith(response), resolveWith(pg(200, null, []))])
    assertEq(out.result, response, `${response.status}: 1 回目の結果`)
    assertEq(out.calls, 1, `${response.status}: 呼び出し回数`)
    assertJsonEq(out.waits, [], `${response.status}: 待機しない`)
    assertJsonEq(out.warns, [], `${response.status}: 再試行ログを出さない`)
  }
})

Deno.test('withRetry: 3 回とも 5xx なら 3 回目の結果を返し、待機は [1000, 3000]', async () => {
  const last = pg(503, { message: 'third' })
  const out = await run([resolveWith(pg(504, { message: 'first' })), resolveWith(pg(502, { message: 'second' })), resolveWith(last)])
  assertEq(out.result, last, '3 回目の結果をそのまま返す（呼び出し側の既存のエラー処理に任せる）')
  assertEq(out.calls, 3, '呼び出し回数（最大 3 回）')
  assertJsonEq(out.waits, [1000, 3000], '待機')
})

Deno.test('withRetry: status 0（fetch の失敗を postgrest-js が変換した応答）を再試行する', async () => {
  const networkFailure = pg(0, {
    message: 'TypeError: error sending request for url',
    details: '',
    hint: '',
    code: '',
  })
  const success = pg(200, null, [])
  const out = await run([resolveWith(networkFailure), resolveWith(success)])
  assertEq(out.result, success, '2 回目の結果')
  assertEq(out.calls, 2, '呼び出し回数')
})

Deno.test('withRetry: 例外 → 成功なら成功の結果を返す', async () => {
  const success = pg(200, null, [])
  const out = await run([rejectWith(new TypeError('fetch failed')), resolveWith(success)])
  assertEq(out.thrown, undefined, '例外を外に出さない')
  assertEq(out.result, success, '2 回目の結果')
  assertEq(out.calls, 2, '呼び出し回数')
  assertJsonEq(out.waits, [1000], '待機')
})

Deno.test('withRetry: 例外が続けば最終回の例外をそのまま投げる', async () => {
  const lastError = new TypeError('third failure')
  const out = await run([
    throwNow(new Error('first failure')),
    rejectWith(new TypeError('second failure')),
    rejectWith(lastError),
  ])
  assertEq(out.thrown, lastError, '最終回の例外（同一インスタンス）')
  assertEq(out.calls, 3, '呼び出し回数')
  assertJsonEq(out.waits, [1000, 3000], '待機')
})

Deno.test('withRetry: Storage 形状は status 500 / status なしを再試行し、4xx は再試行しない', async () => {
  const removed = st(null, [{ name: 'a/ai/1.jpg' }])

  const apiError = await run([resolveWith(st(storageApiError(500, '500', 'Internal Server Error'))), resolveWith(removed)])
  assertEq(apiError.result, removed, 'status 500: 2 回目の結果')
  assertEq(apiError.calls, 2, 'status 500: 呼び出し回数')

  const unknownError = await run([resolveWith(st(storageUnknownError())), resolveWith(removed)])
  assertEq(unknownError.result, removed, 'status なし（StorageUnknownError）: 2 回目の結果')
  assertEq(unknownError.calls, 2, 'status なし: 呼び出し回数')

  const statusCodeOnly = await run([resolveWith(st({ message: 'Service Unavailable', statusCode: '503' })), resolveWith(removed)])
  assertEq(statusCodeOnly.calls, 2, 'statusCode 文字列 503 のみ: 再試行する')

  const badRequest = st(storageApiError(400, '400', 'Invalid path'))
  const badRequestOut = await run([resolveWith(badRequest), resolveWith(removed)])
  assertEq(badRequestOut.result, badRequest, 'status 400: 1 回目の結果')
  assertEq(badRequestOut.calls, 1, 'status 400: 再試行しない')

  // 本文の statusCode が数値でない（'InvalidJWT' 等）場合も HTTP の status で判定する
  const invalidJwt = st(storageApiError(403, 'InvalidJWT', 'invalid signature'))
  const invalidJwtOut = await run([resolveWith(invalidJwt), resolveWith(removed)])
  assertEq(invalidJwtOut.calls, 1, 'status 403 + statusCode InvalidJWT: 再試行しない')
})

Deno.test('withRetry: 成功なら 1 回で返し待機しない', async () => {
  const pgSuccess = pg(200, null, [])
  const pgOut = await run([resolveWith(pgSuccess)])
  assertEq(pgOut.result, pgSuccess, 'PostgREST: 1 回目の結果')
  assertEq(pgOut.calls, 1, 'PostgREST: 呼び出し回数')
  assertJsonEq(pgOut.waits, [], 'PostgREST: 待機しない')

  const stSuccess = st(null, [])
  const stOut = await run([resolveWith(stSuccess)])
  assertEq(stOut.result, stSuccess, 'Storage: 1 回目の結果')
  assertEq(stOut.calls, 1, 'Storage: 呼び出し回数')
  assertJsonEq(stOut.waits, [], 'Storage: 待機しない')
  assertJsonEq(stOut.warns, [], 'Storage: ログを出さない')
})

Deno.test('withRetry: thenable（supabase-js のクエリビルダー相当）を返す操作を毎回呼び直す', async () => {
  // then だけを持つ Promise ではない値。operation を呼ぶたびに新しいものを組み立てる
  const thenable = (value: unknown): Step => () =>
    ({ then: (resolve: (v: unknown) => unknown) => resolve(value) }) as unknown as PromiseLike<unknown>
  const success = pg(201, null, [{ id: 'x' }])
  const out = await run([thenable(pg(504, { message: 'timeout' })), thenable(success)])
  assertEq(out.result, success, '2 回目の thenable の結果')
  assertEq(out.calls, 2, 'operation を 2 回呼ぶ')
})

Deno.test('withRetry: 再試行ログにラベル・試行回数・status・エラーメッセージを出す', async () => {
  const out = await run([
    resolveWith(pg(504, { message: 'upstream\n request   timeout' })),
    rejectWith(new TypeError('fetch failed')),
    resolveWith(pg(503, { message: 'unavailable' })),
  ])
  assertEq(out.warns.length, 3, 'ログ件数（再試行 2 回 + 打ち切り 1 回）')
  assertEq(
    out.warns[0],
    '[retry] test op: attempt 1/3 failed (status=504, error=upstream request timeout); retrying in 1000ms',
    '1 回目（改行・連続空白は詰める）',
  )
  assertEq(
    out.warns[1],
    '[retry] test op: attempt 2/3 failed (status=none, error=TypeError: fetch failed); retrying in 3000ms',
    '2 回目（例外）',
  )
  assertEq(
    out.warns[2],
    '[retry] test op: attempt 3/3 failed (status=503, error=unavailable); giving up',
    '3 回目（打ち切り）',
  )
})

Deno.test('withRetry: maxAttempts / delaysMs を指定できる（待機が足りない分は最後の値）', async () => {
  const last = pg(500, { message: 'fourth' })
  const out = await run(
    [
      resolveWith(pg(500, { message: 'first' })),
      resolveWith(pg(500, { message: 'second' })),
      resolveWith(pg(500, { message: 'third' })),
      resolveWith(last),
    ],
    { maxAttempts: 4, delaysMs: [10] },
  )
  assertEq(out.result, last, '4 回目の結果')
  assertEq(out.calls, 4, '呼び出し回数（最大 4 回）')
  assertJsonEq(out.waits, [10, 10, 10], '待機（足りない分は最後の値）')
})

Deno.test('withRetry: 待機後に締切を過ぎるなら再試行せず、その回の結果を返す', async () => {
  // 時刻 0 で 1 回目が失敗。待機 1000ms 後は締切 1000 に達するので打ち切る
  const first = pg(504, { message: 'upstream request timeout' })
  const out = await run([resolveWith(first), resolveWith(pg(200, null, []))], { deadline: 1000 })
  assertEq(out.result, first, '1 回目の結果をそのまま返す')
  assertEq(out.calls, 1, '呼び出し回数')
  assertJsonEq(out.waits, [], '待機しない')
  assertJsonEq(
    out.warns,
    ['[retry] test op: attempt 1/3 failed (status=504, error=upstream request timeout); giving up (retry deadline reached)'],
    '締切で打ち切ったことをログに出す',
  )
})

Deno.test('withRetry: 締切までに収まる再試行は行い、次の待機が締切を越える時点で打ち切る', async () => {
  // 時刻 0 で失敗 → 1000ms 待って時刻 1000 で再試行（締切 3500 前）→ 失敗 → 3000ms 待つと 4000 で越えるので打ち切る
  const second = pg(502, { message: 'second' })
  const out = await run([resolveWith(pg(504, { message: 'first' })), resolveWith(second), resolveWith(pg(200, null, []))], {
    deadline: 3500,
  })
  assertEq(out.result, second, '2 回目の結果')
  assertEq(out.calls, 2, '呼び出し回数')
  assertJsonEq(out.waits, [1000], '待機')
  assertEq(out.warns.length, 2, 'ログ件数（再試行 1 回 + 締切での打ち切り 1 回）')
})

Deno.test('withRetry: 締切で打ち切るときも例外はその回のものをそのまま投げる', async () => {
  const error = new TypeError('fetch failed')
  const out = await run([rejectWith(error), resolveWith(pg(200, null, []))], { deadline: 500 })
  assertEq(out.thrown, error, 'その回の例外（同一インスタンス）')
  assertEq(out.calls, 1, '呼び出し回数')
  assertJsonEq(out.waits, [], '待機しない')
})

Deno.test('withRetry: 締切を過ぎていても初回の試行は行い、成功・4xx は締切に関係なくそのまま返す', async () => {
  const success = pg(200, null, [{ id: 'x' }])
  const successOut = await run([resolveWith(success)], { deadline: 1000, startAt: 5000 })
  assertEq(successOut.result, success, '成功: 1 回目の結果')
  assertEq(successOut.calls, 1, '成功: 呼び出し回数')
  assertJsonEq(successOut.warns, [], '成功: ログを出さない')

  const notFound = pg(404, { code: 'PGRST202', message: 'Could not find the function' })
  const notFoundOut = await run([resolveWith(notFound)], { deadline: 1000, startAt: 5000 })
  assertEq(notFoundOut.result, notFound, '4xx: 1 回目の結果')
  assertJsonEq(notFoundOut.warns, [], '4xx: ログを出さない')
})
