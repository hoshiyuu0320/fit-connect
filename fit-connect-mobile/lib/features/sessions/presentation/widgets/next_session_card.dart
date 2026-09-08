import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/screens/sessions_screen.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_meta_chip.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_status_badge.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';

/// ホームに表示する「次回のセッション」カード。
///
/// データあり / 当日 / 予定なし / エラー / ローディングの5状態を持ち、
/// どの状態でもヘッダー（アイコン + 見出し）の構造は保持する
/// （docs/tasks/lessons.md「エラー状態のUX原則」）。
///
/// セッション一覧への唯一の入口なので、**予定が0件でも・取得に失敗しても**
/// 一覧（＝過去のセッション履歴）へ辿り着けるようにしてある。
class NextSessionCard extends ConsumerStatefulWidget {
  /// カードタップ時の遷移。未指定ならセッション一覧画面を push する
  final VoidCallback? onTap;

  /// トレーナーへの相談導線。draft はメッセージ入力欄へ流し込む定型文
  /// （予定なし時のCTAは定型文なし＝空文字を渡す）
  final void Function(String draft)? onConsult;

  const NextSessionCard({
    super.key,
    this.onTap,
    this.onConsult,
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
      duration: const Duration(milliseconds: 200),
      child: nextAsync.when(
        loading: () => const _NextSessionCardShell(
          key: ValueKey('next-session-loading'),
          child: _NextSessionLoading(),
        ),
        // 取得に失敗しても一覧へは行けるようにカード全体をタップ可能にする
        error: (_, __) => GestureDetector(
          key: const ValueKey('next-session-error'),
          onTap: _handleTap,
          child: _NextSessionCardShell(
            showChevron: true,
            child: _NextSessionError(
              // nextSession は upcomingSessions を watch しているため、
              // 実データを取り直すには上流を invalidate する
              onRetry: () => ref.invalidate(upcomingSessionsProvider),
            ),
          ),
        ),
        data: (session) {
          if (session == null) {
            // 予定0件のユーザーこそ過去の履歴を見たいので、
            // カード全体のタップ + 明示的な副次アクションの両方を用意する
            return GestureDetector(
              key: const ValueKey('next-session-empty'),
              onTap: _handleTap,
              child: _NextSessionCardShell(
                showChevron: true,
                child: _NextSessionEmpty(
                  onConsult: onConsult == null ? null : () => onConsult(''),
                  onOpenList: _handleTap,
                ),
              ),
            );
          }

          // 1フレームの描画中に now を引き直すと日跨ぎで「今日」判定と
          // 「あとN日」が食い違うため、ここで1回だけ取得して配る
          final now = DateTime.now();
          final daysUntil = session.daysUntilFrom(now);

          return GestureDetector(
            key: ValueKey('next-session-${session.id}'),
            onTap: _handleTap,
            child: _NextSessionCardShell(
              highlighted: daysUntil == 0,
              showChevron: true,
              child: _NextSessionContent(session: session, now: now),
            ),
          );
        },
      ),
    );
  }
}

/// カードの外枠 + 共通ヘッダー。
/// 当日セッションは primary のボーダーで強調する
class _NextSessionCardShell extends StatelessWidget {
  final bool highlighted;
  final bool showChevron;
  final Widget child;

  const _NextSessionCardShell({
    super.key,
    this.highlighted = false,
    this.showChevron = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted ? AppColors.primary600 : colors.border,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダーは全状態で共通（エラー時も構造を崩さない）
          Row(
            children: [
              Icon(
                LucideIcons.calendarClock,
                size: 18,
                color: highlighted ? AppColors.primary600 : colors.textHint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '次回のセッション',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showChevron)
                Icon(
                  LucideIcons.chevronRight,
                  size: 20,
                  color: colors.textHint,
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

/// データあり時の中身（日時 + 残り日数 + 所要時間 / 種別 / ステータス）。
/// [now] は呼び出し側が1回だけ取得した現在時刻（日跨ぎでの表示矛盾を防ぐ）
class _NextSessionContent extends StatelessWidget {
  final SessionModel session;
  final DateTime now;

  const _NextSessionContent({
    required this.session,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final typeLabel = sessionTypeLabel(session.sessionType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                formatSessionDateTime(session.sessionDate, now: now),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DaysUntilBadge(daysUntil: session.daysUntilFrom(now)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SessionMetaChip(
              icon: LucideIcons.clock,
              label: '${session.durationMinutes}分',
            ),
            if (typeLabel != null)
              SessionMetaChip(
                icon: LucideIcons.dumbbell,
                label: typeLabel,
              ),
            SessionStatusBadge(session: session),
          ],
        ),
      ],
    );
  }
}

/// 残り日数バッジ（今日 / 明日 / あとN日）。
/// 日数は呼び出し側が1回の now から算出した値を受け取り、ここでは再計算しない
class _DaysUntilBadge extends StatelessWidget {
  final int daysUntil;

  const _DaysUntilBadge({required this.daysUntil});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    final String label;
    final Color background;
    final Color foreground;
    if (daysUntil == 0) {
      label = '今日';
      background = AppColors.primary600;
      foreground = Colors.white;
    } else if (daysUntil == 1) {
      label = '明日';
      background = AppColors.primary50;
      foreground = AppColors.primary700;
    } else {
      label = 'あと$daysUntil日';
      background = colors.border;
      foreground = colors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// 予定なし（メッセージ + アクションで空状態を埋める）。
/// 予定が無いユーザーでも履歴を見られるよう、相談CTAに加えて一覧導線を出す
class _NextSessionEmpty extends StatelessWidget {
  final VoidCallback? onConsult;
  final VoidCallback? onOpenList;

  const _NextSessionEmpty({this.onConsult, this.onOpenList});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '予定されているセッションはありません',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '次回の予約についてトレーナーに相談してみましょう。',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _CardActionButton(
          icon: LucideIcons.messageCircle,
          label: 'トレーナーに相談',
          filled: true,
          onTap: onConsult,
        ),
        const SizedBox(height: 8),
        _CardActionButton(
          icon: LucideIcons.history,
          label: 'セッション履歴を見る',
          onTap: onOpenList,
        ),
      ],
    );
  }
}

/// エラー（ヘッダーは保持したままリトライ導線を出す）
class _NextSessionError extends StatelessWidget {
  final VoidCallback onRetry;

  const _NextSessionError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              LucideIcons.alertCircle,
              size: 18,
              color: AppColors.rose800,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'セッション情報を読み込めませんでした',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CardActionButton(
          icon: LucideIcons.refreshCw,
          label: 'リトライ',
          onTap: onRetry,
        ),
      ],
    );
  }
}

/// ローディング（カード構造を保ったままプレースホルダを出す）
class _NextSessionLoading extends StatelessWidget {
  const _NextSessionLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.slate400,
          ),
        ),
      ),
    );
  }
}

/// カード内のアクションボタン（タッチターゲット44px確保）
class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  const _CardActionButton({
    required this.icon,
    required this.label,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final foreground = filled ? Colors.white : AppColors.primary600;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary600 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
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
Widget _previewScaffold(Widget card) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: card,
        ),
      ),
    ),
  );
}

@Preview(name: 'NextSessionCard - With Data')
Widget previewNextSessionCardWithData() {
  return _previewScaffold(
    _NextSessionCardShell(
      showChevron: true,
      child: _NextSessionContent(
        session: _makePreviewSession(fromNow: const Duration(days: 3)),
        now: DateTime.now(),
      ),
    ),
  );
}

@Preview(name: 'NextSessionCard - Today')
Widget previewNextSessionCardToday() {
  return _previewScaffold(
    _NextSessionCardShell(
      highlighted: true,
      showChevron: true,
      child: _NextSessionContent(
        session: _makePreviewSession(
          fromNow: const Duration(hours: 3),
          status: 'scheduled',
          sessionType: 'ストレッチ',
          durationMinutes: 45,
        ),
        now: DateTime.now(),
      ),
    ),
  );
}

@Preview(name: 'NextSessionCard - No Session')
Widget previewNextSessionCardNoSession() {
  return _previewScaffold(
    _NextSessionCardShell(
      showChevron: true,
      child: _NextSessionEmpty(
        onConsult: () {},
        onOpenList: () {},
      ),
    ),
  );
}

@Preview(name: 'NextSessionCard - Error')
Widget previewNextSessionCardError() {
  return _previewScaffold(
    _NextSessionCardShell(
      showChevron: true,
      child: _NextSessionError(onRetry: () {}),
    ),
  );
}
