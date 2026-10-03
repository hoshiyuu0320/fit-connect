# 睡眠悪化アラート（フェーズ9.1 拡張 ③ `sleep_decline`）— 設計

- 日付: 2026-10-03
- ブランチ: `feature/sleep-decline-alert`（`develop/1.0.0` から）
- 範囲: Supabase（migration 1本 + SQL テスト）と Web（表示・導線）。Mobile は変更なし
- 前提の設計: `docs/tasks/2026-09-13-trainer-intervention-plan.md`（9.1 / 9.2 の確定版）、
  `fit-connect/docs/superpowers/specs/2026-09-23-record-coaching-flow-design.md`（9.3 の引用導線）

## 1. 目的と成功の条件

**オーナーの依頼**: 次のタスク候補のうち「9.1 の拡張（睡眠悪化の自動検知。9.3 の `sleep:7d` リンクにつなげる）」を進める。

**目的**: 顧客の睡眠がはっきり悪くなったときに、トレーナーがダッシュボードを開いた時点で気づけるようにする。
気づいたら、その場から直近7日の睡眠を引用したメッセージを書き始められるようにする。

**成功の条件**
1. 毎朝 06:00 JST の既存の自動チェック（cron `detect-client-alerts`）で、睡眠悪化が検知される
2. 検知された顧客が「今日の対応」に「睡眠の悪化」の理由付きで並ぶ
3. 直近7日の睡眠の引用チップが入った状態でメッセージ画面を開ける。睡眠悪化が先頭の理由で未返信が無い行は「メッセージ」から、それ以外の行は詳細のリンクから
4. 「記録を見る」で顧客詳細の睡眠タブが開く
5. 誤検知を抑える。1晩の欠測や計測ミスでは検知しない

**この設計で置いた前提**（オーナーへの確認なしで決めたもの。§11 に一覧）
- 判定はカタログの初期案（`docs/tasks/2026-07-08-solution-catalog.md` 1-A ③）を土台にし、誤検知対策を足す
  - カタログの「平均」は、1晩の外れ値に強い「中央値」に置き換える（§4.2）
- 重大度は常に「注意」（medium）。体重の急変（要確認）より下に並ぶ
- 睡眠時間の絶対値（平均6時間未満など）による検知は入れない

## 2. 本番の実測（2026-10-03、読み取り専用の集計値だけ）

- 睡眠の記録は122行・3名。すべて HealthKit 由来で、手動の行は0件
- 目覚め評価が入っている行は2行だけ。判定の中心は睡眠時間になる
- 1晩の睡眠時間は最小273分・中央値約383分・最大571分。2時間未満と14時間超は0件
- カタログの条件（前の週より1時間以上短い、各週3晩以上）を過去45日の全顧客に当てると、評価できた94日のうち該当は1日
- 監視対象（ログインできる・自己登録でない）の顧客に絞り、登録日以降の記録と 06:00 時点の到着だけで見ると、評価できた日は60日で2日、該当は0日
  - 監視対象の顧客の睡眠77行のうち、登録日以降は20行。初回連携で登録前の30日分が入るため
- 自動チェックは12回実行され失敗0件。直近の監視対象は1名、open のアラートは record_gap 1件
- 全 migration（`20260923000000` まで）がリモートに適用済み

**結論**: 本番のデータは実質テストデータで、閾値の妥当性は確かめられない。当面の検知件数はほぼ0件の見込み。
判定の正しさは合成データの SQL テストで固定する。

## 3. 採用案

**採用: 既存の検知関数に3つ目のルールとして足す**
- `evaluate_client_alerts` に睡眠の CTE を足して3本目の `UNION ALL` にする
- `run_client_alert_detection` に睡眠用の期限切れと集計キーを足す
- 監視対象の判定・状態遷移・冪等性・対応済みの操作・「今日の対応」の表示をそのまま使える

**見送った案**
- 睡眠専用の評価関数を別に作り、`evaluate_client_alerts` から呼ぶ案。監視対象の判定（snapshot）を2回計算することになり、結局 `evaluate_client_alerts` の再定義も要るので利点が無い
- Web のダッシュボードで都度計算する案（カタログ 1-C）。対応済み・期限切れ・バッジが使えず、9.1 の方針と食い違う

## 4. 検知ルールの仕様

### 4.1 使うデータ

対象日 D、締め時刻 as_of、登録日 J は 9.1 の共通定義のまま使う（計画書「検知ルールの仕様 > 共通」）。

- `sleep_records` のうち、次をすべて満たす行
  - `recorded_date`（JST の起床日）が `GREATEST(D − 14, J)` 以上、`D − 1` 以下
  - `created_at <= as_of`（06:00 時点で届いていた行だけ。バックテストで当時の状態に近づける）
- 当日 D の晩は使わない。06:00 時点では届いていないことが多いため（到着遅れの中央値は約35時間）
- 登録日より前の晩は使わない。初回連携で入る過去30日分で、担当になる前の変化を検知しないため（体重と同じ理由）
- 窓は2つ
  - 直近の窓: `GREATEST(D − 7, J)` 〜 `D − 1`
  - 前の窓: `GREATEST(D − 14, J)` 〜 `D − 8`

### 4.2 睡眠時間の条件（duration）

- 睡眠時間は `total_sleep_minutes` を使う。HealthKit の値で、覚醒時間を含む
- **120分以上960分以下（2〜16時間、両端を含む）の晩だけを数える**。範囲外は計測ミスとして除き、晩の数にも入れない
  - 時計を外して寝た晩などは、数十分の値で入ることがある
  - 実データは273〜571分で、範囲外は0件
- **窓ごとの代表値は中央値**（`percentile_cont(0.5)`）。カタログの「平均」から変える
  - 体重と同じく `::numeric` にキャストしてから計算・丸めをする。丸めは numeric の `round`（0 から遠い方。340.5 → 341）。double precision のままだと偶数丸めになり、`round(x, 2)` も書けない
  - 平均だと、範囲内でも1晩の外れ値だけで成立してしまう。例: 毎晩383分の人で、前の窓に1晩だけ803分があると、平均の差がちょうど −60 になる
  - 体重は「14日分の中央値から ±15% を超える日を除く」で外れ値を潰しているが、睡眠は日ごとの揺れが大きく（実データの p10〜p90 で ±約25%）、同じ方式だと普通の晩まで除いてしまう
  - 中央値なら、1晩の外れ値では代表値がほとんど動かない。直近の窓の半分以上が短くなったときに成立する
- 評価できる条件: **両方の窓に4晩以上**
  - 体重（3日以上）より厳しくする。HealthKit の睡眠は毎晩入るので、4晩は「週の半分以上」で満たしやすい
  - 登録から11日目（D ≥ J + 11）から評価できる。D = J + 10 では前の窓が3晩以下になる
- Δ = 直近の窓の中央値 − 前の窓の中央値（分。丸める前の値で判定する）
- 状態（5つ）
  - なし: 両方の窓を合わせて有効な晩が0（睡眠時間を連携していない顧客）
  - 不足: 有効な晩はあるが、どちらかの窓が4晩未満（到着遅れで直近の晩が欠ける日を含む）
  - 成立: **Δ ≤ −60**（前の週より1時間以上短い）
  - 解消: Δ > −48（成立値の8割。体重と同じヒステリシス）
  - 保留: −60 < Δ ≤ −48

### 4.3 目覚め評価の条件（wakeup）

- 直近の窓の `wakeup_rating`（1 = だるい、2 = まあまあ、3 = すっきり）を使う
  - 睡眠時間が範囲外・NULL の行の評価も数える（評価は睡眠時間と独立した顧客の申告のため）
  - 平均を使う。値が1〜3の3段階なので、外れ値の問題は無い
- 評価できる条件: 直近の窓に評価が**3回以上**
  - 登録直後は直近の窓が短くなる（`GREATEST(D − 7, J)` から）。表示は「直近7日」ではなく実際の期間を出す（§6.1）
- 状態（5つ）
  - なし: 評価が0回
  - 不足: 1〜2回
  - 成立: **平均 < 1.5**（カタログどおり）
  - 解消: 平均 ≥ 2.0（「まあまあ」以上）
  - 保留: 1.5 以上 2.0 未満
- Web の睡眠カードの警告（9.3、平均 ≤ 1.5）とは境界が違う。カードは水準の目安、アラートは強い兆候なので、アラートはカタログの厳しい方に合わせる
- 目覚め評価を後から付けた行（HealthKit の行に UPDATE で評価を足した行）は `created_at` が古いので、当日の評価でも締め時刻の判定では「届いていた」扱いになる。バックテストの再現性がわずかに落ちるだけで、毎朝の実行には影響しない

### 4.4 全体の状態

上から順に当てる。

1. **detected**: 睡眠時間か目覚め評価のどちらかが成立
2. **unknown**: 睡眠時間が保留か不足、または目覚め評価が保留
3. **cleared**: 睡眠時間が解消、または目覚め評価が解消
4. **unknown**: それ以外（どちらも「なし」、睡眠時間が「なし」で目覚め評価が「不足」など）

unknown は状態を変えない。

| 睡眠時間 \ 目覚め評価 | なし | 不足 | 成立 | 保留 | 解消 |
|---|---|---|---|---|---|
| なし | unknown | unknown | detected | unknown | cleared |
| 不足 | unknown | unknown | detected | unknown | unknown |
| 成立 | detected | detected | detected | detected | detected |
| 保留 | unknown | unknown | detected | unknown | unknown |
| 解消 | cleared | cleared | detected | unknown | cleared |

理由
- 睡眠時間の「不足」で解消させない。到着遅れで直近の窓が3晩になる日は普通にあり、その日に目覚め評価だけで解消すると、翌日に遅れた晩が届いて新しい行が作り直される（対応済みにした行が閉じては開く）
- 睡眠時間が「解消」なら、目覚め評価の「なし」「不足」は解消を止めない。評価を付けない顧客がほとんどで、付けても週に1〜2回の顧客の行が閉じなくなるのを避ける
- 睡眠時間が「なし」の顧客（評価だけを手動で付ける顧客）は、目覚め評価だけで成立・解消する
- 目覚め評価で成立した行が、評価の回数が減った日に睡眠時間の解消で閉じることはありうる。評価はほぼ使われておらず、許容する

監視対象の顧客には、データが無くても `sleep_decline` の行を1行返す（state は unknown）。体重と同じ扱いで、監視対象1名につき3行になる。

### 4.5 重大度

- detected のときは常に **medium**（「注意」）。それ以外は NULL
- 睡眠は生活の兆候で、体重の急変ほど急ぎではないため
- 重大度が上がることが無いので、対応済みの行が再浮上することもない。条件が続く間は対応済みのまま残る

### 4.6 payload（v: 1）

```json
{
  "v": 1,
  "triggers": ["duration", "wakeup"],
  "recent":   { "from": "2026-09-26", "to": "2026-10-02", "median_minutes": 330, "nights": 5 },
  "previous": { "from": "2026-09-19", "to": "2026-09-25", "median_minutes": 402, "nights": 7 },
  "delta_minutes": -72,
  "wakeup": { "avg": 1.33, "count": 3 },
  "threshold": { "drop_minutes": 60, "min_nights": 4, "wakeup_avg": 1.5, "min_ratings": 3 }
}
```

- `triggers`: 成立した条件。detected のときは1つ以上、それ以外は空配列。並びは duration → wakeup
- `from` は窓の実際の始まり（直近は `GREATEST(D − 7, J)`、前は `GREATEST(D − 14, J)`）。登録直後は前の窓の from が to より後になることがある（そのときは nights が0）。体重の payload は直近の from を D − 7 に固定しているが、睡眠は目覚め評価が登録直後から評価できるので、実際の期間を持たせる
- `nights` は有効な晩（120〜960分）の数。窓が空なら0
- `median_minutes` と `delta_minutes` は整数に丸める。窓が空なら `median_minutes` は null、どちらかの窓が空なら `delta_minutes` は null
- `delta_minutes` は丸める前の中央値どうしの差を丸めたもの（丸めた値どうしの差ではない）。成立の判定も丸める前の差で行う。中央値は0.5分刻みなので、差 −59.5 は丸めると −60 になるが成立しない
- `wakeup.avg` は小数2桁に丸める。評価が0回なら null、`count` は0
- 表示用の文字列は入れない（9.1 の方針）
- `severity_reason` は入れない。`run_client_alert_detection` の `severity_lowered` が種別を問わずこのキーを数えるため

### 4.7 状態遷移と期限切れ

- 新規・継続・解消・担当替え・対象外は既存の段（種別に依存しない）がそのまま扱う
- **期限切れを足す**: 生きている `sleep_decline` で `last_detected_on ≤ D − 14` の行を resolved（expired）にする
  - 体重（段 3-1）と同じ形。定数は `c_sleep_expire_days := 14`
  - 監視対象から外れた顧客は evaluate に行が出ず、cleared にならない。これが無いと生きている行が残り続ける
  - 両方の条件が評価できないまま14日たった行も、ここで閉じる

### 4.8 実行記録（`alert_detection_runs.stats`）

- `detected.sleep_decline` を足す（detected の件数。数値）
- 既存のキーは変えない

## 5. DB の変更

**migration**: `supabase/migrations/20261003000000_alert_sleep_decline.sql`（1本）

1. ヘッダー: 既存と同じ罫線の書式。背景・方針・push 前後の確認クエリ
2. **ドリフトガード**: `evaluate_client_alerts` と `run_client_alert_detection` の今の本体（`pg_proc.prosrc`）の md5 が、`20260914000200` の定義と一致することを確かめる。違えば例外で止める
   - 期待値（2026-10-03 に隔離ローカルとリモートの両方で一致を確認済み）
     - `evaluate_client_alerts`: `9c553a939d98fb60d58022897f6a5d4c`
     - `run_client_alert_detection`: `0e80baea1335f09889edac7fc584836f`
   - `20260914000200` より後の migration は両関数に触れていないので、ローカルで全 migration を流す順序でもガードは通る
   - リモートで誰かが関数を直していた場合に、気づかず上書きするのを防ぐ
3. CHECK の作り直し: `alerts_alert_type_check` を DROP して `('weight_change', 'record_gap', 'sleep_decline')` で ADD
4. alerts の列 COMMENT（alert_type / severity / payload / last_detected_on / resolved_reason）に睡眠の説明を足す
5. `CREATE OR REPLACE FUNCTION public.evaluate_client_alerts(date, timestamptz)` を全文で再定義
   - DECLARE に睡眠の定数を足す（§4 の数値。根拠をコメントに書く）
   - `g_eval` の後ろに睡眠の CTE を足し、3本目の `UNION ALL` を足す
   - 関数の COMMENT を「1顧客3行」に直す
6. `CREATE OR REPLACE FUNCTION public.run_client_alert_detection(date)` を全文で再定義
   - 期限切れの段に `sleep_decline` を足す（§4.7）
   - stats に `detected.sleep_decline` を足す。COMMENT のキー一覧も直す
7. 両関数とも `SECURITY DEFINER`・`SET search_path = ''`・完全修飾を守り、REVOKE / GRANT の4行を書き直す
8. **末尾の検査**: 両関数について、`'search_path=""' = ANY (proconfig)`（既存テストと同じ書き方。`proconfig::text` で比べない）で、PUBLIC・anon・authenticated に EXECUTE が無く、service_role にあることを `has_function_privilege` と `proacl` で確かめ、違えば例外で止める
   - REVOKE は自分が付与した権限しか剥がさないため（lessons のフェーズ5.6）
9. 変えないもの: `client_activity_snapshot`、`get_alert_detection_status`、cron、alerts の索引と RLS

**型・モデル**
- Web: `fit-connect/src/types/alert.ts` に `'sleep_decline'` と `SleepDeclinePayload` を足す
- Mobile: alerts を参照していないので変更なし

## 6. Web の変更

### 6.1 表示内容（`fit-connect/src/lib/alerts/describeAlert.ts`）

- `AlertRecordTab` に `'sleep'` を足す。顧客詳細はすでに `?tab=sleep` を受け付ける
- `AlertDescription` に `messageRef: RecordQuoteRef | null` を足す。睡眠悪化は `{ kind: 'sleep_week' }`、それ以外は null
- `readSleepDecline`（payload の検証）と `describeSleepDecline` を足す

| 項目 | 内容 |
|---|---|
| kindLabel・title | 睡眠の悪化 |
| chip | duration が成立:「睡眠 -1時間12分」。wakeup だけ成立:「目覚め評価 1.3」 |
| detail（duration） | 「直近の睡眠 5時間30分（中央値）。前の週より1時間12分短くなっています。9/26〜10/2（5晩）と 9/19〜9/25（7晩）の比較」 |
| detail（wakeup） | 「目覚め評価の平均 1.3（9/26〜10/2 に3回。1 = だるい、3 = すっきり）」 |
| 両方成立 | duration の文のあとに wakeup の文を続ける |
| severityLabel | 注意 |
| tab | sleep |
| messageRef | `{ kind: 'sleep_week' }` |

- chip の符号は体重の chip と同じ ASCII の `-` にそろえる
- 分の表示は 9.3 の `formatSleepMinutes`（「H時間M分」、`fit-connect/src/lib/sleep/sleepQuote.ts` で export 済み）を使う。負の数は0に丸める関数なので、絶対値を渡して符号は文言側で付ける
- 日付は既存と同じく `M/d` の文字列処理で出す（Date のローカル時刻に通さない）
- **payload の検証は triggers にある条件に要る項目だけ**を見る
  - duration が triggers にあるとき: recent / previous の from・to・median_minutes・nights と delta_minutes
  - wakeup が triggers にあるとき: recent の from・to と wakeup の avg・count
  - 目覚め評価だけで成立した行は、前の窓が空（from が to より後、median が null）でも正しい payload として扱う
- 次のときは汎用の文言に落とす: payload が壊れている、v が 1 でない、triggers が空・未知の値だけ、triggers の条件に要る項目が欠けている
  - 計画で追加（2026-10-03）: duration が triggers にあるのに `delta_minutes` が0以上（「短くなっています」と事実と違う文を出さない）、`nights`・`wakeup.count` が0以上の整数でない。triggers の未知の値は無視し、既知の条件が1つあれば読む
  - chip「睡眠の悪化」、detail「睡眠の自動チェックで変化を検知しました。睡眠タブで記録を確認してください。」
  - tab は sleep、messageRef は `{ kind: 'sleep_week' }` のまま（payload に依存しないため）、recognized は false

### 6.2 「今日の対応」の導線

- `buildTriageRows`: 行に `messageRef` を持たせる。**先頭の理由の messageRef をそのまま使う**。理由の並びは既存どおり重要度 → surfaced_on の新しい順 → id
  - record_gap（medium）と睡眠悪化（medium）が同じ行にあると、引用が付くかどうかは surfaced_on で決まる
  - recordTab も先頭の理由から取っているので、「記録を見る」と「メッセージ」の対象がそろう
  - 体重の急変（要確認）と睡眠悪化（注意）が同じ行にあるときは、「記録を見る」は体重タブ、「メッセージ」は引用なし。睡眠への導線は詳細のリンクに任せる
- `TriageRow`
  - 未返信が無い行の「メッセージ」: messageRef があれば `recordQuoteHref(clientId, messageRef)`（`/message?clientId=…&record=sleep%3A7d`）、無ければ今までどおり
  - 未返信がある行の「返信する」は変えない。返信は顧客のメッセージへの応答で、睡眠の引用を勝手に足さない
  - 行を開いた詳細で、睡眠悪化の理由には「睡眠の記録を引用してメッセージ」のテキストリンクを出す（未返信の有無・理由の順番を問わない）。色は 9.3 の SummaryTab と同じ `#0F766E`
- アクセシブルな名前は既存の規約どおり `fit-connect/src/lib/triage/triageLabels.ts` に関数を足し、テストで固定する
  - 引用付きの「メッセージ」:「{名前}さんに睡眠の記録を引用してメッセージを書く」
  - 詳細のリンク: 同じ文言。見えている文字（「睡眠の記録を引用してメッセージ」）が名前にそのまま含まれるようにする（既存の規約。音声操作のため）
- href の組み立ては純関数にして vitest で固定する（コンポーネントのテスト基盤が無いため）
- 優先度スコアは変えない（medium = 10 点）
- バッジは open のアラートがある顧客を数えるので、変更なしで睡眠悪化も入る

### 6.3 9.3 との関係

- 引用は 9.3 の `sleep:7d`（「直近7日」）をそのまま使う
- 引用の数字はアラートの数字と食い違うことがある。引用はその時点の最新のデータを示すものとして、このままにする
  - 9.3 の「直近7日」は書いた時点から数え、当日の晩も入る。アラートの窓（D−7〜D−1）と最大1日ずれる
  - 9.3 は平均で、範囲外の晩・登録日・締め時刻での除外もしない。アラートは中央値で、これらを除く
- アラートが残ったまま直近7日の記録が途絶えると、引用チップは出ない（9.3 の既存の動き。メッセージ画面は開き、コンソールに警告が出るだけ）。成立には直近の窓に睡眠時間4晩以上か目覚め評価3回以上が要るので、検知した直後には起きない

## 7. エラー処理

- payload の不正は §6.1 の汎用の文言に落とす。1件の不正で「今日の対応」全体を落とさない（既存の方針）
- 睡眠の値は顧客が自由に書ける（RLS）。範囲外の睡眠時間は §4.2 で除き、未来の日付は窓の上限（D − 1）で落ちる
- migration のドリフトガードか末尾の検査に引っかかったら push は止まる（トランザクションごと巻き戻る）。そのときはリモートの関数の差分を調べてから migration を直す
- DB の適用前に Web が出ても、睡眠悪化の行が無いだけで壊れない。Web の適用前に DB が出た場合は、既存の未知の種別の表示（「自動チェックの検知」）に落ちる

## 8. テスト

### 8.1 SQL（隔離したローカルのスタックで流す。共有スタック `supabase_db_fit-connect` には migration を当てない）

新しいファイル `supabase/tests/sleep_decline_alert_test.sql`（既存と同じ `BEGIN … ROLLBACK` と `DO` ブロックの書式）

組み立ての注意
- `sleep_records` の `created_at` / `updated_at` は必ず明示する。既定値の now() のままだと、過去の対象日では締め時刻より後になり、窓にも最終到着日 R にも入らない
- 監視対象にするため、各顧客の最終到着 R が D − 14 以降になるようにする（睡眠の created_at で足りる）

evaluate のケース
1. duration が成立（前の窓7晩・直近5晩、Δ −70）→ detected・medium・triggers ["duration"]・payload の各値
2. 境界: Δ = −60 は成立、Δ = −59.5 は保留（丸めると −60 だが成立しない）
3. 解消: Δ = −47 は cleared、Δ = −48 は保留
4. 直近の窓が3晩（目覚め評価なし）→ unknown
5. 範囲外: 119分・961分の晩は数えず、120分・960分ちょうどは数える
6. 外れ値: 毎晩383分で前の窓に900分が1晩 → 成立しない。直近4晩のうち1晩だけ140分 → 成立しない
7. 窓の境界: D − 8 の晩は前の窓、D − 7 の晩は直近の窓に入る
8. 登録日: 登録日より前の晩は数えない。D = J + 10 は評価できず、D = J + 11 は評価できる
9. `created_at > as_of` の晩は数えない
10. 当日 D の晩と未来の日付は数えない
11. `delta_minutes` が丸める前の中央値どうしの差から出ている（例: 直近の中央値 340.5・前 400.0 → `delta_minutes` は −60。丸めた値どうしの 341 − 400 = −59 ではない。状態は保留）
12. 目覚め評価だけで成立（睡眠時間が NULL の評価だけの行、[1, 1, 2]）→ detected・triggers ["wakeup"]・前の窓は nights 0
13. 目覚め評価の境界: 平均ちょうど 1.5（[1, 1, 2, 2]）は保留、[2, 2, 2] は解消
14. 両方成立 → triggers ["duration", "wakeup"]
15. §4.4 の表の代表的な組み合わせ
    - duration 成立 + wakeup 解消 → detected
    - duration 解消 + wakeup 保留 → unknown
    - duration 解消 + wakeup なし → cleared
    - duration 解消 + wakeup 不足 → cleared
    - **duration 不足 + wakeup 解消 → unknown**
    - duration なし + wakeup 解消 → cleared
    - duration なし + wakeup 不足 → unknown
16. 監視対象でない顧客（self・no_account）には行が無い。データの無い監視対象には unknown の行がある

run のケース
17. 新規 → open・medium・`surfaced_on = D`。同じ D の再実行は件数が増えない
18. 保留（unknown）の日は status・`last_detected_on`・payload が変わらない
19. 後の日に cleared → resolved（cleared）
20. 期限切れ: `last_detected_on = D − 14` の生きている行は expired、`D − 13` は残る（この顧客の評価が cleared ではなく unknown になるデータにする。cleared だと期限切れの前に解消で閉じる）
21. 対応済みの行は、成立が続いても対応済みのまま
22. stats に `detected.sleep_decline` がある
23. CHECK は `sleep_decline` を受け付け、未知の値を拒む
24. 再定義の後も両関数が DEFINER・`search_path = ''`、EXECUTE は service_role だけ（`proacl` と PUBLIC を含めて確かめる）

既存テストの修正
- `client_alert_detection_test.sql` case (e) の「監視対象は2行」を3行にする。case (j) に `detected ? 'sleep_decline'` を足す
- 回帰として `client_alert_detection_test.sql`・`client_alerts_rls_test.sql`・`client_activity_snapshot_test.sql`・`cron_jobs_test.sql`・`function_search_path_privileges_test.sql`・`definer_functions_privileges_test.sql` を流す

### 8.2 Web（vitest、純関数）

- `describeAlert.test.ts`: duration だけ・wakeup だけ（前の窓が空）・両方・壊れた payload（v: 2、triggers が空、triggers の条件に要る項目の欠け）の chip・detail・tab・messageRef・重要度ラベル
- `buildTriageRows.test.ts`: messageRef は先頭の理由から取る。睡眠悪化が先頭なら recordTab が sleep で messageRef が sleep_week。体重が先頭なら messageRef は null。record_gap と睡眠悪化（どちらも medium）は surfaced_on の新しい方が先頭になる
- 「メッセージ」の href を組み立てる純関数のテスト。期待値はエンコード済みの `record=sleep%3A7d` で書く
- `triageLabels.test.ts`: 引用付きのアクセシブルな名前
- **既存のテストの期待値の修正**: `AlertDescription` / 行のオブジェクト全体を比べている箇所に `messageRef: null` を足す（`describeAlert.test.ts` の3箇所、`buildTriageRows.test.ts` の行全体の比較）
- tsc・lint・`next build` を通す

### 8.3 画面の確認（chrome-web-qa の代わりに、確立済みの「隔離スタック + 合成 Cookie + 内蔵ブラウザ」）

- 合成データで `run_client_alert_detection` を回し、睡眠悪化の行を作る
- 「今日の対応」に「睡眠の悪化」「注意」と chip が出る
- 「記録を見る」で睡眠タブが開く
- 「メッセージ」でメッセージ画面が開き、「直近7日」の引用チップが入っている
- 詳細を開くと文言と「睡眠の記録を引用してメッセージ」のリンクがある
- 体重の急変と睡眠悪化が同じ行にあるとき、「メッセージ」は引用なしで、詳細のリンクから引用付きで開ける
- 「対応済み」と「元に戻す」が動く。バッジの数が合う

## 9. リリースとロールバック

**前提**: cron `detect-client-alerts` はすでに有効で、毎朝 06:00 JST に動いている。push した翌朝から新しいルールが動く。

**リリース**
1. PR をマージする。Web が先に出ても壊れない（§7）
2. オーナーが push する。06:00 JST の直前は避ける（適用後の確認の時間を取るため）
   - `supabase migration list --linked` と `supabase db push --dry-run` で、未適用が `20261003000000` の1本だけであることを確かめる
   - `supabase db push`
3. 適用後すぐに確認する（Claude が MCP の読み取りで実施できる。件数だけ。MCP が使えないときはオーナーに SQL Editor で頼む）
   - CHECK の定義、両関数の proconfig と EXECUTE 権限
   - dry run: `evaluate_client_alerts()` の種別・状態ごとの件数
   - 30日のバックテスト: 各日 d について `evaluate_client_alerts(d, d の 06:00 JST)` を流し、前日に detected でなかった顧客の新規件数を数える
     - 評価できない日（unknown）を挟むと、翌日にもう一度新規に数えられる。睡眠は到着遅れでこの日が多いので、多めに出る方向にずれる
4. 想定外の件数が出たら、06:00 より前にオーナーが cron を止める（`SELECT cron.alter_job(jobid, active := false) FROM cron.job WHERE jobname = 'detect-client-alerts';`）。止めると体重・途絶の検知も止まるので、原因を直したらすぐ戻す
5. 翌朝 06:00 の実行で `alert_detection_runs.stats` に `detected.sleep_decline` が入ることを確かめる

**ロールバック**（必要になったときだけ。新しい migration で行う）
1. `sleep_decline` の行を、resolved のものも含めてすべて DELETE する（CHECK を ADD するときに全行が検証されるため、resolved にするだけでは戻せない）
2. 両関数を `20260914000200` の定義に戻す
3. CHECK を元の2種別に戻す
4. COMMENT を元の文面に戻す（`CREATE OR REPLACE FUNCTION` では COMMENT は戻らない。`md5(prosrc)` には影響しない）
   - `alerts` の列 COMMENT 5つ（`alert_type` / `severity` / `payload` / `last_detected_on` / `resolved_reason`）は `20260914000000` の `COMMENT ON COLUMN`（96〜127行）の文面に
   - 関数の COMMENT 2つ（`evaluate_client_alerts` / `run_client_alert_detection`）は `20260914000200` の `COMMENT ON FUNCTION`（288行・601行）の文面に

## 10. 触るファイル

| ファイル | 変更 |
|---|---|
| `supabase/migrations/20261003000000_alert_sleep_decline.sql` | 新規（§5） |
| `supabase/tests/sleep_decline_alert_test.sql` | 新規（§8.1） |
| `supabase/tests/client_alert_detection_test.sql` | case (e)・(j) の修正 |
| `fit-connect/src/types/alert.ts` | 種別と payload 型 |
| `fit-connect/src/lib/alerts/describeAlert.ts`（+ テスト） | 睡眠の文言・tab・messageRef |
| `fit-connect/src/lib/sleep/formatSleepMinutes.ts`・`fit-connect/src/lib/message/recordQuoteLink.ts`（新規） | 計画で追加。`describeAlert` は全ページの layout から読まれるので、date-fns を読む `sleepQuote.ts`・`recordQuoteRef.ts` を経由させないよう依存の無い部分を分け、元のファイルから再 export する（/settings の First Load が 218 kB → 207 kB） |
| `fit-connect/src/types/triage.ts` | 行の messageRef |
| `fit-connect/src/lib/triage/buildTriageRows.ts`（+ テスト） | messageRef の選択 |
| `fit-connect/src/lib/triage/triageLabels.ts`（+ テスト） | 引用付きのアクセシブルな名前 |
| href を組み立てる純関数（既存の `clientMessageHref` の隣。+ テスト） | 引用付きの「メッセージ」の href |
| `fit-connect/src/components/dashboard/TriageRow.tsx` | 「メッセージ」の href と詳細のリンク |
| `docs/tasks/2026-07-10-cron-vault-setup.md` | §5 の判定の説明に睡眠を足す。バックテストの SQL に睡眠の新規件数の列と偏りの注記を足す |
| `docs/tasks/2026-09-13-trainer-intervention-plan.md` | データモデルの CHECK と拡張の項に実装済みを書く |
| `docs/tasks/IMPLEMENTATION_TASKS.md` | 9.1 の睡眠悪化、9.3 の PR 番号（#95）と Mobile 確認済み、9.3 拡張「9.1 のアラートからの導線」 |
| `docs/tasks/lessons.md` | 得た知見 |

## 11. 前提として決めたこと（オーナーが覆せる）

| 決めたこと | 理由 | 変えるときに触る場所 |
|---|---|---|
| 窓ごとの代表値は中央値（カタログは平均） | 1晩の外れ値だけで成立させない | 評価関数 |
| 1時間以上の短縮で成立、48分以内に戻ったら解消 | カタログの初期値。解消は体重と同じ8割 | 評価関数の定数 |
| 各週4晩以上で評価 | 3晩どうしの比較は揺れが大きい | 評価関数の定数 |
| 120〜960分の晩だけ数える | 時計を外した晩などの計測ミスを除く | 評価関数の定数 |
| 目覚め評価は直近3回以上・平均1.5未満で成立 | カタログどおり。評価はほぼ使われていない | 評価関数の定数 |
| 睡眠時間が4晩に満たない日は解消しない | 到着遅れで行が閉じては開くのを防ぐ | 評価関数（§4.4 の表） |
| 重大度は常に「注意」 | 体重の急変ほど急ぎではない | 評価関数の定数 |
| 睡眠時間の絶対値では検知しない | カタログに無く、「悪化」は変化で見る | 拡張（§12） |
| 「返信する」には引用を付けない | 返信は顧客のメッセージへの応答 | TriageRow |
| 「メッセージ」の引用は先頭の理由が睡眠悪化のときだけ | 「記録を見る」と対象をそろえる | buildTriageRows |

## 12. 範囲外・拡張候補

- 睡眠時間の絶対値（直近の中央値が6時間未満など）での検知
- 閾値のトレーナー設定（計画書の `alert_settings`）
- 寝る時刻のばらつき、深い睡眠の割合などの質の指標
- トレーナー向け push（計画書「通知」の手順に `sleep_decline` も載る）
- 9.3 の拡張: アラートの窓と同じ期間を引用する `sleep:range`、チャートの点クリック、`metadata.record_ref`
