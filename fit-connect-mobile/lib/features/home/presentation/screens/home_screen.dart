import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/utils/home_formatting.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/coach_comment_card.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/daily_summary_card.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/goal_card.dart';
import 'package:fit_connect_mobile/features/home/providers/latest_trainer_comment_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/getting_started_card.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/next_session_card.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// ホームタブ。
///
/// 正本: home-screens.js の `HomeScreen`。見出し（日付・挨拶）→（はじめて: はじめの3ステップ）→
/// 目標 → 担当トレーナーの最新コメント → 次回のセッション → 今日のまとめ。カード間は 16。
class HomeScreen extends ConsumerWidget {
  final void Function(int tabIndex)? onNavigateToRecordsTab;
  final VoidCallback? onNavigateToMessages;

  /// セッションについてトレーナーへ相談する導線。
  /// draft はメッセージ入力欄へ流し込む定型文（空文字なら定型文なし）
  final void Function(String draft)? onConsultAboutSession;

  const HomeScreen({
    super.key,
    this.onNavigateToRecordsTab,
    this.onNavigateToMessages,
    this.onConsultAboutSession,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();

    final clientAsync = ref.watch(currentClientProvider);
    final goalAsync = ref.watch(currentGoalProvider);
    final latestWeightAsync = ref.watch(latestWeightRecordProvider);
    final trainer = ref.watch(trainerProfileProvider).valueOrNull;
    // メッセージ画面の購読（Realtime）は使わず、ホーム専用の軽い取得を使う
    final commentAsync = ref.watch(latestTrainerCommentProvider);

    final trainerLabel = trainerDisplayName(trainer?.name);
    final horizontal = AppSpacing.pageHorizontalOf(context);
    // ナビ（FcBottomNavLayout）が確保する下余白。内容はナビの下まで潜れるようにして、
    // スクロールの終端でナビの上に収まる
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    // Records tabs order: 0=サマリ, 1=体重, 2=食事, 3=運動, 4=睡眠, 5=ノート
    void goToRecords(int tabIndex) => onNavigateToRecordsTab?.call(tabIndex);
    final hasRecordsNav = onNavigateToRecordsTab != null;

    final children = <Widget>[
      // はじめの3ステップ（全達成 or 14日経過 or 手動クローズで非表示）。出るときだけ下に 16 を含む
      GettingStartedCard(
        onWeightTap: hasRecordsNav ? () => goToRecords(1) : null,
        onMessageTap: onNavigateToMessages,
      ),
      _buildGoalCard(ref, goalAsync, latestWeightAsync, trainerLabel),
      const SizedBox(height: AppSpacing.cardGap),
      _buildCoachComment(
        commentAsync,
        trainerLabel,
        trainer?.profileImageUrl,
        now,
      ),
      const SizedBox(height: AppSpacing.cardGap),
      NextSessionCard(
        trainerName: trainerLabel,
        onConsult: onConsultAboutSession,
      ),
      const SizedBox(height: AppSpacing.cardGap),
      DailySummaryCard(
        onMealsTap: hasRecordsNav ? () => goToRecords(2) : null,
        onWeightTap: hasRecordsNav ? () => goToRecords(1) : null,
        onActivityTap: hasRecordsNav ? () => goToRecords(3) : null,
        onSleepTap: hasRecordsNav ? () => goToRecords(4) : null,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xs,
            horizontal,
            bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeading(clientAsync, now),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  /// 日付・挨拶・ひとこと。名前が取れる前は「こんにちは」
  Widget _buildHeading(AsyncValue<Client?> clientAsync, DateTime now) {
    final name = clientAsync.valueOrNull?.name.trim();
    return FcPageHeading(
      eyebrow: formatSessionDateDisplay(now, now: now),
      title: (name == null || name.isEmpty) ? 'こんにちは' : 'こんにちは、$nameさん',
      subtitle: '今日も、自分のペースで。',
    );
  }

  Widget _buildGoalCard(
    WidgetRef ref,
    AsyncValue<Client?> goalAsync,
    AsyncValue<WeightRecord?> latestWeightAsync,
    String trainerLabel,
  ) {
    return goalAsync.when(
      data: (goal) {
        // 目標体重が決まっていなければ「目標はまだ設定されていません」
        if (goal == null || goal.targetWeight == null) {
          return GoalNotSetCard(trainerName: trainerLabel);
        }
        return latestWeightAsync.when(
          data: (latestWeight) => _goalCardFor(goal, latestWeight?.weight),
          loading: () => const GoalCard.loading(),
          // 体重の取得に失敗しても、目標そのものは見せる（現在は開始時の体重で代用）
          error: (_, __) => _goalCardFor(goal, null),
        );
      },
      loading: () => const GoalCard.loading(),
      error: (_, __) => FcStateMessage.error(
        title: '目標を読み込めませんでした',
        actionLabel: '再試行',
        onAction: () => ref.invalidate(currentGoalProvider),
      ),
    );
  }

  GoalCard _goalCardFor(Client goal, double? latestWeight) {
    final targetWeight = goal.targetWeight!;
    final currentWeight = latestWeight ?? goal.initialWeight;

    // 達成判定: DBフラグ OR ローカル計算
    // 減量目標: initialWeight > targetWeight → currentWeight <= targetWeight で達成
    // 増量目標: initialWeight < targetWeight → currentWeight >= targetWeight で達成
    var isAchievedLocally = false;
    if (currentWeight != null) {
      final initial = goal.initialWeight ?? currentWeight;
      isAchievedLocally = initial > targetWeight
          ? currentWeight <= targetWeight
          : currentWeight >= targetWeight;
    }
    final isAchieved = goal.goalAchievedAt != null || isAchievedLocally;

    return GoalCard(
      currentWeight: currentWeight,
      targetWeight: targetWeight,
      initialWeight: goal.initialWeight,
      targetDate: goal.goalDeadline,
      isAchieved: isAchieved,
      goalDescription: goal.goalDescription,
      achievedAt: goal.goalAchievedAt,
    );
  }

  Widget _buildCoachComment(
    AsyncValue<LatestTrainerComment?> commentAsync,
    String trainerLabel,
    String? profileImageUrl,
    DateTime now,
  ) {
    return commentAsync.when(
      loading: () => const CoachCommentCard.loading(),
      error: (_, __) => CoachCommentCard.unavailable(
        coachName: trainerLabel,
        profileImageUrl: profileImageUrl,
        onOpenMessages: onNavigateToMessages,
      ),
      data: (latest) {
        if (latest == null) {
          return CoachCommentCard.empty(
            coachName: trainerLabel,
            profileImageUrl: profileImageUrl,
            onSendMessage: onNavigateToMessages,
          );
        }
        return CoachCommentCard(
          coachName: trainerLabel,
          profileImageUrl: profileImageUrl,
          contextLine: latest.contextLine(now: now),
          message: latest.body,
          onTap: onNavigateToMessages,
        );
      },
    );
  }
}

// ============================================
// Previews
// ============================================
// ホームは Riverpod のデータで組み立てるので、プレビューは同じ部品を静的に並べて再現する
// （正本の画面: 通常 / はじめて / 読込中 / 目標に届いた日）。

enum _HomePreviewVariant { normal, firstTime, loading, achieved }

class _PreviewHome extends StatelessWidget {
  const _PreviewHome(this.variant);

  final _HomePreviewVariant variant;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final horizontal = AppSpacing.pageHorizontalOf(context);
    final isNew = variant == _HomePreviewVariant.firstTime;
    final isLoading = variant == _HomePreviewVariant.loading;
    final isAchieved = variant == _HomePreviewVariant.achieved;
    const trainer = '田中トレーナー';

    final Widget goal;
    if (isLoading) {
      goal = const GoalCard.loading();
    } else if (isNew) {
      goal = const GoalNotSetCard(trainerName: trainer);
    } else if (isAchieved) {
      goal = GoalCard(
        currentWeight: 65.0,
        targetWeight: 65.0,
        initialWeight: 61.0,
        isAchieved: true,
        goalDescription: '筋肉をつけて体重を増やす',
        achievedAt: DateTime(now.year, 12, 2),
      );
    } else {
      goal = GoalCard(
        currentWeight: 62.4,
        targetWeight: 65.0,
        initialWeight: 61.0,
        targetDate: DateTime(now.year, 12, 31),
        goalDescription: '筋肉をつけて体重を増やす',
      );
    }

    final Widget coach;
    if (isLoading) {
      coach = const CoachCommentCard.loading();
    } else if (isNew) {
      coach = CoachCommentCard.empty(coachName: trainer, onSendMessage: () {});
    } else {
      coach = CoachCommentCard(
        coachName: trainer,
        contextLine:
            isAchieved ? '体重の記録へのコメント · 8:02' : '朝食の記録へのコメント · 9:10',
        message: isAchieved
            ? 'おめでとうございます。ここまで一緒に続けてきた成果ですね。次の目標は、次回のセッションで相談しましょう。'
            : '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
        onTap: () {},
      );
    }

    final Widget session;
    if (isLoading) {
      session = const NextSessionCardView.loading();
    } else if (isNew) {
      session = NextSessionCardView.empty(
        trainerName: trainer,
        onTap: () {},
        onConsult: () {},
        onOpenList: () {},
      );
    } else {
      final fromNow = Duration(days: isAchieved ? 6 : 2);
      session = NextSessionCardView.session(
        session: SessionModel(
          id: 'preview',
          trainerId: 't',
          clientId: 'c',
          sessionDate: DateTime(now.year, now.month, now.day, 19)
              .add(fromNow),
          durationMinutes: 60,
          status: 'confirmed',
          sessionType: 'パーソナル',
          createdAt: now,
          updatedAt: now,
        ),
        now: now,
        onTap: () {},
      );
    }

    final DailySummaryCardBody summary;
    if (isLoading) {
      summary = DailySummaryCardBody(
        meals: const SummaryRowData.loading(),
        exercise: SummaryRowData.loading(sub: formatWeekStartLabel(now)),
        weight: const SummaryRowData.loading(),
        sleep: const SummaryRowData.loading(),
      );
    } else if (isNew) {
      summary = DailySummaryCardBody(
        meals: const SummaryRowData.missing(sub: 'メッセージから記録できます'),
        exercise: SummaryRowData.missing(sub: formatWeekStartLabel(now)),
        weight: const SummaryRowData.missing(),
        sleep: const SummaryRowData.action(
          '目覚めを記録',
          sub: 'ヘルスケアと連携すると自動で入ります',
        ),
        onMealsTap: () {},
        onActivityTap: () {},
        onWeightTap: () {},
        onSleepTap: () {},
        onSleepRecord: () {},
      );
    } else {
      summary = DailySummaryCardBody(
        meals: SummaryRowData.value([const FcValuePart('2', '回')]),
        exercise: SummaryRowData.value(
          [const FcValuePart('3', '日')],
          sub: formatWeekStartLabel(now),
        ),
        weight: SummaryRowData.value(
          [FcValuePart(isAchieved ? '65.0' : '62.4', 'kg')],
          sub: '前回から +0.1 kg · 7:30',
        ),
        sleep: const SummaryRowData.value(
          [FcValuePart('7', '時間'), FcValuePart('30', '分')],
          sub: 'HealthKit',
        ),
        onMealsTap: () {},
        onActivityTap: () {},
        onWeightTap: () {},
        onSleepTap: () {},
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.xs,
            horizontal,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FcPageHeading(
                eyebrow: formatSessionDateDisplay(now, now: now),
                title: isLoading ? 'こんにちは' : 'こんにちは、佐藤さん',
                subtitle: '今日も、自分のペースで。',
              ),
              if (isNew) ...[
                GettingStartedCardBody(
                  doneCount: 1,
                  totalCount: 3,
                  onClose: () {},
                  items: [
                    GettingStartedItem(
                      label: '最初の体重を記録する',
                      isDone: true,
                      onTap: () {},
                    ),
                    GettingStartedItem(
                      label: 'トレーナーにメッセージを送る',
                      isDone: false,
                      onTap: () {},
                    ),
                    GettingStartedItem(
                      label: 'ヘルスケアと連携する',
                      isDone: false,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.cardGap),
              ],
              goal,
              const SizedBox(height: AppSpacing.cardGap),
              coach,
              const SizedBox(height: AppSpacing.cardGap),
              session,
              const SizedBox(height: AppSpacing.cardGap),
              summary,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _previewApp(
  _HomePreviewVariant variant, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: _PreviewHome(variant),
  );
}

@Preview(name: 'HomeScreen - 通常（静的）')
Widget previewHomeScreenNormal() => _previewApp(_HomePreviewVariant.normal);

@Preview(name: 'HomeScreen - はじめて（静的）')
Widget previewHomeScreenFirstTime() =>
    _previewApp(_HomePreviewVariant.firstTime);

@Preview(name: 'HomeScreen - 読み込み中（静的）')
Widget previewHomeScreenLoading() => _previewApp(_HomePreviewVariant.loading);

@Preview(name: 'HomeScreen - 目標に届いた日（静的）')
Widget previewHomeScreenAchieved() =>
    _previewApp(_HomePreviewVariant.achieved);

@Preview(name: 'HomeScreen - ダーク（静的）')
Widget previewHomeScreenDark() => _previewApp(
      _HomePreviewVariant.normal,
      brightness: Brightness.dark,
    );

@Preview(name: 'HomeScreen - 文字 1.35（静的）')
Widget previewHomeScreenLargeText() => _previewApp(
      _HomePreviewVariant.normal,
      textScale: 1.35,
    );
