import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_features_enabled_provider.g.dart';

/// 自身の担当トレーナーの subscription_plan が 'pro' かどうか。
/// 取得失敗・未認証・未紐付けの場合は false を返す（保守的にAI非表示）。
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id → trainers.subscription_plan
// TODO(stage 2): subscribe to auth.onAuthStateChange to invalidate on sign-in/out, and
//                handle subscription_plan changes (Stripe webhook) to flip the gate live.
@riverpod
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

    final trainerRow = await supabase
        .from('trainers')
        .select('subscription_plan')
        .eq('id', trainerId)
        .maybeSingle();
    final plan = trainerRow?['subscription_plan'] as String?;
    final enabled = plan == 'pro';
    if (kDebugMode) debugPrint('[aiFeaturesEnabled] trainer=$trainerId plan=$plan → $enabled');
    return enabled;
  } catch (e, st) {
    if (kDebugMode) debugPrint('[aiFeaturesEnabled] error: $e\n$st');
    return false;
  }
}
