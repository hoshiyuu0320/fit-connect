import { supabase } from '@/lib/supabase'
import { ClientReportRow, DateRange, OverviewKPIData } from '@/types/report'
import { Client } from '@/types/client'
import { differenceInDays, eachDayOfInterval, parseISO, subDays, format } from 'date-fns'

/**
 * 全クライアントのレポート用メトリクスをバッチ取得する
 * trainerId と dateRange を受け取り、全クライアントの ClientReportRow[] と OverviewKPIData を返す
 */
export async function getClientReportMetrics(
  trainerId: string,
  clients: Client[],
  dateRange: DateRange
): Promise<{ rows: ClientReportRow[]; kpi: OverviewKPIData }> {
  // 期間の日数を算出
  const start = parseISO(dateRange.startDate)
  const end = parseISO(dateRange.endDate)
  const totalDays = differenceInDays(end, start) + 1
  const allDates = eachDayOfInterval({ start, end })

  // 過去30日の基準日（アクティブ率算出用）
  const thirtyDaysAgo = format(subDays(new Date(), 30), 'yyyy-MM-dd')

  // 各クライアントのメトリクスを並列取得
  const rowPromises = clients.map(async (client): Promise<ClientReportRow> => {
    const [weightResult, mealResult, exerciseResult] = await Promise.all([
      supabase
        .from('weight_records')
        .select('weight, recorded_at')
        .eq('client_id', client.client_id)
        .gte('recorded_at', dateRange.startDate)
        .lte('recorded_at', dateRange.endDate)
        .order('recorded_at', { ascending: true })
        .limit(10000),
      supabase
        .from('meal_records')
        .select('recorded_at')
        .eq('client_id', client.client_id)
        .gte('recorded_at', dateRange.startDate)
        .lte('recorded_at', dateRange.endDate)
        .limit(10000),
      supabase
        .from('exercise_records')
        .select('recorded_at')
        .eq('client_id', client.client_id)
        .gte('recorded_at', dateRange.startDate)
        .lte('recorded_at', dateRange.endDate)
        .limit(10000),
    ])

    const weights = weightResult.data ?? []
    const meals = mealResult.data ?? []
    const exercises = exerciseResult.data ?? []

    // 体重変動: 期間内最初と最後の差分
    const latestWeight = weights.length > 0 ? weights[weights.length - 1].weight : null
    const firstWeight = weights.length > 0 ? weights[0].weight : null
    const weightChange =
      latestWeight !== null && firstWeight !== null ? latestWeight - firstWeight : null

    // 食事記録率: 記録がある日数 / 期間の総日数 * 100
    const mealDates = new Set(
      meals.map((m) => format(parseISO(m.recorded_at), 'yyyy-MM-dd'))
    )
    const mealRecordRate = totalDays > 0 ? (mealDates.size / totalDays) * 100 : 0

    // 運動記録率: 記録がある日数 / 期間の総日数 * 100
    const exerciseDates = new Set(
      exercises.map((e) => format(parseISO(e.recorded_at), 'yyyy-MM-dd'))
    )
    const exerciseRecordRate = totalDays > 0 ? (exerciseDates.size / totalDays) * 100 : 0

    // 体重スコア: 体重が目標に近づいた割合 (0-100)
    let weightScore = 0
    if (
      client.target_weight &&
      firstWeight !== null &&
      latestWeight !== null &&
      firstWeight !== client.target_weight
    ) {
      const initialDiff = Math.abs(firstWeight - client.target_weight)
      const currentDiff = Math.abs(latestWeight - client.target_weight)
      // 目標に近づいた割合（100% = 目標達成、0% = 変化なし、負 = 逆行）
      const progress = ((initialDiff - currentDiff) / initialDiff) * 100
      weightScore = Math.max(0, Math.min(100, progress))
    }

    // 総合スコア
    let score: number
    if (client.target_weight) {
      score = weightScore * 0.4 + mealRecordRate * 0.3 + exerciseRecordRate * 0.3
    } else {
      score = mealRecordRate * 0.6 + exerciseRecordRate * 0.4
    }
    score = Math.round(score)

    // ステータス判定
    const status: ClientReportRow['status'] =
      score >= 70 ? 'good' : score >= 40 ? 'warning' : 'danger'

    return {
      client_id: client.client_id,
      name: client.name,
      age: client.age,
      gender: client.gender,
      purpose: client.purpose,
      latestWeight: latestWeight !== null ? Number(latestWeight) : null,
      targetWeight: client.target_weight ? Number(client.target_weight) : null,
      weightChange: weightChange !== null ? Number(weightChange) : null,
      mealRecordRate: Math.round(mealRecordRate),
      exerciseRecordRate: Math.round(exerciseRecordRate),
      score,
      status,
    }
  })

  const rows = await Promise.all(rowPromises)

  // --- KPI算出 ---

  // アクティブ率: 過去30日で何らかの記録があるクライアント / 全クライアント * 100
  const activeCheckPromises = clients.map(async (client) => {
    const [w, m, e] = await Promise.all([
      supabase
        .from('weight_records')
        .select('id')
        .eq('client_id', client.client_id)
        .gte('recorded_at', thirtyDaysAgo)
        .limit(1),
      supabase
        .from('meal_records')
        .select('id')
        .eq('client_id', client.client_id)
        .gte('recorded_at', thirtyDaysAgo)
        .limit(1),
      supabase
        .from('exercise_records')
        .select('id')
        .eq('client_id', client.client_id)
        .gte('recorded_at', thirtyDaysAgo)
        .limit(1),
    ])

    const hasWeight = (w.data?.length ?? 0) > 0
    const hasMeal = (m.data?.length ?? 0) > 0
    const hasExercise = (e.data?.length ?? 0) > 0
    return hasWeight || hasMeal || hasExercise
  })

  const activeResults = await Promise.all(activeCheckPromises)
  const activeCount = activeResults.filter(Boolean).length
  const activeRate = clients.length > 0 ? Math.round((activeCount / clients.length) * 100) : 0

  // 平均記録率
  const avgRecordRate =
    rows.length > 0
      ? Math.round(
          rows.reduce((sum, r) => sum + (r.mealRecordRate + r.exerciseRecordRate) / 2, 0) /
            rows.length
        )
      : 0

  // 目標達成者: 体重目標に到達したクライアント数
  const goalAchievers = rows.filter((r) => {
    if (r.targetWeight === null || r.latestWeight === null) return false
    // 目標体重との差が1kg以内なら達成とみなす
    return Math.abs(r.latestWeight - r.targetWeight) <= 1
  }).length

  // 目標設定者数
  const totalClientsGoal = clients.filter((c) => c.target_weight).length

  const kpi: OverviewKPIData = {
    totalClients: clients.length,
    activeRate,
    avgRecordRate,
    goalAchievers,
    totalClientsGoal,
    changes: {
      totalClients: 0,
      activeRate: 0,
      avgRecordRate: 0,
      goalAchievers: 0,
    },
  }

  // 未使用変数を回避（将来の拡張で使用予定）
  void allDates
  void trainerId

  return { rows, kpi }
}
