/**
 * cron_health.ts（cron 失敗の監視の純関数群）の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/cron_health_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 */

import {
  CRON_FAILURE_TITLE,
  CRON_FAILURE_URL,
  dispatchAndCheckDelivered,
  formatProblemsBody,
  isDeliveredStatus,
  parseCheckRequest,
  parseRecipientIds,
  problemsDedupKey,
  problemsTag,
  TEST_NOTIFICATION_BODY,
  TEST_NOTIFICATION_TAG,
  TEST_NOTIFICATION_TITLE,
  testNotificationDedupKey,
} from './cron_health.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

function assertDeepEq(actual: unknown, expected: unknown, label: string): void {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a !== e) throw new Error(`${label}: expected ${e}, got ${a}`)
}

const T1 = '11111111-1111-1111-1111-111111111111'
const T2 = '22222222-2222-4222-8222-222222222222'

// ------------------------------------------------------------
// 定数
// ------------------------------------------------------------

Deno.test('定数: タイトル・クリック先・テスト通知（設計書 §5 の文言）', () => {
  assertEq(CRON_FAILURE_TITLE, '自動処理で問題が起きています', 'title')
  assertEq(CRON_FAILURE_URL, '/dashboard', 'url')
  // テスト通知のタイトルは実際の失敗の通知と変える（見間違えない）
  assertEq(TEST_NOTIFICATION_TITLE, '自動処理の監視', 'test title')
  assertEq(TEST_NOTIFICATION_BODY, 'テスト通知です', 'test body')
  assertEq(TEST_NOTIFICATION_TAG, 'cron_failure_test', 'test tag')
})

// ------------------------------------------------------------
// parseCheckRequest
// ------------------------------------------------------------

Deno.test('parseCheckRequest: 真偽値の false のときだけ本送信（lessons「push を伴う cron 起動 Function は dry_run 省略時に送らない」）', () => {
  assertEq(parseCheckRequest({ dry_run: false }).dryRun, false, 'false')
  assertEq(parseCheckRequest({ dry_run: true }).dryRun, true, 'true')
  assertEq(parseCheckRequest({}).dryRun, true, '省略')
  assertEq(parseCheckRequest({ dry_run: 'false' }).dryRun, true, "'false'")
  assertEq(parseCheckRequest({ dry_run: 0 }).dryRun, true, '0')
  assertEq(parseCheckRequest({ dry_run: null }).dryRun, true, 'null')
})

Deno.test('parseCheckRequest: JSON のオブジェクトでない body は dry run', () => {
  for (const body of [null, undefined, [], [{ dry_run: false }], 'x', 1, true]) {
    assertDeepEq(parseCheckRequest(body), { dryRun: true, testNotification: false }, JSON.stringify(body) ?? 'undefined')
  }
})

Deno.test('parseCheckRequest: test_notification は dry_run が false のときだけ有効', () => {
  assertDeepEq(
    parseCheckRequest({ dry_run: false, test_notification: true }),
    { dryRun: false, testNotification: true },
    '本送信 + true',
  )
  assertDeepEq(
    parseCheckRequest({ test_notification: true }),
    { dryRun: true, testNotification: false },
    'dry_run 省略 + true は送らない',
  )
  assertDeepEq(
    parseCheckRequest({ dry_run: true, test_notification: true }),
    { dryRun: true, testNotification: false },
    'dry_run: true + true は送らない',
  )
  assertDeepEq(
    parseCheckRequest({ dry_run: false, test_notification: 'true' }),
    { dryRun: false, testNotification: false },
    "'true' は真偽値ではない",
  )
  assertDeepEq(
    parseCheckRequest({ dry_run: false, test_notification: false }),
    { dryRun: false, testNotification: false },
    'false',
  )
  assertDeepEq(parseCheckRequest({ dry_run: false }), { dryRun: false, testNotification: false }, '省略')
})

// ------------------------------------------------------------
// parseRecipientIds
// ------------------------------------------------------------

Deno.test('parseRecipientIds: 未設定・空は0人（invalid にも数えない）', () => {
  for (const raw of [undefined, null, '', ' ', ',', ' , ,']) {
    assertDeepEq(parseRecipientIds(raw), { ids: [], invalidCount: 0 }, String(raw))
  }
})

Deno.test('parseRecipientIds: カンマ区切り・前後の空白を除く・書かれた順', () => {
  assertDeepEq(parseRecipientIds(T1), { ids: [T1], invalidCount: 0 }, '1人')
  assertDeepEq(parseRecipientIds(`${T2}, ${T1} ,`), { ids: [T2, T1], invalidCount: 0 }, '2人と末尾のカンマ')
})

Deno.test('parseRecipientIds: 小文字にそろえて重複を除く', () => {
  assertDeepEq(parseRecipientIds(`${T2.toUpperCase()},${T2}`), { ids: [T2], invalidCount: 0 }, '大文字と小文字')
})

Deno.test('parseRecipientIds: UUID の形でないものは捨てて数を返す', () => {
  assertDeepEq(
    parseRecipientIds(`not-a-uuid,${T1},${T2}x,1234`),
    { ids: [T1], invalidCount: 3 },
    '形の違うもの',
  )
  // 値の前後だけでなく途中の改行や、ハイフン無しの32桁も通さない
  assertDeepEq(
    parseRecipientIds(`${T1.replace(/-/g, '')},${T1}\n${T2}`),
    { ids: [], invalidCount: 2 },
    'ハイフン無し・改行入り',
  )
})

// ------------------------------------------------------------
// formatProblemsBody
// ------------------------------------------------------------

const problem = (jobname: string, summary: string) => ({ jobname, summary })

Deno.test('formatProblemsBody: 1〜3件は全部（<job>（<summary>）を・でつなぐ）', () => {
  assertEq(formatProblemsBody([problem('a', 'HTTP 500')]), 'a（HTTP 500）', '1件')
  assertEq(
    formatProblemsBody([problem('a', 'HTTP 500'), problem('b', '失敗')]),
    'a（HTTP 500）・b（失敗）',
    '2件',
  )
  assertEq(
    formatProblemsBody([problem('a', 'HTTP 500'), problem('b', '失敗'), problem('c', '未実行')]),
    'a（HTTP 500）・b（失敗）・c（未実行）',
    '3件（ちょうど3件は「ほか」を付けない）',
  )
})

Deno.test('formatProblemsBody: 4件以上は先頭の3件と「ほかN件」', () => {
  const four = ['a', 'b', 'c', 'd'].map((job) => problem(job, '失敗'))
  assertEq(formatProblemsBody(four), 'a（失敗）・b（失敗）・c（失敗）・ほか1件', '4件')
  const ten = Array.from({ length: 10 }, (_, i) => problem(`job${i}`, '失敗'))
  assertEq(formatProblemsBody(ten), 'job0（失敗）・job1（失敗）・job2（失敗）・ほか7件', '10件')
})

Deno.test('formatProblemsBody: detail が渡っても本文に入らない', () => {
  const row = { jobname: 'a', summary: '失敗', detail: 'secret stack trace' }
  assertEq(formatProblemsBody([row]), 'a（失敗）', 'detail は無視')
})

// ------------------------------------------------------------
// キー・tag
// ------------------------------------------------------------

Deno.test('problemsDedupKey: cron_failure:<trainer>:<first>-<last>:<UTC の YYYY-MM-DDTHH>', () => {
  assertEq(
    problemsDedupKey(T1, 3, 7, new Date('2026-11-01T21:40:12.345Z')),
    `cron_failure:${T1}:3-7:2026-11-01T21`,
    '形',
  )
})

Deno.test('problemsDedupKey: 同じ時間内の再実行は同じキー、時間が変わると別のキー（UTC）', () => {
  const at = (iso: string) => problemsDedupKey(T1, 1, 2, new Date(iso))
  assertEq(at('2026-11-01T21:00:00.000Z'), at('2026-11-01T21:59:59.999Z'), '同じ時間')
  if (at('2026-11-01T21:59:59.999Z') === at('2026-11-01T22:00:00.000Z')) {
    throw new Error('時間が変わってもキーが同じ（届かなかった分を送り直せない）')
  }
  // JST で書かれた時刻でも UTC の時間になる
  assertEq(
    problemsDedupKey(T1, 1, 2, new Date('2026-11-02T06:40:00+09:00')),
    `cron_failure:${T1}:1-2:2026-11-01T21`,
    'UTC の時間',
  )
})

Deno.test('problemsDedupKey: 宛先・問題が変わると別のキー', () => {
  const at = new Date('2026-11-01T21:40:00.000Z')
  const base = problemsDedupKey(T1, 1, 2, at)
  for (const other of [problemsDedupKey(T2, 1, 2, at), problemsDedupKey(T1, 1, 3, at), problemsDedupKey(T1, 2, 2, at)]) {
    if (other === base) throw new Error(`キーが同じ: ${other}`)
  }
})

Deno.test('problemsTag: 問題ごとに変わる（設計書 §5）', () => {
  assertEq(problemsTag(3, 7), 'cron_failure:3-7', '形')
  if (problemsTag(3, 7) === problemsTag(8, 8)) throw new Error('tag が同じ')
})

Deno.test('testNotificationDedupKey: 分単位', () => {
  const at = (iso: string) => testNotificationDedupKey(T1, new Date(iso))
  assertEq(at('2026-11-01T21:40:59.999Z'), `cron_failure_test:${T1}:2026-11-01T21:40`, '形')
  assertEq(at('2026-11-01T21:40:00.000Z'), at('2026-11-01T21:40:59.999Z'), '同じ分')
  if (at('2026-11-01T21:40:59.999Z') === at('2026-11-01T21:41:00.000Z')) {
    throw new Error('分が変わってもキーが同じ（経路を試し直せない）')
  }
})

// ------------------------------------------------------------
// isDeliveredStatus
// ------------------------------------------------------------

Deno.test('isDeliveredStatus: sent / partial だけが届いた（no_tokens の skipped・failed・pending は通知済みにしない）', () => {
  assertEq(isDeliveredStatus('sent'), true, 'sent')
  assertEq(isDeliveredStatus('partial'), true, 'partial')
  for (const status of ['skipped', 'failed', 'pending', '', null, undefined, 1]) {
    assertEq(isDeliveredStatus(status), false, String(status))
  }
})

// ------------------------------------------------------------
// dispatchAndCheckDelivered（届いたときだけ notified_at を埋める判定）
// ------------------------------------------------------------

const keyOf = (trainerId: string) => `key:${trainerId}`

/** console.warn / console.error を黙らせて、呼ばれた数を返す */
async function captureLogs<T>(fn: () => Promise<T>): Promise<{ result: T; warns: number; errors: number }> {
  const { warn, error } = console
  let warns = 0
  let errors = 0
  console.warn = () => { warns += 1 }
  console.error = () => { errors += 1 }
  try {
    return { result: await fn(), warns, errors }
  } finally {
    console.warn = warn
    console.error = error
  }
}

/** 送信は何もせず、読み直しは決まった status を返す */
function delivered(statuses: readonly unknown[], recipients: readonly string[] = [T1]): Promise<boolean> {
  return dispatchAndCheckDelivered({
    recipientIds: recipients,
    dedupKeyOf: keyOf,
    send: () => Promise.resolve(),
    readStatuses: () => Promise.resolve(statuses),
  })
}

Deno.test('dispatchAndCheckDelivered: sent / partial なら true', async () => {
  assertEq(await delivered(['sent']), true, 'sent')
  assertEq(await delivered(['partial']), true, 'partial')
})

Deno.test('dispatchAndCheckDelivered: no_tokens の skipped・failed・pending・行なしは false', async () => {
  assertEq(await delivered(['skipped']), false, 'skipped')
  assertEq(await delivered(['failed']), false, 'failed')
  assertEq(await delivered(['pending']), false, 'pending')
  assertEq(await delivered([]), false, '行なし')
})

Deno.test('dispatchAndCheckDelivered: 1人にでも届けば true', async () => {
  assertEq(await delivered(['skipped', 'sent'], [T1, T2]), true, 'skipped + sent')
  assertEq(await delivered(['failed', 'partial'], [T1, T2]), true, 'failed + partial')
  assertEq(await delivered(['skipped', 'failed'], [T1, T2]), false, 'skipped + failed')
})

Deno.test('dispatchAndCheckDelivered: 読み直しが失敗したら false（console.warn）', async () => {
  const { result, warns, errors } = await captureLogs(() =>
    dispatchAndCheckDelivered({
      recipientIds: [T1],
      dedupKeyOf: keyOf,
      send: () => Promise.resolve(),
      readStatuses: () => Promise.reject(new Error('notification_logs select failed')),
    })
  )
  assertEq(result, false, '結果')
  assertEq(warns, 1, 'console.warn')
  assertEq(errors, 0, 'console.error')
})

Deno.test('dispatchAndCheckDelivered: 同じ時間の dedup 命中でも sent を読めば true（no_tokens の行なら false）', async () => {
  // dedup に命中すると sendNotification は何も送らず、ログも変えない
  const rerun = (logged: string) => {
    let sends = 0
    return dispatchAndCheckDelivered({
      recipientIds: [T1],
      dedupKeyOf: keyOf,
      send: () => {
        sends += 1
        return Promise.resolve()
      },
      readStatuses: () => Promise.resolve([logged]),
    }).then((result) => ({ result, sends }))
  }
  assertDeepEq(await rerun('sent'), { result: true, sends: 1 }, '前回 sent（notified_at の更新だけが失敗した）')
  assertDeepEq(await rerun('skipped'), { result: false, sends: 1 }, '前回 no_tokens')
})

Deno.test('dispatchAndCheckDelivered: 送信の呼び出し前の例外があっても他の宛先に送って判定する', async () => {
  const sent: string[] = []
  let readKeys: string[] = []
  const run = (statuses: readonly unknown[]) =>
    captureLogs(() =>
      dispatchAndCheckDelivered({
        recipientIds: [T1, T2],
        dedupKeyOf: keyOf,
        send: (trainerId) => {
          if (trainerId === T1) return Promise.reject(new Error('before sendNotification'))
          sent.push(trainerId)
          return Promise.resolve()
        },
        readStatuses: (keys) => {
          readKeys = keys
          return Promise.resolve(statuses)
        },
      })
    )

  const reached = await run(['sent'])
  assertEq(reached.result, true, '残りの宛先に届いた')
  assertEq(reached.errors, 1, 'console.error')
  assertDeepEq(sent, [T2], '残りの宛先に送った')
  assertDeepEq(readKeys, [keyOf(T1), keyOf(T2)], '例外になった宛先のキーも読み直す')

  const notReached = await run(['skipped'])
  assertEq(notReached.result, false, '残りの宛先も届かなかった')

  const none = await run([])
  assertEq(none.result, false, 'ログが無い')
})

Deno.test('dispatchAndCheckDelivered: 順に送り（dedup キーは宛先ごと）、全員に送った後で読み直す', async () => {
  const events: string[] = []
  const result = await dispatchAndCheckDelivered({
    recipientIds: [T1, T2],
    dedupKeyOf: keyOf,
    send: async (trainerId, dedupKey) => {
      events.push(`start:${dedupKey}`)
      await new Promise((resolve) => setTimeout(resolve, 1))
      events.push(`end:${trainerId}`)
    },
    readStatuses: (keys) => {
      events.push(`read:${keys.join(',')}`)
      return Promise.resolve(['sent'])
    },
  })
  assertEq(result, true, '結果')
  assertDeepEq(
    events,
    [`start:${keyOf(T1)}`, `end:${T1}`, `start:${keyOf(T2)}`, `end:${T2}`, `read:${keyOf(T1)},${keyOf(T2)}`],
    '順序',
  )
})

Deno.test('dispatchAndCheckDelivered: 宛先が0人なら送らず読まず false', async () => {
  let calls = 0
  const result = await dispatchAndCheckDelivered({
    recipientIds: [],
    dedupKeyOf: keyOf,
    send: () => {
      calls += 1
      return Promise.resolve()
    },
    readStatuses: () => {
      calls += 1
      return Promise.resolve(['sent'])
    },
  })
  assertEq(result, false, '結果')
  assertEq(calls, 0, '呼び出し')
})
