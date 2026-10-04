import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/screens/sleep_record_screen.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/utils/sleep_labels.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_empty_state.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_history_list_item.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_summary_card.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import 'sleep_test_helpers.dart';

/// 記録タブの「睡眠」サブタブの本文（SleepRecordScreen）の表示テスト
/// （正本: record-screens.js の SleepTab。同期できない状態を含む）。
void main() {
  /// 週間の棒の「未取得」の日（今日から 2 日前＝記録なし、4 日前＝手動の記録のみ）
  String shortDate(int daysAgo) {
    final d = parseSleepDateKey(jstDateKeyDaysAgo(daysAgo))!;
    return '${d.month}/${d.day}';
  }

  Future<FakeSleepRecords> pumpScreen(
    WidgetTester tester, {
    List<SleepRecord>? records,
    Future<List<SleepRecord>> Function()? historyLoader,
    Future<SleepRecord?> Function()? todayLoader,
    Future<List<SleepRecord>> Function()? weekLoader,
    HealthSettingsState? settings,
    Future<void> Function()? onRefresh,
    double textScale = 1.0,
    double width = 390,
    EdgeInsets padding = EdgeInsets.zero,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final list = records ?? sampleSleepRecords();
    final today = list.where((r) => r.recordedDate == todayJstDateKey());
    final fake = FakeSleepRecords(historyLoader ?? () => Future.value(list));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todaySleepRecordProvider.overrideWith((ref) {
            return todayLoader?.call() ??
                Future.value(today.isEmpty ? null : today.first);
          }),
          recentSleepRecordsProvider().overrideWith((ref) {
            return weekLoader?.call() ?? Future.value(list);
          }),
          sleepRecordsProvider().overrideWith(() {
            return fake;
          }),
          healthSettingsProvider.overrideWith(
            () => FakeHealthSettings(settings ?? healthSettingsState()),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              padding: padding,
            ),
            child: child!,
          ),
          home: Scaffold(body: SleepRecordScreen(onRefresh: onRefresh)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return fake;
  }

  String heroText(WidgetTester tester) {
    final num = tester.widget<FcNum>(find.byType(FcNum).first);
    return num.parts == null
        ? num.value
        : num.parts!.map((p) => '${p.value}${p.unit ?? ''}').join();
  }

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  group('通常', () {
    testWidgets('昨夜の睡眠 → 直近7日間 → 履歴の順に、正本どおりの内容が並ぶ', (tester) async {
      await pumpScreen(tester);

      // 昨夜の睡眠
      expect(find.text('昨夜の睡眠'), findsOneWidget);
      expect(heroText(tester), '7時間30分');
      expect(find.text('HealthKit'), findsOneWidget);
      expect(find.text('すっきり'), findsOneWidget); // 今日の目覚め（ピル）
      // 直近7日間: 平均は取得できた 5 日（6時間58分）
      expect(find.text('直近7日間'), findsOneWidget);
      expect(find.text('平均 6時間58分'), findsOneWidget);
      expect(find.byType(FcBars), findsOneWidget);
      expect(
        find.text(
          'HealthKit · 5日分の平均'
          '（${shortDate(4)}、${shortDate(2)}は未取得）',
        ),
        findsOneWidget,
      );
      // 履歴
      expect(find.text('履歴'), findsOneWidget);
      expect(find.byType(SleepHistoryListItem), findsNWidgets(6));
      expect(find.text('目覚め だるい · 手動の記録のみ'), findsOneWidget);

      // 並び順
      expect(
        top(tester, find.text('昨夜の睡眠')),
        lessThan(top(tester, find.text('直近7日間'))),
      );
      expect(
        top(tester, find.text('直近7日間')),
        lessThan(top(tester, find.text('履歴'))),
      );
    });

    testWidgets('取得できなかった日は「未取得」で、0 とは出さない', (tester) async {
      await pumpScreen(tester);

      // 棒グラフの 2 日（記録なし・手動のみ）＋ 履歴の手動のみの行 1 件
      expect(find.text('未取得'), findsNWidgets(3));
      final text = allText(tester);
      expect(text, isNot(contains('0:00')));
      expect(text, isNot(contains('0時間')));
      expect(text, isNot(contains('平均 0')));
    });

    testWidgets('絵文字・顔のアイコンを使わず、目覚めは言葉で出る', (tester) async {
      await pumpScreen(tester);

      expect(emojiPattern.hasMatch(allText(tester)), isFalse);
      expect(find.byIcon(LucideIcons.smile), findsNothing);
      expect(find.byIcon(LucideIcons.meh), findsNothing);
      expect(find.byIcon(LucideIcons.frown), findsNothing);
      expect(find.text('まあまあ'), findsNothing); // 履歴の caption は「目覚め まあまあ」
      expect(find.textContaining('目覚め まあまあ'), findsNWidgets(2)); // 1日前と5日前
    });

    testWidgets('下に下部ナビぶんの余白を受け取り、上は空けない・左右は 20', (tester) async {
      await pumpScreen(
        tester,
        padding: const EdgeInsets.only(bottom: 121),
      );

      final list = tester.widget<ListView>(find.byType(ListView));
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(padding.top, 0, reason: '上の余白（サブタブとの間）は記録タブの枠が空ける');
      expect(padding.bottom, 121);
      expect(padding.left, 20);
      expect(padding.right, 20);
      // カードの左端も 20
      expect(tester.getTopLeft(find.byType(SleepSummaryCard)).dx, 20);
    });

    testWidgets('onRefresh が無ければ引っぱって更新は付けない', (tester) async {
      await pumpScreen(tester);
      expect(find.byType(RefreshIndicator), findsNothing);
    });

    testWidgets('onRefresh があれば引っぱって更新で呼ばれる', (tester) async {
      var refreshes = 0;
      await pumpScreen(tester, onRefresh: () async => refreshes++);

      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(refreshes, 1);
    });

    testWidgets('ダークでも描画できる', (tester) async {
      await pumpScreen(tester, theme: AppTheme.darkTheme);
      expect(tester.takeException(), isNull);
      expect(find.text('昨夜の睡眠'), findsOneWidget);
    });

    testWidgets('文字拡大 1.35・狭い幅でも横にはみ出さない', (tester) async {
      await pumpScreen(tester, textScale: 1.35, width: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('直近7日間'), findsOneWidget);
    });
  });

  group('同期の状態', () {
    final syncedAt = DateTime.now().copyWith(hour: 7, minute: 32);

    testWidgets('同期できたときは caption「最終同期 …」が昨夜の睡眠の上に出る', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(lastSyncAt: syncedAt),
      );

      final caption = find.text('最終同期 ${formatSleepDateTime(syncedAt)}');
      expect(caption, findsOneWidget);
      expect(find.byType(FcInlineNotice), findsNothing);
      expect(
        top(tester, caption),
        lessThan(top(tester, find.text('昨夜の睡眠'))),
      );
    });

    testWidgets('同期できないときは警告と再試行。取得済みの値は消さずに表示し続ける', (tester) async {
      var retries = 0;
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
        ),
        onRefresh: () async => retries++,
      );

      expect(
        find.text(
          'HealthKitと同期できませんでした。'
          '${formatSleepDateTime(syncedAt)} に取得した値を表示しています。',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('最終同期'), findsNothing);
      // 取得済みの値（昨夜の睡眠・直近7日間・履歴）はそのまま
      expect(heroText(tester), '7時間30分');
      expect(find.text('平均 6時間58分'), findsOneWidget);
      expect(find.byType(SleepHistoryListItem), findsNWidgets(6));
      // 警告は昨夜の睡眠の上
      expect(
        top(tester, find.byType(FcInlineNotice)),
        lessThan(top(tester, find.text('昨夜の睡眠'))),
      );

      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('onRefresh が無ければ再試行は出さない', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
        ),
      );
      expect(find.byType(FcInlineNotice), findsOneWidget);
      expect(find.text('再試行'), findsNothing);
    });

    testWidgets('睡眠の連携がオフなら、同期エラーがあっても警告も最終同期も出さない', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          sleepEnabled: false,
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
          error: '体重: timeout',
        ),
        onRefresh: () async {},
      );

      expect(find.byType(FcInlineNotice), findsNothing);
      expect(find.textContaining('最終同期'), findsNothing);
      expect(find.textContaining('同期できませんでした'), findsNothing);
      // 値はふつうに出る
      expect(heroText(tester), '7時間30分');
    });

    testWidgets('睡眠の連携がオンでも、体重だけの失敗は睡眠タブに警告を出さない', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
          error: '体重: timeout',
        ),
        onRefresh: () async {},
      );

      expect(find.byType(FcInlineNotice), findsNothing);
      expect(find.textContaining('同期できませんでした'), findsNothing);
      expect(
          find.text('最終同期 ${formatSleepDateTime(syncedAt)}'), findsOneWidget);
    });

    testWidgets('睡眠の連携がオンで睡眠が失敗していれば警告（体重と両方失敗でも）', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
          error: '体重: timeout / 睡眠: timeout',
        ),
        onRefresh: () async {},
      );

      expect(find.byType(FcInlineNotice), findsOneWidget);
      expect(find.textContaining('HealthKitと同期できませんでした。'), findsOneWidget);
    });

    testWidgets('ヘルスケア連携が無効なら同期の表示は出さない', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          enabled: false,
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
        ),
      );
      expect(find.byType(FcInlineNotice), findsNothing);
      expect(find.textContaining('最終同期'), findsNothing);
    });

    testWidgets('同期できない状態でも文字拡大 1.35・ダークで崩れない', (tester) async {
      await pumpScreen(
        tester,
        settings: healthSettingsState(
          status: HealthSyncStatus.error,
          lastSyncAt: syncedAt,
        ),
        onRefresh: () async {},
        textScale: 1.35,
        width: 320,
        theme: AppTheme.darkTheme,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FcInlineNotice), findsOneWidget);
    });
  });

  group('状態', () {
    testWidgets('記録が1件も無ければ「まだ記録がありません」と記録する入口だけ', (tester) async {
      await pumpScreen(tester, records: const []);

      expect(find.byType(SleepEmptyState), findsOneWidget);
      expect(find.text('まだ記録がありません'), findsOneWidget);
      expect(find.text('ヘルスケア連携を確認'), findsOneWidget);
      expect(find.text('目覚めを記録'), findsOneWidget);
      expect(find.text('昨夜の睡眠'), findsNothing);
      expect(find.text('直近7日間'), findsNothing);
      expect(find.text('履歴'), findsNothing);
    });

    testWidgets('睡眠はメッセージからは記録できないので、空の状態にも「メッセージから記録する」は出さない', (tester) async {
      await pumpScreen(tester, records: const []);

      // 入口は連携と目覚めの記録だけ（体重・食事・運動の空の状態とは違う）
      expect(find.text('メッセージから記録する'), findsNothing);
      expect(find.byIcon(LucideIcons.messageCircle), findsNothing);
    });

    testWidgets('記録なしの「目覚めを記録」でシートが開く', (tester) async {
      await pumpScreen(tester, records: const []);

      await tester.tap(find.text('目覚めを記録'));
      await tester.pumpAndSettle();

      expect(find.byType(WakeupRecordSheetContent), findsOneWidget);
      expect(find.text('すっきり'), findsOneWidget);
    });

    testWidgets('記録なしの「ヘルスケア連携を確認」で連携の設定画面へ進む', (tester) async {
      await pumpScreen(tester, records: const []);

      await tester.tap(find.text('ヘルスケア連携を確認'));
      await tester.pumpAndSettle();

      expect(find.byType(HealthSettingsScreen), findsOneWidget);
    });

    testWidgets('今日の記録だけ無いときは「今日の記録はまだありません」＋目覚めを記録', (tester) async {
      await pumpScreen(
        tester,
        records: [
          sleepRecord(1, total: 410, rating: WakeupRating.okay),
          sleepRecord(2, total: 420),
        ],
      );

      expect(find.byType(SleepSummaryEmptyCard), findsOneWidget);
      expect(find.text('今日の記録はまだありません'), findsOneWidget);
      expect(find.byType(SleepEmptyState), findsNothing);
      // 履歴・直近7日間は出る
      expect(find.byType(SleepHistoryListItem), findsNWidgets(2));
      expect(find.text('直近7日間'), findsOneWidget);

      await tester.tap(find.text('目覚めを記録'));
      await tester.pumpAndSettle();
      expect(find.byType(WakeupRecordSheetContent), findsOneWidget);
    });

    testWidgets('手動の記録のみの今日は時間「未取得」と目覚めの言葉', (tester) async {
      await pumpScreen(
        tester,
        records: [sleepRecord(0, rating: WakeupRating.groggy)],
      );

      expect(heroText(tester), '未取得');
      expect(find.text('手動の記録'), findsOneWidget);
      // 直近7日間は 1 日も取得できていない
      expect(find.text('HealthKit の記録はまだありません'), findsOneWidget);
      expect(find.textContaining('平均'), findsNothing);
    });

    testWidgets('読み込み中はスケルトンで配置を保つ（スピナーは出さない）', (tester) async {
      final today = Completer<SleepRecord?>();
      final week = Completer<List<SleepRecord>>();
      final history = Completer<List<SleepRecord>>();
      await pumpScreen(
        tester,
        todayLoader: () => today.future,
        weekLoader: () => week.future,
        historyLoader: () => history.future,
      );

      expect(find.byType(SleepSummaryLoadingCard), findsOneWidget);
      expect(find.text('直近7日間'), findsOneWidget);
      expect(find.text('履歴'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SleepHistoryListItem), findsNothing);
      expect(find.byType(SleepEmptyState), findsNothing);

      today.complete(null);
      week.complete(const []);
      history.complete(const []);
      await tester.pump();
    });

    testWidgets('取得に失敗したらそれぞれ案内と「再試行」。押すと取り直す', (tester) async {
      var todayLoads = 0;
      var weekLoads = 0;
      var historyLoads = 0;
      await pumpScreen(
        tester,
        todayLoader: () {
          todayLoads++;
          return Future<SleepRecord?>.error(Exception('x'));
        },
        weekLoader: () {
          weekLoads++;
          return Future<List<SleepRecord>>.error(Exception('x'));
        },
        historyLoader: () {
          historyLoads++;
          return Future<List<SleepRecord>>.error(Exception('x'));
        },
      );

      expect(find.text('読み込めませんでした'), findsNWidgets(3));
      expect(find.text('再試行'), findsNWidgets(3));
      // 生のエラー文は出さない
      expect(find.textContaining('Exception'), findsNothing);
      expect(
        tester
            .widgetList<FcStateMessage>(find.byType(FcStateMessage))
            .every((m) => m.kind == FcStateKind.error),
        isTrue,
      );

      await tester.tap(find.text('再試行').first);
      await tester.pump();
      expect(todayLoads, 2);
      expect(weekLoads, 1);
      expect(historyLoads, 1);
    });
  });

  group('目覚めの記録（保存の挙動は従来どおり）', () {
    testWidgets('「編集」でシートが開き、評価を押すと今日の日付で保存して閉じる', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();

      expect(find.byType(WakeupRecordSheetContent), findsOneWidget);
      expect(find.text('目覚めを記録'), findsOneWidget);
      // いまの評価（すっきり）が選択中
      final control = tester.widget<FcSegmentedControl<WakeupRating?>>(
        find.byType(FcSegmentedControl<WakeupRating?>),
      );
      expect(control.selected, WakeupRating.refreshed);

      await tester.tap(
        find.descendant(
          of: find.byType(WakeupRecordSheetContent),
          matching: find.text('だるい'),
        ),
      );
      await tester.pumpAndSettle();

      expect(fake.saved, [
        (recordedDate: todayJstDateKey(), rating: WakeupRating.groggy),
      ]);
      expect(find.byType(WakeupRecordSheetContent), findsNothing);
      expect(find.text('記録しました'), findsOneWidget);
    });

    testWidgets('「キャンセル」で保存せずに閉じる', (tester) async {
      final fake = await pumpScreen(tester);

      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      expect(fake.saved, isEmpty);
      expect(find.byType(WakeupRecordSheetContent), findsNothing);
    });
  });
}
