import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';

void main() {
  group('shouldShowMorningDialog', () {
    test('時間外(3:59)は表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 3, 59),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('4:00ちょうどは表示する', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 4, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), true);
    });

    test('11:59は表示する', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 11, 59),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), true);
    });

    test('12:00ちょうどは表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 12, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('設定OFFなら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: false,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('当日評価済みなら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: true,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('今日dismissしてたら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: '2026-04-19',
        todayKey: '2026-04-19',
      ), false);
    });

    test('昨日dismissしてたら今日は表示する', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: '2026-04-18',
        todayKey: '2026-04-19',
      ), true);
    });
  });
}
