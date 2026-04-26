# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

```bash
# Start development server
npm run dev                 # Runs on http://localhost:3000

# Build for production
npm run build

# Start production server
npm start

# Run linting
npm run lint
```

## Development Rules

- `.env`ファイルは参照しないこと
- 実装に関しては`docs/IMPLEMENTATION_TASKS.md`を参照して実装すること
- 実装の進捗は`docs/IMPLEMENTATION_TASKS.md`を随時更新すること

## Architecture Overview

FIT-CONNECT is a fitness trainer management platform consisting of a Next.js 15 web application for trainers and a planned Flutter native app for clients, both backed by Supabase.

### Core Technology Stack

**Trainer Web App (Current)**
- **Framework:** Next.js 15 (App Router)
- **Database:** Supabase (PostgreSQL with Row Level Security)
- **Authentication:** Supabase Auth
- **Messaging:** Supabase Realtime
- **State Management:** Zustand with localStorage persistence
- **UI:** Tailwind CSS + Radix UI components
- **Forms:** React Hook Form + Zod validation

**Client Mobile App (Planned - See ROADMAP.md)**
- **Framework:** Flutter
- **Language:** Dart
- **Backend:** Supabase (shared with web app)

### Project Structure

```
src/
├── app/
│   ├── (auth)/              # Auth routes (login, signup)
│   ├── (user_console)/      # Protected dashboard routes
│   │   ├── clients/         # Client management and detail pages
│   │   ├── dashboard/       # Trainer dashboard
│   │   ├── message/         # Real-time messaging UI
│   │   ├── schedule/        # Session scheduling (placeholder)
│   │   ├── report/          # Analytics and reports (placeholder)
│   │   ├── workoutplan/     # Training plan management (placeholder)
│   │   ├── settings/        # Account settings (placeholder)
│   │   └── layout.tsx       # Sidebar layout
│   └── api/
│       └── messages/send/   # Message sending API endpoint
├── lib/
│   ├── supabase.ts          # Browser Supabase client
│   ├── supabaseAdmin.ts     # Server-side admin client
│   └── supabase/            # Database query functions (one file per operation)
├── store/
│   └── userStore.ts         # Zustand state management
├── types/
│   └── client.ts            # TypeScript type definitions for client domain
└── components/
    ├── clients/             # Client-specific components
    └── ui/                  # Reusable UI components (Radix-based)
```

### Database Schema

**trainers**
- `id` (UUID, PK) - References auth.users.id
- `name` (TEXT) - Trainer name
- `email` (TEXT) - Trainer email
- `profile_image_url` (TEXT) - Profile image URL
- `created_at` (TIMESTAMPTZ)
- `updated_at` (TIMESTAMPTZ)

**clients** (trainer's clients)
- `client_id` (UUID, PK)
- `trainer_id` (UUID, FK) → trainers.id
- `name` (TEXT)
- `gender` (TEXT) - 'male', 'female', 'other'
- `age` (INT)
- `occupation` (TEXT)
- `height` (NUMERIC)
- `target_weight` (NUMERIC)
- `purpose` (TEXT) - 'diet', 'contest', 'body_make', 'health_improvement', 'mental_improvement', 'performance_improvement'
- `goal_description` (TEXT)
- `profile_image_url` (TEXT)
- `line_user_id` (TEXT, UNIQUE) - Legacy LINE integration (deprecated)
- `created_at` (TIMESTAMPTZ)

**messages** (bidirectional messaging)
- `id` (UUID, PK)
- `sender_id` (UUID) - Trainer or client ID
- `receiver_id` (UUID) - Trainer or client ID
- `sender_type` (TEXT) - 'trainer' or 'client'
- `receiver_type` (TEXT) - 'trainer' or 'client'
- `message` (TEXT)
- `timestamp` (TIMESTAMPTZ)

**weight_records** (client weight tracking)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `weight` (NUMERIC)
- `recorded_at` (TIMESTAMPTZ)

**meal_records** (client meal logging)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `meal_type` (TEXT) - 'breakfast', 'lunch', 'dinner', 'snack'
- `description` (TEXT)
- `calories` (INT)
- `images` (TEXT[]) - Array of image URLs
- `recorded_at` (TIMESTAMPTZ)

**exercise_records** (client workout logging)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `exercise_type` (TEXT) - 'walking', 'running', 'strength_training', etc.
- `duration` (INT) - Minutes
- `distance` (NUMERIC) - Kilometers
- `calories` (INT)
- `memo` (TEXT)
- `recorded_at` (TIMESTAMPTZ)

**tickets** (session ticket management)
- `id` (UUID, PK)
- `client_id` (UUID, FK) → clients.client_id
- `ticket_name` (TEXT)
- `ticket_type` (TEXT)
- `total_sessions` (INT)
- `remaining_sessions` (INT)
- `valid_from` (TIMESTAMPTZ)
- `valid_until` (TIMESTAMPTZ)
- `created_at` (TIMESTAMPTZ)

All tables use Row Level Security (RLS) for access control. See `src/types/client.ts` for complete TypeScript type definitions.

## Key Architectural Patterns

### Dual Supabase Client Pattern
- **Browser client** (`src/lib/supabase.ts`): Uses `NEXT_PUBLIC_SUPABASE_ANON_KEY` for client-side operations
- **Admin client** (`src/lib/supabaseAdmin.ts`): Uses `SUPABASE_SERVICE_ROLE_KEY` for server-side/API operations
- API routes act as the security boundary for sensitive operations

### Database Operations
Each database operation is isolated in its own file under `src/lib/supabase/`:
- `getClients.ts` - Fetch trainer's clients
- `getClientDetail.ts` - Fetch single client with details
- `searchClients.ts` - Search/filter clients by name, gender, age, purpose
- `getMessages.ts` - Bidirectional message query
- `sendMessage.ts` - Insert message record
- `createTrainer.ts` - Create trainer record on signup
- `getTrainer.ts` - Fetch trainer info
- `getWeightRecords.ts` - Fetch client weight history
- `getMealRecords.ts` - Fetch client meal logs (with pagination)
- `getExerciseRecords.ts` - Fetch client exercise logs (with pagination)
- `getTickets.ts` - Fetch client session tickets

### Authentication Flow
1. **Trainer:** `supabase.auth.signUp()` → `createTrainer()` → redirect to dashboard
2. **Client:** Will be handled via Flutter mobile app (future implementation)

### Messaging Architecture
**Trainer → Client:**
1. Trainer sends message in web UI ([/message](src/app/(user_console)/message/page.tsx))
2. POST to `/api/messages/send`
3. Save to `messages` table via `supabaseAdmin`
4. Client receives via Realtime subscription (future: push notification to mobile app)

**Client → Trainer:**
1. Client sends message via mobile app (future implementation)
2. Save to `messages` table
3. Trainer sees message in web UI via Realtime subscription

**Real-time Updates:**
```typescript
supabase
  .channel('message-room')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'messages',
    filter: `receiver_id=eq.${userId}`,
  }, handleNewMessage)
  .subscribe()
```

## Environment Variables

Required in `.env.local`:
```
NEXT_PUBLIC_SUPABASE_URL          # Supabase project URL
NEXT_PUBLIC_SUPABASE_ANON_KEY     # Supabase anonymous key
SUPABASE_SERVICE_ROLE_KEY         # Admin key (server-only, never expose to client)
```

**Note:** LINE-related environment variables (LIFF_ID, LINE_CHANNEL_ACCESS_TOKEN) are deprecated as the project is transitioning to a Flutter mobile app architecture.

## Important Notes

### Client vs Server Components
- All auth pages (`/login`, `/signup`) use `"use client"` for form handling
- Dashboard routes use `"use client"` for interactivity and Realtime subscriptions
- API routes are server-side only and use `supabaseAdmin`

### Client Management Features
- **Client List** ([/clients](src/app/(user_console)/clients/page.tsx)): Search and filter clients by name, gender, age range, and fitness purpose
- **Client Detail** ([/clients/[client_id]](src/app/(user_console)/clients/[client_id]/page.tsx)): View comprehensive client profile including:
  - Basic info (age, gender, height, target weight, goals)
  - Weight progression tracking
  - Meal records with images and calorie data
  - Exercise logs with duration, distance, and calories
  - Session tickets with remaining sessions and expiry dates

### Path Aliases
- Use `@/` prefix for imports (maps to `./src/*`)
- Example: `import { supabase } from '@/lib/supabase'`

### Route Groups
- `(auth)` and `(user_console)` are Next.js route groups
- They organize routes without affecting URLs
- Each can have its own layout

### State Management
- Zustand store (`userStore.ts`) persists user data to localStorage
- Minimal global state - most data fetched from Supabase
- Realtime subscriptions handle live updates

### Known Limitations
- No foreign key constraints on `messages.sender_id` and `messages.receiver_id`
- Missing indexes on `messages` table for performance optimization
- Placeholder implementations: `/schedule`, `/report`, `/workoutplan`, `/settings`
- Client-side record creation (meals, exercises, weight) requires Flutter mobile app (not yet implemented)
- Graph visualization for weight tracking not yet implemented (shows table data only)

### Development Roadmap
See [ROADMAP.md](ROADMAP.md) for comprehensive implementation plan including:
- Phase 1: Schedule/session management and dashboard improvements
- Phase 2: Flutter mobile app for clients with meal/exercise logging
- Phase 3: Analytics, reports, and training plan features
- Phase 4: Settings page and performance optimizations

## API Endpoints

### POST /api/messages/send
Send message from trainer to client.

**Body:**
```json
{
  "trainerId": "uuid",
  "clientId": "uuid",
  "message": "text"
}
```

**Returns:** `{ status: 'ok' }` on success

**Note:** Currently saves to database only. Push notifications to mobile app will be added in Phase 2.

## Common Development Patterns

### Adding a new database query
1. Create file in `src/lib/supabase/` (e.g., `getTrainerStats.ts`)
2. Export async function that uses `supabase` or `supabaseAdmin`
3. Handle errors with try/catch or check `error` property
4. Import and use in components or API routes

### Adding a new API route
1. Create `route.ts` in `src/app/api/your-route/`
2. Use `supabaseAdmin` from `@/lib/supabaseAdmin`
3. Export named functions: `GET`, `POST`, `PUT`, `DELETE`
4. Return `NextResponse.json()` for responses

### Adding real-time functionality
1. Create Supabase channel with unique name
2. Subscribe to `postgres_changes` event
3. Filter by table and optionally by row conditions
4. Update local state in callback
5. Clean up subscription on unmount

# 開発フロー

## Subagents（専門エージェント）

このプロジェクトには専門分野に特化したサブエージェント定義があります。

### 利用可能なサブエージェント

| エージェント         | ファイル                      | 用途                                       |
| -------------------- | ----------------------------- | ------------------------------------------ |
| **Next.js UI Agent** | `.claude/agents/nextjs-ui.md` | Page/Component作成、Tailwind CSS、Radix UI |
| **Supabase Agent**   | `.claude/agents/supabase.md`  | クエリ関数、API Route、Realtime購読        |
| **Zustand Agent**    | `.claude/agents/zustand.md`   | Store作成、グローバル状態管理              |
| **Explore Agent**    | `.claude/agents/explore.md`   | コードベース調査・探索、実装箇所特定       |
| **Plan Agent**       | `.claude/agents/plan.md`      | 複雑なタスクの計画・設計、タスク分解       |

### 使用方法

各エージェントの詳細な指示は `.claude/agents/` ディレクトリ内のファイルを参照してください。

**Next.js UI Agent:**
- Client/Server Componentの使い分け
- Radix UIコンポーネントの使用パターン
- Tailwind CSSスタイリングルール
- React Hook Form + Zodによるフォーム実装

**Supabase Agent:**
- デュアルクライアントパターン（Browser/Admin）
- クエリ関数の基本構造（1操作1ファイル）
- API Routeの実装パターン
- Realtime購読の設定

**Zustand Agent:**
- Store作成パターン（persist/non-persist）
- セレクターによるパフォーマンス最適化
- 非同期アクションの実装
- 既存Store一覧

**Explore Agent:**
- ファイル・コード検索パターン
- 依存関係調査方法
- 主要Supabase関数一覧

**Plan Agent:**
- 実装計画の作成プロセス
- タスク分解の基準
- 担当エージェントの割り当て

## Role: Manager & Agent Orchestrator

**あなたはマネージャーであり、Agentオーケストレーターです。**

### 基本原則

1. **実装は絶対に自分で行わない**
   - 全ての実装作業はSubagentまたはTask Agentに委託する
   - 自分の役割は計画・指示・レビュー・調整のみ

2. **タスクの超細分化**
   - 大きなタスクは必ず小さなサブタスクに分解する
   - 1つのサブタスクは1つのファイル変更または1つの機能に限定
   - 曖昧さを排除し、明確な完了条件を設定する

3. **PDCAサイクルの構築**
   ```
   Plan（計画）
   ├─ タスクを細分化してTaskCreate/TaskUpdateで管理
   ├─ 各タスクの担当エージェントを決定
   └─ 期待する成果物を明確化

   Do（実行）
   ├─ Task Agentに具体的な指示を出す
   ├─ 必要なコンテキスト（ファイルパス、既存コード参照）を提供
   └─ 並列実行可能なタスクは同時に依頼

   Check（確認）
   ├─ エージェントの出力をレビュー
   ├─ コードの品質・規約遵守を確認
   └─ エラーや問題点を特定

   Act（改善）
   ├─ 問題があれば修正タスクを作成
   ├─ 学びをドキュメントに反映
   └─ 次のサイクルに進む
   ```

### エージェント委託のパターン

| タスク種別                | 委託先 (subagent_type) | 用途                                     |
| ------------------------- | ---------------------- | ---------------------------------------- |
| Page/Component作成・修正  | `nextjs-ui`            | Tailwind CSS + Radix UIによるUI実装      |
| Supabaseクエリ・API Route | `supabase`             | DB操作関数、API Route、Realtime購読、RLS |
| Zustand Store操作         | `zustand`              | Store作成・拡張、状態の永続化            |
| コードベース調査          | `explore`              | 実装箇所の特定、依存関係の解析           |
| 実装計画の作成            | `plan`                 | 複雑なタスクの計画・設計・タスク分解     |
| ビルド・テスト・Git操作   | `Bash`                 | コマンド実行、ビルド確認                 |

### 委託時の必須情報

```markdown
## タスク: [タスク名]

### 目的
[何を達成するか]

### 対象ファイル
- `src/app/(user_console)/xxx/page.tsx`
- `src/lib/supabase/xxx.ts`

### 参照すべき既存コード
- `src/app/(user_console)/message/page.tsx` （UIパターン参考）
- `src/lib/supabase/getMessages.ts` （クエリパターン参考）

### 完了条件
- [ ] 条件1
- [ ] 条件2
- [ ] 既存レイアウト踏襲

### 制約
- Tailwind CSS + Radix UI使用必須
- `@/` パスエイリアス使用
- supabaseAdmin はAPI Route内のみで使用
```

### ワークフロー例

```
ユーザーの要求: 「メッセージ編集機能を追加して」

1. Plan Agent に実装計画を委託
   → API Route、DB関数、UI変更の計画を受領

2. TaskCreateでサブタスク作成
   - タスク1: Supabase Agent → editMessage.ts 作成
   - タスク2: Supabase Agent → /api/messages/edit API Route 作成
   - タスク3: Next.js UI Agent → message/page.tsx に編集UI追加
   - タスク4: Bash Agent → ビルド確認

3. 依存関係のないタスク1,2を並列実行

4. 完了後レビュー → タスク3実行 → タスク4実行

5. 全体の動作確認・IMPLEMENTATION_TASKS.md更新
```

### セッション継続

作業を再開するときは、まず以下を読むこと

- `docs/tasks/IMPLEMENTATION_TASKS.md` - 未着手タスクと進捗
- `docs/tasks/lessons.md` - 過去の失敗と学び

変更があった場合、上記を更新すること。

### チーム編成

セッション継続の情報をもとに、チーム編成（最大3人）を行い並列作業せよ

複数のエージェントで同一タスクを同時に実行する場合は、同時に同じファイルを触らないこと（上書きを発生させないこと）

## Design Tokens & Core Concept
- Concept: Modern, Sophisticated, Gender-neutral Fitness Management Tool
- Primary Color: #0F172A (Slate 900) // 深く洗練されたネイビー/黒。プロの信頼感を演出
- Accent Color: #14B8A6 (Teal 500) // 爽やかでモダンなティールグリーン。男女問わず好まれる健康的な色
- Background: #F8FAFC // 真っ白ではなく、長時間見ても目が疲れないオフホワイト
- Surface: #FFFFFF // カードや入力エリアの背景
- Typography (EN): 'Plus Jakarta Sans', sans-serif // 海外のモダンなSaaSでよく使われる、洗練された欧文フォント
- Typography (JP): 'Noto Sans JP', sans-serif
- Spacing: 8px grid system (8, 16, 24, 32, 48px) // 余白をたっぷり取り、洗練された印象に
- Border-radius: 6px // 丸すぎず（ポップになりすぎない）、尖りすぎないプロフェッショナルなカーブ
- Borders: 1px solid #E2E8F0 // 非常に薄く控えめな境界線

## UI/UX Anti-Patterns (厳禁ルール)
- AI特有の安っぽいグラデーション（青→紫など）は絶対に使用しない。ベタ塗り（Solid color）を基本とする。
- 意味のない、または濃すぎるドロップシャドウは禁止。フラットデザイン、もしくは極めて薄いシャドウのみを使用する。
- ボタンやカードの角を丸めすぎない（Border-radiusは最大でも8pxまで。丸薬型/Pill-shapeは避ける）。
- システムデフォルトのInterフォントは使用禁止。
- 彩度が高すぎる原色（#FF0000など）はエラーや警告のステータス以外では絶対に使用しない。
- 要素を詰め込みすぎない。常にSpactingトークンに基づいた「十分な余白（White space）」を確保する。