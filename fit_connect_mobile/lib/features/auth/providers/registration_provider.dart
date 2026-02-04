import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'registration_provider.g.dart';

/// 登録時の状態を保持するクラス
class RegistrationState {
  final String? trainerId;
  final String? trainerName;
  final String? trainerImageUrl;

  const RegistrationState({
    this.trainerId,
    this.trainerName,
    this.trainerImageUrl,
  });

  RegistrationState copyWith({
    String? trainerId,
    String? trainerName,
    String? trainerImageUrl,
  }) {
    return RegistrationState(
      trainerId: trainerId ?? this.trainerId,
      trainerName: trainerName ?? this.trainerName,
      trainerImageUrl: trainerImageUrl ?? this.trainerImageUrl,
    );
  }

  bool get hasTrainer => trainerId != null;
}

/// 登録フロー中の状態を管理するProvider
/// keepAlive: true で画面遷移時も状態を保持
@Riverpod(keepAlive: true)
class RegistrationNotifier extends _$RegistrationNotifier {
  @override
  RegistrationState build() => const RegistrationState();

  /// トレーナーIDをセット
  void setTrainerId(String trainerId) {
    state = state.copyWith(trainerId: trainerId);
  }

  /// トレーナー情報をセット
  void setTrainerInfo({
    required String name,
    String? imageUrl,
  }) {
    state = state.copyWith(
      trainerName: name,
      trainerImageUrl: imageUrl,
    );
  }

  /// トレーナーIDからSupabaseでトレーナー情報を取得
  Future<bool> fetchTrainerInfo(String trainerId) async {
    try {
      print('[fetchTrainerInfo] trainerId: $trainerId');
      print(
          "[fetchTrainerInfo] Query: SELECT id, name, profile_image_url FROM trainers WHERE id = '$trainerId'");

      final response = await SupabaseService.client
          .from('trainers')
          .select('id, name, profile_image_url')
          .eq('id', trainerId)
          .maybeSingle();

      print('[fetchTrainerInfo] response: $response');

      if (response == null) {
        return false; // トレーナーが見つからない
      }

      state = RegistrationState(
        trainerId: trainerId,
        trainerName: response['name'] as String?,
        trainerImageUrl: response['profile_image_url'] as String?,
      );
      return true;
    } catch (e) {
      print('[RegistrationNotifier] fetchTrainerInfo error: $e');
      return false;
    }
  }

  /// 登録完了処理（clientsテーブルにレコード作成）
  Future<void> completeRegistration() async {
    final trainerId = state.trainerId;
    if (trainerId == null) {
      throw Exception('Trainer ID is not set');
    }

    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('User not authenticated');
    }

    // clientsテーブルにレコード作成
    final userEmail = SupabaseService.client.auth.currentUser?.email;
    await SupabaseService.client.from('clients').insert({
      'client_id': userId,
      'trainer_id': trainerId,
      'name': '新規クライアント', // 後でプロフィール設定画面で変更可能
      'email': userEmail,
    });

    // 注意: ここでcurrentClientProviderをinvalidateしない
    // invalidateすると_AuthLoadingScreenが再ビルドされ、即座にMainScreenに遷移してしまう
    // invalidateはRegistrationCompleteScreenの_navigateToHome()で行う
  }

  /// 状態をクリア
  void clear() {
    state = const RegistrationState();
  }
}

/// QRコードURLからtrainer_idを抽出するユーティリティ
String? parseTrainerIdFromQrCode(String qrContent) {
  // 形式: fitconnectmobile://register?trainer_id={uuid}
  try {
    final uri = Uri.parse(qrContent);
    if (uri.scheme == 'fitconnectmobile' && uri.host == 'register') {
      return uri.queryParameters['trainer_id'];
    }
    // URLでない場合は、UUIDとして直接扱う
    if (_isValidUuid(qrContent)) {
      return qrContent;
    }
    return null;
  } catch (e) {
    return null;
  }
}

/// UUIDの形式チェック
bool _isValidUuid(String value) {
  final uuidRegex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  return uuidRegex.hasMatch(value);
}
