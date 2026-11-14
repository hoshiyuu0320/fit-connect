import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/record_reminder_settings.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';
import 'package:fit_connect_mobile/features/record_reminders/presentation/widgets/reminder_time_picker_sheet.dart';
import 'package:fit_connect_mobile/features/record_reminders/providers/record_reminder_settings_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録のリマインダーの設定画面（設定タブ › 通知 › 記録のリマインダー から push される。設計 §7・§8）。
///
/// ヘルスケア連携の設定画面と同じ形（本文内の「戻る」＋ 見出し）。冒頭の説明 → 通知の許可が無いときの
/// 案内 → 5項目の行（表示名・時刻・トグル）→ 末尾の注記。
///
/// 通知の許可は、画面を開いたとき・アプリが前面に戻ったとき（設定アプリから戻ったとき）・
/// 項目をオンにした後に読み直す。案内は「オンの項目がある」かつ「拒否」のときだけ出す
/// （不明・未決定・許可では出さない）。項目をオンにしている間（許可を求めているかもしれない間）は、
/// まだ出ていない案内を出さず、終わって許可を読み直してから決める。
class RecordReminderSettingsScreen extends ConsumerStatefulWidget {
  const RecordReminderSettingsScreen({super.key});

  @override
  ConsumerState<RecordReminderSettingsScreen> createState() =>
      _RecordReminderSettingsScreenState();
}

class _RecordReminderSettingsScreenState
    extends ConsumerState<RecordReminderSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  /// 画面を開いたときの許可の読み直しを済ませたか
  /// （didChangeDependencies は依存が変わるたびに呼ばれるので、最初の1回だけにする）
  bool _permissionRereadOnOpen = false;

  /// 時刻のシートを開いている間は、もう一度開かない（連打で2枚重ねない）
  bool _pickingTime = false;

  /// 案内が出ていないときに始めた「オンにする」操作のうち、まだ終わっていない数
  /// （1 以上の間は案内を出さない）。
  ///
  /// オンにすると OS のダイアログで許可を求めることがあり、Android は一度も聞いていなくても許可が
  /// 「拒否」と読めるので、そのままではダイアログが開くまでの間に案内が一瞬出てしまう。
  /// 操作が終わり、許可を読み直し終えてから、その値で決める。すでに出ている案内は出したままにする
  /// （消して出し直すと、行が上下にずれる）
  int _noticeHolds = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _rereadPermission);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 画面を開いたときに読み直す（ref は initState では使えないので、最初の didChangeDependencies で）
    if (!_permissionRereadOnOpen) {
      _permissionRereadOnOpen = true;
      _rereadPermission();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _rereadPermission() {
    if (!mounted) return;
    ref.invalidate(reminderNotificationPermissionProvider);
  }

  /// 許可を読み直し、読み終えるまで待つ（読めなくても投げない）
  Future<void> _rereadPermissionAndWait() async {
    if (!mounted) return;
    _rereadPermission();
    try {
      await ref.read(reminderNotificationPermissionProvider.future);
    } catch (e) {
      // 読み直しの途中で画面を閉じた等。案内はそのときの値で決める
      debugPrint('[RecordReminderSettingsScreen] 通知の許可の読み直しエラー: $e');
    }
  }

  /// 「通知がオフになっています」の案内を出すか
  /// （オンの項目があり、許可が「拒否」で、オンにする操作の間で止めていない）
  bool _permissionNoticeVisible(
    RecordReminderSettings? settings,
    ReminderNotificationPermission? permission,
  ) =>
      _noticeHolds == 0 &&
      settings != null &&
      settings.anyEnabled &&
      permission == ReminderNotificationPermission.denied;

  Future<void> _setEnabled(ReminderKind kind, bool enabled) async {
    // オンにする間は、まだ出ていない案内を出さない（[_noticeHolds]）
    final hold = enabled &&
        !_permissionNoticeVisible(
          ref.read(recordReminderSettingsProvider).valueOrNull,
          ref.read(reminderNotificationPermissionProvider).valueOrNull,
        );
    if (hold) setState(() => _noticeHolds++);
    try {
      try {
        await ref
            .read(recordReminderSettingsProvider.notifier)
            .setEnabled(kind, enabled);
      } catch (e) {
        // ログインしていない（StateError）・保存の失敗。設定は元に戻っている
        _showSaveError(e);
        return;
      }
      // オンにしたときは許可を求めた・拒否されているかもしれないので読み直す（拒否なら案内が出る）。
      // 読み直し終えてから案内を戻す（前に読んだ「拒否」で一瞬出さない）
      if (enabled) await _rereadPermissionAndWait();
    } finally {
      if (hold && mounted) setState(() => _noticeHolds--);
    }
  }

  Future<void> _changeTime(ReminderKind kind, ReminderTime current) async {
    if (_pickingTime) return;
    _pickingTime = true;
    final ReminderTime? picked;
    try {
      picked = await showReminderTimePickerSheet(
        context,
        initial: current,
        title: '${kind.label}の時刻',
      );
    } finally {
      _pickingTime = false;
    }
    // 変えずに「決定」なら保存しない（予約もし直さない）
    if (!mounted || picked == null || picked == current) return;
    try {
      await ref
          .read(recordReminderSettingsProvider.notifier)
          .setTime(kind, picked);
    } catch (e) {
      _showSaveError(e);
    }
  }

  void _showSaveError(Object error) {
    debugPrint('[RecordReminderSettingsScreen] 設定の保存エラー: $error');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('リマインダーの設定を保存できませんでした')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(recordReminderSettingsProvider);
    final permission =
        ref.watch(reminderNotificationPermissionProvider).valueOrNull;
    final settings = settingsAsync.valueOrNull;

    return _ReminderSettingsScaffold(
      showPermissionNotice: _permissionNoticeVisible(settings, permission),
      onOpenNotificationSettings: _openNotificationSettings,
      child: settingsAsync.when(
        data: (loaded) => _ReminderRowsCard(
          settings: loaded,
          onToggle: _setEnabled,
          onChangeTime: _changeTime,
        ),
        loading: () => const _ReminderRowsCard.loading(),
        error: (error, _) => FcInlineNotice.error(
          message: 'リマインダーの設定を読み込めませんでした',
          actionLabel: '再試行',
          onAction: () => ref.invalidate(recordReminderSettingsProvider),
        ),
      ),
    );
  }
}

/// OS の設定アプリで、このアプリの通知の設定を開く（iOS 16 未満などはアプリの設定）
Future<void> _openNotificationSettings() async {
  try {
    await AppSettings.openAppSettings(type: AppSettingsType.notification);
  } catch (e) {
    debugPrint('[RecordReminderSettingsScreen] 設定アプリを開けませんでした: $e');
  }
}

/// 画面の枠（戻る・見出し・説明・許可の案内・注記）と、その間の [child]（行のカード）。
/// Provider に依存させずプレビューでも使う
class _ReminderSettingsScaffold extends StatelessWidget {
  const _ReminderSettingsScaffold({
    required this.child,
    this.showPermissionNotice = false,
    this.onOpenNotificationSettings,
  });

  final Widget child;

  /// 「通知がオフになっています」の案内を出すか
  final bool showPermissionNotice;
  final VoidCallback? onOpenNotificationSettings;

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
              const FcPageHeading(
                title: '記録のリマインダー',
                bottomSpacing: AppSpacing.md,
              ),
              Text(
                '決まった時刻に、この端末へ記録のお知らせを出します。その日すでに記録していれば出しません。',
                style: AppTextStyles.supplement(context),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (showPermissionNotice) ...[
                // 設定アプリへ移るので、操作のアイコンは「再試行」ではなく外部で開く印
                FcInlineNotice.warning(
                  message: '通知がオフになっています。設定アプリでこのアプリの通知を許可してください。',
                  actionLabel: '設定を開く',
                  actionIcon: LucideIcons.externalLink,
                  onAction: onOpenNotificationSettings,
                ),
                const SizedBox(height: AppSpacing.cardGap),
              ],
              child,
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(
                  '時刻は日本時間です。アプリを7日以上開かないと、お知らせは止まります。開くと再開します。',
                  style: AppTextStyles.supplement(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 5項目の行を並べたカード（ReminderKind の並び。行の間だけに区切り線）。
/// [settings] が null の間は読み込み中の行を出す（配置を保つ）。Provider に依存させずプレビューでも使う
class _ReminderRowsCard extends StatelessWidget {
  const _ReminderRowsCard({
    required RecordReminderSettings this.settings,
    this.onToggle,
    this.onChangeTime,
  });

  const _ReminderRowsCard.loading()
      : settings = null,
        onToggle = null,
        onChangeTime = null;

  final RecordReminderSettings? settings;
  final void Function(ReminderKind kind, bool enabled)? onToggle;
  final void Function(ReminderKind kind, ReminderTime current)? onChangeTime;

  @override
  Widget build(BuildContext context) {
    final current = settings;
    return FcRowsCard(
      children: [
        for (final kind in ReminderKind.values)
          if (current == null)
            _ReminderRow.loading(kind: kind)
          else
            _ReminderRow(
              kind: kind,
              setting: current.settingOf(kind),
              onToggle: onToggle == null
                  ? null
                  : (enabled) => onToggle!(kind, enabled),
              onChangeTime: onChangeTime == null
                  ? null
                  : () => onChangeTime!(kind, current.settingOf(kind).time),
            ),
      ],
    );
  }
}

/// 読み上げの時刻（「7:30」「20:00」。時の先頭の 0 は付けない）
String _spokenTime(ReminderTime time) =>
    '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

/// 行の読み上げ（「体重のリマインダー、7:30」「運動のリマインダー、プランがある日だけ、18:00」）。
/// オン・オフはスイッチの状態として読まれる。[time] が null なら「読み込み中」
String _rowSemanticLabel(ReminderKind kind, ReminderTime? time) => [
      '${kind.label}のリマインダー',
      if (kind.caption != null) kind.caption!,
      if (time == null) '読み込み中' else _spokenTime(time),
    ].join('、');

/// 文字の拡大がこの倍率以上なら、行の時刻とトグルを表示名・補足の下へ積み直す。
/// iOS の「さらに大きな文字」の最初の段階（本文 28/17 ≒ 1.65）の手前。iOS の設定の行も
/// この大きさから値を文字の下へ移す（表示名が1文字ずつに折り返されないように）
const double _stackedTextScale = 1.6;

/// 1項目の行（左に表示名・補足、右に時刻とトグル）。
///
/// `FcListRow` は右側に操作を1つしか置けないので、同じ寸法・書体で組む（最小高さ 54・縦余白 10・
/// 表示名 16（textPrimary）・補足 12（textSecondary）・右側との間 12）。表示名・補足は折り返し、
/// 時刻とトグルはいつも1行に並べる（文字を [_stackedTextScale] 以上に拡大したときは、
/// 表示名・補足の下に右寄せで置く）。
/// - 時刻（[_ReminderTimeButton]）: 押すと時刻の選択。押せる範囲 44 以上
/// - トグル（[FcToggle]）: 51×44。時刻との間は 8
/// - 行のほかの場所は押しても何も起きない（時刻を押し損ねてオン・オフが変わらないように）
///
/// 読み上げは、行全体が「体重のリマインダー、7:30」のスイッチ（オン/オフ・ダブルタップで切り替え）で、
/// その中に時刻のボタン「体重の時刻 7:30、変更」がある
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.kind,
    required ReminderSetting this.setting,
    this.onToggle,
    this.onChangeTime,
  });

  /// 読み込み中（右側はスケルトン）
  const _ReminderRow.loading({required this.kind})
      : setting = null,
        onToggle = null,
        onChangeTime = null;

  final ReminderKind kind;
  final ReminderSetting? setting;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onChangeTime;

  @override
  Widget build(BuildContext context) {
    final setting = this.setting;
    final caption = kind.caption;
    const density = FcRowDensity.standard;

    // 表示名・補足は行の読み上げにまとめるので、文字としては読ませない
    final labels = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(kind.label, style: AppTextStyles.body(context)),
          if (caption != null)
            Text(caption, style: AppTextStyles.caption(context)),
        ],
      ),
    );

    final Widget controls;
    if (setting == null) {
      // 読み込めた後のトグル（高さ 44）と行の高さを揃える
      controls = const SizedBox(
        height: AppSizes.minTouch,
        child: Center(child: FcRowValue.loading()),
      );
    } else {
      controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ReminderTimeButton(
            kind: kind,
            time: setting.time,
            active: setting.enabled,
            onPressed: onChangeTime,
          ),
          const SizedBox(width: AppSpacing.sm),
          // 状態は行の読み上げ（スイッチ）で伝えるので、ここでは読ませない
          ExcludeSemantics(
            child: FcToggle(
              value: setting.enabled,
              onChanged: onToggle,
              semanticLabel: _rowSemanticLabel(kind, setting.time),
            ),
          ),
        ],
      );
    }

    final bodySize = AppTextStyles.body(context).fontSize!;
    final stacked =
        MediaQuery.textScalerOf(context).scale(bodySize) / bodySize >=
            _stackedTextScale;

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: density.minHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: density.verticalPadding),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  labels,
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: controls,
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: labels),
                  const SizedBox(width: AppSpacing.md),
                  controls,
                ],
              ),
      ),
    );

    if (setting == null) {
      return Semantics(
        container: true,
        label: _rowSemanticLabel(kind, null),
        excludeSemantics: true,
        child: content,
      );
    }

    final toggleable = onToggle != null;
    return Semantics(
      container: true,
      // 時刻のボタンは行の中の別の読み上げにする
      explicitChildNodes: true,
      label: _rowSemanticLabel(kind, setting.time),
      toggled: setting.enabled,
      enabled: toggleable,
      onTap: toggleable ? () => onToggle!(!setting.enabled) : null,
      child: content,
    );
  }
}

/// 時刻のボタン。カードの中の控えめな囲み（[FcInfoBox]: surfaceSecondary・角丸 12）に、
/// 行の値と同じ 16 / 500 の等幅数字で「07:30」。オフの項目は textSecondary にする（押せるのは同じ。
/// オンにする前に時刻を決められる）。囲みは高さ 32 で、押せる範囲は 44×44 以上
class _ReminderTimeButton extends StatelessWidget {
  const _ReminderTimeButton({
    required this.kind,
    required this.time,
    required this.active,
    this.onPressed,
  });

  final ReminderKind kind;
  final ReminderTime time;

  /// 項目がオンか（オフなら時刻を textSecondary にする）
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: FcPressable(
        onTap: onPressed,
        minSize: const Size.square(AppSizes.minTouch),
        semanticLabel: '${kind.label}の時刻 ${_spokenTime(time)}、変更',
        child: FcInfoBox(
          expand: false,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: FcRowValue.text(time.format(), muted: !active),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// 体重 7:30・夕食 20:00 をオンにした設定
RecordReminderSettings _previewWeightAndDinnerOn() =>
    RecordReminderSettings.defaults()
        .withSetting(
          ReminderKind.weight,
          const ReminderSetting(
            enabled: true,
            time: ReminderTime(hour: 7, minute: 30),
          ),
        )
        .withSetting(
          ReminderKind.dinner,
          const ReminderSetting(
            enabled: true,
            time: ReminderTime(hour: 20, minute: 0),
          ),
        );

/// プレビュー用の画面（Riverpod を使わず、実画面と同じ枠と行を並べる）
Widget _previewScreen({
  required Brightness brightness,
  RecordReminderSettings? settings,
  bool permissionDenied = false,
  double textScale = 1.0,
  Widget? body,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: _ReminderSettingsScaffold(
      showPermissionNotice: permissionDenied,
      onOpenNotificationSettings: () {},
      child: body ??
          _ReminderRowsCard(
            settings: settings ?? RecordReminderSettings.defaults(),
            onToggle: (_, __) {},
            onChangeTime: (_, __) {},
          ),
    ),
  );
}

@Preview(name: 'RecordReminderSettingsScreen - すべてオフ')
Widget previewRecordReminderSettingsAllOff() =>
    _previewScreen(brightness: Brightness.light);

@Preview(name: 'RecordReminderSettingsScreen - 体重 7:30・夕食 20:00')
Widget previewRecordReminderSettingsSomeOn() => _previewScreen(
      brightness: Brightness.light,
      settings: _previewWeightAndDinnerOn(),
    );

@Preview(name: 'RecordReminderSettingsScreen - 通知がオフ（案内）')
Widget previewRecordReminderSettingsPermissionDenied() => _previewScreen(
      brightness: Brightness.light,
      settings: _previewWeightAndDinnerOn(),
      permissionDenied: true,
    );

@Preview(name: 'RecordReminderSettingsScreen - すべてオフ（ダーク）')
Widget previewRecordReminderSettingsAllOffDark() =>
    _previewScreen(brightness: Brightness.dark);

/// ダーク: オンの時刻（textPrimary）とオフの時刻（textSecondary）が囲みの上で読めることを確認する
@Preview(name: 'RecordReminderSettingsScreen - 体重・夕食（ダーク）')
Widget previewRecordReminderSettingsSomeOnDark() => _previewScreen(
      brightness: Brightness.dark,
      settings: _previewWeightAndDinnerOn(),
    );

/// ダーク: 案内（warning）が暗い配色で読めることを確認する
@Preview(name: 'RecordReminderSettingsScreen - 通知がオフ（ダーク）')
Widget previewRecordReminderSettingsPermissionDeniedDark() => _previewScreen(
      brightness: Brightness.dark,
      settings: _previewWeightAndDinnerOn(),
      permissionDenied: true,
    );

/// 文字拡大: 表示名・補足・説明・案内は折り返し、時刻とトグルは1行のまま
@Preview(name: 'RecordReminderSettingsScreen - 文字拡大 1.35')
Widget previewRecordReminderSettingsLargeText() => _previewScreen(
      brightness: Brightness.light,
      settings: _previewWeightAndDinnerOn(),
      permissionDenied: true,
      textScale: 1.35,
    );

/// さらに大きな文字（2.0）: 時刻とトグルを表示名・補足の下へ右寄せで積み直す
@Preview(name: 'RecordReminderSettingsScreen - 文字拡大 2.0（積み直し）')
Widget previewRecordReminderSettingsExtraLargeText() => _previewScreen(
      brightness: Brightness.light,
      settings: _previewWeightAndDinnerOn(),
      textScale: 2.0,
    );

@Preview(name: 'RecordReminderSettingsScreen - 読み込み中')
Widget previewRecordReminderSettingsLoading() => _previewScreen(
      brightness: Brightness.light,
      body: const _ReminderRowsCard.loading(),
    );

@Preview(name: 'RecordReminderSettingsScreen - 読み込みエラー')
Widget previewRecordReminderSettingsError() => _previewScreen(
      brightness: Brightness.light,
      body: FcInlineNotice.error(
        message: 'リマインダーの設定を読み込めませんでした',
        actionLabel: '再試行',
        onAction: () {},
      ),
    );
