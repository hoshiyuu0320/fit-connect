import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';

RecordStreakStatus _status({
  required bool recordedToday,
  required int untilYesterday,
}) =>
    RecordStreakStatus(
      asOfDate: '2026-11-23',
      recordedToday: recordedToday,
      streakUntilYesterday: untilYesterday,
    );

void main() {
  group('recordStreakViewOf（設計 §4）', () {
    group('今日記録済み → 昨日までの日数 + 1', () {
      test('昨日まで 0 日 → 1 日目', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: true, untilYesterday: 0),
            countedTodayByTags: false,
          ),
          const RecordStreakRecordedToday(days: 1),
        );
      });

      test('昨日まで 1 日 → 2 日', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: true, untilYesterday: 1),
            countedTodayByTags: false,
          ),
          const RecordStreakRecordedToday(days: 2),
        );
      });

      test('昨日まで 5 日 → 6 日', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: true, untilYesterday: 5),
            countedTodayByTags: false,
          ),
          const RecordStreakRecordedToday(days: 6),
        );
      });
    });

    group('今日まだ', () {
      test('昨日まで 0 日 → 続いていない', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 0),
            countedTodayByTags: false,
          ),
          const RecordStreakNone(),
        );
      });

      test('昨日まで 1 日 → 続いている（1 日。今日の分は今日が終わるまで切れない）', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 1),
            countedTodayByTags: false,
          ),
          const RecordStreakAlive(days: 1),
        );
      });

      test('昨日まで 5 日 → 続いている（5 日）', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 5),
            countedTodayByTags: false,
          ),
          const RecordStreakAlive(days: 5),
        );
      });
    });

    group('送ったタグの先取り（設計 §6.3）', () {
      test('「今日まだ」が「今日記録済み」になる（続いていない → 1 日目）', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 0),
            countedTodayByTags: true,
          ),
          const RecordStreakRecordedToday(days: 1),
        );
      });

      test('「今日まだ」が「今日記録済み」になる（続いている → 昨日までの日数 + 1）', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 1),
            countedTodayByTags: true,
          ),
          const RecordStreakRecordedToday(days: 2),
        );
        expect(
          recordStreakViewOf(
            _status(recordedToday: false, untilYesterday: 5),
            countedTodayByTags: true,
          ),
          const RecordStreakRecordedToday(days: 6),
        );
      });

      test('DB でも今日記録済みなら、二重には数えない', () {
        expect(
          recordStreakViewOf(
            _status(recordedToday: true, untilYesterday: 5),
            countedTodayByTags: true,
          ),
          const RecordStreakRecordedToday(days: 6),
        );
      });
    });

    test('昨日までの日数が負（DB は返さない）なら 0 として扱う', () {
      expect(
        recordStreakViewOf(
          _status(recordedToday: false, untilYesterday: -1),
          countedTodayByTags: false,
        ),
        const RecordStreakNone(),
      );
      expect(
        recordStreakViewOf(
          _status(recordedToday: true, untilYesterday: -1),
          countedTodayByTags: false,
        ),
        const RecordStreakRecordedToday(days: 1),
      );
    });

    test('基準の日（asOfDate）には依らない（日付の突き合わせは provider が行う）', () {
      for (final date in ['2026-01-01', '2026-11-23', '2027-02-28']) {
        expect(
          recordStreakViewOf(
            RecordStreakStatus(
              asOfDate: date,
              recordedToday: false,
              streakUntilYesterday: 3,
            ),
            countedTodayByTags: false,
          ),
          const RecordStreakAlive(days: 3),
          reason: date,
        );
      }
    });
  });

  group('RecordStreakView の等しさ', () {
    test('同じ種類・同じ日数なら等しく、hashCode も同じ', () {
      expect(
        const RecordStreakRecordedToday(days: 3),
        const RecordStreakRecordedToday(days: 3),
      );
      expect(
        const RecordStreakRecordedToday(days: 3).hashCode,
        const RecordStreakRecordedToday(days: 3).hashCode,
      );
      expect(
          const RecordStreakAlive(days: 3), const RecordStreakAlive(days: 3));
      expect(
        const RecordStreakAlive(days: 3).hashCode,
        const RecordStreakAlive(days: 3).hashCode,
      );
      expect(const RecordStreakNone(), const RecordStreakNone());
      expect(
          const RecordStreakNone().hashCode, const RecordStreakNone().hashCode);
    });

    test('日数か種類が違えば等しくない', () {
      expect(
        const RecordStreakRecordedToday(days: 3),
        isNot(const RecordStreakRecordedToday(days: 4)),
      );
      expect(
        const RecordStreakAlive(days: 3),
        isNot(const RecordStreakAlive(days: 4)),
      );
      // 同じ日数でも「今日記録済み」と「今日まだ」は別
      expect(
        const RecordStreakRecordedToday(days: 3),
        isNot(const RecordStreakAlive(days: 3)),
      );
      expect(
        const RecordStreakAlive(days: 1),
        isNot(const RecordStreakNone()),
      );
    });

    test('switch で 3 つの状態を漏れなく分けられる（sealed）', () {
      String describe(RecordStreakView view) => switch (view) {
            RecordStreakRecordedToday(:final days) => '今日記録済み $days',
            RecordStreakAlive(:final days) => '今日まだ $days',
            RecordStreakNone() => '続いていない',
          };

      expect(describe(const RecordStreakRecordedToday(days: 13)), '今日記録済み 13');
      expect(describe(const RecordStreakAlive(days: 12)), '今日まだ 12');
      expect(describe(const RecordStreakNone()), '続いていない');
    });
  });
}
