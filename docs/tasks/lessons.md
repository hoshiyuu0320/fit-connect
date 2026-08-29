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
