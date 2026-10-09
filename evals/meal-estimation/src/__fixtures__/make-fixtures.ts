/**
 * selftest / 見積りの動作確認用の極小フィクスチャを生成する（単色 JPEG。中身に意味はない）。
 *   npx tsx src/__fixtures__/make-fixtures.ts
 * 生成物（cases.json と images/*.jpg）はリポジトリにコミットしてよい（数 KB）。
 * これは評価データではない: 期待値は採点ロジックのテスト用の架空の値。
 */
import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import sharp from 'sharp'
import type { DatasetFile } from '../dataset.js'

const here = path.dirname(fileURLToPath(import.meta.url))

async function jpeg(file: string, width: number, height: number, rgb: [number, number, number]): Promise<void> {
  const buf = await sharp({ create: { width, height, channels: 3, background: { r: rgb[0], g: rgb[1], b: rgb[2] } } })
    .jpeg({ quality: 80 })
    .toBuffer()
  writeFileSync(file, buf)
}

const PREPROCESSING = 'モバイルアプリ相当: 1920x1080 の枠に収まるよう縮小（拡大なし）、JPEG 品質 80'

export async function makeFixtures(root: string = here): Promise<void> {
  const photosDir = path.join(root, 'photos-fixture')
  const shotsDir = path.join(root, 'screenshots-fixture')
  mkdirSync(path.join(photosDir, 'images'), { recursive: true })
  mkdirSync(path.join(shotsDir, 'images'), { recursive: true })

  // 写真: 横 1920x1080（標準ティアでは 1456x819 に縮小される）、縦 810x1080、正方 1080x1080
  await jpeg(path.join(photosDir, 'images', 'landscape.jpg'), 1920, 1080, [200, 120, 60])
  await jpeg(path.join(photosDir, 'images', 'portrait.jpg'), 810, 1080, [180, 160, 90])
  await jpeg(path.join(photosDir, 'images', 'square.jpg'), 1080, 1080, [90, 140, 70])
  await jpeg(path.join(photosDir, 'images', 'not-meal.jpg'), 1920, 1080, [60, 90, 200])
  // スクショ: iPhone 1170x2532 をアプリが縮小した 499x1080
  await jpeg(path.join(shotsDir, 'images', 'app-a.jpg'), 499, 1080, [245, 245, 245])
  await jpeg(path.join(shotsDir, 'images', 'app-b.jpg'), 499, 1080, [235, 240, 250])
  await jpeg(path.join(shotsDir, 'images', 'not-app.jpg'), 1920, 1080, [30, 30, 30])

  const photos: DatasetFile = {
    dataset: 'photos-fixture',
    input_kind: 'photo',
    description: 'ハーネスのテスト用フィクスチャ（単色画像・架空の期待値）。評価データではない',
    source: 'src/__fixtures__/make-fixtures.ts で生成',
    preprocessing: PREPROCESSING,
    cases: [
      { id: 'p-landscape', images: ['images/landscape.jpg'], meal_type: 'lunch', content: '', expected: { is_meal: true, totals: { calories: 650, protein_g: 25, fat_g: 20, carbs_g: 90 } }, tags: ['fixture'] },
      { id: 'p-three-images', images: ['images/landscape.jpg', 'images/portrait.jpg', 'images/square.jpg'], meal_type: 'dinner', content: 'ご飯大盛り', expected: { is_meal: true, totals: { calories: 900, protein_g: 35, fat_g: 30, carbs_g: 120 }, alt_totals: [{ calories: 1000, protein_g: 36, fat_g: 31, carbs_g: 140 }] }, tags: ['fixture', 'multi-image'] },
      { id: 'p-portrait', images: ['images/portrait.jpg'], meal_type: 'breakfast', content: '', expected: { is_meal: true, totals: { calories: 400, protein_g: 15, fat_g: 12, carbs_g: 55 } }, tags: ['fixture'] },
      { id: 'p-not-meal', images: ['images/not-meal.jpg'], meal_type: 'snack', content: '', expected: { is_meal: false, totals: null }, tags: ['fixture', 'non-meal'] },
    ],
  }
  const shots: DatasetFile = {
    dataset: 'screenshots-fixture',
    input_kind: 'screenshot',
    description: 'ハーネスのテスト用フィクスチャ（単色画像・架空の期待値）。評価データではない',
    source: 'src/__fixtures__/make-fixtures.ts で生成',
    preprocessing: PREPROCESSING,
    cases: [
      { id: 's-single', images: ['images/app-a.jpg'], meal_type: 'lunch', content: '', expected: { is_meal: true, totals: { calories: 712, protein_g: 31, fat_g: 24, carbs_g: 93 }, foods_count: 3, expect_warning: false, app_name: 'あすけん' }, tags: ['fixture'] },
      { id: 's-two-mismatch', images: ['images/app-a.jpg', 'images/app-b.jpg'], meal_type: 'dinner', content: '', expected: { is_meal: true, totals: { calories: 845, protein_g: 40, fat_g: 28, carbs_g: 105 }, foods_count: null, expect_warning: true, app_name: null }, tags: ['fixture', 'mismatch'] },
      { id: 's-not-app', images: ['images/not-app.jpg'], meal_type: 'snack', content: '', expected: { is_meal: false, totals: null, expect_warning: null }, tags: ['fixture', 'non-app'] },
    ],
  }
  writeFileSync(path.join(photosDir, 'cases.json'), JSON.stringify(photos, null, 2) + '\n')
  writeFileSync(path.join(shotsDir, 'cases.json'), JSON.stringify(shots, null, 2) + '\n')
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  makeFixtures().then(() => console.log(`fixtures written under ${here}`))
}
