import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

// ============================================
// 記録フォーム（体重・食事・運動）の共通の殻
// 正本: message-screens.js の `MealForm`（カード・見出し行・写真の並び・「入力欄に入る内容」）
// ============================================

/// 記録フォームのカード。正本 `MealForm` の `Card`（surface・角丸 23・余白 18・左右 16 のマージン）。
///
/// 見出し行の右に置く「×」（44×44）を正本の負マージンの代わりに詰めるため、上の余白を 8 にしてある
/// （正本は 18。見出し行の高さを 24 → 44 にした分）。見出し行は [FormHeading] を使うこと。
class FormCard extends StatelessWidget {
  const FormCard({super.key, required this.child});

  /// カードの左右のマージン（入力欄の左右余白と同じ 16）
  static const double horizontalMargin = AppSpacing.lg;

  /// 正本のカード余白
  static const double inset = 18;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
      child: FcCard(
        paddingOverride: const EdgeInsets.fromLTRB(
          inset,
          inset - FcCloseButton.verticalBleed,
          inset,
          inset,
        ),
        child: child,
      ),
    );
  }
}

/// フォームの見出し行。icon（18・accent）＋ タイトル（16/500）＋ 右の操作。
///
/// 既定の操作は「閉じる」（[FcCloseButton]）。確認画面の「戻る」のように別の操作を置くときは [action]。
/// 行の高さは 44（閉じるボタンの高さ）で、後ろに [FcCloseButton.verticalBleed] を引いた余白 2 を含む
/// （正本: 見出し行 24 + 余白 12 = 36 に揃う）。
class FormHeading extends StatelessWidget {
  const FormHeading({
    super.key,
    required this.icon,
    required this.title,
    this.onClose,
    this.closeLabel = '閉じる',
    this.action,
    this.leading,
  });

  final IconData icon;
  final String title;

  /// 「×」を押したとき。null で [action] だけ（または何も出さない）
  final VoidCallback? onClose;
  final String closeLabel;

  /// 「×」の代わりに右へ置く操作
  final Widget? action;

  /// アイコンの代わりに置く部品（処理中のスピナーなど）
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Widget? trailing = action;
    if (trailing == null && onClose != null) {
      // 「×」の字が本文の右端に揃うよう、押せる範囲ごと右へ 12 ずらす（カードの右余白 18 の中に収まる）
      trailing = Transform.translate(
        offset: const Offset(FcCloseButton.endBleed, 0),
        child: FcCloseButton(onPressed: onClose, semanticLabel: closeLabel),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading ??
                  ExcludeSemantics(
                    child: Icon(icon, size: 18, color: colors.accent),
                  ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTextStyles.body(context)
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
        // 見出し行の下の余白 12 から、閉じるボタンが食い込む 10 を引いた分
        const SizedBox(height: AppSpacing.md - FcCloseButton.verticalBleed),
      ],
    );
  }
}

/// 「入力欄に入る内容」（caption）＋ `#食事:昼食 鶏むね肉のグリル定食`（13・タグは accent）。
///
/// [text] は `#タグ 本文` の形。最初の空白までを accent で、残りを textPrimary で描く。
/// 本文が `--`（未入力）のときは textSecondary にする。
class ComposedPreview extends StatelessWidget {
  const ComposedPreview({
    super.key,
    required this.text,
    this.title = '入力欄に入る内容',
  });

  final String text;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final space = text.indexOf(' ');
    final tag = space == -1 ? text : text.substring(0, space);
    final rest = space == -1 ? '' : text.substring(space);
    final style = AppTextStyles.supplement(context)
        .copyWith(color: colors.textPrimary, height: 1.5);
    final placeholder = rest.trim() == '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppTextStyles.caption(context)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: tag, style: style.copyWith(color: colors.accent)),
              if (rest.isNotEmpty)
                TextSpan(
                  text: rest,
                  style: placeholder
                      ? style.copyWith(color: colors.textSecondary)
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 選んだ写真のサムネイル（72×72・角丸 14）。右上に「削除」（押せる範囲 44×44）。
///
/// [onAdd] を渡すと、枚数が上限未満のときに「追加」ボタン（72×72・1px separator の枠・角丸 14）を続ける
/// （正本 `MealForm` の `Photo` ＋ 「追加」）。写真が 1 枚も無く [onAdd] も無いときは何も出さない。
class PhotoTiles extends StatelessWidget {
  const PhotoTiles({
    super.key,
    required this.images,
    this.onRemove,
    this.onAdd,
    this.maxCount = 3,
  });

  final List<File> images;
  final void Function(int index)? onRemove;

  /// 「追加」を押したとき。null なら「追加」は出さない
  final VoidCallback? onAdd;

  final int maxCount;

  static const double tileSize = 72;
  static const double tileRadius = 14;

  @override
  Widget build(BuildContext context) {
    final showAdd = onAdd != null && images.length < maxCount;
    if (images.isEmpty && !showAdd) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < images.length; i++)
          _PhotoTile(
            file: images[i],
            index: i,
            onRemove: onRemove == null ? null : () => onRemove!(i),
          ),
        if (showAdd) _AddTile(onTap: onAdd!),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.file,
    required this.index,
    required this.onRemove,
  });

  final File file;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: PhotoTiles.tileSize,
      height: PhotoTiles.tileSize,
      child: Stack(
        children: [
          Semantics(
            image: true,
            label: '選んだ写真 ${index + 1}',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PhotoTiles.tileRadius),
              child: Image.file(
                file,
                width: PhotoTiles.tileSize,
                height: PhotoTiles.tileSize,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const FcPhotoPlaceholder(height: 72, width: 72, radius: 14),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: FcPressable(
                onTap: onRemove,
                semanticLabel: '写真 ${index + 1} を削除',
                minSize: const Size.square(AppSizes.minTouch),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface,
                    border: Border.all(color: colors.separator),
                  ),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Icon(
                      LucideIcons.x,
                      size: 12,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcPressable(
      onTap: onTap,
      semanticLabel: '写真を追加',
      child: Container(
        width: PhotoTiles.tileSize,
        height: PhotoTiles.tileSize,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(PhotoTiles.tileRadius),
          border: Border.all(color: colors.separator),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: Icon(LucideIcons.camera, size: 18, color: colors.accent),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(
                '追加',
                style: AppTextStyles.caption(context)
                    .copyWith(color: colors.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
