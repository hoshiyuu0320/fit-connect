# フェーズ8.2 Storage private化 + 署名URL — 実装計画（確定版）

**作成**: 2026-08-29 / ブランチ: `feature/storage-private-signed-urls`
**出典**: `2026-07-08-solution-catalog.md` cat7 課題2（施策2-A 全バケット private）・課題8（8-A/8-B）、`2026-07-10-integration-decisions.md` 判断7-2
**リモート実測（2026-08-29）**: 4バケット全て public=true。message-photos 61 objects（うち /ai/ 24）、client-avatars 3、client-notes 11、profile-images 1。URL格納行: messages 43 / meal_records 9 / exercise_records 0 / client_notes 1（`#ファイル名` 付き）/ clients.profile_image_url 5（うち Storage 3・Google 2）/ trainers.profile_image_url 2（うち Storage 1）。`clients.client_id = auth.uid()`（user_id カラムは存在しない）。

## 確定した設計判断

1. **4バケット全てを private 化**（施策2-A）。LP・未認証ページでの Storage 画像利用ゼロを確認済み。
2. **DB にはバケット相対パスを保存**（例: `9d1ecf80-…/bad437a6-….jpg`）。カラム↔バケット対応は固定:
   - `messages.image_urls` / `meal_records.images` / `exercise_records.images` → `message-photos`
   - `client_notes.file_urls` → `client-notes`（値は `パス#encodeURIComponent(元ファイル名)` 形式を維持）
   - `clients.profile_image_url` → `client-avatars`（外部URL=Google はそのまま通す）
   - `trainers.profile_image_url` → `profile-images`（外部URLはそのまま通す）
3. **表示は署名URL（TTL 3600秒）**。両プラットフォームに共通セマンティクスのヘルパーを新設:
   - `resolveStorageValue(value, bucket)`: null/空→null。`http` 始まり: 同一プロジェクトの `/storage/v1/object/(public|sign)/<bucket>/` を含めばパス抽出（クエリ除去・フラグメント除去）→署名。外部URL（Google 等）→そのまま返す。それ以外→パスとして署名（署名前に `#` フラグメント除去）。
   - 署名URLはメモリキャッシュ（キー=`bucket/path`、残り約5分で再発行）。
   - 存在しないオブジェクト（Seed の架空パス等）で例外を投げず null / エラーフォールバック表示。
4. **強制アップデート機構**: `app_config` 単一行テーブル（anon/authenticated SELECT のみ・書込ポリシーなし）+ Mobile `lib/features/app_update/`。オフライン/取得失敗は fail-open。ダイアログは `consent_dialog.dart` パターン（barrierDismissible:false + PopScope(canPop:false)）。ゲートは `MyApp.build` の StreamBuilder より上位に**新規ファイルの Widget** として挿入（`_AuthLoadingScreenState` と `morningDialogProvider` は別セッション作業中のため触らない）。
5. **AI推定画像**: Mobile は Edge Function に**パス**を渡す。`estimate-meal-nutrition` は URL/パス両対応で受け、service_role で `createSignedUrl(path, 600)` して Anthropic に `source:{type:'url'}` で渡す。
6. **orphan cleanup**: 8-B（キャンセル時即時削除、挿入済みガード付き）+ 8-A（`cleanup-ai-images` Edge Function、dry_run 対応、参照判定は migration の SQL 関数 `find_orphan_ai_images()`、pg_cron は **inactive 登録**）。
7. **既存データ正規化**: migration でフルURL→パスへ regexp_replace（`#` フラグメント・外部URLは保全、アバターの `?t=` は除去）。切り戻しは public=true 復帰 + 表示ヘルパーがパスを署名するため正規化後もロールバック可能（ヘルパー実装が先にマージされる限り）。
8. **Mobile アバターのキャッシュバスター**: `avatar.jpg` 固定 + `?t=` 方式を廃止し、`{uid}/avatar_{timestamp}.jpg` にアップロード→旧ファイル削除。cacheKey=パスでキャッシュが正しく更新される。

## Storage ポリシー最終形（migration `20260829000000_storage_private_and_policies.sql`）

全て `UPDATE storage.buckets SET public=false WHERE id IN (…)` + `DROP POLICY IF EXISTS` → `CREATE POLICY`（リモートは手動作成ポリシーが存在するため、存在チェック DO ブロックではなく DROP→CREATE で冪等化）。

- **message-photos**
  - DROP: "Public read access for message photos", "Authenticated users can upload images"
  - SELECT (authenticated): `folder[1]=auth.uid()` OR `EXISTS(clients c: c.client_id::text=folder[1] AND c.trainer_id=auth.uid())` OR `EXISTS(clients c: c.trainer_id::text=folder[1] AND c.client_id=auth.uid() AND folder[2]=auth.uid()::text)`
    （フォルダ規約: Mobile=`{clientUid}/…`・`{clientUid}/ai/…`、Web=`{trainerUid}/{clientUid}/…`）
  - INSERT (authenticated): `folder[1]=auth.uid()::text`（他人フォルダ封鎖 = タスク8.2の明示項目）
  - UPDATE/DELETE: 既存の own-folder ポリシーを維持
- **client-avatars**: DROP "Public avatar access"。SELECT (authenticated): `folder[1]=auth.uid()` OR `EXISTS(clients c: c.client_id::text=folder[1] AND c.trainer_id=auth.uid())`。書込系は既存維持。
- **profile-images**: DROP "Profile images are publicly accessible"。SELECT (authenticated): `bucket_id='profile-images'`（登録フローで clients 行作成前にトレーナーアバター表示が必要。trainers 全行が authenticated に読める既存 RLS と整合）。DELETE own-folder を新設（欠落中）。
- **client-notes**: DROP "trainers_read_notes"/"trainers_upload_notes"/"trainers_delete_notes"（authenticated 全員が全フォルダ読み書き削除できる重大不備）。フォルダ規約 `{trainerUid}/{clientUid}/…`。SELECT (authenticated): `folder[1]=auth.uid()` OR `folder[2]=auth.uid()::text`。INSERT/UPDATE/DELETE (authenticated): `folder[1]=auth.uid()`。

`folder` = `storage.foldername(name)`。

## タスク分割（実装レーン）

### レーンA: Supabase migrations + RLS テスト
1. `20260829000000_storage_private_and_policies.sql`（上記）
2. `20260829000100_create_app_config.sql`: 単一行 CHECK(id=1)、`min_supported_version text NOT NULL DEFAULT '1.0.0'`, `latest_version text`, `ios_store_url text`, `android_store_url text`, `update_message text`, `updated_at`。RLS: SELECT to anon+authenticated USING(true) のみ。seed 行 INSERT。
3. `20260829000200_normalize_storage_urls_to_paths.sql`: 6カラムの URL→パス正規化（対象は `%/storage/v1/object/public/<bucket>/%` にマッチする要素のみ）
4. `20260829000300_cleanup_ai_images.sql`: `find_orphan_ai_images(cutoff interval)` SQL 関数（messages.image_urls / meal_records.images に `LIKE '%'||name` で未参照判定。EXECUTE は service_role のみ）+ pg_cron ジョブ `cleanup-ai-images`（20260710020000 の Vault + $cmd$ + 存在チェック + inactive パターン踏襲、日次、body `{"dry_run": false}`）
5. `supabase/tests/storage_policies_rls_test.sql`（device_tokens_rls_test.sql パターン。storage.objects へ postgres で試験行 INSERT → anon/本人/担当トレーナー/他人で SELECT/INSERT 可否検証）

### レーンB: Edge Functions
1. `estimate-meal-nutrition`: `image_urls` の各要素を URL/パス両対応でパス化 → service_role client で `createSignedUrl(path, 600)` → Anthropic へ `source:{type:'url', url:署名URL}`。署名失敗時は該当画像スキップ + 全滅なら既存エラー系（ESTIMATION_FAILED）へ。
2. `cleanup-ai-images` 新設: Bearer service_role 認証（auto-skip-workouts パターン）。body `{dry_run?: boolean}`（省略時 true）。`find_orphan_ai_images('48 hours')` RPC → dry_run なら一覧返却、false なら `storage.remove()`（バッチ・ベストエフォート）+ 件数返却。
3. `parse-message-tags` は無変更（値の透過コピーのため）を確認のみ。

### レーンC: Mobile Storage（fit-connect-mobile）
1. `StorageService`: upload 系の戻り値を**パス**に変更（`uploadImage`/`uploadImages`/`uploadAiImage`/`uploadAiImages`/`uploadProfileImage`）。`uploadProfileImage` は `{uid}/avatar_{ts}.jpg` + 旧ファイル削除。パスベースの `deleteByPath(bucket, path)` 新設。URL→パス抽出をヘルパーへ移管。
2. 署名URL解決層の新設: `resolveStorageValue` 純関数（URL/パス/外部URL判定 + パス抽出、単体テスト付き）+ 署名URLキャッシュ付き provider/service + 共通 `StorageImage` ウィジェット（`CachedNetworkImage`、`cacheKey=bucket/path`、エラーフォールバック）。
3. 表示置換: message_bubble（添付+トレーナーアバター）、meal_card、full_screen_image_viewer（値+バケットを受けて内部解決）、meal_estimation_confirm_view、settings_screen アバター、trainer_status_card、trainer_confirm_screen、client_note_detail_screen（画像表示 + PDF は署名URLで url_launcher 起動）。
4. パス保存: message_repository.sendMessage はパスを INSERT（chat_input → provider の透過はそのまま）。registration_provider / client_repository.updateProfileImageUrl はパス保存（Google 外部URLはそのまま）。
5. AI推定: `meal_estimation_api` にパスを渡す。`structured_tag_form` の `_fileToUrlMap` はパス管理に変更。
6. orphan 8-B: AI推定フローのキャンセル（loading キャンセル・confirm の戻る・フォーム dispose）で未送信のアップロード済み AI 画像を fire-and-forget 削除。**送信完了フラグでガード**（挿入済みは削除しない）。chat_input の通常写真は送信直前アップロードのため対象外。
7. build_runner はレーン完了後にマネージャーが一括実行（エージェントは実行しない）。

### レーンD: Mobile 強制アップデート（レーンC完了後に着手）
1. pubspec に `package_info_plus` 追加（SDK 制約変更禁止・`fvm flutter pub get`）。
2. `lib/features/app_update/`: `data/app_config_repository.dart`（consent_repository パターン）、`providers/force_update_provider.dart`（判定は純関数 `isUpdateRequired(current, min)` に分離 + 単体テスト。ビルド番号 `+n` 除去、major.minor.patch 数値比較）、`presentation/force_update_dialog.dart`（consent_dialog パターン、ストアURL null なら文言のみ）。
3. `app.dart` の `MyApp.build`: `home:` を新規 `AppUpdateGate` でラップ（変更は最小行。`_AuthLoadingScreenState` には触れない）。fail-open（例外・タイムアウト時は通常起動）。
4. 設定画面にアプリバージョン表示行を追加（package_info_plus 導入の副産物、任意）。

### レーンE: Web（fit-connect）
1. `src/lib/supabase/storagePaths.ts` 新設: `extractStoragePath(value, bucket)` / `isExternalUrl` / `splitFragment`（純関数、vitest）+ `getSignedStorageUrl(value, bucket)`（ブラウザクライアント createSignedUrl + モジュールキャッシュ）+ `useStorageUrl(value, bucket)` フック + `<StorageImg>`。
2. upload 3種をパス返却に変更（notes/profile は `パス#ファイル名`）。
3. 表示置換: MessageBubble・RecordCard・ImageModal・ChatHeader・ClientListItem・ClientCard（unoptimized 化）・ProfileAvatar・ClientReportHeader・IssuedTicketList・SubscriptionList・ProfileSection・MealTab・WeightTab・NotesTab・Create/EditNoteModal・message/page.tsx（楽観的 state・返信プレビュー含む）。
4. `isPdf`/`getFileName`（NotesTab 等）: フラグメント除去後の**パス**で判定する実装に変更。
5. 削除経路の両対応: `deleteNoteFile.ts` と `/api/client-notes/[id]` DELETE を「フルURL or パス」両対応に。
6. `types/client.ts` / `types/trainer.ts` にセマンティクス変更コメント（パス保存・レガシーURL共存）。

### 統合・QA（マネージャー実施）
1. `dart run build_runner build` → `fvm flutter analyze` → `fvm flutter test`
2. Web: `tsc --noEmit` / vitest / lint / `next build`（dev サーバー停止確認後）
3. `supabase db reset`（Docker）+ storage RLS テスト
4. リモート適用: `supabase db push` + Edge Functions deploy（estimate-meal-nutrition / cleanup-ai-images）
5. chrome-web-qa / ios-simulator-qa（リモートに対して E2E: メッセージ写真送受信表示・アバター・カルテ添付・AI推定）
6. cleanup-ai-images を dry_run で手動実行し、削除候補が「未参照 /ai/ のみ」であることを確認（cron は inactive のまま = 有効化はオーナー判断）
7. `docs/tasks/IMPLEMENTATION_TASKS.md` 8.2 更新・lessons.md 追記

## 既知のリスクと対応

- **旧バイナリのアプリは private 化後、画像表示が壊れる**（開発段階のため許容。強制アップデート機構が今後の同種移行の前提を整備）
- Anthropic 側 fetch までの署名 TTL は 600 秒で十分（推定30秒タイムアウト）
- Realtime 受信メッセージも表示層で解決するため壊れない（解決はレンダリング層に置く）
- Seed の架空パス（`meals/…`）はヘルパーが null フォールバック
- `docs/tasks/2026-05-09-task-2.3-image-meal-estimation-plan.md` の「URL直渡し」記述は本変更で旧設計になる
