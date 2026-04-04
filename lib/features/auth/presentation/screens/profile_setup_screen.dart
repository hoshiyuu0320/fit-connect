import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

/// プロフィール設定画面
///
/// 新規登録フローで、クライアントが自分の名前を入力する画面。
/// 入力した名前は registrationNotifier に保持され、登録完了処理で使用される。
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String _selectedGender = 'other'; // デフォルト: その他
  File? _selectedImage;
  String? _googleAvatarUrl; // Google認証時のアバターURL
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _prefillFromGoogleMetadata();
  }

  /// Google認証時のuserMetadataから名前・画像URLをプリフィル
  void _prefillFromGoogleMetadata() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final metadata = user.userMetadata;
    if (metadata == null) return;

    // 名前のプリフィル
    final fullName = metadata['full_name'] as String?;
    if (fullName != null && fullName.isNotEmpty) {
      _nameController.text = fullName;
    }

    // Google アバターURLの取得
    final avatarUrl = metadata['avatar_url'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      _googleAvatarUrl = avatarUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final file = await StorageService.showImagePickerDialog(context);
    if (file != null) {
      setState(() {
        _selectedImage = file;
      });
    }
  }

  Future<void> _handleSubmit() async {
    // フォームバリデーション
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final registrationNotifier =
          ref.read(registrationNotifierProvider.notifier);

      // プロフィール画像をセット（選択されている場合）
      if (_selectedImage != null) {
        registrationNotifier.setProfileImage(_selectedImage);
      }

      // Google アバターURLを保存（ユーザーが画像を選択していない場合のみ）
      if (_selectedImage == null && _googleAvatarUrl != null) {
        registrationNotifier.setGoogleAvatarUrl(_googleAvatarUrl);
      }

      // クライアント名を状態にセット
      registrationNotifier.setClientName(_nameController.text.trim());

      // 性別をセット
      registrationNotifier.setClientGender(_selectedGender);

      // 年齢をセット（入力されている場合のみ）
      final ageText = _ageController.text.trim();
      if (ageText.isNotEmpty) {
        final age = int.tryParse(ageText);
        if (age != null) {
          registrationNotifier.setClientAge(age);
        }
      }

      // 登録完了処理を実行
      await registrationNotifier.completeRegistration();

      // 登録完了フラグをセット
      // これにより、app.dartの_AuthLoadingScreenがRegistrationCompleteScreenを表示する
      registrationNotifier.setRegistrationComplete(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: ${e.toString()}'),
            backgroundColor: AppColors.rose800,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildGenderOption(String value, String label, IconData icon) {
    final isSelected = _selectedGender == value;
    final colors = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedGender = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary50 : colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary600 : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.primary600 : colors.textHint,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color:
                      isSelected ? AppColors.primary600 : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: IntrinsicHeight(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(),

                          // プロフィール画像選択
                          Center(
                            child: GestureDetector(
                              onTap: _pickProfileImage,
                              child: Stack(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary50,
                                      shape: BoxShape.circle,
                                      image: _selectedImage != null
                                          ? DecorationImage(
                                              image: FileImage(_selectedImage!),
                                              fit: BoxFit.cover,
                                            )
                                          : _googleAvatarUrl != null
                                              ? DecorationImage(
                                                  image:
                                                      CachedNetworkImageProvider(
                                                          _googleAvatarUrl!),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                    ),
                                    child: _selectedImage == null &&
                                            _googleAvatarUrl == null
                                        ? const Icon(
                                            LucideIcons.user,
                                            size: 40,
                                            color: AppColors.primary600,
                                          )
                                        : null,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary600,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: colors.surface, width: 2),
                                      ),
                                      child: const Icon(
                                        LucideIcons.camera,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'タップして写真を設定',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary600,
                            ),
                          ),
                          Text(
                            'あとで設定できます',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textHint,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // タイトル
                          Text(
                            'プロフィール設定',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // 説明文
                          Text(
                            'あなたの基本情報を入力してください',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // 名前入力フィールド
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surfaceDim,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: TextFormField(
                              controller: _nameController,
                              style: TextStyle(color: colors.textPrimary),
                              decoration: InputDecoration(
                                labelText: 'お名前',
                                labelStyle:
                                    TextStyle(color: colors.textSecondary),
                                hintText: '例: 山田 太郎',
                                hintStyle: TextStyle(color: colors.textHint),
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  LucideIcons.user,
                                  color: colors.textHint,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return '名前を入力してください';
                                }
                                if (value.trim().length > 50) {
                                  return '名前は50文字以内で入力してください';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _handleSubmit(),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 性別セクション
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding:
                                  const EdgeInsets.only(left: 4, bottom: 8),
                              child: Text(
                                '性別',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _buildGenderOption(
                                  'male', '男性', LucideIcons.user),
                              const SizedBox(width: 8),
                              _buildGenderOption(
                                  'female', '女性', LucideIcons.user),
                              const SizedBox(width: 8),
                              _buildGenderOption(
                                  'other', 'その他', LucideIcons.users),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // 年齢入力フィールド
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surfaceDim,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: TextFormField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              style: TextStyle(color: colors.textPrimary),
                              decoration: InputDecoration(
                                labelText: '年齢',
                                labelStyle:
                                    TextStyle(color: colors.textSecondary),
                                hintText: '例: 30',
                                hintStyle: TextStyle(color: colors.textHint),
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  LucideIcons.cake,
                                  color: colors.textHint,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              validator: (value) {
                                if (value != null && value.trim().isNotEmpty) {
                                  final age = int.tryParse(value.trim());
                                  if (age == null || age < 1 || age > 149) {
                                    return '正しい年齢を入力してください';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 登録完了ボタン
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary600,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppColors.primary200,
                              disabledForegroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    '登録を完了する',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),

                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用の静的フォームWidget。
/// Riverpodプロバイダーを使わずに名前入力画面のUIを再現する。
/// TextEditingControllerを適切に管理するため StatefulWidget を使用。
class _PreviewProfileSetupForm extends StatefulWidget {
  final String nameText;
  final String ageText;
  final String selectedGender;
  final bool isLoading;
  final bool hasImage;
  final String? validationError;

  const _PreviewProfileSetupForm({
    this.nameText = '',
    this.ageText = '',
    this.selectedGender = 'other',
    this.isLoading = false,
    this.hasImage = false,
    this.validationError,
  });

  @override
  State<_PreviewProfileSetupForm> createState() =>
      _PreviewProfileSetupFormState();
}

class _PreviewProfileSetupFormState extends State<_PreviewProfileSetupForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late String _selectedGender;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.nameText);
    _ageController = TextEditingController(text: widget.ageText);
    _selectedGender = widget.selectedGender;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Widget _buildGenderOption(String value, String label, IconData icon) {
    final isSelected = _selectedGender == value;
    final colors = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedGender = value;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary50 : colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary600 : colors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppColors.primary600 : colors.textHint,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color:
                      isSelected ? AppColors.primary600 : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),

        // プロフィール画像選択
        Center(
          child: Stack(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: widget.hasImage
                      ? colors.textHint
                      : AppColors.primary50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.hasImage ? LucideIcons.image : LucideIcons.user,
                  size: 40,
                  color: widget.hasImage ? Colors.white : AppColors.primary600,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary600,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: const Icon(
                    LucideIcons.camera,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'タップして写真を設定',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.primary600,
          ),
        ),
        Text(
          'あとで設定できます',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: colors.textHint,
          ),
        ),
        const SizedBox(height: 16),

        // タイトル
        Text(
          'プロフィール設定',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // 説明文
        Text(
          'あなたの基本情報を入力してください',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 48),

        // 名前入力フィールド
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.validationError != null
                  ? AppColors.rose800
                  : colors.border,
            ),
          ),
          child: TextField(
            controller: _nameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: 'お名前',
              labelStyle: TextStyle(color: colors.textSecondary),
              hintText: '例: 山田 太郎',
              hintStyle: TextStyle(color: colors.textHint),
              border: InputBorder.none,
              prefixIcon: Icon(
                LucideIcons.user,
                color: colors.textHint,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        // バリデーションエラー
        if (widget.validationError != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.validationError!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.rose800,
            ),
          ),
        ],

        const SizedBox(height: 20),

        // 性別セクション
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '性別',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
        Row(
          children: [
            _buildGenderOption('male', '男性', LucideIcons.user),
            const SizedBox(width: 8),
            _buildGenderOption('female', '女性', LucideIcons.user),
            const SizedBox(width: 8),
            _buildGenderOption('other', 'その他', LucideIcons.users),
          ],
        ),

        const SizedBox(height: 20),

        // 年齢入力フィールド
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceDim,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: _ageController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              labelText: '年齢',
              labelStyle: TextStyle(color: colors.textSecondary),
              hintText: '例: 30',
              hintStyle: TextStyle(color: colors.textHint),
              border: InputBorder.none,
              prefixIcon: Icon(
                LucideIcons.cake,
                color: colors.textHint,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // 登録完了ボタン
        ElevatedButton(
          onPressed: widget.isLoading ? null : () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary600,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary200,
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  '登録を完了する',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),

        const Spacer(),
      ],
    );
  }
}

/// 初期状態（名前入力フィールド空）のプレビュー
@Preview(name: 'ProfileSetupScreen - Empty')
Widget previewProfileSetupScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: _PreviewProfileSetupForm(),
        ),
      ),
    ),
  );
}

/// 名前・性別・年齢入力済みの状態のプレビュー
@Preview(name: 'ProfileSetupScreen - With Name')
Widget previewProfileSetupScreenWithName() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: _PreviewProfileSetupForm(
            nameText: '山田 太郎',
            ageText: '30',
            selectedGender: 'male',
          ),
        ),
      ),
    ),
  );
}

/// ローディング中の状態のプレビュー
@Preview(name: 'ProfileSetupScreen - Loading')
Widget previewProfileSetupScreenLoading() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: _PreviewProfileSetupForm(
            nameText: '山田 太郎',
            ageText: '30',
            selectedGender: 'female',
            isLoading: true,
          ),
        ),
      ),
    ),
  );
}

/// 画像選択済みの状態のプレビュー
@Preview(name: 'ProfileSetupScreen - With Image')
Widget previewProfileSetupScreenWithImage() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: _PreviewProfileSetupForm(
            nameText: '山田 太郎',
            ageText: '30',
            selectedGender: 'male',
            hasImage: true,
          ),
        ),
      ),
    ),
  );
}

/// バリデーションエラー状態のプレビュー
@Preview(name: 'ProfileSetupScreen - Validation Error')
Widget previewProfileSetupScreenValidationError() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      appBar: AppBar(
        elevation: 0,
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: _PreviewProfileSetupForm(
            nameText: '',
            validationError: '名前を入力してください',
          ),
        ),
      ),
    ),
  );
}
