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
          'Apple Health からデータを取得',
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

          // Sleep row (Coming Soon)
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              '同期',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
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
            trailing: Text(
              _formatLastSync(settings.lastSyncAt),
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ),

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
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('同期が完了しました'),
                              backgroundColor: AppColors.emerald600,
                            ),
                          );
                        }
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

  String _formatLastSync(DateTime? lastSync) {
    if (lastSync == null) return '未同期';
    final month = lastSync.month;
    final day = lastSync.day;
    final hour = lastSync.hour.toString().padLeft(2, '0');
    final minute = lastSync.minute.toString().padLeft(2, '0');
    return '$month月$day日 $hour:$minute';
  }
}

// ============================================
// Previews
// ============================================

class _PreviewHealthSettings extends StatelessWidget {
  final bool isConnected;
  const _PreviewHealthSettings({this.isConnected = true});

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
                'Apple Health からデータを取得',
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
                    '同期',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(
                    '最終同期',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  trailing: Text(
                    isConnected ? '4月5日 09:30' : '未同期',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
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
                          color: isConnected
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
