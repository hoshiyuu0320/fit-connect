import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_exercise_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../workout_test_helpers.dart';

/// 呼ばれた保存の記録を持つ、種目カードのテスト用ホスト
class _Recorder {
  final List<List<ActualSet>> saved = [];
}

Future<_Recorder> _pumpCard(
  WidgetTester tester, {
  String name = 'ラットプルダウン',
  int sets = 3,
  int reps = 12,
  double? weight = 30,
  String? memo,
  bool completed = false,
  List<ActualSet>? actual,
  String? trainerName = '田中',
  bool expanded = false,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 1200),
}) async {
  final recorder = _Recorder();
  await pumpWorkout(
    tester,
    Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: WorkoutExerciseCard(
          exerciseName: name,
          targetSets: sets,
          targetReps: reps,
          targetWeight: weight,
          memo: memo,
          isCompleted: completed,
          actualSets: actual,
          trainerName: trainerName,
          initiallyExpanded: expanded,
          onSetsUpdated: (s) => recorder.saved.add(List.of(s)),
        ),
      ),
    ),
    brightness: brightness,
    textScale: textScale,
    size: size,
  );
  return recorder;
}

void main() {
  group('WorkoutExerciseCard（閉じているとき）', () {
    testWidgets('完了マーク・種目名・「3セット × 12回 · 30 kg」・chevron-down だけが見える', (tester) async {
      await _pumpCard(tester);

      expect(find.text('ラットプルダウン'), findsOneWidget);
      expect(find.text('3セット × 12回 · 30 kg'), findsOneWidget);
      expect(find.byType(FcDoneMark), findsOneWidget);
      expect(tester.widget<FcDoneMark>(find.byType(FcDoneMark)).size, 26);
      // セットの行はまだ出ていない
      expect(find.text('セット1'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('重量の目標がなければ「セット × 回」まで', (tester) async {
      await _pumpCard(tester, weight: null);

      expect(find.text('3セット × 12回'), findsOneWidget);
      expect(find.textContaining(' kg'), findsNothing);
    });

    testWidgets('小数の重量は「22.5 kg」のように表示する', (tester) async {
      await _pumpCard(tester, weight: 22.5);

      expect(find.text('3セット × 12回 · 22.5 kg'), findsOneWidget);
    });

    testWidgets('完了した種目は、完了マークだけで示す（薄くしない・取り消し線も付けない）', (tester) async {
      await _pumpCard(tester, completed: true);

      expect(tester.widget<FcDoneMark>(find.byType(FcDoneMark)).done, isTrue);
      expect(find.byType(Opacity), findsNothing);
      final nameStyle = tester.widget<Text>(find.text('ラットプルダウン')).style!;
      expect(nameStyle.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('種目名は 17 / 500、補足は 13 / textSecondary', (tester) async {
      await _pumpCard(tester);

      final name = tester.widget<Text>(find.text('ラットプルダウン')).style!;
      expect(name.fontSize, 17);
      expect(name.fontWeight, FontWeight.w500);
      final detail = tester.widget<Text>(find.text('3セット × 12回 · 30 kg')).style!;
      expect(detail.fontSize, 13);
      expect(detail.color, AppColorsExtension.light.textSecondary);
    });

    testWidgets('カードの余白は 縦16・横20', (tester) async {
      await _pumpCard(tester);

      final card = tester.widget<FcCard>(find.byType(FcCard));
      expect(card.paddingOverride, const EdgeInsets.symmetric(horizontal: 20, vertical: 16));
    });
  });

  group('WorkoutExerciseCard（開閉）', () {
    testWidgets('見出しを押すと開き、もう一度押すと閉じる', (tester) async {
      await _pumpCard(tester);

      await tester.tap(find.text('ラットプルダウン'));
      await tester.pumpAndSettle();
      expect(find.text('セット1'), findsOneWidget);
      expect(find.text('セット2'), findsOneWidget);
      expect(find.text('セット3'), findsOneWidget);

      await tester.tap(find.text('ラットプルダウン'));
      await tester.pumpAndSettle();
      expect(find.text('セット1'), findsNothing);
    });

    testWidgets('chevron は開くと 180 度回る', (tester) async {
      await _pumpCard(tester);

      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0);
      await tester.tap(find.text('ラットプルダウン'));
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0.5);
    });

    testWidgets('initiallyExpanded なら最初から開いている', (tester) async {
      await _pumpCard(tester, expanded: true);

      expect(find.text('セット1'), findsOneWidget);
    });

    testWidgets('見出しの押せる範囲は 44 以上、開閉の状態を読み上げる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCard(tester);

      final header = find.bySemanticsLabel('ラットプルダウン、3セット × 12回 · 30 kg、未完了');
      expect(header, findsOneWidget);
      expect(tester.getSize(header).height, greaterThanOrEqualTo(44));
      Tristate expanded() => tester
          .getSemantics(find.bySemanticsLabel('ラットプルダウン、3セット × 12回 · 30 kg、未完了'))
          .getSemanticsData()
          .flagsCollection
          .isExpanded;
      expect(expanded(), Tristate.isFalse);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(expanded(), Tristate.isTrue);
      handle.dispose();
    });
  });

  group('WorkoutExerciseCard（セットの行）', () {
    testWidgets('「セットN」・重量欄(kg)・回数欄(回)・セット完了が並ぶ。重量が先', (tester) async {
      await _pumpCard(tester, expanded: true);

      expect(find.text('セット1'), findsOneWidget);
      expect(find.text('kg'), findsNWidgets(3));
      expect(find.text('回'), findsNWidgets(3));
      expect(find.byType(TextField), findsNWidgets(6));

      // 並び順: 左から 重量 → 回数
      final fields = find.byType(TextField);
      expect(
        tester.getTopLeft(fields.at(0)).dx,
        lessThan(tester.getTopLeft(fields.at(1)).dx),
      );
      final controllerTexts = [
        for (var i = 0; i < 2; i++) tester.widget<TextField>(fields.at(i)).controller!.text,
      ];
      expect(controllerTexts, ['30', '12']);
    });

    testWidgets('入力欄は 最小 高さ40・surface の面・1px の separator の枠・角丸12・空は「—」', (tester) async {
      await _pumpCard(
        tester,
        expanded: true,
        actual: const [
          ActualSet(setNumber: 1, reps: 0, weight: 0, done: false),
        ],
        sets: 1,
      );

      final colors = AppColorsExtension.light;
      final field = find.byType(TextField).first;
      final box = tester.widget<Container>(find.ancestor(
        of: field,
        matching: find.byType(Container),
      ).first);
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, colors.surface);
      expect(deco.borderRadius, BorderRadius.circular(12));
      expect((deco.border as Border).top.color, colors.separator);
      expect((deco.border as Border).top.width, 1);
      expect(box.constraints!.minHeight, 40);
      // 空のときは「—」
      expect(tester.widget<TextField>(field).decoration!.hintText, '—');
      // 押せる範囲は 44
      final tapArea = find.ancestor(of: field, matching: find.byType(GestureDetector)).first;
      expect(tester.getSize(tapArea).height, greaterThanOrEqualTo(44));
    });

    testWidgets('実績があればそれを表示する（重量・回数・完了）', (tester) async {
      await _pumpCard(
        tester,
        expanded: true,
        actual: const [
          ActualSet(setNumber: 1, reps: 12, weight: 30, done: true),
          ActualSet(setNumber: 2, reps: 10, weight: 27.5, done: true),
          ActualSet(setNumber: 3, reps: 0, weight: 30, done: false),
        ],
      );

      final fields = find.byType(TextField);
      String text(int i) => tester.widget<TextField>(fields.at(i)).controller!.text;
      expect([text(0), text(1)], ['30', '12']);
      expect([text(2), text(3)], ['27.5', '10']);
      expect([text(4), text(5)], ['30', '']); // 回数 0 は空（—）
    });

    testWidgets('セット完了を押すと切り替わり、保存の通知が出る（見た目は完了マーク 28）', (tester) async {
      final recorder = await _pumpCard(tester, expanded: true);

      final marks = find.byWidgetPredicate((w) => w is FcDoneMark && w.size == 28);
      expect(marks, findsNWidgets(3));
      expect(tester.widget<FcDoneMark>(marks.first).done, isFalse);

      await tester.tap(marks.first);
      await tester.pumpAndSettle();

      expect(tester.widget<FcDoneMark>(marks.first).done, isTrue);
      expect(recorder.saved, hasLength(1));
      expect(recorder.saved.single.map((s) => s.done), [true, false, false]);

      // もう一度押すと未完了に戻る
      await tester.tap(marks.first);
      await tester.pumpAndSettle();
      expect(recorder.saved.last.map((s) => s.done), [false, false, false]);
    });

    testWidgets('セット完了の押せる範囲は 44×44 以上、「セット1 完了」のように何セット目かを読み上げる', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpCard(tester, expanded: true, actual: const [
        ActualSet(setNumber: 1, reps: 12, weight: 30, done: true),
        ActualSet(setNumber: 2, reps: 12, weight: 30, done: false),
        ActualSet(setNumber: 3, reps: 12, weight: 30, done: false),
      ]);

      final done = find.bySemanticsLabel('セット1 完了');
      expect(done, findsOneWidget);
      expect(find.bySemanticsLabel('セット2 未完了'), findsOneWidget);
      expect(find.bySemanticsLabel('セット3 未完了'), findsOneWidget);
      // 番号のない読み上げは残さない
      expect(find.bySemanticsLabel('セット完了'), findsNothing);
      expect(find.bySemanticsLabel('セット未完了'), findsNothing);
      final size = tester.getSize(done);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(done).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );

      // 押すと読み上げも切り替わる
      await tester.tap(find.bySemanticsLabel('セット2 未完了'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('セット2 完了'), findsOneWidget);
      expect(find.bySemanticsLabel('セット2 未完了'), findsNothing);
      handle.dispose();
    });

    testWidgets('重量・回数を入力して欄を離れると保存の通知が出る', (tester) async {
      final recorder = await _pumpCard(tester, expanded: true);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '35.5');
      expect(recorder.saved, isEmpty); // 入力中はまだ保存しない
      await tester.enterText(fields.at(1), '8'); // 重量欄を離れた
      expect(recorder.saved, hasLength(1));
      expect(recorder.saved.single.first.weight, 35.5);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(recorder.saved, isNotEmpty);
      final first = recorder.saved.last.first;
      expect(first.weight, 35.5);
      expect(first.reps, 8);
      expect(first.done, isFalse);
    });

    testWidgets('入力してからセット完了を押すと、入力した値で保存される', (tester) async {
      final recorder = await _pumpCard(tester, expanded: true);

      await tester.enterText(find.byType(TextField).at(0), '40');
      await tester.tap(
        find.byWidgetPredicate((w) => w is FcDoneMark && w.size == 28).first,
      );
      await tester.pumpAndSettle();

      expect(recorder.saved.last.first.weight, 40);
      expect(recorder.saved.last.first.done, isTrue);
    });

    testWidgets('重量・回数の欄は数字（と小数点）しか入力できない', (tester) async {
      await _pumpCard(tester, expanded: true);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '12abc.5');
      await tester.enterText(fields.at(1), '1x2');
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, '12.5');
      expect(tester.widget<TextField>(fields.at(1)).controller!.text, '12');
    });
  });

  group('WorkoutExerciseCard（トレーナーのメモ）', () {
    testWidgets('開くと「{名前}トレーナーのメモ」と本文が出る（閉じているときは出ない）', (tester) async {
      await _pumpCard(tester, memo: '肘を後ろに引く意識で、反動を使わずに。');

      expect(find.text('田中トレーナーのメモ'), findsNothing);
      await tester.tap(find.text('ラットプルダウン'));
      await tester.pumpAndSettle();

      expect(find.text('田中トレーナーのメモ'), findsOneWidget);
      expect(find.text('肘を後ろに引く意識で、反動を使わずに。'), findsOneWidget);
      // 囲みは surfaceSecondary・角丸 12
      final box = find.byType(FcInfoBox);
      expect(box, findsOneWidget);
      final title = tester.widget<Text>(find.text('田中トレーナーのメモ')).style!;
      expect(title.fontSize, 13);
      expect(title.fontWeight, FontWeight.w500);
    });

    testWidgets('名前が「田中」でも「田中トレーナー」でも「田中トレーナーのメモ」（二重にならない）', (tester) async {
      for (final raw in ['田中', '田中トレーナー']) {
        await _pumpCard(tester, memo: 'ゆっくり', trainerName: raw, expanded: true);

        expect(find.text('田中トレーナーのメモ'), findsOneWidget, reason: raw);
        expect(find.textContaining('トレーナートレーナー'), findsNothing, reason: raw);
      }
    });

    testWidgets('名前が取れていなければ「トレーナーのメモ」', (tester) async {
      await _pumpCard(tester, memo: 'ゆっくり', trainerName: null, expanded: true);

      expect(find.text('トレーナーのメモ'), findsOneWidget);
    });

    testWidgets('メモがなければ囲みは出ない', (tester) async {
      await _pumpCard(tester, expanded: true);

      expect(find.byType(FcInfoBox), findsNothing);
    });
  });

  group('WorkoutExerciseCard（見た目の状態）', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}・文字 1.35 倍でも開いた状態ではみ出さない（390 幅）', (tester) async {
        await _pumpCard(
          tester,
          expanded: true,
          memo: '肘を後ろに引く意識で、反動を使わずに。',
          brightness: brightness,
          textScale: 1.35,
          size: const Size(390, 1600),
        );

        expect(tester.takeException(), isNull);
        // 文字を大きくしたら、欄は縮まず折り返して縦に積む（セット 1 の 2 つの欄が縦に並ぶ）
        final fields = find.byType(TextField);
        expect(
          tester.getTopLeft(fields.at(1)).dy,
          greaterThan(tester.getTopLeft(fields.at(0)).dy),
        );
      });
    }

    testWidgets('通常幅・通常の文字では、重量欄と回数欄が 1 行に並ぶ', (tester) async {
      await _pumpCard(tester, expanded: true);

      final fields = find.byType(TextField);
      expect(
        tester.getTopLeft(fields.at(1)).dy,
        tester.getTopLeft(fields.at(0)).dy,
      );
    });
  });
}
