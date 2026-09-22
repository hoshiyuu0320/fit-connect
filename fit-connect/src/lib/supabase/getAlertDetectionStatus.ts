import { supabase } from '@/lib/supabase'
import { parseAlertDetectionStatus } from '@/lib/alerts/detectionStatus'
import type { AlertDetectionStatus } from '@/types/alert'

/**
 * 自動チェックの検知状態（RPC get_alert_detection_status）を取得する。
 *
 * - 引数なし。人数は呼び出したトレーナー（auth.uid()）の担当顧客だけを、表示した時点で数えたもの
 * - 呼び出したのがトレーナーでなければ0行 → null
 * - 失敗（migration 未適用を含む）は throw する（呼び出し側で取得失敗の表示に分ける）
 */
export async function getAlertDetectionStatus(): Promise<AlertDetectionStatus | null> {
  const { data, error } = await supabase.rpc('get_alert_detection_status')

  if (error) {
    console.error('検知状態の取得エラー:', error)
    throw error
  }

  return parseAlertDetectionStatus(data)
}
