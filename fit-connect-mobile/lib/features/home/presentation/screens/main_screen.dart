import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/consent/presentation/consent_dialog.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:fit_connect_mobile/features/home/providers/notification_navigation_provider.dart';
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
    // 表示前（起動中・認証待ち）に置かれた通知の「開く先」を、最初のフレームの後で実行する
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openNotificationNavigation();
    });
  }

  /// 通知を押したときの「開く先」の要求を取り出して実行する（記録のリマインダー）。
  /// 体重・食事 → メッセージタブ（入力欄にタグ）、運動 → プランタブ
  void _openNotificationNavigation() {
    if (!mounted) return;
    final request = ref.read(notificationNavigationProvider.notifier).consume();
    if (request == null) return;

    // 上に重なった画面（設定から開いた画面・記録の詳細・ボトムシートなど）を閉じてから
    // タブを切り替える（閉じないと、切り替えが下で起きて見えないまま）。
    // 閉じるのを拒む画面（PopScope の canPop: false。同意ダイアログ・強制アップデートのダイアログ・
    // 送信中の完了報告シートなど）は閉じずに残し、そこで止める（その下の画面もそのまま）。
    // 同意ダイアログは、PopScope が変わっても閉じてしまわないよう、名前でも見分ける
    Navigator.of(context).popUntil(
      (route) =>
          route.isFirst ||
          route.settings.name == consentDialogRouteName ||
          route.popDisposition == RoutePopDisposition.doNotPop,
    );

    switch (request) {
      case OpenMessagesWithDraft(:final draft):
        _navigateToMessagesWithDraft(draft);
      case OpenPlanTab():
        setState(() => _currentIndex = 2);
    }
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
    // 表示中に置かれた通知の「開く先」を実行する
    // （取り出すと provider が変わるので、通知の最中ではなく次の microtask で）
    ref.listen<NotificationNavigationRequest?>(notificationNavigationProvider,
        (previous, next) {
      if (next != null) scheduleMicrotask(_openNotificationNavigation);
    });

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
