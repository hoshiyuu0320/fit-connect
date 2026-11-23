import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/daily_summary_card.dart';
import 'package:fit_connect_mobile/features/record_streak/data/record_streak_repository.dart';
import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';
import 'package:fit_connect_mobile/features/record_streak/providers/record_streak_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

import '../record_streak/fake_record_streak_repository.dart';
import 'home_test_support.dart';

/// `FcRowValue.metric`（Text.rich）の全文
bool _hasRich(String plain) => find
    .byWidgetPredicate((w) =>
        w is RichText &&
        w.text.toPlainText().replaceAll('￼', '') == plain)
    .evaluate()
    .isNotEmpty;

/// 先頭の「記録の連続」の行
Finder _streakRow() => find.ancestor(
      of: find.text('記録の連続'),
      matching: find.byType(FcListRow),
    );

/// 行の中身を 1 つの文字列にする（比べやすくするため）。null は「行なし」
String _describe(SummaryRowData? row) {
  if (row == null) return '行なし';
  final value = switch (row.kind) {
    SummaryRowKind.value =>
      row.parts.map((p) => '${p.value}${p.unit ?? ''}').join(),
    SummaryRowKind.loading => 'スケルトン',
    _ => '${row.kind.name}:${row.text}',
  };
  return row.sub == null ? value : '$value / ${row.sub}';
}

const _clientA = 'client-a';
const _clientB = 'client-b';

/// ログイン中のクライアント（記録の連続の provider のテストで切り替える）
final _signedInClientId = StateProvider<String?>((ref) => _clientA);

/// get_record_streak の 1 行（DB の今日は 2026-11-23）
RecordStreakStatus _streakStatus({
  bool recordedToday = false,
  int untilYesterday = 0,
}) =>
    RecordStreakStatus(
      asOfDate: '2026-11-23',
      recordedToday: recordedToday,
      streakUntilYesterday: untilYesterday,
    );

/// [text] の段落が何行に折り返されたか
int _lineCount(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  );
  return boxes.map((b) => b.top.round()).toSet().length;
}

void main() {
  /// 端末を iOS / Android に見立てて [body] を実行する（変数は本体の中で必ず戻す）。
  ///
  /// `flutter test` の既定は Android。睡眠の補足（連携元の名前）は OS で変わるので、
  /// それを確かめるテストは暗黙の Android に頼らず、OS を明示する
  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<Override> overrides,
    VoidCallback? onMealsTap,
    VoidCallback? onActivityTap,
    VoidCallback? onWeightTap,
    VoidCallback? onSleepTap,
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
    Size size = const Size(390, 844),
    bool settle = true,
  }) {
    return pumpHome(
      tester,
      SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: DailySummaryCard(
          onMealsTap: onMealsTap,
          onActivityTap: onActivityTap,
          onWeightTap: onWeightTap,
          onSleepTap: onSleepTap,
        ),
      ),
      overrides: overrides,
      brightness: brightness,
      textScale: textScale,
      size: size,
      settle: settle,
    );
  }

  final today = DateTime.now();
  final d = DateTime(today.year, today.month, today.day);

  List<Override> recorded({
    int meals = 2,
    int exerciseDays = 3,
    SleepRecord? sleep,
    double latest = 62.4,
    double? previous = 62.3,
    AsyncValue<RecordStreakView?> streak =
        const AsyncData<RecordStreakView?>(null),
  }) {
    final latestRecord =
        sampleWeight(id: 'w1', weight: latest, at: DateTime(d.year, d.month, d.day, 7, 30));
    return homeOverrides(
      latestWeight: latestRecord,
      weightHistory: [
        latestRecord,
        if (previous != null)
          sampleWeight(
            id: 'w0',
            weight: previous,
            at: DateTime(d.year, d.month, d.day - 2, 7, 25),
          ),
      ],
      meals: meals,
      exerciseDays: exerciseDays,
      sleep: sleep ?? sampleSleep(),
      streak: streak,
    );
  }

  group('今日のまとめ（記録あり）', () {
    testWidgets('見出し「今日のまとめ」と 4 行（食事・運動・体重・睡眠）。絵文字・進捗バーは出ない', (tester) async {
      await pumpCard(tester, overrides: recorded());

      expect(find.text('今日のまとめ'), findsOneWidget);
      for (final title in ['食事', '運動', '体重', '睡眠']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(FcListRow), findsNWidgets(4));
      expect(find.byIcon(LucideIcons.utensils), findsOneWidget);
      expect(find.byIcon(LucideIcons.dumbbell), findsOneWidget);
      expect(find.byIcon(LucideIcons.scale), findsOneWidget);
      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      // 区切り線は行の間の 3 本だけ
      expect(find.byType(FcSeparator), findsNWidgets(3));
    });

    testWidgets('値は数値＋単位、運動の補足は今週の起点、体重の補足は前回との差と時刻', (tester) async {
      // 睡眠の補足は連携元の名前（iOS は HealthKit）。OS を iOS に見立てる
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpCard(tester, overrides: recorded());

        expect(_hasRich('2回'), isTrue);
        expect(_hasRich('3日'), isTrue);
        expect(_hasRich('62.4kg'), isTrue);
        expect(_hasRich('7時間30分'), isTrue);

        final monday = d.subtract(Duration(days: d.weekday - 1));
        expect(find.text('今週（${monday.month}/${monday.day}〜）'), findsOneWidget);
        expect(find.text('前回から +0.1 kg · 7:30'), findsOneWidget);
        expect(find.text('HealthKit'), findsOneWidget);
      });
    });

    testWidgets('体重が減ったときは負の符号。色は変えない', (tester) async {
      // 比べる相手は睡眠の補足（連携元の名前）。iOS に見立てて HealthKit で探す
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpCard(
          tester,
          overrides: recorded(latest: 61.8, previous: 62.4),
        );

        final sub = tester.widget<Text>(find.text('前回から -0.6 kg · 7:30'));
        // caption は textSecondary のまま（良し悪しで色分けしない）
        expect(sub.style!.color, isNotNull);
        expect(
          sub.style!.color,
          tester.widget<Text>(find.text('HealthKit')).style!.color,
        );
      });
    });

    testWidgets('前回の記録が見つからなければ時刻だけ', (tester) async {
      await pumpCard(tester, overrides: recorded(previous: null));

      expect(find.text('7:30'), findsOneWidget);
      expect(find.textContaining('前回'), findsNothing);
    });

    testWidgets('睡眠が 1 時間未満なら「分」だけ', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(sleep: sampleSleep(minutes: 45)),
      );
      expect(_hasRich('45分'), isTrue);
    });

    testWidgets('睡眠の補足（連携元）は iOS では HealthKit。Health Connect とは出ない',
        (tester) async {
      await withPlatform(TargetPlatform.iOS, () async {
        await pumpCard(tester, overrides: recorded());

        expect(find.text('HealthKit'), findsOneWidget);
        expect(find.text('Health Connect'), findsNothing);
      });
    });

    testWidgets('睡眠の補足（連携元）は Android では Health Connect。HealthKit とは出ない',
        (tester) async {
      await withPlatform(TargetPlatform.android, () async {
        await pumpCard(tester, overrides: recorded());

        expect(find.text('Health Connect'), findsOneWidget);
        expect(find.text('HealthKit'), findsNothing);
        // 睡眠の値そのものは OS で変わらない
        expect(_hasRich('7時間30分'), isTrue);
      });
    });

    testWidgets('目覚めの記録だけなら評価を言葉で（絵文字なし）', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(
          sleep: sampleSleep(minutes: null, rating: WakeupRating.refreshed),
        ),
      );
      expect(find.text('すっきり'), findsOneWidget);
      expect(find.text('目覚めの記録'), findsOneWidget);
    });
  });

  group('今日のまとめ（未記録・読み込み中）', () {
    testWidgets('未記録は 0 ではなく「未記録」。睡眠は「目覚めを記録」の入口', (tester) async {
      await pumpCard(tester, overrides: homeOverrides());

      expect(find.text('未記録'), findsNWidgets(3)); // 食事・運動・体重
      expect(find.text('メッセージから記録できます'), findsOneWidget);
      expect(find.text('ヘルスケアと連携すると自動で入ります'), findsOneWidget);
      expect(find.text('目覚めを記録'), findsOneWidget);
      expect(_hasRich('0回'), isFalse);
      expect(_hasRich('0日'), isFalse);
    });

    testWidgets('読み込み中は各行の値がスケルトン（0 を出さない）', (tester) async {
      await pumpCard(
        tester,
        overrides: homeOverrides(loading: true),
        settle: false,
      );

      expect(find.byType(FcListRow), findsNWidgets(4));
      expect(find.byType(FcSkeleton), findsNWidgets(4));
      expect(find.text('未記録'), findsNothing);
    });
  });

  group('今日のまとめ（操作）', () {
    testWidgets('各行のタップで記録タブの該当サブタブへ（コールバック）', (tester) async {
      final tapped = <String>[];
      await pumpCard(
        tester,
        overrides: recorded(),
        onMealsTap: () => tapped.add('meals'),
        onActivityTap: () => tapped.add('activity'),
        onWeightTap: () => tapped.add('weight'),
        onSleepTap: () => tapped.add('sleep'),
      );

      for (final title in ['食事', '運動', '体重', '睡眠']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }

      expect(tapped, ['meals', 'activity', 'weight', 'sleep']);
      // 押せる行には chevron
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(4));
    });

    testWidgets('「目覚めを記録」を押すと記録シートが開き、行の遷移は起きない', (tester) async {
      var sleepTaps = 0;
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () => sleepTaps++,
      );

      await tester.tap(find.text('目覚めを記録'));
      await tester.pumpAndSettle();

      expect(find.byType(WakeupRatingSelector), findsOneWidget);
      expect(sleepTaps, 0);
    });

    testWidgets('睡眠の行（「目覚めを記録」以外）を押すと記録タブへ', (tester) async {
      var sleepTaps = 0;
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () => sleepTaps++,
      );

      await tester.tap(find.text('睡眠'));
      await tester.pumpAndSettle();

      expect(sleepTaps, 1);
      expect(find.byType(WakeupRatingSelector), findsNothing);
    });

    testWidgets('「目覚めを記録」は 44×44 以上で、読み上げの操作としても残る', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        overrides: homeOverrides(),
        onSleepTap: () {},
      );

      // いちばん近い FcPressable（行全体ではなく、右の「目覚めを記録」だけ）
      final size = tester.getSize(
        find
            .ancestor(
              of: find.text('目覚めを記録'),
              matching: find.byType(FcPressable),
            )
            .first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      // 行の読み上げは未記録としてまとめ、記録は別の操作として足している
      final node = tester.getSemantics(find.byType(FcListRow).last);
      expect(node.label, contains('睡眠'));
      expect(node.label, contains('未記録'));
      handle.dispose();
    });
  });

  group('今日のまとめ（文字拡大・ダーク）', () {
    for (final (name, brightness) in [
      ('ライト', Brightness.light),
      ('ダーク', Brightness.dark),
    ]) {
      testWidgets('$name・文字 1.35 でも overflow せず、行が縦に伸びる', (tester) async {
        await pumpCard(
          tester,
          overrides: homeOverrides(),
          brightness: brightness,
          textScale: 1.35,
          onMealsTap: () {},
          onActivityTap: () {},
          onWeightTap: () {},
          onSleepTap: () {},
        );

        expect(tester.takeException(), isNull);
        for (final row in tester.widgetList(find.byType(FcListRow))) {
          expect(row, isA<FcListRow>());
        }
        final heights = tester
            .widgetList(find.byType(FcListRow))
            .map((w) => tester.getSize(find.byWidget(w)).height);
        for (final h in heights) {
          expect(h, greaterThanOrEqualTo(56));
        }
      });
    }
  });

  group('記録の連続（streakRowDataOf: 状態 → 行の中身）', () {
    String describeOf(AsyncValue<RecordStreakView?> async) =>
        _describe(DailySummaryCard.streakRowDataOf(async));

    test('今日記録済み: 今日を含む日数と「今日も記録しました」。1 日目だけ「今日記録しました」', () {
      expect(
        describeOf(const AsyncData(RecordStreakRecordedToday(days: 12))),
        '12日 / 今日も記録しました',
      );
      expect(
        describeOf(const AsyncData(RecordStreakRecordedToday(days: 2))),
        '2日 / 今日も記録しました',
      );
      expect(
        describeOf(const AsyncData(RecordStreakRecordedToday(days: 1))),
        '1日 / 今日記録しました',
      );
    });

    test('今日まだ・昨日まで続いている: 昨日までの日数と「今日記録すると{日数+1}日」', () {
      expect(
        describeOf(const AsyncData(RecordStreakAlive(days: 12))),
        '12日 / 今日記録すると13日',
      );
      expect(
        describeOf(const AsyncData(RecordStreakAlive(days: 1))),
        '1日 / 今日記録すると2日',
      );
    });

    test('値は数値（日数）と単位「日」に分ける（ほかの行と同じ数値の書体）', () {
      final row = DailySummaryCard.streakRowDataOf(
        const AsyncData(RecordStreakAlive(days: 12)),
      )!;
      expect(row.kind, SummaryRowKind.value);
      expect(row.parts.single.value, '12');
      expect(row.parts.single.unit, '日');
    });

    test('続いていない: 0 ではなく「これから」（未記録と同じ扱い）と「今日記録すると1日目」', () {
      final row = DailySummaryCard.streakRowDataOf(
        const AsyncData(RecordStreakNone()),
      )!;
      expect(row.kind, SummaryRowKind.missing);
      expect(row.text, 'これから');
      expect(row.sub, '今日記録すると1日目');
      expect(row.parts, isEmpty);
    });

    test('読み込み中（前の値なし）はスケルトン。補足なし', () {
      expect(describeOf(const AsyncLoading()), 'スケルトン');
    });

    test('読めない（前の値なし）・ログインしていない（null）は行を出さない', () {
      expect(
        describeOf(AsyncError(Exception('offline'), StackTrace.empty)),
        '行なし',
      );
      expect(describeOf(const AsyncData(null)), '行なし');
    });

    test('読み直し（invalidate）の間（前の値の AsyncData・isRefreshing）は前の値のまま。スケルトンに戻らない',
        () {
      final refreshing = const AsyncLoading<RecordStreakView?>()
          .copyWithPrevious(const AsyncData(RecordStreakAlive(days: 12)));
      expect(refreshing.isRefreshing, isTrue);
      expect(describeOf(refreshing), '12日 / 今日記録すると13日');
    });

    test('読めなかったあとの読み直しの間は、スケルトンを出さずに隠したまま', () {
      final retrying = const AsyncLoading<RecordStreakView?>().copyWithPrevious(
        AsyncError<RecordStreakView?>(Exception('offline'), StackTrace.empty),
      );
      expect(retrying.isLoading, isTrue);
      expect(retrying.hasValue, isFalse);
      expect(describeOf(retrying), '行なし');
    });

    test('ログインしていない間の読み直し（前の値が null）も行を出さない', () {
      final refreshing = const AsyncLoading<RecordStreakView?>()
          .copyWithPrevious(const AsyncData<RecordStreakView?>(null));
      expect(describeOf(refreshing), '行なし');
    });
  });

  // 上のグループは状態を手で作る。ここでは本物の recordStreakViewProvider（recordStreakProvider を
  // Riverpod 2.6.1 の whenData で写す）が実際に出す状態を、偽の Repository で作って確かめる。
  // 前の値が残るのは読み直し（invalidate）の間だけで、読み直しの失敗・client id の変化では前の値を落とす
  // （どちらも意図した動き。読めないときは行を出さない・前の人の値は出さない。設計 §6.4）
  group('記録の連続（本物の recordStreakViewProvider の状態 → 行の中身）', () {
    late FakeRecordStreakRepository repository;
    late ProviderContainer container;

    setUp(() {
      repository = FakeRecordStreakRepository()
        // A は昨日まで 12 日で、今日はまだ。B は昨日まで 4 日で、今日も記録済み
        ..results[_clientA] = _streakStatus(untilYesterday: 12)
        ..results[_clientB] =
            _streakStatus(recordedToday: true, untilYesterday: 4);
      container = ProviderContainer(overrides: [
        currentClientIdProvider
            .overrideWith((ref) => ref.watch(_signedInClientId)),
        recordStreakRepositoryProvider.overrideWithValue(repository),
      ]);
      addTearDown(container.dispose);
      // ホームの行の代わりに購読して保つ（自動破棄）
      container.listen(recordStreakViewProvider, (_, __) {});
    });

    AsyncValue<RecordStreakView?> view() =>
        container.read(recordStreakViewProvider);
    String row() => _describe(DailySummaryCard.streakRowDataOf(view()));
    Future<void> fetched() => container.read(recordStreakProvider.future);

    test('読み直し（invalidate）が終わるまでは、前の値の AsyncData（isRefreshing）で前の値を出し続ける',
        () async {
      await fetched();
      expect(row(), '12日 / 今日記録すると13日');

      // ほかの画面で記録した。読み直しは終わらせずに止めておく
      final gate = repository.gate = Completer<void>();
      repository.results[_clientA] =
          _streakStatus(recordedToday: true, untilYesterday: 12);
      container.invalidate(recordStreakProvider);

      final refreshing = view();
      expect(refreshing, isA<AsyncData<RecordStreakView?>>());
      expect(refreshing.isRefreshing, isTrue);
      expect(row(), '12日 / 今日記録すると13日');

      gate.complete();
      await fetched();
      expect(view().isRefreshing, isFalse);
      expect(row(), '13日 / 今日も記録しました');
    });

    test('読み直しに失敗したら、前の値を持たない AsyncError になり、行を出さない（前の値を残さない）', () async {
      await fetched();
      expect(row(), '12日 / 今日記録すると13日');

      // 前面に戻ったがオフライン
      repository.error = Exception('offline');
      container.invalidate(recordStreakProvider);
      await expectLater(fetched(), throwsException);

      // recordStreakProvider は前の値を持ったままのエラー。whenData がその値を落とす
      expect(container.read(recordStreakProvider).hasValue, isTrue);
      final failed = view();
      expect(failed, isA<AsyncError<RecordStreakView?>>());
      expect(failed.hasValue, isFalse);
      expect(DailySummaryCard.streakRowDataOf(failed), isNull);

      // もう一度読み直す間も、スケルトンを出さずに隠したまま
      final gate = repository.gate = Completer<void>();
      repository.error = null;
      container.invalidate(recordStreakProvider);
      final retrying = view();
      expect(retrying.isLoading, isTrue);
      expect(retrying.hasValue, isFalse);
      expect(row(), '行なし');

      // 読めたら出る
      gate.complete();
      await fetched();
      expect(row(), '12日 / 今日記録すると13日');
    });

    test('client id が変わったら、前の値を持たない AsyncLoading になり、スケルトン（前の人の値を出さない）',
        () async {
      await fetched();
      expect(row(), '12日 / 今日記録すると13日');

      // 別の人でログインし直した。読み込みは終わらせずに止めておく
      final gate = repository.gate = Completer<void>();
      container.read(_signedInClientId.notifier).state = _clientB;

      // recordStreakProvider は前の値を持った読み込み中（isReloading）。whenData がその値を落とす
      expect(container.read(recordStreakProvider).isReloading, isTrue);
      final reloading = view();
      expect(reloading, isA<AsyncLoading<RecordStreakView?>>());
      expect(reloading.hasValue, isFalse);
      expect(row(), 'スケルトン');

      gate.complete();
      await fetched();
      expect(row(), '5日 / 今日も記録しました');
      expect(repository.fetchedClientIds, [_clientA, _clientB]);
    });
  });

  group('記録の連続（今日のまとめの先頭の行）', () {
    for (final (name, view, value, sub) in [
      (
        '今日記録済み',
        const RecordStreakRecordedToday(days: 12),
        '12日',
        '今日も記録しました',
      ),
      (
        '今日記録済み（1 日目）',
        const RecordStreakRecordedToday(days: 1),
        '1日',
        '今日記録しました',
      ),
      (
        '今日まだ・昨日まで続いている',
        const RecordStreakAlive(days: 12),
        '12日',
        '今日記録すると13日',
      ),
    ]) {
      testWidgets('$name: 先頭の行に「$value」と「$sub」。読み上げは行全体で 1 文', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCard(tester, overrides: recorded(streak: AsyncData(view)));

        expect(find.text('記録の連続'), findsOneWidget);
        expect(find.byIcon(LucideIcons.flame), findsOneWidget);
        expect(
          tester.widget<FcListRow>(find.byType(FcListRow).first).title,
          '記録の連続',
        );
        expect(_hasRich(value), isTrue);
        expect(find.text(sub), findsOneWidget);
        expect(tester.getSemantics(_streakRow()).label, '記録の連続、$value。$sub');
        handle.dispose();
      });
    }

    testWidgets('続いていない: 0 ではなく「これから」（「未記録」と同じ弱い文字色）と「今日記録すると1日目」',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        overrides: homeOverrides(streak: const AsyncData(RecordStreakNone())),
      );

      expect(find.text('これから'), findsOneWidget);
      expect(find.text('今日記録すると1日目'), findsOneWidget);
      expect(_hasRich('0日'), isFalse);
      expect(find.textContaining('0日'), findsNothing);
      final color = tester.widget<Text>(find.text('これから')).style!.color;
      expect(color, AppColorsExtension.light.textSecondary);
      expect(color, tester.widget<Text>(find.text('未記録').first).style!.color);
      expect(
        tester.getSemantics(_streakRow()).label,
        '記録の連続、これから。今日記録すると1日目',
      );
      handle.dispose();
    });

    testWidgets('読み込み中: 値はスケルトン（補足なし）。読み上げは「記録の連続、読み込み中」', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(tester, overrides: recorded(streak: const AsyncLoading()));

      expect(find.text('記録の連続'), findsOneWidget);
      expect(
        find.descendant(of: _streakRow(), matching: find.byType(FcSkeleton)),
        findsOneWidget,
      );
      expect(tester.widget<FcListRow>(_streakRow()).caption, isNull);
      expect(tester.getSemantics(_streakRow()).label, '記録の連続、読み込み中');
      handle.dispose();
    });

    testWidgets('押せない: 矢印なし・ボタンとして読み上げない・押してもどこへも移らない', (tester) async {
      final handle = tester.ensureSemantics();
      final tapped = <String>[];
      await pumpCard(
        tester,
        overrides: recorded(streak: const AsyncData(RecordStreakAlive(days: 12))),
        onMealsTap: () => tapped.add('meals'),
        onActivityTap: () => tapped.add('activity'),
        onWeightTap: () => tapped.add('weight'),
        onSleepTap: () => tapped.add('sleep'),
      );

      expect(tester.widget<FcListRow>(_streakRow()).onTap, isNull);
      expect(
        find.descendant(
          of: _streakRow(),
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: _streakRow(), matching: find.byType(FcPressable)),
        findsNothing,
      );
      // 矢印は押せる 4 行にだけ
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(4));

      final data = tester.getSemantics(_streakRow()).getSemanticsData();
      expect(data.flagsCollection.isButton, isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(find.text('記録の連続'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
      handle.dispose();
    });

    testWidgets('行が増えても、押せる最初の行は食事。各行の行き先は変わらない', (tester) async {
      final tapped = <String>[];
      await pumpCard(
        tester,
        overrides: recorded(
          streak: const AsyncData(RecordStreakRecordedToday(days: 12)),
        ),
        onMealsTap: () => tapped.add('meals'),
        onActivityTap: () => tapped.add('activity'),
        onWeightTap: () => tapped.add('weight'),
        onSleepTap: () => tapped.add('sleep'),
      );

      final rows = tester.widgetList<FcListRow>(find.byType(FcListRow)).toList();
      expect(rows.map((r) => r.title), ['記録の連続', '食事', '運動', '体重', '睡眠']);
      expect(rows.firstWhere((r) => r.onTap != null).title, '食事');
      expect(
        tester.getTopLeft(find.text('記録の連続')).dy,
        lessThan(tester.getTopLeft(find.text('食事')).dy),
      );
      // 区切り線は行の間の 4 本
      expect(find.byType(FcSeparator), findsNWidgets(4));

      for (final title in ['食事', '運動', '体重', '睡眠']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(tapped, ['meals', 'activity', 'weight', 'sleep']);
    });

    testWidgets('アイコンは炎。大きさ・色はほかの行と同じ', (tester) async {
      await pumpCard(
        tester,
        overrides: recorded(streak: const AsyncData(RecordStreakAlive(days: 12))),
        onMealsTap: () {},
      );

      final flame = tester.widget<Icon>(find.byIcon(LucideIcons.flame));
      final utensils = tester.widget<Icon>(find.byIcon(LucideIcons.utensils));
      expect(flame.size, utensils.size);
      expect(flame.color, utensils.color);
    });

    for (final (name, streak) in [
      ('ログインしていない（null）', const AsyncData<RecordStreakView?>(null)),
      (
        '読めない（オフライン・関数がまだ無い DB）',
        AsyncError<RecordStreakView?>(Exception('offline'), StackTrace.empty),
      ),
    ]) {
      testWidgets('$name: 行を出さない（エラーの文言も出さない）。ほかの 4 行は今までどおり', (tester) async {
        await pumpCard(
          tester,
          overrides: recorded(streak: streak),
          onMealsTap: () {},
        );

        expect(find.text('記録の連続'), findsNothing);
        expect(find.byIcon(LucideIcons.flame), findsNothing);
        expect(find.byType(FcListRow), findsNWidgets(4));
        expect(find.byType(FcSeparator), findsNWidgets(3));
        expect(
          tester.widget<FcListRow>(find.byType(FcListRow).first).title,
          '食事',
        );
        expect(_hasRich('2回'), isTrue);
        expect(find.textContaining('読み込め'), findsNothing);
      });
    }
  });

  group('記録の連続（幅 320・文字 2.0・ダーク）', () {
    for (final (name, brightness) in [
      ('ライト', Brightness.light),
      ('ダーク', Brightness.dark),
    ]) {
      for (final (state, view, sub) in [
        ('今日まだ', const RecordStreakAlive(days: 12), '今日記録すると13日'),
        ('これから', const RecordStreakNone(), '今日記録すると1日目'),
        ('今日記録済み 365 日', const RecordStreakRecordedToday(days: 365), '今日も記録しました'),
      ]) {
        testWidgets('$name・$state: はみ出さず、補足は省略せずに折り返す（行は縦に伸びる）', (tester) async {
          await pumpCard(
            tester,
            overrides: homeOverrides(streak: AsyncData(view)),
            brightness: brightness,
            textScale: 2.0,
            size: const Size(320, 568),
            onMealsTap: () {},
            onActivityTap: () {},
            onWeightTap: () {},
            onSleepTap: () {},
          );

          expect(tester.takeException(), isNull);
          final caption = tester.renderObject<RenderParagraph>(find.text(sub));
          expect(caption.maxLines, isNull);
          expect(caption.didExceedMaxLines, isFalse);
          expect(_lineCount(tester, sub), greaterThanOrEqualTo(2));
          expect(
            tester.getSize(_streakRow()).height,
            greaterThan(FcRowDensity.summary.minHeight),
          );
          // 行は画面の幅に収まる
          expect(tester.getRect(_streakRow()).right, lessThanOrEqualTo(320));
        });
      }
    }

    testWidgets('ダーク: 色はトークンから（値・補足・見出し・アイコン）', (tester) async {
      await pumpCard(
        tester,
        overrides: homeOverrides(streak: const AsyncData(RecordStreakNone())),
        brightness: Brightness.dark,
      );

      const dark = AppColorsExtension.dark;
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.text('これから')).style!.color,
          dark.textSecondary);
      expect(tester.widget<Text>(find.text('今日記録すると1日目')).style!.color,
          dark.textSecondary);
      expect(tester.widget<Text>(find.text('記録の連続')).style!.color,
          dark.textPrimary);
      expect(tester.widget<Icon>(find.byIcon(LucideIcons.flame)).color,
          dark.accent);
    });
  });

  group('記録の連続（読み直し）', () {
    testWidgets('読み直し（前面に戻ったときなど）の間は前の値のまま。スケルトンに戻らず、読めたら新しい値', (tester) async {
      var status = const RecordStreakStatus(
        asOfDate: '2026-11-23',
        recordedToday: false,
        streakUntilYesterday: 12,
      );
      Completer<void>? gate;
      await pumpCard(
        tester,
        overrides: [
          ...recorded(),
          // homeOverrides が値で差し替えた行の状態を、本物の組み立て（recordStreakView）に戻す
          // （同じ provider の差し替えが重なったら、後のものが効く）。DB の取得だけを差し替える
          recordStreakViewProvider.overrideWith(recordStreakView),
          currentClientIdProvider.overrideWith((ref) => 'client-1'),
          recordStreakProvider.overrideWith((ref) async {
            final pending = gate;
            if (pending != null) await pending.future;
            return status;
          }),
        ],
      );
      expect(_hasRich('12日'), isTrue);
      expect(find.text('今日記録すると13日'), findsOneWidget);

      // ほかの画面で記録した。読み直しは終わらせずに止めておく
      status = const RecordStreakStatus(
        asOfDate: '2026-11-23',
        recordedToday: true,
        streakUntilYesterday: 12,
      );
      final refetch = gate = Completer<void>();
      ProviderScope.containerOf(tester.element(find.byType(DailySummaryCard)))
          .invalidate(recordStreakProvider);
      await tester.pump();
      await tester.pump();

      expect(_hasRich('12日'), isTrue);
      expect(find.text('今日記録すると13日'), findsOneWidget);
      expect(
        find.descendant(of: _streakRow(), matching: find.byType(FcSkeleton)),
        findsNothing,
      );

      refetch.complete();
      await tester.pumpAndSettle();
      expect(_hasRich('13日'), isTrue);
      expect(find.text('今日も記録しました'), findsOneWidget);
    });
  });

  group('weightSubLabel', () {
    final now = DateTime(2026, 9, 13, 12);
    final latest = sampleWeight(
      id: 'latest',
      weight: 62.4,
      at: DateTime(2026, 9, 13, 7, 30),
    );

    test('前回との差と時刻。同じ体重なら「前回と同じ」', () {
      final same = sampleWeight(
        id: 'prev',
        weight: 62.4,
        at: DateTime(2026, 9, 11, 7, 30),
      );
      expect(
        DailySummaryCard.weightSubLabel(
            latest: latest, history: [latest, same], now: now),
        '前回と同じ · 7:30',
      );
    });

    test('前回は「最新より前でいちばん新しい記録」', () {
      final older = sampleWeight(
        id: 'older',
        weight: 60.0,
        at: DateTime(2026, 9, 1, 7, 30),
      );
      final prev = sampleWeight(
        id: 'prev',
        weight: 62.0,
        at: DateTime(2026, 9, 12, 7, 30),
      );
      expect(
        DailySummaryCard.weightSubLabel(
            latest: latest, history: [latest, prev, older], now: now),
        '前回から +0.4 kg · 7:30',
      );
    });

    test('履歴が無ければ時刻だけ。今日でなければ日付つき', () {
      expect(
        DailySummaryCard.weightSubLabel(latest: latest, history: null, now: now),
        '7:30',
      );
      expect(
        DailySummaryCard.weightSubLabel(
          latest: latest,
          history: const [],
          now: DateTime(2026, 9, 14, 8),
        ),
        '9月13日 7:30',
      );
    });
  });
}
