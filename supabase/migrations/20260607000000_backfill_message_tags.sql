-- 既存 messages の tags を content から補完する（基盤フェーズ「tags統一」）。
-- 対象: cardinality(tags)=0（タグ未設定）かつ content が既知の記録パターン。
-- 正準形は '#' 付き（messages.tags コメント準拠）。
-- 既存 *_records には一切触れない（tags カラムのみ更新）。
-- tags のみのUPDATEは content列変更時のみ発火するwebhookトリガを誘発しないため安全。
-- POSIX正規表現（否定先読み非対応のため !~ で代替）。content先頭一致(^)で誤検出を防止。

BEGIN;

-- 食事（detail あり）: '#食事:朝食 …' → '#食事:朝食'
UPDATE "public"."messages"
SET tags = ARRAY['#食事:' || substring(content from '^#食事:([^[:space:]]+)')]
WHERE cardinality(tags) = 0
  AND content ~ '^#食事:[^[:space:]]+';

-- 食事（detail なし）: 本文キーワードから種別を判定（送信側 parseMessageTags と同じ）
UPDATE "public"."messages"
SET tags = ARRAY[CASE
  WHEN content ~ '朝食|breakfast' THEN '#食事:朝食'
  WHEN content ~ '昼食|lunch'     THEN '#食事:昼食'
  WHEN content ~ '夕食|dinner'    THEN '#食事:夕食'
  WHEN content ~ '間食|snack'     THEN '#食事:間食'
  ELSE '#食事'
END]
WHERE cardinality(tags) = 0
  AND content ~ '^#食事'
  AND content !~ '^#食事:';

-- 体重: '^#体重' → '#体重'
UPDATE "public"."messages"
SET tags = ARRAY['#体重']
WHERE cardinality(tags) = 0
  AND content ~ '^#体重';

-- 運動（detail あり）: '#運動:筋トレ …' / '#運動:完了 …' → '#運動:筋トレ' / '#運動:完了'
UPDATE "public"."messages"
SET tags = ARRAY['#運動:' || substring(content from '^#運動:([^[:space:]]+)')]
WHERE cardinality(tags) = 0
  AND content ~ '^#運動:[^[:space:]]+';

-- 運動（detail なし）: 本文キーワードから種別を判定（送信側 parseMessageTags と同じ）
UPDATE "public"."messages"
SET tags = ARRAY[CASE
  WHEN content ~ '完了'       THEN '#運動:完了'
  WHEN content ~ '筋トレ'     THEN '#運動:筋トレ'
  WHEN content ~ 'ランニング' THEN '#運動:ランニング'
  WHEN content ~ '有酸素'     THEN '#運動:有酸素'
  ELSE '#運動'
END]
WHERE cardinality(tags) = 0
  AND content ~ '^#運動'
  AND content !~ '^#運動:';

-- ワークアウト達成（#なし現行モバイル形式）→ '#運動:完了'
UPDATE "public"."messages"
SET tags = ARRAY['#運動:完了']
WHERE cardinality(tags) = 0
  AND content LIKE '本日のワークアウトプラン「%」を達成しました！%';

COMMIT;
