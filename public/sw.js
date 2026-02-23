// Service Worker for Web Push Notifications

self.addEventListener('push', (event) => {
  if (!event.data) return;

  let data;
  try {
    data = event.data.json();
  } catch (e) {
    data = {
      title: '新着メッセージ',
      body: event.data.text(),
      url: '/message',
    };
  }

  const options = {
    body: data.body || '',
    icon: '/icon.svg',
    badge: '/icon.svg',
    data: { url: data.url || '/message' },
    requireInteraction: false,
    tag: data.tag || 'default',
  };

  event.waitUntil(
    self.registration.showNotification(data.title || '新着メッセージ', options)
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || '/message';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // 既に開いているタブがあればフォーカス
      for (const client of clientList) {
        if (client.url.includes('/message') && 'focus' in client) {
          return client.focus();
        }
      }
      // なければ新しいタブで開く
      return clients.openWindow(targetUrl);
    })
  );
});
