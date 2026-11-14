import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// クライアント情報（自分の `clients` 行）を読み込めなかったときの全画面表示。
///
/// ログイン済みなのに `clients` の取得が失敗した場面（オフライン・通信エラー・サーバーの
/// 一時的な不調など）で出す。失敗は「行が無い」ことを意味しない（取れていないだけ）ので、
/// **サインアウトしない**。代わりに、手動の「再試行」・一定間隔の自動再試行・
/// 逃げ道の「ログアウト」（確認ダイアログあり）を出す。
///
/// Riverpod には依存しない。読み込み中か（[isRetrying]）と、再試行・ログアウトの処理
/// （[onRetry] / [onSignOut]）は呼び出し側から受ける。
///
/// 自動再試行:
/// - [autoRetryInterval]（既定 [defaultAutoRetryInterval] = 15 秒）ごとに [onRetry] を呼ぶ
/// - [isRetrying] が true の間は呼ばない（読み込みを重ねない）
/// - アプリがバックグラウンドの間（`AppLifecycleState.resumed` 以外）は呼ばない。
///   前面に戻ったあと、次の周期から再開する
/// - ログアウトの確認ダイアログを開いている間は呼ばない。閉じたあと、次の周期から再開する
///   （再試行が成功して画面が差し替わると、確認している操作の足元が変わってしまうため）
/// - 画面が外れるとタイマーも止まる。[autoRetryInterval] が変わったら張り直す
///
/// 文字拡大や小さい画面では、全体をスクロールして収める（縮めない）。
class ClientLoadErrorView extends StatefulWidget {
  const ClientLoadErrorView({
    super.key,
    required this.isRetrying,
    required this.onRetry,
    required this.onSignOut,
    this.autoRetryInterval = defaultAutoRetryInterval,
  });

  /// 自動再試行の既定の間隔
  static const Duration defaultAutoRetryInterval = Duration(seconds: 15);

  /// 読み込み中か。true の間は「再試行」を読み込み表示にして押せなくし、自動再試行もしない
  final bool isRetrying;

  /// 再試行する（手動の「再試行」と自動再試行の両方から呼ばれる）
  final VoidCallback onRetry;

  /// ログアウトする。確認ダイアログで「ログアウト」が選ばれたときだけ呼ばれる。
  ///
  /// 確認を待つ間にこの画面が外れていても（再試行が成功して差し替わった等）、
  /// 「ログアウト」が選ばれたなら呼ばれる（確認された操作を黙って捨てない）。
  /// 外れたあとに呼ばれうるので、呼び出し側が自分の状態（mounted など）を確かめること
  final Future<void> Function() onSignOut;

  /// 自動再試行の間隔。0 以下なら自動再試行しない
  final Duration autoRetryInterval;

  @override
  State<ClientLoadErrorView> createState() => _ClientLoadErrorViewState();
}

class _ClientLoadErrorViewState extends State<ClientLoadErrorView> {
  Timer? _autoRetryTimer;

  /// ログアウトの確認ダイアログを開いている間は true。この間は自動再試行しない
  bool _isConfirmingSignOut = false;

  @override
  void initState() {
    super.initState();
    _startAutoRetryTimer();
  }

  @override
  void didUpdateWidget(ClientLoadErrorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoRetryInterval != widget.autoRetryInterval) {
      _startAutoRetryTimer();
    }
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  /// 自動再試行のタイマーを（張り直して）始める
  void _startAutoRetryTimer() {
    _autoRetryTimer?.cancel();
    _autoRetryTimer = null;
    // 0 以下の間隔だと周期タイマーが間を置かずに回り続けるので、自動再試行を使わない扱いにする
    if (widget.autoRetryInterval <= Duration.zero) return;
    _autoRetryTimer = Timer.periodic(
      widget.autoRetryInterval,
      (_) => _onAutoRetryTick(),
    );
  }

  void _onAutoRetryTick() {
    // 読み込み中は重ねて呼ばない
    if (widget.isRetrying) return;

    // ログアウトの確認ダイアログを開いている間は呼ばない（成功して画面が差し替わらないように）
    if (_isConfirmingSignOut) return;

    // バックグラウンドでは通信しない。状態がまだ分からない（null）間は前面として扱う
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    widget.onRetry();
  }

  /// ログアウトの確認ダイアログを出し、「ログアウト」が選ばれたときだけ
  /// [ClientLoadErrorView.onSignOut] を呼ぶ（文言・色は設定画面のログアウトと同じ）。
  ///
  /// 確認を待つ間にこの画面が外れても（再試行が成功して差し替わった等）、
  /// 「ログアウト」が選ばれたなら呼ぶ。確認された操作を黙って捨てない。
  /// 外れたあとに実行してよいかは、呼び出し側が自分の状態で確かめる。
  Future<void> _confirmSignOut() async {
    // 確認している間は自動再試行しない（成功して画面が差し替わらないように）。
    // どう閉じても（失敗しても）下ろす
    _isConfirmingSignOut = true;
    final bool? confirmed;
    try {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ログアウト'),
          content: const Text('ログアウトしますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'キャンセル',
                style:
                    TextStyle(color: AppColors.of(dialogContext).textSecondary),
              ),
            ),
            TextButton(
              // ダイアログを閉じてから onSignOut を呼ぶ（下の await の後）
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'ログアウト',
                style: TextStyle(
                  color: AppColors.of(dialogContext).error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      _isConfirmingSignOut = false;
    }

    // キャンセルや枠外タップは null / false
    if (confirmed != true) return;

    // この画面が外れていても呼ぶ（mounted を見て捨てない）。
    // ログアウトの失敗（通信エラーなど）の扱いは呼び出し側に任せる。
    // ここでは握りつぶさず、そのまま伝える
    await widget.onSignOut();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);

    return Scaffold(
      body: SafeArea(
        // 文字拡大・小さい画面では、全体がスクロールして収まる（縮めない）。
        // 余りの高さは spaceBetween で配る（IntrinsicHeight や SliverFillRemaining は
        // 中の FcButton が LayoutBuilder を使うので置けない）
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    AppSpacing.xl,
                    horizontal,
                    AppSpacing.xxl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 余りを「上の空き」と「メッセージと操作の間」に均等に配るための空きの枠。
                      // これでメッセージが、操作より上の領域の中央に来る
                      const SizedBox.shrink(),

                      const FcStateMessage.error(
                        title: 'ユーザー情報を読み込めませんでした',
                        message: '通信状況を確認してください。つながると自動で読み込み直します。',
                      ),

                      // 操作（下部）。メッセージとの間は最低でも xl 空ける
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FcButton.block(
                              label: '再試行',
                              icon: LucideIcons.refreshCw,
                              loading: widget.isRetrying,
                              loadingLabel: '読み込み中…',
                              onPressed: widget.onRetry,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            // 控えめな逃げ道。横幅いっぱいにせず中央に置く
                            Center(
                              child: FcButton.text(
                                label: 'ログアウト',
                                expand: false,
                                onPressed: () => unawaited(_confirmSignOut()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビューの最中に自動再試行が走らないよう、間隔を長くする
const Duration _previewAutoRetryInterval = Duration(hours: 1);

@Preview(name: 'ClientLoadErrorView - Light')
Widget previewClientLoadErrorViewLight() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: ClientLoadErrorView(
      isRetrying: false,
      onRetry: () {},
      onSignOut: () async {},
      autoRetryInterval: _previewAutoRetryInterval,
    ),
  );
}

@Preview(name: 'ClientLoadErrorView - Dark')
Widget previewClientLoadErrorViewDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: ClientLoadErrorView(
      isRetrying: false,
      onRetry: () {},
      onSignOut: () async {},
      autoRetryInterval: _previewAutoRetryInterval,
    ),
  );
}

/// 再試行中: 「再試行」が「読み込み中…」になり、押せない
@Preview(name: 'ClientLoadErrorView - Retrying')
Widget previewClientLoadErrorViewRetrying() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: ClientLoadErrorView(
      isRetrying: true,
      onRetry: () {},
      onSignOut: () async {},
      autoRetryInterval: _previewAutoRetryInterval,
    ),
  );
}

/// 文字拡大 1.35: メッセージが折り返して縦に伸び、横にはみ出さない
@Preview(name: 'ClientLoadErrorView - Large Text')
Widget previewClientLoadErrorViewLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: ClientLoadErrorView(
      isRetrying: false,
      onRetry: () {},
      onSignOut: () async {},
      autoRetryInterval: _previewAutoRetryInterval,
    ),
  );
}
