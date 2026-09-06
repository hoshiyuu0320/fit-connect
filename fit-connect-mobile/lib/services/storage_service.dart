import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/storage/storage_buckets.dart';
import 'package:uuid/uuid.dart';

/// 画像のアップロードとストレージ管理を行うサービス
class StorageService {
  static final ImagePicker _picker = ImagePicker();
  static const _uuid = Uuid();

  /// バケット名（定義の実体は StorageBuckets。既存呼び出し互換のため別名で公開）
  static const String bucketName = StorageBuckets.messagePhotos;
  static const String avatarBucketName = StorageBuckets.clientAvatars;

  /// 画像の最大サイズ
  static const double maxWidth = 1920;
  static const double maxHeight = 1080;

  /// 画像の圧縮品質 (0-100)
  static const int imageQuality = 80;

  /// 1メッセージあたりの最大画像数
  static const int maxImagesPerMessage = 3;

  /// カメラまたはギャラリーから画像を選択
  /// [source] - ImageSource.camera または ImageSource.gallery
  /// 戻り値: 選択された画像ファイル、キャンセルされた場合はnull
  static Future<File?> pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
      );

      if (pickedFile == null) return null;
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('[StorageService] pickImage error: $e');
      return null;
    }
  }

  /// 複数の画像をギャラリーから選択
  /// 戻り値: 選択された画像ファイルのリスト
  static Future<List<File>> pickMultipleImages() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        imageQuality: imageQuality,
        limit: maxImagesPerMessage,
      );

      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      debugPrint('[StorageService] pickMultipleImages error: $e');
      return [];
    }
  }

  /// AI 由来の画像を保存するときの相対パス（テスト容易化のため pure に切り出し）
  static String aiImagePath(String userId, String uuid) {
    return '$userId/ai/$uuid.jpg';
  }

  /// 画像をSupabase Storageにアップロード
  /// [file] - アップロードする画像ファイル
  /// [userId] - ユーザーID（フォルダ分けに使用）
  /// 戻り値: バケット相対パス（表示時は署名URLに解決する）
  static Future<String?> uploadImage(File file, String userId) async {
    try {
      final fileName = '${_uuid.v4()}.jpg';
      final filePath = '$userId/$fileName';

      await SupabaseService.client.storage
          .from(bucketName)
          .upload(filePath, file);

      debugPrint('[StorageService] Uploaded: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[StorageService] uploadImage error: $e');
      return null;
    }
  }

  /// 複数の画像をアップロード
  /// [files] - アップロードする画像ファイルのリスト
  /// [userId] - ユーザーID
  /// 戻り値: アップロードされた画像のバケット相対パスのリスト
  static Future<List<String>> uploadImages(
      List<File> files, String userId) async {
    final List<String> paths = [];

    for (final file in files) {
      final path = await uploadImage(file, userId);
      if (path != null) {
        paths.add(path);
      }
    }

    return paths;
  }

  /// AI 推定で利用する画像を Supabase Storage にアップロード（プレフィックス分離）
  /// パス形式: `${userId}/ai/${uuid}.jpg`
  /// orphan 識別のため、通常のメッセージ画像 (`${userId}/${uuid}.jpg`) とフォルダで分離する。
  /// 戻り値: バケット相対パス
  static Future<String?> uploadAiImage(File file, String userId) async {
    try {
      final filePath = aiImagePath(userId, _uuid.v4());
      await SupabaseService.client.storage
          .from(bucketName)
          .upload(filePath, file)
          .timeout(const Duration(seconds: 30));
      debugPrint('[StorageService] AI uploaded: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[StorageService] uploadAiImage error: $e');
      return null;
    }
  }

  /// 複数の AI 用画像を並列アップロード（推定レイテンシ短縮）
  /// 戻り値は files と同じ順序、失敗した要素は null
  static Future<List<String?>> uploadAiImages(
      List<File> files, String userId) async {
    if (files.isEmpty) return const [];
    return Future.wait(files.map((f) => uploadAiImage(f, userId)));
  }

  /// パス指定で Storage 上のファイルを削除
  /// [bucket] - バケット名
  /// [path] - バケット相対パス
  static Future<bool> deleteByPath(String bucket, String path) async {
    try {
      await SupabaseService.client.storage.from(bucket).remove([path]);

      debugPrint('[StorageService] Deleted: $bucket/$path');
      return true;
    } catch (e) {
      debugPrint('[StorageService] deleteByPath error: $e');
      return false;
    }
  }

  /// プロフィール画像をアップロード
  /// [file] - アップロードする画像ファイル
  /// [userId] - ユーザーID
  /// 戻り値: バケット相対パス
  ///
  /// パスは `{userId}/avatar_{timestamp}.jpg`。ファイル名を毎回変えることで
  /// cacheKey（=パス）ベースの画像キャッシュが正しく更新される
  /// （旧 `avatar.jpg` 固定 + `?t=` キャッシュバスター方式は廃止）。
  static Future<String?> uploadProfileImage(File file, String userId) async {
    try {
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '$userId/$fileName';

      // 新しい画像をアップロード
      await SupabaseService.client.storage
          .from(avatarBucketName)
          .upload(filePath, file);

      // 旧 avatar ファイルをベストエフォート削除（失敗しても新画像の利用には影響しない）
      try {
        final entries = await SupabaseService.client.storage
            .from(avatarBucketName)
            .list(path: userId);
        final oldPaths = entries
            .where((e) => e.name.startsWith('avatar') && e.name != fileName)
            .map((e) => '$userId/${e.name}')
            .toList();
        if (oldPaths.isNotEmpty) {
          await SupabaseService.client.storage
              .from(avatarBucketName)
              .remove(oldPaths);
        }
      } catch (e) {
        debugPrint('[StorageService] old avatar cleanup skipped: $e');
      }

      debugPrint('[StorageService] Profile image uploaded: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('[StorageService] uploadProfileImage error: $e');
      return null;
    }
  }

  /// プロフィール画像を削除（自フォルダの avatar 系ファイルを一括削除）
  /// [userId] - ユーザーID
  static Future<bool> deleteProfileImage(String userId) async {
    try {
      final entries = await SupabaseService.client.storage
          .from(avatarBucketName)
          .list(path: userId);
      final targets = entries
          .where((e) => e.name.startsWith('avatar'))
          .map((e) => '$userId/${e.name}')
          .toList();
      if (targets.isNotEmpty) {
        await SupabaseService.client.storage
            .from(avatarBucketName)
            .remove(targets);
      }

      debugPrint('[StorageService] Profile image deleted: $targets');
      return true;
    } catch (e) {
      debugPrint('[StorageService] deleteProfileImage error: $e');
      return false;
    }
  }

  /// 画像選択ダイアログを表示
  /// [context] - BuildContext
  /// 戻り値: 選択された画像ファイル、キャンセルされた場合はnull
  static Future<File?> showImagePickerDialog(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('ギャラリーから選択'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return null;
    return pickImage(source);
  }
}
