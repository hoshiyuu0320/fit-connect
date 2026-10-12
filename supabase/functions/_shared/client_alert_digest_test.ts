/**
 * client_alert_digest.ts（朝のまとめ通知の純関数群）の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/client_alert_digest_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 *
 * 「今日（JST）」の日付の境目（UTC 14:59:59 / 15:00:00）は session_reminder_format_test.ts の
 * formatJstDate のテストが押さえている（ここでは todayJst を引数で固定する）
 */

import {
  type AlertRow,
  buildTrainerDigests,
  classifySkipDetail,
  DIGEST_TITLE,
  DIGEST_TTL_SECONDS,
  DIGEST_URL,
  digestDedupKey,
  digestTag,
  formatDigestBody,
  type LogRow,
  parseNotifyRequest,
  summarizeOutcome,
} from './client_alert_digest.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

/** キーの順序に依存しない深い比較（JSON にして比べる） */
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b)))
      : v)
}

function assertDeepEq(actual: unknown, expected: unknown, label: string): void {
  const a = canonical(actual)
  const e = canonical(expected)
  if (a !== e) throw new Error(`${label}: expected ${e}, got ${a}`)
}

const T1 = '11111111-1111-1111-1111-111111111111'
const T2 = '22222222-2222-2222-2222-222222222222'
const T3 = '33333333-3333-3333-3333-333333333333'
const C1 = 'c1000000-0000-0000-0000-000000000001'
const C2 = 'c2000000-0000-0000-0000-000000000002'
const C3 = 'c3000000-0000-0000-0000-000000000003'

function row(trainer: string, client: string, severity: string, clients: AlertRow['clients'] = { trainer_id: trainer }): AlertRow {
  return { trainer_id: trainer, client_id: client, severity, clients }
}

// ------------------------------------------------------------
// 定数・キー
// ------------------------------------------------------------

Deno.test('定数: タイトル・URL・TTL', () => {
  assertEq(DIGEST_TITLE, '今日の対応があります', 'DIGEST_TITLE')
  assertEq(DIGEST_URL, '/dashboard', 'DIGEST_URL')
  assertEq(DIGEST_TTL_SECONDS, 43200, 'DIGEST_TTL_SECONDS')
})

Deno.test('digestDedupKey / digestTag の形', () => {
  assertEq(digestDedupKey(T1, '2026-10-04'), `client_alert_digest:${T1}:2026-10-04`, 'dedup key')
  assertEq(digestTag('2026-10-04'), 'client_alert:2026-10-04', 'tag')
})

// ------------------------------------------------------------
// buildTrainerDigests
// ------------------------------------------------------------

Deno.test('buildTrainerDigests: 1人に high と medium → high に1名', () => {
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'medium'), row(T1, C1, 'high')]),
    [{ trainer_id: T1, high: 1, medium: 0, low: 0 }],
    'high + medium',
  )
  // 順序が逆でも同じ
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high'), row(T1, C1, 'low'), row(T1, C1, 'medium')]),
    [{ trainer_id: T1, high: 1, medium: 0, low: 0 }],
    'high + low + medium',
  )
})

Deno.test('buildTrainerDigests: 顧客ごとに数え、区分ごとに人数を出す', () => {
  assertDeepEq(
    buildTrainerDigests([
      row(T1, C1, 'high'),
      row(T1, C2, 'medium'),
      row(T1, C2, 'low'),
      row(T1, C3, 'low'),
    ]),
    [{ trainer_id: T1, high: 1, medium: 1, low: 1 }],
    '3顧客',
  )
})

Deno.test('buildTrainerDigests: 担当が変わった顧客（clients.trainer_id ≠ alerts.trainer_id）は数えない', () => {
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high', { trainer_id: T2 }), row(T1, C2, 'medium')]),
    [{ trainer_id: T1, high: 0, medium: 1, low: 0 }],
    '担当外を除く',
  )
  // 担当外だけのトレーナーは出ない（0名のトレーナーは対象外）
  assertDeepEq(buildTrainerDigests([row(T1, C1, 'high', { trainer_id: T2 })]), [], '担当外だけ')
})

Deno.test('buildTrainerDigests: 未知の重大度は medium', () => {
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'critical'), row(T1, C2, '')]),
    [{ trainer_id: T1, high: 0, medium: 2, low: 0 }],
    '未知の重大度',
  )
  // 未知（= medium）と low なら medium
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'low'), row(T1, C1, 'weird')]),
    [{ trainer_id: T1, high: 0, medium: 1, low: 0 }],
    '未知 + low',
  )
})

Deno.test('buildTrainerDigests: 複数トレーナーがトレーナー ID 順に並ぶ', () => {
  const digests = buildTrainerDigests([
    row(T3, C3, 'low'),
    row(T1, C1, 'high'),
    row(T2, C2, 'medium'),
  ])
  assertDeepEq(
    digests.map((d) => d.trainer_id),
    [T1, T2, T3],
    '並び',
  )
  assertDeepEq(
    digests,
    [
      { trainer_id: T1, high: 1, medium: 0, low: 0 },
      { trainer_id: T2, high: 0, medium: 1, low: 0 },
      { trainer_id: T3, high: 0, medium: 0, low: 1 },
    ],
    '人数',
  )
})

Deno.test('buildTrainerDigests: 入力が空 → 空', () => {
  assertDeepEq(buildTrainerDigests([]), [], '空')
})

Deno.test('buildTrainerDigests: clients がオブジェクト・配列・null の3通り', () => {
  // オブジェクト
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high', { trainer_id: T1 })]),
    [{ trainer_id: T1, high: 1, medium: 0, low: 0 }],
    'オブジェクト',
  )
  // 配列は先頭を使う
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high', [{ trainer_id: T1 }, { trainer_id: T2 }])]),
    [{ trainer_id: T1, high: 1, medium: 0, low: 0 }],
    '配列（先頭が一致）',
  )
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high', [{ trainer_id: T2 }, { trainer_id: T1 }])]),
    [],
    '配列（先頭が不一致）',
  )
  assertDeepEq(buildTrainerDigests([row(T1, C1, 'high', [])]), [], '空の配列')
  // null は数えない
  assertDeepEq(buildTrainerDigests([row(T1, C1, 'high', null)]), [], 'null')
  // 読めない形も数えない
  assertDeepEq(
    buildTrainerDigests([row(T1, C1, 'high', { trainer_id: 1 } as unknown as AlertRow['clients'])]),
    [],
    'trainer_id が文字列でない',
  )
})

// ------------------------------------------------------------
// formatDigestBody
// ------------------------------------------------------------

Deno.test('formatDigestBody: 区分の組み合わせ', () => {
  assertEq(formatDigestBody({ high: 1, medium: 0, low: 0 }), '新しく要確認 1名', 'high だけ')
  assertEq(formatDigestBody({ high: 0, medium: 2, low: 0 }), '新しく注意 2名', 'medium だけ')
  assertEq(formatDigestBody({ high: 1, medium: 2, low: 1 }), '新しく要確認 1名・注意 2名・参考 1名', '3区分')
  assertEq(formatDigestBody({ high: 1, medium: 1, low: 0 }), '新しく要確認 1名・注意 1名', 'low が0')
  assertEq(formatDigestBody({ high: 3, medium: 0, low: 2 }), '新しく要確認 3名・参考 2名', 'medium が0')
})

// ------------------------------------------------------------
// parseNotifyRequest
// ------------------------------------------------------------

const TODAY = '2026-10-04'

Deno.test('parseNotifyRequest: 省略時は dry run・今日・全員', () => {
  assertDeepEq(
    parseNotifyRequest({}, TODAY),
    { ok: true, dryRun: true, targetDate: TODAY, trainerId: null },
    '{}',
  )
})

Deno.test('parseNotifyRequest: body が null・配列・文字列・数値・undefined → {} 扱い（dry run・今日）', () => {
  for (const body of [null, [], [{ dry_run: false }], 'x', '{"dry_run":false}', 0, 42, undefined, true]) {
    assertDeepEq(
      parseNotifyRequest(body, TODAY),
      { ok: true, dryRun: true, targetDate: TODAY, trainerId: null },
      `body=${JSON.stringify(body)}`,
    )
  }
})

Deno.test('parseNotifyRequest: dry_run が真偽値の false のときだけ本送信', () => {
  assertDeepEq(
    parseNotifyRequest({ dry_run: false, target_date: TODAY }, TODAY),
    { ok: true, dryRun: false, targetDate: TODAY, trainerId: null },
    'false',
  )
  for (const value of ['false', 0, null, true, '']) {
    const result = parseNotifyRequest({ dry_run: value, target_date: TODAY }, TODAY)
    assertDeepEq(result, { ok: true, dryRun: true, targetDate: TODAY, trainerId: null }, `dry_run=${JSON.stringify(value)}`)
  }
})

Deno.test('parseNotifyRequest: dry_run false で日付無し・null → 400', () => {
  const expected = { ok: false, error: 'target_date (YYYY-MM-DD) is required when dry_run is false' }
  assertDeepEq(parseNotifyRequest({ dry_run: false }, TODAY), expected, 'キー無し')
  assertDeepEq(parseNotifyRequest({ dry_run: false, target_date: null }, TODAY), expected, 'null')
  assertDeepEq(parseNotifyRequest({ dry_run: false, target_date: undefined }, TODAY), expected, 'undefined')
})

Deno.test('parseNotifyRequest: 不正な日付・空文字・数値の日付 → 400', () => {
  const expected = { ok: false, error: 'target_date must be an existing date in YYYY-MM-DD format' }
  for (const value of ['2026-02-30', '2026/10/04', '2026-10-4', 'today', '', ' 2026-10-04', '2026-10-04T00:00:00', 20261004, {}, []]) {
    assertDeepEq(parseNotifyRequest({ target_date: value }, TODAY), expected, `dry run target_date=${JSON.stringify(value)}`)
    assertDeepEq(
      parseNotifyRequest({ dry_run: false, target_date: value }, TODAY),
      expected,
      `本送信 target_date=${JSON.stringify(value)}`,
    )
  }
})

Deno.test('parseNotifyRequest: 未来 → 400 / 今日・過去は通る', () => {
  for (const dryRun of [true, false]) {
    const future = parseNotifyRequest({ dry_run: dryRun, target_date: '2026-10-05' }, TODAY)
    assertEq(future.ok, false, `未来 (dry_run=${dryRun})`)
    assertEq(
      !future.ok && future.error.startsWith('target_date must not be later than today'),
      true,
      `未来のエラー文 (dry_run=${dryRun})`,
    )
    assertDeepEq(
      parseNotifyRequest({ dry_run: dryRun, target_date: TODAY }, TODAY),
      { ok: true, dryRun, targetDate: TODAY, trainerId: null },
      `今日 (dry_run=${dryRun})`,
    )
    assertDeepEq(
      parseNotifyRequest({ dry_run: dryRun, target_date: '2026-10-01' }, TODAY),
      { ok: true, dryRun, targetDate: '2026-10-01', trainerId: null },
      `過去 (dry_run=${dryRun})`,
    )
  }
  // 年・月をまたぐ比較
  assertEq(parseNotifyRequest({ target_date: '2027-01-01' }, '2026-12-31').ok, false, '翌年は未来')
  assertEq(parseNotifyRequest({ target_date: '2026-12-31' }, '2027-01-01').ok, true, '前年は過去')
})

Deno.test('parseNotifyRequest: dry run で日付無し・null → 今日', () => {
  assertDeepEq(
    parseNotifyRequest({ dry_run: true }, TODAY),
    { ok: true, dryRun: true, targetDate: TODAY, trainerId: null },
    'キー無し',
  )
  assertDeepEq(
    parseNotifyRequest({ target_date: null }, TODAY),
    { ok: true, dryRun: true, targetDate: TODAY, trainerId: null },
    'null',
  )
})

Deno.test('parseNotifyRequest: trainer_id', () => {
  const expected = { ok: false, error: 'trainer_id must be a UUID' }
  for (const value of ['', 'abc', `${T1}x`, ` ${T1}`, 'g1111111-1111-1111-1111-111111111111', 123, {}, [], true]) {
    assertDeepEq(parseNotifyRequest({ trainer_id: value }, TODAY), expected, `trainer_id=${JSON.stringify(value)}`)
  }
  // 無し・null → 全員
  assertDeepEq(parseNotifyRequest({ trainer_id: null }, TODAY), { ok: true, dryRun: true, targetDate: TODAY, trainerId: null }, 'null')
  assertDeepEq(parseNotifyRequest({ trainer_id: undefined }, TODAY), { ok: true, dryRun: true, targetDate: TODAY, trainerId: null }, 'undefined')
  // UUID → trainerId（大文字は小文字にそろえる）
  assertDeepEq(
    parseNotifyRequest({ dry_run: false, target_date: TODAY, trainer_id: T1 }, TODAY),
    { ok: true, dryRun: false, targetDate: TODAY, trainerId: T1 },
    'UUID',
  )
  assertDeepEq(
    parseNotifyRequest({ trainer_id: 'AAAAAAAA-0913-0000-0000-00000000000A' }, TODAY),
    { ok: true, dryRun: true, targetDate: TODAY, trainerId: 'aaaaaaaa-0913-0000-0000-00000000000a' },
    '大文字の UUID',
  )
})

// ------------------------------------------------------------
// outcome の集計
// ------------------------------------------------------------

Deno.test('classifySkipDetail: push.ts の detail を区分する', () => {
  assertEq(classifySkipDetail('no_tokens'), 'no_tokens', 'no_tokens')
  assertEq(classifySkipDetail('disabled'), 'disabled', 'disabled')
  assertEq(classifySkipDetail('quiet_hours'), 'quiet_hours', 'quiet_hours')
  assertEq(classifySkipDetail('sent=0/1 web_push:skipped(vapid_not_configured)'), 'vapid', 'vapid')
  assertEq(classifySkipDetail('sent=0/1 fcm:skipped(no_service_account_key)'), 'other', 'fcm の鍵なし')
  assertEq(classifySkipDetail(null), 'other', 'null')
})

Deno.test('summarizeOutcome: status 別・duplicate・missing・呼び出し前の例外', () => {
  const keys = ['k-sent', 'k-partial', 'k-skip1', 'k-skip2', 'k-skip3', 'k-failed', 'k-pending', 'k-missing', 'k-dup', 'k-error']
  const logs: LogRow[] = [
    { dedup_key: 'k-sent', status: 'sent', detail: 'sent=1/1' },
    { dedup_key: 'k-partial', status: 'partial', detail: 'sent=1/2 failed=1' },
    { dedup_key: 'k-skip1', status: 'skipped', detail: 'no_tokens' },
    { dedup_key: 'k-skip2', status: 'skipped', detail: 'disabled' },
    { dedup_key: 'k-skip3', status: 'skipped', detail: 'sent=0/1 web_push:skipped(vapid_not_configured)' },
    { dedup_key: 'k-failed', status: 'failed', detail: 'sent=0/1 failed=1' },
    { dedup_key: 'k-pending', status: 'pending', detail: null },
    // duplicate は前回の行（今回の数には入れない）
    { dedup_key: 'k-dup', status: 'sent', detail: 'sent=1/1' },
  ]
  const outcome = summarizeOutcome(keys, logs, new Set(['k-dup']), new Set(['k-error']))
  assertDeepEq(
    outcome,
    {
      sent: 1,
      partial: 1,
      skipped: 3,
      failed: 2,
      pending: 1,
      duplicate: 1,
      missing: 1,
      skippedBy: { no_tokens: 1, disabled: 1, quiet_hours: 0, vapid: 1, other: 0 },
    },
    'outcome',
  )
  // 合計が対象の人数になる
  const total = outcome.sent + outcome.partial + outcome.skipped + outcome.failed + outcome.pending +
    outcome.missing + (outcome.duplicate ?? 0)
  assertEq(total, keys.length, '合計 = trainerCount')
})

Deno.test('summarizeOutcome: 送る前の読み取りが読めなかったときは duplicate: null', () => {
  const outcome = summarizeOutcome(
    ['k1', 'k2'],
    [
      { dedup_key: 'k1', status: 'sent', detail: 'sent=1/1' },
      { dedup_key: 'k2', status: 'skipped', detail: 'quiet_hours' },
    ],
    null,
    new Set(),
  )
  assertEq(outcome.duplicate, null, 'duplicate')
  assertEq(outcome.sent, 1, 'sent')
  assertEq(outcome.skippedBy.quiet_hours, 1, 'quiet_hours')
})

Deno.test('summarizeOutcome: 対象が0件なら全部0', () => {
  assertDeepEq(
    summarizeOutcome([], [], new Set(), new Set()),
    {
      sent: 0,
      partial: 0,
      skipped: 0,
      failed: 0,
      pending: 0,
      duplicate: 0,
      missing: 0,
      skippedBy: { no_tokens: 0, disabled: 0, quiet_hours: 0, vapid: 0, other: 0 },
    },
    '空',
  )
})
