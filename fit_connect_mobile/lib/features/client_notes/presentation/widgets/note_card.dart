import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

class NoteCard extends StatelessWidget {
  final ClientNote note;
  final VoidCallback? onTap;

  const NoteCard({
    super.key,
    required this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fileCount = note.fileUrls.length;
    final hasFiles = fileCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.slate200.withOpacity(0.6),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Session number + Title
            Row(
              children: [
                if (note.sessionNumber != null) ...[
                  Text(
                    '#${note.sessionNumber}',
                    style: const TextStyle(
                      color: AppColors.primary600,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      color: AppColors.slate800,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Date
            Text(
              _formatDateJa(note.createdAt),
              style: const TextStyle(
                color: AppColors.slate400,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: 12),

            // Content preview
            Text(
              note.content,
              style: const TextStyle(
                color: AppColors.slate600,
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
                      color: AppColors.slate100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.paperclip,
                          size: 14,
                          color: AppColors.slate500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$fileCount file${fileCount > 1 ? 's' : ''} attached',
                          style: const TextStyle(
                            color: AppColors.slate500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.slate300,
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

@Preview(name: 'NoteCard - With Session Number')
Widget previewNoteCardWithSessionNumber() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
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
              sessionNumber: 12,
              createdAt: DateTime(2026, 2, 10, 14, 30),
              updatedAt: DateTime(2026, 2, 10, 14, 30),
            ),
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'NoteCard - Without Files')
Widget previewNoteCardWithoutFiles() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: NoteCard(
            note: ClientNote(
              id: '2',
              clientId: 'client_1',
              trainerId: 'trainer_1',
              title: '食事指導メモ',
              content: 'タンパク質の摂取量を増やすよう指導。1日あたり体重1kgあたり2gを目標に。',
              fileUrls: [],
              isShared: false,
              sessionNumber: 8,
              createdAt: DateTime(2026, 2, 5, 10, 15),
              updatedAt: DateTime(2026, 2, 5, 10, 15),
            ),
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
      backgroundColor: AppColors.background,
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
              sessionNumber: null,
              createdAt: DateTime(2026, 2, 15, 16, 45),
              updatedAt: DateTime(2026, 2, 15, 16, 45),
            ),
            onTap: () {},
          ),
        ),
      ),
    ),
  );
}
