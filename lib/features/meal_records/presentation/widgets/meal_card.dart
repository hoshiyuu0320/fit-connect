import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:intl/intl.dart';

class MealCard extends StatefulWidget {
  final MealRecord record;

  const MealCard({super.key, required this.record});

  @override
  State<MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<MealCard> {
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final record = widget.record;
    final (typeColor, textColor, icon, typeLabel) =
        _getMealTypeStyle(context, record.mealType);
    final hasMultipleImages =
        record.images != null && record.images!.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image or Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colors.surfaceDim,
              borderRadius: BorderRadius.circular(12),
            ),
            child: record.images != null && record.images!.isNotEmpty
                ? Stack(
                    children: [
                      // Image PageView
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: PageView.builder(
                          itemCount: record.images!.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () {
                                FullScreenImageViewer.show(
                                  context: context,
                                  imageUrls: record.images!,
                                  initialIndex: index,
                                );
                              },
                              child: Image.network(
                                record.images![index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(icon,
                                      style: const TextStyle(fontSize: 32)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Dot indicator (only show if multiple images)
                      if (hasMultipleImages)
                        Positioned(
                          bottom: 4,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              record.images!.length,
                              (index) => Container(
                                width: 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index == _currentImageIndex
                                      ? Colors.white
                                      : Colors.white.withAlpha(128),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(50),
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
                    child: Text(icon, style: const TextStyle(fontSize: 32))),
          ),

          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Image count badge
                    if (hasMultipleImages) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.border,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '📷 ${record.images!.length}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  record.notes ?? typeLabel,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('⏰ ', style: TextStyle(fontSize: 10)),
                    Text(
                      DateFormat('HH:mm').format(record.recordedAt),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (record.calories != null) ...[
                      const SizedBox(width: 12),
                      const Text('🔥 ', style: TextStyle(fontSize: 10)),
                      Text(
                        '${record.calories!.toInt()} kcal',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, String, String) _getMealTypeStyle(
      BuildContext context, String mealType) {
    final colors = AppColors.of(context);
    switch (mealType.toLowerCase()) {
      case 'breakfast':
        return (AppColors.amber100, AppColors.amber800, '🍳', '朝食');
      case 'lunch':
        return (AppColors.primary100, AppColors.primary700, '🥗', '昼食');
      case 'dinner':
        return (AppColors.rose100, AppColors.rose800, '🥩', '夕食');
      case 'snack':
        return (colors.accentIndigoBorder, AppColors.indigo800, '🍎', '間食');
      default:
        return (colors.surfaceDim, colors.textSecondary, '🍽️', mealType);
    }
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MealCard - Breakfast')
Widget previewMealCardBreakfast() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MealCard(record: _mockBreakfast),
        ),
      ),
    ),
  );
}

@Preview(name: 'MealCard - Lunch')
Widget previewMealCardLunch() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MealCard(record: _mockLunch),
        ),
      ),
    ),
  );
}

@Preview(name: 'MealCard - All Types')
Widget previewMealCardAllTypes() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              MealCard(record: _mockBreakfast),
              MealCard(record: _mockLunch),
              MealCard(record: _mockDinner),
              MealCard(record: _mockSnack),
            ],
          ),
        ),
      ),
    ),
  );
}

// Mock data for previews
final _mockBreakfast = MealRecord(
  id: '1',
  clientId: 'client-1',
  mealType: 'breakfast',
  notes: 'オートミール、バナナ、プロテインシェイク',
  images: null,
  calories: 380,
  recordedAt: DateTime.now(),
  source: 'manual',
  messageId: null,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final _mockLunch = MealRecord(
  id: '2',
  clientId: 'client-1',
  mealType: 'lunch',
  notes: 'グリルチキンサラダ、玄米おにぎり、味噌汁',
  images: ['https://picsum.photos/seed/lunch/200/200'],
  calories: 520,
  recordedAt: DateTime.now(),
  source: 'message',
  messageId: 'msg-1',
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final _mockDinner = MealRecord(
  id: '3',
  clientId: 'client-1',
  mealType: 'dinner',
  notes: '鮭のムニエル、温野菜、もち麦ごはん',
  images: null,
  calories: 580,
  recordedAt: DateTime.now(),
  source: 'manual',
  messageId: null,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);

final _mockSnack = MealRecord(
  id: '4',
  clientId: 'client-1',
  mealType: 'snack',
  notes: 'ミックスナッツ、ギリシャヨーグルト',
  images: null,
  calories: 200,
  recordedAt: DateTime.now(),
  source: 'manual',
  messageId: null,
  createdAt: DateTime.now(),
  updatedAt: DateTime.now(),
);
