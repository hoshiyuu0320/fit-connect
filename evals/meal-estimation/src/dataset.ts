/**
 * データセット契約（datasets/<name>/cases.json）の型とローダー。
 * スクショ合成データを生成する別エージェントと共有している契約なので、形を変えるときは双方を更新すること。
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import sharp from 'sharp'
import { EVAL_ROOT, sha256 } from './prompts.js'
import type { InputKind, MealType, Totals } from './production-logic.js'

export type { Totals } from './production-logic.js'

export interface Expected {
  /** false => 正解は foods: []（EMPTY_RESULT） */
  is_meal: boolean
  /** null = 採点しない */
  totals: Totals | null
  /** 他に正解として認める合計値 */
  alt_totals?: Totals[]
  foods_count?: number | null
  expect_warning?: boolean | null
  app_name?: string | null
}

export interface Case {
  id: string
  /** 1..3 枚の JPEG（dataset ディレクトリからの相対パス、モバイルアプリと同じ前処理済み） */
  images: string[]
  meal_type: MealType
  /** '' = 補足なし */
  content: string
  expected: Expected
  tags: string[]
}

export interface DatasetFile {
  dataset: string
  input_kind: InputKind
  description: string
  source: string
  preprocessing: string
  cases: Case[]
}

export interface LoadedDataset {
  name: string
  dir: string
  cases_path: string
  /** cases.json の SHA-256 */
  sha256: string
  input_kind: InputKind
  file: DatasetFile
}

export const DATASETS_DIR = path.join(EVAL_ROOT, 'datasets')
const MEAL_TYPES = new Set(['breakfast', 'lunch', 'dinner', 'snack'])
const TOTAL_KEYS = ['calories', 'protein_g', 'fat_g', 'carbs_g'] as const

/** datasets/<name>/cases.json が存在するディレクトリを名前順に返す */
export function discoverDatasets(root: string = DATASETS_DIR): string[] {
  if (!existsSync(root)) return []
  return readdirSync(root)
    .map((n) => path.join(root, n))
    .filter((d) => statSync(d).isDirectory() && existsSync(path.join(d, 'cases.json')))
    .sort()
}

function isFiniteNumber(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v)
}

function checkTotals(v: unknown, where: string, errors: string[]): void {
  if (!v || typeof v !== 'object') {
    errors.push(`${where}: totals オブジェクトではありません`)
    return
  }
  for (const k of TOTAL_KEYS) {
    const x = (v as Record<string, unknown>)[k]
    if (!isFiniteNumber(x) || x < 0) errors.push(`${where}.${k}: 0 以上の数値が必要です（${JSON.stringify(x)}）`)
  }
}

/** 契約に沿っているか検証する。問題をすべて列挙して返す（空配列 = OK）。 */
export function validateDatasetFile(file: unknown, dir: string, checkFiles = true): string[] {
  const errors: string[] = []
  if (!file || typeof file !== 'object') return ['cases.json がオブジェクトではありません']
  const f = file as Partial<DatasetFile>
  if (typeof f.dataset !== 'string' || !f.dataset) errors.push('dataset: 文字列が必要です')
  if (f.input_kind !== 'photo' && f.input_kind !== 'screenshot') errors.push(`input_kind: 'photo' | 'screenshot' が必要です（${JSON.stringify(f.input_kind)}）`)
  for (const k of ['description', 'source', 'preprocessing'] as const) {
    if (typeof f[k] !== 'string') errors.push(`${k}: 文字列が必要です`)
  }
  if (!Array.isArray(f.cases)) {
    errors.push('cases: 配列が必要です')
    return errors
  }
  const ids = new Set<string>()
  f.cases.forEach((c, i) => {
    const w = `cases[${i}]${c && typeof c.id === 'string' ? `(${c.id})` : ''}`
    if (!c || typeof c !== 'object') {
      errors.push(`${w}: オブジェクトではありません`)
      return
    }
    if (typeof c.id !== 'string' || !c.id) errors.push(`${w}.id: 文字列が必要です`)
    else if (ids.has(c.id)) errors.push(`${w}.id: 重複しています`)
    else ids.add(c.id)
    if (!Array.isArray(c.images) || c.images.length < 1 || c.images.length > 3) {
      errors.push(`${w}.images: 1〜3 件の配列が必要です`)
    } else {
      for (const rel of c.images) {
        if (typeof rel !== 'string' || !rel) {
          errors.push(`${w}.images: 文字列パスが必要です`)
          continue
        }
        const abs = path.resolve(dir, rel)
        if (path.isAbsolute(rel) || !abs.startsWith(path.resolve(dir) + path.sep)) {
          errors.push(`${w}.images: dataset ディレクトリ外を指しています（${rel}）`)
          continue
        }
        if (checkFiles) {
          if (!existsSync(abs)) {
            errors.push(`${w}.images: ファイルがありません（${rel}）`)
            continue
          }
          const head = readFileSync(abs).subarray(0, 3)
          if (!(head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff)) {
            errors.push(`${w}.images: JPEG ではありません（${rel}）。media_type は image/jpeg 固定で送るため JPEG が必要です`)
          }
        }
      }
    }
    if (!MEAL_TYPES.has(c.meal_type)) errors.push(`${w}.meal_type: breakfast|lunch|dinner|snack が必要です（${JSON.stringify(c.meal_type)}）`)
    if (typeof c.content !== 'string') errors.push(`${w}.content: 文字列が必要です（なしは ''）`)
    if (!Array.isArray(c.tags) || c.tags.some((t) => typeof t !== 'string')) errors.push(`${w}.tags: 文字列配列が必要です`)
    const e = c.expected
    if (!e || typeof e !== 'object') {
      errors.push(`${w}.expected: オブジェクトが必要です`)
      return
    }
    if (typeof e.is_meal !== 'boolean') errors.push(`${w}.expected.is_meal: boolean が必要です`)
    if (e.totals !== null) checkTotals(e.totals, `${w}.expected.totals`, errors)
    if (e.alt_totals !== undefined) {
      if (!Array.isArray(e.alt_totals)) errors.push(`${w}.expected.alt_totals: 配列が必要です`)
      else e.alt_totals.forEach((t, j) => checkTotals(t, `${w}.expected.alt_totals[${j}]`, errors))
    }
    if (e.foods_count !== undefined && e.foods_count !== null && (!Number.isInteger(e.foods_count) || e.foods_count < 0)) {
      errors.push(`${w}.expected.foods_count: 0 以上の整数か null が必要です`)
    }
    if (e.expect_warning !== undefined && e.expect_warning !== null && typeof e.expect_warning !== 'boolean') {
      errors.push(`${w}.expected.expect_warning: boolean か null が必要です`)
    }
    if (e.app_name !== undefined && e.app_name !== null && typeof e.app_name !== 'string') {
      errors.push(`${w}.expected.app_name: 文字列か null が必要です`)
    }
    if (e.is_meal === false && e.totals !== null && e.totals !== undefined) {
      errors.push(`${w}.expected: is_meal=false なら totals は null にしてください`)
    }
  })
  return errors
}

/** ディレクトリ（または cases.json のパス）からデータセットを読み込んで検証する */
export function loadDataset(dirOrFile: string): LoadedDataset {
  const abs = path.resolve(dirOrFile)
  const casesPath = abs.endsWith('.json') ? abs : path.join(abs, 'cases.json')
  const dir = path.dirname(casesPath)
  if (!existsSync(casesPath)) throw new Error(`cases.json がありません: ${casesPath}`)
  const text = readFileSync(casesPath, 'utf8')
  let file: DatasetFile
  try {
    file = JSON.parse(text) as DatasetFile
  } catch (e) {
    throw new Error(`cases.json を JSON として読めません: ${casesPath} (${(e as Error).message})`)
  }
  const errors = validateDatasetFile(file, dir)
  if (errors.length > 0) {
    const shown = errors.slice(0, 20).map((e) => `  - ${e}`).join('\n')
    throw new Error(`データセット契約違反: ${casesPath}\n${shown}${errors.length > 20 ? `\n  ...他 ${errors.length - 20} 件` : ''}`)
  }
  return { name: file.dataset, dir, cases_path: casesPath, sha256: sha256(text), input_kind: file.input_kind, file }
}

export interface CaseImages {
  base64: string[]
  dims: Array<{ width: number; height: number }>
  bytes: number[]
}

/** ケースの画像を base64 と寸法で読み込む（寸法は EXIF の回転を考慮） */
export async function readCaseImages(ds: LoadedDataset, c: Case): Promise<CaseImages> {
  const out: CaseImages = { base64: [], dims: [], bytes: [] }
  for (const rel of c.images) {
    const buf = readFileSync(path.resolve(ds.dir, rel))
    const meta = await sharp(buf).metadata()
    if (!meta.width || !meta.height) throw new Error(`画像サイズを取得できません: ${rel}`)
    const rotated = (meta.orientation ?? 1) >= 5
    out.dims.push(rotated ? { width: meta.height, height: meta.width } : { width: meta.width, height: meta.height })
    out.base64.push(buf.toString('base64'))
    out.bytes.push(buf.length)
  }
  return out
}

/** 採点用に grader が参照する「期待値」スナップショット（run ディレクトリに保存する） */
export interface DatasetSnapshot {
  name: string
  input_kind: InputKind
  cases_path: string
  sha256: string
  cases: Array<Pick<Case, 'id' | 'images' | 'meal_type' | 'content' | 'expected' | 'tags'>>
}

export function snapshotDataset(ds: LoadedDataset, cases: Case[]): DatasetSnapshot {
  return {
    name: ds.name,
    input_kind: ds.input_kind,
    cases_path: path.relative(EVAL_ROOT, ds.cases_path),
    sha256: ds.sha256,
    cases: cases.map((c) => ({ id: c.id, images: c.images, meal_type: c.meal_type, content: c.content, expected: c.expected, tags: c.tags })),
  }
}

/**
 * モバイルアプリ（fit-connect-mobile/lib/services/storage_service.dart: image_picker maxWidth 1920 /
 * maxHeight 1080 / imageQuality 80）相当の前処理。EXIF の向きを適用し、メタデータ（GPS 等）は書き出さない。
 */
export async function preprocessLikeMobile(input: Buffer): Promise<Buffer> {
  return sharp(input)
    .rotate()
    .resize({ width: 1920, height: 1080, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 80 })
    .toBuffer()
}
