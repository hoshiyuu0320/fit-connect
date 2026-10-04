import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/messages/presentation/screens/message_screen.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/records_screen.dart';
import 'package:fit_connect_mobile/features/settings/presentation/screens/settings_screen.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/workout/presentation/screens/workout_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;
  int _recordsTabIndex = 0;

  /// メッセージ画面の入力欄へ流し込む定型文。
  /// ChatInput が反映し終えたら null に戻す（再ビルドでの再注入を防ぐ）
  String? _messageDraft;

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

  /// セッションの「変更を相談」からメッセージタブへ遷移する。
  /// draft が空文字の場合は定型文なしでメッセージ画面を開くだけ
  void _navigateToMessagesWithDraft(String draft) {
    setState(() {
      _currentIndex = 1;
      _messageDraft = draft.isEmpty ? null : draft;
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
          onNavigateToMessages: () => setState(() => _currentIndex = 1),
          onConsultAboutSession: _navigateToMessagesWithDraft,
        ),
        MessageScreen(
          initialDraft: _messageDraft,
          // 反映済みの定型文は破棄し、再ビルドのたびに再注入されないようにする
          onDraftConsumed: () => setState(() => _messageDraft = null),
        ),
        const WorkoutScreen(),
        RecordsScreen(
          initialTabIndex: _recordsTabIndex,
          onTabChanged: (index) => _recordsTabIndex = index,
          // 記録がまだ無いときの「メッセージから記録する」
          onNavigateToMessages: () => setState(() => _currentIndex = 1),
        ),
        const SettingsScreen(),
      ];

  /// 5 タブの定義（順序は `_screens` と対応）
  static const _navTabs = <({IconData icon, String label})>[
    (icon: LucideIcons.home, label: 'ホーム'),
    (icon: LucideIcons.messageSquare, label: 'メッセージ'),
    (icon: LucideIcons.dumbbell, label: 'プラン'),
    (icon: LucideIcons.barChart2, label: '記録'),
    (icon: LucideIcons.settings, label: '設定'),
  ];

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    // ホームタブに切り替わった時もヘルスケア同期を試行（30秒の連打防止のみ）
    if (index == 0) {
      _maybeSyncOnHomeEntry();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 未読は件数ではなく「数字のない小さな点」で示す
    final hasUnreadMessages =
        (ref.watch(unreadMessageCountProvider).valueOrNull ?? 0) > 0;

    // 下部ナビは本文の上に浮かせる。FcBottomNavLayout が各タブ画面へ
    // 「ナビの高さ + 余白」ぶんの MediaQuery.padding.bottom を渡すので、
    // タブ画面側の SafeArea / ListView が自動でナビを避ける。
    // Scaffold より外側に置くのは、キーボード表示（viewInsets）を検知してナビを隠すため
    return FcBottomNavLayout(
      body: Scaffold(body: _screens[_currentIndex]),
      bottomNav: FcBottomNav(
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        items: [
          for (var i = 0; i < _navTabs.length; i++)
            FcBottomNavItem(
              icon: _navTabs[i].icon,
              label: _navTabs[i].label,
              showDot: i == 1 && hasUnreadMessages,
            ),
        ],
      ),
    );
  }
}
