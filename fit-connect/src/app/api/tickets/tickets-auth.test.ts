import { describe, it, expect, vi, beforeEach } from 'vitest'
import { NextRequest } from 'next/server'

const mocks = vi.hoisted(() => ({
  requireTrainer: vi.fn(),
  trainerOwnsClient: vi.fn(),
  trainerOwnsTicket: vi.fn(),
  trainerOwnsTemplate: vi.fn(),
  adminFrom: vi.fn(),
}))

vi.mock('@/lib/api/guards', async () => {
  const { NextResponse } = await import('next/server')
  return {
    requireTrainer: mocks.requireTrainer,
    trainerOwnsClient: mocks.trainerOwnsClient,
    trainerOwnsTicket: mocks.trainerOwnsTicket,
    trainerOwnsTemplate: mocks.trainerOwnsTemplate,
    notFoundResponse: () =>
      NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 }),
  }
})

vi.mock('@/lib/supabaseAdmin', () => ({
  supabaseAdmin: { from: mocks.adminFrom },
}))

import { POST as createTicket } from '@/app/api/tickets/route'
import {
  PUT as updateTicket,
  DELETE as deleteTicket,
} from '@/app/api/tickets/[id]/route'
import { POST as issueTicket } from '@/app/api/tickets/issue/route'
import { GET as getAllTickets } from '@/app/api/tickets/all/route'

const UNAUTHORIZED = async () => {
  const { NextResponse } = await import('next/server')
  return {
    user: null,
    response: NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 }),
  }
}
const AS_TRAINER = { user: { id: 'trainer-1' }, response: null }

const jsonRequest = (url: string, body: unknown, method = 'POST') =>
  new NextRequest(`http://localhost${url}`, {
    method,
    body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json' },
  })

// [id]/route.ts のシグネチャに合わせる（Next.js 15: params は Promise）
const paramsOf = (id: string) => ({ params: Promise.resolve({ id }) })

beforeEach(() => {
  mocks.requireTrainer.mockReset()
  mocks.trainerOwnsClient.mockReset()
  mocks.trainerOwnsTicket.mockReset()
  mocks.trainerOwnsTemplate.mockReset()
  mocks.adminFrom.mockReset()
})

describe('POST /api/tickets', () => {
  it('未認証なら 401 で DB に触れない', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await createTicket(
      jsonRequest('/api/tickets', { clientId: 'victim-client' })
    )
    expect(res.status).toBe(401)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('他トレーナーの clientId なら 404 で DB 書き込みしない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsClient.mockResolvedValue(false)
    const res = await createTicket(
      jsonRequest('/api/tickets', {
        clientId: 'victim-client',
        ticketName: 'x',
        ticketType: 'session',
        totalSessions: 1,
      })
    )
    expect(res.status).toBe(404)
    expect(mocks.trainerOwnsClient).toHaveBeenCalledWith(
      'trainer-1',
      'victim-client'
    )
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})

describe('PUT /api/tickets/[id]', () => {
  it('未認証なら 401 で DB に触れない', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await updateTicket(
      jsonRequest('/api/tickets/ticket-1', { ticketName: 'x' }, 'PUT'),
      paramsOf('ticket-1')
    )
    expect(res.status).toBe(401)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('他トレーナーのチケットなら 404 で DB 更新しない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsTicket.mockResolvedValue(false)
    const res = await updateTicket(
      jsonRequest('/api/tickets/victim-ticket', { ticketName: 'x' }, 'PUT'),
      paramsOf('victim-ticket')
    )
    expect(res.status).toBe(404)
    expect(mocks.trainerOwnsTicket).toHaveBeenCalledWith(
      'trainer-1',
      'victim-ticket'
    )
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})

describe('DELETE /api/tickets/[id]', () => {
  it('未認証なら 401 で DB に触れない', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await deleteTicket(
      new NextRequest('http://localhost/api/tickets/ticket-1', {
        method: 'DELETE',
      }),
      paramsOf('ticket-1')
    )
    expect(res.status).toBe(401)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('他トレーナーのチケットなら 404 で DB 削除しない', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsTicket.mockResolvedValue(false)
    const res = await deleteTicket(
      new NextRequest('http://localhost/api/tickets/victim-ticket', {
        method: 'DELETE',
      }),
      paramsOf('victim-ticket')
    )
    expect(res.status).toBe(404)
    expect(mocks.trainerOwnsTicket).toHaveBeenCalledWith(
      'trainer-1',
      'victim-ticket'
    )
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})

describe('POST /api/tickets/issue', () => {
  it('未認証なら 401', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await issueTicket(
      jsonRequest('/api/tickets/issue', { templateId: 'tpl', clientId: 'c' })
    )
    expect(res.status).toBe(401)
  })

  it('他トレーナーの template なら 404', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsTemplate.mockResolvedValue(false)
    mocks.trainerOwnsClient.mockResolvedValue(true)
    const res = await issueTicket(
      jsonRequest('/api/tickets/issue', {
        templateId: 'victim-tpl',
        clientId: 'c1',
      })
    )
    expect(res.status).toBe(404)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })

  it('template は自分のものでも他トレーナーの client なら 404', async () => {
    mocks.requireTrainer.mockResolvedValue(AS_TRAINER)
    mocks.trainerOwnsTemplate.mockResolvedValue(true)
    mocks.trainerOwnsClient.mockResolvedValue(false)
    const res = await issueTicket(
      jsonRequest('/api/tickets/issue', {
        templateId: 'tpl-1',
        clientId: 'victim-client',
      })
    )
    expect(res.status).toBe(404)
    expect(mocks.trainerOwnsClient).toHaveBeenCalledWith(
      'trainer-1',
      'victim-client'
    )
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})

describe('GET /api/tickets/all', () => {
  it('未認証なら 401', async () => {
    mocks.requireTrainer.mockImplementation(UNAUTHORIZED)
    const res = await getAllTickets()
    expect(res.status).toBe(401)
    expect(mocks.adminFrom).not.toHaveBeenCalled()
  })
})
