# Sign in with Apple — 外部設定手順（1回きり）

作成日: 2026-07-11
対象: フェーズ6.2「Sign in with Apple」（App Store Guideline 4.8 対応）

アプリ側の実装（`sign_in_with_apple` パッケージ + ネイティブ `signInWithIdToken` 方式）は完了済みです。
以下はプロジェクトオーナーが **Apple Developer Portal** と **Supabase Dashboard** で行う1回きりの設定です。
この設定が完了するまで、アプリの「Appleでサインイン」ボタンは認証エラーになります。

---

## 1. Apple Developer Portal

1. [Apple Developer Portal](https://developer.apple.com/account/) にサインイン
2. **Certificates, Identifiers & Profiles → Identifiers** を開く
3. App ID **`com.fitconnect.fitConnectMobile`** を選択
4. Capabilities 一覧の **「Sign In with Apple」にチェック**を入れて Save
   - 設定は「Enable as a primary App ID」（デフォルト）のままでよい

> **注意（プロビジョニングプロファイル）:**
> App ID の capability を変更すると、既存のプロビジョニングプロファイルは無効（Invalid）になります。
> - Xcode の「Automatically manage signing」を使っている場合: Xcode が自動で再生成するため追加作業は不要（Xcode でプロジェクトを開き直せば OK）
> - 手動管理の場合: Portal の **Profiles** から該当プロファイルを Edit → Save で再生成し、ダウンロードし直すこと
> - CI/CD（App Store 配布用プロファイル等）を使っている場合も同様に再生成が必要

### Services ID / Key は不要

本アプリは **ネイティブ方式**（Apple から直接取得した ID トークンを `signInWithIdToken` で Supabase に渡す方式）のため、
Web 向け OAuth フローで必要になる以下は **作成不要** です:

- Services ID（`com.xxx.signin` のような Web 用識別子）
- Sign in with Apple 用の Key（Secret Key / .p8 ファイル）

## 2. Supabase Dashboard

1. [Supabase Dashboard](https://supabase.com/dashboard) で FIT-CONNECT プロジェクトを開く
2. **Authentication → Sign In / Providers → Apple** を開く
3. **「Enable Sign in with Apple」を ON** にする
4. **Client IDs**（Authorized Client IDs）欄にバンドル ID を入力:
   ```
   com.fitconnect.fitConnectMobile
   ```
5. **Secret Key (for OAuth) は空欄のまま** で Save
   - ネイティブ `signInWithIdToken` 方式のため Services ID / Secret Key は不要（これらは Web OAuth フロー用）

## 3. 動作確認

- **Simulator の場合**: Settings アプリで Apple ID にサインイン済みであること（未サインインだとネイティブダイアログが進まない）
- **実機の場合**: iCloud にサインイン済みの iPhone で確認するのが確実
- 確認手順:
  1. アプリのログイン画面で「Appleでサインイン」をタップ
  2. Face ID / パスコードで承認（初回は氏名・メールの共有設定ダイアログが表示される）
  3. ログイン後、ホーム画面に遷移すればOK
  4. Supabase Dashboard → Authentication → Users に `apple` プロバイダのユーザーが作成されていることを確認

> **補足（初回のみの氏名取得）:** Apple は**初回サインイン時のみ**氏名を返します。
> テストでやり直す場合は、iPhone の 設定 → [自分の名前] → サインインとセキュリティ → Appleでサインイン から
> FIT-CONNECT のApple ID連携を削除すると、再び「初回」として扱われます。

## チェックリスト

- [ ] Apple Developer Portal: App ID に Sign In with Apple capability を有効化
- [ ] （手動管理の場合）プロビジョニングプロファイルを再生成
- [ ] Supabase Dashboard: Apple プロバイダを有効化 + Client IDs にバンドル ID を追加
- [ ] 実機 or Simulator でサインイン動作確認
