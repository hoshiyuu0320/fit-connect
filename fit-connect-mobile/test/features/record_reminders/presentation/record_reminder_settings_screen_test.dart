import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/presentation/screens/record_reminder_settings_screen.dart';
import 'package:fit_connect_mobile/features/record_reminders/providers/record_reminder_settings_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録のリマインダーの設定画面の表示・操作のテスト。
///
/// 設定（recordReminderSettingsProvider）と通知の許可（reminderNotificationPermissionProvider）を
/// 差し替え、SharedPreferences・Firebase・端末の予約には触れない。
/// 「設定を開く」は app_settings の MethodChannel を受け止めて確かめる。

/// 設定の偽物。操作を記録し、画面にはすぐ反映する（本物と同じく state を先に変える）
class _FakeReminderSettings extends RecordReminderSettingsNotifier {
  _FakeReminderSettings(this.initial);

  final RecordReminderSettings initial;

  /// 呼ばれた操作（'enabled:dinner:true' / 'time:dinner:21:30'。呼ばれた順）
  final calls = <String>[];

  /// オンにしたときに返す許可（オフにしたときは unknown）
  ReminderPermissionOutcome outcome = ReminderPermissionOutcome.granted;

  /// オンにしたときに呼ぶ（OS のダイアログで断られた、を作る）
  void Function()? onEnable;

  /// 渡すと、オンにしたときは設定を変えた後、これが終わるまで返さない（その後 [onEnable] を呼ぶ）。
  /// 許可を求めている間（OS のダイアログが開いている間）を作る
  Completer<void>? pendingEnable;

  /// 渡すと setEnabled / setTime がこの例外を投げる（設定は変えない。本物は元に戻してから投げる）
  Object? error;

  @override
  Future<RecordReminderSettings> build() async => initial;

  @override
  Future<ReminderPermissionOutcome> setEnabled(
    ReminderKind kind,
    bool enabled,
  ) async {
    calls.add('enabled:${kind.key}:$enabled');
    final failure = error;
    if (failure != null) throw failure;
    final current = state.requireValue;
    state = AsyncData(
      current.withSetting(
        kind,
        current.settingOf(kind).copyWith(enabled: enabled),
      ),
    );
    if (!enabled) return ReminderPermissionOutcome.unknown;
    final pending = pendingEnable;
    if (pending != null) await pending.future;
    onEnable?.call();
    return outcome;
  }

  @override
  Future<void> setTime(ReminderKind kind, ReminderTime time) async {
    calls.add('time:${kind.key}:${time.format()}');
    final failure = error;
    if (failure != null) throw failure;
    final current = state.requireValue;
    state = AsyncData(
      current.withSetting(kind, current.settingOf(kind).copyWith(time: time)),
    );
  }
}

/// 読み込みが終わらない設定
class _PendingReminderSettings extends RecordReminderSettingsNotifier {
  _PendingReminderSettings(this.pending);

  final Future<RecordReminderSettings> pending;

  @override
  Future<RecordReminderSettings> build() => pending;
}

/// 読み込みに失敗する設定（[onBuild] で読み込みの回数を数える）
class _FailingReminderSettings extends RecordReminderSettingsNotifier {
  _FailingReminderSettings(this.onBuild);

  final void Function() onBuild;

  @override
  Future<RecordReminderSettings> build() async {
    onBuild();
    throw StateError('prefs failed');
  }
}

/// 体重 7:30・夕食 20:00 をオンにした設定
RecordReminderSettings _weightAndDinnerOn() => RecordReminderSettings.defaults()
    .withSetting(
      ReminderKind.weight,
      ReminderSetting.defaultFor(ReminderKind.weight).copyWith(enabled: true),
    )
    .withSetting(
      ReminderKind.dinner,
      ReminderSetting.defaultFor(ReminderKind.dinner).copyWith(enabled: true),
    );

const _lead = '決まった時刻に、この端末へ記録のお知らせを出します。その日すでに記録していれば出しません。';
const _footnote = '時刻は日本時間です。アプリを7日以上開かないと、お知らせは止まります。開くと再開します。';
const _permissionNotice = '通知がオフになっています。設定アプリでこのアプリの通知を許可してください。';
const _saveError = 'リマインダーの設定を保存できませんでした';

const _appSettingsChannel =
    MethodChannel('com.spencerccf.app_settings/methods');

/// テストの binding ができてから読む（main の実行時にはまだ無い）
TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  /// 通知の許可の状態（reminderNotificationPermissionProvider が返す値）
  late ReminderNotificationPermission permission;

  /// 通知の許可を読んだ回数
  late int permissionReads;

  /// 渡すと、通知の許可を読むときにこれが終わるまで返さない（読み直しの途中を作る）
  Completer<void>? pendingPermissionRead;

  /// 「設定を開く」で呼ばれた app_settings の呼び出し
  late List<MethodCall> appSettingsCalls;

  setUp(() {
    permission = ReminderNotificationPermission.granted;
    permissionReads = 0;
    pendingPermissionRead = null;
    appSettingsCalls = [];
    _messenger.setMockMethodCallHandler(_appSettingsChannel, (call) async {
      appSettingsCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    _messenger.setMockMethodCallHandler(_appSettingsChannel, null);
  });

  /// 画面の大きさ（論理 px）。MediaQuery の大きさも揃える（幅 360 未満は左右の余白が 16 になる）
  void setScreenSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  List<Override> overrides(RecordReminderSettingsNotifier Function() create) =>
      [
        recordReminderSettingsProvider.overrideWith(create),
        reminderNotificationPermissionProvider.overrideWith((ref) async {
          permissionReads++;
          final pending = pendingPermissionRead;
          if (pending != null) await pending.future;
          return permission;
        }),
      ];

  Widget app({
    required List<Override> overrides,
    required Widget home,
    ThemeData? theme,
    double textScale = 1.0,
  }) {
    return ProviderScope(
      // テストの中で作り直したときに前の設定を持ち越さない
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: home,
      ),
    );
  }

  Future<_FakeReminderSettings> pumpScreen(
    WidgetTester tester, {
    RecordReminderSettings? settings,
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 1400),
  }) async {
    setScreenSize(tester, size);
    final fake = _FakeReminderSettings(
      settings ?? RecordReminderSettings.defaults(),
    );
    await tester.pumpWidget(
      app(
        overrides: overrides(() => fake),
        theme: theme,
        textScale: textScale,
        home: const RecordReminderSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// [kind] の行のトグル（行は ReminderKind の並び）
  Finder toggleOf(ReminderKind kind) => find.byType(FcToggle).at(kind.index);

  /// 時刻のボタン（[time] の文字を含む押せる範囲）
  Finder timeButton(String time) => find
      .ancestor(of: find.text(time), matching: find.byType(FcPressable))
      .first;

  group('RecordReminderSettingsScreen 構成と文言', () {
    testWidgets('戻る・見出し・冒頭の説明・5項目（並びは固定）・末尾の注記が出る', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('戻る'), findsOneWidget);
      expect(find.text('記録のリマインダー'), findsOneWidget);
      expect(find.text(_lead), findsOneWidget);
      expect(find.text(_footnote), findsOneWidget);

      // 説明 → 行 → 注記の順
      expect(
        tester.getTopLeft(find.text(_lead)).dy,
        lessThan(tester.getTopLeft(find.text('体重')).dy),
      );
      expect(
        tester.getTopLeft(find.text(_footnote)).dy,
        greaterThan(tester.getTopLeft(find.text('運動')).dy),
      );

      // 行は ReminderKind の並び（体重・朝食・昼食・夕食・運動）
      expect(
        ReminderKind.values.map((kind) => kind.label),
        ['体重', '朝食', '昼食', '夕食', '運動'],
      );
      double previousTop = -1;
      for (final kind in ReminderKind.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.label);
        final top = tester.getTopLeft(find.text(kind.label)).dy;
        expect(top, greaterThan(previousTop), reason: kind.label);
        previousTop = top;
      }
      expect(find.byType(FcToggle), findsNWidgets(5));
    });

    testWidgets('補足「プランがある日だけ」は運動の表示名の下だけに出る', (tester) async {
      await pumpScreen(tester);

      expect(find.text('プランがある日だけ'), findsOneWidget);
      final caption = tester.getRect(find.text('プランがある日だけ'));
      final title = tester.getRect(find.text('運動'));
      expect(caption.top, greaterThanOrEqualTo(title.bottom - 1));
      expect(caption.left, title.left);
    });

    testWidgets('既定はすべてオフで、時刻は既定（07:30 / 09:00 / 13:00 / 20:00 / 18:00）',
        (tester) async {
      await pumpScreen(tester);

      for (final kind in ReminderKind.values) {
        expect(tester.widget<FcToggle>(toggleOf(kind)).value, isFalse);
      }
      for (final time in ['07:30', '09:00', '13:00', '20:00', '18:00']) {
        expect(find.text(time), findsOneWidget, reason: time);
      }
    });

    testWidgets('画面の文字に絵文字は無い', (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(tester, settings: _weightAndDinnerOn());

      final emoji = RegExp(
        '[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B50}\u{2B06}\u{FE0F}]',
        unicode: true,
      );
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data ?? text.textSpan?.toPlainText() ?? '';
        expect(emoji.hasMatch(data), isFalse, reason: data);
      }
    });
  });

  group('RecordReminderSettingsScreen トグル', () {
    testWidgets('トグルを押すと、その項目の setEnabled が新しい値で呼ばれる（5項目とも）', (tester) async {
      final fake = await pumpScreen(tester);

      for (final kind in ReminderKind.values) {
        await tester.tap(toggleOf(kind));
        await tester.pumpAndSettle();
      }

      expect(fake.calls, [
        'enabled:weight:true',
        'enabled:breakfast:true',
        'enabled:lunch:true',
        'enabled:dinner:true',
        'enabled:workout:true',
      ]);
      for (final kind in ReminderKind.values) {
        expect(tester.widget<FcToggle>(toggleOf(kind)).value, isTrue);
      }

      await tester.tap(toggleOf(ReminderKind.dinner));
      await tester.pumpAndSettle();
      expect(fake.calls.last, 'enabled:dinner:false');
      expect(tester.widget<FcToggle>(toggleOf(ReminderKind.dinner)).value,
          isFalse);
    });

    testWidgets('表示名など行のほかの場所を押しても、オン・オフは変わらない（時刻を押し損ねても変わらない）',
        (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('夕食'));
      await tester.tap(find.text('プランがある日だけ'));
      // 時刻とトグルの間（8 の隙間）
      final time = tester.getRect(timeButton('20:00'));
      final toggle = tester.getRect(toggleOf(ReminderKind.dinner));
      await tester
          .tapAt(Offset((time.right + toggle.left) / 2, time.center.dy));
      await tester.pumpAndSettle();

      expect(fake.calls, isEmpty);
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testWidgets('読み上げでは、行（スイッチ）のダブルタップで切り替わる', (tester) async {
      final handle = tester.ensureSemantics();
      final fake = await pumpScreen(tester);

      tester.semantics.tap(find.semantics.byLabel('朝食のリマインダー、9:00'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['enabled:breakfast:true']);
      handle.dispose();
    });

    testWidgets('ログインしていない（StateError）ときは SnackBar で伝え、トグルは元のまま',
        (tester) async {
      final fake = await pumpScreen(tester);
      fake.error = StateError('signed out');

      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();

      expect(fake.calls, ['enabled:weight:true']);
      expect(find.text(_saveError), findsOneWidget);
      expect(tester.widget<FcToggle>(toggleOf(ReminderKind.weight)).value,
          isFalse);
    });

    testWidgets('保存に失敗したときも SnackBar で伝える', (tester) async {
      final fake = await pumpScreen(tester, settings: _weightAndDinnerOn());
      fake.error = Exception('disk full');

      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();

      expect(find.text(_saveError), findsOneWidget);
    });
  });

  group('RecordReminderSettingsScreen 通知の許可の案内', () {
    testWidgets('オンの項目があって通知が拒否されていると、案内と「設定を開く」が出て、押すと OS の通知の設定を開く',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(tester, settings: _weightAndDinnerOn());

      expect(find.text(_permissionNotice), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
      // 注意（warning）の帯: alert アイコン + 文言。操作のアイコンは再試行ではなく外部で開く印
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
      expect(find.byIcon(LucideIcons.externalLink), findsOneWidget);
      expect(find.byIcon(LucideIcons.refreshCw), findsNothing);
      final notice = tester.widget<FcInlineNotice>(find.byType(FcInlineNotice));
      expect(notice.kind, FcNoticeKind.warning);
      // 案内は説明の下・行の上
      expect(
        tester.getTopLeft(find.text(_permissionNotice)).dy,
        greaterThan(tester.getTopLeft(find.text(_lead)).dy),
      );
      expect(
        tester.getTopLeft(find.text(_permissionNotice)).dy,
        lessThan(tester.getTopLeft(find.text('体重')).dy),
      );
      // 「設定を開く」の押せる範囲は 44 以上
      final action = find
          .ancestor(of: find.text('設定を開く'), matching: find.byType(FcPressable))
          .first;
      expect(tester.getSize(action).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('設定を開く'));
      await tester.pump();

      expect(appSettingsCalls, hasLength(1));
      expect(appSettingsCalls.single.method, 'openSettings');
      expect(
        appSettingsCalls.single.arguments,
        containsPair('type', 'notification'),
      );
    });

    testWidgets('拒否されていても、オンの項目が無ければ案内は出ない', (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(tester);

      expect(find.text(_permissionNotice), findsNothing);
      expect(find.text('設定を開く'), findsNothing);
    });

    testWidgets('許可・未決定・不明なら、オンの項目があっても案内は出ない', (tester) async {
      for (final state in [
        ReminderNotificationPermission.granted,
        ReminderNotificationPermission.notDetermined,
        ReminderNotificationPermission.unknown,
      ]) {
        permission = state;
        await pumpScreen(tester, settings: _weightAndDinnerOn());

        expect(find.text(_permissionNotice), findsNothing, reason: '$state');
        expect(find.text('設定を開く'), findsNothing, reason: '$state');
      }
    });

    testWidgets('オンにして拒否された（denied）ら、許可を読み直して案内が出る', (tester) async {
      permission = ReminderNotificationPermission.notDetermined;
      final fake = await pumpScreen(tester);
      final readsBefore = permissionReads;
      expect(find.text(_permissionNotice), findsNothing);

      // OS のダイアログで断られた
      fake.outcome = ReminderPermissionOutcome.denied;
      fake.onEnable = () => permission = ReminderNotificationPermission.denied;
      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();

      expect(permissionReads, greaterThan(readsBefore));
      expect(find.text(_permissionNotice), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);

      // オンの項目が無くなれば案内は消える
      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();
      expect(find.text(_permissionNotice), findsNothing);
    });

    testWidgets('オンにして許可を求めている間は、許可が「拒否」と読めても案内を出さず、拒否のまま終わったら出す',
        (tester) async {
      // Android は一度も聞いていなくても「拒否」と読める
      permission = ReminderNotificationPermission.denied;
      final fake = await pumpScreen(tester);
      expect(find.text(_permissionNotice), findsNothing);

      // OS のダイアログが開いている間（setEnabled が終わらない）
      final dialog = Completer<void>();
      fake.pendingEnable = dialog;
      fake.outcome = ReminderPermissionOutcome.denied;
      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();

      expect(fake.calls, ['enabled:weight:true']);
      expect(
        tester.widget<FcToggle>(toggleOf(ReminderKind.weight)).value,
        isTrue,
      );
      expect(find.text(_permissionNotice), findsNothing);
      expect(find.text('設定を開く'), findsNothing);

      // ダイアログで断った → 読み直した許可（拒否）で案内が出る
      final readsBefore = permissionReads;
      dialog.complete();
      await tester.pumpAndSettle();

      expect(permissionReads, greaterThan(readsBefore));
      expect(find.text(_permissionNotice), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
    });

    testWidgets('許可を求めて許可されたら、案内は一度も出ない（読み直し終えるまで、前に読んだ「拒否」で出さない）',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      final fake = await pumpScreen(tester);

      final dialog = Completer<void>();
      fake.pendingEnable = dialog;
      fake.onEnable = () => permission = ReminderNotificationPermission.granted;
      await tester.tap(toggleOf(ReminderKind.weight));
      await tester.pumpAndSettle();
      expect(find.text(_permissionNotice), findsNothing);

      // ダイアログで許可した。許可を読み直し終えるまでは、前に読んだ「拒否」が残っている
      final reread = Completer<void>();
      pendingPermissionRead = reread;
      dialog.complete();
      await tester.pumpAndSettle();
      expect(find.text(_permissionNotice), findsNothing);

      reread.complete();
      await tester.pumpAndSettle();
      expect(find.text(_permissionNotice), findsNothing);
      expect(
        tester.widget<FcToggle>(toggleOf(ReminderKind.weight)).value,
        isTrue,
      );
    });

    testWidgets('案内が出ているときに別の項目をオンにしても、案内は出したまま（消して出し直すと行がずれる）',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      final fake = await pumpScreen(tester, settings: _weightAndDinnerOn());
      expect(find.text(_permissionNotice), findsOneWidget);

      // オンにする操作が終わるまでの間（iOS の拒否などは、ダイアログを出さずに拒否のまま終わる）
      final pending = Completer<void>();
      fake.pendingEnable = pending;
      fake.outcome = ReminderPermissionOutcome.denied;
      await tester.tap(toggleOf(ReminderKind.breakfast));
      await tester.pumpAndSettle();

      expect(fake.calls, ['enabled:breakfast:true']);
      expect(find.text(_permissionNotice), findsOneWidget);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text(_permissionNotice), findsOneWidget);
    });

    testWidgets('アプリが前面に戻ったら許可を読み直す（設定アプリで許可して戻ると案内が消える）', (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(tester, settings: _weightAndDinnerOn());
      expect(find.text(_permissionNotice), findsOneWidget);
      final readsBefore = permissionReads;

      permission = ReminderNotificationPermission.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(permissionReads, readsBefore + 1);
      expect(find.text(_permissionNotice), findsNothing);
    });

    testWidgets('画面を開くたびに許可を読み直す', (tester) async {
      setScreenSize(tester, const Size(390, 1400));
      final fake = _FakeReminderSettings(RecordReminderSettings.defaults());
      await tester.pumpWidget(
        app(
          overrides: overrides(() => fake),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const RecordReminderSettingsScreen(),
                    ),
                  ),
                  child: const Text('開く'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(permissionReads, 1);

      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(permissionReads, 2);
    });
  });

  group('RecordReminderSettingsScreen 時刻', () {
    testWidgets('時刻を押すと「夕食の時刻」のシートが開き、キャンセルでは保存しない', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();

      expect(find.text('夕食の時刻'), findsOneWidget);
      final picker =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(picker.initialDateTime.hour, 20);
      expect(picker.initialDateTime.minute, 0);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsNothing);
      expect(fake.calls, isEmpty);
      expect(find.text('20:00'), findsOneWidget);
    });

    testWidgets('ホイールを回して「決定」を押すと、その項目の setTime が選んだ時刻で呼ばれ、行の時刻が変わる',
        (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();
      // 時のホイールを 1 項目（高さ 32）回して 21 時
      await tester.drag(
        find.descendant(
          of: find.byType(CupertinoPicker).first,
          matching: find.text('20'),
        ),
        const Offset(0, -32),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['time:dinner:21:00']);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('20:00'), findsNothing);
      // オン・オフは変えない
      expect(tester.widget<FcToggle>(toggleOf(ReminderKind.dinner)).value,
          isFalse);
    });

    testWidgets('オフの項目でも時刻を変えられる（読み上げの操作で分を回す）', (tester) async {
      final handle = tester.ensureSemantics();
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('07:30'));
      await tester.pumpAndSettle();
      expect(find.text('体重の時刻'), findsOneWidget);
      tester.semantics.increase(find.semantics.byValue('30分'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['time:weight:07:35']);
      expect(find.text('07:35'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('時刻を変えずに「決定」を押したら保存しない', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();
      expect(find.text('運動の時刻'), findsOneWidget);
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(fake.calls, isEmpty);
    });

    testWidgets('時刻を保存できなかったら SnackBar で伝え、時刻は元のまま', (tester) async {
      final fake = await pumpScreen(tester);
      fake.error = Exception('disk full');

      await tester.tap(find.text('13:00'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.descendant(
          of: find.byType(CupertinoPicker).first,
          matching: find.text('13'),
        ),
        const Offset(0, -32),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(fake.calls, ['time:lunch:14:00']);
      expect(find.text(_saveError), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
    });

    testWidgets(
        'オフの項目の時刻は textSecondary、オンの項目は textPrimary（囲みは surfaceSecondary）',
        (tester) async {
      await pumpScreen(tester, settings: _weightAndDinnerOn());

      final light = AppColorsExtension.light;
      Color? colorOf(String time) =>
          tester.widget<Text>(find.text(time)).style!.color;
      // オン（体重・夕食）
      expect(colorOf('07:30'), light.textPrimary);
      expect(colorOf('20:00'), light.textPrimary);
      // オフ（朝食・昼食・運動）
      expect(colorOf('09:00'), light.textSecondary);
      expect(colorOf('13:00'), light.textSecondary);
      expect(colorOf('18:00'), light.textSecondary);
      // 値は 16 / 500 の等幅数字
      final style = tester.widget<Text>(find.text('07:30')).style!;
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      // 囲みは surfaceSecondary（オフでも同じ。押せることは変わらない）
      for (final time in ['07:30', '09:00']) {
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                  of: find.text(time), matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          (box.decoration as BoxDecoration).color,
          light.surfaceSecondary,
          reason: time,
        );
      }
    });
  });

  group('RecordReminderSettingsScreen 押せる範囲と読み上げ', () {
    testWidgets('時刻とトグルは押せる範囲が 44 以上で、間は 8 以上空き、同じ行に並ぶ', (tester) async {
      await pumpScreen(tester);

      const times = ['07:30', '09:00', '13:00', '20:00', '18:00'];
      for (final kind in ReminderKind.values) {
        final time = tester.getRect(timeButton(times[kind.index]));
        final toggle = tester.getRect(toggleOf(kind));
        expect(time.width, greaterThanOrEqualTo(44), reason: kind.label);
        expect(time.height, greaterThanOrEqualTo(44), reason: kind.label);
        expect(toggle.width, greaterThanOrEqualTo(44), reason: kind.label);
        expect(toggle.height, greaterThanOrEqualTo(44), reason: kind.label);
        expect(toggle.left - time.right, greaterThanOrEqualTo(8),
            reason: kind.label);
        expect((time.center.dy - toggle.center.dy).abs(), lessThan(1),
            reason: kind.label);
      }
    });

    testWidgets('行は「体重のリマインダー、7:30」のスイッチ、時刻は「体重の時刻 7:30、変更」のボタンとして読み上げる',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, settings: _weightAndDinnerOn());

      expect(
        tester.getSemantics(find.bySemanticsLabel('体重のリマインダー、7:30')),
        isSemantics(
          label: '体重のリマインダー、7:30',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('朝食のリマインダー、9:00')),
        isSemantics(hasToggledState: true, isToggled: false),
      );
      // 補足は表示名の後ろ（FcListRow と同じ「タイトル、補足、値」の順）
      expect(
        find.bySemanticsLabel('運動のリマインダー、プランがある日だけ、18:00'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('体重の時刻 7:30、変更')),
        isSemantics(
          label: '体重の時刻 7:30、変更',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      // オフの項目の時刻も押せる
      expect(
        tester.getSemantics(find.bySemanticsLabel('朝食の時刻 9:00、変更')),
        isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
      );
      // 表示名・時刻の文字は、行と時刻のボタンの読み上げにまとめてある（重ねて読まない）
      expect(find.bySemanticsLabel('体重'), findsNothing);
      expect(find.bySemanticsLabel('07:30'), findsNothing);
      handle.dispose();
    });
  });

  group('RecordReminderSettingsScreen 読み込み中・失敗', () {
    testWidgets('読み込み中は行の配置を保ち（右側はスケルトン）、読み込めたら時刻とトグルが出る', (tester) async {
      final completer = Completer<RecordReminderSettings>();
      setScreenSize(tester, const Size(390, 1400));
      await tester.pumpWidget(
        app(
          overrides:
              overrides(() => _PendingReminderSettings(completer.future)),
          home: const RecordReminderSettingsScreen(),
        ),
      );
      await tester.pump();

      for (final kind in ReminderKind.values) {
        expect(find.text(kind.label), findsOneWidget, reason: kind.label);
      }
      expect(find.byType(FcToggle), findsNothing);
      expect(find.byType(FcSkeleton), findsNWidgets(5));
      expect(find.text(_lead), findsOneWidget);
      final loadingHeight = tester.getSize(find.byType(FcRowsCard)).height;

      completer.complete(RecordReminderSettings.defaults());
      await tester.pumpAndSettle();

      expect(find.byType(FcSkeleton), findsNothing);
      expect(find.byType(FcToggle), findsNWidgets(5));
      // 読み込めても行の高さは変わらない（配置がずれない）
      expect(tester.getSize(find.byType(FcRowsCard)).height, loadingHeight);
    });

    testWidgets('読み込めなければ再試行つきのエラーが出て、再試行で読み直す', (tester) async {
      var builds = 0;
      setScreenSize(tester, const Size(390, 1400));
      await tester.pumpWidget(
        app(
          overrides: overrides(() => _FailingReminderSettings(() => builds++)),
          home: const RecordReminderSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('リマインダーの設定を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
      expect(find.byType(FcToggle), findsNothing);
      final notice = tester.widget<FcInlineNotice>(find.byType(FcInlineNotice));
      expect(notice.kind, FcNoticeKind.error);
      expect(builds, 1);

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(builds, 2);
    });
  });

  group('RecordReminderSettingsScreen 文字拡大とダーク', () {
    testWidgets('幅 320・文字拡大 1.35 でもはみ出さず、時刻とトグルは1行のまま（表示名・補足は折り返す）',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(
        tester,
        settings: _weightAndDinnerOn(),
        textScale: 1.35,
        size: const Size(320, 1800),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_permissionNotice), findsOneWidget);
      const times = ['07:30', '09:00', '13:00', '20:00', '18:00'];
      for (final kind in ReminderKind.values) {
        final time = tester.getRect(timeButton(times[kind.index]));
        final toggle = tester.getRect(toggleOf(kind));
        expect((time.center.dy - toggle.center.dy).abs(), lessThan(1),
            reason: kind.label);
        expect(toggle.left - time.right, greaterThanOrEqualTo(8),
            reason: kind.label);
        expect(toggle.right, lessThanOrEqualTo(320), reason: kind.label);
      }
      // 「戻る」「設定を開く」の押せる範囲は 44 以上
      for (final label in ['戻る', '設定を開く']) {
        final target = find
            .ancestor(of: find.text(label), matching: find.byType(FcPressable))
            .first;
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44),
            reason: label);
      }
    });

    testWidgets('幅 320・文字拡大 2.0 では、時刻とトグルを表示名・補足の下へ右寄せで積み直す（1行のまま）',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(
        tester,
        settings: _weightAndDinnerOn(),
        textScale: 2.0,
        size: const Size(320, 2800),
      );

      expect(tester.takeException(), isNull);
      const times = ['07:30', '09:00', '13:00', '20:00', '18:00'];
      final cardRight = tester.getRect(find.byType(FcRowsCard)).right;
      for (final kind in ReminderKind.values) {
        final time = tester.getRect(timeButton(times[kind.index]));
        final toggle = tester.getRect(toggleOf(kind));
        final title = tester.getRect(find.text(kind.label));
        expect((time.center.dy - toggle.center.dy).abs(), lessThan(1),
            reason: kind.label);
        expect(toggle.left - time.right, greaterThanOrEqualTo(8),
            reason: kind.label);
        // 表示名（運動は補足も）の下に置く
        final labelsBottom = kind.caption == null
            ? title.bottom
            : tester.getRect(find.text(kind.caption!)).bottom;
        expect(time.top, greaterThanOrEqualTo(labelsBottom),
            reason: kind.label);
        // 右寄せ（カードの右の余白 20 の内側）
        expect(toggle.right, closeTo(cardRight - 20, 1), reason: kind.label);
      }
    });

    testWidgets('文字拡大 1.35 までは、時刻とトグルを表示名の横に置く（積み直さない）', (tester) async {
      await pumpScreen(tester, textScale: 1.35);

      for (final kind in ReminderKind.values) {
        final toggle = tester.getRect(toggleOf(kind));
        final title = tester.getRect(find.text(kind.label));
        expect(toggle.left, greaterThan(title.right), reason: kind.label);
        expect(toggle.top, lessThan(title.bottom), reason: kind.label);
      }
    });

    testWidgets(
        'ダークでも崩れず、カードは surface・時刻の囲みは surfaceSecondary・案内は warningSurface',
        (tester) async {
      permission = ReminderNotificationPermission.denied;
      await pumpScreen(
        tester,
        settings: _weightAndDinnerOn(),
        theme: AppTheme.darkTheme,
      );

      expect(tester.takeException(), isNull);
      final dark = AppColorsExtension.dark;
      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((card.decoration as BoxDecoration).color, dark.surface);
      final chip = tester.widget<DecoratedBox>(
        find
            .ancestor(
                of: find.text('07:30'), matching: find.byType(DecoratedBox))
            .first,
      );
      expect((chip.decoration as BoxDecoration).color, dark.surfaceSecondary);
      expect(
        tester.widget<Text>(find.text('07:30')).style!.color,
        dark.textPrimary,
      );
      expect(
        tester.widget<Text>(find.text('09:00')).style!.color,
        dark.textSecondary,
      );
      final notice = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcInlineNotice),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((notice.decoration as BoxDecoration).color, dark.warningSurface);
    });
  });
}
