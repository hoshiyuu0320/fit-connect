/**
 * Web Push（npm:web-push@3.6.7 の sendNotification）の送信オプションを組み立てる純関数。
 *
 * push.ts から使う。push.ts を import すると型検査で esm.sh / npm の取得が走るので、
 * ネットワーク無しで deno test できるよう、import の無いこのファイルに切り出している
 * （テスト: web_push_options_test.ts）。
 *
 * - vapidDetails: VAPID の subject / publicKey / privateKey
 * - timeout: 10000 ms を常に付ける。無いと push サービスが応答しない1件で逐次の送信が止まり、
 *   notification_logs の行が pending のまま残って、その日の dedup キーを使い切る。
 *   Web Push 全体（メッセージ通知を含む）に効く
 * - TTL: ttlSeconds が正の整数のときだけ付ける（それ以外は web-push の既定のまま）。
 *   ブラウザが閉じている間に push サービスが預かる秒数。Web Push だけに効き、FCM には渡さない
 */

/** web-push に渡す送信のタイムアウト（ミリ秒） */
export const WEB_PUSH_TIMEOUT_MS = 10_000

/** VAPID の鍵の組（push.ts の VapidConfig と同じ形を構造的に受ける） */
export interface VapidDetails {
  subject: string
  publicKey: string
  privateKey: string
}

/** web-push の sendNotification の第3引数のうち、ここで組み立てる部分 */
export interface WebPushOptions {
  vapidDetails: VapidDetails
  timeout: number
  TTL?: number
}

export function buildWebPushOptions(vapid: VapidDetails, ttlSeconds?: number): WebPushOptions {
  const options: WebPushOptions = {
    vapidDetails: {
      subject: vapid.subject,
      publicKey: vapid.publicKey,
      privateKey: vapid.privateKey,
    },
    timeout: WEB_PUSH_TIMEOUT_MS,
  }
  if (typeof ttlSeconds === 'number' && Number.isInteger(ttlSeconds) && ttlSeconds > 0) {
    options.TTL = ttlSeconds
  }
  return options
}
