import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/app_update/presentation/force_update_dialog.dart';
import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';

/// 起動時に app_config の最低サポートバージョンを確認し、
/// 要更新なら強制アップデートダイアログを重ねるゲート Widget。
///
/// MyApp.build の StreamBuilder より上位（home 直下）に置くことで、
/// 未ログイン（WelcomeScreen）にも効く。判定はバックグラウンドで行い、
/// [child] の表示は一切ブロックしない。
/// オフライン・取得失敗・タイムアウト時は fail-open（通常起動）。
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  /// 多重チェック・多重表示ガード（起動時1回のみ判定する）
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForceUpdate());
  }

  Future<void> _checkForceUpdate() async {
    if (_updateChecked || !mounted) return;
    _updateChecked = true;

    try {
      // 3秒以内に判定できなければ fail-open（起動を待たせない）
      final config = await ref
          .read(forceUpdateProvider.future)
          .timeout(const Duration(seconds: 3));
      if (config == null || !mounted) return;

      // 要更新: 閉じられないダイアログでブロックする
      await showForceUpdateDialog(context, config: config);
    } catch (_) {
      // オフライン・取得失敗・タイムアウトは fail-open（通常起動）
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
