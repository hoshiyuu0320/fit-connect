import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';

/// トレーナーのアバター（円形）。
///
/// プロフィール画像は Storage の値（バケット相対パス）なので `StorageImage` で署名 URL に解決する。
/// 画像が無い・読み込み前・失敗したときは [FcAvatar]（イニシャル・accent）に戻る。
/// 名前の隣に置く装飾なので、読み上げは対象外（名前は隣の文字が読み上げる）。
///
/// 基盤の `FcAvatar` は Storage の署名 URL に対応していないため、この feature の中で包んでいる
/// （基盤へ昇格してほしい部品）。
class TrainerAvatar extends StatelessWidget {
  const TrainerAvatar({
    super.key,
    required this.name,
    this.imageValue,
    this.size = FcAvatar.md,
  });

  final String name;

  /// `trainers.profile_image_url`（Storage の値）。null / 空ならイニシャル
  final String? imageValue;

  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = FcAvatar(name: name, size: size, excludeFromSemantics: true);
    final value = imageValue;
    if (value == null || value.isEmpty) return fallback;

    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: StorageImage(
            value: value,
            bucket: StorageBuckets.profileImages,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: fallback,
            errorWidget: fallback,
          ),
        ),
      ),
    );
  }
}
