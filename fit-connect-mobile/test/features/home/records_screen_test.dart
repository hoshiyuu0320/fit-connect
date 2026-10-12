import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/records_screen.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/screens/records_overview_screen.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/screens/weight_record_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../records_overview/records_test_fixtures.dart';

const _tabLabels = ['サマリ', '体重', '食事', '運動', '睡眠', 'ノート'];

Widget _header({
  int selected = 0,
  bool syncing = false,
  ValueChanged<int>? onSelected,
  VoidCallback? onSync,
}) {
  return RecordsFrameHeader(
    selectedIndex: selected,
    syncing: syncing,
    onSelected: onSelected ?? (_) {},
    onSync: onSync ?? () {},
  );
}

/// サブタブの中のタブ（本文にも同じ文字が出るので、サブタブの中に絞る）
Finder _subTab(String label) => find.descendant(
      of: find.byType(FcSubTabs<int>),
      matching: find.text(label),
    );

Finder get _syncButton => find.byWidgetPredicate(
      (w) => w is FcIconButton && w.semanticLabel == '睡眠を同期',
    );

void main() {
  final today = dateOnly(DateTime.now());

  group('枠の見出しとサブタブ', () {
    testWidgets('AppBar と TabBar をやめ、見出し「記録」と 6 つのサブタブが本文に出る', (tester) async {
      await pumpRecordsPage(tester, _header());

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('記録'), findsOneWidget);
      for (final label in _tabLabels) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.widget<FcPageHeading>(find.byType(FcPageHeading)).title, '記録');
    });

    testWidgets('見出しの下余白は 16、サブタブとの間も 16 詰め。左右余白は 20', (tester) async {
      await pumpRecordsPage(tester, _header());

      final heading = tester.widget<FcPageHeading>(find.byType(FcPageHeading));
      expect(heading.bottomSpacing, 16);
      // 見出し（下余白 16 を含む）の下端 = サブタブの上端
      expect(
        tester.getBottomLeft(find.byType(FcPageHeading)).dy,
        tester.getTopLeft(find.byType(FcSubTabs<int>)).dy,
      );
      expect(tester.getTopLeft(find.byType(FcSubTabs<int>)).dx, 20);
      expect(tester.getSize(find.byType(FcSubTabs<int>)).width, 350);
      expect(tester.getSize(find.byType(FcSubTabs<int>)).height, 52);
    });

    for (var i = 0; i < _tabLabels.length; i++) {
      testWidgets('サブタブの選択中は「${_tabLabels[i]}」だけ accent・500', (tester) async {
        await pumpRecordsPage(tester, _header(selected: i));
        final colors = AppColorsExtension.light;
        for (var j = 0; j < _tabLabels.length; j++) {
          final text = tester.widget<Text>(find.text(_tabLabels[j]));
          expect(
            text.style?.color,
            j == i ? colors.accent : colors.textSecondary,
            reason: _tabLabels[j],
          );
          expect(
            text.style?.fontWeight,
            j == i ? FontWeight.w500 : FontWeight.w400,
            reason: _tabLabels[j],
          );
        }
      });
    }

    testWidgets('サブタブを押すと、その位置が通知される', (tester) async {
      final tapped = <int>[];
      await pumpRecordsPage(tester, _header(onSelected: tapped.add));
      await tester.tap(_subTab('食事'));
      await tester.tap(_subTab('ノート'));
      expect(tapped, [2, 5]);
    });

    testWidgets('見出しは上のセーフエリア（47）の下から始まらず、枠の中に収まる', (tester) async {
      await pumpRecordsPage(
        tester,
        SafeArea(bottom: false, child: _header()),
      );
      // セーフエリア 47 + 上の余白 4
      expect(tester.getTopLeft(find.text('記録')).dy, greaterThanOrEqualTo(51));
    });
  });

  group('睡眠の同期ボタン', () {
    for (var i = 0; i < _tabLabels.length; i++) {
      testWidgets('「${_tabLabels[i]}」タブ: 同期ボタンは${i == 4 ? '出る' : '出ない'}', (tester) async {
        await pumpRecordsPage(tester, _header(selected: i));
        expect(_syncButton, i == 4 ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('見た目: 44×44 の丸・surface の面・refresh-cw 19・accent。「睡眠を同期」', (tester) async {
      await pumpRecordsPage(tester, _header(selected: 4));
      final button = tester.widget<FcIconButton>(_syncButton);
      final colors = AppColorsExtension.light;
      expect(button.icon, LucideIcons.refreshCw);
      expect(button.iconSize, 19);
      expect(button.iconColor, colors.accent);
      expect(button.primary, isFalse);
      expect(tester.getSize(_syncButton), const Size(44, 44));
      // 右端は画面の右余白（20）に揃う
      expect(tester.getTopRight(_syncButton).dx, 390 - 20);
    });

    testWidgets('読み上げのラベルは「睡眠を同期」', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRecordsPage(tester, _header(selected: 4));
      expect(find.bySemanticsLabel('睡眠を同期'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('押すと同期が呼ばれる', (tester) async {
      var syncs = 0;
      await pumpRecordsPage(
        tester,
        _header(selected: 4, onSync: () => syncs++),
      );
      await tester.tap(_syncButton);
      expect(syncs, 1);
    });

    testWidgets('同期中はスピナー。ボタンは押せず、読み上げは「睡眠を同期しています」', (tester) async {
      final handle = tester.ensureSemantics();
      var syncs = 0;
      await pumpRecordsPage(
        tester,
        _header(selected: 4, syncing: true, onSync: () => syncs++),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_syncButton, findsNothing);
      expect(find.byIcon(LucideIcons.refreshCw), findsNothing);
      expect(find.bySemanticsLabel('睡眠を同期しています'), findsOneWidget);
      // スピナーのある円は 44×44
      expect(
        tester.getSize(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(Container),
          ).first,
        ),
        const Size(44, 44),
      );
      await tester.tap(find.byType(CircularProgressIndicator), warnIfMissed: false);
      expect(syncs, 0);
      handle.dispose();
    });

    testWidgets('同期ボタンのある行は、ボタンの高さ（44）のぶんだけ見出しの行が高くなる（正本どおり）', (tester) async {
      await pumpRecordsPage(tester, _header(selected: 0));
      final withoutButton = tester.getTopLeft(find.byType(FcSubTabs<int>)).dy;

      await tester.pumpWidget(const SizedBox());
      await pumpRecordsPage(tester, _header(selected: 4));
      final withButton = tester.getTopLeft(find.byType(FcSubTabs<int>)).dy;

      // 見出しの行は同期ボタン（44）のぶんだけ高くなる（正本どおり）
      expect(withButton, greaterThan(withoutButton));
      expect(withButton - withoutButton, lessThan(8));
    });
  });

  group('ダーク・文字拡大', () {
    testWidgets('ダークでも例外なく描画される', (tester) async {
      await pumpRecordsPage(
        tester,
        _header(selected: 4),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      final button = tester.widget<FcIconButton>(_syncButton);
      expect(button.iconColor, AppColorsExtension.dark.accent);
    });

    testWidgets('文字 1.35 倍でも、サブタブは外枠の中で横スクロールし、あふれない', (tester) async {
      await pumpRecordsPage(
        tester,
        _header(selected: 4),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
      // 外枠の幅は画面の左右余白の内側のまま
      expect(tester.getSize(find.byType(FcSubTabs<int>)).width, 350);
      // 各タブは 44 以上
      final size = tester.getSize(
        find.ancestor(of: _subTab('睡眠'), matching: find.byType(FcPressable)),
      );
      expect(size.height, greaterThanOrEqualTo(44));
      // 同期ボタンは文字拡大でも 44×44
      expect(tester.getSize(_syncButton), const Size(44, 44));
    });
  });

  group('RecordsScreen（タブの切り替え）', () {
    List<Override> overrides() => recordsOverrides(
          days: sampleDays(today),
          records: sampleWeights(today),
          goal: sampleGoal(),
        );

    testWidgets('最初はサマリ。AppBar / TabBar は無く、本文がサブタブの下に出る', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsScreen(),
        overrides: overrides(),
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(RecordsFrameHeader), findsOneWidget);
      expect(find.byType(RecordsOverviewScreen), findsOneWidget);
      expect(find.byType(WeightRecordScreen), findsNothing);
      expect(tester.widget<FcSubTabs<int>>(find.byType(FcSubTabs<int>)).selected, 0);
      // 同期ボタンはサマリでは出ない
      expect(_syncButton, findsNothing);

      // サブタブの下 16 から本文
      expect(
        tester.getTopLeft(find.byType(TabBarView)).dy -
            tester.getBottomLeft(find.byType(FcSubTabs<int>)).dy,
        16,
      );
    });

    testWidgets('initialTabIndex を指定すると、そのタブで始まる', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsScreen(initialTabIndex: 1),
        overrides: overrides(),
      );
      expect(find.byType(WeightRecordScreen), findsOneWidget);
      expect(tester.widget<FcSubTabs<int>>(find.byType(FcSubTabs<int>)).selected, 1);
    });

    testWidgets('サブタブを押すと、すぐ選択が移り、本文が切り替わり、onTabChanged が 1 回呼ばれる',
        (tester) async {
      final changed = <int>[];
      await pumpRecordsPage(
        tester,
        RecordsScreen(onTabChanged: changed.add),
        overrides: overrides(),
      );

      await tester.tap(_subTab('体重'));
      await tester.pump();
      // アニメーションの完了を待たずに、選択中の表示が移る
      expect(tester.widget<FcSubTabs<int>>(find.byType(FcSubTabs<int>)).selected, 1);

      await tester.pumpAndSettle();
      expect(find.byType(WeightRecordScreen), findsOneWidget);
      expect(find.byType(RecordsOverviewScreen), findsNothing);
      expect(changed, [1]);

      await tester.tap(_subTab('サマリ'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordsOverviewScreen), findsOneWidget);
      expect(changed, [1, 0]);
    });

    testWidgets('横にスワイプしても切り替わり、サブタブの選択と onTabChanged が追従する', (tester) async {
      final changed = <int>[];
      await pumpRecordsPage(
        tester,
        RecordsScreen(onTabChanged: changed.add),
        overrides: overrides(),
      );

      await tester.fling(find.byType(TabBarView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.byType(WeightRecordScreen), findsOneWidget);
      expect(tester.widget<FcSubTabs<int>>(find.byType(FcSubTabs<int>)).selected, 1);
      expect(changed, [1]);

      await tester.fling(find.byType(TabBarView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(RecordsOverviewScreen), findsOneWidget);
      expect(changed, [1, 0]);
    });

    testWidgets('initialTabIndex が変わると、そのタブへ移る（ホームの「体重」から開くなど）', (tester) async {
      final index = ValueNotifier<int>(0);
      addTearDown(index.dispose);
      await pumpRecordsPage(
        tester,
        ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, value, __) => RecordsScreen(initialTabIndex: value),
        ),
        overrides: overrides(),
      );
      expect(find.byType(RecordsOverviewScreen), findsOneWidget);

      index.value = 1;
      await tester.pumpAndSettle();
      expect(find.byType(WeightRecordScreen), findsOneWidget);
      expect(tester.widget<FcSubTabs<int>>(find.byType(FcSubTabs<int>)).selected, 1);
    });

    testWidgets('見出しとサブタブは固定で、本文だけがスクロールする', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsScreen(),
        overrides: overrides(),
      );
      final headingTop = tester.getTopLeft(find.text('記録')).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('記録')).dy, headingTop);
    });

    group('onNavigateToMessages（記録なしの「メッセージから記録する」）', () {
      List<Override> emptyOverrides() => recordsOverrides(
            days: [
              for (var i = 0; i < 13; i++)
                DailyNutritionStat(
                  date: DateTime(today.year, today.month, today.day - (12 - i)),
                ),
            ],
            goal: sampleGoal(),
          );

      for (final (index, name) in [(0, 'サマリ'), (1, '体重')]) {
        testWidgets('$nameが空のとき、入口を押すとメッセージタブへ移る', (tester) async {
          var opened = 0;
          await pumpRecordsPage(
            tester,
            RecordsScreen(
              initialTabIndex: index,
              onNavigateToMessages: () => opened++,
            ),
            overrides: emptyOverrides(),
          );

          expect(find.text('まだ記録がありません'), findsOneWidget);
          await tester.tap(find.text('メッセージから記録する'));
          await tester.pump();
          expect(opened, 1);
        });

        testWidgets('$nameが空でも、onNavigateToMessages が null なら入口は出さない', (tester) async {
          await pumpRecordsPage(
            tester,
            RecordsScreen(initialTabIndex: index),
            overrides: emptyOverrides(),
          );

          expect(find.text('まだ記録がありません'), findsOneWidget);
          expect(find.text('メッセージから記録する'), findsNothing);
        });
      }

      testWidgets('サブタブで切り替えても、同じコールバックが渡る', (tester) async {
        var opened = 0;
        await pumpRecordsPage(
          tester,
          RecordsScreen(onNavigateToMessages: () => opened++),
          overrides: emptyOverrides(),
        );
        await tester.tap(_subTab('体重'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('メッセージから記録する'));
        await tester.pump();
        expect(opened, 1);
      });
    });

    testWidgets('ダーク・文字 1.35 倍でも例外なく描画される', (tester) async {
      await pumpRecordsPage(
        tester,
        const RecordsScreen(initialTabIndex: 1),
        overrides: overrides(),
        brightness: Brightness.dark,
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
