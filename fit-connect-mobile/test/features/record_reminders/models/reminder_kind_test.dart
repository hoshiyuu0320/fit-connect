import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

/// 絵文字（記号・絵文字のブロック）を含むか
bool _hasEmoji(String text) => text.runes
    .any((r) => (r >= 0x2600 && r <= 0x27BF) || (r >= 0x1F000 && r <= 0x1FAFF));

/// リマインダーの項目（設計 §3・§5 の表）のテスト。
///
/// index は通知 ID に、key は保存・payload に使うので、並びとキーが変わると
/// 予約済みの通知・保存済みの設定と食い違う。
void main() {
  group('ReminderKind', () {
    test('並びは 体重・朝食・昼食・夕食・運動 で固定（index は通知 ID に使う）', () {
      expect(ReminderKind.values, [
        ReminderKind.weight,
        ReminderKind.breakfast,
        ReminderKind.lunch,
        ReminderKind.dinner,
        ReminderKind.workout,
      ]);
      expect(ReminderKind.values.map((k) => k.index), [0, 1, 2, 3, 4]);
    });

    test('key（保存・payload 用）', () {
      expect(
        ReminderKind.values.map((k) => k.key),
        ['weight', 'breakfast', 'lunch', 'dinner', 'workout'],
      );
    });

    test('表示名と、運動だけのキャプション', () {
      expect(
        ReminderKind.values.map((k) => k.label),
        ['体重', '朝食', '昼食', '夕食', '運動'],
      );
      expect(ReminderKind.workout.caption, 'プランがある日だけ');
      for (final kind in ReminderKind.values.where(
        (k) => k != ReminderKind.workout,
      )) {
        expect(kind.caption, isNull, reason: kind.key);
      }
    });

    test('既定の時刻 07:30 / 09:00 / 13:00 / 20:00 / 18:00', () {
      expect(
        ReminderKind.values.map((k) => (k.defaultHour, k.defaultMinute)),
        [(7, 30), (9, 0), (13, 0), (20, 0), (18, 0)],
      );
    });

    test('押したときのタグは末尾の空白込み。運動はプラン画面なので null', () {
      expect(ReminderKind.weight.messageDraft, '#体重 ');
      expect(ReminderKind.breakfast.messageDraft, '#食事:朝食 ');
      expect(ReminderKind.lunch.messageDraft, '#食事:昼食 ');
      expect(ReminderKind.dinner.messageDraft, '#食事:夕食 ');
      expect(ReminderKind.workout.messageDraft, isNull);
    });

    test('通知のタイトルと本文（§5）', () {
      expect(
        ReminderKind.values
            .map((k) => (k.notificationTitle, k.notificationBody)),
        [
          ('体重の記録', '今日の体重を記録しましょう'),
          ('朝食の記録', '朝食を記録しましょう'),
          ('昼食の記録', '昼食を記録しましょう'),
          ('夕食の記録', '夕食を記録しましょう'),
          ('今日のワークアウト', '今日のプランのワークアウトがあります'),
        ],
      );
    });

    test('文面に絵文字と「まだ記録されていません」を使わない', () {
      for (final kind in ReminderKind.values) {
        for (final text in [
          kind.label,
          kind.notificationTitle,
          kind.notificationBody,
        ]) {
          expect(_hasEmoji(text), isFalse, reason: text);
          expect(text, isNot(contains('記録されていません')));
        }
      }
    });

    test('fromKey: key から項目を引き、知らないキーは null', () {
      for (final kind in ReminderKind.values) {
        expect(ReminderKind.fromKey(kind.key), kind);
      }
      expect(ReminderKind.fromKey('sleep'), isNull);
      expect(ReminderKind.fromKey(''), isNull);
      expect(ReminderKind.fromKey('Weight'), isNull);
      expect(ReminderKind.fromKey(' weight'), isNull);
    });
  });
}
