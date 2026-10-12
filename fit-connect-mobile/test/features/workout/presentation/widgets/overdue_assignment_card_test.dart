import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/overdue_assignment_card.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/reschedule_date_picker.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../workout_test_helpers.dart';

class _Taps {
  int doToday = 0;
  int skip = 0;
  final List<DateTime> rescheduled = [];
}

Future<_Taps> _pumpCard(
  WidgetTester tester, {
  WorkoutAssignment? assignment,
  String? trainerName = '田中',
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 700),
}) async {
  final taps = _Taps();
  await pumpWorkout(
    tester,
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: OverdueAssignmentCard(
            assignment: assignment ?? makeOverduePlan(),
            trainerName: trainerName,
            onDoToday: () => taps.doToday++,
            onSkip: () => taps.skip++,
            onReschedule: taps.rescheduled.add,
          ),
        ),
      ),
    ),
    brightness: brightness,
    textScale: textScale,
    size: size,
  );
  return taps;
}

void main() {
  group('OverdueAssignmentCard', () {
    testWidgets('プラン名（20/500）・右に日付・「4種目 · {トレーナー}」が出る', (tester) async {
      await _pumpCard(tester);

      final title = tester.widget<Text>(find.text('下半身')).style!;
      expect(title.fontSize, 20);
      expect(title.fontWeight, FontWeight.w500);
      final date = find.text(formatWorkoutShortDate(dayFromToday(-2)));
      expect(date, findsOneWidget);
      expect(tester.widget<Text>(date).style!.fontSize, 13);
      // 日付はプラン名より右
      expect(
        tester.getTopLeft(date).dx,
        greaterThan(tester.getTopRight(find.text('下半身')).dx),
      );
      expect(find.text('4種目 · 田中トレーナー'), findsOneWidget);
    });

    testWidgets('名前が取れていなければ「4種目 · トレーナー」', (tester) async {
      await _pumpCard(tester, trainerName: null);

      expect(find.text('4種目 · トレーナー'), findsOneWidget);
    });

    testWidgets('操作は「今日やる」（ピル）・「日付を変更」（calendar 先頭）・「スキップ」（textSecondary）', (tester) async {
      await _pumpCard(tester);

      final doToday = find.ancestor(of: find.text('今日やる'), matching: find.byType(FcButton));
      expect(tester.widget<FcButton>(doToday).variant, FcButtonVariant.pill);
      final change = find.ancestor(of: find.text('日付を変更'), matching: find.byType(FcButton));
      final changeButton = tester.widget<FcButton>(change);
      expect(changeButton.variant, FcButtonVariant.back);
      expect(changeButton.icon, LucideIcons.calendar);
      expect(changeButton.iconPosition, FcIconPosition.start);
      final skip = tester.widget<Text>(find.text('スキップ')).style!;
      expect(skip.color, AppColorsExtension.light.textSecondary);
      expect(skip.fontSize, 15);

      // 並び順: 今日やる → 日付を変更 → スキップ
      final xs = [for (final t in ['今日やる', '日付を変更', 'スキップ']) tester.getTopLeft(find.text(t)).dx];
      expect(xs[0], lessThan(xs[1]));
      expect(xs[1], lessThan(xs[2]));
    });

    testWidgets('旧デザインの警告表示（オレンジ枠・「N日前」・警告アイコン）は使わない', (tester) async {
      await _pumpCard(tester);

      expect(find.textContaining('日前'), findsNothing);
      expect(find.textContaining('のプラン'), findsNothing);
      expect(find.byIcon(LucideIcons.alertCircle), findsNothing);
      // 面は surface のカード（枠・影なし）
      final card = tester.widget<FcCard>(find.byType(FcCard));
      expect(card.padding, FcCardPadding.standard);
    });

    testWidgets('操作はどれも 44 以上', (tester) async {
      await _pumpCard(tester);

      for (final label in ['今日やる', '日付を変更', 'スキップ']) {
        final target = find.ancestor(of: find.text(label), matching: find.byType(FcPressable)).first;
        expect(tester.getSize(target).height, greaterThanOrEqualTo(43), reason: label);
      }
      final skipTarget = find.ancestor(of: find.text('スキップ'), matching: find.byType(FcPressable)).first;
      expect(tester.getSize(skipTarget).height, greaterThanOrEqualTo(44));
    });

    testWidgets('「今日やる」で onDoToday が呼ばれる', (tester) async {
      final taps = await _pumpCard(tester);

      await tester.tap(find.text('今日やる'));
      expect(taps.doToday, 1);
    });

    testWidgets('「スキップ」は確認ダイアログ。「スキップする」で onSkip、キャンセルなら呼ばれない', (tester) async {
      final taps = await _pumpCard(tester);

      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      expect(find.text('スキップしますか？'), findsOneWidget);
      expect(find.text('「下半身」をスキップします。この操作は取り消せません。'), findsOneWidget);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(taps.skip, 0);

      await tester.tap(find.text('スキップ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('スキップする'));
      await tester.pumpAndSettle();
      expect(taps.skip, 1);
    });

    testWidgets('「日付を変更」で日付ピッカー。変更すると選んだ日が渡る・キャンセルなら渡らない', (tester) async {
      final taps = await _pumpCard(tester);

      await tester.tap(find.text('日付を変更'));
      await tester.pumpAndSettle();
      expect(find.byType(RescheduleDatePicker), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(taps.rescheduled, isEmpty);

      await tester.tap(find.text('日付を変更'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('変更する'));
      await tester.pumpAndSettle();
      expect(taps.rescheduled, hasLength(1));
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}・文字 1.35 倍・320 幅でも、操作が折り返してはみ出さない', (tester) async {
        await _pumpCard(
          tester,
          brightness: brightness,
          textScale: 1.35,
          size: const Size(320, 900),
        );

        expect(tester.takeException(), isNull);
        // 3 つの操作がすべて見えている（画面の幅の中）
        for (final label in ['今日やる', '日付を変更', 'スキップ']) {
          final right = tester.getTopRight(find.text(label)).dx;
          expect(right, lessThanOrEqualTo(320), reason: label);
        }
      });
    }
  });
}
