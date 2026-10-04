import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

type Call = { method: string; args: unknown[] }
type ChainRecord = { table: string; calls: Call[] }

const mocks = vi.hoisted(() => ({
  // from() ごとに、呼ばれたメソッドと引数の記録
  chains: [] as Array<{ table: string; calls: Array<{ method: string; args: unknown[] }> }>,
  // `${table}.${最初の操作}` ごとに返す結果（既定は { error: null }）。Error なら reject する
  results: {} as Record<string, { error: unknown } | Error>,
}))

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: {
    from: (table: string) => {
      const record = { table, calls: [] as Array<{ method: string; args: unknown[] }> }
      mocks.chains.push(record)
      const builder: Record<string, unknown> = {}
      for (const method of ['upsert', 'delete', 'eq', 'neq']) {
        builder[method] = (...args: unknown[]) => {
          record.calls.push({ method, args })
          return builder
        }
      }
      // await されたときに結果を返す（PostgREST のクエリビルダと同じく thenable）
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

import { savePushSubscription } from './savePushSubscription'

const DATA = {
  trainerId: '11111111-1111-4111-8111-111111111111',
  endpoint: 'https://push.example.test/sub/abc',
  p256dh: 'p256dh-value',
  auth: 'auth-value',
}

function chain(index: number): ChainRecord {
  return mocks.chains[index] as ChainRecord
}

function call(record: ChainRecord, method: string): Call[] {
  return record.calls.filter((c) => c.method === method)
}

describe('savePushSubscription', () => {
  beforeEach(() => {
    mocks.chains.length = 0
    mocks.results = {}
    vi.spyOn(console, 'error').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('device_tokens に upsert → 同じ endpoint の他のトレーナーの行を delete → 旧 push_subscriptions に upsert の順', async () => {
    await savePushSubscription(DATA)

    expect(mocks.chains.map((c) => `${c.table}.${c.calls[0]?.method}`)).toEqual([
      'device_tokens.upsert',
      'device_tokens.delete',
      'push_subscriptions.upsert',
    ])

    const [upsertValues, upsertOptions] = call(chain(0), 'upsert')[0].args as [Record<string, unknown>, unknown]
    expect(upsertValues).toMatchObject({
      user_id: DATA.trainerId,
      user_type: 'trainer',
      platform: 'web_push',
      token: DATA.endpoint,
      web_push_p256dh: DATA.p256dh,
      web_push_auth: DATA.auth,
    })
    expect(typeof upsertValues.last_seen_at).toBe('string')
    expect(upsertOptions).toEqual({ onConflict: 'user_id,token' })

    const deleteChain = chain(1)
    expect(call(deleteChain, 'eq').map((c) => c.args)).toEqual(
      expect.arrayContaining([
        ['platform', 'web_push'],
        ['token', DATA.endpoint],
        ['user_type', 'trainer'],
      ]),
    )
    expect(call(deleteChain, 'eq')).toHaveLength(3)
    expect(call(deleteChain, 'neq').map((c) => c.args)).toEqual([['user_id', DATA.trainerId]])

    const [legacyValues, legacyOptions] = call(chain(2), 'upsert')[0].args as [Record<string, unknown>, unknown]
    expect(legacyValues).toMatchObject({
      trainer_id: DATA.trainerId,
      endpoint: DATA.endpoint,
      p256dh: DATA.p256dh,
      auth: DATA.auth,
    })
    expect(legacyOptions).toEqual({ onConflict: 'endpoint' })
  })

  it('device_tokens の upsert が失敗 → throw し、delete も旧表も呼ばない', async () => {
    mocks.results['device_tokens.upsert'] = { error: { message: 'upsert failed' } }
    await expect(savePushSubscription(DATA)).rejects.toEqual({ message: 'upsert failed' })
    expect(mocks.chains).toHaveLength(1)
  })

  it('他のトレーナーの行の delete が失敗 → throw し、旧表は呼ばない', async () => {
    mocks.results['device_tokens.delete'] = { error: { message: 'delete failed' } }
    await expect(savePushSubscription(DATA)).rejects.toEqual({ message: 'delete failed' })
    expect(mocks.chains.map((c) => c.table)).toEqual(['device_tokens', 'device_tokens'])
  })

  it('device_tokens の upsert が例外 → throw', async () => {
    mocks.results['device_tokens.upsert'] = new Error('network')
    await expect(savePushSubscription(DATA)).rejects.toThrow('network')
  })

  it('旧 push_subscriptions の upsert が失敗しても throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.upsert'] = { error: { message: 'legacy failed' } }
    await expect(savePushSubscription(DATA)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })

  it('旧 push_subscriptions の upsert が例外でも throw しない（console.error だけ）', async () => {
    mocks.results['push_subscriptions.upsert'] = new Error('legacy network')
    await expect(savePushSubscription(DATA)).resolves.toBeUndefined()
    expect(console.error).toHaveBeenCalled()
  })
})
