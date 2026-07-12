/**
 * ヒーローセクション
 * ビジュアルは画像を使わず CSS（div）のみで構成した抽象的なアプリUIモック
 */
import Link from 'next/link'
import { ArrowRight } from 'lucide-react'
import { TRIAL_DAYS } from '@/lib/billing/plans'

/** 抽象化したダッシュボード風モック（装飾のため aria-hidden） */
function HeroVisual() {
  // 体重推移を模した棒グラフ（ゆるやかな下降トレンド）
  const bars = [64, 60, 58, 54, 52, 48, 44]

  return (
    <div aria-hidden="true" className="relative w-full max-w-lg mx-auto lg:max-w-none select-none">
      <div className="rounded-lg border border-[#E2E8F0] bg-white shadow-sm overflow-hidden">
        {/* ウィンドウバー */}
        <div className="flex items-center gap-1.5 border-b border-[#E2E8F0] bg-[#F8FAFC] px-4 py-3">
          <span className="h-2 w-2 rounded-full bg-[#CBD5E1]" />
          <span className="h-2 w-2 rounded-full bg-[#CBD5E1]" />
          <span className="h-2 w-2 rounded-full bg-[#CBD5E1]" />
          <span className="ml-3 h-2 w-24 rounded-full bg-[#E2E8F0]" />
        </div>

        <div className="grid grid-cols-5 gap-3 p-4">
          {/* 左: KPI + グラフ */}
          <div className="col-span-5 sm:col-span-3 space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-md border border-[#E2E8F0] p-3">
                <p className="text-[10px] text-[#94A3B8]">担当顧客</p>
                <p className="mt-1 text-xl font-bold text-[#0F172A]">
                  8<span className="ml-0.5 text-[10px] font-medium text-[#94A3B8]">人</span>
                </p>
                <div className="mt-2 h-1 w-2/3 rounded-full bg-[#14B8A6]" />
              </div>
              <div className="rounded-md border border-[#E2E8F0] p-3">
                <p className="text-[10px] text-[#94A3B8]">今週の記録</p>
                <p className="mt-1 text-xl font-bold text-[#0F172A]">
                  36<span className="ml-0.5 text-[10px] font-medium text-[#94A3B8]">件</span>
                </p>
                <div className="mt-2 h-1 w-1/2 rounded-full bg-[#E2E8F0]" />
              </div>
            </div>

            <div className="rounded-md border border-[#E2E8F0] p-3">
              <div className="flex items-center justify-between">
                <p className="text-[10px] text-[#94A3B8]">体重の推移</p>
                <span className="h-2 w-10 rounded-full bg-[#E2E8F0]" />
              </div>
              <div className="mt-3 flex h-20 items-end gap-1.5">
                {bars.map((h, i) => (
                  <div
                    key={i}
                    style={{ height: `${h}px` }}
                    className={`flex-1 rounded-sm ${i >= bars.length - 2 ? 'bg-[#14B8A6]' : 'bg-[#E2E8F0]'}`}
                  />
                ))}
              </div>
            </div>
          </div>

          {/* 右: チャット */}
          <div className="col-span-5 sm:col-span-2 flex flex-col gap-2 rounded-md border border-[#E2E8F0] p-3">
            <p className="text-[10px] text-[#94A3B8]">メッセージ</p>

            {/* 受信バブル（食事タグ付き） */}
            <div className="max-w-[85%] rounded-md bg-[#F1F5F9] p-2">
              <span className="inline-flex items-center rounded-sm bg-[#F0FDFA] px-1.5 py-0.5 text-[9px] font-medium text-[#0F766E]">
                #食事:昼食
              </span>
              <div className="mt-1.5 h-1.5 w-full rounded-full bg-[#CBD5E1]" />
              <div className="mt-1 h-1.5 w-2/3 rounded-full bg-[#CBD5E1]" />
            </div>

            {/* AI解析カード */}
            <div className="max-w-[85%] rounded-md border border-[#CCFBF1] bg-white p-2">
              <p className="text-[9px] font-semibold text-[#0F766E]">AI解析</p>
              <p className="mt-0.5 text-[10px] font-medium text-[#0F172A]">512 kcal</p>
              <p className="text-[9px] text-[#94A3B8]">P 32g / F 14g / C 58g</p>
            </div>

            {/* 送信バブル */}
            <div className="ml-auto max-w-[85%] rounded-md bg-[#0F172A] p-2">
              <div className="h-1.5 w-20 rounded-full bg-[#475569]" />
              <div className="mt-1 h-1.5 w-14 rounded-full bg-[#475569]" />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export function HeroSection() {
  return (
    <section className="bg-white">
      <div className="max-w-6xl mx-auto grid gap-12 px-4 py-16 sm:px-6 sm:py-24 lg:grid-cols-2 lg:items-center">
        <div>
          <h1 className="text-3xl font-bold leading-tight tracking-tight text-[#0F172A] sm:text-4xl lg:text-[2.75rem] lg:leading-[1.2]">
            パーソナルトレーナーの顧客管理を、これひとつで。
          </h1>
          <p className="mt-6 text-base leading-relaxed text-[#475569] sm:text-lg">
            顧客とのメッセージ、食事・体重の記録、ワークアウト計画、回数券の管理まで。FIT-CONNECT
            は個人トレーナーのための一体型顧客管理ツールです。AI
            が食事写真から栄養素を推定し、日々のチェックの手間を減らします。
          </p>
          <div className="mt-8">
            <Link
              href="/signup"
              className="inline-flex h-12 items-center gap-2 rounded-md bg-[#0F172A] px-8 text-base font-medium text-white hover:bg-[#1E293B] transition-colors duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-2"
            >
              無料で始める
              <ArrowRight className="h-4 w-4" />
            </Link>
            <p className="mt-3 text-sm text-[#64748B]">
              {TRIAL_DAYS}日間 Pro プランを無料でお試し。クレジットカードは不要です。
            </p>
          </div>
        </div>

        <HeroVisual />
      </div>
    </section>
  )
}
