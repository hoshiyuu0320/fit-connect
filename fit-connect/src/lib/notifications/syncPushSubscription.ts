/**
 * 設定画面を開いたときの、ブラウザの Web Push 購読の登録し直し（設計書 §7.2）。
 *
 * ブラウザの購読の鍵を今の VAPID 公開鍵と比べ、
 * - 同じ／比べられない: サーバーへ送り直す（ブラウザでは購読済みなのにサーバーに行が無い状態を直す）
 * - 違う（古い鍵で作った購読）: サーバーの行を消してから、ブラウザの購読を解除する
 * - 公開鍵が無い・購読が無い: 何もしない
 *
 * ブラウザ API と fetch は引数で受ける（コンポーネントから切り離して単体テストするため）。
 * 例外は投げず、結果を返す。
 */
import { compareApplicationServerKey } from './pushSubscriptionKey'

/** ブラウザの購読から、照合と送り直しに要る値だけを抜き出したもの */
export type SubscriptionSnapshot = {
  endpoint: string
  /** subscription.options.applicationServerKey（ブラウザが返さなければ null） */
  applicationServerKey: ArrayBuffer | null
  p256dh: string | null
  auth: string | null
}

export type SyncPushSubscriptionDeps = {
  /** 今のブラウザの購読（Service Worker や購読が無ければ null） */
  getSubscription: () => Promise<SubscriptionSnapshot | null>
  /** NEXT_PUBLIC_VAPID_PUBLIC_KEY */
  vapidPublicKey: string | null | undefined
  /** POST /api/push-subscriptions。成功（2xx）で true */
  post: (body: { endpoint: string; p256dh: string; auth: string }) => Promise<boolean>
  /** DELETE /api/push-subscriptions。成功（2xx）で true */
  del: (body: { endpoint: string }) => Promise<boolean>
  /** ブラウザの購読の解除。解除できたら true */
  unsubscribe: () => Promise<boolean>
}

/**
 * - 'reposted': サーバーへ送り直した
 * - 'purged': 古い鍵の購読を、サーバーとブラウザの両方から消した（利用者にオンにし直してもらう）
 * - 'noop': 何もしなかった（公開鍵が無い・購読が無い）
 * - 'failed': どこかで失敗した（サーバーに行が残ったままブラウザの購読だけを消すことはしない）
 */
export type SyncPushSubscriptionResult = 'reposted' | 'purged' | 'noop' | 'failed'

export async function syncPushSubscription(
  deps: SyncPushSubscriptionDeps,
): Promise<SyncPushSubscriptionResult> {
  // 公開鍵が無い（dev 環境など）は比べられないので、送り直しもしない
  if (!deps.vapidPublicKey) return 'noop'

  try {
    const subscription = await deps.getSubscription()
    if (!subscription) return 'noop'

    const comparison = compareApplicationServerKey(subscription.applicationServerKey, deps.vapidPublicKey)

    if (comparison === 'different') {
      // サーバーの行を先に消す。消せなければブラウザの購読は残す
      const deleted = await deps.del({ endpoint: subscription.endpoint })
      if (!deleted) return 'failed'
      const unsubscribed = await deps.unsubscribe()
      return unsubscribed ? 'purged' : 'failed'
    }

    // same / unknown: 送り直す（API は upsert なので何度送っても行は増えない）
    if (!subscription.p256dh || !subscription.auth) return 'failed'
    const posted = await deps.post({
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
    })
    return posted ? 'reposted' : 'failed'
  } catch {
    return 'failed'
  }
}
