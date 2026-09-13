import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'

type Call = { method: string; args: unknown[] }

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  // select → eq の結果（await されたときに返す）
  result: { data: null as unknown, error: null as unknown },
  calls: [] as Array<{ method: string; args: unknown[] }>,
}))

vi.mock('@/lib/supabase', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}))

import { getOpenAlerts } from '@/lib/supabase/getOpenAlerts'
import { getTriageBadgeCount } from '@/lib/supabase/getTriageBadgeCount'
import { getAlertDetectionStatus } from '@/lib/supabase/getAlertDetectionStatus'

/** ブラウザ用 supabase のクエリビルダを模す（await すると mocks.result を返す） */
function makeBuilder(table: string) {
  mocks.calls.push({ method: 'from', args: [table] })
  const builder: Record<string, unknown> = {}
  for (const method of ['select', 'eq', 'order']) {
    builder[method] = (...args: unknown[]) => {
      mocks.calls.push({ method, args })
      return builder
    }
  }
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
    Promise.resolve(mocks.result).then(resolve, reject)
  return builder
}

let consoleError: ReturnType<typeof vi.spyOn>

const callsOf = (method: string): Call['args'][] =>
  mocks.calls.filter((call) => call.method === method).map((call) => call.args)

const row = (overrides: Record<string, unknown> = {}) => ({
  id: 'alert-1',
  client_id: 'client-1',
  alert_type: 'record_gap',
  severity: 'medium',
  status: 'open',
  payload: { v: 1 },
  first_detected_on: '2026-09-12',
  surfaced_on: '2026-09-12',
  last_detected_on: '2026-09-13',
  acknowledged_at: null,
  reopened_count: 0,
  clients: { name: 'たなか', profile_image_url: 'client-1/avatar.png' },
  ...overrides,
})

beforeEach(() => {
  mocks.from.mockReset()
  mocks.from.mockImplementation(makeBuilder)
  mocks.rpc.mockReset()
  mocks.result = { data: null, error: null }
  mocks.calls.length = 0
  // 失敗ケースで取得関数が出す console.error を黙らせる
  consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
})

afterEach(() => {
  consoleError.mockRestore()
})

describe('getOpenAlerts', () => {
  it('open だけを取り、trainer_id では絞らない（RLS に任せる）。顧客は clients!inner で埋め込む', async () => {
    mocks.result = { data: [row()], error: null }
    const alerts = await getOpenAlerts()

    expect(callsOf('from')).toEqual([['alerts']])
    expect(callsOf('eq')).toEqual([['status', 'open']])
    const [[columns]] = callsOf('select') as [[string]]
    expect(columns.replace(/\s+/g, '')).toContain('clients!inner(name,profile_image_url)')

    expect(alerts).toEqual([
      {
        id: 'alert-1',
        client_id: 'client-1',
        alert_type: 'record_gap',
        severity: 'medium',
        status: 'open',
        payload: { v: 1 },
        first_detected_on: '2026-09-12',
        surfaced_on: '2026-09-12',
        last_detected_on: '2026-09-13',
        acknowledged_at: null,
        reopened_count: 0,
        client_name: 'たなか',
        client_profile_image_url: 'client-1/avatar.png',
      },
    ])
  })

  it('埋め込みが配列で届いても顧客名を取り出す', async () => {
    mocks.result = {
      data: [row({ clients: [{ name: 'さとう', profile_image_url: null }] })],
      error: null,
    }
    const [alert] = await getOpenAlerts()
    expect(alert.client_name).toBe('さとう')
    expect(alert.client_profile_image_url).toBeNull()
  })

  it('失敗は throw する（空の一覧と区別するため）', async () => {
    mocks.result = { data: null, error: { message: 'relation "alerts" does not exist' } }
    await expect(getOpenAlerts()).rejects.toEqual({ message: 'relation "alerts" does not exist' })
  })
})

describe('getTriageBadgeCount', () => {
  it('open のアラートがある顧客の数（同じ顧客は1人）', async () => {
    mocks.result = {
      data: [{ client_id: 'a' }, { client_id: 'a' }, { client_id: 'b' }],
      error: null,
    }
    expect(await getTriageBadgeCount()).toBe(2)
    expect(callsOf('from')).toEqual([['alerts']])
    expect(callsOf('eq')).toEqual([['status', 'open']])
    const [[columns]] = callsOf('select') as [[string]]
    expect(columns).toContain('clients!inner')
  })

  it('0件なら 0、失敗は throw', async () => {
    mocks.result = { data: [], error: null }
    expect(await getTriageBadgeCount()).toBe(0)

    mocks.result = { data: null, error: { message: 'x' } }
    await expect(getTriageBadgeCount()).rejects.toBeTruthy()
  })
})

describe('getAlertDetectionStatus', () => {
  it('引数なしで RPC を呼び、1行目を型に揃える', async () => {
    mocks.rpc.mockResolvedValue({
      data: [
        {
          enabled: false,
          last_succeeded_at: null,
          last_target_date: null,
          monitored_count: 1,
          excluded_no_account: 9,
          excluded_not_started: 3,
          excluded_inactive: 0,
        },
      ],
      error: null,
    })
    expect(await getAlertDetectionStatus()).toEqual({
      enabled: false,
      last_succeeded_at: null,
      last_target_date: null,
      monitored_count: 1,
      excluded_no_account: 9,
      excluded_not_started: 3,
      excluded_inactive: 0,
    })
    expect(mocks.rpc).toHaveBeenCalledWith('get_alert_detection_status')
  })

  it('0行（トレーナーでない）は null、失敗は throw', async () => {
    mocks.rpc.mockResolvedValue({ data: [], error: null })
    expect(await getAlertDetectionStatus()).toBeNull()

    mocks.rpc.mockResolvedValue({ data: null, error: { message: 'x' } })
    await expect(getAlertDetectionStatus()).rejects.toBeTruthy()
  })
})
