import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/trainer_confirm_screen.dart';
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
          const SnackBar(
            content: Text('無効な招待コードです。'),
            backgroundColor: AppColors.rose800,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // トレーナー情報を取得
    final registrationNotifier = ref.read(registrationNotifierProvider.notifier);
    final found = await registrationNotifier.fetchTrainerInfo(trainerId);

    if (!mounted) return;

    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('トレーナーが見つかりませんでした。招待コードを確認してください。'),
          backgroundColor: AppColors.rose800,
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate800,
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
                              color: AppColors.primary50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              LucideIcons.keyRound,
                              size: 40,
                              color: AppColors.primary600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 説明テキスト
                        const Text(
                          '招待コードを入力',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slate800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'トレーナーから受け取った\n招待コードを入力してください',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.slate500,
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
                          decoration: InputDecoration(
                            labelText: '招待コード',
                            hintText: 'コードを入力',
                            prefixIcon: const Icon(LucideIcons.hash),
                            filled: true,
                            fillColor: AppColors.slate50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.slate200,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary500,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.rose800,
                              ),
                            ),
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
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submitCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: AppColors.slate300,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '確認する',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),

                        const Spacer(),

                        // ヘルプテキスト
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.slate100),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                LucideIcons.helpCircle,
                                size: 20,
                                color: AppColors.slate400,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '招待コードがわからない場合は、\nトレーナーにお問い合わせください。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.slate500,
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
