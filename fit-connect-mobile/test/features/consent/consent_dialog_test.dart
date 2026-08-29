import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  @override
  Future<bool> hasCurrentConsent(String userId) async => false;

  @override
  Future<void> recordConsent(String userId) async {
    recordConsentCallCount++;
    lastUserId = userId;
    if (shouldFail) {
      throw Exception('network error');
    }
  }
}

Future<void> _pumpDialog(
  WidgetTester tester,
  _FakeConsentRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consentRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showConsentDialog(context, userId: 'user-1'),
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

    testWidgets('同意の記録に失敗するとSnackBarを表示しダイアログは閉じない（再試行可能）',
        (tester) async {
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
  });
}
