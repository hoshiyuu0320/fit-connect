import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_filter.dart';

Message _msg(String id, {List<String>? tags}) => Message(
      id: id,
      senderId: 'c',
      receiverId: 't',
      senderType: 'client',
      receiverType: 'trainer',
      content: 'x',
      tags: tags,
      createdAt: DateTime(2026, 1, 1),
      isEdited: false,
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final chat = _msg('1'); // tags なし
  final chatEmpty = _msg('2', tags: []); // 空配列
  final meal = _msg('3', tags: ['#食事:昼食']);
  final weight = _msg('4', tags: ['#体重']);
  final all = [chat, chatEmpty, meal, weight];

  group('isRecordMessage', () {
    test('tagsが非空なら記録', () {
      expect(isRecordMessage(meal), isTrue);
    });
    test('tagsがnull/空配列なら会話', () {
      expect(isRecordMessage(chat), isFalse);
      expect(isRecordMessage(chatEmpty), isFalse);
    });
  });

  group('applyMessageFilter', () {
    test('all は全件そのまま', () {
      expect(applyMessageFilter(all, MessageFilter.all), all);
    });
    test('recordsOnly は記録だけ', () {
      expect(applyMessageFilter(all, MessageFilter.recordsOnly), [meal, weight]);
    });
    test('chatOnly は会話だけ', () {
      expect(applyMessageFilter(all, MessageFilter.chatOnly), [chat, chatEmpty]);
    });
  });
}
