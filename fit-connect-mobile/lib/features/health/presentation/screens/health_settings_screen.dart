import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// ヘルスケア連携の設定画面（設定タブ › ヘルスケア連携 から push される）。
///
/// 正本に専用の画面は無いので、設定タブの文法（グループ名 ＋ `FcRowsCard` の `FcListRow.toggle`、
/// 同期の失敗は `FcInlineNotice.warning` ＋ 再試行）で揃えている。
/// AppBar をやめ、本文内の「戻る」＋ 見出しにした。機能・文言は現行のまま。
class HealthSettingsScreen extends ConsumerWidget {
  const HealthSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(healthSettingsProvider);
    final syncAsync = ref.watch(healthSyncProvider);

    return _HealthSettingsScaffold(
      child: settingsAsync.when(
        data: (settings) => _HealthSettingsContent(
          settings: settings,
          isSyncing: syncAsync.isLoading,
          onMasterChanged: (value) async {
            final granted = await ref
                .read(healthSettingsProvider.notifier)
                .toggleEnabled(value);
            if (!granted && value && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('設定アプリからヘルスケアの権限を許可してください'),
                ),
              );
            }
          },
          onWeightChanged: (value) {
            ref
                .read(healthSettingsProvider.notifier)
                .toggleWeightEnabled(value);
          },
          onSleepChanged: (value) async {
            final granted = await ref
                .read(healthSettingsProvider.notifier)
                .toggleSleepEnabled(value);
            if (!granted && value && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('設定アプリから睡眠データの権限を許可してください'),
                ),
              );
            }
          },
          onMorningDialogChanged: (value) async {
            await ref
                .read(healthSettingsProvider.notifier)
                .toggleMorningDialogEnabled(value);
          },
          onSync: () => _runManualSync(context, ref),
        ),
        loading: () => const _HealthSettingsLoading(),
        error: (error, _) => FcStateMessage.error(
          title: '設定を読み込めませんでした',
          message: 'エラー: $error',
          actionLabel: '再試行',
          actionIcon: LucideIcons.refreshCw,
          onAction: () => ref.invalidate(healthSettingsProvider),
        ),
      ),
    );
  }
}

/// 手動同期（「今すぐ同期」と同期エラーの「再試行」で共用）。結果は SnackBar で伝える
Future<void> _runManualSync(BuildContext context, WidgetRef ref) async {
  await ref.read(healthSyncProvider.notifier).syncManual();
  if (!context.mounted) return;
  final result = ref.read(healthSettingsProvider).valueOrNull;
  final isError = result?.lastSyncStatus == HealthSyncStatus.error;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        isError ? '同期に失敗しました: ${result?.lastSyncError ?? "原因不明"}' : '同期が完了しました',
      ),
    ),
  );
}

/// 画面の枠（戻る・見出し）と、その下の内容。Provider に依存させずプレビューでも使う
class _HealthSettingsScaffold extends StatelessWidget {
  const _HealthSettingsScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pageH = AppSpacing.pageHorizontalOf(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pageH, 4, pageH, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FcButton.back(
                  label: '戻る',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const FcPageHeading(title: 'ヘルスケア連携', bottomSpacing: 20),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// グループ名（13・secondary）。設定タブの `GroupLabel` と同じ（前 16 + 10、後 16 - 8）
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

/// 読み込み中（カードの配置を保つ）
class _HealthSettingsLoading extends StatelessWidget {
  const _HealthSettingsLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FcSkeleton.card(height: 88),
          SizedBox(height: AppSpacing.cardGap),
          FcSkeleton.card(height: 150),
          SizedBox(height: AppSpacing.cardGap),
          FcSkeleton.card(height: 110),
        ],
      ),
    );
  }
}

/// 設定の内容（連携 / データソース / 通知 / 同期）。Provider に依存させずプレビューでも使う
class _HealthSettingsContent extends StatelessWidget {
  const _HealthSettingsContent({
    required this.settings,
    required this.isSyncing,
    this.onMasterChanged,
    this.onWeightChanged,
    this.onSleepChanged,
    this.onMorningDialogChanged,
    this.onSync,
  });

  final HealthSettingsState settings;

  /// 手動同期の実行中（ボタンを「同期中…」にして押せなくする）
  final bool isSyncing;
  final ValueChanged<bool>? onMasterChanged;
  final ValueChanged<bool>? onWeightChanged;
  final ValueChanged<bool>? onSleepChanged;
  final ValueChanged<bool>? onMorningDialogChanged;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final hasError = settings.lastSyncStatus == HealthSyncStatus.error;
    final isStatusSyncing = settings.lastSyncStatus == HealthSyncStatus.syncing;
    final enabled = settings.isEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // マスターの連携スイッチ
        FcRowsCard(
          children: [
            FcListRow.toggle(
              icon: LucideIcons.heartPulse,
              title: 'ヘルスケア連携',
              caption:
                  'お使いの端末のヘルスケア（iOS: ヘルスケア / Android: Health Connect）からデータを取得',
              value: settings.isEnabled,
              onChanged: onMasterChanged,
            ),
          ],
        ),

        const _GroupLabel('データソース'),
        FcRowsCard(
          children: [
            // 連携が切れているあいだは操作できない（スイッチ自身が淡色になる。
            // 行をさらに薄くすると二重に薄くなるので、ここでは何も被せない）
            FcListRow.toggle(
              icon: LucideIcons.scale,
              title: '体重',
              caption: '読み取りのみ',
              value: settings.isWeightEnabled,
              onChanged: enabled ? onWeightChanged : null,
            ),
            FcListRow.toggle(
              icon: LucideIcons.moon,
              title: '睡眠',
              caption: 'HealthKit/Health Connect から睡眠データを取得',
              value: settings.isSleepEnabled,
              onChanged: enabled ? onSleepChanged : null,
            ),
          ],
        ),

        const _GroupLabel('通知'),
        FcRowsCard(
          children: [
            FcListRow.toggle(
              icon: LucideIcons.sun,
              title: '朝の目覚めダイアログ',
              caption: '起床後（4:00-12:00）にアプリを開いた時、目覚めの記録を促します',
              value: settings.isMorningDialogEnabled,
              onChanged: onMorningDialogChanged,
            ),
          ],
        ),

        const _GroupLabel('同期'),
        FcRowsCard(
          children: [
            FcListRow(
              title: '最終同期',
              caption: 'アプリ起動時と1時間ごとに自動同期します',
              trailing: FcRowValue.text(
                isStatusSyncing ? '同期中…' : _formatLastSync(settings.lastSyncAt),
                muted: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: FcButton.pill(
                label: '今すぐ同期',
                icon: LucideIcons.refreshCw,
                quiet: true,
                expand: true,
                loading: isSyncing,
                loadingLabel: '同期中…',
                onPressed: enabled ? onSync : null,
              ),
            ),
          ],
        ),

        // 同期に失敗したとき（取得済みの値はそのまま使われる）
        if (hasError && settings.lastSyncError != null) ...[
          const SizedBox(height: AppSpacing.cardGap),
          HealthSyncErrorRow(
            message: settings.lastSyncError!,
            // 「今すぐ同期」と同じく、連携が切れているときは再試行できない
            // （同期が走らないまま古い失敗を読んで「同期に失敗しました」を出してしまう）
            onRetry: (isSyncing || !enabled) ? null : onSync,
          ),
        ],

        const SizedBox(height: AppSpacing.xxl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '手動入力の体重記録がある日はHealthKitからの取り込みをスキップします',
            style: AppTextStyles.caption(context),
          ),
        ),
      ],
    );
  }
}

String _formatLastSync(DateTime? lastSync) {
  if (lastSync == null) return '未同期';
  final diff = DateTime.now().difference(lastSync);
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  if (diff.inDays < 7) return '${diff.inDays}日前';
  // 1週間以上は日付表記
  final m = lastSync.month;
  final d = lastSync.day;
  final hh = lastSync.hour.toString().padLeft(2, '0');
  final mm = lastSync.minute.toString().padLeft(2, '0');
  return '$m月$d日 $hh:$mm';
}

/// ヘルスケア同期エラー行（「同期エラー: …」）。
/// 注意の色（warning）の `FcInlineNotice` で、文字とアイコンを併用する。
/// [onRetry] を渡すと「再試行」の操作が付く（同期をもう一度走らせる）。
class HealthSyncErrorRow extends StatelessWidget {
  const HealthSyncErrorRow({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FcInlineNotice.warning(
      message: '同期エラー: $message',
      actionLabel: onRetry == null ? null : '再試行',
      onAction: onRetry,
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用の設定（Riverpod を使わず、実画面と同じ内容の View を並べる）
class _PreviewHealthSettings extends StatelessWidget {
  final HealthSettingsState settings;
  final bool isSyncing;

  const _PreviewHealthSettings({
    required this.settings,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    return _HealthSettingsScaffold(
      child: _HealthSettingsContent(
        settings: settings,
        isSyncing: isSyncing,
        onMasterChanged: (_) {},
        onWeightChanged: (_) {},
        onSleepChanged: (_) {},
        onMorningDialogChanged: (_) {},
        onSync: () {},
      ),
    );
  }
}

HealthSettingsState _previewConnected({
  HealthSyncStatus status = HealthSyncStatus.idle,
  String? error,
}) =>
    HealthSettingsState(
      isEnabled: true,
      isWeightEnabled: true,
      isSleepEnabled: true,
      isMorningDialogEnabled: true,
      lastSyncAt: DateTime.now().subtract(const Duration(minutes: 5)),
      lastSyncStatus: status,
      lastSyncError: error,
    );

const _previewDisconnected = HealthSettingsState(
  isEnabled: false,
  isWeightEnabled: false,
  isSleepEnabled: false,
  isMorningDialogEnabled: true,
);

@Preview(name: 'HealthSettingsScreen - Connected')
Widget previewHealthSettingsConnected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewHealthSettings(settings: _previewConnected()),
  );
}

@Preview(name: 'HealthSettingsScreen - Disconnected')
Widget previewHealthSettingsDisconnected() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewHealthSettings(settings: _previewDisconnected),
  );
}

@Preview(name: 'HealthSettingsScreen - Syncing')
Widget previewHealthSettingsSyncing() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewHealthSettings(
      settings: _previewConnected(status: HealthSyncStatus.syncing),
      isSyncing: true,
    ),
  );
}

@Preview(name: 'HealthSettingsScreen - Sync Error')
Widget previewHealthSettingsSyncError() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewHealthSettings(
      settings: _previewConnected(
        status: HealthSyncStatus.error,
        error: 'HealthKitへのアクセスが拒否されました',
      ),
    ),
  );
}

/// ダークモード: 同期エラーの帯（warning）が暗い配色で読めることを確認する
@Preview(name: 'HealthSettingsScreen - Sync Error (Dark)')
Widget previewHealthSettingsSyncErrorDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: _PreviewHealthSettings(
      settings: _previewConnected(
        status: HealthSyncStatus.error,
        error: 'HealthKitへのアクセスが拒否されました',
      ),
    ),
  );
}

@Preview(name: 'HealthSettingsScreen - Sync Error (Large Text 1.35)')
Widget previewHealthSettingsLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: _PreviewHealthSettings(
      settings: _previewConnected(
        status: HealthSyncStatus.error,
        error: 'HealthKitへのアクセスが拒否されました',
      ),
    ),
  );
}

@Preview(name: 'HealthSettingsScreen - Loading')
Widget previewHealthSettingsLoading() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _HealthSettingsScaffold(child: _HealthSettingsLoading()),
  );
}
