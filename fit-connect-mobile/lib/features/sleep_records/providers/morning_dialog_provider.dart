import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
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

/// 朝ダイアログ判定を安全に読み取る。
/// - 読み取り中は listenManual で購読を保持し、autoDispose による途中破棄を防ぐ
/// - それでも dispose された場合（画面破棄・invalidate 時）や判定不能時は false（表示しない）
Future<bool> readMorningDialogDecision(WidgetRef ref) async {
  final sub = ref.listenManual(morningDialogProvider, (_, __) {});
  try {
    return await ref.read(morningDialogProvider.future);
  } on StateError {
    // dispose during loading: 判定を破棄して非表示扱い
    return false;
  } catch (e) {
    debugPrint('[MorningDialog] 判定読み取りエラー: $e');
    return false;
  } finally {
    sub.close(); // close() は冪等（widget破棄で既にcloseされていても安全）
  }
}

/// 朝ダイアログ表示制御 Provider
@riverpod
class MorningDialog extends _$MorningDialog {
  @override
  Future<bool> build() async {
    // 多層防御: client 未取得（新規登録フロー中・未ログイン等）は表示しない。
    // app.dart 側のガードと合わせて、登録フロー画面への誤表示を防ぐ。
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return false;

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
