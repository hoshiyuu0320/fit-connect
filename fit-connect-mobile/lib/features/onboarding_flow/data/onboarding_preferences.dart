import 'package:shared_preferences/shared_preferences.dart';

/// オンボーディング後段フロー関連の SharedPreferences キーとアクセサ
///
/// - はじめの3ステップカードの非表示フラグはローカルのみ（cat2 3-B）
class OnboardingPreferences {
  OnboardingPreferences._();

  /// オンボーディング後段フローを完了（または全スキップ）したか
  static const String keyFlowCompleted = 'onboarding_flow_completed';

  /// はじめの3ステップカードを手動で閉じたか
  static const String keyGettingStartedDismissed =
      'getting_started_card_dismissed';

  static Future<bool> isFlowCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyFlowCompleted) ?? false;
  }

  static Future<void> setFlowCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyFlowCompleted, true);
  }

  static Future<bool> isGettingStartedDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyGettingStartedDismissed) ?? false;
  }

  static Future<void> setGettingStartedDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyGettingStartedDismissed, true);
  }
}
