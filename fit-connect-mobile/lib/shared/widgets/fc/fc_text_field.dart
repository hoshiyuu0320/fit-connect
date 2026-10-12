import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';

/// ラベル付きの入力欄。正本は `components/forms/TextField.jsx`。
///
/// - ラベルは入力欄の **上**（15 / 400 / textPrimary、下余白 8）
/// - 入力欄は **surface の面 + 1px の枠**（通常は separator、[errorText] があると error）・角丸 12・内側余白 12
///   （[unit] があると右 48）。文字は 16（行高 1.6）。複数行は最小高さ 107
/// - [unit] は入力欄の右端（右から 14）に **常に** 表示する（13 / textSecondary。空でも消えない）
/// - [helperText]（12 / textSecondary・上 6）は [errorText] が無いときだけ出る。
///   [errorText] は error 色の 13 + alert アイコン 15（色だけで伝えない）
/// - 無効（[enabled] = false）は入力欄を opacity 0.5
/// - フォーカス中は枠が accent になる（正本は outline なしだが、操作中の場所が分かるように残している）
/// - 数値入力は `FcTextField.number(...)`（桁幅を揃える・小数点キーボード）
/// - 複数行は `maxLines: null` か `minLines` / `maxLines` を指定する
class FcTextField extends StatelessWidget {
  const FcTextField({
    super.key,
    this.label,
    this.controller,
    this.focusNode,
    this.hintText,
    this.unit,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
    this.numeric = false,
    this.semanticLabel,
  });

  /// 数値入力。数字と小数点だけを受け付け、桁幅を揃える。[decimal] が false なら整数のみ
  factory FcTextField.number({
    Key? key,
    String? label,
    TextEditingController? controller,
    FocusNode? focusNode,
    String? hintText,
    String? unit,
    bool decimal = true,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    String? errorText,
    String? helperText,
    bool enabled = true,
    bool autofocus = false,
    TextAlign textAlign = TextAlign.start,
    String? semanticLabel,
  }) {
    return FcTextField(
      key: key,
      label: label,
      controller: controller,
      focusNode: focusNode,
      hintText: hintText,
      unit: unit,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimal ? r'[0-9.]' : r'[0-9]'),
        ),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      errorText: errorText,
      helperText: helperText,
      enabled: enabled,
      autofocus: autofocus,
      textAlign: textAlign,
      numeric: true,
      semanticLabel: semanticLabel,
    );
  }

  final String? label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;

  /// 右端に常時表示する単位（例: kg / kcal / 分）
  final String? unit;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextAlign textAlign;

  /// 数値として桁幅を揃えるか（[FcTextField.number] は true）
  final bool numeric;

  /// 読み上げラベル。null なら [label]（[unit] があれば「ラベル（単位）」）
  final String? semanticLabel;

  /// 複数行の入力欄の最小高さ
  static const double multilineMinHeight = 107;

  /// 入力欄の内側余白（枠線 1 + 余白 12）
  static const double _inset = 13;

  /// 単位がある場合の右余白（枠線 1 + 余白 48）
  static const double _insetWithUnit = 49;

  bool get _multiline => !obscureText && (maxLines == null || maxLines! > 1);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasError = errorText != null && errorText!.isNotEmpty;
    final multiline = _multiline;

    final baseStyle = numeric
        ? AppTextStyles.bodyNumber(context)
        : AppTextStyles.body(context);
    final textStyle = baseStyle.copyWith(height: 1.6);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: color, width: width),
        );

    final input = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      obscureText: obscureText,
      keyboardType: keyboardType ??
          (maxLines == 1 ? TextInputType.text : TextInputType.multiline),
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      minLines: minLines,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      textAlign: textAlign,
      textAlignVertical: multiline ? TextAlignVertical.top : null,
      style: textStyle,
      cursorColor: colors.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: colors.surface,
        hintText: hintText,
        hintStyle: textStyle.copyWith(color: colors.textSecondary),
        counterText: '',
        contentPadding: EdgeInsets.fromLTRB(
          _inset,
          _inset,
          unit == null ? _inset : _insetWithUnit,
          _inset,
        ),
        constraints: multiline
            ? const BoxConstraints(minHeight: multilineMinHeight)
            : null,
        border: border(colors.separator),
        enabledBorder: border(hasError ? colors.error : colors.separator),
        disabledBorder: border(hasError ? colors.error : colors.separator),
        focusedBorder:
            hasError ? border(colors.error, 1.5) : border(colors.accent, 1.5),
        errorBorder: border(colors.error),
        focusedErrorBorder: border(colors.error, 1.5),
      ),
    );

    // 無効のときは入力欄だけ opacity 0.5（ラベル・単位は薄くしない）
    final field = enabled ? input : Opacity(opacity: 0.5, child: input);

    // 単位は入力欄の上に重ねる（右から 14・縦は中央）。読み上げには含めず、ラベルへ足す
    final fieldWithUnit = unit == null
        ? field
        : Stack(
            children: [
              field,
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: ExcludeSemantics(
                        child: Text(
                          unit!,
                          style: AppTextStyles.numUnit(context)
                              .copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    final fieldLabel = semanticLabel ??
        (unit == null || label == null ? label : '$label（$unit）');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          ExcludeSemantics(
            child: Text(
              label!,
              style: AppTextStyles.actionLabel(context).copyWith(
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Semantics(
          label: fieldLabel,
          child: fieldWithUnit,
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      LucideIcons.alertCircle,
                      size: 15,
                      color: colors.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: AppTextStyles.supplement(context)
                          .copyWith(color: colors.error),
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (helperText != null && helperText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(helperText!, style: AppTextStyles.caption(context)),
          ),
      ],
    );
  }
}
