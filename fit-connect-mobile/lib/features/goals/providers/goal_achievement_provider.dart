import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'goal_achievement_provider.g.dart';

/// 目標達成時にお祝い画面を表示すべきかを管理するProvider
///
/// 使用方法:
/// 1. HomeScreenで `currentGoalProvider` を監視
/// 2. `goalAchievedAt` が変わったら `checkAndShowCelebration` を呼び出し
/// 3. `showCelebration` が true の場合、お祝いオーバーレイを表示
/// 4. ユーザーが閉じたら `dismissCelebration` を呼び出し
@riverpod
class GoalAchievementNotifier extends _$GoalAchievementNotifier {
  /// 最後にお祝いを表示した達成日時
  DateTime? _lastShownAchievedAt;

  @override
  bool build() => false;

  /// 達成状態をチェックし、新規達成の場合はお祝い表示状態にする
  ///
  /// [goalAchievedAt] - クライアントの goal_achieved_at フィールド
  ///
  /// 新規達成の判定条件:
  /// - goalAchievedAt が null でない（達成済み）
  /// - 以前にお祝いを表示した日時と異なる（新規達成）
  void checkAndShowCelebration(DateTime? goalAchievedAt) {
    if (goalAchievedAt != null && goalAchievedAt != _lastShownAchievedAt) {
      _lastShownAchievedAt = goalAchievedAt;
      state = true; // お祝い画面を表示
    }
  }

  /// 初回ロード時に既存の達成状態を記録（お祝い画面を表示しない）
  ///
  /// アプリ起動時に既に達成済みの場合、毎回お祝い画面が表示されるのを防ぐ
  void initializeAchievedAt(DateTime? goalAchievedAt) {
    if (goalAchievedAt != null) {
      _lastShownAchievedAt = goalAchievedAt;
    }
  }

  /// お祝い画面を閉じる
  void dismissCelebration() {
    state = false;
  }
}
