import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_notes_screen.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/screens/exercise_record_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/screens/meal_record_screen.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/screens/records_overview_screen.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/screens/sleep_record_screen.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/screens/weight_record_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録タブの枠（見出し「記録」＋ 6 つのサブタブ ＋ 睡眠の同期ボタン）。
///
/// 各サブタブの本文（[TabBarView] のページ）は、それぞれが自前でスクロールし、
/// 左右の余白も自分で持つ（`AppSpacing.pageHorizontalOf`）。枠は見出しとサブタブにだけ余白を付ける。
///
/// 各サブタブが「まだ記録がありません」のときは、[onNavigateToMessages] があれば
/// 「メッセージから記録する」の入口を出す（メッセージタブへ移る。null なら文言だけ）。
class RecordsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  /// メッセージタブへ移る（空の状態の「メッセージから記録する」から呼ばれる）
  final VoidCallback? onNavigateToMessages;

  const RecordsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onTabChanged,
    this.onNavigateToMessages,
  });

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _syncing = false;

  /// 見出し・サブタブに表示している選択位置。
  /// スワイプ中は、ページが半分を超えた時点で切り替わる（睡眠の同期ボタンもこれに合わせて出入りする）
  late int _shownIndex;

  /// 最後に [RecordsScreen.onTabChanged] へ通知した位置
  late int _notifiedIndex;

  @override
  void initState() {
    super.initState();
    final initial =
        widget.initialTabIndex.clamp(0, recordsTabLabels.length - 1).toInt();
    _tabController = TabController(
      length: recordsTabLabels.length,
      vsync: this,
      initialIndex: initial,
    );
    _shownIndex = initial;
    _notifiedIndex = initial;
    _tabController.addListener(_onControllerChanged);
    _tabController.animation?.addListener(_onAnimationTick);
  }

  @override
  void didUpdateWidget(RecordsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex);
    }
  }

  @override
  void dispose() {
    _tabController.animation?.removeListener(_onAnimationTick);
    _tabController.removeListener(_onControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _setShownIndex(int index) {
    if (!mounted || index == _shownIndex) return;
    setState(() => _shownIndex = index);
  }

  /// タブの切り替えが確定したとき（タップのアニメーション完了・スワイプの終了）
  void _onControllerChanged() {
    // タップで切り替え中でも、見た目の選択はすぐ移す（アニメーション完了を待たない）
    _setShownIndex(_tabController.index);
    if (_tabController.indexIsChanging) return;
    if (_tabController.index != _notifiedIndex) {
      _notifiedIndex = _tabController.index;
      widget.onTabChanged?.call(_notifiedIndex);
    }
  }

  /// スワイプ中の位置。半分を超えたら選択を移す
  void _onAnimationTick() {
    if (_tabController.indexIsChanging) return;
    final value = _tabController.animation?.value;
    if (value == null) return;
    _setShownIndex(value.round());
  }

  Future<void> _onSyncSleep() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await ref.read(healthSyncProvider.notifier).syncManual();
      ref.invalidate(sleepRecordsProvider);
      ref.invalidate(todaySleepRecordProvider);
      ref.invalidate(recentSleepRecordsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同期しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同期に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        // 下は SafeArea で消さない。各タブの本文が下部ナビぶんの余白を自分で受け取る
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecordsFrameHeader(
              selectedIndex: _shownIndex,
              syncing: _syncing,
              onSelected: (index) => _tabController.animateTo(index),
              onSync: _onSyncSleep,
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  RecordsOverviewScreen(
                    onOpenMessages: widget.onNavigateToMessages,
                  ),
                  WeightRecordScreen(
                    onOpenMessages: widget.onNavigateToMessages,
                  ),
                  MealRecordScreen(
                    onOpenMessages: widget.onNavigateToMessages,
                  ),
                  ExerciseRecordScreen(
                    onOpenMessages: widget.onNavigateToMessages,
                  ),
                  // 睡眠は連携と目覚めの記録が入口（メッセージからは記録できない）
                  SleepRecordScreen(onRefresh: _onSyncSleep),
                  const ClientNotesScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// サブタブの並び（サマリ / 体重 / 食事 / 運動 / 睡眠 / ノート）
const List<String> recordsTabLabels = [
  'サマリ',
  '体重',
  '食事',
  '運動',
  '睡眠',
  'ノート',
];

/// 睡眠サブタブの index
const int recordsSleepTabIndex = 4;

/// 記録タブの見出し行とサブタブ。
///
/// 見出し「記録」（下余白 16）の右に、**睡眠タブのときだけ**同期ボタンを置く。
/// 左右の余白はここで付ける（本文側は自分で持つ）。
class RecordsFrameHeader extends StatelessWidget {
  const RecordsFrameHeader({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSync,
    this.syncing = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onSync;

  /// 同期中（スピナーを出し、押せなくする）
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final horizontal = AppSpacing.pageHorizontalOf(context);
    final showSync = selectedIndex == recordsSleepTabIndex;

    return Padding(
      // 正本の本文は上に 4（ステータスバー相当はセーフエリアで足りる）
      padding: EdgeInsets.fromLTRB(horizontal, AppSpacing.xs, horizontal, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 同期ボタンの出入りで下の位置が跳ねないよう、高さの変化はアニメーションさせる
          AnimatedSize(
            duration:
                AppMotion.reduceOf(context) ? Duration.zero : AppMotion.select,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: FcPageHeading(
              title: '記録',
              bottomSpacing: AppSpacing.lg,
              trailing: showSync
                  ? (syncing
                      ? const _SyncingButton()
                      : FcIconButton(
                          icon: LucideIcons.refreshCw,
                          iconSize: 19,
                          iconColor: colors.accent,
                          semanticLabel: '睡眠を同期',
                          onPressed: onSync,
                        ))
                  : null,
            ),
          ),
          FcSubTabs<int>(
            items: [
              for (var i = 0; i < recordsTabLabels.length; i++)
                FcSubTabItem<int>(value: i, label: recordsTabLabels[i]),
            ],
            selected: selectedIndex,
            onChanged: onSelected,
          ),
        ],
      ),
    );
  }
}

/// 同期中の丸ボタン（[FcIconButton] と同じ 44×44・surface の面。アイコンの代わりにスピナー）。
///
/// 押せない。読み上げは「睡眠を同期しています」。
class _SyncingButton extends StatelessWidget {
  const _SyncingButton();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      container: true,
      button: true,
      enabled: false,
      label: '睡眠を同期しています',
      excludeSemantics: true,
      child: Container(
        width: AppSizes.minTouch,
        height: AppSizes.minTouch,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surface),
        child: SizedBox(
          width: 19,
          height: 19,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Previews（子の画面は Riverpod とネットワークが要るため、枠だけを静的に出す）
// ---------------------------------------------------------------------------

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.selectedIndex, this.syncing = false});

  final int selectedIndex;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RecordsFrameHeader(
              selectedIndex: selectedIndex,
              syncing: syncing,
              onSelected: (_) {},
              onSync: () {},
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontalOf(context),
              ),
              child: FcCard(
                child: Text(
                  '${recordsTabLabels[selectedIndex]}の本文',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'RecordsScreen - サマリ（ライト）')
Widget previewRecordsFrameSummary() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewFrame(selectedIndex: 0),
  );
}

@Preview(name: 'RecordsScreen - 睡眠（同期ボタン）')
Widget previewRecordsFrameSleep() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    home: _PreviewFrame(selectedIndex: recordsSleepTabIndex),
  );
}

@Preview(name: 'RecordsScreen - 睡眠（同期中・ダーク）')
Widget previewRecordsFrameSleepSyncingDark() {
  return const FcPreviewApp(
    brightness: Brightness.dark,
    home: _PreviewFrame(selectedIndex: recordsSleepTabIndex, syncing: true),
  );
}

@Preview(name: 'RecordsScreen - 文字特大 1.35')
Widget previewRecordsFrameLargeText() {
  return const FcPreviewApp(
    brightness: Brightness.light,
    textScale: 1.35,
    home: _PreviewFrame(selectedIndex: 1),
  );
}
