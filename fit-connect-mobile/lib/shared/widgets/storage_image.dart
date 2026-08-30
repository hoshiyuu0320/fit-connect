import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/storage/signed_url_cache.dart';
import 'package:fit_connect_mobile/shared/storage/storage_value_resolver.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Supabase Storage の画像を署名 URL に解決して表示する共通ウィジェット。
///
/// - [value] にはバケット相対パス / レガシー公開URL / 外部URL のいずれも渡せる
///   （判定は resolveStorageValue に委譲。外部 URL はそのまま表示）
/// - キャッシュキーは `bucket/path` 固定。署名 URL のトークンが変わっても
///   キャッシュミスしない
/// - 解決失敗・読み込み失敗時は [errorWidget]（省略時は imageOff アイコン）
///
/// 使い方:
/// ```dart
/// StorageImage(
///   value: message.imageUrls![i],
///   bucket: StorageBuckets.messagePhotos,
///   width: 100,
///   height: 100,
/// )
/// ```
class StorageImage extends StatefulWidget {
  /// DB に保存された Storage 値（バケット相対パス / レガシーURL / 外部URL）
  final String? value;

  /// 値が属するバケット名（StorageBuckets 参照）
  final String bucket;

  final double? width;
  final double? height;
  final BoxFit fit;

  /// 指定時は ClipRRect で角丸クリップする
  final BorderRadius? borderRadius;

  /// ローディング中の表示（省略時はグレーのプレースホルダー）
  final Widget? placeholder;

  /// 解決失敗・読み込み失敗時の表示（省略時は imageOff アイコン）
  final Widget? errorWidget;

  const StorageImage({
    super.key,
    required this.value,
    required this.bucket,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  late Future<String?> _urlFuture;

  /// 直近で URL 解決が null（失敗）で完了した時刻。
  /// この時刻から [_retryInterval] 以上経過後の再ビルドで自動リトライする
  DateTime? _lastFailedAt;

  /// 解決失敗後に自動リトライするまでの間隔
  /// （SignedUrlCache のネガティブキャッシュ期間に合わせる）
  static const Duration _retryInterval = SignedUrlCache.negativeCacheTtl;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.bucket != widget.bucket) {
      _resolveUrl();
    }
  }

  /// _urlFuture を発行し、解決失敗（null）なら失敗時刻を記録する。
  /// 失敗時刻は次回ビルド時の自動リトライ判定にのみ使うため setState は不要
  void _resolveUrl() {
    _lastFailedAt = null;
    late final Future<String?> future;
    future = SignedUrlCache.instance
        .resolveUrl(widget.value, widget.bucket)
        .then((url) {
      // value 変更等で future が差し替わっていた場合は記録しない
      if (url == null && identical(_urlFuture, future)) {
        _lastFailedAt = DateTime.now();
      }
      return url;
    });
    _urlFuture = future;
  }

  /// キャッシュキー。Storage パスなら `bucket/path`、外部 URL は null
  /// （CachedNetworkImage が URL 自体をキーに使う）
  String? get _cacheKey {
    final path = resolveStorageValue(widget.value, widget.bucket).path;
    return path != null ? '${widget.bucket}/$path' : null;
  }

  Widget _buildPlaceholder(BuildContext context) {
    return widget.placeholder ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        );
  }

  Widget _buildError(BuildContext context) {
    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(LucideIcons.imageOff, size: 24),
        );
  }

  @override
  Widget build(BuildContext context) {
    // 前回の解決が失敗（null）のまま一定時間経過していたら再発行して自動リトライ。
    // ネガティブキャッシュにより、オフライン継続中でも実リクエストは30秒に1回以下
    final lastFailedAt = _lastFailedAt;
    if (lastFailedAt != null &&
        DateTime.now().difference(lastFailedAt) >= _retryInterval) {
      _resolveUrl();
    }

    Widget child = FutureBuilder<String?>(
      future: _urlFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildPlaceholder(context);
        }
        final url = snapshot.data;
        if (url == null) return _buildError(context);
        return CachedNetworkImage(
          imageUrl: url,
          cacheKey: _cacheKey,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          placeholder: (context, _) => _buildPlaceholder(context),
          errorWidget: (context, _, __) => _buildError(context),
        );
      },
    );

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }
    return child;
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'StorageImage - External URL')
Widget previewStorageImageExternalUrl() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              // 外部 URL は署名なしでそのまま表示される
              StorageImage(
                value: 'https://picsum.photos/seed/storage1/200/200',
                bucket: 'message-photos',
                width: 100,
                height: 100,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              SizedBox(width: 8),
              // 値なし → エラーフォールバック
              StorageImage(
                value: null,
                bucket: 'message-photos',
                width: 100,
                height: 100,
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
