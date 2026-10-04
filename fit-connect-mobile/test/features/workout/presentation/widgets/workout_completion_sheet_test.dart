import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_completion_overlay.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_sheet_handle.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../workout_test_helpers.dart';

/// 送信の呼ばれ方を記録する
class _Submits {
  final List<({String? feedback, int? calories})> calls = [];
  Object? error;
  Completer<void>? hold;
  bool? result;
  bool closed = false;
}

/// 「開く」ボタンからシートを開く（実際の画面と同じ showModalBottomSheet 経由）
Future<_Submits> _openSheet(
  WidgetTester tester, {
  String? trainerName = '田中',
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  Object? error,
  Completer<void>? hold,
}) async {
  final submits = _Submits()
    ..error = error
    ..hold = hold;
  await pumpWorkout(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FcButton.pill(
            label: '開く',
            onPressed: () async {
              submits.result = await showWorkoutCompletionSheet(
                context,
                planTitle: '上半身',
                exerciseCount: 3,
                date: DateTime(2026, 9, 13),
                trainerName: trainerName,
                onSubmit: (feedback, calories) async {
                  submits.calls.add((feedback: feedback, calories: calories));
                  if (submits.hold != null) await submits.hold!.future;
                  if (submits.error != null) throw submits.error!;
                },
              );
              submits.closed = true;
            },
          ),
        ),
      ),
    ),
    brightness: brightness,
    textScale: textScale,
    size: size,
  );
  await tester.tap(find.text('開く'));
  await tester.pumpAndSettle();
  return submits;
}

void main() {
  group('完了の報告シート（見た目）', () {
    testWidgets('見出し・「上半身 · 3種目 · 9月13日（日）」・2つの入力・説明・ボタンが並ぶ', (tester) async {
      await _openSheet(tester);

      expect(find.text('完了を報告'), findsOneWidget);
      expect(find.text('上半身 · 3種目 · 9月13日（日）'), findsOneWidget);
      expect(find.text('感想・コンディション（任意）'), findsOneWidget);
      expect(find.text('消費カロリー（任意）'), findsOneWidget);
      expect(find.text('kcal'), findsOneWidget);
      expect(find.text('報告はメッセージとして田中トレーナーに届きます。'), findsOneWidget);
      expect(find.text('田中トレーナーに報告する'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      // 入力は FcTextField（感想は複数行・消費カロリーは数値）
      expect(find.byType(FcTextField), findsNWidgets(2));
      expect(tester.widget<FcTextField>(find.byType(FcTextField).at(1)).numeric, isTrue);
    });

    testWidgets('お祝いの演出（紙吹雪・拍手・大きな完了表示）は出さない', (tester) async {
      await _openSheet(tester);

      expect(find.byType(ConfettiWidget), findsNothing);
      expect(find.textContaining('ワークアウト完了'), findsNothing);
      expect(find.textContaining('お疲れ様'), findsNothing);
      expect(find.textContaining('👏'), findsNothing);
      expect(find.textContaining('🎉'), findsNothing);
    });

    testWidgets('名前が取れていなければ「トレーナー」を使う', (tester) async {
      await _openSheet(tester, trainerName: null);

      expect(find.text('報告はメッセージとしてトレーナーに届きます。'), findsOneWidget);
      expect(find.text('トレーナーに報告する'), findsOneWidget);
    });

    testWidgets('ハンドルは 36×5・見出しは 20/500・面は surface・上の角丸は 23', (tester) async {
      await _openSheet(tester);

      expect(
        tester.getSize(find.descendant(
          of: find.byType(WorkoutSheetHandle),
          matching: find.byType(Container),
        )),
        const Size(36, 5),
      );
      final title = tester.widget<Text>(find.text('完了を報告')).style!;
      expect(title.fontSize, 20);
      expect(title.fontWeight, FontWeight.w500);

      // 実際に描かれる面（シートの Material）
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(BottomSheet), matching: find.byType(Material)).first,
      );
      expect(material.color, AppColorsExtension.light.surface);
      expect(
        (material.shape as RoundedRectangleBorder).borderRadius,
        const BorderRadius.vertical(top: Radius.circular(23)),
      );
    });

    testWidgets('余白は 上10・左右20（下は 30 以上）', (tester) async {
      await _openSheet(tester);

      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(of: find.byType(WorkoutCompletionSheet), matching: find.byType(SingleChildScrollView)),
      );
      final padding = scroll.padding as EdgeInsets;
      expect(padding.top, 10);
      expect(padding.left, 20);
      expect(padding.right, 20);
      expect(padding.bottom, greaterThanOrEqualTo(30));
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}・文字 1.35 倍でもはみ出さない', (tester) async {
        await _openSheet(
          tester,
          brightness: brightness,
          textScale: 1.35,
          size: const Size(390, 1400),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('田中トレーナーに報告する'), findsOneWidget);
      });
    }
  });

  group('完了の報告シート（操作）', () {
    testWidgets('感想と消費カロリーを入れて報告すると、その内容で送られてシートが閉じる', (tester) async {
      final submits = await _openSheet(tester);

      await tester.enterText(find.byType(TextField).at(0), '肩の動きがよくなってきました。');
      await tester.enterText(find.byType(TextField).at(1), '280');
      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();

      expect(submits.calls, hasLength(1));
      expect(submits.calls.single.feedback, '肩の動きがよくなってきました。');
      expect(submits.calls.single.calories, 280);
      expect(submits.closed, isTrue);
      expect(submits.result, isTrue);
      expect(find.byType(WorkoutCompletionSheet), findsNothing);
    });

    testWidgets('何も入れなくても報告できる（感想は空、消費カロリーは null）', (tester) async {
      final submits = await _openSheet(tester);

      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();

      expect(submits.calls.single.feedback, '');
      expect(submits.calls.single.calories, isNull);
      expect(submits.result, isTrue);
    });

    testWidgets('消費カロリーは数字しか入力できない', (tester) async {
      await _openSheet(tester);

      await tester.enterText(find.byType(TextField).at(1), '2a8.0');
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, '280');
    });

    testWidgets('キャンセルは何も送らずに閉じる', (tester) async {
      final submits = await _openSheet(tester);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(submits.calls, isEmpty);
      expect(submits.result, isFalse);
      expect(find.byType(WorkoutCompletionSheet), findsNothing);
    });

    testWidgets('送信中は「処理しています…」になり、二重に送れない・キャンセルも効かない', (tester) async {
      final hold = Completer<void>();
      final submits = await _openSheet(tester, hold: hold);

      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pump();

      expect(find.text('処理しています…'), findsOneWidget);
      expect(find.text('田中トレーナーに報告する'), findsNothing);
      await tester.tap(find.text('処理しています…'));
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      expect(submits.calls, hasLength(1));
      expect(find.byType(WorkoutCompletionSheet), findsOneWidget);

      hold.complete();
      await tester.pumpAndSettle();
      expect(submits.result, isTrue);
      expect(find.byType(WorkoutCompletionSheet), findsNothing);
    });

    testWidgets('送れなかったときは閉じずに入力を残し、理由を文字で示す', (tester) async {
      final submits = await _openSheet(tester, error: Exception('network'));

      await tester.enterText(find.byType(TextField).at(0), '重かった');
      await tester.enterText(find.byType(TextField).at(1), '300');
      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutCompletionSheet), findsOneWidget);
      expect(submits.closed, isFalse);
      expect(find.byType(FcInlineNotice), findsOneWidget);
      expect(find.textContaining('報告できませんでした'), findsOneWidget);
      // 入力はそのまま・もう一度押せる
      expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '重かった');
      expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, '300');
      expect(find.text('田中トレーナーに報告する'), findsOneWidget);

      await tester.tap(find.text('田中トレーナーに報告する'));
      await tester.pumpAndSettle();
      expect(submits.calls, hasLength(2));
    });

    testWidgets('操作は 44 以上: 報告ボタン（48）・キャンセル（44）', (tester) async {
      await _openSheet(tester);

      final report = find.ancestor(
        of: find.text('田中トレーナーに報告する'),
        matching: find.byType(FcButton),
      );
      expect(tester.getSize(report).height, greaterThanOrEqualTo(48));
      final cancel = find.ancestor(of: find.text('キャンセル'), matching: find.byType(FcPressable));
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    });
  });
}
