

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_rate NUMERIC;
BEGIN
  -- クライアント情報取得
  SELECT initial_weight, target_weight 
  INTO v_initial_weight, v_target_weight
  FROM clients
  WHERE client_id = p_client_id;
  
  -- 目標が設定されていない場合
  IF v_initial_weight IS NULL OR v_target_weight IS NULL THEN
    RETURN 0;
  END IF;
  
  -- 開始時と目標が同じ場合
  IF v_initial_weight = v_target_weight THEN
    RETURN 0;
  END IF;
  
  -- 達成率計算
  v_rate := (v_initial_weight - p_current_weight) / 
            (v_initial_weight - v_target_weight) * 100;
  
  -- 0%〜100%の範囲に制限
  v_rate := GREATEST(0, LEAST(100, v_rate));
  
  RETURN ROUND(v_rate, 1);
END;
$$;


ALTER FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) IS '目標達成率を計算（0〜100%）';



CREATE OR REPLACE FUNCTION "public"."can_edit_message"("message_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  msg_created_at TIMESTAMPTZ;
BEGIN
  SELECT created_at INTO msg_created_at 
  FROM messages 
  WHERE id = message_id;
  
  IF msg_created_at IS NULL THEN
    RETURN false;
  END IF;
  
  RETURN (NOW() - msg_created_at) < INTERVAL '5 minutes';
END;
$$;


ALTER FUNCTION "public"."can_edit_message"("message_id" "uuid") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."can_edit_message"("message_id" "uuid") IS 'メッセージが編集可能か（5分以内）を判定';



CREATE OR REPLACE FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_is_achieved BOOLEAN;
BEGIN
  -- クライアント情報取得
  SELECT initial_weight, target_weight 
  INTO v_initial_weight, v_target_weight
  FROM clients
  WHERE client_id = p_client_id;
  
  -- 目標が設定されていない場合
  IF v_initial_weight IS NULL OR v_target_weight IS NULL THEN
    RETURN false;
  END IF;
  
  -- 減量目標の場合
  IF v_initial_weight > v_target_weight THEN
    v_is_achieved := p_current_weight <= v_target_weight;
  -- 増量目標の場合
  ELSE
    v_is_achieved := p_current_weight >= v_target_weight;
  END IF;
  
  RETURN v_is_achieved;
END;
$$;


ALTER FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) IS '目標達成判定（減量・増量両対応）';



CREATE OR REPLACE FUNCTION "public"."update_sessions_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_sessions_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."clients" (
    "client_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "trainer_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "line_user_id" "text",
    "gender" "text" DEFAULT 'other'::"text" NOT NULL,
    "age" integer DEFAULT 25 NOT NULL,
    "occupation" "text",
    "height" numeric DEFAULT 170 NOT NULL,
    "target_weight" numeric DEFAULT 60 NOT NULL,
    "purpose" "text" DEFAULT 'health_improvement'::"text" NOT NULL,
    "goal_description" "text",
    "profile_image_url" "text",
    "initial_weight" numeric,
    "goal_deadline" "date",
    "goal_set_at" timestamp with time zone DEFAULT "now"(),
    "goal_achieved_at" timestamp with time zone,
    CONSTRAINT "check_age" CHECK ((("age" > 0) AND ("age" < 150))),
    CONSTRAINT "check_gender" CHECK (("gender" = ANY (ARRAY['male'::"text", 'female'::"text", 'other'::"text"]))),
    CONSTRAINT "check_height" CHECK ((("height" > (0)::numeric) AND ("height" < (300)::numeric))),
    CONSTRAINT "check_purpose" CHECK (("purpose" = ANY (ARRAY['diet'::"text", 'contest'::"text", 'body_make'::"text", 'health_improvement'::"text", 'mental_improvement'::"text", 'performance_improvement'::"text"]))),
    CONSTRAINT "check_target_weight" CHECK ((("target_weight" > (0)::numeric) AND ("target_weight" < (500)::numeric))),
    CONSTRAINT "clients_initial_weight_check" CHECK ((("initial_weight" > (0)::numeric) AND ("initial_weight" < (500)::numeric)))
);


ALTER TABLE "public"."clients" OWNER TO "postgres";


COMMENT ON TABLE "public"."clients" IS '顧客マスタ';



COMMENT ON COLUMN "public"."clients"."line_user_id" IS 'LINEログインしたユーザーのID';



COMMENT ON COLUMN "public"."clients"."gender" IS '性別 (male: 男性, female: 女性, other: その他)';



COMMENT ON COLUMN "public"."clients"."age" IS '年齢';



COMMENT ON COLUMN "public"."clients"."occupation" IS '職業';



COMMENT ON COLUMN "public"."clients"."height" IS '身長 (cm)';



COMMENT ON COLUMN "public"."clients"."target_weight" IS '目標体重 (kg)';



COMMENT ON COLUMN "public"."clients"."purpose" IS '目的 (diet: 
  ダイエット, contest: コンテスト, body_make: ボディメイク, 
  health_improvement: 健康維持・生活習慣の改善, mental_improvement:
   メンタル・自己肯定感向上, performance_improvement: 
  パフォーマンス向上)';



COMMENT ON COLUMN "public"."clients"."goal_description" IS '目標の詳細説明（トレーナーが記入）';



COMMENT ON COLUMN "public"."clients"."profile_image_url" IS 'プロフィール画像URL (Supabase Storage)';



COMMENT ON COLUMN "public"."clients"."initial_weight" IS '開始時体重 (kg) - トレーナーが初回面談時に設定';



COMMENT ON COLUMN "public"."clients"."goal_deadline" IS '目標達成期日（任意）';



COMMENT ON COLUMN "public"."clients"."goal_set_at" IS '目標設定日時';



COMMENT ON COLUMN "public"."clients"."goal_achieved_at" IS '目標達成日時 - 達成時に自動記録';



CREATE TABLE IF NOT EXISTS "public"."exercise_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "exercise_type" "text" NOT NULL,
    "duration" integer,
    "distance" numeric,
    "calories" numeric,
    "memo" "text",
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'manual'::"text",
    "message_id" "uuid",
    "images" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "check_duration_or_distance" CHECK ((("duration" IS NOT NULL) OR ("distance" IS NOT NULL))),
    CONSTRAINT "exercise_records_calories_check" CHECK ((("calories" IS NULL) OR ("calories" >= (0)::numeric))),
    CONSTRAINT "exercise_records_distance_check" CHECK ((("distance" IS NULL) OR ("distance" > (0)::numeric))),
    CONSTRAINT "exercise_records_duration_check" CHECK ((("duration" IS NULL) OR ("duration" > 0))),
    CONSTRAINT "exercise_records_exercise_type_check" CHECK (("exercise_type" = ANY (ARRAY['walking'::"text", 'running'::"text", 'strength_training'::"text", 'cardio'::"text", 'cycling'::"text", 'swimming'::"text", 'yoga'::"text", 'pilates'::"text", 'other'::"text"]))),
    CONSTRAINT "exercise_records_source_check" CHECK (("source" = ANY (ARRAY['manual'::"text", 'message'::"text"])))
);


ALTER TABLE "public"."exercise_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."exercise_records" IS 'クライアントの運動記録';



COMMENT ON COLUMN "public"."exercise_records"."id" IS '記録ID';



COMMENT ON COLUMN "public"."exercise_records"."client_id" IS 'クライアントID';



COMMENT ON COLUMN "public"."exercise_records"."exercise_type" IS '運動種目（cardioは有酸素運動全般）';



COMMENT ON COLUMN "public"."exercise_records"."duration" IS '運動時間 (分)';



COMMENT ON COLUMN "public"."exercise_records"."distance" IS '距離 (km)';



COMMENT ON COLUMN "public"."exercise_records"."calories" IS '消費カロリー (kcal)';



COMMENT ON COLUMN "public"."exercise_records"."memo" IS 'メモ';



COMMENT ON COLUMN "public"."exercise_records"."recorded_at" IS '記録日時';



COMMENT ON COLUMN "public"."exercise_records"."source" IS '記録元（manual: 手動入力, message: メッセージから自動作成）';



COMMENT ON COLUMN "public"."exercise_records"."message_id" IS '元メッセージID - メッセージから作成された記録の場合に設定';



COMMENT ON COLUMN "public"."exercise_records"."images" IS '画像URL配列（最大3枚） - Supabase Storageのパス';



CREATE TABLE IF NOT EXISTS "public"."meal_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "meal_type" "text" NOT NULL,
    "notes" "text",
    "calories" numeric,
    "images" "text"[],
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "source" "text" DEFAULT 'manual'::"text",
    "message_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "meal_records_calories_check" CHECK ((("calories" IS NULL) OR ("calories" >= (0)::numeric))),
    CONSTRAINT "meal_records_images_check" CHECK ((("images" IS NULL) OR ("array_length"("images", 1) <= 10))),
    CONSTRAINT "meal_records_meal_type_check" CHECK (("meal_type" = ANY (ARRAY['breakfast'::"text", 'lunch'::"text", 'dinner'::"text", 'snack'::"text"]))),
    CONSTRAINT "meal_records_source_check" CHECK (("source" = ANY (ARRAY['manual'::"text", 'message'::"text"])))
);


ALTER TABLE "public"."meal_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."meal_records" IS 'クライアントの食事記録';



COMMENT ON COLUMN "public"."meal_records"."id" IS '記録ID';



COMMENT ON COLUMN "public"."meal_records"."client_id" IS 'クライアントID';



COMMENT ON COLUMN "public"."meal_records"."meal_type" IS '食事区分 (breakfast: 朝食, lunch: 昼食, dinner: 夕食, snack: 間食)';



COMMENT ON COLUMN "public"."meal_records"."notes" IS 'メモ・説明（タグを除いたテキスト）';



COMMENT ON COLUMN "public"."meal_records"."calories" IS 'カロリー (kcal) ※自動算出または手動入力';



COMMENT ON COLUMN "public"."meal_records"."images" IS '画像URL配列 (Supabase Storage、最大10枚)';



COMMENT ON COLUMN "public"."meal_records"."recorded_at" IS '記録日時';



COMMENT ON COLUMN "public"."meal_records"."source" IS '記録元（manual: 手動入力, message: メッセージから自動作成）';



COMMENT ON COLUMN "public"."meal_records"."message_id" IS '元メッセージID - メッセージから作成された記録の場合に設定';



CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "sender_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "receiver_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "content" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sender_type" "text" DEFAULT ''::"text" NOT NULL,
    "receiver_type" "text" DEFAULT ''::"text" NOT NULL,
    "image_urls" "text"[] DEFAULT '{}'::"text"[],
    "tags" "text"[] DEFAULT '{}'::"text"[],
    "reply_to_message_id" "uuid",
    "read_at" timestamp with time zone,
    "edited_at" timestamp with time zone,
    "is_edited" boolean DEFAULT false,
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."messages" IS 'メッセージ';



COMMENT ON COLUMN "public"."messages"."content" IS 'メッセージ本文';



COMMENT ON COLUMN "public"."messages"."image_urls" IS '画像URL配列（最大3枚） - Supabase Storageのパス';



COMMENT ON COLUMN "public"."messages"."tags" IS 'タグ配列（例: ["#食事:昼食"]）';



COMMENT ON COLUMN "public"."messages"."reply_to_message_id" IS 'リプライ先メッセージID - トレーナーからのコメント機能';



COMMENT ON COLUMN "public"."messages"."edited_at" IS '編集時刻 - 5分以内の編集が可能';



CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "email" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."email" IS 'Email address of the user';



CREATE TABLE IF NOT EXISTS "public"."sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "trainer_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "session_date" timestamp with time zone NOT NULL,
    "duration_minutes" integer DEFAULT 60 NOT NULL,
    "status" "text" DEFAULT 'scheduled'::"text" NOT NULL,
    "session_type" "text",
    "memo" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "ticket_id" "uuid",
    CONSTRAINT "sessions_status_check" CHECK (("status" = ANY (ARRAY['scheduled'::"text", 'confirmed'::"text", 'completed'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tickets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "ticket_name" "text" NOT NULL,
    "ticket_type" "text" NOT NULL,
    "total_sessions" integer NOT NULL,
    "remaining_sessions" integer NOT NULL,
    "valid_from" "date" NOT NULL,
    "valid_until" "date" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tickets_check" CHECK ((("remaining_sessions" >= 0) AND ("remaining_sessions" <= "total_sessions"))),
    CONSTRAINT "tickets_check1" CHECK (("valid_from" <= "valid_until")),
    CONSTRAINT "tickets_total_sessions_check" CHECK (("total_sessions" > 0))
);


ALTER TABLE "public"."tickets" OWNER TO "postgres";


COMMENT ON TABLE "public"."tickets" IS 'クライアントが保有するセッション回数券';



COMMENT ON COLUMN "public"."tickets"."id" IS 'チケットID';



COMMENT ON COLUMN "public"."tickets"."client_id" IS 'クライアントID';



COMMENT ON COLUMN "public"."tickets"."ticket_name" IS 'チケット名';



COMMENT ON COLUMN "public"."tickets"."ticket_type" IS 'チケット種別';



COMMENT ON COLUMN "public"."tickets"."total_sessions" IS '総セッション数';



COMMENT ON COLUMN "public"."tickets"."remaining_sessions" IS '残りセッション数';



COMMENT ON COLUMN "public"."tickets"."valid_from" IS '有効期限開始日';



COMMENT ON COLUMN "public"."tickets"."valid_until" IS '有効期限終了日';



COMMENT ON COLUMN "public"."tickets"."created_at" IS '購入日時';



CREATE TABLE IF NOT EXISTS "public"."weight_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "weight" numeric NOT NULL,
    "recorded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text",
    "source" "text" DEFAULT 'manual'::"text",
    "message_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "weight_records_source_check" CHECK (("source" = ANY (ARRAY['manual'::"text", 'message'::"text"]))),
    CONSTRAINT "weight_records_weight_check" CHECK ((("weight" > (0)::numeric) AND ("weight" < (500)::numeric)))
);


ALTER TABLE "public"."weight_records" OWNER TO "postgres";


COMMENT ON TABLE "public"."weight_records" IS 'クライアントの体重記録';



COMMENT ON COLUMN "public"."weight_records"."id" IS '記録ID';



COMMENT ON COLUMN "public"."weight_records"."client_id" IS 'クライアントID';



COMMENT ON COLUMN "public"."weight_records"."weight" IS '体重 (kg)';



COMMENT ON COLUMN "public"."weight_records"."recorded_at" IS '記録日時';



COMMENT ON COLUMN "public"."weight_records"."notes" IS 'メモ（タグを除いたテキスト）';



COMMENT ON COLUMN "public"."weight_records"."source" IS '記録元（manual: 手動入力, message: メッセージから自動作成）';



COMMENT ON COLUMN "public"."weight_records"."message_id" IS '元メッセージID - メッセージから作成された記録の場合に設定';



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_line_user_id_key" UNIQUE ("line_user_id");



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_pkey" PRIMARY KEY ("client_id");



ALTER TABLE ONLY "public"."exercise_records"
    ADD CONSTRAINT "exercise_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."meal_records"
    ADD CONSTRAINT "meal_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."weight_records"
    ADD CONSTRAINT "weight_records_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_clients_gender" ON "public"."clients" USING "btree" ("gender");



CREATE INDEX "idx_clients_goal_deadline" ON "public"."clients" USING "btree" ("goal_deadline") WHERE ("goal_deadline" IS NOT NULL);



CREATE INDEX "idx_clients_purpose" ON "public"."clients" USING "btree" ("purpose");



CREATE INDEX "idx_clients_trainer_id" ON "public"."clients" USING "btree" ("trainer_id");



CREATE INDEX "idx_exercise_records_client_date" ON "public"."exercise_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_exercise_records_client_exercise_type" ON "public"."exercise_records" USING "btree" ("client_id", "exercise_type");



CREATE INDEX "idx_exercise_records_client_recorded" ON "public"."exercise_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_exercise_records_client_type" ON "public"."exercise_records" USING "btree" ("client_id", "exercise_type");



CREATE INDEX "idx_exercise_records_message" ON "public"."exercise_records" USING "btree" ("message_id") WHERE ("message_id" IS NOT NULL);



CREATE INDEX "idx_meal_records_client_date" ON "public"."meal_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_meal_records_client_meal_type" ON "public"."meal_records" USING "btree" ("client_id", "meal_type");



CREATE INDEX "idx_meal_records_client_recorded" ON "public"."meal_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_meal_records_client_type" ON "public"."meal_records" USING "btree" ("client_id", "meal_type");



CREATE INDEX "idx_meal_records_message" ON "public"."meal_records" USING "btree" ("message_id") WHERE ("message_id" IS NOT NULL);



CREATE INDEX "idx_messages_receiver_created" ON "public"."messages" USING "btree" ("receiver_id", "created_at" DESC);



CREATE INDEX "idx_messages_reply_to" ON "public"."messages" USING "btree" ("reply_to_message_id") WHERE ("reply_to_message_id" IS NOT NULL);



CREATE INDEX "idx_messages_sender_created" ON "public"."messages" USING "btree" ("sender_id", "created_at" DESC);



CREATE INDEX "idx_messages_tags" ON "public"."messages" USING "gin" ("tags");



CREATE INDEX "idx_sessions_client_id" ON "public"."sessions" USING "btree" ("client_id");



CREATE INDEX "idx_sessions_session_date" ON "public"."sessions" USING "btree" ("session_date");



CREATE INDEX "idx_sessions_status" ON "public"."sessions" USING "btree" ("status");



CREATE INDEX "idx_sessions_trainer_id" ON "public"."sessions" USING "btree" ("trainer_id");



CREATE INDEX "idx_tickets_client_id" ON "public"."tickets" USING "btree" ("client_id");



CREATE INDEX "idx_tickets_valid_until" ON "public"."tickets" USING "btree" ("valid_until");



CREATE INDEX "idx_weight_records_client_date" ON "public"."weight_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_weight_records_client_recorded" ON "public"."weight_records" USING "btree" ("client_id", "recorded_at" DESC);



CREATE INDEX "idx_weight_records_message" ON "public"."weight_records" USING "btree" ("message_id") WHERE ("message_id" IS NOT NULL);



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."exercise_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."meal_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "set_updated_at" BEFORE UPDATE ON "public"."weight_records" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



CREATE OR REPLACE TRIGGER "trigger_update_sessions_updated_at" BEFORE UPDATE ON "public"."sessions" FOR EACH ROW EXECUTE FUNCTION "public"."update_sessions_updated_at"();



ALTER TABLE ONLY "public"."clients"
    ADD CONSTRAINT "clients_trainer_id_fkey" FOREIGN KEY ("trainer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."exercise_records"
    ADD CONSTRAINT "exercise_records_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."exercise_records"
    ADD CONSTRAINT "exercise_records_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id");



ALTER TABLE ONLY "public"."meal_records"
    ADD CONSTRAINT "meal_records_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."meal_records"
    ADD CONSTRAINT "meal_records_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id");



ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_reply_to_message_id_fkey" FOREIGN KEY ("reply_to_message_id") REFERENCES "public"."messages"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_ticket_id_fkey" FOREIGN KEY ("ticket_id") REFERENCES "public"."tickets"("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_trainer_id_fkey" FOREIGN KEY ("trainer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."tickets"
    ADD CONSTRAINT "tickets_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weight_records"
    ADD CONSTRAINT "weight_records_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."weight_records"
    ADD CONSTRAINT "weight_records_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."messages"("id");



CREATE POLICY "LINEユーザー登録の許可_INSERT" ON "public"."clients" FOR INSERT TO "anon" WITH CHECK (true);



CREATE POLICY "LINEユーザー登録の許可_SELECT" ON "public"."clients" FOR SELECT TO "anon" USING (true);



CREATE POLICY "LINEユーザー登録の許可_UPDATE" ON "public"."clients" FOR UPDATE TO "anon" USING (true) WITH CHECK (true);



CREATE POLICY "Trainers can delete their own sessions" ON "public"."sessions" FOR DELETE USING (("auth"."uid"() = "trainer_id"));



CREATE POLICY "Trainers can insert their own sessions" ON "public"."sessions" FOR INSERT WITH CHECK (("auth"."uid"() = "trainer_id"));



CREATE POLICY "Trainers can update their own sessions" ON "public"."sessions" FOR UPDATE USING (("auth"."uid"() = "trainer_id"));



CREATE POLICY "Trainers can view their clients' exercise records" ON "public"."exercise_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."client_id" = "exercise_records"."client_id") AND ("clients"."trainer_id" = "auth"."uid"())))));



CREATE POLICY "Trainers can view their clients' meal records" ON "public"."meal_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."client_id" = "meal_records"."client_id") AND ("clients"."trainer_id" = "auth"."uid"())))));



CREATE POLICY "Trainers can view their clients' weight records" ON "public"."weight_records" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."clients"
  WHERE (("clients"."client_id" = "weight_records"."client_id") AND ("clients"."trainer_id" = "auth"."uid"())))));



CREATE POLICY "Trainers can view their own sessions" ON "public"."sessions" FOR SELECT USING (("auth"."uid"() = "trainer_id"));



CREATE POLICY "Users can edit own messages within 5 minutes" ON "public"."messages" FOR UPDATE USING ((("sender_id" = "auth"."uid"()) AND (("now"() - "created_at") < '00:05:00'::interval))) WITH CHECK (("sender_id" = "auth"."uid"()));



CREATE POLICY "Users can send messages" ON "public"."messages" FOR INSERT WITH CHECK (("sender_id" = "auth"."uid"()));



CREATE POLICY "Users can view their messages" ON "public"."messages" FOR SELECT USING ((("sender_id" = "auth"."uid"()) OR ("receiver_id" = "auth"."uid"())));



ALTER TABLE "public"."clients" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."exercise_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "exercise_records_trainer_select" ON "public"."exercise_records" FOR SELECT USING (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



ALTER TABLE "public"."meal_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "meal_records_trainer_select" ON "public"."meal_records" FOR SELECT USING (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."tickets" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tickets_trainer_insert" ON "public"."tickets" FOR INSERT WITH CHECK (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



CREATE POLICY "tickets_trainer_select" ON "public"."tickets" FOR SELECT USING (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



CREATE POLICY "tickets_trainer_update" ON "public"."tickets" FOR UPDATE USING (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"())))) WITH CHECK (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



ALTER TABLE "public"."weight_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "weight_records_trainer_select" ON "public"."weight_records" FOR SELECT USING (("client_id" IN ( SELECT "clients"."client_id"
   FROM "public"."clients"
  WHERE ("clients"."trainer_id" = "auth"."uid"()))));



CREATE POLICY "トレーナー自身のクライアントだけ見れる" ON "public"."clients" FOR SELECT USING (("trainer_id" = "auth"."uid"()));



CREATE POLICY "ユーザー自身のプロフィールのみ取得可" ON "public"."profiles" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "ユーザー自身のプロフィール作成を許可" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "送信者or受信者が自身のみ読取り可" ON "public"."messages" FOR SELECT USING ((("sender_id" = "auth"."uid"()) OR ("receiver_id" = "auth"."uid"())));



CREATE POLICY "送信者が自身のみ書き込み可" ON "public"."messages" FOR INSERT WITH CHECK (("sender_id" = "auth"."uid"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_achievement_rate"("p_client_id" "uuid", "p_current_weight" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."can_edit_message"("message_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_edit_message"("message_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_edit_message"("message_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) TO "anon";
GRANT ALL ON FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_goal_achievement"("p_client_id" "uuid", "p_current_weight" numeric) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_sessions_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_sessions_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_sessions_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";


















GRANT ALL ON TABLE "public"."clients" TO "anon";
GRANT ALL ON TABLE "public"."clients" TO "authenticated";
GRANT ALL ON TABLE "public"."clients" TO "service_role";



GRANT ALL ON TABLE "public"."exercise_records" TO "anon";
GRANT ALL ON TABLE "public"."exercise_records" TO "authenticated";
GRANT ALL ON TABLE "public"."exercise_records" TO "service_role";



GRANT ALL ON TABLE "public"."meal_records" TO "anon";
GRANT ALL ON TABLE "public"."meal_records" TO "authenticated";
GRANT ALL ON TABLE "public"."meal_records" TO "service_role";



GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."sessions" TO "anon";
GRANT ALL ON TABLE "public"."sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."sessions" TO "service_role";



GRANT ALL ON TABLE "public"."tickets" TO "anon";
GRANT ALL ON TABLE "public"."tickets" TO "authenticated";
GRANT ALL ON TABLE "public"."tickets" TO "service_role";



GRANT ALL ON TABLE "public"."weight_records" TO "anon";
GRANT ALL ON TABLE "public"."weight_records" TO "authenticated";
GRANT ALL ON TABLE "public"."weight_records" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























drop extension if exists "pg_net";


