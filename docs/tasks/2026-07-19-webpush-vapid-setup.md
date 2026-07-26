# Web Push（VAPID）シークレット設定手順（オーナー作業）

**作成日**: 2026/07/19（フェーズ7.3 通知基盤統一）
**所要時間**: 5分

## 背景

フェーズ7.3 で通知送信を Edge Functions の統一ディスパッチャに集約しました。
トレーナー向け **Web Push（ブラウザ通知）の送信を有効化するには、Edge Functions 側に VAPID シークレットの設定が必要**です。

**未設定の間の挙動**: 通知はモバイル（FCM）のみ送信され、Web Push は自動的にスキップされます（エラーにはなりません）。

## 手順

ルート `FIT-CONNECT/` ディレクトリから以下を実行します。

```bash
supabase secrets set \
  VAPID_PUBLIC_KEY=<公開鍵> \
  VAPID_PRIVATE_KEY=<秘密鍵> \
  VAPID_SUBJECT=mailto:<連絡先メールアドレス>
```

- **値は Vercel に設定済みのものと同じものを使う**こと
  - `VAPID_PUBLIC_KEY` ← Vercel の `NEXT_PUBLIC_VAPID_PUBLIC_KEY`
  - `VAPID_PRIVATE_KEY` ← Vercel の `VAPID_PRIVATE_KEY`
  - 鍵ペアが一致しないと、既存のブラウザ購読への送信がすべて失敗します
- `VAPID_SUBJECT` は `mailto:` 形式の連絡先（例: `mailto:admin@example.com`）

設定後、確認:

```bash
supabase secrets list
```

3つのキーが表示されれば完了です。Edge Functions の再デプロイは不要です（次回実行時から反映）。

## 注意

- **鍵の値をリポジトリにコミットしないこと**（このファイルにも値を書かない）
- 鍵をローテーションする場合は Vercel 側と Edge Functions 側を**同時に**更新すること
