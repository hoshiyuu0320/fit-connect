import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/utils/home_formatting.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/providers/record_streak_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_record_sheet.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/widgets/weight_format.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:fit_connect_mobile/shared/utils/health_source_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

// ============================================
// 今日のまとめ
// 正本: home-screens.js の `HomeSummary` / `SumRow`
// 食事・運動・体重・睡眠を 4 行の一覧で示す。カテゴリごとの色・絵文字・進捗バーはやめ、
// アイコンと言葉で区別する。各行は押すと記録タブの該当サブタブへ。
// 先頭に「記録の連続」の行を足す（フェーズ10.3。設計: docs/superpowers/specs/2026-11-23-record-streak-design.md §6.4）。
// 移る先が無いので押せない（矢印も出さない）。読めないときは行ごと出さない。
// ============================================

/// 「今日のまとめ」の 1 行の中身（右側の値と補足）。
enum SummaryRowKind { loading, value, text, missing, action }

@immutable
class SummaryRowData {
  const SummaryRowData._(
    this.kind, {
    this.parts = const [],
    this.text,
    this.sub,
  });

  /// 読み込み中（値はスケルトン。配置は保つ）
  const SummaryRowData.loading({String? sub})
      : this._(SummaryRowKind.loading, sub: sub);

  /// 数値＋単位（`2 回`、`7 時間 30 分`）
  const SummaryRowData.value(List<FcValuePart> parts, {String? sub})
      : this._(SummaryRowKind.value, parts: parts, sub: sub);

  /// 文字の値（目覚めの評価など）
  const SummaryRowData.text(String text, {String? sub})
      : this._(SummaryRowKind.text, text: text, sub: sub);

  /// 値が無い（0 とは表示しない）。既定は「未記録」
  const SummaryRowData.missing({String text = '未記録', String? sub})
      : this._(SummaryRowKind.missing, text: text, sub: sub);

  /// 右に accent の操作文字（睡眠の「目覚めを記録」）
  const SummaryRowData.action(String label, {String? sub})
      : this._(SummaryRowKind.action, text: label, sub: sub);

  final SummaryRowKind kind;
  final List<FcValuePart> parts;
  final String? text;
  final String? sub;
}

/// ホームの「今日のまとめ」カード（データを取得して [DailySummaryCardBody] に渡す）。
///
/// 操作（記録タブの各サブタブへの遷移・睡眠の「目覚めを記録」ダイアログ）は従来どおり。
/// 先頭の「記録の連続」は [recordStreakViewProvider] から作る（[streakRowDataOf]）。
class DailySummaryCard extends ConsumerWidget {
  final VoidCallback? onMealsTap;
  final VoidCallback? onActivityTap;
  final VoidCallback? onWeightTap;
  final VoidCallback? onSleepTap;

  const DailySummaryCard({
    super.key,
    this.onMealsTap,
    this.onActivityTap,
    this.onWeightTap,
    this.onSleepTap,
  });

  /// 「前回から」の差を出すために読む体重記録の期間
  static const PeriodFilter weightHistoryPeriod = PeriodFilter.threeMonths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final mealCount = ref.watch(todayMealCountProvider);
    final exerciseCount = ref.watch(weeklyExerciseCountProvider);
    final latestWeight = ref.watch(latestWeightRecordProvider);
    final weightHistory =
        ref.watch(weightRecordsProvider(period: weightHistoryPeriod));
    final todaySleep = ref.watch(todaySleepRecordProvider);
    final streak = ref.watch(recordStreakViewProvider);

    return DailySummaryCardBody(
      streak: streakRowDataOf(streak),
      meals: _mealRow(mealCount),
      exercise: _exerciseRow(exerciseCount, now),
      weight: _weightRow(latestWeight, weightHistory.valueOrNull, now),
      sleep: _sleepRow(todaySleep),
      onMealsTap: onMealsTap,
      onActivityTap: onActivityTap,
      onWeightTap: onWeightTap,
      onSleepTap: onSleepTap,
      onSleepRecord: () => showWakeupRecordSheet(context, ref),
    );
  }

  /// 「記録の連続」の行の中身（設計 §6.4）。null なら行を出さない。
  ///
  /// - 今日記録済み → `12 日`・「今日も記録しました」（1 日目は `1 日`・「今日記録しました」）
  /// - 今日まだ・昨日まで続いている → `12 日`・「今日記録すると13日」
  /// - 続いていない → 「これから」・「今日記録すると1日目」。0 とは出さない
  ///   （ほかの行の「未記録」と同じ弱い文字色）
  /// - 読み込み中 → スケルトン（補足なし）
  /// - 読めない（オフライン・関数がまだ無い DB など）・ログインしていない（null）→ 行を出さない
  ///
  /// 値があれば値を出す。[recordStreakViewProvider] が前の値を残すのは読み直し（invalidate）の間だけ
  /// （前の値の AsyncData・isRefreshing。行はスケルトンに戻らず、ちらつかない）。
  /// 読み直しに失敗したとき・client id が変わったときは、前の値を持たない AsyncError / AsyncLoading が
  /// 来るので、行を消す / スケルトンにする（前の値・前の人の値は出さない）。
  /// 読めなかったあとの読み直しの間（値の無いエラーのまま読み込み中）は、スケルトンを出さずに隠したままにする
  static SummaryRowData? streakRowDataOf(AsyncValue<RecordStreakView?> async) {
    if (async.hasValue) {
      final view = async.valueOrNull;
      return view == null ? null : _streakRow(view);
    }
    if (async.hasError) return null;
    return const SummaryRowData.loading();
  }

  static SummaryRowData _streakRow(RecordStreakView view) {
    return switch (view) {
      RecordStreakRecordedToday(:final days) => SummaryRowData.value(
          [FcValuePart('$days', '日')],
          sub: days == 1 ? '今日記録しました' : '今日も記録しました',
        ),
      RecordStreakAlive(:final days) => SummaryRowData.value(
          [FcValuePart('$days', '日')],
          sub: '今日記録すると${days + 1}日',
        ),
      RecordStreakNone() => const SummaryRowData.missing(
          text: 'これから',
          sub: '今日記録すると1日目',
        ),
    };
  }

  static SummaryRowData _mealRow(AsyncValue<int> async) {
    return async.when(
      data: (count) => count > 0
          ? SummaryRowData.value([FcValuePart('$count', '回')])
          : const SummaryRowData.missing(sub: 'メッセージから記録できます'),
      loading: () => const SummaryRowData.loading(),
      error: (_, __) => const SummaryRowData.missing(text: '未取得'),
    );
  }

  static SummaryRowData _exerciseRow(AsyncValue<int> async, DateTime now) {
    final week = formatWeekStartLabel(now);
    return async.when(
      data: (count) => count > 0
          ? SummaryRowData.value([FcValuePart('$count', '日')], sub: week)
          : SummaryRowData.missing(sub: week),
      loading: () => SummaryRowData.loading(sub: week),
      error: (_, __) => SummaryRowData.missing(text: '未取得', sub: week),
    );
  }

  static SummaryRowData _weightRow(
    AsyncValue<WeightRecord?> latestAsync,
    List<WeightRecord>? history,
    DateTime now,
  ) {
    return latestAsync.when(
      data: (latest) {
        if (latest == null) return const SummaryRowData.missing();
        return SummaryRowData.value(
          [FcValuePart(formatKg(latest.weight), 'kg')],
          sub: weightSubLabel(latest: latest, history: history, now: now),
        );
      },
      loading: () => const SummaryRowData.loading(),
      error: (_, __) => const SummaryRowData.missing(text: '未取得'),
    );
  }

  /// 体重の補足。「前回から +0.1 kg · 7:30」。前回の記録が見つからなければ時刻だけ。
  ///
  /// 増減は符号だけで、色分けも良し悪しの言葉も付けない。
  static String weightSubLabel({
    required WeightRecord latest,
    required List<WeightRecord>? history,
    required DateTime now,
  }) {
    final time = formatHomeTime(latest.recordedAt, now: now);
    WeightRecord? previous;
    for (final r in history ?? const <WeightRecord>[]) {
      if (r.id == latest.id || r.recordedAt.isAfter(latest.recordedAt)) {
        continue;
      }
      if (previous == null || r.recordedAt.isAfter(previous.recordedAt)) {
        previous = r;
      }
    }
    if (previous == null) return time;
    final signed = formatSignedKg(latest.weight - previous.weight);
    final change = signed == '0.0' ? '前回と同じ' : '前回から $signed kg';
    return '$change · $time';
  }

  static SummaryRowData _sleepRow(AsyncValue<SleepRecord?> async) {
    const hint = 'ヘルスケアと連携すると自動で入ります';
    return async.when(
      data: (record) {
        if (record != null && record.hasObjectiveData) {
          final minutes = record.totalSleepMinutes!;
          final h = minutes ~/ 60;
          final m = minutes % 60;
          return SummaryRowData.value(
            [
              if (h > 0) FcValuePart('$h', '時間'),
              FcValuePart('$m', '分'),
            ],
            sub: healthSourceName(),
          );
        }
        final rating = record?.wakeupRating;
        if (rating != null) {
          return SummaryRowData.text(rating.labelJa, sub: '目覚めの記録');
        }
        return const SummaryRowData.action('目覚めを記録', sub: hint);
      },
      loading: () => const SummaryRowData.loading(),
      error: (_, __) => const SummaryRowData.action('目覚めを記録', sub: hint),
    );
  }
}

/// 「今日のまとめ」の見た目だけを担当する部分（プレビュー・テストでも使える）。
class DailySummaryCardBody extends StatelessWidget {
  const DailySummaryCardBody({
    super.key,
    this.streak,
    required this.meals,
    required this.exercise,
    required this.weight,
    required this.sleep,
    this.onMealsTap,
    this.onActivityTap,
    this.onWeightTap,
    this.onSleepTap,
    this.onSleepRecord,
  });

  /// 先頭の「記録の連続」（押せない行）。null なら行を出さない（読めない・ログインしていない）
  final SummaryRowData? streak;

  final SummaryRowData meals;
  final SummaryRowData exercise;
  final SummaryRowData weight;
  final SummaryRowData sleep;

  final VoidCallback? onMealsTap;
  final VoidCallback? onActivityTap;
  final VoidCallback? onWeightTap;
  final VoidCallback? onSleepTap;

  /// 睡眠が未記録のときの「目覚めを記録」
  final VoidCallback? onSleepRecord;

  @override
  Widget build(BuildContext context) {
    final streak = this.streak;
    return FcRowsCard(
      title: '今日のまとめ',
      padding: FcRowsCard.summaryPadding,
      children: [
        // 移る先が無いので押せない（矢印も出さない）。読み上げは行全体で 1 文
        if (streak != null)
          _SummaryRow(
            icon: LucideIcons.flame,
            title: '記録の連続',
            data: streak,
            readAsSentence: true,
          ),
        _SummaryRow(
          icon: LucideIcons.utensils,
          title: '食事',
          data: meals,
          onTap: onMealsTap,
        ),
        _SummaryRow(
          icon: LucideIcons.dumbbell,
          title: '運動',
          data: exercise,
          onTap: onActivityTap,
        ),
        _SummaryRow(
          icon: LucideIcons.scale,
          title: '体重',
          data: weight,
          onTap: onWeightTap,
        ),
        _SummaryRow(
          icon: LucideIcons.moon,
          title: '睡眠',
          data: sleep,
          onTap: onSleepTap,
          onAction: onSleepRecord,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.data,
    this.onTap,
    this.onAction,
    this.readAsSentence = false,
  });

  final IconData icon;
  final String title;
  final SummaryRowData data;
  final VoidCallback? onTap;

  /// [SummaryRowKind.action] の操作
  final VoidCallback? onAction;

  /// 読み上げを「見出し、値。補足」の 1 文にする（押せない「記録の連続」の行。
  /// 例:「記録の連続、12日。今日記録すると13日」「記録の連続、読み込み中」）。
  /// false の行（食事・運動・体重・睡眠）の読み上げは今までどおり
  final bool readAsSentence;

  @override
  Widget build(BuildContext context) {
    final isAction = data.kind == SummaryRowKind.action;
    final Widget trailing;
    switch (data.kind) {
      case SummaryRowKind.loading:
        trailing = const FcRowValue.loading();
      case SummaryRowKind.value:
        trailing = FcRowValue.metric(data.parts);
      case SummaryRowKind.text:
        trailing = FcRowValue.text(data.text!);
      case SummaryRowKind.missing:
        trailing = FcRowValue.missing(text: data.text!);
      case SummaryRowKind.action:
        final value = FcRowValue.action(data.text!);
        // 行全体（記録タブへ）とは別に、右の文字だけを押して記録できる。
        // 内側のタップが優先される。押せる範囲は 44×44 以上
        trailing = onAction == null
            ? value
            : FcPressable(
                onTap: onAction,
                semanticLabel: data.text,
                minSize: const Size.square(AppSizes.minTouch),
                child: value,
              );
    }

    final String? semanticLabel;
    if (isAction) {
      // 操作を含む行は、読み上げを「未記録」としてまとめ、記録の操作は別の操作として足す
      semanticLabel = [title, if (data.sub != null) data.sub!, '未記録'].join('、');
    } else if (readAsSentence && trailing is FcRowValue) {
      // 値の読み上げ（「12日」「これから」「読み込み中」）は FcRowValue と同じ言葉を使う
      final sub = data.sub;
      semanticLabel =
          '$title、${trailing.semanticText}${sub == null ? '' : '。$sub'}';
    } else {
      semanticLabel = null;
    }

    final row = FcListRow(
      density: FcRowDensity.summary,
      icon: icon,
      title: title,
      caption: data.sub,
      trailing: trailing,
      onTap: onTap,
      semanticLabel: semanticLabel,
    );

    if (isAction && onAction != null && onTap != null) {
      return Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: data.text!): onAction!,
        },
        child: row,
      );
    }
    return row;
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: child,
        ),
      ),
    ),
  );
}

DailySummaryCardBody _previewBody({
  SummaryRowData? streak,
  SummaryRowData? meals,
  SummaryRowData? exercise,
  SummaryRowData? weight,
  SummaryRowData? sleep,
}) {
  return DailySummaryCardBody(
    streak: streak,
    meals: meals ?? SummaryRowData.value([const FcValuePart('2', '回')]),
    exercise: exercise ??
        const SummaryRowData.value(
          [FcValuePart('3', '日')],
          sub: '今週（9/7〜）',
        ),
    weight: weight ??
        const SummaryRowData.value(
          [FcValuePart('62.4', 'kg')],
          sub: '前回から +0.1 kg · 7:30',
        ),
    sleep: sleep ??
        SummaryRowData.value(
          const [FcValuePart('7', '時間'), FcValuePart('30', '分')],
          sub: healthSourceName(),
        ),
    onMealsTap: () {},
    onActivityTap: () {},
    onWeightTap: () {},
    onSleepTap: () {},
    onSleepRecord: () {},
  );
}

@Preview(name: 'DailySummaryCard - 通常')
Widget previewDailySummaryCardNormal() => _previewApp(_previewBody());

@Preview(name: 'DailySummaryCard - はじめて（未記録）')
Widget previewDailySummaryCardNew() {
  return _previewApp(
    _previewBody(
      meals: const SummaryRowData.missing(sub: 'メッセージから記録できます'),
      exercise: const SummaryRowData.missing(sub: '今週（9/7〜）'),
      weight: const SummaryRowData.missing(),
      sleep: const SummaryRowData.action(
        '目覚めを記録',
        sub: 'ヘルスケアと連携すると自動で入ります',
      ),
    ),
  );
}

@Preview(name: 'DailySummaryCard - 読み込み中')
Widget previewDailySummaryCardLoading() {
  return _previewApp(
    _previewBody(
      meals: const SummaryRowData.loading(),
      exercise: const SummaryRowData.loading(sub: '今週（9/7〜）'),
      weight: const SummaryRowData.loading(),
      sleep: const SummaryRowData.loading(),
    ),
  );
}

@Preview(name: 'DailySummaryCard - 睡眠は目覚めの記録')
Widget previewDailySummaryCardSleepManual() {
  return _previewApp(
    _previewBody(
      sleep: const SummaryRowData.text('すっきり', sub: '目覚めの記録'),
    ),
  );
}

@Preview(name: 'DailySummaryCard - ダーク / 文字 1.35')
Widget previewDailySummaryCardDarkLarge() {
  return _previewApp(
    _previewBody(),
    brightness: Brightness.dark,
    textScale: 1.35,
  );
}

// 記録の連続（先頭の行）。中身は画面と同じ変換（DailySummaryCard.streakRowDataOf）で作る

SummaryRowData? _previewStreak(RecordStreakView view) =>
    DailySummaryCard.streakRowDataOf(AsyncData(view));

/// 今日まだ自分で記録していない日（体重は昨日、睡眠はヘルスケアから。どちらも今日の分に数えない）
DailySummaryCardBody _previewStreakAliveBody() {
  return _previewBody(
    streak: _previewStreak(const RecordStreakAlive(days: 12)),
    meals: const SummaryRowData.missing(sub: 'メッセージから記録できます'),
    weight: const SummaryRowData.value(
      [FcValuePart('62.4', 'kg')],
      sub: '前回から +0.1 kg · 9月12日 7:30',
    ),
  );
}

@Preview(name: 'DailySummaryCard - 記録の連続（今日記録済み）')
Widget previewDailySummaryCardStreakRecordedToday() {
  return _previewApp(
    _previewBody(
      streak: _previewStreak(const RecordStreakRecordedToday(days: 12)),
    ),
  );
}

@Preview(name: 'DailySummaryCard - 記録の連続（今日まだ）')
Widget previewDailySummaryCardStreakAlive() =>
    _previewApp(_previewStreakAliveBody());

@Preview(name: 'DailySummaryCard - 記録の連続（これから）')
Widget previewDailySummaryCardStreakNone() {
  return _previewApp(
    _previewBody(
      streak: _previewStreak(const RecordStreakNone()),
      meals: const SummaryRowData.missing(sub: 'メッセージから記録できます'),
      exercise: const SummaryRowData.missing(sub: '今週（9/7〜）'),
      weight: const SummaryRowData.missing(),
      sleep: const SummaryRowData.action(
        '目覚めを記録',
        sub: 'ヘルスケアと連携すると自動で入ります',
      ),
    ),
  );
}

@Preview(name: 'DailySummaryCard - 記録の連続（読み込み中）')
Widget previewDailySummaryCardStreakLoading() {
  return _previewApp(
    _previewBody(
      streak: DailySummaryCard.streakRowDataOf(const AsyncLoading()),
      meals: const SummaryRowData.loading(),
      exercise: const SummaryRowData.loading(sub: '今週（9/7〜）'),
      weight: const SummaryRowData.loading(),
      sleep: const SummaryRowData.loading(),
    ),
  );
}

@Preview(name: 'DailySummaryCard - 記録の連続（今日まだ）ダーク')
Widget previewDailySummaryCardStreakAliveDark() {
  return _previewApp(
    _previewStreakAliveBody(),
    brightness: Brightness.dark,
  );
}

@Preview(name: 'DailySummaryCard - 記録の連続（1 日目）ダーク / 文字 2.0')
Widget previewDailySummaryCardStreakFirstDayDarkLarge() {
  return _previewApp(
    _previewBody(
      streak: _previewStreak(const RecordStreakRecordedToday(days: 1)),
    ),
    brightness: Brightness.dark,
    textScale: 2.0,
  );
}
