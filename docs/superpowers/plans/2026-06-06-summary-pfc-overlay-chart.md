# サマリータブ 体重×PFCオーバーレイ統合 + PFC構成比カード Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** クライアント詳細「サマリー」タブの重複した体重グラフを一本化し、体重×PFCオーバーレイグラフとPFC構成比カードの2部構成に再編する。

**Architecture:** 既存の `aggregateDailyNutrition`（日次集計）を流用。新規の純関数 `computePfcBalance` で構成比・適正判定を算出（vitestで単体テスト）。表示は新規 `WeightNutritionChart`（recharts ComposedChart）と `PfcBalanceCard`（recharts PieChart + divバー）。`SummaryTab` で期間stateを1つに共通化し両者へ渡す。旧 `NutritionTrendChart` は削除。

**Tech Stack:** Next.js 15 (App Router), TypeScript, Tailwind CSS, recharts, date-fns, lucide-react, vitest（純関数テスト用に新規導入）。

**参照スペック:** `docs/superpowers/specs/2026-06-06-summary-pfc-overlay-chart-design.md`

**作業ディレクトリ:** すべて `fit-connect/`（Web）配下。コマンドは `fit-connect/` で実行。

---

## File Structure

- Create: `fit-connect/vitest.config.ts` — vitest 設定（`@/` エイリアス解決）
- Modify: `fit-connect/package.json` — devDep `vitest` + `test` スクリプト
- Create: `fit-connect/src/lib/nutrition/pfcBalance.ts` — PFC構成比・適正判定の純関数 + 既定目安
- Create: `fit-connect/src/lib/nutrition/__tests__/pfcBalance.test.ts` — 純関数の単体テスト
- Create: `fit-connect/src/hooks/usePrefersReducedMotion.ts` — reduced-motion 検知フック
- Create: `fit-connect/src/components/clients/WeightNutritionChart.tsx` — 体重×PFCオーバーレイグラフ
- Create: `fit-connect/src/components/clients/PfcBalanceCard.tsx` — PFC構成比カード（ドーナツ + あすけん風バー）
- Modify: `fit-connect/src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx` — レイアウト統合・期間共通化
- Delete: `fit-connect/src/components/clients/NutritionTrendChart.tsx` — 統合により不要

---

## Task 1: vitest セットアップ（純関数テスト基盤）

**Files:**
- Modify: `fit-connect/package.json`
- Create: `fit-connect/vitest.config.ts`

- [ ] **Step 1: vitest をインストール**

Run（`fit-connect/` で実行）:
```bash
npm install -D vitest
```
Expected: `package.json` の devDependencies に `vitest` が追加される。

- [ ] **Step 2: `package.json` に test スクリプトを追加**

`scripts` を以下に変更（既存 dev/build/start/lint は残す）:
```json
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run",
    "test:watch": "vitest"
  },
```

- [ ] **Step 3: `vitest.config.ts` を作成**

```ts
import { defineConfig } from 'vitest/config'
import { fileURLToPath } from 'node:url'

export default defineConfig({
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    environment: 'node',
  },
})
```

- [ ] **Step 4: 動作確認（テストがまだ無いことを確認）**

Run: `npm test`
Expected: 「No test files found」相当のメッセージで正常終了（exit 0 or 1）。クラッシュしなければOK。

- [ ] **Step 5: Commit**

```bash
git add fit-connect/package.json fit-connect/package-lock.json fit-connect/vitest.config.ts
git commit -m "chore(web): vitest を導入（純関数テスト用）"
```

---

## Task 2: `computePfcBalance` 純関数（TDD）

PFC構成比（エネルギー比%）・1日平均グラム・平均kcal/日・適正判定を算出する純関数。

**Files:**
- Create: `fit-connect/src/lib/nutrition/pfcBalance.ts`
- Test: `fit-connect/src/lib/nutrition/__tests__/pfcBalance.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect/src/lib/nutrition/__tests__/pfcBalance.test.ts`:
```ts
import { describe, it, expect } from 'vitest'
import { computePfcBalance, DEFAULT_PFC_TARGETS } from '@/lib/nutrition/pfcBalance'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'

function pt(over: Partial<DailyNutritionPoint>): DailyNutritionPoint {
  return { date: '2026-05-01', weight: null, calories: 0, protein: 0, fat: 0, carbs: 0, ...over }
}

describe('computePfcBalance', () => {
  it('データが空なら hasData=false', () => {
    const r = computePfcBalance([])
    expect(r.hasData).toBe(false)
    expect(r.avgCaloriesPerDay).toBe(0)
    expect(r.macros.map((m) => m.key)).toEqual(['protein', 'fat', 'carbs'])
  })

  it('全日0なら hasData=false（食事記録のある日0扱い）', () => {
    const r = computePfcBalance([pt({}), pt({ date: '2026-05-02' })])
    expect(r.hasData).toBe(false)
  })

  it('記録のある日だけで平均kcal/日を算出する', () => {
    const points = [
      pt({ date: '2026-05-01', calories: 1800, protein: 100, fat: 60, carbs: 200 }),
      pt({ date: '2026-05-02' }), // 食事なしの日 → 平均の分母に含めない
    ]
    const r = computePfcBalance(points)
    expect(r.hasData).toBe(true)
    expect(r.avgCaloriesPerDay).toBe(1800)
  })

  it('エネルギー比%とステータスを算出する（高/高/低の例）', () => {
    const points = [pt({ calories: 1800, protein: 100, fat: 60, carbs: 200 })]
    // kcal: P400 F540 C800 = 1740 → P22.99% F31.03% C45.98%
    const r = computePfcBalance(points)
    const [p, f, c] = r.macros
    expect(p.ratio).toBeCloseTo(22.99, 1)
    expect(f.ratio).toBeCloseTo(31.03, 1)
    expect(c.ratio).toBeCloseTo(45.98, 1)
    expect(p.status).toBe('high') // 20超
    expect(f.status).toBe('high') // 30超
    expect(c.status).toBe('low') // 50未満
    expect(p.grams).toBe(100)
  })

  it('全て目安内なら optimal', () => {
    const points = [pt({ calories: 1795, protein: 75, fat: 55, carbs: 250 })]
    // kcal: P300 F495 C1000 = 1795 → P16.7% F27.6% C55.7%
    const r = computePfcBalance(points)
    expect(r.macros.every((m) => m.status === 'optimal')).toBe(true)
  })

  it('1日平均グラムは記録日数で割って四捨五入する', () => {
    const points = [
      pt({ date: '2026-05-01', calories: 1000, protein: 90 }),
      pt({ date: '2026-05-02', calories: 1000, protein: 110 }),
    ]
    const r = computePfcBalance(points)
    expect(r.macros[0].grams).toBe(100) // (90+110)/2
  })

  it('既定の目安レンジは厚労省基準相当', () => {
    expect(DEFAULT_PFC_TARGETS.protein).toEqual({ lo: 13, hi: 20 })
    expect(DEFAULT_PFC_TARGETS.fat).toEqual({ lo: 20, hi: 30 })
    expect(DEFAULT_PFC_TARGETS.carbs).toEqual({ lo: 50, hi: 65 })
  })
})
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `npm test`
Expected: FAIL（`pfcBalance` モジュールが存在しない / import エラー）。

- [ ] **Step 3: 純関数を実装**

`fit-connect/src/lib/nutrition/pfcBalance.ts`:
```ts
// ================================================
// PFC構成比・適正判定ユーティリティ（純関数）
// ================================================

import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'

export type MacroKey = 'protein' | 'fat' | 'carbs'

/** エネルギー比（%）の目安レンジ */
export type MacroTarget = { lo: number; hi: number }
export type PfcTargets = Record<MacroKey, MacroTarget>

/** 厚労省 食事摂取基準 相当のエネルギー比目安（既定値） */
export const DEFAULT_PFC_TARGETS: PfcTargets = {
  protein: { lo: 13, hi: 20 },
  fat: { lo: 20, hi: 30 },
  carbs: { lo: 50, hi: 65 },
}

export type MacroStatus = 'low' | 'optimal' | 'high'

export type MacroBalance = {
  key: MacroKey
  grams: number // 1日平均グラム（四捨五入）
  ratio: number // エネルギー比 %（生値・未丸め）
  status: MacroStatus
  target: MacroTarget
}

export type PfcBalance = {
  hasData: boolean
  avgCaloriesPerDay: number // 食事記録のある日の平均（四捨五入）
  macros: MacroBalance[] // protein, fat, carbs の順
}

const KCAL_PER_G: Record<MacroKey, number> = { protein: 4, fat: 9, carbs: 4 }
const MACRO_ORDER: MacroKey[] = ['protein', 'fat', 'carbs']

function statusOf(ratio: number, t: MacroTarget): MacroStatus {
  if (ratio < t.lo) return 'low'
  if (ratio > t.hi) return 'high'
  return 'optimal'
}

/**
 * 日次集計から PFC構成比（エネルギー比）と適正判定を算出する。
 *
 * - 構成比はエネルギー(kcal)比。P×4 / F×9 / C×4 で換算。
 * - 平均kcal/日は「食事記録のある日（calories/PFCいずれか>0）」で割る。
 * - 食事記録のある日が0 or 総kcal0なら hasData=false。
 */
export function computePfcBalance(
  points: DailyNutritionPoint[],
  targets: PfcTargets = DEFAULT_PFC_TARGETS
): PfcBalance {
  const totalG: Record<MacroKey, number> = { protein: 0, fat: 0, carbs: 0 }
  let totalCalories = 0
  let daysWithMeals = 0

  for (const p of points) {
    if (p.calories > 0 || p.protein > 0 || p.fat > 0 || p.carbs > 0) {
      daysWithMeals += 1
    }
    totalG.protein += p.protein
    totalG.fat += p.fat
    totalG.carbs += p.carbs
    totalCalories += p.calories
  }

  const kcal: Record<MacroKey, number> = {
    protein: totalG.protein * KCAL_PER_G.protein,
    fat: totalG.fat * KCAL_PER_G.fat,
    carbs: totalG.carbs * KCAL_PER_G.carbs,
  }
  const totalKcal = kcal.protein + kcal.fat + kcal.carbs

  if (daysWithMeals === 0 || totalKcal === 0) {
    return {
      hasData: false,
      avgCaloriesPerDay: 0,
      macros: MACRO_ORDER.map((key) => ({
        key,
        grams: 0,
        ratio: 0,
        status: 'low',
        target: targets[key],
      })),
    }
  }

  const macros: MacroBalance[] = MACRO_ORDER.map((key) => {
    const ratio = (kcal[key] / totalKcal) * 100
    return {
      key,
      grams: Math.round(totalG[key] / daysWithMeals),
      ratio,
      status: statusOf(ratio, targets[key]),
      target: targets[key],
    }
  })

  return {
    hasData: true,
    avgCaloriesPerDay: Math.round(totalCalories / daysWithMeals),
    macros,
  }
}
```

- [ ] **Step 4: テストを実行して成功を確認**

Run: `npm test`
Expected: PASS（7テスト緑）。

- [ ] **Step 5: Commit**

```bash
git add fit-connect/src/lib/nutrition/pfcBalance.ts fit-connect/src/lib/nutrition/__tests__/pfcBalance.test.ts
git commit -m "feat(web): PFC構成比・適正判定の純関数 computePfcBalance を追加（テスト付き）"
```

---

## Task 3: `usePrefersReducedMotion` フック

rechartsアニメーションを reduced-motion 時に無効化するためのフック。

**Files:**
- Create: `fit-connect/src/hooks/usePrefersReducedMotion.ts`

- [ ] **Step 1: フックを実装**

```ts
'use client'

import { useEffect, useState } from 'react'

/**
 * OSの「視差効果を減らす / reduce motion」設定を検知する。
 * SSRでは false を返し、マウント後に実値へ同期する。
 */
export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    setReduced(mq.matches)
    const handler = (e: MediaQueryListEvent) => setReduced(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])

  return reduced
}
```

- [ ] **Step 2: 型チェック**

Run: `npx tsc --noEmit`
Expected: エラーなし。

- [ ] **Step 3: Commit**

```bash
git add fit-connect/src/hooks/usePrefersReducedMotion.ts
git commit -m "feat(web): prefers-reduced-motion 検知フックを追加"
```

---

## Task 4: `WeightNutritionChart`（体重×PFCオーバーレイグラフ）

体重ライン（青・前面・淡い青エリア）＋目標体重の緑破線を主役に、背面へPFC（kcal換算）の積み上げ棒を淡色で重ねる。左軸=kg / 右軸=kcal。

**Files:**
- Create: `fit-connect/src/components/clients/WeightNutritionChart.tsx`

- [ ] **Step 1: コンポーネントを実装**

`fit-connect/src/components/clients/WeightNutritionChart.tsx`:
```tsx
'use client'

import { useMemo } from 'react'
import { format, parseISO } from 'date-fns'
import { LineChart as LineChartIcon } from 'lucide-react'
import {
  Area,
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import { usePrefersReducedMotion } from '@/hooks/usePrefersReducedMotion'

interface WeightNutritionChartProps {
  data: DailyNutritionPoint[]
  targetWeight: number
  loading?: boolean
}

const COLORS = {
  protein: '#6366F1',
  fat: '#E6B968',
  carbs: '#E294AE',
  weight: '#3B82F6',
  weightArea: 'rgba(59, 130, 246, 0.10)',
  target: '#22C55E',
  grid: '#E2E8F0',
  axis: '#64748B',
} as const

const KCAL = { protein: 4, fat: 9, carbs: 4 } as const

type ChartRow = DailyNutritionPoint & {
  proteinKcal: number
  fatKcal: number
  carbsKcal: number
}

type TooltipPayloadItem = { payload?: ChartRow }
interface ChartTooltipProps {
  active?: boolean
  payload?: TooltipPayloadItem[]
  label?: string
}

function ChartTooltip({ active, payload, label }: ChartTooltipProps) {
  if (!active || !payload || payload.length === 0 || !label) return null
  const point = payload[0]?.payload
  if (!point) return null

  const formattedDate = (() => {
    try {
      return format(parseISO(label), 'yyyy年M月d日')
    } catch {
      return label
    }
  })()

  return (
    <div className="bg-white border border-slate-200 rounded-md p-3 text-xs shadow-sm">
      <div className="font-semibold text-slate-900 mb-1.5">{formattedDate}</div>
      <div className="space-y-0.5">
        <div className="flex items-center justify-between gap-4">
          <span className="text-slate-600">体重</span>
          <span className="font-medium text-slate-900">
            {point.weight !== null ? `${point.weight} kg` : '—'}
          </span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span className="text-slate-600">摂取カロリー</span>
          <span className="font-medium text-slate-900">{point.calories.toLocaleString()} kcal</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.protein }}>P タンパク質</span>
          <span className="font-medium text-slate-900">{point.protein} g</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.fat }}>F 脂質</span>
          <span className="font-medium text-slate-900">{point.fat} g</span>
        </div>
        <div className="flex items-center justify-between gap-4">
          <span style={{ color: COLORS.carbs }}>C 炭水化物</span>
          <span className="font-medium text-slate-900">{point.carbs} g</span>
        </div>
      </div>
    </div>
  )
}

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <LineChartIcon className="w-12 h-12 text-slate-400 mb-3" />
      <p className="font-semibold text-slate-900">データがありません</p>
      <p className="text-sm text-slate-600 mt-1">選択期間に記録された体重・食事がありません</p>
    </div>
  )
}

function LoadingState() {
  return (
    <div className="flex items-center justify-center h-[320px]">
      <div className="w-full h-full bg-slate-50 rounded-md animate-pulse" />
    </div>
  )
}

export function WeightNutritionChart({ data, targetWeight, loading = false }: WeightNutritionChartProps) {
  const reducedMotion = usePrefersReducedMotion()

  const chartData = useMemo<ChartRow[]>(
    () =>
      data.map((d) => ({
        ...d,
        proteinKcal: Math.round(d.protein * KCAL.protein),
        fatKcal: Math.round(d.fat * KCAL.fat),
        carbsKcal: Math.round(d.carbs * KCAL.carbs),
      })),
    [data]
  )

  const weightDomain = useMemo<[number, number]>(() => {
    const weights = data
      .map((d) => d.weight)
      .filter((w): w is number => w !== null)
    const all = targetWeight ? [...weights, targetWeight] : weights
    if (all.length === 0) return [0, 100]
    return [Math.floor(Math.min(...all) - 2), Math.ceil(Math.max(...all) + 2)]
  }, [data, targetWeight])

  if (loading) return <LoadingState />
  if (data.length === 0) return <EmptyState />

  const xTickFormatter = (value: string) => {
    try {
      return format(parseISO(value), 'M/d')
    } catch {
      return value
    }
  }

  return (
    <ResponsiveContainer width="100%" height={320}>
      <ComposedChart data={chartData} margin={{ top: 16, right: 8, left: 0, bottom: 8 }}>
        <CartesianGrid stroke={COLORS.grid} strokeDasharray="3 3" vertical={false} />
        <XAxis
          dataKey="date"
          tickFormatter={xTickFormatter}
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
        />
        {/* 左軸: 体重 kg（主役） */}
        <YAxis
          yAxisId="weight"
          domain={weightDomain}
          tick={{ fill: COLORS.weight, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: '体重 kg',
            angle: -90,
            position: 'insideLeft',
            style: { fill: COLORS.weight, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        {/* 右軸: 摂取 kcal（補助） */}
        <YAxis
          yAxisId="kcal"
          orientation="right"
          tick={{ fill: COLORS.axis, fontSize: 11 }}
          stroke={COLORS.grid}
          tickLine={false}
          label={{
            value: '摂取 kcal',
            angle: 90,
            position: 'insideRight',
            style: { fill: COLORS.axis, fontSize: 11, textAnchor: 'middle' },
          }}
        />
        <Tooltip content={<ChartTooltip />} cursor={{ fill: 'rgba(15, 23, 42, 0.04)' }} />
        <Legend
          align="right"
          verticalAlign="top"
          iconType="circle"
          wrapperStyle={{ fontSize: 12, color: COLORS.axis, paddingBottom: 8 }}
        />
        {/* PFC 積み上げ棒（kcal換算・背面・淡色） */}
        <Bar
          yAxisId="kcal"
          dataKey="proteinKcal"
          name="P (kcal)"
          stackId="pfc"
          fill={COLORS.protein}
          fillOpacity={0.55}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        <Bar
          yAxisId="kcal"
          dataKey="fatKcal"
          name="F (kcal)"
          stackId="pfc"
          fill={COLORS.fat}
          fillOpacity={0.55}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        <Bar
          yAxisId="kcal"
          dataKey="carbsKcal"
          name="C (kcal)"
          stackId="pfc"
          fill={COLORS.carbs}
          fillOpacity={0.55}
          radius={[3, 3, 0, 0]}
          maxBarSize={24}
          isAnimationActive={!reducedMotion}
        />
        {/* 目標体重ライン */}
        {targetWeight ? (
          <ReferenceLine
            yAxisId="weight"
            y={targetWeight}
            stroke={COLORS.target}
            strokeDasharray="5 4"
            label={{ value: `目標 ${targetWeight}kg`, position: 'insideTopLeft', fill: '#16A34A', fontSize: 10 }}
          />
        ) : null}
        {/* 体重エリア（淡い塗り・前面） */}
        <Area
          yAxisId="weight"
          type="monotone"
          dataKey="weight"
          fill={COLORS.weightArea}
          stroke="none"
          connectNulls
          isAnimationActive={!reducedMotion}
        />
        {/* 体重ライン（主役） */}
        <Line
          yAxisId="weight"
          type="monotone"
          dataKey="weight"
          name="体重 (kg)"
          stroke={COLORS.weight}
          strokeWidth={2.5}
          dot={{ r: 3, fill: '#fff', stroke: COLORS.weight, strokeWidth: 2 }}
          activeDot={{ r: 5 }}
          connectNulls
          isAnimationActive={!reducedMotion}
        />
      </ComposedChart>
    </ResponsiveContainer>
  )
}
```

- [ ] **Step 2: 型チェック**

Run: `npx tsc --noEmit`
Expected: エラーなし。

- [ ] **Step 3: Commit**

```bash
git add fit-connect/src/components/clients/WeightNutritionChart.tsx
git commit -m "feat(web): 体重×PFCオーバーレイグラフ WeightNutritionChart を追加"
```

---

## Task 5: `PfcBalanceCard`（PFC構成比カード）

左にドーナツ（構成比% + 中央に平均kcal/日）、右にあすけん風の目安バー（実測%バー + 淡い適正ゾーン + 目標値の縦線 + ▼マーカー + ステータスチップ）。

**Files:**
- Create: `fit-connect/src/components/clients/PfcBalanceCard.tsx`

- [ ] **Step 1: コンポーネントを実装**

`fit-connect/src/components/clients/PfcBalanceCard.tsx`:
```tsx
'use client'

import { useMemo } from 'react'
import { Cell, Pie, PieChart, ResponsiveContainer } from 'recharts'
import { PieChart as PieChartIcon } from 'lucide-react'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import {
  computePfcBalance,
  DEFAULT_PFC_TARGETS,
  type MacroKey,
  type MacroStatus,
  type PfcTargets,
} from '@/lib/nutrition/pfcBalance'
import { usePrefersReducedMotion } from '@/hooks/usePrefersReducedMotion'

interface PfcBalanceCardProps {
  data: DailyNutritionPoint[]
  targets?: PfcTargets
}

const MACRO_META: Record<MacroKey, { label: string; color: string }> = {
  protein: { label: 'たんぱく質', color: '#6366F1' },
  fat: { label: '脂質', color: '#E6B968' },
  carbs: { label: '炭水化物', color: '#E294AE' },
}

const STATUS_META: Record<MacroStatus, { label: string; color: string }> = {
  low: { label: '不足', color: '#2563EB' },
  optimal: { label: '適正', color: '#16A34A' },
  high: { label: '過剰', color: '#EA580C' },
}

const ZONE_COLOR = '#C2E6A8'
const TARGET_LINE = '#2F7D33'
const SCALE_MAX = 70 // バーのx軸上限（%）

function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <PieChartIcon className="w-10 h-10 text-slate-400 mb-3" />
      <p className="font-semibold text-slate-900">データがありません</p>
      <p className="text-sm text-slate-600 mt-1">選択期間に食事の記録がありません</p>
    </div>
  )
}

export function PfcBalanceCard({ data, targets = DEFAULT_PFC_TARGETS }: PfcBalanceCardProps) {
  const reducedMotion = usePrefersReducedMotion()
  const balance = useMemo(() => computePfcBalance(data, targets), [data, targets])

  if (!balance.hasData) return <EmptyState />

  const donutData = balance.macros.map((m) => ({
    key: m.key,
    value: m.ratio,
    color: MACRO_META[m.key].color,
  }))

  return (
    <div className="flex flex-wrap items-center gap-7">
      {/* ドーナツ */}
      <div className="relative" style={{ width: 160, height: 160 }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={donutData}
              dataKey="value"
              nameKey="key"
              cx="50%"
              cy="50%"
              innerRadius={46}
              outerRadius={72}
              startAngle={90}
              endAngle={-270}
              stroke="none"
              isAnimationActive={!reducedMotion}
            >
              {donutData.map((d) => (
                <Cell key={d.key} fill={d.color} />
              ))}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="text-lg font-bold text-slate-900 leading-none">
            {balance.avgCaloriesPerDay.toLocaleString()}
          </span>
          <span className="text-[10px] text-slate-600 mt-1">kcal/日 平均</span>
        </div>
      </div>

      {/* あすけん風 目安バー */}
      <div className="flex-1 min-w-[320px]">
        {balance.macros.map((m) => {
          const meta = MACRO_META[m.key]
          const status = STATUS_META[m.status]
          const actW = Math.min(100, (m.ratio / SCALE_MAX) * 100)
          const mid = (m.target.lo + m.target.hi) / 2
          const midL = (mid / SCALE_MAX) * 100
          const zoneL = (m.target.lo / SCALE_MAX) * 100
          const zoneW = ((m.target.hi - m.target.lo) / SCALE_MAX) * 100
          return (
            <div key={m.key} className="mb-4 last:mb-0">
              <div className="flex items-center gap-2 mb-1.5">
                <span className="text-sm text-slate-700 w-20">{meta.label}</span>
                <span
                  className="text-[11px] font-bold text-white rounded px-1.5 py-px"
                  style={{ backgroundColor: status.color }}
                >
                  {status.label}
                </span>
                <span className="ml-auto text-sm font-bold text-slate-900">
                  {Math.round(m.ratio)}%
                </span>
                <span className="text-[11px] text-slate-600 w-11 text-right">{m.grams}g</span>
              </div>
              <div className="relative h-[18px] bg-slate-100 rounded">
                {/* 適正ゾーン */}
                <div
                  className="absolute top-0 bottom-0 rounded-sm"
                  style={{ left: `${zoneL}%`, width: `${zoneW}%`, backgroundColor: ZONE_COLOR }}
                />
                {/* 目標値の縦線 + ▼マーカー */}
                <div
                  className="absolute"
                  style={{
                    left: `${midL}%`,
                    top: -3,
                    height: 24,
                    width: 3,
                    backgroundColor: TARGET_LINE,
                    transform: 'translateX(-50%)',
                  }}
                />
                <div
                  className="absolute text-[9px] leading-none"
                  style={{ left: `${midL}%`, top: -7, transform: 'translateX(-50%)', color: TARGET_LINE }}
                >
                  ▼
                </div>
                {/* 実測バー */}
                <div
                  className="absolute rounded-sm"
                  style={{ left: 0, width: `${actW}%`, top: 4, bottom: 4, backgroundColor: meta.color }}
                />
              </div>
              <div className="text-[10px] text-slate-600 mt-1">
                適正 {m.target.lo}–{m.target.hi}%
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
```

- [ ] **Step 2: 型チェック**

Run: `npx tsc --noEmit`
Expected: エラーなし。

- [ ] **Step 3: Commit**

```bash
git add fit-connect/src/components/clients/PfcBalanceCard.tsx
git commit -m "feat(web): PFC構成比カード PfcBalanceCard を追加（ドーナツ + あすけん風目安バー）"
```

---

## Task 6: `SummaryTab` 統合（レイアウト再編・期間共通化・旧グラフ削除）

上部カードを `WeightNutritionChart` に置換し、期間セレクタを上部に集約。最下部「栄養トレンド」セクションを `PfcBalanceCard` に置換。旧 `NutritionTrendChart` を削除。

**Files:**
- Modify: `fit-connect/src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx`
- Delete: `fit-connect/src/components/clients/NutritionTrendChart.tsx`

- [ ] **Step 1: import を差し替える**

`SummaryTab.tsx` 冒頭の import を変更:

削除する2行:
```tsx
import { WeightChart } from '@/components/clients/WeightChart'
import { NutritionTrendChart } from '@/components/clients/NutritionTrendChart'
```
追加する2行（同じ位置に）:
```tsx
import { WeightNutritionChart } from '@/components/clients/WeightNutritionChart'
import { PfcBalanceCard } from '@/components/clients/PfcBalanceCard'
```
（`PeriodSelector` の import 行はそのまま残す）

- [ ] **Step 2: 上部カード（体重推移）を統合グラフ + 期間セレクタに置換**

以下の既存ブロック（「体重グラフカード」）:
```tsx
        {/* 体重グラフカード */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <h3 className="text-sm font-semibold text-[#0F172A] mb-3">体重推移</h3>
          {weightRecords.length > 0 ? (
            <WeightChart weightRecords={weightRecords} targetWeight={targetWeight} />
          ) : (
            <div className="flex items-center justify-center h-[200px] bg-[#F8FAFC] rounded-md">
              <p className="text-sm text-[#94A3B8]">体重記録がありません</p>
            </div>
          )}
        </div>
```
を、次に置き換える:
```tsx
        {/* 体重×PFC オーバーレイグラフ + 共通期間セレクタ */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          <div className="flex items-start justify-between gap-4 mb-3 flex-wrap">
            <div>
              <h3 className="text-sm font-semibold text-[#0F172A]">体重推移</h3>
              <p className="text-xs text-slate-600 mt-0.5">体重・摂取カロリー・PFCの推移</p>
            </div>
            <PeriodSelector value={nutritionPeriod} onChange={setNutritionPeriod} />
          </div>
          <WeightNutritionChart data={nutritionTrendData} targetWeight={targetWeight} />
        </div>
```

- [ ] **Step 3: 最下部「栄養トレンド」セクションを PFC構成比カードに置換**

以下の既存ブロック:
```tsx
      {/* 栄養トレンドセクション */}
      <section className="bg-white border border-slate-200 rounded-lg p-6">
        <header className="flex items-start justify-between gap-4 mb-4 flex-wrap">
          <div>
            <h3 className="text-base font-semibold text-slate-900">栄養トレンド</h3>
            <p className="text-sm text-slate-500 mt-0.5">
              体重・摂取カロリー・PFCの推移
            </p>
          </div>
          <PeriodSelector value={nutritionPeriod} onChange={setNutritionPeriod} />
        </header>
        <NutritionTrendChart data={nutritionTrendData} />
      </section>
```
を、次に置き換える（期間セレクタは上部に移動したのでここからは除く）:
```tsx
      {/* PFC構成比セクション */}
      <section className="bg-white border border-slate-200 rounded-lg p-6">
        <header className="mb-4">
          <h3 className="text-base font-semibold text-slate-900">PFC構成比</h3>
          <p className="text-sm text-slate-600 mt-0.5">
            期間平均のエネルギー比と適正バランス（目安: 厚労省 食事摂取基準）
          </p>
        </header>
        <PfcBalanceCard data={nutritionTrendData} />
      </section>
```

- [ ] **Step 4: 旧 NutritionTrendChart を削除**

Run:
```bash
git rm fit-connect/src/components/clients/NutritionTrendChart.tsx
```

- [ ] **Step 5: 型チェック + Lint + ビルド**

Run:
```bash
npx tsc --noEmit
npm run lint
npm run build
```
Expected: いずれもエラーなしで完了。`build` が成功すること。

- [ ] **Step 6: Commit**

```bash
git add fit-connect/src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx
git commit -m "feat(web): サマリータブを体重×PFCオーバーレイ統合 + PFC構成比カードに再編（期間共通化・旧グラフ削除）"
```

---

## Task 7: 仕上げ確認（全テスト + QA）

**Files:** なし（検証のみ）

- [ ] **Step 1: 全テスト + ビルド再確認**

Run（`fit-connect/` で）:
```bash
npm test
npm run build
```
Expected: テスト緑、ビルド成功。

- [ ] **Step 2: ブラウザQA（`chrome-web-qa` スキル）**

クライアント詳細「サマリー」タブで以下を確認:
- 上部グラフ: 体重ライン（青）＋目標体重の緑破線＋PFC積み上げ棒（淡色）が重なって表示される
- 期間セレクタ（週/月/3ヶ月/全期間）の切替で、上部グラフと下部PFCカードが**両方連動**する
- ツールチップに 日付/体重/kcal/PFC(g) が出る
- 下部PFC構成比カード: ドーナツ中央に平均kcal/日、各バーが伸び、適正ゾーン・目標線・ステータス（不足/適正/過剰）が正しい
- データ無し（食事記録なしのクライアント）でカードが EmptyState になる
- レスポンシブ: 狭幅でドーナツとバーが縦積みになる

---

## Self-Review（記入済み）

**1. Spec coverage:**
- レイアウト再編（上部統合・下部置換・期間共通化）→ Task 6 ✓
- 体重×PFCオーバーレイ（青ライン+エリア+目標破線+kcal積み上げ棒/左kg右kcal）→ Task 4 ✓
- PFC構成比カード（ドーナツ+中央kcal+あすけん風バー案2色味B+ステータス）→ Task 5 ✓
- 構成比=kcal比・目安固定props（段階A）→ Task 2（純関数 + DEFAULT_PFC_TARGETS）+ Task 5（props既定値）✓
- 確定配色（P#6366F1/F#E6B968/C#E294AE、ゾーン#C2E6A8/目標線#2F7D33、体重#3B82F6）→ Task 4,5 ✓
- データフロー（aggregateDailyNutrition流用、平均kcal/日は記録日で除算）→ Task 2,6 ✓
- 単体テスト（通常/0日/体重欠損相当/端数丸め/境界）→ Task 2 ✓
- a11y（色だけに依存しないステータス、reduced-motion、コントラスト#475569以上）→ Task 3,4,5 ✓
- QA（chrome-web-qa）→ Task 7 ✓
- スコープ外（clientsスキーマ変更・編集UI・体重タブのWeightChart）→ 触れていない ✓

**2. Placeholder scan:** プレースホルダなし。全ステップに実コード/実コマンド記載。

**3. Type consistency:** `computePfcBalance` / `PfcBalance` / `MacroBalance`(key, grams, ratio, status, target) / `MacroKey` / `MacroStatus` / `PfcTargets` / `DEFAULT_PFC_TARGETS` を Task 2 で定義し、Task 5 で同名・同シグネチャで使用。`DailyNutritionPoint`(date, weight, calories, protein, fat, carbs) は既存 aggregate.ts の定義に一致。`PeriodSelector`(value, onChange) は既存シグネチャに一致。
