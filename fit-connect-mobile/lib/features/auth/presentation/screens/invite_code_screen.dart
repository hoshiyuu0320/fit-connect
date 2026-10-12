import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/trainer_confirm_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

class InviteCodeScreen extends ConsumerStatefulWidget {
  const InviteCodeScreen({super.key});

  @override
  ConsumerState<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends ConsumerState<InviteCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final code = _codeController.text.trim();

    // 招待コードからtrainer_idを解析
    final trainerId = _parseInviteCode(code);

    if (trainerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無効な招待コードです。')),
        );
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // トレーナー情報を取得
    final registrationNotifier =
        ref.read(registrationNotifierProvider.notifier);
    final found = await registrationNotifier.fetchTrainerInfo(trainerId);

    if (!mounted) return;

    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('トレーナーが見つかりませんでした。招待コードを確認してください。'),
        ),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // トレーナー確認画面へ遷移
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const TrainerConfirmScreen(),
      ),
    );
  }

  /// 招待コードからtrainer_idを解析
  /// 完全なUUID形式または短縮コード（UUIDの先頭部分）を受け付ける
  String? _parseInviteCode(String code) {
    // 完全なUUID形式かチェック
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (uuidRegex.hasMatch(code)) {
      return code;
    }

    // 短縮コード（8文字以上の16進数）として検証
    // 注意: 現時点では完全なUUIDのみ対応
    // 短縮コードのサポートはバックエンドの対応が必要
    final shortCodeRegex = RegExp(
      r'^[0-9a-f]{8,}$',
      caseSensitive: false,
    );
    if (shortCodeRegex.hasMatch(code)) {
      // 短縮コードの場合、一旦コードをそのまま返す
      // 実際のルックアップはバックエンドで行う
      return code;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        title: const Text('招待コード入力'),
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 32),

                          // アイコン
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.card),
                              ),
                              child: Icon(
                                LucideIcons.keyRound,
                                size: 40,
                                color: colors.accent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // 説明テキスト
                          Text(
                            '招待コードを入力',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'トレーナーから受け取った\n招待コードを入力してください',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textSecondary,
                              height: 1.6,
                            ),
                          ),

                          const SizedBox(height: 48),

                          // 入力フィールド
                          TextFormField(
                            controller: _codeController,
                            enabled: !_isLoading,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            style: const TextStyle(
                              fontSize: 18,
                              letterSpacing: 2,
                            ),
                            // 枠（通常 separator・フォーカス accent・エラー error）はテーマの
                            // InputDecoration。面だけ surface にする
                            decoration: InputDecoration(
                              labelText: '招待コード',
                              hintText: 'コードを入力',
                              prefixIcon: const Icon(LucideIcons.hash),
                              filled: true,
                              fillColor: colors.surface,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return '招待コードを入力してください';
                              }
                              if (value.trim().length < 8) {
                                return '招待コードは8文字以上です';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _submitCode(),
                          ),

                          const SizedBox(height: 24),

                          // 送信ボタン
                          // 色・形（actionFill・角丸 24・最小高さ 48）はテーマの ElevatedButton
                          // （IntrinsicHeight の中では FcButton.block を置けない）。
                          // 送信中は無効でも塗りのまま（actionFill + onAction）スピナーを見せる
                          ElevatedButton(
                            onPressed: _isLoading ? null : _submitCode,
                            style: _isLoading
                                ? ElevatedButton.styleFrom(
                                    disabledBackgroundColor: colors.actionFill,
                                    disabledForegroundColor: colors.onAction,
                                  )
                                : null,
                            child: _isLoading
                                ? SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onAction,
                                    ),
                                  )
                                : const Text('確認する'),
                          ),

                          const Spacer(),

                          // ヘルプテキスト
                          FcCard(
                            paddingOverride:
                                const EdgeInsets.all(AppSpacing.lg),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.helpCircle,
                                  size: 20,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '招待コードがわからない場合は、\nトレーナーにお問い合わせください。',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
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
