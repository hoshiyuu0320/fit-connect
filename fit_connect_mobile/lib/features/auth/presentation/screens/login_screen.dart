import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/auth/data/auth_repository.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  /// 登録フローから来た場合はtrue
  final bool isRegistration;

  const LoginScreen({
    super.key,
    this.isRegistration = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isEmailSent = false;
  final _authRepository = AuthRepository();

  // 認証状態監視用
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    // 認証状態を監視
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.session != null && mounted) {
        // 認証成功 → スタックをクリアしてルートに戻る
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _authRepository.signInWithEmail(email);
      setState(() {
        _isEmailSent = true;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('認証リンクをメールで送信しました'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: ${e.toString()}'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: widget.isRegistration
          ? AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              foregroundColor: colors.textPrimary,
              elevation: 0,
            )
          : null,
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),

                        // Logo / Icon
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppColors.primary50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              widget.isRegistration
                                  ? LucideIcons.mail
                                  : LucideIcons.activity,
                              size: 40,
                              color: AppColors.primary600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        Text(
                          widget.isRegistration ? 'メールアドレス認証' : 'FIT-CONNECT',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.isRegistration
                              ? 'アカウント登録のため\nメールアドレスを入力してください'
                              : 'トレーナーとつながって\n目標を達成しよう',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textSecondary,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 48),

                        if (_isEmailSent) ...[
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.emerald50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.emerald100),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  LucideIcons.mailCheck,
                                  size: 48,
                                  color: AppColors.success,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'メールを確認してください',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '認証リンクを送信しました:\n${_emailController.text}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'メール内のリンクをタップして\n認証を完了してください',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextButton(
                            onPressed: () =>
                                setState(() => _isEmailSent = false),
                            child: const Text('別のメールアドレスを使う'),
                          ),
                        ] else ...[
                          // Email Input
                          Container(
                            decoration: BoxDecoration(
                              color: colors.surfaceDim,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.border),
                            ),
                            child: TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(color: colors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'メールアドレスを入力',
                                hintStyle: TextStyle(color: colors.textHint),
                                border: InputBorder.none,
                                prefixIcon: Icon(
                                  LucideIcons.mail,
                                  color: colors.textHint,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                              ),
                              onSubmitted: (_) => _handleLogin(),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Login Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary600,
                              foregroundColor: Colors.white,
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
                                : Text(
                                    widget.isRegistration
                                        ? '認証メールを送信'
                                        : 'ログインリンクを送信',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ],

                        const Spacer(),

                        // Footer
                        Text(
                          widget.isRegistration
                              ? 'メールが届かない場合は\n迷惑メールフォルダをご確認ください'
                              : '続行することで利用規約とプライバシーポリシーに同意したものとみなされます',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textHint,
                          ),
                        ),
                      ],
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
