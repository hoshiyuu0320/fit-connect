# メッセージ 記録サイドパネル（Web案②）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Web（トレーナー）のメッセージ画面に、会話メインの右側へ「記録サイドパネル（開閉式・デフォルト開）」を追加する。パネルに **サマリー（PFC・体重推移）＋種別フィルタ＋記録ログ** を表示。会話タイムラインは従来どおり混在のまま。

**Architecture:** 記録ログの抽出/種別フィルタを純関数 `recordLog.ts` に切り出してテスト可能にする。新規 `RecordSidePanel` コンポーネントが、(C)記録ログ＝`messages` を `parseRecordMessage` でフィルタし `RecordCard` で表示、(B)サマリー＝`getMealRecords`/`getWeightRecords`→`aggregateDailyNutrition`→`PfcBalanceCard`/`WeightNutritionChart` で表示。`page.tsx` に第3カラムとして統合し、開閉は `useState`（デフォルト開）。**データ源は分離**（サマリー=meal/weight_records、ログ=messages.tags）。

**Tech Stack:** Next.js 15 + TypeScript + Tailwind + Vitest。**再利用**: `RecordCard` / `parseRecordMessage` / `PfcBalanceCard` / `WeightNutritionChart` / `aggregateDailyNutrition` / `getMealRecords` / `getWeightRecords`。

**設計判断:** トレーナーは記録を**見る側**（閲覧専用パネル、送信フローなし）。Design Tokens（Primary `#0F172A` / Accent `#14B8A6` / border `#E2E8F0` / rounded-md=6px / 8pxグリッド）。サイドパネル幅 `w-96`（384px、`PfcBalanceCard` の `min-w-[320px]` に対応）。記録判定は基盤フェーズの `parseRecordMessage(content, tags)` を使う（`tags` 非空＝記録）。

> **実装前メモ（マネージャー対応）:** UI実装の直前に `ui-ux-pro-max` でサイドパネルのレイアウト/余白/配色を磨き、その指示を nextjs-ui 委託プロンプトに含めること（CLAUDE.md フロー）。本計画は Design Tokens に沿った骨子を提供する。

---

## File Structure

- **Create** `fit-connect/src/components/message/recordLog.ts` — `extractRecordLog`/`filterByType` 純関数（messages→記録ログ抽出と種別フィルタ）
- **Create** `fit-connect/src/components/message/recordLog.test.ts`
- **Create** `fit-connect/src/components/message/RecordSidePanel.tsx` — サイドパネル本体（ヘッダー＋サマリー＋種別フィルタ＋ログ）
- **Modify** `fit-connect/src/app/(user_console)/message/page.tsx` — 第3カラム統合・開閉state・サマリーデータ取得・トグルボタン

---

## Task 1: 記録ログ抽出/フィルタの純関数 ＋ テスト（TDD）

**Files:**
- Create: `fit-connect/src/components/message/recordLog.ts`
- Test: `fit-connect/src/components/message/recordLog.test.ts`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect/src/components/message/recordLog.test.ts`:
```ts
import { describe, it, expect } from 'vitest'
import type { Message } from '@/types/client'
import { extractRecordLog, filterByType } from '@/components/message/recordLog'

function msg(id: string, content: string, tags?: string[] | null): Message {
  return {
    id, sender: 'c', content, timestamp: '', created_at: '2026-01-01T00:00:00Z',
    senderType: 'client', receiverType: 'trainer', image_urls: [], tags,
    is_edited: false, edited_at: null, read_at: null, reply_to_message_id: null,
  } as Message
}

describe('extractRecordLog', () => {
  it('tagsが非空のメッセージだけを記録として抽出しcardを付与', () => {
    const list = [
      msg('1', 'こんにちは'),
      msg('2', '#食事:昼食 サラダ', ['#食事:昼食']),
      msg('3', '#体重 62kg', ['#体重']),
    ]
    const out = extractRecordLog(list)
    expect(out).toHaveLength(2)
    expect(out[0].card.type).toBe('meal')
    expect(out[1].card.type).toBe('weight')
  })
  it('ワークアウト達成(#なし)も記録として拾う', () => {
    const list = [msg('1', '本日のワークアウトプラン「脚の日」を達成しました！')]
    const out = extractRecordLog(list)
    expect(out).toHaveLength(1)
    expect(out[0].card.type).toBe('achievement')
  })
})

describe('filterByType', () => {
  const items = extractRecordLog([
    msg('1', '#食事:昼食 サラダ', ['#食事:昼食']),
    msg('2', '#体重 62kg', ['#体重']),
    msg('3', '#運動:筋トレ ベンチ', ['#運動:筋トレ']),
  ])
  it('all は全件', () => {
    expect(filterByType(items, 'all')).toHaveLength(3)
  })
  it('meal は食事だけ', () => {
    const out = filterByType(items, 'meal')
    expect(out).toHaveLength(1)
    expect(out[0].card.type).toBe('meal')
  })
})
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect && npx vitest run src/components/message/recordLog.test.ts`
Expected: FAIL（`recordLog.ts` が無い）
※ vitest が無ければ `npm install` してから。

- [ ] **Step 3: 実装を書く**

`fit-connect/src/components/message/recordLog.ts`:
```ts
import type { Message } from '@/types/client'
import {
  parseRecordMessage,
  type RecordCardData,
  type RecordCardType,
} from '@/components/message/recordCardParser'

export interface RecordLogItem {
  message: Message
  card: RecordCardData
}

/** messages から記録（parseRecordMessage が非nullを返すもの）だけを抽出し、card を付与する。 */
export function extractRecordLog(messages: Message[]): RecordLogItem[] {
  const items: RecordLogItem[] = []
  for (const m of messages) {
    const card = parseRecordMessage(m.content, m.tags)
    if (card) items.push({ message: m, card })
  }
  return items
}

/** 種別（all/weight/meal/exercise/achievement）で絞り込む。 */
export function filterByType(
  items: RecordLogItem[],
  type: RecordCardType | 'all',
): RecordLogItem[] {
  if (type === 'all') return items
  return items.filter((it) => it.card.type === type)
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd fit-connect && npx vitest run src/components/message/recordLog.test.ts`
Expected: PASS（4 tests）

- [ ] **Step 5: コミット**

```bash
git add fit-connect/src/components/message/recordLog.ts fit-connect/src/components/message/recordLog.test.ts
git commit -m "feat(web): 記録ログ抽出/種別フィルタの純関数を追加"
```

---

## Task 2: RecordSidePanel コンポーネント

**Files:**
- Create: `fit-connect/src/components/message/RecordSidePanel.tsx`

事前確認（実装者は実コードで props を確認すること）:
- `PfcBalanceCard`（`src/components/clients/PfcBalanceCard.tsx`）: props `{ data: DailyNutritionPoint[], targets? }`、`min-w-[320px]`
- `WeightNutritionChart`（`src/components/clients/WeightNutritionChart.tsx`）: props `{ data: DailyNutritionPoint[], targetWeight?: number, loading?: boolean }`
- `RecordCard`（`src/components/message/RecordCard.tsx`）: props `{ data: RecordCardData, clientId?, imageUrls?, onImageClick? }`
- `DailyNutritionPoint`（`src/lib/nutrition/aggregate.ts`）: `{ date, weight, calories, protein, fat, carbs }`
- `RecordCardType`（`src/components/message/recordCardParser.ts`）: `'weight'|'meal'|'exercise'|'achievement'`

- [ ] **Step 1: コンポーネントを作成**

`fit-connect/src/components/message/RecordSidePanel.tsx`:
```tsx
'use client'

import { useMemo, useState } from 'react'
import { X, ClipboardList } from 'lucide-react'
import type { Message } from '@/types/client'
import type { DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import type { RecordCardType } from '@/components/message/recordCardParser'
import { RecordCard } from '@/components/message/RecordCard'
import { PfcBalanceCard } from '@/components/clients/PfcBalanceCard'
import { WeightNutritionChart } from '@/components/clients/WeightNutritionChart'
import { extractRecordLog, filterByType } from '@/components/message/recordLog'

interface RecordSidePanelProps {
  messages: Message[]
  clientId: string
  nutritionData: DailyNutritionPoint[]
  targetWeight?: number
  summaryLoading?: boolean
  onClose: () => void
  onImageClick: (url: string) => void
}

const TYPE_TABS: { value: RecordCardType | 'all'; label: string }[] = [
  { value: 'all', label: 'すべて' },
  { value: 'meal', label: '食事' },
  { value: 'weight', label: '体重' },
  { value: 'exercise', label: '運動' },
]

export function RecordSidePanel({
  messages,
  clientId,
  nutritionData,
  targetWeight,
  summaryLoading,
  onClose,
  onImageClick,
}: RecordSidePanelProps) {
  const [typeFilter, setTypeFilter] = useState<RecordCardType | 'all'>('all')

  // 記録ログ（新しい順）。messages は古→新なので reverse。
  const logItems = useMemo(() => {
    const all = extractRecordLog(messages)
    return filterByType(all, typeFilter).reverse()
  }, [messages, typeFilter])

  return (
    <aside className="w-96 bg-white border-l border-[#E2E8F0] flex flex-col">
      {/* ヘッダー */}
      <div className="px-4 py-4 border-b border-[#E2E8F0] flex items-center justify-between">
        <div className="flex items-center gap-2 text-[#0F172A]">
          <ClipboardList size={18} className="text-[#14B8A6]" />
          <h2 className="text-base font-semibold">記録</h2>
        </div>
        <button
          onClick={onClose}
          className="text-[#94A3B8] hover:text-[#0F172A] transition-colors"
          aria-label="記録パネルを閉じる"
        >
          <X size={18} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto">
        {/* サマリー（B） */}
        <div className="p-4 border-b border-[#E2E8F0] space-y-4">
          <p className="text-xs font-semibold text-[#64748B] uppercase tracking-wide">サマリー</p>
          <PfcBalanceCard data={nutritionData} />
          <WeightNutritionChart data={nutritionData} targetWeight={targetWeight} loading={summaryLoading} />
        </div>

        {/* 種別フィルタ（C上部） */}
        <div className="px-4 pt-4 flex flex-wrap gap-2">
          {TYPE_TABS.map((t) => (
            <button
              key={t.value}
              onClick={() => setTypeFilter(t.value)}
              className={`px-3 py-1 rounded-md text-sm border transition-colors ${
                typeFilter === t.value
                  ? 'bg-[#14B8A6] text-white border-[#14B8A6]'
                  : 'bg-white text-[#64748B] border-[#E2E8F0] hover:border-[#14B8A6]'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {/* 記録ログ（C） */}
        <div className="p-4 space-y-3">
          {logItems.length === 0 ? (
            <p className="text-sm text-[#94A3B8] text-center py-8">記録がありません</p>
          ) : (
            logItems.map(({ message, card }) => (
              <RecordCard
                key={message.id}
                data={card}
                clientId={clientId}
                imageUrls={message.image_urls ?? undefined}
                onImageClick={onImageClick}
              />
            ))
          )}
        </div>
      </div>
    </aside>
  )
}
```

- [ ] **Step 2: 型チェック**

Run: `cd fit-connect && npx tsc --noEmit`
Expected: 新規エラーなし。`PfcBalanceCard`/`WeightNutritionChart` の props が想定と違えばここで判明 → 実コードに合わせて修正（props 名・必須/任意を確認）。

- [ ] **Step 3: コミット**

```bash
git add fit-connect/src/components/message/RecordSidePanel.tsx
git commit -m "feat(web): 記録サイドパネルのコンポーネントを追加"
```

---

## Task 3: page.tsx に統合（第3カラム・開閉state・サマリー取得・トグル）

**Files:**
- Modify: `fit-connect/src/app/(user_console)/message/page.tsx`

- [ ] **Step 1: import を追加**

`page.tsx` 冒頭の import 群に追加:
```tsx
import { RecordSidePanel } from '@/components/message/RecordSidePanel'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { aggregateDailyNutrition, type DailyNutritionPoint } from '@/lib/nutrition/aggregate'
import { PanelRightOpen } from 'lucide-react'
```
（`getMealRecords`/`getWeightRecords` の正確な戻り型・引数は実コードで確認: 調査では `getMealRecords({ clientId, limit, offset }) → { data: MealRecord[], count }`、`getWeightRecords(clientId) → WeightRecord[]`）

- [ ] **Step 2: state を追加**

`MessageContent` の state 群（L43-60 付近）の末尾に追加:
```tsx
    const [isRecordPanelOpen, setIsRecordPanelOpen] = useState(true);
    const [nutritionData, setNutritionData] = useState<DailyNutritionPoint[]>([]);
    const [summaryLoading, setSummaryLoading] = useState(false);
```

- [ ] **Step 3: 選択クライアントのサマリーデータを取得する useEffect を追加**

既存の useEffect 群の近くに追加（`selectedClient` 変化時に meal/weight を取得して集計）:
```tsx
    useEffect(() => {
        const cid = selectedClient?.client_id;
        if (!cid) {
            setNutritionData([]);
            return;
        }
        let cancelled = false;
        (async () => {
            setSummaryLoading(true);
            try {
                const [mealsRes, weights] = await Promise.all([
                    getMealRecords({ clientId: cid, limit: 1000, offset: 0 }),
                    getWeightRecords(cid),
                ]);
                if (cancelled) return;
                const meals = Array.isArray(mealsRes) ? mealsRes : mealsRes.data;
                setNutritionData(aggregateDailyNutrition(meals, weights, 'month'));
            } catch (e) {
                if (!cancelled) setNutritionData([]);
                console.error('記録サマリー取得エラー:', e);
            } finally {
                if (!cancelled) setSummaryLoading(false);
            }
        })();
        return () => { cancelled = true; };
    }, [selectedClient?.client_id]);
```
（`getMealRecords` の戻りが `{data,count}` か配列かは実コードで確認し、`meals` の取り出しを適切に。`'month'` は `PeriodFilter`）

- [ ] **Step 4: チャットヘッダーに開閉トグルボタンを追加**

`ChatHeader`（L466-475）の直後、`{/* Messages */}` の前に、パネルが閉じている時だけ開くボタンを置く（または ChatHeader 内に置く方針なら ChatHeader を拡張）。最小実装として Messages 領域の上にツールバー行を追加:
```tsx
                {!isRecordPanelOpen && selectedClient && (
                    <div className="flex justify-end px-4 py-2 border-b border-[#E2E8F0] bg-white">
                        <button
                            onClick={() => setIsRecordPanelOpen(true)}
                            className="flex items-center gap-1 text-sm text-[#14B8A6] hover:text-[#0D9488]"
                        >
                            <PanelRightOpen size={16} /> 記録を表示
                        </button>
                    </div>
                )}
```

- [ ] **Step 5: 第3カラムとして RecordSidePanel を配置**

チャット領域の閉じ `</div>`（L560）と `{/* 画像拡大モーダル */}`（L562）の**間**に追加:
```tsx
            {/* 記録サイドパネル（開閉式・デフォルト開） */}
            {isRecordPanelOpen && selectedClient && (
                <RecordSidePanel
                    messages={messages}
                    clientId={selectedClient.client_id}
                    nutritionData={nutritionData}
                    targetWeight={selectedClient.target_weight ?? undefined}
                    summaryLoading={summaryLoading}
                    onClose={() => setIsRecordPanelOpen(false)}
                    onImageClick={setSelectedImageUrl}
                />
            )}
```
（`selectedClient.target_weight` の型は `Client` 型で確認。無ければ `undefined`）

- [ ] **Step 6: 型チェック**

Run: `cd fit-connect && npx tsc --noEmit`
Expected: 新規エラーなし

- [ ] **Step 7: コミット**

```bash
git add "fit-connect/src/app/(user_console)/message/page.tsx"
git commit -m "feat(web): メッセージ画面に記録サイドパネルを統合（開閉式・デフォルト開）"
```

---

## QA（実装後）

`chrome-web-qa` スキルで以下を確認:
- メッセージ画面の右側に記録パネルが開いた状態で表示される
- パネル上部にサマリー（PFC・体重推移チャート）が出る
- 種別フィルタ（すべて/食事/体重/運動）で記録ログが絞れる
- 記録ログに食事/体重/運動/達成カードが新しい順で並ぶ
- ✕ で閉じ、「記録を表示」で再度開く
- 会話タイムライン（中央）は従来どおり混在表示で、入力欄も従来どおり動く

---

## Self-Review

**1. Spec coverage（設計書の案②要件 → タスク対応）:**
- 会話メイン＋記録サイドパネル（開閉式・デフォルト開）→ Task 3 Step 2・5（`isRecordPanelOpen=true` 初期値）✅
- パネル中身 B＋C（サマリー＋フィルタ＋ログ）→ Task 2（PfcBalanceCard/WeightNutritionChart＋種別タブ＋RecordCard）✅
- トレーナーは閲覧専用（送信フローなし）→ パネルに入力UIなし ✅
- 記録判定は tags ベース（基盤フェーズ）→ Task 1 が `parseRecordMessage(content, tags)` を使用 ✅
- データ源分離（サマリー=records、ログ=messages）→ Task 3 useEffect（meal/weight_records）と Task 2（messages）で分離 ✅

**2. Placeholder scan:** 各ステップに実コードを記載。再利用コンポーネントの props は「実コードで確認」と明示（Task 2 事前確認・Task 3 Step 1/3/5 の注記）。これは TODO ではなく検証指示。

**3. Type consistency:**
- `RecordLogItem`/`extractRecordLog`/`filterByType`（Task 1）→ Task 2 で同名・同シグネチャ使用 ✅
- `RecordCardType`（'weight'|'meal'|'exercise'|'achievement'）→ Task 1 filterByType / Task 2 TYPE_TABS で一貫 ✅
- `DailyNutritionPoint`（aggregate.ts）→ Task 2 props / Task 3 state で一貫 ✅
- `RecordSidePanel` props（messages/clientId/nutritionData/targetWeight/summaryLoading/onClose/onImageClick）→ Task 2 定義 = Task 3 Step 5 呼び出し ✅
