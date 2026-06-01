# 設計: 食事アプリ スクショ取り込み（タスク2.5）

**作成日**: 2026-05-31
**対象**: fit-connect-mobile（Flutter）+ supabase（Edge Function / migration）+ fit-connect（Web 型定義）
**関連タスク**: `docs/tasks/IMPLEMENTATION_TASKS.md` フェーズ2 タスク2.5
**前提**: 2.1〜2.4(a) 完了（Edge Function `estimate-meal-nutrition`、3-state `MealTagForm`、`MealEstimationConfirmView`、`aiFeaturesEnabledProvider` ゲート）

---

## 1. 目的とスコープ

他社食事管理アプリ（あすけん／カロミル／MyFitnessPal 等）の**画面スクリーンショット**から、Claude Vision で表示済みのカロリー・PFC・食品名を**読み取り**、`meal_records` に取り込む。他アプリユーザーの流入導線として位置づける。

### v1 スコープ（YAGNI）
- **1枚のスクショ＝1食分の合計**を読み取る（合計 kcal + PFC + 食品名リスト）
- 食事区分（朝/昼/夕/間食）は**従来どおりフォームでユーザーが選択**、`recorded_at` は送信時刻
- アプリ名は **Claude が自動検出**（不明時 `unknown`）

### スコープ外（バックログ）
- 1日サマリー（朝・昼・夕・間食）から**複数 meal_records** を一括生成
- スクショからの**日付・食事区分の自動読み取り**（過去日付での記録）
- アプリ別の精緻なレイアウト最適化／信頼度スコア表示

---

## 2. 全体アーキテクチャと決定事項

| 決定 | 内容 | 理由 |
|------|------|------|
| 入口 | 食事タグフォーム上部に**セグメント切替「料理を記録 / 他アプリから取込」**。**Pro のみ表示**、free は従来フォーム | 明示モードで意図が明確、`source` を確実に記録、2.4(a) の責務分離方針と整合 |
| アプリ特定 | **Claude が画面からアプリ名を推測**し `app_name` で返す | ユーザー操作を増やさない。タップ数最小 |
| 抽出単位 | **1食分の合計のみ** | 「1メッセージ=1食記録」モデルを維持、2.3 の confirm UI を流用、アーキ変更最小 |
| source 保存 | `meal_records` に**新カラム `ai_source`** を追加し `text`/`photo`/`screenshot:<app>` を保存 | 既存 `source`（CHECK `manual`/`message`）は記録作成経路用で流用不可 |

### データフロー

```
[input / screenshot モード]（Pro のみ）
  スクショ添付 → ✨「スクショを解析」
    → StorageService.uploadAiImages（既存 ${userId}/ai/ パス・_fileToUrlMap 再upload回避）
    → MealEstimationApi.estimate(inputKind: 'screenshot', mealType, content, imageUrls)
        → Edge Function estimate-meal-nutrition
            input_kind='screenshot' で専用システムプロンプトに分岐（claude-sonnet-4-6）
            → { foods, totals, app_name }
    → confirm ステート（MealEstimationConfirmView 流用 + 「📱 <app名> から読み取り」ラベル）
    → 送信 → metadata.meal_estimation.source = 'screenshot:<app名>'
    → parse-message-tags webhook → meal_records.ai_source に保存
```

---

## 3. コンポーネント別設計

### 3.1 Edge Function `estimate-meal-nutrition`（supabase/functions/）

**リクエスト拡張**:
- 新フィールド `input_kind: 'photo' | 'screenshot'`（任意、デフォルト `'photo'`）
- 未指定時は従来挙動（後方互換）。`screenshot` は `image_urls` 非空が前提（空なら `INVALID_INPUT`）

**プロンプト分岐**:
- `input_kind === 'screenshot'` のとき**専用システムプロンプト**を使用（`cache_control: ephemeral` は維持）:
  - これは他社食事管理アプリの**画面スクリーンショット**である
  - **画面に表示された数値を読み取る（推定しない）**。kcal/PFC が画面にあればその値を優先
  - アプリ名（あすけん/カロミル/MyFitnessPal 等）を画面の特徴から推測し `app_name` に格納。判別不能なら `"unknown"`
  - 1食分の合計を返す。複数食が写っていても**最も主要な1食 or 画面の合計**を返す（v1）
  - 食事アプリの画面でない／数値を読み取れない場合は `foods` を空配列で返す
  - 返却 JSON: `{ "foods": [...], "totals": {...}, "app_name": string }`
- `photo`（既定）は**現行システムプロンプトのまま**

**レスポンス拡張**:
- `app_name`（string）を追加。`screenshot` 以外では空文字 `""` を返す（または省略）
- `foods` 空 → 従来どおり `EMPTY_RESULT(422)`
- `totals` は foods から再計算する既存ロジックを維持

**流用（変更なし）**: モデル切替（hasImages → sonnet）、サブスクゲート、レートリミット、`ai_estimation_logs`、`extractJson`、整数化クランプ、30s タイムアウト

### 3.2 Mobile API クライアント（meal_estimation_api.dart）

- `estimate()` に **`String inputKind = 'photo'`** 引数を追加。body に `input_kind` を付与
- `MealEstimationResult.fromJson` に `app_name` → `appName`（String?, 任意）を追加
- エラーマッピング（`MealEstimationErrorCode`）は流用

### 3.3 結果モデル（meal_estimation_result.dart）

- `MealEstimationResult` に `final String? appName;` を追加（`@JsonKey(name: 'app_name')`）。build_runner 再生成

### 3.4 MealTagForm（structured_tag_form.dart）

- 入力モード状態 **`enum _MealInputMode { cook, screenshot }`** と `_inputMode` フィールドを追加
- input ステート上部に**セグメント切替**（`SegmentedButton` 等）を追加。**`aiEnabled`（Pro）のときのみ表示**。free / 未解決時は非表示（従来フォーム）
- `screenshot` モード時の差分:
  - 画像追加ヒント文言を「スクショを追加」に
  - 主ボタンを「✨ スクショを解析」（sparkles, FilledButton）
  - **「AIなしで挿入」は非表示**（スクショ画像のみ挿入は無意味）
  - `_handleEstimate` に `inputKind: 'screenshot'` を渡す（アップロード・estimate・confirm 遷移は流用）
- `cook` モード時は 2.4(a) の現行挙動（AI推定 + AIなしで挿入）を完全維持
- confirm 遷移時、`_estimation.appName` を保持して confirm view に渡す

### 3.5 確認ビュー（meal_estimation_confirm_view.dart）

- スクショ由来（`appName != null`）のとき、上部に小ラベル「📱 <app名> から読み取り」を表示（アイコンは LucideIcons 系、絵文字は使わない）
- 合計4値編集・食品リスト read-only・画像サムネイル read-only は流用

### 3.6 送信メタデータ（chat_input.dart）

- `_handleSendWithEstimation` の `metadata.meal_estimation.source` を:
  - スクショ: `'screenshot:<appName>'`（appName 不明時 `'screenshot:unknown'`）
  - 料理写真: `'photo'`（現行 `'vision'` から改称し意味を明確化）
  - テキスト: `'text'`（現行どおり）

### 3.7 meal_records スキーマ（supabase/migrations/）

- 新マイグレーション: `meal_records` に **`ai_source text`**（NULL 許容、デフォルト NULL）を追加
  - 値: `'text'` / `'photo'` / `'screenshot:<app名>'`。AI 推定でない記録は NULL
  - CHECK 制約は付けない（`screenshot:<可変app名>` を許容するため）。アプリ層で値を制御
- 既存 `source`（`manual`/`message`）カラムは**変更しない**

### 3.8 parse-message-tags webhook（supabase/functions/）

- `createMealRecord` の insert に **`ai_source: metadata.meal_estimation.source`** を追加
- スクショだけでなく既存の photo/text 経路も保存され、AI 記録の入力経路が全件揃う

### 3.9 Web 型定義（fit-connect/src/types/）

- `MealRecord` 型に `ai_source?: string | null` を追加（トレーナー Web の表示は今回は最小限。型整合のみ）

---

## 4. エラーハンドリング / フォールバック

| ケース | 挙動 |
|--------|------|
| `EMPTY_RESULT(422)`（食事アプリ画面でない/読み取り不可） | input に戻し「スクショから栄養情報を読み取れませんでした」スナックバー。料理写真/テキスト入力への切替を促す |
| `FORBIDDEN`（非 Pro） | そもそもセグメント切替が非表示のため到達しない。万一時は従来のフォールバック |
| `RATE_LIMIT` / `ESTIMATION_FAILED` / `network` | 既存マッピングのスナックバー文言を流用 |
| タイムアウト | API client 45s / Edge 内 Claude 30s を流用 |

---

## 5. テスト / QA 方針

- **Edge Function**: `input_kind='screenshot'` で専用プロンプトが選択されること、`app_name` が返ること、`input_kind` 未指定で後方互換であることを確認
- **build_runner**: `MealEstimationResult` の appName 追加後に `dart run build_runner build --delete-conflicting-outputs`
- **flutter analyze** 通過
- **`@Preview`**: screenshot モードの input ステート（セグメント切替・「スクショを解析」ボタン）の Preview を追加
- **QA**: `ios-simulator-qa` でビルド・起動・モード切替・解析→confirm フロー（実機スクショ画像を用意）。computer-use 制約は lessons.md 既知

---

## 6. 横断影響チェックリスト

- [ ] supabase: 新マイグレーション（`meal_records.ai_source`）→ **ローカル/リモート両方に適用必要**
- [ ] supabase: Edge Function `estimate-meal-nutrition` 再デプロイ
- [ ] supabase: `parse-message-tags` webhook 再デプロイ
- [ ] Mobile: `meal_estimation_api.dart` / `meal_estimation_result.dart`（+ .g.dart）/ `structured_tag_form.dart` / `meal_estimation_confirm_view.dart` / `chat_input.dart`
- [ ] Web: `fit-connect/src/types/` の `MealRecord` 型

---

## 7. 実装順序（依存関係）

1. supabase migration（`ai_source` カラム）
2. Edge Function プロンプト分岐 + `app_name` レスポンス
3. webhook の `ai_source` 保存
4. Mobile: API クライアント + 結果モデル（build_runner）
5. Mobile: MealTagForm セグメント切替 + screenshot モード分岐
6. Mobile: confirm view のアプリ名ラベル + chat_input の source 文字列
7. Web: 型定義
8. Preview 追加 → flutter analyze → QA
