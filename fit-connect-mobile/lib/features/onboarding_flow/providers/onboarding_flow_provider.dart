import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/data/onboarding_preferences.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/data/onboarding_repository.dart';

part 'onboarding_flow_provider.g.dart';

/// OnboardingRepository のプロバイダ
@riverpod
OnboardingRepository onboardingRepository(OnboardingRepositoryRef ref) {
  return const OnboardingRepository();
}

/// はじめの3ステップカードを手動で閉じたかどうか
@riverpod
class GettingStartedCardDismissed extends _$GettingStartedCardDismissed {
  @override
  Future<bool> build() {
    return OnboardingPreferences.isGettingStartedDismissed();
  }

  /// カードを閉じる（以後表示しない）
  Future<void> dismiss() async {
    state = const AsyncData(true);
    await OnboardingPreferences.setGettingStartedDismissed();
  }
}

/// トレーナーへメッセージを送信したことがあるか（はじめの3ステップ判定用）
@riverpod
Future<bool> hasSentFirstMessage(HasSentFirstMessageRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return false;
  return ref.watch(onboardingRepositoryProvider).hasSentMessage(clientId);
}
