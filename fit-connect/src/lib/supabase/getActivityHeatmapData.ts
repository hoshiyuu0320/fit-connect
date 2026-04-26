import { supabase } from '@/lib/supabase'
import { HeatmapRow, DateRange } from '@/types/report'
import { Client } from '@/types/client'
import { format, parseISO } from 'date-fns'

/**
 * ヒートマップ用のデータ取得関数
 * 各クライアントの日付ごとの記録数をカウントして返す
 */
export async function getActivityHeatmapData(
  clients: Client[],
  dateRange: DateRange
): Promise<HeatmapRow[]> {
  const rowPromises = clients.map(async (client): Promise<HeatmapRow> => {
    // weight_records, meal_records, exercise_records を並列取得
    const [weightResult, mealResult, exerciseResult] = await Promise.all([
      supabase
        .from('weight_records')
        .select('recorded_at')
        .eq('client_id', client.client_id)
        .gte('recorded_at', dateRange.startDate)
        .lte('recorded_at', dateRange.endDate)
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

    // 日付ごとの記録数をカウント
    const dateCountMap = new Map<string, number>()

    const allRecords = [...weights, ...meals, ...exercises]
    for (const record of allRecords) {
      const dateStr = format(parseISO(record.recorded_at), 'yyyy-MM-dd')
      dateCountMap.set(dateStr, (dateCountMap.get(dateStr) ?? 0) + 1)
    }

    // dailyCounts配列に変換
    const dailyCounts = Array.from(dateCountMap.entries())
      .map(([date, count]) => ({ date, count }))
      .sort((a, b) => a.date.localeCompare(b.date))

    return {
      clientId: client.client_id,
      clientName: client.name,
      dailyCounts,
    }
  })

  return Promise.all(rowPromises)
}
