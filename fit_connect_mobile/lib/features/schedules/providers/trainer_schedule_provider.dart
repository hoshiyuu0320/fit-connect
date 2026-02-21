import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/schedules/models/trainer_schedule_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'trainer_schedule_provider.g.dart';

/// トレーナーのスケジュール一覧を取得するProvider
@riverpod
Future<List<TrainerSchedule>> trainerSchedules(TrainerSchedulesRef ref) async {
  final trainerId = ref.watch(currentTrainerIdProvider);
  if (trainerId == null) return [];

  final response = await SupabaseService.client
      .from('trainer_schedules')
      .select()
      .eq('trainer_id', trainerId)
      .order('day_of_week', ascending: true);

  return (response as List)
      .map((json) => TrainerSchedule.fromJson(json))
      .toList();
}

/// トレーナーの現在の稼働状態を判定するProvider
/// - スケジュール未設定 → true（常時オン扱い）
/// - 今日のスケジュールなし or is_available=false → false
/// - start_time〜end_time内 → true
@riverpod
bool trainerCurrentStatus(TrainerCurrentStatusRef ref) {
  final schedules = ref.watch(trainerSchedulesProvider).valueOrNull;

  // スケジュール未設定の場合は常時オン扱い
  if (schedules == null || schedules.isEmpty) return true;

  final now = DateTime.now();
  final currentDayOfWeek = now.weekday % 7; // 日=0, 月=1, ..., 土=6

  // 今日のスケジュールを取得
  final todaySchedules =
      schedules.where((s) => s.dayOfWeek == currentDayOfWeek).toList();

  if (todaySchedules.isEmpty) return false;

  // 複数スケジュールがある場合は、いずれか1つでも稼働中ならtrue
  final nowTime =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:00';

  for (final schedule in todaySchedules) {
    if (!schedule.isAvailable) continue;

    final isInTimeRange = nowTime.compareTo(schedule.startTime) >= 0 &&
        nowTime.compareTo(schedule.endTime) < 0;

    if (isInTimeRange) return true;
  }

  return false;
}
