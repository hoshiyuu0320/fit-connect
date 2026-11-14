import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/presentation/widgets/reminder_time_picker_sheet.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録のリマインダーの時刻を選ぶシート（showReminderTimePickerSheet）のテスト。
///
/// ホイールは読み上げの操作（increase / decrease。VoiceOver の上下スワイプと同じ）と
/// ドラッグで回し、「決定」「キャンセル」で返る値を確かめる。
void main() {
  /// 開いたシートの結果（「決定」「キャンセル」で終わる）
  late Future<ReminderTime?> result;

  Future<void> openSheet(
    WidgetTester tester, {
    ReminderTime initial = const ReminderTime(hour: 20, minute: 0),
    ThemeData? theme,
    double textScale = 1.0,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  result = showReminderTimePickerSheet(
                    context,
                    initial: initial,
                    title: '夕食の時刻',
                  );
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
  }

  Finder wheelText(String text) => find.descendant(
        of: find.byType(CupertinoDatePicker),
        matching: find.text(text),
      );

  /// 時のホイール（左の列）の項目（分のホイールにも「20」があるので列で絞る）
  Finder hourText(String text) => find.descendant(
        of: find.byType(CupertinoPicker).first,
        matching: find.text(text),
      );

  group('ReminderTimePickerSheet 構成', () {
    testWidgets('見出し・24 時間表記で5分刻みの時刻のホイール・キャンセル・決定が出る', (tester) async {
      await openSheet(tester);

      expect(find.text('夕食の時刻'), findsOneWidget);
      final picker =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(picker.mode, CupertinoDatePickerMode.time);
      expect(picker.use24hFormat, isTrue);
      expect(picker.minuteInterval, 5);
      expect(picker.initialDateTime.hour, 20);
      expect(picker.initialDateTime.minute, 0);
      // 午前・午後の列は無い
      expect(wheelText('AM'), findsNothing);
      expect(wheelText('PM'), findsNothing);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('決定'), findsOneWidget);
      // Material の時刻の選択（英語）は使わない
      expect(find.byType(TimePickerDialog), findsNothing);
    });

    testWidgets('「キャンセル」と「決定」は fc のボタンで、押せる範囲は 44 以上', (tester) async {
      await openSheet(tester, textScale: 1.35);

      expect(tester.takeException(), isNull);
      for (final label in ['キャンセル', '決定']) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byType(FcButton),
        );
        expect(button, findsOneWidget, reason: label);
        final size = tester.getSize(button);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });
  });

  group('ReminderTimePickerSheet 返す値', () {
    testWidgets('「キャンセル」は null', (tester) async {
      await openSheet(tester);

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testWidgets('シートの外を押して閉じても null', (tester) async {
      await openSheet(tester);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });

    testWidgets('回さずに「決定」は開いたときの時刻', (tester) async {
      await openSheet(
        tester,
        initial: const ReminderTime(hour: 7, minute: 30),
      );

      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(await result, const ReminderTime(hour: 7, minute: 30));
    });

    testWidgets('時・分のホイールを回して「決定」を押すと、選んだ時刻を返す（分は5分刻み）', (tester) async {
      final handle = tester.ensureSemantics();
      await openSheet(tester);

      // 時のホイール（20時）を 1 つ進めて 21 時、分のホイール（0分）を 1 つ進めて 5 分
      tester.semantics.increase(find.semantics.byValue('20時'));
      await tester.pumpAndSettle();
      tester.semantics.increase(find.semantics.byValue('0分'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(await result, const ReminderTime(hour: 21, minute: 5));
      handle.dispose();
    });

    testWidgets('ホイールをドラッグして回した時刻を返す', (tester) async {
      await openSheet(tester);

      // 時のホイールを上へ 2 項目ぶん（項目の高さ 32）回すと 22 時
      await tester.drag(hourText('20'), const Offset(0, -32.0 * 2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(await result, const ReminderTime(hour: 22, minute: 0));
    });

    testWidgets('ホイールが5分刻みでない時刻を伝えてきても、5分刻みに揃えて返す', (tester) async {
      await openSheet(tester);

      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(DateTime(2000, 1, 1, 6, 47));
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();

      expect(await result, const ReminderTime(hour: 6, minute: 45));
    });
  });

  group('ReminderTimePickerSheet 読み上げ・ダーク・文字拡大', () {
    testWidgets('ホイールは日本語で読み上げる（「20時」「0分」。英語の o\'clock / minutes にしない）',
        (tester) async {
      final handle = tester.ensureSemantics();
      await openSheet(tester);

      expect(find.semantics.byValue('20時'), findsOne);
      expect(find.semantics.byValue('0分'), findsOne);
      expect(find.semantics.byValue(RegExp("o'clock|minute")), findsNothing);
      expect(
        tester.getSemantics(find.text('夕食の時刻')),
        isSemantics(label: '夕食の時刻', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('ダークでは、ホイールの数字は textPrimary・面は surface（読める配色）', (tester) async {
      await openSheet(tester, theme: AppTheme.darkTheme);

      final dark = AppColorsExtension.dark;
      final hour = tester.widget<Text>(hourText('20'));
      expect(hour.style!.color, dark.textPrimary);
      final picker =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      expect(picker.backgroundColor, dark.surface);
      // シートの面（BottomSheetTheme）も surface
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(
        sheet.backgroundColor ??
            AppTheme.darkTheme.bottomSheetTheme.modalBackgroundColor,
        dark.surface,
      );
    });

    testWidgets('ライトでは、ホイールの数字は textPrimary（DS の数値: 20 / 500・等幅数字）',
        (tester) async {
      await openSheet(tester);

      final style = tester.widget<Text>(hourText('20')).style!;
      expect(style.color, AppColorsExtension.light.textPrimary);
      expect(style.fontSize, FcNumSize.compact.fontSize);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('幅 320・文字拡大 1.35 でも overflow しない', (tester) async {
      await openSheet(tester, textScale: 1.35, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('決定'), findsOneWidget);
    });
  });
}
