# 記録ストリーク表示（フェーズ10.3）— 設計

- 日付: 2026-11-23
- ブランチ: `feature/record-streak`（`develop/1.0.0` から）
- 範囲: Supabase（関数 1 本）と Mobile（ホームの「今日のまとめ」）。Web は変えない
- 前提: カタログ cat2 2-A（`docs/tasks/2026-07-08-solution-catalog.md`）、`IMPLEMENTATION_TASKS.md` 10.3。マイルストーンバッジ（2-B）は今回入れない
- オーナー決定（2026-11-23）
  1. 数えるのは自分で付けた記録だけ。ヘルスケアから自動で入った体重・睡眠は数えない
  2. 出すのはホームだけ
  3. 1 日抜けたら 0 から。ただし今日の分は、今日が終わるまで切れない
  4. 節目のお祝い（2-B）は今回入れない

## 1. 背景（2026-11-23 の調査）

- 記録の表と「どこから入ったか」（`source`）
  - `weight_records`: `recorded_at`（timestamptz）、`source` は `manual` / `message` / `healthkit`（Android の Health Connect も `healthkit`）
  - `meal_records` / `exercise_records`: `recorded_at`、`source` は `manual` / `message`
  - `sleep_records`: `recorded_date`（起きた日の JST の日付。`(client_id, recorded_date)` で一意）、`source` は `manual` / `healthkit`
    - 目覚めの評価（`wakeup_rating`）は必ず本人が付ける。その日にヘルスケアの行があると評価だけを書き足し、`source` は `healthkit` のまま（`sleep_records_provider.dart` の `upsertWakeupRating`）
  - ワークアウト: 完了すると `workout_assignments.status = 'completed'` と `finished_at` が入る。プランの種類は `workout_plans.plan_type`（`self_guided` / `session`）
    - アプリで完了すると、`#運動:完了` のタグ付きメッセージも送る（`workout_completion_message.dart`）。`parse-message-tags` がそれを運動の記録（`exercise_records`、`source = message`）にするので、ふつうは同じ日に運動の記録もできる。0 時の直前に完了し、メッセージが 0 時を過ぎて届くと、翌日も記録した日になる
    - 訂正（2026-11-23 のレビュー）: 初版は「運動の記録は作られない」と書いた。migration `20261123000000` のヘッダーにも同じ誤りがあるが、本番に適用済みなので書き換えない（数え方には影響しない）
- `manual` / `message` の記録は本人のものだけ
  - Web は記録の表を読むだけで、トレーナーが書ける RLS も無い
  - `parse-message-tags` が記録を作るのは、顧客が送ったメッセージ（`sender_type = 'client'`）のときだけ
- 索引: 体重・食事・運動は `(client_id, recorded_at DESC)`、睡眠は `(client_id, recorded_date)` の一意、割り当ては `(client_id)`（`(client_id, assigned_date)` は 20260710010000 で消えている）。どれも client_id で引けるので、新しい索引は要らない（ローカルで約 7,000 行・3 年分の顧客で 1 回約 4 ms）
- ホーム: メイン画面は表示中のタブだけを作る（`_screens[_currentIndex]`）。ホームに戻るたびに、自動破棄の provider は読み直される
- デザインの決まり（`fit-connect-mobile/CLAUDE.md`）: 絵文字・紙吹雪などの演出・数字入りのバッジは使わない。青緑は操作と選択中の表示だけ。アイコンは Lucide

## 2. 成功の条件

- ホームの「今日のまとめ」の先頭に「記録の連続」の行が出て、連続日数と今日の状態が分かる
- 自分で付けた記録だけを数え、ヘルスケアからの自動の取り込みでは続かない
- メッセージで記録を送ってホームに戻ると、記録の作成を待たずに今日の分が反映される
- 日付は日本時間で数える（記録のほかの画面と同じ）
- 他人の連続日数は読めない

## 3. 「記録した日」の定義

日本時間（Asia/Tokyo）の日付で数える。次のどれか 1 件でもある日を「記録した日」とする。

| 記録 | 条件 | 日付 |
|---|---|---|
| 体重 | `source` が `healthkit` でない（`manual` / `message` / NULL） | `recorded_at` の JST の日付 |
| 食事 | すべて | 同上 |
| 運動 | すべて | 同上 |
| 睡眠 | `source = 'manual'` か、`wakeup_rating` が入っている | `recorded_date` |
| ワークアウト | `status = 'completed'`・`finished_at` が入っている・プランが `self_guided` | `finished_at` の JST の日付 |

数えないもの: ヘルスケアから入った体重、評価の無いヘルスケアの睡眠、トレーナーとのセッション（`plan_type = 'session'`）の完了、未完了の割り当て、今日より後の日付の記録。

## 4. 連続日数の決まり

- `streak_until_yesterday`: 昨日から過去へ、記録した日が途切れずに続く日数。昨日に記録が無ければ 0
- `recorded_today`: 今日（JST）に記録があるか
- 画面に出す連続日数
  - 今日記録済み: `streak_until_yesterday + 1`
  - 今日まだ: `streak_until_yesterday`（0 なら「続いていない」）
- 1 日でも抜けたら、その前の日は数えない。今日の分は、今日が終わるまで切れない（昨日まで続いていれば、今日まだ記録していなくても日数はそのまま）

## 5. DB（migration `20261123000000_record_streak.sql`）

### 5.1 関数

```sql
public.get_record_streak(p_client_id uuid)
  RETURNS TABLE (as_of_date date, recorded_today boolean, streak_until_yesterday integer)
  LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
```

- `as_of_date` は DB の今の JST の日付（`(now() AT TIME ZONE 'Asia/Tokyo')::date`）
- §3 の 5 種類の日付を UNION し、`as_of_date` より前の日付を新しい順に並べて、`日付 = as_of_date - 順位` が続くあいだだけ数える
- 記録が 1 件も無くても必ず 1 行返す（`as_of_date`, false, 0）
- 表名・関数名はすべて `public.` で修飾する
- 時刻を差し込む引数は作らない。テストは `now()` からの相対でデータを作る

### 5.2 権限

- SECURITY INVOKER。呼んだ人の RLS がそのまま効く
  - 本人は自分の行だけ、トレーナーは担当する顧客の行だけが見える
  - 他人の `client_id` を渡しても、見えないので (今日, false, 0) になる
- `REVOKE ALL ... FROM PUBLIC, anon` → `GRANT EXECUTE ... TO authenticated`
- 本人が `workout_plans` の `plan_type` を読めることを、テストで確かめる（読めないと、ワークアウトの完了がいつまでも数えられない）

### 5.3 テスト（`supabase/tests/record_streak_test.sql`）

既存のテストと同じ自己完結の形（`BEGIN ... ROLLBACK`、失敗は `RAISE EXCEPTION 'FAIL: ...'`、最後に `ALL RECORD STREAK TESTS PASSED`）。本人の JWT クレームを `SET LOCAL` してから呼ぶ。

- 記録なし → (今日, false, 0)
- §3 の数える記録それぞれで、今日なら `recorded_today` が true
- 数えない記録だけなら false・0
- 日付の境目: 今日 00:00:00 JST は今日、昨日 23:59:59 JST は昨日（UTC の日付で切ると誤る組み合わせを含める）
- 連続: 昨日・一昨日 → 2。3 日前が抜けていれば、4 日前以降は数えない。同じ日の複数件は 1 日
- 今日の記録と昨日までの連続が両方あるとき（true, 昨日までの日数）
- 今日より後の日付は数えない
- 他人の `client_id` → (今日, false, 0)。担当トレーナーとして呼ぶと本人と同じ値
- anon は EXECUTE できない。関数が SECURITY INVOKER・`search_path = ''`・STABLE であること

## 6. Mobile

### 6.1 型と関数（実装の約束）

新しい feature `lib/features/record_streak/`。

```dart
// models/record_streak_status.dart
@immutable
class RecordStreakStatus {
  const RecordStreakStatus({
    required this.asOfDate,            // 'YYYY-MM-DD'（DB の JST の今日）
    required this.recordedToday,
    required this.streakUntilYesterday,
  });
  factory RecordStreakStatus.fromRow(Map<String, dynamic> row);
}

// domain/record_streak_view.dart
sealed class RecordStreakView {}
final class RecordStreakRecordedToday extends RecordStreakView { final int days; }  // 今日記録済み
final class RecordStreakAlive extends RecordStreakView { final int days; }          // 今日まだ・昨日まで続いている（days >= 1）
final class RecordStreakNone extends RecordStreakView {}                            // 続いていない

/// countedTodayByTags: 今日（status.asOfDate と同じ日）に記録になるタグを送り、送ってから 60 秒以内か（§6.3）
RecordStreakView recordStreakViewOf(RecordStreakStatus status, {required bool countedTodayByTags});

// data/record_streak_repository.dart
class RecordStreakRepository {
  Future<RecordStreakStatus> fetch(String clientId); // rpc('get_record_streak', params: {'p_client_id': clientId}) の 1 行目
}

// providers/record_streak_provider.dart
@riverpod Future<RecordStreakStatus?> recordStreak(Ref ref);          // 自動破棄。未ログインは null
@Riverpod(keepAlive: true) class RecordStreakTagOverlay ...           // 送ったタグの先取り（§6.3）
//   void onMessageSent(List<String> tags, {required DateTime createdAt});   // createdAt = サーバーの送信時刻
//   bool countsToday({required String? clientId, required String asOfDate}); // 同じ人・同じ日・60 秒以内
//   static const window = Duration(seconds: 60);
@riverpod AsyncValue<RecordStreakView?> recordStreakView(Ref ref);    // 上の 2 つを合わせる
```

共通の部品 `lib/shared/utils/record_tags.dart` に、サーバーが記録にするタグの形を移す。

```dart
/// サーバー（parse-message-tags）が記録にするタグの形。'#体重' / '#食事' / '#食事:朝食' / '#運動' など
final RegExp serverRecordTagPattern = RegExp(r'^#(食事|運動|体重)(?::(.+))?$');

/// サーバーは tags[0] だけを記録にする
bool tagsCreateRecord(List<String> tags);
```

10.1 の `reminderKindsFromTags` もこれを使うように置き換える（動きは変えない。10.1 のテストがそのまま通ること）。

### 6.2 更新の時機

- ホームに戻ったとき・アプリを開いたとき: `recordStreakProvider` は自動破棄なので、ホームを作るたびに読み直す。記録タブ・メッセージ・プランでの記録は、ホームに戻れば反映される
- アプリが前面に戻ったとき: `app.dart` の resumed で `ref.invalidate(recordStreakProvider)`（ホームを開いたまま日付をまたいだときも、ここで直る）
- ホームで目覚めの評価を付けたとき: `upsertWakeupRating` の後で `ref.invalidate(recordStreakProvider)`
- ログアウト: `currentClientIdProvider` を見て null を返す。先取りは client id で区別する

### 6.3 送ったタグの先取り

メッセージから作られる記録は、DB の webhook の後で少し遅れて入る。送った直後にホームへ戻ると、まだ記録が無いことがある。

- 送信が成功したら `messages_provider` から `RecordStreakTagOverlay.onMessageSent` を呼ぶ（10.1 の `onMessageSent` の隣）。送ったタグと、サーバーが付けた送信時刻（`messages.created_at`）を渡す
- `tagsCreateRecord(tags)` が true なら、(今の client id, 送信時刻の JST の日付, 送った時刻) を覚える
  - 日付はサーバーの送信時刻で決める。記録の `recorded_at` もこの時刻なので、端末の時計が 0 時の前後でずれていても、記録と同じ日になる
- 表示は `status.recordedToday || (覚えた client id が今の人 && 覚えた日付 == status.asOfDate && 送ってから 60 秒以内)` を今日記録済みとして扱う
  - 先取りは、記録が少し遅れて作られる数秒を埋めるためだけのもの。60 秒を過ぎたら DB の値だけを見る
  - そのため、タグを送っても記録にならなかったとき（全角の数字、範囲外の値など）や、送ったあとにタグを消す編集をしたときも、次に読み直せば DB のとおりに戻る
  - 60 秒を過ぎても、画面は自分では読み直さない（ホームに戻ったとき・前面に戻ったときに読み直す）
- 訂正（2026-11-23 のレビュー）: 初版は端末の今日の日付で覚え、その日のあいだ先取りを効かせていた。記録にならなかったタグでも1日じゅう「今日も記録しました」と出て、本人が記録しないまま 0 時に連続が切れるおそれがあったため、上の形に変えた

### 6.4 画面

「今日のまとめ」（`DailySummaryCardBody`）の先頭に行を足す。

- アイコン `LucideIcons.flame`、見出し「記録の連続」。押せない行（移る先が無いので、矢印も出さない）
- 値と補足

| 状態 | 値 | 補足 |
|---|---|---|
| 今日記録済み（2 日以上） | `{日数} 日` | 今日も記録しました |
| 今日記録済み（1 日目） | `1 日` | 今日記録しました |
| 今日まだ・続いている | `{日数} 日` | 今日記録すると {日数+1} 日 |
| 続いていない | これから | 今日記録すると 1 日目 |
| 読み込み中 | スケルトン | （なし） |
| 読み込めない | 行を出さない | — |

- 0 とは出さない。「これから」は弱い文字色（ほかの行の「未記録」と同じ扱い）
- 読み上げは行全体で 1 つ: 「記録の連続、12日。今日記録すると13日」
- 文字の拡大（2.0 倍）・幅 320dp でも縮めずに折り返す。ダークモードは `AppColors.of(context)` で追従
- 読めないとき（オフライン・関数がまだ無いなど）は行ごと出さない。ほかの行は今までどおり
- `DailySummaryCardBody` の `streak` は省略できる（null なら行を出さない）。プレビューに 4 状態を足す

## 7. テスト

- SQL: §5.3
- Dart
  - `recordStreakViewOf`: 3 状態の分かれ目（今日あり・なし × 昨日まで 0・1・2 以上）と、先取りで「今日まだ」が「今日記録済み」になること。日付が違う先取りは効かないこと
  - `tagsCreateRecord`: `#体重` / `#体重 60`（空白入りは記録にならない）/ `#食事` / `#食事:間食` / `#運動` / 2 つめ以降のタグ / 空
  - `RecordStreakStatus.fromRow`: 日付・真偽・整数の読み取り
  - 先取り: client id が違うと効かない、ログアウトで効かなくなる、送ってから 60 秒を過ぎると効かない、日付はサーバーの送信時刻で決まる
  - 読み直しの動き: 読み直し中は前の値のまま / 読み直しに失敗したら行を出さない / client id が変わったら読み込み中（前の人の値を出さない）
  - 画面: 各状態の文言、読み上げ、行が押せないこと、`streak` が null なら出ないこと、幅 320dp・文字 2.0 倍ではみ出さないこと
  - 10.1 の既存テストがすべて通ること
- QA（iOS シミュレータ・Android エミュレータ、テスト用クライアント）: 本番に関数を入れてから（§8）
  - ホームの行の表示（今の記録の状態に合う値・補足）
  - メッセージで `#体重` を送ってホームに戻ると、すぐ今日記録済みになる（本番に記録を作るので、送る前にオーナーに確認する）
  - ホームで目覚めの評価を付けると、ホームを離れずに反映される
  - （記録タブで手入力 → 反映、削除 → 戻る、は実施できなかった。この版には体重・食事・運動を手で追加・削除する画面が無い）
  - ダークモード・文字拡大・全タブ

## 8. リリース

1. migration を本番に適用（`supabase db push`。2026-11-23 にオーナーの依頼で Claude が適用し、読み取りで確認した）。関数を足すだけで既存のものに触らない。今のアプリは呼ばない
   - シミュレータの確認は本番の関数を使うので、PR を出す前にこの migration だけ先に適用してもらう。そのため、関数は SQL のテストとレビューを済ませて、確定してから適用する（適用後に直すなら新しい migration を足す）
2. アプリの更新（TestFlight・ストア）。適用前の DB に新しいアプリがつながっても、行が出ないだけで落ちない

## 9. 前提として決めたこと（オーナーが覆せる）

1. 日付は `recorded_at`（記録の日時）で数える。昨日の食事を今日付けたときは、昨日の記録になる（記録のほかの画面と同じ。さかのぼって付けると、切れた連続が戻ることがある）
2. 睡眠は、ヘルスケアから入った行でも、本人が目覚めの評価を付けていれば数える
3. ワークアウトは、本人がセルフガイドのプランを完了した日に数える（完了した日時。予定日ではない）
4. 行は押せない。アイコンは炎（Lucide の `flame`）
5. 読めないときは行を出さない（エラーの文言は出さない）
6. 送ったタグの先取りは、送ってから 60 秒だけ効かせる（記録にならなかったタグや、タグを消す編集は、次に読み直せば DB のとおりに戻る）
7. 読み直しに失敗したら、前の値を残さず行を消す（前面に戻るのは翌朝が多く、残した値は「昨日の状態」になりうるため）

## 10. 範囲外・分かっている限界

- 範囲外: 最長記録、記録した日のカレンダー、フリーズ（週 1 回までの猶予）、トレーナーの Web の列、リマインダーへの組み込み（「今日記録すると 13 日」を通知に出すなど）、マイルストーンバッジ（2-B）
- 先取りの 60 秒は端末の時計で数える。送った直後に端末の時計を動かすと、先取りが早く効かなくなるだけ（長く残ることは無い。DB の値は変わらない）
- ホームを開いたまま 0 時をまたぐと、前面に戻るかタブを移るまで前日のまま
- 記録の件数が非常に多い人でも、1 回の呼び出しで全期間を見る（索引で足りる見込み。遅ければ拡張で `client_streaks` のキャッシュを作る）
- トレーナーとして呼ぶと、ワークアウトは自分が割り当てた分・自分のプランしか見えない（RLS）。前のトレーナーが割り当てた完了は数えられない。今回はホームだけなので影響しないが、Web に出す拡張ではこの差を決める必要がある
