// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

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

const FUNCTION_NAME = 'estimate-meal-nutrition'

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
    const jsonText = extractJson(textBlock.text)
    return JSON.parse(jsonText)
  } finally {
    clearTimeout(timeoutId)
  }
}

/**
 * Claude が ```json ... ``` のコードフェンスや前後のテキストを返してきても
 * 最初の { から最後の } までを抜き出して JSON.parse できる形にする防御層。
 */
function extractJson(text: string): string {
  const trimmed = text.trim()
  // コードフェンス除去（```json ... ``` または ``` ... ```）
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/)
  if (fenceMatch) return fenceMatch[1].trim()
  // 最初の { と最後の } で囲まれた範囲を抽出（前後にプロセス説明がある場合のフォールバック）
  const first = trimmed.indexOf('{')
  const last = trimmed.lastIndexOf('}')
  if (first !== -1 && last !== -1 && last > first) {
    return trimmed.substring(first, last + 1)
  }
  // 抽出できなければそのまま返す（JSON.parse がエラーを投げる）
  return trimmed
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
  // totals は foods から再計算（Claude のtotals不整合への防御）
  const totals = foods.reduce(
    (acc, f) => ({
      calories: acc.calories + f.calories,
      protein_g: acc.protein_g + f.protein_g,
      fat_g: acc.fat_g + f.fat_g,
      carbs_g: acc.carbs_g + f.carbs_g,
    }),
    { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 },
  )
  return { foods, totals }
}

function errorResponse(code: string, message: string, status: number) {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }
  try {
    // 1. Auth: 呼び出し元の JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return errorResponse('FORBIDDEN', 'No auth token', 403)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY')

    if (!anthropicKey) {
      console.error('ANTHROPIC_API_KEY not set')
      return errorResponse('ESTIMATION_FAILED', 'API key missing', 500)
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userErr } = await userClient.auth.getUser()
    if (userErr || !userData.user) {
      return errorResponse('FORBIDDEN', 'Invalid token', 403)
    }
    const authUid = userData.user.id

    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 2. クライアント取得
    const { data: client, error: clientErr } = await supabase
      .from('clients')
      .select('client_id, trainer_id')
      .eq('client_id', authUid)
      .maybeSingle()
    if (clientErr || !client) {
      return errorResponse('FORBIDDEN', 'Client not found', 403)
    }

    // 3. subscription gate
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
    // 注: image_urls は Stage 1 では受信しても無視（仕様書 §5.1）

    if (!['breakfast', 'lunch', 'dinner', 'snack'].includes(meal_type)) {
      return errorResponse('INVALID_INPUT', 'Invalid meal_type', 400)
    }
    if (typeof content !== 'string' || content.trim().length === 0) {
      return errorResponse('INVALID_INPUT', 'Empty content', 400)
    }

    // 5. Rate limit (Claude 呼び出し前にチェック、ログは Claude 呼び出し後に挿入)
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const { count: clientCount, error: cErr } = await supabase
      .from('ai_estimation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('client_id', authUid)
      .gte('created_at', since)
    if (cErr) console.error('rate-limit (client) query error:', cErr)
    if ((clientCount ?? 0) >= 50) {
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'RATE_LIMIT',
      })
      return errorResponse('RATE_LIMIT', 'Per-client daily limit (50) exceeded', 429)
    }
    const { count: trainerCount, error: tErr } = await supabase
      .from('ai_estimation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('trainer_id', client.trainer_id)
      .gte('created_at', since)
    if (tErr) console.error('rate-limit (trainer) query error:', tErr)
    if ((trainerCount ?? 0) >= 1000) {
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'RATE_LIMIT',
      })
      return errorResponse('RATE_LIMIT', 'Per-trainer daily limit (1000) exceeded', 429)
    }

    // 6. Claude 呼び出し
    let result
    try {
      const raw = await callClaude(anthropicKey, meal_type, content)
      result = validateEstimation(raw)
    } catch (e) {
      console.error('Claude call/parse failed:', e)
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'ESTIMATION_FAILED',
      })
      return errorResponse('ESTIMATION_FAILED', 'Estimation failed', 500)
    }

    if (result.foods.length === 0) {
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'EMPTY_RESULT',
      })
      return errorResponse('ESTIMATION_FAILED', 'No foods could be estimated', 500)
    }

    // 7. 成功ログ
    await supabase.from('ai_estimation_logs').insert({
      client_id: authUid,
      trainer_id: client.trainer_id,
      function_name: FUNCTION_NAME,
      status: 'success',
    })

    return new Response(JSON.stringify(result), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error('estimate-meal-nutrition error:', e)
    return errorResponse('ESTIMATION_FAILED', 'Internal error', 500)
  }
})
