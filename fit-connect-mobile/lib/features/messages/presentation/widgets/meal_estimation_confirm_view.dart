import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/form_card.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

/// 推定結果を確認するビュー（食事を記録フォームの 2 段目）。
///
/// 正本 `MealForm` の「推定ボックス」に対応する: 写真（または内容・画面）からの **推定（目安）** として、
/// カロリー（20/500）とたんぱく質・脂質・炭水化物（13）を出し、右の「修正」で数値を直せる。
/// 食品リスト（読み取り専用）＋ 合計 4 値（kcal/P/F/C・編集可）＋ 戻る / 送信。
/// AI の断定にせず、「推定」「目安」と明記する。
///
/// カードの殻（[FormCard]）は呼び出し側（`MealTagForm`）が付ける。
class MealEstimationConfirmView extends StatefulWidget {
  final MealEstimationResult estimation;
  final EstimationTotals totals;
  final ValueChanged<EstimationTotals> onTotalsChanged;
  final VoidCallback onBack;
  final VoidCallback onSend;
  final bool isSending;

  /// 推定に使った画像の Storage 値（message-photos のバケット相対パス。
  /// confirm phase では読み取り専用）。空リストならサムネイル領域を描画しない。
  final List<String> imageValues;

  /// スクショ取り込み時の検出アプリ名（'unknown' や null のときラベル非表示）。
  final String? appName;

  /// 複数スクショの整合性が取れない場合の警告文（null/空なら非表示）。
  /// 非ブロッキング: 表示されても送信は可能。
  final String? warning;

  /// 送信されるメッセージの本文（`#食事:昼食 鶏むね肉のグリル定食`）。null なら出さない
  final String? composedText;

  const MealEstimationConfirmView({
    super.key,
    required this.estimation,
    required this.totals,
    required this.onTotalsChanged,
    required this.onBack,
    required this.onSend,
    this.isSending = false,
    this.imageValues = const [],
    this.appName,
    this.warning,
    this.composedText,
  });

  @override
  State<MealEstimationConfirmView> createState() =>
      _MealEstimationConfirmViewState();
}

class _MealEstimationConfirmViewState extends State<MealEstimationConfirmView> {
  late TextEditingController _kcalC;
  late TextEditingController _pC;
  late TextEditingController _fC;
  late TextEditingController _cC;

  /// 「修正」で数値の入力欄を開いているか
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _kcalC =
        TextEditingController(text: widget.totals.calories.toStringAsFixed(0));
    _pC = TextEditingController(text: widget.totals.proteinG.toStringAsFixed(0));
    _fC = TextEditingController(text: widget.totals.fatG.toStringAsFixed(0));
    _cC = TextEditingController(text: widget.totals.carbsG.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant MealEstimationConfirmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親が外部から新しい totals を渡してきた場合に controller を再シードする。
    // 自分が入力した値が親を経由して戻ってきただけなら、入力中の文字（"12." など）を壊さない
    if (!identical(oldWidget.totals, widget.totals) &&
        !_sameTotals(_readTotals(), widget.totals)) {
      _kcalC.text = widget.totals.calories.toStringAsFixed(0);
      _pC.text = widget.totals.proteinG.toStringAsFixed(0);
      _fC.text = widget.totals.fatG.toStringAsFixed(0);
      _cC.text = widget.totals.carbsG.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _kcalC.dispose();
    _pC.dispose();
    _fC.dispose();
    _cC.dispose();
    super.dispose();
  }

  EstimationTotals _readTotals() => EstimationTotals(
        calories: double.tryParse(_kcalC.text) ?? 0,
        proteinG: double.tryParse(_pC.text) ?? 0,
        fatG: double.tryParse(_fC.text) ?? 0,
        carbsG: double.tryParse(_cC.text) ?? 0,
      );

  static bool _sameTotals(EstimationTotals a, EstimationTotals b) =>
      a.calories == b.calories &&
      a.proteinG == b.proteinG &&
      a.fatG == b.fatG &&
      a.carbsG == b.carbsG;

  void _emit() => widget.onTotalsChanged(_readTotals());

  /// 推定の出どころ（見出しの文言）。写真・画面・内容のどれから推定したかを明記する
  String get _sourceLabel {
    final app = widget.appName;
    if (app != null && app.isNotEmpty && app != 'unknown') {
      return '画面からの読み取り（目安）';
    }
    if (widget.imageValues.isNotEmpty) return '写真からの推定（目安）';
    return '内容からの推定（目安）';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final appName = widget.appName;
    final showApp = appName != null && appName.isNotEmpty && appName != 'unknown';
    final hasWarning = widget.warning != null && widget.warning!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeading(
          icon: LucideIcons.calculator,
          title: '推定結果を確認',
          action: FcButton.back(label: '戻る', onPressed: widget.onBack),
        ),

        if (showApp) ...[
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(LucideIcons.smartphone,
                    size: 14, color: colors.textSecondary),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$appName から読み取り',
                  style: AppTextStyles.supplement(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 複数スクショの整合性警告（非ブロッキング: 表示されても送信可能）
        if (hasWarning) ...[
          FcInlineNotice.warning(message: widget.warning!),
          const SizedBox(height: AppSpacing.md),
        ],

        // 推定に使った写真（読み取り専用）
        if (widget.imageValues.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in widget.imageValues)
                StorageImage(
                  value: value,
                  bucket: StorageBuckets.messagePhotos,
                  width: PhotoTiles.tileSize,
                  height: PhotoTiles.tileSize,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(PhotoTiles.tileRadius),
                  placeholder: const FcPhotoPlaceholder(
                    width: PhotoTiles.tileSize,
                    height: PhotoTiles.tileSize,
                    radius: PhotoTiles.tileRadius,
                  ),
                  errorWidget: const FcPhotoPlaceholder(
                    width: PhotoTiles.tileSize,
                    height: PhotoTiles.tileSize,
                    radius: PhotoTiles.tileRadius,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 推定した食品（読み取り専用）
        if (widget.estimation.foods.isNotEmpty) ...[
          Text('推定した内容', style: AppTextStyles.caption(context)),
          const SizedBox(height: 2),
          for (final f in widget.estimation.foods)
            Text(
              '・${f.name}（${f.calories.toStringAsFixed(0)} kcal）',
              style: AppTextStyles.supplement(context),
            ),
          const SizedBox(height: AppSpacing.md),
        ],

        _buildEstimateBox(context),

        if (widget.composedText != null) ...[
          const SizedBox(height: AppSpacing.md),
          ComposedPreview(text: widget.composedText!, title: '送信される内容'),
        ],

        // 送信（送信中は二重送信を防ぎ、文言でも伝える）
        const SizedBox(height: 14),
        FcButton.block(
          label: 'この内容で送信',
          loading: widget.isSending,
          loadingLabel: '送信しています…',
          onPressed: widget.onSend,
        ),
      ],
    );
  }

  /// 推定ボックス（正本: surfaceSecondary・calculator 13 + 出どころ + 右に accent の「修正」）。
  /// 閉じているときはカロリー（20/500）とたんぱく質・脂質・炭水化物（13）、
  /// 開いているときは 4 つの数値入力
  Widget _buildEstimateBox(BuildContext context) {
    final colors = AppColors.of(context);
    final t = _readTotals();
    String g(double v) => v.toStringAsFixed(0);

    return FcInfoBox(
      // 見出し行が「修正」の押せる範囲（高さ 44）で決まるので、上の余白は 0
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(LucideIcons.calculator,
                      size: 13, color: colors.textSecondary),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_sourceLabel, style: AppTextStyles.caption(context)),
                ),
                FcPressable(
                  onTap: () => setState(() => _editing = !_editing),
                  semanticLabel: _editing ? '修正を終える' : '数値を修正する',
                  minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      _editing ? '完了' : '修正',
                      style: AppTextStyles.supplement(context).copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_editing) ...[
            FcNum(
              value: g(t.calories),
              unit: 'kcal',
              size: FcNumSize.compact,
            ),
            const SizedBox(height: 2),
            Text(
              'たんぱく質 ${g(t.proteinG)} g · 脂質 ${g(t.fatG)} g · 炭水化物 ${g(t.carbsG)} g',
              style: AppTextStyles.supplement(context).copyWith(
                fontFeatures: AppTextStyles.tabularFigures,
              ),
            ),
          ] else
            _buildEditFields(context),
        ],
      ),
    );
  }

  Widget _buildEditFields(BuildContext context) {
    final fields = <Widget>[
      FcTextField.number(
        label: 'カロリー',
        unit: 'kcal',
        controller: _kcalC,
        onChanged: (_) {
          _emit();
          setState(() {});
        },
      ),
      FcTextField.number(
        label: 'たんぱく質',
        unit: 'g',
        controller: _pC,
        onChanged: (_) {
          _emit();
          setState(() {});
        },
      ),
      FcTextField.number(
        label: '脂質',
        unit: 'g',
        controller: _fC,
        onChanged: (_) {
          _emit();
          setState(() {});
        },
      ),
      FcTextField.number(
        label: '炭水化物',
        unit: 'g',
        controller: _cC,
        onChanged: (_) {
          _emit();
          setState(() {});
        },
      ),
    ];

    // 文字拡大のときは 1 列に積み直す（縮めない）
    final large = MediaQuery.textScalerOf(context).scale(16) > 20;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = large || constraints.maxWidth < 240
            ? constraints.maxWidth
            : (constraints.maxWidth - AppSpacing.md) / 2;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final f in fields) SizedBox(width: width, child: f),
            ],
          ),
        );
      },
    );
  }
}

// ============================================
// Preview
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required MealEstimationResult estimation,
  String? composedText,
  List<String> imageValues = const [],
  bool isSending = false,
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
        child: SingleChildScrollView(
          reverse: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: FormCard(
              child: MealEstimationConfirmView(
                estimation: estimation,
                totals: estimation.totals,
                composedText: composedText,
                imageValues: imageValues,
                appName: estimation.appName,
                warning: estimation.warning,
                isSending: isSending,
                onTotalsChanged: (_) {},
                onBack: () {},
                onSend: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _previewEstimation = MealEstimationResult(
  foods: [
    EstimatedFood(
        name: '鶏むね肉のグリル', calories: 320, proteinG: 30, fatG: 10, carbsG: 4),
    EstimatedFood(
        name: 'ごはん', calories: 280, proteinG: 4, fatG: 1, carbsG: 62),
    EstimatedFood(
        name: 'サラダ', calories: 40, proteinG: 2, fatG: 3, carbsG: 5),
  ],
  totals: EstimationTotals(calories: 640, proteinG: 38, fatG: 18, carbsG: 82),
);

@Preview(name: 'MealEstimationConfirmView - 推定（ライト）')
Widget previewMealEstimationConfirmViewLight() => _previewApp(
      brightness: Brightness.light,
      estimation: _previewEstimation,
      composedText: '#食事:昼食 鶏むね肉のグリル定食',
    );

@Preview(name: 'MealEstimationConfirmView - 推定（ダーク）')
Widget previewMealEstimationConfirmViewDark() => _previewApp(
      brightness: Brightness.dark,
      estimation: _previewEstimation,
      composedText: '#食事:昼食 鶏むね肉のグリル定食',
    );

@Preview(name: 'MealEstimationConfirmView - 整合性の警告・文字1.35')
Widget previewMealEstimationConfirmViewWarning() => _previewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      estimation: const MealEstimationResult(
        foods: [
          EstimatedFood(
              name: '鶏胸肉（100g）',
              calories: 154,
              proteinG: 0,
              fatG: 0,
              carbsG: 0),
        ],
        totals:
            EstimationTotals(calories: 589, proteinG: 45, fatG: 12, carbsG: 60),
        appName: 'あすけん',
        warning: 'カロリーの画面とPFCの画面で合計が噛み合いません。同じ食事の画面か確認してください',
      ),
    );

@Preview(name: 'MealEstimationConfirmView - 送信中')
Widget previewMealEstimationConfirmViewSending() => _previewApp(
      brightness: Brightness.light,
      estimation: _previewEstimation,
      composedText: '#食事:昼食 鶏むね肉のグリル定食',
      isSending: true,
    );
