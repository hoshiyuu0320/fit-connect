import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

class QuickActionBar extends StatelessWidget {
  final Function(String formType) onTap;

  const QuickActionBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          _ActionChip(
            icon: '⚖️',
            label: '体重',
            colors: colors,
            onTap: () => onTap('weight'),
          ),
          const SizedBox(width: 8),
          _ActionChip(
            icon: '🍽️',
            label: '食事',
            colors: colors,
            onTap: () => onTap('meal'),
          ),
          const SizedBox(width: 8),
          _ActionChip(
            icon: '🏃',
            label: '運動',
            colors: colors,
            onTap: () => onTap('exercise'),
          ),
          const Spacer(),
          Text(
            '#で手入力',
            style: TextStyle(
              fontSize: 12,
              color: colors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String icon;
  final String label;
  final AppColorsExtension colors;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'QuickActionBar - Default')
Widget previewQuickActionBarDefault() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            QuickActionBar(onTap: (_) {}),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'QuickActionBar - Dark')
Widget previewQuickActionBarDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            QuickActionBar(onTap: (_) {}),
          ],
        ),
      ),
    ),
  );
}
