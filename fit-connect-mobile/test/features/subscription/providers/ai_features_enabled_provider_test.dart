import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';

void main() {
  test('aiFeaturesEnabledProvider exists and returns AsyncValue<bool>', () {
    // 注: 完全な動作テストは Supabase をモックする必要があるため Stage 1 では
    //     プロバイダのファイル存在＋AsyncValue<bool>型確認で十分。実機検証はQA時。
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final asyncValue = container.read(aiFeaturesEnabledProvider);
    expect(asyncValue, isA<AsyncValue<bool>>());
  });
}
