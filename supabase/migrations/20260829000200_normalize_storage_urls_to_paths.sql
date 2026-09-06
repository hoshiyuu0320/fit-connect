-- =============================================================================
-- Migration: normalize_storage_urls_to_paths
-- フェーズ8.2: DB 保存済みの Storage 公開URLをバケット相対パスへ正規化する
--
-- 仕様出典: docs/tasks/2026-08-29-storage-private-plan.md 設計判断2・7
--   カラム↔バケット対応（固定）:
--     - messages.image_urls / meal_records.images / exercise_records.images
--         → message-photos
--     - client_notes.file_urls  → client-notes（値の `#encodeURIComponent(元ファイル名)`
--         フラグメントは保全する）
--     - clients.profile_image_url → client-avatars（`?t=timestamp` キャッシュバスターは
--         除去。Google 等の外部URLはそのまま通す）
--     - trainers.profile_image_url → profile-images（`#元ファイル名` フラグメントは保全。
--         外部URLはそのまま通す）
--
-- 変換規則:
--   - 対象は '%/storage/v1/object/public/<バケット>/%' にマッチする要素のみ。
--     外部URL（Google アバター等）・既にパス化済みの値は変更しない = 冪等
--     （変換後の値はマーカーを含まないため、再実行しても無害）
--   - 変換は URL 先頭〜バケット名までのプレフィックスを除去するだけなので、
--     `#フラグメント` は自然に保全される
--   - text[] カラムは unnest WITH ORDINALITY + array_agg(ORDER BY ordinality) で
--     要素順を保ったまま要素ごとに変換する
--
-- 副作用の確認済み事項:
--   - messages の UPDATE トリガー on_message_update は AFTER UPDATE OF content のため
--     image_urls のみの UPDATE では発火しない（parse-message-tags は呼ばれない）
--   - clients の enforce_client_limit_trigger は UPDATE OF trainer_id のため発火しない
--   - set_updated_at 系トリガーによる updated_at の更新のみ発生する（許容）
--
-- 切り戻し: storage.buckets の public=true 復帰で旧URL形式も再び有効になるうえ、
--   表示ヘルパーはパス値も署名できるため、本 migration 適用後もロールバック可能。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. messages.image_urls（text[] → message-photos のパス）
-- -----------------------------------------------------------------------------
UPDATE public.messages m
SET image_urls = (
  SELECT array_agg(
           CASE
             WHEN t.elem LIKE '%/storage/v1/object/public/message-photos/%'
               THEN regexp_replace(t.elem, '^.*/storage/v1/object/public/message-photos/', '')
             ELSE t.elem
           END
           ORDER BY t.ord
         )
  FROM unnest(m.image_urls) WITH ORDINALITY AS t(elem, ord)
)
WHERE EXISTS (
  SELECT 1 FROM unnest(m.image_urls) AS e(elem)
  WHERE e.elem LIKE '%/storage/v1/object/public/message-photos/%'
);

-- -----------------------------------------------------------------------------
-- 2. meal_records.images（text[] → message-photos のパス）
--    parse-message-tags が messages.image_urls をコピーした値のため同じバケット
-- -----------------------------------------------------------------------------
UPDATE public.meal_records r
SET images = (
  SELECT array_agg(
           CASE
             WHEN t.elem LIKE '%/storage/v1/object/public/message-photos/%'
               THEN regexp_replace(t.elem, '^.*/storage/v1/object/public/message-photos/', '')
             ELSE t.elem
           END
           ORDER BY t.ord
         )
  FROM unnest(r.images) WITH ORDINALITY AS t(elem, ord)
)
WHERE EXISTS (
  SELECT 1 FROM unnest(r.images) AS e(elem)
  WHERE e.elem LIKE '%/storage/v1/object/public/message-photos/%'
);

-- -----------------------------------------------------------------------------
-- 3. exercise_records.images（text[] → message-photos のパス）
--    リモート実測 0 行だが、将来の再実行・fresh DB でも安全なため対称に処理する
-- -----------------------------------------------------------------------------
UPDATE public.exercise_records r
SET images = (
  SELECT array_agg(
           CASE
             WHEN t.elem LIKE '%/storage/v1/object/public/message-photos/%'
               THEN regexp_replace(t.elem, '^.*/storage/v1/object/public/message-photos/', '')
             ELSE t.elem
           END
           ORDER BY t.ord
         )
  FROM unnest(r.images) WITH ORDINALITY AS t(elem, ord)
)
WHERE EXISTS (
  SELECT 1 FROM unnest(r.images) AS e(elem)
  WHERE e.elem LIKE '%/storage/v1/object/public/message-photos/%'
);

-- -----------------------------------------------------------------------------
-- 4. client_notes.file_urls（text[] → client-notes のパス。#フラグメント保全）
--    値は `パス#encodeURIComponent(元ファイル名)` 形式になる（プレフィックス除去のみ
--    のため `#` 以降はそのまま残る）
-- -----------------------------------------------------------------------------
UPDATE public.client_notes n
SET file_urls = (
  SELECT array_agg(
           CASE
             WHEN t.elem LIKE '%/storage/v1/object/public/client-notes/%'
               THEN regexp_replace(t.elem, '^.*/storage/v1/object/public/client-notes/', '')
             ELSE t.elem
           END
           ORDER BY t.ord
         )
  FROM unnest(n.file_urls) WITH ORDINALITY AS t(elem, ord)
)
WHERE EXISTS (
  SELECT 1 FROM unnest(n.file_urls) AS e(elem)
  WHERE e.elem LIKE '%/storage/v1/object/public/client-notes/%'
);

-- -----------------------------------------------------------------------------
-- 5. clients.profile_image_url（text → client-avatars のパス。?t= クエリ除去）
--    Google アバター等の外部URLは WHERE 句にマッチしないため不変
-- -----------------------------------------------------------------------------
UPDATE public.clients
SET profile_image_url = regexp_replace(
      regexp_replace(profile_image_url, '^.*/storage/v1/object/public/client-avatars/', ''),
      '\?.*$', ''
    )
WHERE profile_image_url LIKE '%/storage/v1/object/public/client-avatars/%';

-- -----------------------------------------------------------------------------
-- 6. trainers.profile_image_url（text → profile-images のパス。#フラグメント保全）
--    外部URLは WHERE 句にマッチしないため不変
-- -----------------------------------------------------------------------------
UPDATE public.trainers
SET profile_image_url = regexp_replace(
      profile_image_url, '^.*/storage/v1/object/public/profile-images/', ''
    )
WHERE profile_image_url LIKE '%/storage/v1/object/public/profile-images/%';
