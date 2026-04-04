import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';

part 'current_user_provider.g.dart';

/// 現在のクライアント情報を取得するProvider
@riverpod
Future<Client?> currentClient(CurrentClientRef ref) async {
  print('[DEBUG] currentClientProvider: 開始');

  // 認証状態の完了を待つ（.futureで待機することで、ローディング中はawaitされる）
  final user = await ref.watch(authNotifierProvider.future);
  print('[DEBUG] currentClientProvider: user = $user, user.id = ${user?.id}');

  if (user == null) {
    print('[DEBUG] currentClientProvider: user is null, returning null');
    return null;
  }

  try {
    print('[DEBUG] currentClientProvider: fetching client data...');
    final response = await SupabaseService.client
        .from('clients')
        .select()
        .eq('client_id', user.id)
        .maybeSingle();

    print('[DEBUG] currentClientProvider: response = $response');
    if (response == null) return null;
    return Client.fromJson(response);
  } catch (e) {
    print('[DEBUG] currentClientProvider: error = $e');
    return null;
  }
}

/// 現在のクライアントIDを取得するProvider
@riverpod
String? currentClientId(CurrentClientIdRef ref) {
  final client = ref.watch(currentClientProvider).valueOrNull;
  return client?.clientId;
}

/// 現在のトレーナーIDを取得するProvider
@riverpod
String? currentTrainerId(CurrentTrainerIdRef ref) {
  final client = ref.watch(currentClientProvider).valueOrNull;
  return client?.trainerId;
}

/// トレーナーのプロフィール情報を取得するProvider
@riverpod
Future<Trainer?> trainerProfile(TrainerProfileRef ref) async {
  // currentClientProviderを直接watchしてtrainer_idを取得
  final client = await ref.watch(currentClientProvider.future);
  final trainerId = client?.trainerId;

  print('[DEBUG] trainerProfileProvider: trainerId = $trainerId');
  if (trainerId == null) return null;

  try {
    final response = await SupabaseService.client
        .from('trainers')
        .select()
        .eq('id', trainerId)
        .maybeSingle();
    print('[DEBUG] trainerProfileProvider: response = $response');
    if (response == null) return null;
    return Trainer.fromJson(response);
  } catch (e) {
    print('[DEBUG] trainerProfileProvider: error = $e');
    return null;
  }
}
