/**
 * 「今日の対応」の顧客名の呼び方・操作要素のアクセシブルな名前・読み上げの文言（純関数）。
 *
 * - ボタン・リンクの名前には顧客名と種別を入れる（読み上げで、どの顧客のどの操作か分かるように）
 * - 見えている文字を名前に含める（音声操作で、見えているラベルのまま押せるように）
 * - 画面（components/dashboard/Triage*.tsx）とサイドバーのバッジで同じ文言を使う
 * - React や 'use client' に依存させない
 */

import type { DetectionState } from '@/lib/alerts/detectionStatus'

/** 「田中 太郎さん」。名前が空なら「名前未設定の顧客」 */
export function clientHonorific(name: string): string {
  const trimmed = name.trim()
  return trimmed ? `${trimmed}さん` : '名前未設定の顧客'
}

/** 「田中さんの体重の変化を対応済みにする」（見える文字は「対応済みにする」） */
export function acknowledgeButtonLabel(clientName: string, kindLabel: string): string {
  return `${clientHonorific(clientName)}の${kindLabel}を対応済みにする`
}

/** 「田中さんの記録を見る」（見える文字は「記録を見る」） */
export function recordLinkLabel(clientName: string): string {
  return `${clientHonorific(clientName)}の記録を見る`
}

/** 「田中さんにメッセージを送る」（見える文字は「メッセージ」） */
export function messageLinkLabel(clientName: string): string {
  return `${clientHonorific(clientName)}にメッセージを送る`
}

/** 行の開閉ボタン「田中さんの詳細」（見える文字は「詳細」。開閉は aria-expanded で伝える） */
export function detailToggleLabel(clientName: string): string {
  return `${clientHonorific(clientName)}の詳細`
}

/** 「すべて表示（8件）」/ 展開後は「上位5件だけ表示」 */
export function showAllButtonLabel(showAll: boolean, totalCount: number, limit: number): string {
  return showAll ? `上位${limit}件だけ表示` : `すべて表示（${totalCount}件）`
}

/** トースト「対応済みにしました」の補足（「田中さんの体重の変化」） */
export function acknowledgedToastDescription(clientName: string, kindLabel: string): string {
  return `${clientHonorific(clientName)}の${kindLabel}`
}

/** サイドバー「ダッシュボード」のバッジの読み上げ（「今日の対応 3人」） */
export function triageBadgeLabel(count: number): string {
  return `今日の対応 ${count}人`
}

/**
 * 一覧が0件のときの文言。
 * 本実行が一度も成功していなければ「いません」と言い切らない（まだ調べていないだけなので）。
 * 検知状態が分からない（取得失敗・トレーナーでない）ときは、一覧が空であることだけを伝える。
 */
export function triageEmptyMessage(state: DetectionState | null): string {
  if (state !== null && state.lastSucceededAt === null) {
    return '自動チェックの結果はまだありません'
  }
  return '確認が必要な顧客はいません'
}

/** 一覧の件数の読み上げ（aria-live="polite" の領域に入れる） */
export function triageCountAnnouncement(count: number, state: DetectionState | null): string {
  return count > 0 ? `今日の対応は${count}人です` : triageEmptyMessage(state)
}
