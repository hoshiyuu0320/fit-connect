"use client"

import { useCallback, useEffect, useState } from 'react'
import { DndContext, DragOverlay, closestCenter, type DragEndEvent, type DragStartEvent } from '@dnd-kit/core'
import { startOfWeek, addDays, format, addWeeks, subWeeks } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { ClientSelector } from '@/components/workout/ClientSelector'
import { TemplatePanel } from '@/components/workout/TemplatePanel'
import { WeeklyCalendar } from '@/components/workout/WeeklyCalendar'
import TicketSelectModal from '@/components/workout/TicketSelectModal'
import type { WorkoutAssignment, WorkoutPlan } from '@/types/workout'

export default function WorkoutPlanPage() {
  const [trainerId, setTrainerId] = useState('')
  const [selectedClientId, setSelectedClientId] = useState<string | null>(null)
  const [templates, setTemplates] = useState<WorkoutPlan[]>([])
  const [assignments, setAssignments] = useState<WorkoutAssignment[]>([])
  const [currentWeekStart, setCurrentWeekStart] = useState(
    startOfWeek(new Date(), { weekStartsOn: 1 })
  )
  const [loading, setLoading] = useState(true)
  const [draggedTemplate, setDraggedTemplate] = useState<WorkoutPlan | null>(null)
  const [pendingDrop, setPendingDrop] = useState<{ planId: string; date: string } | null>(null)
  const [isTicketModalOpen, setIsTicketModalOpen] = useState(false)

  // トレーナーID取得
  useEffect(() => {
    const fetchUser = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (user) {
        setTrainerId(user.id)
      }
      setLoading(false)
    }
    fetchUser()
  }, [])

  // テンプレート取得
  const fetchTemplates = useCallback(async () => {
    if (!trainerId) return
    try {
      const res = await fetch(`/api/workout-plans?trainerId=${trainerId}`)
      if (res.ok) {
        const json = await res.json()
        setTemplates(json.data || [])
      }
    } catch (error) {
      console.error('テンプレート取得エラー:', error)
    }
  }, [trainerId])

  // アサインメント取得
  const fetchAssignments = useCallback(async () => {
    if (!trainerId || !selectedClientId) {
      setAssignments([])
      return
    }
    try {
      const weekStart = format(currentWeekStart, 'yyyy-MM-dd')
      const weekEnd = format(addDays(currentWeekStart, 6), 'yyyy-MM-dd')
      const res = await fetch(
        `/api/workout-assignments?trainerId=${trainerId}&clientId=${selectedClientId}&weekStart=${weekStart}&weekEnd=${weekEnd}`
      )
      if (res.ok) {
        const json = await res.json()
        setAssignments(json.data || [])
      }
    } catch (error) {
      console.error('アサインメント取得エラー:', error)
    }
  }, [trainerId, selectedClientId, currentWeekStart])

  useEffect(() => {
    fetchTemplates()
  }, [fetchTemplates])

  useEffect(() => {
    fetchAssignments()
  }, [fetchAssignments])

  const handleDragStart = (event: DragStartEvent) => {
    const activeData = event.active.data.current as { type?: string; planId?: string } | undefined
    if (activeData?.type === 'template') {
      const plan = templates.find((t) => t.id === activeData.planId)
      setDraggedTemplate(plan ?? null)
    }
  }

  const handleDragEnd = async (event: DragEndEvent) => {
    setDraggedTemplate(null)
    const { active, over } = event
    if (!over) return

    const activeData = active.data.current as { type: string; planId?: string; assignmentId?: string }
    const overData = over.data.current as { type: string; date?: string }

    // テンプレート -> 日付セル: 新規アサインメント作成
    if (activeData.type === 'template' && overData.type === 'day') {
      if (!selectedClientId) {
        alert('クライアントを選択してください')
        return
      }

      // セッション種別の場合はチケット選択モーダルを表示
      const droppedPlan = templates.find((t) => t.id === activeData.planId)
      if (droppedPlan?.plan_type === 'session') {
        setPendingDrop({ planId: activeData.planId!, date: overData.date! })
        setIsTicketModalOpen(true)
        return
      }

      // 宿題（self_guided）の場合は従来通り即時作成
      try {
        const res = await fetch('/api/workout-assignments', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            trainerId,
            clientId: selectedClientId,
            planId: activeData.planId,
            assignedDate: overData.date,
          }),
        })
        if (res.ok) {
          await fetchAssignments()
        }
      } catch (error) {
        console.error('アサインメント作成エラー:', error)
      }
    }

    // アサインメント -> 別の日付セル: 日付変更
    if (activeData.type === 'assignment' && overData.type === 'day') {
      try {
        const res = await fetch(`/api/workout-assignments/${activeData.assignmentId}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ assignedDate: overData.date }),
        })
        if (res.ok) {
          await fetchAssignments()
        }
      } catch (error) {
        console.error('アサインメント更新エラー:', error)
      }
    }
  }

  const handleTicketConfirm = async (ticketId: string | null, sessionTime: string) => {
    if (!pendingDrop || !selectedClientId) return
    setIsTicketModalOpen(false)
    try {
      const res = await fetch('/api/workout-assignments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerId,
          clientId: selectedClientId,
          planId: pendingDrop.planId,
          assignedDate: pendingDrop.date,
          ticketId,
          sessionTime,
          createSession: true,
        }),
      })
      if (res.ok) {
        await fetchAssignments()
      } else {
        const json = await res.json()
        alert(json.error || 'エラーが発生しました')
      }
    } catch (error) {
      console.error('セッション付きアサインメント作成エラー:', error)
    } finally {
      setPendingDrop(null)
    }
  }

  const handleTicketCancel = () => {
    setIsTicketModalOpen(false)
    setPendingDrop(null)
  }

  const handleDeleteAssignment = async (id: string) => {
    try {
      const res = await fetch(`/api/workout-assignments/${id}`, { method: 'DELETE' })
      if (res.ok) {
        setAssignments((prev) => prev.filter((a) => a.id !== id))
      }
    } catch (error) {
      console.error('アサインメント削除エラー:', error)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent" />
      </div>
    )
  }

  return (
    <DndContext
      collisionDetection={closestCenter}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
    >
      <div className="flex flex-col h-[calc(100vh-48px)] bg-gray-50">
        {/* ヘッダー */}
        <header className="bg-white border-b px-6 py-3 flex items-center justify-between flex-shrink-0">
          <h1 className="text-lg font-bold text-gray-800">ワークアウトプラン</h1>
          <div className="flex items-center gap-3">
            <span className="text-sm text-gray-500">クライアント:</span>
            <ClientSelector
              trainerId={trainerId}
              selectedClientId={selectedClientId}
              onSelect={(id) => setSelectedClientId(id)}
            />
          </div>
        </header>

        {/* メインコンテンツ */}
        <main className="flex flex-1 overflow-hidden">
          <TemplatePanel
            trainerId={trainerId}
            templates={templates}
            onRefetch={fetchTemplates}
          />

          {selectedClientId ? (
            <WeeklyCalendar
              currentWeekStart={currentWeekStart}
              assignments={assignments}
              onPrevWeek={() => setCurrentWeekStart((d) => subWeeks(d, 1))}
              onNextWeek={() => setCurrentWeekStart((d) => addWeeks(d, 1))}
              onThisWeek={() =>
                setCurrentWeekStart(startOfWeek(new Date(), { weekStartsOn: 1 }))
              }
              onDeleteAssignment={handleDeleteAssignment}
            />
          ) : (
            <div className="flex-1 flex items-center justify-center text-gray-400">
              <div className="text-center">
                <p className="text-lg font-medium">クライアントを選択してください</p>
                <p className="text-sm mt-1">
                  上部のセレクターからクライアントを選んでワークアウトプランを管理します
                </p>
              </div>
            </div>
          )}
        </main>
      </div>

      {/* チケット選択モーダル */}
      {selectedClientId && pendingDrop && (
        <TicketSelectModal
          isOpen={isTicketModalOpen}
          clientId={selectedClientId}
          planTitle={templates.find((t) => t.id === pendingDrop.planId)?.title ?? ''}
          assignedDate={pendingDrop.date}
          estimatedMinutes={templates.find((t) => t.id === pendingDrop.planId)?.estimated_minutes ?? null}
          onConfirm={handleTicketConfirm}
          onCancel={handleTicketCancel}
        />
      )}

      {/* ドラッグオーバーレイ */}
      <DragOverlay>
        {draggedTemplate && (
          <div className="p-3 bg-white border-2 border-blue-400 rounded-lg shadow-lg opacity-90">
            <div className="font-bold text-gray-800 text-sm">{draggedTemplate.title}</div>
            <div className="text-xs text-gray-500 mt-1">
              {draggedTemplate.exercise_count ?? 0} 種目
            </div>
          </div>
        )}
      </DragOverlay>
    </DndContext>
  )
}
