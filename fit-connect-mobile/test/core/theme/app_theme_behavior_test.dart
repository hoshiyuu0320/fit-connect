import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// テーマが「画面側の指定」と干渉しないことの確認（入力欄の枠・AppBar の文字色・SnackBar・無効ボタン）。

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG のコントラスト比（不透明な 2 色）
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [top]（半透明でもよい）を [base] の上に重ねた色
Color over(Color top, Color base) => Color.alphaBlend(top, base);

ThemeData themeOf(Brightness b) =>
    b == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;

AppColorsExtension colorsOf(Brightness b) =>
    b == Brightness.dark ? AppColorsExtension.dark : AppColorsExtension.light;

Future<void> pumpThemed(
  WidgetTester tester,
  Widget home, {
  required Brightness brightness,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    final mode = brightness.name;
    final theme = themeOf(brightness);
    final c = colorsOf(brightness);

    group('入力欄（$mode）: 画面側の枠の指定が効く', () {
      InputDecoration mergedDecoration(WidgetTester tester) =>
          tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

      testWidgets(
          '`border: InputBorder.none` の入力欄は、枠も面も付かない（自前の枠付きコンテナの中に置く旧画面）',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: TextField(
              decoration: InputDecoration(
                hintText: 'メールアドレスを入力',
                border: InputBorder.none,
              ),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        expect(d.border, InputBorder.none);
        // テーマが状態別の枠を足していない（足すと border: none より先に使われて枠が戻る）
        expect(d.enabledBorder, isNull);
        expect(d.focusedBorder, isNull);
        expect(d.errorBorder, isNull);
        expect(d.focusedErrorBorder, isNull);
        expect(d.disabledBorder, isNull);
        // 面も塗らない（外側のコンテナの面と二重にならない）
        expect(d.filled, isNot(isTrue));
      });

      testWidgets('ラベル付き・エラー付きでも `border: none` のまま（枠の切り欠き・灰色の面が出ない）',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: TextField(
              decoration: InputDecoration(
                labelText: 'お名前',
                errorText: '名前を入力してください',
                border: InputBorder.none,
              ),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        expect(d.border, InputBorder.none);
        expect(d.enabledBorder, isNull);
        expect(d.errorBorder, isNull);
        expect(d.filled, isNot(isTrue));
      });

      testWidgets('画面側が状態別の枠を自分で持っていれば、それがそのまま使われる（招待コード画面）', (tester) async {
        final own = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        );
        await pumpThemed(
          tester,
          Scaffold(
            body: TextField(
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.amber,
                border: own,
                enabledBorder: own,
                focusedBorder: own,
              ),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        expect(d.enabledBorder, own);
        expect(d.focusedBorder, own);
        expect(d.fillColor, Colors.amber);
        expect(d.filled, isTrue);
      });

      testWidgets('指定のない入力欄の既定は、1px の separator の枠（フォーカス accent・エラー error）',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: TextField(
              decoration: InputDecoration(labelText: '名前', hintText: '名前を入力'),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        final border = d.border! as WidgetStateInputBorder;
        expect(
          (border.resolve({}) as OutlineInputBorder).borderSide.color,
          c.separator,
        );
        expect(
          (border.resolve({WidgetState.focused}) as OutlineInputBorder)
              .borderSide
              .color,
          c.accent,
        );
        expect(
          (border.resolve({WidgetState.error}) as OutlineInputBorder)
              .borderSide
              .color,
          c.error,
        );
        // 既定では面を塗らない（filled: true を渡した入力欄だけ surface）
        expect(d.filled, isNot(isTrue));
        expect(d.fillColor, c.surface);
      });

      testWidgets('FcTextField は自前で面（surface）と状態別の枠を持つ（テーマの変更に影響されない）',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: FcTextField(label: '内容'),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        expect(d.filled, isTrue);
        expect(d.fillColor, c.surface);
        expect(
          (d.enabledBorder! as OutlineInputBorder).borderSide.color,
          c.separator,
        );
        expect(
          (d.focusedBorder! as OutlineInputBorder).borderSide.color,
          c.accent,
        );
      });

      testWidgets('チャット入力欄のように `filled: false` と全部の枠を none にした入力欄も壊れない',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: TextField(
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
              ),
            ),
          ),
          brightness: brightness,
        );
        final d = mergedDecoration(tester);
        expect(d.filled, isFalse);
        expect(d.enabledBorder, InputBorder.none);
      });
    });

    group('AppBar の title（$mode）: 色は foregroundColor に従う', () {
      TextStyle titleStyleOf(WidgetTester tester) {
        final rich = tester.widget<RichText>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(RichText),
              )
              .first,
        );
        return rich.text.style!;
      }

      testWidgets('通常の AppBar（foregroundColor 未指定）は textPrimary・17 / 500',
          (tester) async {
        await pumpThemed(
          tester,
          Scaffold(appBar: AppBar(title: const Text('設定'))),
          brightness: brightness,
        );
        final style = titleStyleOf(tester);
        expect(style.color, c.textPrimary);
        expect(style.fontSize, 17);
        expect(style.fontWeight, FontWeight.w500);
        expect(theme.appBarTheme.titleTextStyle, isNull,
            reason: '色まで固定される titleTextStyle をテーマに置かない');
      });

      testWidgets('QR スキャンの黒い AppBar（foregroundColor: 白）は title も白で読める',
          (tester) async {
        await pumpThemed(
          tester,
          Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('QRコードをスキャン'),
            ),
          ),
          brightness: brightness,
        );
        final style = titleStyleOf(tester);
        expect(style.color, Colors.white);
        expect(contrast(style.color!, Colors.black), greaterThanOrEqualTo(4.5));
        expect(style.fontSize, 17);
        expect(style.fontWeight, FontWeight.w500);
      });
    });

    group('SnackBar（$mode）: どの背景でも読める', () {
      test('面は暗い中立・文字は白固定で、コントラスト 4.5:1 以上。操作の文字も読める', () {
        final snack = theme.snackBarTheme;
        final background = snack.backgroundColor!;
        final text = snack.contentTextStyle!.color!;
        expect(text, Colors.white);
        expect(contrast(text, background), greaterThanOrEqualTo(4.5));
        expect(contrast(snack.actionTextColor!, background),
            greaterThanOrEqualTo(4.5));
        // ライトでも暗い面（ダークでも画面の地・カードと見分けがつく）
        expect(_luminance(background), lessThan(0.1));
        expect(contrast(background, c.background), greaterThan(1.1));
        expect(contrast(background, c.surface), greaterThan(1.1));
      });

      test('浮かせて表示・角丸 12・影なし（固定だと下部ナビの裏に高い帯ができる）', () {
        final snack = theme.snackBarTheme;
        expect(snack.behavior, SnackBarBehavior.floating);
        expect(snack.shape,
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)));
        expect(snack.elevation, 0);
      });

      testWidgets('rose800 / success のような画面側の明示背景がなくても読める（テーマの面で描かれる）',
          (tester) async {
        final key = GlobalKey<ScaffoldMessengerState>();
        tester.view.physicalSize = const Size(390, 844) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: key,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: const Scaffold(body: SizedBox.expand()),
          ),
        );
        key.currentState!.showSnackBar(
          SnackBar(
            content: const Text('保存しました'),
            action: SnackBarAction(label: '元に戻す', onPressed: () {}),
            duration: const Duration(minutes: 5),
          ),
        );
        await tester.pumpAndSettle();

        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, theme.snackBarTheme.backgroundColor);
        final rich = tester.widget<RichText>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(RichText),
              )
              .first,
        );
        expect(rich.text.style!.color, Colors.white);
        key.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
      });
    });

    group('無効なボタン（$mode）: 正本は「通常の面のまま opacity 0.4」', () {
      final disabled = <WidgetState>{WidgetState.disabled};

      test('FilledButton / ElevatedButton: 面は actionFill の 40%、文字は onAction',
          () {
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.elevatedButtonTheme.style!,
        ]) {
          expect(
            style.backgroundColor!.resolve(disabled),
            c.actionFill.withValues(alpha: 0.4),
          );
          expect(style.foregroundColor!.resolve(disabled), c.onAction);
          // 有効時は変わらない
          expect(style.backgroundColor!.resolve({}), c.actionFill);
          expect(style.foregroundColor!.resolve({}), c.onAction);
        }
      });

      test('白いスピナー（onAction）が、無効の面の上で以前より読める（ページ背景に重ねたとき）', () {
        final style = theme.filledButtonTheme.style!;
        final face =
            over(style.backgroundColor!.resolve(disabled)!, c.background);
        final spinner = style.foregroundColor!.resolve(disabled)!;
        // 以前の無効色（surfaceSecondary の面）では、ライトで 1.17:1 だった
        final before = contrast(Colors.white, c.surfaceSecondary);
        expect(contrast(spinner, face), greaterThan(before));
        expect(contrast(spinner, face), greaterThanOrEqualTo(2.0));
        // 面が地に溶けない
        expect(contrast(face, c.background), greaterThan(1.3));
      });

      test(
          'TextButton / OutlinedButton: 無効は accent の 40%（FcButton.text / back と同じ）',
          () {
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve(disabled),
          c.accent.withValues(alpha: 0.4),
        );
        expect(
          theme.outlinedButtonTheme.style!.foregroundColor!.resolve(disabled),
          c.accent.withValues(alpha: 0.4),
        );
        expect(theme.textButtonTheme.style!.foregroundColor!.resolve({}),
            c.accent);
      });

      testWidgets('onPressed: null の ElevatedButton が、面を残したまま薄く描かれる',
          (tester) async {
        await pumpThemed(
          tester,
          const Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: null, child: Text('送信中')),
            ),
          ),
          brightness: brightness,
        );
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(ElevatedButton),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, c.actionFill.withValues(alpha: 0.4));
      });
    });
  }

  group('FcBottomNavLayout と SnackBar（浮かせた SnackBar がナビの上に出る）', () {
    const items = <FcBottomNavItem>[
      FcBottomNavItem(icon: Icons.home, label: 'ホーム'),
      FcBottomNavItem(icon: Icons.chat, label: 'メッセージ'),
      FcBottomNavItem(icon: Icons.fitness_center, label: 'プラン'),
      FcBottomNavItem(icon: Icons.bar_chart, label: '記録'),
      FcBottomNavItem(icon: Icons.settings, label: '設定'),
    ];

    for (final brightness in Brightness.values) {
      testWidgets(
          '${brightness.name}: SnackBar は内容ぶんの高さで、ナビのカプセルの上に収まる（高い帯を作らない）',
          (tester) async {
        final key = GlobalKey<ScaffoldMessengerState>();
        tester.view.physicalSize = const Size(390, 844) * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: key,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: FcBottomNavLayout(
              body: const Scaffold(body: SizedBox.expand()),
              bottomNav: FcBottomNav(
                items: items,
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
          ),
        );
        key.currentState!.showSnackBar(
          const SnackBar(
            content: Text('体重を保存しました'),
            duration: Duration(minutes: 5),
          ),
        );
        await tester.pumpAndSettle();

        // 面（Material）の矩形。SnackBar 自体は外側の余白を含む
        final snack = tester.getRect(find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first);
        final nav = tester.getRect(find.byType(FcBottomNav));
        // ナビのカプセルの上端 = ナビの上端 + 上余白 14
        final capsuleTop = nav.top + AppSizes.navTopPadding;
        expect(snack.bottom, lessThanOrEqualTo(capsuleTop));
        expect(snack.height, lessThan(80), reason: '下余白ぶんの高い帯にならない');
        // 左右は 16 の余白
        expect(snack.left, 16);
        expect(snack.right, 390 - 16);
        key.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
      });
    }
  });
}
