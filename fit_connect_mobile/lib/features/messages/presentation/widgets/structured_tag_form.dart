import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ============================================
// StructuredTagForm（親Widget）
// ============================================

class StructuredTagForm extends StatelessWidget {
  final String formType; // 'weight', 'meal', 'exercise'
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final bool hasImages;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  const StructuredTagForm({
    super.key,
    required this.formType,
    required this.onCompose,
    required this.onClose,
    this.hasImages = false,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    switch (formType) {
      case 'weight':
        return WeightTagForm(
          onCompose: onCompose,
          onClose: onClose,
          selectedImages: selectedImages,
          onPickImage: onPickImage,
          onRemoveImage: onRemoveImage,
        );
      case 'meal':
        return MealTagForm(
          onCompose: onCompose,
          onClose: onClose,
          hasImages: hasImages,
          selectedImages: selectedImages,
          onPickImage: onPickImage,
          onRemoveImage: onRemoveImage,
        );
      case 'exercise':
        return ExerciseTagForm(
          onCompose: onCompose,
          onClose: onClose,
          hasImages: hasImages,
          selectedImages: selectedImages,
          onPickImage: onPickImage,
          onRemoveImage: onRemoveImage,
        );
      default:
        return WeightTagForm(
          onCompose: onCompose,
          onClose: onClose,
          selectedImages: selectedImages,
          onPickImage: onPickImage,
          onRemoveImage: onRemoveImage,
        );
    }
  }
}

// ============================================
// WeightTagForm
// ============================================

class WeightTagForm extends StatefulWidget {
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  const WeightTagForm({
    super.key,
    required this.onCompose,
    required this.onClose,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
  });

  @override
  State<WeightTagForm> createState() => _WeightTagFormState();
}

class _WeightTagFormState extends State<WeightTagForm> {
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _weightController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  bool get _isValid {
    final text = _weightController.text.trim();
    if (text.isEmpty) return false;
    final value = double.tryParse(text);
    if (value == null) return false;
    return value >= 20 && value <= 300;
  }

  String get _previewText {
    final weight = _weightController.text.trim();
    final comment = _commentController.text.trim();
    if (weight.isEmpty) return '#体重 --kg';
    final base = '#体重 ${weight}kg';
    return comment.isNotEmpty ? '$base $comment' : base;
  }

  void _handleInsert() {
    if (!_isValid) return;
    widget.onCompose(_previewText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー行
          Row(
            children: [
              const Text('⚖️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '体重を記録',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: Icon(LucideIcons.x, size: 20, color: colors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 体重入力行
          Row(
            children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '65.5',
                    hintStyle: TextStyle(color: colors.textHint),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // コメント入力
          TextField(
            controller: _commentController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ひとことコメント（任意）',
              hintStyle: TextStyle(color: colors.textHint),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 8),

          // 画像ピッカー行
          _ImagePickerRow(
            images: widget.selectedImages,
            onPick: widget.onPickImage,
            onRemove: widget.onRemoveImage,
            colors: colors,
          ),
          const SizedBox(height: 10),

          // プレビュー行
          _PreviewRow(
            previewText: _previewText,
            isValid: _isValid,
            onInsert: _handleInsert,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

// ============================================
// MealTagForm
// ============================================

class MealTagForm extends StatefulWidget {
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final bool hasImages;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  const MealTagForm({
    super.key,
    required this.onCompose,
    required this.onClose,
    this.hasImages = false,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
  });

  @override
  State<MealTagForm> createState() => _MealTagFormState();
}

class _MealTagFormState extends State<MealTagForm> {
  late String _selectedMealType;
  final TextEditingController _contentController = TextEditingController();

  static const _mealTypes = ['朝食', '昼食', '夕食', '間食'];

  @override
  void initState() {
    super.initState();
    _selectedMealType = _getDefaultMealType();
  }

  String _getDefaultMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 10) return '朝食';
    if (hour >= 10 && hour < 15) return '昼食';
    if (hour >= 15 && hour < 20) return '夕食';
    return '間食';
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  bool get _isValid => _contentController.text.trim().isNotEmpty || widget.hasImages;

  String get _previewText {
    final content = _contentController.text.trim();
    final type = _selectedMealType;
    if (content.isEmpty) return '#食事:$type --';
    return '#食事:$type $content';
  }

  String get _composedText {
    final content = _contentController.text.trim();
    final type = _selectedMealType;
    if (content.isEmpty) return '#食事:$type';
    return '#食事:$type $content';
  }

  void _handleInsert() {
    if (!_isValid) return;
    widget.onCompose(_composedText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー行
          Row(
            children: [
              const Text('🍽️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '食事を記録',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: Icon(LucideIcons.x, size: 20, color: colors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // セグメントコントロール
          _SegmentControl(
            items: _mealTypes,
            selected: _selectedMealType,
            onChanged: (value) => setState(() => _selectedMealType = value),
            colors: colors,
          ),
          const SizedBox(height: 8),

          // 食事内容入力
          TextField(
            controller: _contentController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '食事内容やコメントを入力',
              hintStyle: TextStyle(color: colors.textHint),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 8),

          // 画像ピッカー行
          _ImagePickerRow(
            images: widget.selectedImages,
            onPick: widget.onPickImage,
            onRemove: widget.onRemoveImage,
            colors: colors,
          ),
          const SizedBox(height: 10),

          // プレビュー行
          _PreviewRow(
            previewText: _previewText,
            isValid: _isValid,
            onInsert: _handleInsert,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

// ============================================
// ExerciseTagForm
// ============================================

class ExerciseTagForm extends StatefulWidget {
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final bool hasImages;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  const ExerciseTagForm({
    super.key,
    required this.onCompose,
    required this.onClose,
    this.hasImages = false,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
  });

  @override
  State<ExerciseTagForm> createState() => _ExerciseTagFormState();
}

class _ExerciseTagFormState extends State<ExerciseTagForm> {
  String _selectedType = '筋トレ';
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _kcalController = TextEditingController();

  static const _exerciseTypes = ['筋トレ', '有酸素'];

  @override
  void dispose() {
    _nameController.dispose();
    _minutesController.dispose();
    _kcalController.dispose();
    super.dispose();
  }

  bool get _isValid => _nameController.text.trim().isNotEmpty || widget.hasImages;

  String get _previewText {
    final name = _nameController.text.trim();
    final minutes = _minutesController.text.trim();
    final kcal = _kcalController.text.trim();
    if (name.isEmpty) return '#運動:$_selectedType --';
    String text = '#運動:$_selectedType $name';
    if (minutes.isNotEmpty) text += ' $minutes分';
    if (kcal.isNotEmpty) text += ' ${kcal}kcal';
    return text;
  }

  String get _composedText {
    final name = _nameController.text.trim();
    final minutes = _minutesController.text.trim();
    final kcal = _kcalController.text.trim();
    String text = '#運動:$_selectedType';
    if (name.isNotEmpty) text += ' $name';
    if (minutes.isNotEmpty) text += ' $minutes分';
    if (kcal.isNotEmpty) text += ' ${kcal}kcal';
    return text;
  }

  void _handleInsert() {
    if (!_isValid) return;
    widget.onCompose(_composedText);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // ヘッダー行
            Row(
              children: [
                const Text('🏃', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  '運動を記録',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(LucideIcons.x, size: 20, color: colors.textHint),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // セグメントコントロール
            _SegmentControl(
              items: _exerciseTypes,
              selected: _selectedType,
              onChanged: (value) => setState(() => _selectedType = value),
              colors: colors,
            ),
            const SizedBox(height: 8),

            // 種目入力
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '運動内容やコメントを入力',
                hintStyle: TextStyle(color: colors.textHint),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
                filled: true,
                fillColor: colors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 8),

            // 時間・カロリー入力行
            Row(
              children: [
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _minutesController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '30',
                      hintStyle: TextStyle(color: colors.textHint),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '分',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _kcalController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '150',
                      hintStyle: TextStyle(color: colors.textHint),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppColors.primary, width: 2),
                      ),
                      filled: true,
                      fillColor: colors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'kcal',
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 画像ピッカー行
            _ImagePickerRow(
              images: widget.selectedImages,
              onPick: widget.onPickImage,
              onRemove: widget.onRemoveImage,
              colors: colors,
            ),
            const SizedBox(height: 10),

            // プレビュー行
            _PreviewRow(
              previewText: _previewText,
              isValid: _isValid,
              onInsert: _handleInsert,
              colors: colors,
            ),
          ],
        ),
      );
  }
}

// ============================================
// 共通部品: _ImagePickerRow
// ============================================

class _ImagePickerRow extends StatelessWidget {
  final List<File> images;
  final VoidCallback? onPick;
  final Function(int)? onRemove;
  final AppColorsExtension colors;

  const _ImagePickerRow({
    required this.images,
    this.onPick,
    this.onRemove,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 選択済み画像
        ...images.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: GestureDetector(
                    onTap: () => onRemove?.call(index),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppColors.rose800,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.x,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        // プレースホルダー（3枚未満の場合のみ表示）
        if (images.length < 3)
          GestureDetector(
            onTap: onPick,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                LucideIcons.camera,
                color: colors.textHint,
                size: 24,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================
// 共通部品: _SegmentControl
// ============================================

class _SegmentControl extends StatelessWidget {
  final List<String> items;
  final String selected;
  final ValueChanged<String> onChanged;
  final AppColorsExtension colors;

  const _SegmentControl({
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: items.map((item) {
          final isSelected = item == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(item),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? colors.textPrimary
                          : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ============================================
// 共通部品: _PreviewRow
// ============================================

class _PreviewRow extends StatelessWidget {
  final String previewText;
  final bool isValid;
  final VoidCallback onInsert;
  final AppColorsExtension colors;

  const _PreviewRow({
    required this.previewText,
    required this.isValid,
    required this.onInsert,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '💬 $previewText',
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: isValid ? onInsert : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isValid ? AppColors.primary : colors.border,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '挿入',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isValid ? Colors.white : colors.textHint,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// プレビュー用静的ヘルパーWidget（WeightTagForm Filled）
// ============================================

class _PreviewWeightTagFormFilled extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー行
          Row(
            children: [
              const Text('⚖️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                '体重を記録',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.x, size: 20, color: colors.textHint),
            ],
          ),
          const SizedBox(height: 12),

          // 体重入力行（値入力済み）
          Row(
            children: [
              Container(
                width: 120,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: Text(
                  '65.5',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'kg',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // コメント（入力済み）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              '朝の計測。昨日より少し減りました',
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),

          // 画像ピッカー行（プレースホルダーのみ）
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.camera,
                  color: colors.textHint,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // プレビュー行（有効状態）
          _PreviewRow(
            previewText: '#体重 65.5kg 朝の計測。昨日より少し減りました',
            isValid: true,
            onInsert: () {},
            colors: colors,
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'WeightTagForm - Empty')
Widget previewWeightTagFormEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            WeightTagForm(onCompose: (_) {}, onClose: () {}),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'WeightTagForm - Filled')
Widget previewWeightTagFormFilled() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _PreviewWeightTagFormFilled(),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'MealTagForm - Default')
Widget previewMealTagFormDefault() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            MealTagForm(onCompose: (_) {}, onClose: () {}),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'ExerciseTagForm - Default')
Widget previewExerciseTagFormDefault() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ExerciseTagForm(onCompose: (_) {}, onClose: () {}),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'StructuredTagForm - Dark')
Widget previewStructuredTagFormDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            StructuredTagForm(
              formType: 'weight',
              onCompose: (_) {},
              onClose: () {},
            ),
          ],
        ),
      ),
    ),
  );
}
