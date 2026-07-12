import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import {
  resolvePlanFromSubscription,
  type SubscriptionSnapshot,
} from '@/lib/billing/webhook'

const PRO_PRICE = 'price_pro_123'
const BIZ_PRICE = 'price_biz_456'

// 2026-07-12T00:00:00Z の unix 秒
const PERIOD_END_UNIX = 1783900800
const PERIOD_END_ISO = new Date(PERIOD_END_UNIX * 1000).toISOString()

function sub(over: Partial<SubscriptionSnapshot> = {}): SubscriptionSnapshot {
  return {
    id: 'sub_test_1',
    status: 'active',
    cancel_at_period_end: false,
    items: {
      data: [{ price: { id: PRO_PRICE }, current_period_end: PERIOD_END_UNIX }],
    },
    ...over,
  }
}

describe('resolvePlanFromSubscription', () => {
  beforeEach(() => {
    vi.stubEnv('STRIPE_PRICE_PRO', PRO_PRICE)
    vi.stubEnv('STRIPE_PRICE_BUSINESS', BIZ_PRICE)
  })

  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('active + pro price → plan=pro、patch に契約情報一式', () => {
    const result = resolvePlanFromSubscription(sub())
    expect(result.plan).toBe('pro')
    expect(result.billingPatch).toEqual({
      stripe_subscription_id: 'sub_test_1',
      subscription_status: 'active',
      price_id: PRO_PRICE,
      current_period_end: PERIOD_END_ISO,
      cancel_at_period_end: false,
    })
  })

  it('active + business price → plan=business', () => {
    const result = resolvePlanFromSubscription(
      sub({
        items: {
          data: [
            { price: { id: BIZ_PRICE }, current_period_end: PERIOD_END_UNIX },
          ],
        },
      })
    )
    expect(result.plan).toBe('business')
    expect(result.billingPatch.price_id).toBe(BIZ_PRICE)
  })

  it('trialing → active と同様に price からプランを反映', () => {
    const result = resolvePlanFromSubscription(sub({ status: 'trialing' }))
    expect(result.plan).toBe('pro')
    expect(result.billingPatch.subscription_status).toBe('trialing')
  })

  it('active + 未知の price → plan=null（プラン維持）', () => {
    const result = resolvePlanFromSubscription(
      sub({
        items: { data: [{ price: { id: 'price_unknown' } }] },
      })
    )
    expect(result.plan).toBeNull()
    expect(result.billingPatch.price_id).toBe('price_unknown')
  })

  it('past_due → plan=null（プラン維持、status のみ記録）', () => {
    const result = resolvePlanFromSubscription(sub({ status: 'past_due' }))
    expect(result.plan).toBeNull()
    expect(result.billingPatch.subscription_status).toBe('past_due')
  })

  it('canceled → plan=free', () => {
    const result = resolvePlanFromSubscription(sub({ status: 'canceled' }))
    expect(result.plan).toBe('free')
    expect(result.billingPatch.subscription_status).toBe('canceled')
  })

  it('unpaid → plan=free', () => {
    expect(resolvePlanFromSubscription(sub({ status: 'unpaid' })).plan).toBe(
      'free'
    )
  })

  it('incomplete_expired → plan=free', () => {
    expect(
      resolvePlanFromSubscription(sub({ status: 'incomplete_expired' })).plan
    ).toBe('free')
  })

  it('incomplete / paused など未分類の status → plan=null（維持）', () => {
    expect(
      resolvePlanFromSubscription(sub({ status: 'incomplete' })).plan
    ).toBeNull()
    expect(
      resolvePlanFromSubscription(sub({ status: 'paused' })).plan
    ).toBeNull()
  })

  it('cancel_at_period_end=true が patch に反映される', () => {
    const result = resolvePlanFromSubscription(
      sub({ cancel_at_period_end: true })
    )
    expect(result.plan).toBe('pro') // プランは維持（期間末解約予約）
    expect(result.billingPatch.cancel_at_period_end).toBe(true)
  })

  it('current_period_end: item に無ければトップレベルから取得（旧API互換）', () => {
    const result = resolvePlanFromSubscription(
      sub({
        current_period_end: PERIOD_END_UNIX,
        items: { data: [{ price: { id: PRO_PRICE } }] },
      })
    )
    expect(result.billingPatch.current_period_end).toBe(PERIOD_END_ISO)
  })

  it('current_period_end がどこにも無ければ null', () => {
    const result = resolvePlanFromSubscription(
      sub({ items: { data: [{ price: { id: PRO_PRICE } }] } })
    )
    expect(result.billingPatch.current_period_end).toBeNull()
  })

  it('items が空でも落ちない（price_id=null、plan は canceled 系のみ変化）', () => {
    const active = resolvePlanFromSubscription(sub({ items: { data: [] } }))
    expect(active.plan).toBeNull()
    expect(active.billingPatch.price_id).toBeNull()

    const canceled = resolvePlanFromSubscription(
      sub({ status: 'canceled', items: { data: [] } })
    )
    expect(canceled.plan).toBe('free')
  })
})
