import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';

/// セッションの表示整形（一覧・ホームカード・「変更を相談」の定型文で共用）のテスト。
///
/// 表示と定型文で文面がズレると実害があるため、規則はこの1実装に集約されている。
void main() {
  group('formatSessionDateTime', () {
    test('同じ年なら年を省略する', () {
      expect(
        formatSessionDateTime(
          DateTime(2026, 9, 10, 18, 0),
          now: DateTime(2026, 9, 6, 12, 0),
        ),
        '9月10日(木) 18:00',
      );
    });

    test('年が違えば年を付ける（過去50件が年をまたいでも曖昧にならない）', () {
      expect(
        formatSessionDateTime(
          DateTime(2025, 12, 24, 9, 5),
          now: DateTime(2026, 9, 6, 12, 0),
        ),
        '2025年12月24日(水) 09:05',
      );
    });

    test('includeYear:true なら同じ年でも年を付ける（過去タブ）', () {
      expect(
        formatSessionDateTime(
          DateTime(2026, 9, 1, 7, 30),
          now: DateTime(2026, 9, 6, 12, 0),
          includeYear: true,
        ),
        '2026年9月1日(火) 07:30',
      );
    });

    test('曜日は月曜始まりで正しく対応する', () {
      // 2026-09-07(月) 〜 2026-09-13(日)
      const expected = ['月', '火', '水', '木', '金', '土', '日'];
      for (var i = 0; i < expected.length; i++) {
        final date = DateTime(2026, 9, 7 + i, 10, 0);
        expect(
          formatSessionDateTime(date, now: DateTime(2026, 9, 6)),
          contains('(${expected[i]})'),
        );
      }
    });
  });

  group('formatSessionDateTimeDisplay', () {
    test('全角括弧・時刻の前にスペースなし・時は 0 埋めなし（正本の表記）', () {
      expect(
        formatSessionDateTimeDisplay(
          DateTime(2026, 9, 15, 19, 0),
          now: DateTime(2026, 9, 13, 12, 0),
        ),
        '9月15日（火）19:00',
      );
      expect(
        formatSessionDateTimeDisplay(
          DateTime(2026, 9, 9, 7, 5),
          now: DateTime(2026, 9, 6),
        ),
        '9月9日（水）7:05',
      );
    });

    test('年が違う / includeYear:true なら年を付ける', () {
      expect(
        formatSessionDateTimeDisplay(
          DateTime(2025, 12, 24, 9, 5),
          now: DateTime(2026, 9, 6),
        ),
        '2025年12月24日（水）9:05',
      );
      expect(
        formatSessionDateTimeDisplay(
          DateTime(2026, 9, 1, 7, 30),
          now: DateTime(2026, 9, 6),
          includeYear: true,
        ),
        '2026年9月1日（火）7:30',
      );
    });

    test('曜日は月曜始まりで正しく対応する', () {
      const expected = ['月', '火', '水', '木', '金', '土', '日'];
      for (var i = 0; i < expected.length; i++) {
        final date = DateTime(2026, 9, 7 + i, 10, 0);
        expect(
          formatSessionDateTimeDisplay(date, now: DateTime(2026, 9, 6)),
          contains('（${expected[i]}）'),
        );
      }
    });

    test('定型文用の formatSessionDateTime とは別の表記のまま（半角括弧）', () {
      final date = DateTime(2026, 9, 15, 19, 0);
      final now = DateTime(2026, 9, 13);
      expect(formatSessionDateTime(date, now: now), '9月15日(火) 19:00');
      expect(formatSessionDateTimeDisplay(date, now: now), '9月15日（火）19:00');
    });
  });

  group('formatSessionDateDisplay', () {
    test('日付だけを「9月8日（火）」で返す。年が違えば年を付ける', () {
      expect(
        formatSessionDateDisplay(
          DateTime(2026, 9, 8, 19, 0),
          now: DateTime(2026, 9, 13),
        ),
        '9月8日（火）',
      );
      expect(
        formatSessionDateDisplay(
          DateTime(2025, 9, 8, 19, 0),
          now: DateTime(2026, 9, 13),
        ),
        '2025年9月8日（月）',
      );
    });
  });

  group('sessionTypeLabel', () {
    test("'other' だけ日本語に変換し、それ以外は生値", () {
      expect(sessionTypeLabel('other'), 'その他');
      expect(sessionTypeLabel('パーソナルトレーニング'), 'パーソナルトレーニング');
    });

    test('null / 空文字はチップを出さないため null', () {
      expect(sessionTypeLabel(null), isNull);
      expect(sessionTypeLabel(''), isNull);
    });
  });

  group('buildSessionConsultDraft', () {
    test('表示中のラベルをそのまま定型文に埋め込む', () {
      final label = formatSessionDateTime(
        DateTime(2026, 9, 10, 18, 0),
        now: DateTime(2026, 9, 6),
      );
      expect(
        buildSessionConsultDraft(label),
        '9月10日(木) 18:00 のセッションについて相談です。',
      );
    });
  });
}
