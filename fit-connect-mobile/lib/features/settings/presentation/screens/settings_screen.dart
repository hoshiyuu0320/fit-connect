import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/core/providers/theme_provider.dart';
import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';
import 'package:fit_connect_mobile/features/auth/data/client_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/consent/legal_links.dart';
import 'package:fit_connect_mobile/features/settings/providers/notification_preferences_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(currentClientProvider);
    final trainerAsync = ref.watch(trainerProfileProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: colors.surface,
        elevation: 0,
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー情報セクション
              _buildUserInfoSection(context, ref, clientAsync, trainerAsync),

              const SizedBox(height: 16),

              // 外観セクション
              _buildAppearanceSection(context, ref),

              const SizedBox(height: 16),

              // 通知設定セクション
              _buildNotificationSection(context, ref),

              const SizedBox(height: 16),

              // ヘルスケア連携セクション
              _buildHealthSection(context, ref),

              const SizedBox(height: 16),

              // 法的情報セクション
              _buildLegalSection(context),

              const SizedBox(height: 16),

              // 設定項目セクション
              _buildSettingsSection(context, ref),

              const SizedBox(height: 16),

              // アプリ情報セクション
              _buildAppInfoSection(context, ref),

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
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: clientAsync.when(
        data: (client) {
          if (client == null) {
            return Center(
              child: Text(
                'ユーザー情報を読み込めませんでした',
                style: TextStyle(color: colors.textSecondary),
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
                      child: client.profileImageUrl != null
                          ? ClipOval(
                              child: StorageImage(
                                value: client.profileImageUrl,
                                bucket: StorageBuckets.clientAvatars,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorWidget: const Icon(
                                  LucideIcons.user,
                                  size: 40,
                                  color: AppColors.primary500,
                                ),
                              ),
                            )
                          : const Icon(
                              LucideIcons.user,
                              size: 40,
                              color: AppColors.primary500,
                            ),
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
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
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
                      child: Icon(
                        LucideIcons.pencil,
                        size: 16,
                        color: colors.textHint,
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
                    Icon(
                      LucideIcons.mail,
                      size: 14,
                      color: colors.textHint,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      client.email!,
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textSecondary,
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

  Widget _buildAppearanceSection(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    final colors = AppColors.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '外観',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(LucideIcons.sun),
                  label: Text('ライト'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(LucideIcons.moon),
                  label: Text('ダーク'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(LucideIcons.smartphone),
                  label: Text('システム'),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (Set<ThemeMode> selected) {
                ref
                    .read(themeModeNotifierProvider.notifier)
                    .setThemeMode(selected.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '通知設定',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          prefsAsync.when(
            data: (prefs) => Column(
              children: [
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: LucideIcons.messageCircle,
                  title: 'メッセージ受信',
                  kind: NotificationKind.message,
                  value: prefs.messageEnabled,
                ),
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: LucideIcons.trophy,
                  title: '目標達成のお知らせ',
                  kind: NotificationKind.goalAchievement,
                  value: prefs.goalAchievementEnabled,
                ),
                const SizedBox(height: 8),
              ],
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                '通知設定を読み込めませんでした',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationToggle(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required NotificationKind kind,
    required bool value,
  }) {
    final colors = AppColors.of(context);

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: AppColors.primary500,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      value: value,
      onChanged: (newValue) async {
        try {
          await ref
              .read(notificationPreferencesProvider.notifier)
              .setEnabled(kind, newValue);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('通知設定の更新に失敗しました'),
                backgroundColor: AppColors.rose800,
              ),
            );
          }
        }
      },
    );
  }

  Widget _buildHealthSection(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final healthAvailable = ref.watch(healthAvailableProvider);

    return healthAvailable.when(
      data: (available) {
        if (!available) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'ヘルスケア',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    LucideIcons.heartPulse,
                    size: 20,
                    color: AppColors.primary500,
                  ),
                ),
                title: Text(
                  'ヘルスケア連携',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                trailing: Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: colors.textHint,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HealthSettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLegalSection(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // グループヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '法的情報',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // 利用規約
          _buildLegalLinkTile(
            context,
            icon: LucideIcons.fileText,
            title: '利用規約',
            url: LegalLinks.termsUrl,
          ),

          // プライバシーポリシー
          _buildLegalLinkTile(
            context,
            icon: LucideIcons.shieldCheck,
            title: 'プライバシーポリシー',
            url: LegalLinks.privacyUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildLegalLinkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String url,
  }) {
    final colors = AppColors.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: AppColors.primary500,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      trailing: Icon(
        LucideIcons.externalLink,
        size: 20,
        color: colors.textHint,
      ),
      onTap: () => _openLegalUrl(context, url),
    );
  }

  /// 法務ページを外部ブラウザで開く
  Future<void> _openLegalUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('リンクを開けませんでした'),
          backgroundColor: AppColors.rose800,
        ),
      );
    }
  }

  Widget _buildSettingsSection(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // グループヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'アカウント',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
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
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: colors.textHint,
            ),
            onTap: () => _showLogoutDialog(context, ref),
          ),

          // アカウント削除ボタン（App Store Guideline 5.1.1(v) 対応）
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rose100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.userX,
                size: 20,
                color: AppColors.rose800,
              ),
            ),
            title: const Text(
              'アカウントを削除',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.rose800,
              ),
            ),
            trailing: Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: colors.textHint,
            ),
            onTap: () => _showDeleteAccountDialog(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfoSection(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final packageInfo = ref.watch(packageInfoProvider);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // グループヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'アプリ情報',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // アプリバージョン（package_info_plus 由来。取得中・失敗時は「-」）
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.info,
                size: 20,
                color: AppColors.primary500,
              ),
            ),
            title: Text(
              'バージョン',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            trailing: Text(
              packageInfo.valueOrNull?.version ?? '-',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
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
            child: Text(
              'キャンセル',
              style:
                  TextStyle(color: AppColors.of(dialogContext).textSecondary),
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
      // 画像をアップロード（戻り値はバケット相対パス）
      final imagePath = await StorageService.uploadProfileImage(file, clientId);

      if (imagePath == null) {
        throw Exception('画像のアップロードに失敗しました');
      }

      // DBを更新（profile_image_url にはパスを保存する）
      await ref.read(clientRepositoryProvider).updateProfileImageUrl(
            clientId,
            imagePath,
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('ログアウト'),
        content: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'キャンセル',
              style:
                  TextStyle(color: AppColors.of(dialogContext).textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop(); // ダイアログを閉じる
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

  /// アカウント削除・確認ダイアログ（1段階目: 削除されるデータの説明）
  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('アカウントを削除'),
        content: const _DeleteAccountWarningContent(),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'キャンセル',
              style:
                  TextStyle(color: AppColors.of(dialogContext).textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _showDeleteAccountConfirmDialog(context, ref);
            },
            child: const Text(
              '続ける',
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

  /// アカウント削除・確認ダイアログ（2段階目: 最終確認 + 実行）
  void _showDeleteAccountConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isDeleting = false;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('本当に削除しますか？'),
            content: const Text('この操作は取り消せません。すべてのデータが完全に削除されます。'),
            actions: [
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'キャンセル',
                  style: TextStyle(
                      color: AppColors.of(dialogContext).textSecondary),
                ),
              ),
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        try {
                          await ref
                              .read(authNotifierProvider.notifier)
                              .deleteAccount();
                          // 成功: deleteAccount 内で signOut 済み。
                          // ルーティングはapp.dartのStreamBuilderが自動処理
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (e) {
                          // 失敗: ダイアログを閉じて SnackBar 表示（再試行可能）
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('アカウントの削除に失敗しました: $e'),
                                backgroundColor: AppColors.rose800,
                              ),
                            );
                          }
                        }
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.rose800,
                          ),
                        ),
                      )
                    : const Text(
                        '削除する',
                        style: TextStyle(
                          color: AppColors.rose800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// アカウント削除ダイアログ（1段階目）の本文
/// 実装とプレビューで共用するため独立Widgetにしている
class _DeleteAccountWarningContent extends StatelessWidget {
  const _DeleteAccountWarningContent();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('・', style: TextStyle(color: colors.textPrimary)),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'アカウントを削除すると、以下のデータがすべて削除されます。',
          style: TextStyle(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        bullet('体重・食事・運動・睡眠の記録'),
        bullet('トレーナーとのメッセージと写真'),
        bullet('セッション・チケット情報'),
        const SizedBox(height: 12),
        const Text(
          'この操作は取り消せません。',
          style: TextStyle(
            color: AppColors.rose800,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
              _PreviewAppearanceSection(),
              const SizedBox(height: 16),
              _PreviewNotificationSection(),
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

class _PreviewAppearanceSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '外観',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(LucideIcons.sun),
                  label: Text('ライト'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(LucideIcons.moon),
                  label: Text('ダーク'),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(LucideIcons.smartphone),
                  label: Text('システム'),
                ),
              ],
              selected: const {ThemeMode.system},
              onSelectionChanged: (_) {},
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewNotificationSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget toggleRow(IconData icon, String title, bool value) {
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.primary500,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.slate800,
          ),
        ),
        value: value,
        onChanged: (_) {
          // プレビューでは何もしない
        },
      );
    }

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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '通知設定',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.slate500,
                letterSpacing: 0.5,
              ),
            ),
          ),
          toggleRow(LucideIcons.messageCircle, 'メッセージ受信', true),
          toggleRow(LucideIcons.trophy, '目標達成のお知らせ', false),
          const SizedBox(height: 8),
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

          // アカウント削除ボタン
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.rose100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.userX,
                size: 20,
                color: AppColors.rose800,
              ),
            ),
            title: const Text(
              'アカウントを削除',
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

@Preview(name: 'DeleteAccountDialog - Step1 削除データ説明')
Widget previewDeleteAccountDialogStep1() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AlertDialog(
          title: const Text('アカウントを削除'),
          content: const _DeleteAccountWarningContent(),
          actions: [
            TextButton(
              onPressed: () {},
              child: const Text(
                'キャンセル',
                style: TextStyle(color: AppColors.slate600),
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                '続ける',
                style: TextStyle(
                  color: AppColors.rose800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'DeleteAccountDialog - Step2 最終確認')
Widget previewDeleteAccountDialogStep2() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: AlertDialog(
          title: const Text('本当に削除しますか？'),
          content: const Text('この操作は取り消せません。すべてのデータが完全に削除されます。'),
          actions: [
            TextButton(
              onPressed: () {},
              child: const Text(
                'キャンセル',
                style: TextStyle(color: AppColors.slate600),
              ),
            ),
            TextButton(
              onPressed: () {},
              child: const Text(
                '削除する',
                style: TextStyle(
                  color: AppColors.rose800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
