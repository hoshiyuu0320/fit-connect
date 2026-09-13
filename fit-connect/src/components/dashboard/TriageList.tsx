import React from 'react'
import { TriageRow, TRIAGE_FOCUS_RING } from './TriageRow'
import { showAllButtonLabel } from '@/lib/triage/triageLabels'
import type { TriageReason, TriageRowModel } from '@/lib/triage/buildTriageRows'

/** 行の開閉ボタンの id */
export function triageToggleId(idPrefix: string, clientId: string): string {
  return `${idPrefix}-toggle-${clientId}`
}

/** 行の詳細の領域の id */
export function triageDetailId(idPrefix: string, clientId: string): string {
  return `${idPrefix}-detail-${clientId}`
}

type TriageListProps = {
  /** いま出す行（「すべて表示」前は上位 limit 件） */
  rows: TriageRowModel[]
  /** 行（顧客）の総数 */
  totalCount: number
  hasMore: boolean
  showAll: boolean
  limit: number
  /** 一覧（ul）の id。「すべて表示」の aria-controls */
  listId: string
  /** 行ごとの id の接頭辞（useId の値） */
  idPrefix: string
  expandedClientIds: readonly string[]
  busyAlertIds: ReadonlySet<string>
  onToggleRow: (clientId: string) => void
  onToggleShowAll: () => void
  onAcknowledge: (row: TriageRowModel, reason: TriageReason) => void
}

/** 「今日の対応」の一覧と「すべて表示（N件）」。表示専用（状態は TriageSection の reducer が持つ） */
export function TriageList({
  rows,
  totalCount,
  hasMore,
  showAll,
  limit,
  listId,
  idPrefix,
  expandedClientIds,
  busyAlertIds,
  onToggleRow,
  onToggleShowAll,
  onAcknowledge,
}: TriageListProps) {
  return (
    <>
      {/* role="list": Tailwind の list-style:none で Safari / VoiceOver がリストと読まなくなるため明示する */}
      <ul id={listId} role="list" aria-label="確認が必要な顧客" className="divide-y divide-[#E2E8F0]">
        {rows.map((row) => (
          <TriageRow
            key={row.clientId}
            row={row}
            expanded={expandedClientIds.includes(row.clientId)}
            toggleId={triageToggleId(idPrefix, row.clientId)}
            detailId={triageDetailId(idPrefix, row.clientId)}
            busyAlertIds={busyAlertIds}
            onToggle={onToggleRow}
            onAcknowledge={onAcknowledge}
          />
        ))}
      </ul>
      {hasMore && (
        <div className="border-t border-[#E2E8F0] px-4 py-3 text-center sm:px-6">
          <button
            type="button"
            aria-expanded={showAll}
            aria-controls={listId}
            onClick={onToggleShowAll}
            className={`rounded-sm px-2 py-1 text-sm font-medium text-[#0F766E] transition-colors duration-150 hover:bg-[#F0FDFA] motion-reduce:transition-none ${TRIAGE_FOCUS_RING}`}
          >
            {showAllButtonLabel(showAll, totalCount, limit)}
          </button>
        </div>
      )}
    </>
  )
}
