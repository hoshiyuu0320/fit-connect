// Service Worker for Web Push Notifications
// 設計: docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §7.1
// テスト: src/lib/notifications/sw.test.ts（Node の vm で読み込む。import / export は使わない）

// 版の識別用（DevTools の Application → Service Workers で、どの版が動いているかを見分ける）
const SW_VERSION = '2026-10-04.client-alert-1';

const FALLBACK_URL = '/message';
const FALLBACK_TITLE = '新着メッセージ';
const CLIENT_ALERT_TAG_PREFIX = 'client_alert:';

// 更新した sw.js を、開いているタブが全部閉じるのを待たずに有効にする
self.addEventListener('install', () => {
  self.skipWaiting();
});

// fetch を扱わないので実質の効果は無いが、無害なので入れておく
self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

/**
 * 通知のクリック先を、自分のオリジンのパス（pathname + search + hash）に正規化する。
 * 解析できない・別オリジン・`/` で始まらない・`//` で始まる（スキーム相対で外部ホストに解決される）なら FALLBACK_URL
 */
function normalizeTargetUrl(raw) {
  if (typeof raw !== 'string' || raw === '') return FALLBACK_URL;
  let parsed;
  try {
    parsed = new URL(raw, self.location.origin);
  } catch (e) {
    return FALLBACK_URL;
  }
  if (parsed.origin !== self.location.origin) return FALLBACK_URL;
  const path = parsed.pathname + parsed.search + parsed.hash;
  if (!path.startsWith('/') || path.startsWith('//')) return FALLBACK_URL;
  return path;
}

function isNonEmptyString(value) {
  return typeof value === 'string' && value !== '';
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** tag: payload.tag → payload.data.tag → payload.data.type → 'default'（空でない文字列だけを採る） */
function pickTag(payload, data) {
  const candidates = [payload.tag, data && data.tag, data && data.type];
  for (const candidate of candidates) {
    if (isNonEmptyString(candidate)) return candidate;
  }
  return 'default';
}

/** 今回が client_alert:<D> のときだけ、日付が今回より古い client_alert: の通知を閉じる */
async function closeOlderDigests(tag) {
  if (!tag.startsWith(CLIENT_ALERT_TAG_PREFIX)) return;
  const currentDate = tag.slice(CLIENT_ALERT_TAG_PREFIX.length);
  const notifications = await self.registration.getNotifications();
  for (const notification of notifications) {
    const otherTag = notification.tag;
    if (typeof otherTag !== 'string' || !otherTag.startsWith(CLIENT_ALERT_TAG_PREFIX)) continue;
    const otherDate = otherTag.slice(CLIENT_ALERT_TAG_PREFIX.length);
    if (otherDate < currentDate) notification.close();
  }
}

/** push の本文から、表示する title と options を組み立てる */
function buildNotification(eventData) {
  let payload = null;
  try {
    payload = eventData.json();
  } catch (e) {
    payload = null;
  }

  if (!isPlainObject(payload)) {
    let text = '';
    try {
      text = eventData.text();
    } catch (e) {
      text = '';
    }
    return {
      title: FALLBACK_TITLE,
      options: {
        body: text,
        icon: '/icon.svg',
        badge: '/icon.svg',
        data: { url: FALLBACK_URL },
        requireInteraction: false,
        tag: 'default',
        renotify: true,
      },
    };
  }

  const data = isPlainObject(payload.data) ? payload.data : null;
  const rawUrl = data && data.url !== undefined && data.url !== null ? data.url : payload.url;
  const tag = pickTag(payload, data);

  const options = {
    body: isNonEmptyString(payload.body) ? payload.body : '',
    icon: '/icon.svg',
    badge: '/icon.svg',
    data: { url: normalizeTargetUrl(rawUrl) },
    requireInteraction: false,
    tag,
  };
  // tag 無しの renotify: true は TypeError になる
  if (isNonEmptyString(tag)) options.renotify = true;

  return {
    title: isNonEmptyString(payload.title) ? payload.title : FALLBACK_TITLE,
    options,
  };
}

self.addEventListener('push', (event) => {
  if (!event.data) return;

  event.waitUntil(
    (async () => {
      const { title, options } = buildNotification(event.data);
      // 表示前の補助処理は失敗しても握りつぶし、必ず showNotification を呼ぶ
      // （userVisibleOnly の購読で通知を出さないと、汎用の通知が出たり購読が失効したりする）
      try {
        await closeOlderDigests(options.tag);
      } catch (e) {
        // 何もしない
      }
      await self.registration.showNotification(title, options);
    })()
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data;
  const targetUrl = normalizeTargetUrl(data && typeof data === 'object' ? data.url : undefined);

  event.waitUntil(
    (async () => {
      const clientList = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const targetPathname = new URL(targetUrl, self.location.origin).pathname;

      for (const client of clientList) {
        let clientUrl;
        try {
          clientUrl = new URL(client.url);
        } catch (e) {
          continue;
        }
        if (clientUrl.origin !== self.location.origin || clientUrl.pathname !== targetPathname) continue;

        // 同じパス名のタブは前面に出すだけ（移動しない。書きかけを消さない）。
        // タブが既に見えていた場合は visibilitychange が起きないので、postMessage で取り直させる
        try {
          const focused = await client.focus();
          (focused || client).postMessage({ type: 'notification-clicked', url: targetUrl });
          return;
        } catch (e) {
          // タブが閉じたなど。新しいタブに落とす
          break;
        }
      }

      await self.clients.openWindow(targetUrl);
    })()
  );
});
