import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class GoalCard extends StatelessWidget {
  final double currentWeight;
  final double targetWeight;
  final double initialWeight;
  final DateTime? targetDate;
  final bool isLoading;
  final bool isAchieved;

  const GoalCard({
    super.key,
    required this.currentWeight,
    required this.targetWeight,
    required this.initialWeight,
    this.targetDate,
    this.isLoading = false,
    this.isAchieved = false,
  });

  @override
  Widget build(BuildContext context) {
    // 減量 or 増量の判定
    final isWeightLossGoal = initialWeight > targetWeight;

    // Progress calculation（方向を考慮）
    final totalChange = (initialWeight - targetWeight).abs();
    double progressRaw;
    if (isWeightLossGoal) {
      // 減量: initial から target に向かって減少
      // 例: initial=70, target=60, current=65 → (70-65)/(70-60) = 0.5
      // current > initial の場合は逆方向なので 0
      progressRaw =
          totalChange > 0 ? (initialWeight - currentWeight) / totalChange : 0.0;
    } else {
      // 増量: initial から target に向かって増加
      // 例: initial=60, target=70, current=65 → (65-60)/(70-60) = 0.5
      // current < initial の場合は逆方向なので 0
      progressRaw =
          totalChange > 0 ? (currentWeight - initialWeight) / totalChange : 0.0;
    }
    final progress = isAchieved ? 1.0 : progressRaw.clamp(0.0, 1.0);
    final percentage = isAchieved ? 100 : (progress * 100).toInt();

    // 残り/超過の計算（減量・増量両対応）
    final difference = (currentWeight - targetWeight).abs();
    final bool isExceeded;
    if (isWeightLossGoal) {
      // 減量: current < target なら超過達成
      isExceeded = currentWeight < targetWeight;
    } else {
      // 増量: current > target なら超過達成
      isExceeded = currentWeight > targetWeight;
    }
    final bool isExactlyAchieved = currentWeight == targetWeight;

    // ラベル決定: 残り / 達成 / 超過
    final String statusLabel;
    if (isExactlyAchieved) {
      statusLabel = '達成';
    } else if (isAchieved || isExceeded) {
      statusLabel = '超過';
    } else {
      statusLabel = '残り';
    }

    final daysLeft = targetDate?.difference(DateTime.now()).inDays;

    // Colors based on achieved state
    final gradientColors = isAchieved
        ? const [Color(0xFFFFD700), Color(0xFFFFA500)] // Gold gradient
        : const [AppColors.primary600, AppColors.primary700];
    final shadowColor = isAchieved
        ? const Color(0xFFFFD700).withOpacity(0.3)
        : AppColors.primary500.withOpacity(0.2);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background Decoration
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isAchieved ? LucideIcons.trophy : LucideIcons.scale,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAchieved ? '目標達成!' : '目標進捗',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isAchieved) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '100%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // 3 Column Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatBox(
                        '現在',
                        '$currentWeight',
                        'kg',
                        isHighlighted: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        '目標',
                        '$targetWeight',
                        'kg',
                        isHighlighted: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatBox(
                        statusLabel,
                        difference.toStringAsFixed(1),
                        'kg',
                        isHighlighted: true,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Progress Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '達成率',
                      style: TextStyle(
                        color: AppColors.primary100,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '$percentage%',
                      style: const TextStyle(
                        color: AppColors.primary100,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Deadline Info
                if (targetDate != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.calendar,
                                color: AppColors.primary50, size: 14),
                            const SizedBox(width: 8),
                            Text(
                              '期限: ${_formatDateJa(targetDate!)}',
                              style: const TextStyle(
                                color: AppColors.primary50,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        if (daysLeft != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '残り${daysLeft}日',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(String label, String value, String unit,
      {required bool isHighlighted}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? Colors.white.withOpacity(0.9)
            : Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: isHighlighted
            ? null
            : Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: isHighlighted
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color:
                  isHighlighted ? AppColors.primary600 : AppColors.primary100,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: isHighlighted ? AppColors.primary700 : Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: TextStyle(
                    color: isHighlighted
                        ? AppColors.primary700.withOpacity(0.8)
                        : Colors.white.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateJa(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'GoalCard - In Progress')
Widget previewGoalCardInProgress() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GoalCard(
            currentWeight: 65.2,
            targetWeight: 60.0,
            initialWeight: 67.5,
            targetDate: DateTime(2026, 3, 15),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'GoalCard - Achieved')
Widget previewGoalCardAchieved() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GoalCard(
            currentWeight: 60.0,
            targetWeight: 60.0,
            initialWeight: 67.5,
            targetDate: DateTime(2026, 3, 15),
            isAchieved: true,
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'GoalCard - Both States')
Widget previewGoalCardBothStates() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('進行中',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GoalCard(
                currentWeight: 65.2,
                targetWeight: 60.0,
                initialWeight: 67.5,
                targetDate: DateTime(2026, 3, 15),
              ),
              const SizedBox(height: 24),
              const Text('達成',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GoalCard(
                currentWeight: 60.0,
                targetWeight: 60.0,
                initialWeight: 67.5,
                targetDate: DateTime(2026, 3, 15),
                isAchieved: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
