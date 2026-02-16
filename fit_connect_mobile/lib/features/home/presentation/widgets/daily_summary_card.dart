import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DailySummaryCard extends ConsumerWidget {
  final VoidCallback? onMealsTap;
  final VoidCallback? onActivityTap;
  final VoidCallback? onWeightTap;

  const DailySummaryCard({
    super.key,
    this.onMealsTap,
    this.onActivityTap,
    this.onWeightTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayMealCountAsync = ref.watch(todayMealCountProvider);
    final weeklyExerciseCountAsync = ref.watch(weeklyExerciseCountProvider);
    final latestWeightAsync = ref.watch(latestWeightRecordProvider);
    final weightStatsAsync =
        ref.watch(weightStatsProvider(period: PeriodFilter.week));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          const Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.slate800,
            ),
          ),

          const SizedBox(height: 24),

          // Meal Section
          _buildTappableSection(
            onTap: onMealsTap,
            child: _buildMealSection(todayMealCountAsync),
          ),

          const SizedBox(height: 16),

          // Workout Section
          _buildTappableSection(
            onTap: onActivityTap,
            child: _buildWorkoutSection(weeklyExerciseCountAsync),
          ),

          const Divider(height: 32, color: AppColors.slate50),

          // Weight Section
          _buildTappableSection(
            onTap: onWeightTap,
            child: _buildWeightSection(latestWeightAsync, weightStatsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildTappableSection({
    required VoidCallback? onTap,
    required Widget child,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.primary100,
        highlightColor: AppColors.slate50,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(child: child),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    LucideIcons.chevronRight,
                    color: AppColors.slate300,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMealSection(AsyncValue<int> todayMealCountAsync) {
    return todayMealCountAsync.when(
      data: (count) {
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
                      child: const Icon(LucideIcons.utensils,
                          color: AppColors.orange500, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '食事',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$count',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate800,
                          fontSize: 14,
                        ),
                      ),
                      const TextSpan(
                        text: '/3',
                        style: TextStyle(
                          color: AppColors.slate400,
                          fontSize: 12,
                        ),
                      ),
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
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: AppColors.slate100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.orange500),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$percentage% 記録済み',
                    style: const TextStyle(
                      color: AppColors.slate400,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => _buildMealSectionLoading(),
      error: (_, __) => _buildMealSectionStatic(0),
    );
  }

  Widget _buildMealSectionLoading() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.orange100,
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.utensils,
              color: AppColors.orange500, size: 16),
        ),
        const SizedBox(width: 10),
        const Text(
          '食事',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.slate700,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }

  Widget _buildMealSectionStatic(int count) {
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
                  child: const Icon(LucideIcons.utensils,
                      color: AppColors.orange500, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  '食事',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate800,
                      fontSize: 14,
                    ),
                  ),
                  const TextSpan(
                    text: '/3',
                    style: TextStyle(
                      color: AppColors.slate400,
                      fontSize: 12,
                    ),
                  ),
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
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: AppColors.slate100,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.orange500),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$percentage% 記録済み',
                style: const TextStyle(
                  color: AppColors.slate400,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutSection(AsyncValue<int> weeklyExerciseCountAsync) {
    return weeklyExerciseCountAsync.when(
      data: (count) => Row(
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
                child: const Icon(LucideIcons.dumbbell,
                    color: AppColors.primary500, size: 16),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '運動',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate700,
                      fontSize: 14,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    '今週',
                    style: TextStyle(
                      color: AppColors.slate400,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$count ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                    fontSize: 14,
                  ),
                ),
                const TextSpan(
                  text: '/ 7日',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      loading: () => Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.primary100,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.dumbbell,
                color: AppColors.primary500, size: 16),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '運動',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate700,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
              Text(
                '今週',
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const Spacer(),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
      error: (_, __) => _buildWorkoutSectionStatic(0),
    );
  }

  Widget _buildWorkoutSectionStatic(int count) {
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
              child: const Icon(LucideIcons.dumbbell,
                  color: AppColors.primary500, size: 16),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '運動',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate700,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                Text(
                  '今週',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$count ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                  fontSize: 14,
                ),
              ),
              const TextSpan(
                text: '/ 7日',
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeightSection(
    AsyncValue latestWeightAsync,
    AsyncValue<Map<String, double>> weightStatsAsync,
  ) {
    return latestWeightAsync.when(
      data: (latestWeight) {
        if (latestWeight == null) {
          return _buildWeightSectionNoData();
        }

        final change = weightStatsAsync.whenOrNull(
          data: (stats) => stats['change'],
        );

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
                  child: const Icon(LucideIcons.scale,
                      color: AppColors.emerald500, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  '体重',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${latestWeight.weight.toStringAsFixed(1)} kg',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                if (change != null && change != 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:
                          change < 0 ? AppColors.emerald50 : AppColors.rose100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}kg 今週',
                      style: TextStyle(
                        color: change < 0
                            ? AppColors.emerald500
                            : AppColors.rose800,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
      loading: () => Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.emerald100,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.scale,
                color: AppColors.emerald500, size: 16),
          ),
          const SizedBox(width: 10),
          const Text(
            '体重',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.slate700,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ),
      error: (_, __) => _buildWeightSectionNoData(),
    );
  }

  Widget _buildWeightSectionNoData() {
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
              child: const Icon(LucideIcons.scale,
                  color: AppColors.emerald500, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              '体重',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.slate700,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const Text(
          'データなし',
          style: TextStyle(
            color: AppColors.slate400,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'DailySummaryCard - Static Preview')
Widget previewDailySummaryCardStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PreviewDailySummaryCard(),
        ),
      ),
    ),
  );
}

@Preview(name: 'DailySummaryCard - Empty State')
Widget previewDailySummaryCardEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PreviewDailySummaryCardEmpty(),
        ),
      ),
    ),
  );
}

// Preview helper widget with mock data
class _PreviewDailySummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          const Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 24),

          // Meal Section (2/3)
          _buildTappableRow(child: _buildMealRow(2)),
          const SizedBox(height: 16),

          // Activity Section (3/7)
          _buildTappableRow(child: _buildActivityRow(3)),

          const Divider(height: 32, color: AppColors.slate50),

          // Weight Section
          _buildTappableRow(child: _buildWeightRow(65.2, -0.6)),
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
                  child: const Icon(LucideIcons.utensils,
                      color: AppColors.orange500, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  '食事',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$count',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate800,
                      fontSize: 14,
                    ),
                  ),
                  const TextSpan(
                    text: '/3',
                    style: TextStyle(
                      color: AppColors.slate400,
                      fontSize: 12,
                    ),
                  ),
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
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.orange500),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$percentage% 記録済み',
                style: const TextStyle(
                  color: AppColors.slate400,
                  fontSize: 10,
                ),
              ),
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
              child: const Icon(LucideIcons.dumbbell,
                  color: AppColors.primary500, size: 16),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '運動',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.slate700,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                Text(
                  '今週',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$count ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                  fontSize: 14,
                ),
              ),
              const TextSpan(
                text: '/ 7日',
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 12,
                ),
              ),
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
              child: const Icon(LucideIcons.scale,
                  color: AppColors.emerald500, size: 16),
            ),
            const SizedBox(width: 10),
            const Text(
              '体重',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.slate700,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${weight.toStringAsFixed(1)} kg',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.slate800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: change < 0 ? AppColors.emerald50 : AppColors.rose100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}kg vs yest.',
                style: TextStyle(
                  color: change < 0 ? AppColors.emerald500 : AppColors.rose800,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTappableRow({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(child: child),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              LucideIcons.chevronRight,
              color: AppColors.slate300,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// Preview helper widget with empty data
class _PreviewDailySummaryCardEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          const Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 24),

          // Meal Section (0/3)
          _PreviewDailySummaryCard()._buildTappableRow(
            child: _PreviewDailySummaryCard()._buildMealRow(0),
          ),
          const SizedBox(height: 16),

          // Activity Section (0/7)
          _PreviewDailySummaryCard()._buildTappableRow(
            child: _PreviewDailySummaryCard()._buildActivityRow(0),
          ),

          const Divider(height: 32, color: AppColors.slate50),

          // Weight Section - No data
          _PreviewDailySummaryCard()._buildTappableRow(
            child: Row(
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
                      child: const Icon(LucideIcons.scale,
                          color: AppColors.emerald500, size: 16),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '体重',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'データなし',
                  style: TextStyle(
                    color: AppColors.slate400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
