import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';

/// 3段階の目覚め評価セレクタ。ダイアログ + 編集ボトムシートで再利用
class WakeupRatingSelector extends StatelessWidget {
  final WakeupRating? selected;
  final ValueChanged<WakeupRating> onSelect;

  const WakeupRatingSelector({
    super.key,
    this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _option(context, WakeupRating.refreshed, '😊', 'すっきり'),
        const SizedBox(height: 8),
        _option(context, WakeupRating.okay, '😐', 'まあまあ'),
        const SizedBox(height: 8),
        _option(context, WakeupRating.groggy, '😫', 'だるい'),
      ],
    );
  }

  Widget _option(
    BuildContext context,
    WakeupRating value,
    String emoji,
    String label,
  ) {
    final isSelected = selected == value;
    final colors = AppColorsExtension.of(context);

    return Material(
      color: isSelected ? colors.accentIndigo : colors.surfaceDim,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelect(value),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppColors.primary : colors.textPrimary,
                  letterSpacing: -0.16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'WakeupRatingSelector - Unselected')
Widget previewWakeupRatingSelectorUnselected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WakeupRatingSelector(
            selected: null,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'WakeupRatingSelector - Refreshed Selected')
Widget previewWakeupRatingSelectorRefreshed() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: WakeupRatingSelector(
            selected: WakeupRating.refreshed,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
}
