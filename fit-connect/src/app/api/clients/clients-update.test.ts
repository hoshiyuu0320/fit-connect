import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NextRequest } from 'next/server'

type Call = { method: string; args: unknown[] }
type ChainRecord = { table: string; calls: Call[] }

const mocks = vi.hoisted(() => ({
  requireTrainer: vi.fn(),
  trainerOwnsClient: vi.fn(),
  adminFrom: vi.fn(),
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

// updateClient はモックしない（ルート → updateClient → supabaseAdmin の実経路で、
// 最終的に DB に渡る UPDATE の対象とペイロードを検証する）
vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: { from: mocks.adminFrom },
}))

import { PUT } from '@/app/api/clients/[client_id]/route'

/** supabaseAdmin.from(table) のクエリビルダを模す（呼ばれたメソッドと引数を記録する） */
function makeChain(table: string) {
  const record: ChainRecord = { table, calls: [] }
  mocks.chains.push(record)
  const builder: Record<string, unknown> = {}
  for (const method of ['select', 'update', 'eq']) {
    builder[method] = (...args: unknown[]) => {
      record.calls.push({ method, args })
      return builder
    }
  }
  // DB と同じく「eq で絞った行に update の値を反映した行」を返す
  builder.single = () => {
    const values = record.calls.find((call) => call.method === 'update')?.args[0] as
      | Record<string, unknown>
      | undefined
    const clientId = record.calls.find(
      (call) => call.method === 'eq' && call.args[0] === 'client_id'
    )?.args[1]
    return Promise.resolve({ data: { client_id: clientId, ...values }, error: null })
  }
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

// trainer-1 が担当している顧客
const OWN_CLIENT_ID = '3f2a9c4e-7b1d-4e8a-9c6f-0a1b2c3d4e5f'
// 他のトレーナー（trainer-2）の顧客
const OTHER_CLIENT_ID = '8d7e6f5a-4b3c-4d2e-8f1a-9b8c7d6e5f4a'

// clients のうちトレーナーが編集してよい列（EditClientModal が送る8フィールド）
const ALLOWED_FIELDS = [
  'age',
  'gender',
  'occupation',
  'height',
  'target_weight',
  'purpose',
  'goal_description',
  'goal_deadline',
]

const putRequest = (body: unknown, clientId: string) =>
  new NextRequest(`http://localhost/api/clients/${clientId}`, {
    method: 'PUT',
    body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json' },
  })

// [client_id]/route.ts のシグネチャに合わせる（Next.js 15: params は Promise）
const paramsOf = (client_id: string) => ({ params: Promise.resolve({ client_id }) })

const callPut = (body: unknown, clientId = OWN_CLIENT_ID) =>
  PUT(putRequest(body, clientId), paramsOf(clientId))

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
  mocks.chains.length = 0
})

describe('PUT /api/clients/[client_id]', () => {
  beforeEach(() => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    // 所有は「渡された id」で判定する（trainer-1 が持つのは OWN だけ）
    mocks.trainerOwnsClient.mockImplementation(
      async (_trainerId: string, clientId: string) => clientId === OWN_CLIENT_ID
    )
  })

  it('body.clientId でパスの id を上書きできない（UPDATE の対象はパスの顧客だけ）', async () => {
    const res = await callPut({ clientId: OTHER_CLIENT_ID, age: 30, goal_description: 'x' })
    expect(res.status).toBe(200)

    const chain = updateChain()
    expect(chain?.table).toBe('clients')
    // 更新対象の絞り込みはパスで所有を検証した OWN の1回だけ
    expect(argsOf(chain, 'eq')).toEqual([['client_id', OWN_CLIENT_ID]])
    // どのクエリの eq にも他人の顧客 id が出てこない
    const eqValues = mocks.chains.flatMap((c) => argsOf(c, 'eq')).flat()
    expect(eqValues).not.toContain(OTHER_CLIENT_ID)
  })

  it('許可リスト外のキーは書き込まれず、更新対象にも影響しない', async () => {
    const res = await callPut({
      // 許可リスト外
      clientId: OTHER_CLIENT_ID,
      client_id: OTHER_CLIENT_ID,
      trainer_id: 'trainer-2',
      name: '乗っ取られた名前',
      profile_image_url: 'https://example.com/evil.png',
      line_user_id: 'U-evil',
      // 許可リスト内
      age: 41,
      height: 170.5,
      goal_description: '3か月で-5kg',
    })
    expect(res.status).toBe(200)

    const chain = updateChain()
    expect(chain?.table).toBe('clients')
    const [[values]] = argsOf(chain, 'update') as [[Record<string, unknown>]]
    // update() に渡るキーは許可リストの部分集合
    expect(Object.keys(values).filter((key) => !ALLOWED_FIELDS.includes(key))).toEqual([])
    // 送った許可済みフィールドの値はそのまま渡る
    expect(values).toMatchObject({ age: 41, height: 170.5, goal_description: '3か月で-5kg' })
    // clientId / client_id を混ぜても、書き込み先はパスの顧客のまま
    expect(argsOf(chain, 'eq')).toEqual([['client_id', OWN_CLIENT_ID]])
  })

  it('所有検証はパスの id で行う（body.clientId は使わない）', async () => {
    await callPut({ clientId: OTHER_CLIENT_ID, age: 30 })
    expect(mocks.trainerOwnsClient.mock.calls).toEqual([['trainer-1', OWN_CLIENT_ID]])
  })

  it('所有していないパスの顧客は、body.clientId に自分の顧客を入れても 404 で DB に触れない', async () => {
    const res = await callPut({ clientId: OWN_CLIENT_ID, age: 30 }, OTHER_CLIENT_ID)
    expect(res.status).toBe(404)
    expect(await res.json()).toEqual({ error: 'NOT_FOUND' })
    expect(mocks.trainerOwnsClient).toHaveBeenCalledWith('trainer-1', OTHER_CLIENT_ID)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('未認証なら 401 で DB に触れない', async () => {
    mocks.requireTrainer.mockReset()
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await callPut({ age: 30 })
    expect(res.status).toBe(401)
    expect(mocks.trainerOwnsClient).not.toHaveBeenCalled()
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('編集モーダルと同じ body（null を含む8フィールド）はそのまま OWN に書き込まれる', async () => {
    // EditClientModal の onSubmit が送る形（空欄は || null で null になる）
    const body = {
      age: 34,
      gender: 'female',
      occupation: null,
      height: 162.5,
      target_weight: 55,
      purpose: 'diet',
      goal_description: null,
      goal_deadline: null,
    }
    const res = await callPut(body)

    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      status: 'ok',
      data: { client_id: OWN_CLIENT_ID, ...body },
    })

    const chain = updateChain()
    expect(chain?.table).toBe('clients')
    // null も含めて8フィールドがそのまま渡る
    expect(argsOf(chain, 'update')).toStrictEqual([[body]])
    expect(argsOf(chain, 'eq')).toEqual([['client_id', OWN_CLIENT_ID]])
    expect(mocks.trainerOwnsClient.mock.calls).toEqual([['trainer-1', OWN_CLIENT_ID]])
  })
})
