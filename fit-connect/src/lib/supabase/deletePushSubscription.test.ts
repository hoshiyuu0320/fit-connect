import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  chains: [] as Array<{ table: string; calls: Array<{ method: string; args: unknown[] }> }>,
  results: {} as Record<string, { error: unknown } | Error>,
}))

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      const record = { table, calls: [] as Array<{ method: string; args: unknown[] }> }
      mocks.chains.push(record)
      const builder: Record<string, unknown> = {}
      for (const method of ['delete', 'eq']) {
        builder[method] = (...args: unknown[]) => {
          record.calls.push({ method, args })
          return builder
        }
      }
      builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => {
        const op = record.calls[0]?.method
        const result = mocks.results[`${table}.${op}`] ?? { error: null }
        if (result instanceof Error) return Promise.reject(result).then(resolve, reject)
        return Promise.resolve(result).then(resolve, reject)
      }
      return builder
    },
  },
}))

import { deletePushSubscription } from './deletePushSubscription'

const TRAINER_ID = '11111111-1111-4111-8111-111111111111'
const ENDPOINT = 'https://push.example.test/sub/abc'

describe('deletePushSubscription', () => {
  beforeEach(() => {
    mocks.chains.length = 0
    mocks.results = {}
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('device_tokens の自分の行（endpoint 単位）を消してから、旧 push_subscriptions を消す', async () => {
    await deletePushSubscription(TRAINER_ID, ENDPOINT)

    expect(mocks.chains.map((c) => `${c.table}.${c.calls[0]?.method}`)).toEqual([
      'device_tokens.delete',
      'push_subscriptions.delete',
    ])
    expect(mocks.chains[0].calls.filter((c) => c.method === 'eq').map((c) => c.args)).toEqual([
      ['user_id', TRAINER_ID],
      ['token', ENDPOINT],
    ])
    expect(mocks.chains[1].calls.filter((c) => c.method === 'eq').map((c) => c.args)).toEqual([
      ['trainer_id', TRAINER_ID],
      ['endpoint', ENDPOINT],
    ])
  })

  it('device_tokens の delete が失敗 → throw し、旧表は呼ばない', async () => {
    mocks.results['device_tokens.delete'] = { error: { message: 'delete failed' } }
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).rejects.toEqual({ message: 'delete failed' })
    expect(mocks.chains).toHaveLength(1)
  })

  it('旧 push_subscriptions の delete が失敗しても throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.delete'] = { error: { message: 'legacy failed' } }
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })

  it('旧 push_subscriptions の delete が例外でも throw しない', async () => {
    mocks.results['push_subscriptions.delete'] = new Error('legacy network')
    await expect(deletePushSubscription(TRAINER_ID, ENDPOINT)).resolves.toBeUndefined()
  })
})
