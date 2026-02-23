import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/tag_suggestion_list.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_preview.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ChatInput extends StatefulWidget {
  final Future<void> Function(
      String text, List<String>? imageUrls, String? replyToMessageId) onSend;
  final String? userId;
  final String? replyToMessageId;
  final String? replyToContent;
  final VoidCallback? onCancelReply;
  final String? editingMessageId;
  final String? editingMessageContent;
  final VoidCallback? onCancelEdit;

  const ChatInput({
    super.key,
    required this.onSend,
    this.userId,
    this.replyToMessageId,
    this.replyToContent,
    this.onCancelReply,
    this.editingMessageId,
    this.editingMessageContent,
    this.onCancelEdit,
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
          backgroundColor: AppColors.orange500,
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

  Future<void> _handleSend() async {
    final text = _controller.text.trim();

    // 送信可能かチェック
    if (!_canSend()) {
      if (text.isNotEmpty && RegExp(r'#(食事|運動|体重)').hasMatch(text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('タグだけでなく、内容も入力してください'),
            backgroundColor: AppColors.orange500,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // 画像がある場合はアップロード
    List<String>? imageUrls;
    if (_selectedImages.isNotEmpty) {
      if (widget.userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザー情報が取得できませんでした'),
            backgroundColor: AppColors.rose800,
          ),
        );
        return;
      }

      setState(() {
        _isUploading = true;
      });

      try {
        imageUrls = await StorageService.uploadImages(
          _selectedImages,
          widget.userId!,
        );

        if (imageUrls.isEmpty && _selectedImages.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('画像のアップロードに失敗しました'),
                backgroundColor: AppColors.rose800,
              ),
            );
          }
          setState(() {
            _isUploading = false;
          });
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('画像のアップロードに失敗しました: $e'),
              backgroundColor: AppColors.rose800,
            ),
          );
        }
        setState(() {
          _isUploading = false;
        });
        return;
      }
    }

    // メッセージ送信
    try {
      await widget.onSend(text, imageUrls, widget.replyToMessageId);
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
            backgroundColor: AppColors.rose800,
          ),
        );
      }
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // 編集モードと返信モードの排他制御
    final isEditMode = widget.editingMessageId != null;
    final isReplyMode = widget.replyToContent != null && !isEditMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 編集プレビュー（編集モード時のみ表示）
        if (isEditMode)
          _EditPreview(
            messageContent: widget.editingMessageContent ?? '',
            onCancel: widget.onCancelEdit ?? () {},
          ),
        // 返信プレビュー（返信モード時のみ表示）
        if (isReplyMode)
          ReplyPreview(
            messageContent: widget.replyToContent!,
            onCancel: widget.onCancelReply ?? () {},
          ),
        if (_showSuggestions)
          TagSuggestionList(
            query: _currentTagQuery,
            onSelect: _addTag,
            textFieldFocusNode: _focusNode,
          ),
        // タグ選択後のヒント表示（常に同じ高さを維持）
        if (!_showSuggestions)
          Container(
            width: double.infinity,
            height: 36, // 固定高さでレイアウト変化を防ぐ
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Text(
              _selectedTagHint != null ? '例: $_selectedTagHint' : '',
              style: TextStyle(
                color: colors.textHint,
                fontSize: 12,
              ),
            ),
          ),
        // 画像プレビュー
        if (_selectedImages.isNotEmpty)
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedImages[index],
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 20,
                          height: 20,
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
                );
              },
            ),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Stack(
                          children: [
                            IconButton(
                              icon: Icon(LucideIcons.camera,
                                  color: colors.textHint, size: 20),
                              onPressed: _isUploading ? null : _pickImage,
                            ),
                            if (_selectedImages.isNotEmpty)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary600,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${_selectedImages.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: 4,
                            minLines: 1,
                            enabled: !_isUploading,
                            decoration: InputDecoration(
                              hintText: 'メッセージ... (#でタグ入力)',
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 10),
                              hintStyle: TextStyle(
                                  color: colors.textHint, fontSize: 14),
                            ),
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _canSend() ? _handleSend : null,
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _canSend() ? AppColors.primary600 : colors.border,
                      shape: BoxShape.circle,
                      boxShadow: _canSend()
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.primary600.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            isEditMode ? LucideIcons.check : LucideIcons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================
// EditPreview Widget
// ============================================

class _EditPreview extends StatelessWidget {
  final String messageContent;
  final VoidCallback onCancel;

  const _EditPreview({
    required this.messageContent,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.amber100,
        border: Border(
          top: BorderSide(color: AppColors.amber300),
          bottom: BorderSide(color: AppColors.amber300),
        ),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.pencil, size: 16, color: AppColors.amber800),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '編集中',
                  style: TextStyle(
                    color: AppColors.amber800,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  messageContent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.amber800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon:
                const Icon(LucideIcons.x, size: 16, color: AppColors.amber700),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'ChatInput - Normal Mode')
Widget previewChatInputNormal() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ChatInput(
              onSend: (text, images, replyTo) async {},
              userId: 'user-123',
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'ChatInput - Reply Mode')
Widget previewChatInputReply() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ChatInput(
              onSend: (text, images, replyTo) async {},
              userId: 'user-123',
              replyToMessageId: 'msg-123',
              replyToContent: '昨日のトレーニングはどうでしたか?',
              onCancelReply: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'ChatInput - Edit Mode')
Widget previewChatInputEdit() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            ChatInput(
              onSend: (text, images, replyTo) async {},
              userId: 'user-123',
              editingMessageId: 'msg-456',
              editingMessageContent: '今日のトレーニングは30分のランニングと腹筋100回をやりました！',
              onCancelEdit: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'EditPreview - Short Message')
Widget previewEditPreviewShort() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _EditPreview(
              messageContent: 'こんにちは！',
              onCancel: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'EditPreview - Long Message')
Widget previewEditPreviewLong() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _EditPreview(
              messageContent:
                  'これは非常に長いメッセージで、1行に収まりきらないため省略されるはずです。テストメッセージです。',
              onCancel: () {},
            ),
          ],
        ),
      ),
    ),
  );
}
