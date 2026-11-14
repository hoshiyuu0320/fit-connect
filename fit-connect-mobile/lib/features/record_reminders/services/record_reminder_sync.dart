import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/data/record_reminder_settings_storage.dart';
import 'package:fit_connect_mobile/features/record_reminders/data/reminder_status_repository.dart';
import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/reminder_notification_scheduler.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'record_reminder_sync.g.dart';

/// 今日（[nowJst] の日本時間の日）すでに記録した項目を読む
/// （ReminderStatusRepository.fetchRecordedToday と同じ形）
typedef RecordedTodayFetcher = Future<Set<ReminderKind>> Function({
  required String clientId,
  required tz.TZDateTime nowJst,
});

/// [fromDateKey]〜[toDateKey]（両端を含む）のうち、未完了のセルフガイドの割り当てがある日付を読む
/// （ReminderStatusRepository.fetchPendingWorkoutDates と同じ形）
typedef PendingWorkoutDatesFetcher = Future<Set<String>> Function({
  required String clientId,
  required String fromDateKey,
  required String toDateKey,
});

/// 「記録済み」を DB で確かめる項目（運動は割り当てで決まるので含まない）
const _recordedKinds = {
  ReminderKind.weight,
  ReminderKind.breakfast,
  ReminderKind.lunch,
  ReminderKind.dinner,
};

/// 記録のリマインダーを予約し直す（設計 §4・§4.1）。
///
/// - [refresh]: 設定・今日の記録・運動の予定日から「あるべき予約」を作り、端末の予約との差分だけを
///   取り消し・予約する（Android の起動・ログイン時は、すべて予約し直す。[rescheduleAllOnSignIn]）。
///   同時には走らせず、走っている間に来た要求は1回にまとめて、走り終えた後に走らせる
/// - [onMessageSent]: 送ったタグから今日記録した項目を推定し、その日のうちは「記録済み」として扱う
///   （記録はサーバーが非同期に作るので、送った直後の DB にはまだ無い）
/// - [cancelAll]: ログアウト時に、リマインダーの予約と表示中の通知をすべて消す
///
/// どれも呼び出し元へ例外を投げない（失敗はログに出すだけ）。
class RecordReminderSync {
  RecordReminderSync({
    required RecordReminderSettingsStorage storage,
    required RecordedTodayFetcher fetchRecordedToday,
    required PendingWorkoutDatesFetcher fetchPendingWorkoutDates,
    required ReminderNotificationScheduler scheduler,
    required String? Function() currentUserId,
    required Future<String?> Function() currentClientId,
    this.rescheduleAllOnSignIn = false,
    tz.TZDateTime Function()? now,
    Future<void> Function()? ensureInitialized,
  })  : _storage = storage,
        _fetchRecordedToday = fetchRecordedToday,
        _fetchPendingWorkoutDates = fetchPendingWorkoutDates,
        _scheduler = scheduler,
        _currentUserId = currentUserId,
        _currentClientId = currentClientId,
        _now = now ?? _nowInJst,
        _ensureInitialized = ensureInitialized ??
            NotificationService.ensureLocalNotificationsInitialized;

  final RecordReminderSettingsStorage _storage;
  final RecordedTodayFetcher _fetchRecordedToday;
  final PendingWorkoutDatesFetcher _fetchPendingWorkoutDates;
  final ReminderNotificationScheduler _scheduler;

  /// auth のユーザー ID（ログインしていなければ null）
  final String? Function() _currentUserId;

  /// クライアント ID（clients の行が無ければ null）
  final Future<String?> Function() _currentClientId;

  /// 今（Asia/Tokyo）
  final tz.TZDateTime Function() _now;

  /// ローカル通知の初期化（時間帯の Asia/Tokyo 固定を含む）
  final Future<void> Function() _ensureInitialized;

  /// [signedInReason] の予約し直しで、端末の予約一覧を信用せず「あるべき予約」をすべて予約し直すか
  /// （Android だけ true。recordReminderSyncProvider が決める）。
  ///
  /// Android の flutter_local_notifications（18.0.1）の予約一覧は OS のアラームではなく、プラグインが
  /// 端末に保存した一覧で、そこから消えるのは鳴ったときと取り消したときだけ。強制停止・バックアップからの
  /// 復元（新しい端末）で OS のアラームが消えても一覧には残るので、差分では「予約済み」のまま、
  /// 次の再起動・アプリの更新まで鳴らない。そこで起動・ログインのたびに1回、すべて予約し直して
  /// アラームを作り直す（同じ ID の予約は、アラームも保存した一覧も置き換わる）。
  /// iOS の一覧は OS の予約そのものなので、差分のままでよい
  final bool rescheduleAllOnSignIn;

  /// ログインしてクライアントが分かったとき（起動時を含む）の予約し直しの理由。
  /// app.dart の _AuthLoadingScreen が、クライアントが分かるたびに1回これで [refresh] する
  static const signedInReason = 'signed_in';

  /// 時間帯は日本時間に固定する（ensureLocalNotificationsInitialized が timezone のデータを読み込む）
  static tz.TZDateTime _nowInJst() =>
      tz.TZDateTime.now(tz.getLocation('Asia/Tokyo'));

  /// 予約し直しが走っているか
  bool _running = false;

  /// 走っている間に来た要求（1回にまとめ、走り終えた後に走らせる）
  _QueuedRefresh? _queued;

  /// [cancelAll] のたびに増やす。走っている予約し直しは、増えていたらそれ以上は予約しない
  int _generation = 0;

  /// 送ったタグから推定した「今日記録した項目」（ユーザー・日本時間の日付が違えば使わない）
  _DayValue<Set<ReminderKind>>? _sentToday;

  /// 最後に読めた「今日記録した項目」「運動の予定日」（DB を読めなかったとき、同じ日なら使う）
  _DayValue<Set<ReminderKind>>? _lastRecordedToday;
  _DayValue<Set<String>>? _lastPendingWorkoutDates;

  /// 予約し直す。直列に走らせ、走っている間に来た要求（何件でも）は、走り終えた後の1回にまとめる。
  ///
  /// 返す Future は、この要求の後に始まった予約し直しが終わったときに完了する。例外は投げない
  Future<void> refresh({required String reason}) {
    if (!_running) return _start({reason});
    final queued = _queued ??= _QueuedRefresh();
    queued.reasons.add(reason);
    return queued.completer.future;
  }

  /// 送ったメッセージのタグ（[tags]）から今日記録した項目を推定し、その日の分を止めて予約し直す
  /// （予約し直しは待たない）。
  ///
  /// 推定はその日（日本時間）のうちだけ使い、DB の結果と合わせる。サーバーが記録を作れなかった場合も
  /// その日の分は止まったまま（送った時点で記録しようとしているので、もう一度は促さない）
  void onMessageSent(List<String> tags) {
    try {
      final kinds = reminderKindsFromTags(tags);
      if (kinds.isEmpty) return;
      final userId = _currentUserId();
      if (userId == null) return;

      final todayKey = jstDateKeyOf(_now());
      final sent = _sentToday;
      _sentToday = _DayValue(userId, todayKey, {
        if (sent != null && sent.isFor(userId, todayKey)) ...sent.value,
        ...kinds,
      });
    } catch (e) {
      debugPrint('[RecordReminderSync] 送った記録の反映エラー: $e');
      return;
    }
    unawaited(refresh(reason: 'message_sent'));
  }

  /// リマインダーの予約と表示中の通知をすべて消し、推定・読めた結果を捨てる（ログアウト時）。
  ///
  /// 走っている予約し直しは、この後は予約しない。例外は投げない
  Future<void> cancelAll() async {
    _generation++;
    try {
      await _cancelAllAndForget();
      debugPrint('[RecordReminderSync] リマインダーの予約と表示中の通知をすべて消しました');
    } catch (e) {
      debugPrint('[RecordReminderSync] リマインダーの取り消しエラー: $e');
    }
  }

  /// [reasons] は、まとめた要求の理由（1件以上）
  Future<void> _start(Set<String> reasons) async {
    _running = true;
    try {
      await _run(reasons);
    } finally {
      _running = false;
      final queued = _queued;
      if (queued != null) {
        _queued = null;
        // 待っていた要求をまとめて1回走らせる（この Future はその終わりを待たない）
        queued.completer.complete(_start(queued.reasons));
      }
    }
  }

  /// 予約し直しの本体（設計 §4.1）。例外は投げない
  Future<void> _run(Set<String> reasons) async {
    final reason = reasons.join(',');
    // Android の起動・ログイン時は、端末の予約一覧を信用せずにすべて予約し直す
    // （まとめた要求のどれかが signed_in なら。rescheduleAllOnSignIn）
    final rescheduleAll =
        rescheduleAllOnSignIn && reasons.contains(signedInReason);
    // 走り始めた後に cancelAll されたら、予約しない（stopped）
    final generation = _generation;
    try {
      await _ensureInitialized();

      final userId = _currentUserId();
      if (userId == null) {
        await _cancelAllAndForget();
        debugPrint('[RecordReminderSync] $reason: ログインしていないため、リマインダーをすべて消しました');
        return;
      }

      final settings = await _storage.load(userId);
      final clientId = await _currentClientId();
      if (clientId == null) {
        // clients の行が無い（登録の途中など）。リマインダーではログインしていないものとして扱う
        await _cancelAllAndForget();
        debugPrint(
            '[RecordReminderSync] $reason: クライアントが分からないため、リマインダーをすべて消しました');
        return;
      }

      final now = _now();
      final todayKey = jstDateKeyOf(now);
      // 2つの読み込みは並べて走らせる（どちらも例外を投げない）
      final recordedFuture = settings.enabledKinds.any(_recordedKinds.contains)
          ? _loadRecordedToday(userId, clientId, now, todayKey)
          : Future.value(<ReminderKind>{});
      final workoutFuture = settings.settingOf(ReminderKind.workout).enabled
          ? _loadPendingWorkoutDates(userId, clientId, now, todayKey)
          : Future.value(<String>{});
      final recordedInDb = await recordedFuture;
      final pendingWorkoutDates = await workoutFuture;

      final sent = _sentToday;
      final recordedToday = {
        ...recordedInDb,
        if (sent != null && sent.isFor(userId, todayKey)) ...sent.value,
      };
      final planned = planReminders(
        settings: settings,
        now: now,
        recordedToday: recordedToday,
        pendingWorkoutDates: pendingWorkoutDates,
      );
      final pending = await _scheduler.pendingReminders();
      final diff =
          diffReminders(planned, pending, rescheduleAll: rescheduleAll);

      // 途中でログアウト（cancelAll）・ユーザーの切り替えがあったら、それ以上は取り消し・予約しない
      bool stopped() {
        if (generation == _generation && _currentUserId() == userId) {
          return false;
        }
        debugPrint('[RecordReminderSync] $reason: 途中でログアウトしたため、予約をやめました');
        return true;
      }

      // 取り消しをすべて済ませてから予約する（時刻を変えた項目は同じ ID が両方に入るため）
      var cancelled = 0;
      var scheduled = 0;
      var failed = 0;
      for (final id in diff.cancelIds) {
        if (stopped()) return;
        try {
          await _scheduler.cancel(id);
          cancelled++;
        } catch (e) {
          failed++;
          debugPrint('[RecordReminderSync] 通知 $id の取り消しエラー: $e');
        }
      }
      for (final reminder in diff.toSchedule) {
        if (stopped()) return;
        try {
          await _scheduler.schedule(reminder);
          scheduled++;
        } catch (e) {
          failed++;
          debugPrint('[RecordReminderSync] ${reminder.payload} の予約エラー: $e');
        }
      }

      debugPrint(
        '[RecordReminderSync] $reason: あるべき予約 ${planned.length}件'
        '${rescheduleAll ? '（端末の予約一覧を信用せず、すべて予約し直し）' : ''}'
        '（端末 ${pending.length}件 → 取り消し $cancelled件・予約 $scheduled件・失敗 $failed件。'
        '今日の記録済み ${recordedToday.length}件・運動の予定日 ${pendingWorkoutDates.length}日）',
      );
    } catch (e) {
      debugPrint('[RecordReminderSync] 予約し直しエラー（$reason）: $e');
    }
  }

  /// 今日記録した項目（DB）。読めなければ、同じ日に読めた最後の結果、それも無ければ空
  Future<Set<ReminderKind>> _loadRecordedToday(
    String userId,
    String clientId,
    tz.TZDateTime now,
    String todayKey,
  ) async {
    try {
      final recorded =
          await _fetchRecordedToday(clientId: clientId, nowJst: now);
      _lastRecordedToday = _DayValue(userId, todayKey, recorded);
      return recorded;
    } catch (e) {
      final last = _lastRecordedToday;
      final usable = last != null && last.isFor(userId, todayKey);
      debugPrint('[RecordReminderSync] 今日の記録を読めませんでした'
          '（${usable ? '同じ日に読めた結果を使います' : '記録なしとして予約します'}）: $e');
      return usable ? last.value : <ReminderKind>{};
    }
  }

  /// 今日から6日後までの運動の予定日（DB）。読めなければ、同じ日に読めた最後の結果、それも無ければ空
  Future<Set<String>> _loadPendingWorkoutDates(
    String userId,
    String clientId,
    tz.TZDateTime now,
    String todayKey,
  ) async {
    try {
      final dates = await _fetchPendingWorkoutDates(
        clientId: clientId,
        fromDateKey: todayKey,
        toDateKey: jstDateKeyOf(now.add(const Duration(days: 6))),
      );
      _lastPendingWorkoutDates = _DayValue(userId, todayKey, dates);
      return dates;
    } catch (e) {
      final last = _lastPendingWorkoutDates;
      final usable = last != null && last.isFor(userId, todayKey);
      debugPrint('[RecordReminderSync] 運動の予定日を読めませんでした'
          '（${usable ? '同じ日に読めた結果を使います' : '予定なしとして予約します'}）: $e');
      return usable ? last.value : <String>{};
    }
  }

  /// リマインダーの予約と表示中の通知をすべて消し、推定・読めた結果を捨てる（消すのに失敗しても捨てる）
  Future<void> _cancelAllAndForget() async {
    try {
      await _scheduler.cancelAllReminders();
    } finally {
      _sentToday = null;
      _lastRecordedToday = null;
      _lastPendingWorkoutDates = null;
    }
  }
}

/// 予約し直しを待っている要求（何件来ても1回にまとめる）
class _QueuedRefresh {
  final reasons = <String>{};
  final completer = Completer<void>();
}

/// ユーザーと日本時間の日付に結びつけた値（どちらかが違えば使わない）
class _DayValue<T> {
  const _DayValue(this.userId, this.dateKey, this.value);

  final String userId;
  final String dateKey;
  final T value;

  bool isFor(String userId, String dateKey) =>
      this.userId == userId && this.dateKey == dateKey;
}

/// 記録のリマインダーの設定の保存先（端末の SharedPreferences。アカウントごと）
@Riverpod(keepAlive: true)
RecordReminderSettingsStorage recordReminderSettingsStorage(
    RecordReminderSettingsStorageRef ref) {
  return RecordReminderSettingsStorage();
}

/// 記録のリマインダーの予約し直し（アプリで1つ。送ったタグからの推定と読めた結果をメモリに持つ）
@Riverpod(keepAlive: true)
RecordReminderSync recordReminderSync(RecordReminderSyncRef ref) {
  // ReminderStatusRepository は作るときに SupabaseService.client を読むので、初めて読むときに作る
  ReminderStatusRepository? statusRepository;
  ReminderStatusRepository status() =>
      statusRepository ??= ReminderStatusRepository();

  return RecordReminderSync(
    storage: ref.watch(recordReminderSettingsStorageProvider),
    fetchRecordedToday: ({required clientId, required nowJst}) =>
        status().fetchRecordedToday(clientId: clientId, nowJst: nowJst),
    fetchPendingWorkoutDates: (
            {required clientId, required fromDateKey, required toDateKey}) =>
        status().fetchPendingWorkoutDates(
      clientId: clientId,
      fromDateKey: fromDateKey,
      toDateKey: toDateKey,
    ),
    scheduler: const FlnReminderNotificationScheduler(),
    // Android はプラグインの予約一覧に、OS のアラームが消えた予約が残ることがあるので、
    // 起動・ログインのたびにすべて予約し直す（RecordReminderSync.rescheduleAllOnSignIn）
    rescheduleAllOnSignIn: defaultTargetPlatform == TargetPlatform.android,
    currentUserId: () => SupabaseService.client.auth.currentUser?.id,
    currentClientId: () async {
      // currentClientProvider は autoDispose なので、読み終えるまで購読して破棄されないようにする
      final subscription = ref.listen(currentClientProvider.future, (_, __) {});
      try {
        return (await subscription.read())?.clientId;
      } finally {
        subscription.close();
      }
    },
  );
}
