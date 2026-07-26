/**
 * quiet hours（通知抑制時間帯）判定の純関数群。
 *
 * notification_preferences.quiet_hours_start / quiet_hours_end は
 * Postgres の time 型（JST 解釈）で、PostgREST 経由では 'HH:MM:SS' 文字列で届く。
 * push.ts（統一通知ディスパッチャ）から利用する。
 * 副作用ゼロの純関数として切り出し、単体テスト（quiet_hours_test.ts）を可能にしている。
 */

const SECONDS_PER_DAY = 24 * 60 * 60
const JST_OFFSET_MS = 9 * 60 * 60 * 1000

/**
 * 'HH:MM' / 'HH:MM:SS' 形式の時刻文字列を「0時からの経過秒数」に変換する。
 * 解析できない場合は null。
 */
export function parseTimeToSeconds(time: string): number | null {
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?/.exec(time)
  if (!m) return null
  const hours = parseInt(m[1], 10)
  const minutes = parseInt(m[2], 10)
  const seconds = m[3] ? parseInt(m[3], 10) : 0
  if (hours > 23 || minutes > 59 || seconds > 59) return null
  return hours * 3600 + minutes * 60 + seconds
}

/**
 * 現在時刻（JST）の「0時からの経過秒数」を返す。
 * epoch は UTC 0時起点なので、+9h して 1日で剰余を取れば JST の時刻になる
 * （タイムゾーンDB不要・DST無しの JST 前提）。
 */
export function jstSecondsOfDay(now: Date = new Date()): number {
  return Math.floor((now.getTime() + JST_OFFSET_MS) / 1000) % SECONDS_PER_DAY
}

/**
 * 現在時刻が quiet hours の範囲内かを判定する。
 *
 * - start < end: [start, end) の半開区間（start 含む・end 含まず）
 * - start > end: 日跨ぎレンジ。「start〜24:00」+「00:00〜end」の和集合
 * - start === end: 空区間として常に false（終日抑制の意図には使わない）
 * - 解析不能な文字列: false（通知を握りつぶさない安全側に倒す）
 *
 * @param start quiet_hours_start（'HH:MM:SS'、JST）
 * @param end   quiet_hours_end（'HH:MM:SS'、JST）
 * @param nowSeconds 現在時刻の JST 0時からの経過秒数（jstSecondsOfDay() の戻り値）
 */
export function isWithinQuietHours(start: string, end: string, nowSeconds: number): boolean {
  const s = parseTimeToSeconds(start)
  const e = parseTimeToSeconds(end)
  if (s === null || e === null) return false
  if (s === e) return false
  if (s < e) {
    return nowSeconds >= s && nowSeconds < e
  }
  // 日跨ぎ: start〜24:00 + 00:00〜end
  return nowSeconds >= s || nowSeconds < e
}
