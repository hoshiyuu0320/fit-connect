import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';
import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

late tz.Location _tokyo;

/// 日本時間の日時
tz.TZDateTime _jst(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) =>
    tz.TZDateTime(_tokyo, year, month, day, hour, minute, second);

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

final _allOn = _enabled(ReminderKind.values);

/// [from] から [count] 日分の日本時間の日付キー
Set<String> _dateKeys(tz.TZDateTime from, int count) => {
      for (var i = 0; i < count; i++)
        jstDateKeyOf(
          _jst(from.year, from.month, from.day + i),
        ),
    };

// 通知 ID の日付の桁（日本時間の暦日の 1970-01-01 からの通し日数 % 10。実装とは別に計算した値）:
//   2026-11-07 → 4、11-08 → 5、11-09 → 6、11-10 → 7、11-11 → 8、11-12 → 9、11-13 → 0、11-14 → 1、11-16 → 3
//   2026-12-29 → 6、12-30 → 7、12-31 → 8、2027-01-01 → 9、01-02 → 0、01-03 → 1、01-04 → 2
//   2028-02-28 → 2、02-29 → 3、03-01 → 4
// 例: 2026-11-07 の夕食（index 3）は 7000 + 4 * 10 + 3 = 7043

/// 日本時間の暦日 [year]-[month]-[day] の [kind] の通知 ID（実装とは別の計算で求める）
int _idOf(int year, int month, int day, ReminderKind kind) {
  final epochDay = DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  return 7000 + (epochDay % 10) * 10 + kind.index;
}

/// 読みやすさのための1行表現（'2026-11-07 13:00 lunch 7042'）
String _describe(PlannedReminder r) {
  final t = r.fireAt;
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${jstDateKeyOf(t)} $hh:$mm ${r.kind.key} ${r.id}';
}

List<PendingReminder> _pendingOf(List<PlannedReminder> planned) => [
      for (final r in planned) PendingReminder(id: r.id, payload: r.payload),
    ];

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    _tokyo = tz.getLocation('Asia/Tokyo');
  });

  group('planReminders', () {
    test('すべてオフなら何も予約しない', () {
      final planned = planReminders(
        settings: RecordReminderSettings.defaults(),
        now: _jst(2026, 11, 7, 0, 0),
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(_jst(2026, 11, 7), 7),
      );
      expect(planned, isEmpty);
    });

    test('日の途中: 時刻を過ぎた今日の分は予約せず、まだの分から時刻順に並ぶ', () {
      final now = _jst(2026, 11, 7, 10, 0);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      expect(planned.take(8).map(_describe), [
        // 今日: 体重 07:30・朝食 09:00 は過ぎている
        '2026-11-07 13:00 lunch 7042',
        '2026-11-07 18:00 workout 7044',
        '2026-11-07 20:00 dinner 7043',
        '2026-11-08 07:30 weight 7050',
        '2026-11-08 09:00 breakfast 7051',
        '2026-11-08 13:00 lunch 7052',
        '2026-11-08 18:00 workout 7054',
        '2026-11-08 20:00 dinner 7053',
      ]);
      expect(planned, hasLength(3 + 6 * 5));
      expect(_describe(planned.last), '2026-11-13 20:00 dinner 7003');
    });

    test('今日を含む7日分だけ（8日目は予約しない）。最大 35 件で ID は 7000〜7099 の中で重ならない', () {
      final now = _jst(2026, 11, 7, 0, 0);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {},
        // 8日目（11/14）にも予定がある
        pendingWorkoutDates: _dateKeys(now, 8),
      );

      expect(planned, hasLength(35));
      expect(_describe(planned.first), '2026-11-07 07:30 weight 7040');
      expect(_describe(planned.last), '2026-11-13 20:00 dinner 7003');
      expect(
        planned.map((r) => jstDateKeyOf(r.fireAt)).toSet(),
        _dateKeys(now, 7),
      );
      expect(planned.map((r) => r.id).toSet(), hasLength(35));
      expect(planned.every((r) => isReminderNotificationId(r.id)), isTrue);
    });

    test('日付の変わり目: 23:59 JST は今日の分が残っておらず、翌日からの6日分', () {
      final now = _jst(2026, 11, 7, 23, 59);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(now, 8),
      );

      expect(planned, hasLength(6 * 5));
      expect(_describe(planned.first), '2026-11-08 07:30 weight 7050');
      expect(_describe(planned.last), '2026-11-13 20:00 dinner 7003');
      expect(
          planned.any((r) => jstDateKeyOf(r.fireAt) == '2026-11-07'), isFalse);
      // 11/7 の ID（7040〜7044）は使わない
      expect(planned.any((r) => r.id ~/ 10 == 704), isFalse);
    });

    test('日付の変わり目: 00:00 JST になると新しい日が今日になる', () {
      final now = _jst(2026, 11, 8, 0, 0);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {ReminderKind.weight},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      // 今日（11/8）の体重は記録済みなので止まり、11/9 の体重は鳴る
      expect(planned, hasLength(35 - 1));
      expect(_describe(planned.first), '2026-11-08 09:00 breakfast 7051');
      expect(planned.map(_describe), contains('2026-11-09 07:30 weight 7060'));
      expect(_describe(planned.last), '2026-11-14 20:00 dinner 7013');
    });

    test('日付が変わっても、同じ日の通知は同じもの（23:59 に予約した明日の分 = 00:00 に予約した今日の分）', () {
      final before = planReminders(
        settings: _allOn,
        now: _jst(2026, 11, 7, 23, 59),
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(_jst(2026, 11, 7), 8),
      );
      final after = planReminders(
        settings: _allOn,
        now: _jst(2026, 11, 8, 0, 0),
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(_jst(2026, 11, 7), 8),
      );

      // 11/8〜11/13 は ID・payload・時刻まで同じ。00:00 の方は 11/14 が増えるだけ
      expect(
        after.where((r) => jstDateKeyOf(r.fireAt) != '2026-11-14').toList(),
        before,
      );
      expect(
        after
            .where((r) => jstDateKeyOf(r.fireAt) == '2026-11-14')
            .map((r) => r.id),
        [7010, 7011, 7012, 7014, 7013],
      );
    });

    test('同じ暦日の通知は、別の日に予約しても同じ ID と payload（11/7 と 11/9 に予約した 11/10 の夕食）', () {
      final pendingWorkoutDates = _dateKeys(_jst(2026, 11, 7), 9);
      final planned7 = planReminders(
        settings: _allOn,
        now: _jst(2026, 11, 7, 10, 0),
        recordedToday: const {},
        pendingWorkoutDates: pendingWorkoutDates,
      );
      final planned9 = planReminders(
        settings: _allOn,
        now: _jst(2026, 11, 9, 10, 0),
        recordedToday: const {},
        pendingWorkoutDates: pendingWorkoutDates,
      );

      PlannedReminder dinnerOn10(List<PlannedReminder> planned) =>
          planned.singleWhere(
            (r) =>
                r.kind == ReminderKind.dinner &&
                jstDateKeyOf(r.fireAt) == '2026-11-10',
          );
      final from7 = dinnerOn10(planned7);
      final from9 = dinnerOn10(planned9);
      expect(from7.id, 7073);
      expect(from9.id, from7.id);
      expect(from7.payload, 'record_reminder:dinner@202611102000');
      expect(from9.payload, from7.payload);

      // 重なる日（11/9 の 10:00 より後〜11/13）の通知はすべて同じ
      String keyOf(PlannedReminder r) =>
          '${jstDateKeyOf(r.fireAt)} ${r.kind.key}';
      final byKey7 = {for (final r in planned7) keyOf(r): r};
      final overlap =
          planned9.where((r) => byKey7.containsKey(keyOf(r))).toList();
      expect(overlap, hasLength(3 + 4 * 5));
      for (final r in overlap) {
        expect(r, byKey7[keyOf(r)], reason: keyOf(r));
      }
    });

    test('どの日から始めても、7日・10日の窓の中で ID は重ならず 7000〜7099 に収まる', () {
      // 年末年始・うるう日（2028-02-29）・月末をまたぐ開始日を 1 日ずつ
      for (var i = 0; i < 75; i++) {
        final start = _jst(2027, 12, 20 + i);
        for (final days in [7, 10]) {
          final planned = planReminders(
            settings: _allOn,
            now: start,
            recordedToday: const {},
            pendingWorkoutDates: _dateKeys(start, days),
            days: days,
          );
          final label = '${jstDateKeyOf(start)} / $days日';

          expect(planned, hasLength(days * 5), reason: label);
          expect(
            planned.map((r) => r.id).toSet(),
            hasLength(planned.length),
            reason: label,
          );
          for (final r in planned) {
            expect(isReminderNotificationId(r.id), isTrue, reason: label);
            expect(
              r.id,
              _idOf(r.fireAt.year, r.fireAt.month, r.fireAt.day, r.kind),
              reason: '$label ${_describe(r)}',
            );
          }
        }
      }
    });

    test('UTC の日付ではなく日本時間の日付で数える（now の location に依らない）', () {
      // 2026-11-07 15:30 UTC = 2026-11-08 00:30 JST
      final nowUtc = tz.TZDateTime.utc(2026, 11, 7, 15, 30);
      final nowJst = _jst(2026, 11, 8, 0, 30);
      final pendingWorkoutDates = _dateKeys(nowJst, 7);

      final fromUtc = planReminders(
        settings: _allOn,
        now: nowUtc,
        recordedToday: const {ReminderKind.weight},
        pendingWorkoutDates: pendingWorkoutDates,
      );
      final fromJst = planReminders(
        settings: _allOn,
        now: nowJst,
        recordedToday: const {ReminderKind.weight},
        pendingWorkoutDates: pendingWorkoutDates,
      );

      expect(fromUtc, fromJst);
      // 「今日」は 11/8。記録済みで止まるのも 11/8 の体重
      expect(_describe(fromUtc.first), '2026-11-08 09:00 breakfast 7051');
      expect(fromUtc.map(_describe), contains('2026-11-09 07:30 weight 7060'));
      expect(
          fromUtc.every((r) => r.fireAt.location.name == 'Asia/Tokyo'), isTrue);
    });

    test('鳴らす時刻ちょうどの今は予約しない（今より後だけ）', () {
      final settings = _enabled([ReminderKind.lunch]);

      final atTime = planReminders(
        settings: settings,
        now: _jst(2026, 11, 7, 13, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {},
      );
      expect(_describe(atTime.first), '2026-11-08 13:00 lunch 7052');
      expect(atTime, hasLength(6));

      final justBefore = planReminders(
        settings: settings,
        now: _jst(2026, 11, 7, 12, 59, 59),
        recordedToday: const {},
        pendingWorkoutDates: const {},
      );
      expect(_describe(justBefore.first), '2026-11-07 13:00 lunch 7042');
      expect(justBefore, hasLength(7));
    });

    test('今日記録済みの項目は今日の分だけ止め、明日以降は予約する', () {
      final now = _jst(2026, 11, 7, 6, 0);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {ReminderKind.weight, ReminderKind.dinner},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      expect(planned.take(5).map(_describe), [
        '2026-11-07 09:00 breakfast 7041',
        '2026-11-07 13:00 lunch 7042',
        '2026-11-07 18:00 workout 7044',
        '2026-11-08 07:30 weight 7050',
        '2026-11-08 09:00 breakfast 7051',
      ]);
      // 今日（11/7）の体重 7040・夕食 7043 は止まり、明日（11/8）の夕食 7053 は鳴る
      expect(planned.map((r) => r.id), isNot(contains(7040)));
      expect(planned.map((r) => r.id), isNot(contains(7043)));
      expect(planned.map((r) => r.id), contains(7053));
      expect(planned, hasLength(3 + 6 * 5));
    });

    test('recordedToday にある項目は運動でも今日の分を止める', () {
      final planned = planReminders(
        settings: _enabled([ReminderKind.workout]),
        now: _jst(2026, 11, 7, 6, 0),
        recordedToday: const {ReminderKind.workout},
        pendingWorkoutDates: const {'2026-11-07', '2026-11-08'},
      );
      expect(planned.map(_describe), ['2026-11-08 18:00 workout 7054']);
    });

    test('運動は予定（未完了のセルフガイド）がある日だけ。窓の外の予定日は無視', () {
      final planned = planReminders(
        settings: _enabled([ReminderKind.workout]),
        now: _jst(2026, 11, 7, 12, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {'2026-11-07', '2026-11-09', '2026-11-20'},
      );
      expect(planned.map(_describe), [
        '2026-11-07 18:00 workout 7044',
        '2026-11-09 18:00 workout 7064',
      ]);
    });

    test('運動の予定日でも、時刻を過ぎていれば予約しない', () {
      final planned = planReminders(
        settings: _enabled([ReminderKind.workout]),
        now: _jst(2026, 11, 7, 19, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {'2026-11-07'},
      );
      expect(planned, isEmpty);
    });

    test('運動の予定日が無ければ、運動がオンでも1件も予約しない（ほかの項目は予約する）', () {
      final planned = planReminders(
        settings: _allOn,
        now: _jst(2026, 11, 7, 0, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {},
      );
      expect(planned.any((r) => r.kind == ReminderKind.workout), isFalse);
      expect(planned, hasLength(7 * 4));
    });

    test('時刻の順に並べ、同じ時刻は ReminderKind の並び（index）の順', () {
      final planned = planReminders(
        settings: _enabled(
          [ReminderKind.breakfast, ReminderKind.weight, ReminderKind.lunch],
          times: const {
            ReminderKind.weight: ReminderTime(hour: 8, minute: 0),
            ReminderKind.breakfast: ReminderTime(hour: 8, minute: 0),
            ReminderKind.lunch: ReminderTime(hour: 7, minute: 55),
          },
        ),
        now: _jst(2026, 11, 7, 0, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {},
        days: 2,
      );
      expect(planned.map(_describe), [
        '2026-11-07 07:55 lunch 7042',
        '2026-11-07 08:00 weight 7040',
        '2026-11-07 08:00 breakfast 7041',
        '2026-11-08 07:55 lunch 7052',
        '2026-11-08 08:00 weight 7050',
        '2026-11-08 08:00 breakfast 7051',
      ]);
    });

    test('同じ時刻が多数あっても（35件）各日 ReminderKind の並び', () {
      // List.sort は 32 件を超えると安定ソートではないので、同時刻の並びは index で決める必要がある
      const eight = ReminderTime(hour: 8, minute: 0);
      final now = _jst(2026, 11, 7, 0, 0);
      final planned = planReminders(
        settings: _enabled(
          ReminderKind.values,
          times: {for (final kind in ReminderKind.values) kind: eight},
        ),
        now: now,
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      expect(planned, hasLength(35));
      expect(planned.map((r) => r.id), [
        for (var day = 0; day < 7; day++)
          for (final kind in ReminderKind.values)
            _idOf(2026, 11, 7 + day, kind),
      ]);
    });

    test('ID・payload・文面・時刻（Asia/Tokyo）の形', () {
      final now = _jst(2026, 11, 7, 10, 0);
      final planned = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      // 11/9 の夕食 = 7000 + (11/9 の通し日数 % 10 = 6) * 10 + 3
      final dinner = planned.singleWhere((r) => r.id == 7063);
      expect(dinner.kind, ReminderKind.dinner);
      expect(dinner.fireAt, _jst(2026, 11, 9, 20, 0));
      expect(dinner.fireAt.location.name, 'Asia/Tokyo');
      expect(dinner.payload, 'record_reminder:dinner@202611092000');
      expect(dinner.title, '夕食の記録');
      expect(dinner.body, '夕食を記録しましょう');

      expect(planned.map((r) => r.id).toSet(), hasLength(planned.length));
      for (final r in planned) {
        expect(r.id, reminderNotificationId(r.fireAt, r.kind));
        expect(
          r.id,
          _idOf(r.fireAt.year, r.fireAt.month, r.fireAt.day, r.kind),
        );
        expect(r.payload, reminderPayload(r.kind, r.fireAt));
        expect(reminderKindFromPayload(r.payload), r.kind);
        expect(r.title, r.kind.notificationTitle);
        expect(r.body, r.kind.notificationBody);
      }
    });

    test('月末・年末をまたいでも日付が正しく進む', () {
      final planned = planReminders(
        settings: _enabled([ReminderKind.weight, ReminderKind.workout]),
        now: _jst(2026, 12, 29, 10, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {'2027-01-01'},
      );
      expect(planned.map(_describe), [
        '2026-12-30 07:30 weight 7070',
        '2026-12-31 07:30 weight 7080',
        '2027-01-01 07:30 weight 7090',
        '2027-01-01 18:00 workout 7094',
        '2027-01-02 07:30 weight 7000',
        '2027-01-03 07:30 weight 7010',
        '2027-01-04 07:30 weight 7020',
      ]);
      expect(
        planned.firstWhere((r) => r.id == 7090).payload,
        'record_reminder:weight@202701010730',
      );
    });

    test('days で日数を変えられる（0〜10。11日以上は窓の中で ID が重なるので RangeError）', () {
      List<PlannedReminder> plan(int days) => planReminders(
            settings: _allOn,
            now: _jst(2026, 11, 7, 0, 0),
            recordedToday: const {},
            pendingWorkoutDates: _dateKeys(_jst(2026, 11, 7), 11),
            days: days,
          );

      expect(plan(0), isEmpty);
      expect(_describe(plan(1).last), '2026-11-07 20:00 dinner 7043');
      final tenDays = plan(10);
      expect(tenDays, hasLength(50));
      expect(_describe(tenDays.last), '2026-11-16 20:00 dinner 7033');
      // 10日なら日付の桁 0〜9 を1回ずつ使い、重ならない
      expect(tenDays.map((r) => r.id).toSet(), hasLength(50));
      expect(() => plan(11), throwsRangeError);
      expect(() => plan(-1), throwsRangeError);
    });
  });

  group('通知 ID', () {
    test('7000 + (日本時間の暦日の通し日数 % 10) * 10 + kind.index', () {
      // 1970-01-01 は通し日数 0
      expect(
        reminderNotificationId(_jst(1970, 1, 1, 12, 0), ReminderKind.weight),
        7000,
      );
      expect(
        reminderNotificationId(_jst(1970, 1, 2, 12, 0), ReminderKind.weight),
        7010,
      );
      // 2026-11-07 は通し日数 20764（% 10 = 4）
      expect(
        reminderNotificationId(_jst(2026, 11, 7, 20, 0), ReminderKind.dinner),
        7043,
      );
      expect(
        reminderNotificationId(_jst(2026, 11, 12, 18, 0), ReminderKind.workout),
        7094,
      );
      // 2026-11-13 は 20770（% 10 = 0）
      expect(
        reminderNotificationId(_jst(2026, 11, 13, 7, 30), ReminderKind.weight),
        7000,
      );
    });

    test('同じ暦日なら時刻と location に依らない（日本時間の日付で決まる）', () {
      final sameDay = [
        _jst(2026, 11, 7, 0, 0),
        _jst(2026, 11, 7, 23, 59, 59),
        // 11/6 15:00 UTC = 11/7 00:00 JST（UTC の日付では 11/6）
        tz.TZDateTime.utc(2026, 11, 6, 15, 0),
        // 11/7 14:59 UTC = 11/7 23:59 JST
        tz.TZDateTime.utc(2026, 11, 7, 14, 59),
      ];
      for (final t in sameDay) {
        expect(
          reminderNotificationId(t, ReminderKind.lunch),
          7042,
          reason: t.toIso8601String(),
        );
      }
      // 11/7 15:00 UTC = 11/8 00:00 JST（UTC の日付では 11/7）
      expect(
        reminderNotificationId(
          tz.TZDateTime.utc(2026, 11, 7, 15, 0),
          ReminderKind.lunch,
        ),
        7052,
      );
    });

    test('連続する10日では重ならず、10日後に同じ ID に戻る（月末・年末・うるう日をまたいでも連続）', () {
      for (final start in [
        _jst(2026, 11, 7),
        _jst(2026, 12, 27),
        _jst(2028, 2, 25),
      ]) {
        int idAfter(int days) => reminderNotificationId(
              _jst(start.year, start.month, start.day + days),
              ReminderKind.weight,
            );
        final digits = [for (var i = 0; i < 10; i++) (idAfter(i) - 7000) ~/ 10];

        expect(digits.toSet(), hasLength(10), reason: '$start');
        // 1日ごとに 1 ずつ進む（9 の次は 0）
        for (var i = 1; i < 10; i++) {
          expect(digits[i], (digits[i - 1] + 1) % 10, reason: '$start +$i');
        }
        expect(idAfter(10), idAfter(0), reason: '$start');
      }

      expect(reminderNotificationId(_jst(2026, 12, 31), ReminderKind.weight),
          7080);
      expect(
          reminderNotificationId(_jst(2027, 1, 1), ReminderKind.weight), 7090);
      expect(
          reminderNotificationId(_jst(2027, 1, 2), ReminderKind.weight), 7000);
      expect(
          reminderNotificationId(_jst(2028, 2, 28), ReminderKind.weight), 7020);
      expect(
          reminderNotificationId(_jst(2028, 2, 29), ReminderKind.weight), 7030);
      expect(
          reminderNotificationId(_jst(2028, 3, 1), ReminderKind.weight), 7040);
    });

    test('7000〜7099 だけをリマインダーの ID とみなす', () {
      for (final id in [7000, 7004, 7064, 7099]) {
        expect(isReminderNotificationId(id), isTrue, reason: '$id');
      }
      // ヘルスケア同期エラー 9001・FCM の hashCode など
      for (final id in [6999, 7100, 9001, 0, -7000, 123456789]) {
        expect(isReminderNotificationId(id), isFalse, reason: '$id');
      }
    });
  });

  group('payload', () {
    test("'record_reminder:<key>@<日本時間 yyyyMMddHHmm>'（0 埋め）", () {
      expect(
        reminderPayload(ReminderKind.dinner, _jst(2026, 11, 7, 20, 0)),
        'record_reminder:dinner@202611072000',
      );
      expect(
        reminderPayload(ReminderKind.weight, _jst(2026, 1, 5, 7, 5)),
        'record_reminder:weight@202601050705',
      );
    });

    test('UTC で渡しても日本時間の日時で書く', () {
      expect(
        reminderPayload(
          ReminderKind.dinner,
          tz.TZDateTime.utc(2026, 11, 7, 11, 0),
        ),
        'record_reminder:dinner@202611072000',
      );
      // 15:05 UTC = 翌日 00:05 JST
      expect(
        reminderPayload(
          ReminderKind.weight,
          tz.TZDateTime.utc(2026, 11, 7, 15, 5),
        ),
        'record_reminder:weight@202611080005',
      );
    });

    test('NotificationService の分け方（":" で type と id）と往復する', () {
      for (final kind in ReminderKind.values) {
        final payload = reminderPayload(kind, _jst(2026, 11, 7, 18, 30));
        final parts = payload.split(':');

        expect(parts, hasLength(2), reason: payload);
        expect(parts[0], reminderPayloadType);
        expect(parts[1], '${kind.key}@202611071830');
        expect(reminderKindFromTapId(parts[1]), kind);
        expect(reminderKindFromPayload(payload), kind);
      }
    });

    test('reminderKindFromPayload: リマインダー以外・知らない項目は null', () {
      for (final payload in [
        'health_sync_error',
        'message:abc',
        'session_reminder:123',
        'record_reminder:sleep@202611072000',
        'record_reminder:',
        'record_reminder',
        'Record_reminder:dinner@202611072000',
        '',
      ]) {
        expect(reminderKindFromPayload(payload), isNull, reason: payload);
      }
      // 時刻が無くても項目は読める
      expect(
        reminderKindFromPayload('record_reminder:dinner'),
        ReminderKind.dinner,
      );
    });

    test("reminderKindFromTapId: '@' より前を key として読む", () {
      expect(
        reminderKindFromTapId('dinner@202611072000'),
        ReminderKind.dinner,
      );
      expect(reminderKindFromTapId('workout'), ReminderKind.workout);
      expect(reminderKindFromTapId(null), isNull);
      expect(reminderKindFromTapId(''), isNull);
      expect(reminderKindFromTapId('@202611072000'), isNull);
      expect(reminderKindFromTapId('sleep@202611072000'), isNull);
    });
  });

  group('diffReminders', () {
    List<PlannedReminder> plan(
      RecordReminderSettings settings,
      tz.TZDateTime now,
    ) =>
        planReminders(
          settings: settings,
          now: now,
          recordedToday: const {},
          pendingWorkoutDates: _dateKeys(now, 7),
        );

    test('ID と payload が同じ予約はそのまま（取り消しも予約もしない）', () {
      final planned = plan(_allOn, _jst(2026, 11, 7, 10, 0));
      final diff = diffReminders(planned, _pendingOf(planned));

      expect(diff.isEmpty, isTrue);
      expect(diff.cancelIds, isEmpty);
      expect(diff.toSchedule, isEmpty);
    });

    test('端末に予約が無ければ全部を予約する（planReminders の順）', () {
      final planned = plan(_allOn, _jst(2026, 11, 7, 10, 0));
      final diff = diffReminders(planned, const []);

      expect(diff.cancelIds, isEmpty);
      expect(diff.toSchedule, planned);
    });

    test('あるべき予約が無ければ（すべてオフなど）リマインダーの予約を全部取り消す', () {
      final before = plan(_allOn, _jst(2026, 11, 7, 10, 0));
      final diff = diffReminders(const [], _pendingOf(before));

      expect(diff.cancelIds, before.map((r) => r.id).toList());
      expect(diff.toSchedule, isEmpty);
    });

    test('時刻を変えた項目は、同じ ID を取り消してから予約し直す（ほかは残す）', () {
      final now = _jst(2026, 11, 7, 10, 0);
      final before = plan(
        _enabled([ReminderKind.weight, ReminderKind.dinner]),
        now,
      );
      final after = plan(
        _enabled(
          [ReminderKind.weight, ReminderKind.dinner],
          times: const {ReminderKind.dinner: ReminderTime(hour: 21, minute: 0)},
        ),
        now,
      );

      final diff = diffReminders(after, _pendingOf(before));

      // 11/7〜11/13 の夕食（予約一覧の順）
      final dinnerIds = [7043, 7053, 7063, 7073, 7083, 7093, 7003];
      expect(diff.cancelIds, dinnerIds);
      expect(diff.toSchedule.map((r) => r.id), dinnerIds);
      expect(
          diff.toSchedule.every((r) => r.kind == ReminderKind.dinner), isTrue);
      expect(diff.toSchedule.every((r) => r.fireAt.hour == 21), isTrue);
      expect(
        diff.toSchedule.first.payload,
        'record_reminder:dinner@202611072100',
      );
    });

    test('7000〜7099 以外の ID には触れない', () {
      final diff = diffReminders(const [], const [
        PendingReminder(id: 9001, payload: 'health_sync_error'),
        PendingReminder(id: 123456789, payload: 'message:abc'),
        PendingReminder(id: 6999),
        PendingReminder(
            id: 7100, payload: 'record_reminder:weight@202611080730'),
        PendingReminder(id: -1),
        PendingReminder(
            id: 7099, payload: 'record_reminder:weight@202611080730'),
      ]);

      expect(diff.cancelIds, [7099]);
      expect(diff.toSchedule, isEmpty);
    });

    test('payload が無い・違うリマインダーの予約は取り消して予約し直す', () {
      final planned = planReminders(
        settings: _enabled([ReminderKind.weight]),
        now: _jst(2026, 11, 7, 6, 0),
        recordedToday: const {},
        pendingWorkoutDates: const {},
        days: 1,
      );
      expect(planned.map(_describe), ['2026-11-07 07:30 weight 7040']);

      for (final pending in const [
        PendingReminder(id: 7040),
        PendingReminder(
            id: 7040, payload: 'record_reminder:weight@202611070700'),
        PendingReminder(
            id: 7040, payload: 'record_reminder:breakfast@202611070730'),
      ]) {
        final diff = diffReminders(planned, [pending]);
        expect(diff.cancelIds, [7040], reason: '$pending');
        expect(diff.toSchedule, planned, reason: '$pending');
      }
    });

    test('翌日に予約し直すと、重なる6日分はそのまま残し、新しい1日分だけを予約する', () {
      // 11/7 10:00 に予約した 11/7〜11/13 のうち、11/8 06:00 に端末に残っているのは 11/8〜11/13 の分
      final yesterday = plan(_allOn, _jst(2026, 11, 7, 10, 0));
      final now = _jst(2026, 11, 8, 6, 0);
      final pending = _pendingOf(
        yesterday.where((r) => r.fireAt.isAfter(now)).toList(),
      );
      expect(pending, hasLength(6 * 5));

      final today = plan(_allOn, now);
      final diff = diffReminders(today, pending);

      // 予約中で、あるべき予約にもあるものは取り消さない
      expect(diff.cancelIds, isEmpty);
      expect(diff.toSchedule.map(_describe), [
        '2026-11-14 07:30 weight 7010',
        '2026-11-14 09:00 breakfast 7011',
        '2026-11-14 13:00 lunch 7012',
        '2026-11-14 18:00 workout 7014',
        '2026-11-14 20:00 dinner 7013',
      ]);
    });

    test('鳴り終わった前日の予約が一覧に残っていても、取り消すのはそれだけ', () {
      final yesterday = plan(_allOn, _jst(2026, 11, 7, 10, 0));
      final today = plan(_allOn, _jst(2026, 11, 8, 6, 0));

      // 11/7 の 13:00・18:00・20:00 の分まで一覧に残っている場合
      final diff = diffReminders(today, _pendingOf(yesterday));

      expect(diff.cancelIds, [7042, 7044, 7043]);
      expect(
        diff.cancelIds.toSet().intersection(today.map((r) => r.id).toSet()),
        isEmpty,
      );
      expect(
        diff.toSchedule.map((r) => jstDateKeyOf(r.fireAt)).toSet(),
        {'2026-11-14'},
      );
    });

    test('今日の記録を送ったら、今日のその項目の分だけを取り消す', () {
      final now = _jst(2026, 11, 8, 12, 0);
      final before = plan(_allOn, now);
      final after = planReminders(
        settings: _allOn,
        now: now,
        recordedToday: const {ReminderKind.dinner},
        pendingWorkoutDates: _dateKeys(now, 7),
      );

      final diff = diffReminders(after, _pendingOf(before));

      // 11/8 の夕食だけ。11/9 以降の夕食（7063 など）は残す
      expect(diff.cancelIds, [7053]);
      expect(diff.toSchedule, isEmpty);
    });

    test('予約一覧に同じ ID が重なっていても取り消しは1回', () {
      final diff = diffReminders(const [], const [
        PendingReminder(
            id: 7000, payload: 'record_reminder:weight@202611070730'),
        PendingReminder(
            id: 7000, payload: 'record_reminder:weight@202611080730'),
      ]);
      expect(diff.cancelIds, [7000]);
    });

    group('rescheduleAll（Android の起動時。予約一覧を「予約済み」の根拠にしない）', () {
      test('同じ予約（ID と payload が同じ）が一覧にあっても、あるべき予約をすべて予約し直す（先に取り消さない）', () {
        final planned = plan(_allOn, _jst(2026, 11, 7, 10, 0));

        final diff =
            diffReminders(planned, _pendingOf(planned), rescheduleAll: true);

        expect(diff.cancelIds, isEmpty);
        expect(diff.toSchedule, planned);
      });

      test('あるべき予約に無い ID だけを取り消す（時刻を変えた項目は、取り消さずに予約で置き換える）', () {
        final now = _jst(2026, 11, 7, 10, 0);
        final before = plan(
          _enabled([ReminderKind.weight, ReminderKind.dinner]),
          now,
        );
        final after = plan(
          _enabled(
            [ReminderKind.dinner],
            times: const {
              ReminderKind.dinner: ReminderTime(hour: 21, minute: 0)
            },
          ),
          now,
        );

        final diff =
            diffReminders(after, _pendingOf(before), rescheduleAll: true);

        // 11/8〜11/13 の体重（11/7 の 07:30 は過ぎている。予約一覧の順）
        expect(diff.cancelIds, [7050, 7060, 7070, 7080, 7090, 7000]);
        expect(diff.toSchedule, after);
      });

      test('7000〜7099 以外の ID には触れず、同じ ID が重なっていても取り消しは1回', () {
        final diff = diffReminders(
          const [],
          const [
            PendingReminder(id: 9001, payload: 'health_sync_error'),
            PendingReminder(
                id: 7100, payload: 'record_reminder:weight@202611080730'),
            PendingReminder(
                id: 7000, payload: 'record_reminder:weight@202611070730'),
            PendingReminder(
                id: 7000, payload: 'record_reminder:weight@202611080730'),
          ],
          rescheduleAll: true,
        );

        expect(diff.cancelIds, [7000]);
        expect(diff.toSchedule, isEmpty);
      });
    });
  });

  group('reminderKindsFromTags（parse-message-tags と同じ判定・最初のタグだけ）', () {
    test('食事の種類', () {
      expect(reminderKindsFromTags(['#食事:朝食']), {ReminderKind.breakfast});
      expect(reminderKindsFromTags(['#食事:昼食']), {ReminderKind.lunch});
      expect(reminderKindsFromTags(['#食事:夕食']), {ReminderKind.dinner});
      expect(reminderKindsFromTags(['#食事:夕ご飯']), {ReminderKind.dinner});
      expect(reminderKindsFromTags(['#食事:晩']), {ReminderKind.dinner});
      expect(reminderKindsFromTags(['#食事:晩ごはん']), {ReminderKind.dinner});
    });

    test('間食・詳細なしの #食事（サーバーでは snack）は対象外', () {
      expect(reminderKindsFromTags(['#食事:間食']), isEmpty);
      expect(reminderKindsFromTags(['#食事']), isEmpty);
      expect(reminderKindsFromTags(['#食事:おやつ']), isEmpty);
      expect(reminderKindsFromTags(['#食事:breakfast']), isEmpty);
    });

    test('詳細は「朝」→「昼」→「夕」か「晩」の順に調べる（文字の位置ではない）', () {
      expect(reminderKindsFromTags(['#食事:朝昼兼用']), {ReminderKind.breakfast});
      expect(reminderKindsFromTags(['#食事:夕方に朝ごはん']), {ReminderKind.breakfast});
      expect(reminderKindsFromTags(['#食事:昼と晩']), {ReminderKind.lunch});
      expect(reminderKindsFromTags(['#食事:昼から夕方']), {ReminderKind.lunch});
    });

    test('#体重 は体重（詳細があっても）', () {
      expect(reminderKindsFromTags(['#体重']), {ReminderKind.weight});
      expect(reminderKindsFromTags(['#体重:65.2']), {ReminderKind.weight});
    });

    test('#運動 は対象外（運動はプランの割り当てで判定する）', () {
      expect(reminderKindsFromTags(['#運動:完了']), isEmpty);
      expect(reminderKindsFromTags(['#運動']), isEmpty);
      expect(reminderKindsFromTags(['#運動:筋トレ']), isEmpty);
    });

    test('最初のタグだけを見る', () {
      expect(reminderKindsFromTags(['#運動:完了', '#体重']), isEmpty);
      expect(
        reminderKindsFromTags(['#体重', '#食事:夕食']),
        {ReminderKind.weight},
      );
      expect(reminderKindsFromTags(['#食事:間食', '#食事:夕食']), isEmpty);
      expect(
        reminderKindsFromTags(['#食事:昼食', '#食事:朝食']),
        {ReminderKind.lunch},
      );
    });

    test('タグなし・サーバーの形に合わないタグは対象外', () {
      expect(reminderKindsFromTags(const []), isEmpty);
      for (final tag in [
        '#meal', // 別名（アプリは正準形に直して送る）
        '#weight',
        '#exercise',
        '体重', // # なし
        '#体重 ', // 前後の空白（サーバーの判定は完全一致）
        ' #体重',
        '#食事:', // 詳細が空
        '#体重記録',
        '#睡眠',
        '',
      ]) {
        expect(reminderKindsFromTags([tag]), isEmpty, reason: tag);
      }
    });

    test('アプリが送るタグ（parseMessageTags の結果）での推定', () {
      Set<ReminderKind> fromText(String text) =>
          reminderKindsFromTags(parseMessageTags(text) ?? const []);

      // 別名は正準形に直ってから tags に入る
      expect(fromText('#meal 朝食 トースト'), {ReminderKind.breakfast});
      expect(fromText('#weight 65.2'), {ReminderKind.weight});
      expect(fromText('#食事:夕食 カレー'), {ReminderKind.dinner});
      // 「夕食」と書かないと #食事（間食扱い）になる
      expect(fromText('#食事 夕ご飯 カレー'), isEmpty);
      expect(fromText('#運動:完了 脚の日'), isEmpty);
      expect(fromText('こんにちは'), isEmpty);
    });

    test('通知から開いたタグに続けて送ると、その項目が今日の記録済みになる', () {
      for (final kind in ReminderKind.values) {
        final draft = kind.messageDraft;
        if (draft == null) continue;
        final tags = parseMessageTags('${draft}65.2 メモ');
        expect(reminderKindsFromTags(tags!), {kind}, reason: draft);
      }
    });
  });

  group('jstDayRangeUtc', () {
    test('今日 00:00 JST 〜 翌日 00:00 JST を UTC で返す', () {
      final range = jstDayRangeUtc(_jst(2026, 11, 7, 10, 0));

      expect(range.startUtc, DateTime.utc(2026, 11, 6, 15));
      expect(range.endUtc, DateTime.utc(2026, 11, 7, 15));
      expect(range.startUtc.isUtc, isTrue);
      expect(range.endUtc.isUtc, isTrue);
      expect(range.endUtc.difference(range.startUtc), const Duration(days: 1));
      // 時差付き（Z）の文字列で DB と比べる
      expect(range.startUtc.toIso8601String(), '2026-11-06T15:00:00.000Z');
      expect(range.endUtc.toIso8601String(), '2026-11-07T15:00:00.000Z');
      // 普通の DateTime（TZDateTime ではない）
      expect(range.startUtc, isNot(isA<tz.TZDateTime>()));
    });

    test('日付の変わり目: 00:00 と 23:59:59 は同じ日、翌 00:00 から次の日', () {
      final day7 = (
        startUtc: DateTime.utc(2026, 11, 6, 15),
        endUtc: DateTime.utc(2026, 11, 7, 15),
      );
      expect(jstDayRangeUtc(_jst(2026, 11, 7, 0, 0)), day7);
      expect(jstDayRangeUtc(_jst(2026, 11, 7, 23, 59, 59)), day7);
      expect(jstDayRangeUtc(_jst(2026, 11, 8, 0, 0)), (
        startUtc: DateTime.utc(2026, 11, 7, 15),
        endUtc: DateTime.utc(2026, 11, 8, 15),
      ));
    });

    test('UTC で渡しても日本時間の日で区切る', () {
      // 15:30 UTC = 翌日 00:30 JST
      expect(jstDayRangeUtc(tz.TZDateTime.utc(2026, 11, 7, 15, 30)), (
        startUtc: DateTime.utc(2026, 11, 7, 15),
        endUtc: DateTime.utc(2026, 11, 8, 15),
      ));
      // 14:59 UTC = 23:59 JST（まだ 11/7）
      expect(jstDayRangeUtc(tz.TZDateTime.utc(2026, 11, 7, 14, 59)), (
        startUtc: DateTime.utc(2026, 11, 6, 15),
        endUtc: DateTime.utc(2026, 11, 7, 15),
      ));
    });

    test('年末: 12/31 の終わりは 1/1 00:00 JST', () {
      expect(jstDayRangeUtc(_jst(2026, 12, 31, 12, 0)), (
        startUtc: DateTime.utc(2026, 12, 30, 15),
        endUtc: DateTime.utc(2026, 12, 31, 15),
      ));
    });
  });

  group('jstDateKeyOf', () {
    test("日本時間の日付 'YYYY-MM-DD'（0 埋め）", () {
      expect(jstDateKeyOf(_jst(2026, 11, 7, 23, 59)), '2026-11-07');
      expect(jstDateKeyOf(_jst(2026, 11, 8, 0, 0)), '2026-11-08');
      expect(jstDateKeyOf(_jst(2026, 1, 5)), '2026-01-05');
    });

    test('UTC で渡しても日本時間の日付', () {
      expect(jstDateKeyOf(tz.TZDateTime.utc(2026, 11, 7, 15, 0)), '2026-11-08');
      expect(
          jstDateKeyOf(tz.TZDateTime.utc(2026, 11, 7, 14, 59)), '2026-11-07');
    });
  });
}
