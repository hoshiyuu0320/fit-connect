'use client'

import React, { useCallback, useEffect, useId, useMemo, useReducer, useRef, useState } from 'react'
import { toast } from 'sonner'
import { Info, ListChecks, RotateCw } from 'lucide-react'
import { getOpenAlerts } from '@/lib/supabase/getOpenAlerts'
import { getAlertDetectionStatus } from '@/lib/supabase/getAlertDetectionStatus'
import { updateAlertStatus } from '@/lib/alerts/updateAlertStatus'
import {
  detectionWarning,
  evaluateDetectionState,
  formatDetectionSummary,
  formatExclusionSummary,
  type DetectionState,
} from '@/lib/alerts/detectionStatus'
import {
  createTriageListState,
  selectTriageListView,
  triageListReducer,
  TRIAGE_INITIAL_LIMIT,
} from '@/lib/triage/triageListState'
import { createAlertActionRunner } from '@/lib/triage/alertActionRunner'
import {
  acknowledgedToastDescription,
  triageCountAnnouncement,
  triageEmptyMessage,
} from '@/lib/triage/triageLabels'
import { useTriageBadgeStore } from '@/store/triageBadgeStore'
import { TriageList, triageToggleId } from './TriageList'
import { TRIAGE_FOCUS_RING, TRIAGE_SECONDARY_BUTTON } from './TriageRow'
import type { TriageReason, TriageRowModel } from '@/lib/triage/buildTriageRows'
import type { AlertDetectionStatus } from '@/types/alert'

/** トースト「対応済みにしました」（「元に戻す」付き）を出しておく時間 */
const ACKNOWLEDGED_TOAST_MS = 5000

const MEDICAL_NOTE = '健康データからの自動判定です。医療的な判断ではありません。'

type LoadPhase = 'loading' | 'error' | 'ready'

/** 検知状態（RPC get_alert_detection_status） */
type DetectionInfo =
  | { kind: 'loaded'; status: AlertDetectionStatus; state: DetectionState }
  /** 0行（呼び出したのがトレーナーでない）か、まだ取得していない */
  | { kind: 'none' }
  | { kind: 'failed' }

function TriageSkeleton() {
  return (
    <div role="status">
      <span className="sr-only">今日の対応を読み込んでいます</span>
      {/* 読み込み後の行と同じくらいの高さを確保して、表示のガタつきを抑える */}
      <ul aria-hidden="true" className="divide-y divide-[#E2E8F0]">
        {[0, 1, 2].map((i) => (
          <li key={i} className="flex items-center gap-3 px-4 py-4 sm:px-6">
            <div className="h-10 w-10 flex-shrink-0 rounded-full bg-gray-100 motion-safe:animate-pulse" />
            <div className="min-w-0 flex-1 space-y-2">
              <div className="h-4 w-32 max-w-full rounded bg-gray-100 motion-safe:animate-pulse" />
              <div className="h-5 w-48 max-w-full rounded bg-gray-100 motion-safe:animate-pulse" />
            </div>
            <div className="hidden h-9 w-24 rounded-md bg-gray-100 motion-safe:animate-pulse sm:block" />
          </li>
        ))}
      </ul>
    </div>
  )
}

type RetryButtonProps = {
  retrying: boolean
  onRetry: () => void
  className?: string
}

function RetryButton({ retrying, onRetry, className = '' }: RetryButtonProps) {
  return (
    <button
      type="button"
      onClick={onRetry}
      disabled={retrying}
      className={`${TRIAGE_SECONDARY_BUTTON} ${className}`}
    >
      <RotateCw
        aria-hidden="true"
        className={`h-4 w-4 ${retrying ? 'motion-safe:animate-spin' : ''}`}
      />
      {retrying ? '再読み込み中…' : '再読み込み'}
    </button>
  )
}

/**
 * ダッシュボード上部の「今日の対応」。
 *
 * - アラートと検知状態を自分で取る（Promise.allSettled）。ページの Promise.all に入れないので、
 *   migration 未適用や RPC の失敗でダッシュボード全体が空にならない
 * - 取り直すのは、表示時・タブに戻ったとき（visibilitychange）・「対応済み」「元に戻す」の後
 * - 一覧の状態遷移は triageListState の reducer、API の順序と成否は alertActionRunner に任せる
 * - 操作の後はサイドバーのバッジ（triageBadgeStore）も数え直す
 */
export function TriageSection() {
  const idPrefix = useId()
  const headingId = `${idPrefix}-heading`
  const listId = `${idPrefix}-list`

  const [phase, setPhase] = useState<LoadPhase>('loading')
  const [retrying, setRetrying] = useState(false)
  const [detection, setDetection] = useState<DetectionInfo>({ kind: 'none' })
  const [listState, dispatch] = useReducer(triageListReducer, [], createTriageListState)

  // 取得が重なったときは、後から始めた分だけを反映する（古い応答で新しい状態を戻さない）
  const latestLoadIdRef = useRef(0)

  const load = useCallback(async () => {
    const loadId = ++latestLoadIdRef.current
    const [alertsResult, statusResult] = await Promise.allSettled([
      getOpenAlerts(),
      getAlertDetectionStatus(),
    ])
    if (loadId !== latestLoadIdRef.current) return

    if (statusResult.status === 'fulfilled') {
      const status = statusResult.value
      setDetection(
        status === null
          ? { kind: 'none' }
          : { kind: 'loaded', status, state: evaluateDetectionState(status, new Date()) }
      )
    } else {
      // 表示中の検知状態があれば残す（取り直しの一時的な失敗で警告や人数を消さない）
      setDetection((prev) => (prev.kind === 'loaded' ? prev : { kind: 'failed' }))
    }

    if (alertsResult.status === 'fulfilled') {
      dispatch({ type: 'loaded', alerts: alertsResult.value })
      setPhase('ready')
    } else {
      // 表示中の一覧があれば残す（タブ復帰・操作後の取り直しの一時的な失敗で一覧を消さない）
      setPhase((prev) => (prev === 'ready' ? prev : 'error'))
    }
  }, [])

  // 表示時と、タブに戻ったときに取り直す
  useEffect(() => {
    void load()
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') void load()
    }
    document.addEventListener('visibilitychange', handleVisibilityChange)
    return () => document.removeEventListener('visibilitychange', handleVisibilityChange)
  }, [load])

  const handleRetry = useCallback(async () => {
    setRetrying(true)
    try {
      // 取得失敗から戻ったときは、サイドバーのバッジも一緒に数え直す（見出しの人数と揃える）
      void useTriageBadgeStore.getState().refresh()
      await load()
    } finally {
      setRetrying(false)
    }
  }, [load])

  // 「対応済みにしました」のトースト（acknowledge が失敗したら閉じる）
  const acknowledgedToastIdsRef = useRef(new Map<string, string | number>())

  // runner は API の順序を保つための状態を持つので、表示の間は1つだけ作る
  const [runner] = useState(() =>
    createAlertActionRunner({
      dispatch,
      updateStatus: updateAlertStatus,
      onAcknowledgeFailed: (alertId) => {
        const toastId = acknowledgedToastIdsRef.current.get(alertId)
        if (toastId !== undefined) toast.dismiss(toastId)
        toast.error('対応済みにできませんでした。もう一度お試しください')
      },
      onUndoFailed: (_alertId, reason) => {
        toast.error(
          reason === 'not_applied'
            ? 'すでに解消された項目のため、元に戻せませんでした'
            : '元に戻せませんでした。対応済みのままです'
        )
      },
      onSettled: (alertId) => {
        acknowledgedToastIdsRef.current.delete(alertId)
        void load()
        void useTriageBadgeStore.getState().refresh()
      },
    })
  )

  const view = useMemo(() => selectTriageListView(listState), [listState])
  const busyAlertIds = useMemo(
    () => new Set(Object.keys(listState.restoring)),
    [listState.restoring]
  )

  // 対応済みにした後のフォーカスの行き先（押したボタンが消えるため）。
  // 行き先の行が並び替えで上位5件から外れて見つからないときは、見出しに落とす（body に落とさない）
  const pendingFocusIdRef = useRef<string | null>(null)
  useEffect(() => {
    const id = pendingFocusIdRef.current
    if (id === null) return
    pendingFocusIdRef.current = null
    const target = document.getElementById(id) ?? document.getElementById(headingId)
    target?.focus({ preventScroll: true })
  })

  // 「対応済みにする」をダブルクリックしたときの2回目以降のクリックを捨てる。1回目で行（理由）が消えて
  // 下が詰まり、2回目が別の理由の「対応済みにする」や次の行のリンクに当たるため。
  // 捨てるのは、対応済みにしたクリックに続く detail > 1 のクリックだけ（次の1回目のクリックで解除）
  const swallowFollowUpClicksRef = useRef(false)
  useEffect(() => {
    const handleClickCapture = (event: MouseEvent) => {
      if (event.detail <= 1) {
        swallowFollowUpClicksRef.current = false
        return
      }
      if (swallowFollowUpClicksRef.current) {
        event.preventDefault()
        event.stopPropagation()
      }
    }
    // React より先に止めるため、document の捕捉フェーズで受ける
    document.addEventListener('click', handleClickCapture, true)
    return () => document.removeEventListener('click', handleClickCapture, true)
  }, [])

  const handleAcknowledge = useCallback(
    (row: TriageRowModel, reason: TriageReason) => {
      swallowFollowUpClicksRef.current = true
      // 行が残るならその行の開閉ボタン、行ごと消えるなら隣の行の開閉ボタン、どちらも無ければ見出し
      const index = view.displayedRows.findIndex((r) => r.clientId === row.clientId)
      const neighbor = view.displayedRows[index + 1] ?? view.displayedRows[index - 1]
      pendingFocusIdRef.current =
        row.reasons.length > 1
          ? triageToggleId(idPrefix, row.clientId)
          : neighbor
            ? triageToggleId(idPrefix, neighbor.clientId)
            : headingId

      const toastId = toast('対応済みにしました', {
        description: acknowledgedToastDescription(row.clientName, reason.description.kindLabel),
        duration: ACKNOWLEDGED_TOAST_MS,
        action: {
          label: '元に戻す',
          onClick: () => {
            void runner.undo(reason.alertId)
          },
        },
      })
      acknowledgedToastIdsRef.current.set(reason.alertId, toastId)
      void runner.acknowledge(reason.alertId)
    },
    [view.displayedRows, idPrefix, headingId, runner]
  )

  const handleToggleRow = useCallback((clientId: string) => {
    dispatch({ type: 'toggleExpanded', clientId })
  }, [])

  const handleToggleShowAll = useCallback(() => {
    dispatch({ type: 'toggleShowAll' })
  }, [])

  const detectionState = detection.kind === 'loaded' ? detection.state : null
  const warning = detectionState ? detectionWarning(detectionState) : null
  const summary =
    detection.kind === 'loaded' ? formatDetectionSummary(detection.status, detection.state) : null
  const exclusions = detection.kind === 'loaded' ? formatExclusionSummary(detection.status) : null
  const isEmpty = view.totalCount === 0

  return (
    <section aria-labelledby={headingId} className="bg-white rounded-md border border-[#E2E8F0]">
      {/* ヘッダー（どの状態でも残す） */}
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-[#E2E8F0] px-4 pt-6 pb-4 sm:px-6">
        <div className="flex items-center gap-3">
          <h2
            id={headingId}
            tabIndex={-1}
            className="flex items-center space-x-2 text-lg font-bold text-[#0F172A] focus:outline-none"
          >
            <span className="text-[#94A3B8]" aria-hidden="true">
              <ListChecks className="h-5 w-5" />
            </span>
            <span>今日の対応</span>
          </h2>
          {phase === 'ready' && !isEmpty && (
            <span className="rounded border border-[#CCFBF1] bg-[#F0FDFA] px-2.5 py-1 text-xs font-semibold text-[#0F766E]">
              {view.totalCount}人
            </span>
          )}
        </div>
        <p className="text-xs text-[#475569]">6:00 時点の自動チェック</p>
      </div>

      {phase === 'loading' && <TriageSkeleton />}

      {phase === 'error' && (
        <div className="px-6 py-8 text-center">
          <div role="alert">
            <p className="font-medium text-[#0F172A]">対応リストを読み込めませんでした</p>
            <p className="mt-1 text-sm text-[#475569]">
              通信状況を確かめてから、もう一度お試しください。
            </p>
          </div>
          <RetryButton retrying={retrying} onRetry={handleRetry} className="mt-4" />
        </div>
      )}

      {phase === 'ready' && (
        <>
          {/* 未実行・遅延・停止中（red / amber は重要度だけに使うので、警告は中立色で出す） */}
          {warning && (
            <div className="mx-4 mt-4 flex items-start gap-2 rounded-md border border-[#E2E8F0] bg-[#F8FAFC] px-4 py-3 sm:mx-6">
              <Info aria-hidden="true" className="mt-0.5 h-4 w-4 flex-shrink-0 text-[#475569]" />
              <p className="text-sm font-medium text-[#0F172A]">{warning}</p>
            </div>
          )}

          {isEmpty ? (
            <div className="px-6 py-8 text-center">
              <div
                aria-hidden="true"
                className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-md bg-[#F8FAFC] text-[#94A3B8]"
              >
                <ListChecks className="h-6 w-6" />
              </div>
              <p className="font-medium text-[#475569]">{triageEmptyMessage(detectionState)}</p>
              {summary && <p className="mt-1 text-sm text-[#475569]">{summary}</p>}
            </div>
          ) : (
            <TriageList
              rows={view.displayedRows}
              totalCount={view.totalCount}
              hasMore={view.hasMore}
              showAll={listState.showAll}
              limit={TRIAGE_INITIAL_LIMIT}
              listId={listId}
              idPrefix={idPrefix}
              expandedClientIds={listState.expandedClientIds}
              busyAlertIds={busyAlertIds}
              onToggleRow={handleToggleRow}
              onToggleShowAll={handleToggleShowAll}
              onAcknowledge={handleAcknowledge}
            />
          )}
        </>
      )}

      {/* フッター: 最終チェック・対象外の人数・注記（注記はどの状態でも出す） */}
      <div className="space-y-1 rounded-b-md border-t border-[#E2E8F0] bg-[#F8FAFC] px-4 py-3 sm:px-6">
        {phase === 'ready' && summary && !isEmpty && (
          <p className="text-xs text-[#475569]">{summary}</p>
        )}
        {phase === 'ready' && exclusions && <p className="text-xs text-[#475569]">{exclusions}</p>}
        {phase === 'ready' && detection.kind === 'failed' && (
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <p className="text-xs text-[#475569]">自動チェックの状態を読み込めませんでした</p>
            <button
              type="button"
              onClick={handleRetry}
              disabled={retrying}
              className={`rounded-sm text-xs font-medium text-[#0F766E] underline underline-offset-2 transition-colors duration-150 hover:text-[#0F172A] disabled:cursor-not-allowed disabled:opacity-50 motion-reduce:transition-none ${TRIAGE_FOCUS_RING}`}
            >
              {retrying ? '再読み込み中…' : '再読み込み'}
            </button>
          </div>
        )}
        <p className="text-xs text-[#475569]">{MEDICAL_NOTE}</p>
      </div>

      {/* 一覧の件数の変化を読み上げる（対応済みにした後など） */}
      <p className="sr-only" aria-live="polite">
        {phase === 'ready' ? triageCountAnnouncement(view.totalCount, detectionState) : ''}
      </p>
    </section>
  )
}
