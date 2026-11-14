import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:fit_connect_mobile/features/record_reminders/data/record_reminder_settings_storage.dart';
import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/reminder_notification_scheduler.dart';

/// 記録のリマインダーの予約し直し（RecordReminderSync）のテスト。
///
/// 端末の予約・DB・時計・ログインは偽物に差し替える（Supabase・FLN には出ない）。
/// 設定は SharedPreferences のモックに保存する。

const _userA = '11111111-1111-1111-1111-111111111111';
const _userB = '22222222-2222-2222-2222-222222222222';

late tz.Location _tokyo;

/// 日本時間の日時
tz.TZDateTime _jst(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    tz.TZDateTime(_tokyo, year, month, day, hour, minute);

/// 日本時間の [year]-[month]-[day] の [kind] の通知 ID
int _id(int year, int month, int day, ReminderKind kind) =>
    reminderNotificationId(_jst(year, month, day), kind);

/// [kinds] をオンにした設定（時刻は [times] にあればそれ、無ければ既定）
RecordReminderSettings _enabled(
  Iterable<ReminderKind> kinds, {
  Map<ReminderKind, ReminderTime> times = const {},
}) {
  var settings = RecordReminderSettings.defaults();
  for (final kind in kinds) {
    settings = settings.withSetting(
      kind,
      ReminderSetting(
        enabled: true,
        time: times[kind] ?? ReminderTime.defaultFor(kind),
      ),
    );
  }
  return settings;
}

Future<void> _save(String userId, RecordReminderSettings settings) =>
    RecordReminderSettingsStorage().save(userId, settings);

/// 端末の予約を模した ReminderNotificationScheduler（呼ばれた操作を順に記録する）
class _FakeScheduler implements ReminderNotificationScheduler {
  /// 端末の予約（ID → payload。リマインダー以外の ID も持てる）。schedule で足し、cancel で消す
  final pending = <int, String?>{};

  /// 呼ばれた操作（'pending' / 'cancel:7043' / 'schedule:7043' / 'cancelAll'）
  final calls = <String>[];

  /// 予約できた通知（呼ばれた順）
  final scheduled = <PlannedReminder>[];

  Object? pendingError;
  Object? cancelAllError;
  final scheduleErrors = <int, Object>{};

  @override
  Future<List<PendingReminder>> pendingReminders() async {
    calls.add('pending');
    final error = pendingError;
    if (error != null) throw error;
    // 本物はリマインダーの ID だけを返すが、範囲外が混じっても無視されることも確かめる
    return [
      for (final entry in pending.entries)
        PendingReminder(id: entry.key, payload: entry.value),
    ];
  }

  @override
  Future<void> schedule(PlannedReminder reminder) async {
    calls.add('schedule:${reminder.id}');
    final error = scheduleErrors[reminder.id];
    if (error != null) throw error;
    pending[reminder.id] = reminder.payload;
    scheduled.add(reminder);
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
    pending.remove(id);
  }

  @override
  Future<void> cancelAllReminders() async {
    calls.add('cancelAll');
    final error = cancelAllError;
    if (error != null) throw error;
    pending.removeWhere((id, _) => isReminderNotificationId(id));
  }
}

/// DB の読み込み（今日の記録・運動の予定日）の偽物
class _FakeStatus {
  Set<ReminderKind> recordedToday = {};
  Set<String> pendingWorkoutDates = {};
  Object? recordedError;
  Object? workoutError;

  /// 渡すと、今日の記録の読み込みがこの Future を待つ（予約し直しが走っている間を作る）
  Completer<void>? recordedGate;

  final recordedCalls = <({String clientId, tz.TZDateTime nowJst})>[];
  final workoutCalls =
      <({String clientId, String fromDateKey, String toDateKey})>[];

  Future<Set<ReminderKind>> fetchRecordedToday({
    required String clientId,
    required tz.TZDateTime nowJst,
  }) async {
    recordedCalls.add((clientId: clientId, nowJst: nowJst));
    final gate = recordedGate;
    if (gate != null) await gate.future;
    final error = recordedError;
    if (error != null) throw error;
    return {...recordedToday};
  }

  Future<Set<String>> fetchPendingWorkoutDates({
    required String clientId,
    required String fromDateKey,
    required String toDateKey,
  }) async {
    workoutCalls.add(
        (clientId: clientId, fromDateKey: fromDateKey, toDateKey: toDateKey));
    final error = workoutError;
    if (error != null) throw error;
    return {...pendingWorkoutDates};
  }
}

void main() {
  late _FakeScheduler scheduler;
  late _FakeStatus status;
  late tz.TZDateTime now;
  Object? nowError;
  String? userId;
  String? clientId;
  Object? clientIdError;
  Object? ensureError;
  Completer<void>? ensureGate;
  late int ensureCalls;
  late RecordReminderSync sync;

  RecordReminderSync buildSync({
    RecordReminderSettingsStorage? storage,
    bool rescheduleAllOnSignIn = false,
  }) =>
      RecordReminderSync(
        storage: storage ?? RecordReminderSettingsStorage(),
        fetchRecordedToday: status.fetchRecordedToday,
        fetchPendingWorkoutDates: status.fetchPendingWorkoutDates,
        scheduler: scheduler,
        currentUserId: () => userId,
        currentClientId: () async {
          final error = clientIdError;
          if (error != null) throw error;
          return clientId;
        },
        rescheduleAllOnSignIn: rescheduleAllOnSignIn,
        now: () {
          final error = nowError;
          if (error != null) throw error;
          return now;
        },
        ensureInitialized: () async {
          ensureCalls++;
          final gate = ensureGate;
          if (gate != null) await gate.future;
          final error = ensureError;
          if (error != null) throw error;
        },
      );

  /// [settings] で予約し直したときの「あるべき予約」（planReminders そのもの）
  List<PlannedReminder> planFor(
    RecordReminderSettings settings, {
    Set<ReminderKind> recordedToday = const {},
    Set<String> pendingWorkoutDates = const {},
  }) =>
      planReminders(
        settings: settings,
        now: now,
        recordedToday: recordedToday,
        pendingWorkoutDates: pendingWorkoutDates,
      );

  setUpAll(() {
    tzdata.initializeTimeZones();
    _tokyo = tz.getLocation('Asia/Tokyo');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scheduler = _FakeScheduler();
    status = _FakeStatus();
    now = _jst(2026, 11, 7, 12, 0);
    nowError = null;
    userId = _userA;
    clientId = _userA;
    clientIdError = null;
    ensureError = null;
    ensureGate = null;
    ensureCalls = 0;
    sync = buildSync();
  });

  group('refresh: ログイン・設定', () {
    test('ログインしていなければ、リマインダーをすべて消す（設定・DB は読まない。ほかの通知は残る）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      scheduler.pending
        ..[_id(2026, 11, 7, ReminderKind.dinner)] =
            'record_reminder:dinner@202611072000'
        ..[9001] = 'health_sync_error';
      userId = null;

      await sync.refresh(reason: 'test');

      expect(ensureCalls, 1);
      expect(scheduler.calls, ['cancelAll']);
      expect(scheduler.pending.keys, [9001]);
      expect(status.recordedCalls, isEmpty);
      expect(status.workoutCalls, isEmpty);
    });

    test('クライアントが分からなければ（clients の行が無い）、ログインしていないものとしてすべて消す', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      scheduler.pending[_id(2026, 11, 8, ReminderKind.dinner)] =
          'record_reminder:dinner@202611082000';
      clientId = null;

      await sync.refresh(reason: 'test');

      expect(scheduler.calls, ['cancelAll']);
      expect(scheduler.pending, isEmpty);
      expect(status.recordedCalls, isEmpty);
    });

    test('すべてオフなら、端末に残っているリマインダーを取り消す（DB は読まない。範囲外の ID には触れない）', () async {
      final dinnerId = _id(2026, 11, 7, ReminderKind.dinner);
      final weightId = _id(2026, 11, 8, ReminderKind.weight);
      scheduler.pending
        ..[dinnerId] = 'record_reminder:dinner@202611072000'
        ..[9001] = 'health_sync_error'
        ..[weightId] = 'record_reminder:weight@202611080730';

      await sync.refresh(reason: 'settings_changed');

      expect(
          scheduler.calls, ['pending', 'cancel:$dinnerId', 'cancel:$weightId']);
      expect(scheduler.pending.keys, [9001]);
      expect(status.recordedCalls, isEmpty);
      expect(status.workoutCalls, isEmpty);
    });

    test('オンの項目を planReminders のとおりに予約する（運動はプランがある日だけ）', () async {
      final settings = _enabled({
        ReminderKind.weight,
        ReminderKind.dinner,
        ReminderKind.workout,
      });
      await _save(_userA, settings);
      status.pendingWorkoutDates = {'2026-11-07', '2026-11-09'};

      await sync.refresh(reason: 'signed_in');

      final expected = planFor(
        settings,
        pendingWorkoutDates: {'2026-11-07', '2026-11-09'},
      );
      expect(expected, isNotEmpty);
      expect(scheduler.scheduled, expected);
      expect(
        scheduler.scheduled
            .where((r) => r.kind == ReminderKind.workout)
            .map((r) => jstDateKeyOf(r.fireAt)),
        ['2026-11-07', '2026-11-09'],
      );
      // DB はクライアント本人の分を、今（日本時間）で読む
      expect(status.recordedCalls.single.clientId, _userA);
      expect(status.recordedCalls.single.nowJst, now);
    });

    test('ユーザーごとの設定を使う（別のユーザーは前の人の設定で鳴らない）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await _save(_userB, _enabled({ReminderKind.weight}));
      userId = _userB;
      clientId = _userB;

      await sync.refresh(reason: 'signed_in');

      expect(scheduler.scheduled.map((r) => r.kind).toSet(),
          {ReminderKind.weight});
      expect(status.recordedCalls.single.clientId, _userB);
    });

    test('同じ予約（ID と payload が同じ）はそのまま残し、増えた日の分だけ予約する', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: 'signed_in');
      expect(scheduler.scheduled, hasLength(7));

      // 次の日。端末では 11/7 の分が鳴り終わって消えている
      scheduler.pending.remove(_id(2026, 11, 7, ReminderKind.dinner));
      scheduler.calls.clear();
      now = _jst(2026, 11, 8, 12, 0);
      await sync.refresh(reason: 'resumed');

      expect(scheduler.calls, [
        'pending',
        'schedule:${_id(2026, 11, 14, ReminderKind.dinner)}',
      ]);
    });

    test('時刻を変えたら、同じ ID の予約を取り消してから予約し直す（取り消しをすべて先に）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: 'signed_in');
      scheduler.calls.clear();

      await _save(
        _userA,
        _enabled(
          {ReminderKind.dinner},
          times: {ReminderKind.dinner: const ReminderTime(hour: 21, minute: 0)},
        ),
      );
      await sync.refresh(reason: 'settings_changed');

      final cancels = scheduler.calls.where((c) => c.startsWith('cancel:'));
      final schedules = scheduler.calls.where((c) => c.startsWith('schedule:'));
      expect(cancels, hasLength(7));
      expect(schedules, hasLength(7));
      // 取り消した ID と同じ ID を予約し直す
      expect(
        cancels.map((c) => c.substring('cancel:'.length)).toSet(),
        schedules.map((c) => c.substring('schedule:'.length)).toSet(),
      );
      // 予約はすべての取り消しの後
      final lastCancel =
          scheduler.calls.lastIndexWhere((c) => c.startsWith('cancel:'));
      final firstSchedule =
          scheduler.calls.indexWhere((c) => c.startsWith('schedule:'));
      expect(lastCancel, lessThan(firstSchedule));
      expect(
        scheduler.pending.values,
        everyElement(endsWith('2100')),
      );
    });
  });

  group('refresh: Android の起動・ログイン時（rescheduleAllOnSignIn）', () {
    /// [planned] を端末の予約一覧に入れる（Android のプラグインが保存した一覧。OS のアラームとは限らない）
    void putInPendingList(List<PlannedReminder> planned) {
      for (final reminder in planned) {
        scheduler.pending[reminder.id] = reminder.payload;
      }
    }

    test('signed_in では、予約一覧が「あるべき予約」と同じでも、すべて予約し直す（強制停止で OS のアラームだけが消えた場合）',
        () async {
      sync = buildSync(rescheduleAllOnSignIn: true);
      final settings = _enabled({ReminderKind.dinner});
      await _save(_userA, settings);
      final expected = planFor(settings);
      putInPendingList(expected);

      await sync.refresh(reason: RecordReminderSync.signedInReason);

      // 同じ ID の予約は置き換わるので、先に取り消さない
      expect(scheduler.calls, [
        'pending',
        for (final reminder in expected) 'schedule:${reminder.id}',
      ]);
      expect(scheduler.scheduled, expected);
    });

    test('「あるべき予約」に無いリマインダーの予約は先に取り消す（ほかの通知には触れない）', () async {
      sync = buildSync(rescheduleAllOnSignIn: true);
      final settings = _enabled({ReminderKind.dinner});
      await _save(_userA, settings);
      final expected = planFor(settings);
      final oldLunch = _id(2026, 11, 8, ReminderKind.lunch);
      scheduler.pending
        ..[9001] = 'health_sync_error'
        ..[oldLunch] = 'record_reminder:lunch@202611081300';
      putInPendingList(expected.take(3).toList());

      await sync.refresh(reason: RecordReminderSync.signedInReason);

      expect(scheduler.calls, [
        'pending',
        'cancel:$oldLunch',
        for (final reminder in expected) 'schedule:${reminder.id}',
      ]);
      expect(scheduler.pending.keys.toSet(), {
        9001,
        for (final reminder in expected) reminder.id,
      });
    });

    test('signed_in 以外（前面に戻った・設定やワークアウトの変更・ヘルスケア同期・送信）は、これまでどおり差分だけ', () async {
      sync = buildSync(rescheduleAllOnSignIn: true);
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: RecordReminderSync.signedInReason);
      expect(scheduler.scheduled, hasLength(7));
      scheduler.calls.clear();

      const reasons = [
        'resumed',
        'settings_changed',
        'workout_changed',
        'health_sync',
        'message_sent',
      ];
      for (final reason in reasons) {
        await sync.refresh(reason: reason);
      }

      expect(scheduler.calls, [for (final _ in reasons) 'pending']);
    });

    test('iOS（rescheduleAllOnSignIn: false。予約一覧は OS の予約そのもの）は、signed_in でも差分だけ',
        () async {
      // setUp の sync は rescheduleAllOnSignIn: false
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: RecordReminderSync.signedInReason);
      expect(scheduler.scheduled, hasLength(7));
      scheduler.calls.clear();

      await sync.refresh(reason: RecordReminderSync.signedInReason);

      expect(scheduler.calls, ['pending']);
    });

    test('走っている間に来た要求をまとめた1回も、signed_in が含まれていれば、すべて予約し直す', () async {
      sync = buildSync(rescheduleAllOnSignIn: true);
      final settings = _enabled({ReminderKind.dinner});
      await _save(_userA, settings);
      final expected = planFor(settings);
      putInPendingList(expected);
      final gate = Completer<void>();
      status.recordedGate = gate;

      final first = sync.refresh(reason: 'resumed');
      await pumpEventQueue();
      final merged = [
        sync.refresh(reason: 'health_sync'),
        sync.refresh(reason: RecordReminderSync.signedInReason),
      ];
      status.recordedGate = null;
      gate.complete();
      await first;
      await Future.wait(merged);

      // 1回目（resumed）は差分だけ（予約一覧と同じなので何もしない）、まとめた1回はすべて予約し直す
      expect(status.recordedCalls, hasLength(2));
      expect(scheduler.calls, [
        'pending',
        'pending',
        for (final reminder in expected) 'schedule:${reminder.id}',
      ]);
    });
  });

  group('refresh: 今日の記録・運動の予定日', () {
    test('今日記録済みの項目は、今日の分だけ予約しない（明日からは予約する）', () async {
      await _save(_userA, _enabled({ReminderKind.weight, ReminderKind.dinner}));
      // 体重は 07:30 で過ぎているので、夕食で確かめる
      status.recordedToday = {ReminderKind.dinner};

      await sync.refresh(reason: 'resumed');

      final ids = scheduler.pending.keys.toSet();
      expect(ids, isNot(contains(_id(2026, 11, 7, ReminderKind.dinner))));
      expect(ids, contains(_id(2026, 11, 8, ReminderKind.dinner)));
      expect(
        scheduler.scheduled,
        planFor(
          _enabled({ReminderKind.weight, ReminderKind.dinner}),
          recordedToday: {ReminderKind.dinner},
        ),
      );
    });

    test('DB は、オンの項目に要るものだけを読む（運動の予定日は運動がオンのときだけ）', () async {
      await _save(_userA, _enabled({ReminderKind.weight}));
      await sync.refresh(reason: 'test');
      expect(status.recordedCalls, hasLength(1));
      expect(status.workoutCalls, isEmpty);

      await _save(_userA, _enabled({ReminderKind.workout}));
      await sync.refresh(reason: 'test');
      expect(status.recordedCalls, hasLength(1));
      expect(status.workoutCalls, hasLength(1));
      // 今日から6日後まで（日本時間の日付）
      expect(status.workoutCalls.single.clientId, _userA);
      expect(status.workoutCalls.single.fromDateKey, '2026-11-07');
      expect(status.workoutCalls.single.toDateKey, '2026-11-13');
    });

    test('運動の予定日の窓は日本時間の日付で決まる（00:30 JST は UTC ではまだ前の日）', () async {
      await _save(_userA, _enabled({ReminderKind.workout}));
      now = _jst(2026, 12, 31, 0, 30);

      await sync.refresh(reason: 'test');

      expect(status.workoutCalls.single.fromDateKey, '2026-12-31');
      expect(status.workoutCalls.single.toDateKey, '2027-01-06');
    });

    test('今日の記録を読めなかったら、同じ日に読めた最後の結果を使う', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      status.recordedToday = {ReminderKind.dinner};
      await sync.refresh(reason: 'signed_in');
      expect(scheduler.pending,
          isNot(contains(_id(2026, 11, 7, ReminderKind.dinner))));

      status.recordedError = Exception('offline');
      scheduler.calls.clear();
      now = _jst(2026, 11, 7, 18, 0);
      await sync.refresh(reason: 'resumed');

      // 記録済みのまま（今日の夕食を予約し直さない）
      expect(scheduler.calls, ['pending']);
    });

    test('同じ日に読めた結果が無ければ、記録なし・運動の予定日なしとして予約する', () async {
      final settings = _enabled({ReminderKind.dinner, ReminderKind.workout});
      await _save(_userA, settings);
      status.recordedError = Exception('offline');
      status.workoutError = Exception('offline');

      await sync.refresh(reason: 'signed_in');

      expect(scheduler.scheduled, planFor(settings));
      expect(
          scheduler.pending, contains(_id(2026, 11, 7, ReminderKind.dinner)));
      expect(scheduler.scheduled.where((r) => r.kind == ReminderKind.workout),
          isEmpty);
    });

    test('運動の予定日を読めなかったら、同じ日に読めた結果を使う（運動の予約を消さない）', () async {
      await _save(_userA, _enabled({ReminderKind.workout}));
      status.pendingWorkoutDates = {'2026-11-07', '2026-11-10'};
      await sync.refresh(reason: 'signed_in');
      expect(scheduler.scheduled, hasLength(2));

      status.workoutError = Exception('offline');
      scheduler.calls.clear();
      await sync.refresh(reason: 'resumed');

      expect(scheduler.calls, ['pending']);
      expect(scheduler.pending, hasLength(2));
    });

    test('前の日に読めた結果は使わない（日付が変わって読めなければ、記録なしとして予約する）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      status.recordedToday = {ReminderKind.dinner};
      await sync.refresh(reason: 'signed_in');

      status.recordedError = Exception('offline');
      now = _jst(2026, 11, 8, 12, 0);
      await sync.refresh(reason: 'resumed');

      expect(
          scheduler.pending, contains(_id(2026, 11, 8, ReminderKind.dinner)));
    });

    test('ほかのユーザーが読めた結果は使わない', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await _save(_userB, _enabled({ReminderKind.dinner}));
      status.recordedToday = {ReminderKind.dinner};
      await sync.refresh(reason: 'signed_in');

      userId = _userB;
      clientId = _userB;
      status.recordedError = Exception('offline');
      await sync.refresh(reason: 'signed_in');

      expect(
          scheduler.pending, contains(_id(2026, 11, 7, ReminderKind.dinner)));
    });
  });

  group('onMessageSent', () {
    test('夕食を送ったら今日の夕食を止め、DB にまだ記録が無くても、後の予約し直しで止まったまま', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: 'signed_in');
      final todayDinner = _id(2026, 11, 7, ReminderKind.dinner);
      expect(scheduler.pending, contains(todayDinner));

      scheduler.calls.clear();
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();

      expect(scheduler.calls, ['pending', 'cancel:$todayDinner']);
      expect(scheduler.pending, isNot(contains(todayDinner)));
      // 明日からの分は残る
      expect(
          scheduler.pending, contains(_id(2026, 11, 8, ReminderKind.dinner)));

      // DB にはまだ無い（サーバーが記録を作る前）。前面に戻って予約し直しても止まったまま
      status.recordedToday = {};
      scheduler.calls.clear();
      now = _jst(2026, 11, 7, 19, 0);
      await sync.refresh(reason: 'resumed');

      expect(scheduler.calls, ['pending']);
      expect(scheduler.pending, isNot(contains(todayDinner)));
    });

    test('推定はその日（日本時間）だけ。次の日には使わない', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      now = _jst(2026, 11, 7, 23, 59);
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();

      now = _jst(2026, 11, 8, 0, 0);
      await sync.refresh(reason: 'resumed');

      expect(
          scheduler.pending, contains(_id(2026, 11, 8, ReminderKind.dinner)));
    });

    test('同じ日に送った項目はたまっていく（昼食と夕食）', () async {
      await _save(_userA, _enabled({ReminderKind.lunch, ReminderKind.dinner}));
      now = _jst(2026, 11, 7, 9, 0);
      sync.onMessageSent(['#食事:昼食']);
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();

      expect(scheduler.pending,
          isNot(contains(_id(2026, 11, 7, ReminderKind.lunch))));
      expect(scheduler.pending,
          isNot(contains(_id(2026, 11, 7, ReminderKind.dinner))));
      expect(scheduler.pending, contains(_id(2026, 11, 8, ReminderKind.lunch)));
    });

    test('記録にならないタグ（間食・#食事・#運動・タグなし）では何もしない（予約し直さない）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));

      sync.onMessageSent(['#食事:間食']);
      sync.onMessageSent(['#食事']);
      sync.onMessageSent(['#運動:完了']);
      sync.onMessageSent([]);
      await pumpEventQueue();

      expect(ensureCalls, 0);
      expect(scheduler.calls, isEmpty);
    });

    test('推定は送った人のものだけ（別のユーザーには使わない）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await _save(_userB, _enabled({ReminderKind.dinner}));
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();

      userId = _userB;
      clientId = _userB;
      await sync.refresh(reason: 'signed_in');

      expect(
          scheduler.pending, contains(_id(2026, 11, 7, ReminderKind.dinner)));
    });
  });

  group('直列化', () {
    test('走っている間に5回呼ばれても、走り終えた後に1回だけ走らせる（どれもその回の終わりで完了する）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      status.recordedGate = firstGate;

      var firstDone = false;
      final first = sync.refresh(reason: 'first').then((_) => firstDone = true);
      await pumpEventQueue();
      // 1回目は今日の記録の読み込みで止まっている
      expect(status.recordedCalls, hasLength(1));

      status.recordedGate = secondGate;
      var othersDone = 0;
      final others = [
        for (var i = 0; i < 5; i++)
          sync.refresh(reason: 'again$i').then((_) => othersDone++),
      ];
      await pumpEventQueue();
      // 走っている間は始めない
      expect(status.recordedCalls, hasLength(1));
      expect(ensureCalls, 1);

      firstGate.complete();
      await first;
      expect(firstDone, isTrue);
      await pumpEventQueue();
      // まとめた1回が始まった。それが終わるまで、後の5件は完了しない
      expect(status.recordedCalls, hasLength(2));
      expect(othersDone, 0);

      secondGate.complete();
      await Future.wait(others);
      expect(othersDone, 5);
      expect(ensureCalls, 2);
      expect(status.recordedCalls, hasLength(2));
      // 2回目は1回目の予約をそのまま残す
      expect(scheduler.calls.where((c) => c.startsWith('schedule:')),
          hasLength(7));
    });

    test('走り終えた後の呼び出しは、すぐに走らせる', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      await sync.refresh(reason: 'first');
      await sync.refresh(reason: 'second');

      expect(ensureCalls, 2);
      expect(status.recordedCalls, hasLength(2));
    });

    test('予約し直しの途中で cancelAll されたら（ログアウト）、その後は予約しない', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      final gate = Completer<void>();
      status.recordedGate = gate;
      final running = sync.refresh(reason: 'resumed');
      await pumpEventQueue();

      await sync.cancelAll();
      gate.complete();
      await running;

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.calls, ['cancelAll', 'pending']);
      expect(scheduler.pending, isEmpty);
    });

    test('予約し直しの途中でログインしているユーザーが変わったら、予約しない', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      final gate = Completer<void>();
      status.recordedGate = gate;
      final running = sync.refresh(reason: 'resumed');
      await pumpEventQueue();

      userId = null;
      gate.complete();
      await running;

      expect(scheduler.scheduled, isEmpty);
    });

    test('ローカル通知の初期化を待っている間に cancelAll されても、予約しない', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      final gate = Completer<void>();
      ensureGate = gate;
      final running = sync.refresh(reason: 'signed_in');
      await pumpEventQueue();

      await sync.cancelAll();
      gate.complete();
      await running;

      expect(scheduler.scheduled, isEmpty);
      expect(scheduler.calls, ['cancelAll', 'pending']);
    });
  });

  group('cancelAll', () {
    test('リマインダーをすべて消し、送ったタグからの推定を捨てる（同じ日にログインし直しても使わない）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();
      final todayDinner = _id(2026, 11, 7, ReminderKind.dinner);
      expect(scheduler.pending, isNot(contains(todayDinner)));
      scheduler.pending[9001] = 'health_sync_error';

      await sync.cancelAll();

      expect(scheduler.calls.last, 'cancelAll');
      expect(scheduler.pending.keys, [9001]);

      await sync.refresh(reason: 'signed_in');
      expect(scheduler.pending, contains(todayDinner));
    });

    test('読めた結果も捨てる（ログインし直した後に DB を読めなければ、記録なしとして予約する）', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      status.recordedToday = {ReminderKind.dinner};
      await sync.refresh(reason: 'signed_in');

      await sync.cancelAll();
      status.recordedError = Exception('offline');
      await sync.refresh(reason: 'signed_in');

      expect(
          scheduler.pending, contains(_id(2026, 11, 7, ReminderKind.dinner)));
    });

    test('消すのに失敗しても例外を投げず、推定は捨てる', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      sync.onMessageSent(['#食事:夕食']);
      await pumpEventQueue();

      scheduler.cancelAllError = Exception('platform');
      await expectLater(sync.cancelAll(), completes);

      await sync.refresh(reason: 'signed_in');
      expect(
          scheduler.pending, contains(_id(2026, 11, 7, ReminderKind.dinner)));
    });
  });

  group('例外を投げない', () {
    test('ローカル通知の初期化に失敗しても', () async {
      ensureError = Exception('init');
      await expectLater(sync.refresh(reason: 'test'), completes);
      expect(scheduler.calls, isEmpty);
    });

    test('設定を読めなくても', () async {
      sync = buildSync(
        storage: RecordReminderSettingsStorage(
          preferences: () async => throw Exception('prefs'),
        ),
      );
      await expectLater(sync.refresh(reason: 'test'), completes);
      expect(scheduler.calls, isEmpty);
    });

    test('クライアントを読めなくても', () async {
      clientIdError = Exception('network');
      await expectLater(sync.refresh(reason: 'test'), completes);
      expect(scheduler.calls, isEmpty);
    });

    test('端末の予約一覧を読めなくても', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      scheduler.pendingError = Exception('platform');
      await expectLater(sync.refresh(reason: 'test'), completes);
      expect(scheduler.scheduled, isEmpty);
    });

    test('1件の予約に失敗しても、残りは予約する', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      final failing = _id(2026, 11, 7, ReminderKind.dinner);
      scheduler.scheduleErrors[failing] =
          ArgumentError('Must be a date in the future');

      await expectLater(sync.refresh(reason: 'test'), completes);

      expect(scheduler.scheduled, hasLength(6));
      expect(scheduler.pending, isNot(contains(failing)));
    });

    test('ログインしていないときの全消しに失敗しても', () async {
      userId = null;
      scheduler.cancelAllError = Exception('platform');
      await expectLater(sync.refresh(reason: 'test'), completes);
    });

    test('onMessageSent で時刻を読めなくても（予約し直さない）', () async {
      nowError = Exception('tz');
      expect(() => sync.onMessageSent(['#食事:夕食']), returnsNormally);
      await pumpEventQueue();
      expect(ensureCalls, 0);
    });

    test('エラーの後も、次の要求は走る', () async {
      await _save(_userA, _enabled({ReminderKind.dinner}));
      scheduler.pendingError = Exception('platform');
      await sync.refresh(reason: 'first');

      scheduler.pendingError = null;
      await sync.refresh(reason: 'second');
      expect(scheduler.scheduled, hasLength(7));
    });
  });

  group('recordReminderSyncProvider', () {
    test('作るときに Supabase・端末には触れず、アプリで1つ（keepAlive）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final first = container.read(recordReminderSyncProvider);
      await container.pump();
      await pumpEventQueue();

      expect(
          identical(container.read(recordReminderSyncProvider), first), isTrue);
      expect(
        container.read(recordReminderSettingsStorageProvider),
        isA<RecordReminderSettingsStorage>(),
      );
    });

    test('Android だけ、起動・ログイン時にすべて予約し直す（rescheduleAllOnSignIn）', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final (platform, expected) in [
        (TargetPlatform.android, true),
        (TargetPlatform.iOS, false),
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          container.read(recordReminderSyncProvider).rescheduleAllOnSignIn,
          expected,
          reason: '$platform',
        );
      }
    });
  });
}
