# 食事栄養推定 モデル A/B 評価ハーネス

`supabase/functions/estimate-meal-nutrition`（Edge Function）の **画像ルート** を、現行の Sonnet 4.6 から
Haiku 5.5 などへ切り替えてよいかを **同一入力で比較** して判断するための評価ハーネスです。
背景と判断基準は [`docs/tasks/2026-10-08-haiku-5-5-photo-estimation-feasibility.md`](../../docs/tasks/2026-10-08-haiku-5-5-photo-estimation-feasibility.md)（§4 必要な変更、§7 判断基準）を参照。

- 本番と同じ **システムプロンプト**（実行時に本番 `index.ts` から抽出。手コピーしない）
- 本番と同じ **リクエスト形状**（画像 1〜3 枚 → テキスト、system は `cache_control` 付き 1 ブロック）と **後処理**
  （`extractJson` → `validateEstimation` → app_name/warning → EMPTY 判定。`src/production-logic.ts` に行番号付きで移植）
- 実測 `usage` からの **コスト**、**レイテンシ**（本番の 30 秒タイムアウト超過率）、**refusal / max_tokens 停止** も記録
- 事前登録した **判定ルール** で PASS / FAIL / INSUFFICIENT DATA を出す

## 比較するアーム

| アーム | model | max_tokens | temperature | output_config.effort | 画像ティア |
| --- | --- | --- | --- | --- | --- |
| `sonnet-4-6-prod`（基準） | `claude-sonnet-4-6` | 1024 | 0.2 | 送らない | 標準（長辺 1568px / 1568 visual tokens） |
| `haiku-5-5-low` | `claude-haiku-5-5` | 4096 | 送らない | `low` | 高解像度（2576px / 4784） |
| `haiku-5-5-medium` | `claude-haiku-5-5` | 4096 | 送らない | `medium` | 高解像度 |
| `sonnet-5-5-low` | `claude-sonnet-5-5` | 4096 | 送らない | `low` | 高解像度 |

パラメータが本番と違う理由:

- **temperature を送らない**: Haiku 5.5 / Sonnet 5.5 は `temperature`・`top_p`・`top_k` の非デフォルト値を 400 で拒否する（feasibility §4-2）。そのため候補アームは試行ごとのばらつきが基準より大きくなり得る → 「試行間 CV」で測る。
- **thinking パラメータを送らない**: どちらも adaptive thinking が既定 ON。思考量は `output_config.effort` で調整する（Haiku 5.5 の既定は medium、Sonnet 5.5 の既定は high）。
- **max_tokens 4096**: thinking トークンも max_tokens を消費するため、1024 のままだと JSON の前で `max_tokens` 停止しうる（§4-4）。
- **`fallbacks`（サーバ側フォールバック）はどのアームにも送らない**: refusal を別モデルに逃がすと「そのモデルが拒否する率」が測れなくなるため。Haiku 5.5 にはそもそもサーバ側フォールバックが無い（本番に入れても救済されない）ので、拒否率はそのまま計測する。
- 画像は本番では署名 URL（`source.type: 'url'`）だが、評価では **同じ JPEG バイト列を base64** で送る（モデルが見る画素は同じ。URL 取得時間はレイテンシに含まれない）。

料金（USD / 100 万トークン、2026-10-09 に pricing ページで確認）: Sonnet 4.6 入力 3 / 5 分キャッシュ書込 3.75 / キャッシュ読取 0.30 / 出力 15、
Sonnet 5.5 2 / 2.50 / 0.10 / 10、Haiku 5.5 0.10 / 0.125 / 0.01 / 0.50（1 リクエストのプロンプト = input + キャッシュ書込 + キャッシュ読取 が 100,000 以下）、
超える場合 0.50 / 0.625 / 0.05 / 2.50。為替は 150 円/USD 固定。どのカードが適用されたかは各記録の `price_card` に残る。

## データセット

すべて `datasets/<name>/cases.json`（契約は `src/dataset.ts`）。実行時は既定で存在するものを全部使います。

| データセット | 種類 | 中身 | 入手方法 | Git |
| --- | --- | --- | --- | --- |
| `screenshots-synthetic` | スクショ | 架空の食事管理アプリ画面（Chromium で描画、正解値が厳密に既知）27 件。2 枚組の整合/不整合（warning）、日表示、英語 UI、ダーク、非食事画像を含む | `npm run gen:screenshots`（`generators/screenshots/README.md`） | コミット済み |
| `photos-nutrition5k` | 写真 | Nutrition5k（Google Research, CVPR 2021, CC BY 4.0）の俯瞰 RGB と計量ベースの栄養値 | `npm run fetch:nutrition5k -- --n 50` | 入れない（ライセンス確認前は再配布しない） |
| `photos-custom` | 写真 | オーナー提供のラベル付き写真（コンビニ食品の栄養成分表示 = 正解値） | `npm run import:custom`（[`datasets/photos-custom/README.md`](datasets/photos-custom/README.md)） | README と記入例だけ |

- **Nutrition5k の出典**: Thames, Q. et al., "Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food", CVPR 2021. https://github.com/google-research-datasets/Nutrition5k 。ライセンスは CC BY 4.0（**利用・共有の前に上記 GitHub で最新の条件を必ず確認**）。メタデータ CSV の各行の先頭 6 列（`dish_id,total_calories,total_mass,total_fat,total_carb,total_protein`）だけを使い、50〜1500 kcal の料理をシード付きで抽出、404 の画像は飛ばします。
- `fetch:nutrition5k` は `storage.googleapis.com` に接続します。**Claude Code のクラウド環境では現在このホストがネットワーク許可リストに無く、プロキシが CONNECT に 403 を返す** ため、スクリプトはホスト名を示して即座に失敗します。環境の許可ドメインに `storage.googleapis.com` を追加するか、許可された環境で実行して `datasets/photos-nutrition5k/` をコピーしてください。スクリプトは Node 組み込み fetch にプロキシを使わせるため `NODE_USE_ENV_PROXY=1` で自分を再実行します（Node 22.21 以上）。
- 画像はすべて **モバイルアプリと同じ前処理**（`fit-connect-mobile/lib/services/storage_service.dart`: 1920×1080 の枠に収める・拡大しない・JPEG 品質 80）済みで、そのまま API に送ります。
- `src/__fixtures__/` はハーネス自体のテスト用（単色画像・架空の期待値）で、評価データではありません。

## 使い方

```bash
cd evals/meal-estimation

# 1. ハーネスの自己テスト（オフライン・API キー不要・ネットワーク不使用）
npm run selftest

# 2. 費用の見積り（生成 API は呼ばない）
#    キーが無ければローカル概算、キーがあれば countTokens で入力トークンを実測（countTokens は無料）
npm run estimate
ANTHROPIC_API_KEY=... npm run estimate

# 3. 実行（--yes が無いと見積りを表示して終了するだけ）
ANTHROPIC_API_KEY=... npm run run -- --yes
#    まず少量で疎通確認するなら:
ANTHROPIC_API_KEY=... npm run run -- --yes --limit 2 --trials 1

# 4. レポートの再生成（実行の最後にも自動で作られる）
npm run report -- runs/<日時>
```

`npm run run` のオプション:

| オプション | 既定 | 説明 |
| --- | --- | --- |
| `--dataset <dir>` | `datasets/*/cases.json` 全部 | 繰り返し指定可 |
| `--arms a,b` | 4 アームすべて | 例: `--arms sonnet-4-6-prod,haiku-5-5-low` |
| `--trials N` | 3 | 同一入力の繰り返し回数（ばらつきの測定用） |
| `--limit N` | なし | データセットごとに先頭 N ケースだけ |
| `--concurrency N` | 4 | 同時リクエスト数 |
| `--out <dir>` | `runs/<UTC 日時>` | 出力先 |
| `--resume <dir>` | — | `raw.jsonl` に記録済みの (ケース, アーム, 試行) を飛ばして続きから。データセット・アーム・上限は元の設定を引き継ぐ（`--trials` は増やせる）。本番プロンプトや cases.json が変わっていたら中止 |
| `--retry-errors` | — | `--resume` 時、API エラーで終わったものだけ再実行（採点は各キーの最後の記録を使う） |
| `--estimate` | — | キーがあれば countTokens で入力を実測して見積る |
| `--yes` | — | これが無い限り生成 API は一切呼ばない |

API キーは環境変数 `ANTHROPIC_API_KEY` からのみ読みます（SDK の既定動作）。`.env` は読みません。キーはどのファイルにも書き出しません。
クライアントは `maxRetries: 3`、リクエストごとのタイムアウト 60 秒。アームはケース・試行ごとに隣接して実行します（時間帯の偏りを避けるため）。

### 出力（`runs/<日時>/`、Git には入らない）

| ファイル | 内容 |
| --- | --- |
| `raw.jsonl` | 1 呼び出し 1 行: case_id, dataset, input_kind, arm, model, trial, started_at, latency_ms（最後の HTTP 試行の開始→応答解析完了）, attempts, stop_reason, stop_details, usage（キャッシュ項目含む全項目）, price_card, cost_usd, 最初の `type==='text'` ブロックの本文, validateEstimation 後の結果, app_name, warning, empty_result, outcome（ok / empty / parse_fail / refusal / error）, error {type,status,message}, prod_timeout_exceeded（latency_ms > 30000） |
| `meta.json` | 引数、アーム設定、本番プロンプトの SHA-256、データセット（cases.json の SHA-256）、git HEAD と本番 index.ts の未コミット変更の有無、SDK / Node のバージョン、開始・終了時刻 |
| `datasets.json` | 採点に使う期待値のスナップショット（データセットを後で直しても採点が再現できる） |
| `summary.json` / `report.md` | 採点結果（report.md は日本語） |

API エラー（429・5xx・タイムアウト等）は記録して実行を続けます（落ちない）。`stop_reason: "refusal"` は本文をパースせず refusal として記録し、`max_tokens` 停止は記録したうえで本文があればパースを試みます。

## 指標

データセット × アームごと:

- 呼び出し品質: パース失敗率、refusal 率、max_tokens 停止率、API エラー率
- **false-EMPTY 率**（is_meal=true なのに foods 空 or refusal）、**正しい拒否率**（is_meal=false で foods 空 or refusal）
- レイテンシ p50 / p90、**30 秒超の割合**（本番なら失敗する呼び出し）
- 1 回あたりの平均コスト（USD・円）、1000 回あたりの円
- 写真: kcal の絶対誤差率（APE）中央値 / p90 / 平均、MAE kcal、±20% 以内率、P/F/C の MAE（g）、試行間 CV の中央値
- スクショ: 項目別正解率（|予測−正解| ≤ 1、`alt_totals` のどれかと一致で可）、4 項目同時正解率、warning 正解率、品目数一致率、アプリ名一致率
- ベースラインとのケース単位の対応あり比較（試行平均）: 写真は Δ APE の中央値、スクショは Δ 4 項目同時正解率。シード固定のブートストラップ 95% CI
- 候補ごとの悪化上位 10% のケース（期待値と両者の回答）、スコア対コストの表（パレート最適に ★）

## 判定ルール（事前登録。結果を見てから変えない）

対応ありで採点できたケースが **20 件未満**、または評価できない条件がある場合は **INSUFFICIENT DATA**。

- **写真ルート**: 候補の kcal APE 中央値 ≤ 基準の **1.10 倍** かつ false-EMPTY 率 ≤ 基準 **+2pt** → PASS
- **スクショルート**: 4 項目同時正解率・warning 正解率・正しい拒否率が **すべて基準 −2pt 以上** → PASS

feasibility §7 の「誤差中央値 +10% 以内かつ EMPTY_RESULT 率が悪化しない」「OCR 精度が同等以上」を数値化したもの。
PASS は「切り替えてよい根拠がある」、FAIL は「このままでは切り替えない」。パース失敗率・30 秒超の割合・試行間 CV はルールに入れていないが、レポートで必ず確認すること。

## 費用の目安

ローカル概算（キャッシュ無し、出力は「可視 400 + thinking（low 500 / medium 1500）」トークンと仮定）。1 回あたり:

| 入力 | sonnet-4-6-prod | haiku-5-5-low | haiku-5-5-medium | sonnet-5-5-low |
| --- | --- | --- | --- | --- |
| 写真 1920×1080 × 1 枚 | 約 1.9 円 | 約 0.12 円 | 約 0.19 円 | 約 2.4 円 |
| 写真 1920×1080 × 3 枚 | 約 3.3 円 | 約 0.20 円 | 約 0.27 円 | 約 4.0 円 |
| 写真 640×480 × 1 枚（Nutrition5k 想定） | 約 1.3 円 | 約 0.08 円 | 約 0.16 円 | 約 1.7 円 |
| スクショ 499×1080 × 1 枚 | 約 1.7 円 | 約 0.10 円 | 約 0.17 円 | 約 2.0 円 |

4 アーム × 3 試行で 1 ケースあたり約 10〜14 円。`screenshots-synthetic`（27 件）は `npm run estimate` で約 330 円、
これに写真 50 件を足しても **合計 1,000〜1,500 円程度** の見込み。実行前に必ず `npm run estimate` の表示を確認すること
（thinking が仮定より多ければ候補アームの出力側が増える。結果は実測 usage で再計算される）。

## 制約・注意（結果を読むときに）

- **スクショは合成データ**: 実在アプリ（あすけん・カロミル・MyFitnessPal 等）の画面ではなく、架空アプリを描画したもの。字形・レイアウト・圧縮の具合は実機と違う。実機スクショで数件確認するのが望ましい。
- **Nutrition5k は米国の社員食堂の料理** で、日本食（定食・弁当・丼・汁物）とは分布が違う。俯瞰カメラの固定アングル・低解像度（RealSense）でもある。和食での精度は `photos-custom` で確認すること。
- **画像はアプリ側で最大 1920×1080 に縮小済み** で届くため、高解像度ティア（長辺 2576px）の利点は一部しか使われない。特にスマホのスクショ（例: 1170×2532）はアプリが **約 499×1080** まで縮めるので、両ティアとも縮小なしで同じ画素を見る（Sonnet 4.6 の標準ティアで縮小されるのは 1920×1080 の横長写真など）。
- **試行回数 3 は少ない**: 候補アームは temperature を固定できないため、ばらつきの推定は粗い。境界付近の結果なら `--resume <dir> --trials 5` で増やす。
- **Haiku 5.5 の画像ティア** は Vision ドキュメントの「Claude 4.7 以降のモデル = 高解像度」から判断している。実行後の `usage.input_tokens` で確認すること。
- **プロンプトキャッシュ**: 本番と同じく system に `cache_control` を付けているが、最小キャッシュ長（Sonnet 4.6 は 1024 tokens）未満の写真用プロンプトはキャッシュされない。コストは実測 usage で計算するので、この差は結果にそのまま反映される。
- ローカル概算の文字数→トークン係数（×0.9 / ×1.17）は近似。正確な入力トークンはキーがあるときの `npm run estimate`（countTokens）で。
- Vision ドキュメントの例示表は 2000×1500 を「1269×952」としているが、同ドキュメントの参照実装は 1270×952 を返す（visual token 数はどちらも 1564）。ハーネスは参照実装に従う。

## ファイル構成

| パス | 役割 |
| --- | --- |
| `src/prompts.ts` | 本番 `index.ts` から `SYSTEM_PROMPT` / `SCREENSHOT_SYSTEM_PROMPT` を実行時に抽出・ハッシュ |
| `src/production-logic.ts` | 本番ロジックの移植（extractJson / clampPositive / validateEstimation / テキスト構築 / app_name・warning / EMPTY 判定 / リクエスト形状） |
| `src/arms.ts` | アーム設定、料金表とコスト計算、Vision ティアと `resizedSize`（公式参照実装の移植） |
| `src/dataset.ts` | データセット契約の型・検証・読み込み、モバイル相当の前処理 |
| `src/run.ts` | 実行 CLI（見積り・支出ガード・実行・再開） |
| `src/grade.ts` / `src/report.ts` | 採点と日本語レポート |
| `src/stats.ts` | 分位点・ブートストラップ・シード付き乱数 |
| `src/fetch-nutrition5k.ts` / `src/import-custom-photos.ts` | 写真データセットの作成 |
| `src/selftest.ts` | オフライン自己テスト（偽応答は採点コードの検証専用で、結果ではない） |
| `src/__fixtures__/` | 自己テスト用の極小フィクスチャ（`make-fixtures.ts` で再生成可） |
| `generators/screenshots/` | 合成スクショの生成器 |
