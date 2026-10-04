import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/consent/data/consent_repository.dart';
import 'package:fit_connect_mobile/features/consent/presentation/consent_dialog.dart';

/// Supabaseへ接続しないテスト用のFake Repository
class _FakeConsentRepository extends ConsentRepository {
  _FakeConsentRepository({this.shouldFail = false})
      : super(
          SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            // トークン自動更新タイマーが起動するとテスト終了時に
            // pending timer としてエラーになるため無効化する
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final bool shouldFail;
  int recordConsentCallCount = 0;
  String? lastUserId;

  /// 非 null の間、同意の記録が終わらない（記録中の表示を確かめる）
  Completer<void>? pending;

  @override
  Future<bool> hasCurrentConsent(String userId) async => false;

  @override
  Future<void> recordConsent(String userId) async {
    recordConsentCallCount++;
    lastUserId = userId;
    if (pending != null) await pending!.future;
    if (shouldFail) {
      throw Exception('network error');
    }
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeConsentRepository repository, {
  ThemeData? theme,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consentRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showConsentDialog(context, userId: 'user-1'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _agreeButton() {
  return find.widgetWithText(FilledButton, '同意してはじめる');
}

void main() {
  group('ConsentDialog', () {
    testWidgets('チェック前は同意ボタンがdisabled、チェックでenabledになる', (tester) async {
      final repository = _FakeConsentRepository();
      await _pumpDialog(tester, repository);

      // ダイアログが表示されている
      expect(find.text('ご利用にあたって'), findsOneWidget);

      // チェック前: ボタンはdisabled
      final buttonBefore = tester.widget<FilledButton>(_agreeButton());
      expect(buttonBefore.onPressed, isNull);

      // チェックボックスをタップ
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      // チェック後: ボタンはenabled
      final buttonAfter = tester.widget<FilledButton>(_agreeButton());
      expect(buttonAfter.onPressed, isNotNull);
    });

    testWidgets('同意の記録に成功するとダイアログが閉じる', (tester) async {
      final repository = _FakeConsentRepository();
      await _pumpDialog(tester, repository);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(_agreeButton());
      await tester.pumpAndSettle();

      expect(repository.recordConsentCallCount, 1);
      expect(repository.lastUserId, 'user-1');
      expect(find.text('ご利用にあたって'), findsNothing);
    });

    testWidgets('同意の記録に失敗するとSnackBarを表示しダイアログは閉じない（再試行可能）', (tester) async {
      final repository = _FakeConsentRepository(shouldFail: true);
      await _pumpDialog(tester, repository);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(_agreeButton());
      await tester.pumpAndSettle();

      // ダイアログは開いたまま + エラーSnackBar表示
      expect(find.text('ご利用にあたって'), findsOneWidget);
      expect(
        find.text('同意の記録に失敗しました。通信環境をご確認のうえ、もう一度お試しください。'),
        findsOneWidget,
      );
      // 色は付けない（既定のテーマの SnackBar）。失敗は文言で伝わる
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          isNull);

      // 再試行できる（ボタンが再びenabledに戻っている）
      final buttonAfterFailure = tester.widget<FilledButton>(_agreeButton());
      expect(buttonAfterFailure.onPressed, isNotNull);
    });

    testWidgets('バリアタップや戻る操作ではダイアログが閉じない', (tester) async {
      final repository = _FakeConsentRepository();
      await _pumpDialog(tester, repository);

      // バリア（ダイアログ外）をタップしても閉じない
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('ご利用にあたって'), findsOneWidget);

      // 戻る操作（maybePop）でも閉じない（PopScope: canPop=false）
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('ご利用にあたって'), findsOneWidget);
    });

    testWidgets('ダーク: 利用規約・プライバシーポリシーのリンクとアイコンは accent（#1C1C1E の上で読める）',
        (tester) async {
      await _pumpDialog(
        tester,
        _FakeConsentRepository(),
        theme: AppTheme.darkTheme,
      );
      final dark = AppColorsExtension.dark;

      for (final label in ['利用規約', 'プライバシーポリシー']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.color, dark.accent, reason: label);
        expect(text.style!.decorationColor, dark.accent, reason: label);
        // 静的な primary500/600 は使わない
        expect(text.style!.color, isNot(AppColors.primary600));
      }
      for (final icon in [
        LucideIcons.fileText,
        LucideIcons.shieldCheck,
      ]) {
        expect(tester.widget<Icon>(find.byIcon(icon)).color, dark.accent);
      }
      for (final icon in tester.widgetList<Icon>(
        find.byIcon(LucideIcons.externalLink),
      )) {
        expect(icon.color, dark.accent);
      }
    });

    testWidgets('リンク行のタップ領域は高さ 44 以上で、リンクとして読み上げられる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDialog(tester, _FakeConsentRepository());

      for (final label in ['利用規約', 'プライバシーポリシー']) {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44),
            reason: label);
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          matchesSemantics(
            label: label,
            isLink: true,
            hasTapAction: true,
            hasEnabledState: false,
          ),
          reason: label,
        );
      }
      handle.dispose();
    });

    testWidgets('記録中は押せないが、薄い無効表示にせず塗りのままスピナーを見せる', (tester) async {
      final repository = _FakeConsentRepository()..pending = Completer<void>();
      await _pumpDialog(tester, repository);
      final light = AppColorsExtension.light;

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(_agreeButton());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 押せない（もう一度押しても二重送信しない）
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(repository.recordConsentCallCount, 1);

      // 面は actionFill のまま、スピナーは onAction（読める色）
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, light.onAction);
      final style =
          tester.widget<FilledButton>(find.byType(FilledButton)).style!;
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled}),
        light.actionFill,
      );

      repository.pending!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('文字拡大 1.35 でも overflow しない（ダーク）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpDialog(
        tester,
        _FakeConsentRepository(),
        theme: AppTheme.darkTheme,
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('同意してはじめる'), findsOneWidget);
    });
  });
}
