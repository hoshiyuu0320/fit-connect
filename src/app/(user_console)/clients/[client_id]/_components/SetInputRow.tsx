"use client"

import type { ActualSet } from '@/types/workout'

type SetInputRowProps = {
  setNumber: number
  targetWeight: number | null
  targetReps: number
  actualSet: ActualSet
  previousSet?: ActualSet | null
  onChange: (set: ActualSet) => void
}

export function SetInputRow({ setNumber, targetWeight, targetReps, actualSet, previousSet, onChange }: SetInputRowProps) {
  const handleWeightChange = (delta: number) => {
    onChange({
      ...actualSet,
      weight: Math.max(0, (actualSet.weight ?? targetWeight ?? 0) + delta),
    })
  }

  const handleRepsChange = (delta: number) => {
    onChange({
      ...actualSet,
      reps: Math.max(0, (actualSet.reps ?? targetReps ?? 0) + delta),
    })
  }

  return (
    <div className="flex items-center gap-3 py-2 border-b border-gray-100">
      {/* セット番号 */}
      <div className="w-8 text-center text-sm font-medium text-gray-500">
        {setNumber}
      </div>

      {/* 前回データ（薄い文字） */}
      {previousSet ? (
        <div className="text-xs text-gray-400 w-24">
          前回: {previousSet.weight}kg × {previousSet.reps}
        </div>
      ) : (
        <div className="w-24" />
      )}

      {/* 重量入力 */}
      <div className="flex items-center gap-1">
        <button
          onClick={() => handleWeightChange(-2.5)}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center bg-gray-100 rounded-lg text-lg font-bold hover:bg-gray-200 active:bg-gray-300"
        >
          −
        </button>
        <div className="min-w-[60px] text-center font-semibold">
          {(actualSet.weight ?? targetWeight ?? 0)}kg
        </div>
        <button
          onClick={() => handleWeightChange(2.5)}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center bg-gray-100 rounded-lg text-lg font-bold hover:bg-gray-200 active:bg-gray-300"
        >
          +
        </button>
      </div>

      {/* × */}
      <span className="text-gray-400">×</span>

      {/* 回数入力 */}
      <div className="flex items-center gap-1">
        <button
          onClick={() => handleRepsChange(-1)}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center bg-gray-100 rounded-lg text-lg font-bold hover:bg-gray-200 active:bg-gray-300"
        >
          −
        </button>
        <div className="min-w-[40px] text-center font-semibold">
          {(actualSet.reps ?? targetReps ?? 0)}回
        </div>
        <button
          onClick={() => handleRepsChange(1)}
          className="min-h-[44px] min-w-[44px] flex items-center justify-center bg-gray-100 rounded-lg text-lg font-bold hover:bg-gray-200 active:bg-gray-300"
        >
          +
        </button>
      </div>

      {/* 完了チェック */}
      <button
        onClick={() => onChange({ ...actualSet, done: !actualSet.done })}
        className={`min-h-[44px] min-w-[44px] flex items-center justify-center rounded-lg ${
          actualSet.done ? 'bg-green-500 text-white' : 'bg-gray-100 text-gray-400'
        }`}
      >
        ✓
      </button>
    </div>
  )
}
