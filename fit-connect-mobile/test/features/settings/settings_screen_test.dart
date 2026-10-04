import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase show User;
import 'package:fit_connect_mobile/core/providers/theme_provider.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:fit_connect_mobile/features/settings/providers/notification_preferences_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 設定タブの表示テスト（正本: more-screens.js `SettingsScreen`）。
/// Supabase・SharedPreferences（健康設定）・HealthKit には触れず、Provider を差し替えて検証する。
class _FakePrefs extends NotificationPreferences {
  _FakePrefs(this.initial);

  final NotificationPreferencesState initial;
  final changes = <(NotificationKind, bool)>[];

  @override
  Future<NotificationPreferencesState> build() async => initial;

  @override
  Future<void> setEnabled(NotificationKind kind, bool enabled) async {
    changes.add((kind, enabled));
  }
}

class _PendingPrefs extends NotificationPreferences {
  _PendingPrefs(this.pending);

  final Future<NotificationPreferencesState> pending;

  @override
  Future<NotificationPreferencesState> build() => pending;
}

class _FailingPrefs extends NotificationPreferences {
  @override
  Future<NotificationPreferencesState> build() async =>
      throw StateError('prefs failed');
}

/// 認証の呼び出し記録と、失敗・待機の仕込み。
/// Provider は autoDispose で作り直されることがあるため、Notifier ではなくこちらに持たせる
class _AuthLog {
  int signOuts = 0;
  int deletions = 0;

  /// 非 null ならアカウント削除はこの Future が終わるまで待つ（実行中の状態を作る）
  Completer<void>? deletionGate;

  /// 非 null なら対応する操作がこの例外で失敗する
  Object? signOutError;
  Object? deletionError;
}

/// 認証。Supabase に出ず、ログアウト・アカウント削除の呼び出しだけを [_AuthLog] に残す
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.log);

  final _AuthLog log;

  @override
  Future<supabase.User?> build() async => null;

  @override
  Future<void> signOut() async {
    log.signOuts++;
    if (log.signOutError != null) throw log.signOutError!;
  }

  @override
  Future<void> deleteAccount() async {
    log.deletions++;
    final gate = log.deletionGate;
    if (gate != null) await gate.future;
    if (log.deletionError != null) throw log.deletionError!;
  }
}

class _FakeHealthSettings extends HealthSettings {
  _FakeHealthSettings(this.initial);

  final HealthSettingsState initial;

  @override
  Future<HealthSettingsState> build() async => initial;
}

class _FakeHealthSync extends HealthSync {
  @override
  Future<void> build() async {}
}

final _client = Client(
  clientId: 'client-1',
  name: '佐藤 美咲',
  email: 'misaki.sato@example.com',
  trainerId: 'trainer-1',
  createdAt: DateTime(2026, 1, 1),
);

const _trainer = Trainer(id: 'trainer-1', name: '田中トレーナー');

final _health = HealthSettingsState(
  isEnabled: true,
  isWeightEnabled: true,
  isSleepEnabled: true,
  isMorningDialogEnabled: true,
  lastSyncAt: DateTime(2026, 9, 13, 7, 32),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// 端末を iOS / Android に見立てて [body] を実行する（変数は本体の中で必ず戻す）
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  late _AuthLog auth;

  Future<_FakePrefs> pumpSettings(
    WidgetTester tester, {
    Future<Client?> Function()? client,
    Future<Trainer?> Function()? trainer,
    NotificationPreferencesState prefs = const NotificationPreferencesState(
      sessionReminderEnabled: false,
    ),
    NotificationPreferences Function(_FakePrefs fake)? prefsOverride,
    bool healthAvailable = true,
    ThemeData? theme,
    double textScale = 1.0,
    bool settle = true,

    /// ナビ（FcBottomNavLayout）が MediaQuery に足す下余白の見立て
    double bottomPadding = 0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    auth = _AuthLog();
    final fakePrefs = _FakePrefs(prefs);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWith(() => _FakeAuth(auth)),
          currentClientProvider.overrideWith(
            (ref) => client != null ? client() : Future.value(_client),
          ),
          trainerProfileProvider.overrideWith(
            (ref) => trainer != null ? trainer() : Future.value(_trainer),
          ),
          notificationPreferencesProvider.overrideWith(
            () => prefsOverride != null ? prefsOverride(fakePrefs) : fakePrefs,
          ),
          healthAvailableProvider.overrideWith((ref) async => healthAvailable),
          healthSettingsProvider
              .overrideWith(() => _FakeHealthSettings(_health)),
          healthSyncProvider.overrideWith(() => _FakeHealthSync()),
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'FIT-CONNECT',
              packageName: 'jp.example.fitconnect',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: EdgeInsets.only(bottom: bottomPadding),
            ),
            child: child!,
          ),
          home: const SettingsScreen(),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return fakePrefs;
  }

  group('SettingsScreen 構成と文言', () {
    testWidgets('見出し・プロフィール・各グループ・バージョンが正本の順に出る', (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpSettings(tester);

        expect(find.byType(AppBar), findsNothing);
        expect(find.text('設定'), findsOneWidget);
        // プロフィール
        expect(find.text('佐藤 美咲'), findsOneWidget);
        expect(find.text('misaki.sato@example.com'), findsOneWidget);
        expect(find.text('担当トレーナー'), findsOneWidget);
        expect(find.text('田中トレーナー'), findsOneWidget);
        // グループ（上から順）
        final labels = ['外観', '通知', 'ヘルスケア連携', '法的情報', 'アカウント'];
        double previousTop = -1;
        for (final label in labels) {
          expect(find.text(label), findsOneWidget, reason: label);
          final top = tester.getTopLeft(find.text(label)).dy;
          expect(top, greaterThan(previousTop), reason: label);
          previousTop = top;
        }
        // 行
        for (final title in [
          'トレーナーからのメッセージ',
          '目標の達成',
          'セッションのリマインド',
          'HealthKit',
          '利用規約',
          'プライバシーポリシー',
          'ログアウト',
          'アカウントを削除',
        ]) {
          expect(find.text(title), findsOneWidget, reason: title);
        }
        expect(find.text('FIT-CONNECT バージョン 1.0.0'), findsOneWidget);
      });
    });

    testWidgets('旧デザインの「アプリ情報」「通知設定」「システム」などは出ない', (tester) async {
      await pumpSettings(tester);

      expect(find.text('アプリ情報'), findsNothing);
      expect(find.text('通知設定'), findsNothing);
      expect(find.text('システム'), findsNothing);
      expect(find.text('バージョン'), findsNothing);
    });

    testWidgets('画面の文字に絵文字は無い', (tester) async {
      await pumpSettings(tester);

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

  group('SettingsScreen プロフィール', () {
    testWidgets('アバター（写真を変更）と鉛筆（名前を変更）は 44×44 以上の操作', (tester) async {
      await pumpSettings(tester);

      for (final label in ['写真を変更', '名前を変更']) {
        final target = find.bySemanticsLabel(label);
        expect(target, findsOneWidget, reason: label);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      // 名前の変更ダイアログは現行のまま開く
      await tester.tap(find.bySemanticsLabel('名前を変更'));
      await tester.pumpAndSettle();
      expect(find.text('名前を編集'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('担当トレーナーの値は「田中」でも「田中トレーナー」でも「田中トレーナー」（二重にならない）',
        (tester) async {
      for (final raw in ['田中', '田中トレーナー']) {
        await pumpSettings(
          tester,
          trainer: () => Future.value(Trainer(id: 'trainer-1', name: raw)),
        );

        expect(find.text('担当トレーナー'), findsOneWidget, reason: raw);
        expect(find.text('田中トレーナー'), findsOneWidget, reason: raw);
        expect(find.textContaining('トレーナートレーナー'), findsNothing, reason: raw);
      }
    });

    testWidgets('担当トレーナーが未設定なら「未設定」と出る', (tester) async {
      await pumpSettings(tester, trainer: () => Future.value(null));

      expect(find.text('担当トレーナー'), findsOneWidget);
      expect(find.text('未設定'), findsOneWidget);
    });

    testWidgets('担当トレーナーの読み込み中は値がスケルトン', (tester) async {
      final completer = Completer<Trainer?>();
      await pumpSettings(
        tester,
        trainer: () => completer.future,
        settle: false,
      );
      await tester.pump();

      expect(find.text('担当トレーナー'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      completer.complete(_trainer);
      await tester.pumpAndSettle();
      expect(find.text('田中トレーナー'), findsOneWidget);
    });

    testWidgets('ユーザー情報の読み込み中はスケルトン（配置を保つ）', (tester) async {
      final completer = Completer<Client?>();
      await pumpSettings(
        tester,
        client: () => completer.future,
        settle: false,
      );
      await tester.pump();

      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      expect(find.text('担当トレーナー'), findsNothing);
      // 読み込み中でも見出しと他のグループは出ている
      expect(find.text('設定'), findsOneWidget);
      expect(find.text('外観'), findsOneWidget);
      completer.complete(_client);
      await tester.pumpAndSettle();
      expect(find.text('担当トレーナー'), findsOneWidget);
    });

    testWidgets('ユーザー情報を読めなければ再試行つきのお知らせ', (tester) async {
      await pumpSettings(tester, client: () => Future.value(null));

      expect(find.text('ユーザー情報を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('SettingsScreen 外観', () {
    testWidgets('ライト / ダーク / 自動の 3 択で、選択するとテーマモードが変わる', (tester) async {
      await pumpSettings(tester);

      for (final label in ['ライト', 'ダーク', '自動']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      Color? segmentColor(String label) {
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      // 既定は「自動」が選択中
      expect(segmentColor('自動'), AppColorsExtension.light.actionFill);
      expect(segmentColor('ダーク'), AppColorsExtension.light.surface);

      await tester.tap(find.text('ダーク'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)));
      expect(container.read(themeModeNotifierProvider), ThemeMode.dark);
      expect(segmentColor('ダーク'), AppColorsExtension.light.actionFill);
      expect(segmentColor('自動'), AppColorsExtension.light.surface);
    });
  });

  group('SettingsScreen 通知', () {
    testWidgets('現行の 3 項目がトグルの行で並び、リマインドの補足は実際の送信に合わせる', (tester) async {
      await pumpSettings(tester);

      expect(find.byType(FcToggle), findsNWidgets(3));
      expect(find.text('前日の夜にお知らせ'), findsOneWidget);
      // 実際は前日の夜 1 回なので、正本の「前日と当日の朝」とは書かない
      expect(find.textContaining('当日'), findsNothing);
    });

    testWidgets('行のどこを押しても切り替わり、種別と新しい値が渡る', (tester) async {
      final fake = await pumpSettings(tester);

      await tester.tap(find.text('トレーナーからのメッセージ'));
      await tester.tap(find.text('目標の達成'));
      await tester.tap(find.text('セッションのリマインド'));
      await tester.pump();

      expect(fake.changes, [
        (NotificationKind.message, false),
        (NotificationKind.goalAchievement, false),
        (NotificationKind.sessionReminder, true),
      ]);
    });

    testWidgets('読み込み中は行の配置を保つ（トグルの代わりにスケルトン）', (tester) async {
      final completer = Completer<NotificationPreferencesState>();
      await pumpSettings(
        tester,
        prefsOverride: (_) => _PendingPrefs(completer.future),
        settle: false,
      );
      await tester.pump();

      expect(find.text('トレーナーからのメッセージ'), findsOneWidget);
      expect(find.byType(FcToggle), findsNothing);
      expect(find.byType(FcSkeleton), findsWidgets);
      completer.complete(const NotificationPreferencesState());
      await tester.pumpAndSettle();
      expect(find.byType(FcToggle), findsNWidgets(3));
    });

    testWidgets('読み込みに失敗したら再試行つきのお知らせ', (tester) async {
      await pumpSettings(tester, prefsOverride: (_) => _FailingPrefs());

      expect(find.text('通知設定を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('SettingsScreen ヘルスケア連携', () {
    testWidgets('iOS は HealthKit。連携中・データ・最終同期が補足に出て、押すと設定画面へ進む',
        (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpSettings(tester);

        expect(find.text('HealthKit'), findsOneWidget);
        expect(find.byIcon(LucideIcons.heartPulse), findsOneWidget);
        // 「連携中 · 体重 · 睡眠 · 最終同期 9月13日（日）7:32」
        expect(
          find.text('連携中 · 体重 · 睡眠 · 最終同期 9月13日（日）7:32'),
          findsOneWidget,
        );
        expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);

        await tester.tap(find.text('HealthKit'));
        await tester.pumpAndSettle();
        expect(find.byType(HealthSettingsScreen), findsOneWidget);
      });
    });

    testWidgets('Android は Health Connect と出る', (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        await pumpSettings(tester);

        expect(find.text('Health Connect'), findsOneWidget);
        expect(find.text('HealthKit'), findsNothing);
      });
    });

    testWidgets('連携できない端末ではグループごと出ない', (tester) async {
      await pumpSettings(tester, healthAvailable: false);

      expect(find.text('ヘルスケア連携'), findsNothing);
      expect(find.byIcon(LucideIcons.heartPulse), findsNothing);
    });
  });

  group('SettingsScreen 法的情報とアカウント', () {
    testWidgets('規約・プライバシーポリシーは外部リンクのアイコン（chevron ではない）', (tester) async {
      await pumpSettings(tester);

      expect(find.byIcon(LucideIcons.externalLink), findsNWidgets(2));
    });

    testWidgets('ログアウトは log-out アイコン、削除は error 色・アイコンなしで、どちらも chevron なし',
        (tester) async {
      await pumpSettings(tester);

      expect(find.byIcon(LucideIcons.logOut), findsOneWidget);
      final delete = tester.widget<Text>(find.text('アカウントを削除'));
      expect(delete.style!.color, AppColorsExtension.light.error);
      expect(find.byIcon(LucideIcons.userX), findsNothing);
      // chevron はヘルスケア連携の行（1 つ）だけ
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('外部リンクの行は「外部で開く」を読み上げに含める', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester);

      expect(find.bySemanticsLabel('利用規約、外部で開く'), findsOneWidget);
      expect(find.bySemanticsLabel('プライバシーポリシー、外部で開く'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('ログアウトとアカウント削除は確認ダイアログを開く（文言は現行のまま）', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      expect(find.text('ログアウトしますか？'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      // キャンセルでは何も実行しない
      expect(auth.signOuts, 0);

      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      expect(
        find.text('アカウントを削除すると、以下のデータがすべて削除されます。'),
        findsOneWidget,
      );
      expect(find.text('この操作は取り消せません。'), findsOneWidget);
      expect(find.text('続ける'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 0);
    });
  });

  group('SettingsScreen ログアウトの確定', () {
    // ダイアログの題名と同じ文言のボタンがあるので、操作ボタン（TextButton）の中から探す
    Finder dialogAction(String label) => find.descendant(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ),
          matching: find.text(label),
        );

    testWidgets('「ログアウト」を確定すると signOut が 1 回呼ばれ、ダイアログは閉じる', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction('ログアウト'));
      await tester.pumpAndSettle();

      expect(auth.signOuts, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('失敗したらダイアログを閉じて SnackBar で伝える', (tester) async {
      await pumpSettings(tester);
      auth.signOutError = Exception('network');

      await tester.tap(find.text('ログアウト'));
      await tester.pumpAndSettle();
      await tester.tap(dialogAction('ログアウト'));
      await tester.pumpAndSettle();

      expect(auth.signOuts, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('ログアウトに失敗しました'), findsOneWidget);
    });
  });

  group('SettingsScreen アカウント削除の確定', () {
    // ダイアログの題名と同じ文言のボタンがあるので、操作ボタン（TextButton）の中から探す
    Finder dialogAction(String label) => find.descendant(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextButton),
          ),
          matching: find.text(label),
        );

    /// 1 段階目（説明）を「続ける」で抜け、2 段階目（最終確認）を開く
    Future<void> openFinalConfirm(WidgetTester tester) async {
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      expect(find.text('本当に削除しますか？'), findsOneWidget);
      expect(
        find.text('この操作は取り消せません。すべてのデータが完全に削除されます。'),
        findsOneWidget,
      );
    }

    testWidgets('最終確認で「削除する」を押すと deleteAccount が 1 回呼ばれ、ダイアログは閉じる',
        (tester) async {
      await pumpSettings(tester);
      await openFinalConfirm(tester);
      expect(auth.deletions, 0);

      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();

      expect(auth.deletions, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('削除の実行中は二重に押せず、キャンセルも押せない（進行表示になる）', (tester) async {
      await pumpSettings(tester);
      final gate = Completer<void>();
      auth.deletionGate = gate;
      await openFinalConfirm(tester);

      await tester.tap(find.text('削除する'));
      await tester.pump();

      // 実行中: 「削除する」は進行表示に変わり、2 つのボタンとも無効
      expect(dialogAction('削除する'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final buttons = tester
          .widgetList<TextButton>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextButton),
            ),
          )
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.every((button) => button.onPressed == null), isTrue);

      // 無効のボタンを押しても何も起きない
      await tester.tap(dialogAction('キャンセル'), warnIfMissed: false);
      await tester.pump();
      expect(auth.deletions, 1);
      expect(find.byType(AlertDialog), findsOneWidget);

      // 終わったらダイアログが閉じる
      gate.complete();
      await tester.pumpAndSettle();
      expect(auth.deletions, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('失敗したらダイアログを閉じて SnackBar で伝え、もう一度試せる', (tester) async {
      await pumpSettings(tester);
      auth.deletionError = Exception('server error');
      await openFinalConfirm(tester);

      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();

      expect(auth.deletions, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('アカウントの削除に失敗しました'), findsOneWidget);

      // 再試行できる（行はそのまま残っている）
      auth.deletionError = null;
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('続ける'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(auth.deletions, 2);
    });
  });

  group('SettingsScreen ナビの下まで潜る', () {
    testWidgets('SafeArea は下を含めず、スクロール領域の下余白にナビぶん（MediaQuery の下余白）を足す',
        (tester) async {
      await pumpSettings(tester, bottomPadding: 121);

      final safeArea = tester.widget<SafeArea>(find.byType(SafeArea));
      expect(safeArea.bottom, isFalse);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      // ナビのための余白は 1 回だけ（SafeArea と二重に足さない）
      expect(scroll.padding!.resolve(TextDirection.ltr).bottom, 121);
    });

    testWidgets('ナビが無いとき（下余白 0）は余白を足さない', (tester) async {
      await pumpSettings(tester);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.padding!.resolve(TextDirection.ltr).bottom, 0);
    });
  });

  group('SettingsScreen 文字拡大 1.35 とダーク', () {
    testWidgets('長い名前・メールでも文字拡大 1.35 で overflow せず、行の領域は 44 以上',
        (tester) async {
      await pumpSettings(
        tester,
        client: () => Future.value(
          Client(
            clientId: 'c',
            name: '佐藤 美咲（とても長い名前のユーザー）',
            email:
                'very.long.address.for.overflow.check@example-company.example.com',
            trainerId: 't',
            createdAt: DateTime(2026, 1, 1),
          ),
        ),
        trainer: () => Future.value(
          const Trainer(id: 't', name: '田中トレーナー（パーソナルコーチ）'),
        ),
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      for (final title in ['利用規約', 'ログアウト', 'アカウントを削除']) {
        final row = find
            .ancestor(of: find.text(title), matching: find.byType(FcPressable))
            .first;
        expect(
          tester.getSize(row).height,
          greaterThanOrEqualTo(44),
          reason: title,
        );
      }
    });

    testWidgets('ダークでも崩れない（カードは surface）', (tester) async {
      await pumpSettings(tester, theme: AppTheme.darkTheme);

      expect(tester.takeException(), isNull);
      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard).first,
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (card.decoration as BoxDecoration).color,
        AppColorsExtension.dark.surface,
      );
    });
  });
}
