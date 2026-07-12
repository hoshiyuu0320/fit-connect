/**
 * 料金セクション
 * プラン内容は @/lib/billing/plans の PLANS を単一情報源として表示する（ハードコード禁止）
 * 表示内容は /settings/billing の実装UIを LP 向けに簡潔化したもの
 */
import Link from 'next/link'
import { Check } from 'lucide-react'
import { PLANS, TRIAL_DAYS, type PlanId } from '@/lib/billing/plans'

const PLAN_ORDER: PlanId[] = ['free', 'pro', 'business']

const AI_FEATURE_NOTES: Record<PlanId, string> = {
  free: 'AI食事解析 お試し（月30回）',
  pro: 'AI食事解析（1顧客あたり 日10回・月100回）',
  business: 'AI食事解析（1顧客あたり 日10回・月100回）',
}

const COMMON_FEATURES = [
  'メッセージ & 食事・体重記録',
  'ワークアウト計画',
  'チケット・回数券管理',
] as const

export function PricingSection() {
  return (
    <section className="bg-[#F8FAFC]">
      <div className="max-w-6xl mx-auto px-4 py-16 sm:px-6 sm:py-24">
        <h2 className="text-center text-2xl font-bold tracking-tight text-[#0F172A] sm:text-3xl">
          料金プラン
        </h2>
        <p className="mx-auto mt-4 max-w-2xl text-center text-sm leading-relaxed text-[#64748B] sm:text-base">
          {TRIAL_DAYS}日間の無料トライアルで、Pro プランの機能をすべてお試しいただけます。
        </p>

        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {PLAN_ORDER.map((planId) => {
            const plan = PLANS[planId]
            const recommended = Boolean(plan.recommended)

            return (
              <div
                key={plan.id}
                className={`flex flex-col rounded-lg border bg-white p-6 ${
                  recommended ? 'border-[#14B8A6]' : 'border-[#E2E8F0]'
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <h3 className="text-lg font-semibold text-[#0F172A]">
                    {plan.label}
                  </h3>
                  {recommended && (
                    <span className="inline-flex items-center whitespace-nowrap rounded-md bg-[#0F172A] px-2 py-0.5 text-xs font-medium text-white">
                      おすすめ
                    </span>
                  )}
                </div>

                <div className="mt-3">
                  <span className="text-3xl font-bold text-[#0F172A]">
                    ¥{plan.priceJpy.toLocaleString('ja-JP')}
                  </span>
                  <span className="ml-1 text-sm text-[#64748B]">/月（税込）</span>
                </div>

                <ul className="mt-6 space-y-2.5 text-sm text-[#334155]">
                  <li className="flex items-start gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-[#0D9488]" />
                    <span>顧客 {plan.maxClients} 人まで登録</span>
                  </li>
                  <li className="flex items-start gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-[#0D9488]" />
                    <span>{AI_FEATURE_NOTES[plan.id]}</span>
                  </li>
                  {COMMON_FEATURES.map((feature) => (
                    <li key={feature} className="flex items-start gap-2">
                      <Check className="mt-0.5 h-4 w-4 shrink-0 text-[#0D9488]" />
                      <span>{feature}</span>
                    </li>
                  ))}
                </ul>

                <div className="mt-auto pt-8">
                  <Link
                    href="/signup"
                    className={`flex h-10 w-full items-center justify-center rounded-md text-sm font-medium transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2 ${
                      recommended
                        ? 'bg-[#0F172A] text-white hover:bg-[#1E293B]'
                        : 'border border-[#E2E8F0] bg-white text-[#0F172A] hover:bg-[#F8FAFC]'
                    }`}
                  >
                    無料で始める
                  </Link>
                </div>
              </div>
            )
          })}
        </div>

        <p className="mt-8 text-center text-xs text-[#64748B] sm:text-sm">
          すべて税込。{TRIAL_DAYS}
          日間の無料トライアル後、自動的に Free プランになります（自動課金はありません）
        </p>
      </div>
    </section>
  )
}
