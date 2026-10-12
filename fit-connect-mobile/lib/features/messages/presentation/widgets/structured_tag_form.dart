import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/data/meal_estimation_api.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/form_card.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/meal_estimation_confirm_view.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

// ============================================
// 記録フォーム（体重 / 食事 / 運動）
//
// 正本 `message-screens.js` の `MealForm`: カード（surface・角丸 23・余白 18・左右 16 のマージン）に
// 見出し行（アイコン accent + タイトル 16/500 + 閉じる）→ 区分のセグメント → 写真（72 + 追加）→
// 「内容」の入力 → 推定ボックス → 「入力欄に入る内容」→ 主要ボタン「入力欄に入れる」。
// 体重・運動のフォームも同じカードの作り（見出し・入力・「入力欄に入る内容」・主要ボタン）。
// ============================================

/// 「入力欄に入れる」ボタンの文言（3 つのフォーム共通）
const String _insertLabel = '入力欄に入れる';

class StructuredTagForm extends StatelessWidget {
  final String formType; // 'weight', 'meal', 'exercise'
  final Function(String composedText) onCompose;
  final VoidCallback onClose;
  final bool hasImages;
  final List<File> selectedImages;
  final VoidCallback? onPickImage;
  final Function(int)? onRemoveImage;

  /// PFC込みで送信。preUploadedPaths は 推定時に upload 済みの画像の
  /// バケット相対パス（再 upload 回避用）。
  /// null の場合は 推定なしで `onCompose` のみ実行
  final Future<void> Function(
    String composedText,
    MealEstimationResult estimation,
    List<String> preUploadedPaths,
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

  /// Preview/テスト用に体重の入力欄へ初期値を入れる（本番の導線では未指定）。
  final String? debugInitialWeight;

  const WeightTagForm({
    super.key,
    required this.onCompose,
    required this.onClose,
    this.selectedImages = const [],
    this.onPickImage,
    this.onRemoveImage,
    this.debugInitialWeight,
  });

  @override
  State<WeightTagForm> createState() => _WeightTagFormState();
}

class _WeightTagFormState extends State<WeightTagForm> {
  late final TextEditingController _weightController =
      TextEditingController(text: widget.debugInitialWeight);
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
    return FormCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeading(
            icon: LucideIcons.scale,
            title: '体重を記録',
            onClose: widget.onClose,
          ),

          // 体重
          FcTextField.number(
            label: '体重',
            unit: 'kg',
            hintText: '65.5',
            controller: _weightController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),

          // コメント
          FcTextField(
            label: 'ひとことコメント（任意）',
            controller: _commentController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),

          // 写真
          PhotoTiles(
            images: widget.selectedImages,
            onRemove: widget.onRemoveImage,
            onAdd: widget.onPickImage,
            maxCount: StorageService.maxImagesPerMessage,
          ),
          if (widget.selectedImages.isNotEmpty || widget.onPickImage != null)
            const SizedBox(height: AppSpacing.md),

          // 入力欄に入る内容 + 主要ボタン
          ComposedPreview(text: _previewText),
          const SizedBox(height: 14),
          FcButton.block(
            label: _insertLabel,
            onPressed: _isValid ? _handleInsert : null,
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

  /// PFC込みで送信。preUploadedPaths は AI 推定時に upload 済みの画像の
  /// バケット相対パス（再 upload 回避用）。
  /// null の場合は AI推定なしで `onCompose` のみ実行
  final Future<void> Function(
    String composedText,
    MealEstimationResult estimation,
    List<String> preUploadedPaths,
  )? onSendWithEstimation;

  /// Preview/テスト用に screenshot モードで初期表示する（本番の通常導線では未指定）。
  final bool debugInitialScreenshotMode;

  /// Preview/テスト用に「内容」の入力欄へ初期値を入れる（本番の通常導線では未指定）。
  final String? debugInitialContent;

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
    this.debugInitialContent,
  });

  @override
  ConsumerState<MealTagForm> createState() => _MealTagFormState();
}

class _MealTagFormState extends ConsumerState<MealTagForm> {
  late String _selectedMealType;
  late final TextEditingController _contentController =
      TextEditingController(text: widget.debugInitialContent);
  _MealFormPhase _phase = _MealFormPhase.input;
  MealEstimationResult? _estimation;
  EstimationTotals? _editableTotals;
  bool _isSending = false;
  late _MealInputMode _inputMode;
  // 注: エラーメッセージはスナックバーで表示するだけなので state には持たない

  /// AI推定フロー中の再 upload を防ぐため、File と Storage のバケット相対パスの対応を保持。
  /// 確認シートの「送信」時にこの値を `onSendWithEstimation` の preUploadedPaths として渡す。
  /// キャンセル・戻る・dispose 時には未送信分を Storage から削除する（orphan 8-B）。
  final Map<File, String> _fileToPathMap = {};

  /// 送信（メッセージ挿入）に使われたパス。挿入済み画像の誤削除防止のため、
  /// [_cleanupUnsentAiImages] はここに含まれるパスを絶対に削除しない。
  final Set<String> _sentPaths = {};

  /// AI推定フローの実行世代。キャンセル・戻る・dispose・再実行でインクリメントし、
  /// 旧実行が await 再開後に状態を触る（二重推定・ローディング巻き戻し・
  /// _fileToPathMap 上書きによる orphan）のを無効化する。
  int _estimateGeneration = 0;

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
    // フォーム破棄時、進行中の AI 推定実行を無効化し、
    // upload 済みで未送信の AI 画像を削除する（orphan 8-B）
    _estimateGeneration++;
    _cleanupUnsentAiImages();
    _contentController.dispose();
    super.dispose();
  }

  /// upload 済みだが送信（メッセージ挿入）に使われていない AI 画像を
  /// fire-and-forget で Storage から削除する（orphan 8-B）。
  /// 送信済み（[_sentPaths]）のパスは削除しない。削除失敗は無視する
  /// （8-A の定期クリーンアップが回収する）。
  void _cleanupUnsentAiImages() {
    final targets = _fileToPathMap.values
        .where((path) => !_sentPaths.contains(path))
        .toList();
    _fileToPathMap.removeWhere((_, path) => !_sentPaths.contains(path));
    for (final path in targets) {
      unawaited(
        StorageService.deleteByPath(StorageService.bucketName, path),
      );
    }
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

    // 本実行の世代を捕捉。キャンセル後の即再タップ等で世代が進んだら、
    // この実行は以降の await 再開時に何もせず打ち切る
    final gen = ++_estimateGeneration;

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
    if (!mounted || gen != _estimateGeneration) return;

    if (!aiEnabled) {
      widget.onCompose(_composedText);
      return;
    }

    setState(() {
      _phase = _MealFormPhase.loading;
    });

    try {
      // 1. 未 upload の画像のみ upload する（既存パスは再利用）
      final imagePaths = await _ensureImagesUploaded(gen);
      if (!mounted || gen != _estimateGeneration) {
        // 旧実行（キャンセル・再実行・破棄済み）。今 upload した分は
        // _ensureImagesUploaded 側で削除済みなので何もしない
        // （_cleanupUnsentAiImages を呼ぶと新実行の upload 済みパスを消してしまう）
        return;
      }
      if (_phase != _MealFormPhase.loading) {
        // upload 中にキャンセル・破棄された場合、今 upload した分は不要なので削除
        _cleanupUnsentAiImages();
        return;
      }

      // 全画像 upload に失敗した場合
      if (widget.selectedImages.isNotEmpty && imagePaths.isEmpty) {
        setState(() => _phase = _MealFormPhase.input);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('画像のアップロードに失敗しました'),
            action: SnackBarAction(
              label: '推定なしで送信',
              onPressed: () => widget.onCompose(_composedText),
            ),
          ),
        );
        return;
      }

      // 2. AI 推定（画像はバケット相対パスで渡し、Edge Function 側で署名して利用する）
      final result = await MealEstimationApi.estimate(
        mealType: _mealTypeToEnum(_selectedMealType),
        content: _contentController.text.trim(),
        imagePaths: imagePaths,
        inputKind: _inputMode == _MealInputMode.screenshot ? 'screenshot' : 'photo',
      );
      // ユーザーがローディング中にキャンセルした場合・旧実行の場合は確認画面に進めない
      if (!mounted ||
          gen != _estimateGeneration ||
          _phase != _MealFormPhase.loading) {
        return;
      }
      setState(() {
        _estimation = result;
        _editableTotals = result.totals;
        _phase = _MealFormPhase.confirm;
      });
    } on MealEstimationException catch (e) {
      // 旧実行の失敗が現在のローディングを input に巻き戻して
      // 新実行の結果を破棄しないよう、世代・フェーズをガード
      if (!mounted ||
          gen != _estimateGeneration ||
          _phase != _MealFormPhase.loading) {
        return;
      }
      final msg = _humanError(e);
      setState(() {
        _phase = _MealFormPhase.input;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: '推定なしで送信',
            onPressed: () => widget.onCompose(_composedText),
          ),
        ),
      );
    }
  }

  /// 未 upload の選択画像のみを Storage にアップロードし、バケット相対パスのリストを返す。
  /// 同一フロー内の再試行時、既に `_fileToPathMap` に存在する File は再 upload しない。
  /// 部分失敗（一部の File だけ upload 失敗）した場合、成功したパスのみで推定を継続する。
  /// [gen] は呼び出し元 `_handleEstimate` の実行世代。upload 完了時に世代が進んでいたら
  /// `_fileToPathMap` を上書きせず（新実行のパスを orphan 化させないため）、
  /// 今 upload した分を即削除して空リストを返す。
  Future<List<String>> _ensureImagesUploaded(int gen) async {
    if (widget.selectedImages.isEmpty) return const [];
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return const [];

    // 選択から外された File の upload 済み画像は Storage からも削除する（orphan 8-B）
    _fileToPathMap.removeWhere((file, path) {
      if (widget.selectedImages.contains(file)) return false;
      if (!_sentPaths.contains(path)) {
        unawaited(
          StorageService.deleteByPath(StorageService.bucketName, path),
        );
      }
      return true;
    });

    // 未 upload の File を抽出
    final pending = widget.selectedImages
        .where((f) => !_fileToPathMap.containsKey(f))
        .toList();

    if (pending.isNotEmpty) {
      final results = await StorageService.uploadAiImages(pending, userId);
      // upload 中に世代が進んだ（キャンセル・再実行・破棄）場合、マップへ書くと
      // 新実行の upload 済みパスを上書きして orphan を生むため、
      // 今 upload した分をその場で削除して打ち切る
      if (gen != _estimateGeneration) {
        for (final path in results.whereType<String>()) {
          unawaited(
            StorageService.deleteByPath(StorageService.bucketName, path),
          );
        }
        return const [];
      }
      for (var i = 0; i < pending.length; i++) {
        final path = results[i];
        if (path != null) _fileToPathMap[pending[i]] = path;
      }
    }

    // selectedImages の順序でパスを返す（upload 失敗した File は除外）
    return widget.selectedImages
        .map((f) => _fileToPathMap[f])
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
        return '本日の推定の上限に達しました。写真なしのテキスト推定は引き続き利用できます';
      case MealEstimationErrorCode.monthlyQuotaExceeded:
        return '今月の推定（写真）の上限に達しました。テキスト推定は引き続き利用できます';
      case MealEstimationErrorCode.freeQuotaExceeded:
        return '今月の推定の利用枠を使い切りました。来月また利用できます';
      case MealEstimationErrorCode.network:
        return '通信エラーが発生しました';
      case MealEstimationErrorCode.forbidden:
        return '推定の機能が利用できません';
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
    // selectedImages の順序を保ちつつ upload 済みパスを抽出
    final preUploaded = widget.selectedImages
        .map((f) => _fileToPathMap[f])
        .whereType<String>()
        .toList();
    // 送信に使うパスは呼び出し前に「送信済み」としてマークする。
    // 挿入済み画像の誤削除防止を最優先とし、送信が失敗して orphan になった場合は
    // 8-A の定期クリーンアップに委ねる
    _sentPaths.addAll(preUploaded);
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
    return FormCard(
      child: switch (_phase) {
        _MealFormPhase.input => _buildInputState(context),
        _MealFormPhase.loading => _buildLoadingState(context),
        _MealFormPhase.confirm => _buildConfirmState(),
      },
    );
  }

  Widget _buildInputState(BuildContext context) {
    final aiEnabled = ref.watch(aiFeaturesEnabledProvider).maybeWhen(
          data: (enabled) => enabled,
          orElse: () => false,
        );
    final screenshot = _inputMode == _MealInputMode.screenshot;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeading(
          icon: LucideIcons.utensils,
          title: '食事を記録',
          onClose: widget.onClose,
        ),

        // 入力モード切替（推定が使えるときだけ表示）。未解決時は従来フォーム（cook 固定）。
        if (aiEnabled) ...[
          FcSegmentedControl<_MealInputMode>(
            items: const [
              FcSegmentedItem(value: _MealInputMode.cook, label: '料理を記録'),
              FcSegmentedItem(
                  value: _MealInputMode.screenshot, label: '他アプリから取込'),
            ],
            selected: _inputMode,
            onChanged: (mode) => setState(() => _inputMode = mode),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 食事の区分
        FcSegmentedControl<String>(
          items: [
            for (final type in _mealTypes)
              FcSegmentedItem(value: type, label: type),
          ],
          selected: _selectedMealType,
          onChanged: (value) => setState(() => _selectedMealType = value),
        ),
        const SizedBox(height: AppSpacing.md),

        // 写真（72 + 追加）
        PhotoTiles(
          images: widget.selectedImages,
          onRemove: widget.onRemoveImage,
          onAdd: widget.onPickImage,
          maxCount: StorageService.maxImagesPerMessage,
        ),
        if (widget.selectedImages.isNotEmpty || widget.onPickImage != null)
          const SizedBox(height: AppSpacing.md),

        // 内容
        FcTextField(
          label: '内容',
          hintText: screenshot ? 'メモ（任意）' : '食事内容やコメントを入力',
          controller: _contentController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),

        // スクショモード限定: PFC が写ったスクショで精度が上がる旨のヒント
        if (screenshot) ...[
          const FcInlineNotice.neutral(
            message: 'カロリー・PFCが表示されたスクショを添付すると、PFCも記録され精度が上がります',
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 入力欄に入る内容 + 操作
        ..._buildActions(context, aiEnabled: aiEnabled, screenshot: screenshot),
      ],
    );
  }

  /// 「入力欄に入る内容」と主要ボタン。推定が使えるか（aiEnabledProvider）で出し分ける。
  ///
  /// 未解決（loading/error）時は保守的に free 版（「入力欄に入れる」だけ）を表示し、
  /// true 確定後に推定ボックスを足す（ゲート結果が確定するまで保守的なUI）。
  List<Widget> _buildActions(
    BuildContext context, {
    required bool aiEnabled,
    required bool screenshot,
  }) {
    // free（または未解決）: 「入力欄に入れる」だけ
    if (!aiEnabled) {
      return [
        ComposedPreview(text: _previewText),
        const SizedBox(height: 14),
        FcButton.block(
          label: _insertLabel,
          onPressed: _isValid ? _handleInsert : null,
        ),
      ];
    }

    // 推定が使えて screenshot モード: 「スクショを解析」だけ（「入力欄に入れる」は出さない）
    if (screenshot) {
      final canAnalyze = widget.hasImages;
      return [
        ComposedPreview(text: _previewText, title: '送信される内容'),
        const SizedBox(height: 14),
        FcButton.block(
          label: 'スクショを解析',
          icon: LucideIcons.calculator,
          iconPosition: FcIconPosition.start,
          onPressed: canAnalyze ? _handleEstimate : null,
        ),
        if (!canAnalyze) ...[
          const SizedBox(height: 6),
          Text(
            'スクショ画像を追加してください',
            style: AppTextStyles.caption(context),
          ),
        ],
      ];
    }

    // 推定が使えて cook モード: 推定ボックス（「推定する」）+「入力欄に入れる」
    return [
      _EstimateEntryBox(
        sourceLabel: widget.hasImages ? '写真からの推定（目安）' : '内容からの推定（目安）',
        onEstimate: _isValid ? _handleEstimate : null,
      ),
      const SizedBox(height: AppSpacing.md),
      ComposedPreview(text: _previewText),
      const SizedBox(height: 14),
      FcButton.block(
        label: _insertLabel,
        onPressed: _isValid ? _handleInsert : null,
      ),
    ];
  }

  Widget _buildLoadingState(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormHeading(
          icon: LucideIcons.calculator,
          title: '推定しています…',
          leading: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.accent,
            ),
          ),
          action: FcPressable(
            onTap: _handleCancelLoading,
            semanticLabel: 'キャンセル',
            minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                'キャンセル',
                style: AppTextStyles.actionLabel(context).copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
        // 配置を保つ控えめなプレースホルダー（推定が返るまでの間）
        Semantics(
          label: '推定しています',
          liveRegion: true,
          child: const FcInfoBox(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FcSkeleton.line(width: 140),
                SizedBox(height: AppSpacing.sm),
                FcSkeleton(width: 96, height: 22),
                SizedBox(height: AppSpacing.sm),
                FcSkeleton.line(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 推定ローディングのキャンセル。進行中の実行を世代インクリメントで無効化して
  /// 入力フェーズに戻し、upload 済みで未送信の AI 画像を削除する（orphan 8-B）。
  /// upload がまだ完了していない場合は `_ensureImagesUploaded` 側の
  /// 世代チェック後のクリーンアップが削除を引き継ぐ。
  void _handleCancelLoading() {
    _estimateGeneration++;
    _cleanupUnsentAiImages();
    setState(() => _phase = _MealFormPhase.input);
  }

  Widget _buildConfirmState() {
    return MealEstimationConfirmView(
      estimation: _estimation!,
      totals: _editableTotals!,
      imageValues: widget.selectedImages
          .map((f) => _fileToPathMap[f])
          .whereType<String>()
          .toList(),
      onTotalsChanged: (t) => setState(() => _editableTotals = t),
      onBack: () {
        // 確認シートから戻る場合、進行中の実行を無効化した上で
        // upload 済みの AI 画像は破棄する（orphan 8-B）。
        // 再度 推定する場合は再 upload される
        _estimateGeneration++;
        _cleanupUnsentAiImages();
        setState(() {
          _phase = _MealFormPhase.input;
          _estimation = null;
          _editableTotals = null;
        });
      },
      onSend: _handleSendWithEstimation,
      isSending: _isSending,
      appName: _estimation!.appName,
      warning: _estimation!.warning,
      composedText: _composedText,
    );
  }
}

/// 推定ボックス（まだ推定していない状態）。正本 `MealForm` の推定ボックスの入口。
///
/// surfaceSecondary の囲み: calculator 13 +「写真からの推定（目安）」caption、右に accent の「推定する」。
/// 数値は推定のあとに出る（確認画面）。「推定」「目安」と明記し、AI の断定にしない。
class _EstimateEntryBox extends StatelessWidget {
  const _EstimateEntryBox({required this.sourceLabel, required this.onEstimate});

  final String sourceLabel;

  /// null なら「推定する」を押せない（内容も写真も無いとき）
  final VoidCallback? onEstimate;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onEstimate != null;

    return FcInfoBox(
      // 見出し行が「推定する」の押せる範囲（高さ 44）で決まるので、上の余白は 0
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
                  child: Text(sourceLabel, style: AppTextStyles.caption(context)),
                ),
                FcPressable(
                  onTap: onEstimate,
                  enabled: enabled,
                  semanticLabel: '栄養を推定する',
                  minSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
                  child: Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Text(
                        '推定する',
                        style: AppTextStyles.supplement(context).copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Text(
            'まだ推定していません。内容や写真から、カロリーとPFCの目安を出せます。',
            style: AppTextStyles.supplement(context),
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

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty || widget.hasImages;

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
    final minutesField = FcTextField.number(
      label: '時間（任意）',
      unit: '分',
      hintText: '30',
      decimal: false,
      controller: _minutesController,
      onChanged: (_) => setState(() {}),
    );
    final kcalField = FcTextField.number(
      label: '消費カロリー（任意）',
      unit: 'kcal',
      hintText: '150',
      decimal: false,
      controller: _kcalController,
      onChanged: (_) => setState(() {}),
    );
    // 文字拡大のときは縦に積み直す（縮めない）
    final large = MediaQuery.textScalerOf(context).scale(15) > 17;

    return FormCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormHeading(
            icon: LucideIcons.dumbbell,
            title: '運動を記録',
            onClose: widget.onClose,
          ),

          // 種類
          FcSegmentedControl<String>(
            items: [
              for (final type in _exerciseTypes)
                FcSegmentedItem(value: type, label: type),
            ],
            selected: _selectedType,
            onChanged: (value) => setState(() => _selectedType = value),
          ),
          const SizedBox(height: AppSpacing.md),

          // 内容
          FcTextField(
            label: '内容',
            hintText: '運動内容やコメントを入力',
            controller: _nameController,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),

          // 時間・カロリー
          if (large) ...[
            minutesField,
            const SizedBox(height: AppSpacing.md),
            kcalField,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: minutesField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: kcalField),
              ],
            ),
          const SizedBox(height: AppSpacing.md),

          // 写真
          PhotoTiles(
            images: widget.selectedImages,
            onRemove: widget.onRemoveImage,
            onAdd: widget.onPickImage,
            maxCount: StorageService.maxImagesPerMessage,
          ),
          if (widget.selectedImages.isNotEmpty || widget.onPickImage != null)
            const SizedBox(height: AppSpacing.md),

          // 入力欄に入る内容 + 主要ボタン
          ComposedPreview(text: _previewText),
          const SizedBox(height: 14),
          FcButton.block(
            label: _insertLabel,
            onPressed: _isValid ? _handleInsert : null,
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required Widget form,
  double textScale = 1.0,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
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
              child: form,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 推定が使えるプラン（推定ボックスが出る）
final List<Override> _aiOn = [
  aiFeaturesEnabledProvider.overrideWith((ref) async => true),
];

@Preview(name: 'WeightTagForm - 空')
Widget previewWeightTagFormEmpty() => _previewApp(
      brightness: Brightness.light,
      form: WeightTagForm(onCompose: (_) {}, onClose: () {}),
    );

@Preview(name: 'WeightTagForm - 入力済み')
Widget previewWeightTagFormFilled() => _previewApp(
      brightness: Brightness.light,
      form: WeightTagForm(
        onCompose: (_) {},
        onClose: () {},
        debugInitialWeight: '65.5',
      ),
    );

@Preview(name: 'MealTagForm - 通常')
Widget previewMealTagFormDefault() => _previewApp(
      brightness: Brightness.light,
      form: MealTagForm(onCompose: (_) {}, onClose: () {}),
    );

@Preview(name: 'MealTagForm - 推定あり（入力済み）')
Widget previewMealTagFormPro() => _previewApp(
      brightness: Brightness.light,
      overrides: _aiOn,
      form: MealTagForm(
        onCompose: (_) {},
        onClose: () {},
        debugInitialContent: '鶏むね肉のグリル定食',
      ),
    );

@Preview(name: 'MealTagForm - スクショ取込モード')
Widget previewMealTagFormScreenshot() => _previewApp(
      brightness: Brightness.light,
      overrides: _aiOn,
      form: MealTagForm(
        onCompose: (_) {},
        onClose: () {},
        hasImages: true,
        onSendWithEstimation: (_, __, ___) async {},
        debugInitialScreenshotMode: true,
      ),
    );

@Preview(name: 'MealTagForm - ダーク')
Widget previewMealTagFormDark() => _previewApp(
      brightness: Brightness.dark,
      overrides: _aiOn,
      form: MealTagForm(
        onCompose: (_) {},
        onClose: () {},
        debugInitialContent: '鶏むね肉のグリル定食',
      ),
    );

@Preview(name: 'MealTagForm - 文字1.35')
Widget previewMealTagFormLarge() => _previewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      overrides: _aiOn,
      form: MealTagForm(
        onCompose: (_) {},
        onClose: () {},
        debugInitialContent: '鶏むね肉のグリル定食',
      ),
    );

@Preview(name: 'ExerciseTagForm - 通常')
Widget previewExerciseTagFormDefault() => _previewApp(
      brightness: Brightness.light,
      form: ExerciseTagForm(onCompose: (_) {}, onClose: () {}),
    );

@Preview(name: 'ExerciseTagForm - 文字1.35')
Widget previewExerciseTagFormLarge() => _previewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      form: ExerciseTagForm(onCompose: (_) {}, onClose: () {}),
    );

@Preview(name: 'StructuredTagForm - ダーク（体重）')
Widget previewStructuredTagFormDark() => _previewApp(
      brightness: Brightness.dark,
      form: StructuredTagForm(
        formType: 'weight',
        onCompose: (_) {},
        onClose: () {},
      ),
    );
