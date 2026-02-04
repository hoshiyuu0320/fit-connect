import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';

/// プロフィール設定画面
///
/// 新規登録フローで、クライアントが自分の名前を入力する画面。
/// 入力した名前は registrationNotifier に保持され、登録完了処理で使用される。
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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

      // クライアント名を状態にセット
      registrationNotifier.setClientName(_nameController.text.trim());

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
        elevation: 0,
      ),
      body: SafeArea(
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

                        // アイコン
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              LucideIcons.user,
                              size: 40,
                              color: AppColors.primary600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // タイトル
                        const Text(
                          'プロフィール設定',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate800,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 説明文
                        const Text(
                          'トレーナーに表示される名前を入力してください',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.slate500,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 48),

                        // 名前入力フィールド
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: TextFormField(
                            controller: _nameController,
                            style: const TextStyle(color: AppColors.slate800),
                            decoration: const InputDecoration(
                              labelText: 'お名前',
                              labelStyle: TextStyle(color: AppColors.slate500),
                              hintText: '例: 山田 太郎',
                              hintStyle: TextStyle(color: AppColors.slate400),
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                LucideIcons.user,
                                color: AppColors.slate400,
                              ),
                              contentPadding: EdgeInsets.symmetric(
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
                        const SizedBox(height: 32),

                        // 登録完了ボタン
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary600,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.primary200,
                            disabledForegroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
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
  final bool isLoading;
  final String? validationError;

  const _PreviewProfileSetupForm({
    this.nameText = '',
    this.isLoading = false,
    this.validationError,
  });

  @override
  State<_PreviewProfileSetupForm> createState() =>
      _PreviewProfileSetupFormState();
}

class _PreviewProfileSetupFormState extends State<_PreviewProfileSetupForm> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.nameText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),

        // アイコン
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              LucideIcons.user,
              size: 40,
              color: AppColors.primary600,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // タイトル
        const Text(
          'プロフィール設定',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.slate800,
          ),
        ),
        const SizedBox(height: 8),

        // 説明文
        const Text(
          'トレーナーに表示される名前を入力してください',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.slate500,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 48),

        // 名前入力フィールド
        Container(
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.validationError != null
                  ? AppColors.rose800
                  : AppColors.slate200,
            ),
          ),
          child: TextField(
            controller: _controller,
            style: const TextStyle(color: AppColors.slate800),
            decoration: const InputDecoration(
              labelText: 'お名前',
              labelStyle: TextStyle(color: AppColors.slate500),
              hintText: '例: 山田 太郎',
              hintStyle: TextStyle(color: AppColors.slate400),
              border: InputBorder.none,
              prefixIcon: Icon(
                LucideIcons.user,
                color: AppColors.slate400,
              ),
              contentPadding: EdgeInsets.symmetric(
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: const _PreviewProfileSetupForm(),
        ),
      ),
    ),
  );
}

/// 名前入力済みの状態のプレビュー
@Preview(name: 'ProfileSetupScreen - With Name')
Widget previewProfileSetupScreenWithName() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: const _PreviewProfileSetupForm(
            nameText: '山田 太郎',
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: const _PreviewProfileSetupForm(
            nameText: '山田 太郎',
            isLoading: true,
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: const _PreviewProfileSetupForm(
            nameText: '',
            validationError: '名前を入力してください',
          ),
        ),
      ),
    ),
  );
}
