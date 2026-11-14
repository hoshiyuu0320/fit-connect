import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';

/// 呼ばれた操作を記録するだけの RecordReminderSync（端末の予約・Supabase には触れない）。
///
/// `recordReminderSyncProvider.overrideWithValue(FakeRecordReminderSync())` で差し替えて、
/// フック（メッセージの送信・ログアウト・設定の変更・ワークアウト）が呼んだかを確かめる。
class FakeRecordReminderSync implements RecordReminderSync {
  /// 呼ばれた操作（呼ばれた順。`refresh:<reason>` / `onMessageSent` / `cancelAll`）
  final log = <String>[];

  /// refresh の reason（呼ばれた順）
  final refreshReasons = <String>[];

  /// onMessageSent に渡されたタグ（呼ばれた順）
  final sentTags = <List<String>>[];

  /// cancelAll を呼ばれた回数
  int cancelAllCalls = 0;

  /// 渡すと cancelAll がこの例外を投げる（本物は投げないが、呼び出し側の守りを確かめる）
  Object? cancelAllError;

  /// 渡すと cancelAll が呼ばれたとき（log に足した後・例外を投げる前）に呼ぶ
  /// （呼ばれた時点の状態を確かめる・取り消している間の出来事を作る）
  void Function()? onCancelAll;

  @override
  bool get rescheduleAllOnSignIn => false;

  @override
  Future<void> refresh({required String reason}) async {
    refreshReasons.add(reason);
    log.add('refresh:$reason');
  }

  @override
  void onMessageSent(List<String> tags) {
    sentTags.add(List.of(tags));
    log.add('onMessageSent');
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    log.add('cancelAll');
    onCancelAll?.call();
    final error = cancelAllError;
    if (error != null) throw error;
  }
}
