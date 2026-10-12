import { describe, it, expect, vi } from 'vitest'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'

/**
 * public/sw.js を Node の vm で読み込んで、イベントのハンドラを直接呼ぶ（設計書 §7.1・§10.3）。
 * vm の新しいコンテキストには URL も location も無いので sandbox から渡す。
 * vm の中で作ったオブジェクトは別の realm なので、比較は toEqual を使う（toStrictEqual は落ちうる）
 */
const SW_SOURCE = readFileSync(new URL('../../../public/sw.js', import.meta.url), 'utf8')
const ORIGIN = 'https://app.example.test'

type Handler = (event: unknown) => void

type FakeNotification = { tag: string; close: ReturnType<typeof vi.fn> }

type FakeWindowClient = {
  url: string
  focus: ReturnType<typeof vi.fn>
  postMessage: ReturnType<typeof vi.fn>
}

function loadSw(
  options: {
    notifications?: FakeNotification[]
    getNotifications?: () => Promise<FakeNotification[]>
    windows?: FakeWindowClient[]
  } = {}
) {
  const handlers = new Map<string, Handler>()
  const registration = {
    showNotification: vi.fn(async () => undefined),
    getNotifications: vi.fn(options.getNotifications ?? (async () => options.notifications ?? [])),
  }
  const clients = {
    matchAll: vi.fn(async () => options.windows ?? []),
    openWindow: vi.fn(async () => null),
    claim: vi.fn(async () => undefined),
  }
  const sandbox: Record<string, unknown> = {
    location: { origin: ORIGIN },
    URL,
    clients,
    registration,
    skipWaiting: vi.fn(),
    addEventListener: (type: string, handler: Handler) => {
      handlers.set(type, handler)
    },
  }
  sandbox.self = sandbox
  vm.createContext(sandbox)
  vm.runInContext(SW_SOURCE, sandbox)

  /** ハンドラを呼び、waitUntil に渡された Promise を待つ */
  async function dispatch(type: string, event: Record<string, unknown>) {
    const pending: Promise<unknown>[] = []
    const handler = handlers.get(type)
    if (!handler) throw new Error(`no handler for ${type}`)
    handler({ ...event, waitUntil: (p: Promise<unknown>) => pending.push(p) })
    await Promise.all(pending)
    return pending.length
  }

  function push(body: string | null) {
    return dispatch('push', {
      data:
        body === null
          ? null
          : {
              json: () => JSON.parse(body),
              text: () => body,
            },
    })
  }

  function click(data: unknown) {
    const notification = { data, close: vi.fn() }
    return dispatch('notificationclick', { notification }).then(() => notification)
  }

  return { sandbox, handlers, registration, clients, dispatch, push, click }
}

function shown(sw: ReturnType<typeof loadSw>) {
  expect(sw.registration.showNotification).toHaveBeenCalledTimes(1)
  const [title, options] = sw.registration.showNotification.mock.calls[0] as unknown as [
    string,
    Record<string, unknown> & { data: { url: string } },
  ]
  return { title, options }
}

function notification(tag: string): FakeNotification {
  return { tag, close: vi.fn() }
}

function windowClient(path: string, overrides: Partial<FakeWindowClient> = {}): FakeWindowClient {
  const client: FakeWindowClient = {
    url: `${ORIGIN}${path}`,
    focus: vi.fn(async () => client),
    postMessage: vi.fn(),
    ...overrides,
  }
  return client
}

describe('sw.js: install / activate', () => {
  it('install で skipWaiting を呼ぶ', async () => {
    const sw = loadSw()
    await sw.dispatch('install', {})
    expect(sw.sandbox.skipWaiting).toHaveBeenCalledTimes(1)
  })

  it('activate で clients.claim を waitUntil に渡す', async () => {
    const sw = loadSw()
    const count = await sw.dispatch('activate', {})
    expect(count).toBe(1)
    expect(sw.clients.claim).toHaveBeenCalledTimes(1)
  })

  it('SW_VERSION を持つ', () => {
    expect(SW_SOURCE).toMatch(/const SW_VERSION = '[^']+'/)
  })
})

describe('sw.js: push の URL', () => {
  it('data.url を使う', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ title: 't', body: 'b', data: { url: '/dashboard' } }))
    expect(shown(sw).options.data).toEqual({ url: '/dashboard' })
  })

  it('古い形の url を使う', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ title: 't', url: '/clients/abc?tab=sleep' }))
    expect(shown(sw).options.data).toEqual({ url: '/clients/abc?tab=sleep' })
  })

  it('data.url が url より優先される', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ url: '/old', data: { url: '/dashboard' } }))
    expect(shown(sw).options.data).toEqual({ url: '/dashboard' })
  })

  it('URL が無ければ /message（url の無い古いメッセージ通知の形）', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ title: '新着', body: 'x', data: { type: 'message', messageId: 'm1' } }))
    expect(shown(sw).options.data).toEqual({ url: '/message' })
  })

  it('自オリジンの絶対 URL はパスだけにする', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ data: { url: `${ORIGIN}/dashboard?x=1#top` } }))
    expect(shown(sw).options.data).toEqual({ url: '/dashboard?x=1#top' })
  })

  it.each([
    ['外部オリジン', 'https://evil.example.com/dashboard'],
    ['自オリジンの後ろに //', `${ORIGIN}//evil.com`],
    ['/.//', '/.//evil.com'],
    ['スキーム相対', '//evil.com'],
    ['javascript:', 'javascript:alert(1)'],
    ['data:', 'data:text/html,x'],
    ['バックスラッシュ', '/\\evil.com'],
    ['空文字', ''],
    ['数値', 123],
  ])('%s は /message になる', async (_label, url) => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ data: { url } }))
    expect(shown(sw).options.data).toEqual({ url: '/message' })
  })
})

describe('sw.js: push の tag と renotify', () => {
  it('payload.tag を最優先する', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ tag: 'top', data: { tag: 'inner', type: 'message' } }))
    expect(shown(sw).options).toMatchObject({ tag: 'top', renotify: true })
  })

  it('data.tag → data.type → default の順', async () => {
    const a = loadSw()
    await a.push(JSON.stringify({ data: { tag: 'client_alert:2026-10-04', type: 'client_alert' } }))
    expect(shown(a).options.tag).toBe('client_alert:2026-10-04')

    const b = loadSw()
    await b.push(JSON.stringify({ data: { type: 'message' } }))
    expect(shown(b).options.tag).toBe('message')

    const c = loadSw()
    await c.push(JSON.stringify({ title: 't' }))
    expect(shown(c).options.tag).toBe('default')
  })

  it('空文字・数値の tag は飛ばす', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ tag: '', data: { tag: 42, type: 'message' } }))
    expect(shown(sw).options.tag).toBe('message')
  })

  it('renotify: true を付ける', async () => {
    const sw = loadSw()
    await sw.push(JSON.stringify({ data: { type: 'message' } }))
    expect(shown(sw).options.renotify).toBe(true)
  })

  it('タイトル・本文・アイコン・requireInteraction は今と同じ', async () => {
    const sw = loadSw()
    await sw.push(
      JSON.stringify({
        title: '今日の対応があります',
        body: '新しく要確認 1名',
        data: { type: 'client_alert', url: '/dashboard', tag: 'client_alert:2026-10-04' },
      })
    )
    const { title, options } = shown(sw)
    expect(title).toBe('今日の対応があります')
    expect(options).toEqual({
      body: '新しく要確認 1名',
      icon: '/icon.svg',
      badge: '/icon.svg',
      data: { url: '/dashboard' },
      requireInteraction: false,
      tag: 'client_alert:2026-10-04',
      renotify: true,
    })
  })
})

describe('sw.js: 古いまとめを閉じる', () => {
  it('client_alert:<D> のときは、日付が古い client_alert: だけを閉じる', async () => {
    const older = notification('client_alert:2026-10-03')
    const same = notification('client_alert:2026-10-04')
    const newer = notification('client_alert:2026-10-05')
    const message = notification('message')
    const sw = loadSw({ notifications: [older, same, newer, message] })
    await sw.push(JSON.stringify({ data: { tag: 'client_alert:2026-10-04' } }))
    expect(older.close).toHaveBeenCalledTimes(1)
    expect(same.close).not.toHaveBeenCalled()
    expect(newer.close).not.toHaveBeenCalled()
    expect(message.close).not.toHaveBeenCalled()
    expect(sw.registration.showNotification).toHaveBeenCalledTimes(1)
  })

  it('過去日のまとめは、今日のまとめを閉じない', async () => {
    const today = notification('client_alert:2026-10-04')
    const sw = loadSw({ notifications: [today] })
    await sw.push(JSON.stringify({ data: { tag: 'client_alert:2026-10-01' } }))
    expect(today.close).not.toHaveBeenCalled()
  })

  it('メッセージの push は client_alert: の通知を閉じない（getNotifications も呼ばない）', async () => {
    const today = notification('client_alert:2026-10-04')
    const sw = loadSw({ notifications: [today] })
    await sw.push(JSON.stringify({ data: { type: 'message' } }))
    expect(today.close).not.toHaveBeenCalled()
    expect(sw.registration.getNotifications).not.toHaveBeenCalled()
  })

  it('getNotifications が reject しても showNotification を呼ぶ', async () => {
    const sw = loadSw({ getNotifications: async () => Promise.reject(new Error('boom')) })
    await sw.push(JSON.stringify({ title: 't', data: { tag: 'client_alert:2026-10-04' } }))
    expect(shown(sw).title).toBe('t')
  })
})

describe('sw.js: push の本文が JSON でない', () => {
  const FALLBACK = {
    icon: '/icon.svg',
    badge: '/icon.svg',
    data: { url: '/message' },
    requireInteraction: false,
    tag: 'default',
    renotify: true,
  }

  it('JSON でなければ、本文はテキストで今の既定', async () => {
    const sw = loadSw()
    await sw.push('plain text')
    const { title, options } = shown(sw)
    expect(title).toBe('新着メッセージ')
    expect(options).toEqual({ body: 'plain text', ...FALLBACK })
  })

  it.each([
    ['null', 'null'],
    ['文字列', '"hello"'],
    ['数値', '42'],
    ['配列', '[1,2]'],
  ])('JSON が %s なら今の既定', async (_label, body) => {
    const sw = loadSw()
    await sw.push(body)
    const { title, options } = shown(sw)
    expect(title).toBe('新着メッセージ')
    expect(options).toEqual({ body, ...FALLBACK })
  })

  it('本文が無い push は何もしない', async () => {
    const sw = loadSw()
    const count = await sw.push(null)
    expect(count).toBe(0)
    expect(sw.registration.showNotification).not.toHaveBeenCalled()
  })
})

describe('sw.js: notificationclick', () => {
  it('同じパス名のタブがあれば前面に出して notification-clicked を送るだけ（移動しない）', async () => {
    const dashboard = windowClient('/dashboard?from=x')
    const sw = loadSw({ windows: [dashboard] })
    const n = await sw.click({ url: '/dashboard' })
    expect(n.close).toHaveBeenCalledTimes(1)
    expect(sw.clients.matchAll).toHaveBeenCalledWith({ type: 'window', includeUncontrolled: true })
    expect(dashboard.focus).toHaveBeenCalledTimes(1)
    expect(dashboard.postMessage).toHaveBeenCalledTimes(1)
    expect(dashboard.postMessage.mock.calls[0][0]).toEqual({ type: 'notification-clicked', url: '/dashboard' })
    expect(sw.clients.openWindow).not.toHaveBeenCalled()
  })

  it('同じパス名のタブが無ければ新しいタブを開き、別のパスのタブは動かさない', async () => {
    const message = windowClient('/message')
    const sw = loadSw({ windows: [message] })
    await sw.click({ url: '/dashboard' })
    expect(message.focus).not.toHaveBeenCalled()
    expect(message.postMessage).not.toHaveBeenCalled()
    expect(sw.clients.openWindow).toHaveBeenCalledWith('/dashboard')
  })

  it('別オリジンの同じパス名のタブは使わない', async () => {
    const other = windowClient('/dashboard', { url: 'https://other.example.test/dashboard' })
    const sw = loadSw({ windows: [other] })
    await sw.click({ url: '/dashboard' })
    expect(other.focus).not.toHaveBeenCalled()
    expect(sw.clients.openWindow).toHaveBeenCalledWith('/dashboard')
  })

  it('focus() が reject したら openWindow に落ちる', async () => {
    const dashboard = windowClient('/dashboard', {
      focus: vi.fn(async () => Promise.reject(new Error('closed'))),
    })
    const sw = loadSw({ windows: [dashboard] })
    await sw.click({ url: '/dashboard' })
    expect(sw.clients.openWindow).toHaveBeenCalledWith('/dashboard')
  })

  it('postMessage が投げたら openWindow に落ちる', async () => {
    const dashboard = windowClient('/dashboard', {
      postMessage: vi.fn(() => {
        throw new Error('detached')
      }),
    })
    const sw = loadSw({ windows: [dashboard] })
    await sw.click({ url: '/dashboard' })
    expect(sw.clients.openWindow).toHaveBeenCalledWith('/dashboard')
  })

  it.each([
    ['外部オリジン', { url: 'https://evil.example.com/' }],
    ['//', { url: '//evil.com' }],
    ['自オリジンの後ろに //', { url: `${ORIGIN}//evil.com` }],
    ['url 無し（古いメッセージ通知）', { type: 'message', messageId: 'm1' }],
    ['data 無し', null],
  ])('notification.data.url が %s なら /message', async (_label, data) => {
    const sw = loadSw()
    await sw.click(data)
    expect(sw.clients.openWindow).toHaveBeenCalledWith('/message')
  })

  it('/message のタブがあれば、メッセージ通知のクリックでそれを前面に出す', async () => {
    const message = windowClient('/message')
    const sw = loadSw({ windows: [message] })
    await sw.click({ url: '/message' })
    expect(message.focus).toHaveBeenCalledTimes(1)
    expect(message.postMessage.mock.calls[0][0]).toEqual({ type: 'notification-clicked', url: '/message' })
    expect(sw.clients.openWindow).not.toHaveBeenCalled()
  })
})

describe('sw.js: メッセージ通知のクリックでその顧客の会話を開く', () => {
  // 設計書 docs/superpowers/specs/2026-10-12-message-notification-open-chat-design.md §5
  const CLIENT_ID = '11111111-2222-4333-8444-555555555555'
  const OTHER_CLIENT_ID = '66666666-7777-4888-9999-aaaaaaaaaaaa'
  const MESSAGE_URL = `/message?clientId=${CLIENT_ID}`

  it('push の data.url（/message?clientId=…）を通知の data に載せ、tag は message', async () => {
    const sw = loadSw()
    await sw.push(
      JSON.stringify({ title: 't', body: 'b', data: { type: 'message', messageId: 'm1', url: MESSAGE_URL } })
    )
    const { options } = shown(sw)
    expect(options.data).toEqual({ url: MESSAGE_URL })
    expect(options.tag).toBe('message')
  })

  it('タブが無ければ /message?clientId=… を新しいタブで開く', async () => {
    const sw = loadSw()
    await sw.click({ url: MESSAGE_URL })
    expect(sw.clients.openWindow).toHaveBeenCalledWith(MESSAGE_URL)
  })

  it('/message のタブがあれば、前面に出して url 付きの notification-clicked を送るだけ（移動しない）', async () => {
    const message = windowClient('/message')
    const sw = loadSw({ windows: [message] })
    await sw.click({ url: MESSAGE_URL })
    expect(message.focus).toHaveBeenCalledTimes(1)
    expect(message.postMessage).toHaveBeenCalledTimes(1)
    expect(message.postMessage.mock.calls[0][0]).toEqual({ type: 'notification-clicked', url: MESSAGE_URL })
    expect(sw.clients.openWindow).not.toHaveBeenCalled()
  })

  it('別の顧客の /message?clientId=… のタブでも同じ（パス名だけで照合し、クエリが違っても移動しない）', async () => {
    const message = windowClient(`/message?clientId=${OTHER_CLIENT_ID}`)
    const sw = loadSw({ windows: [message] })
    await sw.click({ url: MESSAGE_URL })
    expect(message.focus).toHaveBeenCalledTimes(1)
    expect(message.postMessage).toHaveBeenCalledTimes(1)
    expect(message.postMessage.mock.calls[0][0]).toEqual({ type: 'notification-clicked', url: MESSAGE_URL })
    expect(sw.clients.openWindow).not.toHaveBeenCalled()
  })

  it('/dashboard のタブだけなら /message?clientId=… を新しいタブで開き、dashboard のタブは動かさない', async () => {
    const dashboard = windowClient('/dashboard')
    const sw = loadSw({ windows: [dashboard] })
    await sw.click({ url: MESSAGE_URL })
    expect(sw.clients.openWindow).toHaveBeenCalledWith(MESSAGE_URL)
    expect(dashboard.focus).not.toHaveBeenCalled()
    expect(dashboard.postMessage).not.toHaveBeenCalled()
  })
})
