import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// ヘルスケア連携の設定画面の表示テスト。
/// 設定の読み書きと同期は Provider を差し替え、SharedPreferences・HealthKit には触れない。
class _FakeHealthSettings extends HealthSettings {
  _FakeHealthSettings(this.initial);

  final HealthSettingsState initial;
  final calls = <String>[];

  @override
  Future<HealthSettingsState> build() async => initial;

  @override
  Future<bool> toggleEnabled(bool value) async {
    calls.add('master:$value');
    return true;
  }

  @override
  Future<void> toggleWeightEnabled(bool value) async {
    calls.add('weight:$value');
  }

  @override
  Future<bool> toggleSleepEnabled(bool value) async {
    calls.add('sleep:$value');
    return true;
  }

  @override
  Future<void> toggleMorningDialogEnabled(bool value) async {
    calls.add('morning:$value');
  }
}

class _FakeHealthSync extends HealthSync {
  int manualSyncs = 0;

  @override
  Future<void> build() async {}

  @override
  Future<void> syncManual() async {
    manualSyncs++;
  }
}

HealthSettingsState _connected({
  HealthSyncStatus status = HealthSyncStatus.idle,
  String? error,
}) =>
    HealthSettingsState(
      isEnabled: true,
      isWeightEnabled: true,
      isSleepEnabled: true,
      isMorningDialogEnabled: true,
      lastSyncAt: DateTime.now().subtract(const Duration(minutes: 5)),
      lastSyncStatus: status,
      lastSyncError: error,
    );

const _disconnected = HealthSettingsState(
  isEnabled: false,
  isWeightEnabled: false,
  isSleepEnabled: false,
  isMorningDialogEnabled: true,
);

void main() {
  late _FakeHealthSync sync;

  Future<_FakeHealthSettings> pumpScreen(
    WidgetTester tester,
    HealthSettingsState settings, {
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fake = _FakeHealthSettings(settings);
    sync = _FakeHealthSync();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          healthSettingsProvider.overrideWith(() => fake),
          healthSyncProvider.overrideWith(() => sync),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const HealthSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  group('HealthSettingsScreen 構成と文言', () {
    testWidgets('戻る・見出しと、連携 / データソース / 通知 / 同期の各グループが出る', (tester) async {
      await pumpScreen(tester, _connected());

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('戻る'), findsOneWidget);
      // 見出しとマスターの行で同じ文言が 2 回
      expect(find.text('ヘルスケア連携'), findsNWidgets(2));
      expect(
        find.text('お使いの端末のヘルスケア（iOS: ヘルスケア / Android: Health Connect）からデータを取得'),
        findsOneWidget,
      );
      expect(find.text('データソース'), findsOneWidget);
      expect(find.text('体重'), findsOneWidget);
      expect(find.text('読み取りのみ'), findsOneWidget);
      expect(find.text('睡眠'), findsOneWidget);
      expect(find.text('HealthKit/Health Connect から睡眠データを取得'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('朝の目覚めダイアログ'), findsOneWidget);
      expect(find.text('同期'), findsOneWidget);
      expect(find.text('最終同期'), findsOneWidget);
      expect(find.text('5分前'), findsOneWidget);
      expect(find.text('今すぐ同期'), findsOneWidget);
      expect(
        find.text('手動入力の体重記録がある日はHealthKitからの取り込みをスキップします'),
        findsOneWidget,
      );
      // 旧デザインの「NEW」バッジは出さない
      expect(find.text('NEW'), findsNothing);
      // 同期に失敗していなければ警告は出ない
      expect(find.byType(HealthSyncErrorRow), findsNothing);
    });

    testWidgets('未同期なら「未同期」と出る', (tester) async {
      await pumpScreen(
        tester,
        const HealthSettingsState(
          isEnabled: true,
          isWeightEnabled: true,
          isSleepEnabled: false,
          isMorningDialogEnabled: true,
        ),
      );

      expect(find.text('未同期'), findsOneWidget);
    });
  });

  group('HealthSettingsScreen 操作', () {
    testWidgets('マスターのスイッチ・データソース・朝のダイアログを切り替えられる', (tester) async {
      final fake = await pumpScreen(tester, _connected());

      await tester.tap(find.byType(FcToggle).at(0));
      await tester.tap(find.text('体重'));
      await tester.tap(find.text('睡眠'));
      await tester.tap(find.text('朝の目覚めダイアログ'));
      await tester.pump();

      expect(fake.calls, [
        'master:false',
        'weight:false',
        'sleep:false',
        'morning:false',
      ]);
    });

    testWidgets('連携していないあいだはデータソースを操作できず、今すぐ同期も押せない', (tester) async {
      final fake = await pumpScreen(tester, _disconnected);

      await tester.tap(find.text('体重'));
      await tester.tap(find.text('睡眠'));
      await tester.tap(find.text('今すぐ同期'));
      await tester.pump();

      expect(fake.calls, isEmpty);
      expect(sync.manualSyncs, 0);
      final button = tester.widget<FcButton>(find.byType(FcButton).last);
      expect(button.onPressed, isNull);
    });

    testWidgets('「今すぐ同期」で同期が走り、結果が SnackBar で出る', (tester) async {
      await pumpScreen(tester, _connected());

      await tester.tap(find.text('今すぐ同期'));
      await tester.pump();
      await tester.pump();

      expect(sync.manualSyncs, 1);
      expect(find.text('同期が完了しました'), findsOneWidget);
    });
  });

  group('HealthSettingsScreen 同期できないとき', () {
    testWidgets('警告（warning）の通知帯に「同期エラー: …」と再試行が出て、再試行で同期が走る', (tester) async {
      await pumpScreen(
        tester,
        _connected(
          status: HealthSyncStatus.error,
          error: 'HealthKitへのアクセスが拒否されました',
        ),
      );

      expect(find.byType(HealthSyncErrorRow), findsOneWidget);
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);

      await tester.tap(find.text('再試行'));
      await tester.pump();
      await tester.pump();
      expect(sync.manualSyncs, 1);
    });

    testWidgets('連携が切れているときは、同期エラーの「再試行」を出さない（押しても同期は走らない）', (tester) async {
      final fake = await pumpScreen(
        tester,
        const HealthSettingsState(
          isEnabled: false,
          isWeightEnabled: false,
          isSleepEnabled: false,
          isMorningDialogEnabled: true,
          lastSyncStatus: HealthSyncStatus.error,
          lastSyncError: 'HealthKitへのアクセスが拒否されました',
        ),
      );

      // 失敗の帯そのものは出る（取得済みの値と失敗の理由は伝える）
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
      // 「今すぐ同期」と同じく、連携が切れていれば再試行は無い
      expect(find.text('再試行'), findsNothing);
      expect(
        tester.widget<FcButton>(find.byType(FcButton).last).onPressed,
        isNull,
      );
      expect(sync.manualSyncs, 0);
      expect(fake.calls, isEmpty);
    });

    testWidgets('連携が切れているときのデータソース行は二重に薄くしない（スイッチだけが無効の見た目）', (tester) async {
      await pumpScreen(tester, _disconnected);

      for (final title in ['体重', '睡眠']) {
        final dimmed = find.ancestor(
          of: find.text(title),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity < 1,
          ),
        );
        expect(dimmed, findsNothing, reason: title);
      }
    });

    testWidgets('同期中は最終同期の値が「同期中…」になる', (tester) async {
      await pumpScreen(tester, _connected(status: HealthSyncStatus.syncing));

      expect(find.text('同期中…'), findsOneWidget);
      expect(find.text('5分前'), findsNothing);
    });
  });

  group('HealthSettingsScreen 読み込み中・失敗', () {
    testWidgets('読み込み中は配置を保つスケルトンを出す', (tester) async {
      final completer = Completer<HealthSettingsState>();
      await tester.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthSettingsProvider.overrideWith(
              () => _PendingHealthSettings(completer.future),
            ),
            healthSyncProvider.overrideWith(() => _FakeHealthSync()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HealthSettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FcSkeleton), findsNWidgets(3));
      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      expect(find.text('最終同期'), findsNothing);

      completer.complete(_connected());
      await tester.pumpAndSettle();
      expect(find.byType(FcSkeleton), findsNothing);
      expect(find.text('最終同期'), findsOneWidget);
    });

    testWidgets('設定を読めなければ再試行つきのエラーが出る', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            healthSettingsProvider.overrideWith(_FailingHealthSettings.new),
            healthSyncProvider.overrideWith(() => _FakeHealthSync()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HealthSettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('設定を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('HealthSettingsScreen 文字拡大 1.35 とダーク', () {
    testWidgets('文字拡大 1.35 の同期エラー表示でも overflow せず、操作は 44 以上', (tester) async {
      await pumpScreen(
        tester,
        _connected(
          status: HealthSyncStatus.error,
          error: 'HealthKitへのアクセスが拒否されました。設定アプリから許可してください',
        ),
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      for (final label in ['戻る', '今すぐ同期', '再試行']) {
        final target = find
            .ancestor(of: find.text(label), matching: find.byType(FcPressable))
            .first;
        expect(
          tester.getSize(target).height,
          greaterThanOrEqualTo(44),
          reason: label,
        );
      }
    });

    testWidgets('ダークの同期エラーは warningSurface の背景', (tester) async {
      await pumpScreen(
        tester,
        _connected(status: HealthSyncStatus.error, error: 'タイムアウト'),
        theme: AppTheme.darkTheme,
      );

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(HealthSyncErrorRow),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (box.decoration as BoxDecoration).color,
        AppColorsExtension.dark.warningSurface,
      );
    });
  });
}

class _PendingHealthSettings extends HealthSettings {
  _PendingHealthSettings(this.pending);

  final Future<HealthSettingsState> pending;

  @override
  Future<HealthSettingsState> build() => pending;
}

class _FailingHealthSettings extends HealthSettings {
  @override
  Future<HealthSettingsState> build() async => throw StateError('prefs failed');
}
