import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// 所要時間 / 種別などの補足情報チップ。
///
/// ※ NextSessionCard / SessionsScreen の両方から使うので、
///   SessionStatusBadge と同様に実装はこのファイル1箇所にだけ置くこと。
class SessionMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const SessionMetaChip({
    super.key,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textHint),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'SessionMetaChip - Duration And Type')
Widget previewSessionMetaChips() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: const [
              SessionMetaChip(icon: LucideIcons.clock, label: '60分'),
              SessionMetaChip(
                icon: LucideIcons.dumbbell,
                label: 'パーソナルトレーニング',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
