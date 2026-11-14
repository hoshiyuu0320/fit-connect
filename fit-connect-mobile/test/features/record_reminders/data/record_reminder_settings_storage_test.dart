import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/record_reminders/data/record_reminder_settings_storage.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

const _userA = '11111111-1111-1111-1111-111111111111';
const _userB = '22222222-2222-2222-2222-222222222222';

RecordReminderSettings _weightAndDinnerOn() => RecordReminderSettings.defaults()
    .withSetting(
      ReminderKind.weight,
      const ReminderSetting(
        enabled: true,
        time: ReminderTime(hour: 6, minute: 45),
      ),
    )
    .withSetting(
      ReminderKind.dinner,
      const ReminderSetting(
        enabled: true,
        time: ReminderTime(hour: 20, minute: 0),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('RecordReminderSettingsStorage', () {
    test("キーは 'record_reminder_settings:<ユーザー ID>'", () {
      expect(
        RecordReminderSettingsStorage.keyFor(_userA),
        'record_reminder_settings:$_userA',
      );
    });

    test('保存していなければ既定（すべてオフ）', () async {
      final storage = RecordReminderSettingsStorage();
      expect(await storage.load(_userA), RecordReminderSettings.defaults());
    });

    test('保存した設定を読み戻せる（値は version 1 の JSON 文字列）', () async {
      final storage = RecordReminderSettingsStorage();
      final settings = _weightAndDinnerOn();

      await storage.save(_userA, settings);

      expect(await storage.load(_userA), settings);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('record_reminder_settings:$_userA');
      expect(jsonDecode(raw!), settings.toJson());
      expect((jsonDecode(raw) as Map)['version'], 1);
    });

    test('アカウントごとに分かれる（別のユーザーは前の人の設定を読まない）', () async {
      final storage = RecordReminderSettingsStorage();
      final settingsA = _weightAndDinnerOn();

      await storage.save(_userA, settingsA);
      expect(await storage.load(_userB), RecordReminderSettings.defaults());

      final settingsB = RecordReminderSettings.defaults().withSetting(
        ReminderKind.workout,
        ReminderSetting.defaultFor(ReminderKind.workout).copyWith(
          enabled: true,
        ),
      );
      await storage.save(_userB, settingsB);

      expect(await storage.load(_userA), settingsA);
      expect(await storage.load(_userB), settingsB);
    });

    test('上書き保存すると新しい設定になる', () async {
      final storage = RecordReminderSettingsStorage();
      await storage.save(_userA, _weightAndDinnerOn());
      await storage.save(_userA, RecordReminderSettings.defaults());

      expect(await storage.load(_userA), RecordReminderSettings.defaults());
    });

    test('壊れた JSON・文字列でない値は既定に戻す（例外を投げない）', () async {
      for (final raw in <Object>[
        '{broken',
        '',
        'null',
        '[]',
        '"text"',
        '{"version":2,"items":{"weight":{"enabled":true,"time":"07:30"}}}',
        42,
        true,
        <String>['a'],
      ]) {
        SharedPreferences.setMockInitialValues({
          'record_reminder_settings:$_userA': raw,
        });
        final storage = RecordReminderSettingsStorage();
        expect(
          await storage.load(_userA),
          RecordReminderSettings.defaults(),
          reason: '$raw',
        );
      }
    });

    test('一部だけ読める JSON は読める項目を使う', () async {
      SharedPreferences.setMockInitialValues({
        'record_reminder_settings:$_userA': jsonEncode({
          'version': 1,
          'items': {
            'lunch': {'enabled': true, 'time': '12:30'},
            'dinner': {'enabled': true, 'time': '7pm'},
          },
        }),
      });

      final settings = await RecordReminderSettingsStorage().load(_userA);

      expect(settings.enabledKinds, [ReminderKind.lunch, ReminderKind.dinner]);
      expect(
        settings.settingOf(ReminderKind.lunch).time,
        const ReminderTime(hour: 12, minute: 30),
      );
      expect(
        settings.settingOf(ReminderKind.dinner).time,
        ReminderTime.defaultFor(ReminderKind.dinner),
      );
    });

    test('差し替えた SharedPreferences の取得関数を使う', () async {
      var calls = 0;
      final storage = RecordReminderSettingsStorage(
        preferences: () {
          calls++;
          return SharedPreferences.getInstance();
        },
      );

      await storage.save(_userA, _weightAndDinnerOn());
      await storage.load(_userA);

      expect(calls, 2);
    });
  });
}
