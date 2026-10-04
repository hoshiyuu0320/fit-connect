import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 部品の見た目が、デザイン正本（`components.jsx` / `parts.js`）の値と一致していることを確かめる。
/// 各テストの数値は正本のインラインスタイルからそのまま取っている。

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  double padding = 20,
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
        body: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppColorsExtension colorsOf(Brightness b) =>
    b == Brightness.dark ? AppColorsExtension.dark : AppColorsExtension.light;

/// ラベル文字を含む最も内側の AnimatedContainer の見た目（面・枠・角丸）
BoxDecoration faceOf(WidgetTester tester, String label) {
  final finder = find
      .ancestor(of: find.text(label), matching: find.byType(AnimatedContainer))
      .first;
  return tester.widget<AnimatedContainer>(finder).decoration as BoxDecoration;
}

TextStyle textStyleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  for (final brightness in Brightness.values) {
    final c = colorsOf(brightness);
    final mode = brightness.name;

    group('FcSegmentedControl（$mode）', () {
      Widget segmented({String selected = 'b'}) => SizedBox(
            width: 350,
            child: FcSegmentedControl<String>(
              items: const [
                FcSegmentedItem(value: 'a', label: '今後'),
                FcSegmentedItem(value: 'b', label: '過去'),
              ],
              selected: selected,
              onChanged: (_) {},
            ),
          );

      testWidgets(
          '選択中 = actionFill の塗り・枠・onAction の文字 / 未選択 = surface + separator の枠 + textSecondary',
          (tester) async {
        await pump(tester, segmented(), brightness: brightness);

        final on = faceOf(tester, '過去');
        expect(on.color, c.actionFill);
        expect((on.border as Border).top.color, c.actionFill);
        expect((on.border as Border).top.width, 1);
        expect(on.borderRadius, BorderRadius.circular(10));
        final onText = textStyleOf(tester, '過去');
        expect(onText.color, c.onAction);
        expect(onText.fontWeight, FontWeight.w500);
        expect(onText.fontSize, 15);

        final off = faceOf(tester, '今後');
        expect(off.color, c.surface);
        expect((off.border as Border).top.color, c.separator);
        final offText = textStyleOf(tester, '今後');
        expect(offText.color, c.textSecondary);
        expect(offText.fontWeight, FontWeight.w400);
      });

      testWidgets('高さ 45 以上・項目の間隔 7・等幅', (tester) async {
        await pump(tester, segmented(), brightness: brightness);
        final a = tester.getRect(find
            .ancestor(
                of: find.text('今後'), matching: find.byType(AnimatedContainer))
            .first);
        final b = tester.getRect(find
            .ancestor(
                of: find.text('過去'), matching: find.byType(AnimatedContainer))
            .first);
        expect(a.height, greaterThanOrEqualTo(45));
        expect(b.left - a.right, 7);
        expect(a.width, closeTo(b.width, 0.01));
        expect(a.width + b.width + 7, 350);
      });

      testWidgets('文字拡大 1.35: 折り返して高さが伸び、全項目が同じ高さ', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSegmentedControl<int>(
              items: const [
                FcSegmentedItem(value: 0, label: '今週'),
                FcSegmentedItem(value: 1, label: '今月'),
                FcSegmentedItem(value: 2, label: '3ヶ月'),
                FcSegmentedItem(value: 3, label: '全期間'),
              ],
              selected: 1,
              onChanged: (_) {},
            ),
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        final heights = [
          for (final l in ['今週', '今月', '3ヶ月', '全期間'])
            tester
                .getSize(find
                    .ancestor(
                        of: find.text(l),
                        matching: find.byType(AnimatedContainer))
                    .first)
                .height,
        ];
        expect(heights.toSet().length, 1);
        expect(heights.first, greaterThanOrEqualTo(45));
      });
    });

    group('FcSubTabs（$mode）', () {
      const items = [
        FcSubTabItem(value: 0, label: 'サマリ'),
        FcSubTabItem(value: 1, label: '体重'),
        FcSubTabItem(value: 2, label: '食事'),
        FcSubTabItem(value: 3, label: '運動'),
        FcSubTabItem(value: 4, label: '睡眠'),
        FcSubTabItem(value: 5, label: 'ノート'),
      ];

      testWidgets(
          '外枠 = surface・角丸 26 / 選択中 = surfaceSecondary + accent + 500 / 未選択 = 面なし + textSecondary',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSubTabs<int>(
              items: items,
              selected: 1,
              onChanged: (_) {},
            ),
          ),
          brightness: brightness,
        );

        final capsule = tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(FcSubTabs<int>),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(capsule.color, c.surface);
        expect(capsule.borderRadius, BorderRadius.circular(26));

        final on = faceOf(tester, '体重');
        expect(on.color, c.surfaceSecondary);
        expect(on.borderRadius, BorderRadius.circular(22));
        final onText = textStyleOf(tester, '体重');
        expect(onText.color, c.accent);
        expect(onText.fontWeight, FontWeight.w500);
        expect(onText.fontSize, 14);

        final off = faceOf(tester, '食事');
        expect(off.color, Colors.transparent);
        final offText = textStyleOf(tester, '食事');
        expect(offText.color, c.textSecondary);
        expect(offText.fontWeight, FontWeight.w400);
      });

      testWidgets('外枠の高さは 52（内側余白 4 + タブ 44 + 4）、タブは 44 以上・幅 48 以上',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSubTabs<int>(
              items: items,
              selected: 0,
              onChanged: (_) {},
            ),
          ),
          brightness: brightness,
        );
        expect(tester.getSize(find.byType(FcSubTabs<int>)).height, 52);
        for (final item in items) {
          final size = tester.getSize(find
              .ancestor(
                  of: find.text(item.label),
                  matching: find.byType(AnimatedContainer))
              .first);
          expect(size.height, greaterThanOrEqualTo(44), reason: item.label);
          expect(size.width, greaterThanOrEqualTo(48), reason: item.label);
        }
      });

      testWidgets('収まるときは余った幅を全タブで等分して、外枠いっぱいに広がる（flex: 1 0 auto）',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSubTabs<int>(
              items: items,
              selected: 0,
              onChanged: (_) {},
            ),
          ),
          brightness: brightness,
        );
        final first = tester.getRect(find
            .ancestor(
                of: find.text('サマリ'), matching: find.byType(AnimatedContainer))
            .first);
        final last = tester.getRect(find
            .ancestor(
                of: find.text('ノート'), matching: find.byType(AnimatedContainer))
            .first);
        final capsule = tester.getRect(find.byType(FcSubTabs<int>));
        // 左右とも外枠の内側余白 4 だけ空いて、タブが端まで並ぶ
        expect(first.left - capsule.left, closeTo(4, 0.01));
        expect(capsule.right - last.right, closeTo(4, 0.01));
        // 同じ文字数のタブは同じ幅
        final a = tester.getSize(find
            .ancestor(
                of: find.text('体重'), matching: find.byType(AnimatedContainer))
            .first);
        final b = tester.getSize(find
            .ancestor(
                of: find.text('睡眠'), matching: find.byType(AnimatedContainer))
            .first);
        expect(a.width, closeTo(b.width, 0.01));
      });

      testWidgets('収まらないとき（文字拡大 1.35）は外枠の中で横スクロールし、例外が出ない', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSubTabs<int>(
              items: items,
              selected: 5,
              onChanged: (_) {},
            ),
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
        // 選択中（最後のノート）が見える位置までスクロールしている
        final capsule = tester.getRect(find.byType(FcSubTabs<int>));
        final note = tester.getRect(find
            .ancestor(
                of: find.text('ノート'), matching: find.byType(AnimatedContainer))
            .first);
        expect(note.right, lessThanOrEqualTo(capsule.right + 0.5));
        expect(note.left, greaterThanOrEqualTo(capsule.left - 0.5));
      });

      testWidgets('タップで onChanged、選択中だけ selected になる', (tester) async {
        final handle = tester.ensureSemantics();
        int? changed;
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcSubTabs<int>(
              items: items,
              selected: 1,
              onChanged: (v) => changed = v,
            ),
          ),
          brightness: brightness,
        );
        await tester.tap(find.text('運動'));
        expect(changed, 3);
        handle.dispose();
      });
    });

    group('FcChips（$mode）', () {
      Widget chips({String selected = 'b'}) => FcChips<String>.single(
            items: const [
              FcChipItem(value: 'a', label: 'すべて'),
              FcChipItem(value: 'b', label: '筋トレ'),
              FcChipItem(value: 'c', label: '有酸素'),
            ],
            selected: selected,
            onSelected: (_) {},
          );

      testWidgets(
          '選択中 = surface の面 + accent + 500 / 未選択 = 透明 + textSecondary・角丸 20・文字 14',
          (tester) async {
        await pump(tester, chips(), brightness: brightness);
        final on = faceOf(tester, '筋トレ');
        expect(on.color, c.surface);
        expect(on.borderRadius, BorderRadius.circular(20));
        final onText = textStyleOf(tester, '筋トレ');
        expect(onText.color, c.accent);
        expect(onText.fontWeight, FontWeight.w500);
        expect(onText.fontSize, 14);

        final off = faceOf(tester, 'すべて');
        expect(off.color, Colors.transparent);
        final offText = textStyleOf(tester, 'すべて');
        expect(offText.color, c.textSecondary);
        expect(offText.fontWeight, FontWeight.w400);
      });

      testWidgets('見た目の高さ 40・左右余白 16・間隔 6 / タッチ領域は高さ 44 以上', (tester) async {
        await pump(tester, chips(), brightness: brightness);
        final face = tester.getRect(find
            .ancestor(
                of: find.text('すべて'), matching: find.byType(AnimatedContainer))
            .first);
        expect(face.height, 40);
        final textWidth = tester.getSize(find.text('すべて')).width;
        expect(face.width, closeTo(textWidth + 32, 0.5));

        final next = tester.getRect(find
            .ancestor(
                of: find.text('筋トレ'), matching: find.byType(AnimatedContainer))
            .first);
        expect(next.left - face.right, closeTo(6, 0.01));

        final touch = tester.getSize(find
            .ancestor(of: find.text('すべて'), matching: find.byType(FcPressable))
            .first);
        expect(touch.height, greaterThanOrEqualTo(44));
        expect(touch.width, greaterThanOrEqualTo(44));
      });

      testWidgets('文字拡大 1.35 でも折り返して並び、例外が出ない', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcChips<int>(
              items: [
                for (var i = 0; i < 8; i++)
                  FcChipItem(value: i, label: '種類 ${i + 1}'),
              ],
              selected: const {2},
              onSelected: (_) {},
            ),
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('FcCardHead（$mode）', () {
      testWidgets('アイコン 17 とラベル 14 がともに accent・間 6・補足 13 textSecondary・下余白 12',
          (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: FcCardHead(
              icon: LucideIcons.scale,
              label: '体重',
              note: '今朝',
            ),
          ),
          brightness: brightness,
        );
        final icon = tester.widget<Icon>(find.byIcon(LucideIcons.scale));
        expect(icon.size, 17);
        expect(icon.color, c.accent);
        final label = textStyleOf(tester, '体重');
        expect(label.color, c.accent);
        expect(label.fontSize, 14);
        final note = textStyleOf(tester, '今朝');
        expect(note.color, c.textSecondary);
        expect(note.fontSize, 13);

        final iconRect = tester.getRect(find.byIcon(LucideIcons.scale));
        final labelRect = tester.getRect(find.text('体重'));
        expect(labelRect.left - iconRect.right, 6);
        // 後ろの余白 12 を含む
        final head = tester.getSize(find.byType(FcCardHead));
        final row = tester.getSize(find
            .descendant(of: find.byType(FcCardHead), matching: find.byType(Row))
            .first);
        expect(head.height - row.height, 12);
      });
    });

    group('FcTextField（$mode）', () {
      InputDecoration decorationOf(WidgetTester tester) =>
          tester.widget<TextField>(find.byType(TextField).first).decoration!;

      testWidgets('surface の面 + 1px の separator の枠・角丸 12・文字 16（行高 1.6）',
          (tester) async {
        await pump(
          tester,
          const SizedBox(width: 350, child: FcTextField(label: '内容')),
          brightness: brightness,
        );
        final d = decorationOf(tester);
        expect(d.filled, isTrue);
        expect(d.fillColor, c.surface);
        final border = d.enabledBorder as OutlineInputBorder;
        expect(border.borderSide.color, c.separator);
        expect(border.borderSide.width, 1);
        expect(border.borderRadius, BorderRadius.circular(12));
        final style = tester.widget<TextField>(find.byType(TextField)).style!;
        expect(style.fontSize, 16);
        expect(style.height, 1.6);
        // 内側余白 12 + 枠 1 = 13
        expect(d.contentPadding, const EdgeInsets.all(13));
      });

      testWidgets('ラベルは入力欄の上・15・textPrimary・下余白 8', (tester) async {
        await pump(
          tester,
          const SizedBox(width: 350, child: FcTextField(label: '内容')),
          brightness: brightness,
        );
        final label = textStyleOf(tester, '内容');
        expect(label.fontSize, 15);
        expect(label.color, c.textPrimary);
        final labelRect = tester.getRect(find.text('内容'));
        final fieldRect = tester.getRect(find.byType(TextField));
        expect(fieldRect.top - labelRect.bottom, closeTo(8, 0.6));
      });

      testWidgets('単位があると右余白 48（+ 枠 1）、単位は右から 14・13px・textSecondary',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcTextField.number(label: '体重', unit: 'kg'),
          ),
          brightness: brightness,
        );
        final d = decorationOf(tester);
        expect(d.contentPadding, const EdgeInsets.fromLTRB(13, 13, 49, 13));
        final unit = textStyleOf(tester, 'kg');
        expect(unit.fontSize, 13);
        expect(unit.color, c.textSecondary);
        final fieldRect = tester.getRect(find.byType(TextField));
        final unitRect = tester.getRect(find.text('kg'));
        expect(fieldRect.right - unitRect.right, closeTo(14, 0.6));
        // 縦は入力欄の中央
        expect(unitRect.center.dy, closeTo(fieldRect.center.dy, 1));
      });

      testWidgets('エラー時は枠が error、13px の error 色の文 + alert アイコン 15 / ヒントは出ない',
          (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: FcTextField(
              label: 'カロリー',
              errorText: '数字で入力してください',
              helperText: '出ない',
            ),
          ),
          brightness: brightness,
        );
        final d = decorationOf(tester);
        expect(
            (d.enabledBorder as OutlineInputBorder).borderSide.color, c.error);
        final error = textStyleOf(tester, '数字で入力してください');
        expect(error.fontSize, 13);
        expect(error.color, c.error);
        final icon = tester.widget<Icon>(find.byIcon(LucideIcons.alertCircle));
        expect(icon.size, 15);
        expect(icon.color, c.error);
        expect(find.text('出ない'), findsNothing);
        // 入力欄の下 6
        final fieldRect = tester.getRect(find.byType(TextField));
        final errorRect = tester.getRect(find.text('数字で入力してください'));
        expect(errorRect.top - fieldRect.bottom, closeTo(6, 1.6));
      });

      testWidgets('ヒントは 12px・textSecondary・上 6', (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: FcTextField(label: 'メモ', helperText: '空でも保存できます'),
          ),
          brightness: brightness,
        );
        final helper = textStyleOf(tester, '空でも保存できます');
        expect(helper.fontSize, 12);
        expect(helper.color, c.textSecondary);
      });

      testWidgets('複数行は最小高さ 107、無効は入力欄が opacity 0.5', (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: Column(
              children: [
                FcTextField(label: '複数行', minLines: 3, maxLines: 5),
                FcTextField(label: '無効', enabled: false),
              ],
            ),
          ),
          brightness: brightness,
        );
        final multi = tester.getSize(find.byType(TextField).first);
        expect(multi.height, greaterThanOrEqualTo(107));
        final opacity = tester.widget<Opacity>(find
            .ancestor(
                of: find.byType(TextField).last, matching: find.byType(Opacity))
            .first);
        expect(opacity.opacity, 0.5);
      });
    });

    group('FcStateMessage（$mode）', () {
      testWidgets('左寄せの surface カード（角丸 23・余白 20）。empty はアイコンなし',
          (tester) async {
        await pump(
          tester,
          const FcStateMessage.empty(
            title: '今日のプランはありません',
            message: '田中トレーナーがプランを設定すると、ここに表示されます。',
          ),
          brightness: brightness,
        );
        final card = tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(FcStateMessage),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(card.color, c.surface);
        expect(card.borderRadius, BorderRadius.circular(23));
        expect(find.byType(Icon), findsNothing);

        final cardRect = tester.getRect(find.byType(FcCard));
        final titleRect = tester.getRect(find.text('今日のプランはありません'));
        expect(titleRect.left - cardRect.left, 20, reason: '左寄せ・余白 20');
        final title = textStyleOf(tester, '今日のプランはありません');
        expect(title.fontSize, 16);
        expect(title.fontWeight, FontWeight.w500);
        final body = textStyleOf(tester, '田中トレーナーがプランを設定すると、ここに表示されます。');
        expect(body.fontSize, 14);
        expect(body.color, c.textSecondary);
        final bodyRect =
            tester.getRect(find.text('田中トレーナーがプランを設定すると、ここに表示されます。'));
        expect(bodyRect.top - titleRect.bottom, closeTo(4, 0.6));
      });

      testWidgets(
          'error = alert アイコン 18 + error 色、success = check + success 色、タイトルは textPrimary',
          (tester) async {
        await pump(
          tester,
          const Column(
            children: [
              FcStateMessage.error(title: '読み込めませんでした'),
              FcStateMessage.success(title: '共有しました'),
            ],
          ),
          brightness: brightness,
        );
        final error = tester.widget<Icon>(find.byIcon(LucideIcons.alertCircle));
        expect(error.size, 18);
        expect(error.color, c.error);
        final ok = tester.widget<Icon>(find.byIcon(LucideIcons.checkCircle));
        expect(ok.color, c.success);
        expect(textStyleOf(tester, '読み込めませんでした').color, c.textPrimary);
      });

      testWidgets('操作は pill（上 14）か text（上 4）で押せる', (tester) async {
        var taps = 0;
        await pump(
          tester,
          Column(
            children: [
              FcStateMessage.error(
                title: 'a',
                actionLabel: '再試行',
                onAction: () => taps++,
              ),
              FcStateMessage.empty(
                title: 'b',
                actionLabel: '戻る',
                actionVariant: FcButtonVariant.text,
                onAction: () => taps += 10,
              ),
            ],
          ),
          brightness: brightness,
          size: const Size(390, 1200),
        );
        await tester.tap(find.text('再試行'));
        await tester.tap(find.text('戻る'));
        expect(taps, 11);
        final titleRect = tester.getRect(find.text('a'));
        final buttonRect = tester.getRect(find
            .ancestor(of: find.text('再試行'), matching: find.byType(DecoratedBox))
            .first);
        // タイトル行（高さ 24）の下 14
        expect(buttonRect.top - titleRect.bottom, closeTo(14, 2));
      });

      testWidgets('文字拡大 1.35 で縦に伸びるだけで例外が出ない', (tester) async {
        await pump(
          tester,
          FcStateMessage.error(
            title: '読み込めませんでした。もう一度お試しください',
            message: '時間をおいてからもう一度お試しください。それでも直らないときはお知らせください。',
            actionLabel: '再試行',
            onAction: () {},
          ),
          brightness: brightness,
          textScale: 1.35,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('FcPageHeading（$mode）', () {
      testWidgets('eyebrow は 13px・textSecondary・字間なし・下 6 / 後ろの余白 24',
          (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: FcPageHeading(
              eyebrow: '10月4日（日）',
              title: 'ホーム',
              subtitle: '今日の記録です。',
            ),
          ),
          brightness: brightness,
        );
        final eyebrow = textStyleOf(tester, '10月4日（日）');
        expect(eyebrow.fontSize, 13);
        expect(eyebrow.letterSpacing, isNull,
            reason: '字間なし（1.6 は AppHeader のブランド表記）');
        expect(eyebrow.fontWeight, FontWeight.w400);
        expect(eyebrow.color, c.textSecondary);
        final title = textStyleOf(tester, 'ホーム');
        expect(title.fontSize, 32);
        expect(title.fontWeight, FontWeight.w500);
        expect(title.letterSpacing, -1);
        expect(title.height, 1.2);
        final subtitle = textStyleOf(tester, '今日の記録です。');
        expect(subtitle.fontSize, 16);
        expect(subtitle.color, c.textSecondary);

        final eyebrowRect = tester.getRect(find.text('10月4日（日）'));
        final titleRect = tester.getRect(find.text('ホーム'));
        expect(titleRect.top - eyebrowRect.bottom, closeTo(6, 0.6));
        final subtitleRect = tester.getRect(find.text('今日の記録です。'));
        final headingRect = tester.getRect(find.byType(FcPageHeading));
        expect(headingRect.bottom - subtitleRect.bottom, closeTo(24, 0.6));
      });

      testWidgets('ブランド表記（AppHeader）は 12px・字間 1.6・500・textSecondary',
          (tester) async {
        late TextStyle brand;
        await pump(
          tester,
          Builder(builder: (context) {
            brand = AppTextStyles.brand(context);
            return const SizedBox.shrink();
          }),
          brightness: brightness,
        );
        expect(brand.fontSize, 12);
        expect(brand.letterSpacing, 1.6);
        expect(brand.fontWeight, FontWeight.w500);
        expect(brand.color, c.textSecondary);
      });
    });

    group('FcButton（$mode）', () {
      Future<Size> faceSize(WidgetTester tester, String label) async =>
          tester.getSize(find
              .ancestor(
                  of: find.text(label), matching: find.byType(DecoratedBox))
              .first);

      testWidgets('pill / block / text / back の最小高さ・余白・文字・アイコンが正本どおり',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FcButton.pill(
                  label: 'ピル',
                  icon: LucideIcons.plus,
                  onPressed: () {},
                ),
                FcButton.block(label: 'ブロック', onPressed: () {}),
                FcButton.text(label: 'テキスト', onPressed: () {}),
                FcButton.back(label: '戻る', onPressed: () {}),
              ],
            ),
          ),
          brightness: brightness,
          size: const Size(390, 1000),
        );

        // pill: 最小高さ 43・文字 15/500・アイコン 15・actionFill
        expect((await faceSize(tester, 'ピル')).height, 43);
        final pill = textStyleOf(tester, 'ピル');
        expect(pill.fontSize, 15);
        expect(pill.fontWeight, FontWeight.w500);
        expect(pill.color, c.onAction);
        expect(tester.widget<Icon>(find.byIcon(LucideIcons.plus)).size, 15);
        // 既定のアイコン位置は末尾（正本）。文字の右にある
        expect(tester.getRect(find.byIcon(LucideIcons.plus)).left,
            greaterThan(tester.getRect(find.text('ピル')).right));
        final pillDeco = tester
            .widget<DecoratedBox>(find
                .ancestor(
                    of: find.text('ピル'), matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(pillDeco.color, c.actionFill);

        // block: 最小高さ 48・横幅いっぱい・文字 16/500
        final block = await faceSize(tester, 'ブロック');
        expect(block.height, 48);
        expect(block.width, 350);
        final blockText = textStyleOf(tester, 'ブロック');
        expect(blockText.fontSize, 16);
        expect(blockText.fontWeight, FontWeight.w500);

        // text: 横幅いっぱい・最小高さ 47・accent・15/500
        final text = await faceSize(tester, 'テキスト');
        expect(text.width, 350);
        expect(text.height, 47);
        final textStyle = textStyleOf(tester, 'テキスト');
        expect(textStyle.color, c.accent);
        expect(textStyle.fontSize, 15);
        expect(textStyle.fontWeight, FontWeight.w500);

        // back: 最小高さ 44・accent・15/400・左矢印 17 が先頭
        final back = await faceSize(tester, '戻る');
        expect(back.height, 44);
        final backStyle = textStyleOf(tester, '戻る');
        expect(backStyle.fontWeight, FontWeight.w400);
        expect(backStyle.color, c.accent);
        final arrow = tester.widget<Icon>(find.byIcon(LucideIcons.arrowLeft));
        expect(arrow.size, 17);
        expect(tester.getRect(find.byIcon(LucideIcons.arrowLeft)).right,
            lessThanOrEqualTo(tester.getRect(find.text('戻る')).left));
      });

      testWidgets('text は文字が左・アイコンが右端（space-between）', (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcButton.text(
              label: 'メッセージを送る',
              icon: LucideIcons.chevronRight,
              onPressed: () {},
            ),
          ),
          brightness: brightness,
        );
        final box = tester.getRect(find.byType(FcButton));
        expect(tester.getRect(find.text('メッセージを送る')).left, box.left);
        expect(tester.getRect(find.byIcon(LucideIcons.chevronRight)).right,
            closeTo(box.right, 0.5));
        expect(tester.widget<Icon>(find.byIcon(LucideIcons.chevronRight)).size,
            16);
      });

      testWidgets('無効は全体 opacity 0.4、処理中は「処理しています…」で薄くせず押せない', (tester) async {
        var taps = 0;
        await pump(
          tester,
          Column(
            children: [
              const FcButton.block(label: '無効', onPressed: null),
              FcButton.block(
                label: '送信',
                loading: true,
                onPressed: () => taps++,
              ),
            ],
          ),
          brightness: brightness,
          size: const Size(390, 400),
        );
        final dimmed = tester.widget<Opacity>(find
            .descendant(
                of: find.widgetWithText(FcButton, '無効'),
                matching: find.byType(Opacity))
            .first);
        expect(dimmed.opacity, 0.4);

        expect(find.text('送信'), findsNothing);
        expect(find.text('処理しています…'), findsOneWidget);
        expect(
          find.descendant(
              of: find.widgetWithText(FcButton, '処理しています…'),
              matching: find.byType(Opacity)),
          findsNothing,
        );
        await tester.tap(find.text('処理しています…'));
        expect(taps, 0);
      });

      testWidgets('Row の中（横幅が無制限）の block / text でも例外が出ない', (tester) async {
        await pump(
          tester,
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FcButton.block(label: 'ブロック', onPressed: () {}),
              FcButton.text(label: 'テキスト', onPressed: () {}),
            ],
          ),
          brightness: brightness,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('FcInlineNotice（$mode）', () {
      testWidgets('tone ごとの面・文字色・アイコン（neutral はアイコンなし）・文字 13・余白 10×12・角丸 12',
          (tester) async {
        await pump(
          tester,
          const SizedBox(
            width: 350,
            child: Column(
              children: [
                FcInlineNotice.warning(message: '注意'),
                FcInlineNotice.error(message: '失敗'),
                FcInlineNotice.success(message: '完了'),
                FcInlineNotice.neutral(message: '中立'),
                FcInlineNotice.info(message: 'お知らせ'),
              ],
            ),
          ),
          brightness: brightness,
          size: const Size(390, 900),
        );

        BoxDecoration surfaceOf(String message) => tester
            .widget<DecoratedBox>(find
                .ancestor(
                    of: find.text(message), matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;

        expect(surfaceOf('注意').color, c.warningSurface);
        expect(textStyleOf(tester, '注意').color, c.warning);
        expect(surfaceOf('失敗').color, c.errorSurface);
        expect(textStyleOf(tester, '失敗').color, c.error);
        expect(surfaceOf('完了').color, c.successSurface);
        expect(textStyleOf(tester, '完了').color, c.success);
        expect(surfaceOf('中立').color, c.surfaceSecondary);
        expect(textStyleOf(tester, '中立').color, c.textSecondary);
        expect(surfaceOf('お知らせ').color, c.surfaceSecondary,
            reason: 'info は neutral の別名');
        expect(surfaceOf('注意').borderRadius, BorderRadius.circular(12));
        expect(textStyleOf(tester, '注意').fontSize, 13);

        expect(find.byIcon(LucideIcons.alertCircle), findsNWidgets(2));
        expect(find.byIcon(LucideIcons.checkCircle), findsOneWidget);
        expect(find.byIcon(LucideIcons.info), findsNothing);
        expect(
            tester.widget<Icon>(find.byIcon(LucideIcons.checkCircle)).size, 16);

        // 余白 10×12: 1 行の高さ = 10 + 行高 (13 × 1.5) + 10
        final rect = tester.getRect(find
            .ancestor(of: find.text('中立'), matching: find.byType(DecoratedBox))
            .first);
        expect(rect.height, closeTo(10 + 13 * 1.5 + 10, 0.6));
        expect(tester.getRect(find.text('中立')).left - rect.left, 12);
      });

      testWidgets('操作は更新アイコン 14 + ラベル（太さ 500）で、タッチ領域 44 以上・押せる',
          (tester) async {
        var taps = 0;
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcInlineNotice.warning(
              message: 'オフラインです',
              actionLabel: '再試行',
              onAction: () => taps++,
            ),
          ),
          brightness: brightness,
        );
        expect(
            tester.widget<Icon>(find.byIcon(LucideIcons.refreshCw)).size, 14);
        expect(textStyleOf(tester, '再試行').fontWeight, FontWeight.w500);
        final touch = tester.getSize(find
            .ancestor(of: find.text('再試行'), matching: find.byType(FcPressable))
            .first);
        expect(touch.height, greaterThanOrEqualTo(44));
        await tester.tap(find.text('再試行'));
        expect(taps, 1);
      });
    });

    group('FcAvatar（$mode）', () {
      testWidgets(
          'サイズ 29/39/46 = 文字 13/15/17、地は surfaceSecondary、イニシャルは accent・500',
          (tester) async {
        await pump(
          tester,
          const Row(
            children: [
              FcAvatar(name: '山田', size: FcAvatar.sm),
              FcAvatar(name: '田中'),
              FcAvatar(name: '佐藤', size: FcAvatar.lg),
            ],
          ),
          brightness: brightness,
        );
        expect(tester.getSize(find.byType(FcAvatar).at(0)), const Size(29, 29));
        expect(tester.getSize(find.byType(FcAvatar).at(1)), const Size(39, 39));
        expect(tester.getSize(find.byType(FcAvatar).at(2)), const Size(46, 46));
        for (final entry in {'山': 13.0, '田': 15.0, '佐': 17.0}.entries) {
          final style = textStyleOf(tester, entry.key);
          expect(style.fontSize, entry.value, reason: entry.key);
          expect(style.color, c.accent);
          expect(style.fontWeight, FontWeight.w500);
        }
        final deco = tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(FcAvatar).at(1),
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration;
        expect(deco.color, c.surfaceSecondary);
        expect(deco.shape, BoxShape.circle);
      });
    });

    group('FcPill / FcDot / FcDoneMark / FcToggle / FcNum（$mode）', () {
      testWidgets('FcPill: 余白 3×10・角丸 999・12px/500・tone ごとの色', (tester) async {
        await pump(
          tester,
          const Row(
            children: [
              FcPill('中立'),
              SizedBox(width: 8),
              FcPill('控えめ', tone: FcPillTone.muted),
              SizedBox(width: 8),
              FcPill('強い', tone: FcPillTone.strong, icon: LucideIcons.check),
            ],
          ),
          brightness: brightness,
        );
        BoxDecoration deco(String label) => tester
            .widget<DecoratedBox>(find
                .ancestor(
                    of: find.text(label), matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(deco('中立').color, c.surfaceSecondary);
        expect(textStyleOf(tester, '中立').color, c.textPrimary);
        expect(deco('控えめ').color, c.surfaceSecondary);
        expect(textStyleOf(tester, '控えめ').color, c.textSecondary);
        expect(deco('強い').color, c.actionFill);
        expect(textStyleOf(tester, '強い').color, c.onAction);
        expect(textStyleOf(tester, '中立').fontSize, 12);
        expect(textStyleOf(tester, '中立').fontWeight, FontWeight.w500);
        expect(tester.widget<Icon>(find.byIcon(LucideIcons.check)).size, 12);
        final rect = tester.getRect(find
            .ancestor(of: find.text('中立'), matching: find.byType(DecoratedBox))
            .first);
        expect(rect.height, closeTo(3 + 12 * 1.5 + 3, 0.6));
        expect(tester.getRect(find.text('中立')).left - rect.left, 10);
      });

      testWidgets('FcDot: 6×6、塗り = accent、中抜き = 1.5px の textSecondary の枠',
          (tester) async {
        await pump(
          tester,
          const Row(
              children: [FcDot(), SizedBox(width: 8), FcDot(filled: false)]),
          brightness: brightness,
        );
        expect(tester.getSize(find.byType(FcDot).first), const Size(6, 6));
        BoxDecoration deco(int i) => tester
            .widget<Container>(find
                .descendant(
                    of: find.byType(FcDot).at(i),
                    matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration;
        expect(deco(0).color, c.accent);
        expect(deco(1).color, Colors.transparent);
        expect((deco(1).border as Border).top.color, c.textSecondary);
        expect((deco(1).border as Border).top.width, 1.5);
      });

      testWidgets(
          'FcDoneMark: 完了 = actionFill の塗り円 + onAction のチェック（60%・線 2.2）/ 未完了 = 1.5px の枠（textSecondary 55%）',
          (tester) async {
        await pump(
          tester,
          const Row(children: [
            FcDoneMark(done: true),
            SizedBox(width: 8),
            FcDoneMark(done: false),
          ]),
          brightness: brightness,
        );
        BoxDecoration deco(int i) => tester
            .widget<AnimatedContainer>(find
                .descendant(
                    of: find.byType(FcDoneMark).at(i),
                    matching: find.byType(AnimatedContainer))
                .first)
            .decoration as BoxDecoration;
        expect(deco(0).color, c.actionFill);
        expect(deco(0).shape, BoxShape.circle);
        expect((deco(1).border as Border).top.width, 1.5);
        expect((deco(1).border as Border).top.color,
            c.textSecondary.withValues(alpha: 0.55));
        // チェックは円（24）の 60%（14）の枠に描く
        final paint = tester.widget<CustomPaint>(find.descendant(
            of: find.byType(FcDoneMark).at(0),
            matching: find.byType(CustomPaint)));
        expect(paint.size, const Size.square(14));
      });

      testWidgets('FcToggle: 51 幅・オン = actionFill / オフ = separator・つまみは白',
          (tester) async {
        await pump(
          tester,
          Column(
            children: [
              FcToggle(value: true, onChanged: (_) {}, semanticLabel: 'オン'),
              FcToggle(value: false, onChanged: (_) {}, semanticLabel: 'オフ'),
            ],
          ),
          brightness: brightness,
        );
        final switches = tester
            .widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch))
            .toList();
        expect(switches, hasLength(2));
        for (final s in switches) {
          expect(s.activeTrackColor, c.actionFill);
          expect(s.inactiveTrackColor, c.separator);
          expect(s.thumbColor, Colors.white);
        }
        // 本体の幅は 51、高さは 31 のトラックに当たり判定の余白が付く（Flutter の CupertinoSwitch）
        expect(tester.getSize(find.byType(CupertinoSwitch).first).width, 51);
        expect(tester.getSize(find.byType(CupertinoSwitch).first).height,
            greaterThanOrEqualTo(31));
        expect(tester.getSize(find.byType(FcToggle).first).height, 44);
      });

      testWidgets(
          'FcNum: 数値 500・行高 1.1・字間（32 は -1）、単位 13/400/textSecondary で数値との間 3',
          (tester) async {
        await pump(
          tester,
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FcNum(value: '68.4', unit: 'kg'),
              FcNum.parts(
                size: FcNumSize.review,
                parts: [FcNumPart('7', '時間'), FcNumPart('30', '分')],
              ),
              FcStat(label: '目標まで', value: '2.6', unit: 'kg'),
              FcStat(
                label: '前回から',
                value: '+0.1',
                unit: 'kg',
                size: FcNumSize.compact,
              ),
            ],
          ),
          brightness: brightness,
        );

        TextSpan spanOf(String text) {
          for (final rich
              in tester.widgetList<RichText>(find.byType(RichText))) {
            TextSpan? found;
            rich.text.visitChildren((span) {
              if (span is TextSpan && span.text == text) found = span;
              return true;
            });
            if (found != null) return found!;
          }
          throw StateError('span "$text" not found');
        }

        final home = spanOf('68.4').style!;
        expect(home.fontSize, 32);
        expect(home.fontWeight, FontWeight.w500);
        expect(home.height, 1.1);
        expect(home.letterSpacing, -1);
        expect(home.fontFeatures, isNotEmpty);

        final review = spanOf('7').style!;
        expect(review.fontSize, 34);
        expect(spanOf('時間').style!.fontSize, 13);
        expect(spanOf('時間').style!.color, c.textSecondary);
        expect(spanOf('分').style!.fontWeight, FontWeight.w400);

        // Stat 既定 26（字間 -0.6）、compact 20
        expect(spanOf('2.6').style!.fontSize, 26);
        expect(spanOf('2.6').style!.letterSpacing, -0.6);
        expect(spanOf('+0.1').style!.fontSize, 20);
        // ラベルは 13 / textSecondary
        expect(textStyleOf(tester, '目標まで').fontSize, 13);
        expect(textStyleOf(tester, '目標まで').color, c.textSecondary);
      });
    });

    group('FcWeekStrip（$mode）', () {
      testWidgets(
          '選択日 = surfaceSecondary の円（34）+ accent + 500、他は面なし / 曜日は caption',
          (tester) async {
        await pump(
          tester,
          SizedBox(
            width: 350,
            child: FcWeekStrip(
              days: [
                for (var i = 0; i < 7; i++)
                  FcWeekDay(
                    date: DateTime(2026, 9, 7).add(Duration(days: i)),
                    mark: i == 1 ? FcDayMark.filled : FcDayMark.none,
                    markWidget: i == 2 ? const Text('2回') : null,
                    selected: i == 6,
                  ),
              ],
              onSelect: (_) {},
            ),
          ),
          brightness: brightness,
        );
        final on = textStyleOf(tester, '13');
        expect(on.color, c.accent);
        expect(on.fontWeight, FontWeight.w500);
        expect(on.fontSize, 16);
        final off = textStyleOf(tester, '8');
        expect(off.color, c.textPrimary);
        expect(off.fontWeight, FontWeight.w400);

        BoxDecoration faceOf(String date) => tester
            .widget<Container>(find
                .ancestor(of: find.text(date), matching: find.byType(Container))
                .first)
            .decoration as BoxDecoration;
        expect(faceOf('13').color, c.surfaceSecondary);
        expect(faceOf('8').color, Colors.transparent);
        final faceSize = tester.getSize(find
            .ancestor(of: find.text('13'), matching: find.byType(Container))
            .first);
        expect(faceSize.height, 34);

        // 曜日は caption（12 / textSecondary）
        final dow = textStyleOf(tester, '日');
        expect(dow.fontSize, 12);
        expect(dow.color, c.textSecondary);
        // 点は 6×6、markWidget は accent の caption
        expect(tester.getSize(find.byType(FcDot)), const Size(6, 6));
        final mark = tester
            .widget<DefaultTextStyle>(find
                .ancestor(
                    of: find.text('2回'),
                    matching: find.byType(DefaultTextStyle))
                .first)
            .style;
        expect(mark.color, c.accent);
        expect(mark.fontSize, 12);
      });
    });

    group('FcBottomNav（$mode）', () {
      const navItems = <FcBottomNavItem>[
        FcBottomNavItem(icon: LucideIcons.home, label: 'ホーム'),
        FcBottomNavItem(
          icon: LucideIcons.messageSquare,
          label: 'メッセージ',
          showDot: true,
        ),
        FcBottomNavItem(icon: LucideIcons.dumbbell, label: 'プラン'),
        FcBottomNavItem(icon: LucideIcons.barChart2, label: '記録'),
        FcBottomNavItem(icon: LucideIcons.settings, label: '設定'),
      ];

      Future<void> pumpNav(WidgetTester tester, {int current = 1}) async {
        tester.view.physicalSize = const Size(390, 844) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Align(
              alignment: Alignment.bottomCenter,
              child: FcBottomNav(
                items: navItems,
                currentIndex: current,
                onTap: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets(
          'footer 余白 上14・左右17・下15、カプセル高さ 64・全体 93、外形角丸 40・枠 1px navigationBorder',
          (tester) async {
        await pumpNav(tester);
        final nav = tester.getRect(find.byType(FcBottomNav));
        expect(nav.height, 93);
        expect(nav.bottom, 844);

        final capsule = tester.getRect(find
            .descendant(
                of: find.byType(FcBottomNav), matching: find.byType(ClipRRect))
            .first);
        expect(capsule.height, 64);
        expect(capsule.left, 17);
        expect(capsule.right, 390 - 17);
        expect(nav.bottom - capsule.bottom, 15);
        expect(capsule.top - nav.top, 14);

        final face = tester
            .widget<DecoratedBox>(find
                .descendant(
                    of: find.byType(ClipRRect),
                    matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration;
        expect(face.borderRadius, BorderRadius.circular(40));
        expect((face.border as Border).top.color, c.navigationBorder);
        expect((face.border as Border).top.width, 1);
        expect(face.color, c.navigationSurface);

        // 影: 0 3px 14px・ライト 4% / ダーク 20%
        final shadow = tester
            .widgetList<DecoratedBox>(find.descendant(
                of: find.byType(FcBottomNav),
                matching: find.byType(DecoratedBox)))
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow != null)
            .boxShadow!
            .single;
        expect(shadow.offset, const Offset(0, 3));
        expect(shadow.blurRadius, 14);
        expect(shadow.color.a,
            closeTo(brightness == Brightness.dark ? 0.20 : 0.04, 0.005));
      });

      testWidgets(
          '操作は最小高さ 52・間隔 2・選択中 = surfaceSecondary の面（角丸 28）+ accent + 500 / 未選択 = textSecondary',
          (tester) async {
        await pumpNav(tester, current: 3);
        final home = tester.getRect(find
            .ancestor(
                of: find.text('ホーム'), matching: find.byType(AnimatedContainer))
            .first);
        final message = tester.getRect(find
            .ancestor(
                of: find.text('メッセージ'),
                matching: find.byType(AnimatedContainer))
            .first);
        expect(home.height, 52);
        expect(message.left - home.right, 2);

        final selected = faceOf(tester, '記録');
        expect(selected.color, c.surfaceSecondary);
        expect(selected.borderRadius, BorderRadius.circular(28));
        expect(textStyleOf(tester, '記録').color, c.accent);
        expect(textStyleOf(tester, '記録').fontWeight, FontWeight.w500);
        expect(textStyleOf(tester, '記録').fontSize, 11);
        expect(faceOf(tester, 'ホーム').color, Colors.transparent);
        expect(textStyleOf(tester, 'ホーム').color, c.textSecondary);
        expect(textStyleOf(tester, 'ホーム').fontWeight, FontWeight.w400);

        // アイコン 20 と文字の間 3
        final icon = tester.getRect(find.byIcon(LucideIcons.home));
        expect(icon.width, closeTo(20, 0.01));
        expect(icon.height, closeTo(20, 0.01));
        expect(tester.getRect(find.text('ホーム')).top - icon.bottom,
            closeTo(3, 0.6));
      });

      testWidgets(
          '新着の点は 7×7・accent・アイコンの右上（top -1 / right -4）・外周 2 の navigationSurface のリング・読み上げに「（新着あり）」',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpNav(tester);
        final dot = find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == c.accent);
        expect(dot, findsOneWidget);
        expect(tester.getSize(dot), const Size(7, 7));
        final deco =
            tester.widget<DecoratedBox>(dot).decoration as BoxDecoration;
        final ring = deco.boxShadow!.single;
        expect(ring.spreadRadius, 2);
        expect(ring.blurRadius, 0);
        expect(ring.color, c.navigationSurface);

        final icon = tester.getRect(find.byIcon(LucideIcons.messageSquare));
        final dotRect = tester.getRect(dot);
        expect(dotRect.top - icon.top, -1);
        expect(icon.right - dotRect.right, -4);
        expect(find.bySemanticsLabel('メッセージ（新着あり）'), findsOneWidget);
        handle.dispose();
      });
    });
  }

  group('狭い画面（320 幅）× 文字拡大 1.35', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: ギャラリーを最後までスクロールしても overflow しない',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.35)),
              child: c!,
            ),
            home: const FcPreviewGallery(),
          ),
        );
        await tester.pumpAndSettle();
        final list = find.byType(ListView);
        for (var i = 0; i < 25; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pump();
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('AppTheme（正本との一致）', () {
    for (final brightness in Brightness.values) {
      final c = colorsOf(brightness);
      final theme = brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme;

      test(
          '${brightness.name}: 入力欄の既定の枠は 1px の separator・角丸 12、フォーカスは accent、エラーは error（状態別の枠は設定しない）',
          () {
        final input = theme.inputDecorationTheme;
        // 状態別の枠（enabledBorder など）は画面側の `border: InputBorder.none` を打ち消すので設定しない
        expect(input.enabledBorder, isNull);
        expect(input.disabledBorder, isNull);
        expect(input.focusedBorder, isNull);
        expect(input.errorBorder, isNull);
        expect(input.focusedErrorBorder, isNull);
        // 面は filled: true を渡した入力欄（FcTextField など）だけに付く
        expect(input.filled, isNot(isTrue));
        expect(input.fillColor, c.surface);

        final border = input.border! as WidgetStateInputBorder;
        OutlineInputBorder resolve(Set<WidgetState> states) =>
            border.resolve(states) as OutlineInputBorder;
        final normal = resolve({});
        expect(normal.borderSide.color, c.separator);
        expect(normal.borderSide.width, 1);
        expect(normal.borderRadius, BorderRadius.circular(12));
        expect(resolve({WidgetState.focused}).borderSide.color, c.accent);
        expect(resolve({WidgetState.error}).borderSide.color, c.error);
        expect(resolve({WidgetState.error}).borderSide.width, 1);
        expect(
            resolve({WidgetState.error, WidgetState.focused}).borderSide.color,
            c.error);
      });

      test('${brightness.name}: Switch のオフ = separator・オン = actionFill', () {
        final track = theme.switchTheme.trackColor!;
        expect(track.resolve(<WidgetState>{}), c.separator);
        expect(track.resolve({WidgetState.selected}), c.actionFill);
      });

      test('${brightness.name}: Chip の選択中 = surface の面 + accent の文字、未選択 = 透明',
          () {
        final chip = theme.chipTheme;
        expect(chip.backgroundColor, Colors.transparent);
        expect(chip.selectedColor, c.surface);
        expect(chip.labelStyle!.color, c.textSecondary);
        expect(chip.secondaryLabelStyle!.color, c.accent);
        expect(chip.secondaryLabelStyle!.fontWeight, FontWeight.w500);
      });
    }

    test('ナビの寸法: 上 14 + カプセル 64 + 下 15 = 93、本文の確保は 93 + 28 = 121', () {
      expect(AppSizes.navCapsuleHeight, 64);
      expect(AppSizes.navTopPadding, 14);
      expect(AppSizes.navBottomOffset, 15);
      expect(AppSizes.navHorizontal, 17);
      expect(AppSizes.navReferenceHeight, 93);
      expect(AppSizes.navReservedReference, 121);
    });
  });
}
