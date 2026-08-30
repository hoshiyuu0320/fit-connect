// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SYSTEM_PROMPT = `あなたは栄養素推定アシスタントです。日本語の食事内容テキストおよび/または食事画像から、食品ごとに推定値（カロリー・タンパク質・脂質・炭水化物）を計算します。

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
- totals は foods の合計と一致させる
- 画像が複数枚ある場合は同一食事の異なる視点／別皿として扱い、合計値を返す
- 画像が食事と無関係（人物、風景、ミーム等）と判断したら foods を空配列で返す
- テキスト補足は画像から得た情報の修正に優先する（例:「ご飯大盛り」なら米飯の量を増やす）`

const SCREENSHOT_SYSTEM_PROMPT = `あなたは食事管理アプリの画面スクリーンショットから栄養情報を読み取るアシスタントです。これは他社の食事管理アプリ（あすけん、カロミル、MyFitnessPal 等）の画面のスクリーンショットです。

返却形式は厳密に以下の JSON のみ（説明文・コードフェンス禁止）:
{
  "foods": [{"name": string, "calories": number, "protein_g": number, "fat_g": number, "carbs_g": number}],
  "totals": {"calories": number, "protein_g": number, "fat_g": number, "carbs_g": number},
  "app_name": string,
  "warning": string | null
}

指針:
- 数値は画面に表示されている値をそのまま使う。自分で推定や再計算をしない
- 画面に表示された合計の「カロリー・たんぱく質(P)・脂質(F)・炭水化物(C)」のグラム数を totals に必ず入れる。多くのアプリは食品リストの上部や円グラフ/棒グラフで P・F・C のグラム数を表示しているので、それを読み取る
- food 単位で PFC が表示されていない場合は、各 food の protein_g/fat_g/carbs_g は 0 でよい。ただし totals の P・F・C は画面の合計表示から必ず読み取ること（totals を 0 のままにしない）
- 食品名リストが画面にあれば foods に列挙する。合計値しか読み取れない場合は foods に1件「合計」としてまとめてよい
- すべて整数（小数点以下は切り捨て）
- app_name には画面の特徴から推測したアプリ名（例: "あすけん", "カロミル", "MyFitnessPal"）を入れる。判別できなければ "unknown"
- 1日分（朝・昼・夕・間食）が写っている場合でも、画面の合計または最も主要な1食分のみを返す
- 食事管理アプリの画面でない、または栄養数値を読み取れない場合は foods を空配列で返す
- スクショが2枚以上ある場合は、それらが同じ食事/記録のものか、カロリーと PFC（P×4 + F×9 + C×4 ≒ カロリー）が噛み合うかを確認する。別の食事・別の日のものが混在している、または数値が大きく食い違うと判断した場合は warning に短い日本語の指摘文を入れる（例: 「カロリーの画面とPFCの画面で合計が噛み合いません。同じ食事の画面か確認してください」）。問題なければ warning は null。スクショが1枚だけの場合は常に null`

const FUNCTION_NAME = 'estimate-meal-nutrition'

// ---- レートリミット / クォータ定数 ----
// 出典: docs/tasks/2026-07-11-pro-pricing-proposal.md §8 決定事項（2026-07-12 オーナー確定）
// - Free: 月30回・トレーナー単位の共通プール（担当顧客全員の合計・全リクエスト種別）。使い切りで全ブロック
// - 有料（pro/business/トライアル中）: 10回/顧客/日 + 100回/顧客/月。超過時はテキストのみ許可
// - 全プラン共通: トレーナー単位 1000回/日 のバックストップ（従来からの既存値を維持）
const FREE_TRAINER_MONTHLY_POOL = 30
const PAID_CLIENT_DAILY_LIMIT = 10
const PAID_CLIENT_MONTHLY_LIMIT = 100
const TRAINER_DAILY_BACKSTOP = 1000

async function callClaude(
  apiKey: string,
  mealType: string,
  content: string,
  imageUrls: string[],
  inputKind: 'photo' | 'screenshot',
): Promise<any> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 30_000)
  try {
    const hasImages = imageUrls.length > 0
    const model = hasImages ? 'claude-sonnet-4-6' : 'claude-haiku-4-5'

    const userBlocks: any[] = []
    for (const url of imageUrls) {
      userBlocks.push({ type: 'image', source: { type: 'url', url } })
    }
    const textPart = content && content.trim().length > 0
      ? `食事タイプ: ${mealType}\n補足: ${content.trim()}`
      : `食事タイプ: ${mealType}\n補足: (なし、画像のみ)`
    userBlocks.push({ type: 'text', text: textPart })

    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      signal: controller.signal,
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        temperature: 0.2,
        system: [
          {
            type: 'text',
            text: inputKind === 'screenshot' ? SCREENSHOT_SYSTEM_PROMPT : SYSTEM_PROMPT,
            cache_control: { type: 'ephemeral' },
          },
        ],
        messages: [{ role: 'user', content: userBlocks }],
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
 * image_urls の要素（フルURL or バケット相対パス）から message-photos の
 * オブジェクトパスを取り出す。
 * - http(s) 始まり: '/storage/v1/object/(public|sign)/message-photos/' 以降を
 *   パスとして抽出（クエリ・フラグメントは除去）。message-photos 以外のURLは null
 * - それ以外: バケット相対パスとみなす（念のためクエリ・フラグメントを除去）
 *
 * バケット private 化後は新クライアントがパスを送るが、旧クライアントの
 * 公開URL・署名URLも受け付けて後方互換を保つ。
 */
function extractMessagePhotoPath(value: string): string | null {
  const trimmed = value.trim()
  if (trimmed.length === 0) return null
  if (/^https?:\/\//i.test(trimmed)) {
    const match = trimmed.match(
      /\/storage\/v1\/object\/(?:public|sign)\/message-photos\/([^?#]+)/,
    )
    return match ? match[1] : null
  }
  const path = trimmed.split(/[?#]/)[0]
  return path.length > 0 ? path : null
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

function validateEstimation(raw: any, trustTotals: boolean): { foods: any[]; totals: any } {
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

  let totals
  if (trustTotals) {
    // スクショ: 画面に表示された合計値をそのまま採用（食品ごとのPFCは未表示のことが多く、
    // foods から再計算すると画面の合計PFCを 0 に潰してしまうため）。clamp のみ行う。
    totals = {
      calories: clampPositive(raw.totals.calories),
      protein_g: clampPositive(raw.totals.protein_g),
      fat_g: clampPositive(raw.totals.fat_g),
      carbs_g: clampPositive(raw.totals.carbs_g),
    }
  } else {
    // 料理写真/テキスト: foods から再計算（Claude のtotals不整合への防御）
    totals = foods.reduce(
      (acc, f) => ({
        calories: acc.calories + f.calories,
        protein_g: acc.protein_g + f.protein_g,
        fat_g: acc.fat_g + f.fat_g,
        carbs_g: acc.carbs_g + f.carbs_g,
      }),
      { calories: 0, protein_g: 0, fat_g: 0, carbs_g: 0 },
    )
  }
  return { foods, totals }
}

/**
 * 「月」= JST（Asia/Tokyo, UTC+9・夏時間なし）の暦月。
 * JST での月初 00:00 を UTC の ISO 文字列に変換して返し、created_at >= の比較に使う。
 * 注意: UTC の月初とはずれる（例: JST 2026-07-01T00:00:00 は UTC では 2026-06-30T15:00:00Z）。
 */
function jstMonthStartIso(now: Date = new Date()): string {
  const JST_OFFSET_MS = 9 * 60 * 60 * 1000
  const jst = new Date(now.getTime() + JST_OFFSET_MS)
  // シフト後の getUTC* が JST のローカル年月を表す
  const monthStartUtcMs = Date.UTC(jst.getUTCFullYear(), jst.getUTCMonth(), 1) - JST_OFFSET_MS
  return new Date(monthStartUtcMs).toISOString()
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

    // 3. トレーナー取得と実効プラン判定
    // §8 決定（2026-07-12）: Free プランも月30回プールで AI を利用可のため、
    // プランによる全面 403 は廃止。403 は trainers 行が見つからない/取得エラー時のみ。
    // 実効プラン規則: pro / business、または trial_ends_at が未来（トライアル中 = Pro相当）
    // なら有料ティア、それ以外は Free ティアとしてクォータ判定する。
    const { data: trainer, error: trainerErr } = await supabase
      .from('trainers')
      .select('id, subscription_plan, trial_ends_at')
      .eq('id', client.trainer_id)
      .maybeSingle()
    if (trainerErr || !trainer) {
      return errorResponse('FORBIDDEN', 'Trainer not found', 403)
    }
    const plan = trainer.subscription_plan
    const isPaidPlan = plan === 'pro' || plan === 'business'
    const isTrialActive =
      typeof trainer.trial_ends_at === 'string' &&
      new Date(trainer.trial_ends_at).getTime() > Date.now()
    const isPaidTier = isPaidPlan || isTrialActive

    // 4. リクエスト body パース
    const body = await req.json().catch(() => null)
    if (!body) return errorResponse('INVALID_INPUT', 'Invalid JSON body', 400)
    const { meal_type, content } = body
    const inputKind: 'photo' | 'screenshot' =
      body.input_kind === 'screenshot' ? 'screenshot' : 'photo'
    const rawImageUrls = body.image_urls
    const imageUrls: string[] = Array.isArray(rawImageUrls)
      ? rawImageUrls.filter((u): u is string => typeof u === 'string' && u.length > 0).slice(0, 3)
      : []

    if (!['breakfast', 'lunch', 'dinner', 'snack'].includes(meal_type)) {
      return errorResponse('INVALID_INPUT', 'Invalid meal_type', 400)
    }
    const contentStr = typeof content === 'string' ? content : ''
    if (inputKind === 'screenshot' && imageUrls.length === 0) {
      return errorResponse('INVALID_INPUT', 'Screenshot mode requires an image', 400)
    }
    if (contentStr.trim().length === 0 && imageUrls.length === 0) {
      return errorResponse('INVALID_INPUT', 'Empty content and no images', 400)
    }

    // 5. レートリミット / クォータ（Claude 呼び出し前にチェック）
    // 出典: docs/tasks/2026-07-11-pro-pricing-proposal.md §8（2026-07-12 オーナー確定）
    // - Free（非トライアル）: トレーナー単位・月30回の共通プール（担当顧客全員の合計・
    //   全リクエスト種別を count）。使い切ったらテキストも含め全ブロック。日次判定はなし。
    // - 有料ティア（pro/business/トライアル中）: 顧客単位 10回/日（24hローリング窓）
    //   + 100回/月（JST暦月）。超過時はテキストのみ許可 = 画像付きリクエストのみ 429 を返す。
    // - 全プラン共通: トレーナー単位 1000回/日 のバックストップ（既存挙動を維持）。
    // count はいずれも従来同様「全 status の試行」を対象とする。
    const hasImages = imageUrls.length > 0
    const logQuotaError = (errorCode: string) =>
      supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: errorCode,
      })
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()

    if (isPaidTier) {
      // 有料ティア: テキストのみのリクエストは顧客単位クォータの対象外（常に通す）ため、
      // 画像付きのときだけ count クエリを発行する
      if (hasImages) {
        const { count: clientDaily, error: cdErr } = await supabase
          .from('ai_estimation_logs')
          .select('*', { count: 'exact', head: true })
          .eq('client_id', authUid)
          .gte('created_at', since)
        if (cdErr) console.error('rate-limit (client daily) query error:', cdErr)
        if ((clientDaily ?? 0) >= PAID_CLIENT_DAILY_LIMIT) {
          await logQuotaError('RATE_LIMIT')
          return errorResponse(
            'RATE_LIMIT',
            `Per-client daily limit (${PAID_CLIENT_DAILY_LIMIT}) exceeded`,
            429,
          )
        }
        const { count: clientMonthly, error: cmErr } = await supabase
          .from('ai_estimation_logs')
          .select('*', { count: 'exact', head: true })
          .eq('client_id', authUid)
          .gte('created_at', jstMonthStartIso())
        if (cmErr) console.error('rate-limit (client monthly) query error:', cmErr)
        if ((clientMonthly ?? 0) >= PAID_CLIENT_MONTHLY_LIMIT) {
          await logQuotaError('MONTHLY_QUOTA_EXCEEDED')
          return errorResponse(
            'MONTHLY_QUOTA_EXCEEDED',
            `Per-client monthly limit (${PAID_CLIENT_MONTHLY_LIMIT}) exceeded`,
            429,
          )
        }
      }
    } else {
      // Free ティア: トレーナー単位・月30回の共通プール（画像有無を問わず全ブロック対象）
      const { count: trainerMonthly, error: fmErr } = await supabase
        .from('ai_estimation_logs')
        .select('*', { count: 'exact', head: true })
        .eq('trainer_id', client.trainer_id)
        .gte('created_at', jstMonthStartIso())
      if (fmErr) console.error('rate-limit (free monthly pool) query error:', fmErr)
      if ((trainerMonthly ?? 0) >= FREE_TRAINER_MONTHLY_POOL) {
        await logQuotaError('FREE_QUOTA_EXCEEDED')
        return errorResponse('FREE_QUOTA_EXCEEDED', '今月のAI利用枠を使い切りました', 429)
      }
    }

    // 全プラン共通バックストップ: トレーナー単位 1000回/日（既存エラー形式のまま）
    const { count: trainerCount, error: tErr } = await supabase
      .from('ai_estimation_logs')
      .select('*', { count: 'exact', head: true })
      .eq('trainer_id', client.trainer_id)
      .gte('created_at', since)
    if (tErr) console.error('rate-limit (trainer) query error:', tErr)
    if ((trainerCount ?? 0) >= TRAINER_DAILY_BACKSTOP) {
      await logQuotaError('RATE_LIMIT')
      return errorResponse(
        'RATE_LIMIT',
        `Per-trainer daily limit (${TRAINER_DAILY_BACKSTOP}) exceeded`,
        429,
      )
    }

    // 6. 画像の署名URL化（message-photos private 化対応）
    // Anthropic API は source:{type:'url'} のURLをサーバー側で fetch するため、
    // service_role で TTL 600秒の署名URLを発行して渡す（推定は30秒タイムアウトなので十分）。
    // 所有権チェック: 呼び出し元（authUid）のフォルダ配下（{uid}/… / {uid}/ai/…）
    // 以外のパスは、他人の写真を署名させる悪用を防ぐためスキップする。
    // 正当なクライアントは常に自フォルダのパスしか送らないため後方互換は壊れない。
    // パス抽出・所有権・署名に失敗した要素はスキップし、画像指定があったのに1枚も
    // 残らなければ既存の推定失敗系（ESTIMATION_FAILED）で返す。
    const signedImageUrls: string[] = (
      await Promise.all(
        imageUrls.map(async (value) => {
          const path = extractMessagePhotoPath(value)
          if (!path) {
            console.error('Could not extract message-photos path from image_urls element')
            return null
          }
          if (!path.startsWith(`${authUid}/`)) {
            console.error('Skipping image_urls element: path not owned by caller')
            return null
          }
          const { data: signed, error: signErr } = await supabase.storage
            .from('message-photos')
            .createSignedUrl(path, 600)
          if (signErr || !signed?.signedUrl) {
            console.error(`createSignedUrl failed for ${path}:`, signErr)
            return null
          }
          return signed.signedUrl
        }),
      )
    ).filter((u): u is string => u !== null)
    if (imageUrls.length > 0 && signedImageUrls.length === 0) {
      await supabase.from('ai_estimation_logs').insert({
        client_id: authUid,
        trainer_id: client.trainer_id,
        function_name: FUNCTION_NAME,
        status: 'error',
        error_code: 'ESTIMATION_FAILED',
      })
      return errorResponse('ESTIMATION_FAILED', 'Failed to resolve image URLs', 500)
    }

    // 7. Claude 呼び出し
    let result
    let appName = ''
    let warning: string | null = null
    try {
      const raw = await callClaude(anthropicKey, meal_type, contentStr, signedImageUrls, inputKind)
      result = validateEstimation(raw, inputKind === 'screenshot')
      if (inputKind === 'screenshot') {
        appName = typeof raw.app_name === 'string' && raw.app_name.trim().length > 0
          ? raw.app_name.trim()
          : 'unknown'
        warning = typeof raw.warning === 'string' && raw.warning.trim().length > 0
          ? raw.warning.trim()
          : null
      }
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
      return errorResponse('EMPTY_RESULT', 'No foods could be identified', 422)
    }

    // 8. 成功ログ
    await supabase.from('ai_estimation_logs').insert({
      client_id: authUid,
      trainer_id: client.trainer_id,
      function_name: FUNCTION_NAME,
      status: 'success',
    })

    const responseBody = inputKind === 'screenshot'
      ? { ...result, app_name: appName, warning }
      : result
    return new Response(JSON.stringify(responseBody), {
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    })
  } catch (e) {
    console.error('estimate-meal-nutrition error:', e)
    return errorResponse('ESTIMATION_FAILED', 'Internal error', 500)
  }
})
