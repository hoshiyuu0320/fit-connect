/**
 * 「今日の対応」の行を組み立てる純関数。
 *
 * - 1行 = 1顧客。open のアラートを顧客ごとにまとめ、理由（アラート）を並べる
 * - 行の並び順: 最大の重要度 → surfaced_on の新しい順 → 顧客名 → 顧客 ID（安定させるため）
 *   行の重要度・surfaced_on は、行の先頭の理由（最も重要度が高く、その中で最も新しいもの）で決める
 * - サイドバー「ダッシュボード」のバッジは「今日の対応」に並ぶ顧客の数。
 *   数え方をここ1箇所に置き、getTriageBadgeCount と画面の見出しで同じ定義を使う
 *   （PR2 で未返信の顧客を合流させるときもここを広げる）
 * - サーバーからも import されうるので、React や 'use client' に依存させない
 */

import {
  describeAlert,
  normalizeSeverity,
  severityRank,
  type AlertDescription,
  type AlertRecordTab,
} from '@/lib/alerts/describeAlert'
import type { AlertSeverity, ClientAlert } from '@/types/alert'

/** 行の中の理由（アラート1件） */
export type TriageReason = {
  alertId: string
  alertType: string
  severity: AlertSeverity
  surfacedOn: string
  firstDetectedOn: string
  description: AlertDescription
}

/** 「今日の対応」の1行（1顧客） */
export type TriageRowModel = {
  clientId: string
  clientName: string
  profileImageUrl: string | null
  /** 行の重要度（先頭の理由の重要度 = 顧客の最大の重要度） */
  severity: AlertSeverity
  /** 先頭の理由の surfaced_on（並び順に使う） */
  surfacedOn: string
  /** 重要度の高い順 → surfaced_on の新しい順 */
  reasons: TriageReason[]
  /** 主ボタン「記録を見る」の遷移先タブ（先頭の理由のタブ） */
  recordTab: AlertRecordTab
}

export type TriageRowsResult = {
  rows: TriageRowModel[]
  /** バッジ用の顧客 ID 集合（size がバッジの数） */
  badgeClientIds: Set<string>
}

/** 文字列の昇順（'YYYY-MM-DD' はこれで日付順になる） */
function compareAsc(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0
}

/** 重要度の高い順 → surfaced_on の新しい順 → alert id（安定させるため） */
function compareReasons(a: TriageReason, b: TriageReason): number {
  return (
    severityRank(b.severity) - severityRank(a.severity) ||
    compareAsc(b.surfacedOn, a.surfacedOn) ||
    compareAsc(a.alertId, b.alertId)
  )
}

/** 最大の重要度 → surfaced_on の新しい順 → 顧客名 → 顧客 ID */
function compareRows(a: TriageRowModel, b: TriageRowModel): number {
  return (
    severityRank(b.severity) - severityRank(a.severity) ||
    compareAsc(b.surfacedOn, a.surfacedOn) ||
    a.clientName.localeCompare(b.clientName, 'ja') ||
    compareAsc(a.clientId, b.clientId)
  )
}

/**
 * バッジに数える顧客 ID の集合。
 * PR1 は open のアラートがある顧客（getOpenAlerts / getTriageBadgeCount はどちらも open だけを取る）。
 */
export function collectTriageClientIds(
  alerts: ReadonlyArray<Pick<ClientAlert, 'client_id'>>
): Set<string> {
  return new Set(alerts.map((alert) => alert.client_id))
}

/** open のアラートから「今日の対応」の行を作る。open 以外の行が混ざっていても数えない */
export function buildTriageRows(alerts: readonly ClientAlert[]): TriageRowsResult {
  const openAlerts = alerts.filter((alert) => alert.status === 'open')
  const byClient = new Map<string, { alert: ClientAlert; reasons: TriageReason[] }>()

  for (const alert of openAlerts) {
    const reason: TriageReason = {
      alertId: alert.id,
      alertType: alert.alert_type,
      severity: normalizeSeverity(alert.severity),
      surfacedOn: alert.surfaced_on,
      firstDetectedOn: alert.first_detected_on,
      description: describeAlert(alert),
    }
    const group = byClient.get(alert.client_id)
    if (group) {
      group.reasons.push(reason)
    } else {
      byClient.set(alert.client_id, { alert, reasons: [reason] })
    }
  }

  const rows: TriageRowModel[] = []
  for (const [clientId, { alert, reasons }] of byClient) {
    reasons.sort(compareReasons)
    const top = reasons[0]
    rows.push({
      clientId,
      clientName: alert.client_name,
      profileImageUrl: alert.client_profile_image_url,
      severity: top.severity,
      surfacedOn: top.surfacedOn,
      reasons,
      recordTab: top.description.tab,
    })
  }
  rows.sort(compareRows)

  return { rows, badgeClientIds: collectTriageClientIds(openAlerts) }
}
