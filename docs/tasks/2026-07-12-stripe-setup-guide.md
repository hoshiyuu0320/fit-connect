# Stripe 課金 初回セットアップ手順（オーナー作業）

**作成日**: 2026-07-12
**対象**: プロジェクトオーナー（個人事業主・Stripe アカウント未開設）
**関連実装**: `feature/stripe-billing-core`（フェーズ6.3 PR1: Checkout / Customer Portal / webhook）
**関連ドキュメント**: `docs/tasks/2026-07-11-pro-pricing-proposal.md` §6（導入ロードマップ）・§8（確定価格）

コード側（API Routes・DB・課金画面）は実装済みです。動かすためには、以下の Stripe 側セットアップが
オーナー作業として必要です。**手順1〜6 はすべてテストモードで完結**し、本番アカウント申請（本人確認）
とは独立して進められます。決定事項（§8 判断10）の通り、本番申請は手順1で並行して開始してください。

確定価格（§8。手順2で使用）:

| プラン | 月額（税込） | 顧客数上限 | Stripe Price |
| --- | --- | --- | --- |
| Free | ¥0 | 3人 | 作成不要（DB管理のみ） |
| Pro | ¥2,980 | 10人 | 要作成 → `STRIPE_PRICE_PRO` |
| Business | ¥6,980 | 30人 | 要作成 → `STRIPE_PRICE_BUSINESS` |

> 14日 Pro トライアルは **DB 管理（`trial_ends_at`）で Stripe 非関与**のため、
> Stripe 側にトライアル設定を入れる必要はありません（入れないこと）。

---

## 1. Stripe アカウント作成

- [ ] https://dashboard.stripe.com/register からメールアドレスでアカウント登録する
- [ ] ダッシュボードに入れることを確認する（右上に「テストモード」トグルがある）
- [ ] 本番利用の申請（アカウント有効化）を**並行で開始**する: ダッシュボードの「本番環境利用の申請」から
  事業情報・本人確認書類・銀行口座を提出する

ポイント:

- **テストモードは登録直後から全機能が使える**。本番申請（本人確認・審査）の完了を待つ必要はなく、
  手順2以降はすぐ進められる
- 本番申請はオンライン提出後、通常数日で有効化される。準備物（本人確認書類・事業用銀行口座・
  事業内容の説明・審査対象サイトの要件）は価格提案書 **§6 Phase 1** を参照
- 審査対象サイトには特商法表記（/tokushoho）等が必要。ページ自体は実装済みだが価格が【要記入】のため、
  本番公開前に手順7で記入する

---

## 2. テストモードで Product / Price を作成（Pro / Business の2件）

ダッシュボード右上の**「テストモード」トグルが ON** であることを確認してから作業します。

### 2-1. Pro プラン

1. ダッシュボード → **商品カタログ**（Product catalog）→ **商品を追加**
2. 商品名: `FIT-CONNECT Pro`（説明は任意。例:「顧客10人まで・AI食事解析込み」）
3. 料金（Price）の設定:
   - 金額: **2,980**、通貨: **JPY**
   - 課金体系: **継続（recurring）・月次（Monthly）**
4. **税の設定（重要）**: 料金設定内の「税の処理（Tax behavior）」を **「内税（税込価格 / inclusive）」** に設定する
   - 項目が見当たらない場合は料金欄の「詳細オプション」（その他のオプション）を展開すると表示される
   - ここを既定のままにすると外税扱いになり、表示価格と請求額がずれるため必ず確認すること
5. 保存後、商品詳細画面の料金欄に表示される **API ID（`price_` で始まる文字列）を控える**
   → 手順4の `STRIPE_PRICE_PRO` に使用

### 2-2. Business プラン

1. 同様に **商品を追加** → 商品名: `FIT-CONNECT Business`
2. 金額: **6,980**、通貨: **JPY**、**月次 recurring**、税の処理: **内税（inclusive）**
3. **API ID（`price_...`）を控える** → 手順4の `STRIPE_PRICE_BUSINESS` に使用

- [ ] Pro（¥2,980・JPY・月次・内税）を作成し `price_...` を控えた
- [ ] Business（¥6,980・JPY・月次・内税）を作成し `price_...` を控えた

> Free プランは Stripe に作成しない（¥0 プランは DB の `subscription_plan` のみで管理）。

---

## 3. Customer Portal の有効化

解約・カード変更はアプリ内に画面を持たず、Stripe の Customer Portal に任せる構成です
（`POST /api/billing/portal` がポータルへのリンクを発行する）。有効化しないとポータル遷移が失敗します。

1. ダッシュボード → **設定**（歯車アイコン）→ **Billing** → **Customer Portal**（カスタマーポータル）
2. 以下を許可する:
   - **サブスクリプションのキャンセル**（解約）を有効化
   - **支払い方法の更新**（カード変更）を有効化
3. **保存**（テストモードでは「テスト環境に保存」）

- [ ] Customer Portal で解約・カード変更を許可し保存した

---

## 4. 環境変数の設定（.env.local と Vercel の両方）

必要な環境変数は次の4つです。**ローカル（`fit-connect/.env.local`）と Vercel の両方**に設定します。

### 4-1. `.env.local` への追記（雛形）

`fit-connect/.env.local` に以下を追記します（値は自分の環境のものに置き換え）:

```bash
# Stripe（テストモード）
STRIPE_SECRET_KEY=sk_test_xxxxxxxxxxxx      # ダッシュボード → 開発者 → APIキー → シークレットキー
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxx    # 手順5-1（stripe listen）で取得した値
STRIPE_PRICE_PRO=price_xxxxxxxxxxxx         # 手順2-1で控えた Pro の Price ID
STRIPE_PRICE_BUSINESS=price_xxxxxxxxxxxx    # 手順2-2で控えた Business の Price ID
```

> ⚠️ **キーの値は絶対にこのリポジトリにコミットしないこと。**
> - `.env*` は `.gitignore` 済みだが、別ファイル・ドキュメント・チャットへの貼り付けも禁止
> - `sk_test_` はテスト用だが、本番切替後の `sk_live_` は決済を実行できる最高権限キーになる。
>   取り扱いは Vault の service_role キー（`2026-07-10-cron-vault-setup.md`）と同等の警戒で行うこと

### 4-2. Vercel への設定

1. Vercel ダッシュボード → プロジェクト **fit-connect** → **Settings** → **Environment Variables**
2. 上記4変数を1件ずつ登録する（対象環境は Production。Preview でもテスト決済を試すなら Preview にも）
   - `STRIPE_WEBHOOK_SECRET` には手順5-2（本番用エンドポイント）で取得する `whsec_` を入れる。
     手順5-2 完了後に設定でよい
3. 環境変数はビルド時に読み込まれるため、**設定後に再デプロイ**して反映する

- [ ] `.env.local` に4変数を追記した
- [ ] Vercel に4変数を登録し、再デプロイした

---

## 5. Webhook の設定

webhook（`POST /api/stripe/webhook`）が `trainers.subscription_plan` と `trainer_billing` を
自動更新する要のため、ローカル・本番の両方で必ず設定します。署名検証があるので
`STRIPE_WEBHOOK_SECRET` が実際のエンドポイントと一致していないと全イベントが拒否されます。

### 5-1. ローカル検証用（stripe CLI）

1. stripe CLI をインストールしてログインする:

```bash
brew install stripe/stripe-cli/stripe
stripe login   # ブラウザが開くので許可する
```

2. 開発サーバー（`localhost:3000`）と別のターミナルで転送を起動する:

```bash
stripe listen --forward-to localhost:3000/api/stripe/webhook
```

3. 起動時に表示される **`whsec_...` を `.env.local` の `STRIPE_WEBHOOK_SECRET`** に設定し、
   開発サーバーを再起動する

- [ ] `stripe listen` で取得した `whsec_` を `.env.local` に設定した

> `stripe listen` はローカル検証のたびに起動が必要（起動していない間はローカルに webhook が届かない）。

### 5-2. 本番用（ダッシュボード）

1. ダッシュボード → **開発者** → **Webhook** → **エンドポイントを追加**
2. エンドポイント URL: `https://<本番ドメイン>/api/stripe/webhook`
3. 購読イベントとして以下の**4種**を選択する:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
4. 作成後に表示される**署名シークレット（`whsec_...`）を Vercel の `STRIPE_WEBHOOK_SECRET`** に設定し、
   再デプロイする

- [ ] 本番エンドポイントを4イベントで登録し、`whsec_` を Vercel に設定した

> ⚠️ エンドポイントの `whsec_` は登録先ごとに異なる。ローカル（stripe listen）と本番（ダッシュボード）で
> 別々の値になるため、`.env.local` と Vercel に同じ値を使い回さないこと。

---

## 6. 動作確認チェックリスト（テストモード）

開発サーバー + `stripe listen` を起動した状態で、以下を順に確認します。
テストカードは **`4242 4242 4242 4242`**（有効期限: 未来の任意の年月、CVC: 任意の3桁、名前・住所: 任意）。

- [ ] **アップグレード**: `/settings/billing` から Pro を選択 → Stripe Checkout に遷移し、
  テストカードで決済が完了する
- [ ] **表示変化**: 決済完了後、`/settings/billing` の表示が Free → **Pro に変わる**
  （webhook 経由で `trainers.subscription_plan` / `trainer_billing` が自動更新される。
  数秒待って変わらない場合は `stripe listen` のターミナルでイベント転送と HTTP 200 を確認）
- [ ] **Portal で解約**: `/settings/billing` から Customer Portal を開き、サブスクリプションをキャンセル
  → `/settings/billing` の表示が **Free に降格**する
- [ ] **プロモーションコード**: ダッシュボード → 商品カタログ → **クーポン**でクーポンを作成し
  プロモーションコードを発行 → Checkout 画面に**コード入力欄が表示され、適用で割引される**
  （`allow_promotion_codes` は Checkout 実装側で有効化済み）
- [ ] （任意）Business へのアップグレード / Pro⇄Business の切替も同様に確認する

---

## 7. 本番切替時の TODO

本番アカウント有効化（手順1の申請完了）後、公開前に以下を行います。
詳細チェックリストは価格提案書 **§6 Phase 2** を参照（本手順書では要点のみ）。

- [ ] **本番モードで Product/Price を再作成**する（手順2と同内容。テストモードの設定は本番にコピーされない）
- [ ] `STRIPE_SECRET_KEY` を `sk_live_...` に、`STRIPE_PRICE_PRO` / `STRIPE_PRICE_BUSINESS` を
  本番の Price ID に差し替える（Vercel）
- [ ] **本番モードで webhook エンドポイントを再設定**し（手順5-2と同内容）、新しい `whsec_` に差し替える
- [ ] **特商法ページ（/tokushoho）に確定価格・支払時期/方法・解約条件を記入**する（公開の前提条件）
- [ ] Customer Portal を本番モードでも有効化する（手順3と同内容。設定はモードごとに独立）
- [ ] そのほか §6 Phase 2 の残項目（規約への課金条項反映、領収書メール設定、webhook 失敗監視、
  Mobile 側で価格・購入導線に言及しない建付けの維持）を確認する
