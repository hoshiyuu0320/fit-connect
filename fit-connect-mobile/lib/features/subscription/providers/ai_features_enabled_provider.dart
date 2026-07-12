import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_features_enabled_provider.g.dart';

/// 自身の担当トレーナーが解決できるかどうか（AI機能のUIゲート）。
/// - 担当トレーナーが解決できれば true（Freeプランにも月次クォータ内でAIが
///   開放されたため、プラン文字列による出し分けは行わない）
/// - 取得失敗・未認証・未紐付け → false（保守的にAI非表示）
///
/// クォータ制御はサーバー側（Edge Function の 429 応答）が実体。
/// このUIゲートは将来のkill switch（AI機能の全停止）用に残している。
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id
// TODO(stage 2): subscribe to auth.onAuthStateChange to invalidate on sign-in/out, and
//                handle subscription_plan changes (Stripe webhook) to flip the gate live.
@Riverpod(keepAlive: true)
Future<bool> aiFeaturesEnabled(AiFeaturesEnabledRef ref) async {
  try {
    final supabase = SupabaseService.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (kDebugMode) debugPrint('[aiFeaturesEnabled] no auth user → false');
      return false;
    }

    final clientRow = await supabase
        .from('clients')
        .select('trainer_id')
        .eq('client_id', user.id)
        .maybeSingle();
    final trainerId = clientRow?['trainer_id'] as String?;
    if (trainerId == null) {
      if (kDebugMode) debugPrint('[aiFeaturesEnabled] no trainer_id for client ${user.id} → false');
      return false;
    }

    if (kDebugMode) {
      debugPrint('[aiFeaturesEnabled] trainer=$trainerId → true');
    }
    return true;
  } catch (e, st) {
    if (kDebugMode) debugPrint('[aiFeaturesEnabled] error: $e\n$st');
    return false;
  }
}
