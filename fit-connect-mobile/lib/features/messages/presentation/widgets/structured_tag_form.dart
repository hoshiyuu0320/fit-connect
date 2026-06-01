import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/data/meal_estimation_api.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/meal_estimation_confirm_view.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
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

  /// PFC込みで送信。preUploadedUrls は AI 推定時に upload 済みの画像 URL（再 upload 回避用）。
  /// null の場合は AI推定なしで `onCompose` のみ実行
  final Future<void> Function(
    String composedText,
    MealEstimationResult estimation,
    List<String> preUploadedUrls,
  )? onSendWithEstimation;

  const StructuredTagForm({
    super.key,
    required this.formType,
    required this.onCompose,
    required this.onClose,
    this.hasImages = false,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
    this.onSendWithEstimation,
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
          onSendWithEstimation: onSendWithEstimation,
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
              Icon(LucideIcons.scale, size: 16, color: colors.textPrimary),
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

enum _MealFormPhase { input, loading, confirm }

/// 食事タグフォームの入力モード。
/// cook = 料理を記録（写真/テキスト）、screenshot = 他アプリのスクショから取込。
enum _MealInputMode { cook, screenshot }

class MealTagForm extends ConsumerStatefulWidget {
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final bool hasImages;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  /// PFC込みで送信。preUploadedUrls は AI 推定時に upload 済みの画像 URL（再 upload 回避用）。
  /// null の場合は AI推定なしで `onCompose` のみ実行
  final Future<void> Function(
    String composedText,
    MealEstimationResult estimation,
    List<String> preUploadedUrls,
  )? onSendWithEstimation;

  /// Preview/テスト用に screenshot モードで初期表示する（本番の通常導線では未指定）。
  final bool debugInitialScreenshotMode;

  const MealTagForm({
    super.key,
    required this.onCompose,
    required this.onClose,
    this.hasImages = false,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
    this.onSendWithEstimation,
    this.debugInitialScreenshotMode = false,
  });

  @override
  ConsumerState<MealTagForm> createState() => _MealTagFormState();
}

class _MealTagFormState extends ConsumerState<MealTagForm> {
  late String _selectedMealType;
  final TextEditingController _contentController = TextEditingController();
  _MealFormPhase _phase = _MealFormPhase.input;
  MealEstimationResult? _estimation;
  EstimationTotals? _editableTotals;
  bool _isSending = false;
  late _MealInputMode _inputMode;
  // 注: エラーメッセージはスナックバーで表示するだけなので state には持たない

  /// 「戻る」→「挿入」再試行時の再 upload を防ぐため、File と Storage URL の対応を保持。
  /// 確認シートの「送信」時にこの値を `onSendWithEstimation` の preUploadedUrls として渡す。
  final Map<File, String> _fileToUrlMap = {};

  static const _mealTypes = ['朝食', '昼食', '夕食', '間食'];

  @override
  void initState() {
    super.initState();
    _selectedMealType = _getDefaultMealType();
    _inputMode = widget.debugInitialScreenshotMode
        ? _MealInputMode.screenshot
        : _MealInputMode.cook;
    // シート表示と同時に AI 機能解放状態を事前フェッチ。
    // 挿入タップ時には resolve 済みになっているように先に future を発火させ、
    // free プランの場合に「AI推定中」のフラッシュが出ないようにする。
    ref.read(aiFeaturesEnabledProvider);
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

  /// テキスト挿入のみ（AI 呼び出しなし）。free プランの「挿入」ボタンと
  /// Pro プランの副「AIなしで挿入」ボタンの両方から呼ばれる。
  void _handleInsert() {
    if (!_isValid) return;
    widget.onCompose(_composedText);
  }

  /// AI 推定ボタン専用。aiEnabled を前提とし、入力がある状態でのみ呼ばれる
  /// （未入力時はボタンが無効化されている）。
  /// loading → estimate → confirm のフローを実行する。
  Future<void> _handleEstimate() async {
    if (!_isValid) return;

    // screenshot モードは画像必須
    if (_inputMode == _MealInputMode.screenshot && !widget.hasImages) return;

    // テキストも画像もない場合は推定しない（安全網）
    final hasContent = _contentController.text.trim().isNotEmpty;
    final canTryEstimate = widget.onSendWithEstimation != null
        && (hasContent || widget.hasImages);

    if (!canTryEstimate) {
      widget.onCompose(_composedText);
      return;
    }

    // 念のため AI 機能解放状態を再確認（initState で事前フェッチ済み）
    bool aiEnabled = false;
    try {
      aiEnabled = await ref.read(aiFeaturesEnabledProvider.future);
    } catch (_) {
      aiEnabled = false;
    }
    if (!mounted) return;

    if (!aiEnabled) {
      widget.onCompose(_composedText);
      return;
    }

    setState(() {
      _phase = _MealFormPhase.loading;
    });

    try {
      // 1. 未 upload の画像のみ upload する（既存 URL は再利用）
      final imageUrls = await _ensureImagesUploaded();
      if (!mounted || _phase != _MealFormPhase.loading) return;

      // 全画像 upload に失敗した場合
      if (widget.selectedImages.isNotEmpty && imageUrls.isEmpty) {
        setState(() => _phase = _MealFormPhase.input);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('画像のアップロードに失敗しました'),
            backgroundColor: AppColors.rose800,
            action: SnackBarAction(
              label: 'AIなしで送信',
              textColor: Colors.white,
              onPressed: () => widget.onCompose(_composedText),
            ),
          ),
        );
        return;
      }

      // 2. AI 推定
      final result = await MealEstimationApi.estimate(
        mealType: _mealTypeToEnum(_selectedMealType),
        content: _contentController.text.trim(),
        imageUrls: imageUrls,
        inputKind: _inputMode == _MealInputMode.screenshot ? 'screenshot' : 'photo',
      );
      // ユーザーがローディング中にキャンセルした場合は確認画面に進めない
      if (!mounted || _phase != _MealFormPhase.loading) return;
      setState(() {
        _estimation = result;
        _editableTotals = result.totals;
        _phase = _MealFormPhase.confirm;
      });
    } on MealEstimationException catch (e) {
      if (!mounted) return;
      final msg = _humanError(e);
      setState(() {
        _phase = _MealFormPhase.input;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.rose800,
          action: SnackBarAction(
            label: 'AIなしで送信',
            textColor: Colors.white,
            onPressed: () => widget.onCompose(_composedText),
          ),
        ),
      );
    }
  }

  /// 未 upload の選択画像のみを Storage にアップロードし、最終的な URL リストを返す。
  /// 「戻る」→「挿入」再試行時、既に `_fileToUrlMap` に存在する File は再 upload しない。
  /// 部分失敗（一部の File だけ upload 失敗）した場合、成功した URL のみで推定を継続する。
  Future<List<String>> _ensureImagesUploaded() async {
    if (widget.selectedImages.isEmpty) return const [];
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return const [];

    // 削除された File に対応するエントリを map から取り除く（orphan は許容）
    _fileToUrlMap.removeWhere((file, _) => !widget.selectedImages.contains(file));

    // 未 upload の File を抽出
    final pending = widget.selectedImages
        .where((f) => !_fileToUrlMap.containsKey(f))
        .toList();

    if (pending.isNotEmpty) {
      final results = await StorageService.uploadAiImages(pending, userId);
      for (var i = 0; i < pending.length; i++) {
        final url = results[i];
        if (url != null) _fileToUrlMap[pending[i]] = url;
      }
    }

    // selectedImages の順序で URL を返す（upload 失敗した File は除外）
    return widget.selectedImages
        .map((f) => _fileToUrlMap[f])
        .whereType<String>()
        .toList();
  }

  String _mealTypeToEnum(String label) {
    switch (label) {
      case '朝食':
        return 'breakfast';
      case '昼食':
        return 'lunch';
      case '夕食':
        return 'dinner';
      default:
        return 'snack';
    }
  }

  String _humanError(MealEstimationException e) {
    switch (e.code) {
      case MealEstimationErrorCode.rateLimit:
        return 'AI推定の上限に達しました。しばらくしてからお試しください';
      case MealEstimationErrorCode.network:
        return '通信エラーが発生しました';
      case MealEstimationErrorCode.forbidden:
        return 'AI機能が利用できません';
      case MealEstimationErrorCode.invalidInput:
        return '入力内容が不正です';
      case MealEstimationErrorCode.emptyResult:
        return '画像から食事を識別できませんでした。テキストで補足して再試行してください';
      case MealEstimationErrorCode.estimationFailed:
        return '推定に失敗しました。内容を変えてお試しください';
    }
  }

  Future<void> _handleSendWithEstimation() async {
    if (_estimation == null || _editableTotals == null) return;
    if (_isSending) return; // 二重送信防止（GestureDetectorの onTap=null と二重に保護）
    setState(() => _isSending = true);
    final estimationToSend = MealEstimationResult(
      foods: _estimation!.foods,
      totals: _editableTotals!,
      appName: _estimation!.appName,
    );
    // selectedImages の順序を保ちつつ upload 済み URL を抽出
    final preUploaded = widget.selectedImages
        .map((f) => _fileToUrlMap[f])
        .whereType<String>()
        .toList();
    try {
      await widget.onSendWithEstimation?.call(
        _composedText,
        estimationToSend,
        preUploaded,
      );
      // 親側でシートクローズが行われる想定。このウィジェットは unmount される
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
      child: switch (_phase) {
        _MealFormPhase.input => _buildInputState(colors),
        _MealFormPhase.loading => _buildLoadingState(colors),
        _MealFormPhase.confirm => _buildConfirmState(colors),
      },
    );
  }

  Widget _buildInputState(AppColorsExtension colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ヘッダー行
        Row(
          children: [
            Icon(LucideIcons.utensils, size: 16, color: colors.textPrimary),
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

        // 入力モード切替（Pro のみ表示）。free/未解決時は従来フォーム（cook 固定）。
        if (ref.watch(aiFeaturesEnabledProvider).maybeWhen(
              data: (enabled) => enabled,
              orElse: () => false,
            )) ...[
          _SegmentControl(
            items: const ['料理を記録', '他アプリから取込'],
            selected: _inputMode == _MealInputMode.screenshot
                ? '他アプリから取込'
                : '料理を記録',
            onChanged: (value) => setState(() {
              _inputMode = value == '他アプリから取込'
                  ? _MealInputMode.screenshot
                  : _MealInputMode.cook;
            }),
            colors: colors,
          ),
          const SizedBox(height: 8),
        ],

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
            hintText: _inputMode == _MealInputMode.screenshot
                ? 'メモ（任意）'
                : '食事内容やコメントを入力',
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
        // スクショモード限定: PFC が写ったスクショで精度が上がる旨のヒント
        if (_inputMode == _MealInputMode.screenshot) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'カロリー・PFCが表示されたスクショを添付すると、PFCも記録され精度が上がります',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),

        // プレビュー行 + アクションボタン
        _buildPreviewActions(colors),
      ],
    );
  }

  /// プレビューテキストとアクションボタンを構築する。
  /// AI 機能解放状態（aiFeaturesEnabledProvider）で「AI推定」「挿入」を出し分ける。
  ///
  /// 未解決（loading/error）時は保守的に free 版（「挿入」1つ）を表示し、
  /// true 確定後に2ボタンへ切り替える（ゲート結果が確定するまで保守的なUI）。
  Widget _buildPreviewActions(AppColorsExtension colors) {
    final aiEnabled = ref.watch(aiFeaturesEnabledProvider).maybeWhen(
          data: (enabled) => enabled,
          orElse: () => false,
        );

    // free（または未解決）: 従来どおり「挿入」1つ
    if (!aiEnabled) {
      return _PreviewRow(
        previewText: _previewText,
        isValid: _isValid,
        onInsert: _handleInsert,
        colors: colors,
      );
    }

    // Pro かつ screenshot モード: 「スクショを解析」主ボタン1つ（「AIなしで挿入」は出さない）
    if (_inputMode == _MealInputMode.screenshot) {
      final canAnalyze = widget.hasImages;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.messageCircle, size: 13, color: colors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _previewText,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canAnalyze ? _handleEstimate : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(LucideIcons.sparkles, size: 16),
              label: const Text('スクショを解析'),
            ),
          ),
          if (!canAnalyze) ...[
            const SizedBox(height: 6),
            Text(
              'スクショ画像を追加してください',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ],
        ],
      );
    }

    // Pro: プレビューテキスト + 「AI推定」「AIなしで挿入」の2ボタン
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // プレビューテキスト
        Row(
          children: [
            Icon(LucideIcons.messageCircle,
                size: 13, color: colors.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _previewText,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 主「AI推定」・副「AIなしで挿入」
        Row(
          children: [
            // 副: AIなしで挿入（低強調）
            Expanded(
              child: OutlinedButton(
                onPressed: _isValid ? _handleInsert : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor:
                      AppColors.primary.withValues(alpha: 0.75),
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.05),
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('AIなしで挿入'),
              ),
            ),
            const SizedBox(width: 8),
            // 主: AI推定（高強調）
            Expanded(
              child: FilledButton.icon(
                onPressed: _isValid ? _handleEstimate : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                icon: const Icon(LucideIcons.sparkles, size: 16),
                label: const Text('AI推定'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingState(AppColorsExtension colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.utensils, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text(
              'AI推定中…',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _phase = _MealFormPhase.input),
              child: Text('キャンセル', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildConfirmState(AppColorsExtension colors) {
    return MealEstimationConfirmView(
      estimation: _estimation!,
      totals: _editableTotals!,
      imageUrls: widget.selectedImages
          .map((f) => _fileToUrlMap[f])
          .whereType<String>()
          .toList(),
      onTotalsChanged: (t) => setState(() => _editableTotals = t),
      onBack: () => setState(() {
        _phase = _MealFormPhase.input;
        _estimation = null;
        _editableTotals = null;
      }),
      onSend: _handleSendWithEstimation,
      isSending: _isSending,
      appName: _estimation!.appName,
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
                Icon(LucideIcons.activity, size: 16, color: colors.textPrimary),
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
          child: Row(
            children: [
              Icon(LucideIcons.messageCircle, size: 13, color: colors.textSecondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  previewText,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
              Icon(LucideIcons.scale, size: 16, color: colors.textPrimary),
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
  return ProviderScope(
    child: MaterialApp(
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
    ),
  );
}

@Preview(name: 'MealTagForm - Pro (AI推定)')
Widget previewMealTagFormPro() {
  return ProviderScope(
    overrides: [
      aiFeaturesEnabledProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(
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
    ),
  );
}

@Preview(name: 'MealTagForm - スクショ取込モード')
Widget previewMealTagFormScreenshot() {
  return ProviderScope(
    overrides: [
      aiFeaturesEnabledProvider.overrideWith((ref) async => true),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: MealTagForm(
            onCompose: (_) {},
            onClose: () {},
            hasImages: true,
            onSendWithEstimation: (_, __, ___) async {},
            debugInitialScreenshotMode: true,
          ),
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
