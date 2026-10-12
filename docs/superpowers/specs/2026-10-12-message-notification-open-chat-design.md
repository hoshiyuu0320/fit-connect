# メッセージ通知のクリックで、その顧客の会話を開く — 設計

- 日付: 2026-10-12
- ブランチ: `feature/message-notification-open-chat`（`develop/1.0.0` から）
- 範囲: Supabase（`parse-message-tags` と `_shared` の純関数・テスト）と Web（メッセージ画面・`notificationClicked.ts`・テスト）、docs。`fit-connect/public/sw.js` と Mobile は変更なし。DB の変更なし
- 前提の設計: `docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md`（以下「10-04 の設計書」）§14 の「メッセージ通知のクリックで、その顧客の会話を開くこと」。§7.1（sw.js の URL の正規化）と §13-5（同じパス名のタブは前面に出すだけで移動しない）はそのまま
- オーナー決定（2026-10-12）
  1. 書きかけがあるときは会話を切り替えず、案内を出す（§5）
  2. メッセージ通知の tag は会話ごとに分けない（10-04 の設計書 §13-9 のまま。§8）

## 1. 背景
- 2026-10-12 の本番確認で、顧客からトレーナーへのメッセージ通知をクリックすると、`/message` が会話を選ばないまま開くことが分かった。`parse-message-tags` が `data: { type: 'message', messageId }` だけを送り URL を含まないので、sw.js がクリック先を既定の `/message` にする
- メッセージ画面は `?clientId=<uuid>` のクエリで、その顧客を選んだ状態で開ける

## 2. 成功の条件
1. 顧客→トレーナーのメッセージ通知をクリックしたとき、メッセージ画面のタブが無ければ `/message?clientId=<その顧客>` が新しいタブで開き、その顧客の会話が選ばれている
2. メッセージ画面のタブがあれば、そのタブが前面に出て（移動はしない）、書きかけが無ければその顧客の会話に切り替わる
3. 書きかけがあれば会話は切り替わらず、書きかけも消えない。案内と「〇〇さんの会話を開く」ボタンが出る
4. トレーナー→顧客のメッセージ通知（Mobile 向け）と目標達成の通知の `data` は変わらない
5. 本番の Web（main の古い sw.js）では、今と同じく `/message` が開く（退行しない）

## 3. Edge Function（`parse-message-tags`）
- 送信者が顧客（`sender_type = 'client'`）で宛先がトレーナー（`receiver_type = 'trainer'`）のときだけ、`data` に `url: '/message?clientId=<sender_id>'` を足す。`sender_id` は顧客の `clients.client_id`（顧客の auth uid）で、`encodeURIComponent` を通す。それ以外は今と同じ `{ type: 'message', messageId }`
- `data` の値はすべて文字列（FCM の data は文字列だけ。Web Push では JSON の `data` に入る）
- 組み立ては import の無い純関数 `buildMessageNotificationData`（`supabase/functions/_shared/message_notification.ts`）に切り出し、Deno でテストする（`parse-message-tags/index.ts` は import すると `Deno.serve` が走るので、テストから読めない）
- dedup キー・タイトル・本文・tag（`data.type` の `message`）は変えない

## 4. sw.js（変更なし）
- 今の `normalizeTargetUrl` はクエリを残す（`/message?clientId=…`）
- クリック時に、パス名が `/message` のタブ（クエリは問わない）があれば前面に出し、`{ type: 'notification-clicked', url: '/message?clientId=…' }` を送る。無ければ `openWindow('/message?clientId=…')`
- `fit-connect/src/lib/notifications/sw.test.ts` にこの形のケースを足して固定する。`SW_VERSION` は据え置き

## 5. メッセージ画面（`fit-connect/src/app/(user_console)/message/page.tsx`）
- `subscribeNotificationClicked` のコールバックに `url`（文字列でなければ `null`）を渡す。既存の呼び出し（`layout.tsx`・`TriageSection.tsx`）は引数を使わないので変わらない
- 受け取った `url` から顧客を読む。パス名が `/message` で `clientId` が UUID の形のときだけ（小文字にそろえる）。自分のオリジンの相対パスとしてだけ読み、絶対 URL は受けない。それ以外（`/message` だけの古い通知など）は何もしない
- 動き

| 状態 | 動き |
|---|---|
| url に顧客が無い／その顧客を表示中 | 何もしない（新着は Realtime で出ている） |
| 顧客一覧（サイドバー）に無い | 何もしない（`console.warn`） |
| 書きかけ無し | その顧客を選ぶ（サイドバーのクリックと同じ。URL の `?clientId=` は変えない。サイドバーも変えないため） |
| 書きかけあり | 切り替えない。案内を出す |

- 書きかけ: 入力欄の文字（空白だけは除く）・添付画像・返信先・記録の引用（チップ）・メッセージの編集中・送信中のどれか
  - 理由: サイドバーの切り替えは、入力欄の文字・画像・返信先を次の顧客へ持ち越し、引用は捨てる（既存の挙動）。通知のクリックは「その顧客の会話を見たい」操作なので、持ち越した書きかけを別の顧客へ送ってしまいやすい
  - 引用の取得中（URL に `record` があって、チップがまだ出ていない）は含めない。取得に失敗すると `record` が URL に残り、ずっと書きかけの扱いになるため
- 案内（`fit-connect/src/components/message/NotificationHoldNotice.tsx`）: チャット欄のヘッダーの下に1本のバーで出す
  - 文言 `〇〇さんから新しいメッセージがあります。書きかけがあるため、会話は切り替えていません。`、ボタン `〇〇さんの会話を開く`（サイドバーのクリックと同じ。書きかけの扱いもサイドバーと同じ）、閉じる（`aria-label="案内を閉じる"`）
  - エラーではないので `role="status"`・中立色（文字は `#0F766E`。白地の teal `#14B8A6` は文字にはコントラストが足りない）。読み上げのため、`role="status"` の外枠は常に置き、中身だけを出し入れする
  - チャット欄が細いとき（左の顧客一覧と右の記録パネルが開いていると、ウィンドウ幅 1024px で 272px）は、ボタンの組が次の行に回る（文言を押しつぶさない。`flex-wrap` と文言の基準の幅 12rem）
  - 顧客を切り替える（どの方法でも）か、閉じると消える。保留中に別の顧客の通知がクリックされたら、その顧客の案内に置き換える
- 判定は依存の無い純関数（`fit-connect/src/lib/message/notificationOpen.ts`: `clientIdFromNotificationUrl`・`hasMessageDraft`・`decideNotificationOpen`）に出して vitest でテストする

## 6. リリース（オーナー作業。Claude はリモートに書き込まない）
1. PR を `develop/1.0.0` へマージ
2. `supabase functions deploy parse-message-tags`。デプロイの後に `supabase functions list` で更新時刻を確かめる
   - 本番の `parse-message-tags` は v27（2026-10-04 のデプロイ。PR1 の `push.ts`）。develop からデプロイすると、PR2 の `push.ts`（`timeout` 10 秒・keep-alive しない agent・種別 `client_alert`・`ttlSeconds`）も一緒に載る（10-04 の設計書 §11.2 手順3 の「次に再デプロイしたとき」にあたる）
3. Web は develop の Preview で確かめる（本番の Web は main のまま。main へのリリースはオーナー判断）
   - Edge Function だけ先に出ても安全: 本番 main の古い sw.js は `payload.url` しか読まないので、クリック先は今と同じ `/message`。develop の sw.js（PR2）は、メッセージ画面のタブが無ければ、この Web の変更の前の画面でも `?clientId=` で顧客を選んで開く。タブがあるときの選び直しは、この Web の変更が入ってから効く
4. 確認: テスト用の顧客アプリから、ブラウザ通知を登録したトレーナーへ本文のあるメッセージを送り、通知のクリックでその顧客の会話が開くこと（メッセージ画面のタブ無し・タブあり・書きかけあり）。`notification_logs`（`dedup_key = 'message:<messageId>'`）が `sent`

## 7. ロールバック
- DB の変更は無いので、PR を revert してよい。Edge だけ戻すときは、戻した版で `parse-message-tags` を再デプロイする（`url` が無くなるだけで、Web はそのまま動く）

## 8. 範囲外
- 会話ごとの tag（オーナー決定。10-04 の設計書 §14 に残す）
- Realtime の取りこぼしの取り直し（通知のクリックで、表示中の会話を取り直すこと）
- サイドバーの切り替えで書きかけを持ち越す既存の挙動の見直し（顧客ごとの下書き）
- ページを開いた後に担当になった顧客（顧客一覧に無い顧客）の通知で、会話を開くこと
