import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/core/providers/theme_provider.dart';
import 'package:fit_connect_mobile/features/app_update/providers/force_update_provider.dart';
import 'package:fit_connect_mobile/features/auth/data/client_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/consent/legal_links.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/features/settings/providers/notification_preferences_provider.dart';
import 'package:fit_connect_mobile/services/storage_service.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

/// 設定タブ。
///
/// 正本: Claude Design の `more-screens.js` `SettingsScreen`。
/// 見出し「設定」→ プロフィールカード → 外観 / 通知 / ヘルスケア連携 / 法的情報 / アカウントを
/// 「グループ名（13・secondary）＋ 行を並べたカード」で縦に積み、末尾にバージョンを置く。
/// 機能（写真・名前の変更、テーマ切替、通知のオン/オフ、ヘルスケア設定への遷移、
/// 規約リンク、ログアウト、アカウント削除）は現行のまま。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageH = AppSpacing.pageHorizontalOf(context);
    // ナビ（FcBottomNavLayout）が確保する下余白。内容はすりガラスのナビの下まで潜れるようにして、
    // スクロールの終端でナビの上に収まる（ホーム・記録と同じ。ナビのための余白は別に足さない）
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pageH, 4, pageH, bottomInset),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FcPageHeading(title: '設定'),
              _ProfileSection(),
              _GroupLabel('外観'),
              _AppearanceSection(),
              _GroupLabel('通知'),
              _NotificationSection(),
              _HealthSection(),
              _GroupLabel('法的情報'),
              _LegalSection(),
              _GroupLabel('アカウント'),
              _AccountSection(),
              _VersionCaption(),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// 共通パーツ
// ============================================

/// グループ名（13・secondary）。正本 `GroupLabel`: `margin: 10px 4px -8px`
/// ＝ 前のカードとの間 16 + 10、次のカードとの間 16 - 8。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        4,
        AppSpacing.cardGap + 10,
        4,
        AppSpacing.cardGap - 8,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTextStyles.supplement(context)),
      ),
    );
  }
}

// ============================================
// プロフィール
// ============================================

/// プロフィールカード（読み込み・失敗・取得済みの出し分け）
class _ProfileSection extends ConsumerWidget {
  const _ProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientAsync = ref.watch(currentClientProvider);
    final trainerAsync = ref.watch(trainerProfileProvider);

    return clientAsync.when(
      data: (client) {
        if (client == null) {
          return FcInlineNotice.error(
            message: 'ユーザー情報を読み込めませんでした',
            actionLabel: '再試行',
            onAction: () => ref.invalidate(currentClientProvider),
          );
        }
        return _ProfileCard(
          name: client.name,
          email: client.email,
          avatar: _ProfileAvatar(
            name: client.name,
            imageValue: client.profileImageUrl,
          ),
          trainer: trainerAsync.when(
            data: (trainer) => _TrainerValue.name(trainer?.name),
            loading: _TrainerValue.loading,
            error: (_, __) => const _TrainerValue.failed(),
          ),
          onChangePhoto: () => _showProfileImagePicker(
            context,
            ref,
            client.clientId,
          ),
          onEditName: () => _showEditNameDialog(
            context,
            ref,
            client.clientId,
            client.name,
          ),
        );
      },
      loading: () => const _ProfileCardSkeleton(),
      error: (error, _) => FcInlineNotice.error(
        message: 'ユーザー情報を読み込めませんでした',
        actionLabel: '再試行',
        onAction: () => ref.invalidate(currentClientProvider),
      ),
    );
  }
}

/// 担当トレーナー行の値（取得済み / 読込中 / 失敗）
class _TrainerValue extends StatelessWidget {
  const _TrainerValue.name(this.trainerName)
      : _loading = false,
        _failed = false;

  const _TrainerValue.loading()
      : trainerName = null,
        _loading = true,
        _failed = false;

  const _TrainerValue.failed()
      : trainerName = null,
        _loading = false,
        _failed = true;

  final String? trainerName;
  final bool _loading;
  final bool _failed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading) {
      return Semantics(
        label: '読み込み中',
        child: const FcSkeleton.line(width: 96, height: 18),
      );
    }
    if (_failed) {
      return Text(
        '読み込めませんでした',
        textAlign: TextAlign.end,
        style: AppTextStyles.supplement(context),
      );
    }
    // 名前は「田中」でも「田中トレーナー」でも同じ「田中トレーナー」。取れていなければ「未設定」
    final raw = trainerName?.trim();
    final name =
        (raw == null || raw.isEmpty) ? null : trainerDisplayName(raw);
    return Text(
      name ?? '未設定',
      textAlign: TextAlign.end,
      style: AppTextStyles.body(context)
          .copyWith(color: name == null ? colors.textSecondary : null),
    );
  }
}

/// プロフィールカード本体（正本: `Card` の中に アバター＋名前・メール、区切り線、担当トレーナー）。
/// Provider に依存させず、プレビューからも同じ実装を使う
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.email,
    required this.avatar,
    required this.trainer,
    this.onChangePhoto,
    this.onEditName,
  });

  final String name;
  final String? email;
  final Widget avatar;

  /// 担当トレーナー行の値
  final Widget trainer;
  final VoidCallback? onChangePhoto;
  final VoidCallback? onEditName;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // アバター全体が「写真を変更」の操作（46 ≥ 44）
              FcPressable(
                onTap: onChangePhoto,
                minSize: const Size.square(AppSizes.minTouch),
                semanticLabel: '写真を変更',
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatar,
                    const Positioned(
                      right: -4,
                      bottom: -4,
                      child: _CameraBadge(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: AppTextStyles.sectionHeading(context),
                          ),
                        ),
                        // 鉛筆は 15 のアイコンだが、押せる範囲は 44×44
                        FcPressable(
                          onTap: onEditName,
                          semanticLabel: '名前を変更',
                          minSize: const Size.square(AppSizes.minTouch),
                          child: SizedBox(
                            width: AppSizes.minTouch,
                            height: AppSizes.minTouch,
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 6,
                                ),
                                child: ExcludeSemantics(
                                  child: Icon(
                                    LucideIcons.pencil,
                                    size: 15,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (email != null)
                      Text(
                        email!,
                        style: AppTextStyles.supplement(context),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const FcSeparator(),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('担当トレーナー', style: AppTextStyles.supplement(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: trainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// アバター右下の小さなカメラ印（22・actionFill・onAction・surface の 2px の縁）
class _CameraBadge extends StatelessWidget {
  const _CameraBadge();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ExcludeSemantics(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.actionFill,
          boxShadow: [
            BoxShadow(color: colors.surface, spreadRadius: 2),
          ],
        ),
        child: Icon(LucideIcons.camera, size: 12, color: colors.onAction),
      ),
    );
  }
}

/// プロフィール画像（Storage の署名 URL に解決して表示。無い・失敗したときはイニシャル）
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.name, required this.imageValue});

  final String name;
  final String? imageValue;

  @override
  Widget build(BuildContext context) {
    final initials = FcAvatar(
      name: name,
      size: FcAvatar.lg,
      excludeFromSemantics: true,
    );
    final value = imageValue;
    if (value == null || value.isEmpty) return initials;

    return SizedBox.square(
      dimension: FcAvatar.lg,
      child: ClipOval(
        child: StorageImage(
          value: value,
          bucket: StorageBuckets.clientAvatars,
          width: FcAvatar.lg,
          height: FcAvatar.lg,
          fit: BoxFit.cover,
          placeholder: const FcSkeleton.circle(size: FcAvatar.lg),
          errorWidget: initials,
        ),
      ),
    );
  }
}

/// プロフィールの読み込み中（配置を保つ）
class _ProfileCardSkeleton extends StatelessWidget {
  const _ProfileCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: const FcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FcSkeleton.circle(size: FcAvatar.lg),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FcSkeleton.line(width: 120, height: 20),
                      SizedBox(height: 8),
                      FcSkeleton.line(width: 180),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.lg),
            FcSeparator(),
            SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FcSkeleton.line(width: 80),
                FcSkeleton.line(width: 96, height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 外観
// ============================================

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    return _AppearanceCard(
      themeMode: themeMode,
      onChanged: (mode) =>
          ref.read(themeModeNotifierProvider.notifier).setThemeMode(mode),
    );
  }
}

/// 外観（ライト / ダーク / 自動）。正本: `Card` に `SegmentedControl`
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({required this.themeMode, required this.onChanged});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return FcCard(
      child: FcSegmentedControl<ThemeMode>(
        items: const [
          FcSegmentedItem(value: ThemeMode.light, label: 'ライト'),
          FcSegmentedItem(value: ThemeMode.dark, label: 'ダーク'),
          FcSegmentedItem(
            value: ThemeMode.system,
            label: '自動',
            semanticLabel: '自動（端末の設定に合わせる）',
          ),
        ],
        selected: themeMode,
        onChanged: onChanged,
      ),
    );
  }
}

// ============================================
// 通知
// ============================================

class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return _NotificationRows(
      prefs: prefsAsync.valueOrNull,
      hasError: prefsAsync.hasError && !prefsAsync.hasValue,
      onRetry: () => ref.invalidate(notificationPreferencesProvider),
      onChanged: (kind, value) async {
        try {
          await ref
              .read(notificationPreferencesProvider.notifier)
              .setEnabled(kind, value);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('通知設定の更新に失敗しました')),
            );
          }
        }
      },
    );
  }
}

/// 通知のオン/オフ（3 行）。[prefs] が null の間は読み込み中の行を出す。
/// 正本: `RowsCard` に `Row`（トグル）。現行の 3 項目に合わせる
class _NotificationRows extends StatelessWidget {
  const _NotificationRows({
    required this.prefs,
    this.hasError = false,
    this.onRetry,
    this.onChanged,
  });

  final NotificationPreferencesState? prefs;
  final bool hasError;
  final VoidCallback? onRetry;
  final void Function(NotificationKind kind, bool value)? onChanged;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return FcInlineNotice.error(
        message: '通知設定を読み込めませんでした',
        actionLabel: '再試行',
        onAction: onRetry,
      );
    }

    const items = <(NotificationKind, String, String?)>[
      (NotificationKind.message, 'トレーナーからのメッセージ', null),
      (NotificationKind.goalAchievement, '目標の達成', null),
      // 実際の送信は前日 20:00（JST）の 1 回（send-session-reminders）なので、
      // 正本の「前日と当日の朝」ではなく実装どおりの文言にする
      (NotificationKind.sessionReminder, 'セッションのリマインド', '前日の夜にお知らせ'),
    ];

    final current = prefs;
    return FcRowsCard(
      children: [
        for (final (kind, title, caption) in items)
          if (current == null)
            FcListRow(
              title: title,
              caption: caption,
              trailing: const FcRowValue.loading(),
            )
          else
            FcListRow.toggle(
              title: title,
              caption: caption,
              value: current.isEnabled(kind),
              onChanged:
                  onChanged == null ? null : (value) => onChanged!(kind, value),
            ),
      ],
    );
  }
}

// ============================================
// ヘルスケア連携
// ============================================

class _HealthSection extends ConsumerWidget {
  const _HealthSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(healthAvailableProvider).valueOrNull ?? false;
    // 連携できない端末（シミュレータ・非対応）ではグループごと出さない
    if (!available) return const SizedBox.shrink();

    final settings = ref.watch(healthSettingsProvider).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _GroupLabel('ヘルスケア連携'),
        _HealthRowCard(
          title: _healthSourceName(),
          caption: _healthCaption(settings, DateTime.now()),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const HealthSettingsScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 連携先の名前（iOS は HealthKit、Android は Health Connect）
String _healthSourceName() => defaultTargetPlatform == TargetPlatform.android
    ? 'Health Connect'
    : 'HealthKit';

/// 「連携中 · 体重 · 睡眠 · 最終同期 9月13日（日）7:32」。設定が読めるまでは null（補足なし）
String? _healthCaption(HealthSettingsState? settings, DateTime now) {
  if (settings == null) return null;
  if (!settings.isEnabled) return '未連携';
  final lastSyncAt = settings.lastSyncAt;
  return [
    '連携中',
    if (settings.isWeightEnabled) '体重',
    if (settings.isSleepEnabled) '睡眠',
    if (lastSyncAt != null)
      '最終同期 ${formatSessionDateTimeDisplay(lastSyncAt, now: now)}',
  ].join(' · ');
}

/// ヘルスケア連携の行（正本: `Row icon="heart-pulse" title="HealthKit" detail=…` ＋ chevron）
class _HealthRowCard extends StatelessWidget {
  const _HealthRowCard({
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final String title;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FcRowsCard(
      children: [
        FcListRow(
          icon: LucideIcons.heartPulse,
          title: title,
          caption: caption,
          onTap: onTap,
        ),
      ],
    );
  }
}

// ============================================
// 法的情報
// ============================================

class _LegalSection extends StatelessWidget {
  const _LegalSection();

  @override
  Widget build(BuildContext context) {
    return _LegalCard(
      onOpenTerms: () => _openLegalUrl(context, LegalLinks.termsUrl),
      onOpenPrivacy: () => _openLegalUrl(context, LegalLinks.privacyUrl),
    );
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({this.onOpenTerms, this.onOpenPrivacy});

  final VoidCallback? onOpenTerms;
  final VoidCallback? onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    return FcRowsCard(
      children: [
        // 外部のブラウザで開くことを読み上げでも伝える
        FcListRow(
          title: '利用規約',
          externalLink: true,
          semanticLabel: '利用規約、外部で開く',
          onTap: onOpenTerms,
        ),
        FcListRow(
          title: 'プライバシーポリシー',
          externalLink: true,
          semanticLabel: 'プライバシーポリシー、外部で開く',
          onTap: onOpenPrivacy,
        ),
      ],
    );
  }
}

/// 法務ページを外部ブラウザで開く
Future<void> _openLegalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('リンクを開けませんでした')),
    );
  }
}

// ============================================
// アカウント
// ============================================

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _AccountCard(
      onLogout: () => _showLogoutDialog(context, ref),
      // App Store Guideline 5.1.1(v) 対応のアカウント削除
      onDeleteAccount: () => _showDeleteAccountDialog(context, ref),
    );
  }
}

/// アカウント（ログアウト = log-out アイコン、アカウントを削除 = error 色・アイコンなし。chevron なし）
class _AccountCard extends StatelessWidget {
  const _AccountCard({this.onLogout, this.onDeleteAccount});

  final VoidCallback? onLogout;
  final VoidCallback? onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcRowsCard(
      children: [
        FcListRow(
          icon: LucideIcons.logOut,
          title: 'ログアウト',
          chevron: false,
          onTap: onLogout,
        ),
        FcListRow(
          title: 'アカウントを削除',
          color: colors.error,
          chevron: false,
          onTap: onDeleteAccount,
        ),
      ],
    );
  }
}

// ============================================
// バージョン
// ============================================

class _VersionCaption extends ConsumerWidget {
  const _VersionCaption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // package_info_plus 由来。取得中・失敗時は「-」
    final version = ref.watch(packageInfoProvider).valueOrNull?.version;
    return _VersionText(version: version);
  }
}

class _VersionText extends StatelessWidget {
  const _VersionText({required this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    // 正本: caption・中央・上 4（カード間 16 と合わせて 20）
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.cardGap + 4),
      child: Text(
        'FIT-CONNECT バージョン ${version ?? '-'}',
        textAlign: TextAlign.center,
        style: AppTextStyles.caption(context),
      ),
    );
  }
}

// ============================================
// 操作（ダイアログ・画像選択）
// ============================================

void _showEditNameDialog(
  BuildContext context,
  WidgetRef ref,
  String clientId,
  String currentName,
) {
  final controller = TextEditingController(text: currentName);
  final formKey = GlobalKey<FormState>();

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('名前を編集'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名前',
            hintText: '名前を入力してください',
          ),
          maxLength: 50,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '名前を入力してください';
            }
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'キャンセル',
            style: TextStyle(color: AppColors.of(dialogContext).textSecondary),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;

            final newName = controller.text.trim();
            Navigator.of(dialogContext).pop();

            try {
              await ref.read(clientRepositoryProvider).updateClientName(
                    clientId,
                    newName,
                  );

              // Providerをinvalidateして再取得
              ref.invalidate(currentClientProvider);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('名前を更新しました')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('更新に失敗しました: $e')),
                );
              }
            }
          },
          child: const Text(
            '保存',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

void _showProfileImagePicker(
  BuildContext context,
  WidgetRef ref,
  String clientId,
) async {
  // 画像選択ダイアログを表示
  final file = await StorageService.showImagePickerDialog(context);
  if (file == null) return;

  // ローディング表示
  if (context.mounted) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  try {
    // 画像をアップロード（戻り値はバケット相対パス）
    final imagePath = await StorageService.uploadProfileImage(file, clientId);

    if (imagePath == null) {
      throw Exception('画像のアップロードに失敗しました');
    }

    // DBを更新（profile_image_url にはパスを保存する）
    await ref.read(clientRepositoryProvider).updateProfileImageUrl(
          clientId,
          imagePath,
        );

    // Providerをinvalidateして再取得
    ref.invalidate(currentClientProvider);

    // ローディングを閉じる
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プロフィール画像を更新しました')),
      );
    }
  } catch (e) {
    // ローディングを閉じる
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の更新に失敗しました: $e')),
      );
    }
  }
}

void _showLogoutDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ログアウト'),
      content: const Text('ログアウトしますか？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'キャンセル',
            style: TextStyle(color: AppColors.of(dialogContext).textSecondary),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop(); // ダイアログを閉じる
            try {
              await ref.read(authNotifierProvider.notifier).signOut();
              // ルーティングはapp.dartのStreamBuilderが自動処理
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ログアウトに失敗しました: $e')),
                );
              }
            }
          },
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
}

/// アカウント削除・確認ダイアログ（1段階目: 削除されるデータの説明）
void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('アカウントを削除'),
      content: const _DeleteAccountWarningContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'キャンセル',
            style: TextStyle(color: AppColors.of(dialogContext).textSecondary),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            _showDeleteAccountConfirmDialog(context, ref);
          },
          child: Text(
            '続ける',
            style: TextStyle(
              color: AppColors.of(dialogContext).error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

/// アカウント削除・確認ダイアログ（2段階目: 最終確認 + 実行）
void _showDeleteAccountConfirmDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var isDeleting = false;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final colors = AppColors.of(dialogContext);
          return AlertDialog(
            title: const Text('本当に削除しますか？'),
            content: const Text('この操作は取り消せません。すべてのデータが完全に削除されます。'),
            actions: [
              TextButton(
                onPressed:
                    isDeleting ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'キャンセル',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() => isDeleting = true);
                        try {
                          await ref
                              .read(authNotifierProvider.notifier)
                              .deleteAccount();
                          // 成功: deleteAccount 内で signOut 済み。
                          // ルーティングはapp.dartのStreamBuilderが自動処理
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (e) {
                          // 失敗: ダイアログを閉じて SnackBar 表示（再試行可能）
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('アカウントの削除に失敗しました: $e'),
                              ),
                            );
                          }
                        }
                      },
                child: isDeleting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.error,
                          ),
                        ),
                      )
                    : Text(
                        '削除する',
                        style: TextStyle(
                          color: colors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}

/// アカウント削除ダイアログ（1段階目）の本文
/// 実装とプレビューで共用するため独立Widgetにしている
class _DeleteAccountWarningContent extends StatelessWidget {
  const _DeleteAccountWarningContent();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('・', style: TextStyle(color: colors.textPrimary)),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'アカウントを削除すると、以下のデータがすべて削除されます。',
          style: TextStyle(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        bullet('体重・食事・運動・睡眠の記録'),
        bullet('トレーナーとのメッセージと写真'),
        bullet('セッション・チケット情報'),
        const SizedBox(height: 12),
        Text(
          'この操作は取り消せません。',
          style: TextStyle(
            color: colors.error,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用の本体（Riverpod を使わず、実画面と同じ View を並べる）
class _PreviewSettingsBody extends StatelessWidget {
  const _PreviewSettingsBody({
    this.themeMode = ThemeMode.system,
    this.loading = false,
  });

  final ThemeMode themeMode;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final pageH = AppSpacing.pageHorizontalOf(context);
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pageH, 4, pageH, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FcPageHeading(title: '設定'),
              if (loading)
                const _ProfileCardSkeleton()
              else
                const _ProfileCard(
                  name: '佐藤 美咲',
                  email: 'misaki.sato@example.com',
                  avatar: FcAvatar(
                    name: '佐藤 美咲',
                    size: FcAvatar.lg,
                    excludeFromSemantics: true,
                  ),
                  trainer: _TrainerValue.name('田中トレーナー'),
                ),
              const _GroupLabel('外観'),
              _AppearanceCard(themeMode: themeMode, onChanged: (_) {}),
              const _GroupLabel('通知'),
              _NotificationRows(
                prefs: loading
                    ? null
                    : const NotificationPreferencesState(
                        sessionReminderEnabled: false,
                      ),
                onChanged: (_, __) {},
              ),
              const _GroupLabel('ヘルスケア連携'),
              _HealthRowCard(
                title: 'HealthKit',
                caption: loading
                    ? null
                    : _healthCaption(
                        HealthSettingsState(
                          isEnabled: true,
                          isWeightEnabled: false,
                          isSleepEnabled: true,
                          isMorningDialogEnabled: true,
                          lastSyncAt: now.subtract(const Duration(hours: 3)),
                        ),
                        now,
                      ),
                onTap: () {},
              ),
              const _GroupLabel('法的情報'),
              const _LegalCard(),
              const _GroupLabel('アカウント'),
              const _AccountCard(),
              const _VersionText(version: '1.0.0'),
            ],
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'SettingsScreen - Light')
Widget previewSettingsScreenLight() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewSettingsBody(),
  );
}

@Preview(name: 'SettingsScreen - Dark')
Widget previewSettingsScreenDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: const _PreviewSettingsBody(themeMode: ThemeMode.dark),
  );
}

@Preview(name: 'SettingsScreen - Loading')
Widget previewSettingsScreenLoading() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewSettingsBody(loading: true),
  );
}

@Preview(name: 'SettingsScreen - Large Text (1.35)')
Widget previewSettingsScreenLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: const _PreviewSettingsBody(),
  );
}

@Preview(name: 'DeleteAccountDialog - Step1 削除データ説明')
Widget previewDeleteAccountDialogStep1() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: AlertDialog(
          title: const Text('アカウントを削除'),
          content: const _DeleteAccountWarningContent(),
          actions: [
            TextButton(
              onPressed: () {},
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('続ける'),
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'DeleteAccountDialog - Step2 最終確認')
Widget previewDeleteAccountDialogStep2() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Center(
        child: AlertDialog(
          title: const Text('本当に削除しますか？'),
          content: const Text('この操作は取り消せません。すべてのデータが完全に削除されます。'),
          actions: [
            TextButton(
              onPressed: () {},
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {},
              child: const Text('削除する'),
            ),
          ],
        ),
      ),
    ),
  );
}
