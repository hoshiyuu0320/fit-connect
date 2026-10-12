import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_card.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_month_calendar.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_summary_card.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_week_calendar.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_date_format.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_month_card.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録タブの「食事」。正本は `record-screens.js` の `MealsTab`。
///
/// 上から: 期間の切り替え（今日 / 今週 / 今月 / 全期間）→ 今日の食事 → 今週の記録 → 月カード →
/// 「記録一覧」→ 食事カード。
///
/// - 3 枚のカード（今日の食事・今週・月）は期間の選択に関わらず常に出す（正本の構成）。
///   選んだ期間で変わるのは「記録一覧」
/// - 月カードの前の月・次の月で月を移すと、「今月」を選んでいるときの一覧もその月になる
/// - 食事の写真は押すと全画面で見られる。AI が推定した栄養には「推定」と書く
/// - 枠（見出し・サブタブ）は記録タブ側。ここは 1 ページぶんの本文
class MealRecordScreen extends ConsumerStatefulWidget {
  /// 記録がまだ無いときの「メッセージから記録する」を押したとき（メッセージタブへ移る）。
  /// null なら入口は出さず、文言だけ
  final VoidCallback? onOpenMessages;

  const MealRecordScreen({super.key, this.onOpenMessages});

  @override
  ConsumerState<MealRecordScreen> createState() => _MealRecordScreenState();
}

class _MealRecordScreenState extends ConsumerState<MealRecordScreen> {
  PeriodFilter _selectedPeriod = PeriodFilter.today;
  late DateTime _currentMonth;

  /// 期間の選択肢（正本の並び）
  static const List<PeriodFilter> _periods = [
    PeriodFilter.today,
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // 一覧: 選んだ期間（今月は月カードで選んだ月）
    final recordsAsync = _selectedPeriod == PeriodFilter.month
        ? ref.watch(mealRecordsProvider(
            startDate: _currentMonth,
            endDate: recordMonthEndOf(_currentMonth),
          ))
        : ref.watch(mealRecordsProvider(period: _selectedPeriod));
    // 今日の食事: 期間の選択とは別に、いつも今日の分
    final todayAsync =
        ref.watch(mealRecordsProvider(period: PeriodFilter.today));

    final header = <Widget>[
      FcSegmentedControl<PeriodFilter>(
        items: [
          for (final period in _periods)
            FcSegmentedItem(value: period, label: period.label),
        ],
        selected: _selectedPeriod,
        onChanged: (period) => setState(() => _selectedPeriod = period),
      ),
      MealSummaryCard(
        date: now,
        slots: MealSummaryCard.slotsFrom(todayAsync.valueOrNull ?? const []),
        loading: !todayAsync.hasValue && !todayAsync.hasError,
        hasError: todayAsync.hasError && !todayAsync.hasValue,
        onRetry: () => ref.invalidate(mealRecordsProvider),
      ),
      const MealWeekCalendar(),
      MealMonthCalendar(
        initialMonth: _currentMonth,
        onMonthChanged: (month) => setState(() => _currentMonth = month),
      ),
      const FcSectionTitle('記録一覧'),
    ];

    return _MealRecordList(
      header: header,
      body: _buildBody(recordsAsync),
    );
  }

  _ListBody _buildBody(AsyncValue<List<MealRecord>> recordsAsync) {
    if (recordsAsync.hasValue) {
      final records = recordsAsync.requireValue;
      if (records.isEmpty) {
        return _ListBody.single(
          _MealEmptyMessage(onOpenMessages: widget.onOpenMessages),
        );
      }
      return _ListBody(
        count: records.length,
        builder: (context, index) => MealCard(
          key: ValueKey(records[index].id),
          record: records[index],
        ),
      );
    }
    if (recordsAsync.hasError) {
      return _ListBody.single(
        FcStateMessage.error(
          title: '読み込めませんでした',
          message: '通信を確認して、もう一度お試しください。',
          actionLabel: '再試行',
          onAction: () => ref.invalidate(mealRecordsProvider),
        ),
      );
    }
    return _ListBody(
      count: 2,
      builder: (context, index) => const _MealCardSkeleton(),
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
class _MealRecordList extends StatelessWidget {
  const _MealRecordList({required this.header, required this.body});

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

/// 記録がないとき。メッセージから記録できることを伝える
class _MealEmptyMessage extends StatelessWidget {
  const _MealEmptyMessage({this.onOpenMessages});

  /// 「メッセージから記録する」（メッセージタブへ移る）。null なら入口は出さない
  final VoidCallback? onOpenMessages;

  @override
  Widget build(BuildContext context) {
    return FcStateMessage.empty(
      title: 'まだ記録がありません',
      message: 'メッセージで「#食事 昼食 鶏むね肉のグリル」のように送ると、'
          'ここに記録が並びます。',
      actionLabel: onOpenMessages == null ? null : 'メッセージから記録する',
      actionIcon: LucideIcons.messageCircle,
      onAction: onOpenMessages,
    );
  }
}

/// 読込中の食事カード（文字の部分 3 行の配置を保つ。写真の有無は読み込むまで分からないので写真欄は出さない）
class _MealCardSkeleton extends StatelessWidget {
  const _MealCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: const FcCard(
        padding: FcCardPadding.none,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FcSkeleton.line(width: 96),
              SizedBox(height: AppSpacing.sm),
              FcSkeleton.line(),
              SizedBox(height: AppSpacing.sm),
              FcSkeleton.line(width: 200),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

// MealRecordScreen は Riverpod のプロバイダーを使うので、プレビューは同じ部品を
// 静的なデータで並べたもの（`_MealRecordList` は画面と共通）。

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
  DateTime at(int hour, int minute, {int daysAgo = 0}) =>
      DateTime(now.year, now.month, now.day - daysAgo, hour, minute);

  MealRecord meal(
    String id,
    String type,
    DateTime recordedAt,
    String notes, {
    double? calories,
    double? protein,
    double? fat,
    double? carbs,
  }) =>
      MealRecord(
        id: id,
        clientId: 'client-1',
        mealType: type,
        notes: notes,
        calories: calories,
        proteinG: protein,
        fatG: fat,
        carbsG: carbs,
        estimatedByAi: calories != null,
        recordedAt: recordedAt,
        source: 'message',
        createdAt: recordedAt,
        updatedAt: recordedAt,
      );

  final records = [
    meal('1', 'lunch', at(12, 30), '鶏むね肉のグリル定食',
        calories: 640, protein: 38, fat: 18, carbs: 82),
    meal('2', 'breakfast', at(8, 10), 'ごはん・卵・ヨーグルト',
        calories: 520, protein: 27, fat: 14, carbs: 70),
  ];
  final todayRecords = empty || loading ? <MealRecord>[] : records;

  final weekStart = recordWeekStartOf(today);
  final counts = <DateTime, int>{
    if (!empty && !loading)
      for (var i = 0; i < 7; i++)
        if (!DateTime(weekStart.year, weekStart.month, weekStart.day + i)
            .isAfter(today))
          DateTime(weekStart.year, weekStart.month, weekStart.day + i):
              (i % 3) + 1,
  };
  final month = DateTime(today.year, today.month, 1);
  final recordedDays = <DateTime>{
    if (!empty && !loading)
      for (var day = 1; day <= today.day; day++)
        if (day % 3 != 0) DateTime(month.year, month.month, day),
  };

  final header = <Widget>[
    FcSegmentedControl<PeriodFilter>(
      items: const [
        FcSegmentedItem(value: PeriodFilter.today, label: '今日'),
        FcSegmentedItem(value: PeriodFilter.week, label: '今週'),
        FcSegmentedItem(value: PeriodFilter.month, label: '今月'),
        FcSegmentedItem(value: PeriodFilter.all, label: '全期間'),
      ],
      selected: PeriodFilter.week,
      onChanged: (_) {},
    ),
    MealSummaryCard(
      date: now,
      slots: MealSummaryCard.slotsFrom(todayRecords),
      loading: loading,
    ),
    MealWeekCard(today: today, counts: loading ? null : counts),
    RecordMonthCard(
      month: month,
      recordedDays: loading ? null : recordedDays,
      onPreviousMonth: () {},
    ),
    const FcSectionTitle('記録一覧'),
  ];

  final _ListBody body;
  if (loading) {
    body = _ListBody(count: 2, builder: (_, __) => const _MealCardSkeleton());
  } else if (empty) {
    body = _ListBody.single(_MealEmptyMessage(onOpenMessages: () {}));
  } else {
    body = _ListBody(
      count: records.length,
      builder: (_, i) => MealCard(record: records[i]),
    );
  }

  return _previewApp(
    brightness,
    textScale,
    _MealRecordList(header: header, body: body),
  );
}

@Preview(name: 'MealRecordScreen - 通常')
Widget previewMealRecordScreen() =>
    _previewScreen(brightness: Brightness.light);

@Preview(name: 'MealRecordScreen - ダーク')
Widget previewMealRecordScreenDark() =>
    _previewScreen(brightness: Brightness.dark);

@Preview(name: 'MealRecordScreen - 記録なし')
Widget previewMealRecordScreenEmpty() =>
    _previewScreen(brightness: Brightness.light, empty: true);

@Preview(name: 'MealRecordScreen - 読込中')
Widget previewMealRecordScreenLoading() =>
    _previewScreen(brightness: Brightness.light, loading: true);

@Preview(name: 'MealRecordScreen - 文字拡大 1.35')
Widget previewMealRecordScreenLargeText() =>
    _previewScreen(brightness: Brightness.light, textScale: 1.35);
