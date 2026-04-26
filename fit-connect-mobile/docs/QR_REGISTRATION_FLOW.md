# QRコード登録フロー

このドキュメントはFIT-CONNECTモバイルアプリのQRコード登録フローを説明します。

## 概要

クライアントがトレーナーのQRコードをスキャンし、アカウント登録を完了するまでのフローです。

---

## フロー図

### 1. アプリ起動時の認証判定

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           アプリ起動 (app.dart)                              │
│                                                                             │
│                    ┌─────────────────────────────┐                          │
│                    │  StreamBuilder<AuthState>   │                          │
│                    │     認証状態チェック          │                          │
│                    └─────────────┬───────────────┘                          │
│                                  │                                          │
│              ┌───────────────────┼───────────────────┐                      │
│              ▼                   │                   ▼                      │
│     ┌─────────────┐              │          ┌─────────────────┐             │
│     │  未認証      │              │          │  認証済み        │             │
│     └──────┬──────┘              │          └────────┬────────┘             │
│            │                     │                   │                      │
│            ▼                     │                   ▼                      │
│  ┌─────────────────┐             │       ┌───────────────────────┐          │
│  │ OnboardingScreen │            │       │  currentClientProvider │          │
│  └─────────────────┘             │       │  クライアントデータ確認   │          │
│                                  │       └───────────┬───────────┘          │
│                                  │                   │                      │
│                                  │    ┌──────────────┼──────────────┐       │
│                                  │    ▼              ▼              ▼       │
│                                  │ client有       client無       client無   │
│                                  │    │       hasTrainer=true hasTrainer=false│
│                                  │    ▼              ▼              ▼       │
│                                  │ MainScreen   Registration   Onboarding  │
│                                  │              CompleteScreen  Screen     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2. 登録フロー詳細

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          登録フロー詳細                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      OnboardingScreen                                │    │
│  │                   「FIT-CONNECTへようこそ」                            │    │
│  │  ┌────────────────────┐    ┌────────────────────┐                   │    │
│  │  │  QRコードをスキャン  │    │  招待コードを入力   │                   │    │
│  │  └─────────┬──────────┘    └─────────┬──────────┘                   │    │
│  └────────────┼─────────────────────────┼──────────────────────────────┘    │
│               │                         │                                   │
│               ▼                         ▼                                   │
│  ┌────────────────────┐    ┌────────────────────┐                          │
│  │   QrScanScreen     │    │  InviteCodeScreen  │                          │
│  │                    │    │                    │                          │
│  │ カメラでQRスキャン    │    │ UUID/短縮コード入力  │                          │
│  │                    │    │                    │                          │
│  │ QR形式:            │    │ 形式:              │                          │
│  │ - fitconnectmobile │    │ - 完全UUID         │                          │
│  │   ://register?     │    │ - 8文字以上16進数   │                          │
│  │   trainer_id=xxx   │    │                    │                          │
│  │ - 直接UUID         │    │                    │                          │
│  └─────────┬──────────┘    └─────────┬──────────┘                          │
│            │                         │                                      │
│            └────────────┬────────────┘                                      │
│                         │                                                   │
│                         ▼                                                   │
│            ┌───────────────────────────┐                                    │
│            │ registrationNotifier      │                                    │
│            │ .fetchTrainerInfo()       │                                    │
│            │                           │                                    │
│            │ Supabase: profiles        │                                    │
│            │ SELECT name, image_url    │                                    │
│            │ WHERE id = trainer_id     │                                    │
│            └─────────────┬─────────────┘                                    │
│                          │                                                  │
│            ┌─────────────┼─────────────┐                                    │
│            ▼             │             ▼                                    │
│      ┌──────────┐        │      ┌──────────────┐                            │
│      │  失敗    │        │      │    成功       │                            │
│      │ SnackBar │        │      │ state更新    │                            │
│      │ エラー表示│        │      │ trainerId    │                            │
│      └──────────┘        │      │ trainerName  │                            │
│                          │      │ trainerImage │                            │
│                          │      └──────┬───────┘                            │
│                          │             │                                    │
│                          │             ▼                                    │
│                          │  ┌───────────────────────┐                       │
│                          │  │ TrainerConfirmScreen  │                       │
│                          │  │                       │                       │
│                          │  │  トレーナー画像        │                       │
│                          │  │  「〇〇さん」         │                       │
│                          │  │                       │                       │
│                          │  │  [このトレーナーで登録] │                       │
│                          │  │  [戻る → clear()]    │                       │
│                          │  └───────────┬───────────┘                       │
│                          │              │                                   │
│                          │              ▼                                   │
│                          │  ┌───────────────────────┐                       │
│                          │  │    LoginScreen        │                       │
│                          │  │  (isRegistration=true)│                       │
│                          │  │                       │                       │
│                          │  │  メールアドレス入力    │                       │
│                          │  │  [認証メールを送信]     │                       │
│                          │  └───────────┬───────────┘                       │
│                          │              │                                   │
│                          │              ▼                                   │
│                          │  ┌───────────────────────┐                       │
│                          │  │  Magic Link 送信      │                       │
│                          │  │  signInWithOtp()     │                       │
│                          │  │                       │                       │
│                          │  │  redirect:           │                       │
│                          │  │  fitconnectmobile:// │                       │
│                          │  │  login-callback      │                       │
│                          │  └───────────────────────┘                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. 認証完了後の処理

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          認証完了後の処理                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌───────────────────────┐                                                  │
│  │  ユーザーのメール受信   │                                                  │
│  │  リンクをタップ         │                                                  │
│  └───────────┬───────────┘                                                  │
│              │                                                              │
│              ▼                                                              │
│  ┌───────────────────────┐                                                  │
│  │  Supabase認証完了      │                                                  │
│  │  AuthState変更検知     │                                                  │
│  └───────────┬───────────┘                                                  │
│              │                                                              │
│              ▼                                                              │
│  ┌───────────────────────────────────┐                                      │
│  │  _AuthLoadingScreen (app.dart)    │                                      │
│  │                                   │                                      │
│  │  client = null                    │                                      │
│  │  registrationState.hasTrainer = true                                     │
│  │                                   │                                      │
│  │  → RegistrationCompleteScreen     │                                      │
│  └───────────┬───────────────────────┘                                      │
│              │                                                              │
│              ▼                                                              │
│  ┌───────────────────────────────────┐                                      │
│  │    RegistrationCompleteScreen     │                                      │
│  │                                   │                                      │
│  │  completeRegistration() 実行       │                                      │
│  │                                   │                                      │
│  │  1. profiles テーブル              │                                      │
│  │     upsert({ id, role: 'client' })│                                      │
│  │                                   │                                      │
│  │  2. clients テーブル               │                                      │
│  │     insert({                      │                                      │
│  │       client_id,                  │                                      │
│  │       trainer_id,                 │                                      │
│  │       name: '新規クライアント'       │                                      │
│  │     })                            │                                      │
│  │                                   │                                      │
│  │  Confetti Animation              │                                      │
│  │  完了メッセージ表示                │                                      │
│  │                                   │                                      │
│  │  [トレーニングを始める]             │                                      │
│  └───────────┬───────────────────────┘                                      │
│              │                                                              │
│              ▼                                                              │
│  ┌───────────────────────┐                                                  │
│  │      MainScreen       │                                                  │
│  │   (pushAndRemoveUntil)│                                                  │
│  │                       │                                                  │
│  │   登録完了!            │                                                  │
│  └───────────────────────┘                                                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 状態管理フロー（RegistrationNotifierProvider）

### RegistrationState

```dart
class RegistrationState {
  final String? trainerId;       // ← fetchTrainerInfo()で設定
  final String? trainerName;     // ← Supabaseから取得
  final String? trainerImageUrl; // ← Supabaseから取得

  bool get hasTrainer => trainerId != null; // 判定用
}
```

### 時系列フロー

```
時系列:
─────────────────────────────────────────────────────────────────
 QRスキャン        トレーナー確認      メール認証       登録完了
─────────────────────────────────────────────────────────────────
     │                  │                 │               │
     ▼                  ▼                 ▼               ▼
fetchTrainerInfo()  state保持      hasTrainer判定  completeRegistration()
     │                  │                 │               │
     ▼                  │                 ▼               ▼
state = {              │          →RegistrationComplete  clear()
 trainerId,            │            Screenへ遷移          │
 trainerName,          │                                  ▼
 trainerImageUrl       │                             state = null
}                      │
─────────────────────────────────────────────────────────────────
```

---

## 画面遷移サマリー

```
OnboardingScreen
    ↓ (Navigator.push)
QrScanScreen / InviteCodeScreen
    ↓ (fetchTrainerInfo → state更新)
TrainerConfirmScreen
    ↓ (Navigator.pushReplacement)
LoginScreen (isRegistration: true)
    ↓ (Magic Link → Supabase認証)
_AuthLoadingScreen (app.dart)
    ↓ (registrationState.hasTrainer判定)
RegistrationCompleteScreen
    ↓ (completeRegistration → profiles/clients作成)
    ↓ (Navigator.pushAndRemoveUntil)
MainScreen
```

---

## データベース操作

| ステップ | テーブル | 操作 | データ |
|---------|---------|------|--------|
| トレーナー情報取得 | profiles | SELECT | id, name, profile_image_url |
| プロフィール作成 | profiles | UPSERT | id, role: 'client' |
| クライアント作成 | clients | INSERT | client_id, trainer_id, name |

---

## 関連ファイル

| ファイル | 役割 |
|---------|------|
| `lib/app.dart` | ルーティング・認証状態判定 |
| `lib/features/auth/presentation/screens/onboarding_screen.dart` | 入口画面 |
| `lib/features/auth/presentation/screens/qr_scan_screen.dart` | QRスキャン |
| `lib/features/auth/presentation/screens/invite_code_screen.dart` | 招待コード入力 |
| `lib/features/auth/presentation/screens/trainer_confirm_screen.dart` | トレーナー確認 |
| `lib/features/auth/presentation/screens/login_screen.dart` | メール認証 |
| `lib/features/auth/presentation/screens/registration_complete_screen.dart` | 登録完了 |
| `lib/features/auth/providers/registration_provider.dart` | 状態管理 |
| `lib/features/auth/data/auth_repository.dart` | 認証処理 |

---

## QRコード形式

### 対応形式

1. **URL形式**
   ```
   fitconnectmobile://register?trainer_id={uuid}
   ```

2. **直接UUID形式**
   ```
   12345678-1234-1234-1234-123456789abc
   ```

### パース処理

```dart
String? parseTrainerIdFromQrCode(String qrContent) {
  final uri = Uri.parse(qrContent);
  if (uri.scheme == 'fitconnectmobile' && uri.host == 'register') {
    return uri.queryParameters['trainer_id']; // URL形式
  }
  if (_isValidUuid(qrContent)) {
    return qrContent; // 直接UUID
  }
  return null;
}
```
