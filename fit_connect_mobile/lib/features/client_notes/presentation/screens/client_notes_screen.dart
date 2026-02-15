import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/providers/client_notes_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/note_card.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';

/// カルテ一覧画面（クライアント側）
class ClientNotesScreen extends ConsumerWidget {
  const ClientNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // カルテ一覧の取得
    final notesAsync = ref.watch(sharedClientNotesProvider);

    // トレーナー名の取得
    final trainerAsync = ref.watch(trainerProfileProvider);
    final trainerName = trainerAsync.valueOrNull?.name;

    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: notesAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (error, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  size: 48,
                  color: AppColors.rose800,
                ),
                const SizedBox(height: 16),
                Text(
                  'エラーが発生しました',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.slate700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.slate500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(sharedClientNotesProvider);
                  },
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
          data: (notes) {
            if (notes.isEmpty) {
              return _buildEmptyState();
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // サマリーカード
                _buildSummaryCard(notes.length),

                const SizedBox(height: 16),

                // カルテリスト
                ...notes.map((note) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NoteCard(
                      note: note,
                      onTap: () {
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
                    ),
                  );
                }).toList(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// サマリーカード
  Widget _buildSummaryCard(int noteCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // アイコン
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              LucideIcons.userCheck,
              color: AppColors.primary600,
              size: 20,
            ),
          ),

          const SizedBox(width: 12),

          // テキスト
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'トレーナーより',
                  style: TextStyle(
                    color: AppColors.primary600,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共有されたカルテ: $noteCount件',
                  style: const TextStyle(
                    color: AppColors.primary400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 空状態
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            LucideIcons.clipboardList,
            size: 48,
            color: AppColors.slate300,
          ),
          const SizedBox(height: 16),
          const Text(
            '共有されたノートはありません',
            style: TextStyle(
              color: AppColors.slate500,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'トレーナーからまだセッションノートが共有されていません。',
            style: TextStyle(
              color: AppColors.slate400,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

/// プレビュー用ヘルパーWidget（データあり）
class _PreviewNotesListWithData extends StatelessWidget {
  const _PreviewNotesListWithData();

  @override
  Widget build(BuildContext context) {
    final dummyNotes = [
      ClientNote(
        id: '1',
        clientId: 'client-1',
        trainerId: 'trainer-1',
        title: '初回トレーニングセッション',
        content: '本日は初回セッションを実施しました。フォームが良好です。',
        fileUrls: ['https://example.com/file1.jpg'],
        isShared: true,
        sharedAt: DateTime.now(),
        sessionNumber: 1,
        createdAt: DateTime(2026, 2, 15, 14, 30),
        updatedAt: DateTime(2026, 2, 15, 14, 30),
      ),
      ClientNote(
        id: '2',
        clientId: 'client-1',
        trainerId: 'trainer-1',
        title: '食事指導フォローアップ',
        content: 'タンパク質摂取量が目標値に達しています。素晴らしいです！',
        fileUrls: [],
        isShared: true,
        sharedAt: DateTime.now(),
        sessionNumber: 2,
        createdAt: DateTime(2026, 2, 10, 10, 15),
        updatedAt: DateTime(2026, 2, 10, 10, 15),
      ),
      ClientNote(
        id: '3',
        clientId: 'client-1',
        trainerId: 'trainer-1',
        title: '体組成測定結果',
        content: '体脂肪率が2%減少し、筋肉量が1.5kg増加しています。',
        fileUrls: [
          'https://example.com/chart1.jpg',
          'https://example.com/report.pdf',
        ],
        isShared: true,
        sharedAt: DateTime.now(),
        sessionNumber: 3,
        createdAt: DateTime(2026, 2, 5, 16, 45),
        updatedAt: DateTime(2026, 2, 5, 16, 45),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // サマリーカード
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.userCheck,
                      color: AppColors.primary600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'トレーナーより',
                          style: TextStyle(
                            color: AppColors.primary600,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '共有されたカルテ: 3件',
                          style: TextStyle(
                            color: AppColors.primary400,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // カルテリスト
            ...dummyNotes.map((note) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NoteCard(
                  note: note,
                  onTap: () {},
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

/// プレビュー用ヘルパーWidget（空状態）
class _PreviewNotesListEmpty extends StatelessWidget {
  const _PreviewNotesListEmpty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                LucideIcons.clipboardList,
                size: 48,
                color: AppColors.slate300,
              ),
              const SizedBox(height: 16),
              const Text(
                '共有されたノートはありません',
                style: TextStyle(
                  color: AppColors.slate500,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'トレーナーからまだセッションノートが共有されていません。',
                style: TextStyle(
                  color: AppColors.slate400,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@Preview(name: 'ClientNotesScreen - With Data')
Widget previewClientNotesScreenWithData() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewNotesListWithData(),
  );
}

@Preview(name: 'ClientNotesScreen - Empty State')
Widget previewClientNotesScreenEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: const _PreviewNotesListEmpty(),
  );
}
