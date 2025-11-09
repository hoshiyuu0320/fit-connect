-- ================================================
-- FIT-CONNECT 顧客管理機能 マイグレーションSQL
-- ================================================
-- 作成日: 2025-11-02
-- 説明: 顧客管理機能に必要なテーブル作成とclientsテーブルの拡張
-- ================================================

-- 1. clientsテーブルの拡張
-- ================================================

-- 新しいカラムを追加
ALTER TABLE public.clients
ADD COLUMN IF NOT EXISTS gender text NOT NULL DEFAULT 'other',
ADD COLUMN IF NOT EXISTS age integer NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS occupation text,
ADD COLUMN IF NOT EXISTS height numeric NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS target_weight numeric NOT NULL DEFAULT 0,
ADD COLUMN IF NOT EXISTS purpose text NOT NULL DEFAULT 'health_improvement',
ADD COLUMN IF NOT EXISTS goal_description text,
ADD COLUMN IF NOT EXISTS profile_image_url text;

-- nameカラムをNOT NULLに変更（既存データがある場合は事前に確認が必要）
ALTER TABLE public.clients
ALTER COLUMN name SET NOT NULL;

-- CHECK制約を追加
ALTER TABLE public.clients
ADD CONSTRAINT check_gender CHECK (gender IN ('male', 'female', 'other')),
ADD CONSTRAINT check_purpose CHECK (purpose IN ('diet', 'contest', 'body_make', 'health_improvement', 'mental_improvement', 'performance_improvement')),
ADD CONSTRAINT check_age CHECK (age > 0 AND age < 150),
ADD CONSTRAINT check_height CHECK (height > 0 AND height < 300),
ADD CONSTRAINT check_target_weight CHECK (target_weight > 0 AND target_weight < 500);

-- trainer_idの外部キー制約を追加（まだ存在しない場合）
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'clients_trainer_id_fkey'
    ) THEN
        ALTER TABLE public.clients
        ADD CONSTRAINT clients_trainer_id_fkey
        FOREIGN KEY (trainer_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
END $$;

-- インデックスを追加
CREATE INDEX IF NOT EXISTS idx_clients_trainer_id ON public.clients(trainer_id);
CREATE INDEX IF NOT EXISTS idx_clients_gender ON public.clients(gender);
CREATE INDEX IF NOT EXISTS idx_clients_purpose ON public.clients(purpose);

-- コメントを追加
COMMENT ON COLUMN public.clients.gender IS '性別 (male: 男性, female: 女性, other: その他)';
COMMENT ON COLUMN public.clients.age IS '年齢';
COMMENT ON COLUMN public.clients.occupation IS '職業';
COMMENT ON COLUMN public.clients.height IS '身長 (cm)';
COMMENT ON COLUMN public.clients.target_weight IS '目標体重 (kg)';
COMMENT ON COLUMN public.clients.purpose IS '目的 (diet: ダイエット, contest: コンテスト, body_make: ボディメイク, health_improvement: 健康維持・生活習慣の改善, mental_improvement: メンタル・自己肯定感向上, performance_improvement: パフォーマンス向上)';
COMMENT ON COLUMN public.clients.goal_description IS '目標の詳細説明（トレーナーが記入）';
COMMENT ON COLUMN public.clients.profile_image_url IS 'プロフィール画像URL (Supabase Storage)';

-- ================================================
-- 2. weight_recordsテーブルの作成
-- ================================================

CREATE TABLE IF NOT EXISTS public.weight_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
    weight numeric NOT NULL CHECK (weight > 0 AND weight < 500),
    recorded_at timestamptz NOT NULL DEFAULT now()
);

-- インデックスを作成
CREATE INDEX IF NOT EXISTS idx_weight_records_client_recorded
ON public.weight_records(client_id, recorded_at DESC);

-- RLSを有効化
ALTER TABLE public.weight_records ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: トレーナーは自分のクライアントの体重記録のみアクセス可能
CREATE POLICY weight_records_trainer_select
ON public.weight_records
FOR SELECT
USING (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

-- コメントを追加
COMMENT ON TABLE public.weight_records IS 'クライアントの体重記録';
COMMENT ON COLUMN public.weight_records.id IS '記録ID';
COMMENT ON COLUMN public.weight_records.client_id IS 'クライアントID';
COMMENT ON COLUMN public.weight_records.weight IS '体重 (kg)';
COMMENT ON COLUMN public.weight_records.recorded_at IS '記録日時';

-- ================================================
-- 3. meal_recordsテーブルの作成
-- ================================================

CREATE TABLE IF NOT EXISTS public.meal_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
    meal_type text NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    description text,
    calories numeric CHECK (calories IS NULL OR calories >= 0),
    images text[] CHECK (images IS NULL OR array_length(images, 1) <= 10),
    recorded_at timestamptz NOT NULL DEFAULT now()
);

-- インデックスを作成
CREATE INDEX IF NOT EXISTS idx_meal_records_client_recorded
ON public.meal_records(client_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_meal_records_client_meal_type
ON public.meal_records(client_id, meal_type);

-- RLSを有効化
ALTER TABLE public.meal_records ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: トレーナーは自分のクライアントの食事記録のみアクセス可能
CREATE POLICY meal_records_trainer_select
ON public.meal_records
FOR SELECT
USING (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

-- コメントを追加
COMMENT ON TABLE public.meal_records IS 'クライアントの食事記録';
COMMENT ON COLUMN public.meal_records.id IS '記録ID';
COMMENT ON COLUMN public.meal_records.client_id IS 'クライアントID';
COMMENT ON COLUMN public.meal_records.meal_type IS '食事区分 (breakfast: 朝食, lunch: 昼食, dinner: 夕食, snack: 間食)';
COMMENT ON COLUMN public.meal_records.description IS 'メモ・説明';
COMMENT ON COLUMN public.meal_records.calories IS 'カロリー (kcal) ※自動算出または手動入力';
COMMENT ON COLUMN public.meal_records.images IS '画像URL配列 (Supabase Storage、最大10枚)';
COMMENT ON COLUMN public.meal_records.recorded_at IS '記録日時';

-- ================================================
-- 4. exercise_recordsテーブルの作成
-- ================================================

CREATE TABLE IF NOT EXISTS public.exercise_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
    exercise_type text NOT NULL CHECK (exercise_type IN ('walking', 'running', 'strength_training', 'cycling', 'swimming', 'yoga', 'pilates', 'other')),
    duration integer CHECK (duration IS NULL OR duration > 0),
    distance numeric CHECK (distance IS NULL OR distance > 0),
    calories numeric CHECK (calories IS NULL OR calories >= 0),
    memo text,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT check_duration_or_distance CHECK (duration IS NOT NULL OR distance IS NOT NULL)
);

-- インデックスを作成
CREATE INDEX IF NOT EXISTS idx_exercise_records_client_recorded
ON public.exercise_records(client_id, recorded_at DESC);

CREATE INDEX IF NOT EXISTS idx_exercise_records_client_exercise_type
ON public.exercise_records(client_id, exercise_type);

-- RLSを有効化
ALTER TABLE public.exercise_records ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: トレーナーは自分のクライアントの運動記録のみアクセス可能
CREATE POLICY exercise_records_trainer_select
ON public.exercise_records
FOR SELECT
USING (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

-- コメントを追加
COMMENT ON TABLE public.exercise_records IS 'クライアントの運動記録';
COMMENT ON COLUMN public.exercise_records.id IS '記録ID';
COMMENT ON COLUMN public.exercise_records.client_id IS 'クライアントID';
COMMENT ON COLUMN public.exercise_records.exercise_type IS '運動種目 (walking: ウォーキング, running: ランニング, strength_training: 筋力トレーニング, cycling: サイクリング, swimming: スイミング, yoga: ヨガ, pilates: ピラティス, other: その他)';
COMMENT ON COLUMN public.exercise_records.duration IS '運動時間 (分)';
COMMENT ON COLUMN public.exercise_records.distance IS '距離 (km)';
COMMENT ON COLUMN public.exercise_records.calories IS '消費カロリー (kcal)';
COMMENT ON COLUMN public.exercise_records.memo IS 'メモ';
COMMENT ON COLUMN public.exercise_records.recorded_at IS '記録日時';

-- ================================================
-- 5. ticketsテーブルの作成
-- ================================================

CREATE TABLE IF NOT EXISTS public.tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
    ticket_name text NOT NULL,
    ticket_type text NOT NULL,
    total_sessions integer NOT NULL CHECK (total_sessions > 0),
    remaining_sessions integer NOT NULL CHECK (remaining_sessions >= 0 AND remaining_sessions <= total_sessions),
    valid_from date NOT NULL,
    valid_until date NOT NULL CHECK (valid_from <= valid_until),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- インデックスを作成
CREATE INDEX IF NOT EXISTS idx_tickets_client_id
ON public.tickets(client_id);

CREATE INDEX IF NOT EXISTS idx_tickets_valid_until
ON public.tickets(valid_until);

-- RLSを有効化
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: トレーナーは自分のクライアントのチケットのみアクセス可能
CREATE POLICY tickets_trainer_select
ON public.tickets
FOR SELECT
USING (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

-- RLSポリシー: トレーナーは自分のクライアントのチケットを作成・更新可能
CREATE POLICY tickets_trainer_insert
ON public.tickets
FOR INSERT
WITH CHECK (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

CREATE POLICY tickets_trainer_update
ON public.tickets
FOR UPDATE
USING (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
)
WITH CHECK (
    client_id IN (
        SELECT client_id FROM public.clients WHERE trainer_id = auth.uid()
    )
);

-- コメントを追加
COMMENT ON TABLE public.tickets IS 'クライアントが保有するセッション回数券';
COMMENT ON COLUMN public.tickets.id IS 'チケットID';
COMMENT ON COLUMN public.tickets.client_id IS 'クライアントID';
COMMENT ON COLUMN public.tickets.ticket_name IS 'チケット名';
COMMENT ON COLUMN public.tickets.ticket_type IS 'チケット種別';
COMMENT ON COLUMN public.tickets.total_sessions IS '総セッション数';
COMMENT ON COLUMN public.tickets.remaining_sessions IS '残りセッション数';
COMMENT ON COLUMN public.tickets.valid_from IS '有効期限開始日';
COMMENT ON COLUMN public.tickets.valid_until IS '有効期限終了日';
COMMENT ON COLUMN public.tickets.created_at IS '購入日時';

-- ================================================
-- マイグレーション完了
-- ================================================
-- 注意事項:
-- 1. 既存のclientsテーブルにデータがある場合、デフォルト値で新しいカラムが埋められます
-- 2. 実運用前に、既存データを適切な値に更新する必要があります
-- 3. RLSポリシーは現状SELECT/INSERT/UPDATEのみ。DELETEポリシーは必要に応じて追加してください
-- ================================================
