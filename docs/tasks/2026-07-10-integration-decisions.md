# 統合設計判断（Integration Decisions）

> 作成日: 2026-07-10
> 対象: `docs/tasks/2026-07-08-solution-catalog.md`（改善施策カタログ）の横断レビューが指摘した「複数カテゴリが同じ基盤を別々に設計している」5点＋横断標準2点の決定。
> 根拠: 2026-07-10 実施の通知配管・招待コード・テンプレート実装の実コード確認調査。
> **カタログの各施策を実装する際は、本ドキュメントの決定が優先する。**

---

## 前提となる実コード確認結果（2026-07-10 調査）

| 項目 | 事実 |
| --- | --- |
| FCMトークン保存先 | `clients.fcm_token` カラム（**migration 欠落＝スキーマドリフト**）。`notification_service.dart` L212-224。trainers 分岐はデッドコード（呼び出しは常に `'client'` 固定） |
| FCM送信側 | **実装済み**。`supabase/functions/parse-message-tags/index.ts` 内に FCM HTTP v1 直叩き（`sendFCMNotification` L375-503、メッセージ通知 L508-561、目標達成通知 L566-591）。messages INSERT 時のみ発火 |
| トレーナーへの通知 | **実質不達**。トレーナーのFCMトークンを保存するフローが存在せず、Web Push（`/api/push-notify`）は購読保存の配管は生きているが**送信を起動するコードがゼロ** |
| 招待コード | 専用テーブルなし。`trainers.id`（生UUID）をQR/コードとして使用。短縮コードは未対応（`invite_code_screen.dart` にコメントあり） |
| テンプレート | DBテーブルは `ticket_templates` のみ。メッセージ定型文・カルテテンプレートは未実装 |

---

## 判断1: 通知基盤 — `device_tokens` テーブルに最初から倒し、送信を共通ディスパッチャへ集約する

**採用**: カテゴリ6 1-C の将来案を前倒し。カテゴリ2・4 の「`clients.fcm_token` で十分」案は**不採用**。

- **`device_tokens` テーブル新設**: `id, user_id, user_type('client'|'trainer'), platform('ios'|'android'|'web_push'), token, endpoint系(web push用), last_seen_at, created_at`。UNIQUE(user_id, token)。
  - 理由: トレーナーモード（cat6 1-C、1アプリ2ロール）と PC+スマホ併用を見据えると単一カラムでは詰む。3カテゴリが別前提で走る手戻りをここで断つ。
  - 移行: `clients.fcm_token` は当面残し**両書き→両読み→新テーブルのみ**の3段階。既存の `fcm_token` カラム自体が migration 欠落なので、修復パック（フェーズ5）で「カラム追認 + device_tokens 新設」を同時にやる。
- **統一通知ディスパッチャ `supabase/functions/_shared/push.ts`**: `parse-message-tags` 内のベタ書き FCM 送信ロジック（JWT生成含む）をここへ切り出し、Web Push（web-push 相当の送出。Deno では `npm:web-push`）と将来の LINE をバックエンド追加できるインターフェースにする。
  - 既存の `/api/push-notify`（Next.js側）は呼び出し元ゼロが確定したため、**ディスパッチャ完成後に廃止**（購読UI・`push_subscriptions` テーブルは device_tokens(platform='web_push') へ移行）。
- **`notification_preferences` + `notification_logs` を同時新設**:
  - `notification_preferences(user_id, kind, enabled, quiet_hours_start, quiet_hours_end)` — 通知種別ごとの opt-in/out。**各機能の設定画面に個別トグルを散らばらせない**。
  - `notification_logs(id, user_id, kind, dedup_key UNIQUE, sent_at, channel)` — 冪等化はこのテーブルの dedup_key 方式に統一（cat4 の「sessions に sent_at カラム」方式は不採用）。
- **トレーナー向け即時通知**: ディスパッチャ完成までは「届かない前提」で設計。実効経路の第一弾は LINE 通知（cat6 1-A）またはトレーナーモード（1-C）で、これらも device_tokens / ディスパッチャの上に載せる。

## 判断2: テンプレート — `templates(kind)` 1テーブルに統一

**採用**: カテゴリ1自身が提案していた `templates(kind)` 統一案。cat1 3-B `reply_templates`・cat1 7-A `note_templates`・cat6 3-A `message_templates` の3テーブル分立は**不採用**。

- `templates(id, trainer_id, kind('message'|'note'|'broadcast'), title, content, variables jsonb, sort_order, created_at, updated_at)` + RLS（trainer_id = auth.uid()）。
- 変数展開（`{{名前}}` 等）の仕様は cat1 7-A の設計を全 kind 共通で使う。
- `ticket_templates` はドメインが別（回数券の雛形）なので現状維持。ワークアウトの `workout_plans`（テンプレート的用途）も対象外。

## 判断3: 進捗写真・身体計測 — 各1テーブルに統一

- **進捗写真**: cat2 5-A と cat8 8-4-A の二重設計を統合し、単一 `progress_photos(id, client_id, taken_on date, pose('front'|'side'|'back'|'other'), storage_path, weight_kg numeric NULL, note, created_at)`。
  - cat2 案をベースに、cat8 のシェアカード生成（8-1-A）・3Dスキャン調査（8-4-B）は**このテーブルを読み専で消費する**関係に整理。
  - 写真は最初から **private バケット + 署名URL**（判断7の標準に従う。public バケットに置かない）。
- **周囲径・体組成**: cat5 F-2 `body_measurement_records` に一本化（cat8 8-4-B の `body_measurements` は破棄）。体脂肪率・筋肉量は cat5 F-1 のとおり `weight_records` への列追加とし、周囲径のみ別テーブル。

## 判断4: 種目ライブラリ — トレーナー所有で開始、グローバル化は列設計だけ先取り

**採用**: cat6 5-B（trainer_id 所有）で開始。cat8 8-8-B のグローバルマスタ＋overrides 構成は**現段階では不採用**（トレーナー数が少ない initial 期に管理コストだけ増える）。

- `exercise_library(id, trainer_id uuid NULL, name, category, description, video_url, reference_url, created_at)` — **trainer_id を最初から NULL 許容**にし、`NULL = 運営提供のグローバル種目` として将来 seed 投入できる設計（RLS: SELECT は trainer_id IS NULL OR trainer_id = auth.uid()）。
- 着手順は cat6 の推奨どおり: 5-A（`workout_exercises.reference_url` 列追加による参考URL添付＝最速MVP）→ 5-B（ライブラリ化）。8-8-A（AIプラン下書き）はライブラリを前提にプロンプトへ種目候補を注入する。

## 判断5: 紹介コード — Stripe 連動案に一本化、顧客招待の正規化は別タスク

- **トレーナー紹介（トレーナー→トレーナー）**: cat3 5-A（`referral_codes`/`referrals` + Stripe Coupon/Promotion Code 連動）を正とする。cat8 8-7-A の `pro_credit_days`（クレジット日数）方式は**破棄**（Stripe の外に割引台帳を持つと請求と乖離する）。実装は Stripe 課金（cat3 1-A）の後続。
- **顧客招待（トレーナー→顧客）**: 現状の `trainers.id` 生UUID 方式は当面維持。短縮コード化（cat8 8-7-B `invite_codes` テーブル）は、`trainers_select_all` RLS（全認証ユーザーがトレーナー全行を読める）の解消とセットで**セキュリティ改善タスクとして別枠**で扱う。

## 判断6: AI利用ログ — `ai_usage_logs(kind)` に統一

- 新規AI機能（返信候補・AI相談・週次講評・スクショ一括・プラン生成・スタンプ等）のログは、`ai_estimation_logs` を横に増やさず **汎用 `ai_usage_logs(id, trainer_id, client_id NULL, kind, model, input_tokens, output_tokens, estimated_cost_usd, created_at)`** に記録する。
- rate limit 判定・トレーナー横断のコスト集計・予算アラート（月額コストダッシュボード）はこのテーブル1本で行う。既存 `ai_estimation_logs` は当面併存し、将来ビューで統合。
- **各AI施策の実装前に、Pro 月額（価格未定）に対する原価試算をこのログ設計とセットで行うこと**（横断レビュー 1-4 節）。

## 判断7: 横断標準（新規実装が従うべき規約）

1. **`messages.metadata` スキーマレジストリ**: metadata に新キーを足す施策（record_ref / silent / recorded_date / meals[] / broadcast_id / payment_request / schedule_proposal / sticker_id 等）は、`docs/architecture/message-metadata-registry.md`（新設）に **キー名・スキーマ・解釈者（Web/Mobile/parse-message-tags）・旧アプリでのフォールバック描画**を登録してから実装する。parse-message-tags のスキップ分岐は early-return テーブル1箇所に集約。
2. **Storage は private + 署名URL が標準**: 新設バケット（進捗写真・動画・スタンプ・種目動画）はすべて private で作成し、cat7 2-A Phase 0 の「URL/パス両対応ヘルパー」を共有実装として先に用意する。DB には URL でなく storage パスを保存する。
3. **cron は pg_cron の migration 管理 + 失敗監視**: 新設ジョブ（異常検知・週次サマリー・リマインダー・cleanup 等 8本以上）は cat7 5-A の Vault 参照パターンで migration 化し、`cron.job_run_details` の失敗を通知ディスパッチャ経由でトレーナー（運営）に飛ばす監視ジョブを1本設ける。
4. **RLS の CI テスト**: 新規 RLS ポリシー追加時は、anon/authenticated/他人ロールでのアクセス可否を検証する pgTAP or スクリプトテストを `supabase/tests/` に追加する（anon 全開放事故の再発防止）。

---

## この決定が変更するカタログ施策の読み替え表

| カタログ記載 | 読み替え |
| --- | --- |
| cat1 3-B `reply_templates` / cat1 7-A `note_templates` / cat6 3-A `message_templates` | すべて `templates(kind)` |
| cat2 1-B・cat4 リマインダーの「`clients.fcm_token` を読む」 | `device_tokens` を読む（ディスパッチャ経由） |
| cat4 「sessions に reminder_sent_at カラム」 | `notification_logs.dedup_key` 方式 |
| cat8 8-4-A `progress_photos` / 8-4-B `body_measurements` | cat2 5-A `progress_photos` / cat5 F-2 `body_measurement_records` |
| cat8 8-8-B `exercise_library`（グローバル+overrides） | cat6 5-B ベース（trainer_id NULL 許容） |
| cat8 8-7-A `referral_codes`（pro_credit_days） | cat3 5-A（Stripe Promotion Code 連動） |
| 各AI施策の個別ログテーブル | `ai_usage_logs(kind)` |
