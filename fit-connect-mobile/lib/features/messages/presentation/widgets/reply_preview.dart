import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/messages/presentation/widgets/reply_quote.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 入力欄の上に出す 1 行のバナー（返信先・編集中）。正本 `ComposerTags` の返信バナー。
///
/// 角丸 16・surface・余白 8×14。アイコン 16（accent）・見出し 13/500・引用 1 行（caption・省略）・
/// 右に閉じる（44×44）。閉じるボタンの右側は余白 14 に食い込ませて、「×」の字を右端に揃える。
class ComposerBanner extends StatelessWidget {
  const ComposerBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.quote,
    required this.closeLabel,
    required this.onClose,
  });

  final IconData icon;

  /// 見出し（「田中トレーナーに返信」「メッセージを編集中」）
  final String title;

  /// 引用する本文（1 行に省略して出す）
  final String quote;

  /// 閉じるボタンの読み上げ（「返信をやめる」「編集をやめる」）
  final String closeLabel;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final oneLine = ReplyQuote.oneLine(quote);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        // 閉じるボタン（高さ 44）が行の高さを決める。縦 8 を足すと正本（約 55）より高くなるので 4
        padding: const EdgeInsets.fromLTRB(
          14,
          4,
          14 - FcCloseButton.endBleed,
          4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: 16, color: colors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.supplement(context).copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (oneLine.isNotEmpty)
                    Text(
                      oneLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(context),
                    ),
                ],
              ),
            ),
            FcCloseButton(onPressed: onClose, semanticLabel: closeLabel),
          ],
        ),
      ),
    );
  }
}

/// 返信先のプレビュー（入力欄の上）。「{名前}に返信」＋返信先の本文 1 行＋閉じる。
class ReplyPreview extends StatelessWidget {
  final String messageContent;
  final VoidCallback onCancel;

  /// 返信先を書いた人の呼び名（トレーナーの名前。自分のメッセージなら [ReplyQuote.selfName]）。
  /// null なら「返信先」
  final String? senderName;

  const ReplyPreview({
    super.key,
    required this.messageContent,
    required this.onCancel,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final name = senderName;
    return ComposerBanner(
      icon: LucideIcons.reply,
      title: name == null ? '返信先' : ReplyQuote.previewTitleFor(name),
      quote: messageContent,
      closeLabel: '返信をやめる',
      onClose: onCancel,
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
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [child],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'ReplyPreview - 短い本文')
Widget previewReplyPreviewShort() {
  return _previewApp(
    brightness: Brightness.light,
    child: ReplyPreview(
      senderName: '田中トレーナー',
      messageContent: 'こんにちは！',
      onCancel: () {},
    ),
  );
}

@Preview(name: 'ReplyPreview - 長い本文')
Widget previewReplyPreviewLong() {
  return _previewApp(
    brightness: Brightness.light,
    child: ReplyPreview(
      senderName: '田中トレーナー',
      messageContent: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
      onCancel: () {},
    ),
  );
}

@Preview(name: 'ReplyPreview - ダーク・文字1.35')
Widget previewReplyPreviewDarkLarge() {
  return _previewApp(
    brightness: Brightness.dark,
    textScale: 1.35,
    child: ReplyPreview(
      senderName: '田中トレーナー',
      messageContent: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで…',
      onCancel: () {},
    ),
  );
}
