import Stripe from 'stripe'

/**
 * Stripe クライアントの遅延初期化。
 *
 * STRIPE_SECRET_KEY はオーナー申請中で未設定の可能性があるため、
 * module スコープでは絶対に参照しない。env 未設定でも import 自体は安全で、
 * ビルド・デプロイ・他機能に影響しない。
 */

let stripeClient: Stripe | null = null

/** STRIPE_SECRET_KEY が設定されているか（課金機能が有効か） */
export function isBillingConfigured(): boolean {
  return Boolean(process.env.STRIPE_SECRET_KEY)
}

/**
 * Stripe クライアントを返す（初回呼び出し時に生成）。
 * STRIPE_SECRET_KEY 未設定なら throw する。
 * 呼び出し側は事前に isBillingConfigured() でガードすること。
 */
export function getStripe(): Stripe {
  const secretKey = process.env.STRIPE_SECRET_KEY
  if (!secretKey) {
    throw new Error(
      'STRIPE_SECRET_KEY is not configured. Billing features are unavailable.'
    )
  }
  if (!stripeClient) {
    // apiVersion は SDK デフォルト（pinned version）に任せる
    stripeClient = new Stripe(secretKey)
  }
  return stripeClient
}
