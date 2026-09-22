import { supabase } from '@/lib/supabase'
import type { UnrepliedClient } from '@/types/triage'

function toNonEmptyString(value: unknown): string | null {
  return typeof value === 'string' && value !== '' ? value : null
}

/** 解釈できる日時の文字列ならそのまま返す */
function toTimestamp(value: unknown): string | null {
  const text = toNonEmptyString(value)
  return text !== null && !Number.isNaN(Date.parse(text)) ? text : null
}

/** 件数（bigint が文字列で届いても数える）。行がある = 未返信が1件以上なので、読めなければ 1 */
function toUnrepliedCount(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(parsed) && parsed >= 1 ? Math.trunc(parsed) : 1
}

/**
 * RPC get_unreplied_clients_for_trainer() の結果を型に揃える。
 *
 * - client_id が無い行と、未返信の時刻が読めない行は落とす（messages.created_at は NOT NULL なので、
 *   RPC が返す行には必ずある。読めない行は並べる位置も未返信の時間も決められない）
 * - latest_unreplied_at が読めなければ unreplied_since で代える
 * - 同じ顧客が2行来たら最初の行を使う（RPC は顧客ごとに1行）
 */
export function parseUnrepliedClients(data: unknown): UnrepliedClient[] {
  if (!Array.isArray(data)) return []
  const seen = new Set<string>()
  const result: UnrepliedClient[] = []
  for (const row of data) {
    if (typeof row !== 'object' || row === null) continue
    const record = row as Record<string, unknown>
    const clientId = toNonEmptyString(record.client_id)
    const since = toTimestamp(record.unreplied_since) ?? toTimestamp(record.latest_unreplied_at)
    if (clientId === null || since === null || seen.has(clientId)) continue
    seen.add(clientId)
    result.push({
      client_id: clientId,
      client_name: typeof record.client_name === 'string' ? record.client_name : '',
      profile_image_url: toNonEmptyString(record.profile_image_url),
      unreplied_since: since,
      latest_unreplied_at: toTimestamp(record.latest_unreplied_at) ?? since,
      unreplied_count: toUnrepliedCount(record.unreplied_count),
    })
  }
  return result
}

/**
 * 未返信の顧客（RPC get_unreplied_clients_for_trainer）を取得する。
 *
 * - 引数なし。trainer_id を渡さず、RPC（SECURITY INVOKER）と messages / clients の RLS で本人の範囲に絞る
 * - 並び順は buildTriageRows（triageScore）が決めるので、ここでは並べない
 * - 失敗（migration 未適用を含む）は throw する（呼び出し側で「読み込めませんでした」と0件を区別するため）
 */
export async function getUnrepliedClients(): Promise<UnrepliedClient[]> {
  const { data, error } = await supabase.rpc('get_unreplied_clients_for_trainer')

  if (error) {
    console.error('未返信の顧客の取得エラー:', error)
    throw error
  }

  return parseUnrepliedClients(data)
}
