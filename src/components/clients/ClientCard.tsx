'use client'

import Image from 'next/image'
import { useRouter } from 'next/navigation'
import { Check, MinusCircle, MessageCircle, FileText, Calendar } from 'lucide-react'
import type { Client } from '@/types/client'
import { GENDER_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'
import type { ClientMetrics } from '@/lib/supabase/getClientListMetrics'

type ClientCardProps = {
  client: Client
  workoutStatus?: 'completed' | 'partial' | 'pending' | null
  metrics?: ClientMetrics | null
}

function getRelativeTime(dateStr: string): string {
  const now = new Date()
  const date = new Date(dateStr)
  const diffMs = now.getTime() - date.getTime()
  const diffMinutes = Math.floor(diffMs / (1000 * 60))
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60))
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24))

  if (diffMinutes < 1) return 'たった今'
  if (diffMinutes < 60) return `${diffMinutes}分前`
  if (diffHours < 24) return `${diffHours}時間前`
  if (diffDays < 30) return `${diffDays}日前`
  return `${Math.floor(diffDays / 30)}ヶ月前`
}

const genderAvatarStyles = {
  male: { bg: 'bg-[#DBEAFE]', text: 'text-[#2563EB]' },
  female: { bg: 'bg-[#FCE7F3]', text: 'text-[#DB2777]' },
  other: { bg: 'bg-[#FEF3C7]', text: 'text-[#D97706]' },
}

export function ClientCard({ client, workoutStatus, metrics }: ClientCardProps) {
  const router = useRouter()

  const handleClick = () => {
    router.push(`/clients/${client.client_id}`)
  }

  const handleMessageClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    router.push(`/message?clientId=${client.client_id}`)
  }

  const handleNotesClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    router.push(`/clients/${client.client_id}?tab=notes`)
  }

  const handleScheduleClick = (e: React.MouseEvent) => {
    e.stopPropagation()
    router.push(`/schedule?clientId=${client.client_id}`)
  }

  const isDone =
    workoutStatus === 'completed' ||
    workoutStatus === 'partial' ||
    (workoutStatus == null && metrics?.todayWorkoutDone === true)

  const avatarStyle = genderAvatarStyles[client.gender] ?? genderAvatarStyles.other
  const initials = client.name.slice(0, 2)

  const weightChangeValue = metrics?.monthlyWeightChange ?? null
  const weightChangeDisplay =
    weightChangeValue === null
      ? '--'
      : weightChangeValue > 0
      ? `+${weightChangeValue}`
      : `${weightChangeValue}`

  return (
    <div
      className="relative bg-white border border-[#E2E8F0] rounded-md p-5 cursor-pointer transition-all hover:border-[#14B8A6] hover:shadow-[0_2px_8px_rgba(20,184,166,0.08)]"
      onClick={handleClick}
    >
      {/* ステータスバッジ */}
      <div className="absolute top-3.5 right-3.5">
        {isDone ? (
          <span className="flex items-center gap-1 px-2 py-1 text-[10px] font-semibold bg-[#F0FDF4] text-[#16A34A] border border-[#BBF7D0] rounded-md">
            <Check size={12} />
            完了
          </span>
        ) : (
          <span className="flex items-center gap-1 px-2 py-1 text-[10px] font-semibold bg-[#F8FAFC] text-[#94A3B8] border border-[#E2E8F0] rounded-md">
            <MinusCircle size={12} />
            未実施
          </span>
        )}
      </div>

      {/* 上部: アバター + 名前・属性 */}
      <div className="flex items-start gap-3.5 mb-3.5">
        {/* アバター */}
        <div className="flex-shrink-0 w-11 h-11 rounded-md overflow-hidden">
          {client.profile_image_url ? (
            <Image
              src={client.profile_image_url}
              alt={client.name}
              width={44}
              height={44}
              className="w-full h-full object-cover rounded-md"
            />
          ) : (
            <div
              className={`w-full h-full flex items-center justify-center rounded-md ${avatarStyle.bg} ${avatarStyle.text} font-bold text-[15px]`}
            >
              {initials}
            </div>
          )}
        </div>

        {/* 名前・属性 */}
        <div className="flex-1 min-w-0 pr-16">
          <p className="text-[15px] font-bold text-[#0F172A] truncate">{client.name}</p>
          <p className="text-xs text-[#94A3B8] mt-0.5">
            {GENDER_OPTIONS[client.gender]} / {client.age}歳
            {client.occupation ? ` / ${client.occupation}` : ''}
          </p>
        </div>
      </div>

      {/* メトリクス行 */}
      <div className="grid grid-cols-3 gap-2 mb-3.5 p-2.5 bg-[#F8FAFC] rounded-md">
        {/* 体重 */}
        <div className="text-center">
          <p className="text-[15px] font-bold text-[#0F172A]">
            {metrics?.latestWeight ?? '--'}
          </p>
          <p className="text-[10px] text-[#94A3B8] mt-0.5">体重 (kg)</p>
        </div>

        {/* 残チケット */}
        <div className="text-center">
          <p
            className={`text-[15px] font-bold ${
              (metrics?.remainingTickets ?? 0) === 0 ? 'text-[#DC2626]' : 'text-[#0F172A]'
            }`}
          >
            {metrics?.remainingTickets ?? 0}
          </p>
          <p className="text-[10px] text-[#94A3B8] mt-0.5">残チケット</p>
        </div>

        {/* 月間変動 */}
        <div className="text-center">
          <p className="text-[15px] font-bold text-[#0F172A]">{weightChangeDisplay}</p>
          <p className="text-[10px] text-[#94A3B8] mt-0.5">月間変動</p>
        </div>
      </div>

      {/* 目的バッジ */}
      <span className="inline-flex px-2 py-0.5 text-[11px] font-semibold bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded-md">
        {PURPOSE_OPTIONS[client.purpose]}
      </span>

      {/* フッター */}
      <div className="flex items-center justify-between mt-3.5 pt-3.5 border-t border-[#E2E8F0]">
        {/* クイックアクション */}
        <div className="flex items-center gap-1">
          <button
            onClick={handleMessageClick}
            className="flex items-center justify-center w-[30px] h-[30px] rounded-md border border-[#E2E8F0] bg-white text-[#94A3B8] transition-colors hover:border-[#14B8A6] hover:text-[#14B8A6] hover:bg-[#F0FDFA]"
            title="メッセージ"
          >
            <MessageCircle size={14} />
          </button>
          <button
            onClick={handleNotesClick}
            className="flex items-center justify-center w-[30px] h-[30px] rounded-md border border-[#E2E8F0] bg-white text-[#94A3B8] transition-colors hover:border-[#14B8A6] hover:text-[#14B8A6] hover:bg-[#F0FDFA]"
            title="カルテ"
          >
            <FileText size={14} />
          </button>
          <button
            onClick={handleScheduleClick}
            className="flex items-center justify-center w-[30px] h-[30px] rounded-md border border-[#E2E8F0] bg-white text-[#94A3B8] transition-colors hover:border-[#14B8A6] hover:text-[#14B8A6] hover:bg-[#F0FDFA]"
            title="スケジュール"
          >
            <Calendar size={14} />
          </button>
        </div>

        {/* 最終活動 */}
        <p className="text-[11px] text-[#94A3B8]">
          {getRelativeTime(client.created_at)}
        </p>
      </div>
    </div>
  )
}
