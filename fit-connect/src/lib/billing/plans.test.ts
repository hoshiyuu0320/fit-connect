import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import {
  PLANS,
  TRIAL_DAYS,
  getEffectivePlan,
  planFromPriceId,
} from '@/lib/billing/plans'

const DAY_MS = 24 * 60 * 60 * 1000

describe('PLANS / TRIAL_DAYS', () => {
  it('3プランが定義され、価格と顧客上限が仕様通り', () => {
    expect(PLANS.free).toMatchObject({ id: 'free', priceJpy: 0, maxClients: 3 })
    expect(PLANS.pro).toMatchObject({
      id: 'pro',
      priceJpy: 2980,
      maxClients: 10,
      recommended: true,
    })
    expect(PLANS.business).toMatchObject({
      id: 'business',
      priceJpy: 6980,
      maxClients: 30,
    })
  })

  it('トライアルは14日', () => {
    expect(TRIAL_DAYS).toBe(14)
  })
})

describe('getEffectivePlan', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-12T00:00:00.000Z'))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('free + トライアル期限が未来 → Pro トライアル中', () => {
    const trialEndsAt = new Date(Date.now() + 5 * DAY_MS).toISOString()
    expect(getEffectivePlan('free', trialEndsAt)).toEqual({
      plan: 'pro',
      isTrial: true,
      trialDaysLeft: 5,
    })
  })

  it('残り1時間でも trialDaysLeft は 1（切り上げ）', () => {
    const trialEndsAt = new Date(Date.now() + 60 * 60 * 1000).toISOString()
    expect(getEffectivePlan('free', trialEndsAt)).toEqual({
      plan: 'pro',
      isTrial: true,
      trialDaysLeft: 1,
    })
  })

  it('free + トライアル期限切れ → free', () => {
    const trialEndsAt = new Date(Date.now() - 1 * DAY_MS).toISOString()
    expect(getEffectivePlan('free', trialEndsAt)).toEqual({
      plan: 'free',
      isTrial: false,
      trialDaysLeft: null,
    })
  })

  it('free + 期限がちょうど今 → free（未来のみトライアル扱い）', () => {
    const trialEndsAt = new Date(Date.now()).toISOString()
    expect(getEffectivePlan('free', trialEndsAt)).toEqual({
      plan: 'free',
      isTrial: false,
      trialDaysLeft: null,
    })
  })

  it('free + trial_ends_at が null → free', () => {
    expect(getEffectivePlan('free', null)).toEqual({
      plan: 'free',
      isTrial: false,
      trialDaysLeft: null,
    })
  })

  it('free + 不正な日付文字列 → free', () => {
    expect(getEffectivePlan('free', 'not-a-date')).toEqual({
      plan: 'free',
      isTrial: false,
      trialDaysLeft: null,
    })
  })

  it('pro 契約中はトライアル期限に関係なく pro', () => {
    const future = new Date(Date.now() + 5 * DAY_MS).toISOString()
    expect(getEffectivePlan('pro', future)).toEqual({
      plan: 'pro',
      isTrial: false,
      trialDaysLeft: null,
    })
    expect(getEffectivePlan('pro', null)).toEqual({
      plan: 'pro',
      isTrial: false,
      trialDaysLeft: null,
    })
  })

  it('business 契約中は business', () => {
    expect(getEffectivePlan('business', null)).toEqual({
      plan: 'business',
      isTrial: false,
      trialDaysLeft: null,
    })
  })
})

describe('planFromPriceId', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('STRIPE_PRICE_PRO に一致 → pro', () => {
    vi.stubEnv('STRIPE_PRICE_PRO', 'price_pro_123')
    vi.stubEnv('STRIPE_PRICE_BUSINESS', 'price_biz_456')
    expect(planFromPriceId('price_pro_123')).toBe('pro')
  })

  it('STRIPE_PRICE_BUSINESS に一致 → business', () => {
    vi.stubEnv('STRIPE_PRICE_PRO', 'price_pro_123')
    vi.stubEnv('STRIPE_PRICE_BUSINESS', 'price_biz_456')
    expect(planFromPriceId('price_biz_456')).toBe('business')
  })

  it('どちらにも一致しない → null', () => {
    vi.stubEnv('STRIPE_PRICE_PRO', 'price_pro_123')
    vi.stubEnv('STRIPE_PRICE_BUSINESS', 'price_biz_456')
    expect(planFromPriceId('price_unknown')).toBeNull()
  })

  it('null / undefined / 空文字 → null', () => {
    vi.stubEnv('STRIPE_PRICE_PRO', 'price_pro_123')
    expect(planFromPriceId(null)).toBeNull()
    expect(planFromPriceId(undefined)).toBeNull()
    expect(planFromPriceId('')).toBeNull()
  })

  it('env 未設定なら一致判定しない（空 env と空 priceId が誤マッチしない）', () => {
    vi.stubEnv('STRIPE_PRICE_PRO', '')
    vi.stubEnv('STRIPE_PRICE_BUSINESS', '')
    expect(planFromPriceId('price_pro_123')).toBeNull()
  })
})
