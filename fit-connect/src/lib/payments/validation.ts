/**
 * 支払記録 API の入力検証（純関数）。
 * API Route から分離してユニットテスト可能にしている。
 */

import type { PaymentMethod } from '@/types/payment'

export const PAYMENT_METHODS = [
  'cash',
  'bank_transfer',
  'card_external',
  'stripe',
] as const

export function isPaymentMethod(value: unknown): value is PaymentMethod {
  return (
    typeof value === 'string' &&
    (PAYMENT_METHODS as readonly string[]).includes(value)
  )
}

/** 0以上の整数か（金額入力の検証） */
export function isNonNegativeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0
}

/** priceYen 入力（0以上の整数 or null）の検証 */
export function isPriceYenInput(value: unknown): value is number | null {
  return value === null || isNonNegativeInteger(value)
}

/** YYYY-MM-DD 形式の日付文字列か */
export function isDateOnlyString(value: unknown): value is string {
  if (typeof value !== 'string') return false
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  return !Number.isNaN(new Date(`${value}T00:00:00Z`).getTime())
}

/** ISO 8601 として解釈できる日時文字列か */
export function isIsoDateTimeString(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length > 0 &&
    !Number.isNaN(new Date(value).getTime())
  )
}

// PATCH /api/payments/[id] の正規化済みアクション
export type PaymentPatchAction =
  | {
      action: 'mark_paid'
      method: PaymentMethod
      paidAt: string | null // null = サーバー側で now を採用
      receiptNumber: string | null
    }
  | { action: 'mark_unpaid' }
  | {
      action: 'update'
      note?: string
      dueDate?: string | null
      amountYen?: number
    }

export type PaymentPatchParseResult =
  | { ok: true; value: PaymentPatchAction }
  | { ok: false; error: string }

/**
 * PATCH /api/payments/[id] のリクエストボディを検証・正規化する。
 * 失敗時は { ok: false, error: 'CODE' }（API はそのまま 400 で返す）。
 */
export function parsePaymentPatchBody(body: unknown): PaymentPatchParseResult {
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return { ok: false, error: 'INVALID_BODY' }
  }
  const record = body as Record<string, unknown>
  const action = record.action

  if (action === 'mark_paid') {
    if (!isPaymentMethod(record.method)) {
      return { ok: false, error: 'INVALID_METHOD' }
    }
    if (record.paidAt !== undefined && !isIsoDateTimeString(record.paidAt)) {
      return { ok: false, error: 'INVALID_PAID_AT' }
    }
    if (
      record.receiptNumber !== undefined &&
      typeof record.receiptNumber !== 'string'
    ) {
      return { ok: false, error: 'INVALID_RECEIPT_NUMBER' }
    }
    return {
      ok: true,
      value: {
        action: 'mark_paid',
        method: record.method,
        paidAt: (record.paidAt as string | undefined) ?? null,
        receiptNumber: (record.receiptNumber as string | undefined) ?? null,
      },
    }
  }

  if (action === 'mark_unpaid') {
    return { ok: true, value: { action: 'mark_unpaid' } }
  }

  if (action === 'update') {
    const hasNote = record.note !== undefined
    const hasDueDate = record.dueDate !== undefined
    const hasAmount = record.amountYen !== undefined

    if (!hasNote && !hasDueDate && !hasAmount) {
      return { ok: false, error: 'EMPTY_UPDATE' }
    }
    if (hasNote && typeof record.note !== 'string') {
      return { ok: false, error: 'INVALID_NOTE' }
    }
    if (hasDueDate && record.dueDate !== null && !isDateOnlyString(record.dueDate)) {
      return { ok: false, error: 'INVALID_DUE_DATE' }
    }
    if (hasAmount && !isNonNegativeInteger(record.amountYen)) {
      return { ok: false, error: 'INVALID_AMOUNT' }
    }

    const value: Extract<PaymentPatchAction, { action: 'update' }> = {
      action: 'update',
    }
    if (hasNote) value.note = record.note as string
    if (hasDueDate) value.dueDate = record.dueDate as string | null
    if (hasAmount) value.amountYen = record.amountYen as number
    return { ok: true, value }
  }

  return { ok: false, error: 'INVALID_ACTION' }
}
