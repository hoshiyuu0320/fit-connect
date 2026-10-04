import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/screens/sessions_screen.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// ホームに表示する「次回のセッション」カード。
///
/// データあり / 予定なし / エラー / ローディングの4状態を持ち、
/// どの状態でもヘッダー（アイコン + 見出し）の構造は保持する
/// （docs/tasks/lessons.md「エラー状態のUX原則」）。
///
/// セッション一覧への唯一の入口なので、**予定が0件でも・取得に失敗しても**
/// 一覧（＝過去のセッション履歴）へ辿り着けるようにしてある。
///
/// 見た目は [NextSessionCardView]（正本: home-screens.js の `HomeSession`）。
class NextSessionCard extends ConsumerStatefulWidget {
  /// カードタップ時の遷移。未指定ならセッション一覧画面を push する
  final VoidCallback? onTap;

  /// トレーナーへの相談導線。draft はメッセージ入力欄へ流し込む定型文
  /// （予定なし時のCTAは定型文なし＝空文字を渡す）
  final void Function(String draft)? onConsult;

  /// 予定なしの文言に入れるトレーナーの表示名（「田中トレーナー」）。未指定なら「トレーナー」
  final String? trainerName;

  const NextSessionCard({
    super.key,
    this.onTap,
    this.onConsult,
    this.trainerName,
  });

  @override
  ConsumerState<NextSessionCard> createState() => _NextSessionCardState();
}

class _NextSessionCardState extends ConsumerState<NextSessionCard> {
  /// 一覧へ遷移中かどうか。連打で一覧が二重に push されるのを防ぐ
  bool _isNavigating = false;

  /// カードタップ時の既定動作。
  /// onTap が渡されていればそちらを優先し、無ければ一覧画面へ遷移する
  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap != null) {
      onTap();
      return;
    }

    if (_isNavigating) return;
    _isNavigating = true;

    // 一覧はフルスクリーンで push するため、「変更を相談」は
    // 一覧を閉じてから親のコールバックへ渡す
    final navigator = Navigator.of(context);
    final consult = widget.onConsult;
    // コールバックが二重に走っても MainScreen まで pop して空画面に
    // ならないよう、pop は一度きり・かつ canPop() を確認してから行う
    var consumed = false;

    final pushed = navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => SessionsScreen(
          onConsult: consult == null
              ? null
              : (draft) {
                  if (consumed) return;
                  consumed = true;
                  if (navigator.canPop()) navigator.pop();
                  consult(draft);
                },
        ),
      ),
    );
    // 一覧を閉じて戻ってきたら、次のタップを受け付けられるよう解除する
    pushed.whenComplete(() {
      if (mounted) _isNavigating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nextAsync = ref.watch(nextSessionProvider);
    final onConsult = widget.onConsult;

    return AnimatedSwitcher(
      duration: AppMotion.reduceOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: nextAsync.when(
        loading: () => const NextSessionCardView.loading(
          key: ValueKey('next-session-loading'),
        ),
        // 取得に失敗しても一覧へは行けるようにカード全体をタップ可能にする
        error: (_, __) => NextSessionCardView.error(
          key: const ValueKey('next-session-error'),
          onTap: _handleTap,
          // nextSession は upcomingSessions を watch しているため、
          // 実データを取り直すには上流を invalidate する
          onRetry: () => ref.invalidate(upcomingSessionsProvider),
        ),
        data: (session) {
          if (session == null) {
            // 予定0件のユーザーこそ過去の履歴を見たいので、
            // カード全体のタップ + 明示的な副次アクションの両方を用意する
            return NextSessionCardView.empty(
              key: const ValueKey('next-session-empty'),
              trainerName: widget.trainerName,
              onTap: _handleTap,
              onConsult: onConsult == null ? null : () => onConsult(''),
              onOpenList: _handleTap,
            );
          }

          // 1フレームの描画中に now を引き直すと日跨ぎで「今日」判定と
          // 「あとN日」が食い違うため、ここで1回だけ取得して配る
          return NextSessionCardView.session(
            key: ValueKey('next-session-${session.id}'),
            session: session,
            now: DateTime.now(),
            onTap: _handleTap,
          );
        },
      ),
    );
  }
}

enum _NextSessionKind { session, empty, error, loading }

/// 「次回のセッション」カードの見た目だけを担当する部分（プレビュー・テストでも使える）。
///
/// 正本: home-screens.js の `HomeSession`。
/// - [NextSessionCardView.session]: 見出し（calendar-days ＋ 右に chevron）／日時（20/500・tabular）＋
///   右に「あと2日」のピル／補足「60分 · パーソナル · 確定」
/// - [NextSessionCardView.empty]: 「予定はまだありません」＋ 相談のピルボタン ＋「これまでのセッション」
/// - [NextSessionCardView.error]: 見出しは保ったまま、再試行の導線
/// - [NextSessionCardView.loading]: 日時と補足の形のスケルトン
///
/// 色分けはしない（ステータス・当日も同じ見た目。言葉で区別する）。
class NextSessionCardView extends StatelessWidget {
  /// データあり
  const NextSessionCardView.session({
    super.key,
    required SessionModel this.session,
    required DateTime this.now,
    this.onTap,
  })  : _kind = _NextSessionKind.session,
        trainerName = null,
        onConsult = null,
        onOpenList = null,
        onRetry = null;

  /// 予定なし
  const NextSessionCardView.empty({
    super.key,
    this.trainerName,
    this.onTap,
    this.onConsult,
    this.onOpenList,
  })  : _kind = _NextSessionKind.empty,
        session = null,
        now = null,
        onRetry = null;

  /// 取得に失敗
  const NextSessionCardView.error({
    super.key,
    this.onTap,
    this.onRetry,
  })  : _kind = _NextSessionKind.error,
        session = null,
        now = null,
        trainerName = null,
        onConsult = null,
        onOpenList = null;

  /// 読み込み中
  const NextSessionCardView.loading({super.key})
      : _kind = _NextSessionKind.loading,
        session = null,
        now = null,
        trainerName = null,
        onTap = null,
        onConsult = null,
        onOpenList = null,
        onRetry = null;

  final _NextSessionKind _kind;
  final SessionModel? session;

  /// 呼び出し側が 1 回だけ取得した現在時刻（日跨ぎでの表示矛盾を防ぐ）
  final DateTime? now;
  final String? trainerName;

  /// カード全体のタップ（セッション一覧へ）
  final VoidCallback? onTap;
  final VoidCallback? onConsult;
  final VoidCallback? onOpenList;
  final VoidCallback? onRetry;

  static const String _heading = '次回のセッション';

  /// 見出し（右側に chevron を出すか）
  Widget _head(BuildContext context, {required bool chevron}) {
    final colors = AppColors.of(context);
    return FcCardHead(
      icon: LucideIcons.calendarDays,
      label: _heading,
      trailing: chevron
          ? ExcludeSemantics(
              child: Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: colors.textSecondary,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _NextSessionKind.loading:
        return _buildLoading(context);
      case _NextSessionKind.error:
        return _buildError(context);
      case _NextSessionKind.empty:
        return _buildEmpty(context);
      case _NextSessionKind.session:
        return _buildSession(context);
    }
  }

  Widget _buildSession(BuildContext context) {
    final session = this.session!;
    final now = this.now!;
    final dateLabel =
        formatSessionDateTimeDisplay(session.sessionDate, now: now);
    final daysLabel = _daysUntilLabel(session.daysUntilFrom(now));
    final typeLabel = sessionTypeLabel(session.sessionType);
    final meta = [
      '${session.durationMinutes}分',
      if (typeLabel != null) typeLabel,
      session.statusLabel,
    ].join(' · ');

    return FcCard(
      onTap: onTap,
      semanticLabel: '$_heading、$dateLabel、$daysLabel、$meta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(context, chevron: onTap != null),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Text(
                dateLabel,
                style: AppTextStyles.sectionHeading(context)
                    .copyWith(fontFeatures: AppTextStyles.tabularFigures),
              ),
              FcPill(daysLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(meta, style: AppTextStyles.supplement(context)),
        ],
      ),
    );
  }

  /// 残り日数（今日 / 明日 / あとN日）。日数は呼び出し側が 1 回の now から算出した値
  static String _daysUntilLabel(int daysUntil) {
    if (daysUntil <= 0) return '今日';
    if (daysUntil == 1) return '明日';
    return 'あと$daysUntil日';
  }

  Widget _buildEmpty(BuildContext context) {
    final name = trainerDisplayName(trainerName);
    return FcCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(context, chevron: false),
          Text('予定はまだありません', style: AppTextStyles.sectionHeading(context)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '日程は$nameと相談して決めます。',
            style: AppTextStyles.supplement(context),
          ),
          const SizedBox(height: 14),
          // 予定が無いユーザーでも履歴を見られるよう、相談に加えて一覧への導線を出す
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 6,
            children: [
              FcButton.pill(
                label: 'トレーナーに相談する',
                icon: LucideIcons.messageCircle,
                iconPosition: FcIconPosition.start,
                onPressed: onConsult,
              ),
              FcButton.back(
                label: 'これまでのセッション',
                icon: LucideIcons.chevronRight,
                iconPosition: FcIconPosition.end,
                onPressed: onOpenList,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return FcCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ヘッダーは全状態で共通（エラー時も構造を崩さない）
          _head(context, chevron: onTap != null),
          FcInlineNotice.error(
            message: 'セッション情報を読み込めませんでした',
            actionLabel: '再試行',
            onAction: onRetry,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return FcCard(
      semanticLabel: '次回のセッションを読み込んでいます',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(context, chevron: false),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.62,
            child: FcSkeleton(height: 22),
          ),
          const SizedBox(height: 10),
          const FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.4,
            child: FcSkeleton(height: 12),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用のダミーセッション生成（相対日付が常に成り立つよう now 基準で作る）
SessionModel _makePreviewSession({
  required Duration fromNow,
  String status = 'confirmed',
  String? sessionType = 'パーソナルトレーニング',
  int durationMinutes = 60,
}) {
  final now = DateTime.now();
  return SessionModel(
    id: 'preview-session',
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now.add(fromNow),
    durationMinutes: durationMinutes,
    status: status,
    sessionType: sessionType,
    createdAt: now,
    updatedAt: now,
  );
}

/// プレビューの共通枠（ホームと同じ余白・背景で表示する）
Widget _previewScaffold(
  Widget card, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: card,
        ),
      ),
    ),
  );
}

@Preview(name: 'NextSessionCard - With Data')
Widget previewNextSessionCardWithData() {
  return _previewScaffold(
    NextSessionCardView.session(
      session: _makePreviewSession(fromNow: const Duration(days: 3)),
      now: DateTime.now(),
      onTap: () {},
    ),
  );
}

@Preview(name: 'NextSessionCard - Today')
Widget previewNextSessionCardToday() {
  return _previewScaffold(
    NextSessionCardView.session(
      session: _makePreviewSession(
        fromNow: const Duration(hours: 3),
        status: 'scheduled',
        sessionType: 'ストレッチ',
        durationMinutes: 45,
      ),
      now: DateTime.now(),
      onTap: () {},
    ),
  );
}

@Preview(name: 'NextSessionCard - No Session')
Widget previewNextSessionCardNoSession() {
  return _previewScaffold(
    NextSessionCardView.empty(
      trainerName: '田中トレーナー',
      onTap: () {},
      onConsult: () {},
      onOpenList: () {},
    ),
  );
}

@Preview(name: 'NextSessionCard - Error')
Widget previewNextSessionCardError() {
  return _previewScaffold(
    NextSessionCardView.error(onTap: () {}, onRetry: () {}),
  );
}

@Preview(name: 'NextSessionCard - Loading')
Widget previewNextSessionCardLoading() {
  return _previewScaffold(const NextSessionCardView.loading());
}

@Preview(name: 'NextSessionCard - Dark / 文字 1.35')
Widget previewNextSessionCardDarkLarge() {
  return _previewScaffold(
    brightness: Brightness.dark,
    textScale: 1.35,
    NextSessionCardView.session(
      session: _makePreviewSession(fromNow: const Duration(days: 3)),
      now: DateTime.now(),
      onTap: () {},
    ),
  );
}
