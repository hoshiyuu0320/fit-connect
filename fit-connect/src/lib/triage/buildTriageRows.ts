/**
 * 「今日の対応」の行を組み立てる純関数。
 *
 * - 1行 = 1顧客。open のアラート（9.1）と未返信（9.2）を顧客ごとにまとめる。
 *   未返信だけの顧客も1行にする（その行の reasons は空、severity は null）
 * - 行の並び順は優先度スコアの降順（lib/triage/triageScore.ts。同点のときの並びもそちら）
 * - 行の中の理由（アラート）は、重要度の高い順 → surfaced_on の新しい順
 * - サイドバー「ダッシュボード」のバッジは「今日の対応」に並ぶ顧客の数
 *   （open のアラートがある顧客と未返信の顧客の和集合）。数え方をここ1箇所に置き、
 *   getTriageBadgeCount と画面の見出しで同じ定義を使う
 * - サーバーからも import されうるので、React や 'use client' に依存させない
 */

import { describeAlert, normalizeSeverity, severityRank } from '@/lib/alerts/describeAlert'
import {
  compareTriagePriority,
  triageScore,
  unrepliedElapsedHours,
  type TriageSortKey,
} from '@/lib/triage/triageScore'
import type { ClientAlert } from '@/types/alert'
import type {
  TriageReason,
  TriageRowModel,
  TriageUnreplied,
  UnrepliedClient,
} from '@/types/triage'

// 行モデルの型は types/triage.ts に置く（PR1 の import 先を変えずに使えるよう、ここからも出す）
export type { TriageReason, TriageRowModel, TriageUnreplied } from '@/types/triage'

/** 未返信の顧客と、未返信の時間を数える表示時点 */
export type TriageUnrepliedInput = {
  /** getUnrepliedClients の結果 */
  unreplied: readonly UnrepliedClient[]
  /** 表示時点（未返信の時間をここから数える。テストで固定できるよう引数で受ける） */
  now: Date
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

function sortKeyOf(row: TriageRowModel): TriageSortKey {
  return {
    score: row.score,
    unrepliedSince: row.unreplied?.since ?? null,
    firstDetectedOn: row.firstDetectedOn,
    clientName: row.clientName,
    clientId: row.clientId,
  }
}

/**
 * バッジに数える顧客 ID の集合（open のアラートがある顧客と未返信の顧客の和集合）。
 * 渡すアラートは open のものだけにする（getOpenAlerts / getTriageBadgeCount はどちらも open だけを取る）。
 */
export function collectTriageClientIds(
  alerts: ReadonlyArray<Pick<ClientAlert, 'client_id'>>,
  unreplied: ReadonlyArray<Pick<UnrepliedClient, 'client_id'>> = []
): Set<string> {
  const ids = new Set(alerts.map((alert) => alert.client_id))
  for (const client of unreplied) ids.add(client.client_id)
  return ids
}

/** 未返信の行モデル。未返信の時間は表示時点 now から数える（スコアと同じ関数） */
function toUnrepliedModel(client: UnrepliedClient, now: Date): TriageUnreplied {
  return {
    since: client.unreplied_since,
    latestAt: client.latest_unreplied_at,
    count: client.unreplied_count,
    elapsedHours: unrepliedElapsedHours(client.unreplied_since, now),
  }
}

type ClientGroup = {
  alerts: ClientAlert[]
  reasons: TriageReason[]
  /** 未返信と、未返信の時間を数える表示時点 */
  unreplied: { client: UnrepliedClient; now: Date } | null
}

/**
 * open のアラートと未返信の顧客から「今日の対応」の行を作る。
 * - open 以外のアラートが混ざっていても、行にもスコアにもバッジにも入れない
 * - unrepliedInput を省くと、未返信の無い一覧になる（アラートだけのスコアで並べる）
 * - 同じ顧客の未返信が2件来たら最初のものを使う（RPC は顧客ごとに1行）
 */
export function buildTriageRows(
  alerts: readonly ClientAlert[],
  unrepliedInput?: TriageUnrepliedInput
): TriageRowsResult {
  const openAlerts = alerts.filter((alert) => alert.status === 'open')
  const groups = new Map<string, ClientGroup>()
  const groupOf = (clientId: string): ClientGroup => {
    let group = groups.get(clientId)
    if (!group) {
      group = { alerts: [], reasons: [], unreplied: null }
      groups.set(clientId, group)
    }
    return group
  }

  for (const alert of openAlerts) {
    const group = groupOf(alert.client_id)
    group.alerts.push(alert)
    group.reasons.push({
      alertId: alert.id,
      alertType: alert.alert_type,
      severity: normalizeSeverity(alert.severity),
      surfacedOn: alert.surfaced_on,
      firstDetectedOn: alert.first_detected_on,
      description: describeAlert(alert),
    })
  }
  if (unrepliedInput) {
    for (const client of unrepliedInput.unreplied) {
      const group = groupOf(client.client_id)
      if (group.unreplied === null) group.unreplied = { client, now: unrepliedInput.now }
    }
  }

  const rows: TriageRowModel[] = []
  for (const [clientId, group] of groups) {
    const reasons = group.reasons.sort(compareReasons)
    const top = reasons.length > 0 ? reasons[0] : null
    // 顧客名・アバターはアラート（clients の埋め込み）を優先し、未返信だけの行は RPC の値を使う
    const firstAlert = group.alerts.length > 0 ? group.alerts[0] : null
    const unreplied = group.unreplied?.client ?? null
    const unrepliedModel: TriageUnreplied | null =
      group.unreplied === null ? null : toUnrepliedModel(group.unreplied.client, group.unreplied.now)
    const firstDetectedOn = reasons.reduce<string | null>(
      (oldest, reason) =>
        oldest === null || compareAsc(reason.firstDetectedOn, oldest) < 0
          ? reason.firstDetectedOn
          : oldest,
      null
    )

    rows.push({
      clientId,
      clientName: firstAlert?.client_name ?? unreplied?.client_name ?? '',
      profileImageUrl: firstAlert
        ? firstAlert.client_profile_image_url
        : (unreplied?.profile_image_url ?? null),
      severity: top?.severity ?? null,
      surfacedOn: top?.surfacedOn ?? null,
      firstDetectedOn,
      reasons,
      unreplied: unrepliedModel,
      recordTab: top?.description.tab ?? 'summary',
      score: triageScore({
        alerts: group.alerts,
        unreplied:
          group.unreplied === null
            ? null
            : { since: group.unreplied.client.unreplied_since, now: group.unreplied.now },
      }),
    })
  }
  rows.sort((a, b) => compareTriagePriority(sortKeyOf(a), sortKeyOf(b)))

  return {
    rows,
    badgeClientIds: collectTriageClientIds(openAlerts, unrepliedInput?.unreplied ?? []),
  }
}
