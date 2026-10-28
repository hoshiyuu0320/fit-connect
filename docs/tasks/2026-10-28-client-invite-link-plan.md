# 顧客招待リンク（Web → ストア → インストール → 登録 → トレーナー紐付け）実装計画

> 作成日: 2026-10-28 / 対象: Web（fit-connect/）・Mobile（fit-connect-mobile/）・共有 supabase/
> 前提資料: `docs/tasks/2026-07-08-solution-catalog.md` 8-7-B（L1964-1972）、`docs/tasks/2026-07-10-integration-decisions.md` 判断5（L58-61）、`docs/tasks/lessons.md`
> 状態: 計画のみ。コードは未着手。§9 のうち D1・D4・D5・D11 はオーナー決定済み（2026-10-28、いずれも推奨案）。残りの論点は推奨案で進め、異論があれば見直す
> 改訂: 初版を作ったあと、コード上の事実（Mobile・DB・Web）、外部の仕様、設計の穴を別々のエージェントで検証し、その指摘を反映した（2026-10-28）

---

## 0. 結論（要約）

- **方式: 自前で作る**（§2）。招待リンクは Web の公開ページ `/invite/<コード>` です。アプリが入っていれば Universal Links / App Links でアプリを直接開き、入っていなければそのページでストアへ案内します。インストール後は、もう一度リンクを開くか、ページに大きく出ているコードを入力してもらいます。Android のインストール元の情報（Install Referrer）による自動の引き継ぎは**段階2**（Play で公開した後）に回します。Branch などの外部サービスは使いません。
- **段階1で、招待コード（invite_codes）の導入と、古い紐付け経路の封鎖を一緒に行う**（§3）。今は誰でも、ログインさえすれば任意のトレーナーに `clients` 行を INSERT できます。このままでは、コードに期限や回数の制限を付けても、その経路で迂回できてしまいます。顧客の行を作っている箇所はアプリの `registration_provider.dart:177` の1か所だけで、アプリもまだストアに出ていません。そのため、封鎖の影響は小さいです。判断5（「UUID 方式は当面維持し、招待コード化は別枠で」）を変えることになるため、オーナーの承認を得ました（論点 D1、2026-10-28 決定）。
- **範囲の広い `trainers_select_all` の解消（未ログインでも全トレーナーの全列が読める状態）は段階3**（別枠のセキュリティタスク）に残します。
- **招待リンクのホストを先に決める必要があります。** `.well-known` のファイルをそのホストに置き、配ったリンクもそのホストに残り続けるためです。トレーナー Web を移さずに済む招待専用のホストにすることが決まりました（論点 D5、2026-10-28 決定。名前は DNS 設定時に確定）。
- **検証で見つかった既存の不具合を3件、別に起票します**（§1-6）。①オフラインで起動すると、登録済みの顧客までサインアウトされる。②トレーナーが同じアカウントで顧客として登録し、その後アプリの「アカウント削除」を押すと、全顧客のデータが消える。③マジックリンクを別の端末で開くと、ログインできない。

---

## 1. 実コードで確認した事実（file:line）

### 1-1. Mobile の登録フロー

- [x] Mobile のモデルは `lib/shared/models/` ではなく `lib/features/auth/models/`（`client_model.dart` / `trainer_model.dart`）にあります。`lib/shared/models/` には `period_filter.dart` しかありません。
- [x] **画面の流れ**: welcome（`welcome_screen.dart:107-112`）→ onboarding（`onboarding_screen.dart:87-111`）→ invite_code / qr_scan → TrainerConfirm（pushReplacement）→ `LoginScreen(isRegistration: true)`（`trainer_confirm_screen.dart:131-141`）→ signedIn で popUntil(isFirst)（`login_screen.dart:54-59`）→ `app.dart:303` の分岐で ProfileSetup → `completeRegistration()`（`profile_setup_screen.dart:122`）→ RegistrationComplete → `clear()`（`onboarding_flow_screen.dart:85`）。ログインはトレーナー確認の後です。
- [x] **トレーナー情報の取得先は `profiles` ではなく `trainers` です**（`registration_provider.dart:133-137`。`id, name, profile_image_url` を取得）。`docs/QR_REGISTRATION_FLOW.md` の L81・L163・L242・L253・L254 にある「profiles」は古い記述です。
- [x] **紐付けは端末から直接 upsert しています**（`registration_provider.dart:177-185`。`onConflict: 'client_id'`、age / gender が null ならキーごと省く、name が空なら '新規クライアント'）。上限超過は `CLIENT_LIMIT_REACHED` の文字列で判定しています（L188-190）。clients を作った後に画像のアップロードなどが続きます（L196-206）。
- [x] **ルーティングは `hasTrainer => trainerId != null`（`registration_provider.dart:70`）で決まります。** `app.dart:300-311` の流れは「clients 行あり → Main」「isRegistrationComplete → 完了画面」「hasTrainer → ProfileSetup」「それ以外 → `_signOutStaleSessionIfNeeded()`（L254-267）で**サインアウト**」です。error 分岐（L337-345）も同じで、朝ダイアログの抑止（L169-172）も hasTrainer を見ています。`completeRegistration` は trainerId が null なら例外を投げます（L164-167）。
- [x] **trainerId はメモリ上の state だけで、永続化していません**（`@Riverpod(keepAlive: true)`、`build()` は同期で const を返す。L75-78）。マジックリンクを待つ間にアプリが kill されると、戻ってきた時点で「セッションあり・clients 行なし・hasTrainer=false」になり、サインアウトされます。
- [x] `MaterialApp` は `home:` だけで、navigatorKey・routes・onGenerateRoute はありません（`app.dart:31-57`）。
- [x] 招待コード画面（`invite_code_screen.dart`）は、UUID（L83-89）のほかに `^[0-9a-f]{8,}$` を「短縮コード」として `trainers.id` に照会しています（L94-102。実際には必ず失敗します）。validator は正規化前の長さで判定し（L198-206）、`textCapitalization` は none（L183）です。エラー表示は「トレーナーが見つかりませんでした」の1種類だけです（L59-68。QR 画面も L75-84 で同じ）。
- [x] QR の解析は `parseTrainerIdFromQrCode`（`registration_provider.dart:227-242`。`fitconnectmobile://register?trainer_id=` と生 UUID）で、`qr_scan_screen.dart:52` から呼ばれます。
- [x] マジックリンクの戻り先は `fitconnectmobile://login-callback`（`auth_repository.dart:25` / `auth_provider.dart:56`）、方式は PKCE です（`supabase_service.dart:19`）。Google / Apple は `signInWithIdToken` で、アプリの外へ遷移しません。

### 1-2. Mobile のネイティブ設定・パッケージ

- [x] **Android**: applicationId は `com.fitconnect.fit_connect_mobile`（`build.gradle.kts:25`）。**release ビルドは debug 鍵で署名されています**（L39）。intent-filter は custom scheme の `fitconnectmobile` / `login-callback` だけです（`AndroidManifest.xml:37-44`）。`launchMode="singleTop"`、`taskAffinity=""`（L17-18）。
- [x] **iOS**: Team ID は `HNKWT8DU57`（`project.pbxproj:502,686,710`）、Bundle ID は `com.fitconnect.fitConnectMobile`（L509,693,717）。Debug / Profile は `Runner.entitlements`、Release は `RunnerRelease.entitlements` を使います（L500,684,708）。entitlements にあるのは aps / applesignin / healthkit だけで、Associated Domains はありません。
- [x] **iOS は UIScene ライフサイクルで動いています**（`Info.plist:61-81` の `FlutterSceneDelegate`、`AppDelegate.swift:5` の `FlutterImplicitEngineDelegate`）。URL も Universal Link も scene delegate 経由で届きます。lessons L225 には、firebase_messaging が UIScene に対応しておらず黙って動かなかった前例があります。
- [x] **リンク受信のパッケージ**: `app_links 6.4.1` が supabase_flutter 2.12.0 の推移的依存として入っています（`pubspec.lock:44-51, 1399-1406`）。アプリ側でリンクを購読するコードはありません。
  - app_links が UISceneDelegate に対応したのは **7.0.0** です（issue #209。Flutter 3.38.1 以上が必要）。7.1 以降は Flutter 3.44 以上が必要で、Flutter は 3.41.9 に固定されています（`.fvmrc`）。
  - supabase_flutter 2.12.0 は app_links を `^6.2.0`（7 未満）に制約しています。2.12.1 以降は `>=6.2.0 <8.0.0` です。
  - Flutter 3.41.9 のエンジンは、scene 接続時の userActivity を旧来型のプラグインに渡しません。そのため、**6 系のままでは、アプリが起動していない状態から Universal Link を開いたときに取りこぼす可能性が高いです**（要実機確認）。
- [x] **supabase_flutter のリンク処理**: v2.12.0 の `supabase_auth.dart` の `_isAuthCallbackDeeplink` は、PKCE ならクエリに `code` を含むもの、または fragment に `error_description` を含むものを auth コールバックとして扱います（scheme と host は見ません）。それ以外は何もせず素通しします。リンクは `uriLinkStream` で受け取り、`Supabase.initialize`（`main.dart:22`、runApp より前）で最初に購読します。初期リンクは最初の購読者にしか流れないので（app_links 6.0.0 の changelog）、**アプリ側は `getInitialLink()` を必ず併用し、同じリンクを二重に処理しないようにする必要があります**。招待 URL には `?code=` も `#error_description` も付けません。
- [x] Flutter 3.27 以降は Flutter 自身の deep linking（`FlutterDeepLinkingEnabled`）が既定で有効です。app_links を使う場合は false にするよう案内されています。home: だけの MaterialApp では、`/invite/...` をルートとして push しようとして失敗します。
- [x] Install Referrer のパッケージはまだ入っていません。`android_play_install_referrer` は discontinued で、後継の `play_install_referrer` は 0.6.0 が Flutter 3.44 以上を要求します。**0.5.0（Flutter 3.29 以上）なら使えます。**
- [x] iOS 16 以降は、Flutter の `Clipboard.getData` をボタンから呼んでも、毎回「ペーストを許可」のダイアログが出ます（プログラムからの読み取りと見なされるため。`UIPasteControl` や入力欄の標準の貼り付けでは出ません）。`Clipboard.hasStrings()` ではダイアログは出ません。
- [x] ストア URL を入れる場所は `app_config.ios_store_url / android_store_url` です（`20260829000100_create_app_config.sql:17-26`。anon / authenticated が SELECT できる。L72-87）。オーナー作業としてタスクにあるのは ios だけで（`IMPLEMENTATION_TASKS.md:443`）、android のタスクはありません。

### 1-3. DB（RLS・トリガー・権限）

- [x] **`trainers_select_all` は `FOR SELECT USING (true)` で、TO 句がありません**（`20260131000001_migrate_profiles_to_trainers.sql:77-80`）。テーブル単位の SELECT GRANT もあるため、anon を含む全ロールが、全トレーナーの全列（email `20260131000001:13`・fcm_token `20260710010002:19`・subscription_plan・trial_ends_at `20260712000000:62`・is_online / last_seen_at `20260307122114:2-3`）を読めます。anon への GRANT は SELECT 以外（DELETE / TRUNCATE など）も残っています。
- [x] **clients の INSERT**: ポリシー `clients_insert_own` は `WITH CHECK (client_id = auth.uid())` だけで、trainer_id を縛っていません（`20260201120000_add_clients_insert_policy.sql:8-12`）。列の GRANT は `(client_id, trainer_id, name, email, age, gender)` です（`20260922000200_column_write_guards.sql:729-731`）。**ログインしていれば誰でも、任意のトレーナーに紐付く行を作れます**（条件は、そのトレーナーが存在して上限内であることだけ）。
- [x] **clients の列**: NOT NULL で既定値が無いのは name だけです。age は `DEFAULT 25 NOT NULL`（CHECK 0〜150）、gender は `DEFAULT 'other' NOT NULL`（CHECK male / female / other）です（`20251230131753_remote_schema.sql:192-215`）。**NULL を明示して INSERT すると 23502 で失敗します。**
- [x] **列ガード**: 顧客は trainer_id を変えられません（同じ値の再送だけ許可。`column_write_guards.sql:370-383`）。ただし、DEFINER の関数の中（current_user=postgres）では素通しされます（L350-352）。
- [x] **顧客数上限のトリガー** `enforce_client_limit()`: SECURITY DEFINER で、`BEFORE INSERT OR UPDATE OF trainer_id` に設定されています。上限は free=3 / pro=10 / business=30 で、トライアル中は pro 扱いです（`20260712100000_enforce_client_limit.sql:35-122`）。**超えたときの DETAIL に trainer_id・plan・limit・current が入り**（L94-100）、PostgREST はこれをそのまま返します。ロックを取らずに数えるので、同時に登録すると上限をすり抜けることがあり、既知の限界として書かれています（L18-23）。search_path の固定は `20260923000000:630` です。本体の md5 は `20260923000000:344` と `function_search_path_privileges_test.sql:1724` で固定されているので、本体を書き換えると両方が落ちます。
- [x] **既存の権限テストは、固定の関数リストだけを検査しています**（`function_search_path_privileges_test.sql:1717-1727` は9本、`definer_functions_privileges_test.sql:1004-1009` は4本）。新しい関数を足しても落ちません。新関数の検査は新しいテストに持たせます。
- [x] **pgcrypto は `extensions` スキーマにあります**（`remote_schema.sql:33`）。`SET search_path = ''` の関数では `extensions.gen_random_bytes` と完全修飾しないと、実行時に 42883 で失敗します（plpgsql は作成時にこれを検査しないので、migration は通ってしまいます）。
- [x] **アバター**: `profile-images` は anon にも署名 URL の作成を許可しています（`20260830000000_profile_images_anon_select.sql:15-19`）。ただし `trainers.profile_image_url` には3つの形式が混ざっています。①`${trainerId}/${timestamp}_${safeName}#元ファイル名`（`uploadProfileImage.ts:30,44`）、②古い行のフルの public URL（`storagePaths.ts:6-8`）、③Web の OAuth ログインで入る Google の外部 URL（`auth/callback/route.ts:47-57`）。①と②には trainer_id が含まれます。
- [x] migration の最新は `20261004000000_client_alert_push.sql` です。新しい版は、引き渡し直前に `supabase migration list --linked` で確かめます（lessons L354, L555）。

### 1-4. Web

- [x] **認証によるリダイレクトはどこにもありません。** middleware はセッションを更新するだけで（`middleware.ts:34`、matcher L48）、`(user_console)/layout.tsx:107-109` は未読数を取るときに未ログインなら何もしないだけです。/login への遷移は settings 配下の各ページにしかありません。したがって `/invite/[code]` は未ログインでも表示できます（前例は `(legal)`）。
- [x] **公開 URL**: `siteConfig.url = NEXT_PUBLIC_APP_URL ?? 'https://fit-connect.vercel.app'`（`siteConfig.ts:8`）。この値を主に使っているのは metadataBase（`layout.tsx:9`）・sitemap・robots です。billing は origin ヘッダーを優先し、この値はフォールバックにすぎません（`api/billing/checkout/route.ts:10-15`）。
- [x] **Web のログインは `${location.origin}/auth/callback` に戻ります**（`(auth)/login/page.tsx:45`、`signup/page.tsx:34,89`）。Supabase の Redirect URLs に無いドメインだと、Site URL の `fitconnectmobile://login-callback`（`config.toml:41`）に飛ばされます。Web Push の購読もオリジンごとです（`NotificationSection.tsx:264`）。**トレーナー Web のドメインを移すと、ログインと通知に影響が出ます。**
- [x] **Web の OAuth ログインは、そのたびに trainers 行を upsert します**（`auth/callback/route.ts:47-57`、ignoreDuplicates）。そのため、顧客が一度 Web に Google でログインすると trainers 行ができます。
- [x] **GA4 はルートレイアウトで全ページに読み込まれます**（`layout.tsx:4,45,51`。計測 ID は未設定。`IMPLEMENTATION_TASKS.md:219`）。ID を入れると、`/invite/<コード>` の URL も Google に送られます。
- [x] サーバー側で使える anon の Supabase クライアントは `src/lib/supabase.ts:7-9` です（Cookie を使わない）。署名 URL の既存実装 `signedStorageUrls.ts` は `'use client'` なので、Server Component から import すると next build が落ちます（lessons L240-244）。`storagePaths.ts` はサーバーでも使える純関数です。`next.config.ts:5-14` の `images.remotePatterns` は本番の Supabase と lh3 だけです。
- [x] 招待モーダル（`ClientInviteModal.tsx`）では、trainerId を QR・表示・コピー（L78・L85 のフォールバック・L145・L160）に使っています。L39 は getClientCount 用なので props は残します。「QRコードをダウンロード」もあります（L95-104）。
- [x] TypeScript の `**` はドットで始まるディレクトリに一致しないので、`src/app/.well-known/**` は `tsc --noEmit` の対象から漏れます（tsconfig の include の追加か、`next build` での確認が必要）。
- [x] 内蔵ブラウザの QA ツール（`chrome-web-qa`）では UA を上書きできません（`SKILL.md:197-215`）。
- [x] Vercel の本番は main で、develop は Preview（Vercel 認証で保護）です。本番の最後のデプロイは 2026-04-26 です（lessons L679-682）。Preview には Apple / Google が `.well-known` を取りに来られないので、Universal Links / App Links の通しの検証は本番のホストでしかできません。
- [x] `fit-connect.app` は Cloudflare Registrar で取得し、DNS も Cloudflare にあります（メール用のレコードあり）。

### 1-5. 外部の仕様

- Firebase Dynamic Links は 2025-08 に終了しています。
- **AASA**: インストール時に Apple の CDN 経由で取得されます。CDN は24時間以内にドメインから取得し直し、端末側の更新はおよそ週1回です。CDN を手動で無効化する手段はありません（TN3155）。AASA を置く前からインストールしていた端末では、再インストールしないと Universal Link が効きません。`?mode=developer` は development プロファイルで署名した場合だけ効き、端末側で設定をオンにする必要があります。
- **App Links**: autoVerify の intent-filter には http と https の両方が必要で、ほかの scheme を同じ filter に入れると検証が通りません。Android 15 以降は再検証に最大7日かかります。
- **Android Chrome の `intent://`**: `package=` だけを指定すると、未インストール時に Play の通常ページへ飛び、**referrer が付きません**。referrer を残すには `S.browser_fallback_url` に referrer 付きの Play URL を入れる必要があります。
- **LINE のアプリ内ブラウザ**では Universal Links が効かないことが多いとされます（二次情報。`openExternalBrowser=1` の効果とあわせて要実機確認）。
- **Branch** にもクリップボードを使う決定的な方式（NativeLink）がありますが、仕組みは自前の「コピー → 貼り付け」と同じです。

### 1-6. 検証で見つかった既存の不具合（招待リンクとは別に起票する）

- [ ] **B1. オフラインで起動すると、登録済みの顧客もサインアウトされる**: `currentClientProvider` は clients の取得で例外が出ても catch して null を返します（`current_user_provider.dart:23-38`）。そのため通信エラーでも「行なし」と同じ扱いになり、`app.dart:306-311` でサインアウトされます。→ 「行なし」と「通信エラー」を分け、エラー時はサインアウトしないようにします。PR-M1 で app.dart を触るので、同じ PR で直します。
- [ ] **B2. トレーナーが顧客として登録すると、アカウント削除で全顧客のデータが消える**: delete-account は「clients 行が無く trainers 行がある」場合しか拒否しません（`delete-account/index.ts:100-115`）。トレーナーが同じアカウントでアプリから顧客登録すると、その後の「アカウント削除」で、全メッセージの削除と auth ユーザーの削除が走ります。そこから trainers → 全顧客の clients → 記録が CASCADE で消えます（`20260131000001:18, 53-55`）。招待リンクを自分のスマホで試すトレーナーは、この操作を踏みやすくなります。→ PR-A0 として先に直します（§4）。
- [ ] **B3. マジックリンクを別の端末で開くとログインできない**: PKCE の code verifier はアプリにしか無く、メールのテンプレートは `{{ .ConfirmationURL }}` だけです（`supabase/templates/magic_link.html:107,150`）。→ 6桁の OTP の併記（`{{ .Token }}` と `verifyOTP`）を別タスクにします。本計画では、メール送信後の画面に「このスマホでメールを開いてください」と出すだけにします。

---

## 2. 方式の比較と推奨

| 観点 | A. 自前（推奨） | B. Branch / AppsFlyer / Adjust |
|---|---|---|
| 未インストール → ストア | ランディングで端末を判定してストアボタンを出す | SDK とリンクサービスが自動で振り分ける |
| インストール後の引き継ぎ | Android: Play Install Referrer（確実。段階2）。iOS: リンクの再タップ、またはコードの入力 | iOS はクリップボード方式（iOS 16 以降は貼り付けダイアログが出る）か、IP / UA による確率的なマッチング |
| 費用 | 0（Vercel 内） | 無料枠は機能・量に制限があり、将来は有償 |
| プライバシー | 第三者 SDK なし。ただし `/invite` で GA を読み込まないようにする | SDK の追加で、プライバシーポリシー・App Privacy・Privacy Manifest の更新が必要。ATT の論点も出る |
| 規模との適合 | トレーナー1人あたりの顧客は最大30人。対面や LINE で手渡しする形が中心なので、手入力でも現実的 | マーケティング用の帰属計測が主な価値で、この用途には過剰 |

**推奨は A です。** iOS では、どちらの方式でもインストール後に招待情報を確実に引き継ぐ手段はありません。B は仕組みが同じまま、プライバシーの負担と外部への依存が増えるだけです。

### 2-1. 流れ（段階1）

1. トレーナーが Web で招待を発行します。`https://<招待ホスト>/invite/ABCD2345` と QR（中身は同じ URL）が出ます。
2. **アプリが入っている場合**: OS が Universal Link / App Link としてアプリを開きます。アプリはコードを resolve し、トレーナー確認画面へ進みます。
3. **入っていない場合、またはアプリ内ブラウザで Universal Link が効かない場合**: ランディングを表示します。
   - トレーナー名・アバター・**コードを大きく**表示します。主ボタンはストアへのリンクです。押すときにコードをクリップボードへコピーし、「インストールしたら、もう一度このリンクを開くか、このコードを入力してください」と案内します。
   - 「アプリをお持ちの方」には custom scheme の `fitconnectmobile://invite/ABCD2345` を出します。iOS は未インストール時にエラーになるので、主ボタンにはしません。Android は `intent://...;S.browser_fallback_url=<referrer 付きの Play URL>;end` にします。
   - ストア URL（`app_config`）がまだ無い間は、ストアボタンを出さず「アプリ公開準備中」と表示します。
4. インストール後: リンクを開き直せば 2 と同じ流れになります。入力するときは、入力欄の標準の貼り付け（長押しメニュー。ダイアログは出ない）で、ランディングでコピーしたコードを入れられます。
5. resolve（未ログインでも可）→ トレーナー確認 → ログイン → プロフィール入力 → **redeem（サーバー側の RPC がコードを確かめて clients 行を作る）** → 完了。保留中の招待（コードだけ）は SharedPreferences に保存し、kill されても再開できるようにします。

段階2（Play で公開した後）: Android は初回起動時に Install Referrer の `invite_code` を一度だけ読み、自動で 5 に進みます。

---

## 3. 段階分け

| 段階 | 内容 |
|---|---|
| **段階1（本計画）** | invite_codes・使用履歴・RPC（create / revoke / resolve / redeem）。**clients の直接 INSERT と trainer_id の更新権限の剥奪**。**UUID による紐付け経路の削除**（Mobile の QR / 手入力 / upsert）。リンク・ランディング・`.well-known`・アプリのリンク受信。既存の不具合 B1 / B2 の修正 |
| **段階2** | Android の Install Referrer（Play での公開が前提。内部テストトラックでしか確認できない） |
| **段階3（別枠のセキュリティタスク）** | `trainers_select_all` を本人と担当顧客に限定し、anon の権限を `REVOKE ALL`。顧客から見てよい列を関数かビューに分ける。アバターを Web のルート経由で返し、パスを外に出さない。`/invite` と resolve のレート制限 |

- **段階1で旧経路まで閉じる理由**: 閉じないと、期限・回数・失効のどれもが迂回できてしまいます。つまり invite_codes は見た目だけの仕組みになり、無料プランの3枠を他人が埋めることもできる状態が続きます。clients に書き込んでいるのはアプリの1か所だけで、Web と Edge Functions からは書き込んでいません。アプリは未公開なので、旧版の利用者もいません。併用期間と強制アップデートも不要になります。
- **トレーナーが既に印刷・掲示した UUID の QR は、段階1で使えなくなります。** Web のモーダルで、新しいリンクの発行を案内します（論点 D3）。
- **判断5との関係**: 判断5は「UUID 方式は当面維持し、invite_codes は RLS の解消とセットで別枠」としています。本計画は「invite_codes と clients の封鎖を先に行い、trainers の RLS の解消は後」に組み替えます。承認を得て、integration-decisions.md の判断5に追記しました（2026-10-28）。

---

## 4. コードと RPC の仕様

### 4-1. コード

- 8文字で、文字は `ABCDEFGHJKMNPQRSTUVWXYZ23456789`（0/1/I/L/O を除く31種類）。大文字で保存し、入力は大文字と小文字を区別せず、空白とハイフンは無視します。組み合わせは 31^8 ≒ 8.5×10^11 通りです。
- 生成は `extensions.gen_random_bytes` を完全修飾で呼び、**248 以上のバイトは捨てます**（256 は 31 で割り切れないので、そのままでは一部の文字が出やすくなるため）。衝突したら `INSERT ... ON CONFLICT (code) DO NOTHING RETURNING` をループして再試行します。
- MVP のコードは**1人用（1回・7日）だけ**です（論点 D4）。手動で失効できます。トレーナーあたりの有効なコードは20件までです。

### 4-2. テーブル

- `invite_codes(code text PK CHECK (code ~ '^[A-HJKMNP-Z2-9]{8}$'), trainer_id uuid NOT NULL REFERENCES trainers ON DELETE CASCADE, expires_at timestamptz NOT NULL, max_uses int NOT NULL DEFAULT 1 CHECK (max_uses > 0), used_count int NOT NULL DEFAULT 0, revoked_at timestamptz, created_at timestamptz NOT NULL DEFAULT now())`
- `invite_code_redemptions(code text REFERENCES invite_codes ON DELETE CASCADE, client_id uuid REFERENCES clients ON DELETE CASCADE, redeemed_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (code, client_id))`。「誰がこのコードを使ったか」をトレーナーが見るためと、監査のためのテーブルです。
- RLS はどちらも「トレーナー本人の SELECT だけ」（`TO authenticated`）です。書き込みは関数からだけ行います。`REVOKE ALL FROM anon, authenticated` のあと `GRANT SELECT TO authenticated` します。

### 4-3. RPC（すべて SECURITY DEFINER・`SET search_path = ''`・完全修飾・`REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` のあと必要な GRANT だけ）

| RPC | EXECUTE | 振る舞い |
|---|---|---|
| `create_invite_code()` | authenticated | 呼び出し元が trainers 行を持つことを確認し、有効なコードが20件未満のときだけ発行する。7日・1回 |
| `revoke_invite_code(p_code)` | authenticated | 本人のコードだけ `revoked_at = now()` |
| `resolve_invite_code(p_code)` | **anon, authenticated** | 形式を確かめてから照会する。未ログインには `{status: 'ok'|'unavailable', trainer_name?, trainer_image?}` だけを返す（期限切れ・失効・使用済み・存在しないを区別しない。名前と画像は ok のときだけ返す）。ログイン済みで clients 行があれば `linked: 'same'|'other'` も返す（trainer_id は返さない）。画像は `{kind: 'storage'|'external', value}` に正規化し、`#` 以降は落とす。**anon に意図して EXECUTE を開けていることを COMMENT に書く** |
| `redeem_invite_code(p_code, p_name DEFAULT NULL, p_age DEFAULT NULL, p_gender DEFAULT NULL)` | authenticated | 下の手順で処理し、結果は jsonb の `status` で返す |

**redeem の手順**（この順序が重要です）:
1. `auth.uid()` が NULL なら 42501 で拒否する。
2. **呼び出し元が trainers 行を持っていれば `trainer_account` で拒否する**（B2 の対策。誤判定のケースは論点 D11）。
3. コードを `FOR UPDATE` でロックする。無ければ `not_found`。コードのトレーナー本人なら `trainer_account`。
4. **呼び出し元の clients 行を先に確認する。** 同じトレーナーなら、コードの状態に関係なく `ok` を返す（used_count は増やさない。応答が届かなかった場合や、後続の画像アップロードの失敗からの再試行のため）。別のトレーナーなら `already_linked`。
5. revoked / expired / exhausted の判定（どれも `unavailable`）。
6. `pg_advisory_xact_lock(hashtextextended(trainer_id::text, 0))` でトレーナー単位に直列化し、上限のすり抜けを防ぐ。
7. `INSERT ... ON CONFLICT (client_id) DO NOTHING RETURNING`。値は `COALESCE(NULLIF(btrim(p_name),''),'新規クライアント')`、`COALESCE(p_age, 25)`、`COALESCE(p_gender, 'other')`（`remote_schema:198-199` の既定値と相互参照する）。事前に検証し、不正な値は `invalid_profile` で返す。email は `auth.users` から読む。行が返らなければ読み直して 4 と同じ扱いにする。**clients を UPDATE しない・DO UPDATE を使わない**（DEFINER の中では列ガードが素通しになり、乗り換えの経路ができてしまうため）。
8. `CLIENT_LIMIT_REACHED` だけを捕まえ、DETAIL を付けずに `status: 'client_limit_reached'` で返す（トリガーの DETAIL にある trainer_id・plan を漏らさないため）。
9. used_count を +1 し、redemptions に INSERT して `{status: 'ok', trainer_id}` を返す。

| status | 意味 | アプリの表示 |
|---|---|---|
| ok | 紐付け完了（再送も含む） | 完了画面へ |
| not_found / unavailable | コードが使えない | 「このコードは使えません。トレーナーに新しいリンクを依頼してください」 |
| already_linked | 別のトレーナーと連携済み | 「別のトレーナーと連携中です」 |
| client_limit_reached | トレーナーの枠が埋まっている | 既存の `ClientLimitReachedException.userMessage` と同じ文言 |
| trainer_account | トレーナーのアカウント | 「トレーナー用のアカウントでは顧客登録できません」→ ログアウト |
| invalid_profile | 入力値が不正 | 該当欄のエラー |

---

## 5. PR 分割とタスク

**順序**: `PR-A0` → `PR-A1` → (`PR-M0` ∥ `PR-M1` ∥ `PR-W2` ∥ `PR-W3`) → `PR-W1`（**M1・W2 のマージ後**）→ `PR-M2` → [リリース] → `PR-M3`（段階2）
ブランチは `develop/1.0.0` から切り、push 前に squash します（`git reset --soft`）。

### PR-A0: `fix/delete-account-trainer-guard`（Edge Function、担当: supabase）
- [ ] `supabase/functions/delete-account/index.ts`: trainers 行がある uid は、clients 行の有無にかかわらず 403 にする
- [ ] テスト（既存のテストの形式に合わせる）と、deploy 手順の記載（deploy はオーナー作業）

### PR-A1: `feature/invite-codes-db`（Supabase、担当: supabase）
対象: `supabase/migrations/<版>_invite_codes.sql`、`supabase/tests/invite_codes_test.sql`、`fit-connect/src/types/invite.ts`、`fit-connect-mobile/lib/features/auth/models/invite_preview.dart`（と `.g.dart`）
- [ ] §4-2 の2テーブルと RLS、§4-3 の4関数
- [ ] **clients の封鎖**: authenticated から INSERT の列 GRANT と `trainer_id` の UPDATE を剥奪し、`clients_insert_own` を DROP する。`column_write_guards` の末尾の検査（L729-731, L769-771 付近）をこれに合わせて更新する
- [ ] migration の末尾の DO ブロックで、新関数ごとに prosecdef・owner=postgres・`search_path=""`・PUBLIC への付与が無いこと・EXECUTE の一覧（anon が使えるのは resolve だけ）を検査し、invite_codes の権限（anon は全て false、authenticated は SELECT だけ）と clients の INSERT 剥奪を検査する。想定と違えば例外を出す
- [ ] `enforce_client_limit` の本体には触れない（md5 が固定されているため）
- [ ] テスト（BEGIN…ROLLBACK）
  - RLS: 本人が見える。他のトレーナー・顧客・anon（クレーム無しとクレーム付き）は0行
  - create: 形式が CHECK に合う（実際に呼ぶ）。21件目は拒否される。顧客には発行できない
  - resolve: anon では ok / unavailable の2値。ok 以外では名前と画像を返さない。戻り値のどこにも trainer_id の文字列が無い。画像の3形式の正規化。ログイン済みの linked same / other
  - redeem: 未認証は拒否。正常系（clients・used_count・redemptions）。**使い切ったコードを本人が再送すると ok で used_count は変わらない**。期限切れの後の本人の再送も ok。2人目は unavailable。already_linked。client_limit_reached（DETAIL が漏れないこと、used_count が変わらないこと）。trainer_account（自分のコード・他のトレーナー）。age / gender / name の省略時の既定値。invalid_profile。DEFINER を経由しても trainer_id が変わらないこと
  - 封鎖: 顧客の JWT で clients に直接 INSERT すると 42501
  - 負の対照: GRANT やポリシーを緩めると、該当するケースだけが FAIL すること
- [ ] 既存のテストは回帰として全件実行する（許可リストの更新は不要）
- [ ] 検証: 隔離スタックで `supabase db reset --no-seed` → テスト → PostgREST の実リクエスト（anon キーで resolve、顧客 JWT で redeem・直接 INSERT、トレーナー JWT で create）（lessons L474）

### PR-M0: `feature/invite-deeplink-spike`（Mobile、実機スパイク。マージしない前提でもよい）
- [ ] UIScene 構成で、custom scheme（`fitconnectmobile://invite/X`）と既存の login-callback が、**コールドスタートとウォームスタートの両方で**届くかを app_links 6.4.1 で確かめる
- [ ] 届かなければ、supabase_flutter を 2.12.1 以上に上げ、app_links を `>=7.0.0 <7.1.0` に固定したうえで再確認する。結果を PR-M2 の前提として計画に書き戻す
- [ ] Android: アプリを起動したまま他のアプリからリンクを開き、同じタスク・インスタンスに届くか確かめる（`taskAffinity=""` のため。`adb shell dumpsys activity activities`）

### PR-M1: `feature/invite-code-mobile`（Mobile、担当: general-purpose に fvm 前提を明示して委託。lessons L156-159）
対象: `invite_repository.dart`、`utils/invite_link_parser.dart`、`data/pending_invite_store.dart`、`registration_provider.dart` と `.g.dart`、`invite_code_screen.dart`、`qr_scan_screen.dart`、`trainer_confirm_screen.dart`、`profile_setup_screen.dart`、`main.dart`、`app.dart`、`current_user_provider.dart`、各テスト、`docs/QR_REGISTRATION_FLOW.md`
- [ ] **`hasTrainer` を `hasPendingRegistration => inviteCode != null` に置き換える**（UUID の経路は無くなる）。app.dart の L170・L303・L339 を更新する。`completeRegistration` の trainerId 必須のチェックを外して redeem を呼び、戻り値の trainer_id を state に保存する
- [ ] **pending の復元は runApp の前に行う**: `main.dart` で SharedPreferences を読み込み、ProviderScope の overrides で初期 state として渡す（build の中で非同期に復元すると、復元より先にサインアウトが走るため）。保存はトレーナー確認画面に進んだ時点。破棄は clear、redeem の終端結果、clients 行ができたとき（Main に入ったとき）。保存するのはコードだけにし、復元時に resolve し直す
- [ ] `copyWith` は inviteCode を null に戻せる形にする（`String? Function()?`）。resolve が成功したら入れ直す
- [ ] **redeem が失敗したときの行き止まりを無くす**: 終端の status では pending を破棄し、「別の招待コードを入力」（セッションを保ったまま入力画面へ。app.dart にこの状態の分岐を足し、サインアウトの対象から外す）と「ログアウト」を出す
- [ ] **B1 の修正**: `currentClientProvider` は「行なし」なら null、通信エラーなら rethrow にする。app.dart の error 分岐ではサインアウトせず、再試行の画面を出す
- [ ] 入力画面と QR 画面: 16進の分岐と UUID / `register?trainer_id=` の受け付けをやめ、8桁のコードと招待 URL だけを受け付ける。入力は大文字化し、区切りを無視する。validator は正規化した後の値で判定する。resolve の結果（ok / unavailable）ごとに文言を出す
- [ ] トレーナー確認画面: ログイン済みなら「次へ」で LoginScreen を経由せず ProfileSetup へ進む。戻るボタン（AppBar）でも clear する
- [ ] メール送信後の画面に「このスマホでメールを開いてください」を出す（B3 の暫定対応）
- [ ] パーサーは login-callback（`?code=` 付き）を無視する
- [ ] ログ出力（`registration_provider.dart:129-139` の print、`current_user_provider` の DEBUG）から、コード・ID・応答の中身を出さない
- [ ] プレビュー関数（確認画面の各状態・エラー・ダークモード）
- [ ] 検証: `fvm dart run build_runner build --delete-conflicting-outputs` を実行し、develop との生成物の差分を確認する（lessons L188-194）。`fvm flutter analyze` / `fvm flutter test`。widget テストで「inviteCode だけの state でログインしてもサインアウトされない」「オフラインで起動してもサインアウトされない」「各 status の表示」を確認する。`ios-simulator-qa`（隔離スタックに向けたビルドで、コード入力 → 登録 → clients・used_count・redemptions を SQL で確認）

### PR-W2: `feature/invite-landing-web`（Web、担当: nextjs-ui ＋ supabase）
対象: `src/app/(public)/layout.tsx`、`(public)/invite/[code]/page.tsx`（Server Component、`force-dynamic`）、`InviteActions.tsx`（client）、`src/lib/invite/storeLinks.ts` とテスト、`src/lib/supabase/resolveInviteCode.ts`、GA の読み込み位置
- [ ] `resolveInviteCode.ts` は `@/lib/supabase` の anon クライアントで RPC と `app_config` を呼ぶ。署名 URL は `storagePaths.ts` と `createSignedUrl` で作る（`signedStorageUrls.ts` / `ProfileAvatar` は import しない）。アバターは素の `<img>`（`referrerPolicy="no-referrer"`、失敗時はイニシャル）
- [ ] 端末の判定はサーバーで `headers().get('user-agent')` から行い、props で渡す。開発ビルドだけで効く `?platform=ios|android` の上書きを用意する（内蔵ブラウザの QA 用）
- [ ] `storeLinks.ts`: Play の URL（`&referrer=invite_code%3D<code>`）、`intent://` は **`S.browser_fallback_url` に referrer 付きの Play URL を必ず入れる**、custom scheme。テストで fallback に referrer が含まれることを確認する
- [ ] 表示: ok（名前・アバター・コードを大きく・ストアボタン・コピー）、unavailable（「トレーナーに新しいリンクを依頼してください」）、ストア URL が NULL の間は「公開準備中」
- [ ] **GA を `/invite` に読み込まない**（GA をマーケティング用のレイアウトへ移すか、パスで除外する）。title と OGP は汎用の文言に固定する。build した HTML に gtag が無いことを確認する
- [ ] `metadata.robots = { index: false, follow: false }`。**robots.txt の disallow には入れない**（入れると noindex を読んでもらえないため）。sitemap にも載せない
- [ ] 検証: vitest、`tsc` / lint / `next build`、`curl -A '<iOS / Android の UA>'` で HTML を確認、`chrome-web-qa`（`?platform=` を使い、隔離スタックのデータで各状態を確認）

### PR-W3: `feature/invite-wellknown-web`（Web、担当: supabase〈Route Handler〉）
対象: `src/app/.well-known/apple-app-site-association/route.ts`、`src/app/.well-known/assetlinks.json/route.ts`、`src/lib/invite/wellKnown.ts` とテスト、`tsconfig.json`（include に `src/app/.well-known/**/*.ts` を追加）
- [ ] AASA: `applinks.details[].appIDs = [APPLE_APP_ID]`、`components = [{"/": "/invite/*"}]`。`/invite/*` 以外のパスはアプリに渡さない
- [ ] assetlinks: `com.fitconnect.fit_connect_mobile` と `ANDROID_SHA256_CERT_FINGERPRINTS`（カンマ区切り）。**環境変数が空なら 404**
- [ ] `export const dynamic = 'force-dynamic'`、`Content-Type: application/json`、リダイレクトしない
- [ ] アプリを公開する前でも安全に main に出せます（entitlement の無いアプリには何も起きないため）。早めに出しておけば、Apple の CDN への反映を先に始められます

### PR-W1: `feature/invite-issue-web`（Web、担当: nextjs-ui ＋ supabase。**M1 と W2 のマージ後**）
対象: `src/lib/supabase/createInviteCode.ts`・`revokeInviteCode.ts`・`getInviteCodes.ts`、`src/lib/invite/inviteUrl.ts` とテスト、`ClientInviteModal.tsx`
- [ ] `buildInviteUrl` は専用の `NEXT_PUBLIC_INVITE_BASE_URL` から URL を作る。**フォールバックは持たない**。未設定なら発行ボタンを無効にする（誤ったドメインのリンクを配らないため）
- [ ] モーダル: 「招待リンクを発行」→ リンク（コピー）・コード（4桁ずつ区切って表示し、コピー時は区切らない）・QR（値は URL）・有効期限・失効ボタン。有効なコードの一覧と、それぞれのコードで登録した顧客（redemptions）を表示する。一覧は `revoked_at is null` と `expires_at > now` で絞り、使い切ったものは画面側で除く
- [ ] trainerId の QR・表示・コピーをやめる（L78, L85, L145, L160）
- [ ] 「QRコードをダウンロード」は残し、画像に有効期限を描き込む
- [ ] 上限到達時の表示と fail-open は今のまま
- [ ] ストア URL がどちらも NULL の間は「アプリ公開前のため、テスト参加者向けです」と表示する
- [ ] `ui-ux-pro-max` はマネージャーが先に実行し、結果を委託プロンプトに含める
- [ ] 検証: `tsc` / vitest / lint / `next build`、`chrome-web-qa`（`NEXT_PUBLIC_INVITE_BASE_URL=http://127.0.0.1:<port>` で dev server を起動し、ランディングまで通す）

### PR-M2: `feature/invite-deeplink-mobile`（Mobile、担当: general-purpose）
対象: `pubspec.yaml` / `pubspec.lock`（M0 の結論による）、`AndroidManifest.xml`、`Runner.entitlements`・`RunnerRelease.entitlements`、`Info.plist`、`lib/features/auth/services/invite_link_listener.dart` とテスト、`app.dart`（navigatorKey）、`trainer_confirm_screen.dart`
- [ ] **Flutter の deep linking を無効にする（必須）**: `Info.plist` で `FlutterDeepLinkingEnabled=false`、MainActivity に `flutter_deeplinking_enabled=false` の meta-data
- [ ] Android: autoVerify の filter（http と https・招待ホスト・`pathPrefix="/invite/"`）、custom scheme の filter（`fitconnectmobile` / `invite`）、既存の login-callback の filter を**別々に**書く
- [ ] iOS: `Runner.entitlements` には `applinks:<host>` と `applinks:<host>?mode=developer` の両方、`RunnerRelease.entitlements` には `applinks:<host>` だけ
- [ ] listener: `getInitialLink()` と `uriLinkStream` の両方で受け、直近に処理した URI で重複を除く
- [ ] 状態ごとの挙動: 未ログインなら resolve → TrainerConfirm を push。ログイン済みで clients 行がある場合は pending を保存せず、`linked` が same なら「既に連携済み」、other なら「別のトレーナーと連携中」を表示。登録フロー中なら、上書きするかを確認ダイアログで選ぶ
- [ ] 検証: `simctl openurl` / `adb shell am start`（コールドスタートとウォームスタート）、`pm verify-app-links --re-verify` と `pm get-app-links`、マジックリンクの回帰確認（Mailpit。コールドスタートも）、`ios-simulator-qa` / `android-emulator-qa`

### PR-M3: `feature/invite-install-referrer`（段階2、Mobile）
- [ ] `play_install_referrer: 0.5.0`（または installreferrer を MethodChannel で直接呼ぶ）。AGP / Kotlin でのビルドを確認する（古いパッケージが新しい Flutter で壊れた前例は lessons L179-187）
- [ ] Android の初回起動時に一度だけ読み、読み取り済みのフラグを保存する。`invite_code=` を取り出して resolve する。空や期限切れでも何もしない（fail-open）
- [ ] 検証: 単体テスト（referrer の解析）。実際の動作は Play の内部テストトラックでしか確認できない（オーナーの実機作業）

---

## 6. テストと QA

| 層 | 自動テスト | QA |
|---|---|---|
| DB | `invite_codes_test.sql`（RLS・RPC・権限・clients の封鎖・負の対照）、既存テストの回帰 | 隔離スタックで PostgREST の実リクエスト |
| Web | vitest（URL 生成・正規化・UA 判定・intent の fallback・AASA / assetlinks の JSON）、`tsc` / lint / `next build`、`/invite` の HTML に gtag が無いこと | `chrome-web-qa`（隔離スタック。ランディングは未ログインで `?platform=` を使う） |
| Mobile | `fvm flutter test`（パーサー・pending・provider・状態の分岐・オフライン起動・listener の重複除去）、`fvm flutter analyze` | `ios-simulator-qa` / `android-emulator-qa`（`dev_login.json`、隔離スタック） |
| 通し（本番のホストが必要） | ― | AASA を置き、Apple の CDN（`https://app-site-association.cdn-apple.com/a/v1/<host>`）で反映を確認 → **検証用の端末にアプリを再インストール** → TestFlight / Play 内部テストで「未インストール → ストア → インストール → リンクの再タップまたはコード入力 → 登録 → Web の顧客一覧」→ SQL で clients・used_count・redemptions を確認。LINE のチャット内のタップと、LINE の QR リーダーでも確認 |

- QA は、本番にテストデータを入れないよう隔離スタックで行います（lessons L499-501）。
- 通しの確認は、SQL で clients 行ができたことを確かめるまでを完了条件にします（lessons L366-370）。

---

## 7. オーナー作業

### 事前
- [ ] **招待ホストを決める**（D5）。Cloudflare で Vercel 向けのレコードを **DNS only**（プロキシしない）で追加し、メール用の既存レコードには触れない。Vercel の Production に追加し、このホストを他のホストへのリダイレクト元にしない。`NEXT_PUBLIC_INVITE_BASE_URL` を設定する
- [ ] トレーナー Web のドメインも移す場合は、Supabase Auth の Redirect URLs に新しいドメインを追加し、旧ドメインから 308 でリダイレクトし（`/.well-known` は除く）、トレーナーに Web Push の再設定とログインのやり直しを案内する
- [ ] Apple Developer: App ID で Associated Domains を有効にし、プロビジョニングプロファイルを作り直す
- [ ] Android: upload key を作り、release の署名を設定する（今は debug 鍵）。Play Console で App Signing を有効にし、SHA-256（App Signing・upload・debug）を `ANDROID_SHA256_CERT_FINGERPRINTS` に登録する。`APPLE_APP_ID=HNKWT8DU57.com.fitconnect.fitConnectMobile` も登録する。**環境変数を変えたら Production を再デプロイする**
- [ ] PR-A0（delete-account）の deploy

### リリース時
- [ ] migration のリモート適用（直前に `supabase migration list --linked` と `db push --dry-run`。`SUPABASE_ACCESS_TOKEN` は unset。lessons L354, L688-690）
- [ ] ストアでの公開（または TestFlight / 内部テスト）→ `app_config.ios_store_url` と **`android_store_url`** を設定する（android はタスクに無かったので追加）
- [ ] 公開後の確認: Apple の CDN、`pm get-app-links`、未インストールの実機で LINE からリンクを開く
- [ ] プライバシーポリシーの確認（Install Referrer の利用。`/invite` を GA の対象外にすること）

---

## 8. ドキュメント更新

- [ ] `docs/tasks/IMPLEMENTATION_TASKS.md` に「顧客招待リンク」のフェーズを追加し、B1〜B3 を起票する
- [ ] `docs/tasks/2026-07-10-integration-decisions.md` の判断5に、D1 の決定を追記する
- [ ] `fit-connect-mobile/docs/QR_REGISTRATION_FLOW.md` を更新する
- [ ] 計測について: 段階1では redemptions の件数だけを見る。`/invite` は GA の対象外にする
- [ ] 実装中に得た知見を `docs/tasks/lessons.md` に追記する

---

## 9. オーナーに決めてもらう論点（推奨付き）

- **D1. 段階1で invite_codes を入れ、旧経路（clients の直接 INSERT・UUID）も閉じるか**（判断5の変更）→ **✅ 決定（2026-10-28）: 閉じる。** integration-decisions.md の判断5に追記済み。 trainers の RLS の解消だけを段階3に残す
- **D2. 方式** → **推奨: 自前。** Branch などは使わない
- **D3. 印刷・掲示済みの UUID の QR** → **推奨: 段階1で使えなくする。** アプリは未公開なので影響は小さい。Web で再発行を案内する
- **D4. コードの種類** → **✅ 決定（2026-10-28）: MVP は1人用（1回・7日）だけ。** 掲示用の複数人向けは、トレーナーが顧客の紐付けを解除できる機能ができてから検討する（今は漏れても回収できないため）
- **D5. 招待リンクのホスト** → **✅ 決定（2026-10-28）: 招待専用のホストを同じ Vercel プロジェクトに追加する**（名前は例 `go.fit-connect.app`。正式な名前はオーナーが DNS 設定時に確定）。 トレーナー Web を移さずに済み、ログインや Web Push に影響しない。トレーナー Web もいずれ `fit-connect.app` に移すなら、そちらに統一する案もある
- **D6. OGP にトレーナー名を出すか** → **推奨: 出さない（汎用の文言）。** ページの中には表示する
- **D7. LINE 共有用の `?openExternalBrowser=1`** → **推奨: 実機で効果を確かめてから決める**（段階1には入れない）
- **D8. 上限到達をランディングで事前に知らせるか** → **推奨: MVP では知らせない。** 上限に達したトレーナーには Web で発行させず、redeem でも拒否する
- **D9. 別のトレーナーと連携済みの顧客がリンクを開いたとき** → **推奨: 乗り換えはできないまま、案内だけ表示する**
- **D10. Web の main へのリリース範囲** → **推奨: 段階1が揃った時点で、develop 全体のリリース判断とあわせて行う。** PR-W3（`.well-known`）だけは先に出してもよい
- **D11. トレーナーのアカウントでの顧客登録の拒否** → **✅ 決定（2026-10-28）: 拒否する。** 誤判定（Web に Google でログインしたことのある顧客）は、Web の callback の trainers の upsert を新規登録のときだけに絞る別タスク（IMPLEMENTATION_TASKS 11.B4）で解消する。 ただし Web に一度 Google でログインした顧客にも trainers 行ができるため、その人はアプリで顧客登録できなくなる。これを許容するか、または Web の callback の trainers の upsert を新規登録のときだけに絞るか（別タスク）を決める
- **D12. iOS の「貼り付け」ボタン** → **推奨: 作らない。** 押すたびに許可のダイアログが出るため。入力欄の標準の貼り付けを案内する
