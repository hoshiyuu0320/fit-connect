# FIT-CONNECT Mobile: ワークアウト完了報告 改修設計書

> 作成日: 2026-02-22
> 対象: モバイルアプリ（Flutter / Riverpod）
> 関連: Web側設計書 `/docs/DESIGN_EXERCISE_TAB_ENHANCEMENT.md`

---

## 1. 背景

### 現在の問題

ワークアウトプラン完了時に送信されるメッセージ:

```dart
content: '#運動:完了 本日のワークアウトプラン「$planTitle」を達成しました！',
tags: ['運動:完了'],
```

このメッセージがEdge Function `parse-message-tags` で処理され、`exercise_records` テーブルに **不正確なレコード** が作成される:

- `exercise_type: 'running'`（本来は `strength_training` であるべき）
- 原因: Edge Functionの `notes.includes('ラン')` が `ワークアウトプ**ラン**` にマッチ

### さらに深い問題

モバイルアプリは既に `workout_assignments` テーブルを直接更新して完了を記録している（`WorkoutRepository.completeAssignment()`）。つまり完了データは **二重登録** されている:

1. `workout_assignments.status = 'completed'` （正確、セット実績あり）
2. `exercise_records` に新規レコード（不正確、詳細なし）

---

## 2. 改修内容

### 2A. 完了メッセージからタグを除去（exercise_records 二重登録の防止）

完了報告メッセージから `#運動:完了` タグを除去し、通知目的のプレーンメッセージに変更する。

### 2B. client_feedback フィールドの追加

完了報告時にクライアントからのフィードバック（感想・体調など）を入力できるようにし、`workout_assignments.client_feedback` に保存する。Web側のセッション画面・運動タブでトレーナーが確認可能。

### 2C. `plan_type` フィルタの見直し（将来対応・任意）

現在は `self_guided`（宿題）のみ表示。`session` タイプはトレーナーがWeb側のセッション画面で操作するため、**モバイルでは引き続き `self_guided` のみ表示で問題ない**。変更不要。

---

## 3. 変更対象ファイル

| # | ファイルパス | 変更内容 |
|---|------------|----------|
| 1 | `lib/features/workout/presentation/screens/workout_screen.dart` | 完了メッセージのタグ除去 + フィードバック入力ダイアログ追加 |
| 2 | `lib/features/workout/data/workout_repository.dart` | `completeAssignment()` に `clientFeedback` パラメータ追加 |
| 3 | `lib/features/workout/providers/workout_provider.dart` | `submitCompletion()` に `clientFeedback` パラメータ追加 |

---

## 4. 変更詳細

### 4A. `workout_screen.dart` の変更

#### 4A-1. 完了メッセージの変更

**現在（45行目）:**
```dart
content: '#運動:完了 本日のワークアウトプラン「$planTitle」を達成しました！',
tags: ['運動:完了'],
```

**変更後:**
```dart
content: '本日のワークアウトプラン「$planTitle」を達成しました！',
// tags パラメータを削除、または空リストに
```

**重要**: `tags` を含めないことで Edge Function がこのメッセージを運動記録として処理しなくなる。メッセージ自体は通知として送信される（トレーナーへのFCMプッシュ通知は維持）。

#### 4A-2. フィードバック入力ダイアログの追加

「完了報告」ボタン押下時に、フィードバック入力ダイアログを表示:

```dart
Future<void> _handleSubmitCompletion(WorkoutAssignment assignment) async {
  // フィードバック入力ダイアログを表示
  final feedback = await showDialog<String>(
    context: context,
    builder: (context) => _FeedbackDialog(),
  );

  // キャンセル時は何もしない
  if (feedback == null) return;

  final planTitle = assignment.planInfo?.title ?? 'ワークアウトプラン';
  final clientId = ref.read(currentClientIdProvider);
  final trainerId = ref.read(currentTrainerIdProvider);

  // DB更新（フィードバック付き）
  await ref
      .read(todayAssignmentsProvider.notifier)
      .submitCompletion(assignment.id, clientFeedback: feedback);

  // 通知メッセージ送信（タグなし）
  if (clientId != null && trainerId != null) {
    try {
      final messageContent = feedback.isNotEmpty
          ? '本日のワークアウトプラン「$planTitle」を達成しました！\n\n💬 $feedback'
          : '本日のワークアウトプラン「$planTitle」を達成しました！';

      await MessageRepository().sendMessage(
        senderId: clientId,
        receiverId: trainerId,
        senderType: 'client',
        receiverType: 'trainer',
        content: messageContent,
        // tags は指定しない（exercise_records 自動作成を防止）
      );
    } catch (e) {
      debugPrint('[WorkoutScreen] メッセージ送信エラー: $e');
    }
  }

  setState(() {
    _completedPlanTitle = planTitle;
    _showCompletionOverlay = true;
  });
}
```

#### 4A-3. フィードバックダイアログ Widget

```dart
class _FeedbackDialog extends StatefulWidget {
  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('完了報告'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '感想やコンディションを入力してください（任意）',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '例: 今日は調子が良かった！',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null), // キャンセル
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('完了報告を送信'),
        ),
      ],
    );
  }
}
```

**UX補足:**
- フィードバックは任意（空文字でも送信可能）
- キャンセルで `null` を返す → 完了処理自体がキャンセルされる
- 既存のお祝いオーバーレイ（Confetti）はダイアログの後に表示される

---

### 4B. `workout_repository.dart` の変更

`completeAssignment()` に `clientFeedback` パラメータを追加:

**現在:**
```dart
Future<void> completeAssignment(String assignmentId) async {
  await SupabaseService.client
      .from('workout_assignments')
      .update({
        'status': 'completed',
        'finished_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', assignmentId);
}
```

**変更後:**
```dart
Future<void> completeAssignment(
  String assignmentId, {
  String? clientFeedback,
}) async {
  final updateData = <String, dynamic>{
    'status': 'completed',
    'finished_at': DateTime.now().toUtc().toIso8601String(),
  };

  if (clientFeedback != null && clientFeedback.isNotEmpty) {
    updateData['client_feedback'] = clientFeedback;
  }

  await SupabaseService.client
      .from('workout_assignments')
      .update(updateData)
      .eq('id', assignmentId);
}
```

---

### 4C. `workout_provider.dart` の変更

`submitCompletion()` に `clientFeedback` パラメータを追加:

**変更後:**
```dart
Future<void> submitCompletion(
  String assignmentId, {
  String? clientFeedback,
}) async {
  await WorkoutRepository().completeAssignment(
    assignmentId,
    clientFeedback: clientFeedback,
  );

  // ローカル state 更新
  final current = state.valueOrNull ?? [];
  state = AsyncData(
    current.map((a) {
      if (a.id == assignmentId) {
        return a.copyWith(status: 'completed');
      }
      return a;
    }).toList(),
  );
}
```

---

## 5. MessageRepository.sendMessage() の確認事項

`tags` パラメータが省略可能（nullable）であることを確認すること。

現在の `sendMessage` のシグネチャ:

```dart
Future<Message> sendMessage({
  required String senderId,
  required String receiverId,
  required String senderType,
  required String receiverType,
  required String content,
  List<String>? tags,          // ← nullable であれば変更不要
  List<String>? imageUrls,
  String? replyToMessageId,
});
```

`tags` が `null` または省略された場合、messages テーブルの `tags` カラムは `null` で INSERT される。Edge Function は `tags` が `null` のメッセージでも `content` 内の `#` タグを解析するため、**content から `#運動:完了` を必ず除去すること**が重要。

---

## 6. Edge Function 側の修正（Web側で対応）

以下はWeb側で対応する。モバイル側の改修とは独立して実施可能。

1. `createExerciseRecord` 内の `notes.includes('ラン')` を正規表現に変更（`プラン` の誤マッチ防止）
2. `#運動:完了` タグ時のデフォルト exercise_type を `strength_training` に変更

---

## 7. テスト項目

| # | テスト | 期待結果 |
|---|--------|----------|
| 1 | 全種目完了後「完了報告」ボタンを押す | フィードバック入力ダイアログが表示される |
| 2 | フィードバック入力して送信 | `workout_assignments.client_feedback` に保存される |
| 3 | フィードバック空で送信 | `client_feedback` は `null` のまま、完了処理は成功 |
| 4 | ダイアログでキャンセル | 完了処理がキャンセルされ、ステータスは `pending` のまま |
| 5 | 完了後のメッセージを確認 | `#運動:完了` タグが含まれない |
| 6 | 完了後、`exercise_records` を確認 | 新規レコードが作成されていない |
| 7 | トレーナーのWeb側でクライアントの運動タブを確認 | ワークアウト実績（セット詳細）が表示される |
| 8 | トレーナーへのプッシュ通知 | メッセージ通知は従来通り届く |
| 9 | お祝いオーバーレイ（Confetti） | フィードバック送信後に表示される |

---

## 8. データフロー（改修後）

```
クライアント: 全種目完了 → 「完了報告」ボタン
    │
    ▼
フィードバック入力ダイアログ
    │
    ├── キャンセル → 何もしない
    │
    └── 送信
        │
        ├── 1. workout_assignments UPDATE
        │   ├── status: 'completed'
        │   ├── finished_at: now()
        │   └── client_feedback: "今日は調子が良かった！"
        │
        ├── 2. messages INSERT（通知目的のみ）
        │   ├── content: "本日のワークアウトプラン「大胸筋の強化」を達成しました！\n\n💬 今日は調子が良かった！"
        │   ├── tags: null  ← タグなし
        │   └── → Edge Function: タグなしのため exercise_records 作成されない
        │       └── → FCM通知はトレーナーに送信される
        │
        └── 3. お祝いオーバーレイ表示（Confetti）
```

**Web側（トレーナー）:**
```
スケジュール画面: sessions テーブル経由で予定表示
顧客詳細 > 運動タブ: workout_assignments からセット実績を表示（別途Web側で改修）
顧客詳細 > セッション画面: 既存通り workout_assignments を表示
```

---

## 9. 変更しないファイル

以下のファイルは変更不要:

| ファイル | 理由 |
|----------|------|
| `workout_assignment_model.dart` | 既存モデルに `clientFeedback` は含まれていないが、Supabase直接UPDATEのため型定義への追加は不要（Repository層で直接カラム指定） |
| `workout_exercise_card.dart` | セット入力UIに変更なし |
| `workout_progress_bar.dart` | 変更なし |
| `workout_completion_overlay.dart` | 変更なし |
| `message_repository.dart` | `tags` が既に nullable であれば変更なし |

---

## 10. 実装の優先順位

| 優先度 | タスク | 変更量 |
|--------|--------|--------|
| **必須** | 完了メッセージから `#運動:完了` タグを除去 | 2行変更 |
| **推奨** | フィードバック入力ダイアログ追加 | 新規Widget + 既存3ファイル変更 |
| **不要** | `plan_type` フィルタ変更 | 変更なし（`self_guided` のみで正しい） |

最小限の修正（タグ除去のみ）であれば `workout_screen.dart` の2行変更で完了する。
