/**
 * 「今日の対応」の顧客名の呼び方・操作要素のアクセシブルな名前・読み上げの文言（純関数）。
 *
 * - ボタン・リンクの名前には顧客名と種別を入れる（読み上げで、どの顧客のどの操作か分かるように）
 * - 見えている文字を名前に含める（音声操作で、見えているラベルのまま押せるように）
 * - 画面（components/dashboard/Triage*.tsx）とサイドバーのバッジで同じ文言を使う
 * - React や 'use client' に依存させない
 */

import { formatJstMonthDayTime, type DetectionState } from '@/lib/alerts/detectionStatus'
import type { TriageUnreplied } from '@/types/triage'

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

/** 未返信のある行の主ボタン「田中さんに返信する」（見える文字は「返信する」） */
export function replyLinkLabel(clientName: string): string {
  return `${clientHonorific(clientName)}に返信する`
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
 * - アラートか未返信のどちらかを読み込めていなければ（incomplete）、読み込めた範囲の話だと断る
 * - 本実行が一度も成功していなければ「いません」と言い切らない（まだ調べていないだけなので）
 * - 検知状態が分からない（取得失敗・トレーナーでない）ときは、一覧が空であることだけを伝える
 */
export function triageEmptyMessage(state: DetectionState | null, incomplete = false): string {
  if (incomplete) {
    return '読み込めた範囲では、確認が必要な顧客はいません'
  }
  if (state !== null && state.lastSucceededAt === null) {
    return '自動チェックの結果はまだありません'
  }
  return '確認が必要な顧客はいません'
}

/** 一覧の件数の読み上げ（aria-live="polite" の領域に入れる） */
export function triageCountAnnouncement(
  count: number,
  state: DetectionState | null,
  incomplete = false
): string {
  return count > 0 ? `今日の対応は${count}人です` : triageEmptyMessage(state, incomplete)
}

// ---------------------------------------------------------------------------
// 未返信（9.2）
// ---------------------------------------------------------------------------

/** これ以上待たせている未返信は、時間でなく日数で出す（「47時間」の次は「2日」） */
export const UNREPLIED_DAYS_FROM_HOURS = 48

/**
 * 未返信の時間の表示（「1時間未満」「18時間」「2日」。どれも切り捨て）。
 * 時間は表示時点で数えたもの（TriageUnreplied.elapsedHours）を受け取り、ここでは計算しない。
 * RPC は最新の未返信が7日以内の顧客を返すが、最も古い未返信は7日より前のことがあるので、長いときは日数で出す
 */
export function formatUnrepliedElapsed(elapsedHours: number): string {
  const hours = Number.isFinite(elapsedHours) ? Math.max(0, Math.floor(elapsedHours)) : 0
  if (hours < 1) return '1時間未満'
  if (hours < UNREPLIED_DAYS_FROM_HOURS) return `${hours}時間`
  return `${Math.floor(hours / 24)}日`
}

/** 行の理由のチップ「未返信 18時間・2件」 */
export function unrepliedChipLabel(unreplied: Pick<TriageUnreplied, 'elapsedHours' | 'count'>): string {
  return `未返信 ${formatUnrepliedElapsed(unreplied.elapsedHours)}・${unreplied.count}件`
}

/** 行を開いたときの未返信の見出し */
export const UNREPLIED_DETAIL_TITLE = '未返信のメッセージ'

/**
 * 見出しのヘルプ。サイドバーの「メッセージ」の数（未読）とは定義が違うことと、
 * RPC が最新の未返信から7日で外すこと（古い未返信が黙って一覧に出なくなること）を伝える
 */
export const TRIAGE_HELP_TEXT =
  '未返信 = 最後のメッセージが顧客からで、まだ返信していないもの（記録の投稿は含みません）。最後に届いた未返信から7日たつと、返信していなくても一覧に出なくなります。サイドバーの「メッセージ」の数は未読の数なので、一致しないことがあります。'

const JST_OFFSET_MS = 9 * 60 * 60 * 1000

/** 時刻を JST の「H:mm」にする。読めなければ null */
function formatJstTime(date: Date): string | null {
  const ms = date.getTime()
  if (Number.isNaN(ms)) return null
  const jst = new Date(ms + JST_OFFSET_MS)
  return `${jst.getUTCHours()}:${String(jst.getUTCMinutes()).padStart(2, '0')}`
}

/**
 * 見出しの横の判定の時点。
 * 未返信は取得した時刻（fetchedAt）を出す。開いたままの画面で、表示が古くなっていることに気づけるように
 * （未返信の時間と並び順は取得した時点で数えたもので、タブに戻るか再読み込みするまで進まない）。
 * まだ取得できていなければ「表示した時点」とだけ書く
 */
export function triageTimingNote(unrepliedFetchedAt: Date | null): string {
  const time = unrepliedFetchedAt === null ? null : formatJstTime(unrepliedFetchedAt)
  return time === null
    ? '未返信は表示した時点、アラートは 6:00 時点の判定'
    : `未返信は ${time} 時点、アラートは 6:00 時点の判定`
}

/**
 * 行を開いたときの未返信の注記。
 * open のアラートもある行は、返信しても未返信の表示が消えるだけで、行はアラートの分で一覧に残る
 */
export function unrepliedDetailNote(hasAlerts: boolean): string {
  return hasAlerts
    ? '返信すると、未返信の表示は消えます（アラートがあるため、この顧客は一覧に残ります）'
    : '返信すると、この一覧から外れます'
}

/**
 * 行を開いたときの未返信の詳細文（時刻は JST の「M/D H:mm」）。
 * - 1件:「9/20 14:05 に届いたメッセージに、まだ返信していません」
 * - 2件以上:「9/20 14:05 以降に届いた2件のメッセージに、まだ返信していません（最新は 9/21 9:12）」
 * - 時刻が読めなければ、時刻を省いて件数だけを伝える
 */
export function unrepliedDetailText(
  unreplied: Pick<TriageUnreplied, 'since' | 'latestAt' | 'count'>
): string {
  const since = formatJstMonthDayTime(unreplied.since)
  const latest = formatJstMonthDayTime(unreplied.latestAt)
  if (unreplied.count <= 1) {
    return since === null
      ? '届いたメッセージに、まだ返信していません'
      : `${since} に届いたメッセージに、まだ返信していません`
  }
  const head =
    since === null
      ? `届いた${unreplied.count}件のメッセージに、まだ返信していません`
      : `${since} 以降に届いた${unreplied.count}件のメッセージに、まだ返信していません`
  return latest === null || latest === since ? head : `${head}（最新は ${latest}）`
}
