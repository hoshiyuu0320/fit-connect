-- Migration: onboarding_and_ai_consent
-- 目的: フェーズ3 オンボーディングフロー（cat2 3-A）の DB 土台を整備する。
--   1. clients.onboarding_completed_at を追加（オンボーディング完了時刻）
--   2. user_consents.document の CHECK 制約を ('terms','privacy') →
--      ('terms','privacy','ai_processing') に拡張
--      （健康データの AI 送信への顧客本人の明示同意。横断レビュー1-6節対応）

-- ============================================================
-- 1. clients.onboarding_completed_at
-- ============================================================
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS onboarding_completed_at timestamptz;

COMMENT ON COLUMN public.clients.onboarding_completed_at IS
  'オンボーディング完了時刻（cat2 3-A）。Mobile が本人 RLS（clients_update_own）で自行を UPDATE する。NULL = 未完了。既存ユーザーは NULL のままでよく、新規登録フローのみが書く';

-- ============================================================
-- 2. user_consents.document CHECK 制約の張り替え
-- ============================================================
-- 既存制約は 20260711000000_create_user_consents.sql のインラインカラム CHECK
-- （自動命名: user_consents_document_check）。
-- pg_constraint ガード付きで冪等に DROP + ADD する（20260712000000 のパターン踏襲）。

DO $$
BEGIN
  -- 'ai_processing' を含まない旧定義のときだけ DROP（再実行時は no-op）
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_consents_document_check'
      AND conrelid = 'public.user_consents'::regclass
      AND pg_get_constraintdef(oid) NOT LIKE '%ai_processing%'
  ) THEN
    ALTER TABLE public.user_consents DROP CONSTRAINT user_consents_document_check;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_consents_document_check'
      AND conrelid = 'public.user_consents'::regclass
  ) THEN
    ALTER TABLE public.user_consents
      ADD CONSTRAINT user_consents_document_check
      CHECK (document IN ('terms', 'privacy', 'ai_processing'));
  END IF;
END $$;

COMMENT ON COLUMN public.user_consents.document IS
  '同意対象ドキュメント（terms / privacy / ai_processing）。''ai_processing'' は健康データ（食事写真・体重等）を AI 解析のため外部 API（Anthropic）へ送信することへの顧客本人の明示同意（横断レビュー1-6節対応）';
