import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:uuid/uuid.dart';

/// 画像のアップロードとストレージ管理を行うサービス
class StorageService {
  static final ImagePicker _picker = ImagePicker();
  static const _uuid = Uuid();

  /// バケット名
  static const String bucketName = 'message-photos';
  static const String avatarBucketName = 'client-avatars';

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

  /// 画像をSupabase Storageにアップロード
  /// [file] - アップロードする画像ファイル
  /// [userId] - ユーザーID（フォルダ分けに使用）
  /// 戻り値: アップロードされた画像の公開URL
  static Future<String?> uploadImage(File file, String userId) async {
    try {
      final fileName = '${_uuid.v4()}.jpg';
      final filePath = '$userId/$fileName';

      await SupabaseService.client.storage
          .from(bucketName)
          .upload(filePath, file);

      // 公開URLを取得
      final publicUrl = SupabaseService.client.storage
          .from(bucketName)
          .getPublicUrl(filePath);

      debugPrint('[StorageService] Uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('[StorageService] uploadImage error: $e');
      return null;
    }
  }

  /// 複数の画像をアップロード
  /// [files] - アップロードする画像ファイルのリスト
  /// [userId] - ユーザーID
  /// 戻り値: アップロードされた画像の公開URLリスト
  static Future<List<String>> uploadImages(
      List<File> files, String userId) async {
    final List<String> urls = [];

    for (final file in files) {
      final url = await uploadImage(file, userId);
      if (url != null) {
        urls.add(url);
      }
    }

    return urls;
  }

  /// 画像を削除
  /// [url] - 削除する画像の公開URL
  static Future<bool> deleteImage(String url) async {
    try {
      // URLからパスを抽出
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;

      // /storage/v1/object/public/bucket-name/path の形式
      final bucketIndex = pathSegments.indexOf(bucketName);
      if (bucketIndex == -1) return false;

      final filePath = pathSegments.sublist(bucketIndex + 1).join('/');

      await SupabaseService.client.storage.from(bucketName).remove([filePath]);

      debugPrint('[StorageService] Deleted: $filePath');
      return true;
    } catch (e) {
      debugPrint('[StorageService] deleteImage error: $e');
      return false;
    }
  }

  /// プロフィール画像をアップロード
  /// [file] - アップロードする画像ファイル
  /// [userId] - ユーザーID
  /// 戻り値: アップロードされた画像の公開URL
  static Future<String?> uploadProfileImage(File file, String userId) async {
    try {
      // プロフィール画像は avatar.jpg 固定（上書き更新）
      final filePath = '$userId/avatar.jpg';

      // 既存の画像を削除（エラーは無視）
      try {
        await SupabaseService.client.storage
            .from(avatarBucketName)
            .remove([filePath]);
      } catch (_) {
        // 既存ファイルがない場合は無視
      }

      // 新しい画像をアップロード
      await SupabaseService.client.storage
          .from(avatarBucketName)
          .upload(filePath, file);

      // 公開URLを取得（キャッシュバスティング用にタイムスタンプ追加）
      final publicUrl = SupabaseService.client.storage
          .from(avatarBucketName)
          .getPublicUrl(filePath);

      final urlWithTimestamp =
          '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      debugPrint('[StorageService] Profile image uploaded: $urlWithTimestamp');
      return urlWithTimestamp;
    } catch (e) {
      debugPrint('[StorageService] uploadProfileImage error: $e');
      return null;
    }
  }

  /// プロフィール画像を削除
  /// [userId] - ユーザーID
  static Future<bool> deleteProfileImage(String userId) async {
    try {
      final filePath = '$userId/avatar.jpg';
      await SupabaseService.client.storage
          .from(avatarBucketName)
          .remove([filePath]);

      debugPrint('[StorageService] Profile image deleted: $filePath');
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
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
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
