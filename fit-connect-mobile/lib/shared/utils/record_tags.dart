/// サーバー（parse-message-tags の parseTagFromTags）が記録にするタグの形。
/// '#体重' / '#食事' / '#食事:朝食' / '#運動' など。
///
/// 完全一致で調べるので、前後に空白があるタグ（' #体重'・'#体重 '）は記録にならない。
/// group(1) が記録の種類（食事・運動・体重）、group(2) が ':' の後の詳細（無ければ null）。
/// サーバーの正規表現を変えたら、ここも合わせること
final RegExp serverRecordTagPattern = RegExp(r'^#(食事|運動|体重)(?::(.+))?$');

/// 送ったメッセージのタグ [tags] から、サーバーが記録を作るか。
///
/// サーバーは `tags[0]` だけを記録にするので、最初のタグだけを見る（2つめ以降は見ない）。
/// タグが無ければ false。
/// アプリの parseMessageTags は別名（#meal / #weight / #exercise）を正準形に直して送るので、
/// 別名がそのまま tags に入ることは無い（入っていても記録にはならない）
bool tagsCreateRecord(List<String> tags) =>
    tags.isNotEmpty && serverRecordTagPattern.hasMatch(tags.first);
