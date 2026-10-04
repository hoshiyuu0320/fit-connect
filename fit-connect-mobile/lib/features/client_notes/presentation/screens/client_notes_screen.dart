import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/note_card.dart';
import 'package:fit_connect_mobile/features/client_notes/providers/client_notes_provider.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 記録タブの「ノート」サブタブの本文（トレーナーが共有したカルテの一覧）。
///
/// 見出し・サブタブは記録タブの枠（`RecordsScreen`）が持つ。この画面は本文だけ。
/// 正本 `record-screens.js` の `NotesTab`: 上に caption「{トレーナー名}が共有したカルテ」→
/// `NoteCard` を縦に並べる（カード間 16）。カードを押すとカルテの詳細へ。
/// 状態: 読み込み中（スケルトン）／共有されたノートがない／読み込めなかった（再試行）。
class ClientNotesScreen extends ConsumerWidget {
  const ClientNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // カルテ一覧の取得
    final notesAsync = ref.watch(sharedClientNotesProvider);

    // トレーナー名の取得
    final trainerAsync = ref.watch(trainerProfileProvider);
    final trainerName = trainerAsync.valueOrNull?.name;

    return ClientNotesBody(
      notes: notesAsync,
      trainerName: trainerName,
      onRetry: () => ref.invalidate(sharedClientNotesProvider),
      onOpen: (note) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClientNoteDetailScreen(
              note: note,
              trainerName: trainerName,
            ),
          ),
        );
      },
    );
  }
}

/// ノート一覧の本文（見た目だけ。取得・遷移は [ClientNotesScreen] が持つ）
class ClientNotesBody extends StatelessWidget {
  final AsyncValue<List<ClientNote>> notes;
  final String? trainerName;
  final VoidCallback onRetry;
  final ValueChanged<ClientNote> onOpen;

  const ClientNotesBody({
    super.key,
    required this.notes,
    required this.trainerName,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    const gap = SizedBox(height: AppSpacing.cardGap);

    // 上の余白（サブタブとの間 16）は記録タブの枠が空ける。
    // 下は、下部ナビぶん（MediaQuery の下余白）を自分で受け取る
    final padding = EdgeInsets.fromLTRB(
      horizontal,
      0,
      horizontal,
      MediaQuery.paddingOf(context).bottom,
    );

    return notes.when(
      loading: () => ListView(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _CaptionSkeleton(),
          gap,
          FcSkeleton.card(height: 168),
          gap,
          FcSkeleton.card(height: 168),
          gap,
          FcSkeleton.card(height: 168),
        ],
      ),
      error: (error, stack) => ListView(
        padding: padding,
        children: [
          FcStateMessage.error(
            title: 'カルテを読み込めませんでした',
            message: 'しばらくしてからもう一度お試しください。',
            actionLabel: '再試行',
            onAction: onRetry,
          ),
        ],
      ),
      data: (list) {
        if (list.isEmpty) {
          return ListView(
            padding: padding,
            children: const [
              FcStateMessage.empty(
                title: '共有されたノートはありません',
                message: 'トレーナーからまだセッションノートが共有されていません。',
              ),
            ],
          );
        }

        // セッション日時の年付与判定用。行ごとに引き直すと日跨ぎで
        // 年表示が食い違うため、ここで1回だけ取得して各カードに配る
        final now = DateTime.now();

        return ListView(
          padding: padding,
          children: [
            _Caption(trainerName: trainerName),
            gap,
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) gap,
              NoteCard(
                note: list[i],
                now: now,
                trainerName: trainerName,
                onTap: () => onOpen(list[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 一覧の先頭の caption「{トレーナー名}が共有したカルテ」（正本: 左右 4）
class _Caption extends StatelessWidget {
  final String? trainerName;
  const _Caption({required this.trainerName});

  /// トレーナー名が分からなければ「トレーナー」とする（「田中」でも「田中トレーナー」でも同じ表示）
  static String textFor(String? trainerName) {
    return '${trainerDisplayName(trainerName)}が共有したカルテ';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        textFor(trainerName),
        style: AppTextStyles.caption(context),
      ),
    );
  }
}

/// 読み込み中の caption の帯
class _CaptionSkeleton extends StatelessWidget {
  const _CaptionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '読み込み中',
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        // ListView の幅いっぱいの制約に負けないよう左寄せで包む
        child: Align(
          alignment: Alignment.centerLeft,
          child: FcSkeleton.line(width: 180, height: 12),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

List<ClientNote> _previewNotes() {
  ClientNote note({
    required String id,
    required String title,
    required String content,
    required DateTime created,
    List<String> files = const [],
    LinkedSession? session,
  }) {
    return ClientNote(
      id: id,
      clientId: 'client-1',
      trainerId: 'trainer-1',
      title: title,
      content: content,
      fileUrls: files,
      isShared: true,
      sharedAt: created,
      sessionId: session == null ? null : 'session-$id',
      session: session,
      createdAt: created,
      updatedAt: created,
    );
  }

  return [
    note(
      id: '1',
      title: '上半身のフォーム確認',
      content: 'ダンベルプレスは肩甲骨を寄せたまま下ろせていました。次回は12 kgで10回×3セットを目安にします。',
      created: DateTime(2026, 9, 8, 21),
      files: const ['a.jpg', 'b.pdf'],
      session: LinkedSession(
        sessionDate: DateTime(2026, 9, 8, 19),
        sessionType: 'パーソナル',
      ),
    ),
    note(
      id: '2',
      title: '目標の見直し',
      content: '体重を増やしながら筋力をつける方針を確認しました。朝食でたんぱく質をとる習慣を続けましょう。',
      created: DateTime(2026, 9, 1, 21),
      files: const ['c.jpg'],
      session: LinkedSession(
        sessionDate: DateTime(2026, 9, 1, 19),
        sessionType: 'パーソナル',
      ),
    ),
    note(
      id: '3',
      title: '食事のポイント',
      content: '毎食、手のひら1枚分のたんぱく質を目安にしましょう。間食はヨーグルトやナッツがおすすめです。',
      created: DateTime(2026, 8, 25, 18),
    ),
  ];
}

Widget _previewScreen({
  required Brightness brightness,
  required AsyncValue<List<ClientNote>> notes,
  double scale = 1,
}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: ClientNotesBody(
          notes: notes,
          trainerName: '田中トレーナー',
          onRetry: () {},
          onOpen: (_) {},
        ),
      ),
    ),
  );
}

@Preview(name: 'ClientNotesScreen - 通常（ライト）')
Widget previewClientNotesScreenWithData() => _previewScreen(
      brightness: Brightness.light,
      notes: AsyncValue.data(_previewNotes()),
    );

@Preview(name: 'ClientNotesScreen - 通常（ダーク）')
Widget previewClientNotesScreenWithDataDark() => _previewScreen(
      brightness: Brightness.dark,
      notes: AsyncValue.data(_previewNotes()),
    );

@Preview(name: 'ClientNotesScreen - 文字拡大 1.35')
Widget previewClientNotesScreenLarge() => _previewScreen(
      brightness: Brightness.light,
      scale: 1.35,
      notes: AsyncValue.data(_previewNotes()),
    );

@Preview(name: 'ClientNotesScreen - 共有されたノートなし')
Widget previewClientNotesScreenEmpty() => _previewScreen(
      brightness: Brightness.light,
      notes: const AsyncValue.data([]),
    );

@Preview(name: 'ClientNotesScreen - 読込中')
Widget previewClientNotesScreenLoading() => _previewScreen(
      brightness: Brightness.light,
      notes: const AsyncValue.loading(),
    );

@Preview(name: 'ClientNotesScreen - 読み込めなかった')
Widget previewClientNotesScreenError() => _previewScreen(
      brightness: Brightness.light,
      notes: AsyncValue.error('error', StackTrace.empty),
    );
