import { describe, it, expect } from 'vitest'
import { parseAlertPatchBody, isAlertPatchAction, isUuid } from '@/lib/alerts/validation'

describe('parseAlertPatchBody', () => {
  it('acknowledge / reopen を受理する', () => {
    expect(parseAlertPatchBody({ action: 'acknowledge' })).toEqual({
      ok: true,
      value: { action: 'acknowledge' },
    })
    expect(parseAlertPatchBody({ action: 'reopen' })).toEqual({
      ok: true,
      value: { action: 'reopen' },
    })
  })

  it('余分な項目は無視し、action だけを返す（status や trainer_id を body から受け取らない）', () => {
    expect(
      parseAlertPatchBody({ action: 'acknowledge', status: 'resolved', trainer_id: 'someone' })
    ).toEqual({ ok: true, value: { action: 'acknowledge' } })
  })

  it('それ以外の action は INVALID_ACTION', () => {
    for (const body of [
      { action: 'resolve' },
      { action: 'ACKNOWLEDGE' },
      { action: '' },
      { action: 1 },
      { action: null },
      {},
    ]) {
      expect(parseAlertPatchBody(body)).toEqual({ ok: false, error: 'INVALID_ACTION' })
    }
  })

  it('オブジェクトでない body は INVALID_BODY', () => {
    expect(parseAlertPatchBody(null)).toEqual({ ok: false, error: 'INVALID_BODY' })
    expect(parseAlertPatchBody(undefined)).toEqual({ ok: false, error: 'INVALID_BODY' })
    expect(parseAlertPatchBody('acknowledge')).toEqual({ ok: false, error: 'INVALID_BODY' })
    expect(parseAlertPatchBody([{ action: 'acknowledge' }])).toEqual({
      ok: false,
      error: 'INVALID_BODY',
    })
  })
})

describe('isAlertPatchAction', () => {
  it('2つの値だけを受理する', () => {
    expect(isAlertPatchAction('acknowledge')).toBe(true)
    expect(isAlertPatchAction('reopen')).toBe(true)
    expect(isAlertPatchAction('open')).toBe(false)
    expect(isAlertPatchAction(undefined)).toBe(false)
  })
})

describe('isUuid', () => {
  it('uuid の形だけを受理する（大文字も可）', () => {
    expect(isUuid('0b6f8e1c-3a2d-4c5e-9f10-1234567890ab')).toBe(true)
    expect(isUuid('0B6F8E1C-3A2D-4C5E-9F10-1234567890AB')).toBe(true)
    expect(isUuid('alert-1')).toBe(false)
    expect(isUuid('0b6f8e1c-3a2d-4c5e-9f10-1234567890ab ')).toBe(false)
    expect(isUuid("0b6f8e1c-3a2d-4c5e-9f10-1234567890ab' OR '1'='1")).toBe(false)
    expect(isUuid(undefined)).toBe(false)
  })
})
