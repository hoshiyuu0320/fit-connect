import { supabase } from '@/lib/supabase'

export type PurposeType =
  | 'diet'
  | 'contest'
  | 'body_make'
  | 'health_improvement'
  | 'mental_improvement'
  | 'performance_improvement'

export interface GoalProgressClient {
  clientId: string
  clientName: string
  profileImageUrl: string | null
  purpose: PurposeType
  initialWeight: number | null
  currentWeight: number | null
  targetWeight: number
  progressRate: number // 0-100+（100超えは達成済み）
  weightChange: number | null // 開始からの変化量
  goalSetAt: string | null
  goalDescription: string | null
}

export interface GoalProgressByCategory {
  purpose: PurposeType
  label: string
  clients: GoalProgressClient[]
}

const PURPOSE_LABELS: Record<PurposeType, string> = {
  diet: 'ダイエット',
  contest: 'コンテスト',
  body_make: 'ボディメイク',
  health_improvement: '健康改善',
  mental_improvement: 'メンタル改善',
  performance_improvement: 'パフォーマンス',
}

/**
 * トレーナーの全顧客の目標達成プログレスをpurposeカテゴリ別にグループ化して返す
 * @param trainerId - トレーナーID
 * @returns GoalProgressByCategory[] - カテゴリ別にグループ化された顧客プログレス一覧
 */
export async function getGoalProgress(trainerId: string): Promise<GoalProgressByCategory[]> {
  // 1. トレーナーの全クライアントを取得
  const { data: clients, error } = await supabase
    .from('clients')
    .select(
      'client_id, name, purpose, target_weight, goal_description, profile_image_url, created_at'
    )
    .eq('trainer_id', trainerId)

  if (error) throw error
  if (!clients || clients.length === 0) return []

  const clientIds = clients.map((c) => c.client_id)

  // 2. 全クライアントの体重記録を取得（recorded_at 降順 = 最新が先頭）
  const { data: weights, error: weightsError } = await supabase
    .from('weight_records')
    .select('client_id, weight, recorded_at')
    .in('client_id', clientIds)
    .order('recorded_at', { ascending: false })

  if (weightsError) throw weightsError

  // クライアントごとに最新体重と最古体重をマッピング
  // data は recorded_at desc で並んでいるため、最初に出現したものが最新、最後が最古
  const latestWeightMap = new Map<string, number>()
  const oldestWeightMap = new Map<string, number>()

  if (weights) {
    weights.forEach((w) => {
      if (!latestWeightMap.has(w.client_id)) {
        latestWeightMap.set(w.client_id, w.weight)
      }
      // 毎回上書きすることで最終的に最古が残る
      oldestWeightMap.set(w.client_id, w.weight)
    })
  }

  // 3. クライアントごとに進捗を計算
  const progressClients: GoalProgressClient[] = clients.map((c) => {
    const initial = oldestWeightMap.get(c.client_id) ?? null
    const current = latestWeightMap.get(c.client_id) ?? null
    const target = c.target_weight as number

    let progressRate = 0
    let weightChange: number | null = null

    if (initial !== null && current !== null) {
      weightChange = Number((current - initial).toFixed(1))
      const diff = initial - target // 体重減少目標(diet系): diff > 0、増加目標(bodymake系): diff < 0

      if (Math.abs(diff) > 0.01) {
        progressRate = Math.round(((initial - current) / diff) * 1000) / 10
      }
    }

    // 進捗率は0以上に制限（スタートより悪化してもマイナス表示しない）
    if (progressRate < 0) progressRate = 0

    return {
      clientId: c.client_id,
      clientName: c.name as string,
      profileImageUrl: c.profile_image_url,
      purpose: c.purpose as PurposeType,
      initialWeight: initial,
      currentWeight: current,
      targetWeight: target,
      progressRate,
      weightChange,
      goalSetAt: c.created_at,
      goalDescription: c.goal_description,
    }
  })

  // 4. purposeごとにグループ化
  const grouped = new Map<PurposeType, GoalProgressClient[]>()
  progressClients.forEach((pc) => {
    if (!grouped.has(pc.purpose)) {
      grouped.set(pc.purpose, [])
    }
    grouped.get(pc.purpose)!.push(pc)
  })

  // 5. カテゴリ順に返す（クライアントが存在するカテゴリのみ）
  const order: PurposeType[] = [
    'diet',
    'contest',
    'body_make',
    'health_improvement',
    'mental_improvement',
    'performance_improvement',
  ]

  return order
    .filter((p) => grouped.has(p))
    .map((p) => ({
      purpose: p,
      label: PURPOSE_LABELS[p],
      clients: grouped.get(p)!,
    }))
}
