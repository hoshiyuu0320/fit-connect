import 'package:flutter/foundation.dart' show debugPrint;
import 'package:fit_connect_mobile/features/onboarding_flow/data/onboarding_preferences.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

/// オンボーディング後段フローの完了記録を担うリポジトリ
class OnboardingRepository {
  const OnboardingRepository();

  /// フロー完了を記録する
  ///
  /// 1. SharedPreferences にローカルフラグを保存
  /// 2. clients.onboarding_completed_at を now() で更新（本人 RLS 経由）
  ///
  /// DB 更新の失敗はログのみで握りつぶす（フロー完了自体は妨げない）。
  Future<void> markFlowCompleted() async {
    try {
      await OnboardingPreferences.setFlowCompleted();
    } catch (e) {
      debugPrint('[OnboardingRepository] ローカルフラグ保存エラー（無視）: $e');
    }

    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[OnboardingRepository] 未認証のため onboarding_completed_at 更新スキップ');
        return;
      }
      await SupabaseService.client.from('clients').update({
        'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('client_id', userId);
      debugPrint('[OnboardingRepository] onboarding_completed_at 更新完了');
    } catch (e) {
      debugPrint('[OnboardingRepository] onboarding_completed_at 更新エラー（無視）: $e');
    }
  }

  /// 自分がトレーナーへメッセージを送信したことがあるか
  Future<bool> hasSentMessage(String clientId) async {
    try {
      final rows = await SupabaseService.client
          .from('messages')
          .select('id')
          .eq('sender_id', clientId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      debugPrint('[OnboardingRepository] メッセージ送信履歴取得エラー: $e');
      return false;
    }
  }
}
