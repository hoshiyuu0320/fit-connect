# FIT-CONNECT Mobile: ワークアウト未完了対応 + 週間ビュー拡張 設計書

> 作成日: 2026-02-22
> 対象: モバイルアプリ（Flutter / Riverpod）+ Supabase Edge Function
> 関連: `DESIGN_WORKOUT_COMPLETION_FIX.md`（完了報告改修）

---

## 1. 背景と課題

### 現在の問題

現在のワークアウト画面（`workout_screen.dart`）は **「今日の日付」のアサインメントのみ** を表示する設計:

```dart
// workout_provider.dart: TodayAssignments.build()
final today = DateTime.now();
final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
return repo.getAssignmentsByDate(clientId, dateStr);
```

**発生する問題:**

1. **未実行の消失**: 月曜に割り当てられたワークアウトを月曜中に実行できなかった場合、火曜日にはアプリ上から消え、クライアントは実行不可能になる
2. **リスケ不可**: 体調不良や予定変更時に別の日に振り替える手段がない
3. **見通しの悪さ**: 今日以外のワークアウト予定が確認できない
4. **未完了の蓄積**: 長期間放置された未完了アサインメントがDBに蓄積される

### 現在の `workout_assignments.status` の値

| ステータス | 意味 | 使用箇所 |
|-----------|------|---------|
| `pending` | 未着手 | 初期状態（POST時に設定） |
| `completed` | 完了済み | `completeAssignment()` で設定 |
| `skipped` | スキップ済み | **未使用**（今回新たに活用） |

---

## 2. 改善方針（案C: ハイブリッド）

以下の4つの機能を組み合わせて、未完了問題を包括的に解決する:

### 2A. 未完了アサインメントの自動表示

`assigned_date` が過去かつ `status = 'pending'` のアサインメントを **今日の画面に自動的に表示** する。「期限切れ」ラベル付きで、今日のアサインメントと区別する。

### 2B. アクションボタン（今日やる / スキップ / 日付変更）

未完了アサインメントに対して3つのアクションを提供:

| アクション | 動作 | DB更新 |
|-----------|------|--------|
| **今日やる** | `assigned_date` を今日に変更し、通常のワークアウトとして表示 | `assigned_date = today` |
| **スキップ** | このプランを見送る | `status = 'skipped'` |
| **日付変更** | 別の日に振り替える（DatePicker表示） | `assigned_date = selectedDate` |

### 2C. 週間ミニカレンダー

画面上部に今週のワークアウト予定を一覧表示する週間カレンダーWidget。既存の `ExerciseWeekCalendar` のUIパターンを踏襲し、各日にワークアウトアサインメントの有無・ステータスをアイコンで表示する。

### 2D. 3日自動スキップ（Edge Function）

`assigned_date` から **3日経過** しても `status = 'pending'` のアサインメントを自動的に `status = 'skipped'` に変更する。Supabase Edge Function + `pg_cron` による日次バッチ処理。

---

## 3. 変更対象ファイル一覧

| # | ファイルパス | 変更内容 |
|---|------------|----------|
| 1 | `lib/features/workout/data/workout_repository.dart` | 4メソッド追加（未完了取得、スキップ、日付変更、週間データ取得） |
| 2 | `lib/features/workout/providers/workout_provider.dart` | Provider群のリネーム・拡張、新規Provider追加 |
| 3 | `lib/features/workout/presentation/screens/workout_screen.dart` | レイアウト再構成（カレンダー + 未完了セクション + 今日セクション） |

---

## 4. 新規作成ファイル一覧

| # | ファイルパス | 内容 |
|---|------------|------|
| 1 | `lib/features/workout/models/workout_screen_state.dart` | 画面表示用のstate値オブジェクト |
| 2 | `lib/features/workout/presentation/widgets/weekly_mini_calendar.dart` | 週間ミニカレンダーWidget |
| 3 | `lib/features/workout/presentation/widgets/overdue_assignment_card.dart` | 未完了アサインメント表示カード |
| 4 | `lib/features/workout/presentation/widgets/upcoming_assignment_card.dart` | 今日/今後のアサインメント表示カード |
| 5 | `lib/features/workout/presentation/widgets/reschedule_date_picker.dart` | 日付変更用DatePickerダイアログ |
| 6 | `supabase/functions/auto-skip-workouts/index.ts` | 3日経過アサインメント自動スキップ Edge Function |

---

## 5. 変更詳細

### 5A. `workout_screen_state.dart`（新規: state値オブジェクト）

画面に表示するデータをまとめた値オブジェクト。Providerの `build()` で生成し、UIで分岐なく使用する。

```dart
/// ワークアウト画面の表示データ
class WorkoutScreenState {
  /// 期限切れの未完了アサインメント（assigned_date < today, status = 'pending'）
  final List<WorkoutAssignment> overdueAssignments;

  /// 今日のアサインメント（assigned_date = today）
  final List<WorkoutAssignment> todayAssignments;

  /// 週間カレンダー用データ（日付 → アサインメントリスト）
  final Map<DateTime, List<WorkoutAssignment>> weeklyData;

  const WorkoutScreenState({
    required this.overdueAssignments,
    required this.todayAssignments,
    required this.weeklyData,
  });

  /// 全アサインメント（overdue + today）
  List<WorkoutAssignment> get allActionable =>
      [...overdueAssignments, ...todayAssignments];

  /// 空判定
  bool get isEmpty =>
      overdueAssignments.isEmpty && todayAssignments.isEmpty;
}
```

**ポイント:**
- `freezed` / `json_annotation` は不要（APIレスポンスではなくUI用の中間データ）
- `.g.dart` 生成不要

---

### 5B. `workout_repository.dart`（変更: 4メソッド追加）

#### 5B-1. `getOverdueAssignments()` - 未完了アサインメント取得

```dart
/// 期限切れの未完了アサインメントを取得
/// assigned_date < today かつ status = 'pending' かつ self_guided
Future<List<WorkoutAssignment>> getOverdueAssignments(
  String clientId,
  String todayStr,
) async {
  final data = await SupabaseService.client
      .from('workout_assignments')
      .select(
        '*, workout_plans(title, description, category, estimated_minutes, plan_type), workout_assignment_exercises(*)',
      )
      .eq('client_id', clientId)
      .eq('status', 'pending')
      .lt('assigned_date', todayStr)
      .order('assigned_date', ascending: true);

  final assignments = data
      .map((json) => WorkoutAssignment.fromJson(json))
      .where((a) => a.planInfo?.planType == 'self_guided')
      .toList();

  return assignments.map((assignment) {
    final sorted = [...assignment.exercises]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return assignment.copyWith(exercises: sorted);
  }).toList();
}
```

#### 5B-2. `skipAssignment()` - アサインメントをスキップ

```dart
/// アサインメントをスキップする
Future<void> skipAssignment(String assignmentId) async {
  await SupabaseService.client
      .from('workout_assignments')
      .update({
        'status': 'skipped',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', assignmentId);
}
```

#### 5B-3. `rescheduleAssignment()` - 日付を変更

```dart
/// アサインメントの実施日を変更する
Future<void> rescheduleAssignment(
  String assignmentId,
  String newDateStr,
) async {
  await SupabaseService.client
      .from('workout_assignments')
      .update({
        'assigned_date': newDateStr,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', assignmentId);
}
```

#### 5B-4. `getWeeklyAssignments()` - 週間アサインメント取得

```dart
/// 指定週のアサインメントを取得（カレンダー表示用）
Future<List<WorkoutAssignment>> getWeeklyAssignments(
  String clientId,
  String weekStartStr,
  String weekEndStr,
) async {
  final data = await SupabaseService.client
      .from('workout_assignments')
      .select(
        '*, workout_plans(title, description, category, estimated_minutes, plan_type)',
      )
      .eq('client_id', clientId)
      .gte('assigned_date', weekStartStr)
      .lte('assigned_date', weekEndStr)
      .order('assigned_date', ascending: true);

  return data
      .map((json) => WorkoutAssignment.fromJson(json))
      .where((a) => a.planInfo?.planType == 'self_guided')
      .toList();
}
```

**注意:** 週間カレンダー用クエリでは `workout_assignment_exercises` は不要（ステータスアイコン表示のみ）。通信量を最小化するため join を省略する。

---

### 5C. `workout_provider.dart`（変更: リネーム・拡張）

#### 5C-1. `TodayAssignments` → `WorkoutScreenNotifier` にリネーム・拡張

既存の `TodayAssignments` を拡張し、未完了アサインメント + 週間データも一括で取得する:

```dart
@riverpod
class WorkoutScreenNotifier extends _$WorkoutScreenNotifier {
  @override
  Future<WorkoutScreenState> build() async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) {
      return const WorkoutScreenState(
        overdueAssignments: [],
        todayAssignments: [],
        weeklyData: {},
      );
    }

    final repo = ref.watch(workoutRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // 今週の範囲計算（月曜始まり）
    final daysFromMonday = (today.weekday - 1) % 7;
    final weekStart = today.subtract(Duration(days: daysFromMonday));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekStartStr =
        '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
    final weekEndStr =
        '${weekEnd.year}-${weekEnd.month.toString().padLeft(2, '0')}-${weekEnd.day.toString().padLeft(2, '0')}';

    // 並列取得
    final results = await Future.wait([
      repo.getOverdueAssignments(clientId, todayStr),
      repo.getAssignmentsByDate(clientId, todayStr),
      repo.getWeeklyAssignments(clientId, weekStartStr, weekEndStr),
    ]);

    final overdueAssignments = results[0];
    final todayAssignments = results[1];
    final weeklyAssignments = results[2];

    // 週間データをMap化
    final weeklyData = <DateTime, List<WorkoutAssignment>>{};
    for (final a in weeklyAssignments) {
      final parts = a.assignedDate.split('-');
      final date = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
      weeklyData.putIfAbsent(date, () => []).add(a);
    }

    return WorkoutScreenState(
      overdueAssignments: overdueAssignments,
      todayAssignments: todayAssignments,
      weeklyData: weeklyData,
    );
  }

  // --- 既存メソッド（toggleExercise, updateExerciseSets, submitCompletion）は維持 ---
  // ただし state の型が WorkoutScreenState に変わるため、
  // todayAssignments / overdueAssignments をそれぞれ更新するように調整

  /// 種目の完了状態をトグル（既存ロジックの型調整）
  Future<void> toggleExercise(
    String assignmentId,
    String exerciseId,
  ) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final allAssignments = currentState.allActionable;
    final assignment = allAssignments.firstWhere((a) => a.id == assignmentId);
    final exercise = assignment.exercises.firstWhere((e) => e.id == exerciseId);
    final newIsCompleted = !exercise.isCompleted;

    final repo = ref.read(workoutRepositoryProvider);
    await repo.toggleExerciseCompletion(exerciseId, newIsCompleted);

    // ローカルstate更新（WorkoutScreenState内の該当リストを更新）
    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        exercises: a.exercises.map((e) {
          if (e.id != exerciseId) return e;
          return e.copyWith(
            isCompleted: newIsCompleted,
            completedAt: newIsCompleted ? DateTime.now() : null,
          );
        }).toList(),
      );
    });
  }

  /// セット記録を更新（既存ロジックの型調整）
  Future<void> updateExerciseSets(
    String assignmentId,
    String exerciseId,
    List<ActualSet> actualSets,
  ) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final repo = ref.read(workoutRepositoryProvider);
    await repo.updateActualSets(exerciseId, actualSets);

    final allDone = actualSets.isNotEmpty && actualSets.every((s) => s.done);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(
        exercises: a.exercises.map((e) {
          if (e.id != exerciseId) return e;
          return e.copyWith(
            actualSets: actualSets,
            isCompleted: allDone,
            completedAt: allDone ? DateTime.now() : null,
          );
        }).toList(),
      );
    });
  }

  /// 完了報告（既存ロジックの型調整）
  Future<void> submitCompletion(
    String assignmentId, {
    String? clientFeedback,
  }) async {
    final repo = ref.read(workoutRepositoryProvider);
    await repo.completeAssignment(assignmentId, clientFeedback: clientFeedback);

    _updateAssignment(assignmentId, (a) {
      return a.copyWith(status: 'completed', finishedAt: DateTime.now());
    });
  }

  /// 未完了アサインメントを「今日やる」に変更
  Future<void> doToday(String assignmentId) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final repo = ref.read(workoutRepositoryProvider);
    await repo.rescheduleAssignment(assignmentId, todayStr);

    // overdue → today に移動
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final target = currentState.overdueAssignments
        .firstWhere((a) => a.id == assignmentId);
    final updated = target.copyWith(assignedDate: todayStr);

    state = AsyncData(WorkoutScreenState(
      overdueAssignments:
          currentState.overdueAssignments.where((a) => a.id != assignmentId).toList(),
      todayAssignments: [...currentState.todayAssignments, updated],
      weeklyData: currentState.weeklyData, // カレンダーは次回rebuild時に更新
    ));
  }

  /// 未完了アサインメントをスキップ
  Future<void> skip(String assignmentId) async {
    final repo = ref.read(workoutRepositoryProvider);
    await repo.skipAssignment(assignmentId);

    // overdueリストから除去
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(WorkoutScreenState(
      overdueAssignments:
          currentState.overdueAssignments.where((a) => a.id != assignmentId).toList(),
      todayAssignments: currentState.todayAssignments,
      weeklyData: currentState.weeklyData,
    ));
  }

  /// 未完了アサインメントの日付を変更
  Future<void> reschedule(String assignmentId, DateTime newDate) async {
    final newDateStr =
        '${newDate.year}-${newDate.month.toString().padLeft(2, '0')}-${newDate.day.toString().padLeft(2, '0')}';

    final repo = ref.read(workoutRepositoryProvider);
    await repo.rescheduleAssignment(assignmentId, newDateStr);

    // overdueリストから除去
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(WorkoutScreenState(
      overdueAssignments:
          currentState.overdueAssignments.where((a) => a.id != assignmentId).toList(),
      todayAssignments: currentState.todayAssignments,
      weeklyData: currentState.weeklyData,
    ));
  }

  /// 内部ヘルパー: assignmentIdで overdue/today 両リストを横断更新
  void _updateAssignment(
    String assignmentId,
    WorkoutAssignment Function(WorkoutAssignment) updater,
  ) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncData(WorkoutScreenState(
      overdueAssignments: currentState.overdueAssignments.map((a) {
        return a.id == assignmentId ? updater(a) : a;
      }).toList(),
      todayAssignments: currentState.todayAssignments.map((a) {
        return a.id == assignmentId ? updater(a) : a;
      }).toList(),
      weeklyData: currentState.weeklyData,
    ));
  }
}
```

#### 5C-2. `completedWorkoutAssignments` Provider は変更なし

既存の `completedWorkoutAssignments` Provider は `records_screen.dart`（運動履歴画面）で使用されており、今回の変更対象外。

---

### 5D. `workout_screen.dart`（変更: レイアウト再構成）

#### 画面レイアウト（上から順）

```
┌─────────────────────────────────────┐
│  AppBar: ワークアウト                 │
├─────────────────────────────────────┤
│  WeeklyMiniCalendar                 │  ← 新規Widget
│  ┌─月─┬─火─┬─水─┬─木─┬─金─┬─土─┬─日─┐│
│  │ 17 │ 18 │ 19 │ 20 │ 21 │ 22 │ 23 ││
│  │ 🏋 │    │ 🏋 │    │ ⏳ │ 🏋 │    ││
│  └────┴────┴────┴────┴────┴────┴────┘│
├─────────────────────────────────────┤
│  ⚠️ 未完了のワークアウト (2件)        │  ← overdueAssignments.isNotEmpty 時のみ
│  ┌─────────────────────────────────┐ │
│  │ 🔶 上半身トレーニング            │ │  ← OverdueAssignmentCard
│  │    2月19日(水) のプラン          │ │
│  │  [今日やる] [スキップ] [日付変更] │ │
│  └─────────────────────────────────┘ │
│  ┌─────────────────────────────────┐ │
│  │ 🔶 下半身トレーニング            │ │
│  │    2月17日(月) のプラン          │ │
│  │  [今日やる] [スキップ] [日付変更] │ │
│  └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│  📅 2026年2月22日                   │  ← 既存の _DateHeader
│                                     │
│  ── 今日のワークアウト ──            │  ← todayAssignments
│  (既存の _AssignmentSection)         │
│  WorkoutProgressBar                 │
│  WorkoutExerciseCard × N            │
│  [完了報告] ボタン                   │
│                                     │
│  ── 空状態 ──                       │  ← 両方空の場合
│  (既存の _EmptyState を調整)         │
└─────────────────────────────────────┘
```

#### 主な変更点

1. **Provider参照変更**: `todayAssignmentsProvider` → `workoutScreenNotifierProvider`
2. **`assignmentsAsync.when` 内のレイアウト再構成**: カレンダー + 未完了セクション + 今日セクション
3. **`_handleSubmitCompletion` 内のProvider参照変更**: `todayAssignmentsProvider.notifier` → `workoutScreenNotifierProvider.notifier`
4. **空状態メッセージの更新**: 未完了もなく今日もない場合の表示

#### 変更コード概要

```dart
// build() 内
final screenStateAsync = ref.watch(workoutScreenNotifierProvider);

return GestureDetector(
  onTap: () => FocusScope.of(context).unfocus(),
  child: Scaffold(
    appBar: AppBar(title: const Text('ワークアウト')),
    backgroundColor: AppColors.background,
    body: Stack(
      children: [
        screenStateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('エラーが発生しました: $e')),
          data: (screenState) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. 週間ミニカレンダー
                WeeklyMiniCalendar(weeklyData: screenState.weeklyData),
                const SizedBox(height: 16),

                // 2. 未完了セクション
                if (screenState.overdueAssignments.isNotEmpty) ...[
                  _OverdueSection(
                    assignments: screenState.overdueAssignments,
                    onDoToday: (id) => ref
                        .read(workoutScreenNotifierProvider.notifier)
                        .doToday(id),
                    onSkip: (id) => ref
                        .read(workoutScreenNotifierProvider.notifier)
                        .skip(id),
                    onReschedule: (id, date) => ref
                        .read(workoutScreenNotifierProvider.notifier)
                        .reschedule(id, date),
                  ),
                  const SizedBox(height: 24),
                ],

                // 3. 今日のワークアウト
                _DateHeader(today: DateTime.now()),
                const SizedBox(height: 16),

                if (screenState.todayAssignments.isEmpty &&
                    screenState.overdueAssignments.isEmpty) ...[
                  _EmptyState(),
                ] else if (screenState.todayAssignments.isEmpty) ...[
                  // 未完了はあるが今日のプランはない
                  _TodayEmptyHint(),
                ] else ...[
                  for (int i = 0; i < screenState.todayAssignments.length; i++) ...[
                    if (i > 0) const SizedBox(height: 24),
                    _AssignmentSection(
                      assignment: screenState.todayAssignments[i],
                      onSetsUpdated: (aId, eId, sets) => ref
                          .read(workoutScreenNotifierProvider.notifier)
                          .updateExerciseSets(aId, eId, sets),
                      onSubmit: () => _handleSubmitCompletion(
                          screenState.todayAssignments[i]),
                    ),
                  ],
                ],
              ],
            );
          },
        ),

        // 完了オーバーレイ（既存）
        if (_showCompletionOverlay)
          WorkoutCompletionOverlay(
            planTitle: _completedPlanTitle,
            onDismiss: () => setState(() => _showCompletionOverlay = false),
          ),
      ],
    ),
  ),
);
```

---

### 5E. 新規Widget群

#### 5E-1. `weekly_mini_calendar.dart` - 週間ミニカレンダー

既存の `ExerciseWeekCalendar` のUIパターンを踏襲。ただしデータソースが `exercise_records` ではなく `workout_assignments` なので、Providerに依存せずプロパティでデータを受け取る StatelessWidget として実装する。

```dart
class WeeklyMiniCalendar extends StatelessWidget {
  final Map<DateTime, List<WorkoutAssignment>> weeklyData;

  const WeeklyMiniCalendar({super.key, required this.weeklyData});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysFromMonday = (today.weekday - 1) % 7;
    final startOfWeek = today.subtract(Duration(days: daysFromMonday));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今週のワークアウト',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.slate800,
            ),
          ),
          const SizedBox(height: 16),
          _buildWeekGrid(today, startOfWeek),
        ],
      ),
    );
  }

  Widget _buildWeekGrid(DateTime today, DateTime startOfWeek) {
    const dayLabels = ['月', '火', '水', '木', '金', '土', '日'];

    return Row(
      children: List.generate(7, (index) {
        final date = startOfWeek.add(Duration(days: index));
        final assignments = weeklyData[date] ?? [];
        final isToday = date == today;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: _DayCell(
              dayLabel: dayLabels[index],
              date: date,
              assignments: assignments,
              isToday: isToday,
            ),
          ),
        );
      }),
    );
  }
}
```

**日セルのアイコン表示ルール:**

| 条件 | アイコン | 背景色 |
|------|---------|--------|
| アサインメントなし | なし | `AppColors.slate50` |
| `status = 'completed'` | `✅` | `AppColors.emerald50` |
| `status = 'pending'` & 未来 | `🏋️` | `AppColors.indigo50` |
| `status = 'pending'` & 過去（未完了） | `⏳` | `AppColors.orange50` |
| `status = 'skipped'` | `⏭` | `AppColors.slate100` |
| 今日 | （上記 + 枠線 `AppColors.primary600`） | 上記 + border |

#### 5E-2. `overdue_assignment_card.dart` - 未完了アサインメントカード

```dart
class OverdueAssignmentCard extends StatelessWidget {
  final WorkoutAssignment assignment;
  final VoidCallback onDoToday;
  final VoidCallback onSkip;
  final ValueChanged<DateTime> onReschedule;

  const OverdueAssignmentCard({
    super.key,
    required this.assignment,
    required this.onDoToday,
    required this.onSkip,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
    final assignedDate = assignment.assignedDate; // "2026-02-19"
    final daysOverdue = _calculateDaysOverdue(assignedDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange500, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー行（タイトル + 日数バッジ）
          Row(
            children: [
              Icon(LucideIcons.alertCircle, size: 18, color: AppColors.orange500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  planTitle,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // 経過日数バッジ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.orange50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$daysOverdue日前',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.orange800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatAssignedDate(assignedDate),
            style: TextStyle(fontSize: 13, color: AppColors.slate500),
          ),
          const SizedBox(height: 12),

          // アクションボタン行
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: '今日やる',
                  icon: LucideIcons.play,
                  color: AppColors.emerald500,
                  onPressed: onDoToday,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: 'スキップ',
                  icon: LucideIcons.skipForward,
                  color: AppColors.slate400,
                  onPressed: onSkip,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  label: '日付変更',
                  icon: LucideIcons.calendarDays,
                  color: AppColors.primary500,
                  onPressed: () async {
                    final picked = await showDialog<DateTime>(
                      context: context,
                      builder: (_) => const RescheduleDatePicker(),
                    );
                    if (picked != null) onReschedule(picked);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _calculateDaysOverdue(String dateStr) {
    final parts = dateStr.split('-');
    final assigned = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    return todayDate.difference(assigned).inDays;
  }

  String _formatAssignedDate(String dateStr) {
    final parts = dateStr.split('-');
    final date = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${date.month}月${date.day}日(${weekdays[date.weekday - 1]}) のプラン';
  }
}
```

#### 5E-3. `upcoming_assignment_card.dart` - 今後のアサインメント表示カード

今日のアサインメントは既存の `_AssignmentSection` をそのまま使用するため、このWidgetは **将来の週間ビューで日付選択時の閲覧用** に設計する。初期実装では不要。**作成は後回しでも可。**

#### 5E-4. `reschedule_date_picker.dart` - 日付変更ダイアログ

```dart
class RescheduleDatePicker extends StatefulWidget {
  const RescheduleDatePicker({super.key});

  @override
  State<RescheduleDatePicker> createState() => _RescheduleDatePickerState();
}

class _RescheduleDatePickerState extends State<RescheduleDatePicker> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return AlertDialog(
      title: const Text('日付を変更'),
      content: SizedBox(
        width: 300,
        height: 300,
        child: CalendarDatePicker(
          initialDate: _selectedDate,
          firstDate: today, // 過去は選択不可
          lastDate: today.add(const Duration(days: 30)), // 30日先まで
          onDateChanged: (date) {
            setState(() => _selectedDate = date);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_selectedDate),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary500,
            foregroundColor: Colors.white,
          ),
          child: const Text('変更する'),
        ),
      ],
    );
  }
}
```

---

### 5F. `auto-skip-workouts` Edge Function（新規）

#### 機能概要

`assigned_date` から **3日経過** かつ `status = 'pending'` のアサインメントを自動的に `status = 'skipped'` に更新する。

#### Edge Function コード

```typescript
// supabase/functions/auto-skip-workouts/index.ts
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  // Authorization チェック（pg_cron からの呼び出し or サービスキー）
  const authHeader = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // サービスロールキーでの認証を確認
  if (authHeader !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // 3日前の日付を計算
  const threeDaysAgo = new Date();
  threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
  const cutoffDate = threeDaysAgo.toISOString().split("T")[0]; // "YYYY-MM-DD"

  // 対象レコードを更新
  const { data, error, count } = await supabase
    .from("workout_assignments")
    .update({
      status: "skipped",
      updated_at: new Date().toISOString(),
    })
    .eq("status", "pending")
    .lt("assigned_date", cutoffDate)
    .select("id");

  if (error) {
    console.error("Auto-skip error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const skippedCount = data?.length ?? 0;
  console.log(`Auto-skipped ${skippedCount} overdue assignments (cutoff: ${cutoffDate})`);

  return new Response(
    JSON.stringify({
      status: "ok",
      skippedCount,
      cutoffDate,
      skippedIds: data?.map((d: { id: string }) => d.id) ?? [],
    }),
    {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }
  );
});
```

#### pg_cron によるスケジュール設定

Supabase Dashboard > Database > Extensions から `pg_cron` を有効化し、以下のSQLで日次ジョブを登録:

```sql
-- 毎日 AM 3:00 (UTC) に実行
SELECT cron.schedule(
  'auto-skip-overdue-workouts',
  '0 3 * * *',
  $$
  SELECT net.http_post(
    url := 'https://<project-ref>.supabase.co/functions/v1/auto-skip-workouts',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

**代替案:** pg_cron の設定が困難な場合は、Edge Function を手動トリガー可能な状態でデプロイしておき、将来的にスケジュール化する。モバイル側の動作には影響しない（`getOverdueAssignments()` で3日以内の未完了は表示されるため）。

---

## 6. データフロー

### フロー1: 画面表示

```
WorkoutScreenNotifier.build()
    │
    ├── getOverdueAssignments(clientId, todayStr)
    │   └── SELECT ... WHERE status='pending' AND assigned_date < today
    │
    ├── getAssignmentsByDate(clientId, todayStr)
    │   └── SELECT ... WHERE assigned_date = today
    │
    └── getWeeklyAssignments(clientId, weekStart, weekEnd)
        └── SELECT ... WHERE assigned_date BETWEEN weekStart AND weekEnd
    │
    ▼
WorkoutScreenState {
  overdueAssignments: [期限切れのペンディング],
  todayAssignments: [今日のアサインメント],
  weeklyData: {日付 → アサインメントリスト},
}
    │
    ▼
workout_screen.dart
  ├── WeeklyMiniCalendar(weeklyData)
  ├── OverdueAssignmentCard × N
  └── _AssignmentSection × N (既存)
```

### フロー2: 「今日やる」アクション

```
ユーザー: [今日やる] タップ
    │
    ▼
WorkoutScreenNotifier.doToday(assignmentId)
    │
    ├── 1. DB: workout_assignments UPDATE
    │       assigned_date = today, updated_at = now
    │
    └── 2. ローカルstate更新（楽観的）
            overdue → today に移動
    │
    ▼
UI自動更新: OverdueAssignmentCard が消え、_AssignmentSection に表示
```

### フロー3: 「スキップ」アクション

```
ユーザー: [スキップ] タップ
    │
    ▼
WorkoutScreenNotifier.skip(assignmentId)
    │
    ├── 1. DB: workout_assignments UPDATE
    │       status = 'skipped', updated_at = now
    │
    └── 2. ローカルstate更新（楽観的）
            overdueリストから除去
    │
    ▼
UI自動更新: OverdueAssignmentCard が消える
```

### フロー4: 「日付変更」アクション

```
ユーザー: [日付変更] タップ
    │
    ▼
RescheduleDatePicker（DatePicker表示）
    │
    ├── キャンセル → 何もしない
    │
    └── 日付選択（例: 2026-02-25）
        │
        ▼
WorkoutScreenNotifier.reschedule(assignmentId, 2026-02-25)
    │
    ├── 1. DB: workout_assignments UPDATE
    │       assigned_date = '2026-02-25', updated_at = now
    │
    └── 2. ローカルstate更新（楽観的）
            overdueリストから除去
    │
    ▼
UI自動更新: OverdueAssignmentCard が消える
（2月25日になると todayAssignments に自動表示）
```

### フロー5: 自動スキップ（Edge Function）

```
pg_cron: 毎日 AM 3:00 (UTC)
    │
    ▼
Edge Function: auto-skip-workouts
    │
    └── DB: workout_assignments UPDATE
        WHERE status = 'pending'
        AND assigned_date < (today - 3 days)
        SET status = 'skipped'
    │
    ▼
翌日のアプリ起動時: 対象アサインメントは表示されない
```

---

## 7. 実装ステップ

依存関係を考慮した実装順序:

| ステップ | タスク | 依存関係 | 担当 |
|---------|--------|---------|------|
| **Step 1** | `workout_screen_state.dart` 作成 | なし | Flutter |
| **Step 2** | `workout_repository.dart` に4メソッド追加 | なし | Flutter |
| **Step 3** | `workout_provider.dart` のリネーム・拡張 | Step 1, 2 | Flutter |
| **Step 4** | 新規Widget群の作成（WeeklyMiniCalendar, OverdueAssignmentCard, RescheduleDatePicker） | なし | Flutter |
| **Step 5** | `workout_screen.dart` のレイアウト再構成 | Step 3, 4 | Flutter |
| **Step 6** | `auto-skip-workouts` Edge Function 作成・デプロイ | なし（独立） | Backend |

**Step 1〜2 と Step 4 は並列実行可能。**
**Step 6 は他のすべてと独立して実行可能。**

### build_runner 再生成

Step 3 完了後、Provider の `.g.dart` ファイルを再生成する必要がある:

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

`TodayAssignments` → `WorkoutScreenNotifier` のリネームにより `workout_provider.g.dart` が再生成される。

---

## 8. テスト項目

### 未完了表示（7項目）

| # | テスト | 期待結果 |
|---|--------|----------|
| 1 | 過去日付のpendingアサインメントがある状態でアプリを開く | 未完了セクションにOverdueAssignmentCardが表示される |
| 2 | 未完了アサインメントの経過日数バッジを確認 | 「1日前」「2日前」のように正しく表示される |
| 3 | 未完了が0件の場合 | 未完了セクションが非表示 |
| 4 | 未完了が複数件ある場合 | assigned_date の昇順（古い順）で表示される |
| 5 | 今日のアサインメントと未完了が同時に存在 | 両方のセクションが正しく表示される |
| 6 | 全て空（今日のプランなし + 未完了なし） | 既存の空状態メッセージが表示される |
| 7 | `status = 'skipped'` のアサインメントは表示されない | 未完了セクションに含まれない |

### アクション（5項目）

| # | テスト | 期待結果 |
|---|--------|----------|
| 8 | [今日やる] タップ | 未完了カードが消え、今日のセクションにアサインメントが表示される |
| 9 | [スキップ] タップ | 未完了カードが消える。DBの `status` が `skipped` に変更される |
| 10 | [日付変更] タップ → DatePicker表示 → 日付選択 | 未完了カードが消える。DBの `assigned_date` が変更される |
| 11 | [日付変更] → キャンセル | 何も変わらない |
| 12 | 「今日やる」で移動したアサインメントの種目入力・完了報告 | 既存と同じ動作（セット記録・完了報告・フィードバック） |

### 週間カレンダー（4項目）

| # | テスト | 期待結果 |
|---|--------|----------|
| 13 | カレンダーの今日セルに枠線 | `AppColors.primary600` の枠線が表示される |
| 14 | 完了済みアサインメントのセル | `✅` アイコン + `emerald50` 背景 |
| 15 | 未完了（過去）のセル | `⏳` アイコン + `orange50` 背景 |
| 16 | 予定（未来）のセル | `🏋️` アイコン + `indigo50` 背景 |

### 自動スキップ（2項目）

| # | テスト | 期待結果 |
|---|--------|----------|
| 17 | Edge Function を手動実行（3日以上前のpendingあり） | 対象レコードの `status` が `skipped` に変更される |
| 18 | Edge Function を手動実行（3日以内のpendingのみ） | レコードが変更されない（`skippedCount: 0`） |

### 回帰テスト（1項目）

| # | テスト | 期待結果 |
|---|--------|----------|
| 19 | 今日のアサインメントの種目入力・完了報告（既存機能） | 従来通り正常に動作する |

---

## 9. リスク・注意点

### 9-1. `.g.dart` 再生成

`TodayAssignments` → `WorkoutScreenNotifier` のリネームにより、`workout_provider.g.dart` の再生成が必要。`build_runner` 実行を忘れるとコンパイルエラーになる。

### 9-2. 楽観的更新の複雑化

`WorkoutScreenState` が `overdueAssignments` と `todayAssignments` の2リストを持つため、`_updateAssignment` ヘルパーで両リストを横断更新する設計を採用。アサインメントIDがユニークであることが前提。

### 9-3. pg_cron 設定

`pg_cron` 拡張の有効化と `pg_net` 拡張（HTTP リクエスト用）の有効化が必要。Supabase Free Tier では `pg_cron` が利用可能だが、`pg_net` は Pro Plan 以上が推奨される場合がある。

**代替:** Edge Function を GitHub Actions の cron ジョブから呼び出す方式も検討可能。

### 9-4. Next.js API 側の変更は不要

既存の `PATCH /api/workout-assignments/[id]` が `assignedDate` と `status` の更新をサポートしているため、API側の変更は不要。ただし、モバイルアプリは Supabase クライアントで直接更新しており、API Route は使用していない。

### 9-5. Web 側のワークアウト画面への影響

Web側（トレーナー画面）でワークアウトアサインメントのステータスを `skipped` に設定する操作が追加される可能性がある。ただし本設計書の範囲では **Web側の変更は不要**。

### 9-6. 並列クエリのパフォーマンス

`build()` で3つのクエリを `Future.wait` で並列実行するため、個別のクエリより高速になる。ただし Supabase の同時接続数に注意（Free Tier: 200 connections）。

---

## 10. 変更しないファイル

| ファイル | 理由 |
|----------|------|
| `workout_assignment_model.dart` | モデルに変更なし（既存の `status`, `assignedDate` で対応） |
| `workout_assignment_exercise_model.dart` | 種目モデルに変更なし |
| `actual_set_model.dart` | セット記録モデルに変更なし |
| `workout_exercise_card.dart` | 種目入力UIに変更なし |
| `workout_progress_bar.dart` | プログレスバーに変更なし |
| `workout_completion_overlay.dart` | お祝いオーバーレイに変更なし |
| `message_repository.dart` | メッセージ送信に変更なし |
| `src/app/api/workout-assignments/[id]/route.ts` | 既存PATCHで status/assignedDate 更新に対応済み |
| `src/app/api/workout-assignments/route.ts` | 既存GETで期間指定取得に対応済み |
