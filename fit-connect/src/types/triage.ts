/**
 * フェーズ9.2 デイリートリアージ（ダッシュボード「今日の対応」）の型。
 *
 * - 1行 = 1顧客。理由は open のアラート（9.1。types/alert.ts）と未返信（9.2）の2種類
 * - 並び順は lib/triage/triageScore.ts の優先度スコア（画面には数値を出さない）
 * - 行の組み立ては lib/triage/buildTriageRows.ts（このファイルは型だけを持つ）
 */

import type { AlertDescription, AlertRecordTab } from '@/lib/alerts/describeAlert'
import type { AlertSeverity } from '@/types/alert'

// ---------------------------------------------------------------------------
// RPC get_unreplied_clients_for_trainer()
// ---------------------------------------------------------------------------

/**
 * RPC get_unreplied_clients_for_trainer() の1行（getUnrepliedClients が型に揃えたもの）。
 *
 * 未返信 = 今の担当顧客から自分宛てに届いたタグ無しのメッセージのうち、
 * トレーナーがその顧客に最後に送ったメッセージより後のもの。最新の未返信が7日以内の顧客だけが返る。
 * 絞り込みは RPC（SECURITY INVOKER）と RLS が行い、trainer_id は引数で渡さない。
 */
export type UnrepliedClient = {
  client_id: string
  client_name: string
  profile_image_url: string | null
  /** 未返信のうち最も古いメッセージの送信時刻（ISO）。未返信の時間はここから数える */
  unreplied_since: string
  /** 未返信のうち最も新しいメッセージの送信時刻（ISO） */
  latest_unreplied_at: string
  /** 未返信の件数（1以上） */
  unreplied_count: number
}

// ---------------------------------------------------------------------------
// 「今日の対応」の行
// ---------------------------------------------------------------------------

/** 行の中の理由（open のアラート1件） */
export type TriageReason = {
  alertId: string
  alertType: string
  severity: AlertSeverity
  surfacedOn: string
  firstDetectedOn: string
  description: AlertDescription
}

/** 行の未返信（表示時点で数えたもの） */
export type TriageUnreplied = {
  /** 未返信のうち最も古いメッセージの送信時刻（ISO） */
  since: string
  /** 未返信のうち最も新しいメッセージの送信時刻（ISO） */
  latestAt: string
  /** 未返信の件数 */
  count: number
  /**
   * 表示時点（buildTriageRows に渡した now）での未返信の時間。時間単位で切り捨て、0以上。
   * スコアの計算と「未返信 18時間」の表示で同じ値を使う（lib/triage/triageScore.ts の unrepliedElapsedHours）
   */
  elapsedHours: number
}

/** 「今日の対応」の1行（1顧客） */
export type TriageRowModel = {
  clientId: string
  clientName: string
  profileImageUrl: string | null
  /** 行の重要度（open のアラートの最大の重要度 = 先頭の理由の重要度）。未返信だけの行は null */
  severity: AlertSeverity | null
  /** 先頭の理由の surfaced_on。未返信だけの行は null */
  surfacedOn: string | null
  /** open のアラートのうち最も古い first_detected_on（同点のときの並びに使う）。未返信だけの行は null */
  firstDetectedOn: string | null
  /** open のアラート（重要度の高い順 → surfaced_on の新しい順）。未返信だけの行は空 */
  reasons: TriageReason[]
  /** 未返信。未返信が無い顧客の行は null */
  unreplied: TriageUnreplied | null
  /** 「記録を見る」の遷移先タブ（先頭の理由のタブ。未返信だけの行は summary） */
  recordTab: AlertRecordTab
  /**
   * 優先度スコア（lib/triage/triageScore.ts）。並べるためだけに使い、画面には出さない
   * （見かけの精度を持たせない。計画書 Web UI > PR2）
   */
  score: number
}
