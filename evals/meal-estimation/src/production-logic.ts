/**
 * 本番 Edge Function（supabase/functions/estimate-meal-nutrition/index.ts）のロジックの忠実な移植。
 * 行番号は 2026-10-09 時点（commit 362829c）の index.ts を指す。本番側を変更したらここも追従させること
 * （selftest の「移植元の行番号」テストが、引用行に該当コードが無くなったら失敗して知らせる）。
 *
 * 移植しているもの:
 *   - extractJson            … index.ts L145-158
 *   - clampPositive          … index.ts L160-164
 *   - validateEstimation     … index.ts L166-204
 *   - ユーザーテキスト構築    … index.ts L77-79（content の文字列化は L302）
 *   - text ブロックの選択     … index.ts L109-112（type === 'text' の最初のブロック）
 *   - app_name / warning 抽出 … index.ts L441-448
 *   - EMPTY_RESULT 判定       … index.ts L461（foods.length === 0）
 *   - リクエスト形状          … index.ts L73-101（画像ブロック → テキストブロック、system は cache_control 付き1ブロック）
 *
 * 本番との意図的な差:
 *   - 画像ソース: 本番は署名 URL（source.type = 'url'）。評価は同じバイト列を base64（image/jpeg）で送る。
 *     モデルが受け取る画素は同一だが、URL 取得のレイテンシは評価に含まれない。
 *   - model / max_tokens / temperature / output_config はアーム設定（src/arms.ts）で差し替える。
 */
import type Anthropic from '@anthropic-ai/sdk'
import type { ArmConfig } from './arms.js'

export type InputKind = 'photo' | 'screenshot'
export type MealType = 'breakfast' | 'lunch' | 'dinner' | 'snack'

export interface Totals {
  calories: number
  protein_g: number
  fat_g: number
  carbs_g: number
}
export interface Food extends Totals {
  name: string
}
export interface Estimation {
  foods: Food[]
  totals: Totals
}

/**
 * index.ts L145-158 の移植。
 * コードフェンス（```json ... ```）や前後の説明文があっても最初の { 〜最後の } を抜き出す。
 */
export function extractJson(text: string): string {
  const trimmed = text.trim()
  // コードフェンス除去（```json ... ``` または ``` ... ```）
  const fenceMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/)
  if (fenceMatch) return fenceMatch[1].trim()
  // 最初の { と最後の } で囲まれた範囲を抽出
  const first = trimmed.indexOf('{')
  const last = trimmed.lastIndexOf('}')
  if (first !== -1 && last !== -1 && last > first) {
    return trimmed.substring(first, last + 1)
  }
  // 抽出できなければそのまま返す（JSON.parse がエラーを投げる）
  return trimmed
}

/** index.ts L160-164 の移植。数値化 → NaN/負数は 0 → 切り捨て。 */
export function clampPositive(n: unknown): number {
  const v = typeof n === 'number' ? n : parseFloat(String(n))
  if (Number.isNaN(v) || v < 0) return 0
  return Math.floor(v)
}

/**
 * index.ts L166-204 の移植。
 * trustTotals = true（スクショ）: 画面の合計値をそのまま採用（clamp のみ）。
 * trustTotals = false（写真/テキスト）: foods から totals を再計算。
 * 形が不正なら production と同じメッセージで throw する（本番では ESTIMATION_FAILED になる）。
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function validateEstimation(raw: any, trustTotals: boolean): Estimation {
  if (!raw || typeof raw !== 'object') throw new Error('Invalid response shape')
  if (!Array.isArray(raw.foods)) throw new Error('Missing foods array')
  if (!raw.totals || typeof raw.totals !== 'object') throw new Error('Missing totals')
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const foods: Food[] = raw.foods.map((f: any) => {
    if (!f || typeof f.name !== 'string') throw new Error('Food missing name')
    return {
      name: f.name,
      calories: clampPositive(f.calories),
      protein_g: clampPositive(f.protein_g),
      fat_g: clampPositive(f.fat_g),
      carbs_g: clampPositive(f.carbs_g),
    }
  })

  let totals: Totals
  if (trustTotals) {
    totals = {
      calories: clampPositive(raw.totals.calories),
      protein_g: clampPositive(raw.totals.protein_g),
      fat_g: clampPositive(raw.totals.fat_g),
      carbs_g: clampPositive(raw.totals.carbs_g),
    }
  } else {
    totals = foods.reduce<Totals>(
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
 * index.ts L77-79 の移植（content の非文字列 → '' は L302）。
 */
export function buildUserText(mealType: string, content: unknown): string {
  const contentStr = typeof content === 'string' ? content : ''
  return contentStr && contentStr.trim().length > 0
    ? `食事タイプ: ${mealType}\n補足: ${contentStr.trim()}`
    : `食事タイプ: ${mealType}\n補足: (なし、画像のみ)`
}

/** index.ts L441-448 の移植（スクショのときのみ呼ばれる）。 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function extractScreenshotMeta(raw: any): { app_name: string; warning: string | null } {
  const app_name = typeof raw?.app_name === 'string' && raw.app_name.trim().length > 0
    ? raw.app_name.trim()
    : 'unknown'
  const warning = typeof raw?.warning === 'string' && raw.warning.trim().length > 0
    ? raw.warning.trim()
    : null
  return { app_name, warning }
}

/** index.ts L461: foods が空なら EMPTY_RESULT（422）。 */
export function isEmptyResult(result: Estimation): boolean {
  return result.foods.length === 0
}

/** 本番の system プロンプト選択（index.ts L97）。 */
export function selectSystemPrompt(inputKind: InputKind, prompts: { photo: string; screenshot: string }): string {
  return inputKind === 'screenshot' ? prompts.screenshot : prompts.photo
}

/**
 * index.ts L73-101 のリクエスト形状を SDK のパラメータとして組み立てる。
 * 画像（1〜3枚、本番は slice(0, 3)）→ テキストブロック の順。system は cache_control 付きの 1 ブロック。
 * サンプリング系・effort はアーム設定から付与（未指定のキーは送らない）。
 */
export function buildRequestParams(
  arm: ArmConfig,
  systemPrompt: string,
  imagesBase64Jpeg: string[],
  mealType: string,
  content: string,
): Anthropic.MessageCreateParamsNonStreaming {
  if (imagesBase64Jpeg.length < 1 || imagesBase64Jpeg.length > 3) {
    throw new Error(`images must be 1..3 (got ${imagesBase64Jpeg.length})`)
  }
  const userBlocks: Anthropic.ContentBlockParam[] = imagesBase64Jpeg.map((data) => ({
    type: 'image',
    source: { type: 'base64', media_type: 'image/jpeg', data },
  }))
  userBlocks.push({ type: 'text', text: buildUserText(mealType, content) })

  const params: Anthropic.MessageCreateParamsNonStreaming = {
    model: arm.model,
    max_tokens: arm.max_tokens,
    system: [{ type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: userBlocks }],
  }
  if (arm.temperature !== undefined) params.temperature = arm.temperature
  if (arm.effort !== undefined) params.output_config = { effort: arm.effort }
  return params
}

export type Outcome = 'ok' | 'empty' | 'parse_fail' | 'refusal' | 'error'

export interface ProcessedResponse {
  /** 最初の type==='text' ブロックの本文（thinking ブロックが先頭に来ても type で選ぶ） */
  raw_text: string | null
  parsed: Estimation | null
  parse_error: string | null
  app_name: string | null
  warning: string | null
  /** 本番の EMPTY_RESULT 判定（foods.length === 0）。パースできなかった場合は null */
  empty_result: boolean | null
  outcome: Outcome
}

/**
 * レスポンス 1 件を本番と同じ順序で処理する:
 *   text ブロック選択（L109-110）→ extractJson + JSON.parse（L111-112）→ validateEstimation（L440）
 *   → app_name/warning（L441-448）→ EMPTY 判定（L461）。
 * 追加: stop_reason === 'refusal' は本文をパースせず outcome='refusal'（feasibility §4-3: EMPTY_RESULT 相当に写像する想定）。
 * stop_reason === 'max_tokens' は本文があればそのままパースを試みる（記録は呼び出し側）。
 */
export function processResponse(
  message: Pick<Anthropic.Message, 'content' | 'stop_reason'>,
  inputKind: InputKind,
): ProcessedResponse {
  const textBlock = message.content.find((b): b is Anthropic.TextBlock => b.type === 'text')
  const raw_text = textBlock ? textBlock.text : null
  const base = { raw_text, parsed: null, app_name: null, warning: null, empty_result: null }

  if (message.stop_reason === 'refusal') {
    return { ...base, parse_error: 'stop_reason=refusal', outcome: 'refusal' }
  }
  if (!raw_text) {
    // index.ts L110: if (!textBlock?.text) throw new Error('No text in Claude response')
    return { ...base, parse_error: 'No text in Claude response', outcome: 'parse_fail' }
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let raw: any
  let parsed: Estimation
  try {
    raw = JSON.parse(extractJson(raw_text))
    parsed = validateEstimation(raw, inputKind === 'screenshot')
  } catch (e) {
    return { ...base, parse_error: (e as Error).message, outcome: 'parse_fail' }
  }
  const meta = inputKind === 'screenshot' ? extractScreenshotMeta(raw) : { app_name: null, warning: null }
  const empty = isEmptyResult(parsed)
  return {
    raw_text,
    parsed,
    parse_error: null,
    app_name: meta.app_name,
    warning: meta.warning,
    empty_result: empty,
    outcome: empty ? 'empty' : 'ok',
  }
}
