'use client'

import { useMemo } from 'react'
import { HeatmapRow } from '@/types/report'

interface ActivityHeatmapProps {
  data: HeatmapRow[]
  loading?: boolean
  startDate: string // YYYY-MM-DD
  endDate: string   // YYYY-MM-DD
}

const CELL_SIZE = 14
const CELL_GAP = 3
const DAY_LABELS = ['月', '火', '水', '木', '金', '土', '日']

function getCellColor(count: number): { bg: string; border?: string } {
  if (count === 0) return { bg: '#F8FAFC', border: '#E2E8F0' }
  if (count === 1) return { bg: '#CCFBF1' }
  if (count === 2) return { bg: '#5EEAD4' }
  if (count === 3) return { bg: '#14B8A6' }
  return { bg: '#0D9488' }
}

/**
 * startDate から endDate までの日付文字列配列を生成
 */
function generateDateRange(startDate: string, endDate: string): string[] {
  const dates: string[] = []
  const start = new Date(startDate + 'T00:00:00')
  const end = new Date(endDate + 'T00:00:00')

  const current = new Date(start)
  while (current <= end) {
    const yyyy = current.getFullYear()
    const mm = String(current.getMonth() + 1).padStart(2, '0')
    const dd = String(current.getDate()).padStart(2, '0')
    dates.push(`${yyyy}-${mm}-${dd}`)
    current.setDate(current.getDate() + 1)
  }
  return dates
}

function HeatmapSkeleton() {
  return (
    <div
      className="bg-white border rounded-md overflow-hidden"
      style={{ borderColor: '#E2E8F0' }}
    >
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: '1px solid #E2E8F0' }}
      >
        <div className="h-4 w-32 rounded animate-pulse" style={{ backgroundColor: '#F8FAFC' }} />
      </div>
      <div className="p-4 space-y-2">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="flex items-center gap-2">
            <div className="h-3 w-12 rounded animate-pulse" style={{ backgroundColor: '#F8FAFC' }} />
            <div className="flex gap-[3px]">
              {Array.from({ length: 7 }).map((_, j) => (
                <div
                  key={j}
                  className="rounded-sm animate-pulse"
                  style={{
                    width: `${CELL_SIZE}px`,
                    height: `${CELL_SIZE}px`,
                    backgroundColor: '#F8FAFC',
                  }}
                />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

const LEGEND_LEVELS = [0, 1, 2, 3, 4]

export function ActivityHeatmap({ data, loading, startDate, endDate }: ActivityHeatmapProps) {
  // 日付範囲を生成
  const allDates = useMemo(() => generateDateRange(startDate, endDate), [startDate, endDate])

  // 各クライアントの日付→カウント Mapを構築
  const clientMaps = useMemo(() => {
    const maps = new Map<string, Map<string, number>>()
    for (const row of data) {
      const dateMap = new Map<string, number>()
      for (const dc of row.dailyCounts) {
        dateMap.set(dc.date, dc.count)
      }
      maps.set(row.clientId, dateMap)
    }
    return maps
  }, [data])

  if (loading) {
    return <HeatmapSkeleton />
  }

  return (
    <div
      className="bg-white border rounded-md overflow-hidden"
      style={{ borderColor: '#E2E8F0' }}
    >
      {/* ヘッダー */}
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: '1px solid #E2E8F0' }}
      >
        <h3 className="font-extrabold text-sm" style={{ color: '#0F172A' }}>
          全顧客アクティビティ
        </h3>
        {/* 凡例 */}
        <div className="flex items-center gap-1.5">
          <span style={{ fontSize: '10px', color: '#94A3B8' }}>少ない</span>
          {LEGEND_LEVELS.map((level) => {
            const cellColor = getCellColor(level)
            return (
              <div
                key={level}
                className="rounded-sm"
                style={{
                  width: `${CELL_SIZE}px`,
                  height: `${CELL_SIZE}px`,
                  backgroundColor: cellColor.bg,
                  border: cellColor.border ? `1px solid ${cellColor.border}` : 'none',
                }}
              />
            )
          })}
          <span style={{ fontSize: '10px', color: '#94A3B8' }}>多い</span>
        </div>
      </div>

      {/* ヒートマップ本体 */}
      <div className="p-4 overflow-x-auto">
        <div className="inline-block">
          {/* 曜日ヘッダー行 */}
          <div className="flex items-center mb-1">
            {/* クライアント名スペーサー */}
            <div style={{ width: '52px', flexShrink: 0 }} />
            <div className="flex" style={{ gap: `${CELL_GAP}px` }}>
              {allDates.map((dateStr) => {
                const d = new Date(dateStr + 'T00:00:00')
                const dayOfWeek = d.getDay()
                // 日曜=0を6に、月曜=1を0に変換してDAY_LABELSのインデックスに合わせる
                const labelIndex = dayOfWeek === 0 ? 6 : dayOfWeek - 1
                return (
                  <div
                    key={dateStr}
                    className="text-center flex-shrink-0"
                    style={{
                      width: `${CELL_SIZE}px`,
                      fontSize: '8px',
                      color: '#94A3B8',
                      lineHeight: '12px',
                    }}
                  >
                    {DAY_LABELS[labelIndex]}
                  </div>
                )
              })}
            </div>
          </div>

          {/* クライアント行 */}
          {data.map((row) => {
            const dateMap = clientMaps.get(row.clientId)
            return (
              <div key={row.clientId} className="flex items-center mb-[3px]">
                {/* クライアント名 */}
                <div
                  className="text-right truncate pr-2 flex-shrink-0"
                  style={{
                    width: '52px',
                    fontSize: '10px',
                    color: '#475569',
                  }}
                  title={row.clientName}
                >
                  {row.clientName}
                </div>
                {/* セル */}
                <div className="flex" style={{ gap: `${CELL_GAP}px` }}>
                  {allDates.map((dateStr) => {
                    const count = dateMap?.get(dateStr) ?? 0
                    const cellColor = getCellColor(count)
                    return (
                      <div
                        key={dateStr}
                        className="rounded-sm flex-shrink-0"
                        style={{
                          width: `${CELL_SIZE}px`,
                          height: `${CELL_SIZE}px`,
                          backgroundColor: cellColor.bg,
                          border: cellColor.border
                            ? `1px solid ${cellColor.border}`
                            : 'none',
                        }}
                        title={`${row.clientName} - ${dateStr}: ${count}件`}
                      />
                    )
                  })}
                </div>
              </div>
            )
          })}

          {data.length === 0 && (
            <div
              className="text-center py-8"
              style={{ fontSize: '13px', color: '#94A3B8' }}
            >
              アクティビティデータがありません
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
