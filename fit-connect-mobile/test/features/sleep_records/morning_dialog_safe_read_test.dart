import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';

/// healthSettingsProvider のフェイク。
/// build() をコンストラクタ注入の Future 関数に差し替えて、
/// SharedPreferences 依存や完了タイミングをテスト側で制御する。
class _FakeHealthSettings extends HealthSettings {
  _FakeHealthSettings(this._buildFn);

  final Future<HealthSettingsState> Function() _buildFn;

  @override
  Future<HealthSettingsState> build() => _buildFn();
}

/// initState で readMorningDialogDecision を呼び、
/// 返り値の Future をコールバックで外に渡すテストハーネス。
class _Harness extends ConsumerStatefulWidget {
  const _Harness({required this.onResult});

  final void Function(Future<bool> result) onResult;

  @override
  ConsumerState<_Harness> createState() => _HarnessState();
}

class _HarnessState extends ConsumerState<_Harness> {
  @override
  void initState() {
    super.initState();
    widget.onResult(readMorningDialogDecision(ref));
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('readMorningDialogDecision', () {
    testWidgets('読み取り中に Widget ツリーが破棄されても未処理例外を出さず false を返す',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      // healthSettings の build を未完了のまま保持する
      final completer = Completer<HealthSettingsState>();
      Future<bool>? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // client 未取得時の early return を通過させ、非同期 build 経路に入れる
            currentClientIdProvider.overrideWith((ref) => 'test-client-id'),
            healthSettingsProvider.overrideWith(
              () => _FakeHealthSettings(() => completer.future),
            ),
            todaySleepRecordProvider.overrideWith((ref) async => null),
          ],
          child: _Harness(onResult: (f) => result = f),
        ),
      );

      // completer 未完了のまま ProviderScope ごと破棄
      // （autoDispose provider が loading 中に dispose されるシナリオを再現）
      await tester.pumpWidget(const SizedBox());

      // 破棄後に healthSettings の build を完了させると、
      // morningDialogProvider の build が破棄済み container 上で再開して
      // StateError となり、provider.future へ dispose 後エラーとして届く。
      // 修正前の素の ref.read(.future) await ではこれが未処理例外になる。
      completer.complete(const HealthSettingsState(
        isEnabled: true,
        isWeightEnabled: false,
        isSleepEnabled: true,
        isMorningDialogEnabled: false,
      ));
      await tester.pump();

      expect(await result!, false);
    });

    testWidgets('読み取り中は autoDispose されず、build 完了後の判定値を返す',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      Future<bool>? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // client 未取得時の early return を通過させ、非同期 build 経路に入れる
            currentClientIdProvider.overrideWith((ref) => 'test-client-id'),
            healthSettingsProvider.overrideWith(
              () => _FakeHealthSettings(() async {
                // 非同期処理中にリスナーゼロで autoDispose されないことを検証する
                await Future<void>.delayed(const Duration(milliseconds: 50));
                return const HealthSettingsState(
                  isEnabled: true,
                  isWeightEnabled: false,
                  isSleepEnabled: true,
                  isMorningDialogEnabled: false,
                );
              }),
            ),
            todaySleepRecordProvider.overrideWith((ref) async => null),
          ],
          child: _Harness(onResult: (f) => result = f),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // isMorningDialogEnabled=false のため DateTime.now() に依存せず false
      // （例外なく build 完了値が返ることが検証点）
      expect(await result!, false);
    });
  });
}
