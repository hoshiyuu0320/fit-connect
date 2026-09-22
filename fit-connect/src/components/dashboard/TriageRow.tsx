import React from 'react'
import Link from 'next/link'
import { Check, ChevronDown } from 'lucide-react'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import {
  clientMessageHref,
  clientRecordHref,
  formatJstMonthDay,
  severityLabel,
} from '@/lib/alerts/describeAlert'
import {
  acknowledgeButtonLabel,
  clientHonorific,
  detailToggleLabel,
  messageLinkLabel,
  recordLinkLabel,
} from '@/lib/triage/triageLabels'
import type { TriageReason, TriageRowModel } from '@/lib/triage/buildTriageRows'
import type { AlertSeverity } from '@/types/alert'

// 「今日の対応」の操作要素の見た目（TriageList / TriageSection でも使う）
export const TRIAGE_FOCUS_RING =
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6] focus-visible:ring-offset-1'

const BUTTON_BASE = `inline-flex items-center justify-center gap-1.5 rounded-md px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors duration-150 motion-reduce:transition-none disabled:cursor-not-allowed disabled:opacity-50 ${TRIAGE_FOCUS_RING}`

export const TRIAGE_PRIMARY_BUTTON = `${BUTTON_BASE} bg-[#14B8A6] text-white hover:bg-[#0D9488]`

export const TRIAGE_SECONDARY_BUTTON = `${BUTTON_BASE} border border-[#E2E8F0] bg-white text-[#475569] hover:bg-[#F8FAFC] hover:text-[#0F172A]`

// 重要度は色だけでなく「要確認」「注意」の文字でも示す（red / amber は重要度の表示だけに使う）
const severityStyles: Record<AlertSeverity, string> = {
  high: 'border-red-200 bg-red-50 text-red-700',
  medium: 'border-amber-200 bg-amber-50 text-amber-800',
  low: 'border-[#E2E8F0] bg-[#F8FAFC] text-[#475569]',
}

export function SeverityBadge({ severity }: { severity: AlertSeverity }) {
  return (
    <span
      className={`inline-flex items-center rounded border px-2 py-0.5 text-xs font-semibold ${severityStyles[severity]}`}
    >
      {severityLabel(severity)}
    </span>
  )
}

type TriageReasonDetailProps = {
  row: TriageRowModel
  reason: TriageReason
  /** 元に戻している途中（応答待ち）は押せない */
  busy: boolean
  onAcknowledge: (row: TriageRowModel, reason: TriageReason) => void
}

/** 行を開いたときの理由1件（詳細文・検知日・「対応済みにする」） */
function TriageReasonDetail({ row, reason, busy, onAcknowledge }: TriageReasonDetailProps) {
  const detectedOn = formatJstMonthDay(reason.firstDetectedOn)

  return (
    <li className="rounded-md border border-[#E2E8F0] bg-[#F8FAFC] p-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between sm:gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <SeverityBadge severity={reason.severity} />
            <p className="text-sm font-semibold text-[#0F172A]">{reason.description.title}</p>
          </div>
          <p className="mt-2 text-sm leading-6 text-[#475569] [overflow-wrap:anywhere]">
            {reason.description.detail}
          </p>
          {detectedOn && <p className="mt-1 text-xs text-[#475569]">検知日 {detectedOn}</p>}
        </div>
        <button
          type="button"
          onClick={(event) => {
            // ダブルクリックの2回目（detail > 1）では押さない。1回目で理由が消えて下の理由が詰まり、
            // 2回目がその「対応済みにする」に当たるため（キーボードの操作は detail = 0）
            if (event.detail > 1) return
            onAcknowledge(row, reason)
          }}
          disabled={busy}
          aria-label={acknowledgeButtonLabel(row.clientName, reason.description.kindLabel)}
          className={`${TRIAGE_SECONDARY_BUTTON} self-start sm:flex-shrink-0`}
        >
          <Check aria-hidden="true" className="h-4 w-4" />
          対応済みにする
        </button>
      </div>
    </li>
  )
}

type TriageRowProps = {
  row: TriageRowModel
  expanded: boolean
  /** 開閉ボタンの id（対応済みにした後のフォーカスの行き先にも使う） */
  toggleId: string
  /** 詳細の領域の id（開閉ボタンの aria-controls） */
  detailId: string
  /** 応答待ちで押せないアラート（元に戻している途中） */
  busyAlertIds: ReadonlySet<string>
  onToggle: (clientId: string) => void
  onAcknowledge: (row: TriageRowModel, reason: TriageReason) => void
}

/**
 * 「今日の対応」の1行（1顧客）。表示専用。
 * 行全体はリンクにせず、顧客名・「記録を見る」・「メッセージ」・開閉ボタンを横に並べる（操作要素を入れ子にしない）。
 */
export function TriageRow({
  row,
  expanded,
  toggleId,
  detailId,
  busyAlertIds,
  onToggle,
  onAcknowledge,
}: TriageRowProps) {
  const name = clientHonorific(row.clientName)

  return (
    <li className="px-4 py-4 sm:px-6">
      <div className="flex flex-col gap-3 md:flex-row md:items-start md:justify-between md:gap-4">
        {/* 顧客と理由 */}
        <div className="flex min-w-0 flex-1 items-start gap-3">
          {/* 名前は隣に文字で出すので、アバターは読み上げない */}
          <span aria-hidden="true" className="flex-shrink-0">
            <ProfileAvatar
              client={{ name: row.clientName, profile_image_url: row.profileImageUrl }}
              size="sm"
            />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
              <h3 className="min-w-0 text-base font-semibold text-[#0F172A] [overflow-wrap:anywhere]">
                <Link
                  href={`/clients/${encodeURIComponent(row.clientId)}`}
                  className={`rounded-sm transition-colors duration-150 hover:text-[#0D9488] motion-reduce:transition-none ${TRIAGE_FOCUS_RING}`}
                >
                  {name}
                </Link>
              </h3>
              <SeverityBadge severity={row.severity} />
            </div>
            {/* role="list": Tailwind の list-style:none で Safari / VoiceOver がリストと読まなくなるため明示する */}
            <ul role="list" aria-label="検知した理由" className="mt-2 flex flex-wrap gap-2">
              {row.reasons.map((reason) => (
                <li
                  key={reason.alertId}
                  className="rounded border border-[#E2E8F0] bg-[#F8FAFC] px-2 py-0.5 text-xs font-medium text-[#475569]"
                >
                  {reason.description.chip}
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* 操作 */}
        <div className="flex flex-wrap items-center gap-2 md:flex-shrink-0">
          <Link
            href={clientRecordHref(row.clientId, row.recordTab)}
            aria-label={recordLinkLabel(row.clientName)}
            className={TRIAGE_PRIMARY_BUTTON}
          >
            記録を見る
          </Link>
          <Link
            href={clientMessageHref(row.clientId)}
            aria-label={messageLinkLabel(row.clientName)}
            className={TRIAGE_SECONDARY_BUTTON}
          >
            メッセージ
          </Link>
          <button
            type="button"
            id={toggleId}
            aria-expanded={expanded}
            aria-controls={detailId}
            aria-label={detailToggleLabel(row.clientName)}
            onClick={() => onToggle(row.clientId)}
            className={TRIAGE_SECONDARY_BUTTON}
          >
            詳細
            <ChevronDown
              aria-hidden="true"
              className={`h-4 w-4 transition-transform duration-150 motion-reduce:transition-none ${expanded ? 'rotate-180' : ''}`}
            />
          </button>
        </div>
      </div>

      {/* 詳細（閉じている間も aria-controls の先として残す） */}
      <div id={detailId} hidden={!expanded} className="mt-4 md:pl-[52px]">
        <ul role="list" className="space-y-3">
          {row.reasons.map((reason) => (
            <TriageReasonDetail
              key={reason.alertId}
              row={row}
              reason={reason}
              busy={busyAlertIds.has(reason.alertId)}
              onAcknowledge={onAcknowledge}
            />
          ))}
        </ul>
      </div>
    </li>
  )
}
