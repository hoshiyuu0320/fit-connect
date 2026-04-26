'use client'

import { Users, Activity, Target } from 'lucide-react'
import { OverviewKPIData } from '@/types/report'

interface OverviewKPIProps {
  data: OverviewKPIData
  loading?: boolean
}

// 上矢印SVG
function ArrowUp() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M5 1L9 6H1L5 1Z" fill="currentColor" />
    </svg>
  )
}

// 下矢印SVG
function ArrowDown() {
  return (
    <svg width="10" height="10" viewBox="0 0 10 10" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M5 9L1 4H9L5 9Z" fill="currentColor" />
    </svg>
  )
}

function ChangeIndicator({ value, suffix = '' }: { value: number; suffix?: string }) {
  if (value === 0) {
    return (
      <span className="inline-flex items-center gap-0.5 font-semibold" style={{ fontSize: '11px', color: '#94A3B8' }}>
        ±0{suffix}
      </span>
    )
  }
  if (value > 0) {
    return (
      <span className="inline-flex items-center gap-0.5 font-semibold" style={{ fontSize: '11px', color: '#16A34A' }}>
        <ArrowUp />
        +{value}{suffix}
      </span>
    )
  }
  return (
    <span className="inline-flex items-center gap-0.5 font-semibold" style={{ fontSize: '11px', color: '#DC2626' }}>
      <ArrowDown />
      {value}{suffix}
    </span>
  )
}

function KPISkeleton() {
  return (
    <div
      className="grid grid-cols-4 overflow-hidden rounded-md border"
      style={{ borderColor: '#E2E8F0' }}
    >
      {Array.from({ length: 4 }).map((_, i) => (
        <div
          key={i}
          className="bg-white p-4"
          style={{ borderRight: i < 3 ? '1px solid #E2E8F0' : 'none' }}
        >
          <div
            className="h-3 w-16 rounded animate-pulse mb-3"
            style={{ backgroundColor: '#F8FAFC' }}
          />
          <div
            className="h-7 w-20 rounded animate-pulse mb-2"
            style={{ backgroundColor: '#F8FAFC' }}
          />
          <div
            className="h-3 w-12 rounded animate-pulse"
            style={{ backgroundColor: '#F8FAFC' }}
          />
        </div>
      ))}
    </div>
  )
}

interface KPIItemConfig {
  label: string
  value: string
  unit: string
  change: number
  changeSuffix: string
  icon: React.ReactNode
}

export function OverviewKPI({ data, loading }: OverviewKPIProps) {
  if (loading) {
    return <KPISkeleton />
  }

  const items: KPIItemConfig[] = [
    {
      label: '担当顧客',
      value: String(data.totalClients),
      unit: '名',
      change: data.changes.totalClients,
      changeSuffix: '名',
      icon: <Users size={14} style={{ color: '#14B8A6' }} />,
    },
    {
      label: 'アクティブ率',
      value: String(data.activeRate),
      unit: '%',
      change: data.changes.activeRate,
      changeSuffix: '%',
      icon: <Activity size={14} style={{ color: '#14B8A6' }} />,
    },
    {
      label: '平均記録率',
      value: String(data.avgRecordRate),
      unit: '%',
      change: data.changes.avgRecordRate,
      changeSuffix: '%',
      icon: (
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#14B8A6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
        </svg>
      ),
    },
    {
      label: '目標達成者',
      value: String(data.goalAchievers),
      unit: `/${data.totalClientsGoal}名`,
      change: data.changes.goalAchievers,
      changeSuffix: '名',
      icon: <Target size={14} style={{ color: '#14B8A6' }} />,
    },
  ]

  return (
    <div
      className="grid grid-cols-4 overflow-hidden rounded-md border"
      style={{ borderColor: '#E2E8F0' }}
    >
      {items.map((item, i) => (
        <div
          key={item.label}
          className="bg-white p-4"
          style={{ borderRight: i < items.length - 1 ? '1px solid #E2E8F0' : 'none' }}
        >
          <div className="flex items-center gap-1.5 mb-2">
            {item.icon}
            <span
              className="font-semibold uppercase tracking-wider"
              style={{ fontSize: '10px', color: '#94A3B8' }}
            >
              {item.label}
            </span>
          </div>
          <div className="flex items-baseline gap-1">
            <span
              className="font-extrabold"
              style={{ fontSize: '22px', color: '#0F172A' }}
            >
              {item.value}
            </span>
            <span style={{ fontSize: '11px', color: '#94A3B8' }}>
              {item.unit}
            </span>
          </div>
          <div className="mt-1">
            <ChangeIndicator value={item.change} suffix={item.changeSuffix} />
          </div>
        </div>
      ))}
    </div>
  )
}
