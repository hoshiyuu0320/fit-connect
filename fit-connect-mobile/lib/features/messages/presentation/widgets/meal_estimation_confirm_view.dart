import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// AI推定結果を確認するビュー。
/// 食品リスト（read-only）+ 合計4値（kcal/P/F/C, 編集可）+ 戻る/送信ボタン
class MealEstimationConfirmView extends StatefulWidget {
  final MealEstimationResult estimation;
  final EstimationTotals totals;
  final ValueChanged<EstimationTotals> onTotalsChanged;
  final VoidCallback onBack;
  final VoidCallback onSend;

  const MealEstimationConfirmView({
    super.key,
    required this.estimation,
    required this.totals,
    required this.onTotalsChanged,
    required this.onBack,
    required this.onSend,
  });

  @override
  State<MealEstimationConfirmView> createState() => _MealEstimationConfirmViewState();
}

class _MealEstimationConfirmViewState extends State<MealEstimationConfirmView> {
  late TextEditingController _kcalC;
  late TextEditingController _pC;
  late TextEditingController _fC;
  late TextEditingController _cC;

  @override
  void initState() {
    super.initState();
    _kcalC = TextEditingController(text: widget.totals.calories.toStringAsFixed(0));
    _pC = TextEditingController(text: widget.totals.proteinG.toStringAsFixed(0));
    _fC = TextEditingController(text: widget.totals.fatG.toStringAsFixed(0));
    _cC = TextEditingController(text: widget.totals.carbsG.toStringAsFixed(0));
  }

  @override
  void didUpdateWidget(covariant MealEstimationConfirmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 親が外部から新しい totals を渡してきた場合に controller を再シード（参照比較で十分）
    if (!identical(oldWidget.totals, widget.totals)) {
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

  void _emit() => widget.onTotalsChanged(_readTotals());

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(LucideIcons.sparkles, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text(
              'AI推定結果を確認',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: widget.onBack,
              child: Text(
                '戻る',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Foods list (read-only in Stage 1)
        ...widget.estimation.foods.map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '・${f.name}（${f.calories.toStringAsFixed(0)}kcal）',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Editable totals row
        Row(
          children: [
            Expanded(child: _NumField(label: 'kcal', controller: _kcalC, onChanged: (_) => _emit(), colors: colors)),
            const SizedBox(width: 6),
            Expanded(child: _NumField(label: 'P', controller: _pC, onChanged: (_) => _emit(), colors: colors)),
            const SizedBox(width: 6),
            Expanded(child: _NumField(label: 'F', controller: _fC, onChanged: (_) => _emit(), colors: colors)),
            const SizedBox(width: 6),
            Expanded(child: _NumField(label: 'C', controller: _cC, onChanged: (_) => _emit(), colors: colors)),
          ],
        ),
        const SizedBox(height: 10),

        // Send button
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: widget.onSend,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '送信',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final AppColorsExtension colors;
  const _NumField({
    required this.label,
    required this.controller,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: colors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      style: TextStyle(color: colors.textPrimary, fontSize: 13),
    );
  }
}

// ============================================
// Preview
// ============================================

@Preview(name: 'MealEstimationConfirmView - Default')
Widget previewMealEstimationConfirmViewDefault() {
  const estimation = MealEstimationResult(
    foods: [
      EstimatedFood(name: '牛丼大盛り', calories: 850, proteinG: 32, fatG: 28, carbsG: 95),
      EstimatedFood(name: 'サラダ', calories: 50, proteinG: 2, fatG: 3, carbsG: 5),
    ],
    totals: EstimationTotals(calories: 900, proteinG: 34, fatG: 31, carbsG: 100),
  );
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: MealEstimationConfirmView(
                estimation: estimation,
                totals: estimation.totals,
                onTotalsChanged: (_) {},
                onBack: () {},
                onSend: () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
