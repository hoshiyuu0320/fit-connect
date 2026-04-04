/// タグデータモデル
/// メッセージから解析されたタグ情報を保持
class TagData {
  final String category; // '食事' | '運動' | '体重'
  final String? detail; // '朝食' | '筋トレ' など
  final String fullTag; // '#食事:朝食'

  const TagData({
    required this.category,
    this.detail,
    required this.fullTag,
  });

  /// タグ文字列から TagData を生成
  /// 例: '#食事:朝食' -> TagData(category: '食事', detail: '朝食', fullTag: '#食事:朝食')
  factory TagData.parse(String tag) {
    // '#' を除去
    final tagWithoutHash = tag.startsWith('#') ? tag.substring(1) : tag;

    // ':' で分割
    final parts = tagWithoutHash.split(':');
    final category = parts[0];
    final detail = parts.length > 1 ? parts[1] : null;

    return TagData(
      category: category,
      detail: detail,
      fullTag: tag,
    );
  }

  @override
  String toString() => fullTag;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagData &&
          runtimeType == other.runtimeType &&
          fullTag == other.fullTag;

  @override
  int get hashCode => fullTag.hashCode;
}
