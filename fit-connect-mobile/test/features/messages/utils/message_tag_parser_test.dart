import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';

void main() {
  group('parseMessageTags', () {
    test('#食事:種別が本文にあれば #付きで返す', () {
      expect(parseMessageTags('#食事:昼食 サラダチキン'), ['#食事:昼食']);
    });
    test('#食事 + 朝食キーワード → #食事:朝食', () {
      expect(parseMessageTags('#食事 朝食を食べた'), ['#食事:朝食']);
    });
    test('#食事 のみ（種別不明）→ #食事', () {
      expect(parseMessageTags('#食事 なにか'), ['#食事']);
    });
    test('#体重 → #体重', () {
      expect(parseMessageTags('#体重 62.4kg'), ['#体重']);
    });
    test('#運動 + 筋トレ → #運動:筋トレ', () {
      expect(parseMessageTags('#運動 筋トレした'), ['#運動:筋トレ']);
    });
    test('#運動 + ランニング → #運動:ランニング', () {
      expect(parseMessageTags('#運動 ランニング 30分'), ['#運動:ランニング']);
    });
    test('#運動 + 有酸素 → #運動:有酸素', () {
      expect(parseMessageTags('#運動 有酸素 20分'), ['#運動:有酸素']);
    });
    test('#運動 + 完了 → #運動:完了', () {
      expect(parseMessageTags('#運動:完了 脚の日'), ['#運動:完了']);
    });
    test('タグ無しは null', () {
      expect(parseMessageTags('こんにちは'), isNull);
    });
  });
}
