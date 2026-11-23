import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/features/auth/data/client_repository.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';

part 'current_user_provider.g.dart';

/// 現在のクライアント情報を取得するProvider
///
/// 「行が無い」と「取得に失敗した」を区別する。呼び出し側も区別して扱うこと。
/// - clients の行が無い: `null`（未ログインのときも `null`）。
///   app.dart が「残ったセッション」とみなしてサインアウトする。
/// - 取得に失敗した（オフライン・サーバーエラー・応答の不整合など）: AsyncError。
///   行が無いとは限らないので、サインアウトさせない（再試行を促す）。
@riverpod
Future<Client?> currentClient(CurrentClientRef ref) async {
  print('[DEBUG] currentClientProvider: 開始');

  // await より前に取得しておく（await の後で ref を使わない）
  final repository = ref.watch(clientRepositoryProvider);

  // 認証状態の完了を待つ（.futureで待機することで、ローディング中はawaitされる）
  final user = await ref.watch(authNotifierProvider.future);
  print('[DEBUG] currentClientProvider: user = $user, user.id = ${user?.id}');

  if (user == null) {
    print('[DEBUG] currentClientProvider: user is null, returning null');
    return null;
  }

  try {
    print('[DEBUG] currentClientProvider: fetching client data...');
    // 行なしは null、取得失敗は例外（null にしない）。氏名・メールなど中身はログに出さない
    final client = await repository.fetchClient(user.id);
    print('[DEBUG] currentClientProvider: found = ${client != null}');
    return client;
  } catch (e) {
    print('[DEBUG] currentClientProvider: error = $e');
    // 取得失敗を「行なし」にすると、オフラインでもサインアウトされてしまうため握りつぶさない
    rethrow;
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
