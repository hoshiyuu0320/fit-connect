import 'package:flutter/material.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/screens/meal_record_screen.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/screens/weight_record_screen.dart';
import 'package:fit_connect_mobile/features/exercise_records/presentation/screens/exercise_record_screen.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_notes_screen.dart';

class RecordsScreen extends StatefulWidget {
  final int initialTabIndex;
  final ValueChanged<int>? onTabChanged;

  const RecordsScreen({super.key, this.initialTabIndex = 0, this.onTabChanged});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        widget.onTabChanged?.call(_tabController.index);
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
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary600,
          unselectedLabelColor: colors.textHint,
          indicatorColor: AppColors.primary600,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '体重'),
            Tab(text: '食事'),
            Tab(text: '運動'),
            Tab(text: 'ノート'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          WeightRecordScreen(),
          MealRecordScreen(),
          ExerciseRecordScreen(),
          ClientNotesScreen(),
        ],
      ),
    );
  }
}
