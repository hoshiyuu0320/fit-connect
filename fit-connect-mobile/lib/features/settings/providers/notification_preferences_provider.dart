import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'notification_preferences_provider.g.dart';

/// 通知種別（notification_preferences.kind に対応）
enum NotificationKind {
  message('message'),
  goalAchievement('goal_achievement');

  const NotificationKind(this.value);

  /// DB上の kind 値
  final String value;
}

/// 通知種別ごとのON/OFF状態
///
/// notification_preferences に行が無い種別は「有効（デフォルトON）」として扱う
class NotificationPreferencesState {
  final bool messageEnabled;
  final bool goalAchievementEnabled;

  const NotificationPreferencesState({
    this.messageEnabled = true,
    this.goalAchievementEnabled = true,
  });

  bool isEnabled(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.message:
        return messageEnabled;
      case NotificationKind.goalAchievement:
        return goalAchievementEnabled;
    }
  }

  NotificationPreferencesState copyWith({
    bool? messageEnabled,
    bool? goalAchievementEnabled,
  }) =>
      NotificationPreferencesState(
        messageEnabled: messageEnabled ?? this.messageEnabled,
        goalAchievementEnabled:
            goalAchievementEnabled ?? this.goalAchievementEnabled,
      );
}

/// 通知設定の状態管理
///
/// notification_preferences テーブルを RLS 経由（本人行のみ）で select/upsert する
@riverpod
class NotificationPreferences extends _$NotificationPreferences {
  @override
  Future<NotificationPreferencesState> build() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      return const NotificationPreferencesState();
    }

    final rows = await SupabaseService.client
        .from('notification_preferences')
        .select('kind, enabled')
        .eq('user_id', userId);

    var prefs = const NotificationPreferencesState();
    for (final row in rows) {
      final enabled = row['enabled'] as bool? ?? true;
      switch (row['kind'] as String?) {
        case 'message':
          prefs = prefs.copyWith(messageEnabled: enabled);
        case 'goal_achievement':
          prefs = prefs.copyWith(goalAchievementEnabled: enabled);
      }
    }
    return prefs;
  }

  /// 種別トグルの切替（行が無ければ作成、あれば enabled を更新）
  Future<void> setEnabled(NotificationKind kind, bool enabled) async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('ログイン情報を取得できませんでした');
    }

    await SupabaseService.client.from('notification_preferences').upsert(
      {
        'user_id': userId,
        'kind': kind.value,
        'enabled': enabled,
      },
      onConflict: 'user_id,kind',
    );

    final current = state.valueOrNull ?? const NotificationPreferencesState();
    switch (kind) {
      case NotificationKind.message:
        state = AsyncData(current.copyWith(messageEnabled: enabled));
      case NotificationKind.goalAchievement:
        state = AsyncData(current.copyWith(goalAchievementEnabled: enabled));
    }
  }
}
