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
    final colors = AppColors.of(context);
    final todayMealCountAsync = ref.watch(todayMealCountProvider);
    final weeklyExerciseCountAsync = ref.watch(weeklyExerciseCountProvider);
    final latestWeightAsync = ref.watch(latestWeightRecordProvider);
    final weightStatsAsync =
        ref.watch(weightStatsProvider(period: PeriodFilter.week));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 24),

          // Meal Section
          _buildTappableSection(
            context: context,
            onTap: onMealsTap,
            child: _buildMealSection(context, todayMealCountAsync),
          ),

          const SizedBox(height: 16),

          // Workout Section
          _buildTappableSection(
            context: context,
            onTap: onActivityTap,
            child: _buildWorkoutSection(context, weeklyExerciseCountAsync),
          ),

          Divider(height: 32, color: colors.surfaceDim),

          // Weight Section
          _buildTappableSection(
            context: context,
            onTap: onWeightTap,
            child: _buildWeightSection(
                context, latestWeightAsync, weightStatsAsync),
          ),
        ],
      ),
    );
  }

  Widget _buildTappableSection({
    required BuildContext context,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: AppColors.primary100,
        highlightColor: colors.surfaceDim,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(child: child),
              if (onTap != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    LucideIcons.chevronRight,
                    color: colors.border,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMealSection(
      BuildContext context, AsyncValue<int> todayMealCountAsync) {
    return todayMealCountAsync.when(
      data: (count) => _buildMealSectionData(context, count),
      loading: () => _buildMealSectionLoading(context),
      error: (_, __) => _buildMealSectionData(context, 0),
    );
  }

  Widget _buildMealSectionData(BuildContext context, int count) {
    final colors = AppColors.of(context);
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
                Text(
                  '食事',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  TextSpan(
                    text: '/3',
                    style: TextStyle(
                      color: colors.textHint,
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
                  backgroundColor: colors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.orange500),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$percentage% 記録済み',
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMealSectionLoading(BuildContext context) {
    final colors = AppColors.of(context);
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
        Text(
          '食事',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
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

  Widget _buildWorkoutSection(
      BuildContext context, AsyncValue<int> weeklyExerciseCountAsync) {
    return weeklyExerciseCountAsync.when(
      data: (count) => _buildWorkoutSectionData(context, count),
      loading: () => _buildWorkoutSectionLoading(context),
      error: (_, __) => _buildWorkoutSectionData(context, 0),
    );
  }

  Widget _buildWorkoutSectionData(BuildContext context, int count) {
    final colors = AppColors.of(context);
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '運動',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                Text(
                  '今週',
                  style: TextStyle(
                    color: colors.textHint,
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                text: '/ 7日',
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutSectionLoading(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '運動',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.2,
              ),
            ),
            Text(
              '今週',
              style: TextStyle(
                color: colors.textHint,
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
    );
  }

  Widget _buildWeightSection(
    BuildContext context,
    AsyncValue latestWeightAsync,
    AsyncValue<Map<String, double>> weightStatsAsync,
  ) {
    return latestWeightAsync.when(
      data: (latestWeight) {
        if (latestWeight == null) {
          return _buildWeightSectionNoData(context);
        }

        final change = weightStatsAsync.whenOrNull(
          data: (stats) => stats['change'],
        );

        return _buildWeightSectionData(context, latestWeight.weight, change);
      },
      loading: () => _buildWeightSectionLoading(context),
      error: (_, __) => _buildWeightSectionNoData(context),
    );
  }

  Widget _buildWeightSectionData(
      BuildContext context, double weight, double? change) {
    final colors = AppColors.of(context);
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
            Text(
              '体重',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            if (change != null && change != 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: change < 0 ? AppColors.emerald50 : AppColors.rose100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}kg 今週',
                  style: TextStyle(
                    color:
                        change < 0 ? AppColors.emerald500 : AppColors.rose800,
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

  Widget _buildWeightSectionLoading(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
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
        Text(
          '体重',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
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

  Widget _buildWeightSectionNoData(BuildContext context) {
    final colors = AppColors.of(context);
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
            Text(
              '体重',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        Text(
          'データなし',
          style: TextStyle(
            color: colors.textHint,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // Meal Section (2/3)
          _buildTappableRow(context: context, child: _buildMealRow(context, 2)),
          const SizedBox(height: 16),

          // Activity Section (3/7)
          _buildTappableRow(context: context, child: _buildActivityRow(context, 3)),

          Divider(height: 32, color: colors.surfaceDim),

          // Weight Section
          _buildTappableRow(context: context, child: _buildWeightRow(context, 65.2, -0.6)),
        ],
      ),
    );
  }

  Widget _buildMealRow(BuildContext context, int count) {
    final colors = AppColors.of(context);
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
                Text(
                  '食事',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  TextSpan(
                    text: '/3',
                    style: TextStyle(
                      color: colors.textHint,
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
                  backgroundColor: colors.border,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.orange500),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$percentage% 記録済み',
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityRow(BuildContext context, int count) {
    final colors = AppColors.of(context);
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '運動',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
                Text(
                  '今週',
                  style: TextStyle(
                    color: colors.textHint,
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                  fontSize: 14,
                ),
              ),
              TextSpan(
                text: '/ 7日',
                style: TextStyle(
                  color: colors.textHint,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeightRow(BuildContext context, double weight, double change) {
    final colors = AppColors.of(context);
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
            Text(
              '体重',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
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

  Widget _buildTappableRow({required BuildContext context, required Widget child}) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(child: child),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              LucideIcons.chevronRight,
              color: colors.border,
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Text(
            '今日のまとめ',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // Meal Section (0/3)
          _PreviewDailySummaryCard()._buildTappableRow(
            context: context,
            child: _PreviewDailySummaryCard()._buildMealRow(context, 0),
          ),
          const SizedBox(height: 16),

          // Activity Section (0/7)
          _PreviewDailySummaryCard()._buildTappableRow(
            context: context,
            child: _PreviewDailySummaryCard()._buildActivityRow(context, 0),
          ),

          Divider(height: 32, color: colors.surfaceDim),

          // Weight Section - No data
          _PreviewDailySummaryCard()._buildTappableRow(
            context: context,
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
                    Text(
                      '体重',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                Text(
                  'データなし',
                  style: TextStyle(
                    color: colors.textHint,
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
