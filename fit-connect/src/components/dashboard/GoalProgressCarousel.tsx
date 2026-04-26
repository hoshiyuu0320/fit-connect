'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ChevronLeft, ChevronRight } from 'lucide-react'
import type { GoalProgressByCategory, GoalProgressClient } from '@/lib/supabase/getGoalProgress'
import type { PurposeType } from '@/lib/supabase/getGoalProgress'

interface GoalProgressCarouselProps {
  categories: GoalProgressByCategory[]
}

// --- アバター背景色マッピング ---
const avatarColorMap: Record<PurposeType, { bg: string; text: string }> = {
  diet: { bg: 'bg-[#F0FDFA]', text: 'text-[#14B8A6]' },
  contest: { bg: 'bg-[#FAF5FF]', text: 'text-[#A855F7]' },
  body_make: { bg: 'bg-[#FAF5FF]', text: 'text-[#A855F7]' },
  health_improvement: { bg: 'bg-[#F0FDFA]', text: 'text-[#14B8A6]' },
  mental_improvement: { bg: 'bg-[#FFF7ED]', text: 'text-[#F97316]' },
  performance_improvement: { bg: 'bg-[#FFF7ED]', text: 'text-[#F97316]' },
}

// --- 経過ヶ月数の計算 ---
function calcMonthsElapsed(dateStr: string): number {
  const start = new Date(dateStr)
  const now = new Date()
  const diffMs = now.getTime() - start.getTime()
  return Math.floor(diffMs / (1000 * 60 * 60 * 24 * 30))
}

// --- YYYY/MM/DD フォーマット ---
function formatDate(dateStr: string): string {
  const d = new Date(dateStr)
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}/${m}/${day}`
}

// --- 達成率バッジの色 ---
function getProgressBadgeStyle(rate: number): { bg: string; text: string } {
  if (rate >= 70) return { bg: 'bg-[#F0FDFA]', text: 'text-[#0D9488]' }
  if (rate >= 40) return { bg: 'bg-[#FEF3C7]', text: 'text-[#92400E]' }
  return { bg: 'bg-[#F8FAFC]', text: 'text-[#94A3B8]' }
}

// --- プログレスバーの色 ---
function getProgressBarColor(rate: number): string {
  if (rate >= 70) return 'bg-[#14B8A6]'
  if (rate >= 40) return 'bg-[#F59E0B]'
  return 'bg-[#94A3B8]'
}

// --- クライアントカード ---
function ClientCard({ client }: { client: GoalProgressClient }) {
  const router = useRouter()
  const avatarColor = avatarColorMap[client.purpose]
  const badgeStyle = getProgressBadgeStyle(client.progressRate)
  const barColor = getProgressBarColor(client.progressRate)
  const barWidth = `${Math.min(client.progressRate, 100)}%`

  const avatarInitial = client.clientName.charAt(0)

  const startLabel =
    client.goalSetAt
      ? `開始: ${formatDate(client.goalSetAt)}（${calcMonthsElapsed(client.goalSetAt)}ヶ月経過）`
      : null

  const initialDisplay = client.initialWeight !== null ? `${client.initialWeight.toFixed(1)} kg` : '-- kg'
  const currentDisplay = client.currentWeight !== null ? `${client.currentWeight.toFixed(1)} kg` : '-- kg'
  const targetDisplay = `${client.targetWeight.toFixed(1)} kg`

  const changeDisplay =
    client.weightChange !== null
      ? client.weightChange >= 0
        ? `+${client.weightChange.toFixed(1)}`
        : `${client.weightChange.toFixed(1)}`
      : null

  return (
    <div
      className="bg-[#F8FAFC] border border-[#F1F5F9] rounded-[6px] p-5 px-6 cursor-pointer hover:border-[#14B8A6] transition-colors"
      onClick={() => router.push(`/clients/${client.clientId}`)}
    >
      {/* ヘッダー */}
      <div className="flex items-center justify-between mb-4">
        {/* 左側: アバター + 名前 + 開始日 */}
        <div className="flex items-center gap-3">
          <div
            className={`w-9 h-9 rounded-full ${avatarColor.bg} ${avatarColor.text} flex items-center justify-center flex-shrink-0`}
          >
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[13px] font-bold"
            >
              {avatarInitial}
            </span>
          </div>
          <div>
            <p
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[14px] font-semibold text-[#0F172A] leading-tight"
            >
              {client.clientName}
            </p>
            {startLabel && (
              <p
                style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
                className="text-[11px] text-[#94A3B8] mt-0.5"
              >
                {startLabel}
              </p>
            )}
          </div>
        </div>

        {/* 右側: 達成率バッジ */}
        <div
          className={`${badgeStyle.bg} ${badgeStyle.text} px-2.5 py-1 rounded-[4px]`}
        >
          <span
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[11px] font-semibold"
          >
            達成率 {client.progressRate}%
          </span>
        </div>
      </div>

      {/* バレットプログレスバー */}
      <div className="h-[28px] bg-[#F1F5F9] rounded-[4px] relative overflow-hidden mb-2">
        {/* フィル */}
        <div
          className={`absolute top-[6px] h-[16px] rounded-[3px] transition-all duration-300 ${barColor}`}
          style={{ width: barWidth }}
        />
        {/* 開始マーカー */}
        <div
          className="absolute left-0 top-[-2px] w-[3px] h-[32px] rounded-[2px]"
          style={{ border: '1px dashed #94A3B8' }}
        />
        {/* ターゲットマーカー */}
        <div
          className="absolute right-0 top-[-2px] w-[3px] h-[32px] bg-[#0F172A] rounded-[2px]"
        />
      </div>

      {/* ラベル行 */}
      <div className="flex items-center justify-between">
        <span
          style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
          className="text-[11px] text-[#94A3B8]"
        >
          開始 {initialDisplay}
        </span>
        <span
          style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
          className="text-[11px] text-[#0F172A] font-semibold"
        >
          現在 {currentDisplay}
          {changeDisplay && (
            <span className="text-[#94A3B8] font-normal ml-1">({changeDisplay})</span>
          )}
        </span>
        <span
          style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
          className="text-[11px] text-[#94A3B8]"
        >
          目標 {targetDisplay}
        </span>
      </div>
    </div>
  )
}

// --- メインコンポーネント ---
export function GoalProgressCarousel({ categories }: GoalProgressCarouselProps) {
  const [activeCategory, setActiveCategory] = useState(0)
  const [slideIndex, setSlideIndex] = useState(0)

  if (categories.length === 0) return null

  const currentCategory = categories[activeCategory]
  const clients = currentCategory?.clients ?? []
  const totalSlides = clients.length
  const currentClient = clients[slideIndex] ?? null

  function handleCategoryChange(idx: number) {
    setActiveCategory(idx)
    setSlideIndex(0)
  }

  function handlePrev() {
    if (slideIndex > 0) setSlideIndex((prev) => prev - 1)
  }

  function handleNext() {
    if (slideIndex < totalSlides - 1) setSlideIndex((prev) => prev + 1)
  }

  return (
    <section className="bg-white border border-[#E2E8F0] rounded-[6px] p-6">
      {/* セクションタイトル */}
      <div className="mb-5">
        <h2
          style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
          className="text-[15px] font-bold text-[#0F172A]"
        >
          目標達成プログレス
        </h2>
        <p
          style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
          className="text-[12px] text-[#94A3B8] mt-0.5"
        >
          カテゴリごとに顧客の進捗を確認
        </p>
      </div>

      {/* カテゴリタブ */}
      <div className="flex flex-wrap gap-2 mb-6">
        {categories.map((cat, idx) => {
          const isActive = idx === activeCategory
          return (
            <button
              key={cat.purpose}
              onClick={() => handleCategoryChange(idx)}
              className={`
                flex items-center gap-1.5 px-4 py-1.5 rounded-[6px] text-[12px] font-semibold border cursor-pointer transition-colors
                ${
                  isActive
                    ? 'bg-[#0F172A] text-white border-[#0F172A]'
                    : 'bg-white text-[#475569] border-[#E2E8F0] hover:border-[#14B8A6] hover:text-[#14B8A6]'
                }
              `}
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            >
              {cat.label}
              <span
                className={`text-[10px] font-bold px-1.5 py-[1px] rounded-[4px] ${
                  isActive
                    ? 'bg-white/20 text-white'
                    : 'bg-[#F1F5F9] text-[#94A3B8]'
                }`}
              >
                {cat.clients.length}
              </span>
            </button>
          )
        })}
      </div>

      {/* カルーセルラッパー */}
      <div className="relative">
        {/* 矢印ボタン（右上） */}
        <div className="absolute top-[-48px] right-0 flex items-center gap-2">
          <button
            onClick={handlePrev}
            disabled={slideIndex === 0}
            className={`
              w-8 h-8 rounded-[6px] border border-[#E2E8F0] bg-white flex items-center justify-center cursor-pointer
              hover:border-[#14B8A6] hover:text-[#14B8A6] transition-colors text-[#475569]
              disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:border-[#E2E8F0] disabled:hover:text-[#475569]
            `}
            aria-label="前のクライアント"
          >
            <ChevronLeft size={14} />
          </button>

          <span
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[11px] text-[#94A3B8] min-w-[32px] text-center"
          >
            {totalSlides > 0 ? `${slideIndex + 1} / ${totalSlides}` : '0 / 0'}
          </span>

          <button
            onClick={handleNext}
            disabled={slideIndex >= totalSlides - 1}
            className={`
              w-8 h-8 rounded-[6px] border border-[#E2E8F0] bg-white flex items-center justify-center cursor-pointer
              hover:border-[#14B8A6] hover:text-[#14B8A6] transition-colors text-[#475569]
              disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:border-[#E2E8F0] disabled:hover:text-[#475569]
            `}
            aria-label="次のクライアント"
          >
            <ChevronRight size={14} />
          </button>
        </div>

        {/* スライド */}
        {currentClient ? (
          <div key={`${activeCategory}-${slideIndex}`} className="animate-fadeIn">
            <ClientCard client={currentClient} />
          </div>
        ) : (
          <div className="bg-[#F8FAFC] border border-[#F1F5F9] rounded-[6px] p-8 text-center">
            <p
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[12px] text-[#94A3B8]"
            >
              このカテゴリの顧客はいません
            </p>
          </div>
        )}

        {/* ドットインジケーター */}
        {totalSlides > 1 && (
          <div className="flex justify-center items-center gap-[6px] mt-4">
            {clients.map((_, idx) => {
              const isActive = idx === slideIndex
              return (
                <button
                  key={idx}
                  onClick={() => setSlideIndex(idx)}
                  className={`
                    h-2 rounded-full cursor-pointer transition-all duration-200
                    ${isActive ? 'bg-[#14B8A6] w-5 rounded-[4px]' : 'bg-[#E2E8F0] w-2'}
                  `}
                  aria-label={`スライド ${idx + 1}`}
                />
              )
            })}
          </div>
        )}
      </div>
    </section>
  )
}
