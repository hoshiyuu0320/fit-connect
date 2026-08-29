import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// はじめの3ステップカード（ホーム画面最上部）
///
/// 初週の行動（初記録・トレーナーに挨拶・ヘルスケア連携）へ
/// 誘導するチェックリスト。達成判定は既存データから導出する。
///
/// 非表示条件:
/// - 全項目達成
/// - 登録（clients.created_at）から14日経過
/// - 手動で閉じた（SharedPreferences）
class GettingStartedCard extends ConsumerWidget {
  /// 体重記録画面（記録タブ・体重）への遷移
  final VoidCallback? onWeightTap;

  /// メッセージタブへの遷移
  final VoidCallback? onMessageTap;

  const GettingStartedCard({
    super.key,
    this.onWeightTap,
    this.onMessageTap,
  });

  /// カードの自動非表示までの日数（clients.created_at 基準）
  static const int visibleDays = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(currentClientProvider).valueOrNull;
    if (client == null) return const SizedBox.shrink();

    // 登録から14日経過で自動非表示
    if (DateTime.now().difference(client.createdAt).inDays >= visibleDays) {
      return const SizedBox.shrink();
    }

    // 手動で閉じた場合は非表示（読み込み完了までも非表示にしてチラつきを防ぐ）
    final dismissedAsync = ref.watch(gettingStartedCardDismissedProvider);
    if (dismissedAsync.valueOrNull != false) return const SizedBox.shrink();

    // 達成判定（既存データから導出）
    final weightDone =
        ref.watch(latestWeightRecordProvider).valueOrNull != null;
    final messageDone =
        ref.watch(hasSentFirstMessageProvider).valueOrNull ?? false;
    final healthDone =
        ref.watch(healthSettingsProvider).valueOrNull?.isEnabled ?? false;

    // 全達成で自動非表示
    if (weightDone && messageDone && healthDone) {
      return const SizedBox.shrink();
    }

    final doneCount = [weightDone, messageDone, healthDone]
        .where((done) => done)
        .length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: GettingStartedCardBody(
        doneCount: doneCount,
        totalCount: 3,
        onClose: () => ref
            .read(gettingStartedCardDismissedProvider.notifier)
            .dismiss(),
        items: [
          GettingStartedItem(
            icon: LucideIcons.scale,
            iconColor: AppColors.emerald500,
            iconBackgroundColor: AppColors.emerald100,
            label: '最初の体重を記録する',
            isDone: weightDone,
            onTap: onWeightTap,
          ),
          GettingStartedItem(
            icon: LucideIcons.messageSquare,
            iconColor: AppColors.primary500,
            iconBackgroundColor: AppColors.primary100,
            label: 'トレーナーにメッセージを送る',
            isDone: messageDone,
            onTap: onMessageTap,
          ),
          GettingStartedItem(
            icon: LucideIcons.heartPulse,
            iconColor: AppColors.rose800,
            iconBackgroundColor: AppColors.rose100,
            label: 'ヘルスケアと連携する',
            isDone: healthDone,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HealthSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// はじめの3ステップカードの1項目分のデータ
class GettingStartedItem {
  final IconData icon;
  final Color iconColor;
  final Color iconBackgroundColor;
  final String label;
  final bool isDone;
  final VoidCallback? onTap;

  const GettingStartedItem({
    required this.icon,
    required this.iconColor,
    required this.iconBackgroundColor,
    required this.label,
    required this.isDone,
    this.onTap,
  });
}

/// カード本体（プレビュー・テストでも使えるよう Riverpod 非依存）
class GettingStartedCardBody extends StatelessWidget {
  final int doneCount;
  final int totalCount;
  final VoidCallback? onClose;
  final List<GettingStartedItem> items;

  const GettingStartedCardBody({
    super.key,
    required this.doneCount,
    required this.totalCount,
    required this.onClose,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Row(
            children: [
              const Icon(
                LucideIcons.rocket,
                size: 18,
                color: AppColors.primary600,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'はじめの3ステップ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$doneCount/$totalCount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onClose,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 18,
                    color: colors.textHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // 項目リスト
          for (final item in items) _buildItemRow(context, item),
        ],
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, GettingStartedItem item) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: item.iconBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: item.iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color:
                      item.isDone ? colors.textHint : colors.textPrimary,
                  decoration:
                      item.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              item.isDone ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: 20,
              color: item.isDone ? AppColors.emerald500 : colors.textHint,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'GettingStartedCard - 進行中 (1/3)')
Widget previewGettingStartedCardInProgress() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GettingStartedCardBody(
            doneCount: 1,
            totalCount: 3,
            onClose: null,
            items: const [
              GettingStartedItem(
                icon: LucideIcons.scale,
                iconColor: AppColors.emerald500,
                iconBackgroundColor: AppColors.emerald100,
                label: '最初の体重を記録する',
                isDone: true,
              ),
              GettingStartedItem(
                icon: LucideIcons.messageSquare,
                iconColor: AppColors.primary500,
                iconBackgroundColor: AppColors.primary100,
                label: 'トレーナーにメッセージを送る',
                isDone: false,
              ),
              GettingStartedItem(
                icon: LucideIcons.heartPulse,
                iconColor: AppColors.rose800,
                iconBackgroundColor: AppColors.rose100,
                label: 'ヘルスケアと連携する',
                isDone: false,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
