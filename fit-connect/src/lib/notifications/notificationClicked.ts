/**
 * 通知のクリックで Service Worker（public/sw.js）が前面に出したタブへ送るメッセージ
 * `{ type: 'notification-clicked', url }` を受ける（設計書 docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §7.3）。
 * タブが既に見えていた場合は visibilitychange が起きないので、これで取り直す。
 * url（sw.js が自分のオリジンのパスに正規化したクリック先）も渡すので、メッセージ画面はそれで顧客の会話を開き直す
 * （docs/superpowers/specs/2026-10-12-message-notification-open-chat-design.md §5）。
 * 全ページの layout から読まれるので、依存の無い小さなモジュールにする
 */

export const NOTIFICATION_CLICKED_MESSAGE_TYPE = 'notification-clicked'

export function isNotificationClickedMessage(data: unknown): boolean {
  return (
    typeof data === 'object' &&
    data !== null &&
    (data as { type?: unknown }).type === NOTIFICATION_CLICKED_MESSAGE_TYPE
  )
}

/**
 * navigator.serviceWorker の message で notification-clicked を受けたら onClicked を呼ぶ。
 * onClicked にはメッセージの url を渡す（文字列でなければ null）。取り直すだけの呼び出し側は受けなくてよい。
 * serviceWorker が無いブラウザ（・サーバー）では何もしない。返り値はリスナーを外す関数（アンマウントで呼ぶ）
 */
export function subscribeNotificationClicked(onClicked: (url: string | null) => void): () => void {
  if (typeof navigator === 'undefined' || !('serviceWorker' in navigator) || !navigator.serviceWorker) {
    return () => {}
  }
  const container = navigator.serviceWorker
  const handleMessage = (event: MessageEvent) => {
    if (!isNotificationClickedMessage(event.data)) return
    const url = (event.data as { url?: unknown }).url
    onClicked(typeof url === 'string' ? url : null)
  }
  container.addEventListener('message', handleMessage)
  return () => container.removeEventListener('message', handleMessage)
}
