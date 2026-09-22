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
import { getUnrepliedClients, parseUnrepliedClients } from '@/lib/supabase/getUnrepliedClients'

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

const unrepliedRow = (overrides: Record<string, unknown> = {}) => ({
  client_id: 'client-1',
  client_name: 'たなか',
  profile_image_url: 'client-1/avatar.png',
  unreplied_since: '2026-09-12T15:00:00+00:00',
  latest_unreplied_at: '2026-09-13T01:00:00+00:00',
  unreplied_count: 2,
  ...overrides,
})

describe('getTriageBadgeCount', () => {
  it('open のアラートがある顧客の数（同じ顧客は1人）', async () => {
    mocks.result = {
      data: [{ client_id: 'a' }, { client_id: 'a' }, { client_id: 'b' }],
      error: null,
    }
    mocks.rpc.mockResolvedValue({ data: [], error: null })
    expect(await getTriageBadgeCount()).toEqual({ count: 2, complete: true })
    expect(callsOf('from')).toEqual([['alerts']])
    expect(callsOf('eq')).toEqual([['status', 'open']])
    const [[columns]] = callsOf('select') as [[string]]
    expect(columns).toContain('clients!inner')
  })

  it('未返信の顧客を合わせた和集合の人数（アラートと未返信の両方がある顧客は1人）', async () => {
    mocks.result = { data: [{ client_id: 'a' }, { client_id: 'b' }], error: null }
    mocks.rpc.mockResolvedValue({
      data: [unrepliedRow({ client_id: 'b' }), unrepliedRow({ client_id: 'c' })],
      error: null,
    })
    expect(await getTriageBadgeCount()).toEqual({ count: 3, complete: true })
    expect(mocks.rpc).toHaveBeenCalledWith('get_unreplied_clients_for_trainer')
  })

  it('アラートと未返信は並列に取る（片方の応答を待ってからもう片方を始めない）', async () => {
    let resolveRpc: (value: unknown) => void = () => {}
    mocks.rpc.mockReturnValue(new Promise((resolve) => (resolveRpc = resolve)))
    mocks.result = { data: [{ client_id: 'a' }], error: null }

    const pending = getTriageBadgeCount()
    // RPC が応答する前に、アラートの取得も始まっている
    expect(callsOf('from')).toEqual([['alerts']])
    expect(mocks.rpc).toHaveBeenCalledTimes(1)
    resolveRpc({ data: [unrepliedRow({ client_id: 'z' })], error: null })
    expect(await pending).toEqual({ count: 2, complete: true })
  })

  it('0件なら 0', async () => {
    mocks.result = { data: [], error: null }
    mocks.rpc.mockResolvedValue({ data: [], error: null })
    expect(await getTriageBadgeCount()).toEqual({ count: 0, complete: true })
  })

  it('未返信だけ失敗したら、open のアラートがある顧客の人数を complete: false で返す（throw しない）', async () => {
    // migration 未適用（PGRST202）など。表示直後でもアラートの顧客をバッジから消さないため
    mocks.result = { data: [{ client_id: 'a' }, { client_id: 'b' }, { client_id: 'a' }], error: null }
    mocks.rpc.mockResolvedValue({
      data: null,
      error: { code: 'PGRST202', message: 'Could not find the function get_unreplied_clients_for_trainer' },
    })
    expect(await getTriageBadgeCount()).toEqual({ count: 2, complete: false })
  })

  it('アラートだけ失敗したら、未返信の顧客の人数を complete: false で返す', async () => {
    mocks.result = { data: null, error: { message: 'x' } }
    mocks.rpc.mockResolvedValue({ data: [unrepliedRow({ client_id: 'c' })], error: null })
    expect(await getTriageBadgeCount()).toEqual({ count: 1, complete: false })
  })

  it('アラートと未返信の両方とも失敗したら throw（ストアは前の値のまま残す）', async () => {
    mocks.result = { data: null, error: { message: 'x' } }
    mocks.rpc.mockResolvedValue({ data: null, error: { message: 'y' } })
    await expect(getTriageBadgeCount()).rejects.toBeTruthy()
  })
})

describe('getUnrepliedClients', () => {
  it('引数なしで RPC を呼び（trainer_id を渡さない）、行を型に揃える', async () => {
    mocks.rpc.mockResolvedValue({ data: [unrepliedRow()], error: null })
    expect(await getUnrepliedClients()).toEqual([
      {
        client_id: 'client-1',
        client_name: 'たなか',
        profile_image_url: 'client-1/avatar.png',
        unreplied_since: '2026-09-12T15:00:00+00:00',
        latest_unreplied_at: '2026-09-13T01:00:00+00:00',
        unreplied_count: 2,
      },
    ])
    expect(mocks.rpc).toHaveBeenCalledWith('get_unreplied_clients_for_trainer')
    expect(mocks.rpc.mock.calls[0]).toHaveLength(1)
  })

  it('0行なら空、失敗は throw（空の一覧と区別するため）', async () => {
    mocks.rpc.mockResolvedValue({ data: [], error: null })
    expect(await getUnrepliedClients()).toEqual([])

    mocks.rpc.mockResolvedValue({ data: null, error: { message: 'x' } })
    await expect(getUnrepliedClients()).rejects.toEqual({ message: 'x' })
  })
})

describe('parseUnrepliedClients', () => {
  it('件数が文字列（bigint）で届いても数える。読めなければ 1（行がある = 1件以上）', () => {
    const [a, b] = parseUnrepliedClients([
      unrepliedRow({ client_id: 'a', unreplied_count: '3' }),
      unrepliedRow({ client_id: 'b', unreplied_count: null }),
    ])
    expect(a.unreplied_count).toBe(3)
    expect(b.unreplied_count).toBe(1)
  })

  it('名前・アバターが空なら空文字 / null', () => {
    const [row] = parseUnrepliedClients([
      unrepliedRow({ client_name: null, profile_image_url: '' }),
    ])
    expect(row.client_name).toBe('')
    expect(row.profile_image_url).toBeNull()
  })

  it('最新の時刻が読めなければ最初の時刻で代え、最初の時刻が読めなければ最新の時刻で代える', () => {
    const [a, b] = parseUnrepliedClients([
      unrepliedRow({ client_id: 'a', latest_unreplied_at: null }),
      unrepliedRow({ client_id: 'b', unreplied_since: 'broken' }),
    ])
    expect(a.latest_unreplied_at).toBe('2026-09-12T15:00:00+00:00')
    expect(b.unreplied_since).toBe('2026-09-13T01:00:00+00:00')
  })

  it('client_id が無い行・時刻がどちらも読めない行・2行目以降の同じ顧客は落とす', () => {
    const rows = parseUnrepliedClients([
      unrepliedRow({ client_id: null }),
      unrepliedRow({ client_id: 'x', unreplied_since: null, latest_unreplied_at: 'broken' }),
      unrepliedRow({ client_id: 'dup', unreplied_count: 1 }),
      unrepliedRow({ client_id: 'dup', unreplied_count: 9 }),
      null,
      'row',
    ])
    expect(rows.map((r) => [r.client_id, r.unreplied_count])).toEqual([['dup', 1]])
  })

  it('配列でなければ空', () => {
    expect(parseUnrepliedClients(null)).toEqual([])
    expect(parseUnrepliedClients({ client_id: 'a' })).toEqual([])
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
