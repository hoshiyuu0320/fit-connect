# ローカル記録リマインダー（フェーズ10.1）— 設計

- 日付: 2026-11-07
- ブランチ: `feature/local-record-reminder`（`develop/1.0.0` から）
- 範囲: Mobile（`fit-connect-mobile/`）だけ。新しい feature `lib/features/record_reminders/`、`NotificationService`、設定画面、メイン画面のタブ切り替え、記録の送信・ワークアウト完了・ヘルスケア同期・ログアウトへのフック、Android の manifest、iOS の AppDelegate、テスト。DB・Edge Functions・Web は変更なし
- 前提: カタログ cat2 1-A（`docs/tasks/2026-07-08-solution-catalog.md`）、`IMPLEMENTATION_TASKS.md` 10.1「汎用記録リマインダー（時刻・記録種類選択式）」。夕食だけの提案は 2026-08-10 にオーナー判断で削除済み（夕食だけを特別扱いする根拠が薄い）
- オーナー決定（2026-11-07）
  1. 項目は5つで固定: 体重・朝食・昼食・夕食・運動（プランがある日だけ）。それぞれにオン・オフと時刻
  2. 通知を押すと記録する場所を開く: 体重・食事はメッセージ画面をタグ入りで、運動はプラン画面

## 1. 背景（2026-11-07 の調査）

- 端末に通知を予約する仕組みが無い。`timezone` パッケージは pubspec にあるが未使用。Android の manifest に予約通知の receiver と `RECEIVE_BOOT_COMPLETED` が無い
- 通知を押しても画面は移らない（`NotificationService.onNotificationTap` は print だけ。router も navigatorKey も無く、タブは `_MainScreenState` の private な状態）。iOS は AppDelegate が `UNUserNotificationCenter` の delegate を設定しておらず、firebase_messaging が delegate になるため、ローカル通知のタップが flutter_local_notifications（FLN）に届かない
- 体重・食事・運動の記録はアプリが作らない。チャットのタグ（`#体重` / `#食事:朝食` など）を Edge Function `parse-message-tags` が非同期に読んで作る。アプリが受け取れるのは「メッセージを送れた」ことだけ
- ヘルスケアの体重はアプリを開いている間にだけ取り込まれる（バックグラウンド同期は無い）
- 通知の許可は新規登録時のオンボーディングでしか聞いていない。既存の利用者には一度も聞いていない人がいる
- 「今日」の数え方が混在している（睡眠・セッションは JST 固定、体重・食事・運動の一部は端末の時刻で、時差のない文字列を送る 9 時間ずれの既知の不具合あり）

## 2. 成功の条件

1. 設定画面から5項目それぞれのオン・オフと時刻を決められ、オンの項目が毎日その時刻（日本時間）に端末の通知として届く
2. その日すでに記録した項目は、その日の分が鳴らない。アプリから記録を送った直後と、アプリを開いたときに反映する
3. 運動は、その日に未完了のプラン（セルフガイド）がある日だけ鳴る
4. 通知を押すと、体重・食事はメッセージ画面がタグ入り（例 `#体重 `）で開き、運動はプラン画面が開く。アプリが終了していても同じ
5. 通知が許可されていない端末では、オンにするときに許可を求める。断られていれば、OS の設定を開く案内を出す
6. ログアウトすると予約と表示中のリマインダーが消える。別のアカウントでログインしても、前の人の設定で鳴らない
7. 既存の通知（FCM のメッセージ・セッションのリマインド・目標達成、ヘルスケア同期エラー）の届き方と押したときの動きを変えない

## 3. 設定

- 項目（`ReminderKind`。並びは固定）

| kind | 表示 | 既定の時刻 | 押したときのタグ | 「記録済み」の条件（その日の JST） |
|---|---|---|---|---|
| `weight` | 体重 | 07:30 | `#体重 ` | `weight_records` が1行以上（source を問わない） |
| `breakfast` | 朝食 | 09:00 | `#食事:朝食 ` | `meal_records.meal_type = 'breakfast'` が1行以上 |
| `lunch` | 昼食 | 13:00 | `#食事:昼食 ` | `meal_type = 'lunch'` |
| `dinner` | 夕食 | 20:00 | `#食事:夕食 ` | `meal_type = 'dinner'` |
| `workout` | 運動（キャプション「プランがある日だけ」） | 18:00 | なし（プラン画面） | その日に `status = 'pending'` のセルフガイドの割り当てが無い |

- 既定はすべてオフ（通知疲れを避ける）。時刻は5分刻み
- 保存先は SharedPreferences。キーはアカウントごと `record_reminder_settings:<auth のユーザー ID>`、値は JSON（`{"version":1,"items":{"weight":{"enabled":true,"time":"07:30"}, ...}}`）。読めない値・欠けた項目は既定に戻す。サーバーには保存しない（別の端末では設定し直し。トレーナーからは見えない）

## 4. 予約

- 時間帯は `Asia/Tokyo` に固定する（`tz.initializeTimeZones()` → `tz.setLocalLocation(tz.getLocation('Asia/Tokyo'))`）。サーバー・トレーナー側の「日」が JST で、新しいネイティブのプラグイン（端末の時間帯の取得）を足さずに済むため
- 今日から7日分（今日 + 6日）を、項目ごと・日ごとの**1回きりの通知**として予約する（毎日繰り返す通知だと「今日の分だけ止める」ができない。iOS は予約が64件までなので、5項目 × 7日 = 最大35件）
  - 予約の時刻が今より後のものだけ
  - 今日（dayOffset 0）は「記録済み」の項目を予約しない
  - 運動は、未完了のセルフガイドの割り当てがある日だけ予約する（今日から6日後まで、予約し直す時点で分かっている分）
- 通知の ID は `7000 + (JST の日付の通し日数 % 10) * 10 + kind.index`。範囲 7000〜7099 をリマインダー専用にする（ヘルスケア同期エラーは 9001、FCM のフォアグラウンド表示は `hashCode`）。ID を日付で決めるので、日をまたいで予約し直しても同じ日の通知は同じ ID と payload のまま残り、毎日増えるのは新しい1日分だけ（今日からの日数で決めると、毎朝すべての ID がずれて最大35件を取り消し・予約し直すことになる）。7日の窓の中では重ならない
- 差分の適用は、取り消しをすべて済ませてから予約する（時刻を変えた通知は同じ ID が両方に入るため）
- payload は `record_reminder:<kind.key>@<予約時刻の JST yyyyMMddHHmm>`（例 `record_reminder:dinner@202611072000`）。既存の `NotificationService` は payload を `:` で分けて type と id にするので、type = `record_reminder`・id = `dinner@202611072000` になる
- 予約し直し（`RecordReminderSync.refresh`）は「あるべき予約」と「今の予約」の差分だけを取り消し・予約する。ID と payload が同じものはそのまま
- Android: チャンネル `record_reminder`（名前「記録のリマインダー」、説明「記録を忘れないためのお知らせ」、`Importance.defaultImportance`）。`AndroidScheduleMode.inexactAllowWhileIdle`（正確な時刻のアラームの権限は使わない）。厳密でないアラームには OS が配信の幅を付け、幅は予約時点から発火までの時間の 75%・上限1時間（2026-11-08 の Android 17 エミュレータの実測: 数分先の予約は +3〜7分、翌日以降の予約は +1時間）。そのため Android では、設定した時刻から最大1時間遅れて届くことがある。正確にするには「アラームとリマインダー」の特別な許可（`SCHEDULE_EXACT_ALARM`。Android 14 以降は既定で拒否で、利用者に設定画面で許可してもらう必要がある）が要るので、今回は使わない。manifest に `RECEIVE_BOOT_COMPLETED` と FLN の `ScheduledNotificationReceiver` / `ScheduledNotificationBootReceiver` を足す（端末の再起動後も予約が残る）
- iOS: `DarwinNotificationDetails()` の既定（フォアグラウンドでもバナーを出す）

### 4.1 予約し直す時機

| 時機 | 中身 |
|---|---|
| ログインしてクライアントが分かったとき（起動時を含む） | 全体を予約し直す。Android は差分を取らず、あるべき予約をすべて予約し直す（FLN の予約一覧は OS ではなく FLN 自身の保存を読むので、強制停止やバックアップからの復元で OS 側のアラームが消えても「予約済み」に見える。同じ ID で予約し直すとアラームと保存の両方が置き換わる） |
| アプリが前面に戻ったとき | 全体を予約し直す |
| 設定を変えたとき | 全体を予約し直す |
| メッセージを送れたとき | 送ったタグから「今日記録した項目」を推定し、今日の分を止めて予約し直す（下記） |
| ワークアウトの完了を送れたとき | 全体を予約し直す（割り当ての status はアプリが直接更新するので、すぐ読める） |
| ヘルスケア同期で体重の行が変わったとき | 全体を予約し直す |
| ログアウト・アカウント削除・自動のサインアウト（トークンの失効など） | リマインダーの予約と表示中の通知をすべて消し、取っておいたタップと「開く先」の要求も捨てる。ログアウトはサインアウトしてから消す（消している間に走り出した予約し直しが、古い利用者のまま予約しないように） |

- メッセージの記録はサーバーで非同期に作られるので、送った直後に DB を読んでもまだ無い。そのため、送ったタグから今日記録した項目を推定し、その日のうちはメモリ上で「記録済み」として扱う（DB の結果との和）。サーバー（`parse-message-tags`）は `tags[0]` だけを記録にするので、推定も最初のタグだけを見る。対応: `#体重` → weight、`#食事:<詳細>` は詳細を「朝」→「昼」→「夕」か「晩」の順に調べて breakfast / lunch / dinner（サーバーの判定と同じ順。実装時に `supabase/functions/parse-message-tags/index.ts` の判定と、アプリの `message_tag_parser.dart` が送るタグの形を確かめる）。`#食事:間食`・詳細なしの `#食事`・`#運動` は対象外
  - 数値が読めないなどでサーバーが記録を作れなかった場合も、その日の分は止まったまま（送った時点で記録しようとしているので、もう一度促さない）
- DB を読めなかったとき（オフラインなど）は、同じ日に読めた最後の結果を使う。無ければ「記録済み」なし・運動の予定日なしとして予約する（運動の分は次に読めたときに戻る）
- 予約し直しは同時に走らせない（直列にし、走っている間に来た要求は1回にまとめる）

### 4.2 「今日」と DB の読み方

- 今日 = JST の日付。範囲は `[今日 00:00 JST, 翌日 00:00 JST)` を UTC に直し、時差付きの ISO 文字列（`toUtc().toIso8601String()`）で `recorded_at` と比べる（時差のない文字列は UTC として読まれる。lessons 参照）
- 割り当ては `workout_assignments.assigned_date`（date）を JST の日付文字列 `YYYY-MM-DD` と比べ、セルフガイドだけ（`workout_plans.plan_type = 'self_guided'`。今の `getAssignmentsByDate` と同じ絞り方）、`status = 'pending'` だけを見る
- 読むのはクライアント本人の行だけ（既存の RLS の範囲）。新しい RPC・migration は作らない

## 5. 通知の文面

| kind | タイトル | 本文 |
|---|---|---|
| weight | 体重の記録 | 今日の体重を記録しましょう |
| breakfast | 朝食の記録 | 朝食を記録しましょう |
| lunch | 昼食の記録 | 昼食を記録しましょう |
| dinner | 夕食の記録 | 夕食を記録しましょう |
| workout | 今日のワークアウト | 今日のプランのワークアウトがあります |

絵文字は使わない。「まだ記録されていません」とは書かない（別の端末で記録した直後などに外れるため）。

## 6. 通知を押したとき

- `record_reminder` の通知だけを扱う。体重・朝食・昼食・夕食 → メインのタブを「メッセージ」にし、入力欄に §3 のタグを入れる（既存の `_navigateToMessagesWithDraft` と同じ動き。送信はしない）。運動 → タブを「プラン」にする
- 仕組み: keepAlive の Riverpod プロバイダー `notificationNavigationProvider` に「開く先」の要求を置き、`MainScreen` が監視して実行し、消す。`MainScreen` がまだ無い（起動中・認証待ち）ときは要求が残り、`MainScreen` が現れたときに実行する
- 切り替える前に、メイン画面の上に重なった画面（設定のサブ画面・記録の詳細・ボトムシートなど）を閉じる（2026-11-07 の QA で、上の画面が残って切り替わった先が見えないと分かったため）。閉じられない画面（`PopScope(canPop: false)`: 同意のダイアログ・強制アップデートのダイアログ・送信中のワークアウト完了シート）はそのまま残し、その下の画面も残す。同意のダイアログは route の名前でも見分ける（PopScope が変わっても閉じないように）
- `NotificationService` の変更
  - タップの受け口（`onNotificationTap`）がまだ設定されていない間に来たタップは、最後の1件を取っておき、受け口が設定されたときに渡す
  - アプリがローカル通知のタップで起動したとき（`getNotificationAppLaunchDetails()`）も同じ経路で渡す
  - 受け口は `app.dart` のサインイン後（`_AuthLoadingScreen`）で設定する。`record_reminder` 以外の type はこれまでどおり何もしない（print だけ）
- iOS: AppDelegate で `UNUserNotificationCenter.current().delegate` に AppDelegate を設定する（FLN の README の手順）。FlutterAppDelegate が FLN と firebase_messaging の両方に通知の callback を回すので、FCM の表示とタップは変わらない想定。FCM の経路はシミュレータで実際の push を受けられないので、ローカル通知の表示・タップと、`xcrun simctl push` で入れた通知の表示で確かめる

## 7. 通知の許可

- 項目をオンにするとき、許可が「未決定」なら `NotificationService.requestPermissionAndRegister()`（オンボーディングと同じ。push のトークンも登録される）で許可を求める
- 「拒否」なら、オンのまま保存し、リマインダーの画面に「通知がオフになっています。設定アプリでこのアプリの通知を許可してください」と「設定を開く」（`AppSettings.openAppSettings(type: AppSettingsType.notification)`）を出す。画面を開いたとき・前面に戻ったときに状態を読み直す
- 許可の状態は `FirebaseMessaging.instance.getNotificationSettings()` で読む（オンボーディングと同じ）。Firebase が初期化されていないときは「不明」として求めない

## 8. 画面

- 設定画面の「通知」グループに行「記録のリマインダー」を足す（既存の3つのトグルの下）。値は、オフなら「オフ」、オンの項目があれば表示名を「・」でつなぐ（例「体重・夕食」）。シェブロンでサブ画面へ
- サブ画面「記録のリマインダー」（`HealthSettingsScreen` と同じ形: `FcButton.back('戻る')` + `FcPageHeading`）
  - 冒頭の説明: 「決まった時刻に、この端末へ記録のお知らせを出します。その日すでに記録していれば出しません。」
  - 許可がないときの案内（§7）
  - 5項目の行。行ごとに表示名・時刻・トグル。運動にはキャプション「プランがある日だけ」。時刻を押すと下から時刻の選択（`CupertinoDatePicker`、時刻、24時間表記、5分刻み、「キャンセル」「決定」。MaterialApp にローカライズの設定が無いので Material の時刻の選択は英語になるため使わない）
  - 末尾の注記: 「時刻は日本時間です。アプリを7日以上開かないと、お知らせは止まります。開くと再開します。」
- デザインは FIT-CONNECT Design System（`AppColors.of(context)`・`AppTextStyles`・`AppSpacing`・`shared/widgets/fc/`、Lucide、絵文字なし）。プレビュー関数を付ける

## 9. 共有する型と関数（実装の約束）

`lib/features/record_reminders/` に置く。名前と引数はこのとおりにする（並行して実装するため）。

```dart
// models/reminder_kind.dart
enum ReminderKind {
  weight, breakfast, lunch, dinner, workout;
  String get key;            // 'weight' など（保存・payload に使う）
  String get label;          // '体重' など
  int get defaultHour; int get defaultMinute;
  String? get messageDraft;  // '#体重 ' など。workout は null
  String get notificationTitle; String get notificationBody;
  static ReminderKind? fromKey(String key);
}

// models/record_reminder_settings.dart
class ReminderTime { final int hour; final int minute; /* '07:30' との相互変換 */ }
class ReminderSetting { final bool enabled; final ReminderTime time; }
class RecordReminderSettings {
  final Map<ReminderKind, ReminderSetting> items; // 5項目すべてを持つ
  factory RecordReminderSettings.defaults();
  factory RecordReminderSettings.fromJson(Object? json); // 壊れた値は既定へ
  Map<String, Object?> toJson();
  RecordReminderSettings withSetting(ReminderKind kind, ReminderSetting setting);
  bool get anyEnabled;
}

// domain/reminder_planner.dart（純関数。Flutter・Supabase・FLN に依存しない。timezone は可）
class PlannedReminder { final int id; final ReminderKind kind; final tz.TZDateTime fireAt; final String title; final String body; final String payload; }
class PendingReminder { final int id; final String? payload; }
class ReminderDiff { final List<int> cancelIds; final List<PlannedReminder> toSchedule; }
const int reminderIdBase = 7000; // 7000〜7099 を使う
int reminderNotificationId(tz.TZDateTime dateJst, ReminderKind kind); // 7000 + (JST の通し日数 % 10) * 10 + kind.index
bool isReminderNotificationId(int id);
String reminderPayload(ReminderKind kind, tz.TZDateTime fireAt);
ReminderKind? reminderKindFromPayload(String payload); // 'record_reminder:dinner@...' → dinner
ReminderKind? reminderKindFromTapId(String? id);       // 'dinner@...' → dinner（NotificationService が分けた後の id）
List<PlannedReminder> planReminders({
  required RecordReminderSettings settings,
  required tz.TZDateTime now,                 // Asia/Tokyo
  required Set<ReminderKind> recordedToday,   // weight / breakfast / lunch / dinner のうち今日記録済み
  required Set<String> pendingWorkoutDates,   // 'YYYY-MM-DD'（JST）
  int days = 7,
});
ReminderDiff diffReminders(List<PlannedReminder> planned, List<PendingReminder> pending); // pending はリマインダー ID のものだけ渡される前提でも、範囲外は無視する
Set<ReminderKind> reminderKindsFromTags(List<String> tags); // §4.1 の対応。最初のタグだけを見る（0件か1件の集合を返す）
({DateTime startUtc, DateTime endUtc}) jstDayRangeUtc(tz.TZDateTime nowJst);
String jstDateKeyOf(tz.TZDateTime dateJst); // 'YYYY-MM-DD'

// services/reminder_notification_scheduler.dart（FLN の薄い包み。テストでは差し替える）
abstract class ReminderNotificationScheduler {
  Future<List<PendingReminder>> pendingReminders(); // リマインダー ID のものだけ
  Future<void> schedule(PlannedReminder reminder);
  Future<void> cancel(int id);
  Future<void> cancelAllReminders();               // 予約と表示中の、リマインダー ID のものすべて
}

// lib/features/home/providers/notification_navigation_provider.dart（keepAlive）
sealed class NotificationNavigationRequest {}
class OpenMessagesWithDraft extends NotificationNavigationRequest { final String draft; }
class OpenPlanTab extends NotificationNavigationRequest {}
// notificationNavigationProvider: state は NotificationNavigationRequest?。request(...) で置き、consume() で取り出して null に戻す
```

## 10. テスト

- 単体（純関数）: `planReminders`（オフの項目・時刻を過ぎた今日の分・今日記録済み・運動の予定日・7日の窓・日付の変わり目（23:59 / 00:00 JST）・ID と payload・並び）、`diffReminders`（同じものは残す・時刻変更・範囲外 ID の無視）、`reminderKindsFromTags`（サーバーの判定と同じ境界: `#食事:朝食` / `#食事:夕ご飯` / `#食事:晩` / `#食事:間食` / `#食事` / `#体重` / `#運動:完了`）、`jstDayRangeUtc`、payload の往復、設定の JSON（壊れた値・欠けた項目・version 違い）
- 保存: SharedPreferences のモックでアカウントごとに分かれること
- 予約し直し: 予約の部分を差し替えて、時機ごとの結果（記録済みの推定・DB を読めないとき・ログアウトで全消し・直列化）
- 画面: 設定画面の行の値（オフ / 「体重・夕食」）、サブ画面のトグル・時刻の選択・許可の案内。既存の `settings_screen_test.dart` は、グループの並び・トグルの数（メイン画面は3のまま）・シェブロンの数を新しい行に合わせて直す
- `MainScreen`: 要求でタブが変わり、入力欄にタグが入ること
- 実機相当: iOS シミュレータと Android エミュレータで、数分後の時刻にした通知が届くこと・押すとタグ入りのメッセージ画面 / プラン画面が開くこと（起動中・終了後の両方）・チャットで記録を送るとその日の分が鳴らないこと・ログアウトで消えること・既存の通知の表示が変わらないこと

## 11. リリース

- Mobile のアプリの更新だけ（TestFlight / ストア）。DB・Edge Functions・Web の作業は無い
- ロールバック: 前のビルドに戻す。予約済みの通知は端末に残るので、戻したビルドで消えるのは次の再インストールかアプリのデータ削除のとき（前のビルドはリマインダーの ID を知らない）。問題が出たときは、修正版で `cancelAllReminders` を呼んで消す

## 12. 前提として決めたこと（オーナーが覆せる）

1. 時刻は日本時間（端末の時間帯に従わない）
2. 7日先まで予約し、アプリを開くたびに予約し直す。7日以上開かないと止まる
3. 設定は端末に保存（アカウントごと）。サーバーには保存しない
4. 既定はすべてオフ。既定の時刻は 体重 07:30・朝食 09:00・昼食 13:00・夕食 20:00・運動 18:00。5分刻み
5. 食事は、その食事の種類が記録されていれば鳴らさない。間食や種類のない `#食事` は数えない
6. 運動は、その日に未完了のセルフガイドのプランがある日だけ鳴らす。`#運動` の記録では止まらない
7. アプリから記録を送ったら、サーバーで記録ができる前でも、その日の分を止める（サーバーが記録を作れなかった場合も止まったまま）
8. 通知の文面は §5
9. 既存の通知（メッセージなど）を押したときの動きは変えない
10. オンボーディングには入れない（設定画面からだけ）
11. Android は正確な時刻のアラームの許可を求めない（最大1時間遅れて届くことがある。§4）

## 13. 範囲外・分かっている限界

- アプリの外で増えた記録（ヘルスケアの体重・別の端末からの送信）は、次にアプリを開くまで分からない。朝に体重計に乗っただけでは体重のリマインダーは鳴る（押してアプリを開けば取り込まれる）
- サーバーから「記録していない人だけ」に送る push（カタログ 1-B）と、設定をサーバーに置いてトレーナーから見えるようにすること（`client_reminder_settings`）は別の変更
- 食事の AI 推定の種類の既定は時刻で決まり、20 時以降は「間食」になる（既存の動き）。夕食のつもりで間食として記録すると、その日の夕食のリマインダーは止まらない。既定の時間帯の見直しは別の変更の候補
- Android は設定した時刻から最大1時間遅れて届くことがある（厳密でないアラームの配信の幅。§4）。端末の時間帯が日本以外だと、日本時間の時刻に鳴る
- 既存の通知（メッセージ・セッションのリマインド）を押したときの画面の移動は、今回の仕組みで足せるが別の変更
- 通知を押したとき、閉じられない画面（同意・強制アップデートなど）が開いていれば、その下でタブだけが切り替わる。閉じた画面に入力途中の内容があれば失われる
