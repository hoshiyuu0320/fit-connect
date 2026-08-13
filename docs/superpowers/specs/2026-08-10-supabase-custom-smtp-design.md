# Supabase Auth Custom SMTP 導入 設計書

- 作成日: 2026-08-10
- 対象: FIT-CONNECT モノレポ（Supabase 共有バックエンド / fit-connect-mobile）
- ブランチ: `feature/auth-custom-smtp`

## 1. 背景と問題

Flutter アプリのログイン時に以下のエラーが発生する。

```
AuthApiException(message: email rate limit exceeded,
                 statusCode: 429, code: over_email_send_rate_limit)
```

原因は Supabase Auth（GoTrue）の**組み込みメールサービスの送信レート制限**。組み込みサービスは全無料プロジェクトで共有されるため **1時間あたり2通** に制限されており、ダッシュボードから引き上げできない。Supabase 公式にも本番利用は非推奨と明記されている。

制限は**プロジェクト単位**であり、メールアドレス単位ではない。`user+1@gmail.com` のようなエイリアスを変えても回避できない。

該当コード:

- `fit-connect-mobile/lib/features/auth/data/auth_repository.dart:22` — `signInWithOtp`（マジックリンク方式、`emailRedirectTo: fitconnectmobile://login-callback`）
- `fit-connect-mobile/lib/features/auth/providers/auth_provider.dart:53` — 同上

## 2. 目的（完了条件）

1. 本番の Supabase プロジェクトで認証メールの送信上限が実用水準（100通/時）になっている
2. 送信元が FIT-CONNECT の独自ドメインになり、SPF / DKIM / DMARC がすべて PASS する
3. 認証メールが FIT-CONNECT ブランドの日本語 HTML になっている
4. 日常の開発検証が本番の送信枠を消費しない

## 3. スコープ

### 含む

- Resend を Custom SMTP として Supabase Auth に接続
- 独自ドメイン取得と DNS 認証レコード（SPF / DKIM / DMARC）設定
- マジックリンクメール（既存ユーザー向け）の日本語 HTML テンプレート作成
- 新規登録確認メール（新規ユーザー向け）の日本語 HTML テンプレート作成
- ローカル開発環境（Inbucket）への切り替え手順整備
- 上記の手順書（Runbook）をリポジトリに残す

### 含まない（YAGNI）

- ステージング用 Supabase プロジェクトの新設（1プロジェクト運用を継続）
- パスワード回復・メールアドレス変更のテンプレート — 現在の認証方式（マジックリンク / Google / Apple）では使用されない
- 通知メール（未読ダイジェスト等）の実装 — `docs/tasks/2026-07-08-solution-catalog.md:1280` の別タスク

> **確認済み（2026-08-12）:** Auth ログにより `signInWithOtp` の挙動が確定した。既存ユーザーは `mail_type: magic_link`、**新規ユーザーは `mail_type: confirmation`**。新規登録の顧客には Confirm signup テンプレートが使われるため、当初スコープ外としていた Confirm signup を「含む」へ移した。

## 4. アーキテクチャ

```
【現状】
Flutter signInWithOtp ──> Supabase Auth ──> Supabase共有SMTP ──> ✗ 429 (2通/時)

【変更後（本番）】
Flutter signInWithOtp ──> Supabase Auth ──> Resend SMTP ──> noreply@fit-connect.app
                                            (3,000通/月・100通/日・SPF/DKIM/DMARC認証済み)

【変更後（開発）】
Flutter (ローカル.env) ──> ローカルSupabase ──> Inbucket (localhost:54324) ──> 無制限
```

### 選定理由

| 項目 | 選定 | 理由 |
| --- | --- | --- |
| 配信サービス | Resend | 無料枠3,000通/月。DNS検証が最も簡単。`docs/tasks/2026-07-08-solution-catalog.md:1280` の未読ダイジェスト案も Resend 前提のため将来揃う |
| レジストラ | Cloudflare Registrar | 更新料が原価固定。DNS 反映が速く、DKIM の長い TXT レコードも素直に扱える |
| ドメイン | `fit-connect.app` | プロジェクト名と完全一致。`.app` は HSTS プリロード必須の TLD でフィッシング耐性が高く、メール受信側の評価も良い部類 |
| 送信元 | `noreply@fit-connect.app` | 認証メールのみの送信のため、ルートドメインから送る。受信者から見て素直で信頼されやすい。将来の一斉配信（未読ダイジェスト等）は別サブドメインに分離して認証メールの到達率を守る |
| 環境分離 | 1プロジェクト + ローカル | 2プロジェクト運用はマイグレーション適用と環境変数の二重管理コストが見合わない |

## 5. 責任分担

本作業の中核は Supabase / Resend / DNS の**管理画面操作**であり、Claude は代行しない。

- API キーなどの認証情報入力は Claude の制約上実施しない（キーがリポジトリやコンテキストに残らない点でも安全）
- ドメイン取得・DNS 設定・アカウント設定変更も同様

| 担当 | 成果物 |
| --- | --- |
| Claude（リポジトリ） | メールテンプレート HTML、`supabase/config.toml` のローカル設定、Runbook、`docs/tasks/` への記録 |
| ユーザー（管理画面） | ドメイン取得、Resend 登録、DNS レコード追加、Supabase の SMTP 設定・レート制限、テンプレート貼り付け |

### 重要な制約

`supabase/config.toml` に記述するメールテンプレート設定とレート制限は **ローカル開発環境にのみ適用される**。本番（リモートプロジェクト `viribpvnpgtgtmeulcmx`）へはダッシュボードから設定する必要がある。したがってテンプレートはリポジトリに HTML として保持しつつ、本番反映は Runbook の手順で行う二段構えとする。

## 6. 実施手順

所要: 1〜2時間 + DNS 伝播待ち（通常10分程度、最大24時間）

### Step 1: ドメイン取得（ユーザー）

Cloudflare Registrar で **`fit-connect.app`** を取得する（年 $14 前後）。2026-08-10 時点で RDAP により空きを確認済み。

`fitconnect.com` / `fit-connect.com` / `fitconnect.io` / `fitconnect.co` / `fitconnect.me` はいずれも登録済み。うち `fitconnect.com` と `fitconnect.co` は afternic のネームサーバーで転売業者の保有のため、取得には高額な交渉が必要となる。

`fitconnect.jp` も空いていたが、**Cloudflare Registrar は `.jp` を取り扱っていない**ため、選定から外した。将来国内向けに `.jp` を併用する場合は お名前.com 等で取得し、ネームサーバーを Cloudflare に向ける構成になる。

### Step 2: Resend 登録（ユーザー）

1. Resend にサインアップ
2. Domains → Add domain
   - Name: `fit-connect.app`（ルートドメイン。サブドメインは付けない）
   - Region: `Tokyo (ap-northeast-1)`
   - Advanced options → Custom Return-Path: `send`（デフォルトのまま）
   - Tracking Subdomain: **空欄のまま**（クリック追跡を無効化するため）
3. API Keys で送信専用キーを1本発行（Sending access のみ）

> **Custom Return-Path の `send` は Return-Path（バウンス受信）用のサブドメインであり、送信元アドレスのサブドメインではない。** Name にルートドメインを指定した場合、送信元は `noreply@fit-connect.app` になり、DNS レコードのみが `send.fit-connect.app` 配下に作られる。

> **クリック追跡を無効にする理由:** 有効だとメール内のリンクが Resend の追跡 URL に書き換えられる。企業のメールセキュリティスキャナがリンクを事前アクセスした時点でマジックリンクのワンタイムトークンが消費され、ユーザーがクリックしたときには既に無効、という事故になる。
>
> Resend の UI では Tracking Subdomain が空欄だと Tracking options が操作不可（グレーアウト）になり、Enable click tracking はオン表示のままとなる。書き換えたリンクをホストするサブドメインが存在しないため追跡は動作しないが、**実際の挙動は検証手順6で確認する。**

### Step 3: DNS レコード追加（ユーザー）

Resend の Domains 画面が表示する値を Cloudflare DNS に登録する。

| レコード | ホスト | 目的 |
| --- | --- | --- |
| MX | `send` | バウンス受信（Return-Path） |
| TXT (SPF) | `send` | 送信元が正規であることの宣言 |
| TXT (DKIM) | `resend._domainkey` | 電子署名による改ざん検知 |
| TXT (DMARC) | `_dmarc` | SPF/DKIM 検証失敗時の扱いを指定（`v=DMARC1; p=none;`） |

ホスト名はいずれも `fit-connect.app` からの相対表記（Cloudflare の DNS 画面はこの形式で入力する）。

DMARC は Resend の必須項目ではないが、2024年以降 Gmail / Yahoo が送信者要件として実質必須化しているため最初から設定する。

Cloudflare で TXT/MX を登録する際は **Proxy status を DNS only にする**（オレンジ雲をオフ）。

完了条件: Resend の Domains 画面で全レコードが `Verified` になること。

> **DNS を登録しただけでは Verified にならない。** Resend の Domains 画面で明示的に **Verify** を実行する必要がある。未検証のまま Step 4 に進むと、送信時に Resend が SMTP レベルで 550 を返し、Supabase 側は `500 unexpected_failure` / `Error sending confirmation email` になる（2026-08-12 に実際に発生）。
>
> 未検証かどうかは、API キー作成画面の Domain ドロップダウンにドメインが出てこないことでも判別できる。

### Step 4: Supabase 設定（ユーザー）

**4-1. Authentication → SMTP Settings**

| 項目 | 値 |
| --- | --- |
| Enable Custom SMTP | ON |
| Host | `smtp.resend.com` |
| Port | `465` |
| Username | `resend` |
| Password | Step 2 で発行した Resend API キー |
| Sender email | `noreply@fit-connect.app` |
| Sender name | `FIT-CONNECT` |

**4-2. Authentication → Rate Limits**

「Rate limit for sending emails」を **100通/時** に設定する。

> **注意:** Custom SMTP を有効にしただけでは上限は無制限にならない。デフォルトが 30通/時 に切り替わるだけなので、この 4-2 を飛ばすと「2通/時が30通/時になっただけ」で終わる。
>
> Resend 無料枠は 100通/日 のため、時間上限をこれ以上上げても日次上限で頭打ちになる。

**4-3. Authentication → Emails → Templates**

Step 5 で作成した HTML を2枚とも貼り付ける。この 4-3 のみ Step 5 の完了後に実施する（4-1 / 4-2 は Step 5 を待たずに進めてよい）。

| テンプレート | Subject | 貼り付ける HTML |
| --- | --- | --- |
| Magic link or OTP | `FIT-CONNECT ログインリンク` | `supabase/templates/magic_link.html` |
| Confirm signup | `FIT-CONNECT アカウント登録の確認` | `supabase/templates/confirmation.html` |

Confirm signup を飛ばすと、新規登録の顧客だけ英語のデフォルトメールを受け取ることになる。

### Step 5: テンプレート作成（Claude）

`supabase/templates/magic_link.html`（既存ユーザー向け）と `supabase/templates/confirmation.html`（新規ユーザー向け）を作成する。2枚は同一デザインで、本文コピーのみ書き分ける。

共通仕様:

- FIT-CONNECT のブランドカラー `#2563EB`（`AppColors.primary`）を使用
- 日本語。本文はアクションボタン、有効期限の明示、URL フォールバック、心当たりがない場合の案内
- テーブルレイアウト + インライン CSS（Gmail は `<style>` ブロックを除去するため）
- 変数は `{{ .ConfirmationURL }}` を使用
- ダークモードでも判読できる配色（背景色を明示指定）

書き分け:

| | magic_link.html | confirmation.html |
| --- | --- | --- |
| 見出し | ログインリンクのご案内 | アカウント登録の確認 |
| 挨拶 | いつも FIT-CONNECT をご利用いただき… | FIT-CONNECT にご登録いただき… |
| ボタン | ログインする | 登録を完了する |
| 末尾 | リンクを開かない限りアカウントに影響はありません | リンクを開かない限りアカウントは作成されません |

`supabase/config.toml` に以下を追記し、ローカル環境へ自動適用する。

```toml
[auth.email.template.magic_link]
subject = "FIT-CONNECT ログインリンク"
content_path = "./supabase/templates/magic_link.html"

[auth.email.template.confirmation]
subject = "FIT-CONNECT アカウント登録の確認"
content_path = "./supabase/templates/confirmation.html"
```

有効期限の文言（「発行から1時間」）は Authentication → Sign In / Providers → Email の **Email OTP expiration** と一致させること。初期値は `86400`（24時間）なので `3600` へ変更する（検証手順7）。

### Step 6: ローカル開発環境への切り替え（Claude が手順化、ユーザーが実行）

`supabase start` でローカルスタックを起動し、`fit-connect-mobile/assets/.env` の `SUPABASE_URL` / `SUPABASE_ANON_KEY` をローカル値に向ける。送信メールは Inbucket（http://localhost:54324）で確認する。本番の送信枠を消費しない。

`.env` の書き換えはユーザーが行う（CLAUDE.md の「`.env` は参照しない」ルールに従う）。

## 7. 検証

> **2026-08-13 時点で全項目完了。** 実測結果は各項目に記載。

1. ✅ **Resend の Domains が `Verified`** — 2026-08-13 00:18 に Domain verified。DNS 4件（MX/SPF/DKIM/DMARC）は `dig` で解決を確認済み
2. ✅ **メールが届く** — auth_logs の `/otp` が 15:22〜15:28 の4件すべて `status 200`、500 はゼロ
3. ✅ **SPF / DKIM / DMARC がすべて `PASS`** — Gmail の「元のメッセージ」で確認。From は `FIT-CONNECT <noreply@fit-connect.app>`、DKIM 署名ドメインも `fit-connect.app` で整合
4. ✅ **429 が発生しない** — 修正後の連続送信で `over_email_send_rate_limit` はゼロ。レート制限の変更は auth_logs にも `2/1h → 30 → 100` として記録されている
5. ✅ **日本語メールからログイン完了** — マジックリンク・登録確認の両方で `fitconnectmobile://login-callback` へ遷移しログイン成功
6. ✅ **新規ユーザー向けテンプレート** — auth_logs の `mail_type` で確定（既存 = `magic_link` / 新規 = `confirmation`）。両方を日本語化して適用済み
7. ✅ **有効期限の記述が実態と一致** — 初期値は `86400`（24時間）でテンプレートの「1時間」と不一致だった。`3600` に変更し、`get_advisors` の `auth_otp_long_expiry` 警告が消えたことも確認
8. ✅ **リンクが書き換えられていない** — 受信メールのリンク先は `https://viribpvnpgtgtmeulcmx.supabase.co/auth/v1/verify?...`。Resend の追跡ドメインは経由していない

## 8. ロールバック

Supabase ダッシュボードの Custom SMTP トグルを OFF にすれば即座に組み込みメールへ戻る（2通/時に戻るのみ、データ影響なし）。

既存ユーザーへの影響はない。送信元アドレスが変わるだけで、認証フロー・セッション・DB スキーマはいずれも変更しない。

## 9. 費用

| 項目 | 費用 |
| --- | --- |
| `fit-connect.app`（Cloudflare Registrar） | 年 $14 前後 |
| Resend | 無料枠（3,000通/月・100通/日）で足りる。超過時は $20/月で 50,000通 |
| Supabase | 変更なし |

## 10. 実装分担

CLAUDE.md の方針に従い、Claude は直接実装せずサブエージェントへ委託する。

| タスク | 担当エージェント |
| --- | --- |
| `supabase/templates/magic_link.html` 作成 | supabase |
| `supabase/config.toml` 追記 | supabase |
| Runbook（`docs/tasks/`）作成 | supabase |
