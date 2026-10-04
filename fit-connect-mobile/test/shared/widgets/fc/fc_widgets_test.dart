import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';
import 'package:fit_connect_mobile/shared/widgets/segmented_control.dart';

/// 390 × 844（iPhone 想定）で部品を置いて pump する
Future<void> pumpFc(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  bool scaffold = true,
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
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: scaffold
          ? Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Align(alignment: Alignment.topLeft, child: child),
              ),
            )
          : child,
    ),
  );
  await tester.pumpAndSettle();
}

const _navItems = <FcBottomNavItem>[
  FcBottomNavItem(icon: LucideIcons.home, label: 'ホーム'),
  FcBottomNavItem(icon: LucideIcons.messageSquare, label: 'メッセージ'),
  FcBottomNavItem(icon: LucideIcons.dumbbell, label: 'プラン'),
  FcBottomNavItem(icon: LucideIcons.barChart2, label: '記録'),
  FcBottomNavItem(icon: LucideIcons.settings, label: '設定'),
];

void main() {
  group('FcCard', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 角丸 23・不透明な surface・枠線も影もない',
          (tester) async {
        await pumpFc(
          tester,
          const FcCard(child: Text('本文')),
          brightness: brightness,
        );

        final decorated = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(FcCard),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = decorated.decoration as BoxDecoration;
        final expected = brightness == Brightness.dark
            ? AppColorsExtension.dark
            : AppColorsExtension.light;

        expect(decoration.borderRadius, BorderRadius.circular(23));
        expect(decoration.color, expected.surface);
        expect(decoration.color!.a, 1.0, reason: 'カードは不透明');
        expect(decoration.border, isNull, reason: '枠線なし');
        expect(decoration.boxShadow, isNull, reason: '影なし');
      });
    }

    testWidgets('padding: standard=20 / coach=17 / none=0', (tester) async {
      Future<EdgeInsetsGeometry> paddingOf(FcCardPadding p) async {
        await pumpFc(tester, FcCard(padding: p, child: const Text('x')));
        return tester
            .widget<Padding>(
              find.descendant(
                of: find.byType(FcCard),
                matching: find.byType(Padding),
              ),
            )
            .padding;
      }

      expect(await paddingOf(FcCardPadding.standard), const EdgeInsets.all(20));
      expect(await paddingOf(FcCardPadding.coach), const EdgeInsets.all(17));
      expect(await paddingOf(FcCardPadding.none), EdgeInsets.zero);
    });

    testWidgets('onTap でタップでき、semanticLabel が読み上げられる', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpFc(
        tester,
        FcCard(
          onTap: () => taps++,
          semanticLabel: '詳細を開く',
          child: const Text('本文'),
        ),
      );

      await tester.tap(find.text('本文'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('詳細を開く'), findsOneWidget);
      handle.dispose();
    });
  });

  group('FcButton', () {
    testWidgets('すべての種類でタッチ領域が 44×44 以上', (tester) async {
      final buttons = <Widget>[
        FcButton.block(label: 'ブロック', onPressed: () {}),
        FcButton.pill(label: 'ピル', onPressed: () {}),
        FcButton.pill(label: '控えめ', quiet: true, onPressed: () {}),
        FcButton.text(label: 'テキスト', onPressed: () {}),
        FcButton.back(label: '戻る', onPressed: () {}),
        const FcButton.block(label: '無効', onPressed: null),
      ];
      await pumpFc(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: buttons,
        ),
        size: const Size(390, 1200),
      );

      for (final element in find.byType(FcButton).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, greaterThanOrEqualTo(44),
            reason: '${(element.widget as FcButton).label} の幅');
        expect(size.height, greaterThanOrEqualTo(44),
            reason: '${(element.widget as FcButton).label} の高さ');
      }
    });

    testWidgets('block は高さ 48・横幅いっぱい、pill は見た目の高さ 43', (tester) async {
      await pumpFc(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcButton.block(label: 'ブロック', onPressed: () {}),
            FcButton.pill(label: 'ピル', onPressed: () {}),
          ],
        ),
      );

      final blockSize = tester.getSize(find.widgetWithText(FcButton, 'ブロック'));
      expect(blockSize.height, 48);
      expect(blockSize.width, 350);

      // pill の面（DecoratedBox）は高さ 43。タッチ領域は 44 まで広げてある
      final pillFace = tester.getSize(
        find
            .descendant(
              of: find.widgetWithText(FcButton, 'ピル'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(pillFace.height, 43);
    });

    testWidgets('block の面は actionFill・角丸 24、無効のときは押せない', (tester) async {
      var pressed = 0;
      await pumpFc(
        tester,
        Column(
          children: [
            FcButton.block(label: '送信', onPressed: () => pressed++),
            const FcButton.block(label: '送信できない', onPressed: null),
          ],
        ),
      );
      final face = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.widgetWithText(FcButton, '送信'),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(face.color, AppColorsExtension.light.actionFill);
      expect(face.borderRadius, BorderRadius.circular(24));

      await tester.tap(find.text('送信'));
      await tester.tap(find.text('送信できない'));
      expect(pressed, 1);
    });

    testWidgets('icon と iconPosition（back は先頭に左矢印）', (tester) async {
      await pumpFc(
        tester,
        Column(
          children: [
            FcButton.back(label: '戻る', onPressed: () {}),
            FcButton.pill(
              label: '追加',
              icon: LucideIcons.plus,
              iconPosition: FcIconPosition.end,
              onPressed: () {},
            ),
          ],
        ),
      );

      final backRow = tester.widget<Row>(
        find.descendant(
          of: find.widgetWithText(FcButton, '戻る'),
          matching: find.byType(Row),
        ),
      );
      expect((backRow.children.first as ExcludeSemantics).child, isA<Icon>());
      expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);

      final pillRow = tester.widget<Row>(
        find.descendant(
          of: find.widgetWithText(FcButton, '追加'),
          matching: find.byType(Row),
        ),
      );
      expect(pillRow.children.last, isA<ExcludeSemantics>());
      expect(pillRow.children.first, isNot(isA<ExcludeSemantics>()));
    });

    testWidgets('文字拡大 1.35 でも折り返して切れない', (tester) async {
      await pumpFc(
        tester,
        FcButton.block(label: '今日の体重をトレーナーに送信する', onPressed: () {}),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(FcButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('FcPressable', () {
    testWidgets('semanticLabel なしでも「ボタン + ラベル + タップ」が 1 ノードにまとまる',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFc(
        tester,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FcButton.pill(label: '記録する', onPressed: () {}),
            FcCard(onTap: () {}, child: const Text('カード本文')),
          ],
        ),
      );

      // 子の Text が持つラベルと、ボタン・タップ・有効が同じノードに載っていること
      for (final text in ['記録する', 'カード本文']) {
        final node = tester.getSemantics(find.text(text));
        final data = node.getSemanticsData();
        expect(data.label, text, reason: '$text: ラベル');
        // ignore: deprecated_member_use
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue,
            reason: '$text: ボタンのフラグが同じノードにある');
        expect(data.hasAction(SemanticsAction.tap), isTrue,
            reason: '$text: タップ操作が同じノードにある');
      }
      handle.dispose();
    });

    testWidgets('押下で scale 0.98、離すと 1.0 に戻る', (tester) async {
      await pumpFc(
        tester,
        FcPressable(
            onTap: () {}, child: const SizedBox(width: 100, height: 60)),
      );
      final scaleFinder = find.descendant(
        of: find.byType(FcPressable),
        matching: find.byType(AnimatedScale),
      );
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FcPressable)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 0.98);
      expect(
        tester.widget<AnimatedScale>(scaleFinder).duration,
        const Duration(milliseconds: 120),
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);
    });

    testWidgets('「動きを減らす」では縮まない', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: c!,
          ),
          home: Scaffold(
            body: Center(
              child: FcPressable(
                onTap: () {},
                child: const SizedBox(width: 100, height: 60),
              ),
            ),
          ),
        ),
      );
      final scaleFinder = find.descendant(
        of: find.byType(FcPressable),
        matching: find.byType(AnimatedScale),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FcPressable)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.0);
      await gesture.up();
    });

    testWidgets('minSize を渡すと見た目が小さくてもタッチ領域が広がる', (tester) async {
      var taps = 0;
      await pumpFc(
        tester,
        FcPressable(
          onTap: () => taps++,
          minSize: const Size.square(44),
          child: const SizedBox(width: 16, height: 16),
        ),
      );
      expect(tester.getSize(find.byType(FcPressable)), const Size(44, 44));
      // 見た目の外側（44×44 の端近く）でも反応する
      final topLeft = tester.getTopLeft(find.byType(FcPressable));
      await tester.tapAt(topLeft + const Offset(2, 2));
      expect(taps, 1);
    });
  });

  group('FcBottomNav', () {
    testWidgets('5 タブが並び、選択中だけ selected になる', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(
            items: _navItems,
            currentIndex: 3,
            onTap: (_) {},
          ),
        ),
        scaffold: false,
      );

      for (final item in _navItems) {
        expect(find.text(item.label), findsOneWidget);
      }
      final selectedLabels = <String>[];
      for (final item in _navItems) {
        final node = tester.getSemantics(find.bySemanticsLabel(item.label));
        // ignore: deprecated_member_use
        if (node.hasFlag(SemanticsFlag.isSelected)) {
          selectedLabels.add(item.label);
        }
      }
      expect(selectedLabels, ['記録']);
      handle.dispose();
    });

    testWidgets('タップで onTap にインデックスが渡る', (tester) async {
      final taps = <int>[];
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(
            items: _navItems,
            currentIndex: 0,
            onTap: taps.add,
          ),
        ),
        scaffold: false,
      );
      await tester.tap(find.text('プラン'));
      await tester.tap(find.text('設定'));
      expect(taps, [2, 4]);
    });

    testWidgets('showDot の点は「数字なし」で、読み上げに新着あり、点だけが出る', (tester) async {
      final handle = tester.ensureSemantics();
      final items = [
        _navItems[0],
        const FcBottomNavItem(
          icon: LucideIcons.messageSquare,
          label: 'メッセージ',
          showDot: true,
        ),
        ..._navItems.skip(2),
      ];
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(items: items, currentIndex: 0, onTap: (_) {}),
        ),
        scaffold: false,
      );

      // 点は小さな円（数字の Text は無い）。ラベル以外の Text が存在しない
      final texts = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(FcBottomNav),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      expect(texts, ['ホーム', 'メッセージ', 'プラン', '記録', '設定']);
      expect(find.bySemanticsLabel('メッセージ（新着あり）'), findsOneWidget);
      expect(find.bySemanticsLabel('ホーム（新着あり）'), findsNothing);

      // 点なしの状態では新着ありの読み上げが出ない
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(items: _navItems, currentIndex: 0, onTap: (_) {}),
        ),
        scaffold: false,
      );
      expect(find.bySemanticsLabel('メッセージ（新着あり）'), findsNothing);
      handle.dispose();
    });

    testWidgets('各操作の高さは 52 以上・幅は 44 以上', (tester) async {
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(items: _navItems, currentIndex: 0, onTap: (_) {}),
        ),
        scaffold: false,
      );
      for (final item in _navItems) {
        final size = tester.getSize(
          find
              .ancestor(
                of: find.text(item.label),
                matching: find.byType(FcPressable),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(52), reason: item.label);
        expect(size.width, greaterThanOrEqualTo(44), reason: item.label);
      }
    });

    testWidgets('通常はぼかし（BackdropFilter）あり、opaque では不透明な surface',
        (tester) async {
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(items: _navItems, currentIndex: 0, onTap: (_) {}),
        ),
        scaffold: false,
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(
            items: _navItems,
            currentIndex: 0,
            onTap: (_) {},
            opaque: true,
          ),
        ),
        scaffold: false,
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('「コントラストを高く」のときは不透明（ぼかしなし）', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(highContrast: true),
            child: c!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FcBottomNav(
                items: _navItems,
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 文字拡大 1.35 でも overflow しない',
          (tester) async {
        await pumpFc(
          tester,
          Align(
            alignment: Alignment.bottomCenter,
            child: FcBottomNav(
              items: [
                _navItems[0],
                const FcBottomNavItem(
                  icon: LucideIcons.messageSquare,
                  label: 'メッセージ',
                  showDot: true,
                ),
                ..._navItems.skip(2),
              ],
              currentIndex: 1,
              onTap: (_) {},
            ),
          ),
          scaffold: false,
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('狭い画面（320 幅）・文字拡大でも overflow しない', (tester) async {
      await pumpFc(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: FcBottomNav(items: _navItems, currentIndex: 0, onTap: (_) {}),
        ),
        scaffold: false,
        size: const Size(320, 568),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcBottomNavLayout（ナビが本文を覆わない仕組み）', () {
    Widget probe(void Function(MediaQueryData) onMedia) => Builder(
          builder: (context) {
            onMedia(MediaQuery.of(context));
            return const SizedBox.expand();
          },
        );

    Future<void> pumpLayout(
      WidgetTester tester, {
      required void Function(MediaQueryData) onMedia,
      double keyboard = 0,
      double safeBottom = 34,
    }) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = FakeViewPadding(bottom: safeBottom * 3);
      tester.view.viewPadding = FakeViewPadding(bottom: safeBottom * 3);
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FcBottomNavLayout(
            body: probe(onMedia),
            bottomNav: FcBottomNav(
              items: _navItems,
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('本文の padding.bottom にナビの高さ + 余白（参照値 121）が入る', (tester) async {
      MediaQueryData? seen;
      await pumpLayout(tester, onMedia: (m) => seen = m);

      expect(seen, isNotNull);
      expect(seen!.padding.bottom, AppSizes.navReservedReference);
      expect(AppSizes.navReservedReference, 93 + 28);
      expect(find.byType(FcBottomNav), findsOneWidget);
    });

    testWidgets('ナビは本文の上に重なり、画面の下端近くに浮く', (tester) async {
      await pumpLayout(tester, onMedia: (_) {});
      final navRect = tester.getRect(find.byType(FcBottomNav));
      expect(navRect.bottom, 844);
      // カプセルの高さ 68 + 下端 25 = 93
      expect(navRect.height, 93);
    });

    testWidgets('キーボード表示中はナビを隠し、余白も足さない', (tester) async {
      MediaQueryData? seen;
      await pumpLayout(
        tester,
        onMedia: (m) => seen = m,
        keyboard: 300,
        safeBottom: 0,
      );
      expect(find.byType(FcBottomNav), findsNothing);
      expect(seen!.padding.bottom, 0);
    });

    testWidgets('viewPadding.bottom にも同じ確保量が入る（浮かせた SnackBar がナビの上に出る）',
        (tester) async {
      MediaQueryData? seen;
      await pumpLayout(tester, onMedia: (m) => seen = m);
      expect(seen!.viewPadding.bottom, AppSizes.navReservedReference);
      expect(seen!.padding.bottom, AppSizes.navReservedReference);
    });

    testWidgets('キーボードの出入りの途中でも確保量は連続的に変わり、入力欄の下端（キーボード + 余白）は跳ねない',
        (tester) async {
      // 入力欄の下端（画面下端から）= キーボード + 本文の下余白（padding.bottom − 余白 28、0 未満は 0）。
      // キーボードがナビの高さ（93）に届くまでは下端はナビの上で動かず、それより上はキーボードに付いてくる
      for (final keyboard in [
        0.0,
        1.0,
        30.0,
        60.0,
        92.0,
        93.0,
        100.0,
        200.0,
        300.0
      ]) {
        MediaQueryData? seen;
        await pumpLayout(
          tester,
          onMedia: (m) => seen = m,
          keyboard: keyboard,
          safeBottom: 0,
        );
        final padding = seen!.padding.bottom;
        final inputBottom =
            keyboard + math.max(0.0, padding - AppSizes.navContentGap);
        expect(
          inputBottom,
          closeTo(math.max(keyboard, 93), 0.01),
          reason: 'キーボード $keyboard のとき',
        );
        // 確保量はキーボードに食われた分だけ減る（出きれば 0）
        expect(
          padding,
          closeTo(math.max(AppSizes.navReservedReference - keyboard, 0), 0.01),
          reason: 'キーボード $keyboard のとき',
        );
      }
    });

    testWidgets('キーボードがナビの高さに届くまでは、ナビを置いたまま操作・読み上げの対象外にし、届いたら外す',
        (tester) async {
      await pumpLayout(
        tester,
        onMedia: (_) {},
        keyboard: 50,
        safeBottom: 0,
      );
      expect(find.byType(FcBottomNav), findsOneWidget);
      final ignore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(FcBottomNav),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(ignore.ignoring, isTrue);
      final exclude = tester.widget<ExcludeSemantics>(
        find
            .ancestor(
              of: find.byType(FcBottomNav),
              matching: find.byType(ExcludeSemantics),
            )
            .first,
      );
      expect(exclude.excluding, isTrue);

      await pumpLayout(
        tester,
        onMedia: (_) {},
        keyboard: 93,
        safeBottom: 0,
      );
      expect(find.byType(FcBottomNav), findsNothing);

      // キーボードが無いときは操作できる
      await pumpLayout(tester, onMedia: (_) {}, keyboard: 0, safeBottom: 0);
      final normal = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(FcBottomNav),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(normal.ignoring, isFalse);
    });

    testWidgets('本文側の SafeArea がナビの上に収まる', (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
      addTearDown(tester.view.reset);

      const bodyKey = Key('body');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: FcBottomNavLayout(
            body: const Scaffold(
              body: SafeArea(child: SizedBox.expand(key: bodyKey)),
            ),
            bottomNav: FcBottomNav(
              items: _navItems,
              currentIndex: 0,
              onTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bodyRect = tester.getRect(find.byKey(bodyKey));
      final navCapsuleTop = tester.getRect(find.byType(FcBottomNav)).bottom -
          AppSizes.navReferenceHeight +
          0; // ナビ全体の上端 = 下端 - 93 + カプセル高さぶん
      expect(
        bodyRect.bottom,
        lessThanOrEqualTo(navCapsuleTop +
            AppSizes.navCapsuleHeight -
            AppSizes.navCapsuleHeight),
        reason: '本文はナビのカプセルより上で終わる',
      );
      expect(bodyRect.bottom, 844 - AppSizes.navReservedReference);
    });
  });

  group('FcSegmentedControl / 旧 SegmentedControl 互換', () {
    testWidgets('タップで onChanged、選択中だけ selected', (tester) async {
      final handle = tester.ensureSemantics();
      String? changed;
      await pumpFc(
        tester,
        FcSegmentedControl<String>(
          items: const [
            FcSegmentedItem(value: 'a', label: '今後'),
            FcSegmentedItem(value: 'b', label: '過去'),
          ],
          selected: 'a',
          onChanged: (v) => changed = v,
        ),
      );
      expect(
        tester.getSize(find.byType(FcSegmentedControl<String>)).height,
        45,
      );
      await tester.tap(find.text('過去'));
      expect(changed, 'b');
      handle.dispose();
    });

    testWidgets('旧名 SegmentedControl / SegmentedControlItem がそのまま動く',
        (tester) async {
      PeriodLike? changed;
      await pumpFc(
        tester,
        SegmentedControl<PeriodLike>(
          items: const [
            SegmentedControlItem(value: PeriodLike.week, label: '週'),
            SegmentedControlItem(value: PeriodLike.month, label: '月'),
          ],
          selected: PeriodLike.week,
          onChanged: (v) => changed = v,
        ),
      );
      await tester.tap(find.text('月'));
      expect(changed, PeriodLike.month);
    });

    testWidgets('文字拡大 1.35 でも overflow しない', (tester) async {
      await pumpFc(
        tester,
        FcSegmentedControl<int>(
          items: const [
            FcSegmentedItem(value: 0, label: '週'),
            FcSegmentedItem(value: 1, label: '月'),
            FcSegmentedItem(value: 2, label: '3ヶ月'),
            FcSegmentedItem(value: 3, label: '全期間'),
          ],
          selected: 1,
          onChanged: (_) {},
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcTextField', () {
    testWidgets('単位は空のときも常に表示される', (tester) async {
      await pumpFc(
        tester,
        SizedBox(
          width: 350,
          child: FcTextField.number(label: '体重', unit: 'kg', hintText: '68.4'),
        ),
      );
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('体重'), findsOneWidget);
    });

    testWidgets('数値入力は数字と小数点だけ受け付ける', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpFc(
        tester,
        SizedBox(
          width: 350,
          child: FcTextField.number(controller: controller, unit: 'kg'),
        ),
      );
      await tester.enterText(find.byType(TextField), '68.4あa');
      expect(controller.text, '68.4');
    });

    testWidgets('高さは 48 以上、複数行は伸びる', (tester) async {
      await pumpFc(
        tester,
        const SizedBox(
          width: 350,
          child: Column(
            children: [
              FcTextField(label: '一行'),
              FcTextField(label: '複数行', minLines: 3, maxLines: 5),
            ],
          ),
        ),
      );
      final single = tester.getSize(find.byType(TextField).first);
      final multi = tester.getSize(find.byType(TextField).last);
      expect(single.height, greaterThanOrEqualTo(48));
      expect(multi.height, greaterThan(single.height));
    });
  });

  group('その他の部品', () {
    testWidgets('FcWeekStrip: 日付をタップすると onSelect に日付が渡る', (tester) async {
      DateTime? selected;
      await pumpFc(
        tester,
        SizedBox(
          width: 350,
          child: FcWeekStrip(
            days: [
              for (var i = 0; i < 7; i++)
                FcWeekDay(
                  date: DateTime(2026, 10, 5).add(Duration(days: i)),
                  mark: i.isEven ? FcDayMark.filled : FcDayMark.hollow,
                  selected: i == 0,
                ),
            ],
            onSelect: (d) => selected = d,
          ),
        ),
      );
      expect(find.text('月'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
      await tester.tap(find.text('8'));
      expect(selected, DateTime(2026, 10, 8));
      // 各日のタッチ領域は高さ 44 以上
      expect(
        tester.getSize(find.byType(FcPressable).first).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('FcToggle: タップで切り替わり、タッチ領域は高さ 44 以上', (tester) async {
      var value = false;
      await pumpFc(
        tester,
        StatefulBuilder(
          builder: (context, setState) => FcToggle(
            value: value,
            onChanged: (v) => setState(() => value = v),
            semanticLabel: '通知',
          ),
        ),
      );
      expect(tester.getSize(find.byType(FcToggle)).height, 44);
      await tester.tap(find.byType(FcToggle));
      await tester.pumpAndSettle();
      expect(value, isTrue);
    });

    testWidgets('FcDoneMark: 完了/未完了で形が違う（チェックの有無）', (tester) async {
      await pumpFc(
        tester,
        const Row(
          children: [
            FcDoneMark(done: true),
            SizedBox(width: 8),
            FcDoneMark(done: false),
          ],
        ),
      );
      // チェックは自前で描く（線 2.2）。完了のときだけ CustomPaint がある
      expect(
        find.descendant(
          of: find.byType(FcDoneMark),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    test('FcAvatar.initialsOf', () {
      expect(FcAvatar.initialsOf('山田 太郎'), '山');
      expect(FcAvatar.initialsOf('John Smith'), 'JS');
      expect(FcAvatar.initialsOf('  '), '?');
      expect(FcAvatar.initialsOf('taro'), 'T');
    });

    testWidgets('FcStateMessage / FcInlineNotice の再試行が押せる', (tester) async {
      var retried = 0;
      await pumpFc(
        tester,
        SizedBox(
          width: 350,
          child: Column(
            children: [
              FcStateMessage.error(
                title: '読み込めませんでした',
                actionLabel: '再試行',
                onAction: () => retried++,
              ),
              FcInlineNotice.warning(
                message: 'オフラインです',
                actionLabel: '再接続',
                onAction: () => retried += 10,
              ),
            ],
          ),
        ),
        size: const Size(390, 1000),
      );
      await tester.tap(find.text('再試行'));
      await tester.tap(find.text('再接続'));
      expect(retried, 11);
    });

    testWidgets('FcNum は単位を常に出し、数値は tabular', (tester) async {
      await pumpFc(tester, const FcNum(value: '68.4', unit: 'kg'));
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.byType(FcNum),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      final valueSpan = spans.firstWhere((s) => s.text == '68.4');
      expect(valueSpan.style!.fontFeatures, isNotEmpty,
          reason: '数値は桁幅を揃える（tabularFigures）');
      expect(valueSpan.style!.fontSize, 32);
      final unitSpan = spans.firstWhere((s) => s.text == 'kg');
      expect(unitSpan.style!.fontSize, 13);
      expect(find.textContaining('kg', findRichText: true), findsOneWidget);
    });
  });

  group('部品ギャラリー（文字拡大・ダーク）', () {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.35]) {
        testWidgets('${brightness.name} / 文字 $scale 倍で overflow しない',
            (tester) async {
          await pumpFc(
            tester,
            const FcPreviewGallery(),
            brightness: brightness,
            textScale: scale,
            scaffold: false,
          );
          // 下までスクロールして、全部品を一度は描画させる
          final list = find.byType(ListView);
          for (var i = 0; i < 12; i++) {
            await tester.drag(list, const Offset(0, -500));
            await tester.pump();
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('下部ナビのプレビュー画面（文字拡大 1.35）が overflow しない', (tester) async {
      await pumpFc(
        tester,
        const FcNavPreview(),
        textScale: 1.35,
        scaffold: false,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

enum PeriodLike { week, month }
