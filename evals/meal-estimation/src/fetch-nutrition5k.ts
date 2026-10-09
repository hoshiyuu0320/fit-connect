/**
 * Nutrition5k から料理写真データセットを作る。
 *   npm run fetch:nutrition5k -- --n 50 [--seed 42]
 *
 * データ出典（再配布・公開前に必ず原典で確認すること）:
 *   Nutrition5k — Thames et al., "Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food",
 *   CVPR 2021, Google Research. https://github.com/google-research-datasets/Nutrition5k
 *   ライセンス: CC BY 4.0（GitHub の README 記載。利用前に上記ページで最新の条件を確認する）
 *
 * - metadata/dish_metadata_cafe1.csv / cafe2.csv の各行先頭 6 列
 *   （dish_id,total_calories,total_mass,total_fat,total_carb,total_protein）だけを使う。以降は食材ごとの列で無視する。
 * - 50 ≤ kcal ≤ 1500 の料理をシード付きで並べ替え、realsense_overhead/<dish_id>/rgb.png を 404 を飛ばしながら N 枚取得。
 * - モバイルアプリと同じ前処理（1920x1080 の枠に収める・拡大なし・JPEG 品質 80）。
 * - 書き出し: datasets/photos-nutrition5k/{cases.json, images/*.jpg}（.gitignore 済み）
 *
 * ネットワーク: Node の組み込み fetch は HTTPS_PROXY を読まないため、NODE_USE_ENV_PROXY=1 を付けて自分自身を
 * 再実行する。プロキシ（と、その許可リスト）を迂回して直接接続することはしない。
 */
import { spawnSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { DATASETS_DIR, preprocessLikeMobile, type Case, type DatasetFile } from './dataset.js'
import { seededShuffle } from './stats.js'

export const N5K_HOST = 'storage.googleapis.com'
export const N5K_BASE = `https://${N5K_HOST}/nutrition5k_dataset/nutrition5k_dataset`
export const N5K_METADATA_URLS = [
  `${N5K_BASE}/metadata/dish_metadata_cafe1.csv`,
  `${N5K_BASE}/metadata/dish_metadata_cafe2.csv`,
]
export const n5kImageUrl = (dishId: string) => `${N5K_BASE}/imagery/realsense_overhead/${dishId}/rgb.png`
export const KCAL_MIN = 50
export const KCAL_MAX = 1500
const OUT_DIR = path.join(DATASETS_DIR, 'photos-nutrition5k')

export const N5K_ATTRIBUTION =
  'Nutrition5k dataset (Google Research). Thames, Q. et al., "Nutrition5k: Towards Automatic Nutritional Understanding of Generic Food", ' +
  'CVPR 2021. https://github.com/google-research-datasets/Nutrition5k — License: CC BY 4.0 ' +
  '(verify the current terms at github.com/google-research-datasets/Nutrition5k before any redistribution).'

export interface DishMeta {
  dish_id: string
  total_calories: number
  total_mass: number
  total_fat: number
  total_carb: number
  total_protein: number
}

const NUM_RE = /^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/

/** 1 行の先頭 6 列だけを解釈する。不正（列不足・非数値・負数・dish_id 形式違い）は null */
export function parseDishMetadataLine(line: string): DishMeta | null {
  const parts = line.replace(/\r$/, '').split(',')
  if (parts.length < 6) return null
  const [id, ...rest] = parts.slice(0, 6).map((s) => s.trim())
  if (!/^dish_\d+$/.test(id)) return null
  const nums: number[] = []
  for (const s of rest) {
    if (!NUM_RE.test(s)) return null
    const v = Number(s)
    if (!Number.isFinite(v) || v < 0) return null
    nums.push(v)
  }
  const [total_calories, total_mass, total_fat, total_carb, total_protein] = nums
  return { dish_id: id, total_calories, total_mass, total_fat, total_carb, total_protein }
}

export function parseDishMetadataCsv(text: string): { dishes: DishMeta[]; skipped: number } {
  const dishes: DishMeta[] = []
  let skipped = 0
  for (const line of text.split('\n')) {
    if (!line.trim()) continue
    const d = parseDishMetadataLine(line)
    if (d) dishes.push(d)
    else skipped++
  }
  return { dishes, skipped }
}

/** kcal 範囲で絞り、dish_id で重複除去・ソートしてからシード付きシャッフル（決定的） */
export function orderCandidates(dishes: DishMeta[], seed: number): DishMeta[] {
  const byId = new Map<string, DishMeta>()
  for (const d of dishes) if (d.total_calories >= KCAL_MIN && d.total_calories <= KCAL_MAX && !byId.has(d.dish_id)) byId.set(d.dish_id, d)
  const sorted = [...byId.values()].sort((a, b) => (a.dish_id < b.dish_id ? -1 : a.dish_id > b.dish_id ? 1 : 0))
  return seededShuffle(sorted, seed)
}

export function dishToCase(d: DishMeta, imageRel: string): Case {
  return {
    id: d.dish_id,
    images: [imageRel],
    meal_type: 'lunch',
    content: '',
    expected: {
      is_meal: true,
      totals: {
        calories: Math.round(d.total_calories),
        protein_g: Math.round(d.total_protein),
        fat_g: Math.round(d.total_fat),
        carbs_g: Math.round(d.total_carb),
      },
    },
    tags: ['nutrition5k'],
  }
}

class NetworkBlockedError extends Error {}

function causeChain(e: unknown): string {
  const parts: string[] = []
  let cur: unknown = e
  for (let i = 0; cur && i < 5; i++) {
    const err = cur as { message?: string; code?: string; cause?: unknown }
    parts.push([err.code, err.message].filter(Boolean).join(' '))
    cur = err.cause
  }
  return parts.filter(Boolean).join(' <- ')
}

function blockedMessage(url: string, detail: string): string {
  return [
    `エラー: ${N5K_HOST} に接続できません（${detail}）。`,
    `  URL: ${url}`,
    `  この実行環境のネットワーク許可リスト（allowed domains）に ${N5K_HOST} を含める必要があります。`,
    '  プロキシ経由の環境（Claude Code のクラウド環境など）では、プロキシがこのホストへの CONNECT を拒否（403）している可能性があります。',
    '  許可リストを変更できない場合は、許可された環境でこのスクリプトを実行し datasets/photos-nutrition5k/ をコピーしてください。',
  ].join('\n')
}

async function get(url: string, timeoutMs: number, method: 'GET' | 'HEAD' = 'GET'): Promise<Response> {
  try {
    return await fetch(url, { method, signal: AbortSignal.timeout(timeoutMs) })
  } catch (e) {
    throw new NetworkBlockedError(blockedMessage(url, causeChain(e) || 'fetch failed'))
  }
}

async function main(): Promise<number> {
  const { values } = parseArgs({
    args: process.argv.slice(2),
    options: { n: { type: 'string', default: '50' }, seed: { type: 'string', default: '42' } },
    strict: true,
  })
  const n = Number(values.n)
  const seed = Number(values.seed)
  if (!Number.isInteger(n) || n < 1 || n > 1000) throw new Error('--n は 1〜1000 の整数で指定してください')
  if (!Number.isInteger(seed)) throw new Error('--seed は整数で指定してください')

  // 1. 事前確認（fail fast）
  console.log(`接続確認: ${N5K_METADATA_URLS[0]}`)
  const probe = await get(N5K_METADATA_URLS[0], 15_000, 'HEAD')
  if (!probe.ok) throw new NetworkBlockedError(blockedMessage(N5K_METADATA_URLS[0], `HTTP ${probe.status}`))

  // 2. メタデータ
  const dishes: DishMeta[] = []
  let skipped = 0
  for (const url of N5K_METADATA_URLS) {
    const res = await get(url, 60_000)
    if (!res.ok) throw new Error(`メタデータ取得失敗 HTTP ${res.status}: ${url}`)
    const parsed = parseDishMetadataCsv(await res.text())
    dishes.push(...parsed.dishes)
    skipped += parsed.skipped
    console.log(`  ${path.basename(url)}: ${parsed.dishes.length} 件（不正行 ${parsed.skipped} 件をスキップ）`)
  }
  const candidates = orderCandidates(dishes, seed)
  console.log(`候補（${KCAL_MIN}〜${KCAL_MAX} kcal、重複除去後）: ${candidates.length} 件 / seed=${seed}`)

  // 3. 画像
  mkdirSync(path.join(OUT_DIR, 'images'), { recursive: true })
  const cases: Case[] = []
  let notFound = 0
  for (const d of candidates) {
    if (cases.length >= n) break
    const url = n5kImageUrl(d.dish_id)
    const res = await get(url, 60_000)
    if (res.status === 404) {
      await res.body?.cancel()
      notFound++
      continue
    }
    if (!res.ok) throw new Error(`画像取得失敗 HTTP ${res.status}: ${url}`)
    const jpeg = await preprocessLikeMobile(Buffer.from(await res.arrayBuffer()))
    const rel = `images/${d.dish_id}.jpg`
    writeFileSync(path.join(OUT_DIR, rel), jpeg)
    cases.push(dishToCase(d, rel))
    console.log(`  [${cases.length}/${n}] ${d.dish_id} ${Math.round(d.total_calories)} kcal`)
  }
  if (cases.length < n) console.warn(`⚠ 候補を使い切りました: ${cases.length}/${n} 件（404: ${notFound} 件）`)

  const file: DatasetFile = {
    dataset: 'photos-nutrition5k',
    input_kind: 'photo',
    description:
      'Nutrition5k の俯瞰 RGB 画像（RealSense, realsense_overhead/rgb.png）と料理全体の栄養値（計量ベースの正解）。' +
      '米国の社員食堂の料理で日本食ではない点に注意。',
    source: `${N5K_ATTRIBUTION} Metadata: ${N5K_METADATA_URLS.join(', ')} (first 6 columns only). ` +
      `Sampling: ${KCAL_MIN}<=kcal<=${KCAL_MAX}, seed=${seed}, n=${cases.length}, 404 skipped=${notFound}, malformed metadata lines skipped=${skipped}.`,
    preprocessing: 'sharp: EXIF 回転適用 → 1920x1080 の枠に収まるよう縮小（拡大なし）→ JPEG 品質 80（モバイルアプリの image_picker 設定と同じ）。期待値は小数を四捨五入した整数。',
    cases,
  }
  writeFileSync(path.join(OUT_DIR, 'cases.json'), JSON.stringify(file, null, 2) + '\n')
  console.log(`書き出し: ${path.join(OUT_DIR, 'cases.json')}（${cases.length} 件）`)
  console.log(`出典: ${N5K_ATTRIBUTION}`)
  return 0
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  if (process.env.NODE_USE_ENV_PROXY !== '1') {
    // 組み込み fetch に環境のプロキシ設定（HTTPS_PROXY / NO_PROXY）を使わせるため、フラグを付けて再実行する。
    // （Node 22.21+ / 24+ で有効。プロキシが無い環境では直接接続になるだけで害はない）
    const [maj, min] = process.versions.node.split('.').map(Number)
    if (maj < 22 || (maj === 22 && min < 21) || maj === 23) {
      console.warn(`⚠ Node ${process.version} は NODE_USE_ENV_PROXY に未対応の可能性があります（22.21+ 推奨）。プロキシ環境では接続に失敗します`)
    }
    const r = spawnSync(process.execPath, [...process.execArgv, ...process.argv.slice(1)], {
      stdio: 'inherit',
      env: { ...process.env, NODE_USE_ENV_PROXY: '1' },
    })
    process.exit(r.status ?? 1)
  }
  main().then(
    (code) => process.exit(code),
    (e) => {
      console.error(e instanceof NetworkBlockedError ? e.message : `エラー: ${(e as Error).message}`)
      process.exit(e instanceof NetworkBlockedError ? 3 : 1)
    },
  )
}
