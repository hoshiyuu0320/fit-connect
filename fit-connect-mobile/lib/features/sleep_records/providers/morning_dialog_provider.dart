import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';

part 'morning_dialog_provider.g.dart';

const _kDismissedDateKey = 'morning_dialog_dismissed_date';

/// 朝ダイアログの表示判定（純粋関数、テスト容易性のため分離）
/// 条件:
/// - 4:00 <= now.hour < 12:00
/// - morningDialogEnabled == true
/// - hasWakeupRatingToday == false
/// - dismissedDate != todayKey
bool shouldShowMorningDialog({
  required DateTime now,
  required bool morningDialogEnabled,
  required bool hasWakeupRatingToday,
  required String? dismissedDate,
  required String todayKey,
}) {
  if (!morningDialogEnabled) return false;
  if (hasWakeupRatingToday) return false;
  if (dismissedDate == todayKey) return false;
  if (now.hour < 4 || now.hour >= 12) return false;
  return true;
}

/// 朝ダイアログ表示制御 Provider
@riverpod
class MorningDialog extends _$MorningDialog {
  @override
  Future<bool> build() async {
    final settings = await ref.watch(healthSettingsProvider.future);

    final today = await ref.watch(todaySleepRecordProvider.future);
    final hasRating = today?.wakeupRating != null;

    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_kDismissedDateKey);

    return shouldShowMorningDialog(
      now: DateTime.now(),
      morningDialogEnabled: settings.isMorningDialogEnabled,
      hasWakeupRatingToday: hasRating,
      dismissedDate: dismissed,
      todayKey: todayJstDateKey(),
    );
  }

  /// 「今日は聞かない」選択時: 当日dismiss記録
  Future<void> dismissToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedDateKey, todayJstDateKey());
    ref.invalidateSelf();
  }
}
