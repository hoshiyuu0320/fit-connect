import { NextRequest, NextResponse } from 'next/server'
import { getAuthenticatedUser } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { getStripe, isBillingConfigured } from '@/lib/billing/stripe'

/**
 * リダイレクト先のベース URL を解決する。
 * 優先順: リクエストヘッダーの origin → NEXT_PUBLIC_APP_URL → req.nextUrl.origin
 */
function resolveOrigin(req: NextRequest): string {
  const originHeader = req.headers.get('origin')
  if (originHeader) return originHeader
  if (process.env.NEXT_PUBLIC_APP_URL) return process.env.NEXT_PUBLIC_APP_URL
  return req.nextUrl.origin
}

/**
 * POST /api/billing/checkout
 * Body: { plan: 'pro' | 'business' }
 * Stripe Checkout セッションを作成し、リダイレクト先 URL を返す。
 */
export async function POST(req: NextRequest) {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }

    // リクエストボディ検証
    let plan: unknown
    try {
      const body = await req.json()
      plan = body?.plan
    } catch {
      return NextResponse.json({ error: 'INVALID_BODY' }, { status: 400 })
    }
    if (plan !== 'pro' && plan !== 'business') {
      return NextResponse.json({ error: 'INVALID_PLAN' }, { status: 400 })
    }

    // Stripe 未設定（キー申請中）の場合は 503
    if (!isBillingConfigured()) {
      return NextResponse.json(
        { error: 'BILLING_NOT_CONFIGURED' },
        { status: 503 }
      )
    }
    const priceId =
      plan === 'pro'
        ? process.env.STRIPE_PRICE_PRO
        : process.env.STRIPE_PRICE_BUSINESS
    if (!priceId) {
      return NextResponse.json(
        { error: 'BILLING_NOT_CONFIGURED' },
        { status: 503 }
      )
    }

    // trainers 行の取得
    const { data: trainer, error: trainerError } = await supabaseAdmin
      .from('trainers')
      .select('id, email')
      .eq('id', user.id)
      .maybeSingle()
    if (trainerError) {
      console.error('checkout: trainers 取得エラー:', trainerError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }
    if (!trainer) {
      return NextResponse.json({ error: 'TRAINER_NOT_FOUND' }, { status: 404 })
    }

    // trainer_billing の取得
    const { data: billing, error: billingError } = await supabaseAdmin
      .from('trainer_billing')
      .select('stripe_customer_id')
      .eq('trainer_id', user.id)
      .maybeSingle()
    if (billingError) {
      console.error('checkout: trainer_billing 取得エラー:', billingError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    const stripe = getStripe()

    // Stripe Customer が未作成なら作成して保存
    let customerId: string | null = billing?.stripe_customer_id ?? null
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: trainer.email || user.email || undefined,
        metadata: { trainer_id: user.id },
      })
      customerId = customer.id

      const { error: upsertError } = await supabaseAdmin
        .from('trainer_billing')
        .upsert(
          {
            trainer_id: user.id,
            stripe_customer_id: customerId,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'trainer_id' }
        )
      if (upsertError) {
        console.error('checkout: trainer_billing upsert エラー:', upsertError)
        return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
      }
    }

    const origin = resolveOrigin(req)
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      allow_promotion_codes: true,
      client_reference_id: user.id,
      subscription_data: { metadata: { trainer_id: user.id } },
      success_url: `${origin}/settings/billing?checkout=success`,
      cancel_url: `${origin}/settings/billing?checkout=cancel`,
    })

    if (!session.url) {
      console.error('checkout: セッション URL が空です:', session.id)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    return NextResponse.json({ url: session.url })
  } catch (error) {
    console.error('checkout: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
