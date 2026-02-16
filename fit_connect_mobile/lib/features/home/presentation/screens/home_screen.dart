import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/goal_card.dart';
import 'package:fit_connect_mobile/features/home/presentation/widgets/daily_summary_card.dart';

class HomeScreen extends ConsumerWidget {
  final void Function(int tabIndex)? onNavigateToRecordsTab;

  const HomeScreen({
    super.key,
    this.onNavigateToRecordsTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();

    // Fetch client data
    final clientAsync = ref.watch(currentClientProvider);
    final goalAsync = ref.watch(currentGoalProvider);
    final latestWeightAsync = ref.watch(latestWeightRecordProvider);
    final achievementRateAsync = ref.watch(achievementRateProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              _buildGreeting(now, clientAsync),

              const SizedBox(height: 24),

              // Goal Card
              _buildGoalCard(
                goalAsync,
                latestWeightAsync,
                achievementRateAsync,
              ),

              const SizedBox(height: 24),

              // Daily Summary
              DailySummaryCard(
                onMealsTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(1)
                    : null,
                onWeightTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(0)
                    : null,
                onActivityTap: onNavigateToRecordsTab != null
                    ? () => onNavigateToRecordsTab!(2)
                    : null,
              ),

              const SizedBox(height: 100), // Bottom padding for FAB/Nav
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(DateTime now, AsyncValue clientAsync) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDateTop(now),
            style: const TextStyle(
              color: AppColors.slate500,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          clientAsync.when(
            data: (client) => Text(
              'こんにちは、${client?.name ?? ''}さん 👋',
              style: const TextStyle(
                color: AppColors.slate800,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            loading: () => const Text(
              'こんにちは 👋',
              style: TextStyle(
                color: AppColors.slate800,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            error: (_, __) => const Text(
              'こんにちは 👋',
              style: TextStyle(
                color: AppColors.slate800,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '今日も頑張りましょう！',
            style: TextStyle(
              color: AppColors.slate600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard(
    AsyncValue goalAsync,
    AsyncValue latestWeightAsync,
    AsyncValue achievementRateAsync,
  ) {
    return goalAsync.when(
      data: (goal) {
        if (goal == null) {
          return _buildNoGoalCard();
        }

        return latestWeightAsync.when(
          data: (latestWeight) {
            final currentWeight =
                latestWeight?.weight ?? goal.initialWeight ?? 0.0;
            final targetWeight = goal.targetWeight ?? 0.0;
            final initialWeight = goal.initialWeight ?? currentWeight;

            // 達成判定: DBフラグ OR ローカル計算
            // 減量目標: initialWeight > targetWeight → currentWeight <= targetWeight で達成
            // 増量目標: initialWeight < targetWeight → currentWeight >= targetWeight で達成
            final isAchievedLocally = initialWeight > targetWeight
                ? currentWeight <= targetWeight
                : currentWeight >= targetWeight;
            final isAchieved = goal.goalAchievedAt != null || isAchievedLocally;

            return GoalCard(
              currentWeight: currentWeight,
              targetWeight: targetWeight,
              initialWeight: initialWeight,
              targetDate: goal.goalDeadline,
              isAchieved: isAchieved,
            );
          },
          loading: () => GoalCard(
            currentWeight: goal.initialWeight ?? 0.0,
            targetWeight: goal.targetWeight ?? 0.0,
            initialWeight: goal.initialWeight ?? 0.0,
            targetDate: goal.goalDeadline,
            isLoading: true,
            isAchieved: goal.goalAchievedAt != null,
          ),
          error: (_, __) => GoalCard(
            currentWeight: goal.initialWeight ?? 0.0,
            targetWeight: goal.targetWeight ?? 0.0,
            initialWeight: goal.initialWeight ?? 0.0,
            targetDate: goal.goalDeadline,
            isAchieved: goal.goalAchievedAt != null,
          ),
        );
      },
      loading: () => _buildLoadingGoalCard(),
      error: (_, __) => _buildNoGoalCard(),
    );
  }

  Widget _buildNoGoalCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.slate400, AppColors.slate500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目標未設定',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'トレーナーに目標を設定してもらいましょう！',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingGoalCard() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary600, AppColors.primary700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }

  String _formatDateTop(DateTime date) {
    const days = ['日', '月', '火', '水', '木', '金', '土'];
    const months = [
      '1月',
      '2月',
      '3月',
      '4月',
      '5月',
      '6月',
      '7月',
      '8月',
      '9月',
      '10月',
      '11月',
      '12月'
    ];
    return '${months[date.month - 1]}${date.day}日（${days[date.weekday % 7]}）';
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'HomeScreen - Static Preview')
Widget previewHomeScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting Preview
              _PreviewGreeting(),
              const SizedBox(height: 24),
              // Goal Card Preview
              _PreviewGoalCard(),
              const SizedBox(height: 24),
              // Daily Summary Preview
              _PreviewDailySummaryCard(),
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'HomeScreen - No Goal')
Widget previewHomeScreenNoGoal() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewGreeting(),
              const SizedBox(height: 24),
              _PreviewNoGoalCard(),
              const SizedBox(height: 24),
              _PreviewDailySummaryCard(),
            ],
          ),
        ),
      ),
    ),
  );
}

// Preview helper widgets
class _PreviewGreeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const days = ['日', '月', '火', '水', '木', '金', '土'];
    const months = [
      '1月',
      '2月',
      '3月',
      '4月',
      '5月',
      '6月',
      '7月',
      '8月',
      '9月',
      '10月',
      '11月',
      '12月'
    ];
    final dateStr =
        '${months[now.month - 1]}${now.day}日（${days[now.weekday % 7]}）';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: const TextStyle(
              color: AppColors.slate500,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'こんにちは、太郎さん 👋',
            style: TextStyle(
              color: AppColors.slate800,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '今日も頑張りましょう！',
            style: TextStyle(
              color: AppColors.slate600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewGoalCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GoalCard(
      currentWeight: 65.2,
      targetWeight: 60.0,
      initialWeight: 67.5,
      targetDate: DateTime(2026, 3, 15),
    );
  }
}

class _PreviewNoGoalCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.slate400, AppColors.slate500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '目標未設定',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'トレーナーに目標を設定してもらいましょう！',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewDailySummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Static preview without Riverpod
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '今日のまとめ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.slate400, size: 20),
            ],
          ),
          const SizedBox(height: 24),
          // Meal Section (2/3)
          _buildMealRow(2),
          const SizedBox(height: 16),
          // Activity Section (3/7)
          _buildActivityRow(3),
          const Divider(height: 32, color: AppColors.slate50),
          // Weight Section
          _buildWeightRow(65.2, -0.6),
        ],
      ),
    );
  }

  Widget _buildMealRow(int count) {
    final progress = count / 3;
    final percentage = (progress * 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: AppColors.orange100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant, color: AppColors.orange500, size: 16),
                ),
                const SizedBox(width: 10),
                const Text('食事', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate700, fontSize: 14)),
              ],
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: '$count', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate800, fontSize: 14)),
                  const TextSpan(text: '/3', style: TextStyle(color: AppColors.slate400, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 42),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.slate100,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange500),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text('$percentage% 記録済み', style: const TextStyle(color: AppColors.slate400, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRow(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.primary100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.fitness_center, color: AppColors.primary500, size: 16),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('運動', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate700, fontSize: 14)),
                Text('今週', style: TextStyle(color: AppColors.slate400, fontSize: 10)),
              ],
            ),
          ],
        ),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(text: '$count ', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate800, fontSize: 14)),
              const TextSpan(text: '/ 7日', style: TextStyle(color: AppColors.slate400, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeightRow(double weight, double change) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.emerald100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monitor_weight, color: AppColors.emerald500, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('体重', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate700, fontSize: 14)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${weight.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.slate800, fontSize: 14)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: change < 0 ? AppColors.emerald50 : AppColors.rose100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}kg 前日比',
                style: TextStyle(color: change < 0 ? AppColors.emerald500 : AppColors.rose800, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
