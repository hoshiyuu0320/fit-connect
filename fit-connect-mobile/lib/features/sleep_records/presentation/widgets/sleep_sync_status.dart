import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 睡眠タブの上部に出す同期の状態。正本 `record-screens.js` の `SleepTab` の先頭。
///
/// - 同期できたとき: caption「最終同期 9月13日（日）7:32」（最終同期の日時が分かるときだけ）
/// - 同期できなかったとき（[failed]）: 警告の囲み（再試行つき）
///   「HealthKitと同期できませんでした。9月13日（日）7:32 に取得した値を表示しています。」
///   **取得済みの値は消さず、下に表示し続ける**（この部品は値を持たない。画面側が値を出し続ける）。
///   最後に取得できた日時が分からないときは日時の文を省く（日時を捏造しない）
/// - 再試行の操作は [onRetry] があるときだけ出す
class SleepSyncStatus extends StatelessWidget {
  /// 最後に同期できた日時（null = 分からない）
  final DateTime? lastSyncAt;

  /// 直近の同期が失敗した
  final bool failed;

  /// 「再試行」を押したとき。null なら再試行の操作を出さない
  final VoidCallback? onRetry;

  /// 年の付与判定に使う現在時刻（省略時は今）
  final DateTime? now;

  const SleepSyncStatus({
    super.key,
    required this.lastSyncAt,
    this.failed = false,
    this.onRetry,
    this.now,
  });

  /// 同期失敗の文言
  static String failureMessage(DateTime? lastSyncAt, {DateTime? now}) {
    const head = 'HealthKitと同期できませんでした。';
    if (lastSyncAt == null) return head;
    final at = formatSleepDateTime(lastSyncAt, now: now ?? DateTime.now());
    return '$head$at に取得した値を表示しています。';
  }

  /// 睡眠タブに出す同期の状態を、ヘルスケア連携の設定から作る。
  ///
  /// 睡眠の連携が有効なとき（マスターと睡眠の両方がオン）だけ出す。体重だけの連携・
  /// 体重だけの失敗は睡眠タブに関係ないので出さない（無効なら何も出さない）。
  /// 再試行は [onRetry]（null なら出さない）
  factory SleepSyncStatus.fromSettings(
    HealthSettingsState? settings, {
    VoidCallback? onRetry,
  }) {
    final active =
        settings != null && settings.isEnabled && settings.isSleepEnabled;
    if (!active) return const SleepSyncStatus(lastSyncAt: null);
    return SleepSyncStatus(
      lastSyncAt: settings.lastSyncAt,
      failed: sleepSyncFailed(settings),
      onRetry: onRetry,
    );
  }

  /// 直近の同期で**睡眠**が失敗したか。
  ///
  /// 同期の失敗は `lastSyncError` に「体重: …」「睡眠: …」を ` / ` でつないで残る
  /// （`HealthSync`）。「睡眠:」の項目があるときだけ失敗とみなす。体重だけの失敗では false。
  /// 失敗なのに理由が残っていないときは、分からないので失敗として扱う。
  static bool sleepSyncFailed(HealthSettingsState settings) {
    if (settings.lastSyncStatus != HealthSyncStatus.error) return false;
    final error = settings.lastSyncError;
    if (error == null || error.isEmpty) return true;
    return error.split(' / ').any((part) => part.trim().startsWith('睡眠:'));
  }

  /// 何も出すものが無いか（呼び出し側が余白を空けるかどうかの判定に使う）
  bool get isEmpty => !failed && lastSyncAt == null;

  @override
  Widget build(BuildContext context) {
    final reference = now ?? DateTime.now();

    if (failed) {
      return FcInlineNotice.warning(
        message: failureMessage(lastSyncAt, now: reference),
        actionLabel: onRetry == null ? null : '再試行',
        onAction: onRetry,
      );
    }
    final synced = lastSyncAt;
    if (synced == null) return const SizedBox.shrink();

    return Padding(
      // 正本: caption の左右 4
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        '最終同期 ${formatSleepDateTime(synced, now: reference)}',
        style: AppTextStyles.caption(context),
      ),
    );
  }
}

// =====================================
// プレビュー
// =====================================

Widget _previewStatus({
  required Brightness brightness,
  required Widget status,
  double scale = 1,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl), child: status),
      ),
    ),
  );
}

final DateTime _syncedAt = DateTime(2026, 9, 13, 7, 32);

@Preview(name: 'SleepSyncStatus - 最終同期')
Widget previewSleepSyncStatusSynced() => _previewStatus(
      brightness: Brightness.light,
      status:
          SleepSyncStatus(lastSyncAt: _syncedAt, now: DateTime(2026, 9, 13)),
    );

@Preview(name: 'SleepSyncStatus - 同期できない（ライト）')
Widget previewSleepSyncStatusFailed() => _previewStatus(
      brightness: Brightness.light,
      status: SleepSyncStatus(
        lastSyncAt: _syncedAt,
        failed: true,
        onRetry: () {},
        now: DateTime(2026, 9, 13),
      ),
    );

@Preview(name: 'SleepSyncStatus - 同期できない（ダーク）')
Widget previewSleepSyncStatusFailedDark() => _previewStatus(
      brightness: Brightness.dark,
      status: SleepSyncStatus(
        lastSyncAt: _syncedAt,
        failed: true,
        onRetry: () {},
        now: DateTime(2026, 9, 13),
      ),
    );

@Preview(name: 'SleepSyncStatus - 同期できない（文字拡大 1.35）')
Widget previewSleepSyncStatusFailedLarge() => _previewStatus(
      brightness: Brightness.light,
      scale: 1.35,
      status: SleepSyncStatus(
        lastSyncAt: _syncedAt,
        failed: true,
        onRetry: () {},
        now: DateTime(2026, 9, 13),
      ),
    );
