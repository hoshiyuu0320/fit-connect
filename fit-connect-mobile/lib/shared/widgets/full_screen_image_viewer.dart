import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/storage_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// フルスクリーン画像ビューア
///
/// DB に保存された Storage 値（バケット相対パス / レガシーURL / 外部URL）と
/// バケット名を受け取り、内部で署名URLに解決して表示する。
///
/// 使い方:
/// ```dart
/// FullScreenImageViewer.show(
///   context: context,
///   values: message.imageUrls!,
///   bucket: StorageBuckets.messagePhotos,
///   initialIndex: 0,
/// );
/// ```
class FullScreenImageViewer extends StatefulWidget {
  /// DB に保存された Storage 値のリスト（バケット相対パス / レガシーURL / 外部URL）
  final List<String> values;

  /// 値が属するバケット名（StorageBuckets 参照）
  final String bucket;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.values,
    required this.bucket,
    this.initialIndex = 0,
  });

  /// 便利メソッド: フルスクリーンで画像ビューアを表示
  static void show({
    required BuildContext context,
    required List<String> values,
    required String bucket,
    int initialIndex = 0,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FullScreenImageViewer(
            values: values,
            bucket: bucket,
            initialIndex: initialIndex,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 画像 PageView（ピンチズーム対応）
          PageView.builder(
            controller: _pageController,
            itemCount: widget.values.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: StorageImage(
                    value: widget.values[index],
                    bucket: widget.bucket,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: const Center(
                      child: Icon(
                        LucideIcons.imageOff,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 閉じるボタン（左上）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
          ),

          // ページインジケーター（複数画像の場合のみ、下部に表示）
          if (widget.values.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ページ番号テキスト
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.values.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
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

// プレビュー用のスタティックWidget
class _PreviewFullScreenImageViewer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // モック画像
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: AppColors.slate700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.image, color: Colors.white54, size: 64),
                  SizedBox(height: 8),
                  Text(
                    'フルスクリーン画像',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          // 閉じるボタン
          Positioned(
            top: 56,
            left: 8,
            child: IconButton(
              onPressed: () {},
              icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
              ),
            ),
          ),
          // ページインジケーター
          Positioned(
            bottom: 56,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    '1 / 3',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

@Preview(name: 'FullScreenImageViewer - Static Preview')
Widget previewFullScreenImageViewer() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: _PreviewFullScreenImageViewer(),
  );
}
