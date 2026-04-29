import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/messages/presentation/screens/message_screen.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/records_screen.dart';
import 'package:fit_connect_mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_achievement_provider.dart';
import 'package:fit_connect_mobile/features/goals/presentation/widgets/goal_achievement_overlay.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  int _recordsTabIndex = 0;
  bool _initialized = false;

  /// 最後にホーム遷移トリガで sync を発火した時刻（連打防止）
  DateTime? _lastHomeTriggerSyncAt;

  @override
  void initState() {
    super.initState();
    // ホーム画面マウント時にヘルスケア同期を試行（アプリ起動時 / 再ログイン時）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeSyncOnHomeEntry();
    });
  }

  void _navigateToRecordsTab(int tabIndex) {
    setState(() {
      _currentIndex = 3;
      _recordsTabIndex = tabIndex;
    });
  }

  /// ホーム画面に到達したタイミングで同期を発火する。
  /// 連打防止のため直近 30 秒以内のみスキップ。
  /// HealthKit のデータを即座に画面に反映させるのが目的なので、
  /// `lastSyncAt` ベースの長時間レート制限はかけない（_AuthLoadingScreen の
  /// 起動時同期と並行することはあるが、HealthKit の呼び出しは軽量で
  /// `filterHealthData` / `upsertObjectiveData` が冪等なので実害はない）。
  Future<void> _maybeSyncOnHomeEntry() async {
    if (!mounted) return;

    // settings provider が cold start 直後でまだ resolve していないケースに備え、
    // valueOrNull ではなく future を await する
    final settings = await ref.read(healthSettingsProvider.future);
    if (!mounted) return;
    if (!settings.isEnabled) return;

    final now = DateTime.now();
    if (_lastHomeTriggerSyncAt != null &&
        now.difference(_lastHomeTriggerSyncAt!) < const Duration(seconds: 30)) {
      return;
    }

    _lastHomeTriggerSyncAt = now;
    try {
      await ref.read(healthSyncProvider.notifier).syncOnLaunch();
      debugPrint('[MainScreen] Home遷移時の同期完了');
    } catch (e) {
      debugPrint('[MainScreen] Home遷移時の同期エラー: $e');
    }
  }

  List<Widget> get _screens => [
        HomeScreen(
          onNavigateToRecordsTab: _navigateToRecordsTab,
        ),
        const MessageScreen(),
        const WorkoutScreen(),
        RecordsScreen(
          initialTabIndex: _recordsTabIndex,
          onTabChanged: (index) => _recordsTabIndex = index,
        ),
        const SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // Watch unread message count
    final unreadCount = ref.watch(unreadMessageCountProvider).valueOrNull ?? 0;

    // Watch goal achievement state
    final showCelebration = ref.watch(goalAchievementNotifierProvider);
    final goalAsync = ref.watch(currentGoalProvider);
    final clientAsync = ref.watch(currentClientProvider);

    // Listen for goal changes and check for new achievements
    ref.listen<AsyncValue>(currentGoalProvider, (previous, next) {
      next.whenData((goal) {
        if (goal != null) {
          if (!_initialized) {
            // 初回ロード時は既存の達成状態を記録（お祝い画面は表示しない）
            ref
                .read(goalAchievementNotifierProvider.notifier)
                .initializeAchievedAt(goal.goalAchievedAt);
            _initialized = true;
          } else {
            // 2回目以降は新規達成をチェック
            ref
                .read(goalAchievementNotifierProvider.notifier)
                .checkAndShowCelebration(goal.goalAchievedAt);
          }
        }
      });
    });

    // Get goal data for overlay
    final targetWeight = goalAsync.valueOrNull?.targetWeight ?? 0.0;
    final clientName = clientAsync.valueOrNull?.name;

    return Stack(
      children: [
        Scaffold(
          body: _screens[_currentIndex],
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              // Ensure it respects safe area on newer iPhones
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, LucideIcons.home, 'ホーム'),
                    _buildNavItem(1, LucideIcons.messageSquare, 'メッセージ',
                        badgeCount: unreadCount),
                    _buildNavItem(2, LucideIcons.dumbbell, 'プラン'),
                    _buildNavItem(3, LucideIcons.barChart2, '記録'),
                    _buildNavItem(4, LucideIcons.settings, '設定'),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Goal achievement overlay
        if (showCelebration)
          GoalAchievementOverlay(
            targetWeight: targetWeight,
            clientName: clientName,
            onDismiss: () {
              ref
                  .read(goalAchievementNotifierProvider.notifier)
                  .dismissCelebration();
            },
          ),
      ],
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label,
      {int? badgeCount}) {
    final colors = AppColors.of(context);
    final isSelected = _currentIndex == index;
    return InkWell(
      onTap: () {
        setState(() => _currentIndex = index);
        // ホームタブに切り替わった時もヘルスケア同期を試行（30秒の連打防止のみ）
        if (index == 0) {
          _maybeSyncOnHomeEntry();
        }
      },
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primary600 : colors.textHint,
                  size: 24,
                ),
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      decoration: BoxDecoration(
                        color: AppColors.rose800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary600 : colors.textHint,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
