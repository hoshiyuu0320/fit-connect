import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_progress_bar.dart';

import '../workout_test_helpers.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required int completed,
  required int total,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 300),
}) {
  return pumpWorkout(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: WorkoutProgressBar(completed: completed, total: total),
        ),
      ),
    ),
    brightness: brightness,
    textScale: textScale,
    size: size,
  );
}

double _fillRatio(WidgetTester tester, Color trackColor) {
  final fill = find.byKey(const ValueKey('workout-progress-fill'));
  final track = find.ancestor(
    of: fill,
    matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == trackColor),
  );
  return tester.getSize(fill).width / tester.getSize(track).width;
}

void main() {
  group('WorkoutProgressBar', () {
    testWidgets('「進み具合」と「1 / 3 種目」。数字は桁幅をそろえる', (tester) async {
      await _pumpBar(tester, completed: 1, total: 3);

      expect(find.text('進み具合'), findsOneWidget);
      final count = tester.widget<Text>(find.text('1 / 3 種目')).style!;
      expect(count.fontSize, 12);
      expect(count.fontFeatures, contains(const FontFeature.tabularFigures()));
      // 旧デザインの「1/3種目完了」「✓」は使わない
      expect(find.textContaining('種目完了'), findsNothing);
    });

    testWidgets('バーは 高さ4・角丸2・surfaceSecondary の地に accent の塗り', (tester) async {
      await _pumpBar(tester, completed: 1, total: 3);

      final colors = AppColorsExtension.light;
      final fill = find.byKey(const ValueKey('workout-progress-fill'));
      expect(tester.widget<ColoredBox>(fill).color, colors.accent);
      final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(2));
      expect(tester.getSize(find.byType(ClipRRect)).height, 4);
      expect(_fillRatio(tester, colors.surfaceSecondary), closeTo(1 / 3, 0.01));
    });

    testWidgets('進み具合に応じて塗りの長さが変わる。完了しても色は変えない', (tester) async {
      final colors = AppColorsExtension.light;

      await _pumpBar(tester, completed: 0, total: 3);
      expect(_fillRatio(tester, colors.surfaceSecondary), 0);

      await _pumpBar(tester, completed: 2, total: 3);
      expect(_fillRatio(tester, colors.surfaceSecondary), closeTo(2 / 3, 0.01));

      await _pumpBar(tester, completed: 3, total: 3);
      expect(_fillRatio(tester, colors.surfaceSecondary), 1);
      expect(
        tester.widget<ColoredBox>(find.byKey(const ValueKey('workout-progress-fill'))).color,
        colors.accent,
      );
    });

    testWidgets('ダークでは dark の surfaceSecondary と accent', (tester) async {
      await _pumpBar(tester, completed: 1, total: 3, brightness: Brightness.dark);

      final colors = AppColorsExtension.dark;
      expect(
        tester.widget<ColoredBox>(find.byKey(const ValueKey('workout-progress-fill'))).color,
        colors.accent,
      );
      expect(_fillRatio(tester, colors.surfaceSecondary), closeTo(1 / 3, 0.01));
    });

    testWidgets('種目が 0 件でも落ちない（塗りは 0）', (tester) async {
      await _pumpBar(tester, completed: 0, total: 0);

      expect(tester.takeException(), isNull);
      expect(find.text('0 / 0 種目'), findsOneWidget);
    });

    testWidgets('完了数が総数を超えても塗りは枠の中', (tester) async {
      await _pumpBar(tester, completed: 5, total: 3);

      expect(_fillRatio(tester, AppColorsExtension.light.surfaceSecondary), 1);
    });

    testWidgets('読み上げは「進み具合 1 / 3 種目」', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpBar(tester, completed: 1, total: 3);

      expect(find.bySemanticsLabel('進み具合 1 / 3 種目'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('文字 1.35 倍・320 幅でもはみ出さない', (tester) async {
      await _pumpBar(
        tester,
        completed: 1,
        total: 3,
        textScale: 1.35,
        size: const Size(320, 300),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
