import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/structured_tag_form.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録フォーム（体重・食事・運動）。正本 `MealForm` の作り（カード・見出し・区分・入力・「入力欄に入れる」）
Future<void> _pump(
  WidgetTester tester,
  Widget form, {
  bool aiEnabled = false,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(390, 1400) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiFeaturesEnabledProvider.overrideWith((ref) async => aiEnabled),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: c!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: form)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('WeightTagForm', () {
    testWidgets('見出し「体重を記録」・体重（kg）・コメント・「入力欄に入れる」', (tester) async {
      await _pump(tester, WeightTagForm(onCompose: (_) {}, onClose: () {}));

      expect(find.text('体重を記録'), findsOneWidget);
      expect(find.text('体重'), findsOneWidget); // 入力欄のラベル
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('ひとことコメント（任意）'), findsOneWidget);
      expect(find.text('入力欄に入る内容'), findsOneWidget);
      expect(find.text('入力欄に入れる'), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsOneWidget);
    });

    testWidgets('範囲外・空のあいだは「入力欄に入れる」を押せない（opacity 0.4）', (tester) async {
      var composed = 0;
      await _pump(
          tester, WeightTagForm(onCompose: (_) => composed++, onClose: () {}));

      Opacity buttonOpacity() => tester.widget<Opacity>(find
          .ancestor(
              of: find.text('入力欄に入れる'), matching: find.byType(Opacity))
          .first);
      expect(buttonOpacity().opacity, 0.4);
      await tester.tap(find.text('入力欄に入れる'));
      expect(composed, 0);

      await tester.enterText(find.widgetWithText(TextField, '65.5'), '5');
      await tester.pump();
      await tester.tap(find.text('入力欄に入れる'));
      expect(composed, 0);
    });

    testWidgets('体重とコメントから `#体重 62.4kg …` を組み立てて渡す', (tester) async {
      String? composed;
      await _pump(
          tester, WeightTagForm(onCompose: (t) => composed = t, onClose: () {}));

      await tester.enterText(find.widgetWithText(TextField, '65.5'), '62.4');
      await tester.enterText(
          find.byType(TextField).last, '朝の計測。昨日より少し減りました');
      await tester.pump();
      expect(find.textContaining('朝の計測。昨日より少し減りました'), findsWidgets);

      await tester.tap(find.text('入力欄に入れる'));
      expect(composed, '#体重 62.4kg 朝の計測。昨日より少し減りました');
    });

    testWidgets('「入力欄に入る内容」のタグは accent、本文は textPrimary', (tester) async {
      await _pump(
        tester,
        WeightTagForm(
            onCompose: (_) {}, onClose: () {}, debugInitialWeight: '62.4'),
      );
      final rich = tester.widget<RichText>(
          find.textContaining('#体重', findRichText: true).first);
      TextSpan? tagSpan;
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == '#体重') tagSpan = span;
        return true;
      });
      expect(tagSpan, isNotNull);
      expect(tagSpan!.style?.color, AppColorsExtension.light.accent);
    });

    testWidgets('閉じる（×）は 44×44 以上で onClose を呼ぶ', (tester) async {
      var closed = 0;
      await _pump(
          tester, WeightTagForm(onCompose: (_) {}, onClose: () => closed++));
      final close = find.bySemanticsLabel('閉じる');
      expect(tester.getSize(close).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
      await tester.tap(close);
      expect(closed, 1);
    });
  });

  group('MealTagForm', () {
    testWidgets('区分（朝食・昼食・夕食・間食）の FcSegmentedControl と内容・写真の追加', (tester) async {
      await _pump(
        tester,
        MealTagForm(onCompose: (_) {}, onClose: () {}, onPickImage: () {}),
      );

      expect(find.text('食事を記録'), findsOneWidget);
      expect(find.byType(FcSegmentedControl<String>), findsOneWidget);
      for (final label in ['朝食', '昼食', '夕食', '間食']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('内容'), findsOneWidget);
      // 写真の「追加」は 72×72
      expect(tester.getSize(find.bySemanticsLabel('写真を追加')),
          const Size(72, 72));
    });

    testWidgets('区分と内容から `#食事:昼食 …` を組み立てて渡す', (tester) async {
      String? composed;
      await _pump(
          tester, MealTagForm(onCompose: (t) => composed = t, onClose: () {}));

      await tester.tap(find.text('昼食'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, '食事内容やコメントを入力'), '鶏むね肉のグリル定食');
      await tester.pump();
      expect(find.text('入力欄に入る内容'), findsOneWidget);

      await tester.tap(find.text('入力欄に入れる'));
      expect(composed, '#食事:昼食 鶏むね肉のグリル定食');
    });

    testWidgets('推定が使えないプランでは推定ボックスを出さない', (tester) async {
      await _pump(tester, MealTagForm(onCompose: (_) {}, onClose: () {}));
      expect(find.textContaining('推定'), findsNothing);
      expect(find.text('料理を記録'), findsNothing);
    });

    testWidgets('推定が使えるプランでは「推定（目安）」の囲みと「推定する」を出す', (tester) async {
      await _pump(
        tester,
        MealTagForm(
            onCompose: (_) {}, onClose: () {}, debugInitialContent: '鶏むね肉'),
        aiEnabled: true,
      );

      expect(find.text('内容からの推定（目安）'), findsOneWidget);
      expect(find.text('推定する'), findsOneWidget);
      expect(find.text('料理を記録'), findsOneWidget);
      expect(find.text('他アプリから取込'), findsOneWidget);
      // 囲みは surfaceSecondary・角丸 12
      final box = tester.widget<DecoratedBox>(find
          .ancestor(of: find.text('内容からの推定（目安）'), matching: find.byType(DecoratedBox))
          .first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, AppColorsExtension.light.surfaceSecondary);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      // 「入力欄に入れる」は推定なしで入れる操作として残る
      expect(find.text('入力欄に入れる'), findsOneWidget);
    });

    testWidgets('スクショ取込モードは「スクショを解析」（写真が無いと押せない）', (tester) async {
      await _pump(
        tester,
        MealTagForm(
          onCompose: (_) {},
          onClose: () {},
          debugInitialScreenshotMode: true,
          onSendWithEstimation: (_, __, ___) async {},
        ),
        aiEnabled: true,
      );

      expect(find.text('スクショを解析'), findsOneWidget);
      expect(find.text('スクショ画像を追加してください'), findsOneWidget);
      expect(find.text('送信される内容'), findsOneWidget);
      expect(find.textContaining('PFCも記録され精度が上がります'), findsOneWidget);
      expect(find.text('入力欄に入れる'), findsNothing);
    });

    testWidgets('文字 1.35・ダークでも横にはみ出さない', (tester) async {
      await _pump(
        tester,
        MealTagForm(
            onCompose: (_) {}, onClose: () {}, debugInitialContent: '鶏むね肉のグリル定食'),
        aiEnabled: true,
        textScale: 1.35,
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ExerciseTagForm', () {
    testWidgets('種類（筋トレ・有酸素）・内容・時間・消費カロリー', (tester) async {
      await _pump(tester, ExerciseTagForm(onCompose: (_) {}, onClose: () {}));

      expect(find.text('運動を記録'), findsOneWidget);
      expect(find.text('筋トレ'), findsOneWidget);
      expect(find.text('有酸素'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      expect(find.text('時間（任意）'), findsOneWidget);
      expect(find.text('消費カロリー（任意）'), findsOneWidget);
      expect(find.text('分'), findsOneWidget);
      expect(find.text('kcal'), findsOneWidget);
    });

    testWidgets('`#運動:有酸素 ランニング 30分 250kcal` を組み立てて渡す', (tester) async {
      String? composed;
      await _pump(tester,
          ExerciseTagForm(onCompose: (t) => composed = t, onClose: () {}));

      await tester.tap(find.text('有酸素'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, '運動内容やコメントを入力'), 'ランニング');
      await tester.enterText(find.widgetWithText(TextField, '30'), '30');
      await tester.enterText(find.widgetWithText(TextField, '150'), '250');
      await tester.pump();

      await tester.tap(find.text('入力欄に入れる'));
      expect(composed, '#運動:有酸素 ランニング 30分 250kcal');
    });

    testWidgets('文字 1.35 では時間とカロリーを縦に積む（はみ出さない）', (tester) async {
      await _pump(tester, ExerciseTagForm(onCompose: (_) {}, onClose: () {}),
          textScale: 1.35);
      expect(tester.takeException(), isNull);
      final minutes = tester.getTopLeft(find.text('時間（任意）'));
      final kcal = tester.getTopLeft(find.text('消費カロリー（任意）'));
      expect(kcal.dy, greaterThan(minutes.dy));
      expect(kcal.dx, minutes.dx);
    });
  });

  testWidgets('StructuredTagForm は formType で出し分ける', (tester) async {
    for (final (type, title) in [
      ('weight', '体重を記録'),
      ('meal', '食事を記録'),
      ('exercise', '運動を記録'),
    ]) {
      await _pump(
        tester,
        StructuredTagForm(formType: type, onCompose: (_) {}, onClose: () {}),
      );
      expect(find.text(title), findsOneWidget);
    }
  });
}
