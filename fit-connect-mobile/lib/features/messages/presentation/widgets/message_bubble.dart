import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/models/tag_model.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_quote.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/trainer_avatar.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/full_screen_image_viewer.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

// ============================================
// 会話の 1 件（正本 `message-screens.js` の `RecordMessage` / `CoachReply` / `DateDivider` / `ReplyTo`）
//
// - 自分のメッセージ = 記録カード（surface・角丸 20・余白 17・左に 22 のインデント）。
//   見出し行（アイコン 14 + 「あなたの体重記録 · 7:30」13px accent）・本文 16・状態行 12px
//   （タグのあるものだけ「体重の記録に追加しました」。**既読は出さない**）
// - トレーナーのメッセージ = 小アバター 29 + surfaceSecondary の吹き出し（左上だけ角丸 0・他 20・余白 15）
//   + 「{名前} · 19:05」12px
// - 写真は記録カード（吹き出し）の下に角丸 20 の画像。タップで全画面表示
// ============================================

/// 日付の区切り（「9月13日（日）」。13px・textSecondary・中央・下 13）
class MessageDateDivider extends StatelessWidget {
  const MessageDateDivider(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Semantics(
        header: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTextStyles.supplement(context),
        ),
      ),
    );
  }
}

/// 自分のメッセージ 1 件を、記録カードの見出し・アイコン・状態行へ対応づけた結果
@immutable
class RecordMessageDescriptor {
  const RecordMessageDescriptor({
    required this.icon,
    required this.heading,
    this.status,
    this.isRecord = false,
    this.body,
  });

  final IconData icon;

  /// 見出し行（「あなたの体重記録 · 7:30」）
  final String heading;

  /// 状態行（タグのあるものは「体重の記録に追加しました」。編集済みなら「 · 編集済み」を足す）
  final String? status;

  /// 記録タグ（#体重 / #食事 / #運動）を持つか
  final bool isRecord;

  /// 本文を整えて見せるときの表示用の本文（null なら受け取った本文をそのまま出す）。
  /// 保存済みの本文は書き換えない（表示だけ）
  final String? body;
}

/// ワークアウト完了のメッセージ本文（`workout_screen.dart` が送る形）を、表示用に分けたもの。
///
/// 本文は「本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 感想」。
/// Web 側（`recordCardParser.ts`）が同じ形を正規表現で解析しているため、**送る本文は変えず**、
/// 表示のときだけここで分ける（絵文字の行 → 「消費 280 kcal」と感想）。
@immutable
class WorkoutCompletionParts {
  const WorkoutCompletionParts({this.planTitle, this.calories, this.feedback});

  /// プラン名（「…」の中）
  final String? planTitle;

  /// 消費カロリー（数字のみ）
  final String? calories;

  /// 感想
  final String? feedback;

  /// 記録カードの本文（「消費 280 kcal」＋ 感想。無いものは出さない）
  String get bodyText => [
        if (calories != null) '消費 $calories kcal',
        if (feedback != null) feedback!,
      ].join('\n');

  static final RegExp _title = RegExp(r'^本日のワークアウトプラン「([^」]+)」を達成しました！');
  static final RegExp _calories = RegExp(r'🔥\s*消費カロリー:\s*([\d.]+)\s*kcal');
  static final RegExp _feedback = RegExp(r'💬\s*(.+)');

  /// 本文がワークアウト完了の形でなければ null
  static WorkoutCompletionParts? parse(String content) {
    final title = _title.firstMatch(content.trim());
    if (title == null) return null;
    return WorkoutCompletionParts(
      planTitle: title.group(1),
      calories: _calories.firstMatch(content)?.group(1),
      feedback: _feedback.firstMatch(content)?.group(1)?.trim(),
    );
  }
}

/// 自分のメッセージの見出し・アイコン・状態行を、タグから決める。
///
/// 種別 → アイコンは `message_tag_parser` の種別に対応: 体重 = scale、食事 = utensils、
/// 運動 = 有酸素 footprints / 筋トレ dumbbell、通常のメッセージ = message-circle。
/// 状態行はタグを持つメッセージだけ「記録に追加しました」を出す（既読は出さない）。
/// カテゴリごとに色は割り振らない（色は常に accent）。
///
/// ワークアウト完了（`#運動:完了`、または「本日のワークアウトプラン「…」を達成しました！」で始まる本文）は、
/// 見出しを「ワークアウト完了 · 上半身 · 18:40」、本文を「消費 280 kcal」＋ 感想に整える
/// （[body] はタグを除いた本文。保存済みの本文は変えず、表示だけ）。
RecordMessageDescriptor describeRecordMessage({
  required List<String>? tags,
  required String time,
  bool isEdited = false,
  String body = '',
}) {
  TagData? tag;
  for (final raw in tags ?? const <String>[]) {
    final parsed = TagData.parse(raw);
    if (parsed.category == '体重' ||
        parsed.category == '食事' ||
        parsed.category == '運動') {
      tag = parsed;
      break;
    }
  }

  String? withEdited(String? base) {
    if (!isEdited) return base;
    return base == null ? '編集済み' : '$base · 編集済み';
  }

  final completion = WorkoutCompletionParts.parse(body);
  final isCompletion = completion != null ||
      (tag?.category == '運動' && tag?.detail == '完了');
  if (isCompletion && (tag == null || tag.category == '運動')) {
    final title = completion?.planTitle;
    return RecordMessageDescriptor(
      icon: LucideIcons.dumbbell,
      heading: title == null
          ? 'ワークアウト完了 · $time'
          : 'ワークアウト完了 · $title · $time',
      status: withEdited('プランの完了を報告しました'),
      isRecord: true,
      body: completion?.bodyText,
    );
  }

  if (tag == null) {
    return RecordMessageDescriptor(
      icon: LucideIcons.messageCircle,
      heading: 'あなたのメッセージ · $time',
      status: withEdited(null),
    );
  }

  switch (tag.category) {
    case '体重':
      return RecordMessageDescriptor(
        icon: LucideIcons.scale,
        heading: 'あなたの体重記録 · $time',
        status: withEdited('体重の記録に追加しました'),
        isRecord: true,
      );
    case '食事':
      const meals = ['朝食', '昼食', '夕食', '間食'];
      final detail = meals.contains(tag.detail) ? tag.detail! : '食事';
      return RecordMessageDescriptor(
        icon: LucideIcons.utensils,
        heading: 'あなたの$detail記録 · $time',
        status: withEdited('食事の記録に追加しました'),
        isRecord: true,
      );
    default: // 運動
      final detail = tag.detail;
      final cardio = detail != null && detail != '筋トレ';
      return RecordMessageDescriptor(
        icon: cardio ? LucideIcons.footprints : LucideIcons.dumbbell,
        heading: detail == null
            ? 'あなたの運動記録 · $time'
            : 'あなたの運動記録 · $detail · $time',
        status: withEdited('運動の記録に追加しました'),
        isRecord: true,
      );
  }
}

class MessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final String timestamp;
  final List<String>? tags;
  final List<String>? images;
  final bool isSystem;
  final String? messageId;
  final String? replyToContent;
  final String? replyToSenderName;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final bool isEdited;

  /// 既読かどうか。**表示には使わない**（再デザインで既読表示をやめ、タグのあるメッセージの
  /// 「記録に追加しました」で置き換えた）。呼び出し側の互換のために残している
  final bool isRead;
  final String? trainerProfileImageUrl;

  /// トレーナーの名前（吹き出しの「{名前} · 19:05」とアバターのイニシャル）。null なら「トレーナー」
  final String? trainerName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isUser,
    required this.timestamp,
    this.tags,
    this.images,
    this.isSystem = false,
    this.messageId,
    this.replyToContent,
    this.replyToSenderName,
    this.onReply,
    this.onEdit,
    this.isEdited = false,
    this.isRead = false,
    this.trainerProfileImageUrl,
    this.trainerName,
  });

  /// メッセージからタグ部分を除去した本文を取得
  String get _messageWithoutTags {
    // タグパターン: #食事:朝食, #運動:筋トレ, #体重 など
    final tagPattern = RegExp(r'#(食事|運動|体重)(?::[^\s]+)?');
    return message.replaceAll(tagPattern, '').trim();
  }

  /// 長押しメニューを表示（返信 / 編集）
  void _showContextMenu(BuildContext context) {
    if (onReply == null && onEdit == null) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: FcRowsCard(
            children: [
              if (onReply != null)
                FcListRow(
                  icon: LucideIcons.reply,
                  title: '返信',
                  chevron: false,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onReply!();
                  },
                ),
              if (isUser && onEdit != null)
                FcListRow(
                  icon: LucideIcons.pencil,
                  title: '編集',
                  chevron: false,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onEdit!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isSystem) {
      return _SystemMessage(message: message);
    }

    final body = _messageWithoutTags;
    final hasQuote = replyToContent != null && replyToSenderName != null;

    final Widget content = isUser
        ? RecordMessageCard(
            descriptor: describeRecordMessage(
              tags: tags,
              time: timestamp,
              isEdited: isEdited,
              body: body,
            ),
            body: body,
            images: images,
            replyToSenderName: hasQuote ? replyToSenderName : null,
            replyToContent: hasQuote ? replyToContent : null,
          )
        : CoachReplyBubble(
            body: body,
            trainerName: trainerDisplayName(trainerName),
            trainerImageValue: trainerProfileImageUrl,
            time: timestamp,
            isEdited: isEdited,
            images: images,
            replyToSenderName: hasQuote ? replyToSenderName : null,
            replyToContent: hasQuote ? replyToContent : null,
          );

    if (onReply == null && onEdit == null) return content;

    // 長押しで「返信 / 編集」。スクリーンリーダー向けに同じ操作をカスタムアクションでも出す
    return Semantics(
      customSemanticsActions: {
        if (onReply != null) const CustomSemanticsAction(label: '返信'): onReply!,
        if (isUser && onEdit != null)
          const CustomSemanticsAction(label: '編集'): onEdit!,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _showContextMenu(context),
        child: content,
      ),
    );
  }
}

/// 自分のメッセージの記録カード（正本 `RecordMessage`）。
///
/// surface・角丸 20・余白 17・左に 22 のインデント。見出し行 → 本文 → 状態行の順。
/// 返信先がある場合はカードの上に「{名前}への返信」、写真はカードの下に出す。
class RecordMessageCard extends StatelessWidget {
  const RecordMessageCard({
    super.key,
    required this.descriptor,
    required this.body,
    this.images,
    this.replyToSenderName,
    this.replyToContent,
  });

  /// 記録カードの左のインデント
  static const double indent = ReplyQuote.defaultLeftInset;

  final RecordMessageDescriptor descriptor;

  /// タグを除いた本文（空なら本文の段落を出さない）
  final String body;

  final List<String>? images;
  final String? replyToSenderName;
  final String? replyToContent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasImages = images != null && images!.isNotEmpty;
    // ワークアウト完了などは、表示用に整えた本文があればそちらを出す
    final shownBody = descriptor.body ?? body;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyToSenderName != null && replyToContent != null)
          ReplyQuote(
            senderName: replyToSenderName!,
            messageContent: replyToContent!,
            isUserMessage: true,
          ),
        Padding(
          padding: const EdgeInsets.only(left: indent),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.chatRecordCard),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.coachCardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 見出し行: アイコン 14 + 13px accent
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          descriptor.icon,
                          size: 14,
                          color: colors.accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          descriptor.heading,
                          style: AppTextStyles.supplement(context)
                              .copyWith(color: colors.accent),
                        ),
                      ),
                    ],
                  ),
                  if (shownBody.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _MessageText(
                      shownBody,
                      style: AppTextStyles.body(context),
                    ),
                  ],
                  if (descriptor.status != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      descriptor.status!,
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (hasImages) MessageImages(images: images!, leftInset: indent),
      ],
    );
  }
}

/// トレーナーのメッセージ（正本 `CoachReply`）。
///
/// 小アバター（29）+ surfaceSecondary の吹き出し（左上だけ角丸 0・他 20・余白 15・行高 1.65）
/// + 「{名前} · 19:05」（12px・吹き出しの中の下）。
class CoachReplyBubble extends StatelessWidget {
  const CoachReplyBubble({
    super.key,
    required this.body,
    required this.trainerName,
    required this.time,
    this.trainerImageValue,
    this.isEdited = false,
    this.images,
    this.replyToSenderName,
    this.replyToContent,
  });

  /// アバター 29 + 間隔 9（返信先の行・写真をこの左端へ揃える）
  static const double bubbleInset = FcAvatar.sm + 9;

  final String body;
  final String trainerName;
  final String time;
  final String? trainerImageValue;
  final bool isEdited;
  final List<String>? images;
  final String? replyToSenderName;
  final String? replyToContent;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasImages = images != null && images!.isNotEmpty;
    final caption = [trainerName, time, if (isEdited) '編集済み'].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replyToSenderName != null && replyToContent != null)
          ReplyQuote(
            senderName: replyToSenderName!,
            messageContent: replyToContent!,
            isUserMessage: false,
            leftInset: bubbleInset,
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TrainerAvatar(
              name: trainerName,
              imageValue: trainerImageValue,
              size: FcAvatar.sm,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceSecondary,
                  // 左上だけ 0（アバターから話している形）
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (body.isNotEmpty) ...[
                        _MessageText(
                          body,
                          style: AppTextStyles.body(context)
                              .copyWith(height: 1.65),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(caption, style: AppTextStyles.caption(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (hasImages) MessageImages(images: images!, leftInset: bubbleInset),
      ],
    );
  }
}

/// 本文。🔥 / 💬 の絵文字は Lucide のアイコンに置き換える（絵文字はアイコンと言葉に）
class _MessageText extends StatelessWidget {
  const _MessageText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  static final RegExp _emoji = RegExp(r'(🔥|💬)');

  @override
  Widget build(BuildContext context) {
    final matches = _emoji.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: style);

    final iconSize = MediaQuery.textScalerOf(context).scale(16);
    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: ExcludeSemantics(
            child: Icon(
              match.group(0) == '🔥'
                  ? LucideIcons.flame
                  : LucideIcons.messageCircle,
              size: iconSize,
              color: style.color,
            ),
          ),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

/// 記録カード（吹き出し）の下に並べる写真。角丸 20・上 6。タップで全画面表示。
///
/// 1 枚は幅いっぱい、複数枚は等分（間隔 6）。高さは 132（正本の `Photo`）。
class MessageImages extends StatelessWidget {
  const MessageImages({
    super.key,
    required this.images,
    required this.leftInset,
  });

  final List<String> images;
  final double leftInset;

  static const double height = 132;
  static const double radius = 20;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: leftInset, top: 6),
      child: Row(
        children: [
          for (var i = 0; i < images.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: FcPressable(
                semanticLabel: '写真 ${i + 1} を拡大して見る',
                onTap: () => FullScreenImageViewer.show(
                  context: context,
                  values: images,
                  bucket: StorageBuckets.messagePhotos,
                  initialIndex: i,
                ),
                child: StorageImage(
                  value: images[i],
                  bucket: StorageBuckets.messagePhotos,
                  width: double.infinity,
                  height: height,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(radius),
                  placeholder: const FcPhotoPlaceholder(
                    height: height,
                    radius: radius,
                    label: '写真',
                  ),
                  errorWidget: const FcPhotoPlaceholder(
                    height: height,
                    radius: radius,
                    label: '写真を読み込めませんでした',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// システムメッセージ（中央・控えめな面）
class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.supplement(context),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required Widget child,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageHorizontal,
            vertical: AppSpacing.lg,
          ),
          children: [child],
        ),
      ),
    ),
  );
}

/// 正本 `ThreadMorning` / `ThreadEvening` と同じ並び（静的）
Widget _previewThread() {
  Widget gap(double h) => SizedBox(height: h);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const MessageDateDivider('9月12日（土）'),
      const MessageBubble(
        message: '#運動:有酸素 ランニング 5.0 km · 30分\nいつもより少し長めに走りました。',
        isUser: true,
        timestamp: '18:20',
        tags: ['#運動:有酸素'],
      ),
      gap(14),
      const MessageBubble(
        message: 'いいペースですね。翌日は脚の張りを見ながら、ストレッチも入れてみてください。',
        isUser: false,
        timestamp: '19:05',
        trainerName: '田中トレーナー',
      ),
      gap(20),
      const MessageDateDivider('9月13日（日）'),
      const MessageBubble(
        message: '#体重 62.4 kg',
        isUser: true,
        timestamp: '7:30',
        tags: ['#体重'],
      ),
      gap(14),
      const MessageBubble(
        message: '#食事:朝食 ごはん・卵・ヨーグルト',
        isUser: true,
        timestamp: '8:10',
        tags: ['#食事:朝食'],
      ),
      gap(14),
      const MessageBubble(
        message: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
        isUser: false,
        timestamp: '9:10',
        trainerName: '田中トレーナー',
      ),
      gap(14),
      const MessageBubble(
        message: 'ありがとうございます。昼もたんぱく質を意識してみます。',
        isUser: true,
        timestamp: '9:24',
        isEdited: true,
        replyToSenderName: '田中トレーナー',
        replyToContent: '朝食の記録、ありがとうございます。',
      ),
      gap(14),
      const MessageBubble(
        message: '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。',
        isUser: true,
        timestamp: '18:40',
        tags: ['#運動:完了'],
      ),
    ],
  );
}

@Preview(name: 'MessageBubble - 会話（ライト）')
Widget previewMessageBubbleThreadLight() =>
    _previewApp(brightness: Brightness.light, child: _previewThread());

@Preview(name: 'MessageBubble - 会話（ダーク）')
Widget previewMessageBubbleThreadDark() =>
    _previewApp(brightness: Brightness.dark, child: _previewThread());

@Preview(name: 'MessageBubble - 会話（文字1.35）')
Widget previewMessageBubbleThreadLarge() => _previewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      child: _previewThread(),
    );

@Preview(name: 'MessageBubble - システム')
Widget previewMessageBubbleSystem() {
  return _previewApp(
    brightness: Brightness.light,
    child: const MessageBubble(
      message: '目標を達成しました',
      isUser: false,
      timestamp: '14:20',
      isSystem: true,
    ),
  );
}
