import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 文字だけの控えめな操作（textSecondary・15）。「キャンセル」「今日は聞かない」など。
///
/// 正本 `plan-screens.js` の完了報告シートの「キャンセル」と同じ見た目
/// （最小高さ 44・textSecondary・action サイズ・背景なし）。accent の文字操作は
/// 基盤の `FcButton.back` / `FcButton.text` を使う。
/// 基盤の `FcButton` に「控えめな文字操作」が増えたら、そちらへ置き換える。
class SleepTextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  /// true なら横幅いっぱいに広げて中央寄せ（シートの「キャンセル」）。false なら内容幅
  final bool expand;

  const SleepTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: AppTextStyles.actionLabel(context).copyWith(
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
        height: 1.5,
      ),
    );

    return FcPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: label,
      minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
      child: expand
          ? SizedBox(
              width: double.infinity,
              child: Center(child: text),
            )
          : text,
    );
  }
}
