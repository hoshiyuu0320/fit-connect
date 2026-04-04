import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/exercise_records/data/exercise_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

part 'exercise_records_provider.g.dart';

/// ExerciseRepositoryのProvider
@riverpod
ExerciseRepository exerciseRepository(ExerciseRepositoryRef ref) {
  return ExerciseRepository();
}

/// 運動記録リストを取得するProvider
@riverpod
class ExerciseRecords extends _$ExerciseRecords {
  @override
  Future<List<ExerciseRecord>> build({
    PeriodFilter period = PeriodFilter.month,
    String? exerciseType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return [];

    final repository = ref.watch(exerciseRepositoryProvider);
    return repository.getExerciseRecords(
      clientId: clientId,
      period: period,
      exerciseType: exerciseType,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 運動記録を追加
  Future<void> addRecord({
    required String exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) throw Exception('Client not found');

    final repository = ref.read(exerciseRepositoryProvider);
    await repository.createExerciseRecord(
      clientId: clientId,
      exerciseType: exerciseType,
      memo: memo,
      images: images,
      duration: duration,
      distance: distance,
      calories: calories,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 運動記録を更新
  Future<void> updateRecord({
    required String id,
    String? exerciseType,
    String? memo,
    List<String>? images,
    int? duration,
    double? distance,
    double? calories,
    DateTime? recordedAt,
  }) async {
    final repository = ref.read(exerciseRepositoryProvider);
    await repository.updateExerciseRecord(
      id: id,
      exerciseType: exerciseType,
      memo: memo,
      images: images,
      duration: duration,
      distance: distance,
      calories: calories,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 運動記録を削除
  Future<void> deleteRecord(String id) async {
    final repository = ref.read(exerciseRepositoryProvider);
    await repository.deleteExerciseRecord(id);

    ref.invalidateSelf();
  }
}

/// 今週の運動回数を取得するProvider
@riverpod
Future<int> weeklyExerciseCount(WeeklyExerciseCountRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return 0;

  final repository = ref.watch(exerciseRepositoryProvider);
  return repository.getWeeklyExerciseCount(clientId);
}

/// 運動タイプ別カウントを取得するProvider
@riverpod
Future<Map<String, int>> exerciseTypeCounts(
  ExerciseTypeCountsRef ref, {
  PeriodFilter period = PeriodFilter.month,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return {};

  final repository = ref.watch(exerciseRepositoryProvider);
  return repository.getExerciseTypeCounts(
    clientId: clientId,
    period: period,
    startDate: startDate,
    endDate: endDate,
  );
}

/// 週間カレンダー用の運動データを取得するProvider
@riverpod
Future<Map<DateTime, List<String>>> weeklyExerciseData(
  WeeklyExerciseDataRef ref, {
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return {};

  final repository = ref.watch(exerciseRepositoryProvider);
  return repository.getWeeklyExerciseData(
    clientId: clientId,
    startDate: startDate,
    endDate: endDate,
  );
}

/// 月カレンダー用の日別運動回数を取得するProvider
@riverpod
Future<Map<DateTime, int>> exerciseRecordCounts(
  ExerciseRecordCountsRef ref, {
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return {};

  final repository = ref.watch(exerciseRepositoryProvider);
  return repository.getExerciseRecordCounts(
    clientId: clientId,
    startDate: startDate,
    endDate: endDate,
  );
}

/// 期間内の消費カロリー合計を取得するProvider
@riverpod
Future<double> exerciseTotalCalories(
  ExerciseTotalCaloriesRef ref, {
  PeriodFilter period = PeriodFilter.month,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return 0;

  final repository = ref.watch(exerciseRepositoryProvider);
  return repository.getTotalCalories(
    clientId: clientId,
    period: period,
    startDate: startDate,
    endDate: endDate,
  );
}
