'use client'

import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { getClientDetail } from '@/lib/supabase/getClientDetail'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getExerciseRecords } from '@/lib/supabase/getExerciseRecords'
import { getTickets } from '@/lib/supabase/getTickets'
import type { ClientDetail, WeightRecord, MealRecord, ExerciseRecord, Ticket } from '@/types/client'
import { ClientHeader } from './_components/ClientHeader'
import { SummaryTab } from './_components/SummaryTab'
import { MealTab } from './_components/MealTab'
import { WeightTab } from './_components/WeightTab'
import { ExerciseTab } from './_components/ExerciseTab'

export default function ClientDetailPage() {
  const params = useParams()
  const clientId = params.client_id as string

  const [client, setClient] = useState<ClientDetail | null>(null)
  const [weightRecords, setWeightRecords] = useState<WeightRecord[]>([])
  const [mealRecords, setMealRecords] = useState<MealRecord[]>([])
  const [exerciseRecords, setExerciseRecords] = useState<ExerciseRecord[]>([])
  const [tickets, setTickets] = useState<Ticket[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchData = async () => {
      try {
        const [clientData, weights, meals, exercises, ticketsData] = await Promise.all([
          getClientDetail(clientId),
          getWeightRecords(clientId),
          getMealRecords({ clientId, limit: 100 }),
          getExerciseRecords({ clientId, limit: 100 }),
          getTickets(clientId),
        ])
        setClient(clientData)
        setWeightRecords(weights)
        setMealRecords(meals.data)
        setExerciseRecords(exercises.data)
        setTickets(ticketsData)
      } catch (error) {
        console.error('データ取得エラー：', error)
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [clientId])

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
        <ClientHeader client={client} />

        {/* タブ */}
        <Tabs defaultValue="summary" className="w-full">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="summary">サマリー</TabsTrigger>
            <TabsTrigger value="meal">食事</TabsTrigger>
            <TabsTrigger value="weight">体重</TabsTrigger>
            <TabsTrigger value="exercise">運動</TabsTrigger>
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
            <ExerciseTab exerciseRecords={exerciseRecords} />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  )
}
