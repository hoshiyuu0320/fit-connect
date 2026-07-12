import { NextResponse } from 'next/server'
import { getAuthenticatedUser } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { isBillingConfigured } from '@/lib/billing/stripe'
import { getEffectivePlan, type PlanId } from '@/lib/billing/plans'

/** DB の text 値を PlanId に安全に変換する（不正値は 'free' 扱い） */
function toPlanId(value: string | null | undefined): PlanId {
  return value === 'pro' || value === 'business' ? value : 'free'
}

/**
 * GET /api/billing/status
 * 現在のトレーナーの課金状態を返す（設定画面 UI との契約）。
 *
 * Response:
 * {
 *   billingConfigured, plan, effectivePlan, isTrial, trialDaysLeft,
 *   trialEndsAt, subscriptionStatus, currentPeriodEnd, cancelAtPeriodEnd,
 *   hasStripeCustomer
 * }
 */
export async function GET() {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }

    const { data: trainer, error: trainerError } = await supabaseAdmin
      .from('trainers')
      .select('id, subscription_plan, trial_ends_at')
      .eq('id', user.id)
      .maybeSingle()
    if (trainerError) {
      console.error('billing/status: trainers 取得エラー:', trainerError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (!trainer) {
      return NextResponse.json({ error: 'TRAINER_NOT_FOUND' }, { status: 404 })
    }

    const { data: billing, error: billingError } = await supabaseAdmin
      .from('trainer_billing')
      .select(
        'stripe_customer_id, subscription_status, current_period_end, cancel_at_period_end'
      )
      .eq('trainer_id', user.id)
      .maybeSingle()
    if (billingError) {
      console.error('billing/status: trainer_billing 取得エラー:', billingError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    const plan = toPlanId(trainer.subscription_plan)
    const trialEndsAt: string | null = trainer.trial_ends_at ?? null
    const effective = getEffectivePlan(plan, trialEndsAt)

    return NextResponse.json({
      billingConfigured: isBillingConfigured(),
      plan,
      effectivePlan: effective.plan,
      isTrial: effective.isTrial,
      trialDaysLeft: effective.trialDaysLeft,
      trialEndsAt,
      subscriptionStatus: billing?.subscription_status ?? null,
      currentPeriodEnd: billing?.current_period_end ?? null,
      cancelAtPeriodEnd: Boolean(billing?.cancel_at_period_end),
      hasStripeCustomer: Boolean(billing?.stripe_customer_id),
    })
  } catch (error) {
    console.error('billing/status: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
