import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/sleep_text_action.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 寝起きの良さ（WakeupRating）を記録する共通ボトムシート。
///
/// ホーム「今日のまとめ」の睡眠行・睡眠画面の編集導線など、
/// `WakeupRatingSelector` を使う記録 UI を一箇所に集約する。
/// 保存は `sleepRecordsProvider().notifier.upsertWakeupRating` に委譲
/// （押した時点で保存して閉じる。挙動は従来どおり）。
///
/// 見た目は正本 `plan-screens.js` の完了報告シートに合わせる（surface の面・上の角丸 23・
/// 上端のつまみ・見出し 20 / 500・下に「キャンセル」）。
Future<void> showWakeupRecordSheet(
  BuildContext context,
  WidgetRef ref, {
  WakeupRating? current,
}) async {
  WakeupRating? selected = current;
  var saving = false;
  await showModalBottomSheet<void>(
    context: context,
    // 面の色と上の角丸 23 はテーマ（BottomSheetTheme）に任せる
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSt) => WakeupRecordSheetContent(
        selected: selected,
        onSelect: (r) async {
          if (saving) return;
          saving = true;
          setSt(() => selected = r);
          try {
            await ref.read(sleepRecordsProvider().notifier).upsertWakeupRating(
                  recordedDate: todayJstDateKey(),
                  rating: r,
                );
            if (sheetCtx.mounted) {
              Navigator.of(sheetCtx).pop();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('記録しました')),
                );
              }
            }
          } catch (e) {
            saving = false;
            if (sheetCtx.mounted) {
              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                SnackBar(content: Text('記録に失敗しました: $e')),
              );
            }
          }
        },
        onCancel: () => Navigator.of(sheetCtx).pop(),
      ),
    ),
  );
}

/// 目覚めを記録するシートの中身（見出し + 選択肢 + キャンセル）。
/// 保存・Riverpod は持たない（呼び出し側 [showWakeupRecordSheet] が持つ）。
class WakeupRecordSheetContent extends StatelessWidget {
  final WakeupRating? selected;
  final ValueChanged<WakeupRating> onSelect;
  final VoidCallback onCancel;

  const WakeupRecordSheetContent({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final horizontal = AppSpacing.pageHorizontalOf(context);

    // 正本のシート: 余白 上10・左右20・下30。端末の下端の安全領域（ホームインジケータ）が
    // 30 より大きければそちらを使う
    final bottom = math.max(30.0, MediaQuery.viewPaddingOf(context).bottom);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 上端のつまみ（36×5・separator）。操作はできないので読み上げ対象外
          ExcludeSemantics(
            child: Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.separator,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              '目覚めを記録',
              style: AppTextStyles.sectionHeading(context),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          WakeupRatingSelector(selected: selected, onSelect: onSelect),
          const SizedBox(height: 6),
          SleepTextAction(label: 'キャンセル', onPressed: onCancel, expand: true),
        ],
      ),
    );
  }
}

// =====================================
// プレビュー
// =====================================

/// 本物のシートと同じ面・角丸（23）でシートの中身を見せる
class _PreviewSheet extends StatelessWidget {
  final WakeupRating? selected;
  const _PreviewSheet({this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.card),
            ),
          ),
          child: WakeupRecordSheetContent(
            selected: selected,
            onSelect: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'WakeupRecordSheet - 未選択')
Widget previewWakeupRecordSheet() => const FcPreviewApp(
      brightness: Brightness.light,
      home: _PreviewSheet(),
    );

@Preview(name: 'WakeupRecordSheet - まあまあ（選択中・ダーク）')
Widget previewWakeupRecordSheetDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: _PreviewSheet(selected: WakeupRating.okay),
    );

@Preview(name: 'WakeupRecordSheet - 文字拡大 1.35')
Widget previewWakeupRecordSheetLarge() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: _PreviewSheet(selected: WakeupRating.groggy),
    );
