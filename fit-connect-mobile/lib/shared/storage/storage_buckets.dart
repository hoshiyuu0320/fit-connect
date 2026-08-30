/// Supabase Storage のバケット名定数。
///
/// DB カラムとバケットの対応は固定:
/// - `messages.image_urls` / `meal_records.images` / `exercise_records.images` → [messagePhotos]
/// - `clients.profile_image_url` → [clientAvatars]（Google 等の外部URLはそのまま保存）
/// - `trainers.profile_image_url` → [profileImages]（Web 側が upload）
/// - `client_notes.file_urls` → [clientNotes]（Web 側が upload。値は `パス#元ファイル名` 形式）
class StorageBuckets {
  StorageBuckets._();

  /// メッセージ添付・記録画像（Mobile が upload）
  static const String messagePhotos = 'message-photos';

  /// クライアントのプロフィール画像（Mobile が upload）
  static const String clientAvatars = 'client-avatars';

  /// トレーナーのプロフィール画像（Web が upload、Mobile は表示のみ）
  static const String profileImages = 'profile-images';

  /// カルテ添付ファイル（Web が upload、Mobile は表示のみ）
  static const String clientNotes = 'client-notes';
}
