import { supabase } from '@/lib/supabase'
import type { AlertSeverity, AlertStatus, ClientAlert, ClientAlertType } from '@/types/alert'

/** 埋め込みの clients は多対一なので通常はオブジェクトだが、型の上では配列でも来うる */
type EmbeddedClient = { name: string | null; profile_image_url: string | null }

type OpenAlertRow = {
  id: string
  client_id: string
  alert_type: string
  severity: string
  status: string
  payload: unknown
  first_detected_on: string
  surfaced_on: string
  last_detected_on: string
  acknowledged_at: string | null
  reopened_count: number | null
  clients: EmbeddedClient | EmbeddedClient[] | null
}

const OPEN_ALERT_COLUMNS = `
  id,
  client_id,
  alert_type,
  severity,
  status,
  payload,
  first_detected_on,
  surfaced_on,
  last_detected_on,
  acknowledged_at,
  reopened_count,
  clients!inner (
    name,
    profile_image_url
  )
`

/**
 * 「今日の対応」に出す open のアラートを取得する。
 *
 * - trainer_id を引数で受け取らない。絞り込みは RLS（alerts_trainer_select: 本人の行かつ今の担当顧客）に任せる
 * - clients!inner で、見えない顧客（担当替え・退会）の行は落とす
 * - 並び順は buildTriageRows が決めるので、ここでは並べない
 * - 失敗は throw する（呼び出し側で「読み込めませんでした」と空の一覧を区別するため）
 * - 未知の種別・壊れた payload の行も落とさずに返す（表示は describeAlert が汎用の文言に落とす）
 */
export async function getOpenAlerts(): Promise<ClientAlert[]> {
  const { data, error } = await supabase
    .from('alerts')
    .select(OPEN_ALERT_COLUMNS)
    .eq('status', 'open')

  if (error) {
    console.error('アラート取得エラー:', error)
    throw error
  }

  return ((data ?? []) as unknown as OpenAlertRow[]).map((row) => {
    const client = Array.isArray(row.clients) ? row.clients[0] : row.clients
    return {
      id: row.id,
      client_id: row.client_id,
      alert_type: row.alert_type as ClientAlertType,
      severity: row.severity as AlertSeverity,
      status: row.status as AlertStatus,
      payload: row.payload,
      first_detected_on: row.first_detected_on,
      surfaced_on: row.surfaced_on,
      last_detected_on: row.last_detected_on,
      acknowledged_at: row.acknowledged_at,
      reopened_count: row.reopened_count ?? 0,
      client_name: client?.name ?? '',
      client_profile_image_url: client?.profile_image_url ?? null,
    }
  })
}
