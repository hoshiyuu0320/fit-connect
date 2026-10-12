import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/screens/weight_record_screen.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../records_overview/records_test_fixtures.dart';

/// 指標（ラベルつき）。ラベルと値で探す
Finder _stat(String label, String value) => find.byWidgetPredicate(
      (w) => w is FcStat && w.label == label && w.value == value,
    );

void main() {
  final today = dateOnly(DateTime.now());

  List<Override> normalOverrides({double? target = 65.0, double? initial = 61.0}) =>
      recordsOverrides(
        records: sampleWeights(today),
        goal: sampleGoal(initial: initial, target: target),
      );

  group('通常（正本の「体重」）', () {
    testWidgets('現在 / 目標 / 目標まで、開始時から・前回から が正本の並びで出る', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );

      // 期間（今週 / 今月 / 3ヶ月 / 全期間）
      for (final label in ['今週', '今月', '3ヶ月', '全期間']) {
        expect(find.text(label), findsOneWidget);
      }

      expect(_stat('現在', '62.4'), findsOneWidget);
      expect(_stat('目標', '65.0'), findsOneWidget);
      expect(_stat('目標まで', '2.6'), findsOneWidget);
      expect(_stat('開始時から', '+1.4'), findsOneWidget);
      expect(_stat('前回から', '+0.1'), findsOneWidget);

      // 大きい 3 つは 26、差の 2 つは 20
      expect(tester.widget<FcStat>(_stat('現在', '62.4')).size, FcNumSize.stat);
      expect(
        tester.widget<FcStat>(_stat('開始時から', '+1.4')).size,
        FcNumSize.compact,
      );
    });

    testWidgets('期間の平均・最高・最低・変動幅と、計算に使った件数', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      for (final label in ['平均', '最高', '最低', '変動幅']) {
        expect(find.text(label), findsOneWidget);
      }
      // 62.4 / 62.3 / 62.2 / 62.1 / 61.7 / 61.8 / 61.6 → 平均 62.01、最高 62.4、最低 61.6、変動幅 0.8
      expect(find.textContaining('62.0'), findsOneWidget);
      expect(find.textContaining('0.8'), findsOneWidget);
      expect(find.text('今週の記録 7件から計算'), findsOneWidget);
    });

    testWidgets('達成率（％）・進捗バー・増減の矢印と色分けは出さない', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      expect(find.textContaining('達成率'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(LucideIcons.arrowUp), findsNothing);
      expect(find.byIcon(LucideIcons.arrowDown), findsNothing);
      // 旧デザインの「前回比」「開始時比」の色つきの箱もない
      expect(find.text('前回比'), findsNothing);
      expect(find.text('開始時比'), findsNothing);
      expect(find.text('期間統計'), findsNothing);
    });

    testWidgets('増減の符号で色を変えない（+1.4 も -0.8 も同じ textPrimary）', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(initial: 63.2),
      );
      // 63.2 → 62.4 は -0.8
      expect(_stat('開始時から', '-0.8'), findsOneWidget);
      final colors = AppColorsExtension.light;
      for (final value in ['-0.8', '+0.1']) {
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is FcStat && w.value == value,
            ),
            matching: find.byType(Text),
          ).at(1),
        );
        final style = text.textSpan?.style ?? text.style;
        expect(style?.color ?? colors.textPrimary, colors.textPrimary);
      }
    });

    testWidgets('体重の推移のカードにグラフ（高さ 170）。目標があれば破線の目標線', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      expect(find.text('体重の推移'), findsOneWidget);
      final chart = tester.widget<FcLineChart>(find.byType(FcLineChart));
      expect(chart.height, 170);
      expect(chart.goal, 65.0);
      expect(chart.goalLabel, '目標 65.0 kg');
      expect(chart.data.length, 7);
      // 古い順（最後が最新の 62.4）
      expect(chart.data.first.value, 61.6);
      expect(chart.data.last.value, 62.4);
      expect(chart.data.where((p) => p.label != null).length, 4);
    });

    testWidgets('最近の記録は 日時 ＋ 出どころ ＋ 値。最大 10 件', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
        size: const Size(390, 2400),
      );
      expect(find.text('最近の記録'), findsOneWidget);
      expect(find.text('${expectedJpDate(today)}7:30'), findsOneWidget);
      expect(find.text('62.4 kg'), findsOneWidget);
      expect(find.text('メッセージから'), findsNWidgets(6));
      expect(find.text('ヘルスケアから'), findsOneWidget);
      expect(find.byType(FcListRow), findsNWidgets(7));
    });

    testWidgets('メモのある記録は、出どころの後ろにメモも出す（現行の機能を残す）', (tester) async {
      final base = sampleWeights(today);
      final withNote = [
        base.first.copyWith(notes: '朝食前に測定'),
        ...base.skip(1),
      ];
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(records: withNote, goal: sampleGoal()),
        size: const Size(390, 2400),
      );
      expect(find.text('メッセージから · 朝食前に測定'), findsOneWidget);
    });

    testWidgets('11 件以上あっても一覧は 10 件まで', (tester) async {
      final many = [
        for (var i = 0; i < 14; i++)
          WeightRecord(
            id: 'w$i',
            clientId: 'c',
            weight: 62.0 + i / 10,
            recordedAt: DateTime(today.year, today.month, today.day - i, 7, 0),
            source: 'message',
            createdAt: today,
            updatedAt: today,
          ),
      ];
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(records: many, goal: sampleGoal()),
        size: const Size(390, 3200),
      );
      expect(find.byType(FcListRow), findsNWidgets(10));
    });
  });

  group('期間の切り替え', () {
    testWidgets('全期間（現行の選択肢）を選べて、期間の言葉が変わる', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      await tester.tap(find.text('全期間'));
      await tester.pumpAndSettle();
      expect(find.text('全期間の記録 7件から計算'), findsOneWidget);

      await tester.tap(find.text('今月'));
      await tester.pumpAndSettle();
      expect(find.text('${today.month}月の記録 7件から計算'), findsOneWidget);

      await tester.tap(find.text('3ヶ月'));
      await tester.pumpAndSettle();
      expect(find.text('直近3ヶ月の記録 7件から計算'), findsOneWidget);
    });

    testWidgets('期間ごとの記録で集計し直す（現在・目標は期間に関係なく最新と目標のまま）', (tester) async {
      final week = sampleWeights(today).take(2).toList();
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          recordsFor: (p) => p == PeriodFilter.week ? week : sampleWeights(today),
          latest: () async => sampleWeights(today).first,
          goal: sampleGoal(),
        ),
      );
      expect(find.text('今週の記録 2件から計算'), findsOneWidget);
      expect(find.byType(FcListRow), findsNWidgets(2));
      expect(_stat('現在', '62.4'), findsOneWidget);

      await tester.tap(find.text('今月'));
      await tester.pumpAndSettle();
      expect(find.text('${today.month}月の記録 7件から計算'), findsOneWidget);
      expect(_stat('現在', '62.4'), findsOneWidget);
    });
  });

  group('目標まで（減量・増量・未設定）', () {
    testWidgets('目標が未設定なら「未設定」と「—」。0.0 を出さない', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(target: null),
      );
      expect(_stat('目標', '未設定'), findsOneWidget);
      expect(_stat('目標まで', '—'), findsOneWidget);
      expect(find.textContaining('目標'), findsWidgets);
      expect(
        tester.widget<FcLineChart>(find.byType(FcLineChart)).goal,
        isNull,
      );
    });

    testWidgets('減量の目標に届いたら、静かに「目標に届きました」（演出・色なし）', (tester) async {
      final records = sampleWeights(today);
      // 開始 70.0 → 現在 62.4、目標 64.0（減量・届いて 1.6 kg 下回っている）
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          records: records,
          goal: sampleGoal(initial: 70.0, target: 64.0),
        ),
      );
      expect(_stat('目標との差', '1.6'), findsOneWidget);
      expect(find.text('目標に届きました'), findsOneWidget);
    });

    testWidgets('増量の目標が途中なら「目標まで」', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(initial: 61.0, target: 65.0),
      );
      expect(_stat('目標まで', '2.6'), findsOneWidget);
      expect(find.text('目標に届きました'), findsNothing);
    });

    testWidgets('開始時の体重が無ければ期間内の最古の記録から数える（現行どおり）', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(initial: null),
      );
      // 最古の記録 61.6 → 62.4 は +0.8
      expect(_stat('開始時から', '+0.8'), findsOneWidget);
    });
  });

  group('記録が少ない・無い', () {
    testWidgets('記録が 1 件だけなら「前回から」は —（0 にしない）', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          records: [sampleWeights(today).first],
          goal: sampleGoal(),
        ),
      );
      expect(_stat('前回から', '—'), findsOneWidget);
      expect(find.text('今週の記録 1件から計算'), findsOneWidget);
    });

    testWidgets('この期間に記録が無いだけなら、最新の値は出し、平均などは —', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          recordsFor: (_) => const [],
          latest: () async => sampleWeights(today).first,
          goal: sampleGoal(),
        ),
      );
      expect(_stat('現在', '62.4'), findsOneWidget);
      expect(_stat('開始時から', '+1.4'), findsOneWidget);
      expect(_stat('前回から', '—'), findsOneWidget);
      expect(find.text('この期間の記録はありません'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(5));
      expect(find.text('この期間の体重の記録はありません。'), findsOneWidget);
      expect(find.byType(FcLineChart), findsNothing);
      expect(find.text('最近の記録'), findsNothing);
    });

    testWidgets('1 件も無ければ「まだ記録がありません」。期間の切り替えは残る', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(goal: sampleGoal()),
      );
      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(find.byType(FcStateMessage), findsOneWidget);
      expect(find.byType(FcStat), findsNothing);
      expect(find.text('今週'), findsOneWidget);
    });

    group('記録なしの「メッセージから記録する」', () {
      testWidgets('コールバックがあれば入口が出て、押すと呼ばれる', (tester) async {
        var opened = 0;
        await pumpRecordsPage(
          tester,
          WeightRecordScreen(onOpenMessages: () => opened++),
          overrides: recordsOverrides(goal: sampleGoal()),
        );

        expect(find.text('メッセージから記録する'), findsOneWidget);
        expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);

        await tester.tap(find.text('メッセージから記録する'));
        await tester.pump();
        expect(opened, 1);
      });

      testWidgets('コールバックが null なら入口は出さず、文言だけ', (tester) async {
        await pumpRecordsPage(
          tester,
          const WeightRecordScreen(),
          overrides: recordsOverrides(goal: sampleGoal()),
        );
        expect(find.text('まだ記録がありません'), findsOneWidget);
        expect(find.text('メッセージから記録する'), findsNothing);
        expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
      });

      testWidgets('記録があるとき（この期間だけ無いときも）は入口を出さない', (tester) async {
        await pumpRecordsPage(
          tester,
          WeightRecordScreen(onOpenMessages: () {}),
          overrides: normalOverrides(),
        );
        expect(find.text('メッセージから記録する'), findsNothing);

        await pumpRecordsPage(
          tester,
          WeightRecordScreen(onOpenMessages: () {}),
          overrides: recordsOverrides(
            recordsFor: (_) => const [],
            latest: () async => sampleWeights(today).first,
            goal: sampleGoal(),
          ),
        );
        expect(find.text('メッセージから記録する'), findsNothing);
      });
    });

    testWidgets('読込中は配置を保つスケルトン（0.0 kg を出さない）', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          latest: () => Completer<WeightRecord?>().future,
          goal: sampleGoal(),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(FcStat), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      handle.dispose();
    });

    testWidgets('読み込みに失敗したら再試行を出し、押すと読み直す', (tester) async {
      var calls = 0;
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          latest: () async {
            calls++;
            throw Exception('boom');
          },
          records: sampleWeights(today),
          goal: sampleGoal(),
        ),
      );
      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
      final before = calls;
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
    });
  });

  group('読み込みの失敗はカードごと（失敗したカードだけエラーと再試行）', () {
    testWidgets('目標が読めないときは、上のカードだけエラー。推移と最近の記録は出し続ける（目標線なし）', (tester) async {
      var calls = 0;
      var fail = true;
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          records: sampleWeights(today),
          goalLoader: () async {
            calls++;
            if (fail) throw Exception('goal failed');
            return sampleGoal();
          },
        ),
        size: const Size(390, 2400),
      );

      // 上のカードだけが失敗
      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('現在の体重と目標を読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('goal failed'), findsNothing);
      expect(find.byType(FcStat), findsNothing);
      // ほかは出ている
      expect(find.text('体重の推移'), findsOneWidget);
      expect(tester.widget<FcLineChart>(find.byType(FcLineChart)).goal, isNull);
      expect(find.text('最近の記録'), findsOneWidget);
      expect(find.byType(FcListRow), findsNWidgets(7));

      final before = calls;
      fail = false;
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
      expect(find.text('読み込めませんでした'), findsNothing);
      expect(_stat('目標', '65.0'), findsOneWidget);
      expect(tester.widget<FcLineChart>(find.byType(FcLineChart)).goal, 65.0);
    });

    testWidgets('最新の体重が読めないときも、上のカードだけエラー。推移と最近の記録は出し続ける', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          records: sampleWeights(today),
          latest: () async => throw Exception('latest failed'),
          goal: sampleGoal(),
        ),
        size: const Size(390, 2400),
      );
      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.byType(FcStat), findsNothing);
      expect(find.byType(FcLineChart), findsOneWidget);
      expect(find.byType(FcListRow), findsNWidgets(7));
    });

    testWidgets('期間の記録だけ読めないときは、推移のカードだけエラー。上のカードは読めた値を出す', (tester) async {
      var calls = 0;
      var fail = true;
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          recordsLoader: (_) async {
            calls++;
            if (fail) throw Exception('records failed');
            return sampleWeights(today);
          },
          latest: () async => sampleWeights(today).first,
          goal: sampleGoal(),
        ),
        size: const Size(390, 2400),
      );

      // 推移のカードがエラー（最近の記録も出さない）
      expect(find.text('読み込めませんでした'), findsOneWidget);
      expect(find.textContaining('体重の推移と最近の記録を読み込めませんでした'), findsOneWidget);
      expect(find.byType(FcLineChart), findsNothing);
      expect(find.text('最近の記録'), findsNothing);

      // 上のカード: 最新・目標・目標まで・開始時からは出す。期間の集計は「—」。0 は出さない
      expect(_stat('現在', '62.4'), findsOneWidget);
      expect(_stat('目標', '65.0'), findsOneWidget);
      expect(_stat('目標まで', '2.6'), findsOneWidget);
      expect(_stat('開始時から', '+1.4'), findsOneWidget);
      expect(_stat('前回から', '—'), findsOneWidget);
      expect(find.text('この期間の記録を読み込めませんでした'), findsOneWidget);
      expect(find.text('この期間の記録はありません'), findsNothing);
      expect(find.textContaining('件から計算'), findsNothing);

      final before = calls;
      fail = false;
      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
      expect(find.text('読み込めませんでした'), findsNothing);
      expect(find.byType(FcLineChart), findsOneWidget);
      expect(_stat('前回から', '+0.1'), findsOneWidget);
      expect(find.text('今週の記録 7件から計算'), findsOneWidget);
    });

    testWidgets('両方失敗したときは、それぞれの「再試行」が自分のカードだけを読み直す', (tester) async {
      var recordCalls = 0;
      var latestCalls = 0;
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          recordsLoader: (_) async {
            recordCalls++;
            throw Exception('records failed');
          },
          latest: () async {
            latestCalls++;
            throw Exception('latest failed');
          },
          goal: sampleGoal(),
        ),
      );
      expect(find.text('読み込めませんでした'), findsNWidgets(2));
      expect(find.text('再試行'), findsNWidgets(2));
      final recordsBefore = recordCalls;
      final latestBefore = latestCalls;

      // 上のカード（最新の体重・目標）の再試行
      await tester.tap(find.text('再試行').first);
      await tester.pumpAndSettle();
      expect(latestCalls, greaterThan(latestBefore));
      expect(recordCalls, recordsBefore);

      // 推移のカードの再試行
      final latestAfter = latestCalls;
      await tester.tap(find.text('再試行').last);
      await tester.pumpAndSettle();
      expect(recordCalls, greaterThan(recordsBefore));
      expect(latestCalls, latestAfter);
    });

    testWidgets('期間の記録だけ読込中のあいだは、上のカードも推移も配置を保つスケルトン', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: recordsOverrides(
          recordsLoader: (_) => Completer<List<WeightRecord>>().future,
          latest: () async => sampleWeights(today).first,
          goal: sampleGoal(),
        ),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.bySemanticsLabel('読み込み中'), findsNWidgets(2));
      expect(find.byType(FcStat), findsNothing);
      expect(find.byType(FcLineChart), findsNothing);
      expect(find.text('最近の記録'), findsNothing);
      handle.dispose();
    });
  });

  group('ダーク・文字拡大・タッチ領域', () {
    testWidgets('ダークでも例外なく描画される', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
        brightness: Brightness.dark,
        size: const Size(390, 2400),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FcStat), findsNWidgets(5));
    });

    testWidgets('文字 1.35 倍で横にはみ出さず、指標が積み直される', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
        textScale: 1.35,
      );
      expect(tester.takeException(), isNull);

      // 通常は 3 つが 1 行に並ぶが、拡大すると 1 行に 2 つまで
      final current = tester.getTopLeft(_stat('現在', '62.4'));
      final goal = tester.getTopLeft(_stat('目標', '65.0'));
      final remaining = tester.getTopLeft(_stat('目標まで', '2.6'));
      expect(goal.dy, current.dy);
      expect(remaining.dy, greaterThan(current.dy));

      // 最後まで届く
      await tester.dragUntilVisible(
        find.text('最近の記録'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('通常の文字では 3 つの指標が 1 行に並ぶ', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      final y = tester.getTopLeft(_stat('現在', '62.4')).dy;
      expect(tester.getTopLeft(_stat('目標', '65.0')).dy, y);
      expect(tester.getTopLeft(_stat('目標まで', '2.6')).dy, y);
      // 4 つの小さな指標も 1 行
      final avg = tester.getTopLeft(find.text('平均')).dy;
      expect(tester.getTopLeft(find.text('変動幅')).dy, avg);
    });

    testWidgets('期間セグメント（4 択）のタッチ領域は 44 以上', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      for (final label in ['今週', '今月', '3ヶ月', '全期間']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(FcPressable)),
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
    });

    testWidgets('左右の余白は 20。カードの幅は 350', (tester) async {
      await pumpRecordsPage(
        tester,
        const WeightRecordScreen(),
        overrides: normalOverrides(),
      );
      final card = find.byType(FcCard).first;
      expect(tester.getTopLeft(card).dx, 20);
      expect(tester.getSize(card).width, 350);
    });
  });
}
