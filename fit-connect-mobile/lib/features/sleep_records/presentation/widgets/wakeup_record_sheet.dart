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
  var saving = false;
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
                if (saving) return;
                saving = true;
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
                  saving = false;
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
