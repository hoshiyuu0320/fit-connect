import { supabase } from '@/lib/supabase'
import { collectTriageClientIds } from '@/lib/triage/buildTriageRows'

/**
 * サイドバー「ダッシュボード」のバッジの数（「今日の対応」に並ぶ顧客の数）を取得する。
 *
 * - PR1 は open のアラートがある顧客の数（PR2 で未返信の顧客を合わせる）
 * - getOpenAlerts と同じ絞り込み（status='open'・clients!inner・RLS）にして、見出しの件数と揃える
 * - 数え方（顧客 ID の重複を除く）は buildTriageRows の collectTriageClientIds に一本化する
 * - 失敗は throw する（ストア側で前の値のまま残す）
 */
export async function getTriageBadgeCount(): Promise<number> {
  const { data, error } = await supabase
    .from('alerts')
    .select('client_id, clients!inner(client_id)')
    .eq('status', 'open')

  if (error) {
    console.error('今日の対応の件数取得エラー:', error)
    throw error
  }

  return collectTriageClientIds((data ?? []) as { client_id: string }[]).size
}
