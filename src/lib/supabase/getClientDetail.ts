import { supabase } from '@/lib/supabase'
import type { ClientDetail } from '@/types/client'

export const getClientDetail = async (clientId: string): Promise<ClientDetail | null> => {
  // 基本情報取得
  const { data: client, error: clientError } = await supabase
    .from('clients')
    .select('*')
    .eq('client_id', clientId)
    .single()

  if (clientError) {
    console.error('クライアント詳細取得エラー：', clientError)
    throw clientError
  }

  if (!client) return null

  // 最新の体重取得
  const { data: latestWeight } = await supabase
    .from('weight_records')
    .select('weight')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  // 初回の体重取得
  const { data: initialWeight } = await supabase
    .from('weight_records')
    .select('weight')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: true })
    .limit(1)
    .maybeSingle()

  return {
    ...client,
    current_weight: latestWeight?.weight,
    initial_weight: initialWeight?.weight,
  } as ClientDetail
}
