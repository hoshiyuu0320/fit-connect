'use client'

import React from 'react'
import Link from 'next/link'
import type { RecordCardData, RecordCardType } from '@/components/message/recordCardParser'

// RecordCardType → クライアント詳細タブ名のマッピング
const tabMap: Record<RecordCardType, string> = {
  weight: 'weight',
  meal: 'meal',
  exercise: 'exercise',
  achievement: 'exercise',
}

interface RecordCardProps {
  data: RecordCardData
  clientId?: string
  imageUrls?: string[]
  onImageClick?: (url: string) => void
}

// 種別ごとのスタイル定義
const styleMap: Record<
  RecordCardType,
  { border: string; bg: string; headerText: string }
> = {
  weight: {
    border: 'border-l-blue-400',
    bg: 'bg-blue-50',
    headerText: 'text-blue-700',
  },
  meal: {
    border: 'border-l-orange-400',
    bg: 'bg-orange-50',
    headerText: 'text-orange-700',
  },
  exercise: {
    border: 'border-l-green-400',
    bg: 'bg-green-50',
    headerText: 'text-green-700',
  },
  achievement: {
    border: 'border-l-purple-400',
    bg: 'bg-purple-50',
    headerText: 'text-purple-700',
  },
}

// 体重計アイコン
function WeightIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="12" r="10" />
      <path d="M8 12h8" />
      <path d="M12 8v4l3 3" />
    </svg>
  )
}

// フォーク&ナイフアイコン
function MealIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M3 2v7c0 1.1.9 2 2 2h4a2 2 0 0 0 2-2V2" />
      <path d="M7 2v20" />
      <path d="M21 15V2a5 5 0 0 0-5 5v6c0 1.1.9 2 2 2h3zm0 0v7" />
    </svg>
  )
}

// ダンベルアイコン
function ExerciseIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6.5 6.5h11" />
      <path d="M6.5 17.5h11" />
      <path d="M3 9.5v5" />
      <path d="M21 9.5v5" />
      <rect x="1" y="8" width="4" height="8" rx="1" />
      <rect x="19" y="8" width="4" height="8" rx="1" />
      <rect x="5" y="5" width="2" height="14" rx="1" />
      <rect x="17" y="5" width="2" height="14" rx="1" />
    </svg>
  )
}

// トロフィーアイコン
function AchievementIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6" />
      <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18" />
      <path d="M4 22h16" />
      <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22" />
      <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22" />
      <path d="M18 2H6v7a6 6 0 0 0 12 0V2z" />
    </svg>
  )
}

const iconMap: Record<RecordCardType, () => React.ReactNode> = {
  weight: WeightIcon,
  meal: MealIcon,
  exercise: ExerciseIcon,
  achievement: AchievementIcon,
}

export function RecordCard({ data, clientId, imageUrls, onImageClick }: RecordCardProps) {
  const style = styleMap[data.type]
  const Icon = iconMap[data.type]

  const card = (
    <div
      className={`
        max-w-xs md:max-w-md lg:max-w-lg
        rounded-lg border-l-4 p-3
        ${style.border} ${style.bg}
        ${clientId ? 'hover:brightness-95 transition-all cursor-pointer' : ''}
      `}
    >
      {/* ヘッダー: アイコン + ラベル */}
      <div className={`flex items-center justify-between mb-1.5`}>
        <div className={`flex items-center gap-1.5 ${style.headerText}`}>
          <Icon />
          <span className="text-sm font-semibold">{data.label}</span>
        </div>
        {clientId && (
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-400">
            <polyline points="9 18 15 12 9 6" />
          </svg>
        )}
      </div>

      {/* ボディ: details を1行ずつ表示 */}
      {data.details.length > 0 && (
        <div className="space-y-0.5">
          {data.details.map((line, index) => (
            <p key={index} className="text-sm text-gray-700 break-words">
              {line}
            </p>
          ))}
        </div>
      )}

      {/* 添付画像（食事記録など） */}
      {imageUrls && imageUrls.length > 0 && (
        <div className="flex flex-wrap gap-2 mt-2">
          {imageUrls.map((url, imgIndex) => (
            <button
              key={imgIndex}
              type="button"
              onClick={(e) => {
                e.preventDefault()
                e.stopPropagation()
                onImageClick?.(url)
              }}
              className="block"
            >
              <img
                src={url}
                alt={`添付画像 ${imgIndex + 1}`}
                className="w-24 h-24 object-cover rounded-lg cursor-pointer hover:opacity-80 transition-opacity"
              />
            </button>
          ))}
        </div>
      )}
    </div>
  )

  if (clientId) {
    return (
      <Link href={`/clients/${clientId}?tab=${tabMap[data.type]}`}>
        {card}
      </Link>
    )
  }

  return card
}
