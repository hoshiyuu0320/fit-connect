import { supabase } from '@/lib/supabase'

// 統合記録の種別
export type RecordType = 'meal' | 'weight' | 'exercise'

// 統合記録の型定義
export interface RecentRecord {
  id: string
  type: RecordType
  client_id: string
  client_name: string
  recorded_at: string
  // 食事
  meal_type?: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  description?: string | null
  calories?: number | null
  images?: string[] | null
  // 体重
  weight?: number
  weight_change?: number | null // 前回比
  // 運動
  exercise_type?: string
  duration?: number | null
  distance?: number | null
  exercise_calories?: number | null
  memo?: string | null
}

export async function getRecentRecords(
  trainerId: string,
  options?: {
    filter?: RecordType | 'all'
    limit?: number
    days?: number // 取得する日数（デフォルト2 = 今日+昨日）
  }
): Promise<RecentRecord[]> {
  const filter = options?.filter ?? 'all'
  const limit = options?.limit ?? 20
  const days = options?.days ?? 2

  // 取得開始日（days日前の0:00）
  const since = new Date()
  since.setDate(since.getDate() - (days - 1))
  since.setHours(0, 0, 0, 0)
  const sinceStr = since.toISOString()

  // トレーナーの全クライアントを取得
  const { data: clients, error: clientsError } = await supabase
    .from('clients')
    .select('client_id, name')
    .eq('trainer_id', trainerId)

  if (clientsError) {
    console.error('クライアント取得エラー:', clientsError)
    throw clientsError
  }

  if (!clients || clients.length === 0) return []

  const clientIds = clients.map((c) => c.client_id)
  const clientMap = new Map(clients.map((c) => [c.client_id, c.name as string]))

  const records: RecentRecord[] = []

  // 食事記録を取得
  if (filter === 'all' || filter === 'meal') {
    const { data: meals, error: mealsError } = await supabase
      .from('meal_records')
      .select('id, client_id, meal_type, notes, calories, images, recorded_at')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr)
      .order('recorded_at', { ascending: false })
      .limit(limit)

    if (mealsError) {
      console.error('食事記録取得エラー:', mealsError)
      throw mealsError
    }

    if (meals) {
      meals.forEach((m) => {
        records.push({
          id: m.id,
          type: 'meal',
          client_id: m.client_id,
          client_name: clientMap.get(m.client_id) ?? '不明',
          recorded_at: m.recorded_at,
          meal_type: m.meal_type,
          description: m.notes,
          calories: m.calories,
          images: m.images,
        })
      })
    }
  }

  // 体重記録を取得
  if (filter === 'all' || filter === 'weight') {
    const { data: weights, error: weightsError } = await supabase
      .from('weight_records')
      .select('id, client_id, weight, recorded_at')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr)
      .order('recorded_at', { ascending: false })
      .limit(limit)

    if (weightsError) {
      console.error('体重記録取得エラー:', weightsError)
      throw weightsError
    }

    if (weights) {
      // 前回比を計算するため、クライアントごとにグループ化
      const weightsByClient = new Map<string, typeof weights>()
      weights.forEach((w) => {
        if (!weightsByClient.has(w.client_id)) {
          weightsByClient.set(w.client_id, [])
        }
        weightsByClient.get(w.client_id)!.push(w)
      })

      weights.forEach((w) => {
        const clientWeights = weightsByClient.get(w.client_id) ?? []
        const idx = clientWeights.findIndex((cw) => cw.id === w.id)
        const prevWeight =
          idx < clientWeights.length - 1 ? clientWeights[idx + 1]?.weight : null
        const weightChange =
          prevWeight != null
            ? Number((w.weight - prevWeight).toFixed(1))
            : null

        records.push({
          id: w.id,
          type: 'weight',
          client_id: w.client_id,
          client_name: clientMap.get(w.client_id) ?? '不明',
          recorded_at: w.recorded_at,
          weight: w.weight,
          weight_change: weightChange,
        })
      })
    }
  }

  // 運動記録を取得
  if (filter === 'all' || filter === 'exercise') {
    const { data: exercises, error: exercisesError } = await supabase
      .from('exercise_records')
      .select('id, client_id, exercise_type, duration, distance, calories, memo, recorded_at')
      .in('client_id', clientIds)
      .gte('recorded_at', sinceStr)
      .order('recorded_at', { ascending: false })
      .limit(limit)

    if (exercisesError) {
      console.error('運動記録取得エラー:', exercisesError)
      throw exercisesError
    }

    if (exercises) {
      exercises.forEach((e) => {
        records.push({
          id: e.id,
          type: 'exercise',
          client_id: e.client_id,
          client_name: clientMap.get(e.client_id) ?? '不明',
          recorded_at: e.recorded_at,
          exercise_type: e.exercise_type,
          duration: e.duration,
          distance: e.distance,
          exercise_calories: e.calories,
          memo: e.memo,
        })
      })
    }
  }

  // 時系列降順にソートしてlimit件返す
  records.sort(
    (a, b) => new Date(b.recorded_at).getTime() - new Date(a.recorded_at).getTime()
  )
  return records.slice(0, limit)
}
