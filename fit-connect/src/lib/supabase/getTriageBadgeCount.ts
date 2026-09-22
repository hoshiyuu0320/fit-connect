import { supabase } from '@/lib/supabase'
import { getUnrepliedClients } from '@/lib/supabase/getUnrepliedClients'
import { collectTriageClientIds } from '@/lib/triage/buildTriageRows'
import type { TriageBadgeCountResult } from '@/lib/triage/triageLoadState'

/** open のアラートがある顧客（getOpenAlerts と同じ絞り込み: status='open'・clients!inner・RLS） */
async function getOpenAlertClientIds(): Promise<{ client_id: string }[]> {
  const { data, error } = await supabase
    .from('alerts')
    .select('client_id, clients!inner(client_id)')
    .eq('status', 'open')

  if (error) {
    console.error('今日の対応の件数取得エラー:', error)
    throw error
  }

  return (data ?? []) as { client_id: string }[]
}

/**
 * サイドバー「ダッシュボード」のバッジの数（「今日の対応」に並ぶ顧客の数）を取得する。
 *
 * - open のアラートがある顧客と未返信の顧客の和集合の人数（同じ顧客は1人）
 * - 数え方は buildTriageRows の collectTriageClientIds に一本化し、見出しの件数と揃える
 * - 2つの取得は並列に行い（Promise.allSettled）、片方が失敗しても取れた分の人数を complete: false で返す。
 *   前の値を残すか取れた分を出すかは、ストアが nextTriageBadgeCount で決める
 *   （表示直後に未返信だけ失敗しても、open のアラートがある顧客をバッジから消さないため。見出しも取れた分を出す）
 * - 両方とも失敗したら throw する（ストア側で前の値のまま残す）
 */
export async function getTriageBadgeCount(): Promise<TriageBadgeCountResult> {
  const [alertsResult, unrepliedResult] = await Promise.allSettled([
    getOpenAlertClientIds(),
    getUnrepliedClients(),
  ])
  if (alertsResult.status === 'rejected' && unrepliedResult.status === 'rejected') {
    throw alertsResult.reason
  }
  const count = collectTriageClientIds(
    alertsResult.status === 'fulfilled' ? alertsResult.value : [],
    unrepliedResult.status === 'fulfilled' ? unrepliedResult.value : []
  ).size
  return {
    count,
    complete: alertsResult.status === 'fulfilled' && unrepliedResult.status === 'fulfilled',
  }
}
