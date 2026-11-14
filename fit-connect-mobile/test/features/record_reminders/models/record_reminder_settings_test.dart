import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

/// 設定の JSON。items に [items] を入れ、version は [version]（省略時 1）
Map<String, Object?> _json(Map<String, Object?> items, {Object? version = 1}) =>
    {'version': version, 'items': items};

void main() {
  group('ReminderTime', () {
    test("'HH:mm' を読む（0〜23時、0〜55分の5分刻み）", () {
      expect(
        ReminderTime.tryParse('07:30'),
        const ReminderTime(hour: 7, minute: 30),
      );
      expect(
        ReminderTime.tryParse('00:00'),
        const ReminderTime(hour: 0, minute: 0),
      );
      expect(
        ReminderTime.tryParse('23:55'),
        const ReminderTime(hour: 23, minute: 55),
      );
      expect(
        ReminderTime.tryParse('12:05'),
        const ReminderTime(hour: 12, minute: 5),
      );
    });

    test('形式が違う・範囲外・5分刻みでない値は null', () {
      for (final value in [
        '7:30', // 0 埋めなし
        '07:3',
        '0730',
        '07:30:00',
        ' 07:30',
        '07:30 ',
        '24:00',
        '23:60',
        '07:32', // 5分刻みでない
        '07:59',
        '-1:00',
        'ab:cd',
        '０７:３０', // 全角数字
        '',
      ]) {
        expect(ReminderTime.tryParse(value), isNull, reason: value);
      }
    });

    test("format は 0 埋めの 'HH:mm'。tryParse と往復する", () {
      expect(const ReminderTime(hour: 7, minute: 5).format(), '07:05');
      expect(const ReminderTime(hour: 0, minute: 0).format(), '00:00');
      expect(const ReminderTime(hour: 23, minute: 55).toString(), '23:55');

      for (var hour = 0; hour < 24; hour++) {
        for (var minute = 0; minute < 60; minute += 5) {
          final time = ReminderTime(hour: hour, minute: minute);
          expect(ReminderTime.tryParse(time.format()), time);
        }
      }
    });

    test('defaultFor は項目の既定の時刻', () {
      expect(
        ReminderTime.defaultFor(ReminderKind.weight),
        const ReminderTime(hour: 7, minute: 30),
      );
      expect(
        ReminderTime.defaultFor(ReminderKind.workout),
        const ReminderTime(hour: 18, minute: 0),
      );
    });

    test('時・分が同じなら等しい', () {
      expect(
        const ReminderTime(hour: 7, minute: 30),
        ReminderTime.tryParse('07:30'),
      );
      expect(
        const ReminderTime(hour: 7, minute: 30).hashCode,
        ReminderTime.tryParse('07:30').hashCode,
      );
      expect(
        const ReminderTime(hour: 7, minute: 30),
        isNot(const ReminderTime(hour: 7, minute: 35)),
      );
    });
  });

  group('ReminderSetting', () {
    test('defaultFor はオフ・既定の時刻', () {
      expect(
        ReminderSetting.defaultFor(ReminderKind.dinner),
        const ReminderSetting(
          enabled: false,
          time: ReminderTime(hour: 20, minute: 0),
        ),
      );
    });

    test('copyWith は指定した値だけ替える', () {
      final base = ReminderSetting.defaultFor(ReminderKind.weight);
      expect(
        base.copyWith(enabled: true),
        const ReminderSetting(
          enabled: true,
          time: ReminderTime(hour: 7, minute: 30),
        ),
      );
      expect(
        base.copyWith(time: const ReminderTime(hour: 6, minute: 45)),
        const ReminderSetting(
          enabled: false,
          time: ReminderTime(hour: 6, minute: 45),
        ),
      );
    });
  });

  group('RecordReminderSettings', () {
    test('defaults: 5項目すべてオフ・既定の時刻', () {
      final settings = RecordReminderSettings.defaults();

      expect(settings.items.keys, ReminderKind.values);
      for (final kind in ReminderKind.values) {
        expect(settings.settingOf(kind), ReminderSetting.defaultFor(kind));
      }
      expect(settings.anyEnabled, isFalse);
      expect(settings.enabledKinds, isEmpty);
    });

    test('toJson: version 1 と、kind.key ごとの enabled / time', () {
      final settings = RecordReminderSettings.defaults()
          .withSetting(
            ReminderKind.weight,
            const ReminderSetting(
              enabled: true,
              time: ReminderTime(hour: 6, minute: 5),
            ),
          )
          .withSetting(
            ReminderKind.dinner,
            const ReminderSetting(
              enabled: true,
              time: ReminderTime(hour: 21, minute: 0),
            ),
          );

      expect(settings.toJson(), {
        'version': 1,
        'items': {
          'weight': {'enabled': true, 'time': '06:05'},
          'breakfast': {'enabled': false, 'time': '09:00'},
          'lunch': {'enabled': false, 'time': '13:00'},
          'dinner': {'enabled': true, 'time': '21:00'},
          'workout': {'enabled': false, 'time': '18:00'},
        },
      });
    });

    test('JSON の文字列を経由しても同じ設定に戻る', () {
      final settings = RecordReminderSettings.defaults()
          .withSetting(
            ReminderKind.breakfast,
            const ReminderSetting(
              enabled: true,
              time: ReminderTime(hour: 8, minute: 15),
            ),
          )
          .withSetting(
            ReminderKind.workout,
            const ReminderSetting(
              enabled: false,
              time: ReminderTime(hour: 19, minute: 30),
            ),
          );

      final restored = RecordReminderSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
      );

      expect(restored, settings);
      expect(restored.hashCode, settings.hashCode);
      expect(
        restored.settingOf(ReminderKind.workout).time,
        const ReminderTime(hour: 19, minute: 30),
      );
    });

    test('withSetting はその項目だけを替えた新しい設定を返す（元は変えない）', () {
      final original = RecordReminderSettings.defaults();
      final updated = original.withSetting(
        ReminderKind.lunch,
        const ReminderSetting(
          enabled: true,
          time: ReminderTime(hour: 12, minute: 30),
        ),
      );

      expect(original, RecordReminderSettings.defaults());
      expect(updated, isNot(original));
      expect(updated.settingOf(ReminderKind.lunch).enabled, isTrue);
      expect(
        updated.settingOf(ReminderKind.lunch).time,
        const ReminderTime(hour: 12, minute: 30),
      );
      for (final kind in ReminderKind.values.where(
        (k) => k != ReminderKind.lunch,
      )) {
        expect(updated.settingOf(kind), ReminderSetting.defaultFor(kind));
      }
    });

    test('anyEnabled / enabledKinds（ReminderKind の並び）', () {
      final settings = RecordReminderSettings.defaults()
          .withSetting(
            ReminderKind.dinner,
            ReminderSetting.defaultFor(ReminderKind.dinner)
                .copyWith(enabled: true),
          )
          .withSetting(
            ReminderKind.weight,
            ReminderSetting.defaultFor(ReminderKind.weight)
                .copyWith(enabled: true),
          );

      expect(settings.anyEnabled, isTrue);
      expect(settings.enabledKinds, [ReminderKind.weight, ReminderKind.dinner]);
      expect(
        settings.enabledKinds.map((k) => k.label).join('・'),
        '体重・夕食',
      );
    });

    test('items は変更できない', () {
      final settings = RecordReminderSettings.defaults();
      expect(
        () => settings.items[ReminderKind.weight] =
            ReminderSetting.defaultFor(ReminderKind.weight),
        throwsUnsupportedError,
      );
    });

    group('fromJson（壊れた値は既定に戻す）', () {
      test('Map でない値は全体を既定に戻す', () {
        for (final json in <Object?>[null, 'x', 42, true, <Object?>[]]) {
          expect(
            RecordReminderSettings.fromJson(json),
            RecordReminderSettings.defaults(),
            reason: '$json',
          );
        }
      });

      test('version が 1 でない（無い・別の版・文字列）なら全体を既定に戻す', () {
        final items = {
          'weight': {'enabled': true, 'time': '07:30'},
        };
        for (final version in <Object?>[null, 0, 2, '1']) {
          expect(
            RecordReminderSettings.fromJson(_json(items, version: version)),
            RecordReminderSettings.defaults(),
            reason: '$version',
          );
        }
        expect(
          RecordReminderSettings.fromJson({'items': items}),
          RecordReminderSettings.defaults(),
        );
        // 正しい版なら読める
        expect(
          RecordReminderSettings.fromJson(_json(items)).enabledKinds,
          [ReminderKind.weight],
        );
      });

      test('items が無い・Map でないなら全体を既定に戻す', () {
        expect(
          RecordReminderSettings.fromJson({'version': 1}),
          RecordReminderSettings.defaults(),
        );
        for (final items in <Object?>[null, 'weight', <Object?>[]]) {
          expect(
            RecordReminderSettings.fromJson({'version': 1, 'items': items}),
            RecordReminderSettings.defaults(),
            reason: '$items',
          );
        }
      });

      test('欠けた項目は既定で埋め、ほかの項目は読む（常に5項目）', () {
        final settings = RecordReminderSettings.fromJson(_json({
          'dinner': {'enabled': true, 'time': '19:45'},
        }));

        expect(settings.items.keys, ReminderKind.values);
        expect(
          settings.settingOf(ReminderKind.dinner),
          const ReminderSetting(
            enabled: true,
            time: ReminderTime(hour: 19, minute: 45),
          ),
        );
        for (final kind in ReminderKind.values.where(
          (k) => k != ReminderKind.dinner,
        )) {
          expect(settings.settingOf(kind), ReminderSetting.defaultFor(kind));
        }
      });

      test('項目が Map でなければその項目だけ既定', () {
        final settings = RecordReminderSettings.fromJson(_json({
          'weight': true,
          'breakfast': '08:00',
          'lunch': null,
          'dinner': {'enabled': true, 'time': '20:30'},
        }));

        expect(
          settings.settingOf(ReminderKind.weight),
          ReminderSetting.defaultFor(ReminderKind.weight),
        );
        expect(
          settings.settingOf(ReminderKind.breakfast),
          ReminderSetting.defaultFor(ReminderKind.breakfast),
        );
        expect(
          settings.settingOf(ReminderKind.lunch),
          ReminderSetting.defaultFor(ReminderKind.lunch),
        );
        expect(settings.settingOf(ReminderKind.dinner).enabled, isTrue);
      });

      test('enabled が bool でなければオフ（時刻は読む）', () {
        final settings = RecordReminderSettings.fromJson(_json({
          'weight': {'enabled': 'true', 'time': '06:30'},
          'breakfast': {'enabled': 1, 'time': '08:30'},
          'lunch': {'time': '12:15'},
        }));

        expect(
          settings.settingOf(ReminderKind.weight),
          const ReminderSetting(
            enabled: false,
            time: ReminderTime(hour: 6, minute: 30),
          ),
        );
        expect(
          settings.settingOf(ReminderKind.breakfast),
          const ReminderSetting(
            enabled: false,
            time: ReminderTime(hour: 8, minute: 30),
          ),
        );
        expect(
          settings.settingOf(ReminderKind.lunch),
          const ReminderSetting(
            enabled: false,
            time: ReminderTime(hour: 12, minute: 15),
          ),
        );
      });

      test('time が読めなければその項目の既定の時刻（オン・オフは読む）', () {
        final cases = <Object?>[
          '7:30',
          '24:00',
          '07:32',
          '07:60',
          '-1:00',
          '07:30:00',
          'ab:cd',
          '',
          730,
          null,
        ];
        for (final time in cases) {
          final settings = RecordReminderSettings.fromJson(_json({
            'weight': {'enabled': true, 'time': time},
            'workout': {'enabled': true, 'time': time},
          }));
          expect(
            settings.settingOf(ReminderKind.weight),
            const ReminderSetting(
              enabled: true,
              time: ReminderTime(hour: 7, minute: 30),
            ),
            reason: '$time',
          );
          expect(
            settings.settingOf(ReminderKind.workout),
            const ReminderSetting(
              enabled: true,
              time: ReminderTime(hour: 18, minute: 0),
            ),
            reason: '$time',
          );
        }
      });

      test('境界の時刻 00:00 と 23:55 は読める', () {
        final settings = RecordReminderSettings.fromJson(_json({
          'weight': {'enabled': true, 'time': '00:00'},
          'dinner': {'enabled': true, 'time': '23:55'},
        }));
        expect(
          settings.settingOf(ReminderKind.weight).time,
          const ReminderTime(hour: 0, minute: 0),
        );
        expect(
          settings.settingOf(ReminderKind.dinner).time,
          const ReminderTime(hour: 23, minute: 55),
        );
      });

      test('知らない項目のキーと余分なフィールドは無視する', () {
        final settings = RecordReminderSettings.fromJson({
          'version': 1,
          'extra': 'ignored',
          'items': {
            'sleep': {'enabled': true, 'time': '22:00'},
            'weight': {'enabled': true, 'time': '07:00', 'note': 'x'},
          },
        });

        expect(settings.enabledKinds, [ReminderKind.weight]);
        expect(
          settings.settingOf(ReminderKind.weight).time,
          const ReminderTime(hour: 7, minute: 0),
        );
        expect(settings.items, hasLength(5));
      });
    });
  });
}
