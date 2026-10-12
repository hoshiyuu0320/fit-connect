import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 認証フローの入力画面（ログイン・プロフィール設定）。入力欄を自前の枠で二重に囲まないこと、
/// ダークで選択・アバターの面が浮かないこと、文字拡大で崩れないことを確かめる。
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // 画面が Supabase.instance を触るだけ（通信しない）
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
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
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 入力欄を囲む「枠付きの Container」（旧: 自前の二重枠）が無いこと
  void expectNoBorderedWrapper(WidgetTester tester, Finder field) {
    final wrappers = tester
        .widgetList<Container>(
          find.ancestor(of: field, matching: find.byType(Container)),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null);
    expect(wrappers, isEmpty);
  }

  group('LoginScreen', () {
    testWidgets('メール入力欄はテーマの枠・surface の面（自前の枠で囲まない）', (tester) async {
      await pump(tester, const LoginScreen());

      final field = find.byType(TextField);
      expectNoBorderedWrapper(tester, field);

      final decoration = tester.widget<TextField>(field).decoration!;
      // 枠は指定しない = テーマの InputDecoration（1px separator・フォーカス accent）
      expect(decoration.border, isNull);
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, AppColorsExtension.light.surface);
    });

    testWidgets('ダーク: ロゴの面は surface、アイコンは accent', (tester) async {
      await pump(tester, const LoginScreen(), theme: AppTheme.darkTheme);
      final dark = AppColorsExtension.dark;

      final tile = tester.widget<Container>(
        find.ancestor(
          of: find.byIcon(LucideIcons.activity),
          matching: find.byType(Container),
        ),
      );
      expect((tile.decoration as BoxDecoration).color, dark.surface);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.activity)).color,
        dark.accent,
      );
    });

    testWidgets('文字拡大 1.35 でも overflow しない（ボタンは 48 以上）', (tester) async {
      await pump(
        tester,
        const LoginScreen(),
        textScale: 1.35,
        size: const Size(390, 1200),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester
            .getSize(find.widgetWithText(ElevatedButton, 'ログインリンクを送信'))
            .height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('ProfileSetupScreen', () {
    testWidgets('入力欄はテーマの枠・surface の面（自前の枠で囲まない）', (tester) async {
      await pump(tester, const ProfileSetupScreen());

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        expectNoBorderedWrapper(tester, fields.at(i));
      }
      for (final field
          in tester.widgetList<TextField>(find.byType(TextField))) {
        // TextFormField はテーマの既定（状態別の枠）を取り込む。InputBorder.none で消さない
        expect(
            field.decoration!.border, isA<WidgetStateProperty<InputBorder>>());
        expect(field.decoration!.border, isNot(InputBorder.none));
        expect(field.decoration!.filled, isTrue);
        expect(field.decoration!.fillColor, AppColorsExtension.light.surface);
      }
    });

    testWidgets('性別は 3 択のセグメント。選択を切り替えられる（既定は「その他」）', (tester) async {
      await pump(tester, const ProfileSetupScreen());

      expect(find.byType(FcSegmentedControl<String>), findsOneWidget);
      FcSegmentedControl<String> control() =>
          tester.widget<FcSegmentedControl<String>>(
              find.byType(FcSegmentedControl<String>));
      expect(control().selected, 'other');

      await tester.tap(find.text('男性'));
      await tester.pumpAndSettle();
      expect(control().selected, 'male');

      await tester.tap(find.text('女性'));
      await tester.pumpAndSettle();
      expect(control().selected, 'female');
    });

    testWidgets('ダーク: 選択中の性別は actionFill、アバターの面は surface（淡いミントで浮かない）',
        (tester) async {
      await pump(tester, const ProfileSetupScreen(), theme: AppTheme.darkTheme);
      final dark = AppColorsExtension.dark;

      // 選択中の「その他」は actionFill の塗り
      final selected = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('その他'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((selected.decoration as BoxDecoration).color, dark.actionFill);

      // アバターの面（80x80）は surface、アイコンは accent
      final avatar = tester.widget<Container>(
        find
            .ancestor(
              of: find.byIcon(LucideIcons.user).first,
              matching: find.byType(Container),
            )
            .first,
      );
      expect((avatar.decoration as BoxDecoration).color, dark.surface);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.user).first).color,
        dark.accent,
      );

      // 「タップして写真を設定」は accent（primary600 固定ではない）
      final hint = tester.widget<Text>(find.text('タップして写真を設定'));
      expect(hint.style!.color, dark.accent);
      expect(hint.style!.color, isNot(AppColors.primary600));
    });

    testWidgets('名前が空のまま送信すると、テーマのエラー表示（文言つき）が出る', (tester) async {
      await pump(tester, const ProfileSetupScreen());

      await tester.tap(find.text('登録を完了する'));
      await tester.pumpAndSettle();

      expect(find.text('名前を入力してください'), findsOneWidget);
    });

    testWidgets('文字拡大 1.35 でも overflow しない（性別の 3 択・ボタンが画面幅に収まる）',
        (tester) async {
      await pump(
        tester,
        const ProfileSetupScreen(),
        textScale: 1.35,
        size: const Size(390, 1200),
      );

      expect(tester.takeException(), isNull);
      for (final label in ['男性', '女性', 'その他']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.right, lessThanOrEqualTo(390), reason: label);
      }
    });
  });
}
