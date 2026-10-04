import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/shared/storage/signed_url_cache.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/storage/storage_value_resolver.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// カルテ詳細画面（読み取り専用）。
///
/// 正本: Claude Design の `more-screens.js` `NoteDetailScreen`。
/// AppBar をやめ、本文内の「戻る」→ セッション行（紐づくときだけ）→ タイトル → 作成者と作成日 →
/// 本文カード → 添付ファイル（写真カード・ファイルカード）の順に縦に並べる。
///
/// 紐づくセッションがあるノートは、ヘッダーの先頭に**セッション日時（+種別）**を出す
/// （廃止した「第N回セッション」の代わり）。紐づけの無いノートはタイトルから始まる。
class ClientNoteDetailScreen extends StatelessWidget {
  final ClientNote note;
  final String? trainerName;

  const ClientNoteDetailScreen({
    super.key,
    required this.note,
    this.trainerName,
  });

  /// 判定用: 値（`パス#元ファイル名` 形式 or レガシーURL）からパス部分を取り出す
  String _pathOf(String value) =>
      resolveStorageValue(value, StorageBuckets.clientNotes).path ?? value;

  // ファイル種別判定ロジック（フラグメント・クエリ除去後のパスで判定）
  bool _isImage(String value) {
    final lower = _pathOf(value).toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool _isPdf(String value) {
    return _pathOf(value).toLowerCase().endsWith('.pdf');
  }

  String _getFileName(String value) {
    final resolved = resolveStorageValue(value, StorageBuckets.clientNotes);
    // フラグメント部分に元のファイル名がある場合はそれを使用
    final fragment = resolved.decodedFragment;
    if (fragment != null && fragment.isNotEmpty) {
      return fragment;
    }
    return _pathOf(value).split('/').last;
  }

  // PDFファイルを開く（署名URLに解決してから外部アプリで起動）
  Future<void> _openPdf(String value) async {
    final url = await SignedUrlCache.instance
        .resolveUrl(value, StorageBuckets.clientNotes);
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 画像URLリストを抽出（FullScreenImageViewer用）
    final imageUrls = note.fileUrls.where(_isImage).toList();

    final attachments = <Widget>[
      for (final url in note.fileUrls)
        if (_isImage(url))
          NoteDetailPhotoCard(
            // 同じ文言の「写真」が並んでも区別できるよう、番号を付けて読み上げる
            number: imageUrls.indexOf(url) + 1,
            total: imageUrls.length,
            imageBuilder: (failedPlaceholder) => StorageImage(
              value: url,
              bucket: StorageBuckets.clientNotes,
              height: _photoHeight,
              width: double.infinity,
              fit: BoxFit.cover,
              placeholder: const FcSkeleton(height: _photoHeight, radius: 0),
              errorWidget: failedPlaceholder,
            ),
            onTap: () {
              final imageIndex = imageUrls.indexOf(url);
              FullScreenImageViewer.show(
                context: context,
                values: imageUrls,
                bucket: StorageBuckets.clientNotes,
                initialIndex: imageIndex,
              );
            },
          )
        else if (_isPdf(url))
          _PdfAttachmentCard(
            fileName: _getFileName(url),
            onTap: () => _openPdf(url),
          )
        else
          // その他のファイル（サポート外）
          _OtherFileCard(fileName: _getFileName(url)),
    ];

    return _NoteDetailView(
      note: note,
      trainerName: trainerName,
      attachmentCount: note.fileUrls.length,
      attachments: attachments,
    );
  }
}

/// 写真の高さ（正本 `Photo height={190}`）
const double _photoHeight = 190;

/// 画面本体。添付のカードは呼び出し側が組む（プレビューではネットワークに出ない代替を渡す）
class _NoteDetailView extends StatelessWidget {
  final ClientNote note;
  final String? trainerName;
  final int attachmentCount;
  final List<Widget> attachments;

  const _NoteDetailView({
    required this.note,
    required this.trainerName,
    required this.attachmentCount,
    required this.attachments,
  });

  /// 本文を空行で段落に分ける（段落の間は 12。段落内の改行はそのまま残す）
  List<String> _paragraphs() {
    return note.content
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pageH = AppSpacing.pageHorizontalOf(context);
    // get_my_sessions（または親セッションからの補完）で取れた場合だけ入る
    final session = note.session;
    final now = DateTime.now();
    final paragraphs = _paragraphs();

    // 「9月8日（火）19:00 · パーソナル」。種別が無ければ日時だけ
    String? sessionLine;
    if (session != null) {
      final typeLabel = sessionTypeLabel(session.sessionType);
      sessionLine = [
        formatSessionDateTimeDisplay(session.sessionDate, now: now),
        if (typeLabel != null) typeLabel,
      ].join(' · ');
    }

    // 「田中トレーナー · 9月8日（火）作成」。名前が取れていなければ日付だけ
    final trainerLabel = trainerName?.trim();
    final meta = [
      if (trainerLabel != null && trainerLabel.isNotEmpty)
        trainerDisplayName(trainerLabel),
      '${formatSessionDateDisplay(note.createdAt, now: now)}作成',
    ].join(' · ');

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
              const SizedBox(height: 10),
              if (sessionLine != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文字の 1 行目（13 × 1.5）の中央にアイコン（15）を合わせる
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: ExcludeSemantics(
                        child: Icon(
                          LucideIcons.calendarDays,
                          size: 15,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sessionLine,
                        style: AppTextStyles.supplement(context)
                            .copyWith(color: colors.accent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Semantics(
                header: true,
                child: Text(
                  note.title,
                  style: AppTextStyles.planName(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(meta, style: AppTextStyles.supplement(context)),
              ),
              const SizedBox(height: AppSpacing.xl),
              FcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < paragraphs.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.md),
                      Text(
                        paragraphs[i],
                        style:
                            AppTextStyles.body(context).copyWith(height: 1.75),
                      ),
                    ],
                  ],
                ),
              ),
              // 添付が無ければセクションごと出さない
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.cardGap),
                FcSectionTitle('添付ファイル（$attachmentCount件）'),
                for (final card in attachments) ...[
                  const SizedBox(height: AppSpacing.cardGap),
                  card,
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 写真カード（写真 190・角丸 0 をカードでクリップ ＋「写真 · タップで拡大」）。タップで拡大表示。
///
/// 読み上げは「写真 1/2 を拡大して表示」。読み込みに失敗したときは「写真 1/2 を読み込めませんでした」
/// （代替の面にも同じ文言を出す）。画像そのものは [imageBuilder] で組む
/// （失敗時に出す代替の面が渡される。プレビュー・テストではネットワークに出ない面を返す）
@visibleForTesting
class NoteDetailPhotoCard extends StatefulWidget {
  /// 写真の番号（1 始まり）と枚数
  final int number;
  final int total;

  final Widget Function(Widget failedPlaceholder) imageBuilder;
  final VoidCallback onTap;

  const NoteDetailPhotoCard({
    super.key,
    required this.number,
    required this.total,
    required this.imageBuilder,
    required this.onTap,
  });

  @override
  State<NoteDetailPhotoCard> createState() => _NoteDetailPhotoCardState();
}

class _NoteDetailPhotoCardState extends State<NoteDetailPhotoCard> {
  /// 代替の面（読み込み失敗）が出ているあいだ true
  bool _failed = false;

  void _setFailed(bool value) {
    if (!mounted || _failed == value) return;
    setState(() => _failed = value);
  }

  @override
  Widget build(BuildContext context) {
    final label = '写真 ${widget.number}/${widget.total}';
    final failedLabel = '$label を読み込めませんでした';

    return FcCard(
      padding: FcCardPadding.none,
      onTap: widget.onTap,
      semanticLabel: _failed ? failedLabel : '$label を拡大して表示',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.imageBuilder(
            _PhotoLoadFailed(label: failedLabel, onChanged: _setFailed),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              14,
            ),
            child: Text(
              '写真 · タップで拡大',
              style: AppTextStyles.supplement(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 写真を読み込めなかったときの代替の面。表示されているあいだ、親のカードへ失敗を伝える
class _PhotoLoadFailed extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;

  const _PhotoLoadFailed({required this.label, required this.onChanged});

  @override
  State<_PhotoLoadFailed> createState() => _PhotoLoadFailedState();
}

class _PhotoLoadFailedState extends State<_PhotoLoadFailed> {
  late final ValueChanged<bool> _onChanged = widget.onChanged;

  @override
  void initState() {
    super.initState();
    // ビルド中に親を setState しないよう、次のフレームで伝える
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged(true));
  }

  @override
  void dispose() {
    // 再取得に成功して面が消えたときは、失敗の表示を戻す
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FcPhotoPlaceholder(
      height: _photoHeight,
      radius: 0,
      label: widget.label,
    );
  }
}

/// PDF のカード（file-text 22 ＋ ファイル名 ＋「PDF · 外部のアプリで開きます」＋ external-link）
class _PdfAttachmentCard extends StatelessWidget {
  final String fileName;
  final VoidCallback onTap;

  const _PdfAttachmentCard({required this.fileName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcCard(
      onTap: onTap,
      semanticLabel: '$fileName、PDF、外部のアプリで開きます',
      child: Row(
        children: [
          Icon(LucideIcons.fileText, size: 22, color: colors.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: AppTextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  'PDF · 外部のアプリで開きます',
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Icon(
            LucideIcons.externalLink,
            size: 16,
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// その他のファイル（アプリ内で開けない。ファイル名だけ表示）
class _OtherFileCard extends StatelessWidget {
  final String fileName;

  const _OtherFileCard({required this.fileName});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcCard(
      child: Row(
        children: [
          Icon(LucideIcons.file, size: 22, color: colors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              fileName,
              style: AppTextStyles.body(context)
                  .copyWith(color: colors.textSecondary),
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

/// プレビュー用ダミー（紐づけあり・添付あり）。ライト/ダーク両プレビューで共有
ClientNote _previewNoteWithLinkedSession() {
  return ClientNote(
    id: '1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: '上半身のフォーム確認',
    content: '本日はダンベルプレスとラットプルダウンのフォームを確認しました。\n\n'
        'ダンベルプレスは、肩甲骨を寄せたまま下ろせていました。次回は12 kgで10回×3セットを目安にします。\n\n'
        'ラットプルダウンは最後のセットで反動が出やすいので、重さを保ったまま回数を優先しましょう。\n\n'
        '次回までは、朝食の記録と週2回のプランを自分のペースで続けてください。',
    fileUrls: [
      'https://example.com/form.jpg',
      'https://example.com/plan.pdf',
    ],
    isShared: true,
    sharedAt: DateTime.now(),
    sessionId: 'session-1',
    // 紐づけあり: ヘッダー先頭にセッション日時 + 種別が出る
    session: LinkedSession(
      sessionDate: DateTime.now().subtract(const Duration(days: 2)),
      sessionType: 'パーソナルトレーニング',
    ),
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    updatedAt: DateTime.now().subtract(const Duration(days: 2)),
  );
}

/// プレビュー用の添付（ネットワークに出ないよう、写真は代替面にする）
List<Widget> _previewAttachments() => [
      NoteDetailPhotoCard(
        number: 1,
        total: 1,
        imageBuilder: (_) => const FcPhotoPlaceholder(
          height: _photoHeight,
          radius: 0,
          label: 'フォームの写真',
        ),
        onTap: () {},
      ),
      _PdfAttachmentCard(fileName: 'トレーニング計画.pdf', onTap: () {}),
    ];

@Preview(name: 'NoteDetail - With Files (Linked Session)')
Widget previewClientNoteDetailWithFiles() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _NoteDetailView(
      note: _previewNoteWithLinkedSession(),
      trainerName: '田中トレーナー',
      attachmentCount: 2,
      attachments: _previewAttachments(),
    ),
  );
}

/// ダークモード: カード・文字・アクセントがダークの配色で読めることを確認する
@Preview(name: 'NoteDetail - With Files (Linked Session, Dark)')
Widget previewClientNoteDetailWithFilesDark() {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: _NoteDetailView(
      note: _previewNoteWithLinkedSession(),
      trainerName: '田中トレーナー',
      attachmentCount: 2,
      attachments: _previewAttachments(),
    ),
  );
}

@Preview(name: 'NoteDetail - With Files (Large Text 1.35)')
Widget previewClientNoteDetailLargeText() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.35),
      ),
      child: child!,
    ),
    home: _NoteDetailView(
      note: _previewNoteWithLinkedSession(),
      trainerName: '田中トレーナー',
      attachmentCount: 2,
      attachments: _previewAttachments(),
    ),
  );
}

@Preview(name: 'NoteDetail - Text Only (No Linked Session)')
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
    // 紐づけ無し: タイトルから始まる。添付が無いので添付セクションも出ない
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
