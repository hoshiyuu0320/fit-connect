/**
 * web_push_options.ts（Web Push の送信オプションの組み立て）の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/web_push_options_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 */

import { buildWebPushOptions, WEB_PUSH_TIMEOUT_MS } from './web_push_options.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

/** キーの順序に依存しない比較のため、キーを並べ替えて JSON にする */
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v) =>
    v && typeof v === 'object' && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b)))
      : v)
}

const VAPID = { subject: 'mailto:test@example.com', publicKey: 'pub', privateKey: 'priv' }

Deno.test('buildWebPushOptions: 正の整数の ttlSeconds は TTL に入る', () => {
  assertEq(buildWebPushOptions(VAPID, 43200).TTL, 43200, 'ttl 43200')
  assertEq(buildWebPushOptions(VAPID, 1).TTL, 1, 'ttl 1')
})

Deno.test('buildWebPushOptions: 0・負・小数・NaN・Infinity・未指定なら TTL を入れない', () => {
  for (const ttl of [0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, undefined]) {
    const options = buildWebPushOptions(VAPID, ttl)
    assertEq('TTL' in options, false, `ttlSeconds=${ttl}`)
  }
})

Deno.test('buildWebPushOptions: timeout（10000 ms）が常に入る', () => {
  assertEq(WEB_PUSH_TIMEOUT_MS, 10000, 'WEB_PUSH_TIMEOUT_MS')
  assertEq(buildWebPushOptions(VAPID).timeout, 10000, 'ttl なし')
  assertEq(buildWebPushOptions(VAPID, 43200).timeout, 10000, 'ttl あり')
  assertEq(buildWebPushOptions(VAPID, 0).timeout, 10000, 'ttl 不正')
})

Deno.test('buildWebPushOptions: vapidDetails に3つの値が入り、余分なキーを持ち込まない', () => {
  const options = buildWebPushOptions({ ...VAPID, extra: 'x' } as typeof VAPID, 60)
  assertEq(
    canonical(options),
    canonical({
      vapidDetails: { subject: 'mailto:test@example.com', publicKey: 'pub', privateKey: 'priv' },
      timeout: 10000,
      TTL: 60,
    }),
    'options 全体',
  )
  assertEq(
    canonical(buildWebPushOptions(VAPID)),
    canonical({ vapidDetails: VAPID, timeout: 10000 }),
    'ttl なしの options 全体',
  )
})
