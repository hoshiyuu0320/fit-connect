import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_features_enabled_provider.g.dart';

/// 自身の担当トレーナーがAI機能を利用可能かどうか（実効プラン判定）。
/// - subscription_plan が 'pro' または 'business' → 利用可
/// - 'free' でも trial_ends_at が現在より未来（トライアル中・Pro相当） → 利用可
/// - それ以外・取得失敗・未認証・未紐付け → false（保守的にAI非表示）
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id
///           → trainers.subscription_plan / trainers.trial_ends_at
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

    final trainerRow = await supabase
        .from('trainers')
        .select('subscription_plan, trial_ends_at')
        .eq('id', trainerId)
        .maybeSingle();
    final plan = trainerRow?['subscription_plan'] as String?;
    final trialEndsAtRaw = trainerRow?['trial_ends_at'] as String?;
    final trialEndsAt =
        trialEndsAtRaw != null ? DateTime.tryParse(trialEndsAtRaw) : null;
    final isPaidPlan = plan == 'pro' || plan == 'business';
    final isTrialActive =
        trialEndsAt != null && trialEndsAt.isAfter(DateTime.now());
    final enabled = isPaidPlan || isTrialActive;
    if (kDebugMode) {
      debugPrint(
        '[aiFeaturesEnabled] trainer=$trainerId plan=$plan '
        'trialEndsAt=$trialEndsAtRaw → $enabled',
      );
    }
    return enabled;
  } catch (e, st) {
    if (kDebugMode) debugPrint('[aiFeaturesEnabled] error: $e\n$st');
    return false;
  }
}
