/**
 * FAQ セクション
 * shadcn の accordion コンポーネントが存在しないため、
 * client component を増やさず native の details/summary で実装
 */
import Link from 'next/link'
import { ChevronDown } from 'lucide-react'

const FAQS: { question: string; answer: React.ReactNode }[] = [
  {
    question: '無料トライアルにクレジットカードは必要ですか？',
    answer:
      '不要です。トライアル終了後は自動的に Free プランに切り替わり、料金は発生しません。',
  },
  {
    question: '顧客側の利用に料金はかかりますか？',
    answer:
      'かかりません。顧客用のスマートフォンアプリは無料でご利用いただけます。',
  },
  {
    question: '解約はいつでもできますか？',
    answer:
      'はい。設定画面からいつでも解約でき、現在の請求期間の終了まで利用できます。',
  },
  {
    question: 'AI の食事解析はどのくらい正確ですか？',
    answer:
      '写真からの推定値は目安です。トレーナーが確認・修正したうえで記録できます。',
  },
  {
    question: 'データは安全に管理されますか？',
    answer: (
      <>
        通信は暗号化され、データはアクセス制御されたクラウド基盤で管理しています。詳細は
        <Link
          href="/privacy"
          className="mx-0.5 text-[#0F766E] underline underline-offset-2 hover:text-[#0F172A] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2 rounded-sm"
        >
          プライバシーポリシー
        </Link>
        をご覧ください。
      </>
    ),
  },
]

export function FaqSection() {
  return (
    <section className="bg-white">
      <div className="max-w-3xl mx-auto px-4 py-16 sm:px-6 sm:py-24">
        <h2 className="text-center text-2xl font-bold tracking-tight text-[#0F172A] sm:text-3xl">
          よくある質問
        </h2>

        <div className="mt-12 border-t border-[#E2E8F0]">
          {FAQS.map(({ question, answer }) => (
            <details key={question} className="group border-b border-[#E2E8F0]">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 py-5 text-left text-sm font-medium text-[#0F172A] sm:text-base [&::-webkit-details-marker]:hidden focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2 rounded-sm">
                {question}
                <ChevronDown className="h-4 w-4 shrink-0 text-[#94A3B8] transition-transform duration-200 group-open:rotate-180" />
              </summary>
              <p className="pb-5 text-sm leading-relaxed text-[#475569]">
                {answer}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
