"use client"

import { useEffect, useState } from 'react'

type SessionTimerBarProps = {
  startedAt: string | null
  finishedAt: string | null
  onStart: () => void
  onFinish: () => void
}

function formatElapsed(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  }
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
}

export function SessionTimerBar({
  startedAt,
  finishedAt,
  onStart,
  onFinish,
}: SessionTimerBarProps) {
  const [elapsed, setElapsed] = useState(0)

  // 実行中のみタイマーを動かす
  useEffect(() => {
    if (startedAt === null || finishedAt !== null) {
      setElapsed(0)
      return
    }

    // 初期値: startedAt から現在までの経過秒数を計算
    const calcElapsed = () =>
      Math.floor((Date.now() - new Date(startedAt).getTime()) / 1000)

    setElapsed(calcElapsed())

    const timer = setInterval(() => {
      setElapsed(calcElapsed())
    }, 1000)

    return () => clearInterval(timer)
  }, [startedAt, finishedAt])

  // 完了状態: 所要時間を計算
  const duration =
    startedAt !== null && finishedAt !== null
      ? Math.floor(
          (new Date(finishedAt).getTime() - new Date(startedAt).getTime()) / 1000
        )
      : 0

  // 未開始
  if (startedAt === null) {
    return (
      <div className="flex items-center justify-between bg-white border border-[#E2E8F0] rounded-md px-4 py-3">
        <span className="text-sm text-[#94A3B8]">セッションを開始してください</span>
        <button
          onClick={onStart}
          className="px-6 py-2 bg-[#14B8A6] hover:bg-[#0D9488] text-white rounded-md font-medium transition-colors"
        >
          セッション開始
        </button>
      </div>
    )
  }

  // 完了
  if (finishedAt !== null) {
    return (
      <div className="flex items-center justify-between bg-[#F0FDF4] rounded-md border border-[#16A34A] px-4 py-3">
        <div className="flex items-center gap-3">
          <span className="text-[#16A34A] text-sm font-medium">セッション完了</span>
          <span className="text-[#94A3B8] text-sm">所要時間:</span>
          <span className="text-2xl font-mono font-bold text-[#0F172A]">
            {formatElapsed(duration)}
          </span>
        </div>
        <span className="text-xs text-[#94A3B8] px-2 py-1 bg-[#DCFCE7] rounded-md">
          終了済み
        </span>
      </div>
    )
  }

  // 実行中
  return (
    <div className="flex items-center justify-between bg-[#F0FDFA] rounded-md border border-[#14B8A6] px-4 py-3">
      <div className="flex items-center gap-3">
        <span className="relative flex h-2.5 w-2.5">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-[#14B8A6] opacity-75"></span>
          <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-[#14B8A6]"></span>
        </span>
        <span className="text-[#14B8A6] text-sm font-medium">セッション中</span>
        <span className="text-2xl font-mono font-bold text-[#0F172A]">
          {formatElapsed(elapsed)}
        </span>
      </div>
      <button
        onClick={onFinish}
        className="px-6 py-2 bg-[#DC2626] hover:bg-[#B91C1C] text-white rounded-md font-medium transition-colors"
      >
        セッション終了
      </button>
    </div>
  )
}
