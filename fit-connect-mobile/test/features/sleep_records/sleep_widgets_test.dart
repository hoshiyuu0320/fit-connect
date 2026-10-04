import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/morning_wakeup_dialog.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/permission_denied_dialog.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_empty_state.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_history_list_item.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_stage_bar.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_summary_card.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_sync_status.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_week_chart.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'sleep_test_helpers.dart';

/// 睡眠画面の部品の表示テスト（正本: record-screens.js の SleepTab / StageBar）。
void main() {
  final light = AppColorsExtension.light;

  Future<void> pumpWidget(
    WidgetTester tester,
    Widget child, {
    double textScale = 1.0,
    double width = 390,
    ThemeData? theme,
    bool scroll = true,
  }) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: c!,
        ),
        home: Scaffold(
          body: scroll
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                )
              : child,
        ),
      ),
    );
  }

  String numText(WidgetTester tester) {
    final num = tester.widget<FcNum>(find.byType(FcNum));
    return num.parts!.map((p) => '${p.value}${p.unit ?? ''}').join();
  }

  void expectNoEmojiOrFaceIcons(WidgetTester tester) {
    expect(emojiPattern.hasMatch(allText(tester)), isFalse,
        reason: '絵文字は使わず、アイコンと言葉にする');
    expect(find.byIcon(LucideIcons.smile), findsNothing);
    expect(find.byIcon(LucideIcons.meh), findsNothing);
    expect(find.byIcon(LucideIcons.frown), findsNothing);
  }

  group('SleepSummaryCard（昨夜の睡眠）', () {
    testWidgets('HealthKit のデータ: 時間・就寝/起床・内訳・目覚めの言葉・編集', (tester) async {
      var edits = 0;
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, total: 450, rating: WakeupRating.refreshed),
          onEditWakeup: () => edits++,
        ),
      );

      expect(find.text('昨夜の睡眠'), findsOneWidget);
      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      // 連携元のピル（muted・heart-pulse）
      expect(find.text('HealthKit'), findsOneWidget);
      expect(find.byIcon(LucideIcons.heartPulse), findsOneWidget);
      final pill = tester.widget<FcPill>(
        find.ancestor(
            of: find.text('HealthKit'), matching: find.byType(FcPill)),
      );
      expect(pill.tone, FcPillTone.muted);
      // 大きな時間（34）
      expect(numText(tester), '7時間30分');
      expect(
        tester.widget<FcNum>(find.byType(FcNum)).size,
        FcNumSize.review,
      );
      // 就寝 / 起床（時は 0 埋めしない）
      expect(find.text('就寝'), findsOneWidget);
      expect(find.text('23:30'), findsOneWidget);
      expect(find.text('起床'), findsOneWidget);
      expect(find.text('7:20'), findsOneWidget);
      // 内訳（深い / レム / 浅い / 覚醒）
      for (final label in ['深い', 'レム', '浅い', '覚醒']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('1時間25分'), findsOneWidget);
      expect(find.text('20分'), findsOneWidget);
      // 目覚め: 言葉のピル + 編集
      expect(find.text('目覚め'), findsOneWidget);
      expect(find.text('すっきり'), findsOneWidget);
      expect(find.text('編集'), findsOneWidget);
      expect(find.byIcon(LucideIcons.pencil), findsOneWidget);
      expectNoEmojiOrFaceIcons(tester);

      await tester.tap(find.text('編集'));
      expect(edits, 1);
    });

    testWidgets('内訳の色は accent の濃淡と separator（indigo 系をやめた）', (tester) async {
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, total: 450, rating: WakeupRating.okay),
          onEditWakeup: () {},
        ),
      );

      Color stage(int i) => tester
          .widget<ColoredBox>(find.byKey(ValueKey('fc-sleep-stage-$i')))
          .color;
      expect(stage(0), light.accent); // 深い 100%
      expect(stage(1), Color.lerp(light.surface, light.accent, 0.6)); // レム
      expect(stage(2), Color.lerp(light.surface, light.accent, 0.3)); // 浅い
      expect(stage(3), light.separator); // 覚醒
      // 幅は分の比率（深い 85 : レム 110 : 浅い 255 : 覚醒 20）
      final deep =
          tester.getSize(find.byKey(const ValueKey('fc-sleep-stage-0')));
      final rem =
          tester.getSize(find.byKey(const ValueKey('fc-sleep-stage-1')));
      expect(rem.width / deep.width, closeTo(110 / 85, 0.01));
    });

    testWidgets('目覚めが未記録ならピルは「未記録」、操作は「記録」', (tester) async {
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, total: 450),
          onEditWakeup: () {},
        ),
      );

      expect(find.text('未記録'), findsOneWidget);
      expect(find.text('記録'), findsOneWidget);
      expect(find.text('編集'), findsNothing);
    });

    testWidgets('手動の記録のみ: 時間は「未取得」（0 にしない）で、詳細の案内が出る', (tester) async {
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, rating: WakeupRating.groggy),
          onEditWakeup: () {},
        ),
      );

      expect(find.text('HealthKit'), findsNothing);
      expect(find.text('手動の記録'), findsOneWidget);
      final num = tester.widget<FcNum>(find.byType(FcNum));
      expect(num.value, '未取得');
      expect(allText(tester), isNot(contains('0分')));
      expect(find.text('詳細データを取得するにはヘルスケア連携を有効にしてください'), findsOneWidget);
      // 就寝/起床・内訳は出さない
      expect(find.text('就寝'), findsNothing);
      expect(find.byType(FcSleepStageBar), findsNothing);
      // 目覚めの評価は言葉で出る
      expect(find.text('だるい'), findsOneWidget);
      expectNoEmojiOrFaceIcons(tester);
    });

    testWidgets('編集は 44×44 以上の領域で、文字拡大 1.35・狭い幅でもはみ出さない', (tester) async {
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, total: 450, rating: WakeupRating.okay),
          onEditWakeup: () {},
        ),
        textScale: 1.35,
        width: 320,
      );

      expect(tester.takeException(), isNull);
      final edit = find.ancestor(
        of: find.text('編集'),
        matching: find.byType(FcPressable),
      );
      final size = tester.getSize(edit);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
    });

    testWidgets('ダークでも描画できる', (tester) async {
      await pumpWidget(
        tester,
        SleepSummaryCard(
          record: sleepRecord(0, total: 450, rating: WakeupRating.okay),
          onEditWakeup: () {},
        ),
        theme: AppTheme.darkTheme,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('昨夜の睡眠'), findsOneWidget);
    });
  });

  group('SleepSummaryEmptyCard / SleepSummaryLoadingCard', () {
    testWidgets('今日の記録が無いときは目覚めを記録する入口が出る', (tester) async {
      var taps = 0;
      await pumpWidget(
        tester,
        SleepSummaryEmptyCard(onRecordWakeup: () => taps++),
      );

      expect(find.text('昨夜の睡眠'), findsOneWidget);
      expect(find.text('今日の記録はまだありません'), findsOneWidget);
      await tester.tap(find.text('目覚めを記録'));
      expect(taps, 1);
    });

    testWidgets('読み込み中はスケルトン（読み上げは「読み込み中」）', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidget(tester, const SleepSummaryLoadingCard());

      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      handle.dispose();
    });
  });

  group('SleepStageBar', () {
    testWidgets('すべて 0 分なら何も出さない', (tester) async {
      await pumpWidget(
        tester,
        const SleepStageBar(
          deepMinutes: 0,
          lightMinutes: 0,
          remMinutes: 0,
          awakeMinutes: 0,
        ),
      );
      expect(find.byType(FcSleepStageBar), findsNothing);
    });

    testWidgets('凡例は 深い・レム・浅い・覚醒（REM の英字は使わない）', (tester) async {
      await pumpWidget(
        tester,
        const SleepStageBar(
          deepMinutes: 85,
          lightMinutes: 255,
          remMinutes: 110,
          awakeMinutes: 20,
        ),
      );
      expect(find.text('レム'), findsOneWidget);
      expect(find.text('REM'), findsNothing);
      // 並びは 深い → レム → 浅い → 覚醒（凡例は 2 列）
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(y('深い'), y('レム'));
      expect(x('深い'), lessThan(x('レム')));
      expect(y('浅い'), y('覚醒'));
      expect(y('深い'), lessThan(y('浅い')));
    });
  });

  group('SleepWeekChart（直近7日間）', () {
    const entries = [
      DailySleepEntry(dateKey: '2026-09-07', minutes: 410),
      DailySleepEntry(dateKey: '2026-09-08', minutes: 430),
      DailySleepEntry(dateKey: '2026-09-09'),
      DailySleepEntry(dateKey: '2026-09-10', minutes: 390),
      DailySleepEntry(dateKey: '2026-09-11', minutes: 420),
      DailySleepEntry(dateKey: '2026-09-12', minutes: 410),
      DailySleepEntry(dateKey: '2026-09-13', minutes: 450),
    ];

    testWidgets('値は「6:50」形式・曜日ラベル・未取得の日は「未取得」', (tester) async {
      await pumpWidget(
          tester, const FcCard(child: SleepWeekChart(entries: entries)));

      expect(find.byType(FcBars), findsOneWidget);
      final bars = tester.widget<FcBars>(find.byType(FcBars));
      expect(bars.max, 540);
      expect(bars.height, 96);
      expect(bars.items.length, 7);
      expect(find.text('6:50'), findsNWidgets(2)); // 9/7 と 9/12
      expect(find.text('7:30'), findsOneWidget); // 今日
      expect(find.text('未取得'), findsOneWidget);
      for (final w in ['月', '火', '水', '木', '金', '土', '日']) {
        expect(find.text(w), findsOneWidget);
      }
      expect(
        find.text('HealthKit · 6日分の平均（9/9は未取得）'),
        findsOneWidget,
      );
    });

    testWidgets('最後の日（今日）だけ accent、未取得の日は高さ 2 の線', (tester) async {
      await pumpWidget(
          tester, const FcCard(child: SleepWeekChart(entries: entries)));

      Color barColor(int i) => (tester
              .widget<DecoratedBox>(find.byKey(ValueKey('fc-bar-$i')))
              .decoration as BoxDecoration)
          .color!;
      expect(barColor(6), light.accent);
      expect(barColor(0), light.textSecondary.withValues(alpha: 0.28));
      // 9/9（index 2）は未取得: 0 の棒ではなく separator の細い線
      expect(barColor(2), light.separator);
      expect(tester.getSize(find.byKey(const ValueKey('fc-bar-2'))).height, 2);
    });

    testWidgets('文字拡大 1.35・狭い幅でもはみ出さない', (tester) async {
      await pumpWidget(
        tester,
        const FcCard(child: SleepWeekChart(entries: entries)),
        textScale: 1.35,
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SleepHistoryListItem（履歴の行）', () {
    Future<void> pumpRows(WidgetTester tester, List<SleepRecord> records) {
      return pumpWidget(
        tester,
        FcRowsCard(
          children: [
            for (final r in records)
              SleepHistoryListItem(record: r, now: DateTime(2026, 9, 13)),
          ],
        ),
      );
    }

    testWidgets('日付・「目覚め まあまあ」・右に「6時間50分」', (tester) async {
      await pumpRows(tester, [
        sleepRecord(1,
            date: '2026-09-12', total: 410, rating: WakeupRating.okay),
      ]);

      expect(find.text('9月12日（土）'), findsOneWidget);
      expect(find.text('目覚め まあまあ'), findsOneWidget);
      expect(find.text('6時間50分'), findsOneWidget);
      expectNoEmojiOrFaceIcons(tester);
    });

    testWidgets('取得なし（手動の記録のみ）は「未取得」で、0 とは出さない', (tester) async {
      await pumpRows(tester, [
        sleepRecord(4, date: '2026-09-09', rating: WakeupRating.groggy),
      ]);

      expect(find.text('9月9日（水）'), findsOneWidget);
      expect(find.text('目覚め だるい · 手動の記録のみ'), findsOneWidget);
      expect(find.text('未取得'), findsOneWidget);
      final value = tester.widget<Text>(find.text('未取得'));
      expect(value.style!.color, light.textSecondary);
      expect(allText(tester), isNot(contains('0時間')));
      expect(allText(tester), isNot(contains('0分')));
    });

    testWidgets('評価が無ければ「目覚め 未記録」、行の間にだけ区切り線', (tester) async {
      await pumpRows(tester, [
        sleepRecord(1, date: '2026-09-12', total: 410),
        sleepRecord(2,
            date: '2026-09-11', total: 420, rating: WakeupRating.refreshed),
        sleepRecord(3, date: '2026-09-10', total: 390),
      ]);

      expect(find.text('目覚め 未記録'), findsNWidgets(2));
      expect(find.byType(FcSeparator), findsNWidgets(2));
    });

    testWidgets('年が違う記録は年付き', (tester) async {
      await pumpRows(tester, [
        sleepRecord(1, date: '2025-12-28', total: 410),
      ]);
      expect(find.text('2025年12月28日（日）'), findsOneWidget);
    });

    testWidgets('onTap があれば行全体が押せて chevron が出る', (tester) async {
      var taps = 0;
      await pumpWidget(
        tester,
        FcRowsCard(
          children: [
            SleepHistoryListItem(
              record: sleepRecord(1, date: '2026-09-12', total: 410),
              now: DateTime(2026, 9, 13),
              onTap: () => taps++,
            ),
          ],
        ),
      );
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      await tester.tap(find.text('9月12日（土）'));
      expect(taps, 1);
    });

    testWidgets('文字拡大 1.35 でも折り返して切れない', (tester) async {
      await pumpWidget(
        tester,
        FcRowsCard(
          children: [
            SleepHistoryListItem(
              record: sleepRecord(
                4,
                date: '2026-09-09',
                rating: WakeupRating.groggy,
              ),
              now: DateTime(2026, 9, 13),
            ),
            SleepHistoryListItem(
              record: sleepRecord(
                1,
                date: '2026-09-12',
                total: 410,
                rating: WakeupRating.okay,
              ),
              now: DateTime(2026, 9, 13),
            ),
          ],
        ),
        textScale: 1.35,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('目覚め だるい · 手動の記録のみ'), findsOneWidget);
      expect(find.text('6時間50分'), findsOneWidget);
    });
  });

  group('WakeupRatingSelector（目覚めの評価）', () {
    testWidgets('絵文字をやめ、すっきり / まあまあ / だるい の言葉で選ぶ', (tester) async {
      WakeupRating? picked;
      await pumpWidget(
        tester,
        WakeupRatingSelector(onSelect: (r) => picked = r),
      );

      for (final w in ['すっきり', 'まあまあ', 'だるい']) {
        expect(find.text(w), findsOneWidget);
      }
      expectNoEmojiOrFaceIcons(tester);
      // 並びは すっきり → まあまあ → だるい
      double x(String t) => tester.getTopLeft(find.text(t)).dx;
      expect(x('すっきり'), lessThan(x('まあまあ')));
      expect(x('まあまあ'), lessThan(x('だるい')));

      await tester.tap(find.text('まあまあ'));
      expect(picked, WakeupRating.okay);
      await tester.tap(find.text('だるい'));
      expect(picked, WakeupRating.groggy);
      await tester.tap(find.text('すっきり'));
      expect(picked, WakeupRating.refreshed);
    });

    testWidgets('選択中は actionFill の塗り、未選択は surface。高さは 44 以上', (tester) async {
      await pumpWidget(
        tester,
        WakeupRatingSelector(
          selected: WakeupRating.okay,
          onSelect: (_) {},
        ),
      );

      Color fill(String label) => (tester
              .widget<AnimatedContainer>(find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first)
              .decoration as BoxDecoration)
          .color!;
      expect(fill('まあまあ'), light.actionFill);
      expect(fill('すっきり'), light.surface);
      expect(fill('だるい'), light.surface);
      expect(
        tester
            .getSize(find
                .ancestor(
                  of: find.text('まあまあ'),
                  matching: find.byType(AnimatedContainer),
                )
                .first)
            .height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('読み上げは評価ごとに選択状態つきのボタン', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpWidget(
        tester,
        WakeupRatingSelector(
          selected: WakeupRating.refreshed,
          onSelect: (_) {},
        ),
      );

      expect(
        tester.getSemantics(find.text('すっきり')),
        matchesSemantics(
          label: 'すっきり',
          isButton: true,
          isSelected: true,
          isEnabled: true,
          hasEnabledState: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('狭いダイアログ幅・文字拡大 1.35 でも折り返して切れない', (tester) async {
      await pumpWidget(
        tester,
        SizedBox(
          width: 250,
          child: WakeupRatingSelector(onSelect: (_) {}),
        ),
        textScale: 1.35,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('まあまあ'), findsOneWidget);
    });
  });

  group('SleepSyncStatus（同期の状態）', () {
    final syncedAt = DateTime(2026, 9, 13, 7, 32);

    testWidgets('同期できたときは caption「最終同期 9月13日（日）7:32」', (tester) async {
      await pumpWidget(
        tester,
        SleepSyncStatus(lastSyncAt: syncedAt, now: DateTime(2026, 9, 13)),
      );
      expect(find.text('最終同期 9月13日（日）7:32'), findsOneWidget);
      expect(find.byType(FcInlineNotice), findsNothing);
    });

    testWidgets('同期できないときは警告の囲み（再試行つき）。押すと onRetry', (tester) async {
      var retries = 0;
      await pumpWidget(
        tester,
        SleepSyncStatus(
          lastSyncAt: syncedAt,
          failed: true,
          now: DateTime(2026, 9, 13),
          onRetry: () => retries++,
        ),
      );

      expect(
        find.text('HealthKitと同期できませんでした。9月13日（日）7:32 に取得した値を表示しています。'),
        findsOneWidget,
      );
      final notice = tester.widget<FcInlineNotice>(find.byType(FcInlineNotice));
      expect(notice.kind, FcNoticeKind.warning);
      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
      expect(find.text('最終同期 9月13日（日）7:32'), findsNothing);

      await tester.tap(find.text('再試行'));
      expect(retries, 1);
    });

    testWidgets('onRetry が無ければ再試行は出さない。取得日時が無ければ日時の文を省く', (tester) async {
      await pumpWidget(
        tester,
        const SleepSyncStatus(lastSyncAt: null, failed: true),
      );
      expect(find.text('HealthKitと同期できませんでした。'), findsOneWidget);
      expect(find.text('再試行'), findsNothing);
    });

    test('睡眠の失敗かの判定: 「睡眠:」の項目があるときだけ（体重だけは false）', () {
      bool failed(HealthSettingsState state) =>
          SleepSyncStatus.sleepSyncFailed(state);
      HealthSettingsState state(HealthSyncStatus status, String? error) =>
          healthSettingsState(status: status, error: error);

      expect(failed(state(HealthSyncStatus.success, null)), isFalse);
      expect(failed(state(HealthSyncStatus.idle, null)), isFalse);
      expect(failed(state(HealthSyncStatus.error, '睡眠: x')), isTrue);
      expect(failed(state(HealthSyncStatus.error, '体重: x / 睡眠: y')), isTrue);
      expect(failed(state(HealthSyncStatus.error, '体重: x')), isFalse);
    });

    test('設定から作る: 睡眠の連携がオフ・設定が未取得なら何も出さない', () {
      final at = DateTime(2026, 9, 13, 7, 32);
      expect(SleepSyncStatus.fromSettings(null).isEmpty, isTrue);
      expect(
        SleepSyncStatus.fromSettings(
          healthSettingsState(
            sleepEnabled: false,
            status: HealthSyncStatus.error,
            lastSyncAt: at,
          ),
        ).isEmpty,
        isTrue,
      );
      expect(
        SleepSyncStatus.fromSettings(
          healthSettingsState(enabled: false, lastSyncAt: at),
        ).isEmpty,
        isTrue,
      );
      final on = SleepSyncStatus.fromSettings(
        healthSettingsState(lastSyncAt: at),
      );
      expect(on.lastSyncAt, at);
      expect(on.failed, isFalse);
    });

    testWidgets('何も無ければ空（isEmpty）', (tester) async {
      const status = SleepSyncStatus(lastSyncAt: null);
      expect(status.isEmpty, isTrue);
      await pumpWidget(tester, status);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('SleepEmptyState（記録なし）', () {
    testWidgets('「まだ記録がありません」と、連携・目覚めを記録する入口', (tester) async {
      var health = 0;
      var record = 0;
      await pumpWidget(
        tester,
        SleepEmptyState(
          onOpenHealthSettings: () => health++,
          onRecordWakeup: () => record++,
        ),
      );

      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(
        find.text('ヘルスケア連携を有効にするか、目覚めを記録してみましょう。'),
        findsOneWidget,
      );
      await tester.tap(find.text('ヘルスケア連携を確認'));
      await tester.tap(find.text('目覚めを記録'));
      expect((health, record), (1, 1));
    });

    testWidgets('文字拡大 1.35・狭い幅でも入口が折り返して並ぶ', (tester) async {
      await pumpWidget(
        tester,
        SleepEmptyState(onOpenHealthSettings: () {}, onRecordWakeup: () {}),
        textScale: 1.35,
        width: 320,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ヘルスケア連携を確認'), findsOneWidget);
      expect(find.text('目覚めを記録'), findsOneWidget);
    });
  });

  group('MorningWakeupDialog（朝の目覚め）', () {
    Widget content({
      WakeupRating? selected,
      bool saving = false,
      ValueChanged<WakeupRating>? onSelect,
      VoidCallback? onLater,
      VoidCallback? onDismissToday,
    }) {
      return MorningWakeupDialogContent(
        selected: selected,
        saving: saving,
        onSelect: onSelect ?? (_) {},
        onLater: onLater ?? () {},
        onDismissToday: onDismissToday ?? () {},
      );
    }

    testWidgets('挨拶・問いかけ・言葉の選択肢・2つの文字操作（絵文字なし）', (tester) async {
      await pumpWidget(tester, content(), scroll: false);

      expect(find.text('おはようございます'), findsOneWidget);
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);
      expect(find.text('今朝の目覚めは？'), findsOneWidget);
      for (final w in ['すっきり', 'まあまあ', 'だるい', 'あとで', '今日は聞かない']) {
        expect(find.text(w), findsOneWidget);
      }
      expectNoEmojiOrFaceIcons(tester);
    });

    testWidgets('評価・あとで・今日は聞かない がそれぞれの操作を呼ぶ', (tester) async {
      WakeupRating? picked;
      var later = 0;
      var dismiss = 0;
      await pumpWidget(
        tester,
        content(
          onSelect: (r) => picked = r,
          onLater: () => later++,
          onDismissToday: () => dismiss++,
        ),
        scroll: false,
      );

      await tester.tap(find.text('だるい'));
      await tester.tap(find.text('あとで'));
      await tester.tap(find.text('今日は聞かない'));
      expect(picked, WakeupRating.groggy);
      expect(later, 1);
      expect(dismiss, 1);
    });

    testWidgets('保存中は評価もあとでも押せない', (tester) async {
      WakeupRating? picked;
      var later = 0;
      var dismiss = 0;
      await pumpWidget(
        tester,
        content(
          selected: WakeupRating.okay,
          saving: true,
          onSelect: (r) => picked = r,
          onLater: () => later++,
          onDismissToday: () => dismiss++,
        ),
        scroll: false,
      );

      await tester.tap(find.text('すっきり'));
      await tester.tap(find.text('あとで'));
      await tester.tap(find.text('今日は聞かない'));
      expect(picked, isNull);
      expect(later, 0);
      expect(dismiss, 0);
    });

    testWidgets('面は surface・角丸 23（テーマの DialogTheme）', (tester) async {
      await pumpWidget(tester, content(), scroll: false);

      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, light.surface);
      expect(
        material.shape,
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      );
    });

    testWidgets('文字拡大 1.35・ダーク・狭い幅でもはみ出さない', (tester) async {
      await pumpWidget(
        tester,
        content(selected: WakeupRating.okay),
        scroll: false,
        textScale: 1.35,
        width: 320,
        theme: AppTheme.darkTheme,
      );
      expect(tester.takeException(), isNull);
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColorsExtension.dark.surface);
    });
  });

  group('WakeupRecordSheetContent（目覚めを記録するシート）', () {
    testWidgets('見出し・言葉の選択肢・キャンセル（絵文字なし）', (tester) async {
      var cancels = 0;
      WakeupRating? picked;
      await pumpWidget(
        tester,
        WakeupRecordSheetContent(
          selected: WakeupRating.refreshed,
          onSelect: (r) => picked = r,
          onCancel: () => cancels++,
        ),
        scroll: false,
      );

      expect(find.text('目覚めを記録'), findsOneWidget);
      for (final w in ['すっきり', 'まあまあ', 'だるい', 'キャンセル']) {
        expect(find.text(w), findsOneWidget);
      }
      expectNoEmojiOrFaceIcons(tester);

      await tester.tap(find.text('まあまあ'));
      expect(picked, WakeupRating.okay);
      await tester.tap(find.text('キャンセル'));
      expect(cancels, 1);
      // キャンセルは 44 以上の領域
      final cancel = find.ancestor(
        of: find.text('キャンセル'),
        matching: find.byType(FcPressable),
      );
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    });
  });

  group('PermissionDeniedDialog（権限なし）', () {
    testWidgets('文言は従来どおり。操作は「あとで」「設定を開く」', (tester) async {
      await pumpWidget(tester, const PermissionDeniedDialog(), scroll: false);

      expect(find.text('ヘルスケアへのアクセスが許可されていません'), findsOneWidget);
      expect(find.text('あとで'), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
      expect(find.byIcon(LucideIcons.lock), findsOneWidget);
      expect(emojiPattern.hasMatch(allText(tester)), isFalse);
      // 旧デザインの赤い面（red100）を使わない
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppColors.red100,
        ),
        findsNothing,
      );
    });

    testWidgets('「あとで」で閉じる', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPermissionDeniedDialog(context),
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.byType(PermissionDeniedDialog), findsOneWidget);

      await tester.tap(find.text('あとで'));
      await tester.pumpAndSettle();
      expect(find.byType(PermissionDeniedDialog), findsNothing);
    });

    testWidgets('文字拡大 1.35・ダーク・狭い幅でもはみ出さない', (tester) async {
      await pumpWidget(
        tester,
        const PermissionDeniedDialog(),
        scroll: false,
        textScale: 1.35,
        width: 320,
        theme: AppTheme.darkTheme,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
