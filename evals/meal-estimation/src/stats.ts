/** 統計ユーティリティ（依存なし・決定的） */

/** mulberry32: 32bit シード付き PRNG。戻り値は [0, 1) */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** Fisher–Yates（シード付き、非破壊） */
export function seededShuffle<T>(items: readonly T[], seed: number): T[] {
  const rand = mulberry32(seed)
  const a = items.slice()
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}

export function mean(xs: readonly number[]): number | null {
  if (xs.length === 0) return null
  let s = 0
  for (const x of xs) s += x
  return s / xs.length
}

/** 線形補間の分位点（R type 7 / numpy 既定と同じ）。空なら null */
export function quantile(xs: readonly number[], q: number): number | null {
  if (xs.length === 0) return null
  const s = xs.slice().sort((a, b) => a - b)
  const pos = (s.length - 1) * q
  const lo = Math.floor(pos)
  const hi = Math.ceil(pos)
  return s[lo] + (s[hi] - s[lo]) * (pos - lo)
}

export function median(xs: readonly number[]): number | null {
  return quantile(xs, 0.5)
}

/** 標本標準偏差（n-1）。2 件未満は null */
export function sampleStd(xs: readonly number[]): number | null {
  if (xs.length < 2) return null
  const m = mean(xs) as number
  let s = 0
  for (const x of xs) s += (x - m) ** 2
  return Math.sqrt(s / (xs.length - 1))
}

/** 変動係数（標本 SD / 平均）。平均 <= 0 や 2 件未満は null */
export function coefficientOfVariation(xs: readonly number[]): number | null {
  const m = mean(xs)
  const sd = sampleStd(xs)
  if (m === null || sd === null || m <= 0) return null
  return sd / m
}

export interface BootstrapCI {
  estimate: number
  lo: number
  hi: number
  n: number
  resamples: number
  seed: number
}

/**
 * ケース単位のパーセンタイル・ブートストラップ 95% CI。
 * stat は値の配列から統計量を返す関数（median / mean など）。
 */
export function bootstrapCI(
  values: readonly number[],
  stat: (xs: number[]) => number | null,
  { resamples = 2000, seed = 20261009, alpha = 0.05 } = {},
): BootstrapCI | null {
  const n = values.length
  if (n === 0) return null
  const estimate = stat(values.slice())
  if (estimate === null) return null
  const rand = mulberry32(seed)
  const stats: number[] = []
  const buf = new Array<number>(n)
  for (let b = 0; b < resamples; b++) {
    for (let i = 0; i < n; i++) buf[i] = values[Math.floor(rand() * n)]
    const s = stat(buf)
    if (s !== null) stats.push(s)
  }
  return {
    estimate,
    lo: quantile(stats, alpha / 2) as number,
    hi: quantile(stats, 1 - alpha / 2) as number,
    n,
    resamples,
    seed,
  }
}
