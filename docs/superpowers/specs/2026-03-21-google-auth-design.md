# Google認証機能 設計書

**作成日**: 2026-03-21
**ステータス**: 承認済み（レビュー反映済み）

---

## 概要

FIT-CONNECTにGoogle OAuth認証を追加し、Googleアカウントのみで新規登録・ログインを可能にする。

## 要件

- Googleアカウントでログイン・サインアップ両方に対応
- 新規登録時はGoogleの表示名を自動取得（後から設定画面で変更可能）
- 既存のメール/パスワード認証はそのまま維持
- ログイン・サインアップ両ページのGoogleボタンは既存UIを使用（変更なし）

## 認証フロー

### 新規ユーザー（Google）

```
Googleボタン → Google OAuth画面 → /auth/callback
  → supabase.auth.exchangeCodeForSession(code)
  → supabaseAdmin で trainers テーブルに upsert（ON CONFLICT DO NOTHING）
    { id: user.id, name: user_metadata.full_name, email: user.email, profile_image_url: user_metadata.avatar_url }
  → upsert の結果で新規作成かどうか判定
  → 新規: /dashboard?welcome=true へリダイレクト（nextパラメータがあればそちらを優先）
  → ダッシュボードでトースト表示:
    「Googleアカウントの名前で登録しました。設定画面から変更できます」
```

### 既存ユーザー（Google）

```
Googleボタン → Google OAuth画面 → /auth/callback
  → セッション交換
  → upsert → ON CONFLICT DO NOTHING（既存レコード維持）
  → next パラメータ or /dashboard へリダイレクト
```

### 既存フロー（メール/パスワード）

変更なし。

## 変更対象ファイル

### 1. `/src/app/auth/callback/route.ts`（主要変更）

コード交換後にトレーナーレコードの upsert ロジックを追加。

- `supabaseAdmin` を使用（RLSバイパス、既存パターン踏襲）
- **upsert** を使用（`ON CONFLICT (id) DO NOTHING`）。select→insertのレースコンディションを防止
- `user_metadata.full_name` が空の場合、メールアドレスの `@` 前をフォールバック名に使用
- `user_metadata.avatar_url` を `profile_image_url` に設定
- 新規作成時は `?welcome=true` を付与してリダイレクト
- **既存の `next` クエリパラメータを維持**（デフォルト: `/dashboard`）
- **エラーハンドリング**: upsert失敗時は `console.error` でログ出力し、リダイレクトは続行する（セッションは有効なため、ダッシュボードの既存の空状態表示で対応）

### 2. トースト基盤の追加

- **ライブラリ**: `sonner` を採用（軽量、Radix UIと相性良好、設定が最小限）
- **Toaster配置**: `/src/app/(user_console)/layout.tsx` に `<Toaster />` を追加（user_console配下全体で利用可能に）
- 今後の通知機能でも再利用可能

### 3. `/src/app/(user_console)/dashboard/page.tsx`（トースト表示）

- URLパラメータ `welcome=true` を検知
- `sonner` の `toast()` で通知表示
- 表示後にURLからパラメータを除去（`router.replace`）

### 4. UIボタン（変更なし）

ログイン・サインアップページのGoogleボタンは既に配置済み。変更不要。

## 事前設定手順（手動）

### Google Cloud Console

1. Google Cloud Console (https://console.cloud.google.com) でプロジェクトを作成（または既存を使用）
2. 「APIとサービス」→「OAuth同意画面」を設定
   - ユーザータイプ: 外部
   - アプリ名、サポートメール等を入力
3. 「認証情報」→「認証情報を作成」→「OAuth 2.0 クライアントID」
   - アプリケーションの種類: ウェブアプリケーション
   - 承認済みJavaScriptオリジン: `http://localhost:3000`（開発用）、本番ドメイン
   - 承認済みリダイレクトURI: `https://<supabase-project-ref>.supabase.co/auth/v1/callback`
4. Client ID と Client Secret を控える

### Supabase Dashboard

1. Authentication → Providers → Google を有効化
2. 取得した Client ID と Client Secret を入力
3. 保存

## 技術的考慮事項

- `supabaseAdmin`（サービスロールキー）はサーバーサイドのみで使用
- トレーナーレコード作成はコールバック（サーバーサイド）で行うため、RLSの影響を受けない
- 既存のメール/パスワードサインアップフローの`/api/trainers/create`ルートはそのまま維持
- **アカウントリンク**: 同一メールで異なるプロバイダ（Google / email+password）を使用した場合の動作はSupabaseの「User Identity Linking」設定に依存する。Supabase Dashboardで自動リンクの設定を確認すること
