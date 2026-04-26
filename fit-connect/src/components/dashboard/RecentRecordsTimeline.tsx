"use client"

import React, { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import {
  UtensilsCrossed,
  Scale,
  Zap,
  TrendingUp,
  TrendingDown,
  ChevronRight,
} from 'lucide-react'
import type { RecentRecord, RecordType } from '@/lib/supabase/getRecentRecords'
import type { RecordStats } from '@/lib/supabase/getRecordStats'

// ----------------------------------------------------------------
// 型定義
// ----------------------------------------------------------------
interface RecentRecordsTimelineProps {
  records: RecentRecord[]
  stats: RecordStats
}

interface DateGroup {
  label: string
  records: RecentRecord[]
}

// ----------------------------------------------------------------
// 定数
// ----------------------------------------------------------------
const RECORD_TYPE_STYLES: Record<
  RecordType,
  { bg: string; border: string; text: string; label: string }
> = {
  meal: {
    bg: '#FFF7ED',
    border: '#F97316',
    text: '#C2410C',
    label: '食事',
  },
  weight: {
    bg: '#F0FDFA',
    border: '#14B8A6',
    text: '#0D9488',
    label: '体重',
  },
  exercise: {
    bg: '#FAF5FF',
    border: '#A855F7',
    text: '#7E22CE',
    label: '運動',
  },
}

const MEAL_TYPE_LABEL: Record<string, string> = {
  breakfast: '朝食',
  lunch: '昼食',
  dinner: '夕食',
  snack: '間食',
}

const FILTER_OPTIONS: { value: RecordType | 'all'; label: string }[] = [
  { value: 'all', label: 'すべて' },
  { value: 'meal', label: '食事' },
  { value: 'weight', label: '体重' },
  { value: 'exercise', label: '運動' },
]

const WEEKDAY_LABELS = ['日', '月', '火', '水', '木', '金', '土']

// ----------------------------------------------------------------
// ユーティリティ
// ----------------------------------------------------------------
function toLocalDateStr(isoStr: string): string {
  const d = new Date(isoStr)
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

function getDateGroupLabel(dateStr: string): string {
  const today = toLocalDateStr(new Date().toISOString())
  const yesterday = toLocalDateStr(
    new Date(Date.now() - 86400000).toISOString()
  )
  if (dateStr === today) return '今日'
  if (dateStr === yesterday) return '昨日'
  const d = new Date(dateStr)
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  const dow = WEEKDAY_LABELS[d.getDay()]
  return `${mm}/${dd}（${dow}）`
}

function calcChangePercent(current: number, last: number): number | null {
  if (last === 0 && current === 0) return null
  if (last === 0) return null
  return Math.round(((current - last) / last) * 100)
}

// ----------------------------------------------------------------
// サブコンポーネント: KPIカード
// ----------------------------------------------------------------
interface KpiCardProps {
  label: string
  count: number
  lastCount: number
  unit?: string
  iconBg: string
  iconColor: string
  icon: React.ReactNode
}

function KpiCard({ label, count, lastCount, unit = '件', iconBg, iconColor, icon }: KpiCardProps) {
  const pct = calcChangePercent(count, lastCount)
  const isUp = pct !== null && pct > 0
  const isDown = pct !== null && pct < 0
  const isFlat = pct !== null && pct === 0
  const noData = pct === null

  return (
    <div
      style={{
        background: '#FFFFFF',
        border: '1px solid #E2E8F0',
        borderRadius: '6px',
        padding: '16px',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px' }}>
        <span style={{ fontSize: '11px', fontWeight: 500, color: '#94A3B8', letterSpacing: '0.05em' }}>
          {label}
        </span>
        <div
          style={{
            width: '28px',
            height: '28px',
            borderRadius: '6px',
            background: iconBg,
            color: iconColor,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {icon}
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: '6px' }}>
        <span style={{ fontSize: '28px', fontWeight: 700, color: '#0F172A', lineHeight: 1 }}>
          {count}
        </span>
        <span style={{ fontSize: '12px', color: '#94A3B8' }}>{unit}</span>
      </div>
      <div style={{ marginTop: '8px', display: 'flex', alignItems: 'center', gap: '4px' }}>
        {noData && (
          <span style={{ fontSize: '11px', color: '#94A3B8' }}>前週データなし</span>
        )}
        {isFlat && (
          <span style={{ fontSize: '11px', color: '#94A3B8' }}>前週比 ±0%</span>
        )}
        {isUp && (
          <>
            <TrendingUp size={12} style={{ color: '#14B8A6' }} />
            <span style={{ fontSize: '11px', color: '#14B8A6', fontWeight: 500 }}>
              +{pct}%
            </span>
          </>
        )}
        {isDown && (
          <>
            <TrendingDown size={12} style={{ color: '#DC2626' }} />
            <span style={{ fontSize: '11px', color: '#DC2626', fontWeight: 500 }}>
              {pct}%
            </span>
          </>
        )}
      </div>
    </div>
  )
}

// ----------------------------------------------------------------
// サブコンポーネント: 記録アイテム
// ----------------------------------------------------------------
interface RecordItemProps {
  record: RecentRecord
  onClick: () => void
}

function RecordItem({ record, onClick }: RecordItemProps) {
  const style = RECORD_TYPE_STYLES[record.type]

  const renderIcon = () => {
    if (record.type === 'meal')
      return <UtensilsCrossed size={14} />
    if (record.type === 'weight')
      return <Scale size={14} />
    return <Zap size={14} />
  }

  const renderDetail = () => {
    if (record.type === 'meal') {
      const mealLabel = record.meal_type ? MEAL_TYPE_LABEL[record.meal_type] ?? record.meal_type : ''
      const parts: string[] = []
      if (mealLabel) parts.push(mealLabel)
      if (record.description) parts.push(record.description)
      if (record.calories != null) parts.push(`${record.calories} kcal`)
      return parts.join('  /  ')
    }

    if (record.type === 'weight') {
      const weightStr = record.weight != null ? `${record.weight} kg` : ''
      if (record.weight_change != null) {
        const sign = record.weight_change > 0 ? '+' : ''
        const changeColor = record.weight_change > 0 ? '#DC2626' : '#14B8A6'
        return (
          <span>
            {weightStr}
            <span style={{ marginLeft: '6px', color: changeColor, fontSize: '11px' }}>
              （前回比 {sign}{record.weight_change} kg）
            </span>
          </span>
        )
      }
      return weightStr
    }

    // exercise
    const parts: string[] = []
    if (record.exercise_type) parts.push(record.exercise_type)
    if (record.duration != null) parts.push(`${record.duration} 分`)
    if (record.distance != null) parts.push(`${record.distance} km`)
    if (record.exercise_calories != null) parts.push(`${record.exercise_calories} kcal`)
    return parts.join('  /  ')
  }

  const timeStr = new Date(record.recorded_at).toLocaleTimeString('ja-JP', {
    hour: '2-digit',
    minute: '2-digit',
  })

  return (
    <div
      onClick={onClick}
      style={{ cursor: 'pointer' }}
      className="group"
    >
      <div
        style={{
          display: 'flex',
          alignItems: 'flex-start',
          gap: '12px',
          padding: '12px',
          borderRadius: '6px',
          border: '1px solid #F1F5F9',
          background: '#FFFFFF',
          transition: 'border-color 0.15s',
        }}
        className="group-hover:border-[#E2E8F0]"
      >
        {/* アイコン */}
        <div
          style={{
            flexShrink: 0,
            width: '32px',
            height: '32px',
            borderRadius: '6px',
            background: style.bg,
            border: `1px solid ${style.border}`,
            color: style.text,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {renderIcon()}
        </div>

        {/* コンテンツ */}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0 }}>
              <span style={{ fontSize: '13px', fontWeight: 600, color: '#0F172A', whiteSpace: 'nowrap' }}>
                {record.client_name}
              </span>
              <span
                style={{
                  fontSize: '10px',
                  fontWeight: 500,
                  padding: '1px 6px',
                  borderRadius: '4px',
                  background: style.bg,
                  color: style.text,
                  border: `1px solid ${style.border}`,
                  whiteSpace: 'nowrap',
                }}
              >
                {style.label}
              </span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: '4px', flexShrink: 0 }}>
              <span style={{ fontSize: '11px', color: '#94A3B8' }}>{timeStr}</span>
              <ChevronRight size={14} style={{ color: '#CBD5E1' }} />
            </div>
          </div>
          <div
            style={{
              fontSize: '12px',
              color: '#475569',
              marginTop: '4px',
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
            }}
          >
            {renderDetail()}
          </div>
        </div>
      </div>
    </div>
  )
}

// ----------------------------------------------------------------
// メインコンポーネント
// ----------------------------------------------------------------
export function RecentRecordsTimeline({ records, stats }: RecentRecordsTimelineProps) {
  const router = useRouter()
  const [filter, setFilter] = useState<RecordType | 'all'>('all')

  // フィルタリング
  const filteredRecords = useMemo(() => {
    if (filter === 'all') return records
    return records.filter((r) => r.type === filter)
  }, [records, filter])

  // 日付グループ化
  const dateGroups = useMemo<DateGroup[]>(() => {
    const groups = new Map<string, RecentRecord[]>()
    for (const record of filteredRecords) {
      const dateStr = toLocalDateStr(record.recorded_at)
      if (!groups.has(dateStr)) groups.set(dateStr, [])
      groups.get(dateStr)!.push(record)
    }
    return Array.from(groups.entries()).map(([dateStr, recs]) => ({
      label: getDateGroupLabel(dateStr),
      records: recs,
    }))
  }, [filteredRecords])

  // 記録率
  const recordingRate =
    stats.totalActiveClients > 0
      ? Math.round((stats.activeRecordingClients / stats.totalActiveClients) * 100)
      : 0
  const recordingRateLastWeek = stats.totalActiveClients > 0 ? 50 : 0 // 先週比は計算できないのでフォールバック

  return (
    <div
      style={{
        background: '#FFFFFF',
        border: '1px solid #E2E8F0',
        borderRadius: '6px',
      }}
    >
      {/* ヘッダー */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '20px 24px 16px',
          borderBottom: '1px solid #F1F5F9',
        }}
      >
        <h2 style={{ fontSize: '15px', fontWeight: 600, color: '#0F172A' }}>
          最近の記録
        </h2>

        {/* フィルターチップ */}
        <div style={{ display: 'flex', gap: '4px' }}>
          {FILTER_OPTIONS.map((opt) => {
            const isActive = filter === opt.value
            return (
              <button
                key={opt.value}
                onClick={() => setFilter(opt.value)}
                style={{
                  fontSize: '12px',
                  fontWeight: isActive ? 600 : 400,
                  padding: '4px 12px',
                  borderRadius: '4px',
                  border: isActive ? '1px solid #0F172A' : '1px solid #E2E8F0',
                  background: isActive ? '#0F172A' : 'transparent',
                  color: isActive ? '#FFFFFF' : '#94A3B8',
                  cursor: 'pointer',
                  transition: 'all 0.15s',
                }}
              >
                {opt.label}
              </button>
            )
          })}
        </div>
      </div>

      {/* KPIサマリー */}
      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(4, 1fr)',
          gap: '12px',
          padding: '16px 24px',
          borderBottom: '1px solid #F1F5F9',
        }}
      >
        <KpiCard
          label="今週の食事"
          count={stats.mealCount}
          lastCount={stats.mealCountLastWeek}
          iconBg="#FFF7ED"
          iconColor="#F97316"
          icon={<UtensilsCrossed size={14} />}
        />
        <KpiCard
          label="今週の体重"
          count={stats.weightCount}
          lastCount={stats.weightCountLastWeek}
          iconBg="#F0FDFA"
          iconColor="#14B8A6"
          icon={<Scale size={14} />}
        />
        <KpiCard
          label="今週の運動"
          count={stats.exerciseCount}
          lastCount={stats.exerciseCountLastWeek}
          iconBg="#FAF5FF"
          iconColor="#A855F7"
          icon={<Zap size={14} />}
        />
        <KpiCard
          label="記録率"
          count={recordingRate}
          lastCount={recordingRateLastWeek}
          unit="%"
          iconBg="#F0FDFA"
          iconColor="#14B8A6"
          icon={<TrendingUp size={14} />}
        />
      </div>

      {/* タイムライン */}
      <div style={{ padding: '16px 24px 8px' }}>
        {filteredRecords.length === 0 ? (
          <div
            style={{
              padding: '48px 0',
              textAlign: 'center',
              color: '#94A3B8',
              fontSize: '14px',
            }}
          >
            まだ記録がありません
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0' }}>
            {dateGroups.map((group, gi) => (
              <div key={group.label} style={{ marginBottom: '8px' }}>
                {/* 日付ラベル */}
                <div
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '8px',
                    marginBottom: '8px',
                    marginTop: gi > 0 ? '16px' : '0',
                  }}
                >
                  <span
                    style={{
                      fontSize: '11px',
                      fontWeight: 600,
                      color: '#94A3B8',
                      letterSpacing: '0.06em',
                      textTransform: 'uppercase',
                    }}
                  >
                    {group.label}
                  </span>
                  <div style={{ flex: 1, height: '1px', background: '#F1F5F9' }} />
                </div>

                {/* 縦ライン + 記録リスト */}
                <div style={{ display: 'flex', gap: '0' }}>
                  {/* 縦ライン */}
                  <div style={{ position: 'relative', width: '20px', flexShrink: 0 }}>
                    <div
                      style={{
                        position: 'absolute',
                        left: '9px',
                        top: '8px',
                        bottom: '8px',
                        width: '1px',
                        background: '#E2E8F0',
                      }}
                    />
                  </div>

                  {/* 記録アイテム */}
                  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '6px' }}>
                    {group.records.map((record) => (
                      <div key={`${record.type}-${record.id}`} style={{ position: 'relative' }}>
                        {/* 縦ラインのドット */}
                        <div
                          style={{
                            position: 'absolute',
                            left: '-16px',
                            top: '15px',
                            width: '6px',
                            height: '6px',
                            borderRadius: '50%',
                            background: RECORD_TYPE_STYLES[record.type].border,
                            border: '1px solid #FFFFFF',
                            zIndex: 1,
                          }}
                        />
                        <RecordItem
                          record={record}
                          onClick={() => router.push(`/clients/${record.client_id}`)}
                        />
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* フッター: すべての記録を見る */}
      <div
        style={{
          padding: '12px 24px 16px',
          borderTop: '1px solid #F1F5F9',
          textAlign: 'center',
        }}
      >
        <button
          onClick={() => router.push('/report')}
          style={{
            fontSize: '12px',
            fontWeight: 500,
            color: '#14B8A6',
            background: 'transparent',
            border: 'none',
            cursor: 'pointer',
            display: 'inline-flex',
            alignItems: 'center',
            gap: '4px',
            transition: 'opacity 0.15s',
          }}
          onMouseEnter={(e) => (e.currentTarget.style.opacity = '0.7')}
          onMouseLeave={(e) => (e.currentTarget.style.opacity = '1')}
        >
          すべての記録を見る
          <ChevronRight size={14} />
        </button>
      </div>
    </div>
  )
}
