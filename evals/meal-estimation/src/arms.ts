/**
 * 比較アーム・料金表・Vision 解像度ティア。
 *
 * 出典（2026-10-09 に確認）:
 *   - 料金: https://platform.claude.com/docs/en/about-claude/pricing（Model pricing / Long context pricing）
 *   - 解像度ティア: https://platform.claude.com/docs/en/build-with-claude/vision（Resolution and token cost:
 *     High-resolution = "Claude 4.7 and later models" 2576px / 4784 tokens、Standard = その他 1568px / 1568 tokens）
 *   - リサイズ規則: https://platform.claude.com/docs/en/build-with-claude/vision-coordinates の TypeScript 参照実装
 *   - Haiku 5.5 の制約（サンプリング非デフォルト値は 400、adaptive thinking 既定 ON、fallback なし）:
 *     claude-api スキル shared/model-migration.md「Migrating to Claude Haiku 5.5」
 */

export type ArmId = 'sonnet-4-6-prod' | 'haiku-5-5-low' | 'haiku-5-5-medium' | 'sonnet-5-5-low'
export type Effort = 'low' | 'medium'
export type Tokenizer = 'legacy' | 'claude-4.7+'
export type VisionTierName = 'standard' | 'high-res'

export interface ArmConfig {
  id: ArmId
  /** 本番ベースライン（比較の基準） */
  baseline: boolean
  model: string
  max_tokens: number
  /** undefined のときはリクエストに含めない */
  temperature?: number
  /** undefined のときは output_config を送らない */
  effort?: Effort
  tokenizer: Tokenizer
  vision_tier: VisionTierName
  /** adaptive thinking が既定 ON のモデルか（thinking パラメータ自体は送らない） */
  adaptive_thinking: boolean
  /** 見積り用: thinking に使われると仮定する出力トークン（low 500 / medium 1500） */
  est_thinking_tokens: number
  /** なぜこの設定なのか（README / meta.json 用） */
  rationale: string
}

export const ARMS: Record<ArmId, ArmConfig> = {
  'sonnet-4-6-prod': {
    id: 'sonnet-4-6-prod',
    baseline: true,
    model: 'claude-sonnet-4-6',
    max_tokens: 1024,
    temperature: 0.2,
    tokenizer: 'legacy',
    vision_tier: 'standard',
    adaptive_thinking: false,
    est_thinking_tokens: 0,
    rationale: '本番そのまま（index.ts L71/L92/L93: claude-sonnet-4-6, max_tokens 1024, temperature 0.2）',
  },
  'haiku-5-5-low': {
    id: 'haiku-5-5-low',
    baseline: false,
    model: 'claude-haiku-5-5',
    max_tokens: 4096,
    effort: 'low',
    tokenizer: 'claude-4.7+',
    vision_tier: 'high-res',
    adaptive_thinking: true,
    est_thinking_tokens: 500,
    rationale:
      'temperature/top_p/top_k は非デフォルト値が 400 になるため送らない。thinking は adaptive が既定なので送らない。' +
      'thinking が max_tokens を消費するため 4096 に拡大。短い抽出タスク向けに effort low。',
  },
  'haiku-5-5-medium': {
    id: 'haiku-5-5-medium',
    baseline: false,
    model: 'claude-haiku-5-5',
    max_tokens: 4096,
    effort: 'medium',
    tokenizer: 'claude-4.7+',
    vision_tier: 'high-res',
    adaptive_thinking: true,
    est_thinking_tokens: 1500,
    rationale: 'haiku-5-5-low と同じで effort のみ medium（Haiku 5.5 の既定値）。',
  },
  'sonnet-5-5-low': {
    id: 'sonnet-5-5-low',
    baseline: false,
    model: 'claude-sonnet-5-5',
    max_tokens: 4096,
    effort: 'low',
    tokenizer: 'claude-4.7+',
    vision_tier: 'high-res',
    adaptive_thinking: true,
    est_thinking_tokens: 500,
    rationale:
      '精度アップグレード候補。サンプリング系は送らない（非デフォルト値は拒否される）。thinking は既定の adaptive。' +
      '既定 effort は high のため、コストを抑える low を明示。',
  },
}

export const ALL_ARM_IDS = Object.keys(ARMS) as ArmId[]
export const BASELINE_ARM_ID: ArmId = 'sonnet-4-6-prod'

export function getArm(id: string): ArmConfig {
  if (!(id in ARMS)) throw new Error(`未知のアーム: ${id}（有効: ${ALL_ARM_IDS.join(', ')}）`)
  return ARMS[id as ArmId]
}

// ---------------------------------------------------------------------------
// 料金（USD / MTok）
// ---------------------------------------------------------------------------

export const JPY_PER_USD = 150

export interface PriceCard {
  name: string
  input: number
  cache_write_5m: number
  cache_write_1h: number
  cache_read: number
  output: number
}

interface ModelPricing {
  /** prompt_tokens <= max_prompt_tokens のカードを先頭から選ぶ */
  cards: Array<{ max_prompt_tokens: number; card: PriceCard }>
}

/** Haiku 5.5 のレートカード切替しきい値（1 リクエストのプロンプト長） */
export const HAIKU_55_LONG_PROMPT_THRESHOLD = 100_000

export const PRICING: Record<string, ModelPricing> = {
  'claude-sonnet-4-6': {
    cards: [{
      max_prompt_tokens: Infinity,
      card: { name: 'sonnet-4-6', input: 3, cache_write_5m: 3.75, cache_write_1h: 6, cache_read: 0.3, output: 15 },
    }],
  },
  'claude-sonnet-5-5': {
    cards: [{
      max_prompt_tokens: Infinity,
      // cache hit は 0.05x（pricing ページ脚注 2: Sonnet 5.5 は $0.10）
      card: { name: 'sonnet-5-5', input: 2, cache_write_5m: 2.5, cache_write_1h: 4, cache_read: 0.1, output: 10 },
    }],
  },
  'claude-haiku-5-5': {
    cards: [
      {
        max_prompt_tokens: HAIKU_55_LONG_PROMPT_THRESHOLD,
        card: { name: 'haiku-5-5:<=100K', input: 0.1, cache_write_5m: 0.125, cache_write_1h: 0.2, cache_read: 0.01, output: 0.5 },
      },
      {
        max_prompt_tokens: Infinity,
        card: { name: 'haiku-5-5:>100K', input: 0.5, cache_write_5m: 0.625, cache_write_1h: 1, cache_read: 0.05, output: 2.5 },
      },
    ],
  },
}

/** SDK の Usage と互換な最小形（テストで偽 usage を渡せるよう構造型にしている） */
export interface UsageLike {
  input_tokens: number
  output_tokens: number
  cache_creation_input_tokens?: number | null
  cache_read_input_tokens?: number | null
  cache_creation?: { ephemeral_5m_input_tokens?: number | null; ephemeral_1h_input_tokens?: number | null } | null
}

export function priceCardFor(model: string, promptTokens: number): PriceCard {
  const p = PRICING[model]
  if (!p) throw new Error(`料金表に無いモデル: ${model}`)
  const hit = p.cards.find((c) => promptTokens <= c.max_prompt_tokens)
  if (!hit) throw new Error(`料金カードを決められません: ${model} prompt=${promptTokens}`)
  return hit.card
}

export interface CostBreakdown {
  cost_usd: number
  price_card: string
  /** input_tokens + cache_creation_input_tokens + cache_read_input_tokens（Haiku 5.5 のカード判定に使う値） */
  prompt_tokens: number
}

/** 実測 usage からコストを計算する。cache_creation の内訳が無ければ全量を 5 分キャッシュ書き込みとみなす。 */
export function costFromUsage(model: string, usage: UsageLike): CostBreakdown {
  const input = usage.input_tokens ?? 0
  const cacheWrite = usage.cache_creation_input_tokens ?? 0
  const cacheRead = usage.cache_read_input_tokens ?? 0
  const output = usage.output_tokens ?? 0
  const prompt = input + cacheWrite + cacheRead
  const card = priceCardFor(model, prompt)
  let write1h = usage.cache_creation?.ephemeral_1h_input_tokens ?? 0
  if (write1h > cacheWrite) write1h = cacheWrite
  const write5m = cacheWrite - write1h
  const cost =
    (input * card.input +
      write5m * card.cache_write_5m +
      write1h * card.cache_write_1h +
      cacheRead * card.cache_read +
      output * card.output) /
    1_000_000
  return { cost_usd: cost, price_card: card.name, prompt_tokens: prompt }
}

/** 見積り用（キャッシュ無しとして計算） */
export function estimateCostUsd(model: string, promptTokens: number, outputTokens: number): CostBreakdown {
  const card = priceCardFor(model, promptTokens)
  return {
    cost_usd: (promptTokens * card.input + outputTokens * card.output) / 1_000_000,
    price_card: card.name,
    prompt_tokens: promptTokens,
  }
}

// ---------------------------------------------------------------------------
// Vision 解像度ティアと visual token
// ---------------------------------------------------------------------------

export interface VisionTier {
  max_edge: number
  max_tokens: number
}

export const VISION_TIERS: Record<VisionTierName, VisionTier> = {
  standard: { max_edge: 1568, max_tokens: 1568 },
  'high-res': { max_edge: 2576, max_tokens: 4784 },
}

/** Visual tokens consumed by an image: one token per 28x28 pixel patch.（vision-coordinates 参照実装） */
export function countImageTokens(width: number, height: number): number {
  return Math.ceil(width / 28) * Math.ceil(height / 28)
}

/**
 * Round half to even (banker's rounding), matching Python's round().（vision-coordinates 参照実装）
 * The live API resolves exact .5 ties toward the even neighbor.
 */
export function roundTiesToEven(value: number): number {
  const floor = Math.floor(value)
  if (value - floor !== 0.5) return Math.round(value)
  return floor % 2 === 0 ? floor : floor + 1
}

/**
 * The size Claude resizes an image to before padding.（vision-coordinates の TypeScript 参照実装をそのまま移植）
 * Returns [width, height]. Images that already fit within the limits are returned unchanged.
 */
export function resizedSize(width: number, height: number, maxEdge = 1568, maxTokens = 1568): [number, number] {
  const fits = (w: number, h: number): boolean =>
    Math.ceil(w / 28) * 28 <= maxEdge &&
    Math.ceil(h / 28) * 28 <= maxEdge &&
    countImageTokens(w, h) <= maxTokens

  if (fits(width, height)) return [width, height]
  if (height > width) {
    const [resizedH, resizedW] = resizedSize(height, width, maxEdge, maxTokens)
    return [resizedW, resizedH]
  }

  // Binary search along the long edge for the largest aspect-preserving size that fits.
  const aspectRatio = width / height
  let lo = 1 // lo always fits
  let hi = width // hi never fits
  while (lo + 1 < hi) {
    const mid = Math.floor((lo + hi) / 2)
    if (fits(mid, Math.max(roundTiesToEven(mid / aspectRatio), 1))) {
      lo = mid
    } else {
      hi = mid
    }
  }
  return [lo, Math.max(roundTiesToEven(lo / aspectRatio), 1)]
}

/** ティア適用後の visual token 数（ローカル見積り用） */
export function visualTokensFor(width: number, height: number, tier: VisionTierName): {
  resized: [number, number]
  tokens: number
} {
  const t = VISION_TIERS[tier]
  const resized = resizedSize(width, height, t.max_edge, t.max_tokens)
  return { resized, tokens: countImageTokens(resized[0], resized[1]) }
}

// ---------------------------------------------------------------------------
// ローカル見積りの係数（概算。--estimate でキーがあれば countTokens の実数を使う）
// ---------------------------------------------------------------------------

/** 文字数 → トークン数の概算係数（日本語主体のプロンプト） */
export const TEXT_TOKENS_PER_CHAR: Record<Tokenizer, number> = {
  legacy: 0.9,
  'claude-4.7+': 1.17, // 0.9 × 約 1.3（新トークナイザ）
}

/** 見積り用: 可視出力（JSON）トークン数の仮定 */
export const EST_VISIBLE_OUTPUT_TOKENS = 400

export function estimatedOutputTokens(arm: ArmConfig): number {
  return EST_VISIBLE_OUTPUT_TOKENS + (arm.adaptive_thinking ? arm.est_thinking_tokens : 0)
}
