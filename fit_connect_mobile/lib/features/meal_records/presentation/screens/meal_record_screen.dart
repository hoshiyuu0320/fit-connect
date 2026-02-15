import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_card.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_week_calendar.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/meal_month_calendar.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

class MealRecordScreen extends ConsumerStatefulWidget {
  const MealRecordScreen({super.key});

  @override
  ConsumerState<MealRecordScreen> createState() => _MealRecordScreenState();
}

class _MealRecordScreenState extends ConsumerState<MealRecordScreen> {
  PeriodFilter _selectedPeriod = PeriodFilter.today;

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(
      mealRecordsProvider(period: _selectedPeriod),
    );
    final todayCountAsync = ref.watch(todayMealCountProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Period Filter
        _buildPeriodFilter(),
        const SizedBox(height: 24),

        // Summary Card (Today only)
        if (_selectedPeriod == PeriodFilter.today) ...[
          _buildSummaryCard(recordsAsync, todayCountAsync),
          const SizedBox(height: 16),
        ],

        // Calendar - show week calendar for week, month calendar for month
        if (_selectedPeriod == PeriodFilter.week) ...[
          const MealWeekCalendar(),
          const SizedBox(height: 16),
        ],
        if (_selectedPeriod == PeriodFilter.month) ...[
          const MealMonthCalendar(),
          const SizedBox(height: 16),
        ],

        // Meal Records List
        _buildRecordsList(recordsAsync),
      ],
    );
  }

  Widget _buildPeriodFilter() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children: PeriodFilter.values.map((period) {
          final isActive = period == _selectedPeriod;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = period),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.primary600.withAlpha(77),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    period.shortLabel,
                    style: TextStyle(
                      color: isActive ? Colors.white : AppColors.slate400,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCard(
    AsyncValue<List<MealRecord>> recordsAsync,
    AsyncValue<int> todayCountAsync,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
      ),
      child: recordsAsync.when(
        data: (records) {
          final totalCalories = records.fold<double>(
            0,
            (sum, r) => sum + (r.calories ?? 0),
          );
          final photosCount = records.where((r) => r.images != null && r.images!.isNotEmpty).length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedPeriod == PeriodFilter.today
                    ? "今日のサマリー"
                    : "${_selectedPeriod.label}のサマリー",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSummaryItem(
                    icon: LucideIcons.utensils,
                    value: todayCountAsync.when(
                      data: (count) => '$count/3',
                      loading: () => '-',
                      error: (_, __) => '-',
                    ),
                    label: '食事',
                    color: AppColors.primary600,
                  ),
                  _buildSummaryItem(
                    icon: LucideIcons.camera,
                    value: '$photosCount',
                    label: '写真',
                    color: AppColors.emerald500,
                  ),
                  _buildSummaryItem(
                    icon: LucideIcons.flame,
                    value: '${totalCalories.toInt()}',
                    label: 'kcal',
                    color: AppColors.orange500,
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.slate800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.slate400,
          ),
        ),
      ],
    );
  }

  Widget _buildRecordsList(AsyncValue<List<MealRecord>> recordsAsync) {
    return recordsAsync.when(
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.utensils, size: 48, color: AppColors.slate300),
                  const SizedBox(height: 12),
                  const Text(
                    '食事記録がありません',
                    style: TextStyle(color: AppColors.slate400),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '食事を記録しましょう！',
                    style: TextStyle(color: AppColors.slate300, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        // Group records by date
        final groupedRecords = _groupRecordsByDate(records);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: groupedRecords.entries.map((entry) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    _formatDateHeader(entry.key),
                    style: const TextStyle(
                      color: AppColors.slate800,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.slate100),
                const SizedBox(height: 16),
                // Meal Cards
                ...entry.value.map((record) => MealCard(record: record)),
                const SizedBox(height: 8),
              ],
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Map<DateTime, List<MealRecord>> _groupRecordsByDate(List<MealRecord> records) {
    final Map<DateTime, List<MealRecord>> grouped = {};
    for (final record in records) {
      final date = DateTime(
        record.recordedAt.year,
        record.recordedAt.month,
        record.recordedAt.day,
      );
      grouped.putIfAbsent(date, () => []);
      grouped[date]!.add(record);
    }
    return grouped;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) {
      return '今日';
    } else if (date == yesterday) {
      return '昨日';
    } else {
      return '${date.month}/${date.day}（${_weekdayLabel(date.weekday)}）';
    }
  }

  String _weekdayLabel(int weekday) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[weekday - 1];
  }
}

// ============================================
// Previews
// ============================================

// Note: MealRecordScreen uses Riverpod providers.
// For full screen preview, run the app with mock data.
// Below are static previews of individual components.

@Preview(name: 'MealRecordScreen - Static Preview')
Widget previewMealRecordScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period Filter Preview
            _PreviewPeriodFilter(),
            const SizedBox(height: 24),

            // Summary Card Preview
            _PreviewSummaryCard(),
            const SizedBox(height: 16),

            // Week Calendar Preview
            _PreviewWeekCalendar(),
            const SizedBox(height: 16),

            // Records List Preview
            _PreviewRecordsList(),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'MealRecordScreen - Empty State')
Widget previewMealRecordScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period Filter Preview
            _PreviewPeriodFilter(),
            const SizedBox(height: 24),

            // Empty Summary Card
            _PreviewSummaryCardEmpty(),
            const SizedBox(height: 16),

            // Week Calendar Preview (empty)
            _PreviewWeekCalendarEmpty(),
            const SizedBox(height: 16),

            // Empty State
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.utensils, size: 48, color: AppColors.slate300),
                    const SizedBox(height: 12),
                    const Text(
                      '食事記録がありません',
                      style: TextStyle(color: AppColors.slate400),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// Preview helper widgets
class _PreviewPeriodFilter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Row(
        children: ['今日', '週', '月', '3ヶ月', '全期間'].asMap().entries.map((entry) {
          final isActive = entry.key == 0;
          return Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary600 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: isActive ? Colors.white : AppColors.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PreviewSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "今日のサマリー",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate800),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildItem(LucideIcons.utensils, '3/3', '食事', AppColors.primary600),
              _buildItem(LucideIcons.camera, '4', '写真', AppColors.emerald500),
              _buildItem(LucideIcons.flame, '1,100', 'kcal', AppColors.orange500),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItem(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slate800)),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
      ],
    );
  }
}

class _PreviewSummaryCardEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "今日のサマリー",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate800),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PreviewSummaryCard()._buildItem(LucideIcons.utensils, '0/3', '食事', AppColors.primary600),
              _PreviewSummaryCard()._buildItem(LucideIcons.camera, '0', '写真', AppColors.emerald500),
              _PreviewSummaryCard()._buildItem(LucideIcons.flame, '0', 'kcal', AppColors.orange500),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewRecordsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('今日', style: TextStyle(color: AppColors.slate800, fontSize: 14, fontWeight: FontWeight.bold)),
        const Divider(height: 24, color: AppColors.slate100),
        ..._mockMealRecords.map((record) => MealCard(record: record)),
      ],
    );
  }
}

class _PreviewWeekCalendar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    // Mock data
    final mockMealCounts = <DateTime, int>{};
    for (int i = 0; i < 7; i++) {
      final date = startOfWeek.add(Duration(days: i));
      if (!date.isAfter(today)) {
        mockMealCounts[date] = (date.day + i) % 4;
      }
    }
    mockMealCounts[today] = 2;

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('M月d日').format(startOfWeek)}〜${DateFormat('M月d日').format(endOfWeek)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(7, (index) {
              final date = startOfWeek.add(Duration(days: index));
              final count = mockMealCounts[date] ?? 0;
              final isToday = date == today;
              final isFuture = date.isAfter(today);
              final color = isFuture ? AppColors.grassLevel0 : _getGrassColor(count);
              final textColor = count >= 2 && !isFuture ? Colors.white : AppColors.slate600;

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      dayLabels[index],
                      style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday
                            ? Border.all(color: AppColors.primary600, width: 3)
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isFuture ? AppColors.slate400 : textColor,
                            ),
                          ),
                          if (count > 0 && !isFuture)
                            Text(
                              '$count食',
                              style: TextStyle(fontSize: 10, color: textColor),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Color _getGrassColor(int count) {
    switch (count) {
      case 0: return AppColors.grassLevel0;
      case 1: return AppColors.grassLevel1;
      case 2: return AppColors.grassLevel2;
      default: return AppColors.grassLevel3;
    }
  }
}

class _PreviewWeekCalendarEmpty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DateFormat('M月d日').format(startOfWeek)}〜${DateFormat('M月d日').format(endOfWeek)}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(7, (index) {
              final date = startOfWeek.add(Duration(days: index));
              final isToday = date == today;
              final isFuture = date.isAfter(today);

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      dayLabels[index],
                      style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.grassLevel0,
                        borderRadius: BorderRadius.circular(12),
                        border: isToday
                            ? Border.all(color: AppColors.primary600, width: 3)
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isFuture ? AppColors.slate400 : AppColors.slate600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// Mock data for previews
final _mockMealRecords = [
  MealRecord(
    id: '1',
    clientId: 'client-1',
    mealType: 'breakfast',
    notes: 'オートミール、バナナ、プロテインシェイク',
    images: null,
    calories: 380,
    recordedAt: DateTime.now().subtract(const Duration(hours: 5)),
    source: 'manual',
    messageId: null,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  MealRecord(
    id: '2',
    clientId: 'client-1',
    mealType: 'lunch',
    notes: 'グリルチキンサラダ、玄米おにぎり、味噌汁',
    images: ['https://picsum.photos/seed/lunch/200/200'],
    calories: 520,
    recordedAt: DateTime.now().subtract(const Duration(hours: 2)),
    source: 'message',
    messageId: 'msg-1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
  MealRecord(
    id: '3',
    clientId: 'client-1',
    mealType: 'snack',
    notes: 'ミックスナッツ、ギリシャヨーグルト',
    images: null,
    calories: 200,
    recordedAt: DateTime.now().subtract(const Duration(hours: 1)),
    source: 'manual',
    messageId: null,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),
];
