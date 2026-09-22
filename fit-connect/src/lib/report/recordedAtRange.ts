// ================================================
// レポート期間 → recorded_at（timestamptz）フィルタ用の境界値ヘルパー
// ================================================

const DATE_ONLY_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/

/**
 * 終了日（'yyyy-MM-dd'）の翌日を 'yyyy-MM-dd' で返す。
 *
 * timestamptz の recorded_at を `.lte('recorded_at', endDate)` でフィルタすると、
 * 素の日付は「endDate 00:00 UTC」に変換されるため、終了日当日 00:00 UTC（JST 9:00）以降の記録が
 * 丸ごと除外されてしまう。代わりに `.lt('recorded_at', exclusiveEndDate(endDate))` とすることで、
 * 個別分析ビュー（`recorded_at.split('T')[0] <= endDate`）と同じく UTC の終了日を丸ごと含める。
 *
 * 実行環境のローカルタイムゾーンに左右されないよう、日付計算はすべて UTC で行う。
 * （Date.UTC は 0〜99 年を 1900 年代に読み替えるため setUTCFullYear を使う）
 *
 * @throws 'yyyy-MM-dd' 形式でない、または実在しない日付（2026-02-30 など）の場合
 */
export function exclusiveEndDate(endDate: string): string {
  const match = DATE_ONLY_PATTERN.exec(endDate)
  if (!match) {
    throw new Error(`exclusiveEndDate: 'yyyy-MM-dd' 形式の日付を指定してください（受け取った値: "${endDate}"）`)
  }

  const year = Number(match[1])
  const monthIndex = Number(match[2]) - 1
  const day = Number(match[3])

  const date = new Date(0)
  date.setUTCFullYear(year, monthIndex, day)

  // 実在しない日付は Date が自動で繰り上げてしまうため、往復して一致するか確認する
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== monthIndex ||
    date.getUTCDate() !== day
  ) {
    throw new Error(`exclusiveEndDate: 実在しない日付です（受け取った値: "${endDate}"）`)
  }

  date.setUTCDate(date.getUTCDate() + 1)
  return formatUtcDate(date)
}

/** Date を UTC の暦日で 'yyyy-MM-dd' に整形する */
function formatUtcDate(date: Date): string {
  const yyyy = String(date.getUTCFullYear()).padStart(4, '0')
  const mm = String(date.getUTCMonth() + 1).padStart(2, '0')
  const dd = String(date.getUTCDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}
