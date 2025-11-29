'use client'

import { useEffect, useState } from 'react'
import Image from 'next/image'
import { useParams, useRouter } from 'next/navigation'
import { getClientDetail } from '@/lib/supabase/getClientDetail'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getExerciseRecords } from '@/lib/supabase/getExerciseRecords'
import { getTickets } from '@/lib/supabase/getTickets'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import type { ClientDetail, WeightRecord, MealRecord, ExerciseRecord, Ticket } from '@/types/client'
import { GENDER_OPTIONS, PURPOSE_OPTIONS, MEAL_TYPE_OPTIONS, EXERCISE_TYPE_OPTIONS } from '@/types/client'

export default function ClientDetailPage() {
  const params = useParams()
  const router = useRouter()
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
          getMealRecords({ clientId, limit: 10 }),
          getExerciseRecords({ clientId, limit: 10 }),
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
        <div className="flex items-center justify-between">
          <button
            onClick={() => router.push('/clients')}
            className="text-blue-600 hover:text-blue-700 flex items-center space-x-1"
          >
            <span>←</span>
            <span>顧客リストに戻る</span>
          </button>
          <button
            onClick={() => router.push(`/message?clientId=${client.client_id}`)}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            メッセージ
          </button>
        </div>

        {/* 基本情報 */}
        <Card>
          <CardHeader>
            <CardTitle>基本情報</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex items-start space-x-6">
              <ProfileAvatar client={client} size="lg" />
              <div className="flex-1 space-y-3">
                <div>
                  <h2 className="text-2xl font-bold">{client.name}</h2>
                  <div className="flex items-center space-x-3 text-gray-600 mt-1">
                    <span>{GENDER_OPTIONS[client.gender]}</span>
                    <span>•</span>
                    <span>{client.age}歳</span>
                    {client.occupation && (
                      <>
                        <span>•</span>
                        <span>{client.occupation}</span>
                      </>
                    )}
                  </div>
                </div>

                <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                  <div>
                    <div className="text-gray-500">身長</div>
                    <div className="font-semibold">{client.height} cm</div>
                  </div>
                  <div>
                    <div className="text-gray-500">目標体重</div>
                    <div className="font-semibold">{client.target_weight} kg</div>
                  </div>
                  <div>
                    <div className="text-gray-500">現在の体重</div>
                    <div className="font-semibold">
                      {client.current_weight ? `${client.current_weight} kg` : '記録なし'}
                    </div>
                  </div>
                  <div>
                    <div className="text-gray-500">目的</div>
                    <div className="font-semibold">{PURPOSE_OPTIONS[client.purpose]}</div>
                  </div>
                </div>

                {client.goal_description && (
                  <div className="pt-2 border-t">
                    <div className="text-sm text-gray-500 mb-1">目標</div>
                    <div className="text-gray-800">{client.goal_description}</div>
                  </div>
                )}
              </div>
            </div>
          </CardContent>
        </Card>

        {/* 体重推移（グラフは後で実装） */}
        <Card>
          <CardHeader>
            <CardTitle>体重推移</CardTitle>
          </CardHeader>
          <CardContent>
            {weightRecords.length > 0 ? (
              <div className="space-y-2">
                <p className="text-sm text-gray-600">記録数: {weightRecords.length}件</p>
                <div className="text-gray-500 text-sm">※グラフ表示は今後実装予定です</div>
                <div className="max-h-40 overflow-y-auto">
                  {weightRecords.slice(-10).reverse().map((record) => (
                    <div key={record.id} className="flex justify-between py-2 border-b text-sm">
                      <span>{new Date(record.recorded_at).toLocaleDateString()}</span>
                      <span className="font-semibold">{record.weight} kg</span>
                    </div>
                  ))}
                </div>
              </div>
            ) : (
              <p className="text-gray-500">まだ体重記録がありません</p>
            )}
          </CardContent>
        </Card>

        {/* 食事記録 */}
        <Card>
          <CardHeader>
            <CardTitle>食事記録</CardTitle>
          </CardHeader>
          <CardContent>
            {mealRecords.length > 0 ? (
              <div className="space-y-4">
                {mealRecords.map((meal) => (
                  <div key={meal.id} className="border-b pb-4 last:border-b-0">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <span className="font-semibold">{MEAL_TYPE_OPTIONS[meal.meal_type]}</span>
                        <span className="text-sm text-gray-500 ml-2">
                          {new Date(meal.recorded_at).toLocaleString()}
                        </span>
                      </div>
                      {meal.calories && (
                        <span className="text-sm font-semibold text-orange-600">
                          {meal.calories} kcal
                        </span>
                      )}
                    </div>
                    {meal.description && <p className="text-sm text-gray-700 mb-2">{meal.description}</p>}
                    {meal.images && meal.images.length > 0 && (
                      <div className="flex gap-2 flex-wrap">
                        {meal.images.map((img, idx) => (
                          <div key={idx} className="relative w-20 h-20 rounded overflow-hidden bg-gray-100">
                            <Image
                              src={img}
                              alt="食事画像"
                              fill
                              className="object-cover"
                              unoptimized
                            />
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-gray-500">まだ食事記録がありません</p>
            )}
          </CardContent>
        </Card>

        {/* 運動記録 */}
        <Card>
          <CardHeader>
            <CardTitle>運動記録</CardTitle>
          </CardHeader>
          <CardContent>
            {exerciseRecords.length > 0 ? (
              <div className="space-y-4">
                {exerciseRecords.map((exercise) => (
                  <div key={exercise.id} className="border-b pb-4 last:border-b-0">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <span className="font-semibold">{EXERCISE_TYPE_OPTIONS[exercise.exercise_type]}</span>
                        <span className="text-sm text-gray-500 ml-2">
                          {new Date(exercise.recorded_at).toLocaleString()}
                        </span>
                      </div>
                      {exercise.calories && (
                        <span className="text-sm font-semibold text-green-600">
                          {exercise.calories} kcal
                        </span>
                      )}
                    </div>
                    <div className="flex gap-4 text-sm text-gray-700">
                      {exercise.duration && <span>時間: {exercise.duration}分</span>}
                      {exercise.distance && <span>距離: {exercise.distance}km</span>}
                    </div>
                    {exercise.memo && <p className="text-sm text-gray-700 mt-2">{exercise.memo}</p>}
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-gray-500">まだ運動記録がありません</p>
            )}
          </CardContent>
        </Card>

        {/* チケット情報 */}
        <Card>
          <CardHeader>
            <CardTitle>保有チケット</CardTitle>
          </CardHeader>
          <CardContent>
            {tickets.length > 0 ? (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {tickets.map((ticket) => {
                  const isExpired = new Date(ticket.valid_until) < new Date()
                  const isUsedUp = ticket.remaining_sessions === 0
                  const progress = (ticket.remaining_sessions / ticket.total_sessions) * 100

                  return (
                    <div
                      key={ticket.id}
                      className={`border rounded-lg p-4 ${isExpired || isUsedUp ? 'bg-gray-50 opacity-60' : 'bg-white'
                        }`}
                    >
                      <h4 className="font-semibold mb-2">{ticket.ticket_name}</h4>
                      <div className="text-sm text-gray-600 mb-2">{ticket.ticket_type}</div>
                      <div className="mb-2">
                        <div className="flex justify-between text-sm mb-1">
                          <span>
                            残り {ticket.remaining_sessions} / {ticket.total_sessions} 回
                          </span>
                          <span>{Math.round(progress)}%</span>
                        </div>
                        <div className="w-full bg-gray-200 rounded-full h-2">
                          <div
                            className="bg-blue-600 h-2 rounded-full"
                            style={{ width: `${progress}%` }}
                          />
                        </div>
                      </div>
                      <div className="text-xs text-gray-500">
                        有効期限: {new Date(ticket.valid_from).toLocaleDateString()} 〜{' '}
                        {new Date(ticket.valid_until).toLocaleDateString()}
                      </div>
                      {isExpired && (
                        <div className="mt-2 text-xs text-red-600 font-semibold">期限切れ</div>
                      )}
                      {isUsedUp && !isExpired && (
                        <div className="mt-2 text-xs text-gray-600 font-semibold">使用済み</div>
                      )}
                    </div>
                  )
                })}
              </div>
            ) : (
              <p className="text-gray-500">チケット情報がありません</p>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
