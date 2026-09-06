import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/providers/theme_provider.dart';
import 'package:fit_connect_mobile/features/home/presentation/screens/main_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/welcome_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/profile_setup_screen.dart';
import 'package:fit_connect_mobile/features/auth/presentation/screens/registration_complete_screen.dart';
import 'package:fit_connect_mobile/features/app_update/presentation/app_update_gate.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/registration_provider.dart';
import 'package:fit_connect_mobile/features/consent/data/consent_repository.dart';
import 'package:fit_connect_mobile/features/consent/presentation/consent_dialog.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/presentation/widgets/morning_wakeup_dialog.dart';
import 'package:fit_connect_mobile/shared/storage/signed_url_cache.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'FIT-CONNECT',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(themeModeNotifierProvider),
      debugShowCheckedModeBanner: false,
      // 強制アップデートゲート: 未ログイン（WelcomeScreen）にも効かせるため
      // 認証分岐の StreamBuilder より上位でラップする
      home: AppUpdateGate(
        child: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }
            final session = snapshot.data?.session;
            if (session != null) {
              // ログイン済み: クライアントデータの確認
              return const _AuthLoadingScreen();
            } else {
              // 未ログイン: オンボーディング画面へ
              return const WelcomeScreen();
            }
          },
        ),
      ),
    );
  }
}

/// 初期ローディング画面
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary600,
        ),
      ),
    );
  }
}

/// 認証後のデータ取得を待つローディング画面
class _AuthLoadingScreen extends ConsumerStatefulWidget {
  const _AuthLoadingScreen();

  @override
  ConsumerState<_AuthLoadingScreen> createState() => _AuthLoadingScreenState();
}

class _AuthLoadingScreenState extends ConsumerState<_AuthLoadingScreen>
    with WidgetsBindingObserver {
  bool _tokenSaved = false;
  bool _healthSynced = false;
  bool _consentChecked = false;
  bool _staleSessionSignOutRequested = false;
  bool _isMorningDialogOpen = false;
  Timer? _periodicSyncTimer;
  bool _isResumeSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 1時間ごとの定期同期（フォアグラウンド時のみ動作）
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 60),
      (_) => _runPeriodicSync(),
    );
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // resumed 時はSleep同期完了を待たずに即時再判定（同期は別途バックグラウンド継続）
      ref.invalidate(morningDialogProvider);
      _maybeShowMorningDialog();
      _maybeRunResumeSync();
    }
  }

  Future<void> _maybeRunResumeSync() async {
    if (_isResumeSyncing || !mounted) return;
    final settings = ref.read(healthSettingsProvider).valueOrNull;
    if (settings == null || !settings.isEnabled) return;
    final last = settings.lastSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 1)) {
      return; // まだ十分新しい
    }
    _isResumeSyncing = true;
    try {
      await ref.read(healthSyncProvider.notifier).syncOnLaunch();
      debugPrint('[App] Resume後の同期完了');
    } catch (e) {
      debugPrint('[App] Resume後の同期エラー: $e');
    } finally {
      _isResumeSyncing = false;
    }
  }

  Future<void> _runPeriodicSync() async {
    if (!mounted) return;
    final settings = ref.read(healthSettingsProvider).valueOrNull;
    if (settings == null || !settings.isEnabled) return;
    try {
      await ref.read(healthSyncProvider.notifier).syncOnLaunch();
      debugPrint('[App] 定期同期完了');
    } catch (e) {
      debugPrint('[App] 定期同期エラー: $e');
    }
  }

  Future<void> _maybeShowMorningDialog() async {
    if (_isMorningDialogOpen) return;
    if (!mounted) return;

    // 新規登録フロー中は表示しない。
    // 登録フロー中は OS の権限アラートやアプリ切替で resumed が発火し、
    // 登録フロー画面の上に root Navigator の showDialog（目覚めダイアログ）が
    // 被ってしまうため、client 取得済み（＝ホーム表示状態）かつ登録フロー外の
    // 場合のみ表示する。
    final client = ref.read(currentClientProvider).valueOrNull;
    final registrationState = ref.read(registrationNotifierProvider);
    if (client == null ||
        registrationState.hasTrainer ||
        registrationState.isRegistrationComplete) {
      return;
    }

    final shouldShow = await readMorningDialogDecision(ref);
    if (!shouldShow || !mounted || _isMorningDialogOpen) return;

    _isMorningDialogOpen = true;
    try {
      await showMorningWakeupDialog(context);
    } finally {
      _isMorningDialogOpen = false;
    }
  }

  /// 同意ゲート: 現行バージョンの規約・ポリシー・AI解析への同意が
  /// 記録されていなければ同意ダイアログを表示する。
  /// 起動セッション中1回だけ判定する（新規登録直後・既存ユーザーの初回起動・
  /// 規約改定後の再同意はすべてここでカバーされる）。
  void _checkConsentIfNeeded(String userId) {
    if (_consentChecked) return;
    _consentChecked = true;

    // build中にダイアログを開けないため、フレーム描画後に実行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runConsentGate(userId);
    });
  }

  Future<void> _runConsentGate(String userId) async {
    if (!mounted) return;

    bool hasConsent;
    try {
      hasConsent =
          await ref.read(consentRepositoryProvider).hasCurrentConsent(userId);
    } catch (e) {
      // オフライン等で判定できない場合はゲートせず通す（fail-open）
      debugPrint('[App] 同意状態の確認に失敗（fail-open）: $e');
      return;
    }

    if (hasConsent || !mounted) return;
    await showConsentDialog(context, userId: userId);
  }

  void _saveTokenIfNeeded(String clientId) {
    if (_tokenSaved) return;
    _tokenSaved = true;

    // iOS/Androidのみ
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      // FCMトークンをDBに保存（非同期で実行、UIをブロックしない）
      NotificationService.saveTokenToSupabase(clientId, 'client').then((saved) {
        print(saved ? '[App] FCMトークン保存完了' : '[App] FCMトークン保存失敗');
      }).catchError((e) {
        print('[App] FCMトークン保存エラー: $e');
      });

      // 通知タップハンドリングを設定
      NotificationService.onNotificationTap = (type, id) {
        print('[App] 通知タップ: type=$type, id=$id');
        // MainScreenのNavigatorを使ってタブ切り替え
        // 注意: MaterialAppのNavigatorContextが必要
        // 現在のcontext経由でMainScreenのStateにアクセスできないため、
        // シンプルにMainScreenを表示するだけ（タブ遷移は将来拡張）
      };
    }
  }

  /// 「セッション有り・clients 行なし・登録フロー外」の残存セッションを
  /// サインアウトして自己修復する。
  ///
  /// この分岐に到達する正当なケース（トレーナーアカウントで Mobile に
  /// ログインした、削除済みアカウントのセッションが残っている等）では、
  /// サインアウトして未ログイン状態に戻すのが正しい挙動。放置すると
  /// 「セッション残存 + clients 行なし」のままウェルカム画面が表示され、
  /// ログイン画面の挙動不整合など不可解な状態になる。
  ///
  /// ビルド中に副作用を起こさないよう post-frame で一度だけ実行する。
  /// サインアウト完了後は onAuthStateChange 経由で MyApp の StreamBuilder が
  /// 未ログイン側（WelcomeScreen）を表示する。
  void _signOutStaleSessionIfNeeded() {
    if (_staleSessionSignOutRequested) return;
    _staleSessionSignOutRequested = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // fire-and-forget: 失敗してもUIをブロックしない
      Supabase.instance.client.auth.signOut().then((_) {
        SignedUrlCache.instance.clear(); // 署名URLキャッシュも破棄
        debugPrint('[App] clients 行のない残存セッションをサインアウトしました');
      }).catchError((e) {
        debugPrint('[App] 残存セッションのサインアウトに失敗: $e');
      });
    });
  }

  void _syncHealthDataIfNeeded() {
    if (_healthSynced) return;
    _healthSynced = true;

    // 同期完了後に朝ダイアログ判定をトリガ（spec §5-C レースコンディション対策）
    ref.read(healthSyncProvider.notifier).syncOnLaunch().then((_) {
      debugPrint('[App] HealthKit同期完了');
      ref.invalidate(morningDialogProvider);
      _maybeShowMorningDialog();
    }).catchError((e) {
      debugPrint('[App] HealthKit同期エラー: $e');
      // 同期失敗でも DB上の手動評価のみで判定可能なのでダイアログトライ
      _maybeShowMorningDialog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final clientAsync = ref.watch(currentClientProvider);
    final registrationState = ref.watch(registrationNotifierProvider);

    return clientAsync.when(
      data: (client) {
        if (client != null) {
          // FCMトークン保存（MainScreen表示前）
          _saveTokenIfNeeded(client.clientId);
          _syncHealthDataIfNeeded();
          // 同意ゲート（client_id は auth.uid と同一）
          _checkConsentIfNeeded(client.clientId);
          // クライアントデータあり → MainScreenへ
          return const MainScreen();
        } else if (registrationState.isRegistrationComplete) {
          // 登録完了 → 登録完了画面へ
          return const RegistrationCompleteScreen();
        } else if (registrationState.hasTrainer) {
          // クライアントデータなし＆登録フロー中 → プロフィール設定画面へ
          return const ProfileSetupScreen();
        } else {
          // クライアントデータなし＆登録フローなし
          // （認証済みだがクライアント登録がない状態）
          // → 残存セッションをサインアウトして未ログイン状態へ自己修復
          _signOutStaleSessionIfNeeded();
          return const WelcomeScreen();
        }
      },
      loading: () {
        // ローディング中
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(
                  color: AppColors.primary600,
                ),
                const SizedBox(height: 16),
                Text(
                  '読み込み中...',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      error: (error, stack) {
        // エラー時: 登録フロー中ならプロフィール設定画面、そうでなければオンボーディング
        if (registrationState.hasTrainer) {
          return const ProfileSetupScreen();
        }
        // セッション有り・client 取得不能・登録フロー外 → 残存セッションを
        // サインアウトして未ログイン状態へ自己修復（data 分岐の else と同様）
        _signOutStaleSessionIfNeeded();
        return const WelcomeScreen();
      },
    );
  }
}
