# 食事アプリ スクショ取り込み（タスク2.5）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 他社食事管理アプリ（あすけん等）の画面スクショから、Claude Vision で表示済みのカロリー・PFC・食品名を読み取り、`meal_records` に1食分として取り込む。

**Architecture:** 既存の食事AI推定インフラ（Edge Function `estimate-meal-nutrition` の画像ルート、`MealTagForm` 3-state マシン、`MealEstimationConfirmView`、`parse-message-tags` webhook）を最大流用。Edge Function に `input_kind='screenshot'` 分岐（専用プロンプト + `app_name` 検出）を追加し、Mobile 側は食事タグフォーム上部のセグメント切替（Pro のみ）で「料理を記録 / 他アプリから取込」を出し分ける。AI 入力経路は新カラム `meal_records.ai_source`（`text`/`photo`/`screenshot:<app>`）に保存する。

**Tech Stack:** Supabase Edge Functions (Deno/TypeScript)、PostgreSQL migration、Flutter (Dart, Riverpod, json_serializable)、Claude (sonnet-4-6 vision)。

**設計ドキュメント:** `docs/superpowers/specs/2026-05-31-meal-screenshot-import-design.md`

**ブランチ:** `feature/meal-screenshot-import`（作成済み）

**役割分担(CLAUDE.md):** マネージャーは実装せず各タスクをサブエージェントへ委託する。Supabase 系（Task 1〜3, 7）は `supabase` エージェント、Mobile 系（Task 4〜6, 8）は `flutter-ui` / `riverpod` エージェントに委託する。

---

## ファイル構成（作成 / 変更）

| ファイル | 責務 | 操作 |
|----------|------|------|
| `supabase/migrations/20260531000000_add_ai_source_to_meal_records.sql` | `meal_records.ai_source` 追加 | Create |
| `supabase/functions/estimate-meal-nutrition/index.ts` | `input_kind` 分岐・スクショ用プロンプト・`app_name` 返却 | Modify |
| `supabase/functions/parse-message-tags/index.ts` | `ai_source` を meal_records に保存 | Modify |
| `fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.dart` | `appName` フィールド追加 | Modify |
| `fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart` | `inputKind` 引数追加 | Modify |
| `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart` | セグメント切替・screenshot モード分岐・preview | Modify |
| `fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart` | アプリ名ラベル表示 | Modify |
| `fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart` | `source` 文字列の組み立て | Modify |
| `fit-connect/src/types/`（`MealRecord` 型定義ファイル） | `ai_source` 型追加 | Modify |

---

## Task 1: meal_records に ai_source カラムを追加（migration）

**委託先:** `supabase` エージェント

**Files:**
- Create: `supabase/migrations/20260531000000_add_ai_source_to_meal_records.sql`

- [ ] **Step 1: マイグレーションファイルを作成**

`supabase/migrations/20260531000000_add_ai_source_to_meal_records.sql`:

```sql
-- AI推定の入力経路を記録する列を追加
-- 'text'（テキスト推定）/ 'photo'（料理写真）/ 'screenshot:<app名>'（他アプリのスクショ）
-- AI推定でない記録は NULL。<app名> が可変のため CHECK 制約は付けずアプリ層で値を制御する。
ALTER TABLE "public"."meal_records"
  ADD COLUMN "ai_source" text;

COMMENT ON COLUMN "public"."meal_records"."ai_source" IS 'AI推定の入力経路: text / photo / screenshot:<app名>。手動記録は NULL';
```

- [ ] **Step 2: ローカル Supabase へ適用して検証**

ルート `FIT-CONNECT/` から実行:

Run: `supabase db push`
Expected: マイグレーションが適用され `meal_records.ai_source` カラムが追加される（エラーなし）。

※ ローカル Supabase が起動していない場合は `supabase start` を先に実行。リモート反映は最終 QA 後にユーザー確認のうえ実施する。

- [ ] **Step 3: コミット**

```bash
git add supabase/migrations/20260531000000_add_ai_source_to_meal_records.sql
git commit -m "feat(db): meal_records に ai_source カラムを追加（タスク2.5）"
```

---

## Task 2: Edge Function に screenshot 分岐を追加

**委託先:** `supabase` エージェント

**Files:**
- Modify: `supabase/functions/estimate-meal-nutrition/index.ts`

- [ ] **Step 1: スクショ用システムプロンプト定数を追加**

`index.ts` の既存 `SYSTEM_PROMPT`（9〜25行）の直後に追記する:

```ts
const SCREENSHOT_SYSTEM_PROMPT = `あなたは食事管理アプリの画面スクリーンショットから栄養情報を読み取るアシスタントです。これは他社の食事管理アプリ（あすけん、カロミル、MyFitnessPal 等）の画面のスクリーンショットです。

返却形式は厳密に以下の JSON のみ（説明文・コードフェンス禁止）:
{
  "foods": [{"name": string, "calories": number, "protein_g": number, "fat_g": number, "carbs_g": number}],
  "totals": {"calories": number, "protein_g": number, "fat_g": number, "carbs_g": number},
  "app_name": string
}

指針:
- 画面に表示されている数値を「読み取る」こと。自分で推定や再計算をしない
- カロリー・PFC（タンパク質・脂質・炭水化物）が画面に表示されていれば、その値をそのまま使う
- 食品名リストが画面にあれば foods に列挙する。合計値しか読み取れない場合は foods に1件「合計」としてまとめてよい
- すべて整数（小数点以下は切り捨て）
- totals は画面の合計表示を優先。読み取れない場合は foods の合計とする
- app_name には画面の特徴から推測したアプリ名（例: "あすけん", "カロミル", "MyFitnessPal"）を入れる。判別できなければ "unknown"
- 1日分（朝・昼・夕・間食）が写っている場合でも、画面の合計または最も主要な1食分のみを返す
- 食事管理アプリの画面でない、または栄養数値を読み取れない場合は foods を空配列で返す`;
```

- [ ] **Step 2: callClaude を inputKind 対応にする**

`callClaude` のシグネチャ（29〜34行）に `inputKind` を追加し、プロンプトを切り替える。

29〜34行を:

```ts
async function callClaude(
  apiKey: string,
  mealType: string,
  content: string,
  imageUrls: string[],
  inputKind: 'photo' | 'screenshot',
): Promise<any> {
```

に変更。さらに 62〜64行の `system` 配列を以下に変更（プロンプトを inputKind で選択）:

```ts
        system: [
          {
            type: 'text',
            text: inputKind === 'screenshot' ? SCREENSHOT_SYSTEM_PROMPT : SYSTEM_PROMPT,
            cache_control: { type: 'ephemeral' },
          },
        ],
```

- [ ] **Step 3: リクエストの input_kind をパースし screenshot を検証**

196〜208行の body パース部を以下に変更（`input_kind` 追加 + screenshot 時の画像必須チェック）:

```ts
    const { meal_type, content } = body
    const inputKind: 'photo' | 'screenshot' =
      body.input_kind === 'screenshot' ? 'screenshot' : 'photo'
    const rawImageUrls = body.image_urls
    const imageUrls: string[] = Array.isArray(rawImageUrls)
      ? rawImageUrls.filter((u): u is string => typeof u === 'string' && u.length > 0).slice(0, 3)
      : []

    if (!['breakfast', 'lunch', 'dinner', 'snack'].includes(meal_type)) {
      return errorResponse('INVALID_INPUT', 'Invalid meal_type', 400)
    }
    const contentStr = typeof content === 'string' ? content : ''
    if (inputKind === 'screenshot' && imageUrls.length === 0) {
      return errorResponse('INVALID_INPUT', 'Screenshot mode requires an image', 400)
    }
    if (contentStr.trim().length === 0 && imageUrls.length === 0) {
      return errorResponse('INVALID_INPUT', 'Empty content and no images', 400)
    }
```

- [ ] **Step 4: Claude 呼び出しに inputKind を渡し、app_name をレスポンスへ含める**

246〜260行（Claude 呼び出し try ブロック）を以下に変更:

```ts
    // 6. Claude 呼び出し
    let result
    let appName = ''
    try {
      const raw = await callClaude(anthropicKey, meal_type, contentStr, imageUrls, inputKind)
      result = validateEstimation(raw)
      if (inputKind === 'screenshot') {
        appName = typeof raw.app_name === 'string' && raw.app_name.trim().length > 0
          ? raw.app_name.trim()
          : 'unknown'
      }
    } catch (e) {
      console.error('Claude call/parse failed:', e)
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'ESTIMATION_FAILED',
      })
      return errorResponse('ESTIMATION_FAILED', 'Estimation failed', 500)
    }
```

そして成功レスポンス（281〜283行）を以下に変更（screenshot のときだけ `app_name` を付与）:

```ts
    const responseBody = inputKind === 'screenshot'
      ? { ...result, app_name: appName }
      : result
    return new Response(JSON.stringify(responseBody), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
```

- [ ] **Step 5: Deno の型チェック / lint で構文確認**

Run: `deno check supabase/functions/estimate-meal-nutrition/index.ts`
Expected: 型エラーなし（`// @ts-nocheck` 付きのため警告のみ許容。構文エラーが出ないこと）。

- [ ] **Step 6: コミット**

```bash
git add supabase/functions/estimate-meal-nutrition/index.ts
git commit -m "feat(edge): estimate-meal-nutrition に screenshot 分岐と app_name 検出を追加（タスク2.5）"
```

---

## Task 3: webhook で ai_source を保存

**委託先:** `supabase` エージェント

**Files:**
- Modify: `supabase/functions/parse-message-tags/index.ts:172-199`

- [ ] **Step 1: createMealRecord の両 insert に ai_source を追加**

`createMealRecord`（153〜200行）の2つの `insert` 呼び出しに `ai_source` を追加する。

hasValidEstimation の insert（173〜187行）に1行追加:

```ts
  if (hasValidEstimation) {
    return await supabase.from('meal_records').insert({
      client_id: commonData.client_id,
      source: commonData.source,
      message_id: commonData.message_id,
      recorded_at: commonData.recorded_at,
      notes: commonData.notes,
      meal_type: mealType,
      images: commonData.image_urls,
      calories: estimation.calories,
      protein_g: estimation.protein_g,
      fat_g: estimation.fat_g,
      carbs_g: estimation.carbs_g,
      ai_foods: estimation.foods,
      estimated_by_ai: true,
      ai_source: typeof estimation.source === 'string' ? estimation.source : null,
    })
  }
```

既存挙動の insert（191〜199行）は AI 推定なしのため `ai_source` は不要（NULL のまま）。変更しない。

- [ ] **Step 2: Deno 型チェック**

Run: `deno check supabase/functions/parse-message-tags/index.ts`
Expected: 構文エラーなし。

- [ ] **Step 3: コミット**

```bash
git add supabase/functions/parse-message-tags/index.ts
git commit -m "feat(edge): parse-message-tags で ai_source を meal_records に保存（タスク2.5）"
```

---

## Task 4: 結果モデルに appName を追加

**委託先:** `flutter-ui` エージェント（または `riverpod`）

**Files:**
- Modify: `fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.dart`
- 再生成: `meal_estimation_result.g.dart`

- [ ] **Step 1: MealEstimationResult に appName フィールドを追加**

`meal_estimation_result.dart` の `MealEstimationResult` クラス（5〜15行）を以下に変更:

```dart
@JsonSerializable()
class MealEstimationResult {
  final List<EstimatedFood> foods;
  final EstimationTotals totals;

  /// スクショ取り込み時に Claude が検出したアプリ名（例: 'あすけん', 'unknown'）。
  /// 料理写真・テキスト推定では null。
  @JsonKey(name: 'app_name')
  final String? appName;

  const MealEstimationResult({
    required this.foods,
    required this.totals,
    this.appName,
  });

  factory MealEstimationResult.fromJson(Map<String, dynamic> json) =>
      _$MealEstimationResultFromJson(json);
  Map<String, dynamic> toJson() => _$MealEstimationResultToJson(this);
}
```

- [ ] **Step 2: build_runner でコード再生成**

Run（`fit-connect-mobile/` から）:
```bash
fvm flutter pub run build_runner build --delete-conflicting-outputs
```
Expected: `meal_estimation_result.g.dart` が再生成され、`appName` が `app_name` キーでマップされる。エラーなし。

- [ ] **Step 3: analyze**

Run: `fvm flutter analyze lib/features/meal_records/models/meal_estimation_result.dart`
Expected: No issues found.

- [ ] **Step 4: コミット**

```bash
git add fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.dart fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.g.dart
git commit -m "feat(mobile): MealEstimationResult に appName を追加（タスク2.5）"
```

---

## Task 5: API クライアントに inputKind を追加

**委託先:** `flutter-ui` エージェント

**Files:**
- Modify: `fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart:17-30`

- [ ] **Step 1: estimate() に inputKind 引数を追加**

`meal_estimation_api.dart` の `estimate` メソッド（17〜30行）を以下に変更:

```dart
  static Future<MealEstimationResult> estimate({
    required String mealType, // 'breakfast' | 'lunch' | 'dinner' | 'snack'
    required String content,
    List<String> imageUrls = const [],
    String inputKind = 'photo', // 'photo' | 'screenshot'
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'estimate-meal-nutrition',
        body: {
          'meal_type': mealType,
          'content': content,
          if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
          'input_kind': inputKind,
        },
      ).timeout(const Duration(seconds: 45));
```

以降（32行目以降）は変更しない。

- [ ] **Step 2: analyze**

Run: `fvm flutter analyze lib/features/meal_records/data/meal_estimation_api.dart`
Expected: No issues found.

- [ ] **Step 3: コミット**

```bash
git add fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart
git commit -m "feat(mobile): MealEstimationApi.estimate に inputKind を追加（タスク2.5）"
```

---

## Task 6: MealTagForm にセグメント切替と screenshot モードを追加

**委託先:** `flutter-ui` エージェント

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`

screenshot モードの状態管理・UI 出し分け・推定呼び出し分岐を追加する。

- [ ] **Step 1: 入力モード enum と状態フィールド、debug 用初期モードを追加**

`_MealFormPhase` enum（289行）の直後に追加:

```dart
/// 食事タグフォームの入力モード。
/// cook = 料理を記録（写真/テキスト）、screenshot = 他アプリのスクショから取込。
enum _MealInputMode { cook, screenshot }
```

`MealTagForm` ウィジェット（291〜316行）に Preview 用の初期モード引数を追加する。`onSendWithEstimation` フィールドの直後（305行付近）に:

```dart
  /// Preview/テスト用に screenshot モードで初期表示する（本番の通常導線では未指定）。
  final bool debugInitialScreenshotMode;
```

を追加し、コンストラクタ（307〜316行）の `this.onSendWithEstimation,` の直後に:

```dart
    this.debugInitialScreenshotMode = false,
```

を追加。

`_MealTagFormState` のフィールド（322〜333行付近、`_isSending` の直後）に状態を追加:

```dart
  late _MealInputMode _inputMode;
```

`initState`（338〜345行）の `_selectedMealType = _getDefaultMealType();` の直後に1行追加:

```dart
    _inputMode = widget.debugInitialScreenshotMode
        ? _MealInputMode.screenshot
        : _MealInputMode.cook;
```

- [ ] **Step 2: _handleEstimate に inputKind を渡す**

`_handleEstimate`（387行）内の `MealEstimationApi.estimate(...)` 呼び出し（441〜445行）を以下に変更:

```dart
      final result = await MealEstimationApi.estimate(
        mealType: _mealTypeToEnum(_selectedMealType),
        content: _contentController.text.trim(),
        imageUrls: imageUrls,
        inputKind: _inputMode == _MealInputMode.screenshot ? 'screenshot' : 'photo',
      );
```

また、screenshot モードでは画像必須のため、`_handleEstimate` 冒頭（388行 `if (!_isValid) return;` の直後）に安全網を追加:

```dart
    // screenshot モードは画像必須
    if (_inputMode == _MealInputMode.screenshot && !widget.hasImages) return;
```

- [ ] **Step 3: input ステートにモード切替セグメントを追加**

`_buildInputState`（578行）で、AI 機能解放時（Pro）のみモード切替セグメントを表示する。
ヘッダー行の `const SizedBox(height: 12),`（603行）の直後、食事区分セグメント（606行）の前に挿入:

```dart
        // 入力モード切替（Pro のみ表示）。free/未解決時は従来フォーム（cook 固定）。
        if (ref.watch(aiFeaturesEnabledProvider).maybeWhen(
              data: (enabled) => enabled,
              orElse: () => false,
            )) ...[
          _SegmentControl(
            items: const ['料理を記録', '他アプリから取込'],
            selected: _inputMode == _MealInputMode.screenshot
                ? '他アプリから取込'
                : '料理を記録',
            onChanged: (value) => setState(() {
              _inputMode = value == '他アプリから取込'
                  ? _MealInputMode.screenshot
                  : _MealInputMode.cook;
            }),
            colors: colors,
          ),
          const SizedBox(height: 8),
        ],
```

- [ ] **Step 4: screenshot モードで画像ヒント文言と入力欄ヒントを切り替える**

`_buildInputState` の TextField hintText（619行）を mode で切り替える。619行を:

```dart
            hintText: _inputMode == _MealInputMode.screenshot
                ? 'メモ（任意）'
                : '食事内容やコメントを入力',
```

に変更。

画像ピッカー行（646〜651行）に追加ラベル引数を渡す（次 Step で `_ImagePickerRow` 側に対応引数を追加）。646〜651行を:

```dart
        // 画像ピッカー行
        _ImagePickerRow(
          images: widget.selectedImages,
          onPick: widget.onPickImage,
          onRemove: widget.onRemoveImage,
          colors: colors,
          addLabel: _inputMode == _MealInputMode.screenshot ? 'スクショを追加' : null,
        ),
```

に変更。

- [ ] **Step 5: _ImagePickerRow に addLabel 引数を追加**

`structured_tag_form.dart` 内の `_ImagePickerRow` ウィジェット定義を探す（`class _ImagePickerRow`）。コンストラクタにオプション引数 `final String? addLabel;` を追加し、「写真を追加」等の追加ボタンのラベルを `addLabel ?? '<既存の既定ラベル>'` に置き換える。既存の既定ラベル文字列はそのまま既定値として維持すること（cook モードの表示を変えない）。

Run: `grep -n "class _ImagePickerRow" fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`
Expected: 定義位置を特定し、`addLabel` を反映。

- [ ] **Step 6: screenshot モードのアクションボタンを出し分ける**

`_buildPreviewActions`（665行）で screenshot モード時は主ボタン1つ（「スクショを解析」）のみ表示する。
Pro 分岐（681行のコメント以降〜753行の Column）の手前、`if (!aiEnabled) { ... }`（672〜679行）の直後に screenshot 分岐を追加:

```dart
    // Pro かつ screenshot モード: 「スクショを解析」主ボタン1つ（「AIなしで挿入」は出さない）
    if (_inputMode == _MealInputMode.screenshot) {
      final canAnalyze = widget.hasImages;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.messageCircle, size: 13, color: colors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _previewText,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canAnalyze ? _handleEstimate : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: const Text('スクショを解析'),
            ),
          ),
          if (!canAnalyze) ...[
            const SizedBox(height: 6),
            Text(
              'スクショ画像を追加してください',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
        ],
      );
    }
```

- [ ] **Step 7: confirm ステートに appName を渡す**

`_buildConfirmState`（783行）の `MealEstimationConfirmView(...)` 呼び出しに `appName` を追加（Task 7 で confirm view 側に引数追加）。`isSending: _isSending,`（798行）の直後に:

```dart
      appName: _estimation!.appName,
```

を追加。

- [ ] **Step 8: analyze**

Run（`fit-connect-mobile/` から）:
```bash
fvm flutter analyze lib/features/messages/presentation/widgets/structured_tag_form.dart
```
Expected: No issues found.（Task 7 の confirm view 引数追加が未了だと `appName` named param エラーになるため、Task 7 を先に/同時に行うか、本 analyze は Task 7 後にまとめて実施してよい。）

- [ ] **Step 9: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart
git commit -m "feat(mobile): 食事タグフォームにスクショ取込モード切替を追加（タスク2.5）"
```

---

## Task 7: confirm view にアプリ名ラベルを追加

**委託先:** `flutter-ui` エージェント

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart`

- [ ] **Step 1: ファイル構造を確認**

Run: `grep -n "class MealEstimationConfirmView\|final \|Widget build\|Column(\|children:" fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart | head -40`
Expected: コンストラクタのフィールド一覧と build の最上位 Column の children 開始位置を把握。

- [ ] **Step 2: appName フィールドを追加**

`MealEstimationConfirmView` のコンストラクタに optional フィールドを追加:

```dart
  /// スクショ取り込み時の検出アプリ名（'unknown' や null のときラベル非表示）。
  final String? appName;
```

をフィールド宣言群に追加し、コンストラクタ初期化リストに `this.appName,` を追加する。

- [ ] **Step 3: build の先頭に検出元ラベルを表示**

build メソッド内、最上位 `Column` の `children:` 配列の先頭に、appName が有効なときだけラベル行を挿入する:

```dart
        if (appName != null && appName!.isNotEmpty && appName != 'unknown') ...[
          Row(
            children: [
              Icon(LucideIcons.smartphone, size: 14, color: colors.textSecondary),
              const SizedBox(width: 6),
              Text(
                '$appName から読み取り',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
```

※ `colors` は build 内で既存の `AppColors.of(context)` 由来の変数を使用（既存コードの命名に合わせる）。`LucideIcons` が未 import の場合は `import 'package:lucide_icons/lucide_icons.dart';` を追加。

- [ ] **Step 4: analyze（structured_tag_form と合わせて）**

Run（`fit-connect-mobile/` から）:
```bash
fvm flutter analyze lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart lib/features/messages/presentation/widgets/structured_tag_form.dart
```
Expected: No issues found.

- [ ] **Step 5: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart
git commit -m "feat(mobile): 確認画面に読み取り元アプリ名ラベルを追加（タスク2.5）"
```

---

## Task 8: 送信 source 文字列の組み立て + Preview + Web 型 + QA

**委託先:** `flutter-ui` エージェント（chat_input/Preview）、`supabase` エージェント不要、Web 型はマネージャー or Web 担当

### 8a. chat_input の source 文字列

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart:364-373`

- [ ] **Step 1: metadata.meal_estimation.source を appName 対応に**

`_handleSendWithEstimation`（355行）の metadata 構築（364〜373行）を以下に変更:

```dart
    final appName = estimation.appName;
    final String mealSource;
    if (appName != null && appName.isNotEmpty) {
      mealSource = 'screenshot:$appName';
    } else if (imageUrls.isNotEmpty) {
      mealSource = 'photo';
    } else {
      mealSource = 'text';
    }

    final metadata = <String, dynamic>{
      'meal_estimation': {
        'foods': estimation.foods.map((f) => f.toJson()).toList(),
        'calories': estimation.totals.calories,
        'protein_g': estimation.totals.proteinG,
        'fat_g': estimation.totals.fatG,
        'carbs_g': estimation.totals.carbsG,
        'source': mealSource,
      },
    };
```

- [ ] **Step 2: analyze**

Run: `fvm flutter analyze lib/features/messages/presentation/widgets/chat_input.dart`
Expected: No issues found.

- [ ] **Step 3: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart
git commit -m "feat(mobile): 送信 source を screenshot:<app>/photo/text で記録（タスク2.5）"
```

### 8b. Preview 追加

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`（既存 `previewMealTagFormPro` の近く）

- [ ] **Step 4: screenshot モードの Preview を追加**

既存 `previewMealTagFormPro` 関数の直後に追加:

```dart
@Preview(name: 'MealTagForm - スクショ取込モード')
Widget previewMealTagFormScreenshot() {
  return ProviderScope(
    overrides: [
      aiFeaturesEnabledProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MealTagForm(
            onCompose: (_) {},
            onClose: () {},
            hasImages: true,
            onSendWithEstimation: (_, __, ___) async {},
            debugInitialScreenshotMode: true,
          ),
        ),
      ),
    ),
  );
}
```

※ `previewMealTagFormPro` と同じ import / 参照（`AppTheme`, `ProviderScope`, `@Preview`）が既にファイル先頭にあることを確認。なければ揃える。

- [ ] **Step 5: analyze**

Run: `fvm flutter analyze lib/features/messages/presentation/widgets/structured_tag_form.dart`
Expected: No issues found.

- [ ] **Step 6: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart
git commit -m "feat(mobile): スクショ取込モードの Preview を追加（タスク2.5）"
```

### 8c. Web 型定義

**Files:**
- Modify: `fit-connect/src/types/`（`MealRecord` 型を含むファイル）

- [ ] **Step 7: MealRecord 型に ai_source を追加**

Run: `grep -rn "interface MealRecord\|type MealRecord\|estimated_by_ai" fit-connect/src/types/`
Expected: `MealRecord` 型の定義ファイルを特定。

特定したファイルの `MealRecord` 型（`estimated_by_ai` や `ai_foods` がある箇所）に追加:

```ts
  ai_source?: string | null; // AI推定の入力経路: text / photo / screenshot:<app名>
```

- [ ] **Step 8: 型チェック**

Run（`fit-connect/` から）: `npm run type-check`（または `npx tsc --noEmit`）
Expected: 型エラーなし。

- [ ] **Step 9: コミット**

```bash
git add fit-connect/src/types/
git commit -m "feat(web): MealRecord 型に ai_source を追加（タスク2.5）"
```

### 8d. 全体ビルド & QA

- [ ] **Step 10: build_runner + 全体 analyze**

Run（`fit-connect-mobile/` から）:
```bash
fvm flutter pub run build_runner build --delete-conflicting-outputs && fvm flutter analyze
```
Expected: コード生成成功、`No issues found!`。

- [ ] **Step 11: ios-simulator-qa スキルで動作確認**

マネージャーが `ios-simulator-qa` スキルを実行。確認項目:
- ビルド・起動
- メッセージ画面で #食事 タグフォームを開く（Pro クライアント）
- 上部セグメントに「料理を記録 / 他アプリから取込」が表示される
- 「他アプリから取込」に切替 → 画像ヒントが「スクショを追加」、主ボタンが「スクショを解析」、「AIなしで挿入」が消える
- 実機スクショ画像（あすけん等の栄養画面）を添付 → 解析 → confirm に「<app名> から読み取り」ラベル + 合計 kcal/PFC が表示される
- 送信 → meal_records に `ai_source = 'screenshot:<app>'`、`estimated_by_ai = true` で保存される（DB 確認）
- free クライアントではセグメント切替が出ず従来フォームのままであること（回帰）

※ computer-use MCP 制約は `docs/tasks/lessons.md` 既知。対話操作不可の場合はビルド成功 + 起動 + Preview 目視 + analyze で代替し、対話 QA 未実施を正直に報告。

- [ ] **Step 12: ドキュメント更新**

`docs/tasks/IMPLEMENTATION_TASKS.md` のタスク 2.5 を完了にし、フェーズ2進捗・バージョン・最終更新日を更新。`docs/tasks/lessons.md` に学びを追記。

```bash
git add docs/tasks/IMPLEMENTATION_TASKS.md docs/tasks/lessons.md
git commit -m "docs: タスク2.5 スクショ取り込み完了を反映"
```

- [ ] **Step 13: リモート反映（ユーザー確認のうえ）**

QA 通過後、ユーザー確認を取ってから:
- `supabase db push`（リモートへ migration 反映）
- `supabase functions deploy estimate-meal-nutrition`
- `supabase functions deploy parse-message-tags`

- [ ] **Step 14: PR 作成**

```bash
git push -u origin feature/meal-screenshot-import
gh pr create --base develop/1.0.0 --title "feat: 食事アプリ スクショ取り込み（タスク2.5）" --body "<変更概要>"
```

---

## Self-Review（計画 vs 設計）

- **spec §2 Edge Function**: Task 2（input_kind 分岐・SCREENSHOT_SYSTEM_PROMPT・app_name 返却・screenshot 画像必須）でカバー ✓
- **spec §3.2 API クライアント**: Task 5（inputKind 引数）✓
- **spec §3.3 結果モデル**: Task 4（appName + build_runner）✓
- **spec §3.4 MealTagForm**: Task 6（_MealInputMode・セグメント・screenshot ボタン・_handleEstimate 分岐）✓
- **spec §3.5 confirm view**: Task 7（appName ラベル）✓
- **spec §3.6 chat_input source**: Task 8a（screenshot:<app>/photo/text）✓
- **spec §3.7 migration**: Task 1（ai_source）✓
- **spec §3.8 webhook**: Task 3（ai_source 保存）✓
- **spec §3.9 Web 型**: Task 8c ✓
- **spec §4 エラー/フォールバック**: 既存 `_humanError`/`MealEstimationErrorCode` を流用（EMPTY_RESULT は既存文言が画像前提で screenshot にも通用。必要なら Task 6 で screenshot 用文言調整可だが v1 は流用）✓
- **spec §5 テスト/QA**: Task 8b（Preview）+ Task 8d（analyze/QA）✓

**型整合チェック**: `appName`（model）→ `_estimation!.appName`（Task 6 Step 7）→ confirm view `appName`（Task 7）→ chat_input `estimation.appName`（Task 8a）で一貫。`inputKind`（Dart `estimate`）→ `input_kind`（Edge body）→ `inputKind`（callClaude）で一貫。`ai_source`（migration / webhook / Web 型 / metadata source）一貫。

**プレースホルダ scan**: なし（Web 型ファイルパスのみ grep 特定だが具体的手順を提示）。
