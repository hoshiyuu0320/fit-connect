'use client'

import { PERIOD_LABELS, type PeriodFilter } from '@/types/period'

interface PeriodSelectorProps {
  value: PeriodFilter
  onChange: (period: PeriodFilter) => void
}

const PERIODS: PeriodFilter[] = ['week', 'month', 'threeMonths', 'all']

export function PeriodSelector({ value, onChange }: PeriodSelectorProps) {
  return (
    <div className="inline-flex items-center gap-1 rounded-lg bg-slate-100 p-1">
      {PERIODS.map((period) => {
        const isActive = value === period
        return (
          <button
            key={period}
            type="button"
            onClick={() => onChange(period)}
            aria-pressed={isActive}
            className={
              isActive
                ? 'px-3 py-1.5 text-sm font-medium rounded-md bg-slate-900 text-white transition'
                : 'px-3 py-1.5 text-sm text-slate-600 rounded-md hover:bg-white transition'
            }
          >
            {PERIOD_LABELS[period]}
          </button>
        )
      })}
    </div>
  )
}
