import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';

enum _SleepCardState { healthkit, manual, empty }

/// ホーム画面に置く睡眠サマリーカード（3状態+ローディング対応）
class SleepSummaryCard extends ConsumerWidget {
  /// カード全体タップ時（通常: SleepRecordScreen への遷移）
  final VoidCallback? onTap;

  const SleepSummaryCard({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todaySleepRecordProvider);
    return today.when(
      loading: () => const _CardShell(
        onTap: null,
        child: _LoadingBody(),
      ),
      error: (_, __) => _CardShell(
        onTap: onTap,
        child: _ErrorBody(onRetry: () {
          ref.invalidate(todaySleepRecordProvider);
        }),
      ),
      data: (record) {
        final state = _resolveState(record);
        return _CardShell(
          onTap: onTap,
          child: _Body(
            state: state,
            record: record,
            onEmptyCta: () => _showRecordSheet(context, ref),
          ),
        );
      },
    );
  }

  static _SleepCardState _resolveState(SleepRecord? r) {
    if (r == null) return _SleepCardState.empty;
    return r.hasObjectiveData ? _SleepCardState.healthkit : _SleepCardState.manual;
  }

  Future<void> _showRecordSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: _RecordSheet(
          onRated: (rating) async {
            await ref.read(sleepRecordsProvider().notifier).upsertWakeupRating(
                  recordedDate: todayJstDateKey(),
                  rating: rating,
                );
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('記録しました')),
              );
            }
          },
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _CardShell({this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final _SleepCardState state;
  final SleepRecord? record;
  final VoidCallback onEmptyCta;
  const _Body({
    required this.state,
    required this.record,
    required this.onEmptyCta,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 共通ヘッダー
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.accentIndigo,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    LucideIcons.moon,
                    size: 15,
                    color: AppColors.indigo600,
                  ),
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
            if (state == _SleepCardState.healthkit)
              Icon(LucideIcons.heartPulse, size: 14, color: colors.textHint),
            if (state == _SleepCardState.manual)
              Icon(LucideIcons.edit3, size: 14, color: colors.textHint),
          ],
        ),
        const SizedBox(height: 10),
        if (state == _SleepCardState.healthkit) _HealthkitContent(record: record!),
        if (state == _SleepCardState.manual) _ManualContent(record: record!),
        if (state == _SleepCardState.empty) _EmptyCta(onTap: onEmptyCta),
      ],
    );
  }
}

class _HealthkitContent extends StatelessWidget {
  final SleepRecord record;
  const _HealthkitContent({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final mins = record.totalSleepMinutes!;
    final h = mins ~/ 60;
    final m = mins % 60;
    final bedTime = record.bedTime?.toLocal();
    final wakeTime = record.wakeTime?.toLocal();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: -0.48,
                  height: 1.1,
                ),
                children: [
                  TextSpan(text: '$h'),
                  TextSpan(
                    text: '時間',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  TextSpan(text: '$m'),
                  TextSpan(
                    text: '分',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (bedTime != null && wakeTime != null)
              Text(
                '${_formatHm(bedTime)} → ${_formatHm(wakeTime)}',
                style: TextStyle(fontSize: 12, color: colors.textHint),
              ),
          ],
        ),
        if (record.wakeupRating != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                _ratingIcon(record.wakeupRating!, size: 18),
                const SizedBox(width: 6),
                Text(
                  record.wakeupRating!.labelJa,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ratingColor(record.wakeupRating!),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ManualContent extends StatelessWidget {
  final SleepRecord record;
  const _ManualContent({required this.record});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final rating = record.wakeupRating!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ratingIcon(rating, size: 22),
            const SizedBox(width: 10),
            Text(
              rating.labelJa,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _ratingColor(rating),
                letterSpacing: -0.18,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'タップして詳細を記録',
          style: TextStyle(fontSize: 12, color: colors.textHint),
        ),
      ],
    );
  }
}

class _EmptyCta extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.primary50,
          foregroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text('目覚めを記録する'),
            SizedBox(width: 8),
            Icon(LucideIcons.arrowRight, size: 15),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return SizedBox(
      height: 60,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.textHint),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダー（他状態と統一）
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.accentIndigo,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.moon, size: 15, color: AppColors.indigo600),
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
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(LucideIcons.alertCircle, size: 14, color: colors.textHint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '読み込みに失敗しました',
                style: TextStyle(fontSize: 13, color: colors.textHint),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 13),
              label: const Text('再試行'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecordSheet extends StatefulWidget {
  final ValueChanged<WakeupRating> onRated;
  const _RecordSheet({required this.onRated});

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  WakeupRating? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '目覚めを記録',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        WakeupRatingSelector(
          selected: _selected,
          onSelect: (r) async {
            if (_saving) return;
            setState(() {
              _selected = r;
              _saving = true;
            });
            widget.onRated(r);
          },
        ),
      ],
    );
  }
}

// ===== shared icon/color helpers =====
Widget _ratingIcon(WakeupRating r, {double size = 18}) {
  final icon = switch (r) {
    WakeupRating.refreshed => LucideIcons.smile,
    WakeupRating.okay => LucideIcons.meh,
    WakeupRating.groggy => LucideIcons.frown,
  };
  return Icon(icon, size: size, color: _ratingColor(r));
}

Color _ratingColor(WakeupRating r) {
  return switch (r) {
    WakeupRating.refreshed => AppColors.success,
    WakeupRating.okay => AppColors.warning,
    WakeupRating.groggy => AppColors.error,
  };
}

String _formatHm(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

// =====================================
// プレビュー (静的ヘルパー使用)
// =====================================

class _PreviewCard extends StatelessWidget {
  final _SleepCardState state;
  const _PreviewCard({required this.state});

  @override
  Widget build(BuildContext context) {
    SleepRecord? record;
    final now = DateTime.now();
    if (state == _SleepCardState.healthkit) {
      record = SleepRecord(
        id: '1',
        clientId: 'c',
        recordedDate: '2026-04-19',
        bedTime: DateTime(2026, 4, 18, 23, 45),
        wakeTime: DateTime(2026, 4, 19, 7, 8),
        totalSleepMinutes: 443,
        deepMinutes: 110,
        lightMinutes: 221,
        remMinutes: 88,
        awakeMinutes: 24,
        wakeupRating: WakeupRating.refreshed,
        source: SleepSource.healthkit,
        createdAt: now,
        updatedAt: now,
      );
    } else if (state == _SleepCardState.manual) {
      record = SleepRecord(
        id: '1',
        clientId: 'c',
        recordedDate: '2026-04-19',
        wakeupRating: WakeupRating.refreshed,
        source: SleepSource.manual,
        createdAt: now,
        updatedAt: now,
      );
    }
    return _CardShell(
      onTap: () {},
      child: _Body(
        state: state,
        record: record,
        onEmptyCta: () {},
      ),
    );
  }
}

@Preview(name: 'SleepSummaryCard - HealthKit')
Widget previewSleepSummaryCardHealthkit() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const _PreviewCard(state: _SleepCardState.healthkit),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepSummaryCard - Manual Only')
Widget previewSleepSummaryCardManual() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const _PreviewCard(state: _SleepCardState.manual),
        ),
      ),
    ),
  );
}

@Preview(name: 'SleepSummaryCard - Empty')
Widget previewSleepSummaryCardEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: const _PreviewCard(state: _SleepCardState.empty),
        ),
      ),
    ),
  );
}
