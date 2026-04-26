import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';

class HealthSettingsScreen extends ConsumerWidget {
  const HealthSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(healthSettingsProvider);
    final syncAsync = ref.watch(healthSyncProvider);
    final colors = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ヘルスケア連携'),
        backgroundColor: colors.surface,
        elevation: 0,
        foregroundColor: colors.textPrimary,
      ),
      body: SafeArea(
        child: settingsAsync.when(
          data: (settings) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Master Toggle Card
                _buildMasterToggleCard(context, ref, settings, colors),

                const SizedBox(height: 16),

                // Data Sources Section
                _buildDataSourcesSection(context, ref, settings, colors),

                const SizedBox(height: 16),

                // Notification Section
                _buildNotificationSection(context, ref, settings, colors),

                const SizedBox(height: 16),

                // Sync Section
                _buildSyncSection(
                  context,
                  ref,
                  settings,
                  syncAsync,
                  colors,
                ),

                const SizedBox(height: 24),

                // Note
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '手動入力の体重記録がある日はHealthKitからの取り込みをスキップします',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textHint,
                    ),
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              'エラー: $error',
              style: const TextStyle(color: AppColors.rose800),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterToggleCard(
    BuildContext context,
    WidgetRef ref,
    HealthSettingsState settings,
    AppColorsExtension colors,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary50,
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
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Text(
          'お使いの端末のヘルスケア（iOS: ヘルスケア / Android: Health Connect）からデータを取得',
          style: TextStyle(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        value: settings.isEnabled,
        onChanged: (value) async {
          final granted = await ref
              .read(healthSettingsProvider.notifier)
              .toggleEnabled(value);
          if (!granted && value && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('設定アプリからヘルスケアの権限を許可してください'),
                backgroundColor: AppColors.orange600,
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildDataSourcesSection(
    BuildContext context,
    WidgetRef ref,
    HealthSettingsState settings,
    AppColorsExtension colors,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'データソース',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Weight row
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.scale,
                size: 20,
                color: AppColors.primary500,
              ),
            ),
            title: Text(
              '体重',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              '読み取りのみ',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            value: settings.isWeightEnabled,
            onChanged: settings.isEnabled
                ? (value) {
                    ref
                        .read(healthSettingsProvider.notifier)
                        .toggleWeightEnabled(value);
                  }
                : null,
          ),

          // Sleep row (active)
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.indigo50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.moon,
                size: 20,
                color: AppColors.indigo600,
              ),
            ),
            title: Row(
              children: [
                Text(
                  '睡眠',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.indigo50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.indigo600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'HealthKit/Health Connect から睡眠データを取得',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            value: settings.isSleepEnabled,
            onChanged: settings.isEnabled
                ? (value) async {
                    final granted = await ref
                        .read(healthSettingsProvider.notifier)
                        .toggleSleepEnabled(value);
                    if (!granted && value && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('設定アプリから睡眠データの権限を許可してください'),
                          backgroundColor: AppColors.orange600,
                        ),
                      );
                    }
                  }
                : null,
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNotificationSection(
    BuildContext context,
    WidgetRef ref,
    HealthSettingsState settings,
    AppColorsExtension colors,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '通知',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            secondary: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.orange100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                LucideIcons.sun,
                size: 20,
                color: AppColors.warning,
              ),
            ),
            title: Row(
              children: [
                Text(
                  '朝の目覚めダイアログ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.indigo50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.indigo600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '起床後（4:00-12:00）にアプリを開いた時、目覚めの記録を促します',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            value: settings.isMorningDialogEnabled,
            onChanged: (value) async {
              await ref
                  .read(healthSettingsProvider.notifier)
                  .toggleMorningDialogEnabled(value);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSyncSection(
    BuildContext context,
    WidgetRef ref,
    HealthSettingsState settings,
    AsyncValue<void> syncAsync,
    AppColorsExtension colors,
  ) {
    final isSyncing = syncAsync.isLoading;
    final hasError = settings.lastSyncStatus == HealthSyncStatus.error;
    final isStatusSyncing =
        settings.lastSyncStatus == HealthSyncStatus.syncing;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '同期',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Periodic sync description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'アプリ起動時と1時間ごとに自動同期します',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ),

          // Last sync row
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              '最終同期',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            trailing: _buildSyncStatusTrailing(
              settings: settings,
              colors: colors,
              hasError: hasError,
              isStatusSyncing: isStatusSyncing,
            ),
          ),

          // Error detail row (only on error)
          if (hasError && settings.lastSyncError != null)
            _buildSyncErrorRow(settings.lastSyncError!, colors),

          // Manual sync button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: settings.isEnabled && !isSyncing
                    ? () async {
                        await ref
                            .read(healthSyncProvider.notifier)
                            .syncManual();
                        if (!context.mounted) return;
                        final result =
                            ref.read(healthSettingsProvider).valueOrNull;
                        final isError = result?.lastSyncStatus ==
                            HealthSyncStatus.error;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isError
                                  ? '同期に失敗しました: ${result?.lastSyncError ?? "原因不明"}'
                                  : '同期が完了しました',
                            ),
                            backgroundColor: isError
                                ? AppColors.error
                                : AppColors.emerald600,
                          ),
                        );
                      }
                    : null,
                icon: isSyncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 18),
                label: Text(isSyncing ? '同期中...' : '今すぐ同期'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color: settings.isEnabled
                        ? AppColors.primary
                        : colors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusTrailing({
    required HealthSettingsState settings,
    required AppColorsExtension colors,
    required bool hasError,
    required bool isStatusSyncing,
  }) {
    final timeText = Text(
      _formatLastSync(settings.lastSyncAt),
      style: TextStyle(
        fontSize: 14,
        color: hasError ? AppColors.error : colors.textSecondary,
      ),
    );

    if (isStatusSyncing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          timeText,
          const SizedBox(width: 8),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }

    if (hasError) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          timeText,
          const SizedBox(width: 6),
          const Icon(
            LucideIcons.alertCircle,
            size: 16,
            color: AppColors.error,
          ),
        ],
      );
    }

    return timeText;
  }

  Widget _buildSyncErrorRow(String message, AppColorsExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.rose100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.alertTriangle,
              size: 16,
              color: AppColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '同期エラー: $message',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastSync(DateTime? lastSync) {
    if (lastSync == null) return '未同期';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    // 1週間以上は日付表記
    final m = lastSync.month;
    final d = lastSync.day;
    final hh = lastSync.hour.toString().padLeft(2, '0');
    final mm = lastSync.minute.toString().padLeft(2, '0');
    return '$m月$d日 $hh:$mm';
  }
}

// ============================================
// Previews
// ============================================

class _PreviewHealthSettings extends StatelessWidget {
  final bool isConnected;
  final HealthSyncStatus syncStatus;
  final String? errorMessage;
  const _PreviewHealthSettings({
    this.isConnected = true,
    this.syncStatus = HealthSyncStatus.idle,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // Master Toggle Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary50,
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
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'お使いの端末のヘルスケア（iOS: ヘルスケア / Android: Health Connect）からデータを取得',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                ),
              ),
              value: isConnected,
              onChanged: (_) {},
            ),
          ),

          const SizedBox(height: 16),

          // Data Sources Section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'データソース',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      LucideIcons.scale,
                      size: 20,
                      color: AppColors.primary500,
                    ),
                  ),
                  title: Text(
                    '体重',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '読み取りのみ',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                    ),
                  ),
                  value: isConnected,
                  onChanged: isConnected ? (_) {} : null,
                ),
                Opacity(
                  opacity: 0.5,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.indigo50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        LucideIcons.moon,
                        size: 20,
                        color: AppColors.indigo600,
                      ),
                    ),
                    title: Text(
                      '睡眠',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      '準備中',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.surfaceDim,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        'Coming Soon',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: colors.textHint,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sync Section
          _buildPreviewSyncSection(colors),

          const SizedBox(height: 24),

          // Note
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '手動入力の体重記録がある日はHealthKitからの取り込みをスキップします',
              style: TextStyle(
                fontSize: 12,
                color: colors.textHint,
              ),
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildPreviewSyncSection(AppColorsExtension colors) {
    final hasError = syncStatus == HealthSyncStatus.error;
    final isStatusSyncing = syncStatus == HealthSyncStatus.syncing;

    Widget timeText = Text(
      isConnected ? '5分前' : '未同期',
      style: TextStyle(
        fontSize: 14,
        color: hasError ? AppColors.error : colors.textSecondary,
      ),
    );

    Widget trailing;
    if (isStatusSyncing) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          timeText,
          const SizedBox(width: 8),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    } else if (hasError) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          timeText,
          const SizedBox(width: 6),
          const Icon(
            LucideIcons.alertCircle,
            size: 16,
            color: AppColors.error,
          ),
        ],
      );
    } else {
      trailing = timeText;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '同期',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'アプリ起動時と1時間ごとに自動同期します',
              style: TextStyle(fontSize: 12, color: colors.textHint),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              '最終同期',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
            trailing: trailing,
          ),
          if (hasError && errorMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.rose100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 16,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '同期エラー: $errorMessage',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isConnected ? () {} : null,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('今すぐ同期'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(
                    color:
                        isConnected ? AppColors.primary : colors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'HealthSettingsScreen - Connected')
Widget previewHealthSettingsConnected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(child: _PreviewHealthSettings(isConnected: true)),
    ),
  );
}

@Preview(name: 'HealthSettingsScreen - Disconnected')
Widget previewHealthSettingsDisconnected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(child: _PreviewHealthSettings(isConnected: false)),
    ),
  );
}

@Preview(name: 'HealthSettingsScreen - Sync Error')
Widget previewHealthSettingsSyncError() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const Scaffold(
      body: SafeArea(
        child: _PreviewHealthSettings(
          isConnected: true,
          syncStatus: HealthSyncStatus.error,
          errorMessage: 'HealthKitへのアクセスが拒否されました',
        ),
      ),
    ),
  );
}
