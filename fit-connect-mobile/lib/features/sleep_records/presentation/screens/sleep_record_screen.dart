import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_history_list_item.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_stage_bar.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_week_chart.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';

class SleepRecordScreen extends ConsumerStatefulWidget {
  const SleepRecordScreen({super.key});

  @override
  ConsumerState<SleepRecordScreen> createState() => _SleepRecordScreenState();
}

class _SleepRecordScreenState extends ConsumerState<SleepRecordScreen> {
  bool _syncing = false;

  Future<void> _onRefresh() async {
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('睡眠記録'),
        backgroundColor: colors.surface,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _syncing ? null : _onRefresh,
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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          const _SummarySection(),
          const SizedBox(height: 24),
          const _SectionTitle(title: '直近7日間'),
          const SizedBox(height: 8),
          const _WeekSection(),
          const SizedBox(height: 24),
          const _HistorySection(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ===== Summary Section =====

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todaySleepRecordProvider);
    return today.when(
      loading: () => const _SummaryShell(child: _SummaryLoading()),
      error: (e, _) => _SummaryShell(child: _SummaryError(message: '$e')),
      data: (record) {
        if (record == null) {
          return const _SummaryShell(child: _SummaryEmpty());
        }
        if (record.hasObjectiveData) {
          return _SummaryShell(child: _SummaryHealthkit(record: record));
        }
        return _SummaryShell(child: _SummaryManualOnly(record: record));
      },
    );
  }
}

class _SummaryShell extends StatelessWidget {
  final Widget child;
  const _SummaryShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }
}

class _SummaryLoading extends StatelessWidget {
  const _SummaryLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 80,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _SummaryError extends StatelessWidget {
  final String message;
  const _SummaryError({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        '読み込みに失敗しました',
        style: TextStyle(fontSize: 13, color: colors.textHint),
      ),
    );
  }
}

class _SummaryEmpty extends ConsumerWidget {
  const _SummaryEmpty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorsExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.accentIndigo,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                LucideIcons.moon,
                size: 17,
                color: AppColors.indigo600,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '今日の記録はまだありません',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: () => _showRatingSheet(context, ref),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('目覚めを記録する'),
          ),
        ),
      ],
    );
  }
}

class _SummaryHealthkit extends ConsumerWidget {
  final SleepRecord record;
  const _SummaryHealthkit({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorsExtension.of(context);
    final mins = record.totalSleepMinutes!;
    final h = mins ~/ 60;
    final m = mins % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダー
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.moon,
                  size: 15,
                  color: AppColors.indigo600,
                ),
                const SizedBox(width: 8),
                Text(
                  '昨夜の睡眠',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: const [
                  Icon(
                    LucideIcons.heartPulse,
                    size: 11,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'HealthKit',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 大きな時間表示
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              letterSpacing: -0.64,
              height: 1.1,
            ),
            children: [
              TextSpan(text: '$h'),
              TextSpan(
                text: '時間',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              TextSpan(text: '$m'),
              TextSpan(
                text: '分',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 就寝/起床グリッド
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(child: _bedWakeColumn('就寝', record.bedTime, colors)),
              Expanded(child: _bedWakeColumn('起床', record.wakeTime, colors)),
            ],
          ),
        ),
        // ステージバー
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.only(top: 14),
            child: SleepStageBar(
              deepMinutes: record.deepMinutes ?? 0,
              lightMinutes: record.lightMinutes ?? 0,
              remMinutes: record.remMinutes ?? 0,
              awakeMinutes: record.awakeMinutes ?? 0,
            ),
          ),
        ),
        // 目覚め行
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '目覚め',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (record.wakeupRating != null) ...[
                      _ratingIcon(record.wakeupRating!, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        record.wakeupRating!.labelJa,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _ratingColor(record.wakeupRating!),
                        ),
                      ),
                    ] else
                      Text(
                        '未記録',
                        style:
                            TextStyle(fontSize: 13, color: colors.textHint),
                      ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _showRatingSheet(
                    context,
                    ref,
                    current: record.wakeupRating,
                  ),
                  icon: const Icon(LucideIcons.edit3, size: 13),
                  label: const Text('編集'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bedWakeColumn(
    String label,
    DateTime? dt,
    AppColorsExtension colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          dt != null ? _formatHm(dt.toLocal()) : '--:--',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: -0.16,
          ),
        ),
      ],
    );
  }
}

class _SummaryManualOnly extends ConsumerWidget {
  final SleepRecord record;
  const _SummaryManualOnly({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorsExtension.of(context);
    final rating = record.wakeupRating!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.moon,
              size: 15,
              color: AppColors.indigo600,
            ),
            const SizedBox(width: 8),
            Text(
              '昨夜の睡眠',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
            const Spacer(),
            Icon(LucideIcons.edit3, size: 14, color: colors.textHint),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _ratingIcon(rating, size: 32),
            const SizedBox(width: 12),
            Text(
              rating.labelJa,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _ratingColor(rating),
                letterSpacing: -0.22,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '詳細データを取得するにはヘルスケア連携を有効にしてください',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '目覚め',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ratingIcon(rating, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      rating.labelJa,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ratingColor(rating),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () =>
                      _showRatingSheet(context, ref, current: rating),
                  icon: const Icon(LucideIcons.edit3, size: 13),
                  label: const Text('編集'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ===== Week Section =====
class _WeekSection extends ConsumerWidget {
  const _WeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorsExtension.of(context);
    final recent = ref.watch(recentSleepRecordsProvider());

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: recent.when(
        loading: () => const SizedBox(
          height: 140,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => SizedBox(
          height: 60,
          child: Center(
            child: Text(
              '読み込めませんでした',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ),
        ),
        data: (records) {
          // 直近7日のラベルを生成（recordedDate が無い日は null）
          final entries = <DailySleepEntry>[];
          final byDate = {for (final r in records) r.recordedDate: r};
          for (var i = 6; i >= 0; i--) {
            final dateKey = jstDateKeyDaysAgo(i);
            final r = byDate[dateKey];
            final parts = dateKey.split('-');
            final label = '${int.parse(parts[1])}/${int.parse(parts[2])}';
            entries.add(DailySleepEntry(
              dateLabel: label,
              hours: r?.totalSleepMinutes != null
                  ? (r!.totalSleepMinutes! / 60.0)
                  : null,
              rating: r?.wakeupRating,
            ));
          }
          return SleepWeekChart(entries: entries);
        },
      ),
    );
  }
}

// ===== History Section =====
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColorsExtension.of(context);
    final list = ref.watch(sleepRecordsProvider());

    return list.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            '読み込めませんでした',
            style: TextStyle(fontSize: 12, color: colors.textHint),
          ),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return const _HistoryEmpty();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              title: '履歴',
              trailing: Text(
                '${records.length}件',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < records.length; i++) ...[
                    SleepHistoryListItem(record: records[i]),
                    if (i < records.length - 1)
                      Divider(
                        height: 1,
                        color: colors.border,
                        indent: 16,
                        endIndent: 16,
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.accentIndigo,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              LucideIcons.moon,
              size: 28,
              color: AppColors.indigo600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '記録がありません',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ヘルスケア連携を有効にするか、\n目覚めを記録してみましょう',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Helpers =====
Color _ratingColor(WakeupRating r) => switch (r) {
      WakeupRating.refreshed => AppColors.success,
      WakeupRating.okay => AppColors.warning,
      WakeupRating.groggy => AppColors.error,
    };

Widget _ratingIcon(WakeupRating r, {double size = 18}) {
  final icon = switch (r) {
    WakeupRating.refreshed => LucideIcons.smile,
    WakeupRating.okay => LucideIcons.meh,
    WakeupRating.groggy => LucideIcons.frown,
  };
  return Icon(icon, size: size, color: _ratingColor(r));
}

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

Future<void> _showRatingSheet(
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

// =====================================
// プレビュー (静的)
// =====================================

@Preview(name: 'SleepRecordScreen - Static')
Widget previewSleepRecordScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: Center(child: Text('SleepRecordScreen (要 Riverpod 起動環境)')),
    ),
  );
}
