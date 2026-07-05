import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/screens/meal_record_screen.dart';
import 'package:fit_connect_mobile/features/records_overview/presentation/screens/records_overview_screen.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/screens/weight_record_screen.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/screens/exercise_record_screen.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_notes_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/screens/sleep_record_screen.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  const RecordsScreen({super.key, this.initialTabIndex = 0, this.onTabChanged});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _syncing = false;

  /// 睡眠サブタブの index（サマリ0/体重1/食事2/運動3/睡眠4/ノート5）
  static const int _sleepTabIndex = 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged?.call(_tabController.index);
        // 睡眠タブ選択時のみ AppBar の同期ボタンを出すため再ビルド
        setState(() {});
      }
    });
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
    _tabController.dispose();
    super.dispose();
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
      backgroundColor: colors.surfaceDim,
      appBar: AppBar(
        title: Text(
          '記録',
          style:
              TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_tabController.index == _sleepTabIndex)
            IconButton(
              onPressed: _syncing ? null : _onSyncSleep,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 18),
              tooltip: '同期',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary600,
          unselectedLabelColor: colors.textHint,
          indicatorColor: AppColors.primary600,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'サマリ'),
            Tab(text: '体重'),
            Tab(text: '食事'),
            Tab(text: '運動'),
            Tab(text: '睡眠'),
            Tab(text: 'ノート'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const RecordsOverviewScreen(),
          const WeightRecordScreen(),
          const MealRecordScreen(),
          const ExerciseRecordScreen(),
          SleepRecordScreen(onRefresh: _onSyncSleep),
          const ClientNotesScreen(),
        ],
      ),
    );
  }
}
