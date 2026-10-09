/**
 * オーナー提供のラベル付き写真を評価データセットに取り込む。
 *   npm run import:custom
 *
 * 入力: datasets/photos-custom/labels.csv
 *   列: id,files,meal_type,content,calories,protein_g,fat_g,carbs_g,note
 *     - files: raw/ からの相対パスを ; 区切りで最大 3 枚
 *     - calories〜carbs_g: 4 つとも空なら「採点しない」（totals: null）。一部だけ空はエラー
 *     - 任意の追加列 is_meal（true/false、既定 true）: false なら「食事ではない画像」（正解は foods: []）
 * 出力: datasets/photos-custom/images/<id>_<n>.jpg（モバイルアプリと同じ前処理・メタデータ除去）と cases.json
 * raw/・images/・labels.csv・cases.json はコミットしない（.gitignore 済み）。
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { DATASETS_DIR, preprocessLikeMobile, type Case, type DatasetFile } from './dataset.js'
import type { MealType } from './production-logic.js'

export const CUSTOM_DIR = path.join(DATASETS_DIR, 'photos-custom')
const REQUIRED_COLUMNS = ['id', 'files', 'meal_type', 'content', 'calories', 'protein_g', 'fat_g', 'carbs_g', 'note'] as const
const MEAL_TYPES = new Set(['breakfast', 'lunch', 'dinner', 'snack'])

/** RFC 4180 の CSV パーサ（ダブルクォート・"" エスケープ・セル内改行・CRLF・BOM 対応） */
export function parseCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, '')
  const rows: string[][] = []
  let row: string[] = []
  let cell = ''
  let inQuotes = false
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]
    if (inQuotes) {
      if (ch === '"') {
        if (src[i + 1] === '"') {
          cell += '"'
          i++
        } else inQuotes = false
      } else cell += ch
      continue
    }
    if (ch === '"' && cell === '') inQuotes = true
    else if (ch === ',') {
      row.push(cell)
      cell = ''
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') i++
      row.push(cell)
      rows.push(row)
      row = []
      cell = ''
    } else cell += ch
  }
  if (inQuotes) throw new Error('CSV: 閉じていないダブルクォートがあります')
  if (cell !== '' || row.length > 0) {
    row.push(cell)
    rows.push(row)
  }
  // 完全な空行は除外
  return rows.filter((r) => !(r.length === 1 && r[0].trim() === ''))
}

export interface LabelRow {
  line: number
  id: string
  files: string[]
  meal_type: MealType
  content: string
  totals: { calories: number; protein_g: number; fat_g: number; carbs_g: number } | null
  is_meal: boolean
  note: string
}

/** labels.csv を検証して行に変換する。エラーはすべて集めて返す */
export function parseLabels(text: string, rawDir: string | null): { rows: LabelRow[]; errors: string[] } {
  const table = parseCsv(text)
  const errors: string[] = []
  if (table.length === 0) return { rows: [], errors: ['labels.csv が空です'] }
  const header = table[0].map((h) => h.trim())
  for (const c of REQUIRED_COLUMNS) if (!header.includes(c)) errors.push(`ヘッダーに列 ${c} がありません`)
  if (errors.length) return { rows: [], errors }
  const col = (r: string[], name: string) => {
    const i = header.indexOf(name)
    return i >= 0 ? (r[i] ?? '').trim() : ''
  }
  const rows: LabelRow[] = []
  const ids = new Set<string>()
  table.slice(1).forEach((r, idx) => {
    const line = idx + 2
    const w = `${line} 行目`
    const id = col(r, 'id')
    if (!/^[A-Za-z0-9_-]+$/.test(id)) errors.push(`${w}: id は英数字・_・- のみ（${JSON.stringify(id)}）`)
    else if (ids.has(id)) errors.push(`${w}: id ${id} が重複しています`)
    ids.add(id)
    const files = col(r, 'files').split(';').map((s) => s.trim()).filter(Boolean)
    if (files.length < 1 || files.length > 3) errors.push(`${w}: files は 1〜3 件（; 区切り）`)
    for (const f of files) {
      if (path.isAbsolute(f) || f.split(/[\\/]/).includes('..')) errors.push(`${w}: files は raw/ からの相対パスで指定してください（${f}）`)
      else if (rawDir && !existsSync(path.join(rawDir, f))) errors.push(`${w}: raw/${f} がありません`)
    }
    const meal = col(r, 'meal_type')
    if (!MEAL_TYPES.has(meal)) errors.push(`${w}: meal_type は breakfast|lunch|dinner|snack（${JSON.stringify(meal)}）`)
    const nums = (['calories', 'protein_g', 'fat_g', 'carbs_g'] as const).map((k) => col(r, k))
    let totals: LabelRow['totals'] = null
    if (nums.some((s) => s !== '')) {
      if (nums.some((s) => s === '')) errors.push(`${w}: calories/protein_g/fat_g/carbs_g は 4 つとも埋めるか、4 つとも空にしてください`)
      else {
        const v = nums.map(Number)
        if (v.some((x) => !Number.isFinite(x) || x < 0)) errors.push(`${w}: 栄養値は 0 以上の数値で（${nums.join(',')}）`)
        else totals = { calories: Math.round(v[0]), protein_g: Math.round(v[1]), fat_g: Math.round(v[2]), carbs_g: Math.round(v[3]) }
      }
    }
    const isMealRaw = col(r, 'is_meal').toLowerCase()
    if (isMealRaw && isMealRaw !== 'true' && isMealRaw !== 'false') errors.push(`${w}: is_meal は true / false / 空`)
    const is_meal = isMealRaw !== 'false'
    if (!is_meal && totals) errors.push(`${w}: is_meal=false の行は栄養値を空にしてください`)
    rows.push({ line, id, files, meal_type: meal as MealType, content: col(r, 'content'), totals, is_meal, note: col(r, 'note') })
  })
  return { rows, errors }
}

export function rowToCase(row: LabelRow, imageRels: string[]): Case & { note?: string } {
  return {
    id: row.id,
    images: imageRels,
    meal_type: row.meal_type,
    content: row.content,
    expected: { is_meal: row.is_meal, totals: row.is_meal ? row.totals : null },
    tags: ['custom'],
    ...(row.note ? { note: row.note } : {}),
  }
}

/** 取り込み本体（selftest からは一時ディレクトリを渡す）。終了コードを返す */
export async function importCustomPhotos(dir: string = CUSTOM_DIR, log: (s: string) => void = console.log, logErr: (s: string) => void = console.error): Promise<number> {
  const labelsPath = path.join(dir, 'labels.csv')
  const rawDir = path.join(dir, 'raw')
  if (!existsSync(labelsPath)) {
    logErr(`labels.csv がありません: ${labelsPath}\n  labels.example.csv をコピーして編集してください（datasets/photos-custom/README.md 参照）`)
    return 1
  }
  const { rows, errors } = parseLabels(readFileSync(labelsPath, 'utf8'), rawDir)
  if (errors.length) {
    logErr(`labels.csv にエラーがあります（cases.json は書き換えていません）:\n${errors.map((e) => `  - ${e}`).join('\n')}`)
    return 1
  }
  const imagesDir = path.join(dir, 'images')
  mkdirSync(imagesDir, { recursive: true })
  const cases: Case[] = []
  for (const row of rows) {
    const rels: string[] = []
    for (const [k, f] of row.files.entries()) {
      const out = await preprocessLikeMobile(readFileSync(path.join(rawDir, f)))
      const rel = `images/${row.id}_${k + 1}.jpg`
      writeFileSync(path.join(dir, rel), out)
      rels.push(rel)
    }
    cases.push(rowToCase(row, rels))
  }
  const graded = cases.filter((c) => c.expected.totals !== null).length
  const file: DatasetFile = {
    dataset: 'photos-custom',
    input_kind: 'photo',
    description: 'オーナー提供のラベル付き料理写真（例: コンビニ食品のパッケージの栄養成分表示 = 正解値）。ローカル専用・コミットしない',
    source: 'datasets/photos-custom/labels.csv + raw/（非公開）',
    preprocessing: 'sharp: EXIF 回転適用 → 1920x1080 の枠に収まるよう縮小（拡大なし）→ JPEG 品質 80、メタデータ（GPS 等）除去（モバイルアプリの image_picker 設定と同じサイズ・品質）',
    cases,
  }
  writeFileSync(path.join(dir, 'cases.json'), JSON.stringify(file, null, 2) + '\n')
  log(`書き出し: ${path.join(dir, 'cases.json')}（${cases.length} 件、うち採点対象 ${graded} 件）`)
  return 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  importCustomPhotos().then(
    (code) => process.exit(code),
    (e) => {
      console.error(`エラー: ${(e as Error).message}`)
      process.exit(1)
    },
  )
}
