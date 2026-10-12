import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/registration_complete_screen.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/screens/onboarding_flow_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

class _FakeRegistration extends RegistrationNotifier {
  _FakeRegistration(this.initial);
  final RegistrationState initial;

  @override
  RegistrationState build() => initial;
}

/// 登録完了画面。紙吹雪・グラデーション・光る影をやめ、ページ背景の上に静かに表示する。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpComplete(
    WidgetTester tester, {
    String? trainerName = '田中',
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registrationNotifierProvider.overrideWith(
            () => _FakeRegistration(
              RegistrationState(
                trainerId: 't1',
                trainerName: trainerName,
                isRegistrationComplete: true,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const RegistrationCompleteScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('RegistrationCompleteScreen', () {
    testWidgets('トレーナー名つきの見出し・説明・ボタンが表示される', (tester) async {
      await pumpComplete(tester);

      expect(find.text('登録完了！'), findsOneWidget);
      expect(find.text('田中トレーナーと\nつながりました！'), findsOneWidget);
      expect(
        find.text('トレーニングを始める準備ができました。\n一緒に目標を達成しましょう！'),
        findsOneWidget,
      );
      expect(find.text('トレーニングを始める'), findsOneWidget);
      expect(find.byIcon(LucideIcons.check), findsOneWidget);
    });

    testWidgets('トレーナー名が無いときは「登録完了！」が見出しになる', (tester) async {
      await pumpComplete(tester, trainerName: null);

      expect(find.text('登録完了！'), findsOneWidget);
      expect(find.textContaining('つながりました'), findsNothing);
    });

    testWidgets('紙吹雪・グラデーション・影を使わない（背景は background）', (tester) async {
      await pumpComplete(tester);

      // 紙吹雪なし
      expect(find.byType(ConfettiWidget), findsNothing);

      // グラデーションと影のある装飾がない
      final decorations = <BoxDecoration>[
        ...tester
            .widgetList<Container>(find.byType(Container))
            .map((c) => c.decoration)
            .whereType<BoxDecoration>(),
        ...tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((d) => d.decoration)
            .whereType<BoxDecoration>(),
      ];
      expect(decorations.where((d) => d.gradient != null), isEmpty);
      expect(
          decorations.where((d) => d.boxShadow?.isNotEmpty ?? false), isEmpty);

      // 全面を青緑で塗らない（背景はページ背景のまま）
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNull);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor,
        AppColorsExtension.light.background,
      );

      // 説明は FcCard（surface）に入る
      expect(find.byType(FcCard), findsOneWidget);
    });

    testWidgets('ダーク: チェックは accent、面は surface、ボタンは actionFill', (tester) async {
      await pumpComplete(tester, theme: AppTheme.darkTheme);
      final dark = AppColorsExtension.dark;

      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.check)).color,
        dark.accent,
      );
      final tile = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(LucideIcons.check),
          matching: find.byType(Container),
        ),
      );
      expect((tile.decoration as BoxDecoration).color, dark.surface);

      final buttonFace = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcButton),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((buttonFace.decoration as BoxDecoration).color, dark.actionFill);
    });

    testWidgets('「トレーニングを始める」でオンボーディング後段フローへ進む（44 以上のタップ領域）', (tester) async {
      await pumpComplete(tester);

      expect(
        tester.getSize(find.byType(FcButton)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.text('トレーニングを始める'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingFlowScreen), findsOneWidget);
      expect(find.text('通知をオンにしましょう'), findsOneWidget);
    });

    testWidgets('文字拡大 1.35: 折り返して縦に伸び、横にはみ出さない', (tester) async {
      await pumpComplete(tester, textScale: 1.35);

      expect(tester.takeException(), isNull);
      for (final text in [
        '田中トレーナーと\nつながりました！',
        'トレーニングを始める準備ができました。\n一緒に目標を達成しましょう！',
      ]) {
        final rect = tester.getRect(find.text(text));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(390));
      }
      // ボタンは画面内に残る
      expect(
        tester.getRect(find.byType(FcButton)).bottom,
        lessThanOrEqualTo(844),
      );
    });
  });
}
