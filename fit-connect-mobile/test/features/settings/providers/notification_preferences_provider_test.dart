import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/settings/providers/notification_preferences_provider.dart';

/// 通知設定の種別・状態のテスト。
///
/// build()/setEnabled() は SupabaseService.client を直接叩くためここでは触らず、
/// 種別の DB 値と、それぞれの楽観更新に使う State の遷移だけを検証する。
void main() {
  group('NotificationKind', () {
    test('value が notification_preferences.kind の文字列と一致する', () {
      // DB の CHECK 制約・ディスパッチャ（push.ts）の kind と共有する固定値
      expect(NotificationKind.message.value, 'message');
      expect(NotificationKind.goalAchievement.value, 'goal_achievement');
      expect(NotificationKind.sessionReminder.value, 'session_reminder');
    });
  });

  group('NotificationPreferencesState', () {
    test('初期値は全種別が有効（行なし＝オプトアウト方式）', () {
      const prefs = NotificationPreferencesState();

      for (final kind in NotificationKind.values) {
        expect(prefs.isEnabled(kind), isTrue, reason: kind.value);
      }
    });

    test('copyWith で該当種別だけが変わる', () {
      const prefs = NotificationPreferencesState();

      final messageOff = prefs.copyWith(messageEnabled: false);
      expect(messageOff.isEnabled(NotificationKind.message), isFalse);
      expect(messageOff.isEnabled(NotificationKind.goalAchievement), isTrue);
      expect(messageOff.isEnabled(NotificationKind.sessionReminder), isTrue);

      final goalOff = prefs.copyWith(goalAchievementEnabled: false);
      expect(goalOff.isEnabled(NotificationKind.message), isTrue);
      expect(goalOff.isEnabled(NotificationKind.goalAchievement), isFalse);
      expect(goalOff.isEnabled(NotificationKind.sessionReminder), isTrue);

      final reminderOff = prefs.copyWith(sessionReminderEnabled: false);
      expect(reminderOff.isEnabled(NotificationKind.message), isTrue);
      expect(reminderOff.isEnabled(NotificationKind.goalAchievement), isTrue);
      expect(reminderOff.isEnabled(NotificationKind.sessionReminder), isFalse);
    });

    test('copyWith は指定しなかった種別の値を引き継ぐ', () {
      const prefs = NotificationPreferencesState(sessionReminderEnabled: false);

      final messageOff = prefs.copyWith(messageEnabled: false);
      expect(messageOff.isEnabled(NotificationKind.message), isFalse);
      expect(messageOff.isEnabled(NotificationKind.sessionReminder), isFalse);
    });
  });
}
