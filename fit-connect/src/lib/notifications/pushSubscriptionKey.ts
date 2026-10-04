/**
 * Web Push の購読の公開鍵（applicationServerKey）を扱う純関数。
 *
 * - ブラウザ専用の API（window）に依存しない。base64 の復号はグローバルの atob を使う
 *   （vitest は environment: 'node' で window が無い）
 * - 設定画面を開いたときの「購読が今の公開鍵で作られたか」の照合に使う（syncPushSubscription）
 */

/** VAPID 公開鍵（P-256 の非圧縮点）のバイト長 */
export const VAPID_PUBLIC_KEY_BYTES = 65

/** base64url（パディングは任意）だけを受け付ける。引用符・空白・'+' '/' を含むものは読めない扱い */
const BASE64URL_RE = /^[A-Za-z0-9_-]+={0,2}$/

/**
 * base64url の文字列をバイト列にする（pushManager.subscribe の applicationServerKey 用）。
 * 読めない文字列では例外を投げる（呼び出し側の try/catch で扱う）。
 */
export function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/')
  const rawData = atob(base64)
  const outputArray = new Uint8Array(rawData.length)
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i)
  }
  return outputArray
}

/**
 * VAPID 公開鍵（base64url）を読む。65 バイトの鍵として読めなければ null（例外を投げない）。
 * 空・引用符つき・base64url でない・長さが違う、はすべて null。
 */
export function decodeVapidPublicKey(value: string | null | undefined): Uint8Array | null {
  if (typeof value !== 'string' || !BASE64URL_RE.test(value)) return null
  try {
    const bytes = urlBase64ToUint8Array(value)
    return bytes.length === VAPID_PUBLIC_KEY_BYTES ? bytes : null
  } catch {
    return null
  }
}

export type KeyComparison = 'same' | 'different' | 'unknown'

/**
 * ブラウザの購読の鍵（subscription.options.applicationServerKey）と、今の VAPID 公開鍵を比べる。
 *
 * - 'same': バイト単位で一致
 * - 'different': どちらも読めて、一致しない（古い鍵で作った購読。送っても push サービスに 403 で拒まれる）
 * - 'unknown': 比べられない（購読の鍵が無い・空、公開鍵が空や壊れている、想定外の例外）。
 *   不一致として扱うと正常な購読を自動で解除してしまうので、different とは分ける
 */
export function compareApplicationServerKey(
  subscriptionKey: ArrayBuffer | ArrayBufferView | null | undefined,
  vapidPublicKeyBase64Url: string | null | undefined,
): KeyComparison {
  try {
    if (!subscriptionKey) return 'unknown'
    const expected = decodeVapidPublicKey(vapidPublicKeyBase64Url)
    if (!expected) return 'unknown'

    const actual = ArrayBuffer.isView(subscriptionKey)
      ? new Uint8Array(subscriptionKey.buffer, subscriptionKey.byteOffset, subscriptionKey.byteLength)
      : new Uint8Array(subscriptionKey)
    if (actual.length === 0) return 'unknown'
    if (actual.length !== expected.length) return 'different'
    for (let i = 0; i < expected.length; i++) {
      if (actual[i] !== expected[i]) return 'different'
    }
    return 'same'
  } catch {
    return 'unknown'
  }
}
