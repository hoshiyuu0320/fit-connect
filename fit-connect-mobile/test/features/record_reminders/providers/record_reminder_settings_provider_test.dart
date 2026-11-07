import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/data/record_reminder_settings_storage.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/providers/record_reminder_settings_provider.dart';
import 'package:fit_connect_mobile/features/record_reminders/services/record_reminder_sync.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';

import '../fake_record_reminder_sync.dart';

/// 記録のリマインダーの設定（recordReminderSettingsProvider）と通知の許可のテスト。
///
/// ログイン（authNotifierProvider）・予約し直し（recordReminderSyncProvider）・Firebase の
/// 許可の読み書き（ReminderNotificationPermissionGateway の引数）を偽物に差し替える。
/// 設定は SharedPreferences のモックに保存する。

const _userA = '11111111-1111-1111-1111-111111111111';
const _userB = '22222222-2222-2222-2222-222222222222';

/// 今ログインしているユーザー（null なら未ログイン）
String? _signedInUser;

class _FakeAuth extends AuthNotifier {
  @override
  Future<supabase.User?> build() async {
    final id = _signedInUser;
    if (id == null) return null;
    return supabase.User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );
  }
}

RecordReminderSettings _dinnerOn() =>
    RecordReminderSettings.defaults().withSetting(
      ReminderKind.dinner,
      ReminderSetting.defaultFor(ReminderKind.dinner).copyWith(enabled: true),
    );

void main() {
  late FakeRecordReminderSync sync;

  // 通知の許可（Firebase Messaging の偽物）
  late bool firebaseReady;
  late AuthorizationStatus status;
  late int statusReads;
  late NotificationSetupResult requestResult;
  late AuthorizationStatus statusAfterRequest;
  late List<String> requests;

  ReminderNotificationPermissionGateway gateway() =>
      ReminderNotificationPermissionGateway(
        isFirebaseInitialized: () => firebaseReady,
        authorizationStatus: () async {
          statusReads++;
          return status;
        },
        requestPermission: (userId) async {
          requests.add(userId);
          status = statusAfterRequest;
          return requestResult;
        },
      );

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      authNotifierProvider.overrideWith(_FakeAuth.new),
      recordReminderSyncProvider.overrideWithValue(sync),
      reminderNotificationPermissionGatewayProvider
          .overrideWithValue(gateway()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<RecordReminderSettings> saved(String userId) =>
      RecordReminderSettingsStorage().load(userId);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _signedInUser = _userA;
    sync = FakeRecordReminderSync();
    firebaseReady = true;
    status = AuthorizationStatus.notDetermined;
    statusReads = 0;
    requestResult = NotificationSetupResult.granted;
    statusAfterRequest = AuthorizationStatus.authorized;
    requests = [];
  });

  group('recordReminderSettingsProvider: 読み込み', () {
    test('保存が無ければ既定（すべてオフ）', () async {
      final container = makeContainer();
      expect(await container.read(recordReminderSettingsProvider.future),
          RecordReminderSettings.defaults());
    });

    test('ログインしているユーザーの保存した設定を読む', () async {
      await RecordReminderSettingsStorage().save(_userA, _dinnerOn());
      final container = makeContainer();

      expect(await container.read(recordReminderSettingsProvider.future),
          _dinnerOn());
    });

    test('ログインしているユーザーが変わったら、その人の設定を読み直す', () async {
      final weightOn = RecordReminderSettings.defaults().withSetting(
        ReminderKind.weight,
        ReminderSetting.defaultFor(ReminderKind.weight).copyWith(enabled: true),
      );
      await RecordReminderSettingsStorage().save(_userA, _dinnerOn());
      await RecordReminderSettingsStorage().save(_userB, weightOn);
      final container = makeContainer();
      container.listen(recordReminderSettingsProvider, (_, __) {});
      expect(await container.read(recordReminderSettingsProvider.future),
          _dinnerOn());

      _signedInUser = _userB;
      container.invalidate(authNotifierProvider);

      expect(await container.read(recordReminderSettingsProvider.future),
          weightOn);

      // 変えた設定は新しいユーザーの分として保存する（前のユーザーの分は変えない）
      await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.lunch, true);
      final weightAndLunchOn = weightOn.withSetting(
        ReminderKind.lunch,
        ReminderSetting.defaultFor(ReminderKind.lunch).copyWith(enabled: true),
      );
      expect(await saved(_userB), weightAndLunchOn);
      expect((await saved(_userB)).enabledKinds,
          [ReminderKind.weight, ReminderKind.lunch]);
      expect(await saved(_userA), _dinnerOn());
      // 通知の許可も新しいユーザーとして求める
      expect(requests, [_userB]);

      // ログアウトしたら既定
      _signedInUser = null;
      container.invalidate(authNotifierProvider);
      expect(await container.read(recordReminderSettingsProvider.future),
          RecordReminderSettings.defaults());
    });

    test('ログインしていなければ既定で、変えようとすると StateError（保存しない）', () async {
      _signedInUser = null;
      final container = makeContainer();
      expect(await container.read(recordReminderSettingsProvider.future),
          RecordReminderSettings.defaults());

      final notifier = container.read(recordReminderSettingsProvider.notifier);
      await expectLater(
          notifier.setEnabled(ReminderKind.dinner, true), throwsStateError);
      await expectLater(
        notifier.setTime(
            ReminderKind.dinner, const ReminderTime(hour: 21, minute: 0)),
        throwsStateError,
      );
      expect(sync.refreshReasons, isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('setEnabled', () {
    test('オンにするとき許可が未決定なら許可を求め、許可されたら granted。保存して予約し直す', () async {
      final container = makeContainer();
      await container.read(recordReminderSettingsProvider.future);

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(outcome, ReminderPermissionOutcome.granted);
      expect(requests, [_userA]);
      expect(
        container
            .read(recordReminderSettingsProvider)
            .requireValue
            .settingOf(ReminderKind.dinner)
            .enabled,
        isTrue,
      );
      expect(await saved(_userA), _dinnerOn());
      expect(sync.refreshReasons, ['settings_changed']);
    });

    test('断られても（拒否）オンのまま保存し、denied を返す', () async {
      requestResult = NotificationSetupResult.denied;
      statusAfterRequest = AuthorizationStatus.denied;
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(outcome, ReminderPermissionOutcome.denied);
      expect(requests, [_userA]);
      expect(await saved(_userA), _dinnerOn());
      expect(sync.refreshReasons, ['settings_changed']);
    });

    test('iOS ですでに拒否されていれば許可は求めず、オンのまま保存して denied を返す', () async {
      status = AuthorizationStatus.denied;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(outcome, ReminderPermissionOutcome.denied);
      expect(requests, isEmpty);
      expect(await saved(_userA), _dinnerOn());
      expect(sync.refreshReasons, ['settings_changed']);
    });

    test('Android は「未決定」を区別できない（一度も聞いていなくても denied）ので、denied でも求める', () async {
      // Android 13 以降で一度も聞いていない → ダイアログで許可された
      status = AuthorizationStatus.denied;
      statusAfterRequest = AuthorizationStatus.authorized;
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(outcome, ReminderPermissionOutcome.granted);
      expect(requests, [_userA]);

      // 断り続けた後（OS はダイアログを出さずに denied を返す）→ オンのまま保存して denied
      status = AuthorizationStatus.denied;
      statusAfterRequest = AuthorizationStatus.denied;
      requestResult = NotificationSetupResult.denied;
      final outcome2 = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.lunch, true);

      expect(outcome2, ReminderPermissionOutcome.denied);
      expect(requests, [_userA, _userA]);
      expect(
        (await saved(_userA)).enabledKinds,
        [ReminderKind.lunch, ReminderKind.dinner],
      );
    });

    test('すでに許可されていれば（仮の許可を含む）求めずに granted', () async {
      for (final allowed in [
        AuthorizationStatus.authorized,
        AuthorizationStatus.provisional,
      ]) {
        status = allowed;
        final container = makeContainer();

        final outcome = await container
            .read(recordReminderSettingsProvider.notifier)
            .setEnabled(ReminderKind.dinner, true);

        expect(outcome, ReminderPermissionOutcome.granted, reason: '$allowed');
      }
      expect(requests, isEmpty);
    });

    test('Firebase が初期化されていなければ、許可は求めず unknown（オンのまま保存する）', () async {
      firebaseReady = false;
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(outcome, ReminderPermissionOutcome.unknown);
      expect(requests, isEmpty);
      expect(statusReads, 0);
      expect(await saved(_userA), _dinnerOn());
    });

    test('push のトークンの登録だけが失敗したときは、許可の状態を読み直して決める', () async {
      requestResult = NotificationSetupResult.registrationFailed;
      statusAfterRequest = AuthorizationStatus.authorized;
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);
      expect(outcome, ReminderPermissionOutcome.granted);

      // 許可を求めること自体が失敗して、まだ未決定のまま
      status = AuthorizationStatus.notDetermined;
      statusAfterRequest = AuthorizationStatus.notDetermined;
      final outcome2 = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.lunch, true);
      expect(outcome2, ReminderPermissionOutcome.unknown);
    });

    test('許可を求めたら、許可の状態（reminderNotificationPermissionProvider）を読み直す',
        () async {
      final container = makeContainer();
      container.listen(reminderNotificationPermissionProvider, (_, __) {});
      expect(
          await container.read(reminderNotificationPermissionProvider.future),
          ReminderNotificationPermission.notDetermined);

      await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, true);

      expect(
          await container.read(reminderNotificationPermissionProvider.future),
          ReminderNotificationPermission.granted);
    });

    test('オフにするときは許可を確かめない（unknown）。保存して予約し直す', () async {
      await RecordReminderSettingsStorage().save(_userA, _dinnerOn());
      final container = makeContainer();

      final outcome = await container
          .read(recordReminderSettingsProvider.notifier)
          .setEnabled(ReminderKind.dinner, false);

      expect(outcome, ReminderPermissionOutcome.unknown);
      expect(statusReads, 0);
      expect(requests, isEmpty);
      expect(await saved(_userA), RecordReminderSettings.defaults());
      expect(sync.refreshReasons, ['settings_changed']);
    });

    test('保存に失敗したら元の設定に戻して例外を投げる（予約し直さない）', () async {
      final container = ProviderContainer(overrides: [
        authNotifierProvider.overrideWith(_FakeAuth.new),
        recordReminderSyncProvider.overrideWithValue(sync),
        reminderNotificationPermissionGatewayProvider
            .overrideWithValue(gateway()),
        recordReminderSettingsStorageProvider.overrideWithValue(
          _FailingSaveStorage(),
        ),
      ]);
      addTearDown(container.dispose);
      container.listen(recordReminderSettingsProvider, (_, __) {});
      await container.read(recordReminderSettingsProvider.future);

      await expectLater(
        container
            .read(recordReminderSettingsProvider.notifier)
            .setEnabled(ReminderKind.dinner, true),
        throwsException,
      );

      expect(container.read(recordReminderSettingsProvider).requireValue,
          RecordReminderSettings.defaults());
      expect(sync.refreshReasons, isEmpty);
    });
  });

  group('setTime', () {
    test('時刻を保存して予約し直す（オン・オフは変えない）', () async {
      await RecordReminderSettingsStorage().save(_userA, _dinnerOn());
      final container = makeContainer();
      const time = ReminderTime(hour: 21, minute: 30);

      await container
          .read(recordReminderSettingsProvider.notifier)
          .setTime(ReminderKind.dinner, time);

      final expected = _dinnerOn().withSetting(
        ReminderKind.dinner,
        const ReminderSetting(enabled: true, time: time),
      );
      expect(container.read(recordReminderSettingsProvider).requireValue,
          expected);
      expect(await saved(_userA), expected);
      expect(sync.refreshReasons, ['settings_changed']);
      expect(requests, isEmpty);
    });
  });

  group('reminderNotificationPermissionProvider', () {
    test('Firebase Messaging の許可の状態を読む', () async {
      const cases = {
        AuthorizationStatus.authorized: ReminderNotificationPermission.granted,
        AuthorizationStatus.provisional: ReminderNotificationPermission.granted,
        AuthorizationStatus.denied: ReminderNotificationPermission.denied,
        AuthorizationStatus.notDetermined:
            ReminderNotificationPermission.notDetermined,
      };
      for (final entry in cases.entries) {
        status = entry.key;
        final container = makeContainer();
        expect(
          await container.read(reminderNotificationPermissionProvider.future),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('Firebase が初期化されていなければ unknown（読まない）', () async {
      firebaseReady = false;
      final container = makeContainer();

      expect(
          await container.read(reminderNotificationPermissionProvider.future),
          ReminderNotificationPermission.unknown);
      expect(statusReads, 0);
    });

    test('iOS/Android 以外では unknown（読まない）', () async {
      status = AuthorizationStatus.authorized;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(await gateway().read(), ReminderNotificationPermission.unknown);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      expect(statusReads, 0);
    });

    test('読めなかったら unknown（例外を投げない）', () async {
      final failing = ReminderNotificationPermissionGateway(
        isFirebaseInitialized: () => true,
        authorizationStatus: () async => throw Exception('platform'),
      );

      expect(await failing.read(), ReminderNotificationPermission.unknown);
    });
  });

  group('reminderSummaryLabel', () {
    test('オンの項目が無ければ「オフ」', () {
      expect(reminderSummaryLabel(RecordReminderSettings.defaults()), 'オフ');
    });

    test('オンの項目の表示名を、項目の並びで「・」でつなぐ', () {
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
      expect(reminderSummaryLabel(settings), '体重・夕食');
    });

    test('1つだけ・すべて', () {
      final workoutOnly = RecordReminderSettings.defaults().withSetting(
        ReminderKind.workout,
        ReminderSetting.defaultFor(ReminderKind.workout)
            .copyWith(enabled: true),
      );
      expect(reminderSummaryLabel(workoutOnly), '運動');

      var all = RecordReminderSettings.defaults();
      for (final kind in ReminderKind.values) {
        all = all.withSetting(
          kind,
          ReminderSetting.defaultFor(kind).copyWith(enabled: true),
        );
      }
      expect(reminderSummaryLabel(all), '体重・朝食・昼食・夕食・運動');
    });
  });
}

/// 保存に失敗する設定の保存先（読むのは既定）
class _FailingSaveStorage extends RecordReminderSettingsStorage {
  @override
  Future<void> save(String userId, RecordReminderSettings settings) async {
    throw Exception('disk full');
  }
}
