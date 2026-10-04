import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart'
    show FcPreviewApp;
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews_extra.dart';

/// 390 × 844（iPhone 想定）で部品を置いて pump する（`fc_widgets_test.dart` の `pumpFc` と同じ流儀）
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
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
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: c!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppColorsExtension _colors(Brightness brightness) =>
    brightness == Brightness.dark
        ? AppColorsExtension.dark
        : AppColorsExtension.light;

/// ValueKey('fc-bar-N') の棒
Finder _bar(int i) => find.byKey(ValueKey('fc-bar-$i'));

Color _barColor(WidgetTester tester, int i) =>
    ((tester.widget<DecoratedBox>(_bar(i))).decoration as BoxDecoration).color!;

/// グラフ本体の RenderObject
RenderObject _chartRender(WidgetTester tester) => tester.renderObject(
      find.descendant(
        of: find.byType(FcLineChart),
        matching: find.byType(CustomPaint),
      ),
    );

const _weight = [
  FcChartPoint(61.6, label: '9/1'),
  FcChartPoint(61.8),
  FcChartPoint(61.7, label: '9/5'),
  FcChartPoint(62.1),
  FcChartPoint(62.2, label: '9/9'),
  FcChartPoint(62.3),
  FcChartPoint(62.4, label: '9/13'),
];

const _stages = [
  FcSleepStage(label: '深い', minutes: 85, percent: 100),
  FcSleepStage(label: 'レム', minutes: 110, percent: 60),
  FcSleepStage(label: '浅い', minutes: 255, percent: 30),
  FcSleepStage(label: '覚醒', minutes: 20, percent: 0),
];

void main() {
  group('FcListRow', () {
    testWidgets('アイコン・タイトル・補足が出て、onTap があるときだけ chevron が出る', (tester) async {
      await _pump(
        tester,
        FcListRow(
          icon: LucideIcons.utensils,
          title: '食事',
          caption: '朝食・昼食を記録',
          onTap: () {},
        ),
      );
      expect(find.text('食事'), findsOneWidget);
      expect(find.text('朝食・昼食を記録'), findsOneWidget);
      expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);

      await _pump(tester, const FcListRow(title: '食事'));
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

      await _pump(
        tester,
        FcListRow(title: 'ログアウト', chevron: false, onTap: () {}),
      );
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

      await _pump(
        tester,
        const FcListRow(title: 'ログアウト', chevron: true),
      );
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });

    testWidgets('外部リンクは external-link アイコンで chevron は出ない', (tester) async {
      await _pump(
        tester,
        FcListRow(title: '利用規約', externalLink: true, onTap: () {}),
      );
      expect(find.byIcon(LucideIcons.externalLink), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
    });

    testWidgets('アイコン 18 / 末尾アイコン 16 / タイトル 16・行高 1.5 / 補足 12', (tester) async {
      await _pump(
        tester,
        FcListRow(
          icon: LucideIcons.scale,
          title: '体重',
          caption: '前回から +0.1 kg',
          onTap: () {},
        ),
      );
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.scale)).size, 18);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.chevronRight)).size,
        16,
      );
      final colors = AppColorsExtension.light;
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.scale)).color,
        colors.accent,
      );
      final title = tester.widget<Text>(find.text('体重')).style!;
      expect(title.fontSize, 16);
      expect(title.height, 1.5);
      expect(
          tester.widget<Text>(find.text('前回から +0.1 kg')).style!.fontSize, 12);
    });

    testWidgets('density: 最小高さ 標準54 / まとめ56 / 記録52', (tester) async {
      for (final entry in {
        FcRowDensity.standard: 54.0,
        FcRowDensity.summary: 56.0,
        FcRowDensity.record: 52.0,
      }.entries) {
        await _pump(
          tester,
          FcListRow(title: '行', density: entry.key),
        );
        expect(
          tester.getSize(find.byType(FcListRow)).height,
          entry.value,
          reason: entry.key.name,
        );
      }
      expect(FcRowDensity.standard.verticalPadding, 10);
      expect(FcRowDensity.summary.verticalPadding, 13);
      expect(FcRowDensity.record.verticalPadding, 12);
    });

    testWidgets('タップできる行はタッチ領域 44 以上・押下で scale 0.98', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        FcListRow(title: '行', onTap: () => taps++),
      );
      final size = tester.getSize(find.byType(FcListRow));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, 350);

      await tester.tap(find.text('行'));
      expect(taps, 1);

      final scale = find.descendant(
        of: find.byType(FcListRow),
        matching: find.byType(AnimatedScale),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FcListRow)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.widget<AnimatedScale>(scale).scale, 0.98);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('読み上げはタイトル・補足・値を 1 つにまとめる（行を押せるとき・押せないとき）', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FcListRow(
          icon: LucideIcons.utensils,
          title: '食事',
          caption: '朝食・昼食を記録',
          trailing: const FcRowValue.metric([FcValuePart('2', '回')]),
          onTap: () {},
        ),
      );
      var node = tester.getSemantics(find.byType(FcListRow));
      expect(node.label, contains('食事'));
      expect(node.label, contains('朝食・昼食を記録'));
      expect(node.label, contains('2回'));
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);

      await _pump(
        tester,
        const FcListRow(
          title: '9月13日（日）7:30',
          caption: 'メッセージから',
          trailing: FcRowValue.text('62.4 kg'),
        ),
      );
      node = tester.getSemantics(find.byType(FcListRow));
      expect(node.label, contains('9月13日（日）7:30'));
      expect(node.label, contains('メッセージから'));
      expect(node.label, contains('62.4 kg'));
      handle.dispose();
    });

    testWidgets('semanticLabel で読み上げを上書きできる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FcListRow(
          title: '体重',
          trailing: const FcRowValue.text('62.4 kg'),
          semanticLabel: '体重 62.4 キログラム',
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('体重 62.4 キログラム'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('color でタイトルとアイコンが同じ色になる', (tester) async {
      final colors = AppColorsExtension.light;
      await _pump(
        tester,
        FcListRow(
          icon: LucideIcons.logOut,
          title: 'アカウントを削除',
          color: colors.error,
        ),
      );
      expect(tester.widget<Text>(find.text('アカウントを削除')).style!.color,
          colors.error);
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.logOut)).color,
        colors.error,
      );
    });

    testWidgets('leading を渡すとアイコンの代わりに置かれる', (tester) async {
      await _pump(
        tester,
        const FcListRow(
          icon: LucideIcons.scale,
          leading: FcDoneMark(done: true, size: 22),
          title: '最初の体重を記録する',
        ),
      );
      expect(find.byType(FcDoneMark), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsNothing);
    });

    group('FcRowValue', () {
      testWidgets('metric: 数値 20 / 500 ＋ 単位 13 が並ぶ（複数の組も）', (tester) async {
        await _pump(
          tester,
          const FcListRow(
            title: '睡眠',
            trailing: FcRowValue.metric(
              [FcValuePart('7', '時間'), FcValuePart('30', '分')],
            ),
          ),
        );
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText(includePlaceholders: false) == '7時間30分',
          ),
        );
        final spans = <TextSpan>[];
        rich.text.visitChildren((s) {
          if (s is TextSpan && s.text != null) spans.add(s);
          return true;
        });
        // 先頭の span が数値（20 / 500 / 字間 -0.4 / tabular）、次が単位（13）
        final value = spans.firstWhere((s) => s.text == '7');
        expect(value.style!.fontSize, 20);
        expect(value.style!.fontWeight, FontWeight.w500);
        expect(value.style!.letterSpacing, -0.4);
        expect(value.style!.fontFeatures, AppTextStyles.tabularFigures);
        final unit = spans.firstWhere((s) => s.text == '時間');
        expect(unit.style!.fontSize, 13);
        expect(unit.style!.color, AppColorsExtension.light.textSecondary);
      });

      testWidgets('missing は「未記録」（textSecondary）、action は accent の文字',
          (tester) async {
        final colors = AppColorsExtension.light;
        await _pump(
          tester,
          const Column(
            children: [
              FcListRow(title: '体重', trailing: FcRowValue.missing()),
              FcListRow(title: '睡眠', trailing: FcRowValue.action('目覚めを記録')),
            ],
          ),
        );
        expect(
          tester.widget<Text>(find.text('未記録')).style!.color,
          colors.textSecondary,
        );
        final action = tester.widget<Text>(find.text('目覚めを記録')).style!;
        expect(action.color, colors.accent);
        expect(action.fontWeight, FontWeight.w500);
        expect(action.fontSize, 15);
      });

      testWidgets('text は 16 / 500、muted は textSecondary', (tester) async {
        final colors = AppColorsExtension.light;
        await _pump(
          tester,
          const Column(
            children: [
              FcListRow(title: 'a', trailing: FcRowValue.text('62.4 kg')),
              FcListRow(
                title: 'b',
                trailing: FcRowValue.text('未取得', muted: true),
              ),
            ],
          ),
        );
        final normal = tester.widget<Text>(find.text('62.4 kg')).style!;
        expect(normal.fontSize, 16);
        expect(normal.fontWeight, FontWeight.w500);
        expect(normal.color, colors.textPrimary);
        expect(
          tester.widget<Text>(find.text('未取得')).style!.color,
          colors.textSecondary,
        );
      });

      testWidgets('loading はスケルトン（64×18）で、値の文字は出ない', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          const FcListRow(title: '食事', trailing: FcRowValue.loading()),
        );
        expect(find.byType(FcSkeleton), findsOneWidget);
        expect(tester.getSize(find.byType(FcSkeleton)), const Size(64, 18));
        expect(find.text('未記録'), findsNothing);
        expect(
          tester.getSemantics(find.byType(FcListRow)).label,
          contains('読み込み中'),
        );
        handle.dispose();
      });
    });

    group('FcListRow.toggle', () {
      testWidgets('行のどこを押しても・スイッチを押しても 1 回だけ切り替わる', (tester) async {
        final changes = <bool>[];
        await _pump(
          tester,
          FcListRow.toggle(
            title: '目標の達成',
            value: false,
            onChanged: changes.add,
          ),
        );
        expect(find.byType(FcToggle), findsOneWidget);
        expect(find.byIcon(LucideIcons.chevronRight), findsNothing);

        await tester.tap(find.text('目標の達成'));
        expect(changes, [true]);
        await tester.tap(find.byType(CupertinoSwitch));
        expect(changes, [true, true]);
      });

      testWidgets('読み上げ: タイトル・補足・切り替え状態。無効なら押せない', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          FcListRow.toggle(
            title: 'セッションのリマインド',
            caption: '前日と当日の朝にお知らせ',
            value: true,
            onChanged: (_) {},
          ),
        );
        var data =
            tester.getSemantics(find.byType(FcListRow)).getSemanticsData();
        expect(data.label, contains('セッションのリマインド'));
        expect(data.label, contains('前日と当日の朝にお知らせ'));
        expect(data.flagsCollection.isToggled, Tristate.isTrue);

        await _pump(
          tester,
          const FcListRow.toggle(title: '通知', value: false, onChanged: null),
        );
        data = tester.getSemantics(find.byType(FcListRow)).getSemanticsData();
        expect(data.flagsCollection.isToggled, Tristate.isFalse);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        handle.dispose();
      });
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 文字拡大 1.35 でも overflow せず折り返して伸びる',
          (tester) async {
        await _pump(
          tester,
          Column(
            children: [
              FcListRow(
                density: FcRowDensity.summary,
                icon: LucideIcons.moon,
                title: '睡眠',
                caption: 'ヘルスケアと連携すると自動で入ります',
                trailing: const FcRowValue.metric(
                  [FcValuePart('7', '時間'), FcValuePart('30', '分')],
                ),
                onTap: () {},
              ),
              FcListRow(
                icon: LucideIcons.heartPulse,
                title: 'HealthKit と連携してトレーナーに共有する',
                caption: '連携中 · 睡眠 · 最終同期 9月13日（日）7:32',
                onTap: () {},
              ),
              const FcListRow.toggle(
                title: 'トレーナーからのメッセージ',
                caption: '前日と当日の朝にお知らせ',
                value: true,
                onChanged: null,
              ),
            ],
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byType(FcListRow).first).height,
          greaterThan(56),
        );
      });
    }

    testWidgets('狭い画面（320 幅）・文字拡大でも overflow しない', (tester) async {
      await _pump(
        tester,
        Column(
          children: [
            FcListRow(
              icon: LucideIcons.utensils,
              title: '食事',
              caption: 'メッセージから記録できます',
              trailing: const FcRowValue.text('1,987 kcal / 1日平均'),
              onTap: () {},
            ),
          ],
        ),
        size: const Size(320, 568),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcRowsCard', () {
    Widget rows(int count, {String? title, EdgeInsetsGeometry? padding}) =>
        FcRowsCard(
          title: title,
          padding: padding ?? FcRowsCard.defaultPadding,
          children: [
            for (var i = 0; i < count; i++) FcListRow(title: '行${i + 1}'),
          ],
        );

    Finder separators() => find.descendant(
          of: find.byType(FcRowsCard),
          matching: find.byType(FcSeparator),
        );

    testWidgets('区切り線は行の間だけ（n 行なら n-1 本・先頭の上と最後の下には無い）', (tester) async {
      await _pump(tester, rows(4));
      expect(separators(), findsNWidgets(3));

      final rowRects = [
        for (var i = 1; i <= 4; i++) tester.getRect(find.text('行$i')),
      ];
      final sepRects = [
        for (var i = 0; i < 3; i++) tester.getRect(separators().at(i)),
      ];
      // 先頭の行より上に線は無く、最後の行より下にも線は無い
      expect(sepRects.every((r) => r.top > rowRects.first.bottom), isTrue);
      expect(sepRects.every((r) => r.bottom < rowRects.last.top), isTrue);

      await _pump(tester, rows(1));
      expect(separators(), findsNothing);
      await _pump(tester, rows(0));
      expect(separators(), findsNothing);
    });

    testWidgets('見出しと最初の行の間には線を引かない', (tester) async {
      await _pump(tester, rows(2, title: '今日のまとめ'));
      expect(find.text('今日のまとめ'), findsOneWidget);
      expect(separators(), findsNWidgets(1));
      final sep = tester.getRect(separators());
      expect(sep.top, greaterThan(tester.getRect(find.text('行1')).bottom));
    });

    testWidgets('header を渡すと title より優先される', (tester) async {
      await _pump(
        tester,
        FcRowsCard(
          title: '使われない',
          header: const Text('はじめの3ステップ'),
          children: const [FcListRow(title: '行1')],
        ),
      );
      expect(find.text('はじめの3ステップ'), findsOneWidget);
      expect(find.text('使われない'), findsNothing);
    });

    testWidgets('余白: 既定は上下2・左右20、summaryPadding は上16・下4・左右20', (tester) async {
      await _pump(tester, rows(1));
      expect(
        tester.widget<FcCard>(find.byType(FcCard)).paddingOverride,
        const EdgeInsets.symmetric(vertical: 2, horizontal: 20),
      );
      // 1 行（標準 54）＋上下 2 = 58
      expect(tester.getSize(find.byType(FcCard)).height, 58);

      await _pump(
        tester,
        rows(1, padding: FcRowsCard.summaryPadding),
      );
      expect(
        tester.widget<FcCard>(find.byType(FcCard)).paddingOverride,
        const EdgeInsets.fromLTRB(20, 16, 20, 4),
      );
      expect(tester.getSize(find.byType(FcCard)).height, 54 + 16 + 4);
    });

    testWidgets('headerEndBleed: 見出しの右端だけカードの右余白へ食い込み、行と線の右端は変わらない',
        (tester) async {
      await _pump(
        tester,
        FcRowsCard(
          header: Row(
            children: [
              const Expanded(child: Text('はじめの3ステップ')),
              FcCloseButton(onPressed: () {}),
            ],
          ),
          headerEndBleed: FcCloseButton.endBleed,
          children: const [
            FcListRow(title: '行1'),
            FcListRow(title: '行2'),
          ],
        ),
      );
      final card = tester.getRect(find.byType(FcCard));
      // 行・線の右端は従来どおり（カード右端から 20）
      expect(tester.getRect(find.byType(FcSeparator)).right, card.right - 20);
      // 「×」の箱はカード右端から 20 - 12 = 8 まで届く（押せる範囲 44×44 は欠けない）
      final close = tester.getRect(find.byType(FcCloseButton));
      expect(close.right, card.right - 8);
      expect(close.size, const Size(44, 44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('角丸 23・不透明（FcCard）で横幅いっぱい', (tester) async {
      await _pump(tester, rows(2));
      final decoration = tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(FcCard),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(23));
      expect(decoration.color!.a, 1.0);
      expect(tester.getSize(find.byType(FcCard)).width, 350);
    });

    testWidgets('文字拡大 1.35 でも overflow しない', (tester) async {
      await _pump(
        tester,
        FcRowsCard(
          title: '今日のまとめ',
          padding: FcRowsCard.summaryPadding,
          children: [
            FcListRow(
              density: FcRowDensity.summary,
              icon: LucideIcons.utensils,
              title: '食事',
              caption: '朝食・昼食を記録',
              trailing: const FcRowValue.metric([FcValuePart('2', '回')]),
              onTap: () {},
            ),
            FcListRow(
              density: FcRowDensity.summary,
              icon: LucideIcons.moon,
              title: '睡眠',
              trailing: const FcRowValue.metric(
                [FcValuePart('7', '時間'), FcValuePart('30', '分')],
              ),
              onTap: () {},
            ),
          ],
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcStatList', () {
    const items = [
      FcStatItem(
        icon: LucideIcons.dumbbell,
        label: '筋トレ',
        description: '9/7〜9/13の運動記録',
        value: '2回',
      ),
      FcStatItem(label: '有酸素', value: '1回'),
      FcStatItem(label: '消費カロリー', value: null),
    ];

    testWidgets('区切り線は項目の間だけ（最後の行は線なし）', (tester) async {
      await _pump(tester, const FcStatList(items: items));
      final sepFinder = find.descendant(
        of: find.byType(FcStatList),
        matching: find.byType(FcSeparator),
      );
      expect(sepFinder, findsNWidgets(2));

      final lastSep = tester.getRect(sepFinder.last);
      final lastLabel = tester.getRect(find.text('消費カロリー'));
      final listRect = tester.getRect(find.byType(FcStatList));
      expect(lastSep.bottom, lessThanOrEqualTo(lastLabel.top));
      // 最後の行の下は余白 14 で終わる（線が無い）
      expect(listRect.bottom - lastLabel.bottom, lessThan(14 + 12));
      expect(listRect.top, tester.getRect(find.text('筋トレ')).top - 14);
    });

    testWidgets('行: 縦余白 14・アイコン 17 accent・ラベル 16・説明 12・値 17 / 500',
        (tester) async {
      final colors = AppColorsExtension.light;
      await _pump(tester, const FcStatList(items: items));

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.dumbbell));
      expect(icon.size, 17);
      expect(icon.color, colors.accent);

      expect(tester.widget<Text>(find.text('筋トレ')).style!.fontSize, 16);
      expect(
        tester.widget<Text>(find.text('9/7〜9/13の運動記録')).style!.fontSize,
        12,
      );
      final value = tester.widget<Text>(find.text('2回')).style!;
      expect(value.fontSize, 17);
      expect(value.fontWeight, FontWeight.w500);
      expect(value.fontFeatures, AppTextStyles.tabularFigures);
      expect(value.color, colors.textPrimary);

      // 説明は上 3 の間隔で、ラベルの下に出る
      final label = tester.getRect(find.text('筋トレ'));
      final description = tester.getRect(find.text('9/7〜9/13の運動記録'));
      expect(description.top - label.bottom, 3);
    });

    testWidgets('値が null なら「未記録」（textSecondary）。0 とは区別される', (tester) async {
      await _pump(
        tester,
        const FcStatList(
          items: [
            FcStatItem(label: '消費カロリー', value: null),
            FcStatItem(label: '合計', value: '0回'),
          ],
        ),
      );
      expect(
        tester.widget<Text>(find.text('未記録')).style!.color,
        AppColorsExtension.light.textSecondary,
      );
      expect(find.text('0回'), findsOneWidget);
    });

    testWidgets('読み上げは項目ごとに 1 つ（ラベル・説明・値）', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const FcStatList(items: items));
      final node = tester.getSemantics(find.text('筋トレ'));
      expect(node.label, contains('筋トレ'));
      expect(node.label, contains('9/7〜9/13の運動記録'));
      expect(node.label, contains('2回'));
      handle.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 文字拡大 1.35 でも overflow しない',
          (tester) async {
        await _pump(
          tester,
          const FcStatList(
            items: [
              FcStatItem(
                icon: LucideIcons.dumbbell,
                label: 'たんぱく質（1日平均）',
                description: '記録した10日の平均',
                value: '95 g',
              ),
              FcStatItem(label: '消費カロリー（入力があった 2 件の合計）', value: '600 kcal'),
            ],
          ),
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FcInfoBox', () {
    testWidgets('surfaceSecondary・角丸 12・余白 縦 10 × 横 14・横幅いっぱい', (tester) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          const FcInfoBox(child: Text('推定')),
          brightness: brightness,
        );
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(FcInfoBox),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.color, _colors(brightness).surfaceSecondary);
        expect(decoration.borderRadius, BorderRadius.circular(12));
        expect(tester.getSize(find.byType(FcInfoBox)).width, 350);
        // 文字 1 行（13px ではなく本文 16 × 1.5 = 24）＋上下 10
        final text = tester.getSize(find.text('推定'));
        expect(
          tester.getSize(find.byType(FcInfoBox)).height,
          text.height + 20,
        );
        expect(
          tester.getTopLeft(find.text('推定')).dx -
              tester.getTopLeft(find.byType(FcInfoBox)).dx,
          14,
        );
      }
    });

    testWidgets('expand: false なら内容の幅', (tester) async {
      await _pump(
        tester,
        const FcInfoBox(expand: false, child: Text('推定')),
      );
      expect(tester.getSize(find.byType(FcInfoBox)).width, lessThan(100));
    });

    testWidgets('文字拡大 1.35 でも overflow しない', (tester) async {
      await _pump(
        tester,
        const FcInfoBox(
          child: Text('たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g と、長めの補足の文章です。'),
        ),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcIconButton', () {
    testWidgets(
        '44×44 の丸。既定は surface ＋ textSecondary、primary は actionFill ＋ onAction',
        (tester) async {
      for (final brightness in Brightness.values) {
        final colors = _colors(brightness);
        await _pump(
          tester,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FcIconButton(
                icon: LucideIcons.camera,
                semanticLabel: '写真を添付',
                onPressed: () {},
              ),
              FcIconButton(
                icon: LucideIcons.arrowUp,
                semanticLabel: '送信',
                primary: true,
                onPressed: () {},
              ),
            ],
          ),
          brightness: brightness,
        );
        expect(
          tester.getSize(find.byType(FcIconButton).first),
          const Size(44, 44),
        );
        expect(
          tester.getSize(find.byType(FcIconButton).last),
          const Size(44, 44),
        );

        BoxDecoration face(Finder f) => tester
            .widget<Container>(
              find.descendant(of: f, matching: find.byType(Container)),
            )
            .decoration! as BoxDecoration;
        final normal = face(find.byType(FcIconButton).first);
        final primary = face(find.byType(FcIconButton).last);
        expect(normal.shape, BoxShape.circle);
        expect(normal.color, colors.surface);
        expect(primary.color, colors.actionFill);

        expect(
          tester.widget<Icon>(find.byIcon(LucideIcons.camera)).color,
          colors.textSecondary,
        );
        expect(
          tester.widget<Icon>(find.byIcon(LucideIcons.arrowUp)).color,
          colors.onAction,
        );
        expect(tester.widget<Icon>(find.byIcon(LucideIcons.camera)).size, 20);
      }
    });

    testWidgets('iconColor でアイコン色を変えられる（同期ボタンは accent）', (tester) async {
      final colors = AppColorsExtension.light;
      await _pump(
        tester,
        FcIconButton(
          icon: LucideIcons.refreshCw,
          semanticLabel: '睡眠を同期',
          iconColor: colors.accent,
          onPressed: () {},
        ),
      );
      expect(
        tester.widget<Icon>(find.byIcon(LucideIcons.refreshCw)).color,
        colors.accent,
      );
    });

    testWidgets('無効は不透明度 0.4 で押せない。有効は押せる', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FcIconButton(
              icon: LucideIcons.arrowUp,
              semanticLabel: '送信',
              primary: true,
              onPressed: () => taps++,
            ),
            const FcIconButton(
              icon: LucideIcons.arrowUp,
              semanticLabel: '送信できない',
              primary: true,
              onPressed: null,
            ),
          ],
        ),
      );
      double opacityOf(Finder f) => tester
          .widget<Opacity>(
            find.descendant(of: f, matching: find.byType(Opacity)),
          )
          .opacity;
      expect(opacityOf(find.byType(FcIconButton).first), 1.0);
      expect(opacityOf(find.byType(FcIconButton).last), 0.4);

      await tester.tap(find.byType(FcIconButton).first);
      await tester.tap(find.byType(FcIconButton).last);
      expect(taps, 1);
    });

    testWidgets('semanticLabel で読み上げられ、ボタンとして扱われる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FcIconButton(
          icon: LucideIcons.camera,
          semanticLabel: '写真を添付',
          onPressed: () {},
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('写真を添付'));
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('FcCloseButton', () {
    testWidgets('44×44・× アイコン 18・textSecondary、押せる', (tester) async {
      var taps = 0;
      await _pump(tester, FcCloseButton(onPressed: () => taps++));
      expect(tester.getSize(find.byType(FcCloseButton)), const Size(44, 44));
      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.x));
      expect(icon.size, 18);
      expect(icon.color, AppColorsExtension.light.textSecondary);
      await tester.tap(find.byType(FcCloseButton));
      expect(taps, 1);
    });

    testWidgets('読み上げは既定「閉じる」、渡せば上書き', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FcCloseButton(onPressed: () {}),
            FcCloseButton(onPressed: () {}, semanticLabel: '返信をやめる'),
          ],
        ),
      );
      expect(find.bySemanticsLabel('閉じる'), findsOneWidget);
      expect(find.bySemanticsLabel('返信をやめる'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('正本の負マージンは配置側で余白を減らして再現できる（見出し行の高さが保たれる）', (tester) async {
      await _pump(
        tester,
        FcCard(
          paddingOverride: EdgeInsets.fromLTRB(
            18,
            18 - FcCloseButton.verticalBleed,
            18 - FcCloseButton.endBleed,
            18,
          ),
          child: Row(
            children: [
              const Expanded(child: Text('食事を記録')),
              FcCloseButton(onPressed: () {}),
            ],
          ),
        ),
      );
      expect(FcCloseButton.endBleed, 12);
      expect(FcCloseButton.verticalBleed, 10);
      // × の中心は、カード右端から 6 + 22 = 28（正本: 18 - 12 + 22）
      final card = tester.getRect(find.byType(FcCard));
      final close = tester.getRect(find.byType(FcCloseButton));
      expect(card.right - close.center.dx, 28);
      expect(close.size, const Size(44, 44));
    });
  });

  group('FcPhotoPlaceholder', () {
    testWidgets('surfaceSecondary・image アイコン 22・既定は高さ 160・角丸 16',
        (tester) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          const FcPhotoPlaceholder(label: '食事の写真'),
          brightness: brightness,
        );
        final decoration = tester
            .widget<DecoratedBox>(
              find.descendant(
                of: find.byType(FcPhotoPlaceholder),
                matching: find.byType(DecoratedBox),
              ),
            )
            .decoration as BoxDecoration;
        expect(decoration.color, _colors(brightness).surfaceSecondary);
        expect(decoration.borderRadius, BorderRadius.circular(16));
        expect(tester.getSize(find.byType(FcPhotoPlaceholder)).height, 160);
        expect(tester.getSize(find.byType(FcPhotoPlaceholder)).width, 350);
        final icon = tester.widget<Icon>(find.byIcon(LucideIcons.image));
        expect(icon.size, 22);
        expect(icon.color, _colors(brightness).textSecondary);
      }
    });

    testWidgets('高さ 100 以上ならラベルも出す。未満はアイコンだけ', (tester) async {
      await _pump(
        tester,
        const FcPhotoPlaceholder(height: 100, label: 'フォームの写真'),
      );
      expect(find.text('フォームの写真'), findsOneWidget);

      await _pump(
        tester,
        const FcPhotoPlaceholder(width: 72, height: 72, radius: 14),
      );
      expect(find.text('写真'), findsNothing);
      expect(find.byIcon(LucideIcons.image), findsOneWidget);
      expect(
        tester.getSize(find.byType(FcPhotoPlaceholder)),
        const Size(72, 72),
      );
    });

    testWidgets('画像として読み上げられる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const FcPhotoPlaceholder(label: '食事の写真'),
      );
      expect(find.bySemanticsLabel('食事の写真'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('文字拡大 1.35・最小の高さ 100 でも overflow しない', (tester) async {
      await _pump(
        tester,
        const FcPhotoPlaceholder(height: 100, label: 'フォームの写真（拡大して確認できます）'),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FcLineChart', () {
    Widget chart({
      List<FcChartPoint> data = _weight,
      double? goal = 65,
      double? min = 61,
      double? max = 65.4,
      double height = 150,
    }) =>
        FcLineChart(
          data: data,
          goal: goal,
          goalLabel: goal == null ? null : '目標 65.0 kg',
          min: min,
          max: max,
          height: height,
          semanticLabel: '9月の体重の推移',
        );

    testWidgets('幅いっぱい・高さ指定で描画され、読み上げは semanticLabel', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, chart());
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(FcLineChart)), const Size(350, 150));
      expect(find.bySemanticsLabel('9月の体重の推移'), findsOneWidget);
      handle.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 横線 3 本・目標線・折れ線・点（最後だけ半径 4 の塗り）を描く',
          (tester) async {
        final colors = _colors(brightness);
        await _pump(tester, chart(), brightness: brightness);
        // 呼び出しは順番に一致する必要がある: 横線 3 → 目標線 → 折れ線 → 点 7 つ（塗り → 枠）
        final pattern = paints
          ..line(color: colors.separator, strokeWidth: 1)
          ..line(color: colors.separator, strokeWidth: 1)
          ..line(color: colors.separator, strokeWidth: 1)
          ..path(color: colors.textSecondary, strokeWidth: 1)
          ..path(color: colors.accent, strokeWidth: 2);
        for (var i = 0; i < _weight.length; i++) {
          final last = i == _weight.length - 1;
          final radius = last ? 4.0 : 2.5;
          pattern
            ..circle(
              color: last ? colors.accent : colors.surface,
              radius: radius,
              style: PaintingStyle.fill,
            )
            ..circle(
              color: colors.accent,
              radius: radius,
              strokeWidth: 1.5,
              style: PaintingStyle.stroke,
            );
        }
        expect(_chartRender(tester), pattern);
      });
    }

    testWidgets('座標: 点の x は 8〜342、最後の点の y は 91、横線は 16 / 71 / 126',
        (tester) async {
      await _pump(tester, chart());
      final render = _chartRender(tester);

      bool near(double a, double b) => (a - b).abs() < 0.01;

      expect(
        render,
        paints
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 16))
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 71))
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 126))
          // 最初の点（x=8, 値 61.6 → y = 16 + (65.4-61.6)/4.4*110 = 111）
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawCircle &&
              near((a[0] as Offset).dx, 8) &&
              near((a[0] as Offset).dy, 111))
          // 最後の点（x=342, 値 62.4 → y = 91）で半径 4
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawCircle &&
              near((a[0] as Offset).dx, 342) &&
              near((a[0] as Offset).dy, 91) &&
              a[1] == 4.0),
      );
    });

    testWidgets('x ラベルが無いときは下の余白 6（横線は 16 / 80 / 144）', (tester) async {
      await _pump(
        tester,
        chart(
          data: const [
            FcChartPoint(61.6),
            FcChartPoint(62.0),
            FcChartPoint(62.4),
          ],
        ),
      );
      bool near(double a, double b) => (a - b).abs() < 0.01;
      expect(
        _chartRender(tester),
        paints
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 16))
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 80))
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawLine && near((a[0] as Offset).dy, 144)),
      );
    });

    testWidgets('データが 1 件のときは中央に点（最後の点 = 塗り）', (tester) async {
      await _pump(
        tester,
        chart(
          data: const [FcChartPoint(62.4, label: '9/13')],
          goal: null,
          min: null,
          max: null,
        ),
      );
      expect(tester.takeException(), isNull);
      bool near(double a, double b) => (a - b).abs() < 0.01;
      expect(
        _chartRender(tester),
        paints
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawCircle &&
              near((a[0] as Offset).dx, 175) &&
              a[1] == 4.0),
      );
    });

    testWidgets('データ無し・値がすべて同じ・min/max 省略・min >= max でも例外なく描ける',
        (tester) async {
      for (final c in [
        chart(data: const [], goal: null, min: null, max: null),
        chart(
          data: const [FcChartPoint(60), FcChartPoint(60), FcChartPoint(60)],
          goal: null,
          min: null,
          max: null,
        ),
        chart(min: null, max: null),
        chart(min: 65, max: 61),
        chart(
          data: const [FcChartPoint(80, label: '範囲外'), FcChartPoint(0)],
        ),
      ]) {
        await _pump(tester, c);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('データが変わると描き直される', (tester) async {
      await _pump(tester, chart());
      await _pump(
        tester,
        chart(
          data: const [
            FcChartPoint(61.6, label: '9/1'),
            FcChartPoint(63.4, label: '9/13'),
          ],
        ),
      );
      bool near(double a, double b) => (a - b).abs() < 0.01;
      // 最後の点 63.4 → y = 16 + (65.4-63.4)/4.4*110 = 66
      expect(
        _chartRender(tester),
        paints
          ..something((Symbol n, List<dynamic> a) =>
              n == #drawCircle &&
              near((a[0] as Offset).dx, 342) &&
              near((a[0] as Offset).dy, 66)),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 文字拡大 1.35・狭い幅でも例外なく描ける（ラベルは 11px 固定）',
          (tester) async {
        await _pump(
          tester,
          chart(),
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(FcLineChart)).height, 150);
      });
    }
  });

  group('FcBars', () {
    List<FcBarItem> week() => [
          const FcBarItem(value: 410, text: '6:50', label: '月'),
          const FcBarItem(value: 430, text: '7:10', label: '火'),
          const FcBarItem(value: null, label: '水'),
          const FcBarItem(value: 390, text: '6:30', label: '木'),
          const FcBarItem(value: 420, text: '7:00', label: '金'),
          const FcBarItem(value: 410, text: '6:50', label: '土'),
          const FcBarItem(
            value: 450,
            text: '7:30',
            highlighted: true,
            label: '日',
          ),
        ];

    testWidgets('列は等幅で、棒は幅いっぱい（最大 28）。高さは max に対する割合', (tester) async {
      await _pump(tester, FcBars(items: week(), max: 540, height: 96));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 7; i++) {
        expect(_bar(i), findsOneWidget);
      }
      // 7 列・間隔 8 → 列幅 (350 - 48) / 7 = 43.14 → 棒は 28
      expect(tester.getSize(_bar(0)).width, 28);
      expect(tester.getSize(_bar(0)).height, closeTo(410 / 540 * 96, 0.01));
      expect(tester.getSize(_bar(6)).height, closeTo(450 / 540 * 96, 0.01));
      // 列の中心が等間隔
      final centers = [
        for (var i = 0; i < 7; i++) tester.getCenter(_bar(i)).dx
      ];
      final step = centers[1] - centers[0];
      for (var i = 1; i < 7; i++) {
        expect(centers[i] - centers[i - 1], closeTo(step, 0.01));
      }
    });

    testWidgets('13 列・間隔 4 では棒は列幅に縮む（28 未満）', (tester) async {
      await _pump(
        tester,
        FcBars(
          showValues: false,
          gap: 4,
          height: 84,
          max: 2400,
          items: [
            for (var i = 0; i < 13; i++)
              FcBarItem(value: 1900.0, text: '1,900', highlighted: i == 12),
          ],
        ),
      );
      expect(tester.getSize(_bar(0)).width, closeTo((350 - 48) / 13, 0.01));
    });

    for (final brightness in Brightness.values) {
      testWidgets(
          '${brightness.name}: ハイライト = accent、それ以外 = textSecondary の 28%、未取得 = separator',
          (tester) async {
        final colors = _colors(brightness);
        await _pump(
          tester,
          FcBars(items: week(), max: 540, height: 96),
          brightness: brightness,
        );
        expect(_barColor(tester, 6), colors.accent);
        expect(
          _barColor(tester, 0),
          colors.textSecondary.withValues(alpha: 0.28),
        );
        expect(_barColor(tester, 2), colors.separator);
      });
    }

    testWidgets('値が null の列は高さ 2 の線。showValues のとき「未取得」を出す', (tester) async {
      await _pump(tester, FcBars(items: week(), max: 540, height: 96));
      expect(tester.getSize(_bar(2)).height, 2);
      expect(find.text('未取得'), findsOneWidget);
      // 値の文字は 11px、ハイライトは accent
      final colors = AppColorsExtension.light;
      expect(tester.widget<Text>(find.text('7:30')).style!.fontSize, 11);
      expect(
          tester.widget<Text>(find.text('7:30')).style!.color, colors.accent);
      expect(
        tester.widget<Text>(find.text('6:50').first).style!.color,
        colors.textSecondary,
      );

      await _pump(
        tester,
        FcBars(items: week(), max: 540, height: 96, showValues: false),
      );
      expect(find.text('未取得'), findsNothing);
      expect(find.text('7:30'), findsNothing);
    });

    testWidgets('最小高さ 4・最大は height（max 超えでも枠から出ない）', (tester) async {
      await _pump(
        tester,
        const FcBars(
          max: 540,
          height: 96,
          items: [
            FcBarItem(value: 1, text: '0:01', label: 'a'),
            FcBarItem(value: 0, text: '0:00', label: 'b'),
            FcBarItem(value: 9999, text: '多い', label: 'c'),
          ],
        ),
      );
      expect(tester.getSize(_bar(0)).height, 4);
      expect(tester.getSize(_bar(1)).height, 4);
      expect(tester.getSize(_bar(2)).height, 96);
    });

    testWidgets('x ラベルは caption（ハイライトは accent・500）', (tester) async {
      await _pump(tester, FcBars(items: week(), max: 540));
      final colors = AppColorsExtension.light;
      final normal = tester.widget<Text>(find.text('月')).style!;
      final highlighted = tester.widget<Text>(find.text('日')).style!;
      expect(normal.fontSize, 12);
      expect(normal.color, colors.textSecondary);
      expect(normal.fontWeight, FontWeight.w400);
      expect(highlighted.color, colors.accent);
      expect(highlighted.fontWeight, FontWeight.w500);
    });

    testWidgets('読み上げは列ごとに「ラベル 値」、null は「未取得」、全体は semanticLabel',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        FcBars(
          items: week(),
          max: 540,
          semanticLabel: '直近7日間の睡眠時間',
        ),
      );
      expect(find.bySemanticsLabel('直近7日間の睡眠時間'), findsOneWidget);
      expect(find.bySemanticsLabel('月 6:50'), findsOneWidget);
      expect(find.bySemanticsLabel('水 未取得'), findsOneWidget);
      expect(find.bySemanticsLabel('日 7:30'), findsOneWidget);
      handle.dispose();
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: 文字拡大 1.35・狭い幅でも overflow しない',
          (tester) async {
        await _pump(
          tester,
          Column(
            children: [
              FcBars(items: week(), max: 540, height: 96),
              const SizedBox(height: 16),
              FcBars(
                gap: 4,
                max: 2400,
                height: 84,
                items: [
                  for (var i = 0; i < 13; i++)
                    FcBarItem(
                      value: 1900,
                      text: '1,900',
                      highlighted: i == 12,
                      label: i % 3 == 0 ? '${i + 1}' : '',
                    ),
                ],
              ),
            ],
          ),
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FcSleepStageBar', () {
    Finder stage(int i) => find.byKey(ValueKey('fc-sleep-stage-$i'));

    testWidgets('formatMinutes: 60 分以上は〇時間〇〇分、未満は〇分', (tester) async {
      expect(FcSleepStageBar.formatMinutes(85), '1時間25分');
      expect(FcSleepStageBar.formatMinutes(60), '1時間00分');
      expect(FcSleepStageBar.formatMinutes(420), '7時間00分');
      expect(FcSleepStageBar.formatMinutes(59), '59分');
      expect(FcSleepStageBar.formatMinutes(20), '20分');
      expect(FcSleepStageBar.formatMinutes(0), '0分');
    });

    testWidgets('帯は高さ 10・角丸 5・区間の間 2・幅は分の比率', (tester) async {
      await _pump(tester, const FcSleepStageBar(stages: _stages));
      expect(tester.takeException(), isNull);

      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(5));
      expect(tester.getSize(find.byType(ClipRRect)).height, 10);
      // 各区間の面も高さ 10 で塗られる（高さ 0 で見えなくならない）
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(stage(i)).height, 10, reason: _stages[i].label);
      }

      const total = 85 + 110 + 255 + 20;
      const usable = 350.0 - 2 * 3;
      final widths = [
        for (var i = 0; i < 4; i++) tester.getSize(stage(i)).width,
      ];
      for (var i = 0; i < 4; i++) {
        expect(
          widths[i],
          closeTo(usable * _stages[i].minutes / total, 0.01),
          reason: _stages[i].label,
        );
      }
      // 区間の間隔 2
      expect(
        tester.getTopLeft(stage(1)).dx - tester.getTopRight(stage(0)).dx,
        closeTo(2, 0.01),
      );
      // 全体は幅いっぱい
      expect(
        tester.getTopRight(stage(3)).dx - tester.getTopLeft(stage(0)).dx,
        closeTo(350, 0.01),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets(
          '${brightness.name}: 色は accent を surface に percent% 混ぜた色（0 は separator）',
          (tester) async {
        final colors = _colors(brightness);
        await _pump(
          tester,
          const FcSleepStageBar(stages: _stages),
          brightness: brightness,
        );
        Color colorOf(int i) => tester.widget<ColoredBox>(stage(i)).color;
        expect(colorOf(0), colors.accent);
        expect(colorOf(1), Color.lerp(colors.surface, colors.accent, 0.6));
        expect(colorOf(2), Color.lerp(colors.surface, colors.accent, 0.3));
        expect(colorOf(3), colors.separator);
      });
    }

    testWidgets('凡例: ラベルと時間（〇時間〇〇分 / 〇分）。四角 8・角丸 2。2 列', (tester) async {
      await _pump(tester, const FcSleepStageBar(stages: _stages));
      for (final text in [
        '深い',
        'レム',
        '浅い',
        '覚醒',
        '1時間25分',
        '1時間50分',
        '4時間15分',
        '20分'
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      final time = tester.widget<Text>(find.text('1時間25分')).style!;
      expect(time.fontSize, 13);
      expect(time.fontWeight, FontWeight.w500);
      expect(time.fontFeatures, AppTextStyles.tabularFigures);
      final label = tester.widget<Text>(find.text('深い')).style!;
      expect(label.fontSize, 13);
      expect(label.color, AppColorsExtension.light.textSecondary);

      // 2 列: 深い と レム は同じ高さ、浅い は 1 段下
      expect(
        tester.getCenter(find.text('深い')).dy,
        tester.getCenter(find.text('レム')).dy,
      );
      expect(
        tester.getCenter(find.text('浅い')).dy,
        greaterThan(tester.getCenter(find.text('深い')).dy),
      );

      // 凡例の四角（8×8・角丸 2）
      final squares = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 8 &&
            w.constraints?.maxHeight == 8,
      );
      expect(squares, findsNWidgets(4));
      final deco =
          tester.widget<Container>(squares.first).decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(2));
    });

    testWidgets('文字が大きい（1.35）ときは凡例を 1 列に積む。overflow しない', (tester) async {
      for (final brightness in Brightness.values) {
        await _pump(
          tester,
          const FcSleepStageBar(stages: _stages),
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
        final x = tester.getCenter(find.text('深い')).dx;
        expect(tester.getCenter(find.text('レム')).dx, x);
        expect(
          tester.getCenter(find.text('レム')).dy,
          greaterThan(tester.getCenter(find.text('深い')).dy),
        );
      }
    });

    testWidgets('0 分の区間は帯に出さず、凡例には「0分」で残す。区間が空でも例外なし', (tester) async {
      await _pump(
        tester,
        const FcSleepStageBar(
          stages: [
            FcSleepStage(label: '深い', minutes: 60, percent: 100),
            FcSleepStage(label: '覚醒', minutes: 0, percent: 0),
          ],
        ),
      );
      expect(stage(0), findsOneWidget);
      expect(stage(1), findsNothing);
      expect(find.text('0分'), findsOneWidget);

      await _pump(tester, const FcSleepStageBar(stages: []));
      expect(tester.takeException(), isNull);
    });

    testWidgets('読み上げは「睡眠の内訳、深い 1時間25分、…」の 1 つ', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const FcSleepStageBar(stages: _stages));
      expect(
        find.bySemanticsLabel(
          '睡眠の内訳、深い 1時間25分、レム 1時間50分、浅い 4時間15分、覚醒 20分',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('プレビュー', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: ギャラリー・状態・グラフが例外なく組める（文字拡大 1.35 も）',
          (tester) async {
        for (final home in const [
          FcExtraPreviewGallery(),
          FcExtraStatesPreview(),
          FcExtraChartsPreview(),
        ]) {
          for (final scale in [1.0, 1.35]) {
            tester.view.physicalSize = const Size(390, 6000) * 2;
            tester.view.devicePixelRatio = 2;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              FcPreviewApp(
                brightness: brightness,
                textScale: scale,
                home: home,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${home.runtimeType} ×$scale');
          }
        }
      });
    }
  });
}
