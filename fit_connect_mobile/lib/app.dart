import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/main_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/welcome_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/registration_complete_screen.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIT-CONNECT',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingScreen();
          }
          final session = snapshot.data?.session;
          if (session != null) {
            // ログイン済み: クライアントデータの確認
            return const _AuthLoadingScreen();
          } else {
            // 未ログイン: オンボーディング画面へ
            return const WelcomeScreen();
          }
        },
      ),
    );
  }
}

/// 初期ローディング画面
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary600,
        ),
      ),
    );
  }
}

/// 認証後のデータ取得を待つローディング画面
class _AuthLoadingScreen extends ConsumerWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(currentClientProvider);
    final registrationState = ref.watch(registrationNotifierProvider);

    return clientAsync.when(
      data: (client) {
        if (client != null) {
          // クライアントデータあり → MainScreenへ
          return const MainScreen();
        } else if (registrationState.isRegistrationComplete) {
          // 登録完了 → 登録完了画面へ
          return const RegistrationCompleteScreen();
        } else if (registrationState.hasTrainer) {
          // クライアントデータなし＆登録フロー中 → プロフィール設定画面へ
          return const ProfileSetupScreen();
        } else {
          // クライアントデータなし＆登録フローなし → オンボーディングへ
          // （認証済みだがクライアント登録がない状態）
          return const WelcomeScreen();
        }
      },
      loading: () {
        // ローディング中
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.primary600,
                ),
                const SizedBox(height: 16),
                Text(
                  '読み込み中...',
                  style: TextStyle(
                    color: AppColors.slate500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      error: (error, stack) {
        // エラー時: 登録フロー中ならプロフィール設定画面、そうでなければオンボーディング
        if (registrationState.hasTrainer) {
          return const ProfileSetupScreen();
        }
        return const WelcomeScreen();
      },
    );
  }
}
