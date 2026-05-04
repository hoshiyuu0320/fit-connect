-- トレーナーの課金プラン (Stage 1: 'free' / 'pro' のみ。将来Stripe連携時に拡張)
ALTER TABLE "public"."trainers"
  ADD COLUMN "subscription_plan" text NOT NULL DEFAULT 'free'
    CHECK ("subscription_plan" IN ('free', 'pro'));

COMMENT ON COLUMN "public"."trainers"."subscription_plan" IS 'サブスクリプションプラン。pro でAI機能解放。Stripe連携時に自動更新する想定';
