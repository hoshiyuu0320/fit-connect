import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/auth/data/auth_repository.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 認証イベントを受けて LoginScreen を閉じる（ルートまで pop する）べきか判定する。
///
/// gotrue の `onAuthStateChange` は BehaviorSubject 仕様のため、購読開始時に
/// 直近のイベント（残存セッションによる initialSession / tokenRefreshed 等）を
/// 再送する。これに反応すると「セッション残存 + clients 行なし」の状態で
/// LoginScreen を push した瞬間に自動 pop してしまうため、
/// 新規サインイン（signedIn）イベントのみを閉じる対象とする。
bool shouldPopOnAuthEvent(AuthChangeEvent event, Session? session) {
  return event == AuthChangeEvent.signedIn && session != null;
}

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
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
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
      if (shouldPopOnAuthEvent(data.event, data.session) && mounted) {
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

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final response = await _authRepository.signInWithGoogle();
      if (response == null) {
        // ユーザーがキャンセル — 何もしない
        return;
      }
      // 認証成功 → _authSubscription が検知してナビゲーション
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google認証エラー: ${e.toString()}'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _handleAppleLogin() async {
    setState(() {
      _isAppleLoading = true;
    });

    try {
      final response = await _authRepository.signInWithApple();
      if (response == null) {
        // ユーザーがキャンセル — 何もしない
        return;
      }
      // 認証成功 → _authSubscription が検知してナビゲーション
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apple認証エラー: ${e.toString()}'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAppleLoading = false;
        });
      }
    }
  }

  /// いずれかの認証処理が実行中か
  bool get _isAnyLoading => _isLoading || _isGoogleLoading || _isAppleLoading;

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
                            onPressed: _isAnyLoading ? null : _handleLogin,
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
                          const SizedBox(height: 24),

                          // 区切り線「または」
                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: colors.border),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'または',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textHint,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: colors.border),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Appleでサインインボタン（iOSのみ、App Store Guideline 4.8対応）
                          // Apple HIG準拠: 他のソーシャルログインボタンより上に配置
                          if (Platform.isIOS) ...[
                            _buildAppleSignInButton(context),
                            const SizedBox(height: 12),
                          ],

                          // Googleでログインボタン
                          OutlinedButton(
                            onPressed:
                                _isAnyLoading ? null : _handleGoogleLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.border),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isGoogleLoading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: colors.textSecondary,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/images/google_logo.svg',
                                        width: 20,
                                        height: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Googleでログイン',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ],
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

  /// Appleデザインガイドライン準拠のサインインボタン。
  /// 高さ（padding vertical 16）・角丸（12）は既存のGoogleボタンと揃える。
  /// ライトテーマでは黒ボタン、ダークテーマでは白ボタン（Appleの推奨スタイル）。
  Widget _buildAppleSignInButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.white : Colors.black;
    final foregroundColor = isDark ? Colors.black : Colors.white;

    return ElevatedButton(
      onPressed: _isAnyLoading ? null : _handleAppleLogin,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      child: _isAppleLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: foregroundColor,
                strokeWidth: 2,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.apple,
                  size: 22,
                  color: foregroundColor,
                ),
                const SizedBox(width: 12),
                Text(
                  'Appleでサインイン',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: foregroundColor,
                  ),
                ),
              ],
            ),
    );
  }
}
