import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/linked_session_line.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// カルテ一覧の1件。
///
/// 紐づくセッションがあるノートは、廃止した `#N` の代わりに
/// **セッション日時（+種別）を先頭行**に出して「どのセッションのノートか」を示す。
/// 紐づけの無いノートは従来どおりタイトルから始まる（作成日のみ）。
class NoteCard extends StatelessWidget {
  final ClientNote note;

  /// セッション日時の年付与判定に使う現在時刻。
  /// 一覧側で1回だけ取得したものを渡す（行ごとに引き直すと日跨ぎで年表示が食い違う）
  final DateTime now;

  final VoidCallback? onTap;

  const NoteCard({
    super.key,
    required this.note,
    required this.now,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fileCount = note.fileUrls.length;
    final hasFiles = fileCount > 0;
    // embed で取れた場合だけ入る（sessionId の有無では判定しない）
    final session = note.session;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linked session (date + type) — 紐づけがあるノートだけ
            if (session != null) ...[
              LinkedSessionLine(session: session, now: now),
              const SizedBox(height: 8),
            ],

            // Title
            Text(
              note.title,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            // Date
            Text(
              _formatDateJa(note.createdAt),
              style: TextStyle(
                color: colors.textHint,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 12),

            // Content preview
            Text(
              note.content,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 16),

            // File badge + Arrow
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (hasFiles)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.paperclip,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '添付ファイル${fileCount}件',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                Icon(
                  LucideIcons.chevronRight,
                  color: colors.textHint,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateJa(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'NoteCard - With Linked Session')
Widget previewNoteCardWithLinkedSession() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NoteCard(
            note: ClientNote(
              id: '1',
              clientId: 'client_1',
              trainerId: 'trainer_1',
              title: 'トレーニングセッション記録',
              content: '今日はスクワットとデッドリフトを中心に行いました。フォームが改善されてきています。',
              fileUrls: [
                'https://example.com/file1.jpg',
                'https://example.com/file2.jpg',
              ],
              isShared: true,
              sessionId: 'session_1',
              // 紐づくセッションの日時が先頭行に出る（今年なら年なし）
              session: LinkedSession(
                sessionDate: DateTime(2026, 2, 10, 18, 0),
                sessionType: 'パーソナルトレーニング',
              ),
              createdAt: DateTime(2026, 2, 10, 20, 30),
              updatedAt: DateTime(2026, 2, 10, 20, 30),
            ),
            now: DateTime(2026, 2, 15),
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'NoteCard - Without Linked Session')
Widget previewNoteCardWithoutLinkedSession() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NoteCard(
            // 紐づけ無し: 従来どおりタイトルから始まり作成日のみ
            note: ClientNote(
              id: '2',
              clientId: 'client_1',
              trainerId: 'trainer_1',
              title: '食事指導メモ',
              content: 'タンパク質の摂取量を増やすよう指導。1日あたり体重1kgあたり2gを目標に。',
              fileUrls: [],
              isShared: true,
              createdAt: DateTime(2026, 2, 5, 10, 15),
              updatedAt: DateTime(2026, 2, 5, 10, 15),
            ),
            now: DateTime(2026, 2, 15),
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'NoteCard - Long Content')
Widget previewNoteCardLongContent() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NoteCard(
            note: ClientNote(
              id: '3',
              clientId: 'client_1',
              trainerId: 'trainer_1',
              title: '体組成測定結果と今後の方針について',
              content:
                  '今月の体組成測定を実施しました。体脂肪率が2%減少し、筋肉量が1.5kg増加しています。非常に良い傾向です。今後もこのペースを維持できるよう、トレーニングメニューを継続します。特に下半身の強化を重点的に行っていきましょう。また、食事面では引き続きタンパク質の摂取を意識してください。',
              fileUrls: [
                'https://example.com/measurement.pdf',
                'https://example.com/chart1.jpg',
                'https://example.com/chart2.jpg',
              ],
              isShared: true,
              sessionId: 'session_3',
              // 去年のセッション: 年付きで表示される
              session: LinkedSession(
                sessionDate: DateTime(2025, 12, 20, 11, 0),
                sessionType: 'other',
              ),
              createdAt: DateTime(2025, 12, 20, 16, 45),
              updatedAt: DateTime(2025, 12, 20, 16, 45),
            ),
            now: DateTime(2026, 2, 15),
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}
