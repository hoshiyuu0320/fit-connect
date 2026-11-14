import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';

part 'notification_navigation_provider.g.dart';

/// 通知を押したときに開く先（MainScreen が実行する）
sealed class NotificationNavigationRequest {
  const NotificationNavigationRequest();
}

/// メッセージタブを開き、入力欄に [draft] を入れる（送信はしない）。
/// 例: 体重のリマインダー → `#体重 `
class OpenMessagesWithDraft extends NotificationNavigationRequest {
  const OpenMessagesWithDraft(this.draft);

  final String draft;

  @override
  bool operator ==(Object other) =>
      other is OpenMessagesWithDraft && other.draft == draft;

  @override
  int get hashCode => Object.hash(OpenMessagesWithDraft, draft);

  @override
  String toString() => 'OpenMessagesWithDraft($draft)';
}

/// プランタブを開く（運動のリマインダー）
class OpenPlanTab extends NotificationNavigationRequest {
  const OpenPlanTab();

  @override
  bool operator ==(Object other) => other is OpenPlanTab;

  @override
  int get hashCode => (OpenPlanTab).hashCode;

  @override
  String toString() => 'OpenPlanTab()';
}

/// 通知タップ（NotificationService が payload を分けた type と id）の「開く先」。
///
/// 記録のリマインダー（type = record_reminder、id = 'dinner@202611072000' など）だけを扱う:
/// 体重・食事はメッセージタブを入力欄にタグ入りで、運動はプランタブを開く。
/// それ以外の通知・知らない項目は null（これまでどおり何もしない）
NotificationNavigationRequest? notificationNavigationRequestFor(
  String type,
  String? id,
) {
  if (type != reminderPayloadType) return null;
  final kind = reminderKindFromTapId(id);
  if (kind == null) return null;
  final draft = kind.messageDraft;
  return draft != null ? OpenMessagesWithDraft(draft) : const OpenPlanTab();
}

/// 通知を押したときの「開く先」の要求
///
/// 通知タップの受け口が [request] で置き、MainScreen が監視して実行し、[consume] で消す。
/// MainScreen がまだ無い（起動中・認証待ち）ときは要求が残り、MainScreen が現れたときに実行される。
/// 監視する画面が無い間も消えないよう keepAlive にする
@Riverpod(keepAlive: true)
class NotificationNavigation extends _$NotificationNavigation {
  @override
  NotificationNavigationRequest? build() => null;

  /// 開く先を置く（実行前の要求が残っていれば置き換える）
  void request(NotificationNavigationRequest r) {
    state = r;
  }

  /// 要求を取り出して消す（無ければ null）
  NotificationNavigationRequest? consume() {
    final current = state;
    if (current != null) state = null;
    return current;
  }
}
