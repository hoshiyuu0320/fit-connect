'use client'

import { useState, useMemo } from 'react'
import Image from 'next/image'
import { format } from 'date-fns'
import { WeightChart } from '@/components/clients/WeightChart'
import { ImageModal } from '@/components/message/ImageModal'
import type { WeightRecord, MealRecord, ExerciseRecord } from '@/types/client'
import {
  type BmrFormula,
  type WeightPeriod,
  calculateBmr,
  calculateCalorieBalance,
  predictWeight,
  getPeriodDays,
} from '@/utils/weightPrediction'

interface WeightTabProps {
  weightRecords: WeightRecord[]
  targetWeight: number
  mealRecords: MealRecord[]
  exerciseRecords: ExerciseRecord[]
  clientHeight: number
  clientAge: number
  clientGender: 'male' | 'female' | 'other'
  bmrFormula: BmrFormula
  onBmrFormulaChange: (formula: BmrFormula) => void
}

const WEIGHT_PERIOD_BUTTONS: { value: WeightPeriod; label: string }[] = [
  { value: '1W', label: '1W' },
  { value: '1M', label: '1M' },
  { value: '3M', label: '3M' },
  { value: 'ALL', label: 'ALL' },
]

export function WeightTab({
  weightRecords,
  targetWeight,
  mealRecords,
  exerciseRecords,
  clientHeight,
  clientAge,
  clientGender,
  bmrFormula,
  onBmrFormulaChange,
}: WeightTabProps) {
  const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null)
  const [weightPeriod, setWeightPeriod] = useState<WeightPeriod>('1M')

  const filteredRecords = useMemo(() => {
    const now = new Date()
    let startDate: Date
    switch (weightPeriod) {
      case '1W':
        startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
        break
      case '1M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 1, now.getDate())
        break
      case '3M':
        startDate = new Date(now.getFullYear(), now.getMonth() - 3, now.getDate())
        break
      case 'ALL':
      default:
        return weightRecords
    }
    return weightRecords.filter((r) => new Date(r.recorded_at) >= startDate)
  }, [weightRecords, weightPeriod])

  const weightStats = useMemo(() => {
    if (filteredRecords.length === 0) {
      return { avg: null, max: null, min: null, range: null }
    }
    const weights = filteredRecords.map((r) => r.weight)
    const sum = weights.reduce((a, b) => a + b, 0)
    const avg = sum / weights.length
    const max = Math.max(...weights)
    const min = Math.min(...weights)
    const range = max - min
    return { avg, max, min, range }
  }, [filteredRecords])

  // --- Prediction computations ---

  const filteredMealRecords = useMemo(() => {
    const days = getPeriodDays(weightPeriod)
    const startDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
    return mealRecords.filter((m) => new Date(m.recorded_at) >= startDate)
  }, [mealRecords, weightPeriod])

  const filteredExerciseRecords = useMemo(() => {
    const days = getPeriodDays(weightPeriod)
    const startDate = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
    return exerciseRecords.filter((e) => new Date(e.recorded_at) >= startDate)
  }, [exerciseRecords, weightPeriod])

  const currentWeight = weightRecords[0]?.weight ?? null

  const bmr = useMemo(() => {
    if (!currentWeight || !clientHeight || !clientAge || !clientGender) return null
    return calculateBmr({
      weight: currentWeight,
      height: clientHeight,
      age: clientAge,
      gender: clientGender,
      formula: bmrFormula,
    })
  }, [currentWeight, clientHeight, clientAge, clientGender, bmrFormula])

  const calorieBalance = useMemo(() => {
    if (bmr === null) return null
    const periodDays = getPeriodDays(weightPeriod)
    return calculateCalorieBalance({
      mealRecords: filteredMealRecords,
      exerciseRecords: filteredExerciseRecords,
      bmr,
      periodDays,
    })
  }, [bmr, filteredMealRecords, filteredExerciseRecords, weightPeriod])

  const prediction = useMemo(() => {
    if (currentWeight === null || calorieBalance === null || calorieBalance.dailyBalance === null) return null
    return predictWeight({
      currentWeight,
      targetWeight,
      dailyBalance: calorieBalance.dailyBalance,
    })
  }, [currentWeight, targetWeight, calorieBalance])

  const predictionChartData = useMemo(() => {
    if (!prediction) return undefined
    return {
      monthlyChange: prediction.monthlyChange,
      predictedWeight: prediction.predictedWeight,
      periodDays: getPeriodDays(weightPeriod),
    }
  }, [prediction, weightPeriod])

  if (weightRecords.length === 0) {
    return (
      <div className="flex items-center justify-center py-12">
        <p className="text-[#94A3B8] text-sm">まだ体重記録がありません</p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* グラフカード */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-sm font-semibold text-[#0F172A]">体重推移</h3>
          <div className="flex items-center gap-1">
            {WEIGHT_PERIOD_BUTTONS.map((btn) => (
              <button
                key={btn.value}
                onClick={() => setWeightPeriod(btn.value)}
                className={`px-2.5 py-1 text-xs font-medium rounded-md transition-colors ${
                  weightPeriod === btn.value
                    ? 'bg-[#14B8A6] text-white'
                    : 'bg-[#F8FAFC] text-[#64748B] border border-[#E2E8F0] hover:border-[#14B8A6]'
                }`}
              >
                {btn.label}
              </button>
            ))}
          </div>
        </div>

        {/* 凡例 */}
        <div className="flex items-center gap-4 mb-2 text-xs text-[#94A3B8]">
          <div className="flex items-center gap-2">
            <span className="inline-block w-4 border-t-2 border-dashed border-[#DC2626]" />
            <span>目標: {targetWeight}kg</span>
          </div>
          {prediction && (
            <div className="flex items-center gap-2">
              <span className="inline-block w-4 border-t-2 border-dashed border-[#14B8A6]" />
              <span>予測トレンド</span>
            </div>
          )}
        </div>

        <WeightChart
          weightRecords={filteredRecords}
          targetWeight={targetWeight}
          showPeriodFilter={false}
          prediction={predictionChartData}
        />
      </div>

      {/* 期間統計 */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">期間統計</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div>
            <p className="text-sm text-[#94A3B8]">平均</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {weightStats.avg !== null ? `${weightStats.avg.toFixed(1)}kg` : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">最高</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {weightStats.max !== null ? `${weightStats.max.toFixed(1)}kg` : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">最低</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {weightStats.min !== null ? `${weightStats.min.toFixed(1)}kg` : '--'}
            </p>
          </div>
          <div>
            <p className="text-sm text-[#94A3B8]">変動幅</p>
            <p className="text-lg font-bold text-[#0F172A]">
              {weightStats.range !== null ? `${weightStats.range.toFixed(1)}kg` : '--'}
            </p>
          </div>
        </div>
      </div>

      {/* 体重予測カード */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">体重予測</h3>

        {/* BMR セクション */}
        {bmr !== null ? (
          <div className="space-y-4">
            <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
              <div className="flex items-center justify-between mb-2">
                <p className="text-xs text-[#94A3B8]">基礎代謝量 (BMR)</p>
                <select
                  value={bmrFormula}
                  onChange={(e) => onBmrFormulaChange(e.target.value as BmrFormula)}
                  className="text-xs text-[#64748B] bg-white border border-[#E2E8F0] rounded-md px-2 py-1"
                >
                  <option value="mifflin">ミフリン・セントジョール式</option>
                  <option value="harris">ハリス・ベネディクト式</option>
                </select>
              </div>
              <p className="text-xl font-bold text-[#0F172A]">
                {Math.round(bmr)}
                <span className="text-xs text-[#94A3B8] ml-1">kcal/日</span>
              </p>
            </div>

            {/* カロリー収支 */}
            {calorieBalance && calorieBalance.dailyBalance !== null && (
              <div className="grid grid-cols-3 gap-3">
                <div className="bg-[#FFF7ED] border border-[#E2E8F0] rounded-md p-3">
                  <p className="text-xs text-[#EA580C] mb-1">平均摂取</p>
                  <p className="text-lg font-bold text-[#EA580C]">
                    {calorieBalance.avgIntake !== null ? calorieBalance.avgIntake.toLocaleString() : '--'}
                    <span className="text-[10px] ml-0.5">kcal</span>
                  </p>
                </div>
                <div className="bg-[#F0FDF4] border border-[#E2E8F0] rounded-md p-3">
                  <p className="text-xs text-[#16A34A] mb-1">平均消費</p>
                  <p className="text-lg font-bold text-[#16A34A]">
                    {calorieBalance.avgExerciseBurn !== null
                      ? (calorieBalance.avgExerciseBurn + Math.round(bmr)).toLocaleString()
                      : Math.round(bmr).toLocaleString()}
                    <span className="text-[10px] ml-0.5">kcal</span>
                  </p>
                </div>
                <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-3">
                  <p className="text-xs text-[#94A3B8] mb-1">1日の収支</p>
                  <p className={`text-lg font-bold ${calorieBalance.dailyBalance > 0 ? 'text-[#DC2626]' : 'text-[#16A34A]'}`}>
                    {calorieBalance.dailyBalance > 0 ? '+' : ''}
                    {calorieBalance.dailyBalance.toLocaleString()}
                    <span className="text-[10px] ml-0.5">kcal</span>
                  </p>
                </div>
              </div>
            )}

            {/* 予測結果 */}
            {prediction && (
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
                  <p className="text-xs text-[#94A3B8] mb-1">1ヶ月後予測</p>
                  <p className={`text-xl font-bold ${prediction.monthlyChange > 0 ? 'text-[#DC2626]' : 'text-[#16A34A]'}`}>
                    {prediction.predictedWeight}
                    <span className="text-xs ml-1">kg</span>
                  </p>
                  <p className={`text-xs mt-0.5 ${prediction.monthlyChange > 0 ? 'text-[#DC2626]' : 'text-[#16A34A]'}`}>
                    {prediction.monthlyChange > 0 ? '+' : ''}
                    {prediction.monthlyChange}kg/月
                  </p>
                </div>
                <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
                  <p className="text-xs text-[#94A3B8] mb-1">目標到達</p>
                  {prediction.monthsToGoal !== null ? (
                    <p className="text-xl font-bold text-[#14B8A6]">
                      {prediction.monthsToGoal}
                      <span className="text-xs ml-1">ヶ月</span>
                    </p>
                  ) : (
                    <p className="text-sm text-[#94A3B8]">
                      現在のペースでは<br />目標に近づいていません
                    </p>
                  )}
                </div>
              </div>
            )}

            {/* データ不足時メッセージ */}
            {calorieBalance === null || calorieBalance.dailyBalance === null ? (
              <p className="text-xs text-[#94A3B8]">
                食事・運動記録が不足しています。記録を追加すると予測が表示されます。
              </p>
            ) : null}
          </div>
        ) : (
          <p className="text-sm text-[#94A3B8]">クライアント情報が不足しています</p>
        )}
      </div>

      {/* 最近の記録リスト（最新5件） */}
      <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
        <h3 className="text-sm font-semibold text-[#0F172A] mb-3">最近の記録</h3>
        <div className="space-y-0">
          {weightRecords.slice(0, 5).map((record, i) => {
            const prevRecord = weightRecords[i + 1]
            const change = prevRecord ? record.weight - prevRecord.weight : null
            const comment = record.notes
              ?.replace(/^[\d.]+\s*(?:kg)?\s*/i, '')
              .trim() || null
            const hasImage = record.image_urls && record.image_urls.length > 0

            return (
              <div key={record.id} className="py-3 border-b border-[#F1F5F9] last:border-0">
                {/* 上段: 日付・体重・変化量 */}
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-[#94A3B8] w-16">
                      {format(new Date(record.recorded_at), 'M/d')}
                    </span>
                    <span className="text-sm font-bold text-[#0F172A]">{record.weight}kg</span>
                  </div>
                  <div className="flex items-center gap-2">
                    {change !== null && (
                      <span
                        className={`text-xs font-medium ${
                          change > 0
                            ? 'text-[#DC2626]'
                            : change < 0
                              ? 'text-[#16A34A]'
                              : 'text-[#94A3B8]'
                        }`}
                      >
                        {change > 0 ? '+' : ''}
                        {change.toFixed(1)}
                      </span>
                    )}
                    {hasImage && (
                      <span className="text-[10px] text-[#94A3B8]">📷</span>
                    )}
                  </div>
                </div>

                {/* コメント */}
                {comment && (
                  <div className="mt-2 bg-[#F8FAFC] border border-[#E2E8F0] rounded-md px-3 py-2 flex items-center gap-2">
                    <svg
                      width="12"
                      height="12"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="text-[#94A3B8] flex-shrink-0"
                    >
                      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                    </svg>
                    <p className="text-xs text-[#64748B] whitespace-pre-wrap leading-tight">
                      {comment}
                    </p>
                  </div>
                )}

                {/* 写真 */}
                {hasImage && (
                  <div className="flex gap-2 mt-2">
                    {record.image_urls!.map((url, imgIndex) => (
                      <button
                        key={imgIndex}
                        type="button"
                        onClick={() => setSelectedImageUrl(url)}
                        className="relative w-14 h-14 rounded-md overflow-hidden border border-[#E2E8F0] hover:opacity-80 transition-opacity"
                      >
                        <Image
                          src={url}
                          alt={`体重記録画像 ${imgIndex + 1}`}
                          fill
                          className="object-cover"
                          unoptimized
                        />
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>

      <ImageModal imageUrl={selectedImageUrl} onClose={() => setSelectedImageUrl(null)} />
    </div>
  )
}
