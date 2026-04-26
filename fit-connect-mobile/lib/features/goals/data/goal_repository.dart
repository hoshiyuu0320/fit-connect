import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class GoalRepository {
  final _supabase = SupabaseService.client;

  /// クライアント情報（目標含む）を取得
  Future<Client?> getClientGoal(String clientId) async {
    final response = await _supabase
        .from('clients')
        .select()
        .eq('client_id', clientId)
        .maybeSingle();

    if (response == null) return null;
    return Client.fromJson(response);
  }

  /// 目標達成率を計算
  Future<double> calculateAchievementRate({
    required String clientId,
    required double currentWeight,
  }) async {
    final result = await _supabase.rpc(
      'calculate_achievement_rate',
      params: {
        'p_client_id': clientId,
        'p_current_weight': currentWeight,
      },
    );

    return (result as num).toDouble();
  }

  /// 目標達成判定
  Future<bool> checkGoalAchievement({
    required String clientId,
    required double currentWeight,
  }) async {
    final result = await _supabase.rpc(
      'check_goal_achievement',
      params: {
        'p_client_id': clientId,
        'p_current_weight': currentWeight,
      },
    );

    return result as bool;
  }

  /// 目標情報を更新（トレーナー側で使用）
  Future<Client> updateGoal({
    required String clientId,
    double? initialWeight,
    double? targetWeight,
    DateTime? goalDeadline,
    String? goalDescription,
  }) async {
    final updateData = <String, dynamic>{};
    if (initialWeight != null) updateData['initial_weight'] = initialWeight;
    if (targetWeight != null) updateData['target_weight'] = targetWeight;
    if (goalDeadline != null) {
      updateData['goal_deadline'] = goalDeadline.toIso8601String();
    }
    if (goalDescription != null)
      updateData['goal_description'] = goalDescription;

    // 目標を更新した場合は goal_set_at を更新し、達成フラグをクリア
    if (updateData.isNotEmpty) {
      updateData['goal_set_at'] = DateTime.now().toIso8601String();
      updateData['goal_achieved_at'] = null;
    }

    final response = await _supabase
        .from('clients')
        .update(updateData)
        .eq('client_id', clientId)
        .select()
        .single();

    return Client.fromJson(response);
  }

  /// 目標達成フラグを手動でクリア
  Future<void> clearGoalAchievement(String clientId) async {
    await _supabase
        .from('clients')
        .update({'goal_achieved_at': null}).eq('client_id', clientId);
  }

  /// 目標達成までの残り日数を計算
  int? getDaysUntilDeadline(Client client) {
    if (client.goalDeadline == null) return null;

    final now = DateTime.now();
    final deadline = client.goalDeadline!;
    final difference = deadline.difference(now).inDays;

    return difference;
  }

  /// 目標達成までの残り体重を計算
  double? getRemainingWeight(Client client, double currentWeight) {
    if (client.targetWeight == null) return null;

    return (currentWeight - client.targetWeight!).abs();
  }

  /// 開始時からの変化量を計算
  double? getWeightChange(Client client, double currentWeight) {
    if (client.initialWeight == null) return null;

    return client.initialWeight! - currentWeight;
  }
}
