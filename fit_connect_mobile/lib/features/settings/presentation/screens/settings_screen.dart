import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/data/client_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(currentClientProvider);
    final trainerAsync = ref.watch(trainerProfileProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.slate800,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー情報セクション
              _buildUserInfoSection(context, ref, clientAsync, trainerAsync),

              const SizedBox(height: 16),

              // 設定項目セクション
              _buildSettingsSection(context, ref),

              const SizedBox(height: 100), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue clientAsync,
    AsyncValue trainerAsync,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: clientAsync.when(
        data: (client) {
          if (client == null) {
            return const Center(
              child: Text(
                'ユーザー情報を読み込めませんでした',
                style: TextStyle(color: AppColors.slate500),
              ),
            );
          }

          return Column(
            children: [
              // プロフィール画像（タップで変更可能）
              GestureDetector(
                onTap: () => _showProfileImagePicker(
                  context,
                  ref,
                  client.clientId,
                ),
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary100,
                      backgroundImage: client.profileImageUrl != null
                          ? NetworkImage(client.profileImageUrl!)
                          : null,
                      child: client.profileImageUrl == null
                          ? const Icon(
                              LucideIcons.user,
                              size: 40,
                              color: AppColors.primary500,
                            )
                          : null,
                    ),
                    // カメラアイコンオーバーレイ
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white,
                            width: 2,
                          ),
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

              const SizedBox(height: 16),

              // クライアント名
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    client.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _showEditNameDialog(
                      context,
                      ref,
                      client.clientId,
                      client.name,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        LucideIcons.pencil,
                        size: 16,
                        color: AppColors.slate400,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // メールアドレス
              if (client.email != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.mail,
                      size: 14,
                      color: AppColors.slate400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      client.email!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.slate600,
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // トレーナー情報
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: trainerAsync.when(
                  data: (trainer) {
                    if (trainer == null) {
                      return const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.userCheck,
                            size: 16,
                            color: AppColors.primary500,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'トレーナー: 未設定',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.userCheck,
                          size: 16,
                          color: AppColors.primary500,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'トレーナー: ${trainer.name}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.primary700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary500,
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '読み込み中...',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primary700,
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.alertCircle,
                        size: 16,
                        color: AppColors.rose800,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'トレーナー情報の読み込みに失敗',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.rose800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (error, _) => Center(
          child: Column(
            children: [
              const Icon(
                LucideIcons.alertCircle,
                size: 40,
                color: AppColors.rose800,
              ),
              const SizedBox(height: 8),
              Text(
                'エラー: $error',
                style: const TextStyle(color: AppColors.rose800),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // グループヘッダー
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'アカウント',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.slate500,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // ログアウトボタン
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rose100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.logOut,
                size: 20,
                color: AppColors.rose800,
              ),
            ),
            title: const Text(
              'ログアウト',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.rose800,
              ),
            ),
            trailing: const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppColors.slate400,
            ),
            onTap: () => _showLogoutDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(
    BuildContext context,
    WidgetRef ref,
    String clientId,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('名前を編集'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名前',
              hintText: '名前を入力してください',
            ),
            maxLength: 50,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '名前を入力してください';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: AppColors.slate600),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final newName = controller.text.trim();
              Navigator.of(dialogContext).pop();

              try {
                await ref.read(clientRepositoryProvider).updateClientName(
                  clientId,
                  newName,
                );

                // Providerをinvalidateして再取得
                ref.invalidate(currentClientProvider);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('名前を更新しました'),
                      backgroundColor: AppColors.emerald600,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('更新に失敗しました: $e'),
                      backgroundColor: AppColors.rose800,
                    ),
                  );
                }
              }
            },
            child: const Text(
              '保存',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileImagePicker(
    BuildContext context,
    WidgetRef ref,
    String clientId,
  ) async {
    // 画像選択ダイアログを表示
    final file = await StorageService.showImagePickerDialog(context);
    if (file == null) return;

    // ローディング表示
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // 画像をアップロード
      final imageUrl =
          await StorageService.uploadProfileImage(file, clientId);

      if (imageUrl == null) {
        throw Exception('画像のアップロードに失敗しました');
      }

      // DBを更新
      await ref.read(clientRepositoryProvider).updateProfileImageUrl(
        clientId,
        imageUrl,
      );

      // Providerをinvalidateして再取得
      ref.invalidate(currentClientProvider);

      // ローディングを閉じる
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プロフィール画像を更新しました'),
            backgroundColor: AppColors.emerald600,
          ),
        );
      }
    } catch (e) {
      // ローディングを閉じる
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('画像の更新に失敗しました: $e'),
            backgroundColor: AppColors.rose800,
          ),
        );
      }
    }
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'キャンセル',
              style: TextStyle(color: AppColors.slate600),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop(); // ダイアログを閉じる
              try {
                await ref.read(authNotifierProvider.notifier).signOut();
                // ルーティングはapp.dartのStreamBuilderが自動処理
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ログアウトに失敗しました: $e'),
                      backgroundColor: AppColors.rose800,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'ログアウト',
              style: TextStyle(
                color: AppColors.rose800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'SettingsScreen - Static Preview')
Widget previewSettingsScreenStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.slate800,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewUserInfoSection(),
              const SizedBox(height: 16),
              _PreviewSettingsSection(),
            ],
          ),
        ),
      ),
    ),
  );
}

// Preview helper widgets
class _PreviewUserInfoSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        children: [
          // プロフィール画像（カメラアイコンオーバーレイ付き）
          Stack(
            children: [
              const CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.primary100,
                child: Icon(
                  LucideIcons.user,
                  size: 40,
                  color: AppColors.primary500,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
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

          const SizedBox(height: 16),

          // クライアント名
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '山田 太郎',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.slate800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(
                  LucideIcons.pencil,
                  size: 16,
                  color: AppColors.slate400,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // メールアドレス
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.mail,
                size: 14,
                color: AppColors.slate400,
              ),
              SizedBox(width: 4),
              Text(
                'yamada@example.com',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.slate600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // トレーナー情報
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.userCheck,
                  size: 16,
                  color: AppColors.primary500,
                ),
                SizedBox(width: 8),
                Text(
                  'トレーナー: 鈴木コーチ',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primary700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // グループヘッダー
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'アカウント',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.slate500,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // ログアウトボタン
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rose100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.logOut,
                size: 20,
                color: AppColors.rose800,
              ),
            ),
            title: const Text(
              'ログアウト',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.rose800,
              ),
            ),
            trailing: const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppColors.slate400,
            ),
            onTap: () {
              // プレビューでは何もしない
            },
          ),
        ],
      ),
    );
  }
}
