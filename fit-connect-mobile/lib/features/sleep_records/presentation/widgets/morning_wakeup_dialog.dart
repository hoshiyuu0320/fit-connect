import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';

/// 朝の目覚め記録ダイアログ。アプリ起動時(4:00-12:00)に表示。
class MorningWakeupDialog extends ConsumerStatefulWidget {
  const MorningWakeupDialog({super.key});

  @override
  ConsumerState<MorningWakeupDialog> createState() =>
      _MorningWakeupDialogState();
}

class _MorningWakeupDialogState extends ConsumerState<MorningWakeupDialog> {
  WakeupRating? _selected;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.42),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ヘッダー
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.sun,
                        size: 22, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Text(
                      'おはようございます',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '今朝の目覚めは？',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // 3オプション
                WakeupRatingSelector(
                  selected: _selected,
                  onSelect: _saving ? (_) {} : _onSelect,
                ),
                const SizedBox(height: 20),

                // セカンダリアクション
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : _onLater,
                      child: const Text(
                        'あとで',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _onDismissToday,
                      child: Text(
                        '今日は聞かない',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onSelect(WakeupRating rating) async {
    if (_saving) return;
    setState(() {
      _selected = rating;
      _saving = true;
    });

    try {
      await ref
          .read(sleepRecordsProvider().notifier)
          .upsertWakeupRating(
            recordedDate: todayJstDateKey(),
            rating: rating,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('記録しました')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('記録に失敗しました: $e')),
      );
    }
  }

  void _onLater() {
    Navigator.of(context).pop();
  }

  Future<void> _onDismissToday() async {
    await ref.read(morningDialogProvider.notifier).dismissToday();
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}

/// MorningWakeupDialog を表示するヘルパー（多重表示は呼び出し元で防ぐ前提）
Future<void> showMorningWakeupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent, // BackdropFilter で半透明黒を描く
    builder: (_) => const MorningWakeupDialog(),
  );
}

// =====================================
// プレビュー (静的、Riverpodなし)
// =====================================

class _PreviewMorningWakeupDialog extends StatelessWidget {
  final WakeupRating? selected;
  const _PreviewMorningWakeupDialog({this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
      child: Container(
        color: Colors.black.withValues(alpha: 0.42),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.sun,
                        size: 22, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Text(
                      'おはようございます',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '今朝の目覚めは？',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                const SizedBox(height: 20),
                WakeupRatingSelector(selected: selected, onSelect: (_) {}),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {},
                      child: const Text(
                        'あとで',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        '今日は聞かない',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'MorningWakeupDialog - Unselected')
Widget previewMorningWakeupDialogUnselected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: Color(0xFFFAFAFA),
      body: _PreviewMorningWakeupDialog(),
    ),
  );
}

@Preview(name: 'MorningWakeupDialog - Selected Refreshed')
Widget previewMorningWakeupDialogRefreshed() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      backgroundColor: Color(0xFFFAFAFA),
      body: _PreviewMorningWakeupDialog(selected: WakeupRating.refreshed),
    ),
  );
}
