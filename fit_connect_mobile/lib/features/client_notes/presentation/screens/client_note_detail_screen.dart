import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';

/// カルテ詳細画面（読み取り専用）
class ClientNoteDetailScreen extends StatelessWidget {
  final ClientNote note;
  final String? trainerName;

  const ClientNoteDetailScreen({
    super.key,
    required this.note,
    this.trainerName,
  });

  // ファイル種別判定ロジック
  bool _isImage(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isPdf(String url) {
    return url.toLowerCase().endsWith('.pdf');
  }

  String _getFileName(String url) {
    final uri = Uri.parse(url);
    // フラグメント部分に元のファイル名がある場合はそれを使用
    if (uri.fragment.isNotEmpty) {
      return Uri.decodeComponent(uri.fragment);
    }
    return uri.pathSegments.last;
  }

  // PDFファイルを開く
  Future<void> _openPdf(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    String formatDate(DateTime dt) {
      return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    // 画像URLリストを抽出（FullScreenImageViewer用）
    final imageUrls = note.fileUrls.where(_isImage).toList();

    return Scaffold(
      backgroundColor: AppColors.slate50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.slate700),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ============================================
            // ヘッダーカード
            // ============================================
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // セッション番号
                  if (note.sessionNumber != null)
                    Text(
                      '第${note.sessionNumber}回セッション',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary600,
                      ),
                    ),
                  if (note.sessionNumber != null) const SizedBox(height: 8),

                  // タイトル
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate800,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // トレーナー名 + 日付
                  Row(
                    children: [
                      if (trainerName != null) ...[
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppColors.slate500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          trainerName!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.slate500,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: AppColors.slate400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatDate(note.createdAt),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ============================================
            // 内容カード
            // ============================================
            Container(
              margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ラベル
                  const Text(
                    '内容',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.slate500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 本文
                  Text(
                    note.content,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.slate700,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            // ============================================
            // 添付ファイルカード
            // ============================================
            if (note.fileUrls.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ラベル
                    Text(
                      '添付ファイル (${note.fileUrls.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.slate500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ファイル一覧
                    ...note.fileUrls.asMap().entries.map((entry) {
                      final index = entry.key;
                      final url = entry.value;

                      if (_isImage(url)) {
                        // 画像プレビュー
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                index < note.fileUrls.length - 1 ? 12 : 0,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              final imageIndex =
                                  imageUrls.indexOf(url);
                              FullScreenImageViewer.show(
                                context: context,
                                imageUrls: imageUrls,
                                initialIndex: imageIndex,
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    height: 200,
                                    color: AppColors.slate100,
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Container(
                                  height: 200,
                                  color: AppColors.slate100,
                                  child: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: AppColors.slate400,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else if (_isPdf(url)) {
                        // PDFアイテム
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                index < note.fileUrls.length - 1 ? 12 : 0,
                          ),
                          child: InkWell(
                            onTap: () => _openPdf(url),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.slate50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  // PDFアイコン
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDC2626),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // ファイル名 + ヒント
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getFileName(url),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.slate800,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'タップして表示',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.slate500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 矢印アイコン
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: AppColors.slate400,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      } else {
                        // その他のファイル（サポート外）
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom:
                                index < note.fileUrls.length - 1 ? 12 : 0,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.slate50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.insert_drive_file,
                                  color: AppColors.slate500,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _getFileName(url),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.slate600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    }).toList(),
                  ],
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

@Preview(name: 'NoteDetail - With Files')
Widget previewClientNoteDetailWithFiles() {
  final dummyNote = ClientNote(
    id: '1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: '初回トレーニングセッション',
    content:
        '本日は初回セッションを実施しました。\n\n【実施内容】\n・ボディチェック\n・目標設定\n・基礎トレーニング（スクワット、プランク）\n\n【所感】\nフォームは良好。次回から負荷を上げていきます。',
    fileUrls: [
      'https://example.com/image1.jpg',
      'https://example.com/image2.png',
      'https://example.com/report.pdf',
    ],
    isShared: true,
    sharedAt: DateTime.now(),
    sessionNumber: 1,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: ClientNoteDetailScreen(
      note: dummyNote,
      trainerName: '山田太郎',
    ),
  );
}

@Preview(name: 'NoteDetail - Text Only')
Widget previewClientNoteDetailTextOnly() {
  final dummyNote = ClientNote(
    id: '2',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: '食事指導フォローアップ',
    content:
        '先週の食事記録を確認しました。\n\nタンパク質摂取量が目標値に達しています。素晴らしいです！\n\n引き続きバランスの良い食事を心がけてください。',
    fileUrls: [],
    isShared: true,
    sharedAt: DateTime.now(),
    sessionNumber: 5,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: ClientNoteDetailScreen(
      note: dummyNote,
      trainerName: '佐藤花子',
    ),
  );
}
