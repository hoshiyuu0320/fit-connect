/**
 * 機能紹介セクション（3列×2段、モバイル1列）
 */
import {
  Users,
  MessageCircle,
  Sparkles,
  Dumbbell,
  Ticket,
  TrendingUp,
} from 'lucide-react'

const FEATURES = [
  {
    icon: Users,
    title: '顧客管理',
    description:
      '顧客ごとのプロフィール・目標・進捗を一元管理。QRコードで招待も簡単。',
  },
  {
    icon: MessageCircle,
    title: 'メッセージ & 自動記録',
    description:
      'チャットにタグを付けるだけで、食事・体重・睡眠が記録として自動整理。',
  },
  {
    icon: Sparkles,
    title: 'AI 食事解析',
    description:
      '食事の写真からカロリー・PFC を AI が推定。確認して直すだけ。',
  },
  {
    icon: Dumbbell,
    title: 'ワークアウト計画',
    description:
      '種目とセットを組んで配信。顧客の実施状況を自動で追跡。',
  },
  {
    icon: Ticket,
    title: 'チケット・回数券',
    description: '回数券の発行・消化・有効期限を自動管理。',
  },
  {
    icon: TrendingUp,
    title: '週次レポート',
    description:
      '体重や記録の変化をグラフで確認。顧客のモチベーション維持に。',
  },
] as const

export function FeatureSection() {
  return (
    <section className="bg-white">
      <div className="max-w-6xl mx-auto px-4 py-16 sm:px-6 sm:py-24">
        <h2 className="text-center text-2xl font-bold tracking-tight text-[#0F172A] sm:text-3xl">
          FIT-CONNECT でできること
        </h2>
        <p className="mx-auto mt-4 max-w-2xl text-center text-sm leading-relaxed text-[#64748B] sm:text-base">
          日々のトレーナー業務に必要な機能を、ひとつのツールにまとめました。
        </p>

        <div className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map(({ icon: Icon, title, description }) => (
            <div
              key={title}
              className="rounded-lg border border-[#E2E8F0] bg-white p-6"
            >
              <span className="flex h-10 w-10 items-center justify-center rounded-md bg-[#F0FDFA] text-[#14B8A6]">
                <Icon className="h-5 w-5" strokeWidth={1.75} />
              </span>
              <h3 className="mt-4 text-base font-semibold text-[#0F172A]">
                {title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-[#475569]">
                {description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
