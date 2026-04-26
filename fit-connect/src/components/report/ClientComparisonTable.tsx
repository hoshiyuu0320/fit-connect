'use client'

import { useState } from 'react'
import { ChevronDown } from 'lucide-react'
import { ClientReportRow } from '@/types/report'
import { PURPOSE_OPTIONS, GENDER_OPTIONS } from '@/types/client'

interface ClientComparisonTableProps {
  rows: ClientReportRow[]
  loading?: boolean
  onClientSelect: (clientId: string) => void
}

type SortKey = 'weight' | 'recordRate' | 'score'

const PURPOSE_BADGE_STYLES: Record<string, { bg: string; text: string }> = {
  diet: { bg: '#F0FDFA', text: '#14B8A6' },
  contest: { bg: '#FFF7ED', text: '#EA580C' },
  body_make: { bg: '#FAF5FF', text: '#7C3AED' },
  health_improvement: { bg: '#EFF6FF', text: '#2563EB' },
  mental_improvement: { bg: '#FFFBEB', text: '#F59E0B' },
  performance_improvement: { bg: '#F0FDF4', text: '#16A34A' },
}

const STATUS_CONFIG = {
  good: { label: '順調', bg: '#F0FDF4', text: '#16A34A' },
  warning: { label: '要注意', bg: '#FFFBEB', text: '#F59E0B' },
  danger: { label: '離脱リスク', bg: '#FEF2F2', text: '#DC2626' },
} as const

function getProgressBarColor(score: number): string {
  if (score >= 70) return '#14B8A6'
  if (score >= 40) return '#F59E0B'
  return '#DC2626'
}

function TableSkeleton() {
  return (
    <div
      className="bg-white border rounded-md overflow-hidden"
      style={{ borderColor: '#E2E8F0' }}
    >
      <div className="p-4" style={{ borderBottom: '1px solid #E2E8F0' }}>
        <div className="h-5 w-40 rounded animate-pulse" style={{ backgroundColor: '#F8FAFC' }} />
      </div>
      <div className="p-4 space-y-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="flex items-center gap-4">
            <div className="h-7 w-7 rounded-full animate-pulse" style={{ backgroundColor: '#F8FAFC' }} />
            <div className="h-4 flex-1 rounded animate-pulse" style={{ backgroundColor: '#F8FAFC' }} />
          </div>
        ))}
      </div>
    </div>
  )
}

export function ClientComparisonTable({ rows, loading, onClientSelect }: ClientComparisonTableProps) {
  const [sortKey, setSortKey] = useState<SortKey>('score')

  if (loading) {
    return <TableSkeleton />
  }

  // ソート処理
  const sortedRows = [...rows].sort((a, b) => {
    switch (sortKey) {
      case 'weight':
        return (Math.abs(b.weightChange ?? 0)) - (Math.abs(a.weightChange ?? 0))
      case 'recordRate':
        return ((b.mealRecordRate + b.exerciseRecordRate) / 2) - ((a.mealRecordRate + a.exerciseRecordRate) / 2)
      case 'score':
      default:
        return b.score - a.score
    }
  })

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
          クライアント進捗一覧
        </h3>
        <div className="relative">
          <select
            value={sortKey}
            onChange={(e) => setSortKey(e.target.value as SortKey)}
            className="appearance-none bg-white border rounded-md px-3 py-1.5 pr-7 text-xs outline-none cursor-pointer"
            style={{ borderColor: '#E2E8F0', color: '#475569' }}
          >
            <option value="score">スコア順</option>
            <option value="weight">体重変動順</option>
            <option value="recordRate">記録率順</option>
          </select>
          <ChevronDown
            size={12}
            className="absolute right-2 top-1/2 -translate-y-1/2 pointer-events-none"
            style={{ color: '#94A3B8' }}
          />
        </div>
      </div>

      {/* テーブル */}
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr style={{ backgroundColor: '#F8FAFC' }}>
              {['#', 'クライアント', '目的', '現在体重', '体重変動', '食事記録率', '運動記録率', '総合スコア', 'ステータス'].map(
                (header) => (
                  <th
                    key={header}
                    className="px-3 py-2.5 text-left font-semibold uppercase tracking-wider whitespace-nowrap"
                    style={{ fontSize: '10px', color: '#94A3B8' }}
                  >
                    {header}
                  </th>
                )
              )}
            </tr>
          </thead>
          <tbody>
            {sortedRows.map((row, index) => {
              const purposeStyle = row.purpose ? PURPOSE_BADGE_STYLES[row.purpose] : null
              const purposeLabel = row.purpose
                ? PURPOSE_OPTIONS[row.purpose as keyof typeof PURPOSE_OPTIONS] ?? row.purpose
                : '-'
              const genderLabel = row.gender
                ? GENDER_OPTIONS[row.gender as keyof typeof GENDER_OPTIONS] ?? row.gender
                : ''
              const statusCfg = STATUS_CONFIG[row.status]

              return (
                <tr
                  key={row.client_id}
                  className="cursor-pointer transition-colors"
                  style={{ borderBottom: '1px solid #E2E8F0' }}
                  onClick={() => onClientSelect(row.client_id)}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = '#F0FDFA'
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = ''
                  }}
                >
                  {/* ランク */}
                  <td className="px-3 py-2.5">
                    <span
                      className="font-semibold"
                      style={{ fontSize: '11px', color: '#94A3B8' }}
                    >
                      {index + 1}
                    </span>
                  </td>

                  {/* クライアント */}
                  <td className="px-3 py-2.5">
                    <div className="flex items-center gap-2">
                      <div
                        className="flex items-center justify-center rounded-full font-semibold text-white flex-shrink-0"
                        style={{
                          width: '28px',
                          height: '28px',
                          fontSize: '11px',
                          backgroundColor: index < 3 ? '#14B8A6' : '#64748B',
                        }}
                      >
                        {row.name.charAt(0)}
                      </div>
                      <div>
                        <div
                          className="font-semibold text-xs whitespace-nowrap"
                          style={{ color: '#0F172A' }}
                        >
                          {row.name}
                        </div>
                        <div style={{ fontSize: '10px', color: '#94A3B8' }}>
                          {row.age !== null ? `${row.age}歳` : ''}
                          {genderLabel ? ` ${genderLabel}` : ''}
                        </div>
                      </div>
                    </div>
                  </td>

                  {/* 目的バッジ */}
                  <td className="px-3 py-2.5">
                    {purposeStyle ? (
                      <span
                        className="inline-block px-2 py-0.5 rounded-md font-medium whitespace-nowrap"
                        style={{
                          fontSize: '10px',
                          backgroundColor: purposeStyle.bg,
                          color: purposeStyle.text,
                        }}
                      >
                        {purposeLabel}
                      </span>
                    ) : (
                      <span style={{ fontSize: '11px', color: '#94A3B8' }}>-</span>
                    )}
                  </td>

                  {/* 現在体重 */}
                  <td className="px-3 py-2.5">
                    <span className="font-semibold text-xs" style={{ color: '#0F172A' }}>
                      {row.latestWeight !== null ? `${row.latestWeight.toFixed(1)} kg` : '-'}
                    </span>
                  </td>

                  {/* 体重変動 */}
                  <td className="px-3 py-2.5">
                    {row.weightChange !== null ? (
                      <span
                        className="font-semibold text-xs"
                        style={{
                          color:
                            row.weightChange < 0
                              ? '#16A34A'
                              : row.weightChange > 0
                              ? '#DC2626'
                              : '#94A3B8',
                        }}
                      >
                        {row.weightChange < 0
                          ? `▼ ${Math.abs(row.weightChange).toFixed(1)} kg`
                          : row.weightChange > 0
                          ? `▲ +${row.weightChange.toFixed(1)} kg`
                          : `→ 0.0 kg`}
                      </span>
                    ) : (
                      <span style={{ fontSize: '11px', color: '#94A3B8' }}>-</span>
                    )}
                  </td>

                  {/* 食事記録率 */}
                  <td className="px-3 py-2.5">
                    <div className="flex items-center gap-2">
                      <div
                        className="w-16 rounded-sm overflow-hidden border"
                        style={{
                          height: '6px',
                          backgroundColor: '#F8FAFC',
                          borderColor: '#E2E8F0',
                        }}
                      >
                        <div
                          className="h-full rounded-sm"
                          style={{
                            width: `${Math.min(row.mealRecordRate, 100)}%`,
                            backgroundColor: getProgressBarColor(row.mealRecordRate),
                          }}
                        />
                      </div>
                      <span className="font-semibold text-xs" style={{ color: '#0F172A' }}>
                        {row.mealRecordRate}%
                      </span>
                    </div>
                  </td>

                  {/* 運動記録率 */}
                  <td className="px-3 py-2.5">
                    <div className="flex items-center gap-2">
                      <div
                        className="w-16 rounded-sm overflow-hidden border"
                        style={{
                          height: '6px',
                          backgroundColor: '#F8FAFC',
                          borderColor: '#E2E8F0',
                        }}
                      >
                        <div
                          className="h-full rounded-sm"
                          style={{
                            width: `${Math.min(row.exerciseRecordRate, 100)}%`,
                            backgroundColor: getProgressBarColor(row.exerciseRecordRate),
                          }}
                        />
                      </div>
                      <span className="font-semibold text-xs" style={{ color: '#0F172A' }}>
                        {row.exerciseRecordRate}%
                      </span>
                    </div>
                  </td>

                  {/* 総合スコア */}
                  <td className="px-3 py-2.5">
                    <div className="flex items-center gap-2">
                      <div
                        className="w-16 rounded-sm overflow-hidden border"
                        style={{
                          height: '6px',
                          backgroundColor: '#F8FAFC',
                          borderColor: '#E2E8F0',
                        }}
                      >
                        <div
                          className="h-full rounded-sm"
                          style={{
                            width: `${Math.min(row.score, 100)}%`,
                            backgroundColor: getProgressBarColor(row.score),
                          }}
                        />
                      </div>
                      <span className="font-extrabold text-xs" style={{ color: '#0F172A' }}>
                        {row.score}
                      </span>
                    </div>
                  </td>

                  {/* ステータスバッジ */}
                  <td className="px-3 py-2.5">
                    <span
                      className="inline-block px-2 py-0.5 rounded-md font-medium whitespace-nowrap"
                      style={{
                        fontSize: '10px',
                        backgroundColor: statusCfg.bg,
                        color: statusCfg.text,
                      }}
                    >
                      {statusCfg.label}
                    </span>
                  </td>
                </tr>
              )
            })}

            {sortedRows.length === 0 && (
              <tr>
                <td
                  colSpan={9}
                  className="text-center py-8"
                  style={{ fontSize: '13px', color: '#94A3B8' }}
                >
                  クライアントデータがありません
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
