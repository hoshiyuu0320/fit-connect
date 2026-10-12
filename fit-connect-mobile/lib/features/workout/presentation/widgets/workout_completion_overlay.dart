import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/workout_sheet_handle.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 完了の報告シートの背景（スクリム）。正本 `ReportSheet` の rgba(0,0,0,.32)
const Color _kReportScrim = Color(0x52000000);

/// 完了の報告シート（ボトムシート）を開く。報告できたら `true`、キャンセルなら `false`（または `null`）。
///
/// 以前の完了演出（紙吹雪・拍手・大きな完了表示）は廃止した。
/// 報告した内容は、メッセージとして担当トレーナーに届く（送信は画面側の [onSubmit]）。
Future<bool?> showWorkoutCompletionSheet(
  BuildContext context, {
  required String planTitle,
  required int exerciseCount,
  required DateTime date,
  String? trainerName,
  required Future<void> Function(String? feedback, int? calories) onSubmit,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    barrierColor: _kReportScrim,
    builder: (_) => WorkoutCompletionSheet(
      planTitle: planTitle,
      exerciseCount: exerciseCount,
      date: date,
      trainerName: trainerName,
      onSubmit: onSubmit,
    ),
  );
}

/// 完了の報告シートの中身（正本 `plan-screens.js` の `ReportSheet`）。
///
/// 上端にハンドル・見出し「完了を報告」・「上半身 · 3種目 · 9月13日（日）」・
/// 感想・コンディション（任意）・消費カロリー（任意・kcal）・説明・
/// 「{トレーナー}に報告する」・「キャンセル」。
///
/// 背景の面・上の角丸（23）は `BottomSheetTheme` が付ける。
/// 送信中は「処理しています…」にして二重に押せなくする。送信に失敗したら入力を残して理由を示す。
class WorkoutCompletionSheet extends StatefulWidget {
  const WorkoutCompletionSheet({
    super.key,
    required this.planTitle,
    required this.exerciseCount,
    required this.date,
    required this.onSubmit,
    this.trainerName,
  });

  final String planTitle;
  final int exerciseCount;
  final DateTime date;

  /// トレーナーの名前（「{名前}トレーナーに報告する」。null なら「トレーナー」）
  final String? trainerName;

  /// 報告を送る。例外が出たら、シートは閉じずにエラーを示す
  final Future<void> Function(String? feedback, int? calories) onSubmit;

  @override
  State<WorkoutCompletionSheet> createState() => _WorkoutCompletionSheetState();
}

class _WorkoutCompletionSheetState extends State<WorkoutCompletionSheet> {
  final _feedbackController = TextEditingController();
  final _caloriesController = TextEditingController();
  bool _submitting = false;
  bool _failed = false;

  /// 上端・下端の余白（正本 10 / 30）
  static const double _topPadding = 10;
  static const double _bottomPadding = 30;

  @override
  void dispose() {
    _feedbackController.dispose();
    _caloriesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final caloriesText = _caloriesController.text.trim();
    final calories = caloriesText.isNotEmpty ? int.tryParse(caloriesText) : null;
    setState(() {
      _submitting = true;
      _failed = false;
    });
    try {
      await widget.onSubmit(_feedbackController.text, calories);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _failed = true;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final trainer = trainerDisplayName(widget.trainerName);
    final metrics = MediaQuery.of(context);
    final bottomInset = metrics.viewInsets.bottom;
    final meta =
        '${widget.planTitle} · ${widget.exerciseCount}種目 · ${formatWorkoutLongDate(widget.date)}';

    return PopScope(
      canPop: !_submitting,
      child: Padding(
        // キーボードが出ても入力欄が隠れないよう、シート全体を持ち上げる
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            _topPadding,
            AppSpacing.pageHorizontal,
            math.max(_bottomPadding, metrics.padding.bottom),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WorkoutSheetHandle(),
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  '完了を報告',
                  style: AppTextStyles.sectionHeading(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(meta, style: AppTextStyles.supplement(context)),
              ),
              const SizedBox(height: 18),
              FcTextField(
                label: '感想・コンディション（任意）',
                controller: _feedbackController,
                minLines: 3,
                maxLines: null,
                enabled: !_submitting,
              ),
              const SizedBox(height: 14),
              FcTextField.number(
                label: '消費カロリー（任意）',
                unit: 'kcal',
                decimal: false,
                controller: _caloriesController,
                enabled: !_submitting,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '報告はメッセージとして$trainerに届きます。',
                  style: AppTextStyles.caption(context),
                ),
              ),
              if (_failed)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: FcInlineNotice.error(
                    message: '報告できませんでした。通信状況を確認して、もう一度お試しください。',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: FcButton.block(
                  label: '$trainerに報告する',
                  loading: _submitting,
                  onPressed: _submit,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FcPressable(
                  enabled: !_submitting,
                  onTap: () => Navigator.of(context).pop(false),
                  minSize: const Size(0, AppSizes.minTouch),
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(
                      child: Text(
                        'キャンセル',
                        style: AppTextStyles.actionLabel(context).copyWith(
                          fontWeight: FontWeight.w400,
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用: シートを画面の下に重ねて見せる（背景は薄暗いスクリム）
class _PreviewSheetHost extends StatelessWidget {
  const _PreviewSheetHost();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: _kReportScrim, child: SizedBox.expand()),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: AppColors.of(context).surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.card),
            ),
            child: WorkoutCompletionSheet(
              planTitle: '上半身',
              exerciseCount: 3,
              date: DateTime(2026, 9, 13),
              trainerName: '田中',
              onSubmit: (_, __) async {},
            ),
          ),
        ),
      ],
    );
  }
}

Widget _previewSheet(Brightness brightness, {double textScale = 1.0}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: const Scaffold(body: _PreviewSheetHost()),
  );
}

@Preview(name: 'WorkoutCompletionSheet')
Widget previewWorkoutCompletionSheet() => _previewSheet(Brightness.light);

@Preview(name: 'WorkoutCompletionSheet - ダーク')
Widget previewWorkoutCompletionSheetDark() => _previewSheet(Brightness.dark);

@Preview(name: 'WorkoutCompletionSheet - 文字特大 (1.35)')
Widget previewWorkoutCompletionSheetLargeText() =>
    _previewSheet(Brightness.light, textScale: 1.35);
