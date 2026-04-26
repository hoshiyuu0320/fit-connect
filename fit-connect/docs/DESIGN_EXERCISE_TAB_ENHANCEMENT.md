# 運動タブ強化 + ワークアウト実績統合 設計書

> 作成日: 2026-02-22

## 1. 背景と課題

### 現状

顧客詳細画面の「運動」タブは `exercise_records` テーブルのデータのみを表示している。

- **exercise_records**: モバイルアプリのメッセージタグ（`#運動:筋トレ 30分`）から自動生成される簡易記録
  - フィールド: exercise_type, duration, distance, calories, memo
- **workout_assignments**: トレーナーが配信したプランの実行記録（セッション画面で使用）
  - フィールド: plan名, 種目ごとのセット × 重量 × 回数, 完了ステータス, タイマー記録

これら2つのデータソースが統合されておらず、セッション画面で記録したワークアウト実績が運動タブに反映されない。

### 発見されたバグ

**Edge Function `parse-message-tags` の運動タイプ誤判定:**

```javascript
// 現在のコード（createExerciseRecord 内）
if (notes.includes('ラン')) exerciseType = 'running'
```

モバイルアプリがワークアウトプラン完了時に送信するメッセージ:
```
#運動:完了 本日のワークアウトプラン「大胸筋の強化」を達成しました！
```

`ワークアウトプ**ラン**` の「ラン」が `notes.includes('ラン')` にマッチし、`exercise_type: 'running'` になる。

---

## 2. 改善方針

### 2A. 運動タブにワークアウト実績を統合表示

運動タブを2セクション構成に変更:

1. **ワークアウト実績**（`workout_assignments` から取得）
   - プラン名、完了ステータス、種目別セット実績
   - セッション画面のスクリーンショットと同等の情報量
2. **その他の運動記録**（`exercise_records` から取得）
   - 従来の簡易運動ログ（ランニング、ウォーキング等）

### 2B. Edge Function のバグ修正

- 運動タイプ推測ロジックの部分一致を修正
- ワークアウトプラン完了時の専用処理を追加

### 2C. モバイルアプリ側の改善

- ワークアウトプラン完了時のメッセージタグを改善
- `exercise_records` ではなく `workout_assignments` の更新で完了を記録する選択肢

---

## 3. 詳細設計

### 3A. Web側 — 運動タブ（ExerciseTab）の改修

#### データ取得の追加

`page.tsx` で `workout_assignments`（完了済み）を追加取得:

```typescript
// 既存
const exerciseRecords = await getExerciseRecords({ clientId, limit: 100 })

// 追加: 完了済みワークアウトアサインメント
const completedAssignments = await getClientAssignments(clientId)
// ※ status === 'completed' でフィルタ
```

#### ExerciseTab の Props 拡張

```typescript
interface ExerciseTabProps {
  exerciseRecords: ExerciseRecord[]
  workoutAssignments: WorkoutAssignment[]  // 追加
}
```

#### UI構成

```
┌─────────────────────────────────────────────┐
│  期間フィルター [本日] [今週] [今月] ...     │
├─────────────────────────────────────────────┤
│                                             │
│  ■ ワークアウト実績（workout_assignments）   │
│  ┌─────────────────────────────────────┐    │
│  │ 大胸筋の強化          ● 完了        │    │
│  │ 目安: 60分                          │    │
│  │ ┌─────────────────────────────┐     │    │
│  │ │ インクラインダンベルベンチ    完了 │     │    │
│  │ │ 目標: 3セット × 10回 60kg   │     │    │
│  │ │ 1  70kg × 11回  ✓         │     │    │
│  │ │ 2  60kg × 10回  ✓         │     │    │
│  │ │ 3  60kg × 10回  ✓         │     │    │
│  │ └─────────────────────────────┘     │    │
│  │ ┌─────────────────────────────┐     │    │
│  │ │ ペックフライ              完了 │     │    │
│  │ │ ...                        │     │    │
│  │ └─────────────────────────────┘     │    │
│  └─────────────────────────────────────┘    │
│                                             │
│  ■ その他の運動（exercise_records）          │
│  ┌─────────────────────────────────────┐    │
│  │ 🏃 ランニング  14:30               │    │
│  │ 時間: 30分  距離: 5km  200kcal     │    │
│  └─────────────────────────────────────┘    │
│                                             │
└─────────────────────────────────────────────┘
```

#### ワークアウト実績カードの表示項目

| 項目 | データソース |
|------|------------|
| プラン名 | `assignment.plan.title` |
| カテゴリ | `assignment.plan.category` |
| 推定時間 | `assignment.plan.estimated_minutes` |
| ステータス | `assignment.status` (pending/partial/completed/skipped) |
| 実施時間 | `assignment.started_at` 〜 `assignment.finished_at` |
| 種目名 | `exercise.exercise_name` |
| 目標 | `exercise.target_sets` × `exercise.target_reps` × `exercise.target_weight` |
| 実績 | `exercise.actual_sets[]` (set_number, weight, reps, done) |
| 種目完了 | `exercise.is_completed` |
| メモ | `exercise.memo` |
| トレーナーノート | `assignment.trainer_note` |

#### 対象ファイル

| ファイル | 変更内容 |
|----------|----------|
| `src/app/(user_console)/clients/[client_id]/page.tsx` | `getClientAssignments` を呼び出し、ExerciseTab に渡す |
| `src/app/(user_console)/clients/[client_id]/_components/ExerciseTab.tsx` | ワークアウト実績セクション追加、2データソース統合表示 |
| `src/lib/supabase/getClientAssignments.ts` | 必要に応じてフィルタ条件追加（completed のみ等） |

---

### 3B. Edge Function — バグ修正

#### 修正箇所: `createExerciseRecord` 内の運動タイプ推測

**現在のコード（バグあり）:**
```javascript
if (exerciseType === 'other' && commonData.notes) {
    const notes = commonData.notes
    if (notes.includes('走') || notes.includes('ラン')) exerciseType = 'running'
    else if (notes.includes('歩')) exerciseType = 'walking'
    else if (notes.includes('筋トレ') || notes.includes('ウェイト')) exerciseType = 'strength_training'
}
```

**修正後:**
```javascript
if (exerciseType === 'other' && commonData.notes) {
    const notes = commonData.notes
    // 単語境界を考慮した正規表現マッチング（部分一致を防止）
    if (/(?:^|[\s、。])(?:走|ランニング|ラン(?!チ|ク|プ|ド|ダム|キング))/.test(notes)) {
      exerciseType = 'running'
    } else if (/(?:^|[\s、。])(?:歩|ウォーキング)/.test(notes)) {
      exerciseType = 'walking'
    } else if (/(?:筋トレ|ウェイト|筋力)/.test(notes)) {
      exerciseType = 'strength_training'
    }
}
```

**ポイント:** `ラン` の後に `チ`（ランチ）、`ク`（ランク）、`プ`（プラン → ランの前にプがある場合除外）、`ド`（ランド）等が続く場合を除外する否定先読みを使用。

#### 追加: ワークアウトプラン完了タグの専用処理

```javascript
// detail が「完了」の場合はワークアウトプラン完了 → strength_training とする
if (tagData.detail === '完了' || tagData.detail === '達成') {
    exerciseType = 'strength_training'
}
```

---

### 3C. モバイルアプリ側の改善

#### 現状のフロー

```
ユーザーが全種目完了 → 「完了報告」ボタン
  → メッセージ自動送信: "#運動:完了 本日のワークアウトプラン「{planTitle}」を達成しました！"
  → Edge Function が exercise_records に INSERT
```

#### 改善案A: タグ形式の変更（最小変更）

メッセージタグを `#運動:完了` → `#運動:筋トレ` に変更（または `#ワークアウト:完了` を新設）。

**モバイル側変更:**
- ワークアウトプラン完了時の送信メッセージフォーマットを変更:
  ```dart
  // Before
  '#運動:完了 本日のワークアウトプラン「$planTitle」を達成しました！'

  // After
  '#運動:筋トレ 本日のワークアウトプラン「$planTitle」を達成しました！'
  ```

**影響範囲:** モバイルアプリの1箇所のみ。Edge Function の修正不要（既に `筋トレ` → `strength_training` のマッピングが存在）。

#### 改善案B: workout_assignments を直接更新（推奨）

モバイルアプリからワークアウトプラン完了時に、`exercise_records` ではなく `workout_assignments` のステータスを直接更新する。

**フロー変更:**
```
ユーザーが全種目完了 → 「完了報告」ボタン
  → PATCH /api/workout-assignments/{id} { status: 'completed' }
  → メッセージ送信（通知目的のみ、タグなし）:
    "本日のワークアウトプラン「{planTitle}」を達成しました！"
```

**モバイル側変更:**

| 変更箇所 | 内容 |
|----------|------|
| プランタブのデータモデル | `workout_assignments` + `workout_assignment_exercises` を取得 |
| 種目完了処理 | `PATCH /api/workout-assignment-exercises/{id}` で `actual_sets`, `is_completed` を更新 |
| プラン完了処理 | `PATCH /api/workout-assignments/{id}` で `status: 'completed'` を更新 |
| 完了メッセージ | タグなしメッセージを送信（`exercise_records` への二重登録を防止） |

**メリット:**
- セット×重量×回数の詳細実績がWeb側のセッション画面・運動タブと完全に一致
- `exercise_records` への不正確なデータ挿入を防止
- トレーナーがWeb側で確認できるデータと、クライアントがモバイルで入力したデータが同一ソース

**デメリット:**
- モバイルアプリ側の変更量が改善案Aより大きい
- 種目ごとのセット入力UIをモバイルに実装する必要がある（現状は全種目一括チェックのみ）

#### 改善案C: 両方併用（段階的移行）

1. **Phase 1（即時）:** Edge Function のバグ修正 + タグ形式変更（案A）
2. **Phase 2（中期）:** モバイルアプリで workout_assignments 直接更新に移行（案B）
3. **Phase 3:** exercise_records のワークアウト完了レコードを廃止

---

## 4. 推奨実装順序

| # | タスク | 対象 | 優先度 |
|---|--------|------|--------|
| 1 | Edge Function のバグ修正（`ラン` 部分一致問題） | Supabase Edge Function | 高 |
| 2 | Web: ExerciseTab にワークアウト実績セクション追加 | Web (`ExerciseTab.tsx`) | 高 |
| 3 | Web: page.tsx で completedAssignments を取得して ExerciseTab に渡す | Web (`page.tsx`) | 高 |
| 4 | モバイル: 完了メッセージのタグ修正（`#運動:完了` → `#運動:筋トレ`） | Mobile (Flutter) | 中 |
| 5 | モバイル: workout_assignments 直接更新への移行 | Mobile (Flutter) | 低（Phase 2） |

---

## 5. モバイルアプリ向け指示書

### 即時対応（Phase 1）

#### 対象ファイル（推定）

ワークアウトプラン完了時にメッセージを送信している箇所。

#### 変更内容

完了報告メッセージのタグを変更:

```dart
// 変更前
final message = '#運動:完了 本日のワークアウトプラン「$planTitle」を達成しました！';

// 変更後
final message = '#運動:筋トレ 本日のワークアウトプラン「$planTitle」を達成しました！';
```

### 中期対応（Phase 2 — workout_assignments 直接更新）

#### 必要なAPI呼び出し

| API | メソッド | 用途 |
|-----|---------|------|
| `/api/workout-assignments?clientId={id}&weekEnd={date}&includeHistory=true` | GET | 本日のアサインメント取得 |
| `/api/workout-assignment-exercises/{id}` | PATCH | 種目のセット実績更新 |
| `/api/workout-assignments/{id}` | PATCH | アサインメントステータス更新 |

#### PATCH `/api/workout-assignment-exercises/{id}` のリクエスト

```json
{
  "actualSets": [
    { "set_number": 1, "weight": 70, "reps": 11, "done": true },
    { "set_number": 2, "weight": 60, "reps": 10, "done": true },
    { "set_number": 3, "weight": 60, "reps": 10, "done": true }
  ],
  "isCompleted": true,
  "memo": "調子良かった"
}
```

#### PATCH `/api/workout-assignments/{id}` のリクエスト

```json
{
  "status": "completed",
  "clientFeedback": "今日のトレーニングは充実していました"
}
```

#### モバイル側の実装要件

1. **プランタブのデータ取得を `workout_assignments` APIに切り替え**
   - 現在の Supabase 直接クエリから API Route 経由に変更
   - `plan` と `exercises` の JOIN データを使用

2. **種目完了をチェックボックスから詳細入力に段階的移行**
   - Phase 2a: 現状のチェックボックス方式を維持しつつ、バックエンドは `workout_assignment_exercises` を更新
   - Phase 2b: セット入力UI（重量 × 回数）の追加

3. **完了報告メッセージからタグを除去**
   - メッセージは通知目的のみ（タグなし）
   - `exercise_records` への二重登録を防止

---

## 6. DB変更

本設計では DB スキーマの変更は不要。既存テーブルの活用のみ。

- `workout_assignments` — 既存テーブル、変更なし
- `workout_assignment_exercises` — 既存テーブル、変更なし
- `exercise_records` — 既存テーブル、従来のメッセージタグ経由の記録は継続

---

## 7. テスト項目

| # | テスト | 期待結果 |
|---|--------|----------|
| 1 | 運動タブにワークアウト実績セクションが表示される | completed のアサインメントが種目・セット詳細付きで表示 |
| 2 | 期間フィルターがワークアウト実績にも適用される | 選択期間内のアサインメントのみ表示 |
| 3 | exercise_records の従来データも「その他の運動」セクションに表示される | ランニング等の簡易記録が従来通り表示 |
| 4 | Edge Function 修正後、「ワークアウトプラン」を含むメッセージで running にならない | strength_training または other になる |
| 5 | モバイルからタグ修正後のメッセージ送信で正しい exercise_type になる | strength_training として記録される |
