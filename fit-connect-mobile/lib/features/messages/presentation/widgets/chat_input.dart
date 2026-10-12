import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/form_card.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/tag_suggestion_list.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_preview.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/quick_action_bar.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/structured_tag_form.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// メッセージの入力エリア（正本 `message-screens.js` の `Composer` / `InputRow` / `ComposerTags`）。
///
/// 3 つの見え方がある（どれも背景の上に直接置く。区切り線・塗りは持たない）:
/// - 会話: クイック操作（体重 / 食事 / 運動）＋入力行
/// - `#` 入力中: 「タグの候補」のカード＋（返信バナー）＋入力行（クイック操作は隠す）
/// - 記録フォーム: フォームのカード＋入力行（入力行は残す。「入力欄に入れる」で入る先を見せる）
///
/// 入力行 = 写真を添付（丸 44）＋テキスト欄（surface・角丸 22・最小高さ 44）＋送信（丸 44・actionFill）。
/// 全体は [SingleChildScrollView] で包み、親が高さを制限したとき（キーボード表示中にフォームを開いた
/// ときなど）はフォームの側がスクロールして、入力行は常に下に見える。
class ChatInput extends StatefulWidget {
  /// メッセージ送信コールバック。
  /// imageUrls には message-photos のバケット相対パスを渡す
  /// （DB カラム `messages.image_urls` に合わせた引数名。表示時に署名URLへ解決する）
  final Future<void> Function(
      String text,
      List<String>? imageUrls,
      String? replyToMessageId,
      Map<String, dynamic>? metadata) onSend;
  final String? userId;
  final String? replyToMessageId;
  final String? replyToContent;

  /// 返信先を書いた人の呼び名（トレーナーの名前。自分のメッセージなら「自分」）。
  /// 返信バナーの「{名前}に返信」に使う。null なら「返信先」
  final String? replyToSenderName;
  final VoidCallback? onCancelReply;
  final String? editingMessageId;
  final String? editingMessageContent;
  final VoidCallback? onCancelEdit;

  /// 外部から流し込む定型文（セッションの「変更を相談」など）。
  /// 編集モードと同時に渡された場合は編集モードを優先する
  final String? initialDraft;

  /// 定型文を入力欄へ反映し終えたタイミングで呼ばれる。
  /// 呼び出し側はここで draft を破棄し、再ビルドでの再注入を防ぐ
  final VoidCallback? onDraftConsumed;

  const ChatInput({
    super.key,
    required this.onSend,
    this.userId,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderName,
    this.onCancelReply,
    this.editingMessageId,
    this.editingMessageContent,
    this.onCancelEdit,
    this.initialDraft,
    this.onDraftConsumed,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _showSuggestions = false;
  String _currentTagQuery = '';
  String? _selectedTagHint; // タグ選択後に表示するヒント（タグ以降の部分）
  List<File> _selectedImages = []; // 選択された画像ファイル
  bool _isUploading = false; // アップロード中フラグ
  String? _activeFormType; // null: フォーム非表示, 'weight'/'meal'/'exercise': 対応フォーム表示

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    // 初期化時に編集モードの場合はテキストをセット
    if (widget.editingMessageContent != null) {
      _controller.text = widget.editingMessageContent!;
      // 次フレームでカーソルを末尾に移動
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      });
    } else {
      // 編集モードでなければ定型文を流し込む
      _applyInitialDraft();
    }
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 編集モードに入った場合（null → 値に変化）
    if (oldWidget.editingMessageId == null && widget.editingMessageId != null) {
      _controller.text = widget.editingMessageContent ?? '';
      // カーソルを末尾に移動
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      });
    }
    // 編集モードが解除された場合（値 → nullに変化）
    if (oldWidget.editingMessageId != null && widget.editingMessageId == null) {
      _controller.clear();
    }
    // 定型文が新しく渡された場合（null → 値、または別の文面に変化）
    if (widget.initialDraft != oldWidget.initialDraft) {
      _applyInitialDraft();
    }
  }

  /// 定型文を入力欄へ流し込む。
  /// 編集モード中は編集内容を壊さないよう何もしない（編集モードが優先）
  void _applyInitialDraft() {
    final draft = widget.initialDraft;
    if (draft == null || draft.isEmpty) return;
    if (widget.editingMessageId != null) return;

    _controller.text = draft;
    // 次フレームでカーソルを末尾に移動。
    // 消費通知も同じタイミングで行う（build 中の setState を避けるため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      widget.onDraftConsumed?.call();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    // テキスト変更時は必ず再描画して送信ボタンの状態を更新する
    setState(() {});

    if (selection.baseOffset >= 0) {
      final upToCursor = text.substring(0, selection.baseOffset);
      final lastHash = upToCursor.lastIndexOf('#');

      if (lastHash != -1) {
        final afterHash = upToCursor.substring(lastHash);
        // ハッシュの後にスペースや改行がない場合のみタグ入力中とみなす
        if (!afterHash.contains(' ') && !afterHash.contains('\n')) {
          if (mounted) {
            setState(() {
              _showSuggestions = true;
              _currentTagQuery = afterHash;
              _selectedTagHint = null; // タグ入力中はヒント非表示
            });
          }
          return;
        }

        // タグ+スペースの後、内容がまだ入力されていない場合はヒントを表示
        if (_selectedTagHint != null) {
          final spaceIndex = afterHash.indexOf(' ');
          if (spaceIndex != -1) {
            final afterSpace = afterHash.substring(spaceIndex + 1).trim();
            // 内容が入力されたらヒントを非表示
            if (afterSpace.isNotEmpty) {
              setState(() {
                _selectedTagHint = null;
              });
            }
          }
        }
      }
    }

    if (_showSuggestions && mounted) {
      setState(() {
        _showSuggestions = false;
        _currentTagQuery = '';
      });
    }
  }

  void _addTag(String tag, bool addSpace, String? example) {
    if (!_showSuggestions) return;

    final text = _controller.text;
    final selection = _controller.selection;
    final suffixSpace = addSpace ? ' ' : '';

    // 入力例からタグ以降の部分を抽出してヒントとして保存
    if (example != null && addSpace) {
      // "例: #食事:昼食 サラダチキン、玄米おにぎり" → "サラダチキン、玄米おにぎり"
      final tagPattern = RegExp(r'^例:\s*#[^\s]+\s+');
      final hintMatch = tagPattern.firstMatch(example);
      if (hintMatch != null) {
        _selectedTagHint = example.substring(hintMatch.end);
      }
    }

    if (selection.baseOffset < 0) {
      _controller.text = '$text $tag$suffixSpace';
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    } else {
      final upToCursor = text.substring(0, selection.baseOffset);
      final lastHash = upToCursor.lastIndexOf('#');

      if (lastHash != -1) {
        final prefix = upToCursor.substring(0, lastHash);
        final suffix = text.substring(selection.baseOffset);

        final newText = '$prefix$tag$suffixSpace$suffix';
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(
              offset: prefix.length + tag.length + suffixSpace.length),
        );
      }
    }

    // 候補リストの表示状態は _onTextChanged リスナーがテキスト変更を検知して適切に更新するため、
    // ここで強制的に非表示にする必要はない。
  }

  /// タグを除いた本文があるかチェック
  bool _hasContentBesidesTag(String text) {
    // タグパターン: #食事:朝食, #運動:筋トレ, #体重 など
    final tagPattern = RegExp(r'#(食事|運動|体重)(?::[^\s]+)?');
    final withoutTags = text.replaceAll(tagPattern, '').trim();
    return withoutTags.isNotEmpty;
  }

  /// 送信可能かどうかを判定
  bool _canSend() {
    if (_isUploading) return false;

    final text = _controller.text.trim();
    final hasImages = _selectedImages.isNotEmpty;

    // テキストも画像もない場合は送信不可
    if (text.isEmpty && !hasImages) return false;

    // タグが含まれている場合は、タグ以外の内容が必要（画像がある場合も可）
    final hasTag = RegExp(r'#(食事|運動|体重)').hasMatch(text);
    if (hasTag && !hasImages) {
      return _hasContentBesidesTag(text);
    }

    // タグがない場合、またはタグ+画像がある場合は送信可能
    return true;
  }

  /// 画像を選択
  Future<void> _pickImage() async {
    if (_selectedImages.length >= StorageService.maxImagesPerMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('画像は最大${StorageService.maxImagesPerMessage}枚までです'),
        ),
      );
      return;
    }

    final file = await StorageService.showImagePickerDialog(context);
    if (file != null) {
      setState(() {
        _selectedImages.add(file);
      });
    }
  }

  /// 選択した画像を削除
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  /// 選択中の画像があればアップロードしてバケット相対パスのリストを返す。
  /// - 画像が1枚も選択されていない場合は空のリスト（`const []`）を返す。
  /// - アップロード失敗 / userId 不在等の異常時は null を返す（呼び出し側は早期 return すべし）。
  Future<List<String>?> _uploadImagesIfAny() async {
    if (_selectedImages.isEmpty) return const [];
    if (widget.userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザー情報が取得できませんでした'),
          ),
        );
      }
      return null;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final paths = await StorageService.uploadImages(
        _selectedImages,
        widget.userId!,
      );
      if (paths.isEmpty && _selectedImages.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('画像のアップロードに失敗しました'),
            ),
          );
        }
        setState(() {
          _isUploading = false;
        });
        return null;
      }
      return paths;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('画像のアップロードに失敗しました: $e'),
          ),
        );
      }
      setState(() {
        _isUploading = false;
      });
      return null;
    }
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();

    // 送信可能かチェック
    if (!_canSend()) {
      if (text.isNotEmpty && RegExp(r'#(食事|運動|体重)').hasMatch(text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('タグだけでなく、内容も入力してください'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 画像がある場合はアップロード
    final imageUrls = await _uploadImagesIfAny();
    if (imageUrls == null) return; // upload失敗 or 異常終了

    // メッセージ送信
    try {
      await widget.onSend(
        text,
        imageUrls.isEmpty ? null : imageUrls,
        widget.replyToMessageId,
        null,
      );
      _controller.clear();
      setState(() {
        _showSuggestions = false;
        _selectedTagHint = null;
        _selectedImages = [];
        _isUploading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('送信に失敗しました: $e'),
          ),
        );
      }
      setState(() {
        _isUploading = false;
      });
    }
  }

  /// MealTagForm からのAI推定送信フロー。
  /// metadata に meal_estimation を含めてメッセージを送信し、
  /// parse-message-tags webhook が PFC込みで meal_records を作成する。
  Future<void> _handleSendWithEstimation(
    String composedText,
    MealEstimationResult estimation,
    List<String> preUploadedPaths,
  ) async {
    // AI 推定フェーズで既に upload 済みなら再 upload しない（二重 upload 防止）。
    // _selectedImages が空なら preUploadedPaths も空のまま、上流の検証で挿入は防がれている。
    final List<String> imageUrls = preUploadedPaths;

    final appName = estimation.appName;
    final String mealSource;
    if (appName != null && appName.isNotEmpty) {
      mealSource = 'screenshot:$appName';
    } else if (imageUrls.isNotEmpty) {
      mealSource = 'photo';
    } else {
      mealSource = 'text';
    }

    final metadata = <String, dynamic>{
      'meal_estimation': {
        'foods': estimation.foods.map((f) => f.toJson()).toList(),
        'calories': estimation.totals.calories,
        'protein_g': estimation.totals.proteinG,
        'fat_g': estimation.totals.fatG,
        'carbs_g': estimation.totals.carbsG,
        'source': mealSource,
      },
    };

    try {
      await widget.onSend(
        composedText,
        imageUrls.isEmpty ? null : imageUrls,
        widget.replyToMessageId,
        metadata,
      );
      _controller.clear();
      _closeStructuredForm();
      setState(() {
        _showSuggestions = false;
        _selectedTagHint = null;
        _selectedImages = [];
        _isUploading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('送信に失敗しました: $e'),
          ),
        );
      }
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _openStructuredForm(String type) {
    setState(() {
      _activeFormType = type;
      _showSuggestions = false;
      _selectedTagHint = null;
    });
  }

  void _closeStructuredForm() {
    setState(() {
      _activeFormType = null;
    });
  }

  void _insertComposedText(String text) {
    final currentText = _controller.text.trim();
    if (currentText.isEmpty) {
      _controller.text = text;
    } else {
      _controller.text = '$currentText\n$text';
    }
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    _closeStructuredForm();
    _focusNode.requestFocus();
  }

  /// 入力行（写真を添付・テキスト欄・送信）。正本 `InputRow`
  Widget _buildInputRow(BuildContext context, {required bool isEditMode}) {
    final colors = AppColors.of(context);
    final canSend = _canSend();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FcIconButton(
          icon: LucideIcons.camera,
          semanticLabel: '写真を添付',
          onPressed: _isUploading ? null : _pickImage,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 4,
              minLines: 1,
              enabled: !_isUploading,
              cursorColor: colors.accent,
              style: AppTextStyles.body(context),
              // テーマの InputDecoration（surface + 1px の枠）は使わず、外側の面だけにする
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'メッセージを入力',
                hintStyle: AppTextStyles.body(context)
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (_isUploading)
          Semantics(
            label: '送信しています',
            liveRegion: true,
            child: Container(
              width: AppSizes.minTouch,
              height: AppSizes.minTouch,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.actionFill,
              ),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onAction,
                ),
              ),
            ),
          )
        else
          FcIconButton(
            icon: isEditMode ? LucideIcons.check : LucideIcons.arrowUp,
            semanticLabel: isEditMode ? '編集を保存' : '送信',
            primary: true,
            onPressed: canSend ? _handleSend : null,
          ),
      ],
    );
  }

  /// 縦に並べる子の間に [gap] を挟む
  List<Widget> _spaced(List<Widget> children, double gap) {
    return [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 編集モードと返信モードの排他制御
    final isEditMode = widget.editingMessageId != null;
    final isReplyMode = widget.replyToContent != null && !isEditMode;
    final formOpen = _activeFormType != null;
    final suggesting = _showSuggestions && !formOpen;
    final inputRow = _buildInputRow(context, isEditMode: isEditMode);

    final Widget body;
    if (formOpen) {
      // 記録フォーム: フォームのカード＋入力行（入力行は残す）。正本 `mode="form"`
      body = Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StructuredTagForm(
              formType: _activeFormType!,
              onCompose: _insertComposedText,
              onClose: _closeStructuredForm,
              hasImages: _selectedImages.isNotEmpty,
              selectedImages: _selectedImages,
              onPickImage: _pickImage,
              onRemoveImage: _removeImage,
              onSendWithEstimation: _handleSendWithEstimation,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: inputRow,
            ),
          ],
        ),
      );
    } else {
      // 会話 / # 入力中。正本 `Composer` / `ComposerTags`
      body = Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          10,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _spaced(
            [
              // タグの候補（# を入力している間だけ）
              if (suggesting)
                TagSuggestionList(
                  query: _currentTagQuery,
                  onSelect: _addTag,
                  textFieldFocusNode: _focusNode,
                ),
              // 編集バナー（編集モード時のみ）
              if (isEditMode)
                ComposerBanner(
                  icon: LucideIcons.pencil,
                  title: 'メッセージを編集中',
                  quote: widget.editingMessageContent ?? '',
                  closeLabel: '編集をやめる',
                  onClose: widget.onCancelEdit ?? () {},
                ),
              // 返信バナー（返信モード時のみ）
              if (isReplyMode)
                ReplyPreview(
                  messageContent: widget.replyToContent!,
                  senderName: widget.replyToSenderName,
                  onCancel: widget.onCancelReply ?? () {},
                ),
              // クイック操作（# の候補を出している間は隠す）
              if (!suggesting) QuickActionBar(onTap: _openStructuredForm),
              // タグ選択後のヒント（タグ以降の入力例）
              if (!suggesting && _selectedTagHint != null)
                Text(
                  '例: $_selectedTagHint',
                  style: AppTextStyles.caption(context),
                ),
              // 選んだ写真
              if (_selectedImages.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PhotoTiles(
                    images: _selectedImages,
                    onRemove: _removeImage,
                  ),
                ),
              inputRow,
            ],
            suggesting ? AppSpacing.sm : 10,
          ),
        ),
      );
    }

    // 親が高さを制限したときだけスクロールする（reverse: 入力行が下に残る）。
    // primary: false … 画面側の ScrollController（会話の一覧）と取り合わない
    return SingleChildScrollView(
      reverse: true,
      primary: false,
      child: body,
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required Widget child,
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
        child: Column(
          children: [
            const Spacer(),
            child,
          ],
        ),
      ),
    ),
  );
}

ChatInput _previewInput({
  String? replyToContent,
  String? replyToSenderName,
  String? editingMessageId,
  String? editingMessageContent,
  String? initialDraft,
}) {
  return ChatInput(
    onSend: (text, images, replyTo, metadata) async {},
    userId: 'user-123',
    replyToMessageId: replyToContent == null ? null : 'msg-123',
    replyToContent: replyToContent,
    replyToSenderName: replyToSenderName,
    onCancelReply: () {},
    editingMessageId: editingMessageId,
    editingMessageContent: editingMessageContent,
    onCancelEdit: () {},
    initialDraft: initialDraft,
    onDraftConsumed: () {},
  );
}

@Preview(name: 'ChatInput - 通常（会話）')
Widget previewChatInputNormal() =>
    _previewApp(brightness: Brightness.light, child: _previewInput());

@Preview(name: 'ChatInput - 返信')
Widget previewChatInputReply() => _previewApp(
      brightness: Brightness.light,
      child: _previewInput(
        replyToContent: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
        replyToSenderName: '田中トレーナー',
      ),
    );

@Preview(name: 'ChatInput - 編集')
Widget previewChatInputEdit() => _previewApp(
      brightness: Brightness.light,
      child: _previewInput(
        editingMessageId: 'msg-456',
        editingMessageContent: '今日のトレーニングは30分のランニングと腹筋100回をやりました！',
      ),
    );

@Preview(name: 'ChatInput - 定型文あり')
Widget previewChatInputWithDraft() {
  // セッションの「変更を相談」から定型文が流し込まれた直後の状態
  return _previewApp(
    brightness: Brightness.light,
    child: _previewInput(initialDraft: '9月10日(水) 18:00 のセッションについて相談です。'),
  );
}

@Preview(name: 'ChatInput - ダーク')
Widget previewChatInputDark() =>
    _previewApp(brightness: Brightness.dark, child: _previewInput());

@Preview(name: 'ChatInput - 文字1.35')
Widget previewChatInputLarge() => _previewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      child: _previewInput(
        replyToContent: 'お疲れさまでした。',
        replyToSenderName: '田中トレーナー',
      ),
    );
