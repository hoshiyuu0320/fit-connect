import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MealSummaryCard extends StatelessWidget {
  final String title;
  final String meals;
  final String photos;
  final String calories;

  const MealSummaryCard({
    super.key,
    required this.title,
    required this.meals,
    required this.photos,
    required this.calories,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary50, AppColors.indigo50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📊 ', style: TextStyle(fontSize: 14)),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.slate800,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildRow(LucideIcons.utensils, '食事', meals),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.primary200.withOpacity(0.5)),
          ),
          _buildRow(LucideIcons.image, '写真', photos),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: AppColors.primary200.withOpacity(0.5)),
          ),
          _buildRow(LucideIcons.flame, 'カロリー', calories),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.slate500),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.slate500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.slate800,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MealSummaryCard - Today')
Widget previewMealSummaryCardToday() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MealSummaryCard(
            title: "今日のサマリー",
            meals: '2/3',
            photos: '4',
            calories: '1,250 kcal',
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MealSummaryCard - Week')
Widget previewMealSummaryCardWeek() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MealSummaryCard(
            title: "今週のサマリー",
            meals: '18/21',
            photos: '24',
            calories: '12,500 kcal',
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'MealSummaryCard - Empty')
Widget previewMealSummaryCardEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MealSummaryCard(
            title: "今日のサマリー",
            meals: '0/3',
            photos: '0',
            calories: '0 kcal',
          ),
        ),
      ),
    ),
  );
}
