import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/utils/note_labels.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/linked_session_line.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// カルテ一覧の1件。正本 `record-screens.js` の `NoteCard`。
///
/// 上から: 紐づくセッションの行（calendar-days ＋「9月8日（火）19:00 · パーソナル」。
/// 紐づけのあるノートだけ）→ タイトル（17 / 500）→ 補足「9月8日（火） · {トレーナー名}」→
/// 本文の抜粋（15・行高 1.6・2 行で省略）→ 下の行（添付があれば「添付 2件」のピル・右に chevron）。
/// カード全体が押せる（[onTap]）。タイトルは行数を固定せず、折り返して伸びる。
class NoteCard extends StatelessWidget {
  final ClientNote note;

  /// セッション日時・作成日の年付与判定に使う現在時刻。
  /// 一覧側で1回だけ取得したものを渡す（行ごとに引き直すと日跨ぎで年表示が食い違う）
  final DateTime now;

  final VoidCallback? onTap;

  /// 担当トレーナーの名前（補足行に出す）。分からなければ null（日付だけを出す）
  final String? trainerName;

  const NoteCard({
    super.key,
    required this.note,
    required this.now,
    this.onTap,
    this.trainerName,
  });

  /// 補足行「9月8日（火） · 田中トレーナー」。トレーナー名が無ければ日付だけ
  String get metaLabel {
    final date = formatNoteDate(note.createdAt, now: now);
    final name = trainerName?.trim();
    return (name == null || name.isEmpty)
        ? date
        : '$date · ${trainerDisplayName(name)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fileCount = note.fileUrls.length;
    final hasFiles = fileCount > 0;
    // get_my_sessions で取れた場合だけ入る（sessionId の有無では判定しない）
    final session = note.session;

    return FcCard(
      onTap: onTap,
      semanticLabel: [
        if (session != null) formatLinkedSessionLabel(session, now: now),
        note.title,
        metaLabel,
        note.content,
        if (hasFiles) '添付 $fileCount件',
      ].join('、'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 紐づくセッション（日時 + 種別）— 紐づけがあるノートだけ。下に 6
          if (session != null) ...[
            LinkedSessionLine(session: session, now: now),
            const SizedBox(height: 6),
          ],

          // タイトル
          Text(note.title, style: AppTextStyles.exerciseName(context)),

          // 補足（作成日 · トレーナー名）。上 4
          const SizedBox(height: AppSpacing.xs),
          Text(metaLabel, style: AppTextStyles.supplement(context)),

          // 本文の抜粋（15・行高 1.6・2 行で省略）。上 10
          const SizedBox(height: 10),
          Text(
            note.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.actionLabel(context).copyWith(
              fontWeight: FontWeight.w400,
              height: 1.6,
            ),
          ),

          // 添付のピル + chevron。上 12・最小高さ 24
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasFiles)
                  Flexible(
                    child: FcPill(
                      '添付 $fileCount件',
                      tone: FcPillTone.muted,
                      icon: LucideIcons.paperclip,
                    ),
                  )
                else
                  const SizedBox.shrink(),
                ExcludeSemantics(
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

ClientNote _previewNote({
  String id = '1',
  String title = '上半身のフォーム確認',
  String content = 'ダンベルプレスは肩甲骨を寄せたまま下ろせていました。次回は12 kgで10回×3セットを目安にします。',
  List<String> fileUrls = const ['a.jpg', 'b.pdf'],
  LinkedSession? session,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 9, 8, 21);
  return ClientNote(
    id: id,
    clientId: 'client_1',
    trainerId: 'trainer_1',
    title: title,
    content: content,
    fileUrls: fileUrls,
    isShared: true,
    sessionId: session == null ? null : 'session_$id',
    session: session,
    createdAt: created,
    updatedAt: created,
  );
}

Widget _previewCards({required Brightness brightness, double scale = 1}) {
  final now = DateTime(2026, 9, 13);
  return FcPreviewApp(
    brightness: brightness,
    textScale: scale,
    home: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            NoteCard(
              note: _previewNote(
                session: LinkedSession(
                  sessionDate: DateTime(2026, 9, 8, 19),
                  sessionType: 'パーソナル',
                ),
              ),
              now: now,
              trainerName: '田中トレーナー',
              onTap: () {},
            ),
            const SizedBox(height: AppSpacing.cardGap),
            NoteCard(
              note: _previewNote(
                id: '2',
                title: '食事のポイント',
                content: '毎食、手のひら1枚分のたんぱく質を目安にしましょう。間食はヨーグルトやナッツがおすすめです。',
                fileUrls: const [],
                createdAt: DateTime(2026, 8, 25, 18),
              ),
              now: now,
              trainerName: '田中トレーナー',
              onTap: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'NoteCard - ライト')
Widget previewNoteCardLight() => _previewCards(brightness: Brightness.light);

@Preview(name: 'NoteCard - ダーク')
Widget previewNoteCardDark() => _previewCards(brightness: Brightness.dark);

@Preview(name: 'NoteCard - 文字拡大 1.35')
Widget previewNoteCardLarge() =>
    _previewCards(brightness: Brightness.light, scale: 1.35);

@Preview(name: 'NoteCard - 長いタイトルと昨年のセッション')
Widget previewNoteCardLongContent() {
  return FcPreviewApp(
    brightness: Brightness.light,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: NoteCard(
            note: _previewNote(
              id: '3',
              title: '体組成測定結果と今後のトレーニング方針について',
              content:
                  '今月の体組成測定を実施しました。体脂肪率が2%減少し、筋肉量が1.5kg増加しています。非常に良い傾向です。今後もこのペースを維持できるよう、トレーニングメニューを継続します。',
              fileUrls: const ['a.pdf', 'b.jpg', 'c.jpg'],
              session: LinkedSession(
                sessionDate: DateTime(2025, 12, 20, 11),
                sessionType: 'other',
              ),
              createdAt: DateTime(2025, 12, 20, 16, 45),
            ),
            now: DateTime(2026, 9, 13),
            trainerName: '田中トレーナー',
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}
