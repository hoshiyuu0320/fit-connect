import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';

void main() {
  group('jstDateKey', () {
    test('UTC 14:00 → JST 23:00 (same day)', () {
      final utc = DateTime.utc(2026, 4, 19, 14, 0);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('UTC 15:00 → JST 00:00 (next day) — day boundary', () {
      final utc = DateTime.utc(2026, 4, 19, 15, 0);
      expect(jstDateKey(utc), '2026-04-20');
    });

    test('UTC 22:00 4/18 → JST 07:00 4/19 (typical morning wake)', () {
      final utc = DateTime.utc(2026, 4, 18, 22, 0);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('UTC 14:59:59 → JST 23:59:59 same day', () {
      final utc = DateTime.utc(2026, 4, 19, 14, 59, 59);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('zero-pads month and day', () {
      final utc = DateTime.utc(2026, 1, 5, 2, 0);
      expect(jstDateKey(utc), '2026-01-05');
    });
  });

  group('todayJstDateKey', () {
    test('returns valid YYYY-MM-DD format', () {
      final result = todayJstDateKey();
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('jstDateKeyDaysAgo', () {
    test('returns valid YYYY-MM-DD format for 30 days ago', () {
      final result = jstDateKeyDaysAgo(30);
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('returns today key for 0 days ago', () {
      expect(jstDateKeyDaysAgo(0), todayJstDateKey());
    });
  });
}
