# 顧客管理機能 API設計書

## 📋 目次
1. [API概要](#api概要)
2. [認証・認可](#認証認可)
3. [エンドポイント一覧](#エンドポイント一覧)
4. [データベースクエリ関数](#データベースクエリ関数)
5. [エラーハンドリング](#エラーハンドリング)

---

## API概要

### アーキテクチャ
顧客管理機能は主に**Supabaseクエリ関数**を使用してデータ取得を行います。
API Routesは必要最小限に留め、以下の場合のみ使用します：

1. 複雑なビジネスロジックが必要な場合
2. 外部APIとの連携が必要な場合（画像認識APIなど）
3. トランザクション処理が必要な場合

### データアクセスパターン
```
Client Component (React)
    ↓
Supabase Query Function (src/lib/supabase/)
    ↓
Supabase Client (supabase.ts)
    ↓
Supabase Database (RLS適用済み)
```

---

## 認証・認可

### 認証方式
- **Supabase Auth**を使用
- JWTトークンによるセッション管理
- トレーナーのみアクセス可能

### Row Level Security (RLS)
すべてのテーブルでRLSが有効化されており、以下のポリシーが適用されます：

```sql
-- トレーナーは自分が担当するクライアントのみアクセス可能
clients: trainer_id = auth.uid()

-- クライアント関連データも同様
weight_records: client_id IN (SELECT client_id FROM clients WHERE trainer_id = auth.uid())
meal_records: client_id IN (SELECT client_id FROM clients WHERE trainer_id = auth.uid())
exercise_records: client_id IN (SELECT client_id FROM clients WHERE trainer_id = auth.uid())
tickets: client_id IN (SELECT client_id FROM clients WHERE trainer_id = auth.uid())
```

---

## エンドポイント一覧

### データベースクエリ関数（推奨）

顧客管理機能では、以下のSupabaseクエリ関数を作成・使用します：

#### 1. 顧客情報取得

##### `getClients(trainerId: string)`
トレーナーが担当するすべてのクライアントを取得

**ファイルパス:** `src/lib/supabase/getClients.ts`（既存）

**パラメータ:**
| パラメータ | 型 | 必須 | 説明 |
|----------|-----|------|------|
| trainerId | string | ○ | トレーナーID |

**戻り値:**
```typescript
type Client = {
  client_id: string
  trainer_id: string
  name: string
  gender: 'male' | 'female' | 'other'
  age: number
  occupation: string | null
  height: number
  target_weight: number
  purpose: 'diet' | 'contest' | 'body_make' | 'health_improvement' | 'mental_improvement' | 'performance_improvement'
  goal_description: string | null
  profile_image_url: string | null
  line_user_id: string | null
  created_at: string
}

Promise<Client[]>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getClients = async (trainerId: string) => {
  const { data, error } = await supabase
    .from('clients')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('name', { ascending: true })

  if (error) throw error
  return data
}
```

---

##### `getClientDetail(clientId: string)`
特定のクライアントの詳細情報を取得

**ファイルパス:** `src/lib/supabase/getClientDetail.ts`（新規作成）

**パラメータ:**
| パラメータ | 型 | 必須 | 説明 |
|----------|-----|------|------|
| clientId | string | ○ | クライアントID |

**戻り値:**
```typescript
type ClientDetail = Client & {
  current_weight?: number  // 最新の体重記録から算出
  initial_weight?: number  // 初回の体重記録
}

Promise<ClientDetail | null>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getClientDetail = async (clientId: string) => {
  // 基本情報取得
  const { data: client, error: clientError } = await supabase
    .from('clients')
    .select('*')
    .eq('client_id', clientId)
    .single()

  if (clientError) throw clientError

  // 最新の体重取得
  const { data: latestWeight } = await supabase
    .from('weight_records')
    .select('weight')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .limit(1)
    .single()

  // 初回の体重取得
  const { data: initialWeight } = await supabase
    .from('weight_records')
    .select('weight')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: true })
    .limit(1)
    .single()

  return {
    ...client,
    current_weight: latestWeight?.weight,
    initial_weight: initialWeight?.weight,
  }
}
```

---

#### 2. 体重記録取得

##### `getWeightRecords(clientId: string)`
特定のクライアントの体重記録を全件取得

**ファイルパス:** `src/lib/supabase/getWeightRecords.ts`（新規作成）

**パラメータ:**
| パラメータ | 型 | 必須 | 説明 |
|----------|-----|------|------|
| clientId | string | ○ | クライアントID |

**戻り値:**
```typescript
type WeightRecord = {
  id: string
  client_id: string
  weight: number
  recorded_at: string
}

Promise<WeightRecord[]>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getWeightRecords = async (clientId: string) => {
  const { data, error } = await supabase
    .from('weight_records')
    .select('*')
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: true })

  if (error) throw error
  return data
}
```

---

#### 3. 食事記録取得

##### `getMealRecords(params: GetMealRecordsParams)`
特定のクライアントの食事記録を取得（ページネーション対応）

**ファイルパス:** `src/lib/supabase/getMealRecords.ts`（新規作成）

**パラメータ:**
```typescript
type GetMealRecordsParams = {
  clientId: string
  mealType?: 'breakfast' | 'lunch' | 'dinner' | 'snack'  // フィルター（任意）
  limit?: number      // 取得件数（デフォルト: 20）
  offset?: number     // オフセット（デフォルト: 0）
}
```

**戻り値:**
```typescript
type MealRecord = {
  id: string
  client_id: string
  meal_type: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  description: string | null
  calories: number | null
  images: string[] | null
  recorded_at: string
}

type GetMealRecordsResult = {
  data: MealRecord[]
  count: number  // 総件数
}

Promise<GetMealRecordsResult>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getMealRecords = async ({
  clientId,
  mealType,
  limit = 20,
  offset = 0,
}: GetMealRecordsParams) => {
  let query = supabase
    .from('meal_records')
    .select('*', { count: 'exact' })
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .range(offset, offset + limit - 1)

  if (mealType) {
    query = query.eq('meal_type', mealType)
  }

  const { data, error, count } = await query

  if (error) throw error

  return {
    data: data || [],
    count: count || 0,
  }
}
```

---

#### 4. 運動記録取得

##### `getExerciseRecords(params: GetExerciseRecordsParams)`
特定のクライアントの運動記録を取得（ページネーション対応）

**ファイルパス:** `src/lib/supabase/getExerciseRecords.ts`（新規作成）

**パラメータ:**
```typescript
type GetExerciseRecordsParams = {
  clientId: string
  limit?: number      // 取得件数（デフォルト: 20）
  offset?: number     // オフセット（デフォルト: 0）
}
```

**戻り値:**
```typescript
type ExerciseRecord = {
  id: string
  client_id: string
  exercise_type: 'walking' | 'running' | 'strength_training' | 'cycling' | 'swimming' | 'yoga' | 'pilates' | 'other'
  duration: number | null
  distance: number | null
  calories: number | null
  memo: string | null
  recorded_at: string
}

type GetExerciseRecordsResult = {
  data: ExerciseRecord[]
  count: number
}

Promise<GetExerciseRecordsResult>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getExerciseRecords = async ({
  clientId,
  limit = 20,
  offset = 0,
}: GetExerciseRecordsParams) => {
  const { data, error, count } = await supabase
    .from('exercise_records')
    .select('*', { count: 'exact' })
    .eq('client_id', clientId)
    .order('recorded_at', { ascending: false })
    .range(offset, offset + limit - 1)

  if (error) throw error

  return {
    data: data || [],
    count: count || 0,
  }
}
```

---

#### 5. チケット取得

##### `getTickets(clientId: string)`
特定のクライアントのチケット情報を全件取得

**ファイルパス:** `src/lib/supabase/getTickets.ts`（新規作成）

**パラメータ:**
| パラメータ | 型 | 必須 | 説明 |
|----------|-----|------|------|
| clientId | string | ○ | クライアントID |

**戻り値:**
```typescript
type Ticket = {
  id: string
  client_id: string
  ticket_name: string
  ticket_type: string
  total_sessions: number
  remaining_sessions: number
  valid_from: string
  valid_until: string
  created_at: string
}

Promise<Ticket[]>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const getTickets = async (clientId: string) => {
  const { data, error } = await supabase
    .from('tickets')
    .select('*')
    .eq('client_id', clientId)
    .order('valid_until', { ascending: false })

  if (error) throw error
  return data
}
```

---

#### 6. 顧客フィルタリング・検索

##### `searchClients(params: SearchClientsParams)`
クライアントを検索・フィルタリングして取得

**ファイルパス:** `src/lib/supabase/searchClients.ts`（新規作成）

**パラメータ:**
```typescript
type SearchClientsParams = {
  trainerId: string
  searchQuery?: string      // 名前検索
  gender?: 'male' | 'female' | 'other'
  ageRange?: {
    min: number
    max: number
  }
  purpose?: string
}
```

**戻り値:**
```typescript
Promise<Client[]>
```

**実装例:**
```typescript
import { supabase } from '@/lib/supabase'

export const searchClients = async ({
  trainerId,
  searchQuery,
  gender,
  ageRange,
  purpose,
}: SearchClientsParams) => {
  let query = supabase
    .from('clients')
    .select('*')
    .eq('trainer_id', trainerId)
    .order('name', { ascending: true })

  if (searchQuery) {
    query = query.ilike('name', `%${searchQuery}%`)
  }

  if (gender) {
    query = query.eq('gender', gender)
  }

  if (ageRange) {
    query = query.gte('age', ageRange.min).lte('age', ageRange.max)
  }

  if (purpose) {
    query = query.eq('purpose', purpose)
  }

  const { data, error } = await query

  if (error) throw error
  return data
}
```

---

### API Routes（必要な場合のみ）

#### POST /api/clients/[client_id]/goal
クライアントの目標体重・目標説明を更新

**ファイルパス:** `src/app/api/clients/[client_id]/goal/route.ts`

**リクエスト:**
```typescript
{
  target_weight: number
  goal_description: string
}
```

**レスポンス:**
```typescript
{
  status: 'ok'
  data: Client
}
```

**実装例:**
```typescript
import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function POST(
  req: NextRequest,
  { params }: { params: { client_id: string } }
) {
  try {
    const { target_weight, goal_description } = await req.json()
    const { client_id } = params

    const { data, error } = await supabaseAdmin
      .from('clients')
      .update({ target_weight, goal_description })
      .eq('client_id', client_id)
      .select()
      .single()

    if (error) throw error

    return NextResponse.json({ status: 'ok', data })
  } catch (error) {
    return NextResponse.json(
      { status: 'error', message: error.message },
      { status: 500 }
    )
  }
}
```

---

## データベースクエリ関数

### ディレクトリ構造
```
src/lib/supabase/
├── getClients.ts               # 既存
├── getClientDetail.ts          # 新規
├── getWeightRecords.ts         # 新規
├── getMealRecords.ts           # 新規
├── getExerciseRecords.ts       # 新規
├── getTickets.ts               # 新規
├── searchClients.ts            # 新規
├── updateClientGoal.ts         # 新規（将来実装）
└── ...（既存の関数）
```

### TypeScript型定義

**ファイルパス:** `src/types/client.ts`（新規作成）

```typescript
// クライアント基本情報
export type Client = {
  client_id: string
  trainer_id: string
  name: string
  gender: 'male' | 'female' | 'other'
  age: number
  occupation: string | null
  height: number
  target_weight: number
  purpose: 'diet' | 'contest' | 'body_make' | 'health_improvement' | 'mental_improvement' | 'performance_improvement'
  goal_description: string | null
  profile_image_url: string | null
  line_user_id: string | null
  created_at: string
}

// クライアント詳細情報
export type ClientDetail = Client & {
  current_weight?: number
  initial_weight?: number
}

// 体重記録
export type WeightRecord = {
  id: string
  client_id: string
  weight: number
  recorded_at: string
}

// 食事記録
export type MealRecord = {
  id: string
  client_id: string
  meal_type: 'breakfast' | 'lunch' | 'dinner' | 'snack'
  description: string | null
  calories: number | null
  images: string[] | null
  recorded_at: string
}

// 運動記録
export type ExerciseRecord = {
  id: string
  client_id: string
  exercise_type: 'walking' | 'running' | 'strength_training' | 'cycling' | 'swimming' | 'yoga' | 'pilates' | 'other'
  duration: number | null
  distance: number | null
  calories: number | null
  memo: string | null
  recorded_at: string
}

// チケット
export type Ticket = {
  id: string
  client_id: string
  ticket_name: string
  ticket_type: string
  total_sessions: number
  remaining_sessions: number
  valid_from: string
  valid_until: string
  created_at: string
}

// 目的の選択肢
export const PURPOSE_OPTIONS = {
  diet: 'ダイエット',
  contest: 'コンテスト',
  body_make: 'ボディメイク',
  health_improvement: '健康維持・生活習慣の改善',
  mental_improvement: 'メンタル・自己肯定感向上',
  performance_improvement: 'パフォーマンス向上（競技・仕事）',
} as const

// 食事区分の選択肢
export const MEAL_TYPE_OPTIONS = {
  breakfast: '朝食',
  lunch: '昼食',
  dinner: '夕食',
  snack: '間食',
} as const

// 運動種目の選択肢
export const EXERCISE_TYPE_OPTIONS = {
  walking: 'ウォーキング',
  running: 'ランニング',
  strength_training: '筋力トレーニング',
  cycling: 'サイクリング',
  swimming: 'スイミング',
  yoga: 'ヨガ',
  pilates: 'ピラティス',
  other: 'その他',
} as const
```

---

## エラーハンドリング

### エラーレスポンス形式
```typescript
{
  status: 'error'
  message: string
  code?: string
}
```

### エラーコード一覧
| コード | 説明 | HTTPステータス |
|--------|------|----------------|
| UNAUTHORIZED | 認証エラー | 401 |
| FORBIDDEN | 権限エラー（RLS違反） | 403 |
| NOT_FOUND | リソースが見つからない | 404 |
| VALIDATION_ERROR | バリデーションエラー | 400 |
| INTERNAL_ERROR | サーバー内部エラー | 500 |

### エラーハンドリング例
```typescript
try {
  const clients = await getClients(trainerId)
  return clients
} catch (error) {
  if (error.code === 'PGRST116') {
    // RLSエラー
    throw new Error('アクセス権限がありません')
  }
  throw error
}
```

---

## パフォーマンス最適化

### 1. インデックス活用
- 検索クエリは必ずインデックスが設定されたカラムを使用
- `trainer_id`, `client_id`, `recorded_at`にはインデックスが設定済み

### 2. ページネーション
- 食事記録・運動記録は必ずページネーション（20件ずつ）
- `range()`関数を使用して効率的に取得

### 3. 不要なデータ取得の回避
- `select('*')`ではなく、必要なカラムのみ指定（将来的に最適化）
- JOIN時は必要最小限のカラムのみ取得

### 4. キャッシング
- React Queryなどを使用してクライアント側でキャッシュ（将来実装）

---

## セキュリティ考慮事項

### 1. RLS（Row Level Security）
- すべてのテーブルでRLSを有効化済み
- トレーナーは自分が担当するクライアントのデータのみアクセス可能

### 2. 入力バリデーション
- フロントエンドでZodを使用したバリデーション
- バックエンド（API Routes）でも再度バリデーション

### 3. SQLインジェクション対策
- Supabase SDKのパラメータ化クエリを使用
- 生SQLは使用しない

### 4. 画像アップロード
- Supabase Storageのセキュリティポリシー設定
- ファイルサイズ制限: 10MB
- 許可する拡張子: jpg, jpeg, png, webp

---

**作成日**: 2025-11-02
**最終更新日**: 2025-11-02
**バージョン**: 1.0.0
