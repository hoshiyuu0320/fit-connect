import { planFromPriceId, type PlanId } from './plans'

/**
 * Stripe webhook イベント → DB 更新内容を導出する純関数群。
 * I/O を持たないためユニットテスト対象（webhook.test.ts）。
 */

/**
 * Stripe.Subscription の構造的サブセット。
 * 純関数をテスト可能に保つため、Stripe SDK の型に依存しない。
 *
 * current_period_end は Stripe API バージョンにより
 * サブスクリプション直下（旧）または items.data[].current_period_end（新, Basil 以降）
 * に存在するため、両方を許容する。単位は unix 秒。
 */
export interface SubscriptionSnapshot {
  id: string
  status: string
  cancel_at_period_end: boolean
  current_period_end?: number | null
  items: {
    data: Array<{
      price: { id: string }
      current_period_end?: number | null
    }>
  }
}

/** trainer_billing テーブルへの更新内容 */
export interface BillingPatch {
  stripe_subscription_id: string
  subscription_status: string
  price_id: string | null
  current_period_end: string | null
  cancel_at_period_end: boolean
}

export interface ResolvedSubscription {
  /**
   * trainers.subscription_plan に反映すべきプラン。
   * null の場合はプラン変更なし（現状維持。status の記録のみ行う）。
   */
  plan: PlanId | null
  billingPatch: BillingPatch
}

/** subscription_plan を 'free' に落とすステータス */
const DOWNGRADE_STATUSES = new Set(['canceled', 'unpaid', 'incomplete_expired'])

/** priceId のプランを反映するステータス */
const ACTIVE_STATUSES = new Set(['active', 'trialing'])

function toIsoOrNull(unixSeconds: number | null | undefined): string | null {
  if (typeof unixSeconds !== 'number' || !Number.isFinite(unixSeconds)) {
    return null
  }
  return new Date(unixSeconds * 1000).toISOString()
}

/**
 * サブスクリプションの状態から、trainers.subscription_plan の更新値と
 * trainer_billing の更新内容を導出する。
 *
 * マッピング:
 * - active / trialing        → planFromPriceId(price) のプラン（price 不明なら維持）
 * - past_due                 → プラン維持（status 記録のみ）
 * - canceled / unpaid /
 *   incomplete_expired       → 'free'
 * - その他（incomplete 等）  → プラン維持（status 記録のみ）
 */
export function resolvePlanFromSubscription(
  sub: SubscriptionSnapshot
): ResolvedSubscription {
  const firstItem = sub.items?.data?.[0]
  const priceId = firstItem?.price?.id ?? null

  // current_period_end: item レベル（新API）優先、無ければトップレベル（旧API）
  const periodEndUnix = firstItem?.current_period_end ?? sub.current_period_end

  const billingPatch: BillingPatch = {
    stripe_subscription_id: sub.id,
    subscription_status: sub.status,
    price_id: priceId,
    current_period_end: toIsoOrNull(periodEndUnix),
    cancel_at_period_end: Boolean(sub.cancel_at_period_end),
  }

  let plan: PlanId | null = null
  if (DOWNGRADE_STATUSES.has(sub.status)) {
    plan = 'free'
  } else if (ACTIVE_STATUSES.has(sub.status)) {
    // 未知の price（env 未設定・プラン外の price）の場合は null = プラン維持
    plan = planFromPriceId(priceId)
  }
  // past_due やその他のステータスは plan = null（維持）のまま

  return { plan, billingPatch }
}
