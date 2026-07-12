import { NextResponse } from 'next/server'
import type Stripe from 'stripe'
import { getStripe, isBillingConfigured } from '@/lib/billing/stripe'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import {
  resolvePlanFromSubscription,
  type SubscriptionSnapshot,
} from '@/lib/billing/webhook'

// Node.js runtime（デフォルト）を維持すること。
// 生ボディの署名検証と Stripe SDK 利用のため Edge runtime は使用不可。

/**
 * サブスクリプションの状態を trainers / trainer_billing に同期する。
 *
 * trainer_id の解決: subscription.metadata.trainer_id を優先し、
 * 無ければ trainer_billing を stripe_customer_id で逆引きする。
 * 解決できない場合はエラーログのみ（Stripe に再送させないため throw しない）。
 */
async function syncSubscription(sub: Stripe.Subscription): Promise<void> {
  const customerId =
    typeof sub.customer === 'string' ? sub.customer : sub.customer?.id ?? null

  // trainer_id の解決
  let trainerId: string | null = sub.metadata?.trainer_id || null
  if (!trainerId && customerId) {
    const { data, error } = await supabaseAdmin
      .from('trainer_billing')
      .select('trainer_id')
      .eq('stripe_customer_id', customerId)
      .maybeSingle()
    if (error) {
      throw new Error(`trainer_billing 逆引きエラー: ${error.message}`)
    }
    trainerId = data?.trainer_id ?? null
  }
  if (!trainerId) {
    // 解決不能: 再送しても解決しないため、エラーログのみで正常終了扱い
    console.error(
      `stripe/webhook: trainer_id を解決できません (subscription=${sub.id}, customer=${customerId})`
    )
    return
  }

  const { plan, billingPatch } = resolvePlanFromSubscription(
    sub as SubscriptionSnapshot
  )

  // trainer_billing の更新（書き込みは service_role のみ）
  const { error: billingError } = await supabaseAdmin
    .from('trainer_billing')
    .upsert(
      {
        trainer_id: trainerId,
        ...(customerId ? { stripe_customer_id: customerId } : {}),
        stripe_subscription_id: billingPatch.stripe_subscription_id,
        subscription_status: billingPatch.subscription_status,
        price_id: billingPatch.price_id,
        current_period_end: billingPatch.current_period_end,
        cancel_at_period_end: billingPatch.cancel_at_period_end,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'trainer_id' }
    )
  if (billingError) {
    throw new Error(`trainer_billing 更新エラー: ${billingError.message}`)
  }

  // trainers.subscription_plan の更新（plan が null の場合は現状維持）
  if (plan) {
    const { error: trainerError } = await supabaseAdmin
      .from('trainers')
      .update({
        subscription_plan: plan,
        updated_at: new Date().toISOString(),
      })
      .eq('id', trainerId)
    if (trainerError) {
      throw new Error(`trainers 更新エラー: ${trainerError.message}`)
    }
  }
}

/**
 * POST /api/stripe/webhook
 * Stripe からの webhook を受信し、署名検証のうえサブスクリプション状態を同期する。
 */
export async function POST(req: Request) {
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET
  if (!webhookSecret || !isBillingConfigured()) {
    return NextResponse.json(
      { error: 'BILLING_NOT_CONFIGURED' },
      { status: 503 }
    )
  }

  const signature = req.headers.get('stripe-signature')
  if (!signature) {
    return NextResponse.json({ error: 'MISSING_SIGNATURE' }, { status: 400 })
  }

  // 署名検証は必ず生ボディに対して行う（先に JSON パースしないこと）
  const rawBody = await req.text()

  let event: Stripe.Event
  try {
    event = getStripe().webhooks.constructEvent(
      rawBody,
      signature,
      webhookSecret
    )
  } catch (error) {
    console.error('stripe/webhook: 署名検証エラー:', error)
    return NextResponse.json({ error: 'INVALID_SIGNATURE' }, { status: 400 })
  }

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        const subscriptionId =
          typeof session.subscription === 'string'
            ? session.subscription
            : session.subscription?.id ?? null
        if (subscriptionId) {
          const subscription =
            await getStripe().subscriptions.retrieve(subscriptionId)
          await syncSubscription(subscription)
        }
        break
      }
      case 'customer.subscription.created':
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        await syncSubscription(event.data.object as Stripe.Subscription)
        break
      }
      default:
        // その他のイベントは何もせず 200 を返す
        break
    }
  } catch (error) {
    // DB 更新失敗など一時的なエラーは 500 を返して Stripe に再送させる
    console.error(`stripe/webhook: イベント処理エラー (${event.type}):`, error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }

  return NextResponse.json({ received: true })
}
