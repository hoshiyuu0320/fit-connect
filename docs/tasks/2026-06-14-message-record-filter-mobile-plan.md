# メッセージ 会話/記録フィルタUI（Mobile案A）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mobile（クライアント）のメッセージ画面に「すべて / 記録」切替トグルを追加し、記録だけに絞り込めるようにする。入力欄は一体のまま（コンセプト「記録と報告が同時」を維持）。

**Architecture:** 記録判定とフィルタを純関数 `applyMessageFilter` に切り出してテスト可能にし、フィルタ状態を Riverpod の `MessageFilter` enum provider で保持。`message_screen` のメッセージ一覧の直上に `SegmentedButton` トグルを置き、「記録のみ」表示中に通常メッセージ（タグなし）を送ると自動で「すべて」に戻す。enum は将来の3タブ（案B）拡張に備え `all`/`recordsOnly`/`chatOnly` の3値で定義（案Aでは `all`/`recordsOnly` のみ使用）。

**Tech Stack:** Flutter 3.41.9 (fvm) + Riverpod(@riverpod/build_runner) + Material 3 `SegmentedButton` + lucide_icons

**前提（基盤フェーズ完了済み）:** `message.tags` が非空 = 記録（`cardinality(tags)>0` 相当）。送信時に `#`付き正準タグが付与される。

---

## File Structure

- **Create** `fit-connect-mobile/lib/features/messages/utils/message_filter.dart` — `MessageFilter` enum＋`isRecordMessage`/`applyMessageFilter` 純関数（記録判定とフィルタ）
- **Create** `fit-connect-mobile/test/features/messages/utils/message_filter_test.dart`
- **Create** `fit-connect-mobile/lib/features/messages/providers/message_filter_provider.dart` — `@riverpod` の enum state controller（`.g.dart` は build_runner 生成）
- **Modify** `fit-connect-mobile/lib/features/messages/presentation/screens/message_screen.dart` — トグルUI設置・フィルタ適用・空状態・送信時の自動復帰

---

## Task 1: フィルタ純関数 ＋ テスト（TDD）

**Files:**
- Create: `fit-connect-mobile/lib/features/messages/utils/message_filter.dart`
- Test: `fit-connect-mobile/test/features/messages/utils/message_filter_test.dart`

- [ ] **Step 1: 失敗するテストを書く**

`fit-connect-mobile/test/features/messages/utils/message_filter_test.dart`:
```dart
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
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect-mobile && (fvm flutter test || flutter test) test/features/messages/utils/message_filter_test.dart`
Expected: コンパイルエラー（`message_filter.dart` が無い）

- [ ] **Step 3: 実装を書く**

`fit-connect-mobile/lib/features/messages/utils/message_filter.dart`:
```dart
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
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd fit-connect-mobile && (fvm flutter test || flutter test) test/features/messages/utils/message_filter_test.dart`
Expected: All tests passed! (5 tests)

- [ ] **Step 5: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/utils/message_filter.dart fit-connect-mobile/test/features/messages/utils/message_filter_test.dart
git commit -m "feat(mobile): メッセージ表示フィルタの純関数とenumを追加"
```

---

## Task 2: フィルタ状態の Riverpod provider

**Files:**
- Create: `fit-connect-mobile/lib/features/messages/providers/message_filter_provider.dart`

- [ ] **Step 1: provider を作成**

`fit-connect-mobile/lib/features/messages/providers/message_filter_provider.dart`:
```dart
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
```

- [ ] **Step 2: コード生成**

Run: `cd fit-connect-mobile && (fvm dart run build_runner build --delete-conflicting-outputs || dart run build_runner build --delete-conflicting-outputs)`
Expected: `message_filter_provider.g.dart` が生成され、ビルドエラーなし

- [ ] **Step 3: 解析で検証**

Run: `cd fit-connect-mobile && (fvm flutter analyze || flutter analyze) lib/features/messages/providers/message_filter_provider.dart`
Expected: No issues found!

- [ ] **Step 4: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/providers/message_filter_provider.dart fit-connect-mobile/lib/features/messages/providers/message_filter_provider.g.dart
git commit -m "feat(mobile): メッセージフィルタ状態のRiverpod providerを追加"
```

---

## Task 3: message_screen にトグルUI・フィルタ・自動復帰を組み込む

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/screens/message_screen.dart`

- [ ] **Step 1: import を追加**

ファイル冒頭の import 群に追加:
```dart
import 'package:fit_connect_mobile/features/messages/utils/message_filter.dart';
import 'package:fit_connect_mobile/features/messages/providers/message_filter_provider.dart';
```

- [ ] **Step 2: build でフィルタを watch し、一覧の直上にトグルを設置**

`build` メソッド内、`final colors = AppColors.of(context);`（L188付近）の直後に追加:
```dart
    final messageFilter = ref.watch(messageFilterControllerProvider);
```

`body: Column` の `children`（L216-）で、オフライン警告バナーの `if (!isTrainerOnline) ...`（L218-240）と `Expanded(`（L241）の**間**に、トグル行を挿入:
```dart
            // 会話/記録 切替トグル（記録だけに絞り込める）
            Container(
              width: double.infinity,
              color: colors.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SegmentedButton<MessageFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MessageFilter.all,
                    icon: Icon(LucideIcons.messagesSquare, size: 16),
                    label: Text('すべて'),
                  ),
                  ButtonSegment(
                    value: MessageFilter.recordsOnly,
                    icon: Icon(LucideIcons.clipboardList, size: 16),
                    label: Text('記録'),
                  ),
                ],
                selected: {messageFilter},
                onSelectionChanged: (selected) {
                  ref
                      .read(messageFilterControllerProvider.notifier)
                      .setFilter(selected.first);
                },
              ),
            ),
```

- [ ] **Step 3: Expanded内の空状態判定をフィルタ後で行う**

`Expanded`（L241-275）内の `stateAsync.when` の `data:` コールバック（L243-250）を以下に置き換える。全体が空 or フィルタ後が空なら空状態、それ以外は一覧:
```dart
                data: (paginatedState) {
                  final filtered = applyMessageFilter(
                      paginatedState.messages, messageFilter);
                  if (filtered.isEmpty) {
                    return _buildEmptyState(
                      colors,
                      recordsOnly: messageFilter == MessageFilter.recordsOnly,
                    );
                  }
                  return _buildMessageList(
                      paginatedState, currentUser?.id, colors, filtered);
                },
```

- [ ] **Step 4: `_buildMessageList` をフィルタ後リストで描画（引用解決は全件から）**

`_buildMessageList` のシグネチャ（L416-417）に絞り込み済みリスト引数を追加し、グルーピングはそれを使う。返信参照は全件から引くため別変数にする。L416-418 を以下に置き換え:
```dart
  Widget _buildMessageList(PaginatedMessagesState paginatedState,
      String? currentUserId, AppColorsExtension colors, List<Message> messages) {
    final allMessages = paginatedState.messages;
    final trainerProfile = ref.watch(trainerProfileProvider).valueOrNull;
    final trainerName = trainerProfile?.name ?? 'トレーナー';
```
さらに、返信参照ヘルパ（L423-430 `findMessageById`）の検索対象を `messages` から `allMessages` に変更:
```dart
    Message? findMessageById(String? id) {
      if (id == null) return null;
      try {
        return allMessages.firstWhere((m) => m.id == id);
      } catch (_) {
        return null;
      }
    }
```
（グルーピング L433-437 以降は引数 `messages`＝フィルタ後リストをそのまま使う。変更不要）

- [ ] **Step 5: `_buildEmptyState` を recordsOnly 対応にする**

既存の `_buildEmptyState` メソッド（`Widget _buildEmptyState(AppColorsExtension colors)` の定義箇所）を探し、シグネチャと文言を変更:
```dart
  Widget _buildEmptyState(AppColorsExtension colors, {bool recordsOnly = false}) {
```
本文中のメインのメッセージ文言（例: 「メッセージがありません」等の Text）を、recordsOnly 時に出し分け。該当 Text を以下のように変更:
```dart
            Text(
              recordsOnly ? 'まだ記録がありません' : 'メッセージがありません',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
```
（`_buildEmptyState` の他の構造・アイコン等は既存のまま。Text の文言のみ条件分岐にする）

- [ ] **Step 6: `_handleSend` で記録のみ表示中の通常メッセージ送信時に「すべて」へ自動復帰**

`_handleSend`（L148-184）の通常送信パス、`final tags = parseMessageTags(text);`（L163付近）の後、`sendMessage(...)` 成功後の `_clearReplyTarget();`（L173付近）の直前に追加:
```dart
      // 記録のみ表示中にタグなしメッセージを送ったら「すべて」に戻す（送ったものが隠れないように）
      if (tags == null || tags.isEmpty) {
        ref
            .read(messageFilterControllerProvider.notifier)
            .setFilter(MessageFilter.all);
      }
```
（`parseMessageTags` は `List<String>?` を返す。タグなしは `null`。編集パスは L156-159 で return 済みのため、このコードは通常送信時のみ実行される）

- [ ] **Step 7: コード生成（必要なら）＋解析**

Run: `cd fit-connect-mobile && (fvm flutter analyze || flutter analyze) lib/features/messages/presentation/screens/message_screen.dart`
Expected: No issues found!（新規 error なし。既存の info/warning は許容）

- [ ] **Step 8: コミット**

```bash
git add fit-connect-mobile/lib/features/messages/presentation/screens/message_screen.dart
git commit -m "feat(mobile): メッセージ画面に会話/記録切替トグルと自動復帰を追加"
```

---

## QA（実装後）

`ios-simulator-qa` スキルで以下を確認:
- トグル「すべて/記録」が一覧上部に表示される
- 「記録」を選ぶと記録（食事/体重/運動/達成）だけ表示、「すべて」で混在に戻る
- 記録のみ表示中に通常メッセージを送ると「すべて」に自動で戻り、送信内容が見える
- 記録ゼロのクライアントで「記録」を選ぶと「まだ記録がありません」が出る
- 入力欄（QuickActionBar含む）はトグルに関わらず常に一体で操作できる

---

## Self-Review

**1. Spec coverage（設計書の案A要件 → タスク対応）:**
- 混在ベース＋切替トグル（すべて/記録）→ Task 3 Step 2 ✅
- フィルタ状態を enum（all/recordsOnly/chatOnly）で保持、将来3タブ拡張可 → Task 1（enum）/ Task 2（provider）✅
- 入力欄は一体のまま → 変更せず（ChatInput は触らない）✅
- 記録のみ表示中の通常メッセージ送信で「すべて」に自動復帰 → Task 3 Step 6 ✅
- 記録ゼロの空状態 → Task 3 Step 3・5 ✅

**2. Placeholder scan:** 各ステップに実コードを記載。"TBD"等なし。

**3. Type consistency:**
- `MessageFilter`（Task 1 定義）→ Task 2 provider・Task 3 UI で一貫使用 ✅
- `applyMessageFilter(List<Message>, MessageFilter)` / `isRecordMessage(Message)`（Task 1）→ Task 3 で同シグネチャ呼び出し ✅
- `messageFilterControllerProvider` / `.setFilter()`（Task 2 の `@riverpod` 生成名）→ Task 3 で watch/read ✅
- `_buildMessageList` 第4引数 `List<Message> messages` 追加（Task 3 Step 4）→ 呼び出し側（Step 3）も4引数に更新済み ✅
- `_buildEmptyState` 第2引数 `{bool recordsOnly}` 追加（Step 5）→ 呼び出し側（Step 3）も対応 ✅
