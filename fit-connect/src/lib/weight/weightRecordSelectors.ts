import type { WeightRecord } from '@/types/client'

// 体重記録の並び順に依存しない純粋ヘルパー群。
// getWeightRecords は古い順（recorded_at 昇順）で返すが、呼び出し側が並び順を
// 前提にすると「最新」を取り違えるため、表示用の値は必ずここを経由して算出する。
// いずれの関数も入力配列を変更しない（React state をそのまま渡してよい）。

const DAY_MS = 24 * 60 * 60 * 1000

// recorded_at をミリ秒に変換（不正な日時は最も古い扱いにして比較を破綻させない）
function toTime(record: WeightRecord): number {
  const t = new Date(record.recorded_at).getTime()
  return Number.isNaN(t) ? Number.NEGATIVE_INFINITY : t
}

// 小数1桁に丸め、-0 は 0 に正規化（page.tsx の既存丸め方と同一）
function round1(value: number): number {
  const rounded = Math.round(value * 10) / 10
  return Object.is(rounded, -0) ? 0 : rounded
}

/** 古い順（recorded_at 昇順）に並べた新しい配列を返す（同時刻は入力順を維持） */
export function sortWeightRecordsChronologically(
  records: readonly WeightRecord[]
): WeightRecord[] {
  return [...records].sort((a, b) => {
    const ta = toTime(a)
    const tb = toTime(b)
    return ta < tb ? -1 : ta > tb ? 1 : 0
  })
}

/** recorded_at が最も新しい記録（空配列なら null） */
export function latestWeightRecord(records: readonly WeightRecord[]): WeightRecord | null {
  let latest: WeightRecord | null = null
  let latestTime = Number.NEGATIVE_INFINITY
  for (const record of records) {
    const t = toTime(record)
    // 同時刻は後勝ち（sortWeightRecordsChronologically の末尾と一致させる）
    if (latest === null || t >= latestTime) {
      latest = record
      latestTime = t
    }
  }
  return latest
}

export type WeightRecordWithChange = {
  record: WeightRecord
  /** 1つ前（より古い）記録との差分 kg。全体で最も古い記録は null */
  change: number | null
}

/**
 * 新しい順に最大 n 件を、直前（1つ古い）記録との差分付きで返す。
 * 差分は全件を対象に計算するため、n 件目も (n+1) 件目が存在すればそれと比較する。
 */
export function recentWeightRecordsWithChange(
  records: readonly WeightRecord[],
  n: number
): WeightRecordWithChange[] {
  const sorted = sortWeightRecordsChronologically(records)
  const count = Math.max(0, Math.min(Math.floor(n), sorted.length))
  const result: WeightRecordWithChange[] = []
  for (let i = 0; i < count; i++) {
    const index = sorted.length - 1 - i
    const record = sorted[index]
    const prev = index > 0 ? sorted[index - 1] : null
    result.push({
      record,
      change: prev ? round1(record.weight - prev.weight) : null,
    })
  }
  return result
}

/**
 * 最新体重と「now から days 日前時点で最も新しい記録」との差（kg、小数1桁）。
 * 最新記録が無い、または基準日以前の記録が無い場合は null。
 */
export function weightChangeSince(
  records: readonly WeightRecord[],
  now: Date,
  days = 30
): number | null {
  const latest = latestWeightRecord(records)
  if (!latest) return null

  const cutoff = now.getTime() - days * DAY_MS
  let baseline: WeightRecord | null = null
  let baselineTime = Number.NEGATIVE_INFINITY
  for (const record of records) {
    const t = toTime(record)
    // 日時が不正な記録は基準に使わない
    if (Number.isFinite(t) && t <= cutoff && (baseline === null || t >= baselineTime)) {
      baseline = record
      baselineTime = t
    }
  }
  if (!baseline) return null

  return round1(latest.weight - baseline.weight)
}
