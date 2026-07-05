# 設計: 睡眠記録を「記録タブ」へ統合

- 日付: 2026-06-28
- 対象: fit-connect-mobile（Flutter）
- ブランチ: `feature/move-sleep-to-records-tab`
- ソースルート: `fit-connect-mobile/lib/`

## 背景・目的

現在、睡眠記録画面（`SleepRecordScreen`）は **ホームタブからのみ** 到達できる（ホーム上の独立カード `SleepSummaryCard` をタップ → `Navigator.push`）。記録タブ（`RecordsScreen`）には睡眠が存在せず、体重・食事・運動などと並んでいない。

本タスクのゴールは、睡眠記録を他の記録種別と同じ導線に揃えること:

1. ホームの「今日のまとめ」カードに睡眠セクションを統合する（独立カードを廃止）
2. 「寝起きの良さ」を記録する動線はホームに残す
3. 記録タブに「睡眠」サブタブを新設し、ホームの睡眠セクションをタップすると睡眠サブタブが選択された状態で遷移する（体重・食事・運動と同じ挙動）

データ層（Provider / Model / Supabase `sleep_records` テーブル）は変更しない。UI の再配置が中心。

## 現状サマリ（調査結果）

### 睡眠機能
- 画面: `lib/features/sleep_records/presentation/screens/sleep_record_screen.dart`
  - `body` は `ListView`（73-84）。内部セクション: `_SummarySection`（116-）／`_SectionTitle('直近7日間')`／`_WeekSection`（606-）／`_HistorySection`（660-）
  - AppBar 右上に「同期」ボタン（59-71、`refreshCw`）→ `_onRefresh`（26-48）が `healthSyncProvider.notifier.syncManual()` を呼び、`sleepRecordsProvider`/`todaySleepRecordProvider`/`recentSleepRecordsProvider` を invalidate
- ホーム用カード: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart`
  - `todaySleepRecordProvider` を watch、状態は empty / healthkit / manual
  - empty 状態のみ「目覚めを記録する」ボタン → ボトムシート `_RecordSheet`（408-）で `WakeupRatingSelector`（436）→ `upsertWakeupRating`
  - `onTap` → `home_screen.dart:86-92` で `SleepRecordScreen` を `Navigator.push`
- 共有UI: `wakeup_rating_selector.dart`（3択の純粋UI）。使用箇所は `morning_wakeup_dialog.dart:75` / `sleep_summary_card.dart:436` / `sleep_record_screen.dart:820`
- Provider / Model / data util は画面の置き場所に依存しない設計（移動の影響なし）

### 記録タブ
- `lib/features/home/presentation/screens/records_screen.dart`
  - `TabController(length: 5)`（26-30）、`didUpdateWidget` で `initialTabIndex` 変化時に `animateTo`（39-44）
  - タブ定義・`TabBarView` children（75-92）: `サマリ / 体重 / 食事 / 運動 / ノート` = `RecordsOverviewScreen / WeightRecordScreen / MealRecordScreen / ExerciseRecordScreen / ClientNotesScreen`
  - サブタブの本体は Scaffold を持たず `ListView` を直接返すのが基本（体重・食事）。サマリのみ独自 Scaffold を持つ（混在あり）
- 外部からサブタブを開く導線: `MainScreen._navigateToRecordsTab(int)`（`main_screen.dart:43-48`）→ `RecordsScreen(initialTabIndex:, onTabChanged:)`（86-89）

### ホーム「今日のまとめ」
- `lib/features/home/presentation/widgets/daily_summary_card.dart`
  - セクション: 食事 → 運動 → Divider → 体重。各行は `_buildTappableSection`（91-123）で `InkWell` + 右端 chevron
  - 各行レイアウト: 32x32 円アイコン（食事=orange/utensils, 運動=primary/dumbbell, 体重=emerald/scale）＋ラベル＋右側に値
  - コールバック: `onMealsTap` / `onActivityTap` / `onWeightTap`
- 配線: `home_screen.dart:70-81`
  - コメント `// Records tabs order: 0=サマリ, 1=体重, 2=食事, 3=運動, 4=ノート`
  - `onMealsTap → onNavigateToRecordsTab(2)`, `onWeightTap → (1)`, `onActivityTap → (3)`
  - ホーム Column 配置順（38-99）: あいさつ → 目標カード → トレーナー状況 → **DailySummaryCard** → **SleepSummaryCard**（直下の独立カード） → 余白

## 合意した設計

### ① 記録タブに「睡眠」サブタブを新設
- `records_screen.dart`: `TabController` を `length: 5 → 6`。サブタブ並びを `サマリ / 体重 / 食事 / 運動 / 睡眠 / ノート` に。
  - 睡眠 = **index 4**、ノートが **index 4 → 5** にずれる。
- 中身は既存 `SleepRecordScreen` の内部セクション（サマリ／直近7日グラフ／履歴）を流用。
- 専用 AppBar を外し、他サブタブ（体重・食事）と同様に本体（`ListView`）を返す形へリファクタ。

### ② HealthKit 同期ボタンの移設
- 記録タブ共通 AppBar の右上に、**睡眠サブタブ選択時のみ**「同期」アイコンを表示（`TabController` の index を監視して `actions` を出し分け）。
- 睡眠サブタブに pull-to-refresh（`RefreshIndicator`）を追加。
- 同期処理（`healthSyncProvider.syncManual()` ＋関連 Provider invalidate）を AppBar ボタンと pull-to-refresh で共有できる形に整理する。

### ③ ホーム「今日のまとめ」へ睡眠セクションを統合
- 独立カード `SleepSummaryCard` は **廃止**。
- `DailySummaryCard` に「睡眠」行を追加（**体重の下、最後**）。他セクションと同じレイアウト（円アイコン=月/indigo ＋ラベル＋右に値＋chevron）。
- 値は `todaySleepRecordProvider` を watch し、客観データがあれば睡眠時間、寝起き評価があれば 😊 等を表示。

### ④ 睡眠行のタップ挙動
- 行タップ → `onNavigateToRecordsTab(4)` で記録タブの睡眠サブタブへ遷移（体重・食事・運動と統一）。
- **寝起きの良さが未記録の日**は行内に小さな「記録」ボタンを表示 → 押すと **その場でボトムシート**（`WakeupRatingSelector`）で記録（ホーム完結、記録タブへは飛ばない）。記録済みなら評価を表示。
- このボトムシートは `WakeupRatingSelector` を使う既存の記録UIと同じ。重複を避けるため **共通化**（「寝起き記録ボトムシート」を関数/ウィジェット化）し、統合後は **睡眠画面・今日のまとめ** の2箇所から再利用する（朝ダイアログは⑤のとおりスコープ外のため従来どおり `WakeupRatingSelector` を直接使用。実装時に確定）。旧 `SleepSummaryCard` の `_RecordSheet` は統合で無くなるため、その実装を共通部品の元にする。

### ⑤ スコープ外（触らないもの）
- 朝の自動起床ダイアログ（`morning_wakeup_dialog`、アプリ起動/復帰時に表示）はそのまま維持。
- 睡眠の Provider / Model / `sleep_records` テーブルは変更なし。

### ⑥ 実装後QA
- Flutter コード変更のため `ios-simulator-qa` スキルでシミュレータ動作確認。

## 影響ファイル

変更:
- `lib/features/home/presentation/screens/records_screen.dart`（タブ追加 + AppBar 同期アクション出し分け）
- `lib/features/sleep_records/presentation/screens/sleep_record_screen.dart`（AppBar 撤去、タブ埋め込み用本体へ。pull-to-refresh 追加。同期処理の共有化）
- `lib/features/home/presentation/widgets/daily_summary_card.dart`（睡眠セクション + `onSleepTap` + 未記録時ミニCTA）
- `lib/features/home/presentation/screens/home_screen.dart`（独立睡眠カード削除、`onSleepTap → onNavigateToRecordsTab(4)` 配線、index コメント更新）
- `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart`（廃止。内部のボトムシート `_RecordSheet` は共通部品化の移設元として活用）

新規（実装計画で確定）:
- 共通「寝起き記録ボトムシート」関数/ウィジェット（既存 `_RecordSheet` / `_showRatingSheet` を共通化）

確認が必要:
- `MainScreen._navigateToRecordsTab` 周辺と、サブタブ index ずれ（ノート 4→5）に依存する箇所の整合。

## 既存パターン・注意点

- ルーティングは go_router 不使用。記録サブタブ間は `TabController` 切替（`Navigator.push` ではない）。
- サブタブ本体は「Scaffold を持たず `ListView` を返す」のが基本パターン（体重・食事に倣う）。
- デザイントークン差異: `DailySummaryCard` は borderRadius 24 / 円アイコン、旧 `SleepSummaryCard` は borderRadius 8 / 角丸アイコン。統合時は `DailySummaryCard` 側の様式（32x32 円アイコン）に揃える。
- 睡眠の日付キーは JST 文字列（`sleep_date_utils.dart`）。`upsertWakeupRating(recordedDate: todayJstDateKey(), rating)` を踏襲。
- 同期は過去30日固定レンジ。`syncSleep` は客観データのみ UPSERT し `wakeup_rating` は保護する（既存挙動を変えない）。

## writing-plans で詰める実装詳細

- 同期処理の状態（`_syncing`）を `records_screen` 側に持つか、Riverpod provider 化して AppBar ボタン／pull-to-refresh／（残すなら）他導線で共有するか。
- `SleepRecordScreen` を「AppBar 無しの本体ウィジェット」に作り替える方式（既存クラスを改修 vs 新ウィジェット抽出）。
- 「寝起き記録ボトムシート」共通化の置き場所と、既存3箇所からの差し替え範囲。
- 睡眠行の表示バリエーション（empty / healthkit / manual / loading）の見せ方を `DailySummaryCard` の行様式に最小限で落とし込む。
