# 睡眠記録を記録タブへ統合 — 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 睡眠記録を記録タブの新サブタブ「睡眠」に移し、ホームでは「今日のまとめ」カードの一行として統合する（独立カードは廃止）。

**Architecture:** UIの再配置が中心でデータ層（Provider / Model / Supabase）は変更しない。記録タブ（`RecordsScreen`）に睡眠サブタブを追加し、HealthKit 同期は記録タブ共通 AppBar の同期ボタン（睡眠タブ選択時のみ）と睡眠サブタブの pull-to-refresh で共有する。寝起き記録ボトムシートは共通関数 `showWakeupRecordSheet()` に抽出し、ホーム・睡眠画面から再利用する。

**Tech Stack:** Flutter（fvm 3.41.9）、Riverpod（コード生成）、Material 3 + AppColors、lucide_icons。

---

## 前提・進め方

- **ブランチ:** `feature/move-sleep-to-records-tab`（作成済み）
- **Flutter コマンドは必ず `fvm flutter` を使う**（このリポジトリは fvm で 3.41.9 にピン留め。`flutter` 直叩きは不可）。作業は `fit-connect-mobile/` ディレクトリで実行。
- **検証方針（TDD 非適用の理由）:** 本タスクは既存ウィジェット/ロジックの再配置であり新規の純粋ロジックがほぼ無い。本リポジトリはウィジェットテストをほぼ持たず、CLAUDE.md は「UI 変更時はプレビュー関数を作る」運用を定めている。よって各タスクの検証は `fvm flutter analyze`（lint 通過）＋必要に応じてプレビュー関数、最後に `ios-simulator-qa` スキルでの動作確認とする。ユニットテストは新規ロジックが出た場合のみ追加。
- **コミット:** 各タスク完了ごとに 1 コミット。
- **コード生成は不要**（`@riverpod` / `@JsonSerializable` の新規追加なし）。

## File Structure

新規:
- `lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart`
  - `showWakeupRecordSheet(context, ref, {current})` — 寝起き評価ボトムシート（共通）
  - `wakeupRatingIcon(rating, {size})` / `wakeupRatingColor(rating)` — 評価アイコン/色の公開ヘルパー

変更:
- `lib/features/sleep_records/presentation/screens/sleep_record_screen.dart` — AppBar/Scaffold を撤去しタブ埋め込み用本体へ。`onRefresh` を受け取り `RefreshIndicator` でラップ。ローカル `_showRatingSheet` を共通関数呼び出しに置換。
- `lib/features/home/presentation/screens/records_screen.dart` — `ConsumerStatefulWidget` 化。睡眠サブタブ追加（`length: 6`）。同期処理 `_onSyncSleep` と AppBar 同期ボタン（睡眠タブ時のみ）。
- `lib/features/home/presentation/widgets/daily_summary_card.dart` — 睡眠行を追加（`onSleepTap` + 状態表示 + 未記録時ミニCTA）。
- `lib/features/home/presentation/screens/home_screen.dart` — 独立睡眠カード削除、`onSleepTap` 配線、タブ index コメント更新。

削除:
- `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart` — ホーム独立カード（統合により不要。内部の `_RecordSheet`/`_ratingIcon`/`_ratingColor` は共通ファイルへ移設済みとなる）。

---

## Task 1: 寝起き記録ボトムシートの共通ウィジェット化

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart`

参照元: `sleep_record_screen.dart:786-853`（`_showRatingSheet`, `_ratingColor`）と `sleep_summary_card.dart:453-468`（`_ratingIcon`, `_ratingColor`）。

- [ ] **Step 1: 新ファイルを作成**

`lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';

/// 寝起きの良さ（WakeupRating）を記録する共通ボトムシート。
///
/// ホーム「今日のまとめ」の睡眠行・睡眠画面の編集導線など、
/// `WakeupRatingSelector` を使う記録 UI を一箇所に集約する。
/// 保存は `sleepRecordsProvider().notifier.upsertWakeupRating` に委譲。
Future<void> showWakeupRecordSheet(
  BuildContext context,
  WidgetRef ref, {
  WakeupRating? current,
}) async {
  WakeupRating? selected = current;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSt) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '目覚めを記録',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            WakeupRatingSelector(
              selected: selected,
              onSelect: (r) async {
                setSt(() => selected = r);
                try {
                  await ref
                      .read(sleepRecordsProvider().notifier)
                      .upsertWakeupRating(
                        recordedDate: todayJstDateKey(),
                        rating: r,
                      );
                  if (sheetCtx.mounted) {
                    Navigator.of(sheetCtx).pop();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('記録しました')),
                      );
                    }
                  }
                } catch (e) {
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text('記録に失敗しました: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// WakeupRating に対応するアイコン。
Icon wakeupRatingIcon(WakeupRating r, {double size = 18}) {
  final icon = switch (r) {
    WakeupRating.refreshed => LucideIcons.smile,
    WakeupRating.okay => LucideIcons.meh,
    WakeupRating.groggy => LucideIcons.frown,
  };
  return Icon(icon, size: size, color: wakeupRatingColor(r));
}

/// WakeupRating に対応する色（ステータスカラー）。
Color wakeupRatingColor(WakeupRating r) {
  return switch (r) {
    WakeupRating.refreshed => AppColors.success,
    WakeupRating.okay => AppColors.warning,
    WakeupRating.groggy => AppColors.error,
  };
}
```

- [ ] **Step 2: lint 通過を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart`
Expected: `No issues found!`（新ファイル単体で解析が通る。未使用警告が出る場合は次タスクで参照されるため、この時点では全体 analyze ではなくファイル指定で確認）

- [ ] **Step 3: コミット**

```bash
git add fit-connect-mobile/lib/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart
git commit -m "feat(mobile): 寝起き記録ボトムシートを共通ウィジェット化"
```

---

## Task 2: SleepRecordScreen をタブ埋め込み用にリファクタ

**Files:**
- Modify: `lib/features/sleep_records/presentation/screens/sleep_record_screen.dart`

ねらい: 専用 AppBar/Scaffold を外し、記録タブのサブタブとして `ListView` を返す。HealthKit 同期の状態と処理は記録タブ側（Task 3）へ移すため、本ウィジェットは `onRefresh` コールバックだけ受け取り `RefreshIndicator` でラップする。

- [ ] **Step 1: import に共通ボトムシートを追加、不要 import を削除**

`sleep_record_screen.dart` 冒頭の import 群（1-14行）を確認。`health_sync_provider` は `_onRefresh` 削除に伴い本ファイルで未使用になるなら削除する（`_SummarySection` 等が使っていない前提。analyze で未使用警告が出たら削除）。共通ボトムシートを追加:

```dart
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
```

- [ ] **Step 2: クラス本体を AppBar 無し・onRefresh 受け取りに置換**

`sleep_record_screen.dart:16-87`（`SleepRecordScreen` クラスと `_SleepRecordScreenState`、`_syncing`/`_onRefresh`/`build`）を、以下で置換:

```dart
class SleepRecordScreen extends StatelessWidget {
  /// 引っぱって更新（pull-to-refresh）で呼ばれる同期処理。
  /// 記録タブのサブタブとして埋め込む際に、記録タブ側の同期処理を渡す。
  /// null の場合は RefreshIndicator を付けない。
  final Future<void> Function()? onRefresh;

  const SleepRecordScreen({super.key, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: const [
        _SummarySection(),
        SizedBox(height: 24),
        _SectionTitle(title: '直近7日間'),
        SizedBox(height: 8),
        _WeekSection(),
        SizedBox(height: 24),
        _HistorySection(),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}
```

注意:
- `flutter/widget_previews.dart` import は末尾のプレビュー関数で使うため残す。
- `lucide_icons` import が本ファイルの他箇所（履歴・サマリ等）で使われていれば残す。`_onRefresh` でしか使っていなければ analyze の指示に従って削除。
- `flutter_riverpod` import は `_SummarySection` 等（ConsumerWidget）が使うため残す。

- [ ] **Step 3: ローカル `_showRatingSheet` を共通関数へ置換**

`sleep_record_screen.dart` 内の `_showRatingSheet(context, ref, current: x)` 呼び出し箇所（サマリの編集導線など複数）を、すべて `showWakeupRecordSheet(context, ref, current: x)` に置換する。
その後、ローカルのトップレベル関数 `_showRatingSheet`（786-853行付近）を**削除**。
また、ローカルのトップレベル `_ratingColor` / `_ratingIcon`（あれば）が本ファイル内の表示でまだ使われている場合は残す（DRY より変更範囲最小を優先。共通版 `wakeupRatingIcon`/`wakeupRatingColor` への全置換は今回スコープ外）。`_formatHm` も使用箇所が残るなら残す。

- [ ] **Step 4: lint 通過を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/sleep_records/presentation/screens/sleep_record_screen.dart`
Expected: `No issues found!`（未使用 import / 未使用関数が残っていれば削除して再実行）

- [ ] **Step 5: コミット**

```bash
git add fit-connect-mobile/lib/features/sleep_records/presentation/screens/sleep_record_screen.dart
git commit -m "refactor(mobile): SleepRecordScreenをタブ埋め込み用本体に変更"
```

---

## Task 3: 記録タブに睡眠サブタブと同期ボタンを追加

**Files:**
- Modify: `lib/features/home/presentation/screens/records_screen.dart`

- [ ] **Step 1: import を追加**

`records_screen.dart` の import 群（1-7行）に追加:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/screens/sleep_record_screen.dart';
```

- [ ] **Step 2: クラスを ConsumerStatefulWidget 化**

`records_screen.dart:9-20` を置換:

```dart
class RecordsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  const RecordsScreen({super.key, this.initialTabIndex = 0, this.onTabChanged});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _syncing = false;

  /// 睡眠サブタブの index（サマリ0/体重1/食事2/運動3/睡眠4/ノート5）
  static const int _sleepTabIndex = 4;
```

- [ ] **Step 3: initState の length と listener を更新**

`records_screen.dart:23-36`（initState）を置換:

```dart
  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged?.call(_tabController.index);
        // 睡眠タブ選択時のみ AppBar の同期ボタンを出すため再ビルド
        setState(() {});
      }
    });
  }
```

- [ ] **Step 4: 同期処理メソッドを追加**

`dispose`（47-50行付近）の直後に追加:

```dart
  Future<void> _onSyncSleep() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ref.read(healthSyncProvider.notifier).syncManual();
      ref.invalidate(sleepRecordsProvider);
      ref.invalidate(todaySleepRecordProvider);
      ref.invalidate(recentSleepRecordsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同期しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同期に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
```

- [ ] **Step 5: AppBar に同期ボタン、TabBar/TabBarView に睡眠を追加**

`records_screen.dart:53-94`（build の `return Scaffold(...)`）を置換:

```dart
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceDim,
      appBar: AppBar(
        title: Text(
          '記録',
          style:
              TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_tabController.index == _sleepTabIndex)
            IconButton(
              onPressed: _syncing ? null : _onSyncSleep,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 18),
              tooltip: '同期',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary600,
          unselectedLabelColor: colors.textHint,
          indicatorColor: AppColors.primary600,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'サマリ'),
            Tab(text: '体重'),
            Tab(text: '食事'),
            Tab(text: '運動'),
            Tab(text: '睡眠'),
            Tab(text: 'ノート'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const RecordsOverviewScreen(),
          const WeightRecordScreen(),
          const MealRecordScreen(),
          const ExerciseRecordScreen(),
          SleepRecordScreen(onRefresh: _onSyncSleep),
          const ClientNotesScreen(),
        ],
      ),
    );
  }
```

注意: `children` は `SleepRecordScreen(onRefresh:)` が非 const のため、リスト全体の `const` を外し各要素に `const` を付ける（上記の通り）。

- [ ] **Step 6: lint 通過を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/home/presentation/screens/records_screen.dart`
Expected: `No issues found!`

- [ ] **Step 7: コミット**

```bash
git add fit-connect-mobile/lib/features/home/presentation/screens/records_screen.dart
git commit -m "feat(mobile): 記録タブに睡眠サブタブと同期ボタンを追加"
```

---

## Task 4: 今日のまとめカードに睡眠行を追加

**Files:**
- Modify: `lib/features/home/presentation/widgets/daily_summary_card.dart`

体重行（`daily_summary_card.dart:375-459`）と同じパターンで睡眠行を追加。状態は `record.hasObjectiveData`（HealthKit）/ `record.wakeupRating != null`（手動評価）/ それ以外（未記録）で分岐。未記録時は行内に「記録」ミニボタンを置き、`showWakeupRecordSheet` を開く（記録タブへは飛ばさない）。

- [ ] **Step 1: import を追加**

`daily_summary_card.dart` の import 群（1-10行）に追加:

```dart
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
```

- [ ] **Step 2: onSleepTap コールバックを追加**

`daily_summary_card.dart:12-22`（フィールドとコンストラクタ）を置換:

```dart
class DailySummaryCard extends ConsumerWidget {
  final VoidCallback? onMealsTap;
  final VoidCallback? onActivityTap;
  final VoidCallback? onWeightTap;
  final VoidCallback? onSleepTap;

  const DailySummaryCard({
    super.key,
    this.onMealsTap,
    this.onActivityTap,
    this.onWeightTap,
    this.onSleepTap,
  });
```

- [ ] **Step 3: build に睡眠 provider の watch と睡眠行を追加**

`daily_summary_card.dart:27-31`（watch 群）の直後に追加:

```dart
    final todaySleepAsync = ref.watch(todaySleepRecordProvider);
```

`daily_summary_card.dart:79-85`（Weight Section の `_buildTappableSection`）の直後、Column の `children` 末尾（`],` の前）に追加:

```dart
          Divider(height: 32, color: colors.surfaceDim),

          // Sleep Section
          _buildTappableSection(
            context: context,
            onTap: onSleepTap,
            child: _buildSleepSection(context, ref, todaySleepAsync),
          ),
```

- [ ] **Step 4: 睡眠行のビルダー群を追加**

`_buildWeightSectionNoData`（531行で `}` 終わり）の直後、クラス閉じ `}`（532行）の前に以下のメソッド群を追加:

```dart
  Widget _buildSleepSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<SleepRecord?> todaySleepAsync,
  ) {
    return todaySleepAsync.when(
      data: (record) {
        if (record == null) return _buildSleepEmpty(context, ref);
        if (record.hasObjectiveData) {
          return _buildSleepHealthkit(context, record);
        }
        if (record.wakeupRating != null) {
          return _buildSleepManual(context, record);
        }
        return _buildSleepEmpty(context, ref);
      },
      loading: () => _buildSleepLoading(context),
      error: (_, __) => _buildSleepEmpty(context, ref),
    );
  }

  Widget _buildSleepLabel(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.indigo100,
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.moon,
              color: AppColors.indigo600, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          '睡眠',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildSleepHealthkit(BuildContext context, SleepRecord record) {
    final colors = AppColors.of(context);
    final mins = record.totalSleepMinutes!;
    final h = mins ~/ 60;
    final m = mins % 60;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSleepLabel(context),
        Text(
          '$h時間$m分',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildSleepManual(BuildContext context, SleepRecord record) {
    final rating = record.wakeupRating!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSleepLabel(context),
        Row(
          children: [
            wakeupRatingIcon(rating, size: 16),
            const SizedBox(width: 6),
            Text(
              rating.labelJa,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: wakeupRatingColor(rating),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSleepEmpty(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSleepLabel(context),
        TextButton(
          onPressed: () => showWakeupRecordSheet(context, ref),
          style: TextButton.styleFrom(
            backgroundColor: AppColors.primary50,
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('記録'),
        ),
      ],
    );
  }

  Widget _buildSleepLoading(BuildContext context) {
    return Row(
      children: [
        _buildSleepLabel(context),
        const Spacer(),
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
```

- [ ] **Step 5: 色トークン（確認済み）**

`AppColors` の indigo 系は `indigo50 / indigo100 / indigo600 / indigo800` が定義済み（`indigo500` は**存在しない**）。本計画では睡眠アイコンに **背景 `indigo100` + アイコン `indigo600`** を使用する（Step4 のコードに反映済み）。追加の対応は不要。

- [ ] **Step 6: 睡眠行のプレビュー関数を追加（任意だが推奨）**

`daily_summary_card.dart` 末尾のプレビュー領域（534行以降）に、睡眠行3状態（healthkit/manual/empty）を確認できる静的プレビューがあれば追加する。既存のプレビュー構造（`_Preview*` ヘルパー）に倣う。Riverpod に依存しない静的ヘルパーで表現できない場合はスキップ可（CLAUDE.md のプレビュー方針に沿い、可能な範囲で）。

- [ ] **Step 7: lint 通過を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/home/presentation/widgets/daily_summary_card.dart`
Expected: `No issues found!`

- [ ] **Step 8: コミット**

```bash
git add fit-connect-mobile/lib/features/home/presentation/widgets/daily_summary_card.dart
git commit -m "feat(mobile): 今日のまとめカードに睡眠行を追加"
```

---

## Task 5: ホーム画面の配線変更（独立カード削除・睡眠行配線）

**Files:**
- Modify: `lib/features/home/presentation/screens/home_screen.dart`

- [ ] **Step 1: 不要 import を削除**

`home_screen.dart:13-14` の2行を削除:

```dart
import 'package:fit_connect_mobile/features/sleep_records/presentation/screens/sleep_record_screen.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_summary_card.dart';
```

- [ ] **Step 2: タブ index コメントと DailySummaryCard 配線を更新**

`home_screen.dart:70-81` を置換:

```dart
              // Daily Summary
              // Records tabs order: 0=サマリ, 1=体重, 2=食事, 3=運動, 4=睡眠, 5=ノート
              DailySummaryCard(
                onMealsTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(2)
                    : null,
                onWeightTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(1)
                    : null,
                onActivityTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(3)
                    : null,
                onSleepTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(4)
                    : null,
              ),
```

- [ ] **Step 3: 独立した睡眠カードのブロックを削除**

`home_screen.dart:83-92`（`const SizedBox(height: 16),` と `// Sleep summary` コメント、`SleepSummaryCard(...)` ブロック）を削除する。削除後は DailySummaryCard の直後が `const SizedBox(height: 100), // Bottom padding for FAB/Nav` になる。

- [ ] **Step 4: ノート(旧index4→新5)への外部遷移が無いか確認**

Run: `cd fit-connect-mobile && grep -rnE 'onNavigateToRecordsTab!?\(4\)|_navigateToRecordsTab\(4\)|initialTabIndex: 4' lib/`
Expected: 今回追加した `home_screen.dart` の睡眠行（`onNavigateToRecordsTab!(4)`）以外に、旧「ノート=4」を意図した遷移呼び出しが**無い**こと。もし他にノートを index 4 で開く箇所があれば 5 に修正する（調査時点ではホームからのノート遷移は存在しない）。

- [ ] **Step 5: lint 通過を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze lib/features/home/presentation/screens/home_screen.dart`
Expected: `No issues found!`

- [ ] **Step 6: コミット**

```bash
git add fit-connect-mobile/lib/features/home/presentation/screens/home_screen.dart
git commit -m "feat(mobile): ホームの睡眠カードを今日のまとめに統合"
```

---

## Task 6: 旧 SleepSummaryCard を削除

**Files:**
- Delete: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart`

- [ ] **Step 1: 参照が無いことを確認**

Run: `cd fit-connect-mobile && grep -rn 'sleep_summary_card\|SleepSummaryCard' lib/ test/`
Expected: 出力なし（Task 5 で home_screen からの参照を削除済み）。もし残っていれば先に解消する。

- [ ] **Step 2: ファイルを削除**

```bash
git rm fit-connect-mobile/lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart
```

- [ ] **Step 3: 全体 lint を確認**

Run: `cd fit-connect-mobile && fvm flutter analyze`
Expected: `No issues found!`（プロジェクト全体。未使用 import 等の積み残しがあればここで解消）

- [ ] **Step 4: コミット**

```bash
git commit -m "chore(mobile): 統合により不要になったSleepSummaryCardを削除"
```

---

## Task 7: ビルド確認とシミュレータ QA

**Files:** なし（検証のみ）

- [ ] **Step 1: 既存テストが壊れていないか確認**

Run: `cd fit-connect-mobile && fvm flutter test`
Expected: 全テスト pass（睡眠の `sleep_date_utils_test` / `morning_dialog_shouldshow_test` 含む。UI 再配置なので影響しない想定）。

- [ ] **Step 2: デバッグビルドが通るか確認**

Run: `cd fit-connect-mobile && fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: シミュレータ動作確認（ios-simulator-qa スキル）**

`ios-simulator-qa` スキルを実行し、以下を確認:
1. 記録タブを開くと `サマリ / 体重 / 食事 / 運動 / 睡眠 / ノート` の順でサブタブが並ぶ
2. 睡眠サブタブで、AppBar 右上に同期アイコンが表示される（他サブタブでは非表示）
3. 睡眠サブタブを引っぱって更新（pull-to-refresh）できる
4. ホーム「今日のまとめ」に睡眠行が表示される（独立カードは消えている）
5. 睡眠行（未記録時）の「記録」ボタンでボトムシートが開き、評価を保存でき、その場で完結する（記録タブに飛ばない）
6. 睡眠行の他領域タップで記録タブの睡眠サブタブへ遷移する
7. 朝の自動起床ダイアログは従来どおり動作する（リグレッション無し）

- [ ] **Step 4: ドキュメント更新**

`fit-connect-mobile/docs/tasks/IMPLEMENTATION_TASKS.md` に本タスクの完了を記録。学びがあれば `fit-connect-mobile/docs/tasks/lessons.md` に追記。

```bash
git add fit-connect-mobile/docs/tasks/
git commit -m "docs(mobile): 睡眠記録の記録タブ統合を記録"
```

---

## Self-Review（計画作成者によるチェック結果）

**1. Spec coverage（design ①〜⑥との対応）:**
- ① 睡眠サブタブ新設（index 4、ノート→5） → Task 3 ✅
- ② 同期ボタン移設（AppBar 睡眠タブ時のみ + pull-to-refresh、処理共有） → Task 2（RefreshIndicator）+ Task 3（AppBar ボタン・`_onSyncSleep`）✅
- ③ 今日のまとめへ統合（独立カード廃止、睡眠行追加） → Task 4 + Task 5 + Task 6 ✅
- ④ 睡眠行タップ挙動（行=記録タブ遷移、未記録時ミニCTA=ホーム完結） → Task 4（`_buildSleepEmpty` の記録ボタン）+ Task 5（`onSleepTap`）✅
- ⑤ スコープ外（朝ダイアログ・Provider/Model/テーブル不変） → 触っていない。Task 7 Step3-7 でリグレッション確認 ✅
- ⑥ QA（ios-simulator-qa） → Task 7 ✅
- ボトムシート共通化 → Task 1 + Task 2 ✅

**2. Placeholder scan:** 各 Step に実コードまたは実コマンドを記載。プレースホルダー無し。Task 4 Step6（プレビュー）と Task 5 Step4（index 確認）は条件付き作業として明示済み。

**3. Type consistency:**
- `showWakeupRecordSheet(BuildContext, WidgetRef, {WakeupRating? current})` — Task 1 定義、Task 2・Task 4 で同一シグネチャ使用 ✅
- `wakeupRatingIcon(WakeupRating, {double size})` / `wakeupRatingColor(WakeupRating)` — Task 1 定義、Task 4 使用 ✅
- `SleepRecordScreen({Future<void> Function()? onRefresh})` — Task 2 定義、Task 3 で `SleepRecordScreen(onRefresh: _onSyncSleep)` 使用 ✅
- `_onSyncSleep()` → `Future<void>` — Task 3 定義、`onRefresh`（`Future<void> Function()`）に渡して型一致 ✅
- `record.hasObjectiveData` / `record.totalSleepMinutes` / `record.wakeupRating` / `WakeupRating.labelJa` — 既存 model のメンバ（Task 4 で使用）✅

**確認済み事項（計画作成時に grep で検証）:**
- 色トークン: `indigo100`（背景）+ `indigo600`（アイコン）を使用。`indigo500` は不在のため不使用。
- `record.hasObjectiveData` getter は `sleep_record_model.dart:91`（`totalSleepMinutes != null`）に存在。
- `_showRatingSheet` 呼び出しは3箇所（`sleep_record_screen.dart:226, 416, 581`）+ 定義（796）。Task 2 Step3 で全件を `showWakeupRecordSheet` に置換し、定義を削除する。
