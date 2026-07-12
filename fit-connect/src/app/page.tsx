/**
 * サービス紹介ランディングページ（トップ / マーケティングLP）
 *
 * - 静的生成可能な server component のみで構成（認証・DB呼び出しなし）
 * - 料金・トライアル日数は @/lib/billing/plans を単一情報源として参照
 * - ログイン導線は既存の /login、登録導線は /signup へ誘導
 */
import type { Metadata } from 'next'
import { LandingHeader } from '@/components/marketing/LandingHeader'
import { HeroSection } from '@/components/marketing/HeroSection'
import { ProblemSection } from '@/components/marketing/ProblemSection'
import { FeatureSection } from '@/components/marketing/FeatureSection'
import { PricingSection } from '@/components/marketing/PricingSection'
import { FaqSection } from '@/components/marketing/FaqSection'
import { FinalCtaSection } from '@/components/marketing/FinalCtaSection'
import { LandingFooter } from '@/components/marketing/LandingFooter'

export const metadata: Metadata = {
  title: 'FIT-CONNECT | パーソナルトレーナーのための顧客管理ツール',
  description:
    '顧客とのメッセージ、食事・体重の記録、ワークアウト計画、回数券の管理までを一体化した、個人パーソナルトレーナー向けの顧客管理ツール。AIが食事写真からカロリー・PFCを推定し、日々のチェックの手間を減らします。',
}

export default function LandingPage() {
  return (
    <div className="bg-[#F8FAFC]">
      <LandingHeader />
      <HeroSection />
      <ProblemSection />
      <FeatureSection />
      <PricingSection />
      <FaqSection />
      <FinalCtaSection />
      <LandingFooter />
    </div>
  )
}
