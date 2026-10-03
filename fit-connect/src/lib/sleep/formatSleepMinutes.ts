/**
 * 分 → 'H時間M分'（ゼロ埋めなし。分が 0 なら 'H時間'、60分未満は 'M分'）。負の数は 0 に丸める。
 *
 * 依存の無い小さなモジュールに分けてある。lib/alerts/describeAlert.ts が使い、describeAlert は
 * (user_console)/layout.tsx から triageLabels → detectionStatus 経由で全ページに読み込まれるため、
 * date-fns とロケールを読む sleepQuote.ts を経由させない（sleepQuote.ts はこれを再 export する）
 */
export function formatSleepMinutes(totalMinutes: number): string {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}分`
  return m === 0 ? `${h}時間` : `${h}時間${m}分`
}
