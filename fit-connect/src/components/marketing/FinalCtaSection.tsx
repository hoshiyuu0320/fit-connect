/**
 * 最終CTAセクション（primary 濃色帯）
 */
import Link from 'next/link'
import { ArrowRight } from 'lucide-react'
import { TRIAL_DAYS } from '@/lib/billing/plans'

export function FinalCtaSection() {
  return (
    <section className="bg-[#0F172A]">
      <div className="max-w-6xl mx-auto px-4 py-16 text-center sm:px-6 sm:py-20">
        <h2 className="text-2xl font-bold tracking-tight text-white sm:text-3xl">
          今日から、顧客管理をシンプルに。
        </h2>
        <p className="mt-4 text-sm text-[#94A3B8] sm:text-base">
          {TRIAL_DAYS}日間の無料トライアル。クレジットカードは不要です。
        </p>
        <Link
          href="/signup"
          className="mt-8 inline-flex h-12 items-center gap-2 rounded-md bg-white px-8 text-base font-medium text-[#0F172A] hover:bg-[#F1F5F9] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
        >
          無料で始める
          <ArrowRight className="h-4 w-4" />
        </Link>
      </div>
    </section>
  )
}
