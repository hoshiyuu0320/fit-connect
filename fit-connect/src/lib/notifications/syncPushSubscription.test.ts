import { describe, it, expect, vi } from 'vitest'
import { syncPushSubscription, type SubscriptionSnapshot, type SyncPushSubscriptionDeps } from './syncPushSubscription'

/** テスト用: バイト列 → base64url（パディング無し） */
function toBase64Url(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

const KEY = new Uint8Array(65).map((_, i) => (i === 0 ? 4 : (i * 31 + 5) % 256))
const KEY_B64URL = toBase64Url(KEY)
const OTHER_KEY = KEY.slice()
OTHER_KEY[10] = (OTHER_KEY[10] + 1) % 256

function snapshot(overrides: Partial<SubscriptionSnapshot> = {}): SubscriptionSnapshot {
  return {
    endpoint: 'https://push.example.test/sub/1',
    applicationServerKey: KEY.slice().buffer,
    p256dh: 'p256dh-value',
    auth: 'auth-value',
    ...overrides,
  }
}

function makeDeps(overrides: Partial<SyncPushSubscriptionDeps> = {}) {
  const calls: string[] = []
  const deps: SyncPushSubscriptionDeps = {
    vapidPublicKey: KEY_B64URL,
    getSubscription: vi.fn(async () => snapshot()),
    post: vi.fn(async () => {
      calls.push('post')
      return true
    }),
    del: vi.fn(async () => {
      calls.push('del')
      return true
    }),
    unsubscribe: vi.fn(async () => {
      calls.push('unsubscribe')
      return true
    }),
    ...overrides,
  }
  return { deps, calls }
}

describe('syncPushSubscription', () => {
  it('同じ鍵 → post を1回だけ呼び、reposted', async () => {
    const { deps, calls } = makeDeps()
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
    expect(deps.post).toHaveBeenCalledWith({
      endpoint: 'https://push.example.test/sub/1',
      p256dh: 'p256dh-value',
      auth: 'auth-value',
    })
  })

  it('購読の鍵が null（比べられない）→ post を1回だけ呼び、reposted', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: null })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
  })

  it('環境変数が壊れている（引用符つき）→ 比べられないので post だけ（自動で解除しない）', async () => {
    const { deps, calls } = makeDeps({ vapidPublicKey: `"${KEY_B64URL}"` })
    await expect(syncPushSubscription(deps)).resolves.toBe('reposted')
    expect(calls).toEqual(['post'])
  })

  it('違う鍵 → del → unsubscribe の順に呼び、post は呼ばない（purged）', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('purged')
    expect(calls).toEqual(['del', 'unsubscribe'])
    expect(deps.del).toHaveBeenCalledWith({ endpoint: 'https://push.example.test/sub/1' })
  })

  it.each([
    ['undefined', undefined],
    ['空文字', ''],
  ])('公開鍵が %s → 何もしない（noop）', async (_label, vapidPublicKey) => {
    const { deps, calls } = makeDeps({ vapidPublicKey })
    await expect(syncPushSubscription(deps)).resolves.toBe('noop')
    expect(calls).toEqual([])
    expect(deps.getSubscription).not.toHaveBeenCalled()
  })

  it('ブラウザに購読が無い → 何もしない（noop）', async () => {
    const { deps, calls } = makeDeps({ getSubscription: vi.fn(async () => null) })
    await expect(syncPushSubscription(deps)).resolves.toBe('noop')
    expect(calls).toEqual([])
  })

  it('post が失敗（false）→ failed', async () => {
    const { deps } = makeDeps({ post: vi.fn(async () => false) })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('post が例外 → failed', async () => {
    const { deps } = makeDeps({
      post: vi.fn(async () => {
        throw new Error('network')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('購読の鍵データ（p256dh / auth）が欠けている → post せず failed', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ auth: null })),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
  })

  it('違う鍵で del が失敗（false）→ unsubscribe を呼ばず failed', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      del: vi.fn(async () => false),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
    expect(deps.unsubscribe).not.toHaveBeenCalled()
  })

  it('違う鍵で del が例外 → unsubscribe を呼ばず failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      del: vi.fn(async () => {
        throw new Error('network')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(deps.unsubscribe).not.toHaveBeenCalled()
  })

  it('違う鍵で unsubscribe が失敗（false）→ failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      unsubscribe: vi.fn(async () => false),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('違う鍵で unsubscribe が例外 → failed', async () => {
    const { deps } = makeDeps({
      getSubscription: vi.fn(async () => snapshot({ applicationServerKey: OTHER_KEY.slice().buffer })),
      unsubscribe: vi.fn(async () => {
        throw new Error('boom')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
  })

  it('getSubscription が例外 → failed（何も送らない）', async () => {
    const { deps, calls } = makeDeps({
      getSubscription: vi.fn(async () => {
        throw new Error('no sw')
      }),
    })
    await expect(syncPushSubscription(deps)).resolves.toBe('failed')
    expect(calls).toEqual([])
  })
})
