import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';

void main() {
  group('RecordStreakStatus.fromRow（get_record_streak の 1 行）', () {
    test('日付・真偽・整数を読む', () {
      final status = RecordStreakStatus.fromRow({
        'as_of_date': '2026-11-23',
        'recorded_today': true,
        'streak_until_yesterday': 12,
      });

      expect(status.asOfDate, '2026-11-23');
      expect(status.recordedToday, isTrue);
      expect(status.streakUntilYesterday, 12);
    });

    test('記録が無い人の行 (今日, false, 0)', () {
      final status = RecordStreakStatus.fromRow({
        'as_of_date': '2026-01-05',
        'recorded_today': false,
        'streak_until_yesterday': 0,
      });

      expect(
        status,
        const RecordStreakStatus(
          asOfDate: '2026-01-05',
          recordedToday: false,
          streakUntilYesterday: 0,
        ),
      );
    });

    test('日数が整数でなく数値（5.0）で来ても整数にする', () {
      final status = RecordStreakStatus.fromRow({
        'as_of_date': '2026-11-23',
        'recorded_today': false,
        'streak_until_yesterday': 5.0,
      });

      expect(status.streakUntilYesterday, 5);
      expect(status.streakUntilYesterday, isA<int>());
    });

    test('列が無い・型が違う行は例外（provider がエラーになり、ホームは行を出さない）', () {
      expect(
        () => RecordStreakStatus.fromRow({
          'as_of_date': '2026-11-23',
          'streak_until_yesterday': 3,
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => RecordStreakStatus.fromRow({
          'as_of_date': '2026-11-23',
          'recorded_today': 'true',
          'streak_until_yesterday': 3,
        }),
        throwsA(isA<TypeError>()),
      );
      expect(
        () => RecordStreakStatus.fromRow({
          'as_of_date': null,
          'recorded_today': true,
          'streak_until_yesterday': 3,
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('RecordStreakStatus の等しさ', () {
    const base = RecordStreakStatus(
      asOfDate: '2026-11-23',
      recordedToday: false,
      streakUntilYesterday: 3,
    );

    test('同じ値なら等しく、hashCode も同じ', () {
      const same = RecordStreakStatus(
        asOfDate: '2026-11-23',
        recordedToday: false,
        streakUntilYesterday: 3,
      );
      expect(same, base);
      expect(same.hashCode, base.hashCode);
    });

    test('どれか 1 つでも違えば等しくない', () {
      expect(
        const RecordStreakStatus(
          asOfDate: '2026-11-24',
          recordedToday: false,
          streakUntilYesterday: 3,
        ),
        isNot(base),
      );
      expect(
        const RecordStreakStatus(
          asOfDate: '2026-11-23',
          recordedToday: true,
          streakUntilYesterday: 3,
        ),
        isNot(base),
      );
      expect(
        const RecordStreakStatus(
          asOfDate: '2026-11-23',
          recordedToday: false,
          streakUntilYesterday: 4,
        ),
        isNot(base),
      );
    });
  });
}
