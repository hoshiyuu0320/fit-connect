/**
 * メッセージ通知（parse-message-tags の sendMessageNotification）の data を組み立てる純関数。
 * 設計: docs/superpowers/specs/2026-10-12-message-notification-open-chat-design.md §3
 *
 * parse-message-tags/index.ts から使う。index.ts は import 時に Deno.serve が走るのでテストから読めない。
 * ネットワーク無しで deno test できるよう、import の無いこのファイルに切り出している
 * （テスト: message_notification_test.ts）。
 *
 * - type: 'message' / messageId: 常に入れる（従来どおり）
 * - url: 送信者が顧客（sender_type = 'client'）で宛先がトレーナー（receiver_type = 'trainer'）のときだけ付ける。
 *   トレーナーが Web Push の通知をクリックすると、sw.js が data.url を自分のオリジンのパスに正規化して開く
 *   （無ければ既定の /message）。/message?clientId=<sender_id> なら message/page.tsx がその顧客の会話を選ぶ。
 *   sender_id は顧客の clients.client_id（auth uid）。文字列でない・空文字なら付けない
 * - トレーナー→顧客の通知は Mobile 向けなので url を付けない（キー自体を作らない）
 * - 値はすべて文字列（FCM の data は文字列だけ。Web Push では JSON.stringify({ title, body, data }) の data に入る）
 */

/** data の組み立てに使う messages の列（parse-message-tags が取り直した行を構造的に受ける） */
export interface MessageNotificationSource {
  id: string
  sender_id: string | null
  sender_type: string | null
  receiver_type: string | null
}

/** その顧客との会話を開くパス（Web の clientMessageHref と同じ形。値はエンコードする） */
export function messageConversationPath(clientId: string): string {
  return `/message?clientId=${encodeURIComponent(clientId)}`
}

export function buildMessageNotificationData(message: MessageNotificationSource): Record<string, string> {
  const data: Record<string, string> = { type: 'message', messageId: message.id }
  if (
    message.sender_type === 'client' &&
    message.receiver_type === 'trainer' &&
    typeof message.sender_id === 'string' &&
    message.sender_id !== ''
  ) {
    data.url = messageConversationPath(message.sender_id)
  }
  return data
}
