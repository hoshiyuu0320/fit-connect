import 'package:fit_connect_mobile/features/messages/models/message_model.dart';

/// メッセージ一覧の表示フィルタ。
/// 案Aでは all / recordsOnly のみ使用。chatOnly は将来の3タブ（案B）拡張用。
enum MessageFilter { all, recordsOnly, chatOnly }

/// tags が非空なら記録メッセージ（cardinality(tags) > 0 相当）。
bool isRecordMessage(Message m) => m.tags != null && m.tags!.isNotEmpty;

/// フィルタを適用したメッセージ一覧を返す（元リストは変更しない）。
List<Message> applyMessageFilter(List<Message> messages, MessageFilter filter) {
  switch (filter) {
    case MessageFilter.all:
      return messages;
    case MessageFilter.recordsOnly:
      return messages.where(isRecordMessage).toList();
    case MessageFilter.chatOnly:
      return messages.where((m) => !isRecordMessage(m)).toList();
  }
}
