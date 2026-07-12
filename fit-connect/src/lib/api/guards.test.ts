import { describe, it, expect, vi, beforeEach } from 'vitest'

const mocks = vi.hoisted(() => ({
  getAuthenticatedUser: vi.fn(),
  // maybeSingle() が順に返す結果のキュー
  queryResults: [] as Array<{ data: unknown; error: unknown }>,
  fromCalls: [] as string[],
}))

vi.mock('@/lib/supabase/server', () => ({
  getAuthenticatedUser: mocks.getAuthenticatedUser,
}))

vi.mock('@/lib/supabaseAdmin', () => {
  const makeChain = () => {
    const chain: Record<string, unknown> = {}
    for (const m of ['select', 'eq']) {
      chain[m] = vi.fn(() => chain)
    }
    chain.maybeSingle = vi.fn(() =>
      Promise.resolve(mocks.queryResults.shift() ?? { data: null, error: null })
    )
    return chain
  }
  return {
    supabaseAdmin: {
      from: vi.fn((table: string) => {
        mocks.fromCalls.push(table)
        return makeChain()
      }),
    },
  }
})

import {
  requireTrainer,
  trainerOwnsClient,
  trainerOwnsTicket,
  trainerOwnsSubscription,
  trainerOwnsMessage,
  trainerOwnsAssignmentExercise,
} from '@/lib/api/guards'

describe('requireTrainer', () => {
  beforeEach(() => {
    mocks.getAuthenticatedUser.mockReset()
  })

  it('未認証なら 401 レスポンスを返す', async () => {
    mocks.getAuthenticatedUser.mockResolvedValue(null)
    const auth = await requireTrainer()
    expect(auth.user).toBeNull()
    expect(auth.response?.status).toBe(401)
    const body = await auth.response!.json()
    expect(body.error).toBe('UNAUTHORIZED')
  })

  it('認証済みなら user を返し response は null', async () => {
    mocks.getAuthenticatedUser.mockResolvedValue({ id: 'trainer-1' })
    const auth = await requireTrainer()
    expect(auth.user?.id).toBe('trainer-1')
    expect(auth.response).toBeNull()
  })
})

describe('ownership guards', () => {
  beforeEach(() => {
    mocks.queryResults.length = 0
    mocks.fromCalls.length = 0
  })

  it('trainerOwnsClient: 該当行があれば true', async () => {
    mocks.queryResults.push({ data: { client_id: 'c1' }, error: null })
    expect(await trainerOwnsClient('t1', 'c1')).toBe(true)
    expect(mocks.fromCalls).toEqual(['clients'])
  })

  it('trainerOwnsClient: 行なしなら false', async () => {
    mocks.queryResults.push({ data: null, error: null })
    expect(await trainerOwnsClient('t1', 'c1')).toBe(false)
  })

  it('trainerOwnsClient: DBエラーでも false', async () => {
    mocks.queryResults.push({ data: null, error: { message: 'boom' } })
    expect(await trainerOwnsClient('t1', 'c1')).toBe(false)
  })

  it('trainerOwnsTicket: ticket→client の2段検証で true', async () => {
    mocks.queryResults.push({ data: { client_id: 'c1' }, error: null }) // tickets
    mocks.queryResults.push({ data: { client_id: 'c1' }, error: null }) // clients
    expect(await trainerOwnsTicket('t1', 'ticket-1')).toBe(true)
    expect(mocks.fromCalls).toEqual(['tickets', 'clients'])
  })

  it('trainerOwnsTicket: チケット不在なら clients を引かず false', async () => {
    mocks.queryResults.push({ data: null, error: null })
    expect(await trainerOwnsTicket('t1', 'ticket-1')).toBe(false)
    expect(mocks.fromCalls).toEqual(['tickets'])
  })

  it('trainerOwnsSubscription: subscription→template の2段検証', async () => {
    mocks.queryResults.push({ data: { template_id: 'tpl-1' }, error: null })
    mocks.queryResults.push({ data: { id: 'tpl-1' }, error: null })
    expect(await trainerOwnsSubscription('t1', 'sub-1')).toBe(true)
    expect(mocks.fromCalls).toEqual(['ticket_subscriptions', 'ticket_templates'])
  })

  it('trainerOwnsMessage: sender_id 一致かつ sender_type=trainer のみ true', async () => {
    mocks.queryResults.push({
      data: { sender_id: 't1', sender_type: 'trainer' },
      error: null,
    })
    expect(await trainerOwnsMessage('t1', 'm1')).toBe(true)

    mocks.queryResults.push({
      data: { sender_id: 'other', sender_type: 'trainer' },
      error: null,
    })
    expect(await trainerOwnsMessage('t1', 'm1')).toBe(false)

    mocks.queryResults.push({
      data: { sender_id: 't1', sender_type: 'client' },
      error: null,
    })
    expect(await trainerOwnsMessage('t1', 'm1')).toBe(false)
  })

  it('trainerOwnsAssignmentExercise: exercise→assignment の2段検証', async () => {
    mocks.queryResults.push({ data: { assignment_id: 'a1' }, error: null })
    mocks.queryResults.push({ data: { id: 'a1' }, error: null })
    expect(await trainerOwnsAssignmentExercise('t1', 'ex-1')).toBe(true)
    expect(mocks.fromCalls).toEqual([
      'workout_assignment_exercises',
      'workout_assignments',
    ])
  })
})
