import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/login_screen.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

class TrainerConfirmScreen extends ConsumerWidget {
  const TrainerConfirmScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final registrationState = ref.watch(registrationNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // タイトル
              Text(
                '担当トレーナー',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              // トレーナーアバター
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  // 影は付けない（面の色だけで区別する）
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceSecondary,
                  ),
                  child: ClipOval(
                    child: registrationState.trainerImageUrl != null
                        ? StorageImage(
                            value: registrationState.trainerImageUrl,
                            bucket: StorageBuckets.profileImages,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            placeholder: const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            errorWidget: Icon(
                              LucideIcons.user,
                              size: 48,
                              color: colors.textHint,
                            ),
                          )
                        : Icon(
                            LucideIcons.user,
                            size: 48,
                            color: colors.textHint,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // トレーナー名
              Text(
                registrationState.trainerName ?? '名前未設定',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'パーソナルトレーナー',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),

              const SizedBox(height: 48),

              // 確認メッセージ（カードは surface。淡い青緑の面は使わない）
              FcCard(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.userCheck,
                      size: 32,
                      color: colors.accent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'このトレーナーの元で\nトレーニングを始めますか？',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.textPrimary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 次へボタン
              FcButton.block(
                label: '次へ進む',
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(
                        isRegistration: true,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // 戻るボタン
              TextButton(
                onPressed: () {
                  // 登録状態をクリアして戻る
                  ref.read(registrationNotifierProvider.notifier).clear();
                  Navigator.of(context).pop();
                },
                child: Text(
                  '別のトレーナーを選ぶ',
                  style: TextStyle(
                    color: colors.textSecondary,
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
