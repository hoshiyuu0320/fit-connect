/**
 * message_notification.ts（メッセージ通知の data の組み立て）の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/message_notification_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 */

import {
  buildMessageNotificationData,
  type MessageNotificationSource,
  messageConversationPath,
} from './message_notification.ts'

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

/** data の値がすべて文字列か（FCM の data は文字列だけ） */
function assertAllStrings(data: Record<string, unknown>, label: string): void {
  for (const [key, value] of Object.entries(data)) {
    assertEq(typeof value, 'string', `${label}: data.${key} の型`)
  }
}

const CLIENT_ID = '3f2b8c1d-4e5a-4b6c-8d7e-9f0a1b2c3d4e'
const TRAINER_ID = '7a6b5c4d-3e2f-4a1b-9c8d-0e1f2a3b4c5d'

/** 顧客→トレーナーのメッセージ（overrides で列を差し替える） */
function clientToTrainer(overrides: Partial<MessageNotificationSource> = {}): MessageNotificationSource {
  return { id: 'm1', sender_id: CLIENT_ID, sender_type: 'client', receiver_type: 'trainer', ...overrides }
}

/** url を付けない場合の data（今までと同じ） */
const WITHOUT_URL = { type: 'message', messageId: 'm1' }

Deno.test('messageConversationPath: /message?clientId=<id>（値はエンコードする）', () => {
  assertEq(messageConversationPath(CLIENT_ID), `/message?clientId=${CLIENT_ID}`, 'uuid')
  assertEq(messageConversationPath('a&b'), '/message?clientId=a%26b', 'a&b')
})

Deno.test('buildMessageNotificationData: 顧客→トレーナーは url（/message?clientId=<sender_id>）が付く', () => {
  const data = buildMessageNotificationData(clientToTrainer())
  assertEq(
    canonical(data),
    canonical({ type: 'message', messageId: 'm1', url: `/message?clientId=${CLIENT_ID}` }),
    'data 全体',
  )
  assertAllStrings(data, '顧客→トレーナー')
})

Deno.test('buildMessageNotificationData: トレーナー→顧客は url を付けない（Mobile 向けの data は変えない）', () => {
  const data = buildMessageNotificationData({
    id: 'm1',
    sender_id: TRAINER_ID,
    sender_type: 'trainer',
    receiver_type: 'client',
  })
  assertEq(canonical(data), canonical(WITHOUT_URL), 'data 全体')
  assertEq('url' in data, false, 'url キー')
  assertAllStrings(data, 'トレーナー→顧客')
})

Deno.test('buildMessageNotificationData: 顧客→顧客・トレーナー→トレーナー・種別が null なら url を付けない', () => {
  const cases: [string, Partial<MessageNotificationSource>][] = [
    ['顧客→顧客', { receiver_type: 'client' }],
    ['トレーナー→トレーナー', { sender_id: TRAINER_ID, sender_type: 'trainer', receiver_type: 'trainer' }],
    ['sender_type が null', { sender_type: null }],
    ['receiver_type が null', { receiver_type: null }],
    ['両方 null', { sender_type: null, receiver_type: null }],
    ['未知の種別', { sender_type: 'system' }],
  ]
  for (const [label, overrides] of cases) {
    const data = buildMessageNotificationData(clientToTrainer(overrides))
    assertEq(canonical(data), canonical(WITHOUT_URL), `${label}: data 全体`)
    assertEq('url' in data, false, `${label}: url キー`)
    assertAllStrings(data, label)
  }
})

Deno.test('buildMessageNotificationData: 顧客→トレーナーでも sender_id が null・空文字・文字列でないなら url を付けない', () => {
  // index.ts は @ts-nocheck なので、型に無い値（undefined・数値）も来うるものとして確かめる
  const cases: [string, unknown][] = [
    ['null', null],
    ['空文字', ''],
    ['undefined', undefined],
    ['数値', 123],
  ]
  for (const [label, senderId] of cases) {
    const data = buildMessageNotificationData(
      clientToTrainer({ sender_id: senderId as MessageNotificationSource['sender_id'] }),
    )
    assertEq(canonical(data), canonical(WITHOUT_URL), `sender_id ${label}: data 全体`)
    assertEq('url' in data, false, `sender_id ${label}: url キー`)
    assertAllStrings(data, `sender_id ${label}`)
  }
})

Deno.test('buildMessageNotificationData: sender_id の & ? # / などはエンコードする', () => {
  const data = buildMessageNotificationData(clientToTrainer({ sender_id: 'a&b?c#d/e=f g%h' }))
  assertEq(data.url, '/message?clientId=a%26b%3Fc%23d%2Fe%3Df%20g%25h', 'url')
  assertAllStrings(data, 'エンコード')

  // sw.js の正規化（自分のオリジンの pathname + search + hash）でそのまま残り、
  // message/page.tsx の searchParams.get('clientId') で元の値に戻る
  const origin = 'https://app.example.com'
  const parsed = new URL(data.url, origin)
  assertEq(parsed.origin, origin, 'origin')
  assertEq(parsed.pathname + parsed.search + parsed.hash, data.url, '正規化後のパス')
  assertEq(parsed.searchParams.get('clientId'), 'a&b?c#d/e=f g%h', 'clientId')
})

Deno.test('buildMessageNotificationData: メッセージの行の他の列（content など）を data に持ち込まない', () => {
  // index.ts は messages から取り直した行をそのまま渡す
  const row = {
    ...clientToTrainer(),
    content: '#体重 65.2kg',
    receiver_id: TRAINER_ID,
    created_at: '2026-10-12T00:00:00Z',
    image_urls: [],
    metadata: null,
    tags: ['#体重'],
  }
  assertEq(
    canonical(buildMessageNotificationData(row)),
    canonical({ type: 'message', messageId: 'm1', url: `/message?clientId=${CLIENT_ID}` }),
    'data 全体',
  )
})
