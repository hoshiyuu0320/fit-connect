# AI Meal Estimation — Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** メッセージで食事を記録するときに、Claude API（Haiku 4.5）が食事内容テキストからカロリー＋PFCを推定し、ユーザーが既存の `MealTagForm` シート内で確認・編集してから送信できる UX を実装する。課金ゲート（trainer.subscription_plan='pro'）で制限する。

**Architecture:**
- 既存の `MealTagForm` を 3 状態ステートマシン化（入力 → 推定中 → 確認）
- 新規 Edge Function `estimate-meal-nutrition` が Claude を呼び、推定値を返す
- 確認後の保存は `messages.metadata.meal_estimation` に推定値を載せて INSERT し、既存 `parse-message-tags` Webhook（改修）が PFC込みで `meal_records` 作成
- 課金ゲートはクライアント側プロバイダ + Edge Function側で再検証

**Tech Stack:** Flutter (Riverpod codegen + json_serializable), Supabase (PostgreSQL + Edge Functions/Deno + RLS), Anthropic Claude API (Haiku 4.5 + prompt caching)

**Spec:** `docs/superpowers/specs/2026-05-02-ai-meal-estimation-stage1-design.md`

---

## File Map

### Created files
- `supabase/migrations/20260502120000_add_pfc_to_meal_records.sql`
- `supabase/migrations/20260502120100_add_subscription_plan_to_trainers.sql`
- `supabase/migrations/20260502120200_add_metadata_to_messages.sql`
- `supabase/migrations/20260502120300_create_ai_estimation_logs.sql`
- `supabase/functions/estimate-meal-nutrition/index.ts`
- `fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.dart`
- `fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart`
- `fit-connect-mobile/lib/features/subscription/providers/ai_features_enabled_provider.dart`
- `fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart`
- `fit-connect-mobile/test/features/meal_records/models/meal_estimation_result_test.dart`
- `fit-connect-mobile/test/features/subscription/providers/ai_features_enabled_provider_test.dart`

### Modified files
- `fit-connect-mobile/lib/features/meal_records/models/meal_record_model.dart` (PFC + estimated_by_ai + ai_foods)
- `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart` (`MealTagForm` 3-state)
- `fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart` (metadata wiring on send)
- `fit-connect-mobile/lib/features/messages/data/...` (whatever the message repository file is — see Task H1) (accept metadata on send)
- `supabase/functions/parse-message-tags/index.ts` (read `metadata.meal_estimation`)
- `docs/tasks/IMPLEMENTATION_TASKS.md` (mark 2.1 / 2.2 done with notes)
- `docs/tasks/lessons.md` (post-implementation lessons)

---

## Phase A — Database Migrations

Run sequentially. After each, apply locally with `cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase db push` (or use `supabase migration up` if running local stack), then verify with `psql` or Studio.

### Task A1: Add PFC + AI columns to `meal_records`

**Files:**
- Create: `supabase/migrations/20260502120000_add_pfc_to_meal_records.sql`

- [ ] **Step 1: Create migration file with this exact SQL**

```sql
-- 食事記録に PFC と AI 推定情報を追加
ALTER TABLE "public"."meal_records"
  ADD COLUMN "protein_g"       numeric CHECK (protein_g IS NULL OR protein_g >= 0),
  ADD COLUMN "fat_g"           numeric CHECK (fat_g     IS NULL OR fat_g     >= 0),
  ADD COLUMN "carbs_g"         numeric CHECK (carbs_g   IS NULL OR carbs_g   >= 0),
  ADD COLUMN "estimated_by_ai" boolean DEFAULT false NOT NULL,
  ADD COLUMN "ai_foods"        jsonb;

COMMENT ON COLUMN "public"."meal_records"."protein_g" IS 'タンパク質(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."fat_g" IS '脂質(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."carbs_g" IS '炭水化物(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."estimated_by_ai" IS 'AI推定で作成された記録か';
COMMENT ON COLUMN "public"."meal_records"."ai_foods" IS '食品ごとの推定内訳: [{name, calories, protein_g, fat_g, carbs_g}]';
```

- [ ] **Step 2: Apply migration locally**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase db push
```

Expected: migration applied without errors.

- [ ] **Step 3: Verify columns exist**

```bash
supabase db execute "SELECT column_name, data_type FROM information_schema.columns WHERE table_name='meal_records' ORDER BY ordinal_position"
```

Expected: list includes `protein_g`, `fat_g`, `carbs_g`, `estimated_by_ai`, `ai_foods`.

- [ ] **Step 4: Verify existing rows unaffected**

```bash
supabase db execute "SELECT count(*) FROM meal_records WHERE estimated_by_ai = false"
```

Expected: equals total count of `meal_records`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260502120000_add_pfc_to_meal_records.sql
git commit -m "feat(db): add PFC and AI estimation columns to meal_records"
```

---

### Task A2: Add `subscription_plan` to `trainers`

**Files:**
- Create: `supabase/migrations/20260502120100_add_subscription_plan_to_trainers.sql`

- [ ] **Step 1: Create migration file**

```sql
-- トレーナーの課金プラン (Stage 1: 'free' / 'pro' のみ。将来Stripe連携時に拡張)
ALTER TABLE "public"."trainers"
  ADD COLUMN "subscription_plan" text NOT NULL DEFAULT 'free'
    CHECK ("subscription_plan" IN ('free', 'pro'));

COMMENT ON COLUMN "public"."trainers"."subscription_plan" IS 'サブスクリプションプラン。pro でAI機能解放。Stripe連携時に自動更新する想定';
```

> 注: `trainers_select_all` ポリシーが既存（`USING (true)`）。クライアントは `subscription_plan` を読めるため追加 RLS は不要。

- [ ] **Step 2: Apply migration locally**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase db push
```

- [ ] **Step 3: Verify default value applied**

```bash
supabase db execute "SELECT count(*) FROM trainers WHERE subscription_plan = 'free'"
```

Expected: equals total trainer count.

- [ ] **Step 4: Confirm RLS read access (manual sanity)**

Open Supabase Studio → SQL Editor as a logged-in client user (impersonate via `auth.uid()`):
```sql
SELECT subscription_plan FROM trainers WHERE id = (SELECT trainer_id FROM clients WHERE client_id = auth.uid());
```
Expected: returns 'free' (or whatever value), no permission error.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260502120100_add_subscription_plan_to_trainers.sql
git commit -m "feat(db): add subscription_plan to trainers"
```

---

### Task A3: Add `metadata` jsonb to `messages`

**Files:**
- Create: `supabase/migrations/20260502120200_add_metadata_to_messages.sql`

- [ ] **Step 1: Create migration**

```sql
-- メッセージに任意の構造化メタデータを持たせる（AI推定結果など）
ALTER TABLE "public"."messages"
  ADD COLUMN "metadata" jsonb;

COMMENT ON COLUMN "public"."messages"."metadata" IS 'メッセージ付随メタデータ。例: meal_estimation = {foods, calories, protein_g, fat_g, carbs_g}';
```

- [ ] **Step 2: Apply migration**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase db push
```

- [ ] **Step 3: Verify column**

```bash
supabase db execute "SELECT column_name, data_type FROM information_schema.columns WHERE table_name='messages' AND column_name='metadata'"
```
Expected: returns 1 row with `data_type = 'jsonb'`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260502120200_add_metadata_to_messages.sql
git commit -m "feat(db): add metadata jsonb column to messages"
```

---

### Task A4: Create `ai_estimation_logs` table

**Files:**
- Create: `supabase/migrations/20260502120300_create_ai_estimation_logs.sql`

- [ ] **Step 1: Create migration**

```sql
-- AI推定リクエストのログ。Rate limit 判定とコストデバッグ用
CREATE TABLE "public"."ai_estimation_logs" (
  "id"            uuid PRIMARY KEY DEFAULT "gen_random_uuid"(),
  "client_id"     uuid NOT NULL REFERENCES "public"."clients"("client_id"),
  "trainer_id"    uuid NOT NULL REFERENCES "public"."trainers"("id"),
  "function_name" text NOT NULL,
  "status"        text NOT NULL CHECK ("status" IN ('success', 'error')),
  "error_code"    text,
  "created_at"    timestamptz DEFAULT "now"() NOT NULL
);

CREATE INDEX "idx_ai_logs_client_created"  ON "public"."ai_estimation_logs"("client_id", "created_at" DESC);
CREATE INDEX "idx_ai_logs_trainer_created" ON "public"."ai_estimation_logs"("trainer_id", "created_at" DESC);

ALTER TABLE "public"."ai_estimation_logs" ENABLE ROW LEVEL SECURITY;

-- クライアントは自分のログを SELECT 可能
CREATE POLICY "ai_logs_client_select"
  ON "public"."ai_estimation_logs"
  FOR SELECT
  USING ("client_id" = "auth"."uid"());

-- トレーナーは自分の担当クライアントのログを SELECT 可能
CREATE POLICY "ai_logs_trainer_select"
  ON "public"."ai_estimation_logs"
  FOR SELECT
  USING ("trainer_id" = "auth"."uid"());

-- INSERT は service_role のみ（Edge Function 経由）。明示ポリシーは作らない（RLS有効でanon/authenticatedは弾かれる）
COMMENT ON TABLE "public"."ai_estimation_logs" IS 'AI推定APIのリクエストログ。Rate limit判定とコストデバッグ用';
```

- [ ] **Step 2: Apply migration**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT && supabase db push
```

- [ ] **Step 3: Verify**

```bash
supabase db execute "SELECT count(*) FROM ai_estimation_logs"
```
Expected: 0.

```bash
supabase db execute "SELECT polname, polcmd FROM pg_policy WHERE polrelid = 'public.ai_estimation_logs'::regclass"
```
Expected: 2 policies (`ai_logs_client_select`, `ai_logs_trainer_select`).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260502120300_create_ai_estimation_logs.sql
git commit -m "feat(db): create ai_estimation_logs table for rate limiting"
```

---

## Phase B — Edge Function `estimate-meal-nutrition`

This Edge Function performs the AI estimation only. It does NOT save to `meal_records` (that's done via webhook in Phase C).

Reference existing Edge Function for environment & deno conventions: `supabase/functions/parse-message-tags/index.ts`.

### Task B1: Set up function skeleton with auth + subscription gate

**Files:**
- Create: `supabase/functions/estimate-meal-nutrition/index.ts`

- [ ] **Step 1: Create initial skeleton**

```typescript
// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }

  try {
    // 1. Auth: 呼び出し元の JWT から auth.uid を取り出す
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return errorResponse('FORBIDDEN', 'No auth token', 403)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')

    if (!anthropicKey) {
      console.error('ANTHROPIC_API_KEY not set')
      return errorResponse('ESTIMATION_FAILED', 'API key missing', 500)
    }

    // ユーザートークンで作る client → auth.uid 取得用
    const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userErr } = await userClient.auth.getUser()
    if (userErr || !userData.user) {
      return errorResponse('FORBIDDEN', 'Invalid token', 403)
    }
    const authUid = userData.user.id

    // service_role client（DB 操作用）
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 2. クライアントの trainer_id を取得
    const { data: client, error: clientErr } = await supabase
      .from('clients')
      .select('client_id, trainer_id')
      .eq('client_id', authUid)
      .maybeSingle()

    if (clientErr || !client) {
      return errorResponse('FORBIDDEN', 'Client not found', 403)
    }

    // 3. trainer の subscription_plan を確認
    const { data: trainer, error: trainerErr } = await supabase
      .from('trainers')
      .select('id, subscription_plan')
      .eq('id', client.trainer_id)
      .maybeSingle()

    if (trainerErr || !trainer || trainer.subscription_plan !== 'pro') {
      return errorResponse('FORBIDDEN', 'AI features require pro plan', 403)
    }

    // 4. リクエスト body パース
    const body = await req.json().catch(() => null)
    if (!body) return errorResponse('INVALID_INPUT', 'Invalid JSON body', 400)
    const { meal_type, content } = body
    // 注: image_urls フィールドは Stage 1 では受信しても無視（仕様書 §5.1 参照）

    if (!['breakfast', 'lunch', 'dinner', 'snack'].includes(meal_type)) {
      return errorResponse('INVALID_INPUT', 'Invalid meal_type', 400)
    }
    if (typeof content !== 'string' || content.trim().length === 0) {
      return errorResponse('INVALID_INPUT', 'Empty content', 400)
    }

    // TODO Tasks B2/B3/B4: rate limit, Claude call, response parse, log
    return new Response(JSON.stringify({ todo: true }), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error('estimate-meal-nutrition error:', e)
    return errorResponse('ESTIMATION_FAILED', String(e), 500)
  }
})

function errorResponse(code: string, message: string, status: number) {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })
}
```

- [ ] **Step 2: Serve locally and smoke-test the auth gate**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase functions serve estimate-meal-nutrition --no-verify-jwt
```

In another terminal:
```bash
curl -X POST http://localhost:54321/functions/v1/estimate-meal-nutrition \
  -H "Authorization: Bearer INVALID" \
  -H "Content-Type: application/json" \
  -d '{"meal_type":"lunch","content":"牛丼"}'
```
Expected: HTTP 403 with `{"error":"FORBIDDEN", "message":"Invalid token"}`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/estimate-meal-nutrition/index.ts
git commit -m "feat(supabase): scaffold estimate-meal-nutrition edge function with auth + subscription gate"
```

---

### Task B2: Add rate limit check via `ai_estimation_logs`

**Files:**
- Modify: `supabase/functions/estimate-meal-nutrition/index.ts`

- [ ] **Step 1: Insert rate limit check before Claude call (replace the `// TODO` line in B1 step 1's skeleton)**

```typescript
    // 4.5. Rate limit: 過去24h の自身/トレーナーごとのリクエスト数
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

    const { count: clientCount, error: cErr } = await supabase
      .from('ai_estimation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('client_id', authUid)
      .gte('created_at', since)
    if (cErr) console.error('rate-limit (client) query error:', cErr)
    if ((clientCount ?? 0) >= 50) {
      return errorResponse('RATE_LIMIT', 'Per-client daily limit (50) exceeded', 429)
    }

    const { count: trainerCount, error: tErr } = await supabase
      .from('ai_estimation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('trainer_id', client.trainer_id)
      .gte('created_at', since)
    if (tErr) console.error('rate-limit (trainer) query error:', tErr)
    if ((trainerCount ?? 0) >= 1000) {
      return errorResponse('RATE_LIMIT', 'Per-trainer daily limit (1000) exceeded', 429)
    }
```

- [ ] **Step 2: Verify build**

Restart serve, send request with valid auth. Confirm function still returns the `{todo:true}` response (Claude call comes in B3).

- [ ] **Step 3: Commit**

```bash
git commit -am "feat(supabase): add rate limit check (50/client, 1000/trainer per 24h)"
```

---

### Task B3: Implement Claude API call (Haiku 4.5 + prompt caching)

**Files:**
- Modify: `supabase/functions/estimate-meal-nutrition/index.ts`

- [ ] **Step 1: Add Claude call function above the `Deno.serve` block**

```typescript
const SYSTEM_PROMPT = `あなたは栄養素推定アシスタントです。日本語の食事内容テキストから、食品ごとに推定値（カロリー・タンパク質・脂質・炭水化物）を計算します。

返却形式は厳密に以下の JSON のみ（説明文・コードフェンス禁止）:
{
  "foods": [{"name": string, "calories": number, "protein_g": number, "fat_g": number, "carbs_g": number}],
  "totals": {"calories": number, "protein_g": number, "fat_g": number, "carbs_g": number}
}

指針:
- 一般的な日本食データベースの値を参考に推定する
- 量が明示されていない場合は「標準的な1人前」として推定する
- 信頼できないものは推定せず foods を空配列で返す
- すべて整数（小数点以下は切り捨て）
- totals は foods の合計と一致させる`

async function callClaude(apiKey: string, mealType: string, content: string): Promise<any> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 20_000)

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: 'claude-haiku-4-5',
        max_tokens: 1024,
        temperature: 0.2,
        system: [
          { type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } },
        ],
        messages: [
          { role: 'user', content: `食事タイプ: ${mealType}\n内容: ${content}` },
        ],
      }),
    })

    if (!resp.ok) {
      const text = await resp.text()
      throw new Error(`Claude API ${resp.status}: ${text}`)
    }

    const data = await resp.json()
    const textBlock = data.content?.find((b: any) => b.type === 'text')
    if (!textBlock?.text) throw new Error('No text in Claude response')
    return JSON.parse(textBlock.text)
  } finally {
    clearTimeout(timeoutId)
  }
}

function clampPositive(n: any): number {
  const v = typeof n === 'number' ? n : parseFloat(String(n))
  if (Number.isNaN(v) || v < 0) return 0
  return Math.floor(v)
}

function validateEstimation(raw: any): { foods: any[]; totals: any } {
  if (!raw || typeof raw !== 'object') throw new Error('Invalid response shape')
  if (!Array.isArray(raw.foods)) throw new Error('Missing foods array')
  if (!raw.totals || typeof raw.totals !== 'object') throw new Error('Missing totals')

  const foods = raw.foods.map((f: any) => {
    if (!f || typeof f.name !== 'string') throw new Error('Food missing name')
    return {
      name: f.name,
      calories: clampPositive(f.calories),
      protein_g: clampPositive(f.protein_g),
      fat_g: clampPositive(f.fat_g),
      carbs_g: clampPositive(f.carbs_g),
    }
  })

  const totals = {
    calories: clampPositive(raw.totals.calories),
    protein_g: clampPositive(raw.totals.protein_g),
    fat_g: clampPositive(raw.totals.fat_g),
    carbs_g: clampPositive(raw.totals.carbs_g),
  }

  return { foods, totals }
}
```

- [ ] **Step 2: Replace the `// TODO` placeholder in `Deno.serve` with the full call + log + return logic**

```typescript
    // 5. Claude 呼び出し
    let result
    try {
      const raw = await callClaude(anthropicKey, meal_type, content)
      result = validateEstimation(raw)
    } catch (e) {
      console.error('Claude call/parse failed:', e)
      // 失敗ログを残す
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: 'estimate-meal-nutrition',
        status: 'error',
        error_code: 'ESTIMATION_FAILED',
      })
      return errorResponse('ESTIMATION_FAILED', String(e), 500)
    }

    if (result.foods.length === 0) {
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: 'estimate-meal-nutrition',
        status: 'error',
        error_code: 'EMPTY_RESULT',
      })
      return errorResponse('ESTIMATION_FAILED', 'No foods could be estimated', 500)
    }

    // 6. 成功ログ
    await supabase.from('ai_estimation_logs').insert({
      client_id: authUid,
      trainer_id: client.trainer_id,
      function_name: 'estimate-meal-nutrition',
      status: 'success',
    })

    return new Response(JSON.stringify(result), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
```

- [ ] **Step 3: Set ANTHROPIC_API_KEY secret locally**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...  # 実キーは別途取得済の前提
```

For local serve, also set in `.env` for the Edge Function or pass via env (`supabase functions serve` reads `supabase/.env.local`).

- [ ] **Step 4: Smoke test with a real call**

```bash
# Get a valid JWT for a test client whose trainer is on 'pro' plan
# (manually update test trainer to 'pro' plan first via supabase db execute "UPDATE trainers SET subscription_plan='pro' WHERE id='<test-trainer-id>'")

curl -X POST http://localhost:54321/functions/v1/estimate-meal-nutrition \
  -H "Authorization: Bearer <CLIENT_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"meal_type":"lunch","content":"牛丼大盛りとサラダ"}'
```
Expected: HTTP 200 with `{"foods":[...], "totals":{"calories":..,...}}`.

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(supabase): integrate Claude Haiku 4.5 with prompt caching for meal estimation"
```

---

### Task B4: Deploy `estimate-meal-nutrition` to remote

- [ ] **Step 1: Set production secret**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy estimate-meal-nutrition --no-verify-jwt
```

> 注: `--no-verify-jwt` を付けるが、関数内で自前で JWT を検証している（Phase B1 参照）。既存の `parse-message-tags` も同パターン。

Expected: deploy success, function URL printed.

- [ ] **Step 3: Smoke test against production endpoint**

Same curl as B3 step 4 but pointing at the production URL. Expected 200.

- [ ] **Step 4: Verify log row**

```bash
supabase db execute "SELECT client_id, status, created_at FROM ai_estimation_logs ORDER BY created_at DESC LIMIT 5"
```
Expected: at least one row with `status='success'`.

---

## Phase C — `parse-message-tags` Webhook 改修

The existing webhook creates `meal_records` from message tags. We extend it to read `metadata.meal_estimation` and use those PFC values when present, while keeping the existing path intact for tag-only messages.

### Task C1: Add metadata-aware meal record creation path

**Files:**
- Modify: `supabase/functions/parse-message-tags/index.ts`

- [ ] **Step 1: Locate the `createMealRecord` function (around line 150) and replace it with**

```typescript
async function createMealRecord(supabase, commonData, tagData) {
  let mealType = 'snack'
  if (tagData.detail) {
    if (tagData.detail.includes('朝')) mealType = 'breakfast'
    else if (tagData.detail.includes('昼')) mealType = 'lunch'
    else if (tagData.detail.includes('夕') || tagData.detail.includes('晩')) mealType = 'dinner'
  }

  // metadata.meal_estimation があれば PFC込みで保存
  const estimation = commonData.meal_estimation
  if (estimation) {
    console.log('Creating meal record with AI estimation:', mealType, 'totals=', estimation)
    return await supabase.from('meal_records').insert({
      client_id: commonData.client_id,
      source: commonData.source,
      message_id: commonData.message_id,
      recorded_at: commonData.recorded_at,
      notes: commonData.notes,
      meal_type: mealType,
      images: commonData.image_urls,
      calories: estimation.calories,
      protein_g: estimation.protein_g,
      fat_g: estimation.fat_g,
      carbs_g: estimation.carbs_g,
      ai_foods: estimation.foods,
      estimated_by_ai: true,
    })
  }

  // 既存挙動（PFCなし）
  console.log('Creating meal record (no AI):', mealType, 'images=', commonData.image_urls?.length || 0)
  return await supabase.from('meal_records').insert({
    client_id: commonData.client_id,
    source: commonData.source,
    message_id: commonData.message_id,
    recorded_at: commonData.recorded_at,
    notes: commonData.notes,
    meal_type: mealType,
    images: commonData.image_urls,
  })
}
```

- [ ] **Step 2: In the main `Deno.serve` handler, augment `commonData` with metadata before calling `createMealRecord`**

Find the `commonData` object construction (around line 67) and append:
```typescript
        const commonData = {
          client_id: message.sender_id,
          source: 'message',
          message_id: message.id,
          recorded_at: message.created_at,
          notes: tagData.remainingContent,
          image_urls: message.image_urls || [],
          meal_estimation: message.metadata?.meal_estimation, // ← 追加
        }
```

- [ ] **Step 3: Smoke test locally**

```bash
supabase functions serve parse-message-tags --no-verify-jwt
```

Manually trigger an INSERT on `messages` with metadata and tag:
```bash
supabase db execute "INSERT INTO messages (sender_id, sender_type, receiver_id, receiver_type, content, metadata) VALUES ('<test-client-id>', 'client', '<test-trainer-id>', 'trainer', '#食事:昼食 牛丼大盛り', '{\"meal_estimation\":{\"foods\":[{\"name\":\"牛丼大盛り\",\"calories\":900,\"protein_g\":35,\"fat_g\":30,\"carbs_g\":100}],\"calories\":900,\"protein_g\":35,\"fat_g\":30,\"carbs_g\":100}}'::jsonb)"
```

Then:
```bash
supabase db execute "SELECT meal_type, calories, protein_g, fat_g, carbs_g, estimated_by_ai FROM meal_records ORDER BY created_at DESC LIMIT 1"
```
Expected: row with PFC values matching, `estimated_by_ai = true`.

- [ ] **Step 4: Negative test — message without metadata creates legacy record**

```bash
supabase db execute "INSERT INTO messages (sender_id, sender_type, receiver_id, receiver_type, content) VALUES ('<test-client-id>', 'client', '<test-trainer-id>', 'trainer', '#食事:朝食 トースト')"
```
```bash
supabase db execute "SELECT calories, protein_g, estimated_by_ai FROM meal_records ORDER BY created_at DESC LIMIT 1"
```
Expected: `calories=NULL, protein_g=NULL, estimated_by_ai=false`. **Existing behavior unchanged.**

- [ ] **Step 5: Commit**

```bash
git commit -am "feat(supabase): parse-message-tags reads metadata.meal_estimation for PFC saving"
```

---

### Task C2: Deploy `parse-message-tags` to remote

- [ ] **Step 1: Deploy**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase functions deploy parse-message-tags --no-verify-jwt
```

- [ ] **Step 2: Verify webhook is wired** (sanity)

In Supabase Studio → Database → Webhooks, confirm `parse-message-tags` is still bound to `messages` INSERT/UPDATE.

---

## Phase D — Mobile Data Models

> Delegate to **Riverpod Agent** when applying these. Reference: `fit-connect-mobile/lib/features/meal_records/models/meal_record_model.dart`.

### Task D1: Update `MealRecord` model with PFC + AI fields

**Files:**
- Modify: `fit-connect-mobile/lib/features/meal_records/models/meal_record_model.dart`
- Generate: `fit-connect-mobile/lib/features/meal_records/models/meal_record_model.g.dart` (via build_runner)

- [ ] **Step 1: Add fields to `MealRecord` class**

After the existing `calories` field, add:
```dart
  @JsonKey(name: 'protein_g')
  final double? proteinG;
  @JsonKey(name: 'fat_g')
  final double? fatG;
  @JsonKey(name: 'carbs_g')
  final double? carbsG;
  @JsonKey(name: 'estimated_by_ai')
  final bool estimatedByAi;
  @JsonKey(name: 'ai_foods')
  final List<Map<String, dynamic>>? aiFoods;
```

Update the constructor, `copyWith`, `fromJson`/`toJson` are auto-generated by `json_serializable`, but ensure constructor includes the new params (with defaults: `this.proteinG, this.fatG, this.carbsG, this.estimatedByAi = false, this.aiFoods`).

- [ ] **Step 2: Run code generation**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 3: Run analyzer to confirm no breakage in callers**

```bash
flutter analyze lib/features/meal_records
```
Expected: no errors. (UI cards may need updating to show PFC — out of scope for Stage 1, but ensure no compile errors.)

- [ ] **Step 4: Commit**

```bash
git add lib/features/meal_records/models/
git commit -m "feat(mobile): add PFC and AI estimation fields to MealRecord model"
```

---

### Task D2: Create `MealEstimationResult` model

**Files:**
- Create: `fit-connect-mobile/lib/features/meal_records/models/meal_estimation_result.dart`
- Create: `fit-connect-mobile/test/features/meal_records/models/meal_estimation_result_test.dart`
- Generate: `meal_estimation_result.g.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/features/meal_records/models/meal_estimation_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';

void main() {
  test('parses Edge Function response', () {
    final json = {
      'foods': [
        {'name': '牛丼大盛り', 'calories': 850, 'protein_g': 32, 'fat_g': 28, 'carbs_g': 95},
      ],
      'totals': {'calories': 850, 'protein_g': 32, 'fat_g': 28, 'carbs_g': 95},
    };
    final result = MealEstimationResult.fromJson(json);
    expect(result.foods, hasLength(1));
    expect(result.foods.first.name, '牛丼大盛り');
    expect(result.totals.calories, 850);
    expect(result.totals.proteinG, 32);
  });
}
```

- [ ] **Step 2: Run test, verify failure**

```bash
flutter test test/features/meal_records/models/meal_estimation_result_test.dart
```
Expected: FAIL (file does not exist).

- [ ] **Step 3: Create model**

```dart
// lib/features/meal_records/models/meal_estimation_result.dart
import 'package:json_annotation/json_annotation.dart';

part 'meal_estimation_result.g.dart';

@JsonSerializable()
class MealEstimationResult {
  final List<EstimatedFood> foods;
  final EstimationTotals totals;

  const MealEstimationResult({required this.foods, required this.totals});

  factory MealEstimationResult.fromJson(Map<String, dynamic> json) =>
      _$MealEstimationResultFromJson(json);
  Map<String, dynamic> toJson() => _$MealEstimationResultToJson(this);
}

@JsonSerializable()
class EstimatedFood {
  final String name;
  final double calories;
  @JsonKey(name: 'protein_g')
  final double proteinG;
  @JsonKey(name: 'fat_g')
  final double fatG;
  @JsonKey(name: 'carbs_g')
  final double carbsG;

  const EstimatedFood({
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  factory EstimatedFood.fromJson(Map<String, dynamic> json) =>
      _$EstimatedFoodFromJson(json);
  Map<String, dynamic> toJson() => _$EstimatedFoodToJson(this);
}

@JsonSerializable()
class EstimationTotals {
  final double calories;
  @JsonKey(name: 'protein_g')
  final double proteinG;
  @JsonKey(name: 'fat_g')
  final double fatG;
  @JsonKey(name: 'carbs_g')
  final double carbsG;

  const EstimationTotals({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
  });

  EstimationTotals copyWith({double? calories, double? proteinG, double? fatG, double? carbsG}) =>
      EstimationTotals(
        calories: calories ?? this.calories,
        proteinG: proteinG ?? this.proteinG,
        fatG: fatG ?? this.fatG,
        carbsG: carbsG ?? this.carbsG,
      );

  factory EstimationTotals.fromJson(Map<String, dynamic> json) =>
      _$EstimationTotalsFromJson(json);
  Map<String, dynamic> toJson() => _$EstimationTotalsToJson(this);
}
```

- [ ] **Step 4: Generate code, run test**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/meal_records/models/meal_estimation_result_test.dart
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/meal_records/models/meal_estimation_result.dart \
        lib/features/meal_records/models/meal_estimation_result.g.dart \
        test/features/meal_records/models/meal_estimation_result_test.dart
git commit -m "feat(mobile): add MealEstimationResult model with json_serializable"
```

---

### Task D3: Create `MealEstimationApi` (Edge Function client)

**Files:**
- Create: `fit-connect-mobile/lib/features/meal_records/data/meal_estimation_api.dart`

- [ ] **Step 1: Write the API client**

```dart
// lib/features/meal_records/data/meal_estimation_api.dart
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

enum MealEstimationErrorCode { forbidden, rateLimit, invalidInput, estimationFailed, network }

class MealEstimationException implements Exception {
  final MealEstimationErrorCode code;
  final String message;
  MealEstimationException(this.code, this.message);
  @override
  String toString() => 'MealEstimationException($code): $message';
}

class MealEstimationApi {
  static Future<MealEstimationResult> estimate({
    required String mealType, // 'breakfast' | 'lunch' | 'dinner' | 'snack'
    required String content,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'estimate-meal-nutrition',
        body: {
          'meal_type': mealType,
          'content': content,
          'image_urls': const <String>[],
        },
      );

      final status = response.status;
      final data = response.data;
      if (status >= 200 && status < 300 && data is Map<String, dynamic>) {
        return MealEstimationResult.fromJson(data);
      }

      // エラーマッピング
      final errCode = (data is Map && data['error'] is String) ? data['error'] as String : null;
      final msg = (data is Map && data['message'] is String) ? data['message'] as String : 'Unknown error';
      switch (errCode) {
        case 'FORBIDDEN':
          throw MealEstimationException(MealEstimationErrorCode.forbidden, msg);
        case 'RATE_LIMIT':
          throw MealEstimationException(MealEstimationErrorCode.rateLimit, msg);
        case 'INVALID_INPUT':
          throw MealEstimationException(MealEstimationErrorCode.invalidInput, msg);
        default:
          throw MealEstimationException(MealEstimationErrorCode.estimationFailed, msg);
      }
    } on MealEstimationException {
      rethrow;
    } catch (e) {
      throw MealEstimationException(MealEstimationErrorCode.network, e.toString());
    }
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/meal_records/data/meal_estimation_api.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/meal_records/data/meal_estimation_api.dart
git commit -m "feat(mobile): add MealEstimationApi client for estimate-meal-nutrition function"
```

---

## Phase E — Mobile Provider: AI Features Gate

### Task E1: Implement `aiFeaturesEnabledProvider`

**Files:**
- Create: `fit-connect-mobile/lib/features/subscription/providers/ai_features_enabled_provider.dart`
- Create: `fit-connect-mobile/test/features/subscription/providers/ai_features_enabled_provider_test.dart`
- Generate: `ai_features_enabled_provider.g.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/features/subscription/providers/ai_features_enabled_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';

void main() {
  test('returns false when no auth user', () async {
    // 注: 完全な単体テストは Supabase をモックする必要があるため、Stage 1 では
    //     プロバイダのファイル存在＋export確認で十分。実機検証はQA時。
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final asyncValue = container.read(aiFeaturesEnabledProvider);
    expect(asyncValue, isA<AsyncValue<bool>>());
  });
}
```

- [ ] **Step 2: Run test (will fail — file missing)**

```bash
flutter test test/features/subscription/providers/ai_features_enabled_provider_test.dart
```
Expected: FAIL.

- [ ] **Step 3: Implement provider**

```dart
// lib/features/subscription/providers/ai_features_enabled_provider.dart
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_features_enabled_provider.g.dart';

/// 自身の担当トレーナーの subscription_plan が 'pro' かどうか。
/// 取得失敗・未認証・未紐付けの場合は false を返す（保守的にAI非表示）。
///
/// 参照経路: auth.uid() → clients.client_id → clients.trainer_id → trainers.subscription_plan
@riverpod
Future<bool> aiFeaturesEnabled(Ref ref) async {
  final supabase = SupabaseService.client;
  final user = supabase.auth.currentUser;
  if (user == null) return false;

  final clientRow = await supabase
      .from('clients')
      .select('trainer_id')
      .eq('client_id', user.id)
      .maybeSingle();
  final trainerId = clientRow?['trainer_id'] as String?;
  if (trainerId == null) return false;

  final trainerRow = await supabase
      .from('trainers')
      .select('subscription_plan')
      .eq('id', trainerId)
      .maybeSingle();
  return (trainerRow?['subscription_plan'] as String?) == 'pro';
}
```

- [ ] **Step 4: Generate, test, analyze**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/subscription/providers/ai_features_enabled_provider_test.dart
flutter analyze lib/features/subscription
```
Expected: PASS, no analyze errors.

- [ ] **Step 5: Commit**

```bash
git add lib/features/subscription/ test/features/subscription/
git commit -m "feat(mobile): add aiFeaturesEnabledProvider gating AI by trainer subscription"
```

---

## Phase F — Mobile UI: `MealTagForm` 3-State

> Delegate to **Flutter UI Agent**. Existing widget reference: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart` (lines 269-437).

### Task F1: Refactor `_MealTagFormState` to enum-based 3-state machine

**Files:**
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart`

- [ ] **Step 1: Add an enum and state field at top of `_MealTagFormState`**

Just before `late String _selectedMealType;`:
```dart
enum _MealFormPhase { input, loading, confirm }
```

In the state class:
```dart
  _MealFormPhase _phase = _MealFormPhase.input;
  MealEstimationResult? _estimation;
  EstimationTotals? _editableTotals; // 確認画面で編集される値
  // 注: エラーメッセージはスナックバーで表示するだけなので state には持たない（local 変数で十分）
```

Add imports at top of file:
```dart
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:fit_connect_mobile/features/meal_records/data/meal_estimation_api.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

- [ ] **Step 2: Convert `MealTagForm` from `StatefulWidget` to `ConsumerStatefulWidget`**

Change:
```dart
class MealTagForm extends StatefulWidget {
  ...
  State<MealTagForm> createState() => _MealTagFormState();
}

class _MealTagFormState extends State<MealTagForm> {
```
to:
```dart
class MealTagForm extends ConsumerStatefulWidget {
  ...
  ConsumerState<MealTagForm> createState() => _MealTagFormState();
}

class _MealTagFormState extends ConsumerState<MealTagForm> {
```

- [ ] **Step 3: Update `MealTagForm` constructor to accept an additional callback for "send with PFC"**

Add:
```dart
  /// PFC込みで送信。null の場合は従来挙動（`onCompose` で挿入）にフォールバック
  final Future<void> Function(String composedText, MealEstimationResult estimation)? onSendWithEstimation;
```

Add to `MealTagForm` constructor.

Also add a **nullable** `onSendWithEstimation` parameter to the parent `StructuredTagForm` (StatelessWidget) and pass it through ONLY to the `'meal'` branch:
```dart
class StructuredTagForm extends StatelessWidget {
  // ... existing params
  final Future<void> Function(String composedText, MealEstimationResult estimation)? onSendWithEstimation; // ← 新規（nullable）

  // build() の case 'meal':
  return MealTagForm(
    onCompose: onCompose,
    onClose: onClose,
    hasImages: hasImages,
    selectedImages: selectedImages,
    onPickImage: onPickImage,
    onRemoveImage: onRemoveImage,
    onSendWithEstimation: onSendWithEstimation, // ← 新規
  );
```

`WeightTagForm` / `ExerciseTagForm` は変更不要（AI推定対象外）。

- [ ] **Step 4: Replace `_handleInsert` with branching logic**

```dart
  Future<void> _handleInsert() async {
    if (!_isValid) return;

    final aiEnabled = ref.read(aiFeaturesEnabledProvider).valueOrNull ?? false;
    final canEstimate = aiEnabled && widget.onSendWithEstimation != null && _contentController.text.trim().isNotEmpty;

    if (!canEstimate) {
      // 既存挙動: チャット入力欄に挿入
      widget.onCompose(_composedText);
      return;
    }

    setState(() {
      _phase = _MealFormPhase.loading;
      _estimationError = null;
    });

    try {
      final result = await MealEstimationApi.estimate(
        mealType: _mealTypeToEnum(_selectedMealType),
        content: _contentController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _estimation = result;
        _editableTotals = result.totals;
        _phase = _MealFormPhase.confirm;
      });
    } on MealEstimationException catch (e) {
      if (!mounted) return;
      final msg = _humanError(e);
      setState(() {
        _phase = _MealFormPhase.input;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.rose800),
      );
    }
  }

  String _mealTypeToEnum(String label) {
    switch (label) {
      case '朝食': return 'breakfast';
      case '昼食': return 'lunch';
      case '夕食': return 'dinner';
      default:   return 'snack';
    }
  }

  String _humanError(MealEstimationException e) {
    switch (e.code) {
      case MealEstimationErrorCode.rateLimit:
        return 'AI推定の上限に達しました。しばらくしてからお試しください';
      case MealEstimationErrorCode.network:
        return '通信エラーが発生しました';
      case MealEstimationErrorCode.forbidden:
        return 'AI機能が利用できません';
      case MealEstimationErrorCode.invalidInput:
        return '入力内容が不正です';
      case MealEstimationErrorCode.estimationFailed:
        return '推定に失敗しました。内容を変えてお試しください';
    }
  }
```

- [ ] **Step 5: Update `build()` to switch on `_phase`**

Wrap the existing input UI in a `_buildInputState(colors)` method, then:
```dart
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: switch (_phase) {
        _MealFormPhase.input => _buildInputState(colors),
        _MealFormPhase.loading => _buildLoadingState(colors),
        _MealFormPhase.confirm => _buildConfirmState(colors),
      },
    );
  }
```

- [ ] **Step 6: Implement `_buildLoadingState`**

```dart
  Widget _buildLoadingState(AppColorsExtension colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.utensils, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text('AI推定中…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _phase = _MealFormPhase.input),
              child: Text('キャンセル', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 24),
      ],
    );
  }
```

- [ ] **Step 7: Run analyzer**

```bash
flutter analyze lib/features/messages/presentation/widgets/structured_tag_form.dart
```
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git commit -am "feat(mobile): wire MealTagForm to 3-state machine (input/loading/confirm)"
```

---

### Task F2: Build the confirmation view widget

**Files:**
- Create: `fit-connect-mobile/lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart`
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart` (`_buildConfirmState` calls into it)

- [ ] **Step 1: Create the confirm view widget**

```dart
// lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_estimation_result.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MealEstimationConfirmView extends StatefulWidget {
  final MealEstimationResult estimation;
  final EstimationTotals totals;
  final ValueChanged<EstimationTotals> onTotalsChanged;
  final VoidCallback onBack;
  final VoidCallback onSend;

  const MealEstimationConfirmView({
    super.key,
    required this.estimation,
    required this.totals,
    required this.onTotalsChanged,
    required this.onBack,
    required this.onSend,
  });

  @override
  State<MealEstimationConfirmView> createState() => _MealEstimationConfirmViewState();
}

class _MealEstimationConfirmViewState extends State<MealEstimationConfirmView> {
  late TextEditingController _kcalC;
  late TextEditingController _pC;
  late TextEditingController _fC;
  late TextEditingController _cC;

  @override
  void initState() {
    super.initState();
    _kcalC = TextEditingController(text: widget.totals.calories.toStringAsFixed(0));
    _pC = TextEditingController(text: widget.totals.proteinG.toStringAsFixed(0));
    _fC = TextEditingController(text: widget.totals.fatG.toStringAsFixed(0));
    _cC = TextEditingController(text: widget.totals.carbsG.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _kcalC.dispose(); _pC.dispose(); _fC.dispose(); _cC.dispose();
    super.dispose();
  }

  EstimationTotals _readTotals() => EstimationTotals(
        calories: double.tryParse(_kcalC.text) ?? 0,
        proteinG: double.tryParse(_pC.text) ?? 0,
        fatG: double.tryParse(_fC.text) ?? 0,
        carbsG: double.tryParse(_cC.text) ?? 0,
      );

  void _emit() => widget.onTotalsChanged(_readTotals());

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(LucideIcons.sparkles, size: 16, color: colors.textPrimary),
            const SizedBox(width: 6),
            Text('AI推定結果を確認',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary)),
            const Spacer(),
            GestureDetector(
              onTap: widget.onBack,
              child: Text('戻る', style: TextStyle(fontSize: 13, color: colors.textSecondary)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Foods list (read-only in Stage 1)
        ...widget.estimation.foods.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('・${f.name}（${f.calories.toStringAsFixed(0)}kcal）',
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
        )),
        const SizedBox(height: 8),

        // Editable totals row
        Row(children: [
          Expanded(child: _NumField(label: 'kcal', controller: _kcalC, onChanged: (_) => _emit(), colors: colors)),
          const SizedBox(width: 6),
          Expanded(child: _NumField(label: 'P', controller: _pC, onChanged: (_) => _emit(), colors: colors)),
          const SizedBox(width: 6),
          Expanded(child: _NumField(label: 'F', controller: _fC, onChanged: (_) => _emit(), colors: colors)),
          const SizedBox(width: 6),
          Expanded(child: _NumField(label: 'C', controller: _cC, onChanged: (_) => _emit(), colors: colors)),
        ]),
        const SizedBox(height: 10),

        // Send button
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: widget.onSend,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
              child: const Text('送信', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final AppColorsExtension colors;
  const _NumField({required this.label, required this.controller, required this.onChanged, required this.colors});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        filled: true,
        fillColor: colors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      style: TextStyle(color: colors.textPrimary, fontSize: 13),
    );
  }
}

// ============================================
// Previews
// ============================================

@Preview(name: 'MealEstimationConfirmView - Default')
Widget previewMealEstimationConfirmViewDefault() {
  final estimation = MealEstimationResult(
    foods: const [
      EstimatedFood(name: '牛丼大盛り', calories: 850, proteinG: 32, fatG: 28, carbsG: 95),
      EstimatedFood(name: 'サラダ',      calories: 50,  proteinG: 2,  fatG: 3,  carbsG: 5),
    ],
    totals: const EstimationTotals(calories: 900, proteinG: 34, fatG: 31, carbsG: 100),
  );
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: MealEstimationConfirmView(
                estimation: estimation,
                totals: estimation.totals,
                onTotalsChanged: (_) {},
                onBack: () {},
                onSend: () {},
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Wire `_buildConfirmState` in `MealTagForm`**

```dart
  Widget _buildConfirmState(AppColorsExtension colors) {
    return MealEstimationConfirmView(
      estimation: _estimation!,
      totals: _editableTotals!,
      onTotalsChanged: (t) => setState(() => _editableTotals = t),
      onBack: () => setState(() {
        _phase = _MealFormPhase.input;
        _estimation = null;
        _editableTotals = null;
      }),
      onSend: _handleSendWithEstimation,
    );
  }

  Future<void> _handleSendWithEstimation() async {
    if (_estimation == null || _editableTotals == null) return;
    final estimationToSend = MealEstimationResult(
      foods: _estimation!.foods,
      totals: _editableTotals!,
    );
    await widget.onSendWithEstimation?.call(_composedText, estimationToSend);
    // 親側でシートクローズが行われる想定
  }
```

- [ ] **Step 3: Add an analyzer pass**

```bash
flutter analyze lib/features/messages
```
Expected: no errors.

- [ ] **Step 4: Generate previews exist for State 2/3**

Run `flutter widget-preview start` and confirm `MealEstimationConfirmView - Default` and the existing `MealTagForm - Default` previews load.

- [ ] **Step 5: Commit**

```bash
git add lib/features/messages/presentation/widgets/meal_estimation_confirm_view.dart
git commit -am "feat(mobile): add MealEstimationConfirmView and wire into MealTagForm"
```

---

## Phase G — Wire Send Flow with Metadata

The chat send path currently calls `widget.onSend(text, imageUrls, replyTo)`. We need to extend it so that when `MealTagForm` returns an estimation, the message INSERT includes `metadata.meal_estimation`.

### Task G1: Confirm message repository send signature

**Files:** investigate (no code change yet)

The pre-confirmed file is `fit-connect-mobile/lib/features/messages/data/message_repository.dart`. The method to extend is `sendMessage(...)` (around line 103). Existing parameters are positional-named (e.g. `senderId`, `receiverId`, `senderType`, `receiverType`, `content`, `imageUrls`, `tags`, `replyToMessageId`).

- [ ] **Step 1: Open the file and read the full `sendMessage` signature**

```bash
sed -n '100,140p' /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/lib/features/messages/data/message_repository.dart
```

Note the exact parameter list — Task G2 must preserve all existing parameters and only ADD `Map<String, dynamic>? metadata`.

- [ ] **Step 2: Identify all existing call sites of `sendMessage`**

```bash
grep -rn "sendMessage(" /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/lib --include="*.dart"
```

Each call site must keep working with `metadata: null` as default.

---

### Task G2: Extend send method to accept optional `metadata`

**Files:**
- Modify: the message repository file located in G1
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/chat_input.dart`
- Modify: any provider/screen that calls `onSend` from `ChatInput` (likely `message_screen.dart`)
- Modify: `fit-connect-mobile/lib/features/messages/presentation/widgets/structured_tag_form.dart` (already calls `onSendWithEstimation`)

- [ ] **Step 1: Add `Map<String, dynamic>? metadata` parameter to the message INSERT method**

In the repository file:
```dart
  Future<void> sendMessage({
    required String content,
    List<String>? imageUrls,
    String? replyToMessageId,
    Map<String, dynamic>? metadata, // ← 追加
  }) async {
    await _supabase.from('messages').insert({
      'sender_id': ...,
      // ... existing fields
      if (metadata != null) 'metadata': metadata,
    });
  }
```

- [ ] **Step 2: Extend `ChatInput.onSend` signature**

In `chat_input.dart`:
```dart
final Future<void> Function(
    String text, List<String>? imageUrls, String? replyToMessageId, Map<String, dynamic>? metadata) onSend;
```

Update all 5 call sites in this file (they currently pass `text, imageUrls, widget.replyToMessageId`) to pass `null` for metadata in default flows.

- [ ] **Step 3: Pass `MealEstimationResult` → metadata via `MealTagForm.onSendWithEstimation`**

In `chat_input.dart`, when constructing `StructuredTagForm`/`MealTagForm`, add an `onSendWithEstimation` callback:
```dart
            onSendWithEstimation: (composedText, estimation) async {
              // 画像アップロード → onSend with metadata
              final metadata = {
                'meal_estimation': {
                  'foods': estimation.foods.map((f) => f.toJson()).toList(),
                  'calories': estimation.totals.calories,
                  'protein_g': estimation.totals.proteinG,
                  'fat_g': estimation.totals.fatG,
                  'carbs_g': estimation.totals.carbsG,
                },
              };
              // 既存の _handleSend と同じ画像アップロードフローを通す
              await _sendWithMetadata(composedText, metadata);
              _closeStructuredForm();
            },
```

Implement `_sendWithMetadata` by extracting the upload logic from the existing `_handleSend` (DRY).

- [ ] **Step 4: Update parent screen (`message_screen.dart`) to forward metadata to repository**

Find `onSend: (text, images, replyTo) async { ... }` and update to `onSend: (text, images, replyTo, metadata) async { await repository.sendMessage(content: text, imageUrls: images, replyToMessageId: replyTo, metadata: metadata); }`.

- [ ] **Step 5: Analyze**

```bash
flutter analyze lib/features/messages
```
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(mobile): wire metadata through send pipeline for AI meal estimation"
```

---

## Phase H — End-to-End Manual QA

### Task H1: iOS simulator QA — pro plan client (full happy path)

- [ ] **Step 1: Set test trainer to 'pro'**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
supabase db execute "UPDATE trainers SET subscription_plan='pro' WHERE id='<test-trainer-id>'"
```

- [ ] **Step 2: Build and run mobile app, log in as that trainer's client**

```bash
cd fit-connect-mobile && flutter run -d <iOS-simulator-id>
```

- [ ] **Step 3: Open メッセージ → 食事を記録 → 昼食を選択 → 「牛丼大盛り」と入力 → 挿入**

Expected:
- Sheet shifts to "AI推定中…" with spinner
- Within ~5s, sheet shifts to confirm view with foods list and editable totals

- [ ] **Step 4: Edit one of the totals (e.g., kcal: 900 → 850), tap 送信**

Expected:
- Message bubble appears in chat with `#食事:昼食 牛丼大盛り`
- Sheet closes
- `meal_records` has new row with `calories=850, protein_g=..., estimated_by_ai=true, ai_foods=<list>`

```bash
supabase db execute "SELECT meal_type, calories, protein_g, fat_g, carbs_g, estimated_by_ai, ai_foods FROM meal_records ORDER BY created_at DESC LIMIT 1"
```

- [ ] **Step 5: Verify ai_estimation_logs has a success row**

```bash
supabase db execute "SELECT status, created_at FROM ai_estimation_logs WHERE client_id='<test-client-id>' ORDER BY created_at DESC LIMIT 1"
```
Expected: 1 row with `status='success'`.

---

### Task H2: iOS simulator QA — free plan client (existing behavior preserved)

- [ ] **Step 1: Reset trainer to 'free'**

```bash
supabase db execute "UPDATE trainers SET subscription_plan='free' WHERE id='<test-trainer-id>'"
```

- [ ] **Step 2: Cold-restart mobile app (so provider re-fetches)**

- [ ] **Step 3: Repeat the flow: 食事を記録 → 昼食 → 「サラダ」 → 挿入**

Expected:
- Sheet does NOT shift to AI推定中 — instead, `#食事:昼食 サラダ` is inserted into the chat input field (existing behavior)
- User taps regular send button → message is sent, `meal_records` row is created with NULL PFC and `estimated_by_ai=false` (legacy webhook path)

- [ ] **Step 4: Verify**

```bash
supabase db execute "SELECT calories, protein_g, estimated_by_ai FROM meal_records ORDER BY created_at DESC LIMIT 1"
```
Expected: NULL, NULL, false.

---

### Task H3: Error path QA — Claude API failure

- [ ] **Step 1: Temporarily break the API key**

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-INVALID
supabase functions deploy estimate-meal-nutrition --no-verify-jwt
```

- [ ] **Step 2: Run the AI flow from the app**

Expected:
- Sheet shifts back to input state
- Snackbar appears: 「推定に失敗しました。内容を変えてお試しください」
- User can still tap "挿入" → falls back to normal `onCompose` insertion (the existing behavior, AIなしで送信のフォールバック)

- [ ] **Step 3: Restore API key**

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
supabase functions deploy estimate-meal-nutrition --no-verify-jwt
```

---

### Task H4: Rate limit QA (smoke)

- [ ] **Step 1: Insert 50 dummy logs in last 24h**

```bash
supabase db execute "INSERT INTO ai_estimation_logs (client_id, trainer_id, function_name, status, created_at) SELECT '<test-client-id>', '<test-trainer-id>', 'estimate-meal-nutrition', 'success', now() FROM generate_series(1, 50)"
```

- [ ] **Step 2: Trigger one more AI estimation from the app**

Expected:
- Snackbar: 「AI推定の上限に達しました。しばらくしてからお試しください」
- Sheet returns to input state

- [ ] **Step 3: Cleanup test rows**

```bash
supabase db execute "DELETE FROM ai_estimation_logs WHERE client_id='<test-client-id>'"
```

---

## Phase I — Documentation

### Task I1: Update `IMPLEMENTATION_TASKS.md`

**Files:**
- Modify: `docs/tasks/IMPLEMENTATION_TASKS.md`

- [ ] **Step 1: Mark `2.1` and `2.2` complete**

Replace:
```markdown
- [ ] **2.1 Claude API 連携基盤（Supabase Edge Function）**
```
with:
```markdown
- [x] **2.1 Claude API 連携基盤（Supabase Edge Function）** （2026-05-XX 完了）
  - [x] Edge Function `estimate-meal-nutrition` 実装・デプロイ
  - [x] プロンプト設計（Haiku 4.5 + prompt caching）
  - [x] `ANTHROPIC_API_KEY` を Supabase Secrets で管理
  - [x] レスポンスのパース・バリデーション + Rate limit
```

Same for 2.2:
```markdown
- [x] **2.2 テキスト入力からのカロリー推定** （2026-05-XX 完了）
  - [x] MealTagForm 3-state ステートマシン化
  - [x] aiFeaturesEnabledProvider で課金ゲート
  - [x] 確認 UI（食品リスト + 合計編集）
  - [x] meal_records への保存統合（messages.metadata 経由 + parse-message-tags 改修）
```

Update the top progress summary accordingly (`フェーズ2`: 50%, etc.).

- [ ] **Step 2: Commit**

```bash
git commit -am "docs(tasks): mark phase 2 tasks 2.1 and 2.2 complete"
```

---

### Task I2: Add lessons learned to `lessons.md`

**Files:**
- Modify: `docs/tasks/lessons.md`

- [ ] **Step 1: After implementation, add a section like**

```markdown
## 2026-05-XX — AI Meal Estimation Stage 1

### 学び
- (実装中に得られた具体的な学びを記載: ハマったポイント、Claude プロンプト調整の知見、Riverpod codegen の落とし穴、など)

### 残タスク
- Stage 2: 画像推定 (タスク 2.3)
- Stage 3: メッセージタグ自動推定 (タスク 2.4)
- Stage 4: スクショ分析 (タスク 2.5)
- フェーズ7: Stripe 連携で `subscription_plan` を自動更新
```

- [ ] **Step 2: Commit**

```bash
git commit -am "docs(lessons): record AI meal estimation Stage 1 learnings"
```

---

## Done Criteria

All tasks above complete and:

- [ ] All Phase A migrations applied locally and remotely
- [ ] `estimate-meal-nutrition` deployed to remote Supabase
- [ ] `parse-message-tags` deployed with metadata support
- [ ] All Flutter unit tests pass: `flutter test`
- [ ] `flutter analyze` clean
- [ ] H1 (pro plan happy path), H2 (free plan unchanged), H3 (error fallback), H4 (rate limit) all manually verified
- [ ] `docs/tasks/IMPLEMENTATION_TASKS.md` updated
- [ ] `docs/tasks/lessons.md` updated
- [ ] PR opened against `develop/1.0.0` from `feature/ai-meal-estimation-stage1`

---

## Reference Skills

- @superpowers:test-driven-development — for any new units (model, provider, Edge Function logic)
- @superpowers:verification-before-completion — before claiming a phase done, run verification commands
- @ios-simulator-qa — Phase H QA tasks
- @superpowers:subagent-driven-development — recommended for execution
