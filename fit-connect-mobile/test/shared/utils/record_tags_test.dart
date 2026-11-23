import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/features/messages/utils/message_tag_parser.dart';
import 'package:fit_connect_mobile/features/record_reminders/domain/reminder_planner.dart';
import 'package:fit_connect_mobile/shared/utils/record_tags.dart';

void main() {
  group('serverRecordTagPattern（parse-message-tags の parseTagFromTags と同じ形）',
      () {
    test('種類と詳細を読む（詳細が無ければ null）', () {
      final withDetail = serverRecordTagPattern.firstMatch('#食事:朝食')!;
      expect(withDetail.group(1), '食事');
      expect(withDetail.group(2), '朝食');

      final noDetail = serverRecordTagPattern.firstMatch('#体重')!;
      expect(noDetail.group(1), '体重');
      expect(noDetail.group(2), isNull);
    });

    test('完全一致で調べる（前後の空白・続く文字があると合わない）', () {
      expect(serverRecordTagPattern.hasMatch('#運動'), isTrue);
      expect(serverRecordTagPattern.hasMatch(' #運動'), isFalse);
      expect(serverRecordTagPattern.hasMatch('#運動 '), isFalse);
      expect(serverRecordTagPattern.hasMatch('#運動\n'), isFalse);
      expect(serverRecordTagPattern.hasMatch('#運動記録'), isFalse);
    });
  });

  group('tagsCreateRecord（サーバーが tags[0] で記録を作るか）', () {
    test('記録になるタグ', () {
      for (final tag in [
        '#体重',
        '#体重:朝',
        '#食事',
        '#食事:朝食',
        '#食事:間食', // サーバーでは snack（リマインダーでは対象外だが、記録にはなる）
        '#食事:夕食',
        '#運動',
        '#運動:完了',
        '#運動:筋トレ',
      ]) {
        expect(tagsCreateRecord([tag]), isTrue, reason: tag);
      }
    });

    test('前後に空白があるタグは記録にならない（サーバーの判定は完全一致）', () {
      expect(tagsCreateRecord([' #体重']), isFalse);
      expect(tagsCreateRecord(['#体重 ']), isFalse);
      expect(tagsCreateRecord(['#体重 60']), isFalse);
      expect(tagsCreateRecord(['#食事 :朝食']), isFalse);
    });

    test('最初のタグだけを見る（2つめ以降は記録にならない）', () {
      expect(tagsCreateRecord(['#メモ', '#体重']), isFalse);
      expect(tagsCreateRecord(['', '#食事:夕食']), isFalse);
      // 最初が記録になれば、後ろに何があっても記録になる
      expect(tagsCreateRecord(['#体重', '#メモ']), isTrue);
    });

    test('タグなし・サーバーの形に合わないタグは記録にならない', () {
      expect(tagsCreateRecord(const []), isFalse);
      for (final tag in [
        '#meal', // 別名（アプリは正準形に直して送る）
        '#weight',
        '#exercise',
        '体重', // # なし
        '#食事:', // 詳細が空
        '#体重記録',
        '#睡眠',
        '#メモ',
        '',
      ]) {
        expect(tagsCreateRecord([tag]), isFalse, reason: tag);
      }
    });

    test('アプリが送るタグ（parseMessageTags の結果）での判定', () {
      bool fromText(String text) =>
          tagsCreateRecord(parseMessageTags(text) ?? const []);

      expect(fromText('#体重 62.4kg'), isTrue);
      // 別名は正準形に直ってから tags に入る
      expect(fromText('#weight 62.4'), isTrue);
      expect(fromText('#meal 朝食 トースト'), isTrue);
      expect(fromText('#食事 夕ご飯 カレー'), isTrue); // '#食事'（間食扱い）でも記録になる
      expect(fromText('#運動 筋トレ'), isTrue);
      expect(fromText('#運動:完了 脚の日'), isTrue);
      expect(fromText('こんにちは'), isFalse);
    });

    test('リマインダーが「今日記録した」と推定するタグは、どれも記録になる（同じ形を使う）', () {
      for (final tag in [
        '#体重',
        '#体重:65.2',
        '#食事:朝食',
        '#食事:昼食',
        '#食事:夕食',
        '#食事:晩ごはん',
        '#食事:間食',
        '#食事',
        '#運動',
        ' #体重',
        '#体重 ',
        '#meal',
        '',
      ]) {
        if (reminderKindsFromTags([tag]).isNotEmpty) {
          expect(tagsCreateRecord([tag]), isTrue, reason: tag);
        }
        if (!tagsCreateRecord([tag])) {
          expect(reminderKindsFromTags([tag]), isEmpty, reason: tag);
        }
      }
    });
  });
}
