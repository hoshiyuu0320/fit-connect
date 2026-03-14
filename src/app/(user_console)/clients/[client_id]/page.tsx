'use client'

import { useEffect, useState } from 'react'
import { useParams, useSearchParams } from 'next/navigation'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { getClientDetail } from '@/lib/supabase/getClientDetail'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getExerciseRecords } from '@/lib/supabase/getExerciseRecords'
import { getTickets } from '@/lib/supabase/getTickets'
import { getClientNotes } from '@/lib/supabase/getClientNotes'
import { getClientAssignments } from '@/lib/supabase/getClientAssignments'
import { supabase } from '@/lib/supabase'
import type { ClientDetail, WeightRecord, MealRecord, ExerciseRecord, Ticket, ClientNote } from '@/types/client'
import type { WorkoutAssignment } from '@/types/workout'
import { ClientHeader } from './_components/ClientHeader'
import { SummaryTab } from './_components/SummaryTab'
import { MealTab } from './_components/MealTab'
import { WeightTab } from './_components/WeightTab'
import { ExerciseTab } from './_components/ExerciseTab'
import { NotesTab } from './_components/NotesTab'
import { TicketsTab } from './_components/TicketsTab'
import { SessionTab } from './_components/SessionTab'
import { BarChart3, Scale, UtensilsCrossed, Dumbbell, ClipboardList, Ticket as TicketIcon } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'

const TABS: { value: string; label: string; icon: LucideIcon }[] = [
  { value: 'summary', label: 'サマリー', icon: BarChart3 },
  { value: 'weight', label: '体重', icon: Scale },
  { value: 'meal', label: '食事', icon: UtensilsCrossed },
  { value: 'exercise', label: '運動', icon: Dumbbell },
  { value: 'notes', label: 'カルテ', icon: ClipboardList },
  { value: 'tickets', label: 'チケット', icon: TicketIcon },
]

export default function ClientDetailPage() {
  const params = useParams()
  const searchParams = useSearchParams()
  const clientId = params.client_id as string
  const tabParam = searchParams.get('tab')
  const validTabs = ['summary', 'weight', 'meal', 'exercise', 'notes', 'tickets']
  const initialTab = tabParam && validTabs.includes(tabParam) ? tabParam : 'summary'

  const [activeTab, setActiveTab] = useState(initialTab)
  const [client, setClient] = useState<ClientDetail | null>(null)
  const [weightRecords, setWeightRecords] = useState<WeightRecord[]>([])
  const [mealRecords, setMealRecords] = useState<MealRecord[]>([])
  const [exerciseRecords, setExerciseRecords] = useState<ExerciseRecord[]>([])
  const [tickets, setTickets] = useState<Ticket[]>([])
  const [notes, setNotes] = useState<ClientNote[]>([])
  const [workoutAssignments, setWorkoutAssignments] = useState<WorkoutAssignment[]>([])
  const [trainerId, setTrainerId] = useState<string>('')
  const [loading, setLoading] = useState(true)
  const [mode, setMode] = useState<'info' | 'session'>('info')
  const [prevMode, setPrevMode] = useState<'info' | 'session'>('info')

  useEffect(() => {
    const fetchData = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          setTrainerId(user.id)
        }

        const [clientData, weights, meals, exercises, ticketsData, notesData, assignmentsData] = await Promise.all([
          getClientDetail(clientId),
          getWeightRecords(clientId),
          getMealRecords({ clientId, limit: 100 }),
          getExerciseRecords({ clientId, limit: 100 }),
          getTickets(clientId),
          getClientNotes(clientId),
          getClientAssignments(clientId),
        ])
        setClient(clientData)
        setWeightRecords(weights)
        setMealRecords(meals.data)
        setExerciseRecords(exercises.data)
        setTickets(ticketsData)
        setNotes(notesData)
        setWorkoutAssignments(assignmentsData)
      } catch (error) {
        console.error('データ取得エラー：', error)
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [clientId])

  // セッションモードから情報モードに戻った時にデータを再取得
  useEffect(() => {
    if (prevMode === 'session' && mode === 'info') {
      const refetch = async () => {
        try {
          const [exercises, assignmentsData] = await Promise.all([
            getExerciseRecords({ clientId, limit: 100 }),
            getClientAssignments(clientId),
          ])
          setExerciseRecords(exercises.data)
          setWorkoutAssignments(assignmentsData)
        } catch (error) {
          console.error('データ再取得エラー:', error)
        }
      }
      refetch()
    }
    setPrevMode(mode)
  }, [mode])

  const refetchNotes = async () => {
    try {
      const notesData = await getClientNotes(clientId)
      setNotes(notesData)
    } catch (error) {
      console.error('カルテ再取得エラー:', error)
    }
  }

  const refetchClient = async () => {
    try {
      const clientData = await getClientDetail(clientId)
      setClient(clientData)
    } catch (error) {
      console.error('クライアント再取得エラー:', error)
    }
  }

  if (loading) {
    return (
      <div className="h-[calc(100vh-48px)] flex flex-col bg-[#F8FAFC]">
        {/* Skeleton Header */}
        <div className="border-b border-[#E2E8F0] py-3 px-6">
          <div className="flex items-center gap-2">
            <div className="h-4 w-16 bg-[#E2E8F0] rounded-md animate-pulse" />
            <div className="h-4 w-3 bg-[#E2E8F0] rounded-md animate-pulse" />
            <div className="h-4 w-24 bg-[#E2E8F0] rounded-md animate-pulse" />
          </div>
        </div>
        {/* Skeleton Profile Row */}
        <div className="flex items-center gap-3 px-6 pt-4 pb-2">
          <div className="w-10 h-10 bg-[#E2E8F0] rounded-md animate-pulse" />
          <div className="space-y-1.5">
            <div className="h-5 w-28 bg-[#E2E8F0] rounded-md animate-pulse" />
            <div className="h-3 w-20 bg-[#E2E8F0] rounded-md animate-pulse" />
          </div>
        </div>
        {/* Skeleton KPI */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 px-6 py-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="bg-white border border-[#E2E8F0] rounded-md p-3 space-y-2">
              <div className="h-3 w-16 bg-[#E2E8F0] rounded-md animate-pulse" />
              <div className="h-6 w-12 bg-[#E2E8F0] rounded-md animate-pulse" />
            </div>
          ))}
        </div>
        {/* Centered spinner */}
        <div className="flex-1 flex items-center justify-center">
          <div className="animate-spin rounded-full h-10 w-10 border-4 border-[#14B8A6] border-t-transparent" />
        </div>
      </div>
    )
  }

  if (!client) {
    return (
      <div className="h-[calc(100vh-48px)] flex items-center justify-center bg-[#F8FAFC]">
        <div className="text-[#94A3B8]">顧客が見つかりませんでした</div>
      </div>
    )
  }

  // KPI 計算
  const currentWeight = weightRecords[0]?.weight ?? null
  const thirtyDaysAgo = new Date()
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30)
  const oldRecord = weightRecords.find(
    (r) => new Date(r.recorded_at) <= thirtyDaysAgo
  )
  const weightChange =
    currentWeight !== null && oldRecord
      ? Math.round((currentWeight - oldRecord.weight) * 10) / 10
      : null
  const now = new Date()
  const remainingTickets = tickets
    .filter((t) => new Date(t.valid_until) >= now)
    .reduce((sum, t) => sum + t.remaining_sessions, 0)

  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto bg-[#F8FAFC]">
      {/* Header (sticky) + Profile Row */}
      <ClientHeader
        client={client}
        onClientUpdated={refetchClient}
        mode={mode}
        onModeChange={setMode}
      />

      {/* KPI Stats Bar */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 px-6 py-4">
        {/* 現在体重 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
          <p className="text-[11px] text-[#94A3B8] mb-1">現在体重</p>
          <p className="text-xl font-bold text-[#0F172A]">
            {currentWeight !== null ? currentWeight : '--'}
            <span className="text-xs text-[#94A3B8] ml-1">kg</span>
          </p>
        </div>
        {/* 目標体重 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
          <p className="text-[11px] text-[#94A3B8] mb-1">目標体重</p>
          <p className="text-xl font-bold text-[#0F172A]">
            {client.target_weight ?? '--'}
            <span className="text-xs text-[#94A3B8] ml-1">kg</span>
          </p>
        </div>
        {/* 月間変動 */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
          <p className="text-[11px] text-[#94A3B8] mb-1">月間変動</p>
          {weightChange !== null ? (
            <p
              className={`text-xl font-bold ${
                weightChange > 0 ? 'text-[#DC2626]' : weightChange < 0 ? 'text-[#16A34A]' : 'text-[#0F172A]'
              }`}
            >
              {weightChange > 0 ? '+' : ''}
              {weightChange}
              <span className="text-xs ml-1">kg</span>
            </p>
          ) : (
            <p className="text-xl font-bold text-[#0F172A]">
              --<span className="text-xs text-[#94A3B8] ml-1">kg</span>
            </p>
          )}
        </div>
        {/* 残チケット */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-3">
          <p className="text-[11px] text-[#94A3B8] mb-1">残チケット</p>
          <p className="text-xl font-bold text-[#0F172A]">
            {remainingTickets}
            <span className="text-xs text-[#94A3B8] ml-1">回</span>
          </p>
        </div>
      </div>

      {/* Mode Content */}
      {mode === 'info' ? (
        <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
          {/* Tab Navigation */}
          <TabsList className="flex w-full border-b border-[#E2E8F0] px-6 bg-transparent h-auto rounded-none gap-0">
            {TABS.map((tab) => (
              <TabsTrigger
                key={tab.value}
                value={tab.value}
                className={`px-3 py-2.5 text-sm font-medium flex items-center gap-1.5 rounded-none border-b-2 transition-colors data-[state=active]:shadow-none data-[state=active]:bg-transparent ${
                  activeTab === tab.value
                    ? 'text-[#14B8A6] border-[#14B8A6]'
                    : 'text-[#94A3B8] border-transparent hover:text-[#64748B]'
                }`}
              >
                <tab.icon size={16} />
                <span>{tab.label}</span>
              </TabsTrigger>
            ))}
          </TabsList>

          <div className="px-6 py-4">
            <TabsContent value="summary">
              <SummaryTab
                weightRecords={weightRecords}
                mealRecords={mealRecords}
                exerciseRecords={exerciseRecords}
                tickets={tickets}
                targetWeight={client.target_weight || 0}
                height={client.height}
                purpose={client.purpose}
                goalDescription={client.goal_description}
                goalDeadline={client.goal_deadline}
              />
            </TabsContent>

            <TabsContent value="meal">
              <MealTab mealRecords={mealRecords} />
            </TabsContent>

            <TabsContent value="weight">
              <WeightTab
                weightRecords={weightRecords}
                targetWeight={client.target_weight || 0}
              />
            </TabsContent>

            <TabsContent value="exercise">
              <ExerciseTab exerciseRecords={exerciseRecords} workoutAssignments={workoutAssignments} />
            </TabsContent>

            <TabsContent value="notes">
              <NotesTab
                notes={notes}
                clientId={clientId}
                trainerId={trainerId}
                onRefetch={refetchNotes}
              />
            </TabsContent>

            <TabsContent value="tickets">
              <TicketsTab tickets={tickets} />
            </TabsContent>
          </div>
        </Tabs>
      ) : (
        <div className="px-6 py-4">
          <SessionTab clientId={clientId} trainerId={trainerId} />
        </div>
      )}
    </div>
  )
}
