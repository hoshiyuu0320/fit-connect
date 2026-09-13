/**
 * セッション前日リマインダーの通知本文を組み立てる純関数群と、対象日（target_date）の入力検証。
 *
 * sessions.session_date は timestamptz（PostgREST 経由では ISO 8601 文字列で届く）。
 * 表示は JST 固定。quiet_hours.ts の JST_OFFSET_MS を共有し、+9h の手計算で JST 暦を得る
 * （タイムゾーンDB不要・DST無しの JST 前提）。
 * send-session-reminders（Edge Function）から利用する。
 * 副作用ゼロの純関数として切り出し、単体テスト（session_reminder_format_test.ts）を可能にしている。
 */

import { JST_OFFSET_MS } from './quiet_hours.ts'

/** 曜日の日本語1文字表記（getUTCDay() の 0=日曜 に対応） */
const JA_WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土'] as const

/** target_date として受理する書式（ゼロ埋め必須。区切りは '-' のみ。時刻・前後の空白は不可） */
const TARGET_DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/

/**
 * Date / ISO 文字列を「+9h シフトした Date」に変換する。
 * シフト後の getUTC* が JST のローカル年月日・時分・曜日を表す
 * （estimate-meal-nutrition の jstMonthStartIso と同じ手法）。
 * 解析できない値は例外を投げる（呼び出し元が1件ごとに try/catch する前提。
 * 日付の無いリマインダーを黙って送るより失敗として残す方が安全）。
 */
function toJstShifted(value: Date | string): Date {
  const ms = value instanceof Date ? value.getTime() : new Date(value).getTime()
  if (Number.isNaN(ms)) {
    throw new Error(`Invalid session date: ${String(value)}`)
  }
  return new Date(ms + JST_OFFSET_MS)
}

/**
 * JST の暦日を 'YYYY-MM-DD' で返す（対象日の表記用。dedup_key と同じ書式）。
 */
export function formatJstDate(value: Date | string): string {
  const jst = toJstShifted(value)
  const y = jst.getUTCFullYear()
  const m = String(jst.getUTCMonth() + 1).padStart(2, '0')
  const d = String(jst.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

/**
 * JST の日時を '9月13日(日) 18:00' 形式で返す。
 * 月日はゼロ埋めなし・時刻は HH:mm（Mobile の formatSessionDateTime と同じ 'M月d日(曜) HH:mm'。
 * Web のセッション表示 'M月d日 (E)' とは曜日前のスペース有無が異なる）。
 */
export function formatJstDateTime(value: Date | string): string {
  const jst = toJstShifted(value)
  const month = jst.getUTCMonth() + 1
  const day = jst.getUTCDate()
  const weekday = JA_WEEKDAYS[jst.getUTCDay()]
  const hh = String(jst.getUTCHours()).padStart(2, '0')
  const mm = String(jst.getUTCMinutes()).padStart(2, '0')
  return `${month}月${day}日(${weekday}) ${hh}:${mm}`
}

/**
 * リマインダー本文を組み立てる。
 *
 * 例: '9月13日(日) 18:00 から 山田 トレーナーとのセッションがあります'
 * trainer_name が NULL / 空（空白のみ含む）のときは名前を省き
 * '… から トレーナーとのセッションがあります' に落とす。
 *
 * @param sessionDate sessions.session_date（timestamptz。Date か ISO 8601 文字列）
 * @param trainerName trainers.name（NULL 可）
 */
export function formatSessionReminderBody(sessionDate: Date | string, trainerName: string | null): string {
  const when = formatJstDateTime(sessionDate)
  const name = trainerName?.trim() ?? ''
  const who = name.length > 0 ? `${name} トレーナー` : 'トレーナー'
  return `${when} から ${who}とのセッションがあります`
}

/**
 * Edge Function の body.target_date を検証し、正規化した 'YYYY-MM-DD' を返す。
 *
 * 受理するのは文字列かつ /^\d{4}-\d{2}-\d{2}$/ に一致し、実在する日付のみ
 * （'tomorrow' / '2026/09/13' / '2026-09-13 12:34' / '2026-02-30' / 数値などは null）。
 * 書式が固定なので正規化後の値は入力と同じ文字列になる（dedup_key・SQL 関数の date 引数と同書式）。
 * 実在判定は Date の繰り上げ（setUTCFullYear で 2月30日 → 3月2日 に化ける）を利用し、
 * 組み立て直した年月日が入力と一致するかで行う
 * （Date.UTC ではなく setUTCFullYear を使うのは 0〜99 年が 1900 年代に化けるのを避けるため）。
 *
 * @param input body.target_date（型不明の生値）
 * @returns 正規化した 'YYYY-MM-DD'。不正なら null（呼び出し元は 400 を返す）
 */
export function parseTargetDate(input: unknown): string | null {
  if (typeof input !== 'string') return null
  const m = TARGET_DATE_RE.exec(input)
  if (!m) return null
  const year = Number(m[1])
  const month = Number(m[2])
  const day = Number(m[3])
  const utc = new Date(0)
  utc.setUTCFullYear(year, month - 1, day)
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) {
    return null
  }
  return input
}
