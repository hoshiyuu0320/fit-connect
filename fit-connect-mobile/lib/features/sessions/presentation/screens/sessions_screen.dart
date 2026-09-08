import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_meta_chip.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_status_badge.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/shared/widgets/segmented_control.dart';

/// 一覧の表示対象（今後 / 過去）
enum _SessionsTab { upcoming, past }

const _tabItems = <SegmentedControlItem<_SessionsTab>>[
  SegmentedControlItem(value: _SessionsTab.upcoming, label: '今後'),
  SegmentedControlItem(value: _SessionsTab.past, label: '過去'),
];

/// セッション一覧画面（クライアント側）。
/// ホームの NextSessionCard からフルスクリーンで push される。
///
/// ※ features/schedules（トレーナーの稼働可能時間）とは別ドメイン。
class SessionsScreen extends ConsumerStatefulWidget {
  /// 「変更を相談」タップ時。draft はメッセージ入力欄へ流し込む定型文。
  /// 導線は「今後」タブのみ（「過去」は終わったセッションのため出さない）。
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
    final colors = AppColors.of(context);
    final isUpcoming = _tab == _SessionsTab.upcoming;

    // 切替はローカルstateで持ち、対応するProviderをwatchする
    final sessionsAsync = isUpcoming
        ? ref.watch(upcomingSessionsProvider)
        : ref.watch(pastSessionsProvider);

    // ノート詳細のヘッダーに出す名前（カルテ一覧と同じ出典）。
    // 取得できないうちは null のままで、詳細側が名前欄ごと省略する
    final trainerName = ref.watch(trainerProfileProvider).valueOrNull?.name;

    return Scaffold(
      backgroundColor: colors.surfaceDim,
      appBar: AppBar(
        title: const Text('セッション'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedControl<_SessionsTab>(
                items: _tabItems,
                selected: _tab,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
            Expanded(
              child: sessionsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => _SessionsErrorState(
                  message: error.toString(),
                  onRetry: () => ref.invalidate(
                    isUpcoming
                        ? upcomingSessionsProvider
                        : pastSessionsProvider,
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
            ),
          ],
        ),
      ),
    );
  }
}

/// セッションのリスト本体。
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionListTile(
          key: ValueKey(session.id),
          session: session,
          // 過去は最大50件で年をまたぐため常に年を出す
          dateTimeLabel: formatSessionDateTime(
            session.sessionDate,
            now: now,
            includeYear: !isUpcoming,
          ),
          // 「今後」には未来のキャンセル/完了も時系列どおり残るので、
          // 生きている予定と区別できるよう淡色にする
          dimmed: isUpcoming && session.isClosed,
          trainerName: trainerName,
          // 「過去」は終わったセッションなので相談導線を出さない
          onConsult: isUpcoming ? onConsult : null,
        );
      },
    );
  }
}

/// 一覧の1行（日時・所要時間・種別・ステータス、および「今後」のみ「変更を相談」）
///
/// 共有ノートが紐づく行だけ「ノート」チップ + chevron を出し、行タップで
/// カルテ詳細へ push する。ノートが無い行はタップ不可のまま（空振りタップを作らない）。
/// ノート導線は「今後 / 過去」の両方で有効（事前の注意事項を共有する運用があるため）
class _SessionListTile extends StatelessWidget {
  final SessionModel session;

  /// 表示と定型文で共通に使う日時ラベル（画面側で now を1回だけ引いて生成する）
  final String dateTimeLabel;

  /// 予定として生きていない（キャンセル/完了）セッションを淡色表示にするか
  final bool dimmed;

  /// ノート詳細へ渡すトレーナー名（未取得なら null）
  final String? trainerName;

  final void Function(String draft)? onConsult;

  const _SessionListTile({
    super.key,
    required this.session,
    required this.dateTimeLabel,
    this.dimmed = false,
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
    final colors = AppColors.of(context);
    final typeLabel = sessionTypeLabel(session.sessionType);
    final consult = onConsult;
    // 共有済みノート（未共有はRLSでもモデル側でも落ちている）。null なら導線を出さない
    final note = session.sharedNote;

    final tile = Container(
      decoration: BoxDecoration(
        color: dimmed ? colors.surfaceDim : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateTimeLabel,
                  style: TextStyle(
                    color: dimmed ? colors.textSecondary : colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SessionStatusBadge(session: session),
            ],
          ),

          const SizedBox(height: 8),

          // 所要時間 / 種別 / ノート。
          // chevron は「この行はタップで開ける」ことの合図なので、
          // ノートがある行にだけ出す
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
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
                    if (note != null)
                      const SessionMetaChip(
                        icon: LucideIcons.fileText,
                        label: 'ノート',
                      ),
                  ],
                ),
              ),
              if (note != null) ...[
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: colors.textHint,
                ),
              ],
            ],
          ),

          // 相談導線（タッチターゲット44px確保）。
          // 定型文は表示中のラベルから作り、画面表示と必ず一致させる。
          // 「過去」タブは onConsult が null で渡るため、ボタンごと描画しない
          if (consult != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _ConsultButton(
                onTap: () => consult(buildSessionConsultDraft(dateTimeLabel)),
              ),
            ),
          ],
        ],
      ),
    );

    // ノートが無い行はタップ不可のまま返す（GestureDetectorごと巻かない）
    if (note == null) return tile;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openNote(context, note),
      child: tile,
    );
  }
}

/// 「変更を相談」ボタン（「今後」タブ専用）
///
/// 無効状態の見た目を持たないため、押せない場面では
/// このボタン自体を描画しない（onTap は非 null 必須）
class _ConsultButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ConsultButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.messageCircle,
              size: 16,
              color: AppColors.primary600,
            ),
            SizedBox(width: 6),
            Text(
              '変更を相談',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary600,
              ),
            ),
          ],
        ),
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
    final colors = AppColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUpcoming ? LucideIcons.calendarX : LucideIcons.history,
              size: 48,
              color: colors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              isUpcoming ? '予定されているセッションはありません' : '過去のセッションはありません',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isUpcoming
                  ? '次回の予約についてトレーナーに相談してみましょう。'
                  : '完了・キャンセルしたセッションがここに表示されます。',
              style: TextStyle(
                color: colors.textHint,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
    final colors = AppColors.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.alertCircle,
              size: 48,
              color: AppColors.rose800,
            ),
            const SizedBox(height: 16),
            Text(
              'エラーが発生しました',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'リトライ',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
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
/// [noteTitle] を渡した行だけ共有ノートが紐づき、「ノート」チップ + chevron が出る
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
class _PreviewSessionsList extends StatelessWidget {
  final _SessionsTab tab;
  final List<SessionModel> sessions;

  const _PreviewSessionsList({
    required this.tab,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isUpcoming = tab == _SessionsTab.upcoming;

    return Scaffold(
      backgroundColor: colors.surfaceDim,
      appBar: AppBar(
        title: const Text('セッション'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedControl<_SessionsTab>(
                items: _tabItems,
                selected: tab,
                onChanged: (_) {},
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? _SessionsEmptyState(isUpcoming: isUpcoming)
                  : _SessionsList(
                      sessions: sessions,
                      isUpcoming: isUpcoming,
                      trainerName: '山田太郎',
                      onConsult: (_) {},
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

@Preview(name: 'SessionsScreen - Upcoming')
Widget previewSessionsScreenUpcoming() {
  final sessions = [
    // 事前の注意事項を共有されたケース（「今後」でもノート導線は出る）
    _makePreviewSession(
      id: 'preview-1',
      fromNow: const Duration(hours: 5),
      status: 'confirmed',
      sessionType: 'パーソナルトレーニング',
      noteTitle: '次回セッションの事前確認',
    ),
    _makePreviewSession(
      id: 'preview-2',
      fromNow: const Duration(days: 3),
      status: 'scheduled',
      sessionType: 'ストレッチ',
      durationMinutes: 45,
    ),
    // 未来のキャンセル済み（「今後」に残るが淡色で区別される）
    _makePreviewSession(
      id: 'preview-3',
      fromNow: const Duration(days: 7),
      status: 'cancelled',
      sessionType: 'パーソナルトレーニング',
    ),
    _makePreviewSession(
      id: 'preview-4',
      fromNow: const Duration(days: 10),
      status: 'scheduled',
      sessionType: 'other',
      durationMinutes: 90,
    ),
  ];

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewSessionsList(
      tab: _SessionsTab.upcoming,
      sessions: sessions,
    ),
  );
}

@Preview(name: 'SessionsScreen - Past')
Widget previewSessionsScreenPast() {
  final sessions = [
    // ノートあり: 「ノート」チップ + 右端の chevron が出てタップできる
    _makePreviewSession(
      id: 'preview-past-1',
      fromNow: const Duration(days: -2),
      status: 'completed',
      sessionType: 'パーソナルトレーニング',
      noteTitle: '第3回セッションの記録',
    ),
    // ノートなし: チップも chevron も出ず、タップ不可
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
    home: _PreviewSessionsList(
      tab: _SessionsTab.past,
      sessions: sessions,
    ),
  );
}

@Preview(name: 'SessionsScreen - Empty')
Widget previewSessionsScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewSessionsList(
      tab: _SessionsTab.upcoming,
      sessions: [],
    ),
  );
}
