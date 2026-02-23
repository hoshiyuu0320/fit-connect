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
      <div className="h-[calc(100vh-48px)] flex items-center justify-center bg-gray-50">
        <div className="text-gray-600">読み込み中...</div>
      </div>
    )
  }

  if (!client) {
    return (
      <div className="h-[calc(100vh-48px)] flex items-center justify-center bg-gray-50">
        <div className="text-gray-600">顧客が見つかりませんでした</div>
      </div>
    )
  }

  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-6xl mx-auto p-6 space-y-6">
        {/* ヘッダー */}
        <ClientHeader client={client} onClientUpdated={refetchClient} mode={mode} onModeChange={setMode} />

        {/* モード別コンテンツ */}
        {mode === 'info' ? (
          <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
            <TabsList className="grid w-full grid-cols-6">
              <TabsTrigger value="summary">サマリー</TabsTrigger>
              <TabsTrigger value="weight">体重</TabsTrigger>
              <TabsTrigger value="meal">食事</TabsTrigger>
              <TabsTrigger value="exercise">運動</TabsTrigger>
              <TabsTrigger value="notes">カルテ</TabsTrigger>
              <TabsTrigger value="tickets">チケット</TabsTrigger>
            </TabsList>

            <TabsContent value="summary">
              <SummaryTab
                weightRecords={weightRecords}
                mealRecords={mealRecords}
                exerciseRecords={exerciseRecords}
                tickets={tickets}
                targetWeight={client.target_weight || 0}
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
          </Tabs>
        ) : (
          <SessionTab clientId={clientId} trainerId={trainerId} />
        )}
      </div>
    </div>
  )
}
