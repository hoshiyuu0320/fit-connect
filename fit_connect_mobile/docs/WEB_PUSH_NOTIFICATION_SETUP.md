# WEBアプリ（トレーナー側）プッシュ通知セットアップ手順

トレーナー向けWEBアプリで、クライアントからのメッセージ受信時にブラウザプッシュ通知を受け取るための実装手順です。

**バックエンド（Edge Function）は対応済み**のため、WEBアプリ側のFCMトークン取得・保存のみ実装が必要です。

---

## 前提条件

- Firebase プロジェクトにWEBアプリが登録済みであること
- Supabase の `trainers` テーブルに `fcm_token` カラムが存在すること（マイグレーション済み）
- Edge Function `parse-message-tags` がデプロイ済みであること

---

## 既存のバックエンド処理（対応済み）

Edge Function `parse-message-tags` は、メッセージINSERT時に以下の処理を行います:

```
クライアントがメッセージ送信
  → messages テーブルに INSERT
  → Database Webhook 発火
  → Edge Function が receiver_type を判定
  → receiver_type === 'trainer' の場合、trainers テーブルから fcm_token を取得
  → FCM HTTP v1 API で通知送信
  → トレーナーのブラウザに通知表示
```

WEBアプリ側で必要なのは、**FCMトークンを取得して `trainers.fcm_token` に保存する**ことだけです。

---

## 実装手順

### 1. Firebase SDK のインストール

```bash
npm install firebase
```

### 2. VAPID Key の取得

1. [Firebase Console](https://console.firebase.google.com/) → 対象プロジェクト
2. **歯車アイコン** → **「プロジェクトの設定」**
3. **「Cloud Messaging」** タブを選択
4. **「ウェブの構成」** セクション → **「ウェブプッシュ証明書」**
5. 「鍵ペアを生成」をクリック（未作成の場合）
6. 表示された **公開鍵（VAPID Key）** をコピー

### 3. Firebase Messaging の初期化とトークン取得

```javascript
import { initializeApp } from 'firebase/app';
import { getMessaging, getToken, onMessage } from 'firebase/messaging';

// Firebase設定（Firebase Console → プロジェクト設定 → 全般 → マイアプリ から取得）
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID",
};

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);

/**
 * ブラウザ通知の権限をリクエストしてFCMトークンを取得する
 */
async function requestNotificationPermission() {
  try {
    const permission = await Notification.requestPermission();

    if (permission !== 'granted') {
      console.log('通知権限が拒否されました');
      return null;
    }

    const token = await getToken(messaging, {
      vapidKey: 'YOUR_VAPID_KEY', // Step 2 で取得した VAPID Key
    });

    console.log('FCM Token:', token);
    return token;
  } catch (error) {
    console.error('FCMトークン取得エラー:', error);
    return null;
  }
}
```

### 4. FCMトークンを Supabase に保存

```javascript
import { supabase } from './supabaseClient'; // 既存のSupabaseクライアント

/**
 * トレーナーのFCMトークンをDBに保存する
 * ログイン後に呼び出す
 */
async function saveTrainerFCMToken(trainerId) {
  const token = await requestNotificationPermission();

  if (!token) return;

  const { error } = await supabase
    .from('trainers')
    .update({ fcm_token: token })
    .eq('id', trainerId);

  if (error) {
    console.error('FCMトークン保存エラー:', error);
  } else {
    console.log('FCMトークン保存完了');
  }
}

/**
 * ログアウト時にFCMトークンを削除する
 */
async function clearTrainerFCMToken(trainerId) {
  const { error } = await supabase
    .from('trainers')
    .update({ fcm_token: null })
    .eq('id', trainerId);

  if (error) {
    console.error('FCMトークン削除エラー:', error);
  }
}
```

### 5. フォアグラウンド通知の処理

ブラウザがアクティブな状態で通知を受信した場合の処理です:

```javascript
/**
 * フォアグラウンドでの通知受信リスナー
 */
onMessage(messaging, (payload) => {
  console.log('フォアグラウンド通知受信:', payload);

  // ブラウザのNotification APIで通知を表示
  if (Notification.permission === 'granted') {
    new Notification(payload.notification?.title || '新しい通知', {
      body: payload.notification?.body || '',
      icon: '/favicon.ico', // アプリアイコンのパス
    });
  }
});
```

### 6. Service Worker の作成（バックグラウンド通知用）

ブラウザがバックグラウンドや閉じている状態でも通知を受信するために必要です。

**ファイル: `public/firebase-messaging-sw.js`**（publicディレクトリ直下に配置）

```javascript
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID",
});

const messaging = firebase.messaging();

// バックグラウンド通知の処理
messaging.onBackgroundMessage((payload) => {
  console.log('バックグラウンド通知受信:', payload);

  const title = payload.notification?.title || '新しい通知';
  const options = {
    body: payload.notification?.body || '',
    icon: '/favicon.ico',
  };

  self.registration.showNotification(title, options);
});
```

> **注意**: `importScripts` のバージョンは使用している Firebase SDK のバージョンに合わせてください。

### 7. 呼び出しタイミング

```javascript
// ログイン成功後
async function onLoginSuccess(trainer) {
  await saveTrainerFCMToken(trainer.id);
}

// ログアウト時
async function onLogout(trainerId) {
  await clearTrainerFCMToken(trainerId);
  await supabase.auth.signOut();
}
```

---

## 通知の動作フロー

```
1. トレーナーがWEBアプリにログイン
2. ブラウザ通知権限をリクエスト → ユーザーが許可
3. FCMトークン取得 → trainers.fcm_token に保存

4. クライアントがモバイルアプリからメッセージ送信
5. messages テーブルに INSERT
6. Database Webhook → Edge Function 発火
7. Edge Function が trainers テーブルから fcm_token を取得
8. FCM HTTP v1 API で通知送信
9. トレーナーのブラウザに通知表示
```

---

## 動作確認

### 確認手順

1. WEBアプリにトレーナーとしてログイン
2. ブラウザの通知権限を許可
3. Supabase Studio → `trainers` テーブルで `fcm_token` に値が入っていることを確認
4. モバイルアプリからクライアントとしてメッセージを送信
5. トレーナーのブラウザに通知が表示されることを確認

### 確認ポイント

| 状態 | 期待される動作 |
|------|--------------|
| ブラウザがアクティブ | `onMessage` リスナーで通知表示 |
| ブラウザがバックグラウンド | Service Worker で通知表示 |
| ブラウザを閉じている | Service Worker で通知表示（ブラウザ完全終了時は不可） |

---

## ブラウザ対応状況

| ブラウザ | Web Push対応 |
|---------|-------------|
| Chrome (Desktop/Android) | 対応 |
| Firefox | 対応 |
| Edge | 対応 |
| Safari (macOS 13+) | 対応 |
| Safari (iOS) | iOS 16.4+ で対応（PWA経由のみ） |

---

## トラブルシューティング

### 通知権限が表示されない
- HTTPS環境（または localhost）でのみ動作します
- ブラウザ設定で通知がブロックされていないか確認

### トークンが取得できない
- VAPID Key が正しいか確認
- Service Worker (`firebase-messaging-sw.js`) が正しく配置されているか確認
- ブラウザのDevTools → Application → Service Workers で登録状況を確認

### 通知が届かない
- Supabase Studio で `trainers.fcm_token` に値が入っているか確認
- Edge Function のログで `[FCM] Notification sent successfully` が出ているか確認
- `[FCM] No FCM token for receiver` → トークン未保存
