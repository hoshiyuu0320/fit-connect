# AI Meal Estimation — Stage 1 Design

**作成日**: 2026-05-02
**対象タスク**: `IMPLEMENTATION_TASKS.md` フェーズ2「LLM（Claude）カロリー計算」のうち **2.1 Claude API 連携基盤** + **2.2 テキスト入力からのカロリー推定**
**プロジェクト**: FIT-CONNECT Mobile (Flutter) + Supabase（共有バックエンド）
**ステージ戦略**: フェーズ2 全体を 4 Stage に分解した最初のステージ（Stage 1）

---

## 1. 背景とゴール

### 1.1 背景

FIT-CONNECT のコア体験は **「メッセージ上で記録が完結する」** ことにある。クライアントは `#食事:昼食 牛丼` のようなタグ付きメッセージを送るだけで、トレーナーへの共有と `meal_records` への保存が同時に行われる（既存の `parse-message-tags` Edge Function による）。

現状の食事記録には以下の課題がある:
- カロリーは手入力 or 未記録（多くは未記録）
- PFC（タンパク質・脂質・炭水化物）は完全に未対応 — トレーナーが定量的な食事指導を行えない
- ユーザーがカロリー計算アプリを別途使う必要があり、面倒で続かない

### 1.2 ゴール

クライアントがメッセージで食事を記録するときに、Claude API（Haiku 4.5）が食事内容テキストから **カロリーと PFC を自動推定** し、ユーザーが確認・編集してから送信できる UX を提供する。

### 1.3 非ゴール（Stage 1 範囲外）

| 機能 | 担当 |
|---|---|
| 画像（料理写真）からの推定 | Stage 2（タスク 2.3） |
| メッセージタグだけで自動推定発火 | Stage 3（タスク 2.4） |
| スクショ画像分析（あすけん等） | Stage 4（タスク 2.5） |
| Stripe 連携で `subscription_plan` を自動更新 | フェーズ7 |
| Web 側で PFC 表示（トレーナー閲覧） | 別タスク（スキーマは整うが UI は別件） |
| 食品単位の編集UI（食品追加・削除・個別PFC編集） | Stage 2 以降 |
| 推定履歴・精度フィードバック | フェーズ2 タスク 2.4 の任意項目 |

---

## 2. プロダクト要件

### 2.1 課金ゲート（Feature Gating）

- **AI 機能の課金はトレーナー側のみ** が負担する。クライアントは課金 UI も課金の存在も意識しない
- トレーナーの `subscription_plan` が `'pro'` のとき、その担当クライアントが AI 機能を利用できる
- `subscription_plan` が `'free'` のとき、AI 関連 UI は **一切表示しない**（既存の挿入挙動のままになる）

### 2.2 ユーザーフロー

**前提**: クライアントの担当トレーナーが `subscription_plan = 'pro'`

```
1. クライアントがメッセージ画面で「食事を記録」シートを開く（既存）
2. 食事タイプ選択（朝/昼/夕/間食）+ 内容テキスト + 画像（任意）入力（既存）
3. 「挿入」ボタンタップ
   ↓
4. シートが「AI推定中…」状態に切り替わる（同じシート領域で state 切替、画面遷移なし）
   - Edge Function `estimate-meal-nutrition` を呼ぶ
   ↓
5. シートが「確認」状態に切り替わる（同じシート領域）
   - 食品リスト（read-only、Stage 1）
   - 合計 kcal / P / F / C（editable）
   - 「送信」ボタン / 「戻る」ボタン
   ↓
6. 「送信」タップ
   - メッセージを送信（チャットには `#食事:昼食 牛丼` がそのまま表示）
   - 同時に `meal_records` に PFC込みで保存される（webhook 経由）
```

### 2.3 「AIなしで送信」フォールバック

任意のエラー画面に「AIなしで送信」リンクを配置する。タップすると、既存の挙動（タグ文字列をチャット入力欄に挿入）にフォールバックし、ユーザーは普通に送信ボタンを押すだけで AI 推定なしで送れる。これにより **AI 障害時にも食事記録機能が止まらない** ことを担保する。

---

## 3. アーキテクチャ

### 3.1 概要

```
┌─────────────────┐                       ┌──────────────────────────────┐
│  Flutter        │ ──estimate request─→  │ Edge Function:               │
│  MealTagForm    │                       │ estimate-meal-nutrition      │
│  (3-state)      │ ←─PFC result─────     │  - subscription再検証        │
└─────────────────┘                       │  - rate limit                │
       │                                  │  - Claude Haiku 4.5 呼出     │
       │                                  │  - ai_estimation_logs に記録 │
       │                                  └──────────────────────────────┘
       │ (確認後)
       ↓
┌─────────────────┐  metadata込み INSERT   ┌──────────────────────────────┐
│  Supabase       │ ←──────────────────── │ Flutter (送信処理)           │
│  messages       │                       │ messages.metadata に         │
└─────────────────┘                       │ meal_estimation を同梱        │
       │ webhook                          └──────────────────────────────┘
       ↓
┌──────────────────────────────┐
│ parse-message-tags（改修）   │
│ - metadata.meal_estimation   │
│   が存在 → その値で          │
│   meal_records 作成           │
│ - 無い場合は既存挙動         │
└──────────────────────────────┘
```

### 3.2 設計ポイント

- **AI 推定 Edge Function は推定のみ、保存はしない**
- **メッセージに metadata を載せて parse-message-tags に推定値を伝える** ことで、メッセージ INSERT 単発で記録作成まで完結する（race condition なし）
- **既存の `parse-message-tags` の素の挙動を完全維持**（metadata が無いメッセージは従来通り）

---

## 4. データモデル変更

### 4.1 マイグレーション 1: `meal_records` 拡張

```sql
ALTER TABLE meal_records
  ADD COLUMN protein_g       numeric CHECK (protein_g IS NULL OR protein_g >= 0),
  ADD COLUMN fat_g           numeric CHECK (fat_g     IS NULL OR fat_g     >= 0),
  ADD COLUMN carbs_g         numeric CHECK (carbs_g   IS NULL OR carbs_g   >= 0),
  ADD COLUMN estimated_by_ai boolean DEFAULT false NOT NULL,
  ADD COLUMN ai_foods        jsonb;  -- [{name, calories, protein_g, fat_g, carbs_g}]
```

- 既存レコードは PFC = NULL、`estimated_by_ai = false`（破壊的変更なし）
- `ai_foods` は将来 UI 拡張（食品単位の編集など）に備えた保管庫

### 4.2 マイグレーション 2: `trainers.subscription_plan`

```sql
ALTER TABLE trainers
  ADD COLUMN subscription_plan text NOT NULL DEFAULT 'free'
    CHECK (subscription_plan IN ('free', 'pro'));
```

- Stage 1 ではテストアカウントを手動で `'pro'` に更新
- フェーズ7（Stripe 連携）で webhook が自動更新する想定

### 4.3 マイグレーション 3: `messages.metadata`

```sql
ALTER TABLE messages
  ADD COLUMN metadata jsonb;
```

想定される中身（食事推定の場合）:
```json
{
  "meal_estimation": {
    "foods": [{"name": "牛丼大盛り", "calories": 850, "protein_g": 32, "fat_g": 28, "carbs_g": 95}],
    "calories": 850,
    "protein_g": 32,
    "fat_g": 28,
    "carbs_g": 95
  }
}
```

汎用 jsonb なので、将来の他用途（運動推定、スタンプ生成など）にも流用できる。

### 4.4 マイグレーション 4: `ai_estimation_logs`

```sql
CREATE TABLE ai_estimation_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     uuid NOT NULL REFERENCES clients(client_id),
  trainer_id    uuid NOT NULL REFERENCES trainers(id),
  function_name text NOT NULL,
  status        text NOT NULL CHECK (status IN ('success', 'error')),
  error_code    text,
  created_at    timestamptz DEFAULT now() NOT NULL
);

CREATE INDEX idx_ai_logs_client_created  ON ai_estimation_logs(client_id, created_at DESC);
CREATE INDEX idx_ai_logs_trainer_created ON ai_estimation_logs(trainer_id, created_at DESC);
```

- Rate limit 判定 + コストデバッグ用
- RLS: クライアント・トレーナーは自身のログを SELECT 可能。INSERT は service_role のみ（Edge Function 経由）

### 4.5 RLS 確認事項（実装時タスク）

- `clients.trainer_id` 経由で `trainers.subscription_plan` を SELECT できる必要あり
- 既存 RLS（trainers は誰でも SELECT 可、QR フロー用）でカバーされていれば追加不要
- カバーされていない場合は補完マイグレーションを追加

---

## 5. Edge Function `estimate-meal-nutrition`

### 5.1 仕様

**Endpoint**: `POST /functions/v1/estimate-meal-nutrition`
**Auth**: Supabase JWT 必須

**Request**:
```json
{
  "meal_type": "breakfast" | "lunch" | "dinner" | "snack",
  "content": "牛丼大盛りとサラダ",
  "image_urls": []
}
```

**Response（成功）**:
```json
{
  "foods": [
    {"name": "牛丼大盛り", "calories": 850, "protein_g": 32, "fat_g": 28, "carbs_g": 95},
    {"name": "サラダ",      "calories":  50, "protein_g":  2, "fat_g":  3, "carbs_g":  5}
  ],
  "totals": {"calories": 900, "protein_g": 34, "fat_g": 31, "carbs_g": 100}
}
```

**Response（エラー）**:
```json
{ "error": "FORBIDDEN" | "RATE_LIMIT" | "ESTIMATION_FAILED" | "INVALID_INPUT", "message": "..." }
```

### 5.2 処理フロー

1. JWT 検証 → `auth.uid()` 取得
2. `clients` テーブルから自身のレコード取得 → `trainer_id` 取得
3. `trainers.subscription_plan == 'pro'` チェック → false なら `403 FORBIDDEN`
4. Rate Limit チェック（5.4 参照）→ 超過なら `429 RATE_LIMIT`
5. Claude API 呼び出し（Haiku 4.5、prompt caching 有効）
6. レスポンスをパース・バリデーション
7. `ai_estimation_logs` に記録（成功・失敗ともに）
8. 結果返却

### 5.3 Claude プロンプト設計（要点）

**System prompt（prompt caching 対象）**:
- 役割定義: 栄養素推定アシスタント
- 厳密な JSON スキーマ要求
- 日本食データベース基準で推定する指針
- 量が不明な場合は「標準的な1人前」として推定
- 信頼できないものは推定せず空配列を返す
- すべて整数（小数点切り捨て）で返す

**User prompt**:
```
食事タイプ: ${meal_type}
内容: ${content}
```

**API パラメータ**:
- model: `claude-haiku-4-5`
- max_tokens: 1024
- temperature: 0.2（推定の安定性優先）
- prompt caching を system prompt 全体に適用

### 5.4 Rate Limit

| 単位 | 制限 | 根拠 |
|---|---|---|
| クライアント | 50 回/24h | 重ヘビーユーザーでも 3食 + 間食 = 4回/日 程度、十分余裕 |
| トレーナー（合計） | 1000 回/24h | コスト上限のセーフティネット |

判定: Edge Function 内で `ai_estimation_logs` に対して `client_id` および `trainer_id` 別の COUNT を実行。超過時は `429 RATE_LIMIT` を返却。

### 5.5 シークレット管理

- `ANTHROPIC_API_KEY` を Supabase Secrets で管理
- Edge Function は `SUPABASE_SERVICE_ROLE_KEY` で DB 操作（既存の `parse-message-tags` と同様）

---

## 6. parse-message-tags の改修

### 6.1 改修内容

`payload.record.metadata?.meal_estimation` が存在する場合、その値を使って `meal_records` を作成する:

```js
if (tagData.category === '食事') {
  const estimation = message.metadata?.meal_estimation;
  if (estimation) {
    // PFC込みで作成
    await supabase.from('meal_records').insert({
      ...commonData,
      meal_type: ...,
      calories:  estimation.calories,
      protein_g: estimation.protein_g,
      fat_g:     estimation.fat_g,
      carbs_g:   estimation.carbs_g,
      ai_foods:  estimation.foods,
      estimated_by_ai: true,
      images:    commonData.image_urls,
    });
  } else {
    // 既存挙動（PFC・カロリー無し）
    await createMealRecord(supabase, commonData, tagData);
  }
}
```

### 6.2 UPDATE 時の挙動

メッセージが編集された場合（5分ウィンドウ内）:
- 既存レコードを削除（既存の挙動を維持）
- metadata に推定値があれば、その値で再作成（つまり推定値はそのまま再利用）
- メッセージテキストが大きく変わっても **AI 推定は再実行しない**（簡素化のため）

→ **Stage 1 では「メッセージ編集すると `meal_records` の PFC は元の値のまま」** とする。テキストとの整合性が取れなくなるが、UX として許容範囲（編集機能は5分ウィンドウかつ稀）。

### 6.3 既存挙動の互換性

- metadata が無いメッセージは **既存と完全に同じ挙動**
- 体重・運動タグは Stage 1 では一切変更なし

---

## 7. UI 詳細: `MealTagForm` 3 状態ステートマシン

### 7.1 状態遷移

```
[State 1: 入力] (既存UI)
  segment + content text + image picker + 「挿入」button
  ├─ AI機能解放されていない → 既存通り `onCompose` で挿入文字列を返す
  └─ AI機能解放済み + 内容あり → 「挿入」tap で State 2 へ
       │
       ↓
[State 2: 推定中]
  - 「AI推定中…」LoadingIndicator
  - 「キャンセル」button (→ State 1、入力値保持)
  - Edge Function 呼び出し中
       │
       ├─ 推定成功 → State 3
       └─ 推定失敗 → State 1 にスナックバー + 「AIなしで送信」リンク
       │
       ↓
[State 3: 確認]
  - 食品リスト（read-only）: ・牛丼大盛り（800kcal）・サラダ（50kcal）...
  - 合計編集フォーム（editable）: 🔥 850 kcal | 🥩 P 32g | 🥑 F 28g | 🍞 C 95g
  - 「戻る」button (→ State 1、入力値保持、推定値破棄)
  - 「送信」button → 送信処理
       │
       ↓
[Sheet クローズ + チャットに送信メッセージ表示]
```

### 7.2 編集スコープ判断（Stage 1）

| UI 要素 | Stage 1 | Stage 2以降 |
|---|---|---|
| 食品リスト | read-only（名前・kcalのみ表示） | editable（食品追加・削除・個別PFC編集） |
| 合計 4 値（kcal/P/F/C） | editable | （変更なし） |
| 再推定ボタン | 提供しない | 検討 |

### 7.3 未解放トレーナーのクライアント

- AI 関連 UI は一切表示しない
- State 1 のみ存在し、「挿入」tap は **既存の `onCompose` 挙動** に直結（チャット入力欄に挿入）

### 7.4 Provider 設計

- `aiFeaturesEnabledProvider` (Riverpod): 自身の担当トレーナーの `subscription_plan` を取得し、`'pro'` なら `true`
- `mealEstimationNotifier`: `MealTagForm` の3状態を保持する `AsyncNotifier` または `StateNotifier`

---

## 8. エラーハンドリング

### 8.1 エラー分類

| エラー種別 | 原因 | レスポンス | クライアント挙動 |
|---|---|---|---|
| `FORBIDDEN` | subscription_plan != 'pro' | 403 | UIにAI機能を表示しないため通常到達しない（防御線） |
| `RATE_LIMIT` | 24h 上限超過 | 429 | スナックバー「AI推定の上限に達しました」+ AIなし送信に誘導 |
| `INVALID_INPUT` | content 空、meal_type 不正 | 400 | スナックバー（防御線） |
| `ESTIMATION_FAILED` | Claude API 障害・JSONパース失敗 | 500 | スナックバー「推定に失敗しました」+ AIなし送信に誘導 |
| ネットワーク障害 | クライアント側のタイムアウト | timeout 30s | 「通信エラー。再試行しますか？」ダイアログ |

### 8.2 Claude レスポンスバリデーション

- JSON パース失敗 → `ESTIMATION_FAILED`
- `foods` 配列の各要素に必須キー欠落 → `ESTIMATION_FAILED`
- カロリー・PFC が負数 → 0 にクリップ（指針違反だがリトライしない）
- `foods` が空配列 → `ESTIMATION_FAILED` 扱い（「内容から推定できませんでした」表示）

### 8.3 Stage 1 で対応しないこと（KISS）

- リトライボタン（ユーザーが「挿入」を再度押すだけで再試行可能）
- 部分結果保持（推定失敗時に「とりあえずカロリーだけ」のような中途半端な状態は作らない）
- 推定結果のキャッシュ（同じテキストで何度も呼ぶ可能性は低い）

---

## 9. テスト戦略

### 9.1 Flutter 側

- **Widget Preview関数追加**:
  - `MealTagForm - State 1 (Input)` (既存)
  - `MealTagForm - State 2 (Loading)` (新規)
  - `MealTagForm - State 3 (Confirmation)` (新規)
  - `MealTagForm - Error State` (新規)
- **Provider のユニットテスト**: `aiFeaturesEnabledProvider` の課金プラン分岐
- **ステートマシン遷移のテスト**

### 9.2 Edge Function 側

- Claude API モック（`fetch` モックして決まった JSON を返す）
- 課金チェック分岐テスト（free / pro / 担当trainer無し）
- Rate limit テスト（50回目までOK、51回目 429）
- バリデーション失敗テスト（不正レスポンス、必須キー欠落、負数）

### 9.3 手動 QA

`ios-simulator-qa` スキルで:
- 課金済みトレーナーのクライアントでフルフロー（入力 → 推定 → 確認 → 送信 → DB確認）
- 課金未解放トレーナーのクライアントで既存挙動が変わらないこと
- エラー時の「AIなしで送信」フォールバック動作確認

---

## 10. オープンな技術的論点

これらは設計範囲外として、実装時に解消するもの:

1. **`clients.trainer_id` の null 許容**: 現状クライアントは必ずトレーナーに紐づくが、未紐付けケースの挙動 → 実装時にスキーマ確認、未紐付けなら AI 機能非表示（403）
2. **既存 RLS で `trainers.subscription_plan` をクライアントが SELECT できるか**: 実装時に既存ポリシーを確認、不足なら追加マイグレーション（4.5 参照）
3. **編集時の metadata 整合性**: Stage 1 では「メッセージ編集すると `meal_records` の PFC は元の値のまま」（webhookは metadata を再利用、AI 再推定なし）

---

## 11. 完了条件（Stage 1）

- [ ] DB マイグレーション 4本適用（meal_records 拡張、trainers.subscription_plan、messages.metadata、ai_estimation_logs）
- [ ] Edge Function `estimate-meal-nutrition` 実装・デプロイ
- [ ] `parse-message-tags` の metadata 対応改修
- [ ] Flutter `MealTagForm` 3状態化
- [ ] `aiFeaturesEnabledProvider` 実装
- [ ] 「AIなしで送信」フォールバック動作確認
- [ ] Widget Preview 関数追加（State 2/3/Error）
- [ ] テストアカウント（'pro' プラン）でフルフロー成功
- [ ] テストアカウント（'free' プラン）で既存挙動が変わらないことを確認
- [ ] `IMPLEMENTATION_TASKS.md` のフェーズ2 進捗を更新（2.1 / 2.2 完了マーク）

---

## 12. 参考: Stage 2 以降への布石

本設計は以下を「Stage 2 以降で増分追加できる」ように構成している:

- **画像推定（Stage 2）**: Edge Function を `image_urls` 対応に拡張、Claude Vision で同じレスポンス形式を返す
- **タグ自動推定（Stage 3）**: `parse-message-tags` が metadata 無しメッセージを検知したとき、AI 推定を発火するパスを追加
- **スクショ分析（Stage 4）**: 別プロンプト系統の Edge Function を追加、`source = 'screenshot:<app_name>'` で記録

すべて Stage 1 のスキーマ・アーキテクチャの上に成り立つ。
