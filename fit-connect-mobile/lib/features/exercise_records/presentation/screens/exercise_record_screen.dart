import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/completed_workout_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_kind.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_month_calendar.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_record_card.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/widgets/exercise_week_calendar.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_date_format.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/providers/workout_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

// ============================================
// 一覧の 1 件（運動の記録 / プランの完了）
// ============================================

/// 一覧・合計・カレンダーで同じように扱うための 1 件。
/// 運動の記録（`exercise_records`）と、完了したプラン（`workout_assignments`）を並べて見せる。
sealed class _Activity {
  const _Activity();

  String get id;

  /// 並び替え（新しい順）に使う日時
  DateTime get at;

  /// 系統（筋トレ / 有酸素 / その他）。プランの完了は筋トレ
  ExerciseKind get kind;

  /// 消費カロリー（入力が無ければ null）
  double? get calories;

  Widget buildCard();
}

class _RecordActivity extends _Activity {
  const _RecordActivity(this.record);

  final ExerciseRecord record;

  @override
  String get id => 'record-${record.id}';

  @override
  DateTime get at => record.recordedAt;

  @override
  ExerciseKind get kind => exerciseKindOf(record.exerciseType);

  @override
  double? get calories => record.calories;

  @override
  Widget buildCard() => ExerciseRecordCard(key: ValueKey(id), record: record);
}

class _PlanActivity extends _Activity {
  const _PlanActivity(this.assignment);

  final WorkoutAssignment assignment;

  @override
  String get id => 'plan-${assignment.id}';

  @override
  DateTime get at => completedWorkoutDate(assignment);

  @override
  ExerciseKind get kind => ExerciseKind.strength;

  @override
  double? get calories => assignment.calories?.toDouble();

  @override
  Widget buildCard() =>
      CompletedWorkoutCard(key: ValueKey(id), assignment: assignment);
}

/// 期間の合計（種類フィルタの影響を受けない、その期間のぜんぶ）
class _Totals {
  const _Totals({
    required this.total,
    required this.strength,
    required this.cardio,
    required this.calories,
    required this.calorieEntries,
  });

  factory _Totals.of(List<_Activity> activities) {
    var strength = 0;
    var cardio = 0;
    var calories = 0.0;
    var entries = 0;
    for (final activity in activities) {
      switch (activity.kind) {
        case ExerciseKind.strength:
          strength++;
        case ExerciseKind.cardio:
          cardio++;
        case ExerciseKind.other:
          break;
      }
      final kcal = activity.calories;
      if (kcal != null) {
        calories += kcal;
        entries++;
      }
    }
    return _Totals(
      total: activities.length,
      strength: strength,
      cardio: cardio,
      calories: calories,
      calorieEntries: entries,
    );
  }

  final int total;
  final int strength;
  final int cardio;

  /// 入力があった分の消費カロリーの合計
  final double calories;

  /// 消費カロリーの入力があった件数（0 なら「未記録」）
  final int calorieEntries;
}

/// 種類フィルタ（すべて / 筋トレ / 有酸素）
enum _KindFilter {
  all('すべて', null),
  strength('筋トレ', ExerciseKind.strength),
  cardio('有酸素', ExerciseKind.cardio);

  const _KindFilter(this.label, this.kind);

  final String label;
  final ExerciseKind? kind;
}

// ============================================
// 画面
// ============================================

/// 記録タブの「運動」。正本は `record-screens.js` の `ExerciseTab`。
///
/// 上から: 期間の切り替え（今週 / 今月 / 全期間）→ 種類フィルタ（すべて / 筋トレ / 有酸素）→
/// 今週（または今月）のカレンダー → 合計 → 「記録一覧」→ 運動のカード。
///
/// - 運動の種類（9 種）は、筋トレ系・有酸素系にまとめて絞り込む（対応は [ExerciseKind]）。
///   どちらにも入らない種類（ヨガなど）は「すべて」のときだけ出る
/// - 一覧・合計・カレンダーには、運動の記録に加えて完了したプランも含める（正本どおり）
/// - 合計は種類フィルタの影響を受けない（その期間のぜんぶ）。消費カロリーは入力があった分だけの合計で、
///   1 件も無ければ「未記録」
/// - 枠（見出し・サブタブ）は記録タブ側。ここは 1 ページぶんの本文
class ExerciseRecordScreen extends ConsumerStatefulWidget {
  /// 記録がまだ無いときの「メッセージから記録する」を押したとき（メッセージタブへ移る）。
  /// null なら入口は出さず、文言だけ
  final VoidCallback? onOpenMessages;

  const ExerciseRecordScreen({super.key, this.onOpenMessages});

  @override
  ConsumerState<ExerciseRecordScreen> createState() =>
      _ExerciseRecordScreenState();
}

class _ExerciseRecordScreenState extends ConsumerState<ExerciseRecordScreen> {
  PeriodFilter _selectedPeriod = PeriodFilter.week;
  _KindFilter _selectedKind = _KindFilter.all;
  late DateTime _currentMonth;

  /// 期間の選択肢（正本の並び）
  static const List<PeriodFilter> _periods = [
    PeriodFilter.week,
    PeriodFilter.month,
    PeriodFilter.all,
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    final next = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    if (!next.isAfter(DateTime(now.year, now.month, 1))) {
      setState(() => _currentMonth = next);
    }
  }

  void _retry() {
    ref.invalidate(exerciseRecordsProvider);
    ref.invalidate(completedWorkoutAssignmentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = recordDayOf(now);
    final isMonth = _selectedPeriod == PeriodFilter.month;
    final monthEnd = recordMonthEndOf(_currentMonth);

    // 種類の絞り込みは画面側で行う（系統は複数の exercise_type にまたがるため、
    // 取得は常に全種類）。
    final recordsAsync = isMonth
        ? ref.watch(exerciseRecordsProvider(
            startDate: _currentMonth,
            endDate: monthEnd,
          ))
        : ref.watch(exerciseRecordsProvider(period: _selectedPeriod));
    final workoutsAsync = isMonth
        ? ref.watch(completedWorkoutAssignmentsProvider(
            startDate: _currentMonth,
            endDate: monthEnd,
          ))
        : ref.watch(
            completedWorkoutAssignmentsProvider(period: _selectedPeriod));

    final ready = recordsAsync.hasValue && workoutsAsync.hasValue;
    final failed = !ready &&
        ((recordsAsync.hasError && !recordsAsync.hasValue) ||
            (workoutsAsync.hasError && !workoutsAsync.hasValue));

    final List<_Activity>? activities = ready
        ? ([
            ...recordsAsync.requireValue.map(_RecordActivity.new),
            ...workoutsAsync.requireValue.map(_PlanActivity.new),
          ]..sort((a, b) => b.at.compareTo(a.at)))
        : null;

    final kind = _selectedKind.kind;
    final shown = activities == null
        ? null
        : (kind == null
            ? activities
            : activities.where((a) => a.kind == kind).toList());

    final header = <Widget>[
      FcSegmentedControl<PeriodFilter>(
        items: [
          for (final period in _periods)
            FcSegmentedItem(value: period, label: period.label),
        ],
        selected: _selectedPeriod,
        onChanged: (period) => setState(() => _selectedPeriod = period),
      ),
      FcChips<_KindFilter>.single(
        items: [
          for (final filter in _KindFilter.values)
            FcChipItem(value: filter, label: filter.label),
        ],
        selected: _selectedKind,
        onSelected: (filter) => setState(() => _selectedKind = filter),
      ),
      if (_selectedPeriod == PeriodFilter.week)
        ExerciseWeekCalendar(
          today: today,
          kindsByDay: activities == null ? null : _kindsByDay(activities),
          filter: kind,
          hasError: failed,
          onRetry: _retry,
        ),
      if (isMonth)
        ExerciseMonthCalendar(
          month: _currentMonth,
          recordedDays:
              shown == null ? null : {for (final a in shown) recordDayOf(a.at)},
          hasError: failed,
          onRetry: _retry,
          onPreviousMonth: _previousMonth,
          onNextMonth: (_currentMonth.year == now.year &&
                  _currentMonth.month == now.month)
              ? null
              : _nextMonth,
        ),
      if (!failed)
        _ExerciseTotalsCard(
          totals: activities == null ? null : _Totals.of(activities),
          rangeLabel: _rangeLabel(now),
        ),
      if (!failed) const FcSectionTitle('記録一覧'),
    ];

    return _ExerciseRecordList(
      header: header,
      body: _buildBody(
        failed: failed,
        shown: shown,
        hasAny: activities?.isNotEmpty ?? false,
      ),
    );
  }

  /// 合計の説明に使う期間（「9/7〜9/13」「9月」「全期間」）
  String _rangeLabel(DateTime now) {
    switch (_selectedPeriod) {
      case PeriodFilter.week:
        return recordWeekRangeLabel(recordWeekStartOf(now));
      case PeriodFilter.month:
        return '${_currentMonth.month}月';
      case PeriodFilter.today:
      case PeriodFilter.threeMonths:
      case PeriodFilter.all:
        return '全期間';
    }
  }

  /// 日付 → その日にあった系統（週の印用）
  Map<DateTime, Set<ExerciseKind>> _kindsByDay(List<_Activity> activities) {
    final result = <DateTime, Set<ExerciseKind>>{};
    for (final activity in activities) {
      result.putIfAbsent(recordDayOf(activity.at), () => {}).add(activity.kind);
    }
    return result;
  }

  _ListBody _buildBody({
    required bool failed,
    required List<_Activity>? shown,
    required bool hasAny,
  }) {
    if (failed) {
      return _ListBody.single(
        FcStateMessage.error(
          title: '読み込めませんでした',
          message: '通信を確認して、もう一度お試しください。',
          actionLabel: '再試行',
          onAction: _retry,
        ),
      );
    }
    if (shown == null) {
      return _ListBody(
        count: 2,
        builder: (context, index) => const _ExerciseCardSkeleton(),
      );
    }
    if (shown.isEmpty) {
      // 絞り込みで空になったときは、元の記録はあることを伝える
      return _ListBody.single(
        hasAny
            ? const FcStateMessage.empty(
                title: 'この種類の記録はありません',
                message: '「すべて」に切り替えると、ほかの種類の記録も見られます。',
              )
            : FcStateMessage.empty(
                title: 'まだ記録がありません',
                message: 'メッセージで「#運動 ランニング 5km 30分」のように送ると、'
                    'ここに記録が並びます。',
                actionLabel:
                    widget.onOpenMessages == null ? null : 'メッセージから記録する',
                actionIcon: LucideIcons.messageCircle,
                onAction: widget.onOpenMessages,
              ),
      );
    }
    return _ListBody(
      count: shown.length,
      builder: (context, index) => shown[index].buildCard(),
    );
  }
}

/// 記録一覧の中身（件数と、i 番目の作り方）。長い一覧でも見える分だけ作る
class _ListBody {
  const _ListBody({required this.count, required this.builder});

  factory _ListBody.single(Widget child) =>
      _ListBody(count: 1, builder: (_, __) => child);

  final int count;
  final IndexedWidgetBuilder builder;
}

/// 1 ページぶんの本文。左右余白は画面幅に応じて 20 / 16、上 16、下はナビ（+余白）のぶん
/// （`MediaQuery.padding.bottom` に加算済み）。カード・見出しの間は 16
class _ExerciseRecordList extends StatelessWidget {
  const _ExerciseRecordList({required this.header, required this.body});

  final List<Widget> header;
  final _ListBody body;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView.separated(
      padding:
          EdgeInsets.fromLTRB(horizontal, AppSpacing.lg, horizontal, bottom),
      itemCount: header.length + body.count,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.cardGap),
      itemBuilder: (context, index) => index < header.length
          ? header[index]
          : body.builder(context, index - header.length),
    );
  }
}

/// 合計カード。合計 / 筋トレ / 有酸素 / 消費カロリー。
/// 正本は `record-screens.js` の `ExerciseTab` の `StatList` のカード（余白は上 4・下 2）。
///
/// 入力が無い値は「未記録」（0 と区別する）。[totals] が null のあいだは読込中。
class _ExerciseTotalsCard extends StatelessWidget {
  const _ExerciseTotalsCard({required this.totals, required this.rangeLabel});

  final _Totals? totals;

  /// 説明に入れる期間（「9/7〜9/13」「9月」「全期間」）
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    final totals = this.totals;
    if (totals == null) {
      return Semantics(
        label: '読み込み中',
        child: const FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FcSkeleton.line(width: 120),
              SizedBox(height: AppSpacing.lg),
              FcSkeleton.line(width: 80),
              SizedBox(height: AppSpacing.lg),
              FcSkeleton.line(width: 80),
              SizedBox(height: AppSpacing.lg),
              FcSkeleton.line(width: 140),
            ],
          ),
        ),
      );
    }

    final number = NumberFormat('#,###');
    return FcCard(
      paddingOverride: const EdgeInsets.fromLTRB(20, 4, 20, 2),
      child: FcStatList(
        items: [
          FcStatItem(
            label: '合計',
            description: '$rangeLabelの運動記録',
            value: '${totals.total}回',
          ),
          FcStatItem(
            icon: LucideIcons.dumbbell,
            label: '筋トレ',
            value: '${totals.strength}回',
          ),
          FcStatItem(
            icon: LucideIcons.footprints,
            label: '有酸素',
            value: '${totals.cardio}回',
          ),
          FcStatItem(
            label: '消費カロリー',
            description: totals.calorieEntries > 0
                ? '入力があった${totals.calorieEntries}件の合計'
                : null,
            value: totals.calorieEntries > 0
                ? '${number.format(totals.calories.round())} kcal'
                : null,
          ),
        ],
      ),
    );
  }
}

/// 読込中の運動カード（見出し・題名・補足の配置を保つ）
class _ExerciseCardSkeleton extends StatelessWidget {
  const _ExerciseCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: const FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FcSkeleton.line(width: 96),
            SizedBox(height: AppSpacing.md),
            FcSkeleton.line(width: 200, height: 17),
            SizedBox(height: AppSpacing.sm),
            FcSkeleton.line(width: 160),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

// ExerciseRecordScreen は Riverpod のプロバイダーを使うので、プレビューは同じ部品を
// 静的なデータで並べたもの（`_ExerciseRecordList` は画面と共通）。

Widget _previewApp(Brightness brightness, double textScale, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(body: SafeArea(child: child)),
  );
}

Widget _previewScreen({
  required Brightness brightness,
  double textScale = 1,
  bool empty = false,
  bool loading = false,
}) {
  final now = DateTime.now();
  final today = recordDayOf(now);
  final weekStart = recordWeekStartOf(today);
  DateTime day(int i) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + i);

  final header = <Widget>[
    FcSegmentedControl<PeriodFilter>(
      items: const [
        FcSegmentedItem(value: PeriodFilter.week, label: '今週'),
        FcSegmentedItem(value: PeriodFilter.month, label: '今月'),
        FcSegmentedItem(value: PeriodFilter.all, label: '全期間'),
      ],
      selected: PeriodFilter.week,
      onChanged: (_) {},
    ),
    FcChips<_KindFilter>.single(
      items: [
        for (final filter in _KindFilter.values)
          FcChipItem(value: filter, label: filter.label),
      ],
      selected: _KindFilter.all,
      onSelected: (_) {},
    ),
    ExerciseWeekCalendar(
      today: today,
      kindsByDay: loading
          ? null
          : empty
              ? const {}
              : {
                  day(0): {ExerciseKind.strength},
                  day(2): {ExerciseKind.strength},
                  day(5): {ExerciseKind.cardio},
                },
    ),
    _ExerciseTotalsCard(
      totals: loading
          ? null
          : empty
              ? const _Totals(
                  total: 0,
                  strength: 0,
                  cardio: 0,
                  calories: 0,
                  calorieEntries: 0,
                )
              : const _Totals(
                  total: 3,
                  strength: 2,
                  cardio: 1,
                  calories: 600,
                  calorieEntries: 2,
                ),
      rangeLabel: recordWeekRangeLabel(weekStart),
    ),
    const FcSectionTitle('記録一覧'),
  ];

  final _ListBody body;
  if (loading) {
    body =
        _ListBody(count: 2, builder: (_, __) => const _ExerciseCardSkeleton());
  } else if (empty) {
    body = _ListBody.single(
      FcStateMessage.empty(
        title: 'まだ記録がありません',
        message: 'メッセージで「#運動 ランニング 5km 30分」のように送ると、'
            'ここに記録が並びます。',
        actionLabel: 'メッセージから記録する',
        actionIcon: LucideIcons.messageCircle,
        onAction: () {},
      ),
    );
  } else {
    final records = [
      ExerciseRecord(
        id: '1',
        clientId: 'client-1',
        exerciseType: 'running',
        duration: 30,
        distance: 5,
        calories: 320,
        recordedAt: DateTime(day(5).year, day(5).month, day(5).day, 18, 20),
        source: 'message',
        createdAt: now,
        updatedAt: now,
      ),
      ExerciseRecord(
        id: '2',
        clientId: 'client-1',
        exerciseType: 'strength_training',
        memo: 'プランク 1分 × 3セット',
        recordedAt: DateTime(day(0).year, day(0).month, day(0).day, 21),
        source: 'message',
        createdAt: now,
        updatedAt: now,
      ),
    ];
    body = _ListBody(
      count: records.length,
      builder: (_, i) => ExerciseRecordCard(record: records[i]),
    );
  }

  return _previewApp(
    brightness,
    textScale,
    _ExerciseRecordList(header: header, body: body),
  );
}

@Preview(name: 'ExerciseRecordScreen - 通常')
Widget previewExerciseRecordScreen() =>
    _previewScreen(brightness: Brightness.light);

@Preview(name: 'ExerciseRecordScreen - ダーク')
Widget previewExerciseRecordScreenDark() =>
    _previewScreen(brightness: Brightness.dark);

@Preview(name: 'ExerciseRecordScreen - 記録なし')
Widget previewExerciseRecordScreenEmpty() =>
    _previewScreen(brightness: Brightness.light, empty: true);

@Preview(name: 'ExerciseRecordScreen - 読込中')
Widget previewExerciseRecordScreenLoading() =>
    _previewScreen(brightness: Brightness.light, loading: true);

@Preview(name: 'ExerciseRecordScreen - 文字拡大 1.35')
Widget previewExerciseRecordScreenLargeText() =>
    _previewScreen(brightness: Brightness.light, textScale: 1.35);
