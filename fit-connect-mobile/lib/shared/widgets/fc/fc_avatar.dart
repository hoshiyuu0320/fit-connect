import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';

/// 円形のアバター。画像があれば画像、無ければ名前のイニシャル（surfaceSecondary の面）。
/// 正本は `components/core/Avatar.jsx`。
///
/// - サイズは [sm] 29（文字 13）・[md] 39（文字 15・既定）・[lg] 46（文字 17）。プロフィールは
///   [AppSizes.avatarProfile] = 43（文字 16）。ほかの値は直径の 0.38 倍の文字
/// - イニシャルは **accent**・太さ 500（文字拡大には追従する。円は固定）
/// - [imageUrl]（ネットワーク）か [image]（任意の ImageProvider）を渡せる。読み込み失敗時はイニシャルに戻る
/// - 読み上げは [semanticLabel]（null なら名前）。装飾だけにしたいときは `excludeFromSemantics: true`
/// - カテゴリ色は付けない
class FcAvatar extends StatelessWidget {
  const FcAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.image,
    this.size = AppSizes.avatar,
    this.semanticLabel,
    this.excludeFromSemantics = false,
  });

  /// 小（29）
  static const double sm = 29;

  /// 標準（39）
  static const double md = AppSizes.avatar;

  /// 大（46）
  static const double lg = 46;

  /// 円の直径に対するイニシャルの文字サイズ（正本: 29→13 / 39→15 / 46→17 / プロフィール 43→16）
  static double initialsFontSize(double size) {
    if (size == sm) return 13;
    if (size == md) return 15;
    if (size == lg) return 17;
    if (size == AppSizes.avatarProfile) return 16;
    return (size * 0.38).roundToDouble();
  }

  final String name;
  final String? imageUrl;
  final ImageProvider? image;
  final double size;
  final String? semanticLabel;
  final bool excludeFromSemantics;

  /// 名前からイニシャルを作る。「山田 太郎」→「山」、「John Smith」→「JS」、空→「?」
  static String initialsOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final latin = RegExp(r'^[A-Za-z]');
    if (parts.length >= 2 &&
        latin.hasMatch(parts[0]) &&
        latin.hasMatch(parts[1])) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final provider = image ??
        ((imageUrl != null && imageUrl!.isNotEmpty)
            ? NetworkImage(imageUrl!)
            : null);

    final initials = Center(
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: initialsFontSize(size),
          fontWeight: FontWeight.w500,
          color: colors.accent,
          height: 1.0,
        ),
      ),
    );

    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surfaceSecondary,
      ),
      child: provider == null
          ? initials
          : Image(
              image: provider,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => initials,
            ),
    );

    if (excludeFromSemantics) return ExcludeSemantics(child: avatar);
    return Semantics(
      image: true,
      label: semanticLabel ?? name,
      excludeSemantics: true,
      child: avatar,
    );
  }
}
