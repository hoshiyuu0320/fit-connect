import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/weight_records/presentation/widgets/weight_format.dart';

void main() {
  group('日付の整形', () {
    test('日付は「9月13日（日）」、日時は「9月13日（日）7:30」（分は 2 桁）', () {
      // 2026-09-13 は日曜日
      expect(formatJpDate(DateTime(2026, 9, 13)), '9月13日（日）');
      expect(formatJpDateTime(DateTime(2026, 9, 13, 7, 30)), '9月13日（日）7:30');
      expect(formatJpDateTime(DateTime(2026, 9, 7, 21, 5)), '9月7日（月）21:05');
    });

    test('範囲は同じ月なら「9月1日〜13日」、月をまたぐなら両方の月を出す', () {
      expect(
        formatJpRange(DateTime(2026, 9, 1), DateTime(2026, 9, 13)),
        '9月1日〜13日',
      );
      expect(
        formatJpRange(DateTime(2026, 6, 13), DateTime(2026, 9, 13)),
        '6月13日〜9月13日',
      );
      expect(
        formatJpRange(DateTime(2026, 9, 13), DateTime(2026, 9, 13)),
        '9月13日',
      );
    });

    test('x ラベルは「9/13」', () {
      expect(formatMonthDay(DateTime(2026, 9, 13)), '9/13');
    });
  });

  group('体重の整形', () {
    test('kg は小数 1 桁', () {
      expect(formatKg(62.4), '62.4');
      expect(formatKg(65), '65.0');
    });

    test('差は符号つき。丸めて 0 なら符号なしの 0.0（-0.0 を出さない）', () {
      expect(formatSignedKg(1.4), '+1.4');
      expect(formatSignedKg(-0.8), '-0.8');
      expect(formatSignedKg(0), '0.0');
      expect(formatSignedKg(-0.04), '0.0');
    });
  });

  group('グラフの x ラベルの位置', () {
    test('7 点なら正本どおり 0・2・4・6 番目（9/1・9/5・9/9・9/13）', () {
      expect(chartLabelIndices(7), {0, 2, 4, 6});
    });

    test('点が少ないときは全部、多いときも 4 つまで（最初と最後を含む）', () {
      expect(chartLabelIndices(0), isEmpty);
      expect(chartLabelIndices(1), {0});
      expect(chartLabelIndices(2), {0, 1});
      expect(chartLabelIndices(3), {0, 1, 2});
      final many = chartLabelIndices(90);
      expect(many.length, 4);
      expect(many.first, 0);
      expect(many.last, 89);
    });
  });
}
