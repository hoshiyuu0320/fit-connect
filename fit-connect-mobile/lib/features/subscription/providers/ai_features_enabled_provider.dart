import 'package:fit_connect_mobile/services/supabase_service.dart';
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
    if (user == null) return false;

    final clientRow = await supabase
        .from('clients')
        .select('trainer_id')
        .eq('client_id', user.id)
        .maybeSingle();
    final trainerId = clientRow?['trainer_id'] as String?;
    if (trainerId == null) return false;

    final trainerRow = await supabase
        .from('trainers')
        .select('subscription_plan')
        .eq('id', trainerId)
        .maybeSingle();
    return (trainerRow?['subscription_plan'] as String?) == 'pro';
  } catch (_) {
    // どんな失敗（ネットワーク・RLS拒否・型キャスト）でも false を返す（dartdoc の契約）
    return false;
  }
}
