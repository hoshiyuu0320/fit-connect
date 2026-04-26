# トレーナー週間スケジュール管理機能 — 基本設計書

## 1. 概要

### 目的
トレーナーが自身の対応可能時間帯（曜日ベースの定期スケジュール）を設定・管理できるようにする。
設定されたスケジュールはクライアント側アプリに反映され、オフライン時間帯にはバナーが表示される。

### 前提条件
- **DBテーブル `trainer_schedules` は作成済み**（クライアント側アプリで実装済み）
- **RLSポリシーも適用済み**（トレーナーが自身のスケジュールをCRUD可能）
- テストデータ投入済み（月〜金 9:00-18:00）

### テーブル構造（既存）
```sql
trainer_schedules (
  id uuid PRIMARY KEY,
  trainer_id uuid NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  day_of_week int NOT NULL CHECK (0-6),  -- 0=日, 1=月, ..., 6=土
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz,
  updated_at timestamptz,
  UNIQUE(trainer_id, day_of_week)
)
```

---

## 2. 機能要件

### 2.1 スケジュール一覧表示
- 月〜日の7曜日のスケジュールを一覧表示
- 各曜日ごとに「対応可能」「休み」の状態を表示
- 対応可能な場合は開始時刻・終了時刻を表示

### 2.2 スケジュール編集
- 各曜日の「対応可能/休み」をトグルで切替
- 対応可能の場合、開始時刻・終了時刻を設定
- 変更は「保存」ボタンで一括保存（UPSERTパターン）

### 2.3 クライアント側への即時反映
- 保存完了後、クライアント側アプリでリアルタイムにステータスが切り替わる
- 追加対応不要（クライアント側は毎回DBから取得するため）

---

## 3. 画面設計

### 3.1 配置場所: 設定ページ (`/settings`)

既存の設定ページ構成:
```
設定
├── ProfileSection      ← プロフィール情報
├── PasswordSection     ← パスワード変更
├── ScheduleSection     ← ★ 新規追加
├── NotificationSection ← 通知設定
└── AccountSection      ← アカウント管理
```

**理由:** スケジュールはトレーナーの基本設定であり、設定ページの一セクションとして自然。
既存の `/schedule` ページ（セッション管理カレンダー）とは用途が異なる。

### 3.2 UI モックアップ

```
┌─────────────────────────────────────────────┐
│ 対応スケジュール                    [保存]  │
│ クライアントに表示される対応可能時間帯       │
├─────────────────────────────────────────────┤
│                                             │
│  月曜日    ● 対応可能   09:00 〜 18:00      │
│  火曜日    ● 対応可能   09:00 〜 18:00      │
│  水曜日    ● 対応可能   09:00 〜 18:00      │
│  木曜日    ● 対応可能   09:00 〜 18:00      │
│  金曜日    ● 対応可能   09:00 〜 18:00      │
│  土曜日    ○ 休み                           │
│  日曜日    ○ 休み                           │
│                                             │
└─────────────────────────────────────────────┘
```

**対応可能の行:**
```
  月曜日    [●○ トグル]   [09:00 ▼] 〜 [18:00 ▼]
```

**休みの行:**
```
  土曜日    [●○ トグル]   (時刻セレクタは非表示 or グレーアウト)
```

---

## 4. 技術設計

### 4.1 ファイル構成

```
src/
├── components/settings/
│   └── ScheduleSection.tsx          ← 新規: スケジュール設定セクション
├── lib/supabase/
│   ├── getTrainerSchedules.ts       ← 新規: スケジュール取得
│   └── upsertTrainerSchedules.ts    ← 新規: スケジュール一括保存
├── app/api/trainer-schedules/
│   └── route.ts                     ← 新規: APIルート (GET/PUT)
└── types/
    └── schedule.ts                  ← 新規: 型定義
```

### 4.2 型定義

**ファイル:** `src/types/schedule.ts`

```typescript
export type TrainerSchedule = {
  id: string
  trainer_id: string
  day_of_week: number    // 0=日, 1=月, ..., 6=土
  start_time: string     // "HH:mm:ss"
  end_time: string       // "HH:mm:ss"
  is_available: boolean
  created_at: string
  updated_at: string
}

// 保存時のパラメータ（idは不要、UPSERTのため）
export type UpsertScheduleItem = {
  day_of_week: number
  start_time: string
  end_time: string
  is_available: boolean
}

// UIのローカル状態用
export type ScheduleFormItem = {
  dayOfWeek: number
  label: string          // "月曜日" 等
  isAvailable: boolean
  startTime: string      // "09:00"
  endTime: string        // "18:00"
}
```

### 4.3 Supabase データ取得関数

**ファイル:** `src/lib/supabase/getTrainerSchedules.ts`

```typescript
import { supabase } from '../supabase'
import type { TrainerSchedule } from '@/types/schedule'

export async function getTrainerSchedules(
  trainerId: string
): Promise<TrainerSchedule[]> {
  const { data, error } = await supabase
    .from('trainer_schedules')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('day_of_week', { ascending: true })

  if (error) throw error
  return data ?? []
}
```

### 4.4 Supabase 一括保存関数

**ファイル:** `src/lib/supabase/upsertTrainerSchedules.ts`

```typescript
import { supabaseAdmin } from '../supabaseAdmin'
import type { UpsertScheduleItem } from '@/types/schedule'

export async function upsertTrainerSchedules(
  trainerId: string,
  schedules: UpsertScheduleItem[]
) {
  const rows = schedules.map((s) => ({
    trainer_id: trainerId,
    day_of_week: s.day_of_week,
    start_time: s.start_time,
    end_time: s.end_time,
    is_available: s.is_available,
  }))

  const { data, error } = await supabaseAdmin
    .from('trainer_schedules')
    .upsert(rows, { onConflict: 'trainer_id,day_of_week' })
    .select()

  if (error) throw error
  return data
}
```

**ポイント:**
- `onConflict: 'trainer_id,day_of_week'` でUNIQUE制約を利用したUPSERT
- 7曜日分を一括で送信し、存在すればUPDATE・なければINSERT
- `supabaseAdmin` を使用（APIルート経由で呼び出し）

### 4.5 API ルート

**ファイル:** `src/app/api/trainer-schedules/route.ts`

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { getTrainerSchedules } from '@/lib/supabase/getTrainerSchedules'
import { upsertTrainerSchedules } from '@/lib/supabase/upsertTrainerSchedules'

// GET: スケジュール取得
export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url)
  const trainerId = searchParams.get('trainerId')

  if (!trainerId) {
    return NextResponse.json(
      { error: 'trainerId is required' },
      { status: 400 }
    )
  }

  try {
    const schedules = await getTrainerSchedules(trainerId)
    return NextResponse.json({ data: schedules })
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to fetch schedules' },
      { status: 500 }
    )
  }
}

// PUT: スケジュール一括保存
export async function PUT(request: NextRequest) {
  const body = await request.json()
  const { trainerId, schedules } = body

  if (!trainerId || !schedules) {
    return NextResponse.json(
      { error: 'trainerId and schedules are required' },
      { status: 400 }
    )
  }

  try {
    const data = await upsertTrainerSchedules(trainerId, schedules)
    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to update schedules' },
      { status: 500 }
    )
  }
}
```

### 4.6 UI コンポーネント

**ファイル:** `src/components/settings/ScheduleSection.tsx`

```typescript
'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Clock } from 'lucide-react'
import type { Trainer } from '@/types/trainer'
import type { ScheduleFormItem } from '@/types/schedule'

const DAY_LABELS = ['日曜日', '月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日']

// 月曜始まりで表示（曜日順: 1,2,3,4,5,6,0）
const DISPLAY_ORDER = [1, 2, 3, 4, 5, 6, 0]

const TIME_OPTIONS = [
  '06:00', '06:30', '07:00', '07:30', '08:00', '08:30',
  '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
  '12:00', '12:30', '13:00', '13:30', '14:00', '14:30',
  '15:00', '15:30', '16:00', '16:30', '17:00', '17:30',
  '18:00', '18:30', '19:00', '19:30', '20:00', '20:30',
  '21:00', '21:30', '22:00',
]

const DEFAULT_SCHEDULE: ScheduleFormItem[] = DISPLAY_ORDER.map((dow) => ({
  dayOfWeek: dow,
  label: DAY_LABELS[dow],
  isAvailable: false,
  startTime: '09:00',
  endTime: '18:00',
}))

type Props = {
  trainer: Trainer
}

export function ScheduleSection({ trainer }: Props) {
  const [schedules, setSchedules] = useState<ScheduleFormItem[]>(DEFAULT_SCHEDULE)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  // 初期データ取得
  useEffect(() => {
    const fetchSchedules = async () => {
      try {
        const res = await fetch(`/api/trainer-schedules?trainerId=${trainer.id}`)
        const { data } = await res.json()

        if (data && data.length > 0) {
          setSchedules(
            DISPLAY_ORDER.map((dow) => {
              const existing = data.find(
                (s: { day_of_week: number }) => s.day_of_week === dow
              )
              return {
                dayOfWeek: dow,
                label: DAY_LABELS[dow],
                isAvailable: existing?.is_available ?? false,
                startTime: existing?.start_time?.substring(0, 5) ?? '09:00',
                endTime: existing?.end_time?.substring(0, 5) ?? '18:00',
              }
            })
          )
        }
      } catch (error) {
        console.error('スケジュール取得エラー:', error)
      }
    }

    fetchSchedules()
  }, [trainer.id])

  // トグル切替
  const handleToggle = (dayOfWeek: number) => {
    setSchedules((prev) =>
      prev.map((s) =>
        s.dayOfWeek === dayOfWeek ? { ...s, isAvailable: !s.isAvailable } : s
      )
    )
  }

  // 時刻変更
  const handleTimeChange = (
    dayOfWeek: number,
    field: 'startTime' | 'endTime',
    value: string
  ) => {
    setSchedules((prev) =>
      prev.map((s) =>
        s.dayOfWeek === dayOfWeek ? { ...s, [field]: value } : s
      )
    )
  }

  // 保存
  const handleSave = async () => {
    setSaving(true)
    setMessage(null)

    try {
      const payload = schedules.map((s) => ({
        day_of_week: s.dayOfWeek,
        start_time: s.startTime + ':00',   // "HH:mm" → "HH:mm:00"
        end_time: s.endTime + ':00',
        is_available: s.isAvailable,
      }))

      const res = await fetch('/api/trainer-schedules', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerId: trainer.id,
          schedules: payload,
        }),
      })

      if (!res.ok) throw new Error('保存に失敗しました')

      setMessage('スケジュールを保存しました')
      setTimeout(() => setMessage(null), 3000)
    } catch (error) {
      setMessage('保存に失敗しました。再度お試しください。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle className="flex items-center gap-2">
            <Clock className="h-5 w-5" />
            対応スケジュール
          </CardTitle>
          <p className="text-sm text-gray-500 mt-1">
            クライアントに表示される対応可能時間帯
          </p>
        </div>
        <Button onClick={handleSave} disabled={saving}>
          {saving ? '保存中...' : '保存'}
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {/* 成功/エラーメッセージ */}
        {message && (
          <div className={`text-sm px-3 py-2 rounded ${
            message.includes('失敗')
              ? 'bg-red-50 text-red-600'
              : 'bg-green-50 text-green-600'
          }`}>
            {message}
          </div>
        )}

        {/* 曜日リスト */}
        {schedules.map((schedule) => (
          <ScheduleRow
            key={schedule.dayOfWeek}
            schedule={schedule}
            onToggle={() => handleToggle(schedule.dayOfWeek)}
            onTimeChange={(field, value) =>
              handleTimeChange(schedule.dayOfWeek, field, value)
            }
          />
        ))}
      </CardContent>
    </Card>
  )
}

// 各曜日の行コンポーネント
function ScheduleRow({
  schedule,
  onToggle,
  onTimeChange,
}: {
  schedule: ScheduleFormItem
  onToggle: () => void
  onTimeChange: (field: 'startTime' | 'endTime', value: string) => void
}) {
  return (
    <div className="flex items-center gap-4 py-2 border-b border-gray-100 last:border-0">
      {/* 曜日ラベル */}
      <span className="w-16 text-sm font-medium text-gray-700">
        {schedule.label}
      </span>

      {/* トグルボタン */}
      <button
        type="button"
        onClick={onToggle}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
          schedule.isAvailable ? 'bg-blue-600' : 'bg-gray-300'
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
            schedule.isAvailable ? 'translate-x-6' : 'translate-x-1'
          }`}
        />
      </button>

      {/* ステータスラベル */}
      <span className={`text-xs w-16 ${
        schedule.isAvailable ? 'text-blue-600' : 'text-gray-400'
      }`}>
        {schedule.isAvailable ? '対応可能' : '休み'}
      </span>

      {/* 時刻セレクタ */}
      {schedule.isAvailable ? (
        <div className="flex items-center gap-2">
          <select
            value={schedule.startTime}
            onChange={(e) => onTimeChange('startTime', e.target.value)}
            className="text-sm border border-gray-300 rounded px-2 py-1"
          >
            {TIME_OPTIONS.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
          <span className="text-gray-400">〜</span>
          <select
            value={schedule.endTime}
            onChange={(e) => onTimeChange('endTime', e.target.value)}
            className="text-sm border border-gray-300 rounded px-2 py-1"
          >
            {TIME_OPTIONS.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>
      ) : (
        <div className="text-sm text-gray-300">—</div>
      )}
    </div>
  )
}
```

### 4.7 設定ページへの組み込み

**ファイル:** `src/app/(user_console)/settings/page.tsx`

```diff
  import { ProfileSection } from '@/components/settings/ProfileSection'
  import { PasswordSection } from '@/components/settings/PasswordSection'
+ import { ScheduleSection } from '@/components/settings/ScheduleSection'
  import { NotificationSection } from '@/components/settings/NotificationSection'
  import { AccountSection } from '@/components/settings/AccountSection'

  ...

        <ProfileSection trainer={trainer} onUpdate={handleUpdate} />
        <PasswordSection />
+       <ScheduleSection trainer={trainer} />
        <NotificationSection />
        <AccountSection onLogout={handleLogout} />
```

---

## 5. データフロー

```
[設定ページ]
  ↓ useEffect
  ├─ GET /api/trainer-schedules?trainerId=xxx
  │   └─ getTrainerSchedules() → supabase (RLS)
  │       └─ trainer_schedules テーブル SELECT
  │
  ↓ 保存ボタン押下
  ├─ PUT /api/trainer-schedules
  │   └─ upsertTrainerSchedules() → supabaseAdmin
  │       └─ trainer_schedules テーブル UPSERT (7行)
  │
  ↓ クライアント側への反映
  └─ クライアントアプリが次回 trainerSchedulesProvider を
     watch した時点で最新データを取得（自動反映）
```

---

## 6. バリデーションルール

| 項目 | ルール |
|------|--------|
| start_time | end_time より前であること |
| end_time | start_time より後であること |
| 時刻範囲 | 06:00 〜 22:00（UIのセレクタで制限） |
| is_available | boolean。false の場合、時刻は保存時にデフォルト値 |

**バリデーション実装場所:** `ScheduleSection` コンポーネントの `handleSave` 内

```typescript
// バリデーション例
const invalid = schedules.find(
  (s) => s.isAvailable && s.startTime >= s.endTime
)
if (invalid) {
  setMessage(`${invalid.label}の開始時刻は終了時刻より前にしてください`)
  return
}
```

---

## 7. 実装タスク一覧

| # | タスク | ファイル | 工数目安 |
|---|--------|---------|---------|
| 1 | 型定義作成 | `src/types/schedule.ts` | 小 |
| 2 | スケジュール取得関数 | `src/lib/supabase/getTrainerSchedules.ts` | 小 |
| 3 | スケジュール保存関数 | `src/lib/supabase/upsertTrainerSchedules.ts` | 小 |
| 4 | APIルート (GET/PUT) | `src/app/api/trainer-schedules/route.ts` | 中 |
| 5 | ScheduleSection UI | `src/components/settings/ScheduleSection.tsx` | 大 |
| 6 | 設定ページに組み込み | `src/app/(user_console)/settings/page.tsx` | 小 |

**推奨実装順序:** 1 → 2 → 3 → 4 → 5 → 6

---

## 8. 将来の拡張案

### 8.1 ダッシュボードへのステータス表示
ダッシュボード上部に「現在のステータス: 対応可能 / オフライン」を表示。
既存の `StatCard` コンポーネントパターンを活用。

### 8.2 一時的なスケジュール変更（臨時休業）
特定日のみ休みにする機能。`trainer_schedule_overrides` テーブルを追加し、
曜日ベースのスケジュールを日付ベースで上書き。

### 8.3 メッセージ画面への連動
トレーナー側メッセージ画面で「現在オフライン時間帯です」のバナー表示。
自身のスケジュール外にメッセージを送信する際の自覚促進。

---

## 9. 注意事項

- **タイムゾーン:** DBの `time` 型はタイムゾーンなし。UIでは JST として表示・入力。
  Supabase の time 型は時刻のみ保存するため、タイムゾーン変換は不要。
- **RLS:** `getTrainerSchedules()` はクライアント用 supabase で呼び出し可能
  （RLSポリシー "Trainers can view own schedules" が適用される）。
  `upsertTrainerSchedules()` は supabaseAdmin 経由（APIルート内）で実行。
- **UNIQUE制約:** `(trainer_id, day_of_week)` のUNIQUE制約により、
  同一曜日の重複レコードは発生しない。UPSERT で安全に更新可能。
