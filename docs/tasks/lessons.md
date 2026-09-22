# Lessons - 過去の失敗と学び

## 記録ルール

- バグを解決したら、ここにパターンと対策を追記する
- 設計上の判断ミスや整合性の注意点も記録する
- 同じ失敗を繰り返さないための知見をまとめる

## 日付比較のタイムゾーン問題

- **発生箇所**: GoalAchievementChart（目標達成率推移グラフ）
- **症状**: 体重進捗率が実際の記録と連動せず、古い値のまま固定される
- **原因**: `new Date(record.recorded_at)` と date-fns の interval（ローカルタイム）を直接比較すると、JST(UTC+9) のレコードが期間境界で正しく振り分けられない
- **対策**: Supabase の `recorded_at` をフィルタする際は `recorded_at.split('T')[0]` の文字列比較を使う（report/page.tsx と同じパターン）。`new Date()` 同士の比較は避ける

## SleepRecord 設計時の知見（タスク 1.3）

- **recorded_date は DATE 型 + String 表現**: Mobile側でも `String "YYYY-MM-DD"` で扱い、`DateTime` 比較は禁止。`jstDateKey()` ヘルパーで一貫処理
- **UPSERT 戦略**: 手動評価と HealthKit 客観データを混在させる場合、ペイロードに**含めないフィールドを保持する** UPSERT が必要。Supabase の `.upsert(... onConflict: '...')` で実現
- **Supabase Trigger関数名**: 既存トリガは `update_updated_at_column()`（`set_updated_at` ではない）。新規テーブルでも踏襲すること
- **Sleep カラーは AppColorsExtension に追加**: `sleepStageDeep/Light/Rem/Awake` をライト/ダーク両preset対応。`AppColors` 直定数より ThemeExtension パターン優先

## エラー状態のUX原則（タスク 1.3）

- カードの error state は **ヘッダー構造を保持**してカードらしさを残す（テキスト1行のみは視認性が低い）
- **リトライ導線**を必ず提供（該当 provider を `ref.invalidate()`）
- 関連: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart` `_ErrorBody`

## モノレポ移行（2026-04-26 完了）

- **背景**: Web (`fit-connect`) と Mobile (`fit-connect-mobile`) を独立リポジトリで運用していたが、同一 Supabase 共有・1セッションで両方を統括したい等の理由でモノレポ化
- **戦略**: `git subtree add --prefix=fit-connect-mobile mobile-origin develop/1.0.0`（フル履歴保持）→ Web側ファイルを `fit-connect/` サブディレクトリへ `git mv` → 親レベル CLAUDE.md/.claude/docs を統合 → main を develop で上書き force push
- **トラップ**:
  - **subtree 取り込み元は default branch を確認**: mobile は `main` ではなく `develop/1.0.0` が事実上の運用ブランチだった（main は古い）。Web も同様で main は Initial commit のみ、develop に122コミット
  - **Vercel の Production Branch と実際のデプロイ元の不一致**: Production Branch は main 設定だが、実際の本番 deploy は Mar 14 の develop スナップショット凍結（main へ push されてなかった）。移行を機にこの歪みを解消
  - **Default branch を別運用ブランチに変更してあると、リポジトリ整理時にそれが削除できない**: GitHub の default branch を main に切り替える操作が必要（develop 削除前）
  - **Supabase の `_remote_schema.sql` は完全スキーマダンプ**: 両プロジェクト両方にあるからといって両方を採用してはいけない（時系列で新しい方を採用、古い方は破棄）
- **意図せず混入したもの** (.gitignore 追加候補): `.superpowers/brainstorm/*/.server.pid` 系、`.claude/skills/*/scripts/__pycache__/*.pyc`
- **移行詳細手順書**: `docs/tasks/2026-04-26-monorepo-migration.md`
- **未完のフォローアップ**: `docs/tasks/2026-04-26-monorepo-migration-followups.md`

## バックグラウンド同期の戦略選定（タスク 1.4）

- **`workmanager` を見送った理由**:
  - iOS の `BGAppRefreshTask` / `BGProcessingTask` は OS が裁量で実行するため、最短でも数時間に1回・最悪は数日に1回しか起動しない（ヘルスケアの即時性とミスマッチ）
  - 両プラットフォーム共通の native 設定（`AppDelegate.swift` 修正、`MainActivity.kt` 修正、トップレベル callback の dispatch 制約）が必要で、リグレッション影響範囲が大きい
  - 体重・睡眠は1日1回〜数回程度しか変動しないため、フォアグラウンド復帰時の同期で十分鮮度を保てる
- **採用した戦略**: `Timer.periodic(60min)` + アプリ resume 時 `lastSyncAt > 1h` で再同期。両者とも `_AuthLoadingScreenState` に集約 (`lib/app.dart`)
- **冪等性の確保**: `_isResumeSyncing` フラグで resume 経路の二重起動を防止。`_sync()` 自体は SharedPreferences の status (idle/syncing/success/error) で進行中を可視化するが、Riverpod レベルの mutex は省略（同期内部処理は body の異常系 try/catch で完結する設計）
- **リトライポリシー**: `_runWithRetry()` で `_syncWeight` / `_syncSleep` 各々独立に最大3回（初回 + 2リトライ、1s/2s 指数バックオフ）。体重と睡眠の片方失敗でも他方は完了させ、`lastSyncAt` は両方成功時のみ更新
- **エラー通知**: `flutter_local_notifications` で固定 ID=9001（連続失敗時に通知トレイが膨張しない）、メッセージは120字で省略
- **iOS/Android 以外（macOS/Web）のガード**: `health_sync_provider` 側で `kIsWeb || (!iOS && !android)` を判定し `showSyncErrorNotification` をスキップ。サービス内部の二重ガードは省略

## AI Meal Estimation Stage 1（タスク 2.1 + 2.2、2026-05-03 完了）

### Supabase Database Webhook の payload に jsonb カラムが含まれない罠

- **症状**: `messages.metadata jsonb` を追加して Edge Function (`parse-message-tags`) でそれを参照しても、webhook payload では `metadata = undefined` になり meal_record が NULL PFC で作られた
- **原因**: Database Webhooks の column filter のデフォルト挙動が新規追加カラムを自動で含めない（プロジェクト初期化時の filter config がレガシー）
- **対策**: webhook handler 内で `record.id` を使って `messages` テーブルから `metadata` を **再フェッチ** する。webhook payload は trigger 通知だと割り切り、必要なフィールドは SELECT で取り直す方針で固定
- **関連**: `supabase/functions/parse-message-tags/index.ts`

### `supabase functions_client` は非 2xx で例外を throw する

- **症状**: Edge Function が 403 や 429 を返したとき、Mobile 側のエラーハンドリングが `network` エラーに collapse して原因が特定できなくなる
- **原因**: `functions_client 2.5.0` の `invoke()` は `Response { status, data }` を返すのではなく `FunctionException` を **throw** する。`response.status` チェックでは到達不能
- **対策**: `try { await client.functions.invoke(...) } on FunctionException catch (e) { /* e.status, e.details を読む */ }` パターンを使う。`e.details` に Edge Function 側で `JSON.stringify` した body が入っている
- **関連**: `lib/features/meal_records/data/meal_estimation_api.dart`

### Claude Haiku 4.5 が JSON をコードフェンスで包むことがある

- **症状**: `JSON.parse(response.content[0].text)` が `Unexpected token \`` で失敗する
- **原因**: モデルが ` ```json\n{...}\n``` ` 形式で返すケースがある（プロンプトで明示しても発生）
- **対策**: parse 前に `extractJson()` ヘルパーで先頭末尾の ` ``` ` / ` ```json ` を strip する。正規表現で `^```(?:json)?\s*\n?` と `\n?\s*```$` を順次除去
- **関連**: `supabase/functions/estimate-meal-nutrition/index.ts`

### Anthropic API は credit balance が 0 だと API キー有効でも 400 を返す

- **症状**: HTTP 400 `Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.`
- **対策**: Anthropic Console の Plans & Billing で **Auto Reload** を設定（残高が閾値を下回ったら自動課金）。本番運用では必須
- **副次**: workspace を分けるなら API キーも別ワークスペースで発行し、Supabase Secrets と紐付ける

### Riverpod AsyncValue ゲート系 UI のフラッシュ問題

- **症状**: `aiFeaturesEnabledProvider` (AsyncValue) で「pro なら AI 呼出 / free なら既存挙動」を分岐したい場合、未 resolve のまま loading フェーズに切り替えてしまうと free プランで一瞬だけ「AI推定中…」が出るフラッシュが発生する
- **試行錯誤**:
  1. ❌ 同期 `ref.read()` で `cached.hasValue && cached.value == false` 早期 return → provider が未 resolve だと素通りしてフラッシュ発生
  2. ❌ `initState` で `ref.read(provider)` 先行フェッチ → タップが速いと resolve 前に await 開始でフラッシュ発生
  3. ✅ **loading フェーズへの遷移は `aiEnabled == true` 確定後**にする。input フェーズのまま `await ref.read(provider.future)` で resolve を待ち、`true` のときだけ `setState(_phase = loading)`
- **教訓**: AsyncValue ゲートで分岐するときは、**ゲート結果が確定するまで UI 状態を変えない**。`AsyncValue.when` で UI を直接組むパターンが使えない場合（命令的フロー）も同じ原則を守る
- **関連**: `lib/features/messages/presentation/widgets/structured_tag_form.dart` `_handleInsert`

### Subscription gate を B2B2C で組むときの認証チェーン

- **背景**: クライアントには課金 UI を一切持たせず、トレーナーの `subscription_plan` を継承するモデル（FIT-CONNECT のビジネス要件）
- **チェーン**: `auth.uid()` → `clients.user_id` → `clients.trainer_id` → `trainers.subscription_plan`
- **RLS の罠**: クライアントが自分のトレーナーの subscription_plan を SELECT できる必要がある。FIT-CONNECT の `trainers_select_all USING (true)` ポリシーがすでにこれを許可していたので追加対応不要だったが、新規プロジェクトでは要注意
- **関連**: `lib/features/subscription/providers/ai_features_enabled_provider.dart`

### Anthropic 構造化出力の totals 不整合

- **症状**: Claude に `foods[]` と `totals` を同時に返させると、`totals.calories` が `sum(foods[].calories)` と一致しないケースがある（モデルの算術ミス）
- **対策**: validator で `foods` から totals を **再計算して上書き**。Claude の totals は捨てる（食品レベルの推定だけ信用する）
- **関連**: `supabase/functions/estimate-meal-nutrition/index.ts`

### 残タスク（フェーズ 2 続き）

- **Stage 4**: 食事アプリスクショ画像分析（タスク 2.5）
- **2.4 任意項目（バックログ）**: 手入力 #食事 送信の自動推定 / 推定履歴・精度フィードバックUI
- **インフラ**: Stripe 連携で `trainers.subscription_plan` を自動更新（フェーズ 7 想定）

## 「AI推定」ボタンの明示化と責務分離（タスク 2.4(a)、2026-05-31 完了）

### 「食事記録画面への追加」が実は別物だった — 既存アーキテクチャ確認の重要性

- **背景**: タスク定義は「食事記録画面への『AI推定』ボタン追加」だったが、調査の結果 `MealRecordScreen` は**閲覧専用**で入力導線が一切なく（`meal_records_provider` の `addRecord`/`updateRecord` はUI未配線）、食事記録の作成は**メッセージ #食事 タグ経由のみ**だった
- **判断**: 記録画面に直接入力UIを新設すると「食事記録はトレーナーとのメッセージ経由で作る」というプロダクトモデルを変えてしまう。ユーザー確認の上、**記録画面は閲覧専用のまま維持し、AI推定をメッセージ #食事 タグフォーム内の明示ボタンとして分離**する最小スコープに決定
- **教訓**: タスク文言を額面どおり受け取らず、まず既存フローを調査してから方針を確定する。「画面に〇〇を追加」が、その画面に前提機能が無いために実質「新機能の新設」になるケースがある

### 暗黙分岐ボタンの責務分離

- **症状になりかけた設計**: 「挿入」1ボタンが、Pro+入力ありの時だけ暗黙でAI推定→確認に分岐していた（押すまで挙動が読めない）
- **対策**: `_handleInsert`（暗黙分岐, async）を `_handleInsert`（テキスト挿入のみ, 同期）と `_handleEstimate`（AI専用, async）に分割。UIも Pro では「AI推定」主＋「AIなしで挿入」副の2ボタンに分離。「ボタン＝1つの明確な動作」に
- **フラッシュ対策**: ボタン構成を `ref.watch(aiFeaturesEnabledProvider).maybeWhen(data: e=>e, orElse: ()=>false)` で出し分け、**未解決時は保守的に free 版を表示**。既存「AsyncValueゲートは結果確定までUIを変えない」原則の踏襲
- **関連**: `lib/features/messages/presentation/widgets/structured_tag_form.dart`

### ios-simulator-qa スキルの制約（このセッションでの実情）

- **症状**: `ios-simulator-qa` スキルは `mcp__computer-use__*` ツール前提だが、当セッションには computer-use MCP が未登録（利用可能MCPは supabase / Google系のみ）、`idb` も未インストール。→ **シミュレータへのタップ/入力の自動操作が不可**。加えてアプリ未ログイン（認証情報は手入力依頼が必要）
- **代替で確保した検証**: `fvm flutter run` での**ビルド成功 + アプリ起動成功**、`fvm flutter analyze`（対象ファイル No issues）、`xcrun simctl io <udid> screenshot` での画面キャプチャ確認。対話的UI検証（ボタン表示・無効化・推定フロー）は未実施として正直に区別して報告
- **補完策**: UI変更時はプレビュー関数（`@Preview`）を必ず追加し、provider依存UIは override で状態を再現（`previewMealTagFormPro` で `aiFeaturesEnabledProvider.overrideWith((ref) async => true)`）。`flutter widget-preview` で視覚確認の手段を残す
- **スキル内の旧パス**: skill本文のプロジェクトルートが旧構成 `/Users/hoshidayuuya/Documents/FIT-CONNECT/...` のまま。実際は `/Users/hosidayuya/Documents/work/fit-connect/fit-connect-mobile`、Flutter は fvm 3.41.9 pinned。スキル更新候補

## 食事アプリ スクショ取り込み（タスク 2.5、2026-05-31 完了）

### 既存の画像推定インフラを「OCR的読み取り」に転用 — プロンプトだけ分岐

- **方針**: 料理写真推定（2.3）とスクショ読み取りは、画像をURLで Claude Vision に渡す配管が**完全に同一**。違いは「推定する」vs「画面の数値を読み取る」というタスク性質だけ。→ Edge Function に `input_kind='screenshot'` を足し、**システムプロンプトのみ分岐**（`SCREENSHOT_SYSTEM_PROMPT`）。モデル（sonnet）・サブスクゲート・レートリミット・アップロード・confirm UI・webhook はすべて流用
- **教訓**: 新機能でも「データフローのどこが本当に違うのか」を見極めると、差分を1点（プロンプト）に閉じ込められる。配管を再発明しない

### `source` カラムの CHECK 制約に既存意味があり流用不可 → 新カラム

- **罠**: `meal_records.source` は `manual`/`message`（記録の**作成経路**）の CHECK 制約付き。AI推定の**入力経路**（text/photo/screenshot）を入れたくなるが、意味が違ううえ制約に弾かれる
- **対策**: 新カラム `ai_source text`（CHECK なし、`screenshot:<可変app名>` を許容）。`metadata.meal_estimation.source` は従来 webhook で読み捨てていたので、ここで初めて永続化。`vision`→`photo` に改称し意味を明確化（過去データ未保存のため安全）

### 確認画面で totals を再構築すると `appName` が落ちる（計画の見落としを実装者が検出）

- **症状**: confirm 画面はユーザーが合計値を編集できるため、送信時に `MealEstimationResult(foods:..., totals: _editableTotals!)` を**作り直す**。ここで `appName` を渡し忘れると、chat_input 側の `estimation.appName` が常に null になり `source` が `screenshot:<app>` にならず機能が無効化される
- **対策**: 再構築時に `appName: _estimation!.appName` を明示的に引き継ぐ。**「オブジェクトを部分的に作り直す箇所」は新フィールド追加時の漏れポイント** — copyWith が無いモデルは特に注意
- **関連**: `structured_tag_form.dart` `_handleSendWithEstimation`

### Pro 限定UIは AsyncValue ゲートで保守的に出し分け（2.4(a) の踏襲）

- スクショ取込モードのセグメント切替は `aiFeaturesEnabledProvider.maybeWhen(data: e=>e, orElse: ()=>false)` で**未解決時は非表示**。さらに `_handleEstimate` 内で再確認、`_buildPreviewActions` の `!aiEnabled` 早期 return で三重に防御。free ユーザーに screenshot UI が一瞬も漏れない

### サブプロジェクト固有エージェントは親レベルから呼べない

- **症状**: `flutter-ui` / `riverpod`（`fit-connect-mobile/.claude/agents/`）は**親ディレクトリの Agent ツールからは未登録**でエラー。利用可能なのは `general-purpose` / `explore` / `supabase` / `plan` 等のみ
- **対策**: Mobile 実装の委託は `general-purpose` に、fvm/Flutter 制約（`fvm flutter` 必須・3.41.9 pinned・lucide_icons）をプロンプトで明示して渡す

### Edge Function は deno 未導入環境で構文検証できない

- ローカルに deno が無く `deno check` 不可。`// @ts-nocheck` 付きのため型検証も限定的。→ **デプロイ前に deno check を通すこと**を必須化（QA/デプロイ手順に明記）。実装中はコード全行の目視確認で代替

### スクショ推定では totals の「foods 再計算」が画面の合計PFCを潰す（2026-06-01 修正）

- **症状**: PFC が写ったスクショを渡しても `meal_records` の protein_g/fat_g/carbs_g が常に 0。calories は入る
- **原因**: `validateEstimation` が **totals を foods（食品ごと）から再計算**する設計（料理写真ルート用の「Claude の totals 不整合への防御」）。あすけん等の食事リスト画面は **food 単位の PFC を出さない**（PFC は画面上部の合計バー/数値）。モデルは food 配列の PFC を 0 で返し、合計を再計算すると画面の合計PFCも 0 に潰れる
- **対策**: `validateEstimation(raw, trustTotals)` を追加。`input_kind='screenshot'` のときは **totals をモデル値（画面の合計）採用**（clamp のみ）、photo/text は従来どおり再計算。あわせてプロンプトで「合計 P/F/C のグラムを必ず totals に入れる／totals を 0 のままにしない」を明示
- **教訓**: 「読み取り（OCR的）」タスクと「推定」タスクで totals の信頼源が逆（前者=画面の合計が真、後者=食品ごとの推定の合計が真）。同じ関数を流用するなら入力種別で分岐する
- **副次**: PFC が画面に無いスクショ（カロリー/食品だけ）は 0 のまま正しく返る（捏造しない）。UI 側で「PFCが写ったスクショを添付すると精度が上がる」ヒントを出して運用で補う

### 複数スクショの整合性は Claude に判定させ非ブロッキング警告（2026-06-01）

- **要件**: PFCの画面と食べ物の画面を別々に添付したとき、それらが噛み合わない（別の食事/別日）と「組み合わせ正しい？」と警告したい
- **実装**: スクショは元々まとめて1リクエストで Claude に渡すので、レスポンスに `warning: string|null` を追加。プロンプトで「2枚以上のとき同じ食事か・`P×4+F×9+C×4 ≒ kcal` が噛み合うかを見て、不整合なら短い指摘文、問題なければ null、1枚なら常に null」と指示。確認画面に**非ブロッキングの警告バナー**（アンバー、送信は可能）
- **設計判断**: per-image の構造化出力は作らず、合算結果＋Claude の総合判定だけで足りる（YAGNI）。warning は送信前の助言なので DB 保存しない

## lucide_icons が新Flutter(IconData final化)でビルド不可（2026-05-31）

- **症状**: `flutter run`(iOS) が `lucide_icons-0.257.0/lib/src/icon_data.dart:3: Error: The class 'IconData' can't be extended outside of its library because it's a final class.` で失敗。Xcodeログ末尾は `keyWindow` deprecated 等の警告ばかりで真因が埋もれる。`flutter build ios --debug --simulator 2>&1 | grep -i "error:"` で抽出するのが速い
- **原因**: Flutter 3.44.0 で `IconData` が `final class` 化。`lucide_icons` は `class LucideIconData extends IconData` で継承しており継承不可に。`lucide_icons` は pubspec が `sdk: ">=2.12.0 <3.0.0"`（Dart2系）で実質メンテ終了、最新 0.257.0 でも修正なし。アプリ側は50ファイル・81種を `LucideIcons.xxx` で使用中
- **対策（採用）**: ローカル vendor + パッチ。`fit-connect-mobile/third_party/lucide_icons/` にコピーし、(1) 自動生成 `lib/lucide_icons.dart` の `const LucideIconData(0xYYYY)` を `IconData(0xYYYY, fontFamily: 'Lucide', fontPackage: 'lucide_icons')` に一括 sed 置換、(2) 壊れた `lib/src/icon_data.dart` を空(コメントのみ)化＋import削除、(3) vendor pubspec の sdk を `<4.0.0` に緩和、(4) アプリ pubspec に `dependency_overrides: lucide_icons: { path: third_party/lucide_icons }`。アプリ50ファイルは無変更で `LucideIcons.xxx` API 互換のままビルド成功(EXIT 0)
- **トレードオフ/今後**: 放置気味パッケージを vendor として抱えた状態。長期的には active な後継 `lucide_icons_flutter`(^3.x) 移行が本筋（アイコン名差異の照合が必要なため今回見送り）
- **横展開**: Flutter SDK 更新時、`IconData`/`Color` 等を `extends` する古いパッケージは同様に壊れる。`flutter upgrade` を安易に勧めない方針とも整合
- **再発モード（2026-06-19, 別マシン継続時に再発）**: vendor パッチ自体は健全（`third_party/lucide_icons/lib/lucide_icons.dart` は `IconData(...)` 直書き、壊れた `src/icon_data.dart` は未 import の死にコード）でも、**`pubspec.lock` が `source: path` → `source: hosted`（pub.dev 0.257.0）に巻き戻る**と、ビルドが `.pub-cache` の壊れた本家版を読みに行き同じ `IconData can't be extended` で失敗する。`pubspec.yaml` の `dependency_overrides: lucide_icons: { path: ... }` は無傷なので、**`flutter pub get` で lock を `source: path` に再生成**すれば解消（`git diff pubspec.lock` で hosted への巻き戻りを確認できる）。別マシンへの環境移動・`flutter pub upgrade`・マージ後はこの lock 巻き戻りを最初に疑う。※このマシンは `flutter` 3.44.0 直（fvm ではない）

## develop の生成物 (package-lock.json / .g.dart) が feature ブランチへ漏れ出す（2026-06-28）

- **症状**: `feature/*` で作業中、`git status` に `fit-connect/package-lock.json` や Mobile の `*.g.dart`（Riverpod 生成物）が変更として出る。中身は develop 側で、`package.json` は feature のまま（例: `vitest` 未導入）なのに `package-lock.json` の `root.devDependencies` だけ `vitest` を含む、という **package.json と lock の不整合**になる。上の pubspec.lock 巻き戻りと同じ「生成物のブランチ間漏れ」族
- **原因**: `develop/<version>` ⇄ `feature/*` のブランチ往復後に `npm install` / `build_runner` を流す、または別マシン・別セッションで develop をチェックアウトした生成物が working tree に残るため。コードの意図的変更ではなくツール再実行・ブランチ往復の副産物。`vitest` は develop/1.0.0 の PR #55（サマリータブ再編, c1b52b2 / 3dbc794）で導入され、現 feature ブランチには未取り込みだった
- **診断**: 生成物・lock の差分を「npm install の結果」と即断しない。`git diff --numstat origin/develop/<version>:<path> -- <path>` で develop と完全一致しないか確認（完全一致＝漏れ出し）。`git log -S <pkg>` で依存追加コミットが出ても `git merge-base --is-ancestor <commit> HEAD` で現ブランチの先祖か必ず確認する
- **対処**: 漏れ出しと判断したら `git restore <files>` で破棄してからコミットする
- **横展開**: pubspec.lock と同根。生成物・ロックファイルはブランチ往復で漏れるものとして、コミット前に develop との差分を必ず確認する

## Supabase Auth の Custom SMTP 導入（Resend）でハマった4点（2026-08-13）

- **背景**: モバイルのログインが `over_email_send_rate_limit` (429) で失敗。Supabase 組み込みメールは全無料プロジェクト共有で **1時間2通**、ダッシュボードから引き上げ不可。制限は**プロジェクト単位**なので `user+1@gmail.com` のエイリアス変更では回避できない。Resend を Custom SMTP として接続し `noreply@fit-connect.app` から送る構成に変更した
- **落とし穴1: DNS を入れただけでは Resend は Verified にならない**。4レコード（MX/SPF/DKIM/DMARC）が `dig` で正しく引けていても、Resend の Domains 画面で **Verify を明示実行**するまで未検証のまま。この状態で送信すると Resend が SMTP レベルで `550 The domain is not verified` を返し、アプリには `500 unexpected_failure / Error sending confirmation email` として届く。**未検証は API キー作成画面の Domain ドロップダウンにドメインが出ないことでも判別できる**（この兆候を見逃して500まで進めてしまった）
- **落とし穴2: `signInWithOtp` はユーザーの新旧でテンプレートが変わる**。auth_logs の `mail_type` が既存ユーザー = `magic_link`、**新規ユーザー = `confirmation`**。Magic Link だけ日本語化すると、最も重要な新規オンボーディング導線だけ英語のデフォルトメールが届く。**両方（`magic_link.html` / `confirmation.html`）を用意すること**
- **落とし穴3: Custom SMTP を有効化しても上限は解放されない**。デフォルトが 2通/時 → **30通/時 に変わるだけ**。Authentication → Rate Limits で別途引き上げが必要（100通/時に設定。Resend 無料枠が 100通/日 なのでそれ以上は無意味）
- **落とし穴4: Email OTP expiration のデフォルト 86400 秒（24時間）はセキュリティ警告対象**。`get_advisors` の `auth_otp_long_expiry` が「1時間未満を推奨」と検出する。3600 に変更して解消。**メール本文に有効期限を書くならこの値と必ず突き合わせること**（テンプレートに「1時間」と書きながら実態24時間だと嘘になる）
- **診断の教訓**: SMTP 障害は **auth_logs に Resend からの生の SMTP エラーがそのまま入る**。`query_logs` で `source='auth_logs'` を引けば一発で原因が出るので、設定を推測でいじらない
- **クリック追跡は必ずオフ**: 有効だとリンクが追跡URLに書き換えられ、企業のメールセキュリティスキャナの事前アクセスでマジックリンクのワンタイムトークンが消費される。Resend では Tracking Subdomain 空欄で無効のまま
- **設計書**: `docs/superpowers/specs/2026-08-10-supabase-custom-smtp-design.md`（手順・DNS値・ロールバック手順）

## GoogleService-Info.plist が Xcode 未登録で Firebase が初期化されない（2026-08-15）

- **症状**: 実機で通知を ON にしても「設定できませんでした」。起動ログに `⚠️ Firebase/通知初期化エラー: [core/not-initialized]`、以降すべての Firebase 呼び出しが `[core/no-app] No Firebase App '[DEFAULT]' has been created`。FCM トークンが取れず `device_tokens` に登録されない
- **原因**: `ios/Runner/GoogleService-Info.plist` は**ディスク上に存在し git 管理下にもあり BUNDLE_ID も正しい**が、`Runner.xcodeproj/project.pbxproj` に **PBXFileReference も Copy Bundle Resources 登録も一切無い**。よって `.app` に同梱されず、引数無しの `Firebase.initializeApp()`（バンドル内 plist を読む）が失敗する。`develop/1.0.0` を含む全ブランチで同じ状態だった
- **診断**: 「plist があるか」ではなく **`grep -c "GoogleService-Info" ios/Runner.xcodeproj/project.pbxproj`** で登録有無を見る。0 なら未同梱
- **対策（採用）**: `lib/firebase_options.dart` を追加し `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` に変更。バンドル同梱に依存しなくなる。`firebase`/`flutterfire` CLI 未インストール＋ブラウザログインが必要だったため、CLI 生成物と同じ構造・同じ値を `GoogleService-Info.plist` と `android/app/google-services.json` から手書きした
- **二次障害（重要）**: 修正して初めて `NotificationService.initialize()` が実際に走るようになった結果、内部の `getInitialMessage()` が APNs トークン到着を待って解決せず、`await` していた `main()` が `runApp()` に到達せず **iOS シミュレータで画面が真っ白**になった。修正前は `Firebase.initializeApp()` が即例外で `initialize()` 自体が動かず露見していなかった
- **対策2**: `unawaited(NotificationService.initialize())` に変更。リスナー登録のみで初回フレームに必要な処理は無く、例外は `initialize()` 内で捕捉済み。起動描画をプッシュ通知初期化に依存させない
- **教訓**: 「初期化が例外で握り潰されている」バグを直すと、それまで実行されていなかった後続コードが初めて走る。**修正後は必ず起動〜描画まで通しで確認する**（ログの成功行だけでなくスクリーンショットまで）
- **三次障害（実機）**: Firebase が初期化されるようになった実機で、今度は `[firebase_messaging/apns-token-not-set]` が発生し `device_tokens` の行が 0 件のまま。UI は「通知を設定できました」と表示していた
- **原因3**: iOS の `getToken()` は APNs トークンが FIRMessaging にセットされている必要がある。`requestPermissionAndRegister()` が `requestPermission()` 直後に `saveTokenToSupabase()` → `getToken()` を呼ぶため、APNs 登録の往復完了前に叩いて失敗していた
- **対策3**: `_waitForApnsToken()`（iOS のみ、`getAPNSToken()` を最大15秒ポーリング）を追加し、`getToken()` の全呼び出し前に挟む。あわせて `saveTokenToSupabase` を `Future<bool>` 化し、`requestPermissionAndRegister` はその結果を返す（登録できていないのに「設定できました」と出さないため）。`app.dart` の `[App] FCMトークン保存完了` も成否で出し分け
- **教訓2**: **成功ログを信用しない。** `.then((_) => print('完了'))` は、内部で例外を握り潰した失敗時にも「完了」を出す。非同期処理の成否は戻り値で表現し、ログとUIメッセージはその戻り値に従わせる
- **検証の限界**: iOS シミュレータは APNs トークンを取得できないため、FCM トークン登録は**実機でしか検証できない**。シミュレータで確認できるのは Firebase 初期化と起動描画まで。最終確認は `device_tokens` の行数を SQL で直接見る
- ~~**未解決**: `develop/1.0.0` と `feature/auth-custom-smtp` の `Runner.entitlements` に `aps-environment` が無い~~ → PR #78（本ブランチ）のマージで develop にも entitlement が入り解消

## 実機で APNs トークンが届かない問題の最終解決（2026-08-29）

- **真因（2段構え）**: ① firebase_messaging 15.2.10 は UIScene + `FlutterImplicitEngineDelegate` 方式のプラグイン登録に未対応で、`UIApplicationDidFinishLaunchingNotification` observer が発火せず `registerForRemoteNotifications` が一度も呼ばれない（flutter/flutter#185048）。② 16.5.0 へ上げても、scene 接続時のセットアップ末尾が `[FIRMessaging messaging].isAutoInitEnabled` でガードされており、Firebase を Dart 側で初期化する本アプリでは scene 接続時点で FIRMessaging が nil → ObjC の nil メッセージングで偽 → 登録スキップ。`didReinitializeFirebaseCore` も空実装で再登録されない
- **修正**: (a) firebase_messaging ^16.5.0 / firebase_core ^4.13.0 へアップグレード（iOS 最低バージョン 13.0→15.0、Firebase iOS SDK 12.17.0）。(b) `NotificationService.initialize()` 先頭で `setAutoInitEnabled(true)` を毎起動呼ぶ — ネイティブハンドラが `registerForRemoteNotifications` + `ensureAPNSTokenSetting` を発火させる公式 API 経路（プラグイン実装 messagingSetAutoInitEnabled 参照）
- **検証**: 実機 YH で FCM トークン取得 → `device_tokens`（ios/client）と `clients.fcm_token` に同一トークンが保存されたことを SQL で実測確認
- **教訓**: プラグインの「自動でやってくれるはず」の初期化は、アプリのライフサイクル構成（UIScene / 新旧 AppDelegate 方式 / Dart側Firebase初期化）次第で丸ごとスキップされうる。ネイティブの前提条件（誰がいつ registerForRemoteNotifications を呼ぶか）をソースで確認する
- **副次観察**: 起動時に `morningDialogProvider ... disposed during loading` の未処理例外がログに出る（非致命・別件）

## Storage private化（フェーズ8.2、2026-08-30）で踏んだ罠

### storage.objects ポリシーのサブクエリ内で無修飾 `name` が内側テーブルに解決される（実バグ・RLSテストが検出）

- **症状**: `message_photos_select_participants` の「担当トレーナー閲覧」「クライアントがWebフォルダ閲覧」分岐が一切マッチせず、本人の自フォルダ以外が見えない
- **原因**: ポリシー式の `EXISTS (SELECT 1 FROM public.clients c WHERE … (storage.foldername(name))[1] …)` で、無修飾の `name` が**外側の storage.objects.name ではなく clients.name に解決**される（SQLのスコープ規則どおり。`pg_get_expr` で確認すると `storage.foldername(c.name)` になっていた）。カタログ 2026-07-08 の下書きSQLにも同じ潜在バグがある
- **対策**: サブクエリ内では必ず `objects.name` と修飾する。**RLS ポリシーは書いたら必ず `pg_get_expr(polqual, polrelid)` で実際の解決結果を目視**し、supabase/tests/ の実クエリテストを通す（構文パーサ検証では検出不能）
- **関連**: `supabase/migrations/20260829000000_storage_private_and_policies.sql` / `supabase/tests/storage_policies_rls_test.sql`

### React hooks 入り共有モジュールをサーバー(API Route)から import すると next build だけが落ちる

- **症状**: `tsc --noEmit` / vitest / lint は全て通るのに `next build` が「You're importing a component that needs useState」で失敗
- **原因**: 純関数（パス抽出）と `useStorageUrl` フックを1ファイル（storagePaths.ts）に同居させ、純関数を API Route から import したため、サーバーバンドルに react hooks が混入
- **対策**: サーバーからも使う純関数と、クライアント専用（フック・ブラウザクライアント依存）を**最初からファイル分離**する（storagePaths.ts = 純関数 / signedStorageUrls.ts = 'use client'）。**tsc/vitest が通っても next build までがWebの検証セット**
- **横展開**: 「Web/Mobile共通セマンティクスのヘルパー」を作るときは、Web側は server/client 境界も設計に含める

### CocoaPods は非対話シェルで LANG 未設定だと Encoding::CompatibilityError で落ちる

- **症状**: `pod install --repo-update` が `Unicode Normalization not appropriate for ASCII-8BIT` で失敗（エラーの手前に「terminal encoding UTF-8にせよ」の警告）
- **対策**: `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install …` で実行。新プラグイン追加（今回 package_info_plus）で pod の specs 更新が要る時は `--repo-update` も付ける

### その他（このセッションの環境メモ）

- `supabase start` を Docker Desktop 起動直後に走らせるとハングすることがある（CPU時間ほぼゼロで待ち続ける）。kill → 再実行で正常にイメージ pull が始まる
- 旧モノレポ移行前の `supabase_*_fit-connect-mobile` コンテナが Docker 再起動で自動復活しポートを塞ぐ。`docker stop $(docker ps -q --filter name=fit-connect-mobile)` で停止してから `supabase start`
- claude-in-chrome の接続先 Chrome が**別デバイス**のことがある（localhost:3000 が ERR で LAN IP `http://192.168.1.15:3000` なら届く、が判別サイン）。ただし別オリジンには auth セッションが無い点に注意
- normalize 系のデータ migration は「リモート実測 → 変換regexのシミュレーション → ローカル db reset → リモート push 後の残存件数SQL検証」の順で安全に適用できた（今回: http残存 0 件・外部URL 2 件保全を実測確認）

## セッション表示とカルテ連携（フェーズ8.3①、2026-09-06〜10）で得た知見

### カタログの RLS ポリシー案は実スキーマで裏取りしてから使う

- **症状になりかけた**: `2026-07-08-solution-catalog.md` cat4 課題2 の案 `client_id IN (SELECT id FROM clients WHERE client_id = auth.uid())` は、`clients` に `id` 列が無く（PK は `client_id` で auth.uid() と同一）実行時エラーになる
- **対策**: 既存の同種ポリシー（`weight_records` / `sleep_records` の顧客用は `client_id = auth.uid()`）と `\d` の実スキーマで確認してから書く。カタログは設計意図の参考であって SQL の正本ではない

### RLS テストの anon ケースは「クレーム付き anon」も入れないと偽陰性になる

- **症状**: `sessions_client_select`（`TO authenticated`）のテストで、anon ケースを「JWT クレームを空にしてから `SET LOCAL ROLE anon`」で書くと `auth.uid()` が NULL になるだけで 0 行になり、**ポリシーから `TO authenticated` を外してもテストが通る**
- **対策**: anon ケースは (d-1) クレーム無し と (d-2) **顧客 UUID のクレームを入れたまま anon に切替** の2本立てにし、(d-2) が role 限定を直接検証する。修正後に実際に role 限定を外して (d-2) だけ FAIL することを確認（負のコントロール）
- **副次の罠**: `SET LOCAL request.jwt.claims` はトランザクション内に残るため、先行ケースのクレームを消さずに anon へ切り替えると `TO PUBLIC` の既存ポリシーが通ってしまう

### 導出値を非正規化して保存すると必ずドリフトする

- **症状**: 「何回目のセッションか」を対象セッション集合から算出して `client_notes.session_number` に自動保存する設計にしたところ、過去セッションを後からキャンセルすると以降の番号が繰り上がり、保存済みカルテの番号と衝突しうる（レビューで CONFIRMED）
- **判断**: 参照は `session_id` に一本化し、番号は**列ごと廃止**して表示は `sessions.session_date` から導出（オーナー判断: 「番号は何のために入れていたか分からない。日付が目立てばよい」）
- **教訓**: 「自動で入る値」を DB に書くなら、その値が後から変わらないことを保証できる場合に限る。導出できるものは保存せず表示時に導出する

### 選択肢の非同期取得と「意図した紐づけ」は別に扱う

- **症状**: 「カルテを書く」でカルテ作成を開いたのに、対象セッションの選択肢取得が失敗・未完了だと `session_id = null` のまま無言で保存され、紐づけ忘れ防止という機能の目的が黙って無効化された
- **対策**: (1) 装飾用データ（「カルテ作成済み」ラベル用の別クエリ）の失敗で選択肢本体を落とさない (2) 取得中・失敗を UI に出す (3) `initialSessionId` を指定して開いたのに反映できていない間は保存をブロック。「意図した紐づけが落ちたまま保存できない」を要件として明文化する

### 2箇所から同じ状態遷移を起こすなら UPDATE 自体に条件を付ける

- **症状**: セッション完了（＋チケット消化）をスケジュール画面とワークアウト実施画面の両方から起こせるようにした際、「読んでから書く」ガードだと同時実行でチケットを二重消化しうる
- **対策**: `update({status:'completed'}).eq('id', id).neq('status','completed').select().maybeSingle()` のように**未完了の行だけを更新する条件付き UPDATE** にし、行が返ったときだけ消化へ進む。DB 側で必ず片方しか通らないので、アプリ側の読み取りタイミングに依存しない

### 固定の明色背景にテーマ追従の文字色を載せるとダークモードで消える

- **症状**: カルテ詳細ヘッダー（`AppColors.primary50` 固定背景 + `colors.textPrimary`）がダークモードで白文字が淡青に溶けて読めない。全画面を洗い出すと既存コードにも同型が4箇所（同意ダイアログの AI 枠、ログインのメール送信カード、ヘルスケア同期エラー行、週間ミニカレンダーの完了セル）
- **対策**: 背景を `AppColorsExtension` のテーマ追従トークンにする（`primaryTint` = light primary50 / dark blue900、`primaryTintForeground` = light primary600 / dark primary200 を追加。既存 `accentIndigo` と同じ流儀で fields / constructor / light / dark / copyWith / lerp の6箇所に漏れなく）。**背景と文字のどちらか片方だけテーマ追従**にしない。`@Preview` にダークモード版を並べて目視できるようにする
- **追補（2026-09-12, feature/dark-mode-tint-fixes）**: 残り4箇所（同意ダイアログ AI 枠 / ログインのメール送信カード / ヘルスケア同期エラー行 / 週間ミニカレンダー完了セル）+ MealSummaryCard を修正。緑系・赤系にも同じ流儀で `successTint`（light emerald50 / dark emerald900）・`dangerTint`（light rose100 / dark rose900）を追加。固定の `AppColors.emerald50` / `rose100` は「文字も固定色」の箇所（ステータスバッジ等）が使うので残す
- **枠線も忘れない**: 背景だけテーマ追従にしても、固定の `*100` 枠線（emerald100 / primary100）がダークでは白っぽいリングとして残る。枠線は半透明アクセントオーバーレイ（`AppColors.success.withValues(alpha: 0.3)` 等。既存の `error.withValues(alpha: 0.3)` と同じ）にして両背景に馴染ませる。プレビュー不可の画面（Supabase.instance に触る LoginScreen 等）はカードを別 Widget に切り出して `@Preview` とテストを付ける
- 残り4箇所は別タスク化済み（2026-09-08）


### Edge Function の認証を `SUPABASE_SERVICE_ROLE_KEY` との文字列一致で書くと本番で通らない（2026-09-12）

- **症状**: cron（pg_net）から Vault の旧 service_role キーを `Authorization: Bearer` で送ると、`auto-skip-workouts` が本番だけ 401。Vault のキーはプロジェクト作成時の正規 JWT（role=service_role・ref一致・前後空白なし）で、ローカルでは通っていた。`cleanup-ai-images` も同じ書き方で同様に通らない状態だった
- **原因**: 関数が `authHeader === \`Bearer ${SUPABASE_SERVICE_ROLE_KEY}\`` の文字列一致で判定しており、新 API キー（publishable/secret）を作成済みの本番プロジェクトでは関数に入っている値が Dashboard の旧キーと一致しなかった
- **対策**: Supabase 公式の新キー移行ガイドどおり、cron / pg_net は新 secret キーを **`apikey` ヘッダー**で送り（Bearer で送ると JWT として弾かれる）、関数は `verify_jwt = false` にして `SUPABASE_SECRET_KEYS` と照合する（`_shared/service_auth.ts`）
- **教訓**: サーバー間呼び出しの認証は**本番で実際に一度呼んで確かめるまで**動くと思わない。副作用のない `dry_run` を関数に持たせておくと、cron 有効化前に本番で安全に通しテストできる（今回それで有効化前に発見できた）

## セッション前日リマインダー（フェーズ8.3②、2026-09-12）で得た知見

### JST の「暦日」判定は範囲比較で書く（索引と正しさの両方のため）

- `(session_date AT TIME ZONE 'Asia/Tokyo')::date = target_date` は正しいが `idx_sessions_session_date` が効かない。`session_date >= target_date::timestamp AT TIME ZONE 'Asia/Tokyo' AND session_date < (target_date + 1)::timestamp AT TIME ZONE 'Asia/Tokyo'` の範囲比較にする（EXPLAIN で Bitmap Index Scan を確認）
- `CURRENT_DATE` や Edge 側の `toISOString().split('T')[0]` は UTC 日付なので、JST 0:00〜8:59 のセッションを「前日」に誤分類する。**UTC 日付で判定すると壊れる時刻（JST 0:30 = UTC 前日 15:30）を SQL テストの境界ケースに必ず入れる**。誤実装に差し替えてテストが落ちること（判別力）まで確認した
- 関連: `supabase/migrations/20260913000000_session_reminder.sql` / `supabase/tests/session_reminder_test.sql`

### 通知の dedup_key には「いつの通知か」を含める

- `notification_logs.dedup_key` は UNIQUE で、設定 OFF や quiet hours で skip した場合も行が残るため**同一キーの再送は永久に不可**。セッション ID だけをキーにすると別日へリスケされても再送されない
- `session_reminder:<session_id>:<対象日>` のように対象日を含め、「別日へのリスケは再送・同日内の時刻変更は再送しない」を仕様として明文化した

### push を伴う cron 起動 Function は dry_run 省略時に送らない

- 既存は `auto-skip-workouts`（省略時=実行）と `cleanup-ai-images`（省略時=dry run）で既定が不統一だった。実顧客に通知が飛ぶ関数は**省略時 dry run**にし、cron の body で `{"dry_run": false}` を明示する。手動実行・検証時の事故を防げる

### 通知種別の追加は4箇所を同時に

- `push.ts` の kind ユニオン / `notification_preferences.kind` の CHECK 制約 / Mobile の `NotificationKind` enum（+State・switch）/ Web の種別一覧（トレーナー宛なら）。**CHECK 拡張 migration を先にリモート適用しないと、Mobile のトグル保存が check_violation で失敗する**

## SECURITY DEFINER 関数の権限是正（フェーズ5.6、2026-09-13）で得た知見

### 関数の EXECUTE は「anon から剥がす」だけでは閉じない
- PostgreSQL は関数作成時に **PUBLIC へ EXECUTE を既定で付ける**。加えて Supabase のプラットフォーム既定（postgres が public に作る関数への default privileges）で anon / authenticated / service_role にも付く（20251230131753 はそれを記録しただけで、fresh DB では同じ `ALTER DEFAULT PRIVILEGES` で再現される）。anon は PUBLIC のメンバーなので、`REVOKE ... FROM anon` だけでは PUBLIC 経由で実行できてしまう。**SECURITY DEFINER 関数を作ったら `REVOKE ALL ... FROM PUBLIC` と `FROM anon` を必ずセットで書く**
- `CREATE OR REPLACE FUNCTION` は既存の ACL を保持する。REVOKE を書かない限り、関数を作り直しても権限は1ミリも変わらない
- テストでは `has_function_privilege('anon', ...)` に加えて **`proacl IS NOT NULL`（NULL = 既定権限 = PUBLIC に EXECUTE）と `aclexplode(proacl)` の `grantee = 0`（PUBLIC）** を検査する
- 関連: `supabase/migrations/20260913000500_capture_remote_definer_functions.sql` / `supabase/migrations/20260913000510_harden_definer_functions.sql` / `supabase/tests/definer_functions_privileges_test.sql`

### 是正の前にリモートの実定義を取る（repo の定義は古いことがある）
- `calculate_achievement_rate` は repo（20251230131753）より新しい本体（開始体重 NULL 時に最古の体重記録へフォールバック）が**リモートにだけ**あった。`mark_messages_as_read` はリモートにしか存在しなかった（2026-02-08 に migration を経ずに作成）
- repo の定義を土台に `CREATE OR REPLACE` すると、権限の是正と同時に**本番ロジックを巻き戻す**。先に「一言一句の追認 migration（リモート no-op）」→「是正 migration」の2本に分けた。追認の一致は `prosrc` の md5 で確認する（行末空白も含めて一致させる。エディタの自動トリムに注意）
- dump から owner の push までの間にリモートが変わると、追認・是正の `CREATE OR REPLACE` がそれを黙って巻き戻す。**両 migration の先頭に `md5(prosrc)` のドリフトガード**を置き、想定外の本体なら `REMOTE_DRIFT_SINCE_CAPTURE` で push ごと中断させる（fresh DB 用に repo の旧本体の md5 も許容値に入れる）
- MCP（execute_sql）が無いセッションでも、`supabase db dump --linked --schema public`（読み取り専用トランザクションの pg_dump）でリモートの関数定義と GRANT は取れる。`supabase migration list --linked` でリモートの適用履歴も見られる。ただし **cron.job の中身は dump に出ない**（CLI の一時ログインロールでは cron スキーマのデータが取れない）

### `SET search_path = ''` は関数内で発火するトリガーにも効く
- 関数の SET 句は実行中ずっと有効なので、関数の DML が発火させるトリガー関数（search_path 未設定のもの）も空の search_path で動く。**是正前に、DML 先テーブルのトリガー関数本文が無修飾参照を含まないか確認する**（今回は `update_updated_at_column()` が `NOW()` のみで安全、`on_message_update` は `UPDATE OF content` なので read_at 更新では発火しない）

### DEFINER 関数の本文チェックで「auth.uid() が NULL なら許可」にしない
- service_role キーの JWT は sub を持たないため、Edge Function を通すために「uid NULL は許可」と書きがちだが、それだと **sub の無い authenticated クレーム**も通る。許可するのは `auth.jwt() ->> 'role' = 'service_role'` と、`auth.jwt() IS NULL`（JWT クレーム自体が無い直接 DB 接続 = postgres / cron）だけにした。比較は `IS DISTINCT FROM` で NULL を拒否側に倒す（`p_client_id` が NULL のときの素通り防止も同じ）
- 実際の anon キー / publishable キーの要求は `{"role":"anon"}`（sub 無し）を持つので本文チェックでも拒否されるが、本文はあくまで第2層。**クレーム無しの anon セッションや、本人のクレームを持った anon は本文上「直接 DB 接続」「本人」として通ってしまう**ため、テストは (a) クレーム無し anon と (b) クレーム付き anon で GRANT 層を単独で検証する（上の RLS テストの教訓の関数版）。拒否の種類は `SQLERRM`（本文 = `ACHIEVEMENT_RATE_FORBIDDEN` / GRANT 層 = `permission denied for function ...`）まで見分ける。負の対照6本（anon へ GRANT / 本文チェック除去 / PUBLIC へ GRANT / search_path=public / authenticated へ GRANT / service_role へ GRANT）で、それぞれ狙ったケースだけが FAIL することを確認した
- PostgREST 経由では 42501 は anon（公開キー・publishable キー）→ **401**、authenticated / service_role → **403** になる

### cron ジョブの実行ロールを EXECUTE 剥奪で壊さないためのガード
- `cron.job` には RLS（`username = CURRENT_USER`）があり、postgres が全ジョブを見られるのは BYPASSRLS を持つからにすぎない。migration 内のガードは「ジョブが見えない」を黙って skip せず WARNING にし、実行ロールが EXECUTE を失う場合は例外で migration 全体を中断させる
- postgres では `cron.job.username` を変更できない（superuser 必要）。ガードの負の対照は「オーナーから EXECUTE を剥がす」で代替した

### 共有ローカルスタックを使えないときは隔離スタックで検証する
- 他セッションが共有 DB（`supabase_db_fit-connect`）で migration 検証中だったため、scratch の git worktree で `config.toml` の `project_id` とポート（5532x）だけを変え、studio / inbucket / realtime / edge_runtime を無効化した隔離スタックを `supabase start` → 検証 → `supabase stop --no-backup` した。repo の config.toml は触らない
- `supabase start` が CPU ほぼ 0 のまま進まない場合、既定版の PostgREST イメージの pull で止まっていることがある。`supabase/.temp/rest-version` に**リモートと同じ版（v12.2.3、ローカルにキャッシュ済み）**を置くと pull 不要になり、API 検証も本番と同じ PostgREST で行える
- **migration のタイムスタンプはリモート適用履歴と一緒に動く標的**。当初は「リモート適用済みの 000300」と「保留中の 000400」の間（000310 / 000320）に置いたが、作業中にオーナーが 000400 をリモートへ適用し、そのままでは `--include-all` が必要になった（`db push --dry-run` が「Remote migration versions not found」で検出）→ 000500 / 000510 に振り直した。**引き渡し直前に `supabase migration list --linked` と `db push --dry-run` を取り直し、リモートの最新より後ろに並んでいることを確認する**。並行ブランチ（feature/client-alerts の 20260914*）が先に入った場合も同じ確認が要る

## cron 本番初回実行と sessions.memo の露出（2026-09-13）で得た知見

### cron の「succeeded」は HTTP の成否ではない — 初回実行の後は関数ログで status を見る

- **症状**: `cleanup-ai-images` の初回（2026-09-13 04:00 JST）は `cron.job_run_details` では succeeded だったが、実際は Edge Function 内の `rpc('find_orphan_ai_images')` が PostgREST から 504 Gateway Timeout（約7秒待ち）を受けて 500 終了し、削除候補5件が残っていた。SQL 自体は 6.5ms、PostgREST 側にログなし＝一時障害
- **原因**: pg_net の `net.http_post` はリクエストを積んだ時点で戻るので、cron の成否は「投げたか」だけ。結果は `net._http_response`（保持は既定6時間）と Edge Function ログ（`function_edge_logs` / `function_logs`）にしか残らない。さらに auto-skip / cleanup の cron は pg_net 既定の5秒タイムアウトのままで、遅い応答は `timed_out` になり中身を確認できなかった
- **対策**: 3つの cron 関数の DB / Storage 呼び出しに、一時障害（status 0・5xx・例外）に限った再試行を入れ、cron の HTTP タイムアウトを60秒に揃えた（push 送信は二重送信を避けるため再試行しない）
- **教訓**: cron を有効化したら、**初回実行の後に Edge Function ログで status を確認する**。副作用の結果（skipped 件数・残った候補数）を SQL で数えるのが一番確実（auto-skip はこれで9件 skipped を確認できた）
- **その後（同日 20:00 JST）**: send-session-reminders の初回本送信でも、対象抽出の RPC が1回目に 504 を受けたが、再試行で成功した（ログに `[retry] ... attempt 1/3 failed (status=504 ...)`）。04:00 と 20:00 のどちらも毎時0分ちょうどの呼び出しで起きている

### 「トークンが登録できた」は「通知が届く」ではない — FCM→APNs は実送信で確かめる

- 2026-08-29 の APNs 対応では、実機の FCM トークンが `device_tokens` に保存されることまでを確認して完了扱いにしていた。9/13 のリマインダー初回送信で、FCM が `401 Invalid APNs credential`（THIRD_PARTY_AUTH_ERROR）を返し、**本番の push は一度も届いていなかった**ことが分かった（notification_logs に sent が0件）
- 原因は Firebase Console 側の APNs 認証キー（.p8）の未登録または不正。コードでは直せない
- **教訓**: 通知の検証は「トークン保存」ではなく「実機に届く + notification_logs が sent」まで行う。notification_logs の status 別件数（sent が0のままか）を定期的に見るだけで、配信経路の断絶に気づける

### 行単位 RLS は全列を見せる — 他ロールに SELECT を開けたテーブルの内輪の列は漏れる

- フェーズ8.3①で `sessions` に顧客用 SELECT ポリシーを足した結果、アプリが取得・表示していなくても、顧客は API 経由でトレーナーの内輪メモ `memo` を読める状態だった（本番の記入が0件のうちに発見）
- RLS が決めるのは行の可否だけで、列は GRANT 単位。トレーナーと顧客はどちらも `authenticated` なので、列の GRANT でも分けられない
- **対策**: 顧客用ポリシーを DROP し、返す列を許可リストで固定した SECURITY DEFINER 関数 `get_my_sessions` 経由に切り替えた。SECURITY DEFINER ビューは、自動更新可能ビュー経由で書き込みが RLS をすり抜ける危険と、Supabase Advisor の `security_definer_view` エラーがあるため採らなかった
- **教訓**: 他ロールに SELECT を開けるポリシーを足すときは、行ではなく**「このテーブルの全列を相手に見せてよいか」**で判断する。内輪の列があるなら、列を絞った関数経由にするか別テーブルに分ける

## 異常検知エンジン（フェーズ9 PR1、2026-09-13）で得た知見

### 行単位 RLS の WITH CHECK は他の列を守らない — 利用者が書ける値は「敵対的な入力」として扱う

- `clients_update_own` は `client_id = auth.uid()` しか見ないので、顧客は自分の行の `created_at` や `trainer_id` まで書き換えられる。messages の INSERT / UPDATE も `sender_id` / `receiver_id` しか見ず、`read_at`・`created_at`・`receiver_type` を自由に書ける（リモートの pg_policies で確認。修正は別タスク）
- レビューで実害が2つ見つかった: (1) 顧客が `created_at = '-infinity'` にするだけで、全トレーナー分の検知バッチが日付計算の 22008 で毎日落ちる (2) 担当関係の無い誰かが既読（read_at）を偽造して、他人の顧客の「最終到着日」を動かし、アラートを出したり消したりできる
- **対策**: 検知側で `isfinite()` の絞り込みと、snapshot から消えた顧客の行を ineligible で閉じる処理を入れた。既読は「今の担当トレーナーが送った分」だけを数える
- **教訓**: SECURITY DEFINER の一括処理は、**利用者が書ける列の値が1件でも想定外だと全員分が止まる**。DEFINER から読む列は「誰が書けるか」を pg_policies で確かめ、書けるなら値の範囲と出どころ（送信者など）で絞る

### 条件の違う複数の UPDATE で状態遷移するなら、先に FOR UPDATE で対象行をロックする

- 検知の本実行は、継続中のアラートを「再浮上」「open のまま昇格」「値だけ更新」の3本の条件付き UPDATE で更新する。その間にトレーナーの「対応済み」（API の条件付き UPDATE）が挟まると、昇格したときの再浮上が失われる
- 遷移の前に `SELECT ... FROM alerts WHERE resolved_at IS NULL FOR UPDATE` を取り、API の UPDATE を本実行のコミットまで待たせた

### SQL を直接呼ぶ cron と HTTP 経由の cron では、失敗の見え方が違う

- `detect-client-alerts` は pg_cron から SQL 関数を直接呼ぶので、例外は `cron.job_run_details` に failed で残る（HTTP 経由の cron は投げた時点で succeeded になる。8.4 の教訓）。push しない処理に Edge Function を挟む理由は無い

### 睡眠の upsert と `set_updated_at` トリガーへの依存

- 「アプリからデータが届いた日」は、Mobile の睡眠 upsert が同期のたびに約30行の `updated_at` を更新することにも頼っている。weight / sleep を一括 UPDATE する migration を流すと全員が「今日同期した」ように見え、休眠中の顧客が監視対象に戻って「記録なし」が大量に出る。流すときはトリガーを一時的に無効にするか、前後で検知を止める
- 兼務アカウント（トレーナーでもあり、別トレーナーの顧客でもある）の痕跡は、`sender_type` / `receiver_type` で分けないと混ざる


## parse-message-tags の本番 URL 直書きと未認証（フェーズ5.7、2026-09-22）で得た知見

### DB トリガーに本番の URL を直書きすると、migration を流したすべての DB が本番を呼ぶ

- **症状**: 本番の `notification_logs` に、Seed.sql のプレースホルダー顧客（`11111111-…` / `22222222-…`）宛ての `kind='message'`・`status='skipped'` が 18 行あった（その後の照会で実数は 186 行。2026-07-26 の notification_logs 新設直後から、seed 投入のたびに書かれていた）。ローカル・隔離スタックの `supabase start` / `db reset`（Seed.sql のメッセージ投入）が原因
- **原因**: `call_parse_message_tags()` が `https://<本番 ref>.supabase.co/functions/v1/parse-message-tags` を直書きしていた。コミットされたメッセージの INSERT / content UPDATE は、どの DB で起きても本番の関数へ送られる。本番の関数は payload を信用して動くので、たまたまプレースホルダー UUID が本番に無かったから記録と push が作られなかっただけ（ロールバックしたトランザクションは pg_net のキュー行ごと消えるので送られない）
- **対策**: 送信先は環境ごとの Vault（`project_url`）から組み立て、**無ければ送らない**（WARNING だけ）。フォールバック URL は持たない。`net.http_post` は url が NULL だと `net.http_request_queue` の NOT NULL 違反でメッセージの INSERT 自体を落とすので、skip 分岐は「親切」ではなく必須
- **教訓**: トリガー・cron から外部 HTTP を呼ぶ SQL に**環境固有の値を直書きしない**。「その migration を空の DB に流したら、どこへ何が飛ぶか」をレビュー観点に入れる。検証は「Vault 空で Seed.sql をコミットしても pg_net の要求 0 件・応答 0 件」で確かめた

### Vault を読むトリガーは、トリガー関数そのものを SECURITY DEFINER にする

- トリガー関数は INSERT したロール（authenticated）の権限で動くので、Vault を読むには DEFINER が要る。「secret を返す DEFINER ヘルパー」や「payload を受けて送る DEFINER ヘルパー」に分けると、INVOKER のトリガーから呼ぶために authenticated へ EXECUTE を付けざるを得ず、PostgREST RPC から secret の取得・任意 payload の送信ができてしまう
- トリガー関数はトリガー以外から呼べない（`trigger functions can only be called as triggers`）うえ、**発火時に EXECUTE は検査されない**（検査は CREATE TRIGGER の時だけ）。なのでトリガー関数を DEFINER にして EXECUTE を全ロールから剥がすのが最小権限になる。テストで「authenticated に EXECUTE が無いのにトリガーが発火する」ことまで確かめた

### Webhook 型の Edge Function は payload を「通知」と割り切り、DB から取り直す。ただし DB の値も「誰が書けるか」次第

- 認証（`_shared/service_auth.ts` で apikey を照合）を入れても、payload の sender_id / content / created_at を使い続けると「secret を持つ呼び出し元が間違った値を送る」事故に弱い。type と record.id だけを使い、行を service role で取り直す（jsonb カラムが payload に入らない罠の対策とも一致）
- DB の sender_id が信用できるのは、それを**書ける経路が絞られている間だけ**。INSERT は `WITH CHECK sender_id = auth.uid()` で固定されるが、受信者用の UPDATE ポリシーは列を制限しておらず、受信者が sender_id / content を書き換えて on_message_update を起こせる（`fix/rls-column-write-guards` で塞ぐ前提）。記録の作成・削除は `sender_type = 'client'` のときだけにし、トレーナー発のメッセージは通知だけにした

### ローカルで secret キー認証の Edge Function を通す方法（CLI v2.75）

- ローカルの CLI は edge runtime に `SUPABASE_SECRET_KEYS` / `SUPABASE_SECRET_KEY` を渡さない（`SUPABASE_` で始まる env は functions の env ファイルからも弾かれる）。代わりにローカルの kong が `apikey: <ローカルの sb_secret>`（Authorization なし）を `Authorization: Bearer <ローカルの service_role JWT>` に書き換えるので、`service_auth.ts` の互換経路で通る
- DB コンテナから見たローカル API は `http://kong:8000`（スタックの Docker ネットワーク内のエイリアス。project_id / ポートによらず同じ）。ローカルの Vault に `project_url = http://kong:8000` と `secret_key = supabase status の Secret` を入れれば、トリガー → pg_net → 関数 → DB を通しで検証できる（手順: `2026-07-10-cron-vault-setup.md` §1-3）

### 並行ブランチと migration のタイムスタンプが衝突する

- 同じ日に別セッションの worktree（`fix/rls-column-write-guards`）が**未コミットの** `20260922000000_*.sql` を作っていた。同じ version だと後から push する側が schema_migrations の主キーで衝突する。作成前に `git worktree list` の各 worktree の `supabase/migrations/` も覗き、空いている番号（今回は 000100）を使う。どちらが先に push されても、後の側は引き渡し直前に `migration list --linked` と `db push --dry-run` で並びを確認する（5.6 の教訓と同じ）

### 隔離スタックは修正が develop に入るまで seed を無効にする

- 修正前の migration で起動した隔離スタックは、`supabase start` / `db reset` の seed 投入だけで本番を叩く。隔離スタックの scratch の config.toml に `[db.seed] enabled = false` を入れ、reset は `--no-seed` で行った。検証時点で他セッションの隔離スタック（`fit-connect-triage` / `fit-connect-colguard`）も起動していたので、18 行より増えている可能性がある（削除文は user_id で絞るので件数によらず有効）
- 負の対照: 隔離スタックの edge runtime に旧 index.ts を戻し、認証なしで偽 payload を POST すると 200 で `recorded_at = 2000-01-01` の体重記録が作られた。新しい関数では同じ POST が 401

## 顧客詳細の体重表示の取り違えとアバターの壊れた画像（フェーズ8.5、2026-09-22）で得た知見

### 取得関数の並び順を呼び出し側で「暗黙に」前提にしない — 似た関数のロジックを流用すると逆順のまま動く

- **症状**: 顧客詳細の体重タブ「最近の記録（最新5件）」に最新の記録が出ず、最古の5件が古い順に並んでいた（8/7 に +0.3）。同じページの KPI「現在体重」は最古の体重、「月間変動」は常に 0、体重予測（BMR・1ヶ月後予測）も最古の体重で計算されていた。半年間誰も気づかなかった
- **原因**: `getWeightRecords` は作成時から古い順。UI 刷新（0c16d3f）で、新しい順を返す `getClientListMetrics` 用のロジック（`records[0]` が最新・`find(<=30日前)`）を、古い順のデータにそのまま流用した。取得関数は正しく、壊れたのは呼び出し側の前提
- **対策**: 表示用の値（最新・最新 N 件・前回比・N 日前比）は**並び順に依存しない純粋関数**（`src/lib/weight/weightRecordSelectors.ts`）で算出し、テストは古い順・新しい順・シャッフルの3通りの入力で同じ結果になることを確かめる。取得関数の順序を変えて直す案は、`WeightChart` が props の配列をその場で sort していた（描画中に親の state を書き換える）ため、ALL 期間を押すと再発する不安定なバグになるので採らなかった
- **教訓**: `[0]` / `slice(0, N)` / `[i + 1]` を「最新」「前回」の意味で書くときは、**その配列を作った関数の order を必ず読む**。新しい順・古い順の取得関数が混在するコードベースでは、呼び出し側に並び順の前提を持たせない。`.sort()` は入力配列を破壊するので props / state には使わない（`[...xs].sort()`）

### 外部 URL の画像は読み込みに失敗しうる前提で、失敗時の表示を用意する

- Google のプロフィール写真（lh3.googleusercontent.com）を hotlink しているアバターが、ユーザーのブラウザでだけ壊れた画像アイコンになった。URL 自体は curl でも別ブラウザでも 200 で読める。外部ホストは 403 / 429・拡張機能のブロック・写真の差し替えによる失効などで**こちらの制御外で失敗する**
- `ProfileAvatar` と `ClientCard` の next/image に onError が無かったので、失敗すると alt テキスト付きの壊れた画像のまま残った（`StorageImg` は fallback 済みだった）。失敗した URL を state に持ち、同じ URL の間はイニシャル表示、URL が変われば再試行する形にした。Referer は送らない（`referrerPolicy="no-referrer"`）
- 失敗の原因をユーザーの環境で確かめるには DevTools の Network のステータス（403 / 429 / `(blocked:other)` / `ERR_BLOCKED_BY_CLIENT`）を見てもらう。こちらのブラウザで再現しないからといって「直った」とは言わない
- ログに URL 全体を出さない（Supabase の署名 URL はクエリにトークンを含む）。ホスト名だけ出す

### timestamptz を素の日付（'yyyy-MM-dd'）で `.lte` すると終了日がほぼ丸ごと漏れる

- レポート概要が `.lte('recorded_at', endDate)` で絞っており、`'2026-09-22'` は 2026-09-22 00:00 UTC（JST 9:00）として比較されるため、終了日の JST 9:00 以降の記録（今日の体重）が出なかった。上限は `.lt('recorded_at', 翌日)` の半開区間にする（`src/lib/report/recordedAtRange.ts`。翌日の計算は UTC で行い、実行環境のタイムゾーンに左右されないようにする）
- 同じ期間を「UTC の日付文字列で比べるビュー」と「timestamptz を素の日付で比べるビュー」で扱うと、同じ画面の中で数値が食い違う。期間フィルタと日付の数え方（UTC / ローカル）は 1 画面の中で揃える（ヒートマップはまだローカル日付で数えている。フォローアップ）

## 列単位の書き込みガード（フェーズ5.8、2026-09-22）で得た知見

### 行単位の WITH CHECK は他の列を守らない

- **症状（2026-09-13 リモートの pg_policies 照会で確認）**: `clients_update_own` は `WITH CHECK (client_id = auth.uid())` だけなので、顧客は自分の行の `trainer_id`（任意のトレーナーへの紐づけ・担当外し）/ `created_at`（`'-infinity'` 等。フェーズ9 は登録日として使う）/ トレーナーが決める列（目標体重・目的など）を書き換えられた。messages も INSERT は `sender_id` だけ、送信者の UPDATE は `sender_id` だけ（`created_at` を未来にすれば5分の編集枠も延ばせる）、受信者の UPDATE は `receiver_id` だけを縛っていて、受信者が本文・タグ・メタデータまで書き換えられた
- **原因**: RLS が決めるのは「どの行か」だけ。WITH CHECK は新しい行が条件を満たすかを見るだけで、**条件に出てこない列は何に変えても通る**。上の「行単位 RLS は全列を見せる」（読み取り側）の書き込み版。フェーズ9 の「行単位 RLS の WITH CHECK は他の列を守らない — 利用者が書ける値は敵対的な入力」（上）は**読む側（検知バッチ）での防御**で、本節は**書く側での封鎖**。両方が要る（封鎖前に書かれた値・service_role が書く値は検知側で引き続き疑う）
- **対策の選び方**:
  - 書き手のロールが違う（顧客 = authenticated / トレーナー = supabaseAdmin の service_role）→ **列レベル GRANT**（trainers の 20260712000000 §4 と同じ方式）。clients はこれ
  - 書き手が同じロール（送信者も受信者も authenticated）→ 列 GRANT では区別できないので **BEFORE トリガー**。messages はこれ。UPDATE は `to_jsonb(NEW) - 許可列` と `to_jsonb(OLD) - 許可列` の比較にすると、今後追加される列も既定で保護される
  - システム列（created_at / read_at / edited_at）は拒否ではなく**強制値で上書き**すると、端末時計の値を送っている既存アプリ（Mobile の edited_at は offset 無しのローカル時刻で 9 時間ずれていた、Web の read_at はブラウザ時計）を壊さずにサーバー時刻へ揃えられる
- **ポリシーを足すときのチェック**: 「その行の**どの列を、誰が、どんな値に**書いてよいか」を列ごとに表にしてから書く。正規の書き込み経路（Mobile / Web / Edge Function / DEFINER 関数）を全数調査して表の根拠にする
- 関連: `supabase/migrations/20260922000200_column_write_guards.sql` / `supabase/tests/column_write_guards_test.sql`

### PostgREST の upsert は SET 句の全列に UPDATE 権限が要る（衝突しない初回でも）

- Mobile の登録は `upsert(..., onConflict: 'client_id')` = `INSERT ... ON CONFLICT (client_id) DO UPDATE SET <ペイロードの全列> = EXCLUDED.<列>`。PostgreSQL は **SET 句の列の UPDATE 権限を計画時に検査する**ため、`trainer_id` の UPDATE 権限を剥がすと、行がまだ無い初回登録まで permission denied で落ちる
- そこで `client_id` / `trainer_id` にも UPDATE 列権限を残し、トリガーで「OLD と同じ値の再送だけ許可」にした（登録リトライは同じ trainer_id を送るので通る）
- **列 GRANT の変更は、実アプリと同じ HTTP リクエストで検証する**。SQL テストだけでは PostgREST が組み立てる SQL の形（upsert の SET 句、`.select()` の RETURNING）を再現しきれない。今回は postgrest-dart のソースを読んで同じクエリ文字列・`Prefer` ヘッダーを raw fetch で再現し、隔離スタックの PostgREST に投げた（47 ケース）

### トリガーで「誰が書いているか」は current_user で見る（auth.role() ではない）

- PostgREST は `SET ROLE authenticated / anon / service_role` するので、SECURITY INVOKER のトリガー関数内の `current_user` は呼び出し元ロールになる。**SECURITY DEFINER 関数の中から発火した場合は所有者（postgres）**になるので、`IF current_user NOT IN ('authenticated', 'anon') THEN RETURN NEW` で service_role と DEFINER 関数（`mark_messages_as_read`）を素通しできる。`auth.role()` は JWT のクレームを読むだけなので DEFINER 関数内でも 'authenticated' のままで、使うと DEFINER 経路まで制限してしまう
- ガード関数自身は SECURITY INVOKER（DEFINER にすると current_user が失われる）+ `SET search_path = ''` + 完全修飾。トリガー関数は発火時に EXECUTE 権限を要らないので、EXECUTE は PUBLIC / anon / authenticated から剥がしてよい（テストで確認済み）
- **BEFORE ROW トリガーは RLS の WITH CHECK より先に走る**。固定コード（`MESSAGES_SENDER_MISMATCH` 等）で先に落とせる一方、トリガー内の参照クエリは呼び出し元の RLS の下で動くので、正規の呼び出し元から見える行だけで判定を組む（見えなければ拒否 = fail closed）
- BEFORE トリガーは名前順に発火する。`messages_guard_update` は `set_updated_at` より先に走るので、updated_at は比較対象から外した
- anon は GRANT 剥奪で先に permission denied になるが、将来の `GRANT ALL`（Supabase の既定権限）で戻っても書けないように、トリガーでも `ANON_WRITE_FORBIDDEN` で拒否する。負の対照で anon に GRANT を戻すと、messages の書き込みはこの層で止まり、clients の UPDATE は `clients_update_own` が `TO authenticated` のため RLS で 0 行になる

### REVOKE は「自分が付与した権限」しか剥がさない — 権限の最終形は migration の末尾で検査する

- `REVOKE ... FROM authenticated` を postgres が実行しても、**別の grantor（例: GRANT OPTION を持つ service_role）が付けた権限は WARNING も無く残る**（隔離スタックで再現済み）。オーナーが手で push するリモートでこれが起きると、列 GRANT に切り替えたつもりでトレーナー所有列が書けたままになる
- 対策: migration の最後に `has_table_privilege` / `has_column_privilege` / `has_any_column_privilege` とトリガーの存在・有効状態を検査する DO ブロックを置き、想定と違えば例外で migration ごと中断させる（`COLUMN_GUARD_PRIVILEGE_CHECK_FAILED`）

### ポリシーの OR 結合で「別の役割の USING」から行に入られる — 自分宛ての行に注意

- 受信者の UPDATE ポリシーには時間制限が無い。`sender_id = receiver_id`（自分宛て）の行では、送信者として5分を過ぎても受信者ポリシー経由で行に入れ、ガードが「送信者だから content 可」と判定していた（レビューで発見）
- **トリガーで役割ごとの許可列を決めるときは、その役割の RLS 条件（ここでは5分の編集枠）もトリガー側で同じ式で再確認する**。PERMISSIVE ポリシーは OR なので、どのポリシーで行に入ったかをトリガーは知らない

### ローカルスタックで messages を INSERT すると本番の Edge Function が呼ばれていた（→ 5.7 で是正済み）

- 本タスクの検証中、隔離スタックを seed 付きで起動しただけで本番の `notification_logs` に行が入り、`call_parse_message_tags()` の本番 URL 直書きが見つかった（5.7 / #89 で是正。経緯と教訓は上の「DB トリガーに本番の URL を直書きすると、migration を流したすべての DB が本番を呼ぶ」「隔離スタックは修正が develop に入るまで seed を無効にする」）
- 是正前の回避策として使ったのは、SQL テストは BEGIN…ROLLBACK（pg_net のキュー行も巻き戻る）、reset は `--no-seed`、メッセージを実際に書く API テスト・UI QA の前に隔離 DB の中だけで呼び出し先 URL を到達不能なアドレスへ差し替える、の3つ

### DB だけの変更でも UI QA は「migration を当てた隔離スタック」に向けたアプリで行う

- アプリのコードが変わらない変更（RLS・GRANT・トリガー）は、本番や共有スタックを向いたアプリで QA しても何も検証できない（しかもテストデータが本番に入る）。アプリを**隔離スタックへ向けて**正規経路を実際に通す
- Web: worktree には `.env.local` が無いので、`NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` を隔離スタックのローカル既定キーで環境変数として渡して `pnpm dev --port <別ポート>`（3000 は他セッションが使っていることがある）。ログインはパスワード入力をせず、テスト用トレーナーのセッションを `sb-127-auth-token`（`base64-` + base64url(JSON)）Cookie として内蔵ブラウザに入れた
- Mobile: worktree の `assets/.env`（本物のコピー）を隔離スタックの値で書いた別ファイルに一時的に差し替え（元ファイルは読まない。終わったら `cp` で戻す）、`flutter build ios --simulator --debug`。他セッションが起動中のシミュレータは避けて別機種を boot。ログインは隔離スタックの Mailpit（`/api/v1/messages`）からマジックリンク（PKCE）を取り、`open_url` でシミュレータに開かせる
- 同意ダイアログ等のテスト用前提データは、隔離 DB に直接入れてよい（今回は user_consents）

### チェック済みのタスクでも実装を確かめる

- IMPLEMENTATION_TASKS 5.1 では cat7 1-B「anon への書き込み系 GRANT の REVOKE」が `[x]` だったが、どの migration にも REVOKE は無く、リモートでも clients / messages は anon に `arwdDxt` のままだった。**権限系のチェック項目は `relacl` / `has_table_privilege` で実物を見る**。今回剥奪したのは anon の clients INSERT / UPDATE と messages INSERT / UPDATE / DELETE だけ（clients の DELETE、両テーブルの TRUNCATE、他テーブルは未実施）

## デイリートリアージ（フェーズ9.2 PR2、2026-09-22）で得た知見

### RLS 付きの表を読む SQL 関数で `(SELECT auth.uid())` と書くと、索引が効かない計画になることがある

- 未返信 RPC（SECURITY INVOKER）の最初の版は、顧客ごとにトレーナーの受信箱全体を走査する計画になり、合成データで 155ms かかった。原因は2つ: (1) 関数本体の `(SELECT auth.uid())` は計画時に値が分からず、索引条件として使われなかった (2) 「返信が無いときは -infinity」の coalesce を比較の側に書くと、RLS 下で索引条件にならなかった
- `auth.uid()` を直接書き、coalesce を「最後の返信」を求めるサブクエリの中に移すと、`(sender_id, created_at DESC)` / `(receiver_id, created_at DESC)` の範囲走査と逆順 LIMIT 1 になり 1.3ms（結果の差分 0 行）
- **教訓**: RLS ポリシーでは `(SELECT auth.uid())` で包むのが定石だが、関数本体のクエリでは逆効果になることがある。SQL 関数を書いたら、**本番と同じロール・JWT クレーム**で合成データを入れて EXPLAIN を取り、索引が使われているかを確かめる（postgres では auto_explain を LOAD できないので、本体クエリを取り出して EXPLAIN する）

