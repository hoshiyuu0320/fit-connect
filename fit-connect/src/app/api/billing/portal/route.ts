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
 * POST /api/billing/portal
 * Stripe Billing Portal セッションを作成し、リダイレクト先 URL を返す。
 * 支払い方法の変更・プラン変更・解約はポータル側で行う。
 */
export async function POST(req: NextRequest) {
  try {
    // 認証必須
    const user = await getAuthenticatedUser()
    if (!user) {
      return NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 })
    }

    // Stripe 未設定（キー申請中）の場合は 503
    if (!isBillingConfigured()) {
      return NextResponse.json(
        { error: 'BILLING_NOT_CONFIGURED' },
        { status: 503 }
      )
    }

    const { data: billing, error: billingError } = await supabaseAdmin
      .from('trainer_billing')
      .select('stripe_customer_id')
      .eq('trainer_id', user.id)
      .maybeSingle()
    if (billingError) {
      console.error('portal: trainer_billing 取得エラー:', billingError)
      return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
    }

    const customerId = billing?.stripe_customer_id
    if (!customerId) {
      return NextResponse.json({ error: 'NO_CUSTOMER' }, { status: 400 })
    }

    const origin = resolveOrigin(req)
    const session = await getStripe().billingPortal.sessions.create({
      customer: customerId,
      return_url: `${origin}/settings/billing`,
    })

    return NextResponse.json({ url: session.url })
  } catch (error) {
    console.error('portal: 予期しないエラー:', error)
    return NextResponse.json({ error: 'INTERNAL_ERROR' }, { status: 500 })
  }
}
