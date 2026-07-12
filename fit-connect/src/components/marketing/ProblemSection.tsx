/**
 * 課題セクション「こんな悩みはありませんか？」
 */
import { MessageSquareText, Clock, Layers } from 'lucide-react'

const PROBLEMS = [
  {
    icon: MessageSquareText,
    text: 'LINE のやりとりに食事報告が埋もれて、あとから見返せない',
  },
  {
    icon: Clock,
    text: '食事チェックとフィードバックに毎日時間がかかりすぎる',
  },
  {
    icon: Layers,
    text: '記録は Excel、連絡は LINE、予定は別アプリ…と管理がバラバラ',
  },
] as const

export function ProblemSection() {
  return (
    <section className="bg-[#F8FAFC]">
      <div className="max-w-6xl mx-auto px-4 py-16 sm:px-6 sm:py-24">
        <h2 className="text-center text-2xl font-bold tracking-tight text-[#0F172A] sm:text-3xl">
          こんな悩みはありませんか？
        </h2>

        <div className="mt-12 grid gap-6 md:grid-cols-3">
          {PROBLEMS.map(({ icon: Icon, text }) => (
            <div
              key={text}
              className="rounded-lg border border-[#E2E8F0] bg-white p-6"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-md bg-[#F0FDFA] text-[#14B8A6]">
                <Icon className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <p className="mt-4 text-sm leading-relaxed text-[#334155] sm:text-base">
                {text}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
