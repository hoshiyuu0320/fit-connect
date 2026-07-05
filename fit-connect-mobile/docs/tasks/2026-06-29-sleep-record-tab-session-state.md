# セッション継続メモ: 睡眠記録を「記録タブ」へ統合

- 更新日: 2026-06-29
- ブランチ: `feature/move-sleep-to-records-tab`（`develop/1.0.0` から分岐、作業中）
- 対象: fit-connect-mobile（Flutter）
- 役割: マネージャー（実装はサブエージェント委託、自分では実装しない）

## ゴール（1行）

睡眠記録を「記録タブ」の新サブタブ『睡眠』へ移し、ホームでは独立カードを廃止して「今日のまとめ」カードの一行に統合する。データ層は変更せず UI 再配置が中心。

## 関連ドキュメント（詳細はこちら）

- 設計書: `fit-connect-mobile/docs/tasks/2026-06-28-sleep-record-to-records-tab-design.md`（commit 済み）
- 実装計画（各タスクに完全なコード付き）: `fit-connect-mobile/docs/tasks/2026-06-28-sleep-record-to-records-tab-plan.md`（commit 済み）
- **新セッションでは、まず上記2ファイルとこのメモを読むこと。**

## 合意済みの設計（①〜⑥）

1. 記録タブ（`records_screen.dart`）に『睡眠』サブタブを新設。並び順は **サマリ / 体重 / 食事 / 運動 / 睡眠 / ノート**（睡眠 = index 4、ノートが 4→5 にずれる）。`TabController` length 5→6。
2. HealthKit 同期ボタンは **記録タブ共通 AppBar 右上に、睡眠サブタブ選択時のみ**表示（`refreshCw`、同期中スピナー）。睡眠サブタブは pull-to-refresh 対応。同期処理は `records_screen` 側の `_onSyncSleep`（`syncManual` + invalidate3つ + SnackBar）を AppBar ボタンと `RefreshIndicator` で共有。
3. ホーム独立カード `SleepSummaryCard` は**廃止**。`DailySummaryCard` に「睡眠」行を追加（体重の下、最後）。indigo 系（背景 `indigo100` / アイコン `indigo600` / 月アイコン `moon`）。
4. 睡眠行タップ = `onNavigateToRecordsTab(4)` で記録タブの睡眠サブタブへ遷移。**寝起きの良さが未記録の日は行内に「記録」ミニボタン**を出し、押すとその場でボトムシート（ホーム完結、記録タブへ飛ばない）。記録済みは値/評価を表示。
5. スコープ外（触らない）: 朝の自動起床ダイアログ（`morning_wakeup_dialog`）、睡眠の Provider / Model / `sleep_records` テーブル。
6. 実装後 QA: `ios-simulator-qa` スキル。

## タスクリスト（TaskCreate 済み・8個）

| # | タスク | 状態 | 依存 | 委託先 |
|---|--------|------|------|--------|
| 0 | **UIモック生成（睡眠行・睡眠サブタブ）** | **in_progress** | — | マネージャー（HTMLモック） |
| 1 | 寝起き記録ボトムシート共通化（新規 `wakeup_record_sheet.dart`） | pending | — | flutter-ui/riverpod |
| 2 | SleepRecordScreen をタブ埋め込み用にリファクタ | pending | Task1 | flutter-ui |
| 3 | 記録タブに睡眠サブタブ+同期ボタン追加 | pending | Task2 | flutter-ui（**要モック反映**） |
| 4 | 今日のまとめカードに睡眠行追加 | pending | Task1 | flutter-ui（**要モック反映**） |
| 5 | ホーム画面の配線変更（独立カード削除） | pending | Task3,4 | flutter-ui |
| 6 | 旧 SleepSummaryCard 削除 | pending | Task4,5 | flutter-ui/マネージャー |
| 7 | ビルド確認とシミュレータQA | pending | Task1-6 | マネージャー（QAスキル） |

実装順: 1 → 2 → 3 → 4 → 5 → 6 → 7（1完了後は 2 と 4 を並行可）。

## 現在地（2026-07-05: 実装完了）

- モックはユーザー承認済み（「完璧です」）→ `subagent-driven-development` で Task1〜6 実装完了（各タスク: 実装サブエージェント→レビューサブエージェント、全て Spec ✅/Approved）。
- コミット列: 99a833c(T1) → dee4d53(T2) → 806d864(T3) → 42c9c6d(T4) → 70d70ed(T5) → d1c10b4(T6) → 2069a9a(最終レビューfix)。
- ブランチ全体の最終レビュー: **Ready to merge = Yes**。検出された Important 1件（共通シートの連打ガード欠落）+ Minor（Android pull-to-refresh 物理）は 2069a9a で修正、再レビュー APPROVED。
- `fvm flutter test`: 55/55 pass。全体 analyze: 既存106件のみ（ブランチ関連ゼロ）。
- ios-simulator-qa: 完了。ビルド/起動/朝の起床ダイアログは自動確認、タブ順・同期ボタン出し分け・pull-to-refresh・睡眠行・記録シート・遷移はユーザー手動確認で **全項目 OK**（2026-07-05）。
- 以後: squash → develop/1.0.0 への PR。

## 重要な技術メモ（検証済み）

- **Flutter コマンドは `fvm flutter`**（このリポジトリは fvm で 3.41.9 にピン留め。`flutter` 直叩き不可）。作業は `fit-connect-mobile/` で実行。
- `AppColors.indigo500` は**存在しない**（`indigo50/100/600/800` のみ）。睡眠アイコンは **背景 `indigo100` + アイコン `indigo600`** を使う。
- `record.hasObjectiveData` getter は `sleep_record_model.dart:91`（`totalSleepMinutes != null`）に存在。睡眠行の状態判定に使用。
- `_showRatingSheet` は `sleep_record_screen.dart` の **226 / 416 / 581 行で呼び出し + 796 行で定義**。Task2 で全件を共通 `showWakeupRecordSheet` に置換し定義削除。
- 共通化: `sleep_record_screen.dart:796-853` の `_showRatingSheet`（`current` 引数 + エラーハンドリングあり）を移植元に、新規 `lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart` に `showWakeupRecordSheet(context, ref, {current})` + `wakeupRatingIcon` / `wakeupRatingColor` を公開。
- `records_screen.dart` は現在 `StatefulWidget` → `ConsumerStatefulWidget` へ変更（同期に ref 必要）。`_tabController.addListener` の index 確定時に `setState` を追加し AppBar の同期ボタン出し分けを更新。
- `SleepRecordScreen` は AppBar/Scaffold を撤去し `StatelessWidget` 化、`onRefresh` コールバックを受け取り `RefreshIndicator`+`ListView` を返す（`_syncing`/`_onRefresh` は records 側へ移管）。
- 記録タブへの外部遷移は `MainScreen._navigateToRecordsTab(int)`（`main_screen.dart:43-48`）→ `RecordsScreen(initialTabIndex:)`。ホームの睡眠行は `onNavigateToRecordsTab(4)`。ノート(旧4→新5)への外部遷移は現状無い（Task5 で grep 再確認）。

## 実装方針

- **実装は全てサブエージェント委託**（flutter-ui / riverpod）。マネージャーは計画・指示・レビュー・QA のみ。
- UI 部分はモック確定後に着手（ユーザー指示）。
- 各タスク完了ごとに `fvm flutter analyze` で lint 通過を確認し 1 コミット。最後に `fvm flutter test` + `ios-simulator-qa`。

## 未コミットの作業ツリー状態（注意）

- `fit-connect-mobile/pubspec.lock` に差分（M）あり。**睡眠タスクとは無関係**なので今回のコミットには含めない。
- `fit-connect-mobile/.fvm/` は untracked。
- 上記2ファイルとこのメモ・設計書・計画書以外に、睡眠タスクのソース変更はまだ無い（実装未着手）。
