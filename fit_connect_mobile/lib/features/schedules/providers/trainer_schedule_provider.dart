import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/schedules/models/trainer_schedule_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'trainer_schedule_provider.g.dart';

/// トレーナーのプレゼンス（オンライン状態）を表すクラス
class TrainerPresence {
  final bool isOnline;
  final DateTime? lastSeenAt;

  const TrainerPresence({
    required this.isOnline,
    this.lastSeenAt,
  });
}

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

/// トレーナーのプレゼンス（オンライン状態）を Realtime で監視する Notifier
@riverpod
class TrainerPresenceNotifier extends _$TrainerPresenceNotifier {
  RealtimeChannel? _channel;

  @override
  TrainerPresence build() {
    // trainerProfileProvider から初期値を取得
    final trainer = ref.watch(trainerProfileProvider).valueOrNull;

    // Realtime subscription をセットアップ
    _setupRealtimeChannel();

    // dispose 時にチャンネルをクリーンアップ
    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });

    return TrainerPresence(
      isOnline: trainer?.isOnline ?? false,
      lastSeenAt: trainer?.lastSeenAt,
    );
  }

  void _setupRealtimeChannel() {
    final trainerId = ref.read(currentTrainerIdProvider);
    if (trainerId == null) return;

    _channel = SupabaseService.client
        .channel('trainer-presence:$trainerId');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'trainers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: trainerId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            state = TrainerPresence(
              isOnline: newRecord['is_online'] as bool? ?? false,
              lastSeenAt: newRecord['last_seen_at'] != null
                  ? DateTime.parse(newRecord['last_seen_at'] as String).toLocal()
                  : null,
            );
          },
        )
        .subscribe();
  }
}

/// トレーナーの現在の稼働状態を返すProvider（後方互換用）
///
/// 既存の UI で `trainerCurrentStatusProvider` を使っている箇所に影響を与えない。
@riverpod
bool trainerCurrentStatus(TrainerCurrentStatusRef ref) {
  return ref.watch(trainerPresenceNotifierProvider).isOnline;
}
