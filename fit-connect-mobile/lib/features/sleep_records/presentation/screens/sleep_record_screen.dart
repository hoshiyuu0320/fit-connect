import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_empty_state.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_history_list_item.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_summary_card.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_sync_status.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_week_chart.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録タブの「睡眠」サブタブの本文。
///
/// 見出し・サブタブ・同期ボタンは記録タブの枠（`RecordsScreen`）が持つ。この画面は本文だけ。
/// 並びは正本 `record-screens.js` の `SleepTab`:
/// 同期の状態（最終同期 / 同期できなかった警告）→ 昨夜の睡眠 → 直近7日間 → 履歴。
/// 同期できなかったときも、取得済みの値は消さず下に表示し続ける。
/// 取得できなかった日は「未取得」と出し、0 とは表示しない。
class SleepRecordScreen extends ConsumerWidget {
  /// 引っぱって更新（pull-to-refresh）と「再試行」で呼ばれる同期処理。
  /// 記録タブのサブタブとして埋め込む際に、記録タブ側の同期処理を渡す。
  /// null の場合は RefreshIndicator を付けず、「再試行」も出さない。
  final Future<void> Function()? onRefresh;

  const SleepRecordScreen({super.key, this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    final today = ref.watch(todaySleepRecordProvider);
    final history = ref.watch(sleepRecordsProvider());
    final settings = ref.watch(healthSettingsProvider).valueOrNull;

    // 今日の記録も履歴も無いと分かったときだけ「まだ記録がありません」にする
    final noRecordsAtAll = today.hasValue &&
        today.value == null &&
        history.hasValue &&
        (history.value ?? const <SleepRecord>[]).isEmpty;

    // 睡眠の連携が有効なときだけ、睡眠の同期の状態（最終同期 / 失敗の警告）を出す
    final retry = onRefresh;
    final status = SleepSyncStatus.fromSettings(
      settings,
      onRetry: retry == null ? null : () => unawaited(retry()),
    );

    const gap = SizedBox(height: AppSpacing.cardGap);

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // 上の余白（サブタブとの間 16）は記録タブの枠が空ける。
      // 下は、下部ナビぶん（MediaQuery の下余白）を自分で受け取る
      padding: EdgeInsets.fromLTRB(
        horizontal,
        0,
        horizontal,
        MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (!status.isEmpty) ...[status, gap],
        if (noRecordsAtAll)
          SleepEmptyState(
            onOpenHealthSettings: () => _openHealthSettings(context),
            onRecordWakeup: () => showWakeupRecordSheet(context, ref),
          )
        else ...[
          const _SummarySection(),
          gap,
          const _WeekSection(),
          gap,
          const _HistorySection(),
        ],
      ],
    );
    if (retry == null) return list;
    return RefreshIndicator(onRefresh: retry, child: list);
  }

  void _openHealthSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HealthSettingsScreen()),
    );
  }
}

// ===== 昨夜の睡眠 =====

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todaySleepRecordProvider);
    return today.when(
      loading: () => const SleepSummaryLoadingCard(),
      error: (_, __) => FcStateMessage.error(
        title: '読み込めませんでした',
        actionLabel: '再試行',
        onAction: () => ref.invalidate(todaySleepRecordProvider),
      ),
      data: (record) {
        if (record == null) {
          return SleepSummaryEmptyCard(
            onRecordWakeup: () => showWakeupRecordSheet(context, ref),
          );
        }
        return SleepSummaryCard(
          record: record,
          onEditWakeup: () => showWakeupRecordSheet(
            context,
            ref,
            current: record.wakeupRating,
          ),
        );
      },
    );
  }
}

// ===== 直近7日間 =====

class _WeekSection extends ConsumerWidget {
  const _WeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSleepRecordsProvider());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        recent.when(
          data: (records) {
            final summary = SleepWeekSummary.from(
              SleepWeekChart.entriesFrom(records),
            );
            final average = summary.averageMinutes;
            return FcSectionTitle(
              '直近7日間',
              note:
                  average == null ? null : '平均 ${formatSleepDuration(average)}',
            );
          },
          loading: () => const FcSectionTitle('直近7日間'),
          error: (_, __) => const FcSectionTitle('直近7日間'),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        recent.when(
          loading: () => const _WeekLoadingCard(),
          error: (_, __) => FcStateMessage.error(
            title: '読み込めませんでした',
            actionLabel: '再試行',
            onAction: () => ref.invalidate(recentSleepRecordsProvider),
          ),
          data: (records) => FcCard(
            child: SleepWeekChart(entries: SleepWeekChart.entriesFrom(records)),
          ),
        ),
      ],
    );
  }
}

/// 読み込み中の「直近7日間」カード（棒と補足の配置を保つ）
class _WeekLoadingCard extends StatelessWidget {
  const _WeekLoadingCard();

  /// 仮の棒の高さ（見た目だけ。値ではない）
  static const List<double> _heights = [56, 64, 40, 60, 66, 52, 70];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < _heights.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FcSkeleton(
                          width: 28,
                          height: _heights[i],
                          radius: 7,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const FcSkeleton.line(width: 200),
          ],
        ),
      ),
    );
  }
}

// ===== 履歴 =====

class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(sleepRecordsProvider());

    return list.when(
      loading: () => const _HistoryFrame(
        child: FcRowsCard(
          children: [
            _HistorySkeletonRow(),
            _HistorySkeletonRow(),
            _HistorySkeletonRow(),
          ],
        ),
      ),
      error: (_, __) => _HistoryFrame(
        child: FcStateMessage.error(
          title: '読み込めませんでした',
          actionLabel: '再試行',
          onAction: () => ref.invalidate(sleepRecordsProvider),
        ),
      ),
      data: (records) {
        // 履歴がまったく無いときの案内は画面の先頭（SleepEmptyState）が出す
        if (records.isEmpty) return const SizedBox.shrink();
        final now = DateTime.now();
        return _HistoryFrame(
          child: FcRowsCard(
            children: [
              for (final record in records)
                SleepHistoryListItem(record: record, now: now),
            ],
          ),
        );
      },
    );
  }
}

/// 見出し「履歴」＋ 本文（見出しの下はカード間隔 16）
class _HistoryFrame extends StatelessWidget {
  final Widget child;
  const _HistoryFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FcSectionTitle('履歴'),
        const SizedBox(height: AppSpacing.cardGap),
        child,
      ],
    );
  }
}

/// 読み込み中の履歴の行（日付・補足・値の帯。最小高さ 52・縦余白 12 で行の高さを保つ）
class _HistorySkeletonRow extends StatelessWidget {
  const _HistorySkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FcSkeleton.line(width: 120),
                    SizedBox(height: AppSpacing.xs),
                    FcSkeleton.line(width: 168, height: 12),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.md),
              FcSkeleton(width: 64, height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================
// プレビュー（Riverpod はダミーのデータで上書きして画面ごと出す）
// =====================================

class _PreviewSleepRecords extends SleepRecords {
  _PreviewSleepRecords(this._records);
  final Future<List<SleepRecord>> _records;

  @override
  Future<List<SleepRecord>> build({int limit = 30}) => _records;
}

class _PreviewHealthSettings extends HealthSettings {
  _PreviewHealthSettings(this._state);
  final HealthSettingsState _state;

  @override
  Future<HealthSettingsState> build() async => _state;
}

/// 今日から [daysAgo] 日前の記録（HealthKit 由来）
SleepRecord _previewRecord(
  int daysAgo,
  int? total, {
  WakeupRating? rating,
  SleepSource source = SleepSource.healthkit,
}) {
  final created = DateTime.now();
  return SleepRecord(
    id: 'preview-$daysAgo',
    clientId: 'preview-client',
    recordedDate: jstDateKeyDaysAgo(daysAgo),
    bedTime: total == null
        ? null
        : DateTime(
            created.year, created.month, created.day - daysAgo - 1, 23, 30),
    wakeTime: total == null
        ? null
        : DateTime(created.year, created.month, created.day - daysAgo, 7, 20),
    totalSleepMinutes: total,
    deepMinutes: total == null ? null : 85,
    lightMinutes: total == null ? null : 255,
    remMinutes: total == null ? null : 110,
    awakeMinutes: total == null ? null : 20,
    wakeupRating: rating,
    source: source,
    createdAt: created,
    updatedAt: created,
  );
}

/// 正本のサンプル（昨夜 7時間30分・直近7日・9/9 に当たる日は未取得・履歴に手動の記録のみの日）
List<SleepRecord> _previewRecords() => [
      _previewRecord(0, 450, rating: WakeupRating.refreshed),
      _previewRecord(1, 410, rating: WakeupRating.okay),
      _previewRecord(2, 420, rating: WakeupRating.refreshed),
      _previewRecord(3, 390),
      _previewRecord(4, null,
          rating: WakeupRating.groggy, source: SleepSource.manual),
      _previewRecord(5, 430, rating: WakeupRating.okay),
      _previewRecord(6, 410, rating: WakeupRating.refreshed),
    ];

HealthSettingsState _previewSettings({required bool failed}) {
  final synced = DateTime.now();
  return HealthSettingsState(
    isEnabled: true,
    isWeightEnabled: true,
    isSleepEnabled: true,
    isMorningDialogEnabled: true,
    lastSyncAt: DateTime(synced.year, synced.month, synced.day, 7, 32),
    lastSyncStatus: failed ? HealthSyncStatus.error : HealthSyncStatus.success,
    lastSyncError: failed ? '睡眠: timeout' : null,
  );
}

Widget _previewScreen({
  Brightness brightness = Brightness.light,
  double scale = 1,
  bool failed = false,
  bool empty = false,
  bool loading = false,
}) {
  final records = empty ? <SleepRecord>[] : _previewRecords();
  // 読み込み中は完了しない Future にする（スケルトンのまま止める）
  Future<List<SleepRecord>> pending() => Completer<List<SleepRecord>>().future;

  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: ProviderScope(
          overrides: [
            todaySleepRecordProvider.overrideWith(
              (ref) => loading
                  ? Completer<SleepRecord?>().future
                  : Future.value(records.isEmpty ? null : records.first),
            ),
            recentSleepRecordsProvider().overrideWith(
              (ref) => loading ? pending() : Future.value(records),
            ),
            sleepRecordsProvider().overrideWith(
              () => _PreviewSleepRecords(
                  loading ? pending() : Future.value(records)),
            ),
            healthSettingsProvider.overrideWith(
              () => _PreviewHealthSettings(_previewSettings(failed: failed)),
            ),
          ],
          child: SleepRecordScreen(onRefresh: () async {}),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepRecordScreen - 通常（ライト）')
Widget previewSleepRecordScreenLight() => _previewScreen();

@Preview(name: 'SleepRecordScreen - 通常（ダーク）')
Widget previewSleepRecordScreenDark() =>
    _previewScreen(brightness: Brightness.dark);

@Preview(name: 'SleepRecordScreen - 文字拡大 1.35')
Widget previewSleepRecordScreenLarge() => _previewScreen(scale: 1.35);

@Preview(name: 'SleepRecordScreen - 同期できない（取得済みの値を表示）')
Widget previewSleepRecordScreenSyncFailed() => _previewScreen(failed: true);

@Preview(name: 'SleepRecordScreen - 記録なし')
Widget previewSleepRecordScreenEmpty() => _previewScreen(empty: true);

@Preview(name: 'SleepRecordScreen - 読込中')
Widget previewSleepRecordScreenLoading() => _previewScreen(loading: true);
