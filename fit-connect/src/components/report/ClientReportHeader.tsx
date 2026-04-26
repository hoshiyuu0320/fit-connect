'use client'

import { User, Scale, Utensils, Dumbbell, TrendingUp, TrendingDown } from 'lucide-react'
import type { Client } from '@/types/client'
import { PURPOSE_OPTIONS, GENDER_OPTIONS } from '@/types/client'

interface ClientReportHeaderProps {
  client: Client
  latestWeight: number | null
  weightChange: number | null
  mealRecordRate: number
  exerciseTotal: { count: number; minutes: number }
  score: number
  scoreChange: number
}

export function ClientReportHeader({
  client,
  latestWeight,
  weightChange,
  mealRecordRate,
  exerciseTotal,
  score,
  scoreChange,
}: ClientReportHeaderProps) {
  const genderLabel = client.gender
    ? GENDER_OPTIONS[client.gender as keyof typeof GENDER_OPTIONS] ?? client.gender
    : null
  const purposeLabel = client.purpose
    ? PURPOSE_OPTIONS[client.purpose as keyof typeof PURPOSE_OPTIONS] ?? client.purpose
    : null

  const attributeParts = [
    client.age ? `${client.age}歳` : null,
    genderLabel,
    purposeLabel,
  ].filter(Boolean)

  // 目標体重までの進捗計算
  const hasTargetWeight = client.target_weight != null && client.target_weight > 0
  const hasLatestWeight = latestWeight !== null

  let progressPercent = 0
  let remaining = 0
  let initialWeight = latestWeight // fallback if no other info
  if (hasTargetWeight && hasLatestWeight) {
    remaining = Math.abs(latestWeight - client.target_weight)
    // We calculate progress as how far they've come from their initial state.
    // Since we don't have initial weight here, use the assumption that
    // start weight was latestWeight + |weightChange| when weightChange is available.
    const startWeight = weightChange !== null ? latestWeight - weightChange : latestWeight
    initialWeight = startWeight
    const totalToLose = Math.abs(startWeight - client.target_weight)
    if (totalToLose > 0) {
      const lost = Math.abs(startWeight - latestWeight)
      progressPercent = Math.min(100, Math.max(0, (lost / totalToLose) * 100))
    }
  }

  // 食事記録の日数計算（totalDays想定30）
  const mealDaysTotal = 30
  const mealDaysRecorded = Math.round((mealRecordRate / 100) * mealDaysTotal)

  return (
    <div className="space-y-3">
      {/* 上段: クライアント情報バー */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          {/* アバター */}
          {client.profile_image_url ? (
            <img
              src={client.profile_image_url}
              alt={client.name}
              className="w-[48px] h-[48px] rounded-full object-cover"
            />
          ) : (
            <div className="w-[48px] h-[48px] rounded-full bg-[#14B8A6] flex items-center justify-center">
              <User className="w-5 h-5 text-white" />
            </div>
          )}
          <div>
            <p className="font-bold text-base text-[#0F172A]">{client.name}</p>
            {attributeParts.length > 0 && (
              <p className="text-xs text-[#94A3B8]">{attributeParts.join(' / ')}</p>
            )}
          </div>
        </div>

        {/* 目標体重までの進捗バー */}
        {hasTargetWeight && hasLatestWeight && (
          <div className="w-[240px]">
            <div className="flex items-center justify-between mb-1">
              <span className="text-[11px] text-[#94A3B8]">目標体重まで</span>
              <span className="text-[#14B8A6] font-extrabold text-sm">
                あと {remaining.toFixed(1)} kg
              </span>
            </div>
            <div className="w-full h-[8px] bg-[#F8FAFC] border border-[#E2E8F0] rounded-full overflow-hidden">
              <div
                className="h-full bg-[#14B8A6] rounded-full transition-all"
                style={{ width: `${progressPercent}%` }}
              />
            </div>
            <div className="flex justify-between mt-1">
              <span className="text-[10px] text-[#94A3B8]">
                開始: {initialWeight !== null ? `${initialWeight.toFixed(1)} kg` : '--'}
              </span>
              <span className="text-[10px] text-[#94A3B8]">
                現在: {latestWeight.toFixed(1)} kg
              </span>
              <span className="text-[10px] text-[#94A3B8]">
                目標: {client.target_weight.toFixed(1)} kg
              </span>
            </div>
          </div>
        )}
      </div>

      {/* 下段: 4列KPIバー */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {/* 現在体重 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-center gap-2 mb-2">
            <Scale className="w-4 h-4 text-[#94A3B8]" />
            <span className="text-[11px] text-[#94A3B8]">現在体重</span>
          </div>
          {latestWeight !== null ? (
            <div>
              <span className="text-xl font-bold text-[#0F172A]">
                {latestWeight.toFixed(1)}
              </span>
              <span className="text-sm text-[#64748B] ml-1">kg</span>
              {weightChange !== null && weightChange !== 0 && (
                <div className="flex items-center gap-1 mt-1">
                  {weightChange < 0 ? (
                    <>
                      <TrendingDown className="w-3 h-3 text-[#16A34A]" />
                      <span className="text-xs font-semibold text-[#16A34A]">
                        {weightChange.toFixed(1)} kg
                      </span>
                    </>
                  ) : (
                    <>
                      <TrendingUp className="w-3 h-3 text-[#DC2626]" />
                      <span className="text-xs font-semibold text-[#DC2626]">
                        +{weightChange.toFixed(1)} kg
                      </span>
                    </>
                  )}
                </div>
              )}
            </div>
          ) : (
            <span className="text-sm text-[#94A3B8]">データなし</span>
          )}
        </div>

        {/* 食事記録率 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-center gap-2 mb-2">
            <Utensils className="w-4 h-4 text-[#94A3B8]" />
            <span className="text-[11px] text-[#94A3B8]">食事記録率</span>
          </div>
          <div>
            <span className="text-xl font-bold text-[#0F172A]">
              {mealRecordRate}
            </span>
            <span className="text-sm text-[#64748B] ml-1">%</span>
          </div>
          <p className="text-[10px] text-[#94A3B8] mt-1">
            {mealDaysRecorded}/{mealDaysTotal}日
          </p>
        </div>

        {/* 運動合計 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-center gap-2 mb-2">
            <Dumbbell className="w-4 h-4 text-[#94A3B8]" />
            <span className="text-[11px] text-[#94A3B8]">運動合計</span>
          </div>
          <div>
            <span className="text-xl font-bold text-[#0F172A]">
              {exerciseTotal.minutes}
            </span>
            <span className="text-sm text-[#64748B] ml-1">分</span>
          </div>
          <p className="text-[10px] text-[#94A3B8] mt-1">
            {exerciseTotal.count}回
          </p>
        </div>

        {/* 総合スコア */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-center gap-2 mb-2">
            <TrendingUp className="w-4 h-4 text-[#94A3B8]" />
            <span className="text-[11px] text-[#94A3B8]">総合スコア</span>
          </div>
          <div>
            <span className="text-xl font-bold text-[#0F172A]">{score}</span>
            <span className="text-sm text-[#64748B] ml-1">/100</span>
          </div>
          {scoreChange !== 0 && (
            <div className="flex items-center gap-1 mt-1">
              {scoreChange > 0 ? (
                <>
                  <TrendingUp className="w-3 h-3 text-[#16A34A]" />
                  <span className="text-xs font-semibold text-[#16A34A]">
                    +{scoreChange} 前月比
                  </span>
                </>
              ) : (
                <>
                  <TrendingDown className="w-3 h-3 text-[#DC2626]" />
                  <span className="text-xs font-semibold text-[#DC2626]">
                    {scoreChange} 前月比
                  </span>
                </>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
