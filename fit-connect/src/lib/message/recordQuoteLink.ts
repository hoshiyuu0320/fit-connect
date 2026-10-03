// /message?clientId=…&record=<ref> の <ref> の型と、リンクを組み立てる部分（依存なし）。
// 文法・解釈（parseRecordQuoteRef）・取得範囲は recordQuoteRef.ts にあり、そちらから再 export している。
// lib/alerts/describeAlert.ts は (user_console)/layout.tsx から triageLabels → detectionStatus 経由で
// 全ページに読み込まれるので、date-fns を読む recordQuoteRef.ts ではなくこちらを import する。

export type RecordQuoteRef =
  | { kind: 'sleep_night'; date: string } // 'yyyy-MM-dd'
  | { kind: 'sleep_week' }

/** 直近7日の参照（sleep:7d） */
export const SLEEP_WEEK_PARAM = 'sleep:7d'

export function formatRecordQuoteRef(ref: RecordQuoteRef): string {
  return ref.kind === 'sleep_week' ? SLEEP_WEEK_PARAM : `sleep:${ref.date}`
}

/** 顧客詳細・「今日の対応」→ メッセージ画面のリンク */
export function recordQuoteHref(clientId: string, ref: RecordQuoteRef): string {
  return `/message?clientId=${encodeURIComponent(clientId)}&record=${encodeURIComponent(formatRecordQuoteRef(ref))}`
}
