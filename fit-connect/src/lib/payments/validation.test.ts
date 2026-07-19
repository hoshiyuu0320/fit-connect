import { describe, it, expect } from 'vitest'
import { parsePaymentPatchBody, isPriceYenInput } from '@/lib/payments/validation'

describe('parsePaymentPatchBody', () => {
  it('mark_paid: method + paidAt + receiptNumber を正規化して返す', () => {
    const result = parsePaymentPatchBody({
      action: 'mark_paid',
      method: 'bank_transfer',
      paidAt: '2026-07-12T03:00:00.000Z',
      receiptNumber: 'R-0001',
    })
    expect(result).toEqual({
      ok: true,
      value: {
        action: 'mark_paid',
        method: 'bank_transfer',
        paidAt: '2026-07-12T03:00:00.000Z',
        receiptNumber: 'R-0001',
      },
    })
  })

  it('mark_paid: paidAt / receiptNumber 省略時は null に正規化', () => {
    const result = parsePaymentPatchBody({ action: 'mark_paid', method: 'cash' })
    expect(result).toEqual({
      ok: true,
      value: {
        action: 'mark_paid',
        method: 'cash',
        paidAt: null,
        receiptNumber: null,
      },
    })
  })

  it('mark_paid: 不正な method は INVALID_METHOD', () => {
    expect(parsePaymentPatchBody({ action: 'mark_paid', method: 'paypay' })).toEqual({
      ok: false,
      error: 'INVALID_METHOD',
    })
    expect(parsePaymentPatchBody({ action: 'mark_paid' })).toEqual({
      ok: false,
      error: 'INVALID_METHOD',
    })
  })

  it('mark_paid: 解釈できない paidAt は INVALID_PAID_AT', () => {
    expect(
      parsePaymentPatchBody({ action: 'mark_paid', method: 'cash', paidAt: 'not-a-date' })
    ).toEqual({ ok: false, error: 'INVALID_PAID_AT' })
  })

  it('mark_paid: 文字列でない receiptNumber は INVALID_RECEIPT_NUMBER', () => {
    expect(
      parsePaymentPatchBody({ action: 'mark_paid', method: 'cash', receiptNumber: 123 })
    ).toEqual({ ok: false, error: 'INVALID_RECEIPT_NUMBER' })
  })

  it('mark_unpaid: そのまま受理', () => {
    expect(parsePaymentPatchBody({ action: 'mark_unpaid' })).toEqual({
      ok: true,
      value: { action: 'mark_unpaid' },
    })
  })

  it('update: note / dueDate / amountYen を受理（dueDate null で期日クリア）', () => {
    const result = parsePaymentPatchBody({
      action: 'update',
      note: '7月分',
      dueDate: null,
      amountYen: 5000,
    })
    expect(result).toEqual({
      ok: true,
      value: { action: 'update', note: '7月分', dueDate: null, amountYen: 5000 },
    })
  })

  it('update: 更新フィールドが1つも無ければ EMPTY_UPDATE', () => {
    expect(parsePaymentPatchBody({ action: 'update' })).toEqual({
      ok: false,
      error: 'EMPTY_UPDATE',
    })
  })

  it('update: 負数・小数の amountYen は INVALID_AMOUNT', () => {
    expect(parsePaymentPatchBody({ action: 'update', amountYen: -1 })).toEqual({
      ok: false,
      error: 'INVALID_AMOUNT',
    })
    expect(parsePaymentPatchBody({ action: 'update', amountYen: 100.5 })).toEqual({
      ok: false,
      error: 'INVALID_AMOUNT',
    })
  })

  it('update: YYYY-MM-DD 以外の dueDate は INVALID_DUE_DATE', () => {
    expect(parsePaymentPatchBody({ action: 'update', dueDate: '2026/07/12' })).toEqual({
      ok: false,
      error: 'INVALID_DUE_DATE',
    })
  })

  it('未知の action は INVALID_ACTION', () => {
    expect(parsePaymentPatchBody({ action: 'refund' })).toEqual({
      ok: false,
      error: 'INVALID_ACTION',
    })
  })

  it('オブジェクトでない body は INVALID_BODY', () => {
    expect(parsePaymentPatchBody(null)).toEqual({ ok: false, error: 'INVALID_BODY' })
    expect(parsePaymentPatchBody('mark_paid')).toEqual({ ok: false, error: 'INVALID_BODY' })
    expect(parsePaymentPatchBody([{ action: 'mark_unpaid' }])).toEqual({
      ok: false,
      error: 'INVALID_BODY',
    })
  })
})

describe('isPriceYenInput', () => {
  it('null と 0以上の整数を受理', () => {
    expect(isPriceYenInput(null)).toBe(true)
    expect(isPriceYenInput(0)).toBe(true)
    expect(isPriceYenInput(8800)).toBe(true)
  })

  it('負数・小数・文字列・undefined は拒否', () => {
    expect(isPriceYenInput(-100)).toBe(false)
    expect(isPriceYenInput(100.5)).toBe(false)
    expect(isPriceYenInput('8800')).toBe(false)
    expect(isPriceYenInput(undefined)).toBe(false)
  })
})
