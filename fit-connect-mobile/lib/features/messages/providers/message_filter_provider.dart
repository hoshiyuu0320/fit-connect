import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/messages/utils/message_filter.dart';

part 'message_filter_provider.g.dart';

/// メッセージ画面の表示フィルタ状態（デフォルト: すべて）。
@riverpod
class MessageFilterController extends _$MessageFilterController {
  @override
  MessageFilter build() => MessageFilter.all;

  void setFilter(MessageFilter filter) => state = filter;
}
