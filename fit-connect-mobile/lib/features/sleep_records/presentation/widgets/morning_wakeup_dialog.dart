import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_text_action.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

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
    return MorningWakeupDialogContent(
      selected: _selected,
      saving: _saving,
      onSelect: _onSelect,
      onLater: _onLater,
      onDismissToday: _onDismissToday,
    );
  }

  Future<void> _onSelect(WakeupRating rating) async {
    if (_saving) return;
    setState(() {
      _selected = rating;
      _saving = true;
    });

    try {
      await ref.read(sleepRecordsProvider().notifier).upsertWakeupRating(
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

/// 朝の目覚めダイアログの中身（見た目だけ。保存・Riverpod は [MorningWakeupDialog] が持つ）。
///
/// surface の面・角丸 23・余白 20 の左寄せのカード。挨拶は絵文字ではなくアイコン（sun）と言葉。
/// 目覚めの評価は言葉の選択肢（[WakeupRatingSelector]）。「あとで」は accent、
/// 「今日は聞かない」は textSecondary の文字操作。保存中はどの操作も押せない。
class MorningWakeupDialogContent extends StatelessWidget {
  final WakeupRating? selected;
  final bool saving;
  final ValueChanged<WakeupRating> onSelect;
  final VoidCallback onLater;
  final VoidCallback onDismissToday;

  const MorningWakeupDialogContent({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onLater,
    required this.onDismissToday,
    this.saving = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // 面の色・角丸 23 は DialogTheme（surface・card の形）に任せる
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontalOf(context),
        vertical: AppSpacing.xxl,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(LucideIcons.sun, size: 20, color: colors.accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'おはようございます',
                      style: AppTextStyles.sectionHeading(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '今朝の目覚めは？',
              style: AppTextStyles.label(context)
                  .copyWith(color: colors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            WakeupRatingSelector(
              selected: selected,
              onSelect: saving ? (_) {} : onSelect,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FcButton.back(
                  label: 'あとで',
                  icon: null,
                  onPressed: saving ? null : onLater,
                ),
                SleepTextAction(
                  label: '今日は聞かない',
                  onPressed: saving ? null : onDismissToday,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// MorningWakeupDialog を表示するヘルパー（多重表示は呼び出し元で防ぐ前提）
Future<void> showMorningWakeupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // 背景の暗幕。ぼかしは下部ナビだけに使うので、薄い黒の面だけにする
    // （正本のシートの暗幕 rgba(0,0,0,.32) に合わせた）
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => const MorningWakeupDialog(),
  );
}

// =====================================
// プレビュー (静的、Riverpodなし)
// =====================================

Widget _previewDialog({
  required Brightness brightness,
  WakeupRating? selected,
  bool saving = false,
  double scale = 1,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: MorningWakeupDialogContent(
        selected: selected,
        saving: saving,
        onSelect: (_) {},
        onLater: () {},
        onDismissToday: () {},
      ),
    ),
  );
}

@Preview(name: 'MorningWakeupDialog - 未選択')
Widget previewMorningWakeupDialogUnselected() =>
    _previewDialog(brightness: Brightness.light);

@Preview(name: 'MorningWakeupDialog - すっきり（保存中）')
Widget previewMorningWakeupDialogRefreshed() => _previewDialog(
      brightness: Brightness.light,
      selected: WakeupRating.refreshed,
      saving: true,
    );

@Preview(name: 'MorningWakeupDialog - ダーク')
Widget previewMorningWakeupDialogDark() =>
    _previewDialog(brightness: Brightness.dark);

@Preview(name: 'MorningWakeupDialog - 文字拡大 1.35')
Widget previewMorningWakeupDialogLarge() =>
    _previewDialog(brightness: Brightness.light, scale: 1.35);
