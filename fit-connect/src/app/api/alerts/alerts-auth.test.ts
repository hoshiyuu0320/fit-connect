import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NextRequest } from 'next/server'

type Call = { method: string; args: unknown[] }
type ChainRecord = { table: string; calls: Call[] }

const mocks = vi.hoisted(() => ({
  requireTrainer: vi.fn(),
  trainerOwnsClient: vi.fn(),
  adminFrom: vi.fn(),
  // maybeSingle() が順に返す結果のキュー
  results: [] as Array<{ data: unknown; error: unknown }>,
  // from() ごとに、呼ばれたメソッドと引数の記録
  chains: [] as Array<{ table: string; calls: Array<{ method: string; args: unknown[] }> }>,
}))

vi.mock('@/lib/api/guards', async () => {
  const { NextResponse } = await import('next/server')
  return {
    requireTrainer: mocks.requireTrainer,
    trainerOwnsClient: mocks.trainerOwnsClient,
    notFoundResponse: () =>
      NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 }),
  }
})

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: { from: mocks.adminFrom },
}))

import { PATCH } from '@/app/api/alerts/[id]/route'

/** supabaseAdmin.from(table) のクエリビルダを模す（呼ばれたメソッドと引数を記録する） */
function makeChain(table: string) {
  const record: ChainRecord = { table, calls: [] }
  mocks.chains.push(record)
  const builder: Record<string, unknown> = {}
  for (const method of ['select', 'update', 'eq', 'is', 'neq']) {
    builder[method] = (...args: unknown[]) => {
      record.calls.push({ method, args })
      return builder
    }
  }
  builder.maybeSingle = () =>
    Promise.resolve(mocks.results.shift() ?? { data: null, error: null })
  return builder
}

const UNAUTHORIZED = async () => {
  const { NextResponse } = await import('next/server')
  return {
    user: null,
    response: NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 }),
  }
}
const AS_TRAINER = { user: { id: 'trainer-1' }, response: null }

const ALERT_ID = '0b6f8e1c-3a2d-4c5e-9f10-1234567890ab'
const OWN_ALERT = {
  data: { id: ALERT_ID, trainer_id: 'trainer-1', client_id: 'client-1' },
  error: null,
}

const patchRequest = (body: unknown, id = ALERT_ID) =>
  new NextRequest(`http://localhost/api/alerts/${id}`, {
    method: 'PATCH',
    body: typeof body === 'string' ? body : JSON.stringify(body),
    headers: { 'Content-Type': 'application/json' },
  })

// [id]/route.ts のシグネチャに合わせる（Next.js 15: params は Promise）
const paramsOf = (id: string) => ({ params: Promise.resolve({ id }) })

const callPatch = (body: unknown, id = ALERT_ID) => PATCH(patchRequest(body, id), paramsOf(id))

/** UPDATE を組み立てたクエリの記録（無ければ undefined） */
const updateChain = () =>
  mocks.chains.find((chain) => chain.calls.some((call) => call.method === 'update'))

const argsOf = (chain: ChainRecord | undefined, method: string) =>
  (chain?.calls ?? []).filter((call) => call.method === method).map((call) => call.args)

beforeEach(() => {
  mocks.requireTrainer.mockReset()
  mocks.trainerOwnsClient.mockReset()
  mocks.adminFrom.mockReset()
  mocks.adminFrom.mockImplementation(makeChain)
  mocks.results.length = 0
  mocks.chains.length = 0
})

describe('PATCH /api/alerts/[id]: 認証・入力', () => {
  it('未認証なら 401 で DB に触れない', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(401)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('action が不正なら 400 で DB に触れない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    for (const body of [{ action: 'resolve' }, {}, [{ action: 'acknowledge' }], null]) {
      const res = await callPatch(body)
      expect(res.status).toBe(400)
    }
    const res = await callPatch({ action: 'resolved' })
    expect(await res.json()).toEqual({ error: 'INVALID_ACTION' })
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('JSON として読めない body は 400 INVALID_BODY', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    const res = await callPatch('{not json')
    expect(res.status).toBe(400)
    expect(await res.json()).toEqual({ error: 'INVALID_BODY' })
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('uuid の形でない id は 404 で DB に触れない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    const res = await callPatch({ action: 'acknowledge' }, 'not-a-uuid')
    expect(res.status).toBe(404)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})

describe('PATCH /api/alerts/[id]: 所有（他人・不存在・担当変更済みは 404）', () => {
  it('存在しないアラートは 404 で UPDATE しない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.results.push({ data: null, error: null })
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(404)
    expect(updateChain()).toBeUndefined()
    expect(mocks.trainerOwnsClient).not.toHaveBeenCalled()
  })

  it('他のトレーナーのアラートは 404 で UPDATE しない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.results.push({
      data: { id: ALERT_ID, trainer_id: 'trainer-2', client_id: 'victim-client' },
      error: null,
    })
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(404)
    expect(await res.json()).toEqual({ error: 'NOT_FOUND' })
    expect(updateChain()).toBeUndefined()
  })

  it('自分が検知時の担当でも、顧客の担当が替わっていれば 404 で UPDATE しない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.results.push(OWN_ALERT)
    mocks.trainerOwnsClient.mockResolvedValue(false)
    const res = await callPatch({ action: 'reopen' })
    expect(res.status).toBe(404)
    expect(mocks.trainerOwnsClient).toHaveBeenCalledWith('trainer-1', 'client-1')
    expect(updateChain()).toBeUndefined()
  })

  it('対象はパスの id で引く（body の値は使わない）', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.results.push({ data: null, error: null })
    await callPatch({ action: 'acknowledge', id: 'other-alert', trainer_id: 'trainer-2' })
    expect(mocks.chains[0].table).toBe('alerts')
    expect(argsOf(mocks.chains[0], 'eq')).toEqual([['id', ALERT_ID]])
  })
})

describe('PATCH /api/alerts/[id]: 条件付き UPDATE と冪等', () => {
  beforeEach(() => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsClient.mockResolvedValue(true)
  })

  it('acknowledge: open の行だけを acknowledged にし、acknowledged_at を入れる', async () => {
    mocks.results.push(OWN_ALERT, { data: { id: ALERT_ID, status: 'acknowledged' }, error: null })
    const res = await callPatch({ action: 'acknowledge', trainer_id: 'trainer-2' })

    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      status: 'ok',
      alert: { id: ALERT_ID, status: 'acknowledged' },
    })

    const chain = updateChain()
    expect(chain?.table).toBe('alerts')
    const [[values]] = argsOf(chain, 'update') as [[Record<string, unknown>]]
    expect(values.status).toBe('acknowledged')
    expect(typeof values.acknowledged_at).toBe('string')
    expect(Number.isNaN(new Date(values.acknowledged_at as string).getTime())).toBe(false)
    // trainer_id はセッションの値（body の trainer_id は使わない）
    expect(argsOf(chain, 'eq')).toEqual([
      ['id', ALERT_ID],
      ['trainer_id', 'trainer-1'],
      ['status', 'open'],
    ])
    expect(argsOf(chain, 'is')).toEqual([])
  })

  it('reopen: acknowledged かつ resolved_at が NULL の行だけを open に戻し、acknowledged_at を消す', async () => {
    mocks.results.push(OWN_ALERT, { data: { id: ALERT_ID, status: 'open' }, error: null })
    const res = await callPatch({ action: 'reopen' })

    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ status: 'ok', alert: { id: ALERT_ID, status: 'open' } })

    const chain = updateChain()
    expect(argsOf(chain, 'update')).toEqual([[{ status: 'open', acknowledged_at: null }]])
    expect(argsOf(chain, 'eq')).toEqual([
      ['id', ALERT_ID],
      ['trainer_id', 'trainer-1'],
      ['status', 'acknowledged'],
    ])
    expect(argsOf(chain, 'is')).toEqual([['resolved_at', null]])
  })

  it('二度押し（すでに acknowledged）は更新0行で、今の status を 200 で返す', async () => {
    mocks.results.push(
      OWN_ALERT,
      { data: null, error: null }, // 条件に合わず0行
      { data: { id: ALERT_ID, status: 'acknowledged' }, error: null }
    )
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      status: 'ok',
      alert: { id: ALERT_ID, status: 'acknowledged' },
    })
    expect(mocks.chains).toHaveLength(3)
  })

  it('検知が先に resolved にしていたら、元に戻さず resolved を 200 で返す', async () => {
    mocks.results.push(
      OWN_ALERT,
      { data: null, error: null },
      { data: { id: ALERT_ID, status: 'resolved' }, error: null }
    )
    const res = await callPatch({ action: 'reopen' })
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ status: 'ok', alert: { id: ALERT_ID, status: 'resolved' } })
  })

  it('更新0行のあと行が消えていたら（退会の CASCADE）404', async () => {
    mocks.results.push(OWN_ALERT, { data: null, error: null }, { data: null, error: null })
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(404)
  })

  it('取得・UPDATE・再取得のエラーは 500（中身は返さない）', async () => {
    mocks.results.push({ data: null, error: { message: 'db down' } })
    expect((await callPatch({ action: 'acknowledge' })).status).toBe(500)

    mocks.results.push(OWN_ALERT, { data: null, error: { message: 'db down' } })
    const res = await callPatch({ action: 'acknowledge' })
    expect(res.status).toBe(500)
    expect(await res.json()).toEqual({ error: 'INTERNAL_ERROR' })

    mocks.results.push(OWN_ALERT, { data: null, error: null }, { data: null, error: { message: 'x' } })
    expect((await callPatch({ action: 'acknowledge' })).status).toBe(500)
  })
})
