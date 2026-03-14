import { supabase } from '@/lib/supabase'

export interface DailyRecordPoint {
  date: string         // 'YYYY-MM-DD'
  label: string        // '3/12 (木)' 形式
  meal: number
  weight: number
  exercise: number
}

/**
 * 過去7日間の日別記録件数（食事・体重・運動）を集計する
 * @param trainerId - トレーナーID
 * @returns DailyRecordPoint[] - 7日分の日別記録件数（古い順）
 */
export async function getDailyRecordTrend(trainerId: string): Promise<DailyRecordPoint[]> {
  // 1. トレーナーの全クライアントIDを取得
  const { data: clients, error: clientsError } = await supabase
    .from('clients')
    .select('client_id')
    .eq('trainer_id', trainerId)

  if (clientsError) throw clientsError
  if (!clients || clients.length === 0) return []

  const clientIds = clients.map(c => c.client_id)

  // 2. 過去7日分の日付を生成
  const weekdays = ['日', '月', '火', '水', '木', '金', '土']
  const days: { date: string; label: string }[] = []
  for (let i = 6; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    const yyyy = d.getFullYear()
    const mm = String(d.getMonth() + 1).padStart(2, '0')
    const dd = String(d.getDate()).padStart(2, '0')
    days.push({
      date: `${yyyy}-${mm}-${dd}`,
      label: `${d.getMonth() + 1}/${d.getDate()} (${weekdays[d.getDay()]})`,
    })
  }

  // 3. 7日前の0:00を起点に3テーブルからデータ取得（並列）
  const since = new Date()
  since.setDate(since.getDate() - 6)
  since.setHours(0, 0, 0, 0)
  const sinceStr = since.toISOString()

  const [mealRes, weightRes, exerciseRes] = await Promise.all([
    supabase.from('meal_records').select('recorded_at').in('client_id', clientIds).gte('recorded_at', sinceStr),
    supabase.from('weight_records').select('recorded_at').in('client_id', clientIds).gte('recorded_at', sinceStr),
    supabase.from('exercise_records').select('recorded_at').in('client_id', clientIds).gte('recorded_at', sinceStr),
  ])

  if (mealRes.error) throw mealRes.error
  if (weightRes.error) throw weightRes.error
  if (exerciseRes.error) throw exerciseRes.error

  // 4. 各レコードを日付ごとにカウント
  const toDateStr = (iso: string) => {
    const d = new Date(iso)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  const mealByDate = new Map<string, number>()
  const weightByDate = new Map<string, number>()
  const exerciseByDate = new Map<string, number>()

  mealRes.data?.forEach(r => {
    const d = toDateStr(r.recorded_at)
    mealByDate.set(d, (mealByDate.get(d) ?? 0) + 1)
  })
  weightRes.data?.forEach(r => {
    const d = toDateStr(r.recorded_at)
    weightByDate.set(d, (weightByDate.get(d) ?? 0) + 1)
  })
  exerciseRes.data?.forEach(r => {
    const d = toDateStr(r.recorded_at)
    exerciseByDate.set(d, (exerciseByDate.get(d) ?? 0) + 1)
  })

  // 5. 結果を日付順に返す
  return days.map(day => ({
    date: day.date,
    label: day.label,
    meal: mealByDate.get(day.date) ?? 0,
    weight: weightByDate.get(day.date) ?? 0,
    exercise: exerciseByDate.get(day.date) ?? 0,
  }))
}
