import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/form_card.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/meal_estimation_confirm_view.dart';

const _estimation = MealEstimationResult(
  foods: [
    EstimatedFood(
        name: '鶏むね肉のグリル', calories: 320, proteinG: 30, fatG: 10, carbsG: 4),
    EstimatedFood(name: 'ごはん', calories: 280, proteinG: 4, fatG: 1, carbsG: 62),
  ],
  totals: EstimationTotals(calories: 640, proteinG: 38, fatG: 18, carbsG: 82),
);

Future<void> _pump(
  WidgetTester tester, {
  MealEstimationResult estimation = _estimation,
  ValueChanged<EstimationTotals>? onTotalsChanged,
  VoidCallback? onBack,
  VoidCallback? onSend,
  bool isSending = false,
  String? composedText = '#食事:昼食 鶏むね肉のグリル定食',
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(390, 1400) * 3;
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
          child: FormCard(
            child: MealEstimationConfirmView(
              estimation: estimation,
              totals: estimation.totals,
              composedText: composedText,
              appName: estimation.appName,
              warning: estimation.warning,
              isSending: isSending,
              onTotalsChanged: onTotalsChanged ?? (_) {},
              onBack: onBack ?? () {},
              onSend: onSend ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('「推定（目安）」と明記して、カロリーとたんぱく質・脂質・炭水化物を出す', (tester) async {
    await _pump(tester);

    expect(find.text('推定結果を確認'), findsOneWidget);
    expect(find.text('内容からの推定（目安）'), findsOneWidget);
    expect(find.bySemanticsLabel('640kcal'), findsOneWidget);
    expect(find.text('たんぱく質 38 g · 脂質 18 g · 炭水化物 82 g'), findsOneWidget);
    expect(find.text('・鶏むね肉のグリル（320 kcal）'), findsOneWidget);
    expect(find.text('送信される内容'), findsOneWidget);
    // 「AI」と断定しない
    expect(find.textContaining('AI'), findsNothing);
  });

  testWidgets('スクショ取込は「画面からの読み取り（目安）」とアプリ名・整合性の警告を出す', (tester) async {
    await _pump(
      tester,
      estimation: const MealEstimationResult(
        foods: [],
        totals: EstimationTotals(calories: 589, proteinG: 45, fatG: 12, carbsG: 60),
        appName: 'あすけん',
        warning: 'カロリーの画面とPFCの画面で合計が噛み合いません',
      ),
    );

    expect(find.text('画面からの読み取り（目安）'), findsOneWidget);
    expect(find.text('あすけん から読み取り'), findsOneWidget);
    expect(find.text('カロリーの画面とPFCの画面で合計が噛み合いません'), findsOneWidget);
  });

  testWidgets('「修正」で数値の入力欄が開き、直すと onTotalsChanged に渡る', (tester) async {
    EstimationTotals? latest;
    await _pump(tester, onTotalsChanged: (t) => latest = t);

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('修正'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('完了'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '700');
    await tester.pump();
    expect(latest?.calories, 700);
    expect(latest?.proteinG, 38);

    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('700kcal'), findsOneWidget);
  });

  testWidgets('戻る・送信のコールバック（送信は「この内容で送信」）', (tester) async {
    var back = 0;
    var sent = 0;
    await _pump(tester, onBack: () => back++, onSend: () => sent++);

    await tester.tap(find.text('戻る'));
    expect(back, 1);
    await tester.tap(find.text('この内容で送信'));
    expect(sent, 1);
  });

  testWidgets('送信中は文言を「送信しています…」にして押せない（二重送信を防ぐ）', (tester) async {
    var sent = 0;
    await _pump(tester, isSending: true, onSend: () => sent++);

    expect(find.text('送信しています…'), findsOneWidget);
    expect(find.text('この内容で送信'), findsNothing);
    await tester.tap(find.text('送信しています…'));
    expect(sent, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets('文字 1.35（${brightness.name}）でも横にはみ出さない・修正の入力欄は縦に積む', (tester) async {
      await _pump(tester, textScale: 1.35, brightness: brightness);
      await tester.tap(find.text('修正'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getTopLeft(find.byType(TextField).first);
      final second = tester.getTopLeft(find.byType(TextField).at(1));
      expect(second.dy, greaterThan(first.dy));
      expect(second.dx, first.dx);
    });
  }
}
