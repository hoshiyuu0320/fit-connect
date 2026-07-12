/**
 * プラン定義の単一情報源（Single Source of Truth）
 *
 * - UI（設定画面）とAPI（checkout/status/webhook）の両方から参照される
 * - 環境変数 STRIPE_PRICE_PRO / STRIPE_PRICE_BUSINESS は呼び出し時に評価する
 *   （module スコープで参照しない — env 未設定でもビルド・他機能が動くこと）
 */

export type PlanId = 'free' | 'pro' | 'business'

export interface PlanDef {
  id: PlanId
  label: string
  priceJpy: number
  maxClients: number
  recommended?: boolean
}

export const PLANS: Record<PlanId, PlanDef> = {
  free: {
    id: 'free',
    label: 'Free',
    priceJpy: 0,
    maxClients: 3,
  },
  pro: {
    id: 'pro',
    label: 'Pro',
    priceJpy: 2980,
    maxClients: 10,
    recommended: true,
  },
  business: {
    id: 'business',
    label: 'Business',
    priceJpy: 6980,
    maxClients: 30,
  },
}

export const TRIAL_DAYS = 14

export interface EffectivePlan {
  plan: PlanId
  isTrial: boolean
  trialDaysLeft: number | null
}

const MS_PER_DAY = 24 * 60 * 60 * 1000

/**
 * 実効プランを算出する。
 *
 * - subscription_plan が 'free' 以外（有料契約中）→ そのプラン
 * - 'free' かつ trial_ends_at が未来 → Pro トライアル中
 * - それ以外 → free
 */
export function getEffectivePlan(
  subscriptionPlan: PlanId,
  trialEndsAt: string | null
): EffectivePlan {
  if (subscriptionPlan !== 'free') {
    return { plan: subscriptionPlan, isTrial: false, trialDaysLeft: null }
  }

  if (trialEndsAt) {
    const endMs = new Date(trialEndsAt).getTime()
    const nowMs = Date.now()
    if (Number.isFinite(endMs) && endMs > nowMs) {
      return {
        plan: 'pro',
        isTrial: true,
        trialDaysLeft: Math.ceil((endMs - nowMs) / MS_PER_DAY),
      }
    }
  }

  return { plan: 'free', isTrial: false, trialDaysLeft: null }
}

/**
 * Stripe Price ID からプランを逆引きする。
 * env（STRIPE_PRICE_PRO / STRIPE_PRICE_BUSINESS）と突合し、
 * 一致しない・env 未設定の場合は null を返す。
 */
export function planFromPriceId(priceId: string | null | undefined): PlanId | null {
  if (!priceId) return null

  const proPriceId = process.env.STRIPE_PRICE_PRO
  const businessPriceId = process.env.STRIPE_PRICE_BUSINESS

  if (proPriceId && priceId === proPriceId) return 'pro'
  if (businessPriceId && priceId === businessPriceId) return 'business'
  return null
}
