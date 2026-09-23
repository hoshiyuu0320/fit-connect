# 記録→指導動線（フェーズ9.3 MVP）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** トレーナーが記録（サイドパネルの記録カード / 顧客詳細の睡眠）を見た場所から1クリックで、その記録に触れたメッセージを書き始められるようにする。

**Architecture:** (1) メッセージ画面の記録サイドパネルに「返信で触れる」を付け、既存の返信機構（`replyToMessage` → `reply_to_message_id`）に乗せる。(2) 顧客詳細の睡眠カード / 睡眠記録行から `/message?clientId=…&record=sleep:…` へ遷移し、メッセージ画面が睡眠の要約を取り消し可能な「引用チップ」として用意し、送信時に本文の先頭へ平文で付ける。要約の生成・クエリの解釈・本文合成・7日サマリーは純関数に切り出して vitest で検証する。DB・Mobile の変更なし。

**Tech Stack:** Next.js 15 App Router (`'use client'` ページ、`useSearchParams` / `useRouter`)、TypeScript、Tailwind、lucide-react、date-fns 4（`ja` ロケール）、Supabase browser client（RLS 委任）、vitest（node 環境、純関数テストのみ）。

**Spec:** `fit-connect/docs/superpowers/specs/2026-09-23-record-coaching-flow-design.md`

---

## 前提・共通ルール

- 作業ディレクトリは worktree の `fit-connect/`: `/Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/record-reply-quote/fit-connect`。ブランチ `feature/record-reply-quote`
- パッケージコマンドは `npx -y pnpm@10.32.1 …`（例: `npx -y pnpm@10.32.1 vitest run src/lib/sleep`）。`.env` / `.env.local` は参照しない・コピーしない
- コミットはタスクごと（最後に squash する）。コミットメッセージ末尾に `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` を付ける。`git add` はタスクで触ったファイルだけ（`pnpm-lock.yaml` などが差分に出ていたら混ぜない）
- スタイルは既存の hex 直書き（`#14B8A6` teal / `#F0FDFA` tint / `#0F172A` text / `#94A3B8` muted / `#E2E8F0` border）に合わせる。角丸は `rounded-md`（6px）。グラデーション・濃い影は使わない。アイコンは lucide-react のみ（絵文字をアイコンにしない）。クリック要素に `cursor-pointer`（`<button>` / `<Link>` は既定で pointer）、`transition-colors`、`focus-visible:ring-2 focus-visible:ring-[#14B8A6]`
- テストは既存の `src/components/message/recordLog.test.ts` の流儀（`describe` / `it` は日本語、フィクスチャ関数）。`import { describe, it, expect } from 'vitest'`
- パス `src/app/(user_console)/…` は括弧を含むので、シェルでは必ずクォートする

## ファイル構成

新規:
| ファイル | 責務 |
| --- | --- |
| `src/lib/sleep/sleepSummary.ts` | 直近N日の睡眠サマリー（SummaryTab の `useMemo` を純関数化） |
| `src/lib/sleep/sleepSummary.test.ts` | 上のテスト |
| `src/lib/sleep/sleepQuote.ts` | 睡眠の引用文（1晩 / 7日）と `RecordQuote` 型、分の書式 |
| `src/lib/sleep/sleepQuote.test.ts` | 上のテスト |
| `src/lib/message/recordQuoteRef.ts` | `record` クエリの解釈・逆変換・リンク生成・取得範囲 |
| `src/lib/message/recordQuoteRef.test.ts` | 上のテスト |
| `src/lib/message/composeMessageContent.ts` | 引用 + 入力 → 送信本文 |
| `src/lib/message/composeMessageContent.test.ts` | 上のテスト |
| `src/lib/supabase/getSleepRecordsInRange.ts` | `sleep_records` を日付範囲で取得 |
| `src/components/message/RecordQuotePreview.tsx` | 入力欄の上に出す引用チップ |

変更:
| ファイル | 変更 |
| --- | --- |
| `src/components/message/RecordSidePanel.tsx` | `onReplyStart` prop と「返信で触れる」ボタン |
| `src/app/(user_console)/message/page.tsx` | `record` の解釈・`recordQuote` 状態・チップ・本文合成・`onReplyStart` の受け渡し |
| `src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx` | サマリー計算を `summarizeRecentSleep` へ・「メッセージで触れる」・`clientId` prop |
| `src/app/(user_console)/clients/[client_id]/_components/SleepTab.tsx` | 行の「この記録についてメッセージ」・`clientId` prop |
| `src/app/(user_console)/clients/[client_id]/page.tsx` | `clientId` を2つのタブに渡す |
| `../docs/tasks/IMPLEMENTATION_TASKS.md`（モノレポルート） | 9.2 を完了に、9.3 を MVP 完了に |

---

### Task 1: 7日睡眠サマリーの純関数化（`summarizeRecentSleep`）

**Files:**
- Create: `src/lib/sleep/sleepSummary.ts`
- Create: `src/lib/sleep/sleepSummary.test.ts`
- Modify: `src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx:103-124`（`sleepSummary` の `useMemo`）

- [ ] **Step 1: 失敗するテストを書く**

`src/lib/sleep/sleepSummary.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import type { SleepRecord } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'

function sleep(
  recorded_date: string,
  total_sleep_minutes: number | null,
  wakeup_rating: 1 | 2 | 3 | null = null
): SleepRecord {
  return {
    id: `s-${recorded_date}`, client_id: 'c1', recorded_date,
    bed_time: null, wake_time: null, total_sleep_minutes,
    deep_minutes: null, light_minutes: null, rem_minutes: null, awake_minutes: null,
    wakeup_rating, source: 'healthkit',
    created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z',
  }
}

// 2026-09-23 12:00 JST。7日前の境界は 2026-09-16T03:00:00Z
const NOW = new Date('2026-09-23T03:00:00Z')

describe('summarizeRecentSleep', () => {
  it('空配列は記録なし', () => {
    expect(summarizeRecentSleep([], NOW)).toEqual({
      avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0,
    })
  })

  it('7日より前の記録は数えない（recorded_date は UTC 0:00 として比較）', () => {
    const out = summarizeRecentSleep(
      [sleep('2026-09-16', 480), sleep('2026-09-17', 480)],
      NOW
    )
    expect(out.recentCount).toBe(1)
  })

  it('直近7日に記録が無ければ記録なし', () => {
    const out = summarizeRecentSleep([sleep('2026-09-01', 480, 3)], NOW)
    expect(out).toEqual({ avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 0 })
  })

  it('平均は null の項目を除いて計算する', () => {
    const out = summarizeRecentSleep(
      [sleep('2026-09-22', 480, 3), sleep('2026-09-21', 360, null), sleep('2026-09-20', null, 1)],
      NOW
    )
    expect(out.avgHours).toBe(7)          // (480 + 360) / 2 / 60
    expect(out.avgWakeupRating).toBe(2)   // (3 + 1) / 2
    expect(out.recentCount).toBe(3)
    expect(out.hasWarning).toBe(false)
  })

  it('平均6時間未満なら警告', () => {
    const out = summarizeRecentSleep([sleep('2026-09-22', 330, 3)], NOW)
    expect(out.avgHours).toBe(5.5)
    expect(out.hasWarning).toBe(true)
  })

  it('平均目覚め評価1.5以下なら警告（1.5 ちょうどを含む）', () => {
    expect(summarizeRecentSleep([sleep('2026-09-22', 480, 1), sleep('2026-09-21', 480, 2)], NOW).hasWarning).toBe(true)
    expect(summarizeRecentSleep([sleep('2026-09-22', 480, 2), sleep('2026-09-21', 480, 2)], NOW).hasWarning).toBe(false)
  })

  it('値がすべて null の記録だけなら平均も警告も無いが日数は数える', () => {
    const out = summarizeRecentSleep([sleep('2026-09-22', null, null)], NOW)
    expect(out).toEqual({ avgHours: null, avgWakeupRating: null, hasWarning: false, recentCount: 1 })
  })

  it('入力配列を変更しない', () => {
    const records = [sleep('2026-09-22', 480, 3), sleep('2026-09-21', 360, 2)]
    const copy = [...records]
    summarizeRecentSleep(records, NOW)
    expect(records).toEqual(copy)
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/sleep/sleepSummary.test.ts`
Expected: FAIL（`Failed to resolve import "@/lib/sleep/sleepSummary"`）

- [ ] **Step 3: 実装**

`src/lib/sleep/sleepSummary.ts`:

```ts
import type { SleepRecord } from '@/types/client'

// 顧客詳細「睡眠（直近7日）」カードと、メッセージ画面の睡眠引用（sleep:7d）が
// 同じ数字を出すための純関数。SummaryTab の useMemo から移した（挙動は同じ）。
// 入力配列は変更しない。

export interface RecentSleepSummary {
  /** 平均睡眠時間（時間）。total_sleep_minutes が非 null の記録だけの平均。無ければ null */
  avgHours: number | null
  /** 平均目覚め評価（1〜3）。wakeup_rating が非 null の記録だけの平均。無ければ null */
  avgWakeupRating: number | null
  /** 平均6時間未満 or 平均評価1.5以下 */
  hasWarning: boolean
  /** 直近 days 日の記録日数 */
  recentCount: number
}

const DAY_MS = 24 * 60 * 60 * 1000

const EMPTY_SUMMARY: RecentSleepSummary = {
  avgHours: null,
  avgWakeupRating: null,
  hasWarning: false,
  recentCount: 0,
}

/**
 * 直近 days 日（now を基準）の睡眠サマリー。
 * recorded_date（'yyyy-MM-dd'）は new Date() で UTC 0:00 として解釈し、now - days 日 以降を対象にする
 * （SummaryTab の従来の判定と同じ）。
 */
export function summarizeRecentSleep(
  records: readonly SleepRecord[],
  now: Date = new Date(),
  days = 7
): RecentSleepSummary {
  if (records.length === 0) return EMPTY_SUMMARY
  const since = new Date(now.getTime() - days * DAY_MS)
  const recent = records.filter((r) => new Date(r.recorded_date) >= since)
  if (recent.length === 0) return EMPTY_SUMMARY

  const withMinutes = recent.filter((r) => r.total_sleep_minutes !== null)
  const avgHours =
    withMinutes.length > 0
      ? withMinutes.reduce((sum, r) => sum + (r.total_sleep_minutes ?? 0), 0) / withMinutes.length / 60
      : null

  const withRating = recent.filter((r) => r.wakeup_rating !== null)
  const avgWakeupRating =
    withRating.length > 0
      ? withRating.reduce((sum, r) => sum + (r.wakeup_rating ?? 0), 0) / withRating.length
      : null

  // 6時間未満 or 平均評価1.5以下なら注意喚起
  const hasWarning =
    (avgHours !== null && avgHours < 6) || (avgWakeupRating !== null && avgWakeupRating <= 1.5)

  return { avgHours, avgWakeupRating, hasWarning, recentCount: recent.length }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/sleep/sleepSummary.test.ts`
Expected: PASS（8 tests）

- [ ] **Step 5: SummaryTab を純関数に置き換える（挙動は変えない）**

`src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx` の import に追加:

```ts
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'
```

L103-124 の `// 直近7日の睡眠サマリー` から `}, [sleepRecords])` までの `useMemo` ブロック全体を次に置き換える:

```ts
  // 直近7日の睡眠サマリー（メッセージ画面の睡眠引用と同じ計算）
  const sleepSummary = useMemo(() => summarizeRecentSleep(sleepRecords), [sleepRecords])
```

- [ ] **Step 6: 型チェック**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`
Expected: エラー 0

- [ ] **Step 7: コミット**

```bash
git add src/lib/sleep/sleepSummary.ts src/lib/sleep/sleepSummary.test.ts "src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx"
git commit -m "refactor(web): 直近7日の睡眠サマリー計算を純関数 summarizeRecentSleep に切り出し

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `record` クエリの解釈とリンク生成（`recordQuoteRef`）

**Files:**
- Create: `src/lib/message/recordQuoteRef.ts`
- Create: `src/lib/message/recordQuoteRef.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`src/lib/message/recordQuoteRef.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import {
  parseRecordQuoteRef,
  formatRecordQuoteRef,
  recordQuoteHref,
  recordQuoteDateRange,
} from '@/lib/message/recordQuoteRef'

describe('parseRecordQuoteRef', () => {
  it('sleep:YYYY-MM-DD は1晩', () => {
    expect(parseRecordQuoteRef('sleep:2026-09-22')).toEqual({ kind: 'sleep_night', date: '2026-09-22' })
  })
  it('sleep:7d は直近7日', () => {
    expect(parseRecordQuoteRef('sleep:7d')).toEqual({ kind: 'sleep_week' })
  })
  it('空・null・未知の種別・形式違いは null', () => {
    expect(parseRecordQuoteRef(null)).toBeNull()
    expect(parseRecordQuoteRef(undefined)).toBeNull()
    expect(parseRecordQuoteRef('')).toBeNull()
    expect(parseRecordQuoteRef('sleep:')).toBeNull()
    expect(parseRecordQuoteRef('weight:2026-09-22')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026/09/22')).toBeNull()
    expect(parseRecordQuoteRef('sleep:20260922')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-09-22T00:00:00Z')).toBeNull()
    expect(parseRecordQuoteRef('SLEEP:2026-09-22')).toBeNull()
  })
  it('暦日として無効な日付は null', () => {
    expect(parseRecordQuoteRef('sleep:2026-13-40')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-02-30')).toBeNull()
    expect(parseRecordQuoteRef('sleep:2026-00-10')).toBeNull()
  })
  it('うるう日は有効', () => {
    expect(parseRecordQuoteRef('sleep:2028-02-29')).toEqual({ kind: 'sleep_night', date: '2028-02-29' })
    expect(parseRecordQuoteRef('sleep:2026-02-29')).toBeNull()
  })
})

describe('formatRecordQuoteRef / recordQuoteHref', () => {
  it('parse と往復できる', () => {
    expect(formatRecordQuoteRef({ kind: 'sleep_night', date: '2026-09-22' })).toBe('sleep:2026-09-22')
    expect(formatRecordQuoteRef({ kind: 'sleep_week' })).toBe('sleep:7d')
    expect(parseRecordQuoteRef(formatRecordQuoteRef({ kind: 'sleep_week' }))).toEqual({ kind: 'sleep_week' })
  })
  it('リンクは clientId と record をエンコードする', () => {
    expect(recordQuoteHref('abc-123', { kind: 'sleep_night', date: '2026-09-22' }))
      .toBe('/message?clientId=abc-123&record=sleep%3A2026-09-22')
    expect(recordQuoteHref('a b&c', { kind: 'sleep_week' }))
      .toBe('/message?clientId=a%20b%26c&record=sleep%3A7d')
  })
})

describe('recordQuoteDateRange', () => {
  it('1晩はその日だけ', () => {
    expect(recordQuoteDateRange({ kind: 'sleep_night', date: '2026-09-22' }, new Date('2026-09-23T03:00:00Z')))
      .toEqual({ from: '2026-09-22', to: '2026-09-22' })
  })
  it('7日は今日（ローカル日付）から8日前まで', () => {
    // ローカル時刻で 2026-09-23 12:00 を作る（タイムゾーンに依存しない）
    const now = new Date(2026, 8, 23, 12, 0, 0)
    expect(recordQuoteDateRange({ kind: 'sleep_week' }, now)).toEqual({ from: '2026-09-15', to: '2026-09-23' })
  })
  it('7日の範囲は月をまたいでも正しい', () => {
    const now = new Date(2026, 9, 3, 9, 0, 0) // 2026-10-03
    expect(recordQuoteDateRange({ kind: 'sleep_week' }, now)).toEqual({ from: '2026-09-25', to: '2026-10-03' })
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/message/recordQuoteRef.test.ts`
Expected: FAIL（import 解決エラー）

- [ ] **Step 3: 実装**

`src/lib/message/recordQuoteRef.ts`:

```ts
import { format, isValid, parseISO, subDays } from 'date-fns'

// /message?clientId=…&record=<ref> の <ref> の文法。
//   sleep:YYYY-MM-DD … その日付（sleep_records.recorded_date）の1晩
//   sleep:7d         … 直近7日のサマリー（SummaryTab の睡眠カードと同じ計算）
// それ以外は受け付けない（拡張で weight: 等を足すときはここに追加する）。
// URL に載せるのは日付だけで、睡眠時間などの値は載せない。

export type RecordQuoteRef =
  | { kind: 'sleep_night'; date: string } // 'yyyy-MM-dd'
  | { kind: 'sleep_week' }

const SLEEP_WEEK = 'sleep:7d'
const SLEEP_NIGHT_RE = /^sleep:(\d{4}-\d{2}-\d{2})$/

/** 'yyyy-MM-dd' が実在する暦日か（parseISO の検証 + 往復で桁ずれを弾く） */
function isCalendarDate(date: string): boolean {
  const parsed = parseISO(date)
  return isValid(parsed) && format(parsed, 'yyyy-MM-dd') === date
}

export function parseRecordQuoteRef(param: string | null | undefined): RecordQuoteRef | null {
  if (!param) return null
  if (param === SLEEP_WEEK) return { kind: 'sleep_week' }
  const m = SLEEP_NIGHT_RE.exec(param)
  if (!m) return null
  const date = m[1]
  return isCalendarDate(date) ? { kind: 'sleep_night', date } : null
}

export function formatRecordQuoteRef(ref: RecordQuoteRef): string {
  return ref.kind === 'sleep_week' ? SLEEP_WEEK : `sleep:${ref.date}`
}

/** 顧客詳細 → メッセージ画面のリンク */
export function recordQuoteHref(clientId: string, ref: RecordQuoteRef): string {
  return `/message?clientId=${encodeURIComponent(clientId)}&record=${encodeURIComponent(formatRecordQuoteRef(ref))}`
}

/**
 * 引用の対象を取るための recorded_date の範囲（両端含む、'yyyy-MM-dd'、ローカル日付）。
 * 7日は summarizeRecentSleep が「now - 7日 以降」を UTC 0:00 基準で判定するので、
 * 取りこぼさないよう 8 日前から今日まで取り、絞り込みは summarizeRecentSleep に任せる。
 */
export function recordQuoteDateRange(ref: RecordQuoteRef, now: Date = new Date()): { from: string; to: string } {
  if (ref.kind === 'sleep_night') return { from: ref.date, to: ref.date }
  return { from: format(subDays(now, 8), 'yyyy-MM-dd'), to: format(now, 'yyyy-MM-dd') }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/message/recordQuoteRef.test.ts`
Expected: PASS（10 tests）

- [ ] **Step 5: コミット**

```bash
git add src/lib/message/recordQuoteRef.ts src/lib/message/recordQuoteRef.test.ts
git commit -m "feat(web): 記録引用の record クエリを解釈・生成する recordQuoteRef を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: 睡眠の引用文（`sleepQuote`）

**Files:**
- Create: `src/lib/sleep/sleepQuote.ts`
- Create: `src/lib/sleep/sleepQuote.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`src/lib/sleep/sleepQuote.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import type { SleepRecord } from '@/types/client'
import {
  formatSleepMinutes,
  buildSleepNightQuote,
  buildSleepWeekQuote,
  buildSleepQuote,
} from '@/lib/sleep/sleepQuote'

function sleep(
  recorded_date: string,
  total_sleep_minutes: number | null,
  wakeup_rating: 1 | 2 | 3 | null = null
): SleepRecord {
  return {
    id: `s-${recorded_date}`, client_id: 'c1', recorded_date,
    bed_time: null, wake_time: null, total_sleep_minutes,
    deep_minutes: null, light_minutes: null, rem_minutes: null, awake_minutes: null,
    wakeup_rating, source: 'healthkit',
    created_at: '2026-09-01T00:00:00Z', updated_at: '2026-09-01T00:00:00Z',
  }
}

// 2026-09-23 12:00 JST
const NOW = new Date('2026-09-23T03:00:00Z')

describe('formatSleepMinutes', () => {
  it('H時間M分（ゼロ埋めなし）', () => {
    expect(formatSleepMinutes(252)).toBe('4時間12分')
    expect(formatSleepMinutes(425)).toBe('7時間5分')
  })
  it('分が0なら時間だけ、60分未満は分だけ、0分は0分', () => {
    expect(formatSleepMinutes(420)).toBe('7時間')
    expect(formatSleepMinutes(45)).toBe('45分')
    expect(formatSleepMinutes(0)).toBe('0分')
  })
  it('小数は分に丸める', () => {
    expect(formatSleepMinutes(330.4)).toBe('5時間30分')
    expect(formatSleepMinutes(329.6)).toBe('5時間30分')
  })
})

describe('buildSleepNightQuote', () => {
  it('時間と目覚め評価の両方', () => {
    // 2026-09-22 は火曜
    expect(buildSleepNightQuote(sleep('2026-09-22', 252, 1))).toEqual({
      label: '睡眠 9/22(火)',
      text: '【睡眠 9/22(火)】4時間12分・目覚め: だるい',
    })
  })
  it('時間だけ / 評価だけ', () => {
    expect(buildSleepNightQuote(sleep('2026-09-22', 420, null))?.text).toBe('【睡眠 9/22(火)】7時間')
    expect(buildSleepNightQuote(sleep('2026-09-22', null, 3))?.text).toBe('【睡眠 9/22(火)】目覚め: すっきり')
  })
  it('両方 null なら引用しない', () => {
    expect(buildSleepNightQuote(sleep('2026-09-22', null, null))).toBeNull()
  })
  it('曜日は日本語の1文字', () => {
    expect(buildSleepNightQuote(sleep('2026-09-27', 480, 2))?.label).toBe('睡眠 9/27(日)')
    expect(buildSleepNightQuote(sleep('2026-10-05', 480, 2))?.label).toBe('睡眠 10/5(月)')
  })
})

describe('buildSleepWeekQuote', () => {
  it('平均時間・平均評価・記録日数', () => {
    const records = [sleep('2026-09-22', 330, 1), sleep('2026-09-21', 330, 2), sleep('2026-09-20', 330, 1)]
    expect(buildSleepWeekQuote(records, NOW)).toEqual({
      label: '睡眠 直近7日',
      text: '【睡眠 直近7日】平均 5時間30分・目覚め評価 1.3/3・記録 3日',
    })
  })
  it('平均時間が無ければ項を省く / 評価が無ければ項を省く', () => {
    expect(buildSleepWeekQuote([sleep('2026-09-22', null, 3)], NOW)?.text)
      .toBe('【睡眠 直近7日】目覚め評価 3.0/3・記録 1日')
    expect(buildSleepWeekQuote([sleep('2026-09-22', 480, null)], NOW)?.text)
      .toBe('【睡眠 直近7日】平均 8時間・記録 1日')
  })
  it('平均は分に丸めてから書式化する', () => {
    // (480 + 481) / 2 = 480.5 分 → 481 分 → 8時間1分
    expect(buildSleepWeekQuote([sleep('2026-09-22', 480), sleep('2026-09-21', 481)], NOW)?.text)
      .toBe('【睡眠 直近7日】平均 8時間1分・記録 2日')
  })
  it('直近7日に記録が無ければ null', () => {
    expect(buildSleepWeekQuote([sleep('2026-09-01', 480, 3)], NOW)).toBeNull()
    expect(buildSleepWeekQuote([], NOW)).toBeNull()
  })
})

describe('buildSleepQuote', () => {
  it('sleep_night は日付が一致する記録から作る', () => {
    const records = [sleep('2026-09-22', 252, 1), sleep('2026-09-21', 480, 3)]
    expect(buildSleepQuote({ kind: 'sleep_night', date: '2026-09-21' }, records, NOW)?.text)
      .toBe('【睡眠 9/21(月)】8時間・目覚め: すっきり')
  })
  it('sleep_night で日付が無ければ null', () => {
    expect(buildSleepQuote({ kind: 'sleep_night', date: '2026-09-19' }, [sleep('2026-09-22', 252, 1)], NOW)).toBeNull()
  })
  it('sleep_week は buildSleepWeekQuote と同じ', () => {
    const records = [sleep('2026-09-22', 480, 3)]
    expect(buildSleepQuote({ kind: 'sleep_week' }, records, NOW)).toEqual(buildSleepWeekQuote(records, NOW))
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/sleep/sleepQuote.test.ts`
Expected: FAIL（import 解決エラー）

- [ ] **Step 3: 実装**

`src/lib/sleep/sleepQuote.ts`:

```ts
import { format, parseISO } from 'date-fns'
import { ja } from 'date-fns/locale'
import type { SleepRecord } from '@/types/client'
import { WAKEUP_RATING_OPTIONS } from '@/types/client'
import { summarizeRecentSleep } from '@/lib/sleep/sleepSummary'
import type { RecordQuoteRef } from '@/lib/message/recordQuoteRef'

// メッセージ画面の「記録の引用」。送信時に本文の先頭へ平文で付く（Mobile でも崩れない）。
// 将来 metadata.record_ref を添えるときも text はそのまま旧アプリ向けのフォールバックになる。

export interface RecordQuote {
  /** チップの見出し（例 '睡眠 9/22(火)'） */
  label: string
  /** 本文の先頭に付ける1行（例 '【睡眠 9/22(火)】4時間12分・目覚め: だるい'） */
  text: string
}

/** 分 → 'H時間M分'（ゼロ埋めなし。分が 0 なら 'H時間'、60分未満は 'M分'） */
export function formatSleepMinutes(totalMinutes: number): string {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}分`
  return m === 0 ? `${h}時間` : `${h}時間${m}分`
}

/** 'yyyy-MM-dd' → 'M/d(曜)'（曜日は日本語1文字） */
function formatSleepDate(recordedDate: string): string {
  return format(parseISO(recordedDate), 'M/d(E)', { locale: ja })
}

function quote(label: string, parts: string[]): RecordQuote {
  return { label, text: `【${label}】${parts.join('・')}` }
}

/** 1晩の引用。時間と目覚め評価の両方が無ければ null */
export function buildSleepNightQuote(record: SleepRecord): RecordQuote | null {
  const parts: string[] = []
  if (record.total_sleep_minutes !== null) parts.push(formatSleepMinutes(record.total_sleep_minutes))
  if (record.wakeup_rating !== null) parts.push(`目覚め: ${WAKEUP_RATING_OPTIONS[record.wakeup_rating]}`)
  if (parts.length === 0) return null
  return quote(`睡眠 ${formatSleepDate(record.recorded_date)}`, parts)
}

/** 直近7日の引用（SummaryTab の睡眠カードと同じ数字）。記録が無ければ null */
export function buildSleepWeekQuote(records: readonly SleepRecord[], now: Date = new Date()): RecordQuote | null {
  const s = summarizeRecentSleep(records, now)
  if (s.recentCount === 0) return null
  const parts: string[] = []
  if (s.avgHours !== null) parts.push(`平均 ${formatSleepMinutes(s.avgHours * 60)}`)
  if (s.avgWakeupRating !== null) parts.push(`目覚め評価 ${s.avgWakeupRating.toFixed(1)}/3`)
  parts.push(`記録 ${s.recentCount}日`)
  return quote('睡眠 直近7日', parts)
}

/** record クエリの参照と取得済みの記録から引用を作る */
export function buildSleepQuote(
  ref: RecordQuoteRef,
  records: readonly SleepRecord[],
  now: Date = new Date()
): RecordQuote | null {
  if (ref.kind === 'sleep_week') return buildSleepWeekQuote(records, now)
  const record = records.find((r) => r.recorded_date === ref.date)
  return record ? buildSleepNightQuote(record) : null
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/sleep/sleepQuote.test.ts`
Expected: PASS（14 tests）。曜日が英語（`Tue`）で落ちる場合は `date-fns/locale` の `ja` import を確認する

- [ ] **Step 5: コミット**

```bash
git add src/lib/sleep/sleepQuote.ts src/lib/sleep/sleepQuote.test.ts
git commit -m "feat(web): 睡眠記録の引用文（1晩 / 直近7日）を生成する sleepQuote を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: 送信本文の合成（`composeMessageContent`）

**Files:**
- Create: `src/lib/message/composeMessageContent.ts`
- Create: `src/lib/message/composeMessageContent.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`src/lib/message/composeMessageContent.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { composeMessageContent } from '@/lib/message/composeMessageContent'

describe('composeMessageContent', () => {
  it('引用が無ければ入力をそのまま返す（前後の空白も触らない）', () => {
    expect(composeMessageContent(null, ' こんにちは ')).toBe(' こんにちは ')
    expect(composeMessageContent(undefined, '')).toBe('')
    expect(composeMessageContent('', 'a')).toBe('a')
  })
  it('引用があれば「引用 + 改行 + 入力（前後の空白を除く）」', () => {
    expect(composeMessageContent('【睡眠 9/22(火)】4時間12分', '  昨夜は短かったですね\n早めに休みましょう  '))
      .toBe('【睡眠 9/22(火)】4時間12分\n昨夜は短かったですね\n早めに休みましょう')
  })
  it('引用があって入力が空白だけなら引用だけ（末尾に改行を残さない）', () => {
    expect(composeMessageContent('【睡眠 9/22(火)】4時間12分', '   ')).toBe('【睡眠 9/22(火)】4時間12分')
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/message/composeMessageContent.test.ts`
Expected: FAIL（import 解決エラー）

- [ ] **Step 3: 実装**

`src/lib/message/composeMessageContent.ts`:

```ts
/**
 * 送信本文 = 記録の引用（あれば）+ 改行 + 入力。
 * 引用が無いときは入力をそのまま返し、既存の送信挙動を変えない。
 */
export function composeMessageContent(quoteText: string | null | undefined, input: string): string {
  if (!quoteText) return input
  const body = input.trim()
  return body ? `${quoteText}\n${body}` : quoteText
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `npx -y pnpm@10.32.1 vitest run src/lib/message/composeMessageContent.test.ts`
Expected: PASS（3 tests）

- [ ] **Step 5: コミット**

```bash
git add src/lib/message/composeMessageContent.ts src/lib/message/composeMessageContent.test.ts
git commit -m "feat(web): 記録の引用と入力から送信本文を合成する composeMessageContent を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: 睡眠記録の範囲取得（`getSleepRecordsInRange`）と引用チップ（`RecordQuotePreview`）

**Files:**
- Create: `src/lib/supabase/getSleepRecordsInRange.ts`
- Create: `src/components/message/RecordQuotePreview.tsx`

（どちらも純関数ではないのでテストは書かない。ブラウザ QA で確認する）

- [ ] **Step 1: 取得関数**

`src/lib/supabase/getSleepRecordsInRange.ts`（`getSleepRecords.ts` と同じ流儀）:

```ts
import { supabase } from '@/lib/supabase'
import type { SleepRecord } from '@/types/client'

/**
 * recorded_date が from〜to（両端含む、'yyyy-MM-dd'）の睡眠記録を新しい順で返す。
 * 閲覧可否は RLS（sleep_records_trainer_select）に委任。recorded_date は date 列なので
 * 素の日付で .lte しても終了日は漏れない。
 */
export const getSleepRecordsInRange = async (
  clientId: string,
  from: string,
  to: string
): Promise<SleepRecord[]> => {
  const { data, error } = await supabase
    .from('sleep_records')
    .select('*')
    .eq('client_id', clientId)
    .gte('recorded_date', from)
    .lte('recorded_date', to)
    .order('recorded_date', { ascending: false })

  if (error) {
    console.error('睡眠記録（範囲）取得エラー:', error)
    throw error
  }

  return (data ?? []) as SleepRecord[]
}
```

- [ ] **Step 2: 引用チップ**

`src/components/message/RecordQuotePreview.tsx`（`ReplyPreview.tsx` と同系の見た目）:

```tsx
'use client'

import { Moon, X } from 'lucide-react'

interface RecordQuotePreviewProps {
  /** 見出し（例 '睡眠 9/22(火)'） */
  label: string
  /** 本文の先頭に付く1行 */
  text: string
  onCancel: () => void
}

/** 入力欄の上に出す「記録の引用」チップ。送信時に text が本文の先頭に付く */
export function RecordQuotePreview({ label, text, onCancel }: RecordQuotePreviewProps) {
  return (
    <div className="bg-[#F0FDFA] border-l-[3px] border-[#14B8A6] rounded-md p-3 mb-2 flex items-center justify-between gap-3">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5 mb-1">
          <Moon className="h-3.5 w-3.5 text-[#14B8A6]" aria-hidden="true" />
          <span className="text-sm font-semibold text-[#14B8A6]">{label}</span>
        </div>
        <p className="text-sm text-[#475569] break-words">{text}</p>
      </div>
      <button
        type="button"
        onClick={onCancel}
        className="flex-shrink-0 p-1 text-[#94A3B8] hover:text-[#64748B] hover:bg-[#CCFBF1] rounded-md transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
        aria-label="引用を取り消す"
        title="引用を取り消す"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  )
}
```

- [ ] **Step 3: 型チェック**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`
Expected: エラー 0

- [ ] **Step 4: コミット**

```bash
git add src/lib/supabase/getSleepRecordsInRange.ts src/components/message/RecordQuotePreview.tsx
git commit -m "feat(web): 睡眠記録の範囲取得と記録引用チップ RecordQuotePreview を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: 記録サイドパネルの「返信で触れる」

**Files:**
- Modify: `src/components/message/RecordSidePanel.tsx`（props L15-26、import L4、リスト L218-237）
- Modify: `src/app/(user_console)/message/page.tsx`（`<RecordSidePanel` の呼び出し L630-643）

- [ ] **Step 1: props と import**

`RecordSidePanel.tsx` L4 を:

```ts
import { X, ClipboardList, Reply } from "lucide-react";
```

`RecordSidePanelProps` に追加（`onImageClick` の後）:

```ts
  /** 記録カードの「返信で触れる」。未指定ならボタンを出さない */
  onReplyStart?: (msg: Message) => void;
```

関数の分割代入（`export function RecordSidePanel({ … onImageClick, })`）に `onReplyStart,` を追加。

- [ ] **Step 2: リスト項目にボタンを追加**

`<li key={item.message.id} className="px-4 py-3">` の中の日時 `<p …>` を、次のブロックに置き換える（`RecordCard` はそのまま）:

```tsx
                <div className="flex items-center justify-between gap-2 mt-1.5">
                  <p className="text-[10px] text-[#94A3B8]">
                    {new Date(item.message.created_at).toLocaleString("ja-JP", {
                      month: "numeric",
                      day: "numeric",
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </p>
                  {onReplyStart && (
                    <button
                      type="button"
                      onClick={() => onReplyStart(item.message)}
                      className="inline-flex items-center gap-1 text-[11px] text-[#94A3B8] hover:text-[#14B8A6] rounded-md px-1.5 py-0.5 transition-colors cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
                      title="この記録に返信する"
                    >
                      <Reply className="h-3 w-3" aria-hidden="true" />
                      返信で触れる
                    </button>
                  )}
                </div>
```

（hover 時だけ表示にしない: iPad などタッチ環境で押せなくなるため。`RecordCard` は顧客詳細への `Link` で包まれているので、ボタンはその外に置く。）

- [ ] **Step 3: ページから渡す**

`page.tsx` の `<RecordSidePanel … onImageClick={setSelectedImageUrl} />` に1行追加:

```tsx
                    onReplyStart={handleReplyStart}
```

- [ ] **Step 4: 型チェック**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit`
Expected: エラー 0

- [ ] **Step 5: コミット**

```bash
git add src/components/message/RecordSidePanel.tsx "src/app/(user_console)/message/page.tsx"
git commit -m "feat(web): 記録サイドパネルの記録カードに「返信で触れる」を追加（既存の返信機構に接続）

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: メッセージ画面の記録引用（`record` クエリ → チップ → 本文）

**Files:**
- Modify: `src/app/(user_console)/message/page.tsx`

- [ ] **Step 1: import**

L5 の `import { useSearchParams } from 'next/navigation';` を:

```ts
import { useSearchParams, useRouter } from 'next/navigation';
```

`import { ReplyPreview } …` の下に追加:

```ts
import { RecordQuotePreview } from '@/components/message/RecordQuotePreview';
import { getSleepRecordsInRange } from '@/lib/supabase/getSleepRecordsInRange';
import { parseRecordQuoteRef, recordQuoteDateRange } from '@/lib/message/recordQuoteRef';
import { buildSleepQuote, type RecordQuote } from '@/lib/sleep/sleepQuote';
import { composeMessageContent } from '@/lib/message/composeMessageContent';
```

- [ ] **Step 2: 状態**

`const client_id = searchParams.get("clientId")` の直後に:

```ts
    const recordParam = searchParams.get("record")
    const router = useRouter()
```

`const [replyToMessage, setReplyToMessage] = useState<Message | null>(null);` の直後に:

```ts
    // 記録の引用（顧客詳細の睡眠カード等から ?record=sleep:… で着地したとき）。送信時に本文の先頭へ付く
    const [recordQuote, setRecordQuote] = useState<RecordQuote | null>(null);
```

- [ ] **Step 3: 引用を用意する effect と、顧客切替でのクリア**

「既読マーク: クライアント選択時」の `useEffect` の直前に追加:

```ts
    // 顧客を切り替えたら引用を捨てる（別の顧客の睡眠を引用しない）
    useEffect(() => {
        setRecordQuote(null);
    }, [selectedClient?.client_id]);

    // ?record=sleep:… の引用を用意する（顧客の自動選択が済んでから）
    useEffect(() => {
        if (!client_id || !recordParam) return;
        const ref = parseRecordQuoteRef(recordParam);
        if (!ref) {
            // 不正な値は無視してクエリから落とす（再読み込みのたびに warn が出ないように）
            console.warn('record クエリを解釈できません:', recordParam);
            router.replace(`/message?clientId=${encodeURIComponent(client_id)}`);
            return;
        }
        if (selectedClient?.client_id !== client_id) return;
        const cid = client_id;
        let cancelled = false;
        (async () => {
            try {
                const now = new Date();
                const { from, to } = recordQuoteDateRange(ref, now);
                const records = await getSleepRecordsInRange(cid, from, to);
                // 取得中に別の顧客へ切り替わっていたら捨てる（StrictMode の二重実行も同じ扱い）
                if (cancelled || selectedClientRef.current?.client_id !== cid) return;
                const quote = buildSleepQuote(ref, records, now);
                if (quote) {
                    setRecordQuote(quote);
                    textareaRef.current?.focus();
                } else {
                    console.warn('引用する睡眠記録がありません:', recordParam);
                }
                // 消費したらクエリから record を落とす（再読み込みで引用が復活しない。clientId は同じなので再選択は起きない）
                router.replace(`/message?clientId=${encodeURIComponent(cid)}`);
            } catch (e) {
                if (!cancelled) console.error('睡眠記録（引用）取得エラー:', e);
            }
        })();
        return () => { cancelled = true; };
    }, [client_id, recordParam, selectedClient?.client_id, router]);
```

注意: `selectedClientRef` は既存（L70、`selectedClient` と同期する effect が L77-79 にある）。`textareaRef` も既存。

- [ ] **Step 4: 送信本文の合成**

`handleSend` の中を次のように変える:

1. `setLoading(true);` の直前（`if ((!hasText && !hasImages) …) return;` の後）に:

```ts
        const content = composeMessageContent(recordQuote?.text, input);
```

2. `body: JSON.stringify({ … content: input, … })` の `content: input,` を `content,` に
3. 楽観表示 `const newMsg: Message = { … content: input, … }` の `content: input,` を `content,` に
4. `setLastMessages` 内の `content: input || (imageUrls.length > 0 ? '画像' : ''),` を `content: content || (imageUrls.length > 0 ? '画像' : ''),` に
5. `setReplyToMessage(null);` の直後に `setRecordQuote(null);` を追加（成功時だけ。失敗時はチップを残して再送できるようにする）

- [ ] **Step 5: チップの表示**

footer の `{replyToMessage && ( <ReplyPreview … /> )}` の直後に:

```tsx
                    {recordQuote && (
                        <RecordQuotePreview
                            label={recordQuote.label}
                            text={recordQuote.text}
                            onCancel={() => setRecordQuote(null)}
                        />
                    )}
```

- [ ] **Step 6: 型チェックと lint**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit && npx -y pnpm@10.32.1 lint`
Expected: tsc エラー 0、lint はエラー 0（既存の警告 6 件はそのまま）。`react-hooks/exhaustive-deps` の警告が新しい effect に出たら、依存配列を本計画のとおりにしているか確認する（`selectedClientRef` / `textareaRef` は ref なので依存に入れない）

- [ ] **Step 7: コミット**

```bash
git add "src/app/(user_console)/message/page.tsx"
git commit -m "feat(web): メッセージ画面に記録の引用（?record=sleep:… → 引用チップ → 本文の先頭）を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: 顧客詳細からの導線（睡眠カード / 睡眠記録行）

**Files:**
- Modify: `src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx`（props、import、睡眠カード見出し L249-257）
- Modify: `src/app/(user_console)/clients/[client_id]/_components/SleepTab.tsx`（props、import、最近の記録の行 L183-215）
- Modify: `src/app/(user_console)/clients/[client_id]/page.tsx`（`<SummaryTab` L269-283、`<SleepTab` L305）

- [ ] **Step 1: SummaryTab**

import に追加:

```ts
import Link from 'next/link'
import { MessageSquare } from 'lucide-react'
import { recordQuoteHref } from '@/lib/message/recordQuoteRef'
```

`SummaryTabProps` の末尾に:

```ts
  /** 「メッセージで触れる」のリンク先。未指定ならリンクを出さない */
  clientId?: string
```

分割代入に `clientId,` を追加。

睡眠カードの見出し行（`<div className="flex items-center justify-between mb-3">` 〜 `</div>`、「改善余地あり」バッジを含む）を次に置き換える:

```tsx
          <div className="flex items-center justify-between gap-2 mb-3">
            <h3 className="text-sm font-semibold text-[#0F172A]">睡眠（直近7日）</h3>
            <div className="flex items-center gap-2">
              {sleepSummary.hasWarning && (
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-[#FEF3C7] text-[#B45309]">
                  改善余地あり
                </span>
              )}
              {clientId && sleepSummary.recentCount > 0 && (
                <Link
                  href={recordQuoteHref(clientId, { kind: 'sleep_week' })}
                  className="inline-flex items-center gap-1 text-xs text-[#14B8A6] hover:bg-[#F0FDFA] rounded-md px-2 py-1 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
                  title="直近7日の睡眠についてメッセージを書く"
                >
                  <MessageSquare className="h-3.5 w-3.5" aria-hidden="true" />
                  メッセージで触れる
                </Link>
              )}
            </div>
          </div>
```

- [ ] **Step 2: SleepTab**

import に追加:

```ts
import Link from 'next/link'
import { MessageSquare } from 'lucide-react'
import { recordQuoteHref } from '@/lib/message/recordQuoteRef'
```

`SleepTabProps` に:

```ts
  /** 「この記録についてメッセージ」のリンク先。未指定ならリンクを出さない */
  clientId?: string
```

`export function SleepTab({ sleepRecords }: SleepTabProps)` を `export function SleepTab({ sleepRecords, clientId }: SleepTabProps)` に。

最近の記録の行で、ソースバッジの `<span className={`text-[10px] px-1.5 py-0.5 rounded ${sourceBadgeClass}`}>{sourceLabel}</span>` を次に置き換える:

```tsx
                  <div className="flex items-center gap-2">
                    <span
                      className={`text-[10px] px-1.5 py-0.5 rounded ${sourceBadgeClass}`}
                    >
                      {sourceLabel}
                    </span>
                    {clientId && (
                      <Link
                        href={recordQuoteHref(clientId, { kind: 'sleep_night', date: record.recorded_date })}
                        className="inline-flex items-center justify-center h-8 w-8 rounded-md text-[#94A3B8] hover:text-[#14B8A6] hover:bg-[#F0FDFA] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#14B8A6]"
                        aria-label="この記録についてメッセージ"
                        title="この記録についてメッセージ"
                      >
                        <MessageSquare className="h-4 w-4" aria-hidden="true" />
                      </Link>
                    )}
                  </div>
```

- [ ] **Step 3: 顧客詳細ページから clientId を渡す**

`page.tsx` の `<SummaryTab … sleepRecords={sleepRecords} />` に `clientId={clientId}` を、`<SleepTab sleepRecords={sleepRecords} />` を `<SleepTab sleepRecords={sleepRecords} clientId={clientId} />` に（`clientId` は L44 の `const clientId = params.client_id as string`）。

- [ ] **Step 4: 型チェックと lint**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit && npx -y pnpm@10.32.1 lint`
Expected: tsc エラー 0、lint エラー 0

- [ ] **Step 5: コミット**

```bash
git add "src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx" "src/app/(user_console)/clients/[client_id]/_components/SleepTab.tsx" "src/app/(user_console)/clients/[client_id]/page.tsx"
git commit -m "feat(web): 顧客詳細の睡眠カード・睡眠記録行から「メッセージで触れる」導線を追加

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: 全体検証（テスト・型・lint・ビルド）

**Files:** なし（検証のみ）

- [ ] **Step 1: 全テスト**

Run: `npx -y pnpm@10.32.1 vitest run`
Expected: 31 files / 460 tests 前後、すべて PASS（着手前は 27 files / 425 tests）

- [ ] **Step 2: 型と lint**

Run: `npx -y pnpm@10.32.1 exec tsc --noEmit && npx -y pnpm@10.32.1 lint`
Expected: エラー 0

- [ ] **Step 3: 本番ビルド（公開 env はダミー）**

Run:
```bash
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321 NEXT_PUBLIC_SUPABASE_ANON_KEY=dummy npx -y pnpm@10.32.1 build
```
Expected: `Compiled successfully`、`/message` と `/clients/[client_id]` がルート一覧に出る。別の env が足りないというエラーが出たら、そのキーもダミー値で足して再実行する（`.env.local` は読まない）

- [ ] **Step 4: 差分の混入確認**

Run: `git status --short && git diff --stat origin/develop/1.0.0...HEAD`
Expected: 変更は本計画のファイルと docs だけ。`pnpm-lock.yaml` や `.g.dart` などが出ていたら `git checkout -- <file>` で戻す

---

### Task 10: ドキュメント更新

**Files:**
- Modify: `../docs/tasks/IMPLEMENTATION_TASKS.md`（モノレポルートの `docs/tasks/`。worktree では `/Users/hoshidayuuya/Documents/FIT-CONNECT/.claude/worktrees/record-reply-quote/docs/tasks/IMPLEMENTATION_TASKS.md`）

- [ ] **Step 1: 9.2 を完了に**

サマリー表のフェーズ9 行（`| 9 | トレーナー介入機能 …`）の進捗を `50%` → `100%`、状態を次に:

```
🟢 計画確定（2026/09/13、`2026-09-13-trainer-intervention-plan.md`）/ 9.1 MVP 完了（#88、2026/09/22 リモート適用・cron 有効化）/ 9.2 MVP 完了（#91、2026/09/22 マージ・migration `20260922200000` リモート適用済み）/ 9.3 MVP 完了（2026/09/23、ブランチ `feature/record-reply-quote`）。拡張（睡眠悪化・カロリー超過の検知、閾値設定、トレーナー向け push、消し込み、チャート点クリック、record_ref）は未着手
```

`- [ ] **9.2 デイリートリアージ**` を `- [x] **9.2 デイリートリアージ**（… — **MVP 完了**（#91 マージ、2026-09-22。migration `20260922200000` リモート適用済み）` にし、サブ項目の「（オーナー）Web の動作確認 → マージ → `supabase db push`」と「ダッシュボードに統合、alerts テーブルを消費」を `[x]` にする。残る確認（返信で行が消える・バッジが減る）はオーナー確認待ちとして1行残す。

- [ ] **Step 2: 9.3 を MVP 完了に**

`- [ ] **9.3 睡眠→指導動線**` を次に置き換える:

```
- [x] **9.3 記録→指導動線**（cat1 6-A。旧「睡眠→指導動線」）— **MVP 完了**（2026-09-23、ブランチ `feature/record-reply-quote`。設計: `fit-connect/docs/superpowers/specs/2026-09-23-record-coaching-flow-design.md`）
  - [x] メッセージ画面の記録サイドパネル: 記録カード（体重・食事・運動・達成）に「返信で触れる」→ 既存の返信機構（`reply_to_message_id`）。Mobile 変更なし
  - [x] 顧客詳細 → メッセージ: 睡眠（直近7日）カードの「メッセージで触れる」（`/message?clientId=…&record=sleep:7d`）と睡眠タブの記録行（`record=sleep:YYYY-MM-DD`）。メッセージ画面が睡眠の要約を取り消し可能な引用チップにし、送信時に本文の先頭へ平文で付ける（`【睡眠 9/22(火)】4時間12分・目覚め: だるい`）。`messages.metadata` は使わない
  - [x] 純関数 + テスト: `summarizeRecentSleep`（SummaryTab から切り出し）/ `sleepQuote` / `recordQuoteRef` / `composeMessageContent`
  - [ ] 拡張1: `SleepChart` / `WeightChart` のデータ点クリック → `recordQuoteHref`
  - [ ] 拡張2: `metadata.record_ref` + Mobile のカード描画（統合判断7-1 のレジストリ文書 `docs/architecture/message-metadata-registry.md` の新設が前提）
  - [ ] 9.1 の睡眠悪化アラート（未実装）の行から `sleep:7d` の引用リンクへ接続
```

- [ ] **Step 3: 先頭の「最終更新」に1文追加**

`**最終更新**: 2026年9月23日 - ` の直後に次を挿入:

```
フェーズ9.3 MVP 実装（記録サイドパネルの「返信で触れる」＋顧客詳細の睡眠カード / 記録行からの「メッセージで触れる」→ メッセージ画面の引用チップ。Web のみ・DB / Mobile 変更なし。ブランチ `feature/record-reply-quote`）。9.2 を完了に更新（#91）。
```

- [ ] **Step 4: コミット**

```bash
git add ../docs/tasks/IMPLEMENTATION_TASKS.md
git commit -m "docs: フェーズ9.3 MVP 完了と 9.2 完了を IMPLEMENTATION_TASKS に反映

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## 実装後（マネージャー）

1. `chrome-web-qa` スキルでブラウザ確認（ログインが要るためオーナー実施になる可能性あり。確認項目: ①サイドパネルの「返信で触れる」→ ReplyPreview が出て送信後に引用付きで表示 ②顧客詳細 睡眠カードの「メッセージで触れる」→ チップに7日サマリー、URL から `record` が消える、送信本文の先頭に引用 ③睡眠タブの行アイコン → 1晩の引用 ④✕で取り消し ⑤引用中に別の顧客へ切り替えるとチップが消える ⑥`?record=weight:x` など不正値は無視）
2. `superpowers:finishing-a-development-branch` → squash → PR（`develop/1.0.0` 向け）

## 実装時の差分（レビューで採った変更。最終形は spec を正とする）

- `RecentSleepSummary` に `avgMinutes` を追加し `avgHours` はそこから導出。フィールドは `readonly`、返り値と `EMPTY_SUMMARY` は `Object.freeze`（コミット 487d95c / 26f69a9）
- `buildSleepWeekQuote` は `avgMinutes` を分のまま丸める。`buildSleepQuote` は `sleep_week` / `sleep_night` / それ以外 → null の明示 3 分岐（487d95c）
- `router.replace` は 2 箇所とも `{ scroll: false }`。不正な `record` もクエリから落とす（124d49a）
- 色: サイドパネルのボタンは `text-[#64748B]`、SummaryTab のリンクは `text-[#0F766E] shrink-0 whitespace-nowrap`、SleepTab の行は `text-[#64748B]` のアイコンのみ（26f69a9 / c61f486 / 75775e7）
