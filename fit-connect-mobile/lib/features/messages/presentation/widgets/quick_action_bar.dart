import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 入力欄の上のクイック操作（正本 `message-screens.js` の `Composer` の 1 段目）。
///
/// 「体重」「食事」「運動」のチップ（surface・角丸 20・高さ 40・アイコン 16 accent・文字 14）と、
/// 右に「# で手入力」の caption。押すと対応する記録フォームを開く（`'weight'` / `'meal'` / `'exercise'`）。
/// 文字拡大ではチップが折り返して 2 段になる。
class QuickActionBar extends StatelessWidget {
  final Function(String formType) onTap;

  const QuickActionBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 0,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _QuickChip(
                icon: LucideIcons.scale,
                label: '体重',
                onTap: () => onTap('weight'),
              ),
              _QuickChip(
                icon: LucideIcons.utensils,
                label: '食事',
                onTap: () => onTap('meal'),
              ),
              _QuickChip(
                icon: LucideIcons.dumbbell,
                label: '運動',
                onTap: () => onTap('exercise'),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const _HashHint(),
      ],
    );
  }
}

/// 「# で手入力」（caption・# は 13 のアイコン）
class _HashHint extends StatelessWidget {
  const _HashHint();

  @override
  Widget build(BuildContext context) {
    final caption = AppTextStyles.caption(context);
    return Semantics(
      label: '# で手入力',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.hash, size: 13, color: caption.color),
          const SizedBox(width: 2),
          Text('で手入力', style: caption),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcPressable(
      onTap: onTap,
      semanticLabel: '$labelを記録',
      // 見た目の高さは 40、タッチ領域は 44
      minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FcChips.height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 16, color: colors.accent),
                ),
                const SizedBox(width: 6),
                Text(label, style: AppTextStyles.label(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: QuickActionBar(onTap: (_) {}),
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'QuickActionBar - ライト')
Widget previewQuickActionBarLight() =>
    _previewApp(brightness: Brightness.light);

@Preview(name: 'QuickActionBar - ダーク')
Widget previewQuickActionBarDark() => _previewApp(brightness: Brightness.dark);

@Preview(name: 'QuickActionBar - 文字1.35')
Widget previewQuickActionBarLarge() =>
    _previewApp(brightness: Brightness.light, textScale: 1.35);
