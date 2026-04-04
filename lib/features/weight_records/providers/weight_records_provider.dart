import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/data/weight_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

part 'weight_records_provider.g.dart';

/// WeightRepositoryのProvider
@riverpod
WeightRepository weightRepository(WeightRepositoryRef ref) {
  return WeightRepository();
}

/// 体重記録リストを取得するProvider
@riverpod
class WeightRecords extends _$WeightRecords {
  @override
  Future<List<WeightRecord>> build({
    PeriodFilter period = PeriodFilter.month,
  }) async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return [];

    final repository = ref.watch(weightRepositoryProvider);
    return repository.getWeightRecords(
      clientId: clientId,
      period: period,
    );
  }

  /// 体重記録を追加
  Future<void> addRecord({
    required double weight,
    String? notes,
    DateTime? recordedAt,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) throw Exception('Client not found');

    final repository = ref.read(weightRepositoryProvider);
    await repository.createWeightRecord(
      clientId: clientId,
      weight: weight,
      notes: notes,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 体重記録を更新
  Future<void> updateRecord({
    required String id,
    double? weight,
    String? notes,
    DateTime? recordedAt,
  }) async {
    final repository = ref.read(weightRepositoryProvider);
    await repository.updateWeightRecord(
      id: id,
      weight: weight,
      notes: notes,
      recordedAt: recordedAt,
    );

    ref.invalidateSelf();
  }

  /// 体重記録を削除
  Future<void> deleteRecord(String id) async {
    final repository = ref.read(weightRepositoryProvider);
    await repository.deleteWeightRecord(id);

    ref.invalidateSelf();
  }
}

/// 最新の体重記録を取得するProvider
@riverpod
Future<WeightRecord?> latestWeightRecord(LatestWeightRecordRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return null;

  final repository = ref.watch(weightRepositoryProvider);
  return repository.getLatestWeightRecord(clientId);
}

/// 体重統計を取得するProvider
@riverpod
Future<Map<String, double>> weightStats(
  WeightStatsRef ref, {
  PeriodFilter period = PeriodFilter.month,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) {
    return {'average': 0.0, 'min': 0.0, 'max': 0.0, 'change': 0.0};
  }

  final repository = ref.watch(weightRepositoryProvider);
  return repository.getWeightStats(
    clientId: clientId,
    period: period,
  );
}
