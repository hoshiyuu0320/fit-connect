import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/home/presentation/utils/home_formatting.dart';
import 'package:fit_connect_mobile/features/home/providers/latest_trainer_comment_provider.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

// ============================================
// 担当トレーナーの最新コメント
// 正本: home-screens.js の `HomeCoach` / components の `CoachCommentCard`
// （現行の「トレーナーのオンライン表示」の置き換え。オンライン状態・未読の数は出さない）
// ============================================

/// コンテキスト行。「朝食の記録へのコメント · 9:10」。種別が分からなければ時刻のみ。
extension LatestTrainerCommentDisplay on LatestTrainerComment {
  String contextLine({required DateTime now}) {
    final time = formatHomeTime(message.createdAt, now: now);
    final label = recordLabel;
    return label == null ? time : '$labelの記録へのコメント · $time';
  }
}

enum _CoachCardKind { comment, empty, unavailable, loading }

/// ホームの「担当トレーナーの最新コメント」カード。
///
/// - 通常: アバター 39 ＋ 名前（16/500）＋ コンテキスト（12）＋ 本文（16・行高 1.6）＋ 右端の chevron。
///   カード全体を押すとメッセージタブへ
/// - [CoachCommentCard.empty]: メッセージがまだ無いとき。「メッセージを送る」の入口を出す
/// - [CoachCommentCard.unavailable]: 取得に失敗したとき（メッセージ画面への入口は残す）
/// - [CoachCommentCard.loading]: アバターと 2 行のスケルトンで配置を保つ
class CoachCommentCard extends StatelessWidget {
  const CoachCommentCard({
    super.key,
    required this.coachName,
    required String this.message,
    this.profileImageUrl,
    this.contextLine,
    this.onTap,
  })  : _kind = _CoachCardKind.comment,
        onActionTap = null;

  /// メッセージがまだ無い状態
  const CoachCommentCard.empty({
    super.key,
    required this.coachName,
    this.profileImageUrl,
    VoidCallback? onSendMessage,
  })  : _kind = _CoachCardKind.empty,
        message = null,
        contextLine = null,
        onTap = null,
        onActionTap = onSendMessage;

  /// 取得に失敗した状態
  const CoachCommentCard.unavailable({
    super.key,
    required this.coachName,
    this.profileImageUrl,
    VoidCallback? onOpenMessages,
  })  : _kind = _CoachCardKind.unavailable,
        message = null,
        contextLine = null,
        onTap = null,
        onActionTap = onOpenMessages;

  /// 読み込み中
  const CoachCommentCard.loading({super.key})
      : _kind = _CoachCardKind.loading,
        coachName = '',
        message = null,
        profileImageUrl = null,
        contextLine = null,
        onTap = null,
        onActionTap = null;

  final _CoachCardKind _kind;

  /// 表示名（「田中トレーナー」）
  final String coachName;

  final String? message;

  /// `trainers.profile_image_url`（Storage の値）。無ければイニシャル
  final String? profileImageUrl;

  /// 「朝食の記録へのコメント · 9:10」。null なら出さない
  final String? contextLine;

  /// カード全体のタップ（メッセージタブへ）
  final VoidCallback? onTap;

  /// 空・失敗のときのテキストボタン
  final VoidCallback? onActionTap;

  static const _roleCaption = 'あなたの担当トレーナー';

  @override
  Widget build(BuildContext context) {
    switch (_kind) {
      case _CoachCardKind.loading:
        return _buildLoading();
      case _CoachCardKind.comment:
        return _buildComment(context);
      case _CoachCardKind.empty:
        return _buildNotice(
          context,
          body: 'まだメッセージはありません。体重や食事の記録も、メッセージから送れます。',
          actionLabel: 'メッセージを送る',
        );
      case _CoachCardKind.unavailable:
        return _buildNotice(
          context,
          body: 'コメントを読み込めませんでした。メッセージ画面で確認できます。',
          actionLabel: 'メッセージを開く',
        );
    }
  }

  Widget _buildComment(BuildContext context) {
    final colors = AppColors.of(context);
    final label = [
      coachName,
      if (contextLine != null) contextLine!,
      message!,
    ].join('、');

    return FcCard(
      padding: FcCardPadding.coach,
      onTap: onTap,
      semanticLabel: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CoachAvatar(name: coachName, imageUrl: profileImageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: _NameBlock(name: coachName, caption: contextLine),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 10),
                ExcludeSemantics(
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(context).copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice(
    BuildContext context, {
    required String body,
    required String actionLabel,
  }) {
    // 下の「テキストボタン」は高さ 47 あるので、正本の marginBottom -8 にならい
    // カードの下余白を 17 → 9 に詰める（押せる範囲は欠けない）
    const bottom = AppSpacing.coachCardPadding - 8;
    return FcCard(
      paddingOverride: const EdgeInsets.fromLTRB(
        AppSpacing.coachCardPadding,
        AppSpacing.coachCardPadding,
        AppSpacing.coachCardPadding,
        bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CoachAvatar(name: coachName, imageUrl: profileImageUrl),
              const SizedBox(width: 10),
              Expanded(child: _NameBlock(name: coachName, caption: _roleCaption)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            style: AppTextStyles.body(context).copyWith(height: 1.6),
          ),
          FcButton.text(
            label: actionLabel,
            icon: LucideIcons.chevronRight,
            onPressed: onActionTap,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const FcCard(
      padding: FcCardPadding.coach,
      semanticLabel: 'コメントを読み込んでいます',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FcSkeleton.circle(),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBar(widthFactor: 0.45),
                    SizedBox(height: 6),
                    _SkeletonBar(widthFactor: 0.6, height: 10),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          _SkeletonBar(widthFactor: 0.92),
          SizedBox(height: AppSpacing.sm),
          _SkeletonBar(widthFactor: 0.7),
        ],
      ),
    );
  }
}

/// 名前（16/500）と、その下の補足（12 caption）
class _NameBlock extends StatelessWidget {
  const _NameBlock({required this.name, this.caption});

  final String name;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style:
              AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w500),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, style: AppTextStyles.caption(context)),
        ],
      ],
    );
  }
}

/// 幅の割合で決める帯（読み込み中の行）
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor, this.height = 14});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: FcSkeleton(height: height),
    );
  }
}

/// トレーナーのアバター。画像（Storage の値）があれば重ね、読み込み中・失敗時はイニシャルのまま。
///
/// `FcAvatar` は `StorageImage`（署名 URL の解決）を経由できないので、
/// イニシャルの円の上に画像を重ねている。
class _CoachAvatar extends StatelessWidget {
  const _CoachAvatar({required this.name, this.imageUrl});

  final String name;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final base = FcAvatar(name: name, excludeFromSemantics: true);
    final url = imageUrl;
    if (url == null || url.isEmpty) return base;
    return Stack(
      children: [
        base,
        ClipOval(
          child: StorageImage(
            value: url,
            bucket: StorageBuckets.profileImages,
            width: AppSizes.avatar,
            height: AppSizes.avatar,
            fit: BoxFit.cover,
            placeholder: const SizedBox.shrink(),
            errorWidget: const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: child,
        ),
      ),
    ),
  );
}

@Preview(name: 'CoachCommentCard - コメントあり')
Widget previewCoachCommentCard() {
  return _previewApp(
    CoachCommentCard(
      coachName: '田中トレーナー',
      contextLine: '朝食の記録へのコメント · 9:10',
      message: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
      onTap: () {},
    ),
  );
}

@Preview(name: 'CoachCommentCard - コメントあり（ダーク）')
Widget previewCoachCommentCardDark() {
  return _previewApp(
    brightness: Brightness.dark,
    CoachCommentCard(
      coachName: '田中トレーナー',
      contextLine: '体重の記録へのコメント · 8:02',
      message: 'おめでとうございます。ここまで一緒に続けてきた成果ですね。',
      onTap: () {},
    ),
  );
}

@Preview(name: 'CoachCommentCard - メッセージなし')
Widget previewCoachCommentCardEmpty() {
  return _previewApp(
    CoachCommentCard.empty(coachName: '田中トレーナー', onSendMessage: () {}),
  );
}

@Preview(name: 'CoachCommentCard - 読み込めなかった')
Widget previewCoachCommentCardUnavailable() {
  return _previewApp(
    CoachCommentCard.unavailable(
      coachName: '田中トレーナー',
      onOpenMessages: () {},
    ),
  );
}

@Preview(name: 'CoachCommentCard - 読み込み中')
Widget previewCoachCommentCardLoading() {
  return _previewApp(const CoachCommentCard.loading());
}
