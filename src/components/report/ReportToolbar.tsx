'use client'

import { Download, FileText } from 'lucide-react'
import { ReportMode, PeriodPreset, DateRange } from '@/types/report'
import { Client } from '@/types/client'

interface ReportToolbarProps {
  mode: ReportMode
  onModeChange: (mode: ReportMode) => void
  periodPreset: PeriodPreset
  onPeriodPresetChange: (preset: PeriodPreset) => void
  dateRange: DateRange
  onDateRangeChange: (range: DateRange) => void
  // 個別分析モード用
  clients: Client[]
  selectedClientId: string | null
  onClientSelect: (clientId: string) => void
  // エクスポート
  onExportCSV: () => void
  onExportPDF: () => void
}

const PERIOD_PRESETS: { value: PeriodPreset; label: string }[] = [
  { value: '1W', label: '1W' },
  { value: '1M', label: '1M' },
  { value: '3M', label: '3M' },
  { value: '6M', label: '6M' },
  { value: '1Y', label: '1Y' },
]

export function ReportToolbar({
  mode,
  onModeChange,
  periodPreset,
  onPeriodPresetChange,
  dateRange,
  onDateRangeChange,
  clients,
  selectedClientId,
  onClientSelect,
  onExportCSV,
  onExportPDF,
}: ReportToolbarProps) {
  return (
    <div className="bg-white border-b" style={{ borderColor: '#E2E8F0' }}>
      <div className="px-6 pt-4 pb-3">
        {/* パンくず */}
        <nav className="mb-3">
          <ol className="flex items-center gap-1.5" style={{ fontSize: '12px' }}>
            <li style={{ color: '#94A3B8' }}>ホーム</li>
            <li style={{ color: '#94A3B8' }}>/</li>
            <li className="font-semibold" style={{ color: '#0F172A' }}>
              レポート
            </li>
          </ol>
        </nav>

        {/* ツールバー */}
        <div className="flex items-center gap-3 flex-wrap">
          {/* ページタイトル */}
          <h1
            className="text-lg font-extrabold mr-auto"
            style={{ color: '#0F172A' }}
          >
            レポート
          </h1>

          {/* モード切替トグル */}
          <div
            className="flex items-center p-0.5 rounded-md border"
            style={{ backgroundColor: '#F8FAFC', borderColor: '#E2E8F0' }}
          >
            <button
              onClick={() => onModeChange('overview')}
              className="px-3 py-1.5 text-xs font-medium rounded transition-colors"
              style={
                mode === 'overview'
                  ? {
                      backgroundColor: '#FFFFFF',
                      color: '#14B8A6',
                      border: '1px solid #E2E8F0',
                    }
                  : {
                      backgroundColor: 'transparent',
                      color: '#94A3B8',
                      border: '1px solid transparent',
                    }
              }
            >
              全体概況
            </button>
            <button
              onClick={() => onModeChange('individual')}
              className="px-3 py-1.5 text-xs font-medium rounded transition-colors"
              style={
                mode === 'individual'
                  ? {
                      backgroundColor: '#FFFFFF',
                      color: '#14B8A6',
                      border: '1px solid #E2E8F0',
                    }
                  : {
                      backgroundColor: 'transparent',
                      color: '#94A3B8',
                      border: '1px solid transparent',
                    }
              }
            >
              個別分析
            </button>
          </div>

          {/* 個別分析モード時: クライアント選択 */}
          {mode === 'individual' && (
            <select
              value={selectedClientId ?? ''}
              onChange={(e) => onClientSelect(e.target.value)}
              className="min-w-[160px] px-3 py-1.5 text-xs rounded-md border bg-white outline-none"
              style={{
                borderColor: '#E2E8F0',
                color: '#0F172A',
              }}
            >
              <option value="">クライアントを選択</option>
              {clients.map((c) => (
                <option key={c.client_id} value={c.client_id}>
                  {c.name}
                </option>
              ))}
            </select>
          )}

          {/* 期間プリセット */}
          <div className="flex items-center gap-1">
            {PERIOD_PRESETS.map((preset) => (
              <button
                key={preset.value}
                onClick={() => onPeriodPresetChange(preset.value)}
                className="px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors"
                style={
                  periodPreset === preset.value
                    ? { backgroundColor: '#14B8A6', color: '#FFFFFF' }
                    : { backgroundColor: 'transparent', color: '#94A3B8' }
                }
              >
                {preset.label}
              </button>
            ))}
          </div>

          {/* 日付入力 */}
          <div className="flex items-center gap-1.5">
            <input
              type="date"
              value={dateRange.startDate}
              onChange={(e) =>
                onDateRangeChange({ ...dateRange, startDate: e.target.value })
              }
              className="px-2 py-1.5 text-xs rounded-md border bg-white outline-none"
              style={{
                width: '130px',
                borderColor: '#E2E8F0',
                color: '#0F172A',
              }}
            />
            <span className="text-xs" style={{ color: '#94A3B8' }}>
              〜
            </span>
            <input
              type="date"
              value={dateRange.endDate}
              onChange={(e) =>
                onDateRangeChange({ ...dateRange, endDate: e.target.value })
              }
              className="px-2 py-1.5 text-xs rounded-md border bg-white outline-none"
              style={{
                width: '130px',
                borderColor: '#E2E8F0',
                color: '#0F172A',
              }}
            />
          </div>

          {/* エクスポートボタン（個別分析モードのみ表示） */}
          {mode === 'individual' && (
            <div className="flex items-center gap-1.5">
              <button
                onClick={onExportCSV}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md border transition-colors hover:bg-[#F8FAFC]"
                style={{ borderColor: '#E2E8F0', color: '#475569' }}
              >
                <Download size={14} />
                CSV
              </button>
              <button
                onClick={onExportPDF}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md border transition-colors hover:bg-[#F8FAFC]"
                style={{ borderColor: '#E2E8F0', color: '#475569' }}
              >
                <FileText size={14} />
                PDF
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
