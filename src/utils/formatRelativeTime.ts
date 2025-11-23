/**
 * タイムスタンプを相対時刻表示に変換
 * 例: "2分前", "1時間前", "11/8 15:30"
 * @param timestamp - ISO形式のタイムスタンプ
 * @returns 相対時刻の文字列
 */
export function formatRelativeTime(timestamp: string): string {
  const now = new Date()
  const date = new Date(timestamp)
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000)

  // 1分未満
  if (diffInSeconds < 60) {
    return 'たった今'
  }

  // 1時間未満
  if (diffInSeconds < 3600) {
    const minutes = Math.floor(diffInSeconds / 60)
    return `${minutes}分前`
  }

  // 24時間未満
  if (diffInSeconds < 86400) {
    const hours = Math.floor(diffInSeconds / 3600)
    return `${hours}時間前`
  }

  // 7日未満
  if (diffInSeconds < 604800) {
    const days = Math.floor(diffInSeconds / 86400)
    return `${days}日前`
  }

  // それ以上は日付表示
  const month = date.getMonth() + 1
  const day = date.getDate()
  const hour = date.getHours().toString().padStart(2, '0')
  const minute = date.getMinutes().toString().padStart(2, '0')

  return `${month}/${day} ${hour}:${minute}`
}
