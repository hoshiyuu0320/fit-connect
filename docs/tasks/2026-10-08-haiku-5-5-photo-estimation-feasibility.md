# 写真カロリー推定モデルの Haiku 5.5 移行 — 実現性・差分調査

- 作成日: 2026-10-08
- 対象: `supabase/functions/estimate-meal-nutrition/index.ts`（`callClaude`）
- 位置づけ: `docs/tasks/2026-07-11-pro-pricing-proposal.md` §8 決定事項 7「写真解析 haiku 化検証（Go）」の前段調査。実装・切替はまだ行っていない

## 1. 結論（要約）

| 観点 | 結論 |
| --- | --- |
| Haiku 5.5 は使えるか | **使える**。画像入力（URL ソース含む）対応、Messages API（`anthropic-version: 2023-06-01`）でそのまま呼べる。ただし現コードのまま model 名だけ差し替えると **400 エラー**（`temperature` 指定が原因）。必須修正は 3 点（§4） |
| コスト差 | 1 リクエストあたり **約 1/15**（写真 1 枚: 約 1.9 円 → 約 0.13 円、3 枚: 約 3.3 円 → 約 0.21 円）。料金提案書で試算した Haiku 4.5 案（0.7〜1.4 円）よりさらに約 1/5。100K トークン超過時の 5 倍レートは本件のリクエスト（最大約 1 万トークン）では発生せず、仮に適用されても約 1/3（§5.1） |
| 精度差 | **公開データからは定量化できない**。Sonnet 4.6 と Haiku 5.5 を直接比較した Vision ベンチマークが存在しない。唯一の視覚ベンチ Chartography では Haiku 5.5 = 46.4%（Haiku 4.5 の 6.4% から 7 倍超、現行 Sonnet 5.5 の 61.6% には 15pt 届かず）。Sonnet 4.6 は 2 世代前の Sonnet なので「同等〜やや劣る」のどちらもあり得る。**自前の評価データで A/B するしかない**（料金提案書の方針どおり） |
| 推奨 | 評価データ（写真 30〜50 件 + スクショ 10〜20 件）で Sonnet 4.6 / Haiku 5.5(effort low, medium) / Sonnet 5.5 を同時比較してから切替判断。評価実行コストは数百円以下 |

## 2. 現状

| 項目 | 値 |
| --- | --- |
| 画像あり（料理写真・他社アプリスクショ） | `claude-sonnet-4-6`（$3 / $15 per MTok、画像は標準解像度ティア: 長辺 1568px・最大 1,568 visual tokens） |
| テキストのみ | `claude-haiku-4-5`（$1 / $5 per MTok） |
| パラメータ | `max_tokens: 1024`、`temperature: 0.2`、system prompt に `cache_control: ephemeral`、生 `fetch` 呼び出し（SDK 不使用） |
| 画像の渡し方 | service_role 署名 URL（600s）を `source: { type: 'url' }` で最大 3 枚 |
| Mobile 側の画像サイズ | `StorageService`: 長辺 1920 × 短辺 1080 上限、JPEG 品質 80 |
| 出力処理 | `content` から `type === 'text'` ブロックを検索 → `extractJson`（コードフェンス除去）→ `validateEstimation`（整数化・totals 再計算） |
| ログ | `ai_estimation_logs` に status / error_code のみ。**model・トークン数・コストは記録していない**（実測ベースラインが取れない） |
| 既存の判断 | `2026-05-09-task-2.3` 設計で「Vision 精度確保のため画像あり → Sonnet 4.6」と決定。`2026-07-11` 料金提案書で「写真解析 haiku 化は評価データで A/B 後に判断（Go）」 |

## 3. Haiku 5.5 の仕様（2026-10-07 リリース、公式ドキュメントより）

| 項目 | Haiku 5.5 | 備考 |
| --- | --- | --- |
| Model ID | `claude-haiku-5-5` | 日付サフィックスなし |
| 入力 | テキスト + 画像 → テキスト | 画像 URL ソース対応 |
| 料金（プロンプト 100K tok 以下） | 入力 $0.10 / 出力 $0.50 per MTok、cache read $0.01 | 本件は常に 100K 以下 |
| 画像解像度ティア | 高解像度ティア（長辺 2576px・最大 4,784 visual tokens）と解釈 | Vision docs は「Claude 4.7 以降のモデル」と記載し Haiku 5.5 を個別には明記していない。初回テスト呼び出しの `usage.input_tokens` で確認が必要 |
| Thinking | adaptive がデフォルト ON。`effort`（low〜max、既定 medium）で制御 | thinking トークンは `max_tokens` に含まれる |
| サンプリング | `temperature` / `top_p` / `top_k` の非デフォルト値は **400** | 現コードの `temperature: 0.2` が該当 |
| Prefill | 400 | 本件は未使用 |
| 安全分類器 | `stop_reason: "refusal"` が返りうる。**サーバ側 fallback なし** | Haiku 4.5 からの移行では新規事項 |
| トークナイザ | 同一テキストで Haiku 4.5 / Sonnet 4.6 比 **約 +30%** | コスト試算に反映済み |
| キャッシュ最小長 | 512 tokens | Sonnet 4.6 は 1024、Haiku 4.5 は 4096。現状の SYSTEM_PROMPT（約 500〜600 tok）は **どちらのモデルでもキャッシュされていない可能性が高い**。Haiku 5.5 では両プロンプトともキャッシュ対象になる見込み |
| 位置づけ（公式） | 「分類・抽出・ルーティング・サブエージェント向け。複雑なエージェント的コーディングは Sonnet 5.5 / Opus 5.5 が引き続き優位」 | 料理写真 → 栄養値 JSON は「抽出」寄りのタスク |

## 4. 切替に必要なコード変更（Edge Function のみ、Mobile/Web 変更不要）

優先度 BLOCKS = これをしないと動かない / TUNE = 品質・コスト調整

| # | 種別 | 変更 | 理由 |
| --- | --- | --- | --- |
| 1 | BLOCKS | `model` を `claude-haiku-5-5` に | — |
| 2 | BLOCKS | `temperature: 0.2` を削除 | 非デフォルト値は 400 |
| 3 | BLOCKS | `stop_reason === 'refusal'` を判定し、`EMPTY_RESULT`（または専用コード）にマップ | 現コードは text ブロック不在で `No text in Claude response` → 500 になる |
| 4 | TUNE | `output_config: { effort: 'low' }` を明示し、`max_tokens` を 1024 → 4096 程度に | thinking が `max_tokens` を食い、JSON 出力前に `max_tokens` 停止するリスク。短い抽出タスクは `low` が公式推奨 |
| 5 | TUNE | （任意）`output_config.format` による structured outputs で JSON スキーマ強制 | `extractJson` のコードフェンス剥がし（lessons.md の Haiku 4.5 事例）を根本解消。全モデル対応 |
| 6 | TUNE | （任意）テキストのみルートも `claude-haiku-4-5` → `claude-haiku-5-5` | 同じ変更で約 1/10 のコスト、命令追従も向上。Haiku 4.5 のキャッシュ最小 4096 問題も解消 |
| 7 | TUNE | `ai_estimation_logs` に `model`, `input_tokens`, `output_tokens`, `cache_read_input_tokens` を追加し `data.usage` を保存 | A/B と本番コスト集計（料金提案書 §5-3）の前提。スキーマ変更のため Web 型 / Mobile モデルへの影響確認が必要（Edge Function 以外は参照していない見込み） |
| 8 | TUNE | `content`（補足テキスト）に文字数上限（例: 2,000 字）を設ける | 現状は自由文の長さが無制限。Haiku 5.5 の 100K トークン超過レート（§5.1）を構造的に踏めなくするための保険。Mobile 側入力にも同じ上限を置く |

既存コードで **そのまま使える** 点: text ブロックを `type` で検索している（thinking ブロック先頭でも壊れない）、`extractJson` / `validateEstimation` の防御、URL 画像、30s タイムアウト。

## 5. コスト比較（試算）

前提: 150 円/$。画像は Mobile 上限の 1920×1080。テキスト入力は SYSTEM_PROMPT（写真: 588 字 ≈ 550 tok、スクショ: 1,179 字 ≈ 1,100 tok）+ 補足文。出力 JSON ≈ 400 tok。Haiku 5.5 はトークナイザ +30%、画像は高解像度ティア（1920×1080 → 69×39 = 2,691 tok、縮小なし）、thinking ≈ 500 tok（effort low 想定）を加算。Sonnet 4.6 は標準ティア（1456×819 に縮小 → 1,560 tok/枚）。

| ケース | Sonnet 4.6（現状） | Haiku 5.5 | 比率 | 参考: Haiku 4.5（旧提案） |
| --- | --- | --- | --- | --- |
| 料理写真 1 枚 | 入力 2,160 tok + 出力 400 ≈ $0.0125 ≈ **1.9 円** | 入力 3,470 tok + 出力 1,000 ≈ $0.00085 ≈ **0.13 円** | 約 1/15 | ≈ $0.0042 ≈ 0.6 円 |
| 料理写真 3 枚 | 入力 5,280 + 出力 400 ≈ $0.0218 ≈ **3.3 円** | 入力 8,850 + 出力 1,000 ≈ $0.0014 ≈ **0.21 円** | 約 1/16 | ≈ $0.0073 ≈ 1.1 円 |
| スクショ 1 枚 | 入力 2,710 + 出力 400 ≈ $0.0141 ≈ **2.1 円** | 入力 4,190 + 出力 1,000 ≈ $0.0009 ≈ **0.14 円** | 約 1/15 | ≈ $0.0047 ≈ 0.7 円 |
| 1,000 リクエストあたり | 約 1,900〜3,300 円 | 約 130〜210 円 | — | 約 600〜1,100 円 |

注記:
- 単価は 30 倍差だが、画像トークン ×1.7（高解像度ティア）・テキスト ×1.3・thinking 分で実効 1/15 前後に収まる。
- 画像トークン増が気になる場合は Mobile 側で長辺 1456px 程度に縮小すれば Sonnet 4.6 と同じ visual token 数になる（ただし高解像度のまま渡す方がスクショの小文字読み取りには有利）。
- `effort: medium` にすると thinking が増え、出力側が 2〜3 倍になる可能性があるが、それでも 0.3〜0.5 円/回のオーダー。
- Sonnet 5.5（$2 / $10、高解像度ティア、既定 effort high）は同条件で 2〜3 円/回と Sonnet 4.6 とほぼ同コスト。**コスト削減ではなく精度アップグレードの選択肢**として A/B の第 3 アームに入れる価値あり。

### 5.1 100K トークン超過時の高額レート（5 倍）は本件に影響するか

Haiku 5.5 だけは **1 リクエストのプロンプト（入力）が 100,000 トークンを超えると** 入力・出力ともに 5 倍のレートカード（$0.50 / $2.50 per MTok、cache read $0.05）になる。判定はリクエスト単位で、月間累計ではない。入力にはシステムプロンプト・画像・キャッシュ読み取り分がすべて含まれる（公式: Context windows / Pricing「Long context pricing」）。

本件のリクエストサイズ（Haiku 5.5 の新トークナイザ・高解像度ティアで最大側に見積もり）:

| ルート | 入力トークンの上限見積もり | しきい値に対する比率 |
| --- | --- | --- |
| 料理写真 3 枚（Edge Function が `slice(0, 3)` で上限） | 画像 2,691 × 3 = 8,073 + SYSTEM_PROMPT ≈ 720 + 補足文 ≈ 100 → **約 8,900** | 約 9% |
| スクショ 3 枚 | 8,073 + SCREENSHOT_SYSTEM_PROMPT ≈ 1,450 + 100 → **約 9,600** | 約 10% |
| テキストのみ | 720 + 補足文 → **約 1,000** | 約 1% |

結論: **通常運用では 100K を超えることは構造的に起きない**（画像枚数と解像度は Edge Function / Mobile 側で固定されている）。唯一の抜け道は補足テキスト `content` に長さ制限が無いことで、日本語で 15 万字以上を貼り付けないと到達しない。§4-8 の文字数上限で封じるのが安全。

仮に高額レートが適用された場合でも現状より安い:

| ケース | Sonnet 4.6（現状） | Haiku 5.5 通常レート | Haiku 5.5 高額レート（仮） |
| --- | --- | --- | --- |
| 写真 1 枚 | 約 1.9 円 | 約 0.13 円（1/15） | 入力 3,470 × $0.50/M + 出力 1,000 × $2.50/M ≈ $0.0042 ≈ **約 0.63 円（1/3）** |
| 写真 3 枚 | 約 3.3 円 | 約 0.21 円（1/16） | 入力 8,850 × $0.50/M + 出力 1,000 × $2.50/M ≈ $0.0069 ≈ **約 1.0 円（1/3）** |

高額レートでも入力 $0.50 / 出力 $2.50 は Sonnet 4.6 の $3 / $15 に対して 1/6 であり、画像トークン ×1.7・テキスト ×1.3・thinking を乗せても約 1/3 に収まる。

## 6. 精度差の見立て（定性的）

公開ベンチマークで Sonnet 4.6 と Haiku 5.5 を直接比べたものは無い。入手できた数値:

| ベンチマーク（Vision） | Haiku 4.5 | Haiku 5.5 | Sonnet 5.5 | Opus 5.5 | Sonnet 4.6 |
| --- | --- | --- | --- | --- | --- |
| Chartography（no tools、専門チャート読解） | 6.4% | 46.4% | 61.6% | 64.4% | 未公開 |

本タスクに照らした見立て:

- **料理認識・分量推定（写真ルート）**: 最も不確実。Haiku 4.5 比では別物レベルに改善しているが、現行 Sonnet 5.5 には 15pt 差。Sonnet 4.6 は Sonnet 5 → 5.5 の 2 世代前なので「同等」も「数%〜十数% の誤差悪化」もあり得る。複数皿・和食の見分け・大盛り判定などで差が出やすい。
- **他社アプリスクショの数値読み取り**: Haiku 5.5 は 1920×1080 を縮小せずに見られる（Sonnet 4.6 は 1456×819 に縮小）ため、小さい PFC 数字の OCR は **むしろ有利になる可能性**。数値を「そのまま読む」タスクは Haiku の得意領域（抽出）。
- **JSON 形式遵守**: Haiku 4.5 より命令追従が大きく改善（公式）。thinking 既定 ON も有利。structured outputs を併用すればフォーマット崩れはほぼ排除できる。
- **出力のばらつき**: `temperature` 固定ができず adaptive thinking になるため、同一画像でも kcal が毎回わずかに変わる幅は現状より大きくなる可能性。
- **誤拒否**: 安全分類器（`general_harms` 等）の誤検知は食事写真では稀と見込むが、ゼロではないため §4-3 の処理が必要。
- **レイテンシ**: 「Fastest」ティア。thinking 分を含めても Sonnet 4.6 より短くなる見込み。
- **リリース直後（2026-10-07）**: 実運用の知見がまだ無い。

## 7. 推奨する次のアクション（A/B 検証）

1. **評価データの用意**: 既存テスト 45 件のうち画像付きを抽出 + 新規収集で、料理写真 30〜50 件・スクショ 10〜20 件。正解値はオーナー判定（または Sonnet 4.6 出力を基準に目視補正）。
2. **評価スクリプト**: 同一画像・同一プロンプトで 3 アーム（Sonnet 4.6 / Haiku 5.5 effort low・medium / Sonnet 5.5）を実行し、各 `response.usage` を保存。
3. **指標**: kcal 絶対誤差の中央値・p90、PFC 誤差、`foods` 空率（EMPTY_RESULT）、JSON パース失敗率、refusal 件数、レイテンシ、実測コスト/件。「平均」ではなく **誤差の大きい上位 10% の事例** を重点比較。
4. **判断基準（案）**: Haiku 5.5 の kcal 誤差中央値が Sonnet 4.6 比 +10% 以内かつ EMPTY_RESULT 率が悪化しなければ写真ルートを切替。スクショルートは OCR 精度が同等以上なら切替。
5. **実装順**: §4 の 1〜4 + 7（ログ拡張）→ `feature/haiku-5-5-meal-estimation` ブランチで Edge Function 改修 → 評価 → 切替。

## 8. A/B 評価の実施状況（2026-10-09 更新）

評価ハーネスは `evals/meal-estimation/` に用意済み。使い方・判定ルール・制約は同ディレクトリの `README.md`。

| 項目 | 状況 |
| --- | --- |
| ハーネス | 本番 `index.ts` のプロンプトを実行時に読み込み、パース・検証処理は本番の移植。4 アーム（sonnet-4-6-prod / haiku-5-5-low / haiku-5-5-medium / sonnet-5-5-low）。セルフテスト 29/29 |
| スクショ評価データ | 合成 27 件（架空アプリ 3 種、ダークモード・小数・1 日表示・2 枚整合/不整合・非食事画面を含む）。正解値は描画データから自動導出 |
| 料理写真評価データ | 未取得。Nutrition5k（実測カロリー付き、CC BY 4.0）の取得スクリプトはあるが、クラウド環境のネットワークポリシーが `storage.googleapis.com` を拒否 |
| 実行 | 未実施。このセッションに Anthropic API キーが無いため |
| 費用見積もり（スクショ 27 件 × 3 試行 × 4 アーム = 324 回、ローカル概算） | 合計 約 $2.2（約 330 円）。1 回あたり Sonnet 4.6 約 1.8 円、Haiku 5.5 low 約 0.10 円、medium 約 0.18 円、Sonnet 5.5 low 約 2.0 円 |

前提の補正: Mobile の `image_picker` は 1920×1080 の枠に収まるよう縮小する。縦長の iPhone スクショ（1170×2532）は **499×1080** に、縦向きの料理写真は 810×1080 になる。§5 の試算は 1920×1080 を仮定しており、実際の画像トークンはそれより少ない。またスクショは両モデルとも縮小なしで見られるサイズのため、Haiku 5.5 の高解像度ティアの利点はスクショではほぼ生きない。

## 参考リンク

- 公式: [Introducing Claude Haiku 5.5](https://www.anthropic.com/claude-haiku-5-5) / [Model overview](https://platform.claude.com/docs/en/models/haiku-5-5/overview) / [What's new](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5) / [Prompting Claude Haiku 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5)
- 公式: [Pricing](https://platform.claude.com/docs/en/about-claude/pricing) / [Vision（解像度ティアとトークン計算）](https://platform.claude.com/docs/en/build-with-claude/vision) / [Models overview](https://platform.claude.com/docs/en/about-claude/models/overview)
- 第三者: [Vellum: Sonnet 5.5 benchmarks](https://www.vellum.ai/blog/claude-sonnet-5-5-benchmarks-explained)（Chartography の Sonnet 5.5 / Opus 5.5 値）
