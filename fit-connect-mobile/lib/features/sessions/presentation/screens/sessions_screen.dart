import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 一覧の表示対象（今後 / 過去）
enum _SessionsTab { upcoming, past }

const _tabItems = <FcSegmentedItem<_SessionsTab>>[
  FcSegmentedItem(value: _SessionsTab.upcoming, label: '今後'),
  FcSegmentedItem(value: _SessionsTab.past, label: '過去'),
];

/// セッション一覧画面（クライアント側）。
/// ホームの NextSessionCard からフルスクリーンで push される。
///
/// 正本: Claude Design の `more-screens.js` `SessionsScreen` / `SessionCard`。
/// AppBar をやめ、本文内の「戻る」＋ 見出し「セッション」＋ 今後/過去の切替 ＋ カードを縦に並べる。
///
/// ※ features/schedules（トレーナーの稼働可能時間）とは別ドメイン。
class SessionsScreen extends ConsumerStatefulWidget {
  /// 「変更を相談」タップ時。draft はメッセージ入力欄へ流し込む定型文。
  /// 導線は「今後」タブの、まだ生きている予定（キャンセル・完了以外）だけ
  /// （「過去」は終わったセッションのため出さない）。
  /// 遷移そのものは呼び出し側（MainScreen まで引き回したコールバック）の責務
  final void Function(String draft)? onConsult;

  const SessionsScreen({
    super.key,
    this.onConsult,
  });

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  _SessionsTab _tab = _SessionsTab.upcoming;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = _tab == _SessionsTab.upcoming;

    // 切替はローカルstateで持ち、対応するProviderをwatchする
    final sessionsAsync = isUpcoming
        ? ref.watch(upcomingSessionsProvider)
        : ref.watch(pastSessionsProvider);

    // ノート詳細のヘッダーに出す名前（カルテ一覧と同じ出典）。
    // 取得できないうちは null のままで、詳細側が名前欄ごと省略する
    final trainerName = ref.watch(trainerProfileProvider).valueOrNull?.name;

    return _SessionsScaffold(
      tab: _tab,
      onTabChanged: (tab) => setState(() => _tab = tab),
      child: sessionsAsync.when(
        loading: () => const _SessionsLoading(),
        error: (error, stack) => _SessionsErrorState(
          message: error.toString(),
          onRetry: () => ref.invalidate(
            isUpcoming ? upcomingSessionsProvider : pastSessionsProvider,
          ),
        ),
        data: (sessions) {
          if (sessions.isEmpty) {
            return _SessionsEmptyState(isUpcoming: isUpcoming);
          }

          return _SessionsList(
            sessions: sessions,
            isUpcoming: isUpcoming,
            trainerName: trainerName,
            onConsult: widget.onConsult,
          );
        },
      ),
    );
  }
}

/// 画面の枠（戻る・見出し・今後/過去の切替）と、その下の内容。
/// プレビューからも同じ実装を使えるよう Provider に依存させない
class _SessionsScaffold extends StatelessWidget {
  final _SessionsTab tab;
  final ValueChanged<_SessionsTab> onTabChanged;
  final Widget child;

  const _SessionsScaffold({
    required this.tab,
    required this.onTabChanged,
    required this.child,
  });

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
              const FcPageHeading(title: 'セッション', bottomSpacing: 20),
              FcSegmentedControl<_SessionsTab>(
                items: _tabItems,
                selected: tab,
                onChanged: onTabChanged,
              ),
              const SizedBox(height: AppSpacing.cardGap),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// セッションのカード列（間隔 16）。
/// プレビューからも同じ実装を使えるよう Provider に依存させない
class _SessionsList extends StatelessWidget {
  final List<SessionModel> sessions;
  final bool isUpcoming;

  /// ノート詳細へ渡すトレーナー名（未取得なら null）
  final String? trainerName;

  final void Function(String draft)? onConsult;

  const _SessionsList({
    required this.sessions,
    required this.isUpcoming,
    this.trainerName,
    this.onConsult,
  });

  @override
  Widget build(BuildContext context) {
    // now は全行で共有する（行ごとに引き直すと日跨ぎで年表示がズレる）
    final now = DateTime.now();

    // 「あとN日」は、今後のうち最初の「生きている予定」（＝次回）にだけ付ける
    final nextIndex = isUpcoming ? sessions.indexWhere((s) => !s.isClosed) : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sessions.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.cardGap),
          _SessionListTile(
            key: ValueKey(sessions[index].id),
            session: sessions[index],
            now: now,
            // キャンセルは淡色（0.55）。ステータスの色分けはせず文言で示す
            dimmed: sessions[index].statusType == SessionStatus.cancelled,
            untilLabel:
                index == nextIndex ? _untilLabel(sessions[index], now) : null,
            trainerName: trainerName,
            // 「過去」は終わったセッション、キャンセル・完了は動かせないので相談導線を出さない
            onConsult:
                isUpcoming && !sessions[index].isClosed ? onConsult : null,
          ),
        ],
      ],
    );
  }
}

/// 次回までの日数（今日 / 明日 / あとN日）。日付が過ぎていれば null
String? _untilLabel(SessionModel session, DateTime now) {
  final days = session.daysUntilFrom(now);
  if (days < 0) return null;
  if (days == 0) return '今日';
  if (days == 1) return '明日';
  return 'あと$days日';
}

/// 一覧の1枚（日時・所要時間・種別・ステータスの文言、操作「変更を相談」「ノート」）
///
/// 共有ノートが紐づく行だけ「ノート」でカルテ詳細へ push する。ノートが無い行には出さない。
/// ノート導線は「今後 / 過去」の両方で有効（事前の注意事項を共有する運用があるため）
class _SessionListTile extends StatelessWidget {
  final SessionModel session;

  /// 1フレームにつき1回だけ引いた現在時刻（日時の年判定に使う。
  /// 年は今年と違うときだけ付く。過去タブが年をまたいでも曖昧にならない）
  final DateTime now;

  /// 淡色表示（キャンセル）
  final bool dimmed;

  /// 日時の右に出す「あと2日」などのピル。null なら出さない
  final String? untilLabel;

  /// ノート詳細へ渡すトレーナー名（未取得なら null）
  final String? trainerName;

  final void Function(String draft)? onConsult;

  const _SessionListTile({
    super.key,
    required this.session,
    required this.now,
    this.dimmed = false,
    this.untilLabel,
    this.trainerName,
    this.onConsult,
  });

  /// カルテ詳細へ遷移（ノートがある行のみ呼ばれる）
  void _openNote(BuildContext context, ClientNote note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientNoteDetailScreen(
          note: note,
          trainerName: trainerName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = sessionTypeLabel(session.sessionType);
    final consult = onConsult;
    // 共有済みノート（未共有はRLSでもモデル側でも落ちている）。null なら導線を出さない
    final note = session.sharedNote;
    final hasActions = consult != null || note != null;
    final until = untilLabel;

    // 「60分 · パーソナル · 確定」。ステータスは色ではなく文言で示す
    final meta = [
      '${session.durationMinutes}分',
      if (typeLabel != null) typeLabel,
      session.statusLabel,
    ].join(' · ');

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: FcCard(
        // 操作行の下は -8（ボタンの高さ 44 のぶん、文字の下に余白があるため）
        paddingOverride: EdgeInsets.fromLTRB(
          AppSpacing.cardPadding,
          AppSpacing.cardPadding,
          AppSpacing.cardPadding,
          hasActions ? AppSpacing.cardPadding - 8 : AppSpacing.cardPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                Text(
                  formatSessionDateTimeDisplay(session.sessionDate, now: now),
                  style: AppTextStyles.sectionHeading(context).copyWith(
                    fontFeatures: AppTextStyles.tabularFigures,
                  ),
                ),
                if (until != null) FcPill(until),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(meta, style: AppTextStyles.supplement(context)),
            ),
            // 相談導線・ノート導線（タッチターゲット44px確保）。
            // 定型文は push 通知本文と同じ表記（formatSessionDateTime）で作る
            if (hasActions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 22,
                  children: [
                    if (consult != null)
                      FcButton.back(
                        label: '変更を相談',
                        icon: LucideIcons.messageCircle,
                        onPressed: () => consult(
                          buildSessionConsultDraft(
                            formatSessionDateTime(session.sessionDate,
                                now: now),
                          ),
                        ),
                      ),
                    if (note != null)
                      FcButton.back(
                        label: 'ノート',
                        icon: LucideIcons.fileText,
                        onPressed: () => _openNote(context, note),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 読み込み中（カードの配置を保つ）
class _SessionsLoading extends StatelessWidget {
  const _SessionsLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '読み込み中',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.cardGap),
            const FcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FcSkeleton.line(width: 190, height: 22),
                  SizedBox(height: AppSpacing.sm),
                  FcSkeleton.line(width: 140),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 空状態（メッセージ + 補足。真っ白にしない）
class _SessionsEmptyState extends StatelessWidget {
  final bool isUpcoming;

  const _SessionsEmptyState({required this.isUpcoming});

  @override
  Widget build(BuildContext context) {
    return FcStateMessage.empty(
      title: isUpcoming ? '予定されているセッションはありません' : '過去のセッションはありません',
      message: isUpcoming
          ? '次回の予約についてトレーナーに相談してみましょう。'
          : '完了・キャンセルしたセッションがここに表示されます。',
    );
  }
}

/// エラー状態（必ずリトライ導線を出す）
class _SessionsErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SessionsErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FcStateMessage.error(
      title: 'エラーが発生しました',
      message: message,
      actionLabel: 'リトライ',
      actionIcon: LucideIcons.refreshCw,
      onAction: onRetry,
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用のダミー共有ノート生成（embed で返ってくる形を模す）
ClientNote _makePreviewNote({
  required String id,
  required String sessionId,
  required String title,
}) {
  final now = DateTime.now();
  return ClientNote(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: title,
    content: '本日の内容と次回に向けたポイントをまとめています。',
    isShared: true,
    sharedAt: now,
    sessionId: sessionId,
    createdAt: now,
    updatedAt: now,
  );
}

/// プレビュー用のダミーセッション生成（相対日付が常に成り立つよう now 基準で作る）
///
/// [noteTitle] を渡した行だけ共有ノートが紐づき、「ノート」の操作が出る
SessionModel _makePreviewSession({
  required String id,
  required Duration fromNow,
  required String status,
  String? sessionType,
  int durationMinutes = 60,
  String? noteTitle,
}) {
  final now = DateTime.now();
  return SessionModel(
    id: id,
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now.add(fromNow),
    durationMinutes: durationMinutes,
    status: status,
    sessionType: sessionType,
    notes: noteTitle == null
        ? const []
        : [
            _makePreviewNote(
              id: '$id-note',
              sessionId: id,
              title: noteTitle,
            ),
          ],
    createdAt: now,
    updatedAt: now,
  );
}

/// プレビュー用ヘルパーWidget（Riverpodを使わず一覧のUIを再現）
class _PreviewSessionsView extends StatelessWidget {
  final _SessionsTab tab;
  final List<SessionModel>? sessions;

  const _PreviewSessionsView({
    required this.tab,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final isUpcoming = tab == _SessionsTab.upcoming;
    final list = sessions;

    return _SessionsScaffold(
      tab: tab,
      onTabChanged: (_) {},
      child: list == null
          ? const _SessionsLoading()
          : list.isEmpty
              ? _SessionsEmptyState(isUpcoming: isUpcoming)
              : _SessionsList(
                  sessions: list,
                  isUpcoming: isUpcoming,
                  trainerName: '山田太郎',
                  onConsult: (_) {},
                ),
    );
  }
}

List<SessionModel> _previewUpcomingSessions() => [
      // 事前の注意事項を共有されたケース（「今後」でもノート導線は出る）
      _makePreviewSession(
        id: 'preview-1',
        fromNow: const Duration(days: 2),
        status: 'confirmed',
        sessionType: 'パーソナルトレーニング',
        noteTitle: '次回セッションの事前確認',
      ),
      _makePreviewSession(
        id: 'preview-2',
        fromNow: const Duration(days: 9),
        status: 'scheduled',
        sessionType: 'ストレッチ',
        durationMinutes: 45,
      ),
      // 未来のキャンセル済み（「今後」に残るが淡色で区別される）
      _makePreviewSession(
        id: 'preview-3',
        fromNow: const Duration(days: 16),
        status: 'cancelled',
        sessionType: 'カウンセリング',
      ),
    ];

@Preview(name: 'SessionsScreen - Upcoming')
Widget previewSessionsScreenUpcoming() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewSessionsView(
      tab: _SessionsTab.upcoming,
      sessions: _previewUpcomingSessions(),
    ),
  );
}

@Preview(name: 'SessionsScreen - Upcoming (Dark)')
Widget previewSessionsScreenUpcomingDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: _PreviewSessionsView(
      tab: _SessionsTab.upcoming,
      sessions: _previewUpcomingSessions(),
    ),
  );
}

@Preview(name: 'SessionsScreen - Upcoming (Large Text 1.35)')
Widget previewSessionsScreenUpcomingLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: _PreviewSessionsView(
      tab: _SessionsTab.upcoming,
      sessions: _previewUpcomingSessions(),
    ),
  );
}

@Preview(name: 'SessionsScreen - Past')
Widget previewSessionsScreenPast() {
  final sessions = [
    // ノートあり: 「ノート」の操作が出る
    _makePreviewSession(
      id: 'preview-past-1',
      fromNow: const Duration(days: -2),
      status: 'completed',
      sessionType: 'パーソナルトレーニング',
      noteTitle: '第3回セッションの記録',
    ),
    // ノートなし: 操作なし
    _makePreviewSession(
      id: 'preview-past-2',
      fromNow: const Duration(days: -9),
      status: 'cancelled',
      sessionType: 'カウンセリング',
      durationMinutes: 30,
    ),
    // 年をまたいだ行（過去タブは年付きで表示される）
    _makePreviewSession(
      id: 'preview-past-3',
      fromNow: const Duration(days: -400),
      status: 'completed',
      sessionType: 'パーソナルトレーニング',
      noteTitle: '初回カウンセリングの記録',
    ),
  ];

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewSessionsView(
      tab: _SessionsTab.past,
      sessions: sessions,
    ),
  );
}

@Preview(name: 'SessionsScreen - Empty')
Widget previewSessionsScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewSessionsView(
      tab: _SessionsTab.upcoming,
      sessions: [],
    ),
  );
}

@Preview(name: 'SessionsScreen - Loading')
Widget previewSessionsScreenLoading() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewSessionsView(
      tab: _SessionsTab.upcoming,
      sessions: null,
    ),
  );
}
